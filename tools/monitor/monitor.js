#!/usr/bin/env node
"use strict";

const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');
const nodemailer = require('nodemailer');
require('dotenv').config();

const ROOT = path.resolve(__dirname, '..', '..');
const cfgPath = process.env.CONFIG_PATH || path.join(__dirname, 'config.json');
let config = {};
if (fs.existsSync(cfgPath)) {
  try { config = JSON.parse(fs.readFileSync(cfgPath)); } catch (e) { console.error('Invalid JSON in', cfgPath); process.exit(1); }
}

const providerUrl = process.env.PROVIDER_URL || config.providerUrl;
if (!providerUrl) { console.error('Missing provider URL. Set PROVIDER_URL or config.providerUrl'); process.exit(1); }

const watched = (process.env.WATCHED_ADDRS ? process.env.WATCHED_ADDRS.split(',') : (config.watchedAddresses || [])).map(a => a.toLowerCase());
const abiPath = process.env.ABI_PATH || config.abiPath || '';
let iface = null;
if (abiPath && fs.existsSync(path.resolve(abiPath))) {
  try {
    const abi = JSON.parse(fs.readFileSync(path.resolve(abiPath)));
    iface = new ethers.Interface(abi);
    console.log('Loaded ABI from', abiPath);
  } catch (e) {
    console.warn('Failed loading ABI:', e.message);
  }
}

const emailFrom = process.env.EMAIL_FROM || (config.email && config.email.from) || 'monitor@localhost';
const emailTo = process.env.EMAIL_TO || (config.email && config.email.to);

const smtp = {
  host: process.env.SMTP_HOST || (config.email && config.email.smtp && config.email.smtp.host),
  port: +(process.env.SMTP_PORT || (config.email && config.email.smtp && config.email.smtp.port) || 587),
  secure: (process.env.SMTP_SECURE === 'true') || (config.email && config.email.smtp && config.email.smtp.secure) || false,
  auth: {
    user: process.env.SMTP_USER || (config.email && config.email.smtp && config.email.smtp.user),
    pass: process.env.SMTP_PASS || (config.email && config.email.smtp && config.email.smtp.pass)
  }
};

let transporter = null;
if (smtp.host && smtp.auth.user && smtp.auth.pass && emailTo) {
  transporter = nodemailer.createTransport(smtp);
  console.log('Email transport configured (to:', emailTo, ')');
} else {
  console.warn('Email not fully configured. Alerts will be logged only. Provide SMTP_HOST/SMTP_USER/SMTP_PASS and EMAIL_TO to enable email alerts.');
}

const provider = providerUrl.startsWith('ws') || providerUrl.startsWith('wss')
  ? new ethers.WebSocketProvider(providerUrl)
  : new ethers.JsonRpcProvider(providerUrl);

const processed = new Set();

async function sendAlert(subject, body) {
  console.log('ALERT:', subject);
  console.log(body);
  if (!transporter) return;
  try {
    await transporter.sendMail({ from: emailFrom, to: emailTo, subject, text: body });
    console.log('Email sent');
  } catch (e) {
    console.warn('Failed sending email:', e.message);
  }
}

function shortAddr(a){ return (a||'').slice(0,6)+'...'+(a||'').slice(-4); }

async function handleTx(tx, blockNumber) {
  if (!tx || !tx.hash) return;
  if (processed.has(tx.hash)) return;
  processed.add(tx.hash);

  const to = tx.to ? tx.to.toLowerCase() : null;
  const from = tx.from ? tx.from.toLowerCase() : null;

  let matched = false;
  let reasons = [];

  if (to && watched.includes(to)) {
    matched = true;
    reasons.push(`Direct tx to watched address ${to}`);
  }

  try {
    const receipt = await provider.getTransactionReceipt(tx.hash);
    // check logs for ERC20 Transfer events or any log pointing to watched addresses
    for (const log of receipt.logs || []) {
      // topic[0] == Transfer(address,address,uint256)
      if (log.topics && log.topics[0] === ethers.id('Transfer(address,address,uint256)')) {
        // decode addresses from topics (indexed)
        const fromLog = ethers.getAddress(ethers.hexZeroPad(ethers.hexStripZeros(log.topics[1] || '0x'), 20));
        const toLog = ethers.getAddress(ethers.hexZeroPad(ethers.hexStripZeros(log.topics[2] || '0x'), 20));
        if (watched.includes(toLog.toLowerCase()) || watched.includes(fromLog.toLowerCase())) {
          matched = true;
          reasons.push(`ERC20 Transfer involving watched address in log (token contract ${log.address})`);
        }
      }
      // generic check: any data or topic containing watched address (not perfect)
      for (const w of watched) {
        if (log.data && log.data.toLowerCase().includes(w.replace('0x',''))) {
          matched = true;
          reasons.push(`Watcher substring matched in log data for ${w}`);
        }
      }
    }

    // try decode tx input if we have ABI
    if (iface && tx.data && tx.data !== '0x') {
      try {
        const parsed = iface.parseTransaction({ data: tx.data, value: tx.value });
        // inspect args for any watched addresses
        for (const [k,v] of Object.entries(parsed.args || {})) {
          if (typeof v === 'string' && v.startsWith('0x') && watched.includes(v.toLowerCase())) {
            matched = true;
            reasons.push(`Function ${parsed.name} called with watched address in arg ${k}`);
          }
        }
        if (matched) reasons.push(`Decoded function: ${parsed.name}`);
      } catch (e) {
        // ignore decode errors
      }
    }

    if (matched) {
      const valueEth = ethers.formatEther(tx.value || 0n);
      let body = `Transaction ${tx.hash} in block ${blockNumber}\nFrom: ${from} -> To: ${to} (value ${valueEth} ETH)\nReasons:\n- ${reasons.join('\n- ')}\n\nLink: https://etherscan.io/tx/${tx.hash}`;
      await sendAlert(`ALERT: funds/activity to watched address (${shortAddr(to)})`, body);
    }
  } catch (e) {
    console.warn('Error handling tx', tx.hash, e.message);
  }
}

provider.on('block', async (bn) => {
  console.log('New block', bn);
  try {
    const block = await provider.getBlockWithTransactions(bn);
    for (const tx of block.transactions) {
      // quick check for to-address match to reduce receipts
      if (tx.to && watched.includes(tx.to.toLowerCase())) {
        await handleTx(tx, bn);
        continue;
      }
      // otherwise, inspect receipt logs for watched patterns
      let inspect = false;
      // simple heuristic: if tx.data contains any watched address
      const dataLower = (tx.data || '').toLowerCase();
      for (const w of watched) if (dataLower.includes(w.replace('0x',''))) inspect = true;
      if (inspect) await handleTx(tx, bn);
    }
  } catch (e) {
    console.warn('Block handling error:', e.message);
  }
});

process.on('SIGINT', () => { console.log('Exit'); process.exit(0); });

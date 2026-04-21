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
const controlledCfg = (process.env.CONTROLLED_ADDRS ? process.env.CONTROLLED_ADDRS.split(',') : (config.controlledAddresses || [])).map(a => a.toLowerCase());

// dynamic in-memory controlled set - seeded from config and updated from on-chain VerifierSet/owner
const controlledSet = new Set(controlledCfg);
const verifiersSet = new Set();
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

// Bounded processed-tx cache — prevents unbounded memory growth in long-running processes.
// Evicts the oldest entry when the cap is reached (FIFO approximation via insertion order).
const MAX_PROCESSED = 10_000;
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
  // Evict oldest entry if at capacity
  if (processed.size >= MAX_PROCESSED) {
    processed.delete(processed.values().next().value);
  }
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

// If ABI loaded, attempt to attach to any watched addresses that are contracts (e.g., the IMMAC contract)
async function setupContractListeners() {
  if (!iface) return;
  for (const addr of watched) {
    try {
      const code = await provider.getCode(addr);
      if (!code || code === '0x') continue; // not a contract
      const contract = new ethers.Contract(addr, iface, provider);
      console.log('Attaching contract listeners to', addr);

      // initialize controlled set from on-chain state: owner + past VerifierSet events
      try {
        const ownerOnChain = await contract.owner();
        if (ownerOnChain) { controlledSet.add(ownerOnChain.toLowerCase()); }
        // fetch historical VerifierSet events to build verifier set
        const filter = contract.filters.VerifierSet();
        const events = await contract.queryFilter(filter, 0, 'latest');
        for (const ev of events) {
          const v = (ev.args && ev.args[0]) ? ev.args[0].toLowerCase() : null;
          const enabled = (ev.args && ev.args[1]) ? ev.args[1] : false;
          if (v) {
            if (enabled) { verifiersSet.add(v); controlledSet.add(v); }
            else { verifiersSet.delete(v); /* keep controlledSet unchanged on disable? remove to be strict */ controlledSet.delete(v); }
          }
        }
        console.log('Controlled set initialized, owner + verifiers count:', controlledSet.size);
      } catch (e) {
        console.warn('Failed to initialize controlled set from chain for', addr, e.message);
      }

      // ContributionSubmitted(uint256 indexed id, address indexed contributor, bytes32 contentHash, string category)
      if (contract.filters && contract.filters.ContributionSubmitted) {
        contract.on('ContributionSubmitted', async (id, contributor, contentHash, category, event) => {
          const caddr = (contributor || '').toLowerCase();
          const msg = `ContributionSubmitted id=${id} contributor=${caddr} category=${category}`;
          console.log(msg);
          // If contributor is not in controlled set, alert
          if (!controlledSet.has(caddr)) {
            await sendAlert(`UNCONTROLLED CONTRIBUTOR: ${shortAddr(caddr)}`, `${msg}\nContract: ${addr}\nEvent tx: ${event.transactionHash}`);
          } else {
            await sendAlert(`Contribution submitted (controlled): ${shortAddr(caddr)}`, `${msg}\nContract: ${addr}\nEvent tx: ${event.transactionHash}`);
          }
        });
      }

      // ContributionApproved(uint256 indexed id, address indexed verifier, uint256 impactMultiplier, uint256 qualityFactor)
      if (contract.filters && contract.filters.ContributionApproved) {
        contract.on('ContributionApproved', async (id, verifier, impactMultiplier, qualityFactor, event) => {
          const vaddr = (verifier || '').toLowerCase();
          console.log(`ContributionApproved id=${id} verifier=${vaddr} impact=${impactMultiplier} quality=${qualityFactor}`);
          // fetch reward via calculateReward (view)
          let reward = 'unknown';
          try { reward = (await contract.calculateReward(id)).toString(); } catch (e) { /* ignore */ }
          let body = `ContributionApproved id=${id}\nverifier=${vaddr}\nimpact=${impactMultiplier}\nquality=${qualityFactor}\ncalculatedRewardWei=${reward}\nContract: ${addr}\nTx: ${event.transactionHash}`;
          if (!controlledSet.has(vaddr)) {
            await sendAlert(`UNCONTROLLED VERIFIER: ${shortAddr(vaddr)}`, body);
          } else {
            await sendAlert(`Contribution approved (controlled verifier): ${shortAddr(vaddr)}`, body);
          }
        });
      }

      // RewardClaimed(uint256 indexed id, address indexed contributor, uint256 amount)
      if (contract.filters && contract.filters.RewardClaimed) {
        contract.on('RewardClaimed', async (id, contributor, amount, event) => {
          const caddr = (contributor || '').toLowerCase();
          const body = `RewardClaimed id=${id}\ncontributor=${caddr}\namountWei=${amount}\nContract: ${addr}\nTx: ${event.transactionHash}`;
          await sendAlert(`Reward claimed: ${shortAddr(caddr)}`, body);
        });
      }

      // VerifierSet and BaseValueSet can be useful
      if (contract.filters && contract.filters.VerifierSet) {
        contract.on('VerifierSet', async (verifier, enabled, event) => {
          const v = (verifier || '').toLowerCase();
          try {
            if (enabled) { verifiersSet.add(v); controlledSet.add(v); }
            else { verifiersSet.delete(v); controlledSet.delete(v); }
          } catch (e) {}
          await sendAlert(`VerifierSet ${v} -> ${enabled}`, `Contract: ${addr}\nTx: ${event.transactionHash}`);
        });
      }
      if (contract.filters && contract.filters.BaseValueSet) {
        contract.on('BaseValueSet', async (category, value, event) => {
          await sendAlert(`BaseValueSet ${category} -> ${value}`, `Contract: ${addr}\nTx: ${event.transactionHash}`);
        });
      }

    } catch (e) {
      console.warn('Error attaching to contract', addr, e.message);
    }
  }
}

// start contract listeners asynchronously
setupContractListeners().catch(e => console.warn('setupContractListeners failed', e.message));

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

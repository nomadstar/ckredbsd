const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('IMMAC contract MVP', function () {
  let IMMAC, immac, owner, verifier, contributor;

  beforeEach(async function () {
    [owner, verifier, contributor] = await ethers.getSigners();
    IMMAC = await ethers.getContractFactory('IMMAC');
    immac = await IMMAC.connect(owner).deploy();
    await immac.deployed();
  });

  it('registers, approves and pays out rewards', async function () {
    // Set base value for category 'security'
    await immac.connect(owner).setBaseValue('security', ethers.utils.parseEther('0.01'));

    // Owner enables verifier
    await immac.connect(owner).setVerifier(verifier.address, true);

    // Contributor submits contribution (hash arbitrary)
    const h = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('contrib1'));
    const tx = await immac.connect(contributor).submitContribution(h, 'security');
    const rc = await tx.wait();
    const id = 1;

    // Verifier approves with multipliers 100 (1.00x) each
    await immac.connect(verifier).approveContribution(id, 100, 100);

    // Fund contract
    await owner.sendTransaction({ to: immac.address, value: ethers.utils.parseEther('0.1') });

    // Check calculated reward
    const reward = await immac.calculateReward(id);
    expect(reward).to.equal(ethers.utils.parseEther('0.01'));

    // Contributor claims
    const before = await ethers.provider.getBalance(contributor.address);
    const claimTx = await immac.connect(contributor).claimReward(id);
    const receipt = await claimTx.wait();
    const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);
    const after = await ethers.provider.getBalance(contributor.address);

    // after = before + reward - gasUsed
    expect(after).to.equal(before.add(reward).sub(gasUsed));
  });
});

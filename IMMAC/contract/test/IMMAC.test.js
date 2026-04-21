const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('IMMAC contract', function () {
  let IMMAC, immac, owner, verifier, contributor, other;

  beforeEach(async function () {
    [owner, verifier, contributor, other] = await ethers.getSigners();
    IMMAC = await ethers.getContractFactory('IMMAC');
    immac = await IMMAC.connect(owner).deploy();
    await immac.waitForDeployment();
  });

  // ── Happy path ──────────────────────────────────────────────────────────────

  it('registers, approves and pays out rewards', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    await immac.connect(owner).setVerifier(verifier.address, true);

    const h = ethers.keccak256(ethers.toUtf8Bytes('contrib1'));
    await immac.connect(contributor).submitContribution(h, 'security');
    const id = 1;

    await immac.connect(verifier).approveContribution(id, 100, 100);
    await owner.sendTransaction({ to: await immac.getAddress(), value: ethers.parseEther('0.1') });

    const reward = await immac.calculateReward(id);
    expect(reward).to.equal(ethers.parseEther('0.01'));

    const before = await ethers.provider.getBalance(contributor.address);
    const claimTx = await immac.connect(contributor).claimReward(id);
    const receipt = await claimTx.wait();
    const gasUsed = receipt.gasUsed * (receipt.gasPrice ?? 0n);
    const after = await ethers.provider.getBalance(contributor.address);
    expect(after).to.equal(before + reward - gasUsed);
  });

  // ── Fix: self-approval blocked ──────────────────────────────────────────────

  it('blocks verifier from approving their own contribution', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    // Make contributor also a verifier
    await immac.connect(owner).setVerifier(contributor.address, true);

    const h = ethers.keccak256(ethers.toUtf8Bytes('self-contrib'));
    await immac.connect(contributor).submitContribution(h, 'security');

    await expect(
      immac.connect(contributor).approveContribution(1, 100, 100)
    ).to.be.revertedWith('Cannot approve own contribution');
  });

  // ── Fix: duplicate hash rejected ───────────────────────────────────────────

  it('rejects duplicate content hash submissions', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    const h = ethers.keccak256(ethers.toUtf8Bytes('same-content'));

    await immac.connect(contributor).submitContribution(h, 'security');
    await expect(
      immac.connect(other).submitContribution(h, 'security')
    ).to.be.revertedWith('Hash already submitted');
  });

  // ── Fix: multiplier cap enforced ───────────────────────────────────────────

  it('rejects impact multiplier above MAX_MULTIPLIER', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    await immac.connect(owner).setVerifier(verifier.address, true);

    const h = ethers.keccak256(ethers.toUtf8Bytes('contrib-cap'));
    await immac.connect(contributor).submitContribution(h, 'security');

    await expect(
      immac.connect(verifier).approveContribution(1, 501, 100)
    ).to.be.revertedWith('Impact multiplier exceeds cap');
  });

  it('rejects quality factor above MAX_MULTIPLIER', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    await immac.connect(owner).setVerifier(verifier.address, true);

    const h = ethers.keccak256(ethers.toUtf8Bytes('contrib-cap2'));
    await immac.connect(contributor).submitContribution(h, 'security');

    await expect(
      immac.connect(verifier).approveContribution(1, 100, 501)
    ).to.be.revertedWith('Quality factor exceeds cap');
  });

  // ── Fix: two-step ownership transfer ───────────────────────────────────────

  it('transfers ownership in two steps', async function () {
    await immac.connect(owner).initiateOwnershipTransfer(other.address);
    expect(await immac.pendingOwner()).to.equal(other.address);

    await immac.connect(other).acceptOwnership();
    expect(await immac.owner()).to.equal(other.address);
    expect(await immac.pendingOwner()).to.equal(ethers.ZeroAddress);
  });

  it('blocks non-pending address from accepting ownership', async function () {
    await immac.connect(owner).initiateOwnershipTransfer(other.address);
    await expect(
      immac.connect(contributor).acceptOwnership()
    ).to.be.revertedWith('Not pending owner');
  });

  // ── Fix: double-claim blocked ──────────────────────────────────────────────

  it('blocks double-claiming the same reward', async function () {
    await immac.connect(owner).setBaseValue('security', ethers.parseEther('0.01'));
    await immac.connect(owner).setVerifier(verifier.address, true);
    await owner.sendTransaction({ to: await immac.getAddress(), value: ethers.parseEther('0.1') });

    const h = ethers.keccak256(ethers.toUtf8Bytes('contrib-double'));
    await immac.connect(contributor).submitContribution(h, 'security');
    await immac.connect(verifier).approveContribution(1, 100, 100);
    await immac.connect(contributor).claimReward(1);

    await expect(
      immac.connect(contributor).claimReward(1)
    ).to.be.revertedWith('Already claimed');
  });

  // ── Fix: withdraw restricted to owner ─────────────────────────────────────

  it('blocks non-owner from calling withdraw', async function () {
    await owner.sendTransaction({ to: await immac.getAddress(), value: ethers.parseEther('0.1') });
    await expect(
      immac.connect(other).withdraw(ethers.parseEther('0.01'), other.address)
    ).to.be.revertedWith('Not owner');
  });
});

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// [FIX #1] ReentrancyGuard inline (no OpenZeppelin dependency needed for this pattern)
// Protects claimReward from reentrancy even if future changes break the CEI order
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract IMMAC is ReentrancyGuard {

    // [FIX #2] Two-step ownership transfer: prevents permanently losing control
    // if the owner wallet is lost or compromised mid-transfer
    address public owner;
    address public pendingOwner;

    uint256 public contributionCount;

    // [FIX #6] Cap multipliers to prevent a rogue verifier from inflating rewards to drain the contract
    uint256 public constant MAX_MULTIPLIER = 500; // 5.00x max per factor

    struct Contribution {
        bytes32 contentHash;
        address contributor;
        uint256 timestamp;
        string category;
        bool approved;
        uint256 impactMultiplier; // e.g., 100 = 1.00x
        uint256 qualityFactor;    // e.g., 100 = 1.00x
        bool rewarded;
        uint256 baseValue;        // in wei, locked at submit time
    }

    mapping(uint256 => Contribution) public contributions;
    mapping(bytes32 => uint256) public baseValues;  // categoryHash -> baseValue (wei)
    mapping(address => bool) public verifiers;
    // [FIX #7] Track used content hashes to prevent duplicate submissions
    mapping(bytes32 => bool) public hashUsed;

    // --- Events ---
    event ContributionSubmitted(uint256 indexed id, address indexed contributor, bytes32 contentHash, string category);
    event ContributionApproved(uint256 indexed id, address indexed verifier, uint256 impactMultiplier, uint256 qualityFactor);
    event RewardClaimed(uint256 indexed id, address indexed contributor, uint256 amount);
    event VerifierSet(address indexed verifier, bool enabled);
    event BaseValueSet(string category, uint256 value);
    // [FIX #2] Ownership transfer events
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    // [FIX #8] Log unexpected ETH received via fallback
    event FundsReceived(address indexed sender, uint256 amount);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyVerifier() {
        require(verifiers[msg.sender], "Not verifier");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Ownership — two-step transfer
    // [FIX #2] Step 1: owner nominates a new owner
    // [FIX #2] Step 2: new owner accepts — prevents accidental transfer to wrong address
    // -------------------------------------------------------------------------

    function initiateOwnershipTransfer(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Zero address");
        pendingOwner = _newOwner;
        emit OwnershipTransferInitiated(owner, _newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    // -------------------------------------------------------------------------
    // Verifier management
    // -------------------------------------------------------------------------

    function setVerifier(address _verifier, bool _enabled) external onlyOwner {
        verifiers[_verifier] = _enabled;
        emit VerifierSet(_verifier, _enabled);
    }

    // -------------------------------------------------------------------------
    // Base value management
    // -------------------------------------------------------------------------

    function setBaseValue(string calldata category, uint256 valueWei) external onlyOwner {
        bytes32 k = keccak256(abi.encodePacked(category));
        baseValues[k] = valueWei;
        emit BaseValueSet(category, valueWei);
    }

    // -------------------------------------------------------------------------
    // Submit contribution
    // -------------------------------------------------------------------------

    function submitContribution(bytes32 contentHash, string calldata category) external returns (uint256) {
        // [FIX #7] Reject duplicate content hashes
        require(!hashUsed[contentHash], "Hash already submitted");
        hashUsed[contentHash] = true;

        contributionCount += 1;
        uint256 id = contributionCount;
        bytes32 catk = keccak256(abi.encodePacked(category));

        contributions[id] = Contribution({
            contentHash:      contentHash,
            contributor:      msg.sender,
            timestamp:        block.timestamp,
            category:         category,
            approved:         false,
            impactMultiplier: 0,
            qualityFactor:    0,
            rewarded:         false,
            baseValue:        baseValues[catk]
        });

        emit ContributionSubmitted(id, msg.sender, contentHash, category);
        return id;
    }

    // -------------------------------------------------------------------------
    // Approve contribution
    // -------------------------------------------------------------------------

    function approveContribution(
        uint256 id,
        uint256 impactMultiplierScaled,
        uint256 qualityFactorScaled
    ) external onlyVerifier {
        Contribution storage c = contributions[id];
        require(c.contributor != address(0), "No such contribution");
        require(!c.approved, "Already approved");

        // [FIX #4] Prevent self-approval: verifier cannot approve their own contribution
        require(c.contributor != msg.sender, "Cannot approve own contribution");

        // [FIX #6] Cap multipliers to prevent reward inflation / contract drain
        require(impactMultiplierScaled <= MAX_MULTIPLIER, "Impact multiplier exceeds cap");
        require(qualityFactorScaled <= MAX_MULTIPLIER, "Quality factor exceeds cap");

        // Multipliers must be at least 1x (100) if approving
        require(impactMultiplierScaled >= 100, "Impact multiplier below minimum");
        require(qualityFactorScaled >= 100, "Quality factor below minimum");

        c.approved         = true;
        c.impactMultiplier = impactMultiplierScaled;
        c.qualityFactor    = qualityFactorScaled;

        emit ContributionApproved(id, msg.sender, impactMultiplierScaled, qualityFactorScaled);
    }

    // -------------------------------------------------------------------------
    // Calculate reward
    // -------------------------------------------------------------------------

    function calculateReward(uint256 id) public view returns (uint256) {
        Contribution storage c = contributions[id];
        require(c.contributor != address(0), "No such contribution");
        if (!c.approved) return 0;
        // base * impact/100 * quality/100
        uint256 reward = (c.baseValue * c.impactMultiplier * c.qualityFactor) / (100 * 100);
        return reward;
    }

    // -------------------------------------------------------------------------
    // Claim reward
    // [FIX #1] nonReentrant guard added as defense-in-depth alongside CEI pattern
    // -------------------------------------------------------------------------

    function claimReward(uint256 id) external nonReentrant {
        Contribution storage c = contributions[id];
        require(c.contributor == msg.sender, "Not contributor");
        require(c.approved,                  "Not approved");
        require(!c.rewarded,                 "Already claimed");

        uint256 amount = calculateReward(id);
        require(amount > 0,                           "No reward");
        require(address(this).balance >= amount,      "Insufficient contract funds");

        // Checks-Effects-Interactions: state update before external call
        c.rewarded = true;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Transfer failed");

        emit RewardClaimed(id, msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Fund contract
    // [FIX #8] Emit event on receive so funding is always traceable on-chain
    // -------------------------------------------------------------------------

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    // [FIX #8] fallback only accepts ETH with data if intentional; revert otherwise
    // to avoid silently swallowing malformed calls
    fallback() external payable {
        require(msg.value > 0, "Unexpected call");
        emit FundsReceived(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // Emergency withdraw
    // [FIX #3] onlyOwner already limits this, but note: for production
    // this should be a timelock or multisig — see comment below
    // -------------------------------------------------------------------------

    function withdraw(uint256 amountWei, address payable dest) external onlyOwner {
        // NOTE: In production, replace `owner` with a Gnosis Safe multisig address
        // and/or add a timelock (e.g., 48h delay) before withdrawal executes.
        // This is the primary remaining centralization risk.
        require(dest != address(0),              "Zero address");
        require(address(this).balance >= amountWei, "Insufficient balance");

        (bool sent, ) = dest.call{value: amountWei}("");
        require(sent, "Withdraw failed");
    }
}

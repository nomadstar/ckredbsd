// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract IMMAC {
    address public owner;
    uint256 public contributionCount;

    struct Contribution {
        bytes32 contentHash;
        address contributor;
        uint256 timestamp;
        string category;
        bool approved;
        uint256 impactMultiplier; // e.g., 100 = 1.00x
        uint256 qualityFactor;    // e.g., 100 = 1.00x
        bool rewarded;
        uint256 baseValue; // in wei
    }

    mapping(uint256 => Contribution) public contributions;
    mapping(bytes32 => uint256) public baseValues; // categoryHash -> baseValue (wei)
    mapping(address => bool) public verifiers;

    event ContributionSubmitted(uint256 indexed id, address indexed contributor, bytes32 contentHash, string category);
    event ContributionApproved(uint256 indexed id, address indexed verifier, uint256 impactMultiplier, uint256 qualityFactor);
    event RewardClaimed(uint256 indexed id, address indexed contributor, uint256 amount);
    event VerifierSet(address indexed verifier, bool enabled);
    event BaseValueSet(string category, uint256 value);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyVerifier() {
        require(verifiers[msg.sender] == true, "Not verifier");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // Owner can set verifiers (could be a multisig in production)
    function setVerifier(address _verifier, bool _enabled) external onlyOwner {
        verifiers[_verifier] = _enabled;
        emit VerifierSet(_verifier, _enabled);
    }

    // Owner sets base value per category (in wei)
    function setBaseValue(string calldata category, uint256 valueWei) external onlyOwner {
        bytes32 k = keccak256(abi.encodePacked(category));
        baseValues[k] = valueWei;
        emit BaseValueSet(category, valueWei);
    }

    // Submit a contribution: store hash + metadata
    function submitContribution(bytes32 contentHash, string calldata category) external returns (uint256) {
        contributionCount += 1;
        uint256 id = contributionCount;
        bytes32 catk = keccak256(abi.encodePacked(category));
        contributions[id] = Contribution({
            contentHash: contentHash,
            contributor: msg.sender,
            timestamp: block.timestamp,
            category: category,
            approved: false,
            impactMultiplier: 0,
            qualityFactor: 0,
            rewarded: false,
            baseValue: baseValues[catk]
        });
        emit ContributionSubmitted(id, msg.sender, contentHash, category);
        return id;
    }

    // Verifier approves and supplies multipliers (scaled by 100, e.g., 125 = 1.25)
    function approveContribution(uint256 id, uint256 impactMultiplierScaled, uint256 qualityFactorScaled) external onlyVerifier {
        Contribution storage c = contributions[id];
        require(c.contributor != address(0), "No such contribution");
        require(!c.approved, "Already approved");
        c.approved = true;
        c.impactMultiplier = impactMultiplierScaled;
        c.qualityFactor = qualityFactorScaled;
        emit ContributionApproved(id, msg.sender, impactMultiplierScaled, qualityFactorScaled);
    }

    // Calculate reward in wei (using scaled multipliers)
    function calculateReward(uint256 id) public view returns (uint256) {
        Contribution storage c = contributions[id];
        require(c.contributor != address(0), "No such contribution");
        if (!c.approved) return 0;
        // base * impact/100 * quality/100
        uint256 reward = (c.baseValue * c.impactMultiplier * c.qualityFactor) / (100 * 100);
        return reward;
    }

    // Claim reward: contract must hold enough ETH
    function claimReward(uint256 id) external {
        Contribution storage c = contributions[id];
        require(c.contributor == msg.sender, "Not contributor");
        require(c.approved, "Not approved");
        require(!c.rewarded, "Already claimed");
        uint256 amount = calculateReward(id);
        require(amount > 0, "No reward");
        require(address(this).balance >= amount, "Insufficient contract funds");
        c.rewarded = true;
        payable(msg.sender).transfer(amount);
        emit RewardClaimed(id, msg.sender, amount);
    }

    // Fund contract
    receive() external payable {}
    fallback() external payable {}

    // Emergency withdraw by owner
    function withdraw(uint256 amountWei, address payable dest) external onlyOwner {
        require(address(this).balance >= amountWei, "Insufficient balance");
        dest.transfer(amountWei);
    }
}

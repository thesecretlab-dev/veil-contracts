// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract VeilFaucet {
    address public owner;
    uint256 public claimAmount = 1 ether;
    uint256 public cooldown = 1 days;
    mapping(address => uint256) public lastClaim;

    event Claimed(address indexed user, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    function claim() external {
        require(block.timestamp >= lastClaim[msg.sender] + cooldown, "cooldown active");
        require(address(this).balance >= claimAmount, "faucet empty");
        lastClaim[msg.sender] = block.timestamp;
        (bool ok,) = msg.sender.call{value: claimAmount}("");
        require(ok, "transfer failed");
        emit Claimed(msg.sender, claimAmount);
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok,) = owner.call{value: bal}("");
        require(ok, "transfer failed");
        emit Withdrawn(owner, bal);
    }

    function setClaimAmount(uint256 _amount) external onlyOwner {
        claimAmount = _amount;
    }

    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
    }
}

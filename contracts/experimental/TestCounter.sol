// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TestCounter {
    address public immutable owner;
    uint256 public count;

    event CountChanged(uint256 previousCount, uint256 newCount, address indexed caller);

    error NotOwner();
    error Underflow();

    constructor(uint256 initialCount) {
        owner = msg.sender;
        count = initialCount;
    }

    function increment() external {
        _setCount(count + 1);
    }

    function decrement() external {
        if (count == 0) revert Underflow();
        _setCount(count - 1);
    }

    function setCount(uint256 newCount) external {
        _setCount(newCount);
    }

    function ownerReset() external {
        if (msg.sender != owner) revert NotOwner();
        _setCount(0);
    }

    function _setCount(uint256 newCount) internal {
        uint256 previous = count;
        count = newCount;
        emit CountChanged(previous, newCount, msg.sender);
    }
}

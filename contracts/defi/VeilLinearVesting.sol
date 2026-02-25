// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVestingERC20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Linear token vesting vault used for memecoin creator allocations.
contract VeilLinearVesting {
  IVestingERC20 public immutable token;
  address public immutable beneficiary;
  uint64 public immutable start;
  uint64 public immutable duration;
  uint256 public immutable totalAmount;

  uint256 public released;

  event Released(address indexed beneficiary, uint256 amount, uint256 totalReleased);

  error BadConfig();
  error NothingToRelease();
  error TransferFailed();

  constructor(address token_, address beneficiary_, uint64 start_, uint64 duration_, uint256 amount_) {
    if (token_ == address(0) || beneficiary_ == address(0)) revert BadConfig();
    if (duration_ == 0 || amount_ == 0) revert BadConfig();

    token = IVestingERC20(token_);
    beneficiary = beneficiary_;
    start = start_;
    duration = duration_;
    totalAmount = amount_;
  }

  function vestedAmount(uint64 timestamp) public view returns (uint256) {
    if (timestamp <= start) return 0;
    uint256 elapsed = uint256(timestamp - start);
    if (elapsed >= duration) return totalAmount;
    return (totalAmount * elapsed) / duration;
  }

  function releasableAmount() public view returns (uint256) {
    uint256 vested = vestedAmount(uint64(block.timestamp));
    if (vested <= released) return 0;
    return vested - released;
  }

  function release() external returns (uint256 amount) {
    amount = releasableAmount();
    if (amount == 0) revert NothingToRelease();

    released += amount;
    if (!token.transfer(beneficiary, amount)) revert TransferFailed();

    emit Released(beneficiary, amount, released);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Minimal staking rewards for an LP token paying native VEIL.
/// @dev Modeled after the common "StakingRewards" pattern, simplified.
contract NativeVeilGauge {
  IERC20 public immutable stakingToken;
  address public owner;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;

  // Reward accounting.
  uint256 public rewardRate; // wei per second
  uint256 public periodFinish;
  uint256 public lastUpdateTime;
  uint256 public rewardPerTokenStored;
  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public rewards;

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
  event RewardNotified(uint256 reward, uint256 duration, uint256 rewardRate, uint256 periodFinish);
  event OwnershipTransferred(address indexed prevOwner, address indexed nextOwner);

  error NotOwner();

  modifier onlyOwner() {
    if (msg.sender != owner) revert NotOwner();
    _;
  }

  modifier updateReward(address account) {
    rewardPerTokenStored = rewardPerToken();
    lastUpdateTime = lastTimeRewardApplicable();
    if (account != address(0)) {
      rewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
    _;
  }

  constructor(address stakingToken_) {
    require(stakingToken_ != address(0), "Gauge/invalid-staking");
    stakingToken = IERC20(stakingToken_);
    owner = msg.sender;
  }

  receive() external payable {}

  function transferOwnership(address nextOwner) external onlyOwner {
    require(nextOwner != address(0), "Gauge/invalid-owner");
    emit OwnershipTransferred(owner, nextOwner);
    owner = nextOwner;
  }

  function lastTimeRewardApplicable() public view returns (uint256) {
    uint256 t = block.timestamp;
    return t < periodFinish ? t : periodFinish;
  }

  function rewardPerToken() public view returns (uint256) {
    if (totalSupply == 0) return rewardPerTokenStored;
    uint256 dt = lastTimeRewardApplicable() - lastUpdateTime;
    return rewardPerTokenStored + ((dt * rewardRate * 1e18) / totalSupply);
  }

  function earned(address account) public view returns (uint256) {
    return ((balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
  }

  function stake(uint256 amount) external updateReward(msg.sender) {
    require(amount > 0, "Gauge/zero");
    totalSupply += amount;
    unchecked {
      balanceOf[msg.sender] += amount;
    }
    require(stakingToken.transferFrom(msg.sender, address(this), amount), "Gauge/transfer-in-failed");
    emit Staked(msg.sender, amount);
  }

  function withdraw(uint256 amount) public updateReward(msg.sender) {
    require(amount > 0, "Gauge/zero");
    require(balanceOf[msg.sender] >= amount, "Gauge/insufficient");
    unchecked {
      balanceOf[msg.sender] -= amount;
    }
    totalSupply -= amount;
    require(stakingToken.transfer(msg.sender, amount), "Gauge/transfer-out-failed");
    emit Withdrawn(msg.sender, amount);
  }

  function getReward() public updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward == 0) return;
    rewards[msg.sender] = 0;

    // Do not allow overdrawing.
    uint256 bal = address(this).balance;
    if (reward > bal) reward = bal;

    (bool ok, ) = msg.sender.call{ value: reward }("");
    require(ok, "Gauge/veil-transfer-failed");
    emit RewardPaid(msg.sender, reward);
  }

  function exit() external {
    withdraw(balanceOf[msg.sender]);
    getReward();
  }

  /// @notice Fund rewards and set the distribution duration.
  /// @dev Sends `msg.value` as the reward pot; distributes linearly over `duration`.
  function notifyRewardAmount(uint256 duration) external payable onlyOwner updateReward(address(0)) {
    require(duration > 0, "Gauge/bad-duration");
    uint256 reward = msg.value;
    require(reward > 0, "Gauge/zero-reward");

    if (block.timestamp >= periodFinish) {
      rewardRate = reward / duration;
    } else {
      uint256 remaining = periodFinish - block.timestamp;
      uint256 leftover = remaining * rewardRate;
      rewardRate = (reward + leftover) / duration;
    }

    require(rewardRate > 0, "Gauge/zero-rate");
    lastUpdateTime = block.timestamp;
    periodFinish = block.timestamp + duration;
    emit RewardNotified(reward, duration, rewardRate, periodFinish);
  }
}

contract IronVeilGauge is NativeVeilGauge {
  constructor(address stakingToken_) NativeVeilGauge(stakingToken_) {}
}

contract CopperVeilGauge is NativeVeilGauge {
  constructor(address stakingToken_) NativeVeilGauge(stakingToken_) {}
}

contract SilverVeilGauge is NativeVeilGauge {
  constructor(address stakingToken_) NativeVeilGauge(stakingToken_) {}
}

contract GoldVeilGauge is NativeVeilGauge {
  constructor(address stakingToken_) NativeVeilGauge(stakingToken_) {}
}

contract DiamondVeilGauge is NativeVeilGauge {
  constructor(address stakingToken_) NativeVeilGauge(stakingToken_) {}
}


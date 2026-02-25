// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20LikeKeep3r {
  function balanceOf(address account) external view returns (uint256);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Fast companion EVM Keep3r-style registry and payout rail.
/// @dev Lightweight fork surface for VEIL local/ops workflows.
contract VeilKeep3r {
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event JobSet(address indexed job, bool enabled);
  event MinimumBondSet(uint256 previousMinimumBond, uint256 nextMinimumBond);
  event Bonded(address indexed keeper, uint256 amount, uint256 bondedTotal);
  event Unbonded(address indexed keeper, uint256 amount, uint256 bondedTotal);
  event Funded(address indexed from, uint256 amount);
  event Worked(address indexed job, address indexed keeper, uint256 amount);
  event Slashed(address indexed keeper, address indexed recipient, uint256 amount);

  error Keep3rZeroAddress();
  error Keep3rOnlyOwner();
  error Keep3rOnlyJob();
  error Keep3rInvalidAmount();
  error Keep3rTransferFailed();
  error Keep3rInsufficientBond();
  error Keep3rNotActiveKeeper();
  error Keep3rInsufficientCredits();

  IERC20LikeKeep3r public immutable VEIL;
  address public owner;
  uint256 public minimumBond;
  uint256 public totalBonded;

  mapping(address => bool) public jobs;
  mapping(address => uint256) public keeperBond;

  modifier onlyOwner() {
    if (msg.sender != owner) revert Keep3rOnlyOwner();
    _;
  }

  modifier onlyJob() {
    if (!jobs[msg.sender]) revert Keep3rOnlyJob();
    _;
  }

  constructor(address veilToken_, uint256 minimumBond_, address owner_) {
    if (veilToken_ == address(0) || owner_ == address(0)) revert Keep3rZeroAddress();
    VEIL = IERC20LikeKeep3r(veilToken_);
    minimumBond = minimumBond_;
    owner = owner_;
    emit OwnershipTransferred(address(0), owner_);
  }

  function transferOwnership(address nextOwner) external onlyOwner {
    if (nextOwner == address(0)) revert Keep3rZeroAddress();
    emit OwnershipTransferred(owner, nextOwner);
    owner = nextOwner;
  }

  function setJob(address job, bool enabled) external onlyOwner {
    if (job == address(0)) revert Keep3rZeroAddress();
    jobs[job] = enabled;
    emit JobSet(job, enabled);
  }

  function setMinimumBond(uint256 nextMinimumBond) external onlyOwner {
    uint256 previous = minimumBond;
    minimumBond = nextMinimumBond;
    emit MinimumBondSet(previous, nextMinimumBond);
  }

  function isKeeper(address keeper) public view returns (bool) {
    return keeperBond[keeper] >= minimumBond;
  }

  function availableCredits() public view returns (uint256) {
    uint256 bal = VEIL.balanceOf(address(this));
    if (bal <= totalBonded) {
      return 0;
    }
    return bal - totalBonded;
  }

  function fund(uint256 amount) external {
    if (amount == 0) revert Keep3rInvalidAmount();
    if (!VEIL.transferFrom(msg.sender, address(this), amount)) {
      revert Keep3rTransferFailed();
    }
    emit Funded(msg.sender, amount);
  }

  function bond(uint256 amount) external {
    if (amount == 0) revert Keep3rInvalidAmount();
    if (!VEIL.transferFrom(msg.sender, address(this), amount)) {
      revert Keep3rTransferFailed();
    }
    keeperBond[msg.sender] += amount;
    totalBonded += amount;
    emit Bonded(msg.sender, amount, keeperBond[msg.sender]);
  }

  function unbond(uint256 amount) external {
    if (amount == 0) revert Keep3rInvalidAmount();
    uint256 bonded = keeperBond[msg.sender];
    if (bonded < amount) revert Keep3rInsufficientBond();
    unchecked {
      keeperBond[msg.sender] = bonded - amount;
      totalBonded -= amount;
    }
    if (!VEIL.transfer(msg.sender, amount)) revert Keep3rTransferFailed();
    emit Unbonded(msg.sender, amount, keeperBond[msg.sender]);
  }

  function worked(address keeper, uint256 amount) external onlyJob {
    if (amount == 0) revert Keep3rInvalidAmount();
    if (!isKeeper(keeper)) revert Keep3rNotActiveKeeper();
    if (availableCredits() < amount) revert Keep3rInsufficientCredits();
    if (!VEIL.transfer(keeper, amount)) revert Keep3rTransferFailed();
    emit Worked(msg.sender, keeper, amount);
  }

  function slash(address keeper, uint256 amount, address recipient) external onlyOwner {
    if (recipient == address(0)) revert Keep3rZeroAddress();
    if (amount == 0) revert Keep3rInvalidAmount();
    uint256 bonded = keeperBond[keeper];
    if (bonded < amount) revert Keep3rInsufficientBond();
    unchecked {
      keeperBond[keeper] = bonded - amount;
      totalBonded -= amount;
    }
    if (!VEIL.transfer(recipient, amount)) revert Keep3rTransferFailed();
    emit Slashed(keeper, recipient, amount);
  }
}

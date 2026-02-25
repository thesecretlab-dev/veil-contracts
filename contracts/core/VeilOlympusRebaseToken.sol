// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Rebasing payout token for Olympus-style LP bonds.
/// @dev Uses a share + index accounting model so rebases are O(1).
contract VeilOlympusRebaseToken {
  uint256 public constant INDEX_SCALE = 1e18;
  uint256 public constant BPS_DENOMINATOR = 10_000;

  string public name;
  string public symbol;
  uint8 public constant decimals = 18;

  address public owner;
  address public vault;

  uint256 public index;
  uint256 public totalShares;

  mapping(address => uint256) public sharesOf;
  mapping(address => mapping(address => uint256)) public allowance;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event VaultSet(address indexed vault);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Rebased(uint256 oldIndex, uint256 newIndex, uint256 rebaseBps);
  event SharesMinted(address indexed to, uint256 shareAmount, uint256 amount);
  event SharesBurned(address indexed from, uint256 shareAmount, uint256 amount);
  event SharesTransferred(address indexed from, address indexed to, uint256 shareAmount, uint256 amount);

  modifier onlyOwner() {
    require(msg.sender == owner, "RebaseToken/not-owner");
    _;
  }

  modifier onlyVault() {
    require(msg.sender == vault, "RebaseToken/not-vault");
    _;
  }

  constructor(string memory name_, string memory symbol_) {
    require(bytes(name_).length != 0, "RebaseToken/empty-name");
    require(bytes(symbol_).length != 0, "RebaseToken/empty-symbol");
    owner = msg.sender;
    name = name_;
    symbol = symbol_;
    index = INDEX_SCALE;
    emit OwnershipTransferred(address(0), msg.sender);
  }

  function totalSupply() public view returns (uint256) {
    return amountForShares(totalShares);
  }

  function balanceOf(address account) public view returns (uint256) {
    return amountForShares(sharesOf[account]);
  }

  function amountForShares(uint256 shareAmount) public view returns (uint256) {
    return (shareAmount * index) / INDEX_SCALE;
  }

  function sharesForAmount(uint256 amount) public view returns (uint256) {
    return (amount * INDEX_SCALE) / index;
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "RebaseToken/invalid-owner");
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

  function setVault(address vault_) external onlyOwner {
    require(vault_ != address(0), "RebaseToken/invalid-vault");
    vault = vault_;
    emit VaultSet(vault_);
  }

  function approve(address spender, uint256 value) external returns (bool) {
    allowance[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transfer(address to, uint256 value) external returns (bool) {
    return transferFrom(msg.sender, to, value);
  }

  function transferFrom(address from, address to, uint256 value) public returns (bool) {
    require(to != address(0), "RebaseToken/invalid-recipient");
    require(value > 0, "RebaseToken/zero-value");

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "RebaseToken/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    uint256 shareAmount = sharesForAmount(value);
    require(shareAmount > 0, "RebaseToken/amount-too-small");
    require(sharesOf[from] >= shareAmount, "RebaseToken/insufficient-balance");

    unchecked {
      sharesOf[from] -= shareAmount;
      sharesOf[to] += shareAmount;
    }

    // Emit the exact token amount represented by transferred shares.
    emit Transfer(from, to, amountForShares(shareAmount));
    return true;
  }

  function mintShares(address to, uint256 shareAmount) external onlyVault returns (uint256 mintedAmount) {
    require(to != address(0), "RebaseToken/invalid-recipient");
    require(shareAmount > 0, "RebaseToken/zero-shares");
    totalShares += shareAmount;
    unchecked {
      sharesOf[to] += shareAmount;
    }
    mintedAmount = amountForShares(shareAmount);
    emit SharesMinted(to, shareAmount, mintedAmount);
    emit Transfer(address(0), to, mintedAmount);
  }

  /// @notice Moves raw shares from the vault to `to`, avoiding amount->shares rounding on claims.
  function transferShares(address to, uint256 shareAmount) external onlyVault returns (uint256 amountOut) {
    require(to != address(0), "RebaseToken/invalid-recipient");
    require(shareAmount > 0, "RebaseToken/zero-shares");
    require(sharesOf[vault] >= shareAmount, "RebaseToken/insufficient-vault-shares");

    unchecked {
      sharesOf[vault] -= shareAmount;
      sharesOf[to] += shareAmount;
    }

    amountOut = amountForShares(shareAmount);
    emit SharesTransferred(vault, to, shareAmount, amountOut);
    emit Transfer(vault, to, amountOut);
  }

  function burnShares(address from, uint256 shareAmount) external onlyVault returns (uint256 burnedAmount) {
    require(from != address(0), "RebaseToken/invalid-from");
    require(shareAmount > 0, "RebaseToken/zero-shares");
    require(sharesOf[from] >= shareAmount, "RebaseToken/insufficient-balance");
    unchecked {
      sharesOf[from] -= shareAmount;
      totalShares -= shareAmount;
    }
    burnedAmount = amountForShares(shareAmount);
    emit SharesBurned(from, shareAmount, burnedAmount);
    emit Transfer(from, address(0), burnedAmount);
  }

  function rebase(uint256 rebaseBps) external onlyVault returns (uint256 newIndex) {
    require(rebaseBps > 0, "RebaseToken/zero-rebase");
    uint256 oldIndex = index;
    newIndex = (oldIndex * (BPS_DENOMINATOR + rebaseBps)) / BPS_DENOMINATOR;
    require(newIndex > oldIndex, "RebaseToken/no-growth");
    index = newIndex;
    emit Rebased(oldIndex, newIndex, rebaseBps);
  }
}

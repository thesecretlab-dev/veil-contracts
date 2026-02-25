// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal VAI token for companion EVM rails.
/// @dev Owner sets minter (treasury); minter mints, holders can burn.
contract VeilVAI {
  string public constant name = "VEIL USD";
  string public constant symbol = "VAI";
  uint8 public constant decimals = 18;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event MinterSet(address indexed previousMinter, address indexed nextMinter);

  error VAIZeroAddress();
  error VAIOnlyOwner();
  error VAIOnlyMinter();
  error VAIInsufficientBalance();
  error VAIInsufficientAllowance();

  address public owner;
  address public minter;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  modifier onlyOwner() {
    if (msg.sender != owner) revert VAIOnlyOwner();
    _;
  }

  modifier onlyMinter() {
    if (msg.sender != minter) revert VAIOnlyMinter();
    _;
  }

  constructor(
    address owner_,
    address minter_,
    address initialRecipient_,
    uint256 initialSupply_
  ) {
    if (owner_ == address(0) || minter_ == address(0)) revert VAIZeroAddress();
    owner = owner_;
    minter = minter_;
    emit OwnershipTransferred(address(0), owner_);

    if (initialSupply_ > 0) {
      address recipient = initialRecipient_ == address(0) ? owner_ : initialRecipient_;
      _mint(recipient, initialSupply_);
    }
  }

  function transferOwnership(address nextOwner) external onlyOwner {
    if (nextOwner == address(0)) revert VAIZeroAddress();
    emit OwnershipTransferred(owner, nextOwner);
    owner = nextOwner;
  }

  function setMinter(address nextMinter) external onlyOwner {
    if (nextMinter == address(0)) revert VAIZeroAddress();
    emit MinterSet(minter, nextMinter);
    minter = nextMinter;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        if (allowed < amount) revert VAIInsufficientAllowance();
        unchecked {
          allowance[from][msg.sender] = allowed - amount;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }
    _transfer(from, to, amount);
    return true;
  }

  function mint(address to, uint256 amount) external onlyMinter {
    _mint(to, amount);
  }

  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }

  function burnFrom(address from, uint256 amount) external {
    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        if (allowed < amount) revert VAIInsufficientAllowance();
        unchecked {
          allowance[from][msg.sender] = allowed - amount;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }
    _burn(from, amount);
  }

  function _transfer(address from, address to, uint256 amount) internal {
    if (to == address(0)) revert VAIZeroAddress();
    uint256 fromBal = balanceOf[from];
    if (fromBal < amount) revert VAIInsufficientBalance();
    unchecked {
      balanceOf[from] = fromBal - amount;
      balanceOf[to] += amount;
    }
    emit Transfer(from, to, amount);
  }

  function _mint(address to, uint256 amount) internal {
    if (to == address(0)) revert VAIZeroAddress();
    totalSupply += amount;
    unchecked {
      balanceOf[to] += amount;
    }
    emit Transfer(address(0), to, amount);
  }

  function _burn(address from, uint256 amount) internal {
    uint256 fromBal = balanceOf[from];
    if (fromBal < amount) revert VAIInsufficientBalance();
    unchecked {
      balanceOf[from] = fromBal - amount;
      totalSupply -= amount;
    }
    emit Transfer(from, address(0), amount);
  }
}

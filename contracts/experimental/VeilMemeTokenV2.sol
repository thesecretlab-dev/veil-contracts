// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC-20 for VEIL memecoins with optional transfer burn + dividend fee.
/// @dev Fees are applied on transfer amount; burn permanently reduces totalSupply.
contract VeilMemeTokenV2 {
  string public name;
  string public symbol;
  uint8 public constant decimals = 18;
  uint256 public totalSupply;

  uint16 public immutable burnBps;
  uint16 public immutable dividendBps;
  address public immutable dividendRecipient;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  error BadConfig();
  error BadRecipient();
  error InsufficientAllowance();
  error InsufficientBalance();

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 supply_,
    address recipient_,
    uint16 burnBps_,
    uint16 dividendBps_,
    address dividendRecipient_
  ) {
    bytes memory nameBytes = bytes(name_);
    bytes memory symbolBytes = bytes(symbol_);
    if (nameBytes.length == 0 || nameBytes.length > 64) revert BadConfig();
    if (symbolBytes.length == 0 || symbolBytes.length > 12) revert BadConfig();
    if (recipient_ == address(0) || supply_ == 0) revert BadConfig();
    if (uint256(burnBps_) + uint256(dividendBps_) > 2_000) revert BadConfig(); // max 20% aggregate fee
    if (dividendBps_ > 0 && dividendRecipient_ == address(0)) revert BadConfig();

    name = name_;
    symbol = symbol_;
    burnBps = burnBps_;
    dividendBps = dividendBps_;
    dividendRecipient = dividendBps_ > 0 ? dividendRecipient_ : address(0);

    _mint(recipient_, supply_);
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
    if (to == address(0)) revert BadRecipient();

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        if (allowed < value) revert InsufficientAllowance();
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    if (balanceOf[from] < value) revert InsufficientBalance();

    uint256 burnFee = burnBps > 0 ? (value * burnBps) / 10_000 : 0;
    uint256 dividendFee = dividendBps > 0 ? (value * dividendBps) / 10_000 : 0;
    uint256 net = value - burnFee - dividendFee;

    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += net;
    }
    emit Transfer(from, to, net);

    if (dividendFee > 0) {
      address recipient = dividendRecipient;
      unchecked {
        balanceOf[recipient] += dividendFee;
      }
      emit Transfer(from, recipient, dividendFee);
    }

    if (burnFee > 0) {
      totalSupply -= burnFee;
      emit Transfer(from, address(0), burnFee);
    }

    return true;
  }

  function _mint(address to, uint256 value) internal {
    totalSupply += value;
    unchecked {
      balanceOf[to] += value;
    }
    emit Transfer(address(0), to, value);
  }
}

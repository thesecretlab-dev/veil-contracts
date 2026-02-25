// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal fixed-supply ERC-20 used for bot-launched ecosystem tokens.
contract VeilMemeToken {
  string public name;
  string public symbol;
  uint8 public constant decimals = 18;
  uint256 public totalSupply;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  constructor(string memory name_, string memory symbol_, uint256 supply_, address recipient_) {
    bytes memory nameBytes = bytes(name_);
    bytes memory symbolBytes = bytes(symbol_);
    require(nameBytes.length > 0 && nameBytes.length <= 64, "VeilMemeToken/bad-name");
    require(symbolBytes.length > 0 && symbolBytes.length <= 12, "VeilMemeToken/bad-symbol");
    require(recipient_ != address(0), "VeilMemeToken/bad-recipient");
    require(supply_ > 0, "VeilMemeToken/zero-supply");

    name = name_;
    symbol = symbol_;
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
    require(to != address(0), "VeilMemeToken/bad-recipient");

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "VeilMemeToken/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    require(balanceOf[from] >= value, "VeilMemeToken/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }
    emit Transfer(from, to, value);
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


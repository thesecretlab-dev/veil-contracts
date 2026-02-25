// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal WETH-style wrapper for the VEIL native token.
/// @dev This is foundational for using VEIL as ERC-20 collateral (Maker-style vaults, AMMs, POL, etc.).
contract WVEIL {
  string public constant name = "Wrapped VEIL";
  string public constant symbol = "wVEIL";
  uint8 public constant decimals = 18;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Deposit(address indexed account, uint256 value);
  event Withdrawal(address indexed account, uint256 value);

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  receive() external payable {
    deposit();
  }

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
    emit Deposit(msg.sender, msg.value);
    emit Transfer(address(0), msg.sender, msg.value);
  }

  function withdraw(uint256 value) external {
    require(balanceOf[msg.sender] >= value, "WVEIL/insufficient-balance");
    unchecked {
      balanceOf[msg.sender] -= value;
    }
    emit Transfer(msg.sender, address(0), value);
    emit Withdrawal(msg.sender, value);
    (bool ok, ) = msg.sender.call{ value: value }("");
    require(ok, "WVEIL/withdraw-failed");
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
    require(to != address(0), "WVEIL/invalid-recipient");

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "WVEIL/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    require(balanceOf[from] >= value, "WVEIL/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }

    emit Transfer(from, to, value);
    return true;
  }
}


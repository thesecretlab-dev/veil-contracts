// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Like {
  function balanceOf(address) external view returns (uint256);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Minimal constant-product pool between an ERC20 token and native VEIL.
/// @dev Meant for local L1 experiments, not production.
contract NativeVeilPool {
  // --- LP token (ERC20) ---
  string public name;
  string public symbol;
  uint8 public constant decimals = 18;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  // --- Pool ---
  IERC20Like public immutable token;
  uint16 public feeBps; // e.g. 30 = 0.30%
  address public owner;

  uint256 public reserveToken;
  uint256 public reserveVeil;

  event Sync(uint256 reserveToken, uint256 reserveVeil);
  event Mint(address indexed sender, address indexed to, uint256 tokenIn, uint256 veilIn, uint256 lpOut);
  event Burn(address indexed sender, address indexed to, uint256 lpIn, uint256 tokenOut, uint256 veilOut);
  event Swap(address indexed sender, address indexed to, uint256 tokenIn, uint256 veilIn, uint256 tokenOut, uint256 veilOut);

  error NotOwner();
  error InvalidRecipient();
  error InsufficientOut();
  error InsufficientLiquidity();

  modifier onlyOwner() {
    if (msg.sender != owner) revert NotOwner();
    _;
  }

  constructor(address token_, string memory name_, string memory symbol_, uint16 feeBps_) {
    require(token_ != address(0), "Pool/invalid-token");
    token = IERC20Like(token_);
    name = name_;
    symbol = symbol_;
    feeBps = feeBps_;
    owner = msg.sender;
  }

  receive() external payable {}

  function approve(address spender, uint256 value) external returns (bool) {
    allowance[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transfer(address to, uint256 value) external returns (bool) {
    return transferFrom(msg.sender, to, value);
  }

  function transferFrom(address from, address to, uint256 value) public returns (bool) {
    if (to == address(0)) revert InvalidRecipient();

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "Pool/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    require(balanceOf[from] >= value, "Pool/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }
    emit Transfer(from, to, value);
    return true;
  }

  function setFeeBps(uint16 nextFeeBps) external onlyOwner {
    require(nextFeeBps <= 1000, "Pool/fee-too-high");
    feeBps = nextFeeBps;
  }

  function transferOwnership(address nextOwner) external onlyOwner {
    require(nextOwner != address(0), "Pool/invalid-owner");
    owner = nextOwner;
  }

  function getReserves() external view returns (uint256, uint256) {
    return (reserveToken, reserveVeil);
  }

  function _sqrt(uint256 y) internal pure returns (uint256 z) {
    if (y > 3) {
      z = y;
      uint256 x = y / 2 + 1;
      while (x < z) {
        z = x;
        x = (y / x + x) / 2;
      }
    } else if (y != 0) {
      z = 1;
    }
  }

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function _update(uint256 tokenBal, uint256 veilBal) internal {
    reserveToken = tokenBal;
    reserveVeil = veilBal;
    emit Sync(tokenBal, veilBal);
  }

  function quoteLiquidity(uint256 tokenIn, uint256 veilIn) external view returns (uint256 lpOut) {
    uint256 supply = totalSupply;
    if (supply == 0) {
      lpOut = _sqrt(tokenIn * veilIn);
    } else {
      uint256 lp1 = (tokenIn * supply) / reserveToken;
      uint256 lp2 = (veilIn * supply) / reserveVeil;
      lpOut = _min(lp1, lp2);
    }
  }

  function addLiquidity(uint256 tokenIn, uint256 minLpOut, address to) external payable returns (uint256 lpOut) {
    if (to == address(0)) revert InvalidRecipient();
    require(tokenIn > 0 && msg.value > 0, "Pool/zero-in");

    uint256 tokenBalBefore = reserveToken;
    uint256 veilBalBefore = reserveVeil;

    require(token.transferFrom(msg.sender, address(this), tokenIn), "Pool/token-transfer-in-failed");

    uint256 supply = totalSupply;
    if (supply == 0) {
      lpOut = _sqrt(tokenIn * msg.value);
    } else {
      uint256 lp1 = (tokenIn * supply) / tokenBalBefore;
      uint256 lp2 = (msg.value * supply) / veilBalBefore;
      lpOut = _min(lp1, lp2);
    }
    require(lpOut > 0, "Pool/zero-lp");
    if (lpOut < minLpOut) revert InsufficientOut();

    totalSupply = supply + lpOut;
    unchecked {
      balanceOf[to] += lpOut;
    }
    emit Transfer(address(0), to, lpOut);
    emit Mint(msg.sender, to, tokenIn, msg.value, lpOut);

    _update(tokenBalBefore + tokenIn, veilBalBefore + msg.value);
  }

  function removeLiquidity(uint256 lpIn, uint256 minTokenOut, uint256 minVeilOut, address to)
    external
    returns (uint256 tokenOut, uint256 veilOut)
  {
    if (to == address(0)) revert InvalidRecipient();
    require(lpIn > 0, "Pool/zero-lp");
    require(balanceOf[msg.sender] >= lpIn, "Pool/insufficient-lp");

    uint256 supply = totalSupply;
    if (supply == 0) revert InsufficientLiquidity();

    uint256 tokenBal = reserveToken;
    uint256 veilBal = reserveVeil;

    tokenOut = (lpIn * tokenBal) / supply;
    veilOut = (lpIn * veilBal) / supply;
    if (tokenOut < minTokenOut || veilOut < minVeilOut) revert InsufficientOut();

    unchecked {
      balanceOf[msg.sender] -= lpIn;
    }
    totalSupply = supply - lpIn;
    emit Transfer(msg.sender, address(0), lpIn);

    require(token.transfer(to, tokenOut), "Pool/token-transfer-out-failed");
    (bool ok, ) = to.call{ value: veilOut }("");
    require(ok, "Pool/veil-transfer-out-failed");

    emit Burn(msg.sender, to, lpIn, tokenOut, veilOut);
    _update(tokenBal - tokenOut, veilBal - veilOut);
  }

  function getAmountOut(uint256 amountIn, bool inputIsVeil) public view returns (uint256 amountOut) {
    require(amountIn > 0, "Pool/zero-in");
    uint256 rIn = inputIsVeil ? reserveVeil : reserveToken;
    uint256 rOut = inputIsVeil ? reserveToken : reserveVeil;
    require(rIn > 0 && rOut > 0, "Pool/empty");

    uint256 amountInAfterFee = (amountIn * (10_000 - feeBps)) / 10_000;
    amountOut = (rOut * amountInAfterFee) / (rIn + amountInAfterFee);
  }

  function swapExactVeilForTokens(uint256 minTokensOut, address to) external payable returns (uint256 tokensOut) {
    if (to == address(0)) revert InvalidRecipient();
    uint256 veilIn = msg.value;
    tokensOut = getAmountOut(veilIn, true);
    if (tokensOut < minTokensOut) revert InsufficientOut();

    uint256 tokenBal = reserveToken;
    uint256 veilBal = reserveVeil;

    require(token.transfer(to, tokensOut), "Pool/token-transfer-out-failed");

    emit Swap(msg.sender, to, 0, veilIn, tokensOut, 0);
    _update(tokenBal - tokensOut, veilBal + veilIn);
  }

  function swapExactTokensForVeil(uint256 tokenIn, uint256 minVeilOut, address to) external returns (uint256 veilOut) {
    if (to == address(0)) revert InvalidRecipient();
    veilOut = getAmountOut(tokenIn, false);
    if (veilOut < minVeilOut) revert InsufficientOut();

    uint256 tokenBal = reserveToken;
    uint256 veilBal = reserveVeil;

    require(token.transferFrom(msg.sender, address(this), tokenIn), "Pool/token-transfer-in-failed");
    (bool ok, ) = to.call{ value: veilOut }("");
    require(ok, "Pool/veil-transfer-out-failed");

    emit Swap(msg.sender, to, tokenIn, 0, 0, veilOut);
    _update(tokenBal + tokenIn, veilBal - veilOut);
  }
}

contract IronVeilPool is NativeVeilPool {
  constructor(address token_) NativeVeilPool(token_, "Iron/VEIL LP", "iMIN-VEIL-LP", 30) {}
}

contract CopperVeilPool is NativeVeilPool {
  constructor(address token_) NativeVeilPool(token_, "Copper/VEIL LP", "cMIN-VEIL-LP", 30) {}
}

contract SilverVeilPool is NativeVeilPool {
  constructor(address token_) NativeVeilPool(token_, "Silver/VEIL LP", "sMIN-VEIL-LP", 30) {}
}

contract GoldVeilPool is NativeVeilPool {
  constructor(address token_) NativeVeilPool(token_, "Gold/VEIL LP", "gMIN-VEIL-LP", 30) {}
}

contract DiamondVeilPool is NativeVeilPool {
  constructor(address token_) NativeVeilPool(token_, "Diamond/VEIL LP", "dMIN-VEIL-LP", 30) {}
}


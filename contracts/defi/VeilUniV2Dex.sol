// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20MiniUniV2 {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library VeilUniV2Math {
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function sqrt(uint256 y) internal pure returns (uint256 z) {
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
}

/// @notice Minimal Uniswap V2-style pair for VEIL companion EVM rails.
contract VeilUniV2Pair {
  string public constant name = "VEIL LP";
  string public constant symbol = "VLP";
  uint8 public constant decimals = 18;
  uint256 public constant MINIMUM_LIQUIDITY = 1_000;

  address public immutable factory;
  address public immutable token0;
  address public immutable token1;

  uint112 private reserve0;
  uint112 private reserve1;
  uint32 private blockTimestampLast;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Mint(address indexed sender, uint256 amount0, uint256 amount1);
  event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );
  event Sync(uint112 reserve0, uint112 reserve1);

  error UniV2BadConfig();
  error UniV2InsufficientLiquidityMinted();
  error UniV2InsufficientLiquidityBurned();
  error UniV2InsufficientOutputAmount();
  error UniV2InsufficientLiquidity();
  error UniV2InvalidTo();
  error UniV2TransferFailed();
  error UniV2KInvariant();

  constructor(address token0_, address token1_) {
    if (token0_ == token1_ || token0_ == address(0) || token1_ == address(0)) {
      revert UniV2BadConfig();
    }
    factory = msg.sender;
    token0 = token0_;
    token1 = token1_;
  }

  function getReserves() external view returns (uint112, uint112, uint32) {
    return (reserve0, reserve1, blockTimestampLast);
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
    if (to == address(0)) revert UniV2InvalidTo();
    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "UniV2/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }
    require(balanceOf[from] >= value, "UniV2/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }
    emit Transfer(from, to, value);
    return true;
  }

  function mint(address to) external returns (uint256 liquidity) {
    (uint112 r0, uint112 r1,) = (reserve0, reserve1, blockTimestampLast);
    uint256 balance0 = IERC20MiniUniV2(token0).balanceOf(address(this));
    uint256 balance1 = IERC20MiniUniV2(token1).balanceOf(address(this));
    uint256 amount0 = balance0 - r0;
    uint256 amount1 = balance1 - r1;

    uint256 _totalSupply = totalSupply;
    if (_totalSupply == 0) {
      liquidity = VeilUniV2Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
      _mint(address(0), MINIMUM_LIQUIDITY);
    } else {
      liquidity = VeilUniV2Math.min((amount0 * _totalSupply) / r0, (amount1 * _totalSupply) / r1);
    }

    if (liquidity == 0) revert UniV2InsufficientLiquidityMinted();
    _mint(to, liquidity);
    _update(balance0, balance1);
    emit Mint(msg.sender, amount0, amount1);
  }

  function burn(address to) external returns (uint256 amount0, uint256 amount1) {
    if (to == address(0)) revert UniV2InvalidTo();
    address _token0 = token0;
    address _token1 = token1;
    uint256 balance0 = IERC20MiniUniV2(_token0).balanceOf(address(this));
    uint256 balance1 = IERC20MiniUniV2(_token1).balanceOf(address(this));
    uint256 liquidity = balanceOf[address(this)];

    uint256 _totalSupply = totalSupply;
    amount0 = (liquidity * balance0) / _totalSupply;
    amount1 = (liquidity * balance1) / _totalSupply;
    if (amount0 == 0 || amount1 == 0) revert UniV2InsufficientLiquidityBurned();

    _burn(address(this), liquidity);
    _safeTransfer(_token0, to, amount0);
    _safeTransfer(_token1, to, amount1);

    balance0 = IERC20MiniUniV2(_token0).balanceOf(address(this));
    balance1 = IERC20MiniUniV2(_token1).balanceOf(address(this));

    _update(balance0, balance1);
    emit Burn(msg.sender, amount0, amount1, to);
  }

  function swap(uint256 amount0Out, uint256 amount1Out, address to) external {
    if (amount0Out == 0 && amount1Out == 0) revert UniV2InsufficientOutputAmount();
    (uint112 r0, uint112 r1,) = (reserve0, reserve1, blockTimestampLast);
    if (amount0Out >= r0 || amount1Out >= r1) revert UniV2InsufficientLiquidity();
    if (to == token0 || to == token1 || to == address(0)) revert UniV2InvalidTo();

    if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
    if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

    uint256 balance0 = IERC20MiniUniV2(token0).balanceOf(address(this));
    uint256 balance1 = IERC20MiniUniV2(token1).balanceOf(address(this));
    uint256 amount0In = balance0 > (r0 - amount0Out) ? balance0 - (r0 - amount0Out) : 0;
    uint256 amount1In = balance1 > (r1 - amount1Out) ? balance1 - (r1 - amount1Out) : 0;
    if (amount0In == 0 && amount1In == 0) revert UniV2InsufficientOutputAmount();

    // 30 bps fee: x * 997 / 1000.
    uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
    uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
    if (balance0Adjusted * balance1Adjusted < uint256(r0) * uint256(r1) * 1_000_000) {
      revert UniV2KInvariant();
    }

    _update(balance0, balance1);
    emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
  }

  function sync() external {
    _update(
      IERC20MiniUniV2(token0).balanceOf(address(this)),
      IERC20MiniUniV2(token1).balanceOf(address(this))
    );
  }

  function _safeTransfer(address token, address to, uint256 value) private {
    (bool ok, bytes memory data) =
      token.call(abi.encodeWithSelector(IERC20MiniUniV2.transfer.selector, to, value));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
      revert UniV2TransferFailed();
    }
  }

  function _update(uint256 balance0, uint256 balance1) private {
    reserve0 = uint112(balance0);
    reserve1 = uint112(balance1);
    blockTimestampLast = uint32(block.timestamp);
    emit Sync(reserve0, reserve1);
  }

  function _mint(address to, uint256 value) private {
    totalSupply += value;
    unchecked {
      balanceOf[to] += value;
    }
    emit Transfer(address(0), to, value);
  }

  function _burn(address from, uint256 value) private {
    unchecked {
      balanceOf[from] -= value;
      totalSupply -= value;
    }
    emit Transfer(from, address(0), value);
  }
}

contract VeilUniV2Factory {
  mapping(address => mapping(address => address)) public getPair;
  address[] public allPairs;

  event PairCreated(address indexed token0, address indexed token1, address pair, uint256 totalPairs);

  error UniV2IdenticalAddresses();
  error UniV2ZeroAddress();
  error UniV2PairExists();

  function allPairsLength() external view returns (uint256) {
    return allPairs.length;
  }

  function createPair(address tokenA, address tokenB) external returns (address pair) {
    if (tokenA == tokenB) revert UniV2IdenticalAddresses();
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    if (token0 == address(0)) revert UniV2ZeroAddress();
    if (getPair[token0][token1] != address(0)) revert UniV2PairExists();

    pair = address(new VeilUniV2Pair(token0, token1));
    getPair[token0][token1] = pair;
    getPair[token1][token0] = pair;
    allPairs.push(pair);

    emit PairCreated(token0, token1, pair, allPairs.length);
  }
}

contract VeilUniV2Router {
  address public immutable factory;

  error UniV2InvalidPath();
  error UniV2PairMissing();
  error UniV2InsufficientA();
  error UniV2InsufficientB();
  error UniV2InsufficientOut();
  error UniV2TransferFailed();

  constructor(address factory_) {
    require(factory_ != address(0), "UniV2Router/bad-factory");
    factory = factory_;
  }

  function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
    require(amountA > 0, "UniV2Router/insufficient-amount");
    require(reserveA > 0 && reserveB > 0, "UniV2Router/insufficient-liquidity");
    amountB = (amountA * reserveB) / reserveA;
  }

  function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
    public
    pure
    returns (uint256 amountOut)
  {
    require(amountIn > 0, "UniV2Router/insufficient-input");
    require(reserveIn > 0 && reserveOut > 0, "UniV2Router/insufficient-liquidity");
    uint256 amountInWithFee = amountIn * 997;
    amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
  }

  function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
    if (path.length < 2) revert UniV2InvalidPath();
    amounts = new uint256[](path.length);
    amounts[0] = amountIn;
    for (uint256 i = 0; i < path.length - 1; i++) {
      (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);
      amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
    }
  }

  function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
    address pair = VeilUniV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) revert UniV2PairMissing();
    (address token0,) = sortTokens(tokenA, tokenB);
    (uint112 reserve0, uint112 reserve1,) = VeilUniV2Pair(pair).getReserves();
    (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to
  ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
    address pair = VeilUniV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) {
      pair = VeilUniV2Factory(factory).createPair(tokenA, tokenB);
    }

    (uint256 reserveA, uint256 reserveB) = _tryGetReserves(tokenA, tokenB);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        if (amountBOptimal < amountBMin) revert UniV2InsufficientB();
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
        if (amountAOptimal < amountAMin) revert UniV2InsufficientA();
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }

    _safeTransferFrom(tokenA, msg.sender, pair, amountA);
    _safeTransferFrom(tokenB, msg.sender, pair, amountB);
    liquidity = VeilUniV2Pair(pair).mint(to);
  }

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to
  ) external returns (uint256 amountA, uint256 amountB) {
    address pair = VeilUniV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) revert UniV2PairMissing();
    _safeTransferFrom(pair, msg.sender, pair, liquidity);
    (uint256 amount0, uint256 amount1) = VeilUniV2Pair(pair).burn(to);
    (address token0,) = sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    if (amountA < amountAMin) revert UniV2InsufficientA();
    if (amountB < amountBMin) revert UniV2InsufficientB();
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to
  ) external returns (uint256[] memory amounts) {
    amounts = getAmountsOut(amountIn, path);
    if (amounts[amounts.length - 1] < amountOutMin) revert UniV2InsufficientOut();
    address firstPair = VeilUniV2Factory(factory).getPair(path[0], path[1]);
    if (firstPair == address(0)) revert UniV2PairMissing();
    _safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);
    _swap(amounts, path, to);
  }

  function _swap(uint256[] memory amounts, address[] calldata path, address to_) internal {
    for (uint256 i = 0; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      address pair = VeilUniV2Factory(factory).getPair(input, output);
      if (pair == address(0)) revert UniV2PairMissing();
      (address token0,) = sortTokens(input, output);
      uint256 amountOut = amounts[i + 1];
      (uint256 amount0Out, uint256 amount1Out) =
        input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
      address to = i < path.length - 2
        ? VeilUniV2Factory(factory).getPair(output, path[i + 2])
        : to_;
      VeilUniV2Pair(pair).swap(amount0Out, amount1Out, to);
    }
  }

  function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
    require(tokenA != tokenB, "UniV2Router/identical");
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "UniV2Router/zero");
  }

  function _tryGetReserves(address tokenA, address tokenB)
    internal
    view
    returns (uint256 reserveA, uint256 reserveB)
  {
    address pair = VeilUniV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) return (0, 0);
    (address token0,) = sortTokens(tokenA, tokenB);
    (uint112 reserve0, uint112 reserve1,) = VeilUniV2Pair(pair).getReserves();
    (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
  }

  function _safeTransferFrom(address token, address from, address to, uint256 value) private {
    (bool ok, bytes memory data) =
      token.call(abi.encodeWithSelector(IERC20MiniUniV2.transferFrom.selector, from, to, value));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
      revert UniV2TransferFailed();
    }
  }
}

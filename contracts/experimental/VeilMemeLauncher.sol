// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./VeilMemeTokenV2.sol";
import "./VeilLinearVesting.sol";
import "./VeilMemeV2Dex.sol";

/// @notice Permissionless VEIL memecoin launchpad with bonding-curve discovery and V2 graduation.
contract VeilMemeLauncher {
  uint256 private constant WAD = 1e18;
  address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

  address public immutable vdai;
  VeilMemeV2Factory public immutable v2Factory;
  VeilMemeV2Router public immutable v2Router;

  uint256 public totalLaunches;
  mapping(address => uint256) public launchesByCreator;
  mapping(address => address) public tokenCreator;
  mapping(address => LaunchInfo) private launchStore;

  struct TokenConfig {
    uint256 totalSupply;
    uint16 burnBps;
    uint16 dividendBps;
    uint16 creatorVestingBps;
    uint32 creatorVestingDuration;
    bool burnLpOnGraduate;
    address dividendRecipient;
  }

  struct CurveConfig {
    uint256 virtualTokenReserve;
    uint256 virtualVdaiReserve;
    uint256 minVdaiForGraduation;
  }

  struct LaunchInfo {
    address creator;
    address recipient;
    address vesting;
    address pair;
    uint256 totalSupply;
    uint256 curveTokenReserve;
    uint256 curveVdaiReserve;
    uint256 virtualTokenReserve;
    uint256 virtualVdaiReserve;
    uint256 minVdaiForGraduation;
    uint16 burnBps;
    uint16 dividendBps;
    uint16 creatorVestingBps;
    uint32 creatorVestingDuration;
    bool burnLpOnGraduate;
    bool graduated;
  }

  event TokenLaunched(
    address indexed creator,
    address indexed token,
    address indexed recipient,
    string name,
    string symbol,
    uint256 supply
  );
  event TokenConfigured(
    address indexed token,
    uint16 burnBps,
    uint16 dividendBps,
    uint16 creatorVestingBps,
    uint32 creatorVestingDuration,
    bool burnLpOnGraduate
  );
  event CurveBought(
    address indexed buyer,
    address indexed token,
    address indexed recipient,
    uint256 vdaiIn,
    uint256 tokenOut,
    uint256 spotPriceVdaiWad
  );
  event CurveSold(
    address indexed seller,
    address indexed token,
    address indexed recipient,
    uint256 tokenIn,
    uint256 vdaiOut,
    uint256 spotPriceVdaiWad
  );
  event TokenGraduated(
    address indexed token,
    address indexed pair,
    uint256 tokenLiquidity,
    uint256 vdaiLiquidity,
    uint256 lpLiquidity,
    bool burnedLp
  );

  error BadConfig();
  error UnknownToken();
  error LaunchClosed();
  error Slippage();
  error TransferFailed();
  error NotGraduationReady();

  constructor(address vdai_, address factory_, address router_) {
    if (vdai_ == address(0)) revert BadConfig();
    vdai = vdai_;

    if (factory_ == address(0)) {
      VeilMemeV2Factory deployedFactory = new VeilMemeV2Factory();
      v2Factory = deployedFactory;
    } else {
      v2Factory = VeilMemeV2Factory(factory_);
    }

    if (router_ == address(0)) {
      v2Router = new VeilMemeV2Router(address(v2Factory));
    } else {
      v2Router = VeilMemeV2Router(router_);
      if (v2Router.factory() != address(v2Factory)) revert BadConfig();
    }
  }

  /// @notice Backward-compatible launch path with defaults.
  function launchToken(
    string calldata name_,
    string calldata symbol_,
    uint256 supply_,
    address recipient_
  ) external returns (address token) {
    TokenConfig memory tokenConfig = TokenConfig({
      totalSupply: supply_,
      burnBps: 0,
      dividendBps: 0,
      creatorVestingBps: 0,
      creatorVestingDuration: 0,
      burnLpOnGraduate: true,
      dividendRecipient: recipient_
    });
    CurveConfig memory curveConfig = CurveConfig({
      virtualTokenReserve: supply_,
      virtualVdaiReserve: 100 * WAD,
      minVdaiForGraduation: 25 * WAD
    });
    token = _launchToken(name_, symbol_, tokenConfig, curveConfig, recipient_);
  }

  function launchTokenAdvanced(
    string calldata name_,
    string calldata symbol_,
    TokenConfig calldata tokenConfig_,
    CurveConfig calldata curveConfig_,
    address recipient_
  ) external returns (address token) {
    token = _launchToken(name_, symbol_, tokenConfig_, curveConfig_, recipient_);
  }

  function launches(address token) external view returns (LaunchInfo memory) {
    return launchStore[token];
  }

  function buyOnCurve(address token, uint256 vdaiIn, uint256 minTokensOut, address recipient)
    external
    returns (uint256 tokenOut, bool graduatedNow)
  {
    if (vdaiIn == 0) revert BadConfig();
    LaunchInfo storage launch = launchStore[token];
    if (launch.creator == address(0)) revert UnknownToken();
    if (launch.graduated) revert LaunchClosed();

    address to = recipient == address(0) ? msg.sender : recipient;

    uint256 beforeBal = IERC20Mini(vdai).balanceOf(address(this));
    _safeTransferFrom(vdai, msg.sender, address(this), vdaiIn);
    uint256 afterBal = IERC20Mini(vdai).balanceOf(address(this));
    uint256 actualIn = afterBal - beforeBal;
    if (actualIn == 0) revert BadConfig();

    tokenOut = _quoteOut(launch.virtualTokenReserve, launch.virtualVdaiReserve, actualIn);
    if (tokenOut > launch.curveTokenReserve) tokenOut = launch.curveTokenReserve;
    if (tokenOut == 0 || tokenOut < minTokensOut) revert Slippage();

    launch.curveVdaiReserve += actualIn;
    launch.curveTokenReserve -= tokenOut;
    launch.virtualVdaiReserve += actualIn;
    launch.virtualTokenReserve -= tokenOut;

    _safeTransfer(token, to, tokenOut);
    uint256 spotPrice = curveSpotPriceWad(token);
    emit CurveBought(msg.sender, token, to, actualIn, tokenOut, spotPrice);

    if (launch.curveVdaiReserve >= launch.minVdaiForGraduation && launch.curveTokenReserve > 0) {
      (, , graduatedNow) = _graduate(token, launch);
    }
  }

  function sellOnCurve(address token, uint256 tokenIn, uint256 minVdaiOut, address recipient) external returns (uint256 vdaiOut) {
    if (tokenIn == 0) revert BadConfig();
    LaunchInfo storage launch = launchStore[token];
    if (launch.creator == address(0)) revert UnknownToken();
    if (launch.graduated) revert LaunchClosed();

    address to = recipient == address(0) ? msg.sender : recipient;

    uint256 beforeToken = IERC20Mini(token).balanceOf(address(this));
    _safeTransferFrom(token, msg.sender, address(this), tokenIn);
    uint256 afterToken = IERC20Mini(token).balanceOf(address(this));
    uint256 actualIn = afterToken - beforeToken;
    if (actualIn == 0) revert BadConfig();

    vdaiOut = _quoteOut(launch.virtualVdaiReserve, launch.virtualTokenReserve, actualIn);
    if (vdaiOut > launch.curveVdaiReserve) vdaiOut = launch.curveVdaiReserve;
    if (vdaiOut == 0 || vdaiOut < minVdaiOut) revert Slippage();

    launch.curveTokenReserve += actualIn;
    launch.curveVdaiReserve -= vdaiOut;
    launch.virtualTokenReserve += actualIn;
    launch.virtualVdaiReserve -= vdaiOut;

    _safeTransfer(vdai, to, vdaiOut);
    uint256 spotPrice = curveSpotPriceWad(token);
    emit CurveSold(msg.sender, token, to, actualIn, vdaiOut, spotPrice);
  }

  function graduate(address token) external returns (address pair, uint256 lpLiquidity) {
    LaunchInfo storage launch = launchStore[token];
    if (launch.creator == address(0)) revert UnknownToken();
    if (launch.graduated) revert LaunchClosed();
    if (launch.curveVdaiReserve < launch.minVdaiForGraduation) revert NotGraduationReady();

    (pair, lpLiquidity,) = _graduate(token, launch);
  }

  function curveSpotPriceWad(address token) public view returns (uint256) {
    LaunchInfo memory launch = launchStore[token];
    if (launch.creator == address(0)) return 0;
    if (launch.graduated && launch.pair != address(0)) {
      (uint256 reserveToken, uint256 reserveVdai) = _pairReservesInTokenOrder(launch.pair, token, vdai);
      if (reserveToken == 0) return 0;
      return (reserveVdai * WAD) / reserveToken;
    }
    if (launch.virtualTokenReserve == 0) return 0;
    return (launch.virtualVdaiReserve * WAD) / launch.virtualTokenReserve;
  }

  function quoteCurveBuy(address token, uint256 vdaiIn) external view returns (uint256 tokenOut) {
    LaunchInfo memory launch = launchStore[token];
    if (launch.creator == address(0) || launch.graduated || vdaiIn == 0) return 0;
    tokenOut = _quoteOut(launch.virtualTokenReserve, launch.virtualVdaiReserve, vdaiIn);
    if (tokenOut > launch.curveTokenReserve) tokenOut = launch.curveTokenReserve;
  }

  function quoteCurveSell(address token, uint256 tokenIn) external view returns (uint256 vdaiOut) {
    LaunchInfo memory launch = launchStore[token];
    if (launch.creator == address(0) || launch.graduated || tokenIn == 0) return 0;
    vdaiOut = _quoteOut(launch.virtualVdaiReserve, launch.virtualTokenReserve, tokenIn);
    if (vdaiOut > launch.curveVdaiReserve) vdaiOut = launch.curveVdaiReserve;
  }

  function _launchToken(
    string calldata name_,
    string calldata symbol_,
    TokenConfig memory tokenConfig_,
    CurveConfig memory curveConfig_,
    address recipient_
  ) internal returns (address token) {
    address recipient = recipient_ == address(0) ? msg.sender : recipient_;
    address dividendRecipient = _validateTokenConfig(tokenConfig_, recipient);
    token = _deployMemeToken(name_, symbol_, tokenConfig_, dividendRecipient);

    (address vesting, uint256 curveTokenReserve) = _setupVesting(token, recipient, tokenConfig_);
    (uint256 virtualToken, uint256 virtualVdai, uint256 minGrad) = _resolveCurveConfig(curveConfig_, curveTokenReserve);

    LaunchInfo storage info = launchStore[token];
    info.creator = msg.sender;
    info.recipient = recipient;
    info.vesting = vesting;
    info.pair = address(0);
    info.totalSupply = tokenConfig_.totalSupply;
    info.curveTokenReserve = curveTokenReserve;
    info.curveVdaiReserve = 0;
    info.virtualTokenReserve = virtualToken;
    info.virtualVdaiReserve = virtualVdai;
    info.minVdaiForGraduation = minGrad;
    info.burnBps = tokenConfig_.burnBps;
    info.dividendBps = tokenConfig_.dividendBps;
    info.creatorVestingBps = tokenConfig_.creatorVestingBps;
    info.creatorVestingDuration = tokenConfig_.creatorVestingDuration;
    info.burnLpOnGraduate = tokenConfig_.burnLpOnGraduate;
    info.graduated = false;

    totalLaunches += 1;
    launchesByCreator[msg.sender] += 1;
    tokenCreator[token] = msg.sender;

    emit TokenLaunched(msg.sender, token, recipient, "", "", tokenConfig_.totalSupply);
  }

  function _validateTokenConfig(TokenConfig memory tokenConfig_, address recipient) internal pure returns (address) {
    if (tokenConfig_.totalSupply == 0) revert BadConfig();
    if (uint256(tokenConfig_.burnBps) + uint256(tokenConfig_.dividendBps) > 2_000) revert BadConfig();
    if (tokenConfig_.creatorVestingBps > 8_000) revert BadConfig();
    if (tokenConfig_.creatorVestingBps > 0 && tokenConfig_.creatorVestingDuration == 0) revert BadConfig();
    return tokenConfig_.dividendRecipient == address(0) ? recipient : tokenConfig_.dividendRecipient;
  }

  function _deployMemeToken(
    string calldata name_,
    string calldata symbol_,
    TokenConfig memory tokenConfig_,
    address dividendRecipient
  ) internal returns (address token) {
    VeilMemeTokenV2 deployed = new VeilMemeTokenV2(
      name_,
      symbol_,
      tokenConfig_.totalSupply,
      address(this),
      tokenConfig_.burnBps,
      tokenConfig_.dividendBps,
      dividendRecipient
    );
    token = address(deployed);
  }

  function _setupVesting(address token, address recipient, TokenConfig memory tokenConfig_)
    internal
    returns (address vesting, uint256 curveTokenReserve)
  {
    uint256 vestingAmount = (tokenConfig_.totalSupply * tokenConfig_.creatorVestingBps) / 10_000;
    if (vestingAmount > 0) {
      vesting = address(
        new VeilLinearVesting(
          token,
          recipient,
          uint64(block.timestamp),
          tokenConfig_.creatorVestingDuration,
          vestingAmount
        )
      );
      _safeTransfer(token, vesting, vestingAmount);
    }

    curveTokenReserve = tokenConfig_.totalSupply - vestingAmount;
    if (curveTokenReserve == 0) revert BadConfig();
  }

  function _resolveCurveConfig(CurveConfig memory curveConfig_, uint256 curveTokenReserve)
    internal
    pure
    returns (uint256 virtualToken, uint256 virtualVdai, uint256 minGrad)
  {
    virtualToken = curveConfig_.virtualTokenReserve >= curveTokenReserve ? curveConfig_.virtualTokenReserve : curveTokenReserve;
    virtualVdai = curveConfig_.virtualVdaiReserve == 0 ? 100 * WAD : curveConfig_.virtualVdaiReserve;
    minGrad = curveConfig_.minVdaiForGraduation == 0 ? 25 * WAD : curveConfig_.minVdaiForGraduation;
  }

  function _graduate(address token, LaunchInfo storage launch)
    internal
    returns (address pair, uint256 lpLiquidity, bool graduatedNow)
  {
    uint256 tokenLiquidity = launch.curveTokenReserve;
    uint256 vdaiLiquidity = launch.curveVdaiReserve;
    if (tokenLiquidity == 0 || vdaiLiquidity == 0) revert BadConfig();

    pair = v2Factory.getPair(token, vdai);
    if (pair == address(0)) pair = v2Factory.createPair(token, vdai);

    _approveMax(token, address(v2Router), tokenLiquidity);
    _approveMax(vdai, address(v2Router), vdaiLiquidity);

    address lpRecipient = launch.burnLpOnGraduate ? DEAD : launch.recipient;
    (uint256 usedToken, uint256 usedVdai, uint256 minted) =
      v2Router.addLiquidity(token, vdai, tokenLiquidity, vdaiLiquidity, 0, 0, lpRecipient);

    launch.curveTokenReserve -= usedToken;
    launch.curveVdaiReserve -= usedVdai;
    launch.pair = pair;
    launch.graduated = true;
    lpLiquidity = minted;
    graduatedNow = true;

    emit TokenGraduated(token, pair, usedToken, usedVdai, minted, launch.burnLpOnGraduate);
  }

  function _quoteOut(uint256 reserveOut, uint256 reserveIn, uint256 amountIn) internal pure returns (uint256 amountOut) {
    if (reserveOut == 0 || reserveIn == 0 || amountIn == 0) return 0;
    uint256 k = reserveOut * reserveIn;
    uint256 newReserveIn = reserveIn + amountIn;
    if (newReserveIn == 0) return 0;
    uint256 newReserveOut = k / newReserveIn;
    if (newReserveOut >= reserveOut) return 0;
    amountOut = reserveOut - newReserveOut;
  }

  function _pairReservesInTokenOrder(address pair, address tokenA, address tokenB) internal view returns (uint256, uint256) {
    (uint112 reserve0, uint112 reserve1,) = VeilMemeV2Pair(pair).getReserves();
    address token0 = VeilMemeV2Pair(pair).token0();
    if (tokenA == token0) {
      return (reserve0, reserve1);
    }
    if (tokenB == token0) {
      return (reserve1, reserve0);
    }
    revert BadConfig();
  }

  function _approveMax(address token, address spender, uint256 needed) internal {
    if (IERC20Mini(token).allowance(address(this), spender) < needed) {
      _safeApprove(token, spender, type(uint256).max);
    }
  }

  function _safeTransfer(address token, address to, uint256 value) internal {
    (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Mini.transfer.selector, to, value));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
  }

  function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
    (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Mini.transferFrom.selector, from, to, value));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
  }

  function _safeApprove(address token, address spender, uint256 value) internal {
    (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Mini.approve.selector, spender, value));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
  }

}

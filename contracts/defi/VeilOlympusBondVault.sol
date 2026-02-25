// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20LikeOlympus {
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function totalSupply() external view returns (uint256);
}

interface IUniV2LikePairOlympus is IERC20LikeOlympus {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IVeilOlympusRebaseToken {
  function sharesForAmount(uint256 amount) external view returns (uint256);
  function amountForShares(uint256 shareAmount) external view returns (uint256);
  function mintShares(address to, uint256 shareAmount) external returns (uint256 mintedAmount);
  function transferShares(address to, uint256 shareAmount) external returns (uint256 amountOut);
  function rebase(uint256 rebaseBps) external returns (uint256 newIndex);
}

/// @notice Olympus-style LP bond vault for wsVEIL/svDAI liquidity with rebasing payouts.
/// @dev Accepts only wsVEIL/svDAI LP bonds and supports an upward-only RBS floor on payout token liquidity.
contract VeilOlympusBondVault {
  uint256 public constant BPS_DENOMINATOR = 10_000;
  uint256 public constant PRICE_SCALE = 1e18;
  uint256 public constant YEAR_SECONDS = 365 days;

  struct BondPosition {
    uint128 totalShares;
    uint128 claimedShares;
    uint64 vestStart;
    uint64 vestEnd;
  }

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event TreasurySet(address indexed treasury);
  event BondTermsSet(uint32 vestingTerm, uint16 defaultBondDiscountBps);
  event RebaseTermsSet(uint32 annualProjectedGrowthBps, uint16 maxEpochRebaseBps, uint32 epochLength);
  event RbsConfigSet(
    address indexed pair,
    uint256 floorPriceE18,
    uint16 floorGrowthBpsPerEpoch,
    uint16 maxBondDiscountBps,
    bool payoutTokenIsToken0
  );
  event RbsFloorAdvanced(uint256 previousFloorPriceE18, uint256 nextFloorPriceE18, uint256 epochsAdvanced);
  event BondDeposited(
    address indexed depositor,
    address indexed receiver,
    uint256 lpAmount,
    uint256 payoutAmount,
    uint256 payoutShares,
    uint16 discountBps
  );
  event BondClaimed(address indexed account, address indexed receiver, uint256 payoutAmount, uint256 payoutShares);
  event RebaseTriggered(
    address indexed caller, uint256 rebaseBps, uint256 epochsElapsed, uint256 newIndex, uint256 effectiveFloorPriceE18
  );

  address public owner;
  address public treasury;

  IUniV2LikePairOlympus public immutable bondLpToken;
  address public immutable wsVEIL;
  address public immutable svDAI;
  IVeilOlympusRebaseToken public immutable payoutToken;

  uint32 public vestingTerm;
  uint32 public epochLength;
  uint32 public annualProjectedGrowthBps;
  uint16 public maxEpochRebaseBps;
  uint16 public defaultBondDiscountBps;

  // RBS (Range Bound Stability): upward-only floor for payout token spot price against svDAI.
  address public rbsPair;
  bool public rbsPayoutTokenIsToken0;
  uint256 public rbsFloorPriceE18; // svDAI per payout token (1e18 scale)
  uint16 public rbsFloorGrowthBpsPerEpoch;
  uint16 public rbsMaxBondDiscountBps;
  uint64 public rbsLastFloorAt;

  uint64 public lastRebaseAt;

  mapping(address => BondPosition) public bonds;

  modifier onlyOwner() {
    require(msg.sender == owner, "OlympusVault/not-owner");
    _;
  }

  constructor(
    address bondLpToken_,
    address wsVEIL_,
    address svDAI_,
    address payoutToken_,
    address treasury_,
    uint32 vestingTerm_,
    uint32 epochLength_,
    uint32 annualProjectedGrowthBps_,
    uint16 maxEpochRebaseBps_,
    uint16 defaultBondDiscountBps_
  ) {
    require(bondLpToken_ != address(0), "OlympusVault/invalid-bond-lp");
    require(wsVEIL_ != address(0), "OlympusVault/invalid-wsVEIL");
    require(svDAI_ != address(0), "OlympusVault/invalid-svDAI");
    require(payoutToken_ != address(0), "OlympusVault/invalid-payout-token");
    require(treasury_ != address(0), "OlympusVault/invalid-treasury");
    require(vestingTerm_ > 0, "OlympusVault/invalid-vesting");
    require(epochLength_ > 0, "OlympusVault/invalid-epoch");
    require(defaultBondDiscountBps_ < BPS_DENOMINATOR, "OlympusVault/invalid-discount");

    bondLpToken = IUniV2LikePairOlympus(bondLpToken_);
    wsVEIL = wsVEIL_;
    svDAI = svDAI_;
    payoutToken = IVeilOlympusRebaseToken(payoutToken_);
    treasury = treasury_;

    vestingTerm = vestingTerm_;
    epochLength = epochLength_;
    annualProjectedGrowthBps = annualProjectedGrowthBps_;
    maxEpochRebaseBps = maxEpochRebaseBps_;
    defaultBondDiscountBps = defaultBondDiscountBps_;

    owner = msg.sender;
    lastRebaseAt = uint64(block.timestamp);
    rbsLastFloorAt = uint64(block.timestamp);

    _requireBondLpMatchesPair();
    emit OwnershipTransferred(address(0), msg.sender);
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "OlympusVault/invalid-owner");
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

  function setTreasury(address treasury_) external onlyOwner {
    require(treasury_ != address(0), "OlympusVault/invalid-treasury");
    treasury = treasury_;
    emit TreasurySet(treasury_);
  }

  function setBondTerms(uint32 vestingTerm_, uint16 defaultBondDiscountBps_) external onlyOwner {
    require(vestingTerm_ > 0, "OlympusVault/invalid-vesting");
    require(defaultBondDiscountBps_ < BPS_DENOMINATOR, "OlympusVault/invalid-discount");
    vestingTerm = vestingTerm_;
    defaultBondDiscountBps = defaultBondDiscountBps_;
    emit BondTermsSet(vestingTerm_, defaultBondDiscountBps_);
  }

  function setRebaseTerms(uint32 annualProjectedGrowthBps_, uint16 maxEpochRebaseBps_, uint32 epochLength_) external onlyOwner {
    require(epochLength_ > 0, "OlympusVault/invalid-epoch");
    annualProjectedGrowthBps = annualProjectedGrowthBps_;
    maxEpochRebaseBps = maxEpochRebaseBps_;
    epochLength = epochLength_;
    emit RebaseTermsSet(annualProjectedGrowthBps_, maxEpochRebaseBps_, epochLength_);
  }

  /// @notice Sets upward-RBS controls for the payout token liquidity pair (payout token / svDAI).
  function setRbsConfig(
    address pair,
    uint256 floorPriceE18,
    uint16 floorGrowthBpsPerEpoch,
    uint16 maxBondDiscountBps
  ) external onlyOwner {
    if (pair == address(0)) {
      rbsPair = address(0);
      rbsPayoutTokenIsToken0 = false;
      rbsFloorPriceE18 = floorPriceE18;
      rbsFloorGrowthBpsPerEpoch = floorGrowthBpsPerEpoch;
      rbsMaxBondDiscountBps = maxBondDiscountBps;
      rbsLastFloorAt = uint64(block.timestamp);
      emit RbsConfigSet(address(0), floorPriceE18, floorGrowthBpsPerEpoch, maxBondDiscountBps, false);
      return;
    }

    IUniV2LikePairOlympus pairRef = IUniV2LikePairOlympus(pair);
    address token0 = pairRef.token0();
    address token1 = pairRef.token1();
    bool payoutIs0 = token0 == address(payoutToken) && token1 == svDAI;
    bool payoutIs1 = token1 == address(payoutToken) && token0 == svDAI;
    require(payoutIs0 || payoutIs1, "OlympusVault/invalid-rbs-pair");
    require(maxBondDiscountBps < BPS_DENOMINATOR, "OlympusVault/invalid-rbs-discount");

    rbsPair = pair;
    rbsPayoutTokenIsToken0 = payoutIs0;
    rbsFloorPriceE18 = floorPriceE18;
    rbsFloorGrowthBpsPerEpoch = floorGrowthBpsPerEpoch;
    rbsMaxBondDiscountBps = maxBondDiscountBps;
    rbsLastFloorAt = uint64(block.timestamp);

    emit RbsConfigSet(pair, floorPriceE18, floorGrowthBpsPerEpoch, maxBondDiscountBps, payoutIs0);
  }

  function setRbsFloorPrice(uint256 floorPriceE18) external onlyOwner {
    require(rbsPair != address(0), "OlympusVault/rbs-disabled");
    uint256 previous = rbsFloorPriceE18;
    rbsFloorPriceE18 = floorPriceE18;
    rbsLastFloorAt = uint64(block.timestamp);
    emit RbsFloorAdvanced(previous, floorPriceE18, 0);
  }

  function projectedEpochRebaseBps() public view returns (uint256 perEpochBps) {
    if (annualProjectedGrowthBps == 0) return 0;
    perEpochBps = (uint256(annualProjectedGrowthBps) * uint256(epochLength)) / YEAR_SECONDS;
    if (perEpochBps == 0) perEpochBps = 1;
    if (maxEpochRebaseBps > 0 && perEpochBps > maxEpochRebaseBps) {
      perEpochBps = maxEpochRebaseBps;
    }
  }

  function payoutSpotPriceE18() public view returns (uint256) {
    if (rbsPair == address(0)) return PRICE_SCALE;
    (uint112 reserve0, uint112 reserve1,) = IUniV2LikePairOlympus(rbsPair).getReserves();
    uint256 payoutReserve = rbsPayoutTokenIsToken0 ? uint256(reserve0) : uint256(reserve1);
    uint256 quoteReserve = rbsPayoutTokenIsToken0 ? uint256(reserve1) : uint256(reserve0);
    if (payoutReserve == 0 || quoteReserve == 0) return 0;
    return (quoteReserve * PRICE_SCALE) / payoutReserve;
  }

  function quoteValueOfBondLp(uint256 lpAmount) public view returns (uint256 quoteValue) {
    require(lpAmount > 0, "OlympusVault/zero-lp-amount");
    uint256 totalLpSupply = bondLpToken.totalSupply();
    require(totalLpSupply > 0, "OlympusVault/empty-bond-lp");
    (uint112 reserve0, uint112 reserve1,) = bondLpToken.getReserves();
    uint256 reserveWs = bondLpToken.token0() == wsVEIL ? uint256(reserve0) : uint256(reserve1);
    uint256 reserveSv = bondLpToken.token0() == wsVEIL ? uint256(reserve1) : uint256(reserve0);
    require(reserveWs > 0 && reserveSv > 0, "OlympusVault/invalid-bond-reserves");

    uint256 lpWs = (lpAmount * reserveWs) / totalLpSupply;
    uint256 lpSv = (lpAmount * reserveSv) / totalLpSupply;
    uint256 wsPriceInSv = (reserveSv * PRICE_SCALE) / reserveWs;
    uint256 wsValueInSv = (lpWs * wsPriceInSv) / PRICE_SCALE;
    quoteValue = lpSv + wsValueInSv;
  }

  function maxBondDiscountAllowedBps() public view returns (uint16) {
    uint256 cap = defaultBondDiscountBps;
    if (rbsPair != address(0) && rbsMaxBondDiscountBps < cap) {
      cap = rbsMaxBondDiscountBps;
    }
    if (rbsPair == address(0) || rbsFloorPriceE18 == 0) {
      return _toUint16Checked(cap);
    }

    uint256 spot = payoutSpotPriceE18();
    if (spot == 0 || spot <= rbsFloorPriceE18) {
      return 0;
    }

    uint256 floorBoundCap = ((spot - rbsFloorPriceE18) * BPS_DENOMINATOR) / spot;
    if (floorBoundCap < cap) cap = floorBoundCap;
    return _toUint16Checked(cap);
  }

  function previewBondPayout(uint256 lpAmount) external view returns (uint256 payoutAmount, uint16 discountBps) {
    uint256 quoteValue = quoteValueOfBondLp(lpAmount);
    uint256 spotPrice = payoutSpotPriceE18();
    require(spotPrice > 0, "OlympusVault/invalid-payout-price");
    discountBps = maxBondDiscountAllowedBps();
    uint256 discountedPrice = (spotPrice * (BPS_DENOMINATOR - discountBps)) / BPS_DENOMINATOR;
    if (rbsFloorPriceE18 > 0 && discountedPrice < rbsFloorPriceE18) discountedPrice = rbsFloorPriceE18;
    payoutAmount = (quoteValue * PRICE_SCALE) / discountedPrice;
  }

  function rollRbsFloor() public returns (uint256 nextFloorPriceE18) {
    if (rbsPair == address(0) || epochLength == 0) {
      return rbsFloorPriceE18;
    }

    uint256 elapsed = block.timestamp - rbsLastFloorAt;
    uint256 epochs = elapsed / epochLength;
    if (epochs == 0) {
      return rbsFloorPriceE18;
    }

    uint256 previous = rbsFloorPriceE18;
    nextFloorPriceE18 = previous;

    if (nextFloorPriceE18 > 0 && rbsFloorGrowthBpsPerEpoch > 0) {
      uint256 growthBps = uint256(rbsFloorGrowthBpsPerEpoch) * epochs;
      nextFloorPriceE18 = nextFloorPriceE18 + ((nextFloorPriceE18 * growthBps) / BPS_DENOMINATOR);
    }

    uint256 spot = payoutSpotPriceE18();
    if (spot > nextFloorPriceE18) {
      // Upward-only ratchet: floor follows spot upward, never downward.
      nextFloorPriceE18 = spot;
    }

    rbsFloorPriceE18 = nextFloorPriceE18;
    rbsLastFloorAt = uint64(rbsLastFloorAt + (epochs * epochLength));
    emit RbsFloorAdvanced(previous, nextFloorPriceE18, epochs);
  }

  function depositBond(uint256 lpAmount, address receiver)
    external
    returns (uint256 payoutAmount, uint256 payoutShares, uint16 discountBps)
  {
    require(receiver != address(0), "OlympusVault/invalid-receiver");
    require(lpAmount > 0, "OlympusVault/zero-lp-amount");
    if (rbsPair != address(0)) {
      rollRbsFloor();
    }

    uint256 quoteValue = quoteValueOfBondLp(lpAmount);
    uint256 spotPrice = payoutSpotPriceE18();
    require(spotPrice > 0, "OlympusVault/invalid-payout-price");

    discountBps = maxBondDiscountAllowedBps();
    uint256 discountedPrice = (spotPrice * (BPS_DENOMINATOR - discountBps)) / BPS_DENOMINATOR;
    if (rbsFloorPriceE18 > 0 && discountedPrice < rbsFloorPriceE18) {
      discountedPrice = rbsFloorPriceE18;
    }

    payoutAmount = (quoteValue * PRICE_SCALE) / discountedPrice;
    require(payoutAmount > 0, "OlympusVault/zero-payout");

    payoutShares = payoutToken.sharesForAmount(payoutAmount);
    require(payoutShares > 0, "OlympusVault/zero-payout-shares");

    require(bondLpToken.transferFrom(msg.sender, treasury, lpAmount), "OlympusVault/lp-transfer-failed");
    payoutToken.mintShares(address(this), payoutShares);
    _mergeBond(receiver, payoutShares);

    emit BondDeposited(msg.sender, receiver, lpAmount, payoutAmount, payoutShares, discountBps);
  }

  function claim(address receiver) external returns (uint256 payoutAmount, uint256 payoutShares) {
    require(receiver != address(0), "OlympusVault/invalid-receiver");
    BondPosition storage position = bonds[msg.sender];
    payoutShares = _claimableShares(position);
    require(payoutShares > 0, "OlympusVault/nothing-claimable");

    uint256 nextClaimed = uint256(position.claimedShares) + payoutShares;
    require(nextClaimed <= type(uint128).max, "OlympusVault/claimed-overflow");
    position.claimedShares = _toUint128Checked(nextClaimed);
    payoutAmount = payoutToken.transferShares(receiver, payoutShares);

    if (position.claimedShares >= position.totalShares) {
      delete bonds[msg.sender];
    }

    emit BondClaimed(msg.sender, receiver, payoutAmount, payoutShares);
  }

  function claimable(address account) external view returns (uint256 payoutAmount, uint256 payoutShares) {
    BondPosition memory position = bonds[account];
    payoutShares = _claimableShares(position);
    payoutAmount = payoutToken.amountForShares(payoutShares);
  }

  function triggerRebase() external returns (uint256 rebaseBpsApplied, uint256 newIndex) {
    uint256 elapsed = block.timestamp - lastRebaseAt;
    require(elapsed >= epochLength, "OlympusVault/epoch-not-reached");

    uint256 epochs = elapsed / epochLength;
    uint256 perEpochBps = projectedEpochRebaseBps();
    require(perEpochBps > 0, "OlympusVault/zero-projected-growth");

    rebaseBpsApplied = perEpochBps * epochs;
    if (maxEpochRebaseBps > 0) {
      uint256 cap = uint256(maxEpochRebaseBps) * epochs;
      if (rebaseBpsApplied > cap) rebaseBpsApplied = cap;
    }
    require(rebaseBpsApplied > 0, "OlympusVault/zero-rebase");

    newIndex = payoutToken.rebase(rebaseBpsApplied);
    lastRebaseAt = uint64(lastRebaseAt + (epochs * epochLength));

    uint256 floorPrice = rbsFloorPriceE18;
    if (rbsPair != address(0)) {
      floorPrice = rollRbsFloor();
    }
    emit RebaseTriggered(msg.sender, rebaseBpsApplied, epochs, newIndex, floorPrice);
  }

  function _requireBondLpMatchesPair() internal view {
    address token0 = bondLpToken.token0();
    address token1 = bondLpToken.token1();
    bool isWsSv = token0 == wsVEIL && token1 == svDAI;
    bool isSvWs = token1 == wsVEIL && token0 == svDAI;
    require(isWsSv || isSvWs, "OlympusVault/bond-lp-must-be-ws-sv");
  }

  function _mergeBond(address receiver, uint256 newShares) internal {
    BondPosition storage position = bonds[receiver];
    uint256 remaining = uint256(position.totalShares) - uint256(position.claimedShares);
    uint256 nextTotal = remaining + newShares;
    require(nextTotal <= type(uint128).max, "OlympusVault/position-overflow");

    position.totalShares = _toUint128Checked(nextTotal);
    position.claimedShares = 0;
    position.vestStart = uint64(block.timestamp);
    position.vestEnd = uint64(block.timestamp + vestingTerm);
  }

  function _toUint16Checked(uint256 value) internal pure returns (uint16) {
    require(value <= type(uint16).max, "OlympusVault/u16-overflow");
    // forge-lint: disable-next-line(unsafe-typecast)
    return uint16(value);
  }

  function _toUint128Checked(uint256 value) internal pure returns (uint128) {
    require(value <= type(uint128).max, "OlympusVault/u128-overflow");
    // forge-lint: disable-next-line(unsafe-typecast)
    return uint128(value);
  }

  function _claimableShares(BondPosition memory position) internal view returns (uint256) {
    if (position.totalShares == 0) return 0;
    if (position.claimedShares >= position.totalShares) return 0;

    uint256 vested;
    if (block.timestamp >= position.vestEnd) {
      vested = position.totalShares;
    } else if (block.timestamp <= position.vestStart || position.vestEnd <= position.vestStart) {
      vested = 0;
    } else {
      uint256 elapsed = block.timestamp - position.vestStart;
      uint256 duration = position.vestEnd - position.vestStart;
      vested = (uint256(position.totalShares) * elapsed) / duration;
    }

    if (vested <= position.claimedShares) return 0;
    return vested - uint256(position.claimedShares);
  }
}

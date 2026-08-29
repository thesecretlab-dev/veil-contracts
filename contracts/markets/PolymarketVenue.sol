// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PolymarketVenue
/// @notice Local companion settlement for Polymarket-routed fills.
///         Live CLOB (Polygon 137) is a separate forwarder. This contract is not Polymarket mainnet.
contract PolymarketVenue {
    struct Fill {
        bytes32 conditionId;
        bytes32 tokenId;
        address trader;
        bool yes;
        uint256 usdcIn;
        uint256 sharesOut;
        uint16 feeBps;
        uint256 priceE6;
    }

    mapping(bytes32 => Fill) public fills;
    mapping(bytes32 => bool) public used;
    uint256 public count;
    address public issuer;

    event Filled(
        bytes32 indexed orderId,
        address indexed trader,
        bytes32 conditionId,
        bool yes,
        uint256 usdcIn,
        uint256 sharesOut,
        uint16 feeBps
    );

    error NotIssuer();
    error Used();
    error ZeroTrader();
    error BadFee();

    constructor() {
        issuer = msg.sender;
    }

    function fill(
        bytes32 orderId,
        bytes32 conditionId,
        bytes32 tokenId,
        address trader,
        bool yes,
        uint256 usdcIn,
        uint256 sharesOut,
        uint16 feeBps,
        uint256 priceE6
    ) external {
        if (msg.sender != issuer) revert NotIssuer();
        if (trader == address(0)) revert ZeroTrader();
        if (feeBps < 3) revert BadFee();
        if (used[orderId]) revert Used();
        used[orderId] = true;
        fills[orderId] = Fill(conditionId, tokenId, trader, yes, usdcIn, sharesOut, feeBps, priceE6);
        count += 1;
        emit Filled(orderId, trader, conditionId, yes, usdcIn, sharesOut, feeBps);
    }
}

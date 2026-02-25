// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20LikeDaiJoin {
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function decimals() external view returns (uint8);
}

interface IVatLikeDaiJoin {
  function move(address src, address dst, uint256 rad) external;
}

/// @notice Minimal stablecoin adapter inspired by Maker `DaiJoin`.
contract DaiJoin {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event Cage();
  event Join(address indexed usr, uint256 wad);
  event Exit(address indexed usr, uint256 wad);

  error DaiJoinAuth();
  error DaiJoinBounds();
  error DaiJoinTransferFailed();

  mapping(address => uint256) public wards;
  IVatLikeDaiJoin public immutable vat;
  IERC20LikeDaiJoin public immutable dai;
  uint256 public immutable one;
  uint256 public live = 1;

  modifier auth() {
    if (wards[msg.sender] != 1) revert DaiJoinAuth();
    _;
  }

  constructor(address vat_, address dai_, address owner_) {
    uint8 dec = IERC20LikeDaiJoin(dai_).decimals();
    if (dec > 27) revert DaiJoinBounds();
    wards[owner_] = 1;
    emit Rely(owner_);
    vat = IVatLikeDaiJoin(vat_);
    dai = IERC20LikeDaiJoin(dai_);
    one = 10 ** (27 - dec);
  }

  function rely(address usr) external auth {
    wards[usr] = 1;
    emit Rely(usr);
  }

  function deny(address usr) external auth {
    wards[usr] = 0;
    emit Deny(usr);
  }

  function cage() external auth {
    live = 0;
    emit Cage();
  }

  function join(address usr, uint256 wad) external {
    if (live != 1) revert DaiJoinBounds();
    if (!dai.transferFrom(msg.sender, address(this), wad)) revert DaiJoinTransferFailed();
    vat.move(address(this), usr, wad * one);
    emit Join(usr, wad);
  }

  function exit(address usr, uint256 wad) external {
    vat.move(msg.sender, address(this), wad * one);
    if (!dai.transfer(usr, wad)) revert DaiJoinTransferFailed();
    emit Exit(usr, wad);
  }
}


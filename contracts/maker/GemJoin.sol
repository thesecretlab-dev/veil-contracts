// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20LikeGemJoin {
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function decimals() external view returns (uint8);
}

interface IVatLikeGemJoin {
  function slip(bytes32 ilk, address usr, int256 wad) external;
}

/// @notice Minimal collateral adapter inspired by Maker `GemJoin`.
contract GemJoin {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event Cage();
  event Join(address indexed usr, uint256 wad);
  event Exit(address indexed usr, uint256 wad);

  error GemJoinAuth();
  error GemJoinBounds();
  error GemJoinTransferFailed();

  mapping(address => uint256) public wards;
  IVatLikeGemJoin public immutable vat;
  bytes32 public immutable ilk;
  IERC20LikeGemJoin public immutable gem;
  uint8 public immutable dec;
  uint256 public live = 1;

  modifier auth() {
    if (wards[msg.sender] != 1) revert GemJoinAuth();
    _;
  }

  constructor(address vat_, bytes32 ilk_, address gem_, address owner_) {
    wards[owner_] = 1;
    emit Rely(owner_);
    vat = IVatLikeGemJoin(vat_);
    ilk = ilk_;
    gem = IERC20LikeGemJoin(gem_);
    dec = IERC20LikeGemJoin(gem_).decimals();
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
    if (live != 1) revert GemJoinBounds();
    if (!gem.transferFrom(msg.sender, address(this), wad)) revert GemJoinTransferFailed();
    vat.slip(ilk, usr, int256(wad));
    emit Join(usr, wad);
  }

  function exit(address usr, uint256 wad) external {
    vat.slip(ilk, msg.sender, -int256(wad));
    if (!gem.transfer(usr, wad)) revert GemJoinTransferFailed();
    emit Exit(usr, wad);
  }
}


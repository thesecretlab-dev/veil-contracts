// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal companion accounting core inspired by Maker `Vat`.
/// @dev Scoped for local VEIL economic integration and audit coverage.
contract Vat {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
  event Slip(bytes32 indexed ilk, address indexed usr, int256 wad);
  event Move(address indexed src, address indexed dst, uint256 rad);
  event Suck(address indexed u, address indexed v, uint256 rad);
  event Heal(uint256 rad);

  error VatAuth();
  error VatBounds();

  mapping(address => uint256) public wards;
  mapping(bytes32 => mapping(address => uint256)) public gem;
  mapping(address => uint256) public dai;
  mapping(address => uint256) public sin;
  mapping(bytes32 => uint256) public rate;
  mapping(bytes32 => uint256) public spot;
  mapping(bytes32 => uint256) public lineByIlk;

  uint256 public Line;
  uint256 public debt;
  uint256 public live = 1;

  bytes32 private constant WHAT_LINE = keccak256("line");
  bytes32 private constant WHAT_LIVE = keccak256("live");
  bytes32 private constant WHAT_RATE = keccak256("rate");
  bytes32 private constant WHAT_SPOT = keccak256("spot");
  bytes32 private constant WHAT_ILK_LINE = keccak256("line");

  modifier auth() {
    if (wards[msg.sender] != 1) revert VatAuth();
    _;
  }

  constructor(address owner_) {
    wards[owner_] = 1;
    emit Rely(owner_);
  }

  function rely(address usr) external auth {
    wards[usr] = 1;
    emit Rely(usr);
  }

  function deny(address usr) external auth {
    wards[usr] = 0;
    emit Deny(usr);
  }

  function file(bytes32 what, uint256 data) external auth {
    if (what == WHAT_LINE) {
      Line = data;
    } else if (what == WHAT_LIVE) {
      live = data;
    } else {
      revert VatBounds();
    }
    emit File(what, data);
  }

  function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
    if (what == WHAT_RATE) {
      rate[ilk] = data;
    } else if (what == WHAT_SPOT) {
      spot[ilk] = data;
    } else if (what == WHAT_ILK_LINE) {
      lineByIlk[ilk] = data;
    } else {
      revert VatBounds();
    }
    emit File(ilk, what, data);
  }

  function slip(bytes32 ilk, address usr, int256 wad) external auth {
    if (wad >= 0) {
      gem[ilk][usr] += uint256(wad);
    } else {
      uint256 down = uint256(-wad);
      uint256 bal = gem[ilk][usr];
      if (bal < down) revert VatBounds();
      unchecked {
        gem[ilk][usr] = bal - down;
      }
    }
    emit Slip(ilk, usr, wad);
  }

  function move(address src, address dst, uint256 rad) external {
    if (msg.sender != src && wards[msg.sender] != 1) revert VatAuth();
    uint256 bal = dai[src];
    if (bal < rad) revert VatBounds();
    unchecked {
      dai[src] = bal - rad;
      dai[dst] += rad;
    }
    emit Move(src, dst, rad);
  }

  function suck(address u, address v, uint256 rad) external auth {
    unchecked {
      dai[u] += rad;
      sin[v] += rad;
      debt += rad;
    }
    emit Suck(u, v, rad);
  }

  function heal(uint256 rad) external {
    uint256 d = dai[msg.sender];
    uint256 s = sin[msg.sender];
    if (d < rad || s < rad || debt < rad) revert VatBounds();
    unchecked {
      dai[msg.sender] = d - rad;
      sin[msg.sender] = s - rad;
      debt -= rad;
    }
    emit Heal(rad);
  }
}


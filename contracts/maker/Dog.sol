// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal liquidation trigger inspired by Maker `Dog`.
contract Dog {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, address data);
  event Bark(bytes32 indexed ilk, address indexed urn, uint256 lot, uint256 tab);

  error DogAuth();
  error DogBounds();

  struct Ilk {
    address clip;
    uint256 chop;
    uint256 hole;
    uint256 dirt;
  }

  mapping(address => uint256) public wards;
  mapping(bytes32 => Ilk) public ilks;

  uint256 public Hole;
  uint256 public Dirt;
  uint256 public live = 1;

  bytes32 private constant WHAT_HOLE = keccak256("Hole");
  bytes32 private constant WHAT_LIVE = keccak256("live");
  bytes32 private constant WHAT_CLIP = keccak256("clip");
  bytes32 private constant WHAT_CHOP = keccak256("chop");
  bytes32 private constant WHAT_ILK_HOLE = keccak256("hole");

  modifier auth() {
    if (wards[msg.sender] != 1) revert DogAuth();
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
    if (what == WHAT_HOLE) {
      Hole = data;
    } else if (what == WHAT_LIVE) {
      live = data;
    } else {
      revert DogBounds();
    }
    emit File(what, data);
  }

  function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
    if (what == WHAT_CHOP) {
      ilks[ilk].chop = data;
    } else if (what == WHAT_ILK_HOLE) {
      ilks[ilk].hole = data;
    } else {
      revert DogBounds();
    }
    emit File(ilk, what, data);
  }

  function file(bytes32 ilk, bytes32 what, address data) external auth {
    if (what != WHAT_CLIP) revert DogBounds();
    ilks[ilk].clip = data;
    emit File(ilk, what, data);
  }

  function bark(bytes32 ilk, address urn, uint256 lot, uint256 tab) external auth {
    if (live == 0) revert DogBounds();
    Ilk storage i = ilks[ilk];
    uint256 next = Dirt + tab;
    if (Hole > 0 && next > Hole) revert DogBounds();
    if (i.hole > 0 && i.dirt + tab > i.hole) revert DogBounds();
    Dirt = next;
    i.dirt += tab;
    emit Bark(ilk, urn, lot, tab);
  }
}


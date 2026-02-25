// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal surplus/deficit accounting inspired by Maker `Vow`.
contract Vow {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed what, address data);
  event Fess(uint256 tab);
  event Heal(uint256 rad);
  event Kiss(uint256 rad);
  event Feed(uint256 rad);

  error VowAuth();
  error VowBounds();

  mapping(address => uint256) public wards;

  address public flap;
  address public flop;
  uint256 public Sin;
  uint256 public Joy;
  uint256 public hump;
  uint256 public live = 1;

  bytes32 private constant WHAT_HUMP = keccak256("hump");
  bytes32 private constant WHAT_LIVE = keccak256("live");
  bytes32 private constant WHAT_FLAP = keccak256("flap");
  bytes32 private constant WHAT_FLOP = keccak256("flop");

  modifier auth() {
    if (wards[msg.sender] != 1) revert VowAuth();
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
    if (what == WHAT_HUMP) {
      hump = data;
    } else if (what == WHAT_LIVE) {
      live = data;
    } else {
      revert VowBounds();
    }
    emit File(what, data);
  }

  function file(bytes32 what, address data) external auth {
    if (what == WHAT_FLAP) {
      flap = data;
    } else if (what == WHAT_FLOP) {
      flop = data;
    } else {
      revert VowBounds();
    }
    emit File(what, data);
  }

  function fess(uint256 tab) external auth {
    Sin += tab;
    emit Fess(tab);
  }

  function heal(uint256 rad) external auth {
    if (rad > Sin || rad > Joy) revert VowBounds();
    unchecked {
      Sin -= rad;
      Joy -= rad;
    }
    emit Heal(rad);
  }

  function kiss(uint256 rad) external auth {
    if (rad > Sin) revert VowBounds();
    Sin -= rad;
    emit Kiss(rad);
  }

  function feed(uint256 rad) external auth {
    Joy += rad;
    emit Feed(rad);
  }
}


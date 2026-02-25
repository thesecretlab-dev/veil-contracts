// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal collateral auction house inspired by Maker `Clip`.
contract Clip {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed what, address data);
  event Kick(uint256 indexed id, address indexed usr, uint256 lot, uint256 tab);
  event Take(uint256 indexed id, address indexed to, uint256 lot, uint256 cost);
  event Yank(uint256 indexed id);

  error ClipAuth();
  error ClipBounds();

  struct Sale {
    address usr;
    uint256 lot;
    uint256 tab;
    bool active;
  }

  mapping(address => uint256) public wards;
  mapping(uint256 => Sale) public sales;
  uint256 public kicks;

  address public vow;
  address public dog;
  address public spotter;
  uint256 public chip;
  uint256 public tip;
  uint256 public tail;
  uint256 public buf = 1e18;

  bytes32 private constant WHAT_VOW = keccak256("vow");
  bytes32 private constant WHAT_DOG = keccak256("dog");
  bytes32 private constant WHAT_SPOTTER = keccak256("spotter");
  bytes32 private constant WHAT_CHIP = keccak256("chip");
  bytes32 private constant WHAT_TIP = keccak256("tip");
  bytes32 private constant WHAT_TAIL = keccak256("tail");
  bytes32 private constant WHAT_BUF = keccak256("buf");

  modifier auth() {
    if (wards[msg.sender] != 1) revert ClipAuth();
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
    if (what == WHAT_CHIP) {
      chip = data;
    } else if (what == WHAT_TIP) {
      tip = data;
    } else if (what == WHAT_TAIL) {
      tail = data;
    } else if (what == WHAT_BUF) {
      buf = data;
    } else {
      revert ClipBounds();
    }
    emit File(what, data);
  }

  function file(bytes32 what, address data) external auth {
    if (what == WHAT_VOW) {
      vow = data;
    } else if (what == WHAT_DOG) {
      dog = data;
    } else if (what == WHAT_SPOTTER) {
      spotter = data;
    } else {
      revert ClipBounds();
    }
    emit File(what, data);
  }

  function kick(address usr, uint256 lot, uint256 tab) external auth returns (uint256 id) {
    if (lot == 0 || tab == 0) revert ClipBounds();
    unchecked {
      id = ++kicks;
    }
    sales[id] = Sale({
      usr: usr,
      lot: lot,
      tab: tab,
      active: true
    });
    emit Kick(id, usr, lot, tab);
  }

  function take(uint256 id, uint256 lot, uint256 maxPrice, address to) external returns (uint256 cost) {
    Sale storage s = sales[id];
    if (!s.active || lot == 0 || to == address(0)) revert ClipBounds();
    uint256 fill = lot > s.lot ? s.lot : lot;
    cost = (fill * maxPrice) / 1e18;
    if (cost > s.tab) {
      cost = s.tab;
    }
    unchecked {
      s.lot -= fill;
      s.tab -= cost;
    }
    if (s.lot == 0 || s.tab == 0) {
      s.active = false;
    }
    emit Take(id, to, fill, cost);
  }

  function yank(uint256 id) external auth {
    Sale storage s = sales[id];
    if (!s.active) revert ClipBounds();
    s.active = false;
    emit Yank(id);
  }
}


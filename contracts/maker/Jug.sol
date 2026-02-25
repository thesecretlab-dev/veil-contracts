// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVatJug {
  function file(bytes32 ilk, bytes32 what, uint256 data) external;
}

/// @notice Minimal stability-fee module inspired by Maker `Jug`.
contract Jug {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
  event Drip(bytes32 indexed ilk, uint256 nextRate, uint256 at);

  error JugAuth();
  error JugBounds();

  mapping(address => uint256) public wards;
  mapping(bytes32 => uint256) public duty;
  mapping(bytes32 => uint256) public rho;

  IVatJug public immutable vat;
  uint256 public base;

  bytes32 private constant WHAT_BASE = keccak256("base");
  bytes32 private constant WHAT_DUTY = keccak256("duty");
  bytes32 private constant WHAT_RHO = keccak256("rho");
  bytes32 private constant WHAT_RATE = keccak256("rate");

  modifier auth() {
    if (wards[msg.sender] != 1) revert JugAuth();
    _;
  }

  constructor(address vat_, address owner_) {
    vat = IVatJug(vat_);
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
    if (what != WHAT_BASE) revert JugBounds();
    base = data;
    emit File(what, data);
  }

  function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
    if (what == WHAT_DUTY) {
      duty[ilk] = data;
    } else if (what == WHAT_RHO) {
      rho[ilk] = data;
    } else {
      revert JugBounds();
    }
    emit File(ilk, what, data);
  }

  function drip(bytes32 ilk) external returns (uint256 nextRate) {
    uint256 prev = rho[ilk];
    if (prev == 0) prev = block.timestamp;
    if (block.timestamp < prev) revert JugBounds();
    unchecked {
      rho[ilk] = block.timestamp;
      nextRate = base + duty[ilk];
    }
    vat.file(ilk, WHAT_RATE, nextRate);
    emit Drip(ilk, nextRate, block.timestamp);
  }
}


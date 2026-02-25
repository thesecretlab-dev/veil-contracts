// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal oracle/spot module inspired by Maker `Spot`.
contract Spot {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
  event File(bytes32 indexed ilk, bytes32 indexed what, address data);
  event Poke(bytes32 indexed ilk, uint256 price);

  error SpotAuth();
  error SpotBounds();

  struct Ilk {
    address pip;
    uint256 mat;
    uint256 price;
  }

  mapping(address => uint256) public wards;
  mapping(bytes32 => Ilk) public ilks;
  uint256 public par = 1e27;

  bytes32 private constant WHAT_PAR = keccak256("par");
  bytes32 private constant WHAT_MAT = keccak256("mat");
  bytes32 private constant WHAT_PIP = keccak256("pip");

  modifier auth() {
    if (wards[msg.sender] != 1) revert SpotAuth();
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
    if (what != WHAT_PAR) revert SpotBounds();
    par = data;
    emit File(what, data);
  }

  function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
    if (what != WHAT_MAT) revert SpotBounds();
    ilks[ilk].mat = data;
    emit File(ilk, what, data);
  }

  function file(bytes32 ilk, bytes32 what, address data) external auth {
    if (what != WHAT_PIP) revert SpotBounds();
    ilks[ilk].pip = data;
    emit File(ilk, what, data);
  }

  function poke(bytes32 ilk, uint256 price) external auth {
    ilks[ilk].price = price;
    emit Poke(ilk, price);
  }
}


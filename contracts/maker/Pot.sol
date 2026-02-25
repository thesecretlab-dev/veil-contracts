// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal savings-rate module inspired by Maker `Pot`.
contract Pot {
  event Rely(address indexed usr);
  event Deny(address indexed usr);
  event File(bytes32 indexed what, uint256 data);
  event Drip(uint256 nextChi, uint256 at);
  event Join(address indexed usr, uint256 wad);
  event Exit(address indexed usr, uint256 wad);

  error PotAuth();
  error PotBounds();

  mapping(address => uint256) public wards;
  mapping(address => uint256) public pie;

  uint256 public Pie;
  uint256 public dsr = 1e27;
  uint256 public chi = 1e27;
  uint256 public rho;

  bytes32 private constant WHAT_DSR = keccak256("dsr");

  modifier auth() {
    if (wards[msg.sender] != 1) revert PotAuth();
    _;
  }

  constructor(address owner_) {
    wards[owner_] = 1;
    rho = block.timestamp;
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
    if (what != WHAT_DSR) revert PotBounds();
    dsr = data;
    emit File(what, data);
  }

  function drip() public returns (uint256 nextChi) {
    uint256 dt = block.timestamp - rho;
    if (dt > 0) {
      // Simplified accrual model for local companion usage.
      nextChi = chi + ((chi * (dsr - 1e27) * dt) / 1e27);
      chi = nextChi;
      rho = block.timestamp;
    } else {
      nextChi = chi;
    }
    emit Drip(nextChi, rho);
  }

  function join(uint256 wad) external {
    drip();
    pie[msg.sender] += wad;
    Pie += wad;
    emit Join(msg.sender, wad);
  }

  function exit(uint256 wad) external {
    uint256 p = pie[msg.sender];
    if (p < wad) revert PotBounds();
    unchecked {
      pie[msg.sender] = p - wad;
      Pie -= wad;
    }
    emit Exit(msg.sender, wad);
  }
}


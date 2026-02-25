// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20LikeTreasury {
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IVeilVAITreasury {
  function mint(address to, uint256 amount) external;
  function burnFrom(address from, uint256 amount) external;
}

/// @notice Companion EVM treasury for VEIL/wVEIL + VAI operations.
/// @dev Owner-controlled for now; designed for fast local recovery workflows.
contract VeilTreasury {
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event Keep3rSet(address indexed previousKeep3r, address indexed nextKeep3r);
  event VeilDeposited(address indexed from, uint256 amount);
  event Keep3rFunded(address indexed keep3r, uint256 amount);
  event VAIMinted(address indexed to, uint256 amount);
  event VAIBurned(address indexed from, uint256 amount);
  event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

  error TreasuryZeroAddress();
  error TreasuryOnlyOwner();
  error TreasuryKeep3rUnset();
  error TreasuryTokenTransferFailed();

  address public owner;
  address public keep3r;
  IERC20LikeTreasury public immutable VEIL;
  IVeilVAITreasury public immutable VAI;

  modifier onlyOwner() {
    if (msg.sender != owner) revert TreasuryOnlyOwner();
    _;
  }

  constructor(address veilToken_, address vaiToken_, address owner_) {
    if (veilToken_ == address(0) || vaiToken_ == address(0) || owner_ == address(0)) {
      revert TreasuryZeroAddress();
    }
    VEIL = IERC20LikeTreasury(veilToken_);
    VAI = IVeilVAITreasury(vaiToken_);
    owner = owner_;
    emit OwnershipTransferred(address(0), owner_);
  }

  function transferOwnership(address nextOwner) external onlyOwner {
    if (nextOwner == address(0)) revert TreasuryZeroAddress();
    emit OwnershipTransferred(owner, nextOwner);
    owner = nextOwner;
  }

  function setKeep3r(address nextKeep3r) external onlyOwner {
    if (nextKeep3r == address(0)) revert TreasuryZeroAddress();
    emit Keep3rSet(keep3r, nextKeep3r);
    keep3r = nextKeep3r;
  }

  function depositVeil(uint256 amount) external {
    if (!VEIL.transferFrom(msg.sender, address(this), amount)) {
      revert TreasuryTokenTransferFailed();
    }
    emit VeilDeposited(msg.sender, amount);
  }

  function fundKeep3r(uint256 amount) external onlyOwner {
    address target = keep3r;
    if (target == address(0)) revert TreasuryKeep3rUnset();
    if (!VEIL.transfer(target, amount)) revert TreasuryTokenTransferFailed();
    emit Keep3rFunded(target, amount);
  }

  function mintVAI(address to, uint256 amount) external onlyOwner {
    VAI.mint(to, amount);
    emit VAIMinted(to, amount);
  }

  function burnVAIFrom(address from, uint256 amount) external onlyOwner {
    VAI.burnFrom(from, amount);
    emit VAIBurned(from, amount);
  }

  function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
    if (token == address(0) || to == address(0)) revert TreasuryZeroAddress();
    if (!IERC20LikeTreasury(token).transfer(to, amount)) {
      revert TreasuryTokenTransferFailed();
    }
    emit TokenWithdrawn(token, to, amount);
  }
}

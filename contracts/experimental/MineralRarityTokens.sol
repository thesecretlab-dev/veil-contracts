// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVeilMinerals404 {
  struct MineralMeta {
    bytes32 inscriptionHash;
    uint8 rarity; // enum Rarity { Common, Uncommon, Rare, Epic, Legendary }
    uint64 minedAt;
  }

  function mineralMeta(uint256 tokenId) external view returns (bytes32 inscriptionHash, uint8 rarity, uint64 minedAt);
  function transferFrom(address from, address to, uint256 valueOrId) external returns (bool);
}

/// @notice Wraps VeilMinerals404 NFTs of a given rarity into a fungible ERC20 (decimals=0).
/// @dev This avoids ERC404 approve/transfer ambiguity for DeFi; pools use this wrapper token.
abstract contract MineralRarityTokenBase {
  string public name;
  string public symbol;
  uint8 public constant decimals = 0;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Deposit(address indexed caller, address indexed receiver, uint256 tokenId);
  event Redeem(address indexed caller, address indexed receiver, uint256 tokenId);

  IVeilMinerals404 public immutable minerals;
  uint8 public immutable rarity;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  uint256[] internal _vaultTokenIds;
  mapping(uint256 => uint256) internal _vaultIndex;

  constructor(address minerals_, uint8 rarity_, string memory name_, string memory symbol_) {
    require(minerals_ != address(0), "MIN/invalid-minerals");
    minerals = IVeilMinerals404(minerals_);
    rarity = rarity_;
    name = name_;
    symbol = symbol_;
  }

  function approve(address spender, uint256 value) external returns (bool) {
    allowance[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transfer(address to, uint256 value) external returns (bool) {
    return transferFrom(msg.sender, to, value);
  }

  function transferFrom(address from, address to, uint256 value) public returns (bool) {
    require(to != address(0), "MIN/invalid-recipient");

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "MIN/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    require(balanceOf[from] >= value, "MIN/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }
    emit Transfer(from, to, value);
    return true;
  }

  function vaultCount() external view returns (uint256) {
    return _vaultTokenIds.length;
  }

  function deposit(uint256 tokenId, address receiver) public returns (uint256 shares) {
    require(receiver != address(0), "MIN/invalid-receiver");

    (, uint8 r, ) = minerals.mineralMeta(tokenId);
    require(r == rarity, "MIN/wrong-rarity");

    // This is an ERC721-path transfer (tokenId exists); depositor must approve this wrapper.
    require(minerals.transferFrom(msg.sender, address(this), tokenId), "MIN/transfer-in-failed");
    _pushVault(tokenId);

    shares = 1;
    totalSupply += shares;
    unchecked {
      balanceOf[receiver] += shares;
    }
    emit Transfer(address(0), receiver, shares);
    emit Deposit(msg.sender, receiver, tokenId);
  }

  function depositBatch(uint256[] calldata tokenIds, address receiver) external returns (uint256 shares) {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      deposit(tokenIds[i], receiver);
      shares += 1;
    }
  }

  function redeem(uint256 shares, address receiver) external returns (uint256[] memory tokenIds) {
    require(receiver != address(0), "MIN/invalid-receiver");
    require(shares > 0, "MIN/zero-shares");
    require(balanceOf[msg.sender] >= shares, "MIN/insufficient-balance");
    require(_vaultTokenIds.length >= shares, "MIN/insufficient-vault");

    unchecked {
      balanceOf[msg.sender] -= shares;
      totalSupply -= shares;
    }
    emit Transfer(msg.sender, address(0), shares);

    tokenIds = new uint256[](shares);
    for (uint256 i = 0; i < shares; i++) {
      uint256 tokenId = _popVault();
      tokenIds[i] = tokenId;
      require(minerals.transferFrom(address(this), receiver, tokenId), "MIN/transfer-out-failed");
      emit Redeem(msg.sender, receiver, tokenId);
    }
  }

  function _pushVault(uint256 tokenId) internal {
    _vaultIndex[tokenId] = _vaultTokenIds.length;
    _vaultTokenIds.push(tokenId);
  }

  function _popVault() internal returns (uint256 tokenId) {
    uint256 last = _vaultTokenIds.length - 1;
    tokenId = _vaultTokenIds[last];
    _vaultTokenIds.pop();
    delete _vaultIndex[tokenId];
  }
}

contract IronMIN is MineralRarityTokenBase {
  constructor(address minerals_) MineralRarityTokenBase(minerals_, 0, "Iron Minerals", "iMIN") {}
}

contract CopperMIN is MineralRarityTokenBase {
  constructor(address minerals_) MineralRarityTokenBase(minerals_, 1, "Copper Minerals", "cMIN") {}
}

contract SilverMIN is MineralRarityTokenBase {
  constructor(address minerals_) MineralRarityTokenBase(minerals_, 2, "Silver Minerals", "sMIN") {}
}

contract GoldMIN is MineralRarityTokenBase {
  constructor(address minerals_) MineralRarityTokenBase(minerals_, 3, "Gold Minerals", "gMIN") {}
}

contract DiamondMIN is MineralRarityTokenBase {
  constructor(address minerals_) MineralRarityTokenBase(minerals_, 4, "Diamond Minerals", "dMIN") {}
}

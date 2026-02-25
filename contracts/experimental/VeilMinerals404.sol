// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC404-style hybrid token for "mined" minerals + inscriptions.
///
/// This is intentionally a minimal, self-contained implementation meant for L1 demos.
/// It combines:
/// - ERC20-like balances/allowances (1 unit == 1 mineral)
/// - ERC721-like ownership/approvals (each unit is represented by a unique tokenId)
///
/// Important:
/// - This is NOT an official ERC standard.
/// - ERC20 and ERC721 share function signatures (approve/transferFrom/Transfer/Approval),
///   so this contract uses the common ERC404 pattern:
///   - approve(spender, valueOrId): if valueOrId is an existing tokenId -> NFT approval; else ERC20 allowance
///   - transferFrom(from, to, valueOrId): if valueOrId is an owned tokenId -> NFT transfer (and 1 unit);
///     else ERC20 transfer of "amount" units (and moves that many NFTs)
///
/// Gas notes:
/// - ERC20 transfers of large amounts loop over NFTs and will be expensive.
contract VeilMinerals404 {
  // --- ERC metadata ---
  string public name;
  string public symbol;
  uint8 public constant decimals = 0;

  // --- Supply ---
  uint256 public totalSupply;
  uint256 public totalMinted;

  // --- ERC20 balances/allowances ---
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  // --- ERC721 ownership ---
  mapping(uint256 => address) public ownerOf;
  mapping(address => uint256) public erc721BalanceOf;
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  // Owned token enumeration (swap-and-pop).
  mapping(address => uint256[]) internal _ownedTokens;
  mapping(uint256 => uint256) internal _ownedIndex;

  // --- Inscriptions / minerals ---
  enum Rarity {
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary
  }

  struct MineralMeta {
    bytes32 inscriptionHash;
    Rarity rarity;
    uint64 minedAt;
  }

  mapping(uint256 => MineralMeta) public mineralMeta;
  mapping(bytes32 => bool) public inscriptionClaimed;

  // --- Mining difficulty ---
  // Require digest to have N trailing zero bits: digest & ((1<<difficultyBits)-1) == 0
  uint8 public difficultyBits;
  address public owner;

  // --- Mining fee (paid in native VEIL) ---
  // Kept as (token, treasury, fee) for config compatibility, but token is enforced to be address(0).
  address public wveil;
  address public feeTreasury;
  uint256 public mineFee;

  // Dynamic fee (optional): fee tracks activity via EIP-1559 basefee.
  // currentMineFee() = clamp(minMineFee + block.basefee * baseFeeMultiplierBps / 10_000, minMineFee, maxMineFee)
  bool public dynamicFeeEnabled;
  uint256 public minMineFee;
  uint256 public maxMineFee;
  uint32 public baseFeeMultiplierBps; // basis points multiplier over block.basefee

  // Cap calldata bloat (hash-only inscriptions).
  uint256 public maxInscriptionBytes = 512;

  // --- Events ---
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

  event MineFeePaid(address indexed miner, address indexed token, address indexed treasury, uint256 amount);

  event InscriptionMined(
    address indexed miner,
    uint256 indexed tokenId,
    bytes32 indexed inscriptionHash,
    Rarity rarity,
    bytes32 digest,
    uint256 seedBlock
  );

  error NotOwner();
  error InvalidRecipient();
  error NotAuthorized();
  error NotFound();
  error InvalidProof();
  error InvalidFee();
  error InscriptionAlreadyClaimed();
  error BlockhashUnavailable();
  error InscriptionTooLarge();
  error FeeConfigMissing();

  modifier onlyOwner() {
    if (msg.sender != owner) revert NotOwner();
    _;
  }

  constructor(string memory _name, string memory _symbol, uint8 _difficultyBits) {
    name = _name;
    symbol = _symbol;
    difficultyBits = _difficultyBits;
    owner = msg.sender;
  }

  // --- Admin ---

  function setDifficultyBits(uint8 bits) external onlyOwner {
    // Keep it sane: shifting by >=256 is invalid.
    if (bits > 240) bits = 240;
    difficultyBits = bits;
  }

  function setMiningFeeConfig(address token, address treasury, uint256 fee) external onlyOwner {
    // "Native-only" mining: the fee must be paid in `msg.value` (not an ERC20).
    // Keeping the (token, treasury, fee) signature avoids breaking tooling, but `token` must be 0.
    require(token == address(0), "VeilMinerals404/native-only");
    wveil = address(0);
    feeTreasury = treasury;
    mineFee = fee;
    dynamicFeeEnabled = false;
  }

  function setDynamicMiningFeeConfig(address treasury, uint256 minFeeWei, uint256 maxFeeWei, uint32 baseFeeMultBps)
    external
    onlyOwner
  {
    require(treasury != address(0), "VeilMinerals404/invalid-treasury");
    require(maxFeeWei >= minFeeWei, "VeilMinerals404/bad-fee-range");
    require(baseFeeMultBps <= 1_000_000, "VeilMinerals404/mult-too-high"); // <= 100x basefee

    wveil = address(0);
    feeTreasury = treasury;
    mineFee = 0; // unused when dynamic is enabled

    dynamicFeeEnabled = true;
    minMineFee = minFeeWei;
    maxMineFee = maxFeeWei;
    baseFeeMultiplierBps = baseFeeMultBps;
  }

  function disableDynamicMiningFee(uint256 staticFeeWei) external onlyOwner {
    dynamicFeeEnabled = false;
    mineFee = staticFeeWei;
  }

  function currentMineFee() public view returns (uint256) {
    if (!dynamicFeeEnabled) return mineFee;

    uint256 fee = minMineFee + (uint256(block.basefee) * uint256(baseFeeMultiplierBps)) / 10_000;
    if (fee < minMineFee) fee = minMineFee;
    if (fee > maxMineFee) fee = maxMineFee;
    return fee;
  }

  function setMaxInscriptionBytes(uint256 nextMax) external onlyOwner {
    // Safety ceiling; keeps view/indexer predictable.
    if (nextMax > 8192) nextMax = 8192;
    maxInscriptionBytes = nextMax;
  }

  function transferOwnership(address nextOwner) external onlyOwner {
    if (nextOwner == address(0)) revert InvalidRecipient();
    owner = nextOwner;
  }

  // --- ERC20-like ---

  function transfer(address to, uint256 amount) external returns (bool) {
    transferFrom(msg.sender, to, amount);
    return true;
  }

  // --- ERC721-like ---

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
    emit ApprovalForAll(msg.sender, operator, approved);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    transferFrom(from, to, tokenId);
    // For demo simplicity we do not implement ERC721Receiver checks.
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
    transferFrom(from, to, tokenId);
  }

  // --- ERC404-style unified approve/transferFrom ---

  function approve(address spender, uint256 valueOrId) external returns (bool) {
    // If valueOrId is an existing tokenId, treat as ERC721 approval.
    address tokenOwner = ownerOf[valueOrId];
    if (tokenOwner != address(0)) {
      if (msg.sender != tokenOwner && !isApprovedForAll[tokenOwner][msg.sender]) {
        revert NotAuthorized();
      }
      getApproved[valueOrId] = spender;
      emit Approval(tokenOwner, spender, valueOrId);
      return true;
    }

    // Otherwise treat as ERC20 allowance.
    allowance[msg.sender][spender] = valueOrId;
    emit Approval(msg.sender, spender, valueOrId);
    return true;
  }

  function transferFrom(address from, address to, uint256 valueOrId) public returns (bool) {
    if (to == address(0)) revert InvalidRecipient();

    // ERC721 path if valueOrId is an existing tokenId owned by `from`.
    if (ownerOf[valueOrId] == from && valueOrId != 0) {
      if (!_isApprovedOrOwner(from, msg.sender, valueOrId)) revert NotAuthorized();
      _transferOne(from, to, valueOrId);
      return true;
    }

    // ERC20 path: valueOrId is amount.
    uint256 amount = valueOrId;
    if (amount == 0) {
      emit Transfer(from, to, 0);
      return true;
    }

    if (msg.sender != from) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        if (allowed < amount) revert NotAuthorized();
        unchecked {
          allowance[from][msg.sender] = allowed - amount;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    _transferFungible(from, to, amount);
    return true;
  }

  // --- Mining / inscriptions ---

  /// @notice Attempt to mine a new mineral + inscription.
  /// @dev `seedBlock` must be within the last 256 blocks, otherwise blockhash is unavailable.
  function mine(bytes calldata inscriptionData, uint256 seedBlock, uint256 nonce) external payable returns (uint256 tokenId) {
    if (inscriptionData.length > maxInscriptionBytes) revert InscriptionTooLarge();
    if (seedBlock >= block.number) revert InvalidProof();
    if (block.number - seedBlock > 256) revert BlockhashUnavailable();

    bytes32 bh = blockhash(seedBlock);
    if (bh == bytes32(0)) revert BlockhashUnavailable();

    bytes32 inscriptionHash = keccak256(inscriptionData);
    if (inscriptionClaimed[inscriptionHash]) revert InscriptionAlreadyClaimed();

    uint256 fee = currentMineFee();
    if (fee > 0) {
      if (feeTreasury == address(0)) revert FeeConfigMissing();
      if (msg.value != fee) revert InvalidFee();

      (bool ok, ) = feeTreasury.call{ value: msg.value }("");
      require(ok, "VeilMinerals404/fee-native-transfer-failed");
      emit MineFeePaid(msg.sender, address(0), feeTreasury, fee);
    } else {
      if (msg.value != 0) revert InvalidFee();
    }

    bytes32 digest = keccak256(abi.encodePacked(bh, msg.sender, inscriptionHash, nonce));
    if (!_meetsDifficulty(digest)) revert InvalidProof();

    inscriptionClaimed[inscriptionHash] = true;

    // Rarity is derived from "extra" trailing zeros beyond difficultyBits.
    Rarity rarity = _rarityFromDigest(digest);

    tokenId = ++totalMinted;
    totalSupply += 1;

    balanceOf[msg.sender] += 1;
    erc721BalanceOf[msg.sender] += 1;
    ownerOf[tokenId] = msg.sender;
    _pushOwned(msg.sender, tokenId);

    mineralMeta[tokenId] = MineralMeta({
      inscriptionHash: inscriptionHash,
      rarity: rarity,
      minedAt: uint64(block.timestamp)
    });

    emit Transfer(address(0), msg.sender, 1);
    emit InscriptionMined(msg.sender, tokenId, inscriptionHash, rarity, digest, seedBlock);
  }

  /// @notice Burn a mineral for crafting (burns both the NFT and 1 fungible unit).
  function burn(uint256 tokenId) public {
    address tokenOwner = ownerOf[tokenId];
    if (tokenOwner == address(0)) revert NotFound();
    if (msg.sender != tokenOwner && !isApprovedForAll[tokenOwner][msg.sender] && getApproved[tokenId] != msg.sender) {
      revert NotAuthorized();
    }

    _burnOne(tokenOwner, tokenId);
  }

  function burnBatch(uint256[] calldata tokenIds) external {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      burn(tokenIds[i]);
    }
  }

  // --- Views ---

  function ownedTokens(address account) external view returns (uint256[] memory) {
    return _ownedTokens[account];
  }

  /// @notice Deterministic "random art" seed derived only from the inscription hash.
  /// @dev This supports "hash-only inscriptions": the bytes aren't stored, but can be rendered off-chain.
  function artSeed(uint256 tokenId) external view returns (bytes32) {
    if (ownerOf[tokenId] == address(0)) revert NotFound();
    return keccak256(abi.encodePacked(mineralMeta[tokenId].inscriptionHash, tokenId));
  }

  /// @notice Convenience: returns 4 packed RGB colors derived from `artSeed`.
  /// @dev UI/indexers can map these into SVG or pixel-art.
  function artPalette(uint256 tokenId) external view returns (uint32[4] memory palette) {
    bytes32 seed = this.artSeed(tokenId);
    uint256 x = uint256(seed);

    // 4 x 24-bit colors packed into uint32s: 0xRRGGBB
    palette[0] = uint32((x >> 0) & 0xFFFFFF);
    palette[1] = uint32((x >> 24) & 0xFFFFFF);
    palette[2] = uint32((x >> 48) & 0xFFFFFF);
    palette[3] = uint32((x >> 72) & 0xFFFFFF);
  }

  function mineralName(uint256 tokenId) external view returns (string memory) {
    MineralMeta memory meta = mineralMeta[tokenId];
    if (ownerOf[tokenId] == address(0)) revert NotFound();

    if (meta.rarity == Rarity.Common) return "Iron";
    if (meta.rarity == Rarity.Uncommon) return "Copper";
    if (meta.rarity == Rarity.Rare) return "Silver";
    if (meta.rarity == Rarity.Epic) return "Gold";
    return "Diamond";
  }

  // --- Internals ---

  function _meetsDifficulty(bytes32 digest) internal view returns (bool) {
    uint8 bits = difficultyBits;
    if (bits == 0) return true;

    uint256 mask = (uint256(1) << bits) - 1;
    return (uint256(digest) & mask) == 0;
  }

  function _rarityFromDigest(bytes32 digest) internal view returns (Rarity) {
    // Count trailing zero bits; rarer if you found more zeros than required.
    uint256 x = uint256(digest);
    uint256 tz = 0;
    while (tz < 255 && (x & 1) == 0) {
      tz++;
      x >>= 1;
    }

    uint256 extra = tz > difficultyBits ? (tz - difficultyBits) : 0;

    if (extra >= 20) return Rarity.Legendary;
    if (extra >= 12) return Rarity.Epic;
    if (extra >= 7) return Rarity.Rare;
    if (extra >= 3) return Rarity.Uncommon;
    return Rarity.Common;
  }

  function _isApprovedOrOwner(address from, address spender, uint256 tokenId) internal view returns (bool) {
    return (spender == from ||
      spender == getApproved[tokenId] ||
      isApprovedForAll[from][spender]);
  }

  function _transferFungible(address from, address to, uint256 amount) internal {
    if (balanceOf[from] < amount) revert NotAuthorized();

    unchecked {
      balanceOf[from] -= amount;
      balanceOf[to] += amount;
    }

    // Move that many NFTs 1:1 (decimals=0).
    // We move "most recently received" tokenIds first (swap-and-pop).
    for (uint256 i = 0; i < amount; i++) {
      uint256 tokenId = _popOwned(from);
      _transferNftOnly(from, to, tokenId);
    }

    emit Transfer(from, to, amount);
  }

  function _transferOne(address from, address to, uint256 tokenId) internal {
    // Move the NFT.
    _transferNftOnly(from, to, tokenId);

    // Mirror it in the ERC20 balance (1 unit).
    if (balanceOf[from] < 1) revert NotAuthorized();
    unchecked {
      balanceOf[from] -= 1;
      balanceOf[to] += 1;
    }

    emit Transfer(from, to, 1);
  }

  function _transferNftOnly(address from, address to, uint256 tokenId) internal {
    if (ownerOf[tokenId] != from) revert NotAuthorized();

    // Clear approvals
    if (getApproved[tokenId] != address(0)) {
      getApproved[tokenId] = address(0);
      emit Approval(from, address(0), tokenId);
    }

    // Update ownership + balances
    ownerOf[tokenId] = to;
    unchecked {
      erc721BalanceOf[from] -= 1;
      erc721BalanceOf[to] += 1;
    }

    _removeOwned(from, tokenId);
    _pushOwned(to, tokenId);
  }

  function _burnOne(address tokenOwner, uint256 tokenId) internal {
    // Clear approvals
    if (getApproved[tokenId] != address(0)) {
      getApproved[tokenId] = address(0);
      emit Approval(tokenOwner, address(0), tokenId);
    }

    ownerOf[tokenId] = address(0);
    delete mineralMeta[tokenId];

    unchecked {
      erc721BalanceOf[tokenOwner] -= 1;
      balanceOf[tokenOwner] -= 1;
      totalSupply -= 1;
    }

    _removeOwned(tokenOwner, tokenId);

    emit Transfer(tokenOwner, address(0), 1);
  }

  function _pushOwned(address account, uint256 tokenId) internal {
    _ownedIndex[tokenId] = _ownedTokens[account].length;
    _ownedTokens[account].push(tokenId);
  }

  function _popOwned(address account) internal returns (uint256 tokenId) {
    uint256 len = _ownedTokens[account].length;
    if (len == 0) revert NotAuthorized();

    uint256 index = len - 1;
    tokenId = _ownedTokens[account][index];
    _ownedTokens[account].pop();
    delete _ownedIndex[tokenId];
  }

  function _removeOwned(address account, uint256 tokenId) internal {
    uint256 index = _ownedIndex[tokenId];
    uint256 lastIndex = _ownedTokens[account].length - 1;

    if (index != lastIndex) {
      uint256 lastTokenId = _ownedTokens[account][lastIndex];
      _ownedTokens[account][index] = lastTokenId;
      _ownedIndex[lastTokenId] = index;
    }

    _ownedTokens[account].pop();
    delete _ownedIndex[tokenId];
  }
}

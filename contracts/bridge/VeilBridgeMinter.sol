// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title VeilBridgeMinter — Production bridge minter for VEIL <-> EVM cross-chain
/// @notice Handles lock/mint and burn/release of WVEIL via Teleporter (AWM) messages.
///
/// Flow:
///   Lock on VeilVM → Teleporter message → mintWVEIL() on companion EVM
///   burnWVEIL() on companion EVM → Teleporter message → Release on VeilVM
///
/// Security:
///   - Only authorized relayers can mint (via Teleporter callback or direct relay)
///   - NativeMinter precompile integration for WVEIL issuance
///   - Pause mechanism for emergency stops
///   - Rate limiting: per-epoch mint cap prevents catastrophic bridge exploits
///   - Ownership transferable to multisig/HSM

interface IERC20Bridge {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface ITeleporterMessenger {
    function sendCrossChainMessage(
        TeleporterMessageInput calldata messageInput
    ) external returns (bytes32 messageID);
}

struct TeleporterMessageInput {
    bytes32 destinationBlockchainID;
    address destinationAddress;
    TeleporterFeeInfo feeInfo;
    uint256 requiredGasLimit;
    address[] allowedRelayerAddresses;
    bytes message;
}

struct TeleporterFeeInfo {
    address feeTokenAddress;
    uint256 amount;
}

contract VeilBridgeMinter {
    // ═══════════════════════════════ ERRORS ═══════════════════════════════

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error Paused();
    error MintCapExceeded(uint256 requested, uint256 remaining);
    error BurnExceedsBalance(uint256 requested, uint256 balance);
    error CooldownActive(uint256 availableAt);
    error InvalidSourceChain(bytes32 received);
    error NonceAlreadyUsed(uint256 nonce);

    // ═══════════════════════════════ EVENTS ════════════════════════════════

    event OwnershipTransferred(address indexed prev, address indexed next);
    event RelayerSet(address indexed relayer, bool authorized);
    event BridgePaused(address indexed by);
    event BridgeUnpaused(address indexed by);
    event MintCapUpdated(uint256 newCapPerEpoch, uint256 newEpochDuration);
    event BridgeMinted(
        address indexed to,
        uint256 amount,
        bytes32 indexed sourceChainId,
        uint256 indexed nonce
    );
    event BridgeBurned(
        address indexed from,
        uint256 amount,
        bytes32 indexed destChainId,
        bytes32 indexed messageId
    );
    event TeleporterUpdated(address indexed prev, address indexed next);
    event SourceChainSet(bytes32 indexed chainId, address indexed sourceContract);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    // ═══════════════════════════════ STATE ═════════════════════════════════

    address public owner;
    IERC20Bridge public immutable wveil;
    ITeleporterMessenger public teleporter;

    // Relayer authorization
    mapping(address => bool) public authorizedRelayers;
    uint256 public relayerCount;

    // Pause
    bool public paused;

    // Rate limiting
    uint256 public mintCapPerEpoch;     // Max WVEIL mintable per epoch
    uint256 public epochDuration;       // Epoch length in seconds
    uint256 public currentEpochStart;
    uint256 public currentEpochMinted;

    // Replay protection
    mapping(uint256 => bool) public usedNonces;
    uint256 public totalMinted;
    uint256 public totalBurned;

    // Source chain validation
    mapping(bytes32 => address) public sourceContracts; // chainId -> expected source contract
    bytes32 public veilChainId; // VeilVM blockchain ID

    // Burn cooldown (per-user)
    uint256 public burnCooldown; // seconds between burns per user
    mapping(address => uint256) public lastBurnAt;

    // ═══════════════════════════════ MODIFIERS ═════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyRelayer() {
        if (!authorizedRelayers[msg.sender]) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    // ═══════════════════════════════ CONSTRUCTOR ═══════════════════════════

    constructor(
        address wveil_,
        address teleporter_,
        address owner_,
        bytes32 veilChainId_,
        uint256 mintCapPerEpoch_,
        uint256 epochDuration_
    ) {
        if (wveil_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        wveil = IERC20Bridge(wveil_);
        teleporter = ITeleporterMessenger(teleporter_);
        owner = owner_;
        veilChainId = veilChainId_;
        mintCapPerEpoch = mintCapPerEpoch_;
        epochDuration = epochDuration_ > 0 ? epochDuration_ : 1 hours;
        currentEpochStart = block.timestamp;
        burnCooldown = 0; // no cooldown by default
        emit OwnershipTransferred(address(0), owner_);
    }

    // ═══════════════════════════════ BRIDGE: MINT (VeilVM → EVM) ══════════

    /// @notice Mint WVEIL on companion EVM after verified lock on VeilVM.
    ///         Called by authorized relayer after validating Teleporter/AWM message.
    /// @param to Recipient on EVM
    /// @param amount Amount of WVEIL to mint (1:1 with locked VEIL)
    /// @param sourceChainId The VeilVM chain ID the lock originated from
    /// @param nonce Unique nonce for replay protection
    function mintWVEIL(
        address to,
        uint256 amount,
        bytes32 sourceChainId,
        uint256 nonce
    ) external onlyRelayer whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (sourceChainId != veilChainId) revert InvalidSourceChain(sourceChainId);
        if (usedNonces[nonce]) revert NonceAlreadyUsed(nonce);

        // Rate limit check
        _checkAndUpdateMintCap(amount);

        // Mark nonce used
        usedNonces[nonce] = true;
        totalMinted += amount;

        // Mint via WVEIL token (must have minter role)
        wveil.mint(to, amount);

        emit BridgeMinted(to, amount, sourceChainId, nonce);
    }

    // ═══════════════════════════════ BRIDGE: BURN (EVM → VeilVM) ══════════

    /// @notice Burn WVEIL to initiate release of native VEIL on VeilVM.
    ///         User must have approved this contract for the burn amount.
    ///         Sends a Teleporter message to VeilVM to release locked VEIL.
    /// @param amount Amount of WVEIL to burn
    /// @param veilRecipient Recipient address on VeilVM (encoded as bytes for flexibility)
    /// @param requiredGasLimit Gas limit for the destination chain execution
    function burnWVEIL(
        uint256 amount,
        bytes calldata veilRecipient,
        uint256 requiredGasLimit
    ) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        // Cooldown check
        if (burnCooldown > 0) {
            uint256 nextAllowed = lastBurnAt[msg.sender] + burnCooldown;
            if (block.timestamp < nextAllowed) revert CooldownActive(nextAllowed);
        }

        // Check user balance
        uint256 bal = wveil.balanceOf(msg.sender);
        if (bal < amount) revert BurnExceedsBalance(amount, bal);

        // Burn WVEIL
        wveil.burnFrom(msg.sender, amount);
        totalBurned += amount;
        lastBurnAt[msg.sender] = block.timestamp;

        // Send Teleporter message to VeilVM to release native VEIL
        bytes memory message = abi.encode(
            msg.sender,       // original burner (for audit trail)
            veilRecipient,    // recipient on VeilVM
            amount            // amount to release
        );

        TeleporterMessageInput memory input = TeleporterMessageInput({
            destinationBlockchainID: veilChainId,
            destinationAddress: sourceContracts[veilChainId],
            feeInfo: TeleporterFeeInfo({
                feeTokenAddress: address(0),
                amount: 0
            }),
            requiredGasLimit: requiredGasLimit,
            allowedRelayerAddresses: new address[](0), // any relayer can deliver
            message: message
        });

        bytes32 messageId = teleporter.sendCrossChainMessage(input);

        emit BridgeBurned(msg.sender, amount, veilChainId, messageId);
    }

    // ═══════════════════════════════ ADMIN ═════════════════════════════════

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRelayer(address relayer, bool authorized) external onlyOwner {
        if (relayer == address(0)) revert ZeroAddress();
        if (authorizedRelayers[relayer] != authorized) {
            authorizedRelayers[relayer] = authorized;
            if (authorized) relayerCount++;
            else relayerCount--;
            emit RelayerSet(relayer, authorized);
        }
    }

    function setTeleporter(address newTeleporter) external onlyOwner {
        emit TeleporterUpdated(address(teleporter), newTeleporter);
        teleporter = ITeleporterMessenger(newTeleporter);
    }

    function setSourceChain(bytes32 chainId, address sourceContract) external onlyOwner {
        sourceContracts[chainId] = sourceContract;
        emit SourceChainSet(chainId, sourceContract);
    }

    function setVeilChainId(bytes32 newChainId) external onlyOwner {
        veilChainId = newChainId;
    }

    function setMintCap(uint256 newCap, uint256 newEpochDuration) external onlyOwner {
        mintCapPerEpoch = newCap;
        if (newEpochDuration > 0) epochDuration = newEpochDuration;
        // Reset epoch on cap change
        currentEpochStart = block.timestamp;
        currentEpochMinted = 0;
        emit MintCapUpdated(newCap, epochDuration);
    }

    function setBurnCooldown(uint256 cooldownSeconds) external onlyOwner {
        burnCooldown = cooldownSeconds;
    }

    function pause() external onlyOwner {
        paused = true;
        emit BridgePaused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit BridgeUnpaused(msg.sender);
    }

    /// @notice Emergency token recovery (for stuck tokens, not WVEIL in normal operation)
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        IERC20Bridge(token).mint(to, 0); // existence check (will revert if no code)
        // Use low-level call for maximum compatibility
        (bool ok, ) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok, "transfer failed");
        emit EmergencyWithdraw(token, to, amount);
    }

    // ═══════════════════════════════ VIEW ══════════════════════════════════

    function remainingMintThisEpoch() external view returns (uint256) {
        if (block.timestamp >= currentEpochStart + epochDuration) {
            return mintCapPerEpoch; // new epoch, full cap available
        }
        if (currentEpochMinted >= mintCapPerEpoch) return 0;
        return mintCapPerEpoch - currentEpochMinted;
    }

    function currentEpochInfo() external view returns (
        uint256 epochStart,
        uint256 epochEnd,
        uint256 minted,
        uint256 cap
    ) {
        return (currentEpochStart, currentEpochStart + epochDuration, currentEpochMinted, mintCapPerEpoch);
    }

    function bridgeStats() external view returns (
        uint256 minted,
        uint256 burned,
        uint256 netOutstanding
    ) {
        return (totalMinted, totalBurned, totalMinted - totalBurned);
    }

    // ═══════════════════════════════ INTERNAL ══════════════════════════════

    function _checkAndUpdateMintCap(uint256 amount) internal {
        // Roll epoch if needed
        if (block.timestamp >= currentEpochStart + epochDuration) {
            currentEpochStart = block.timestamp;
            currentEpochMinted = 0;
        }

        uint256 remaining = mintCapPerEpoch - currentEpochMinted;
        if (amount > remaining) revert MintCapExceeded(amount, remaining);

        currentEpochMinted += amount;
    }
}

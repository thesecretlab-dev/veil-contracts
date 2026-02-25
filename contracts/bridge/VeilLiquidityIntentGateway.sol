// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice EVM-side opaque intent gateway for VEIL UniV2 liquidity actions.
/// Relayers consume submitted commitments and execute decrypted envelopes on VeilVM.
contract VeilLiquidityIntentGateway {
    enum IntentState {
        NONE,
        SUBMITTED,
        EXECUTED,
        CANCELLED
    }

    struct LiquidityIntent {
        address trader;
        bytes32 commitment;
        bytes32 nullifier;
        bytes32 envelopeHash;
        uint64 nonce;
        IntentState state;
    }

    error Unauthorized();
    error InvalidAddress();
    error InvalidCommitment();
    error InvalidNullifier();
    error NullifierAlreadyUsed(bytes32 nullifier);
    error IntentAlreadyExists(bytes32 intentId);
    error IntentNotFound(bytes32 intentId);
    error IntentNotSubmitted(bytes32 intentId);
    error IntentNotOwned(bytes32 intentId, address expectedOwner, address sender);

    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);
    event RelayExecutorSet(address indexed previousRelay, address indexed newRelay);
    event LiquidityIntentSubmitted(
        bytes32 indexed intentId,
        bytes32 indexed commitment,
        bytes32 indexed nullifier,
        bytes32 envelopeHash,
        uint64 nonce
    );
    event LiquidityIntentExecuted(bytes32 indexed intentId, bytes32 indexed veilTxHash, address indexed executor);
    event LiquidityIntentCancelled(bytes32 indexed intentId, bytes32 indexed nullifier);

    address public owner;
    address public relayExecutor;

    mapping(address => uint64) public nonces;
    mapping(bytes32 => bool) public usedNullifiers;
    mapping(bytes32 => LiquidityIntent) private intents;

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyRelay() {
        if (msg.sender != relayExecutor) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address initialOwner, address initialRelayExecutor) {
        owner = initialOwner == address(0) ? msg.sender : initialOwner;
        relayExecutor = initialRelayExecutor;
        emit OwnerTransferred(address(0), owner);
        emit RelayExecutorSet(address(0), initialRelayExecutor);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRelayExecutor(address newRelayExecutor) external onlyOwner {
        emit RelayExecutorSet(relayExecutor, newRelayExecutor);
        relayExecutor = newRelayExecutor;
    }

    /// @notice Commit-only submit path: no envelope bytes are sent on-chain.
    /// The relayer must source the opaque envelope off-chain and enforce
    /// sha256(envelope) == commitment before forwarding to VEIL.
    function submitIntent(bytes32 commitment, bytes32 nullifier) external returns (bytes32 intentId) {
        if (commitment == bytes32(0)) {
            revert InvalidCommitment();
        }
        if (nullifier == bytes32(0)) {
            revert InvalidNullifier();
        }
        if (usedNullifiers[nullifier]) {
            revert NullifierAlreadyUsed(nullifier);
        }

        bytes32 envelopeHash = commitment;

        uint64 nonce = nonces[msg.sender];
        nonces[msg.sender] = nonce + 1;

        intentId = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                msg.sender,
                commitment,
                nullifier,
                envelopeHash,
                nonce
            )
        );

        if (intents[intentId].state != IntentState.NONE) {
            revert IntentAlreadyExists(intentId);
        }

        intents[intentId] = LiquidityIntent({
            trader: msg.sender,
            commitment: commitment,
            nullifier: nullifier,
            envelopeHash: envelopeHash,
            nonce: nonce,
            state: IntentState.SUBMITTED
        });
        usedNullifiers[nullifier] = true;

        emit LiquidityIntentSubmitted(intentId, commitment, nullifier, envelopeHash, nonce);
    }

    function markIntentExecuted(bytes32 intentId, bytes32 veilTxHash) external onlyRelay {
        LiquidityIntent storage intent = intents[intentId];
        if (intent.state == IntentState.NONE) {
            revert IntentNotFound(intentId);
        }
        if (intent.state != IntentState.SUBMITTED) {
            revert IntentNotSubmitted(intentId);
        }
        intent.state = IntentState.EXECUTED;
        emit LiquidityIntentExecuted(intentId, veilTxHash, msg.sender);
    }

    function cancelIntent(bytes32 intentId) external {
        LiquidityIntent storage intent = intents[intentId];
        if (intent.state == IntentState.NONE) {
            revert IntentNotFound(intentId);
        }
        if (intent.trader != msg.sender) {
            revert IntentNotOwned(intentId, intent.trader, msg.sender);
        }
        if (intent.state != IntentState.SUBMITTED) {
            revert IntentNotSubmitted(intentId);
        }
        intent.state = IntentState.CANCELLED;
        emit LiquidityIntentCancelled(intentId, intent.nullifier);
    }

    function getIntent(bytes32 intentId)
        external
        view
        returns (
            bytes32 commitment,
            bytes32 nullifier,
            bytes32 envelopeHash,
            uint64 nonce,
            IntentState state
        )
    {
        LiquidityIntent memory intent = intents[intentId];
        if (intent.state == IntentState.NONE) {
            revert IntentNotFound(intentId);
        }
        return (
            intent.commitment,
            intent.nullifier,
            intent.envelopeHash,
            intent.nonce,
            intent.state
        );
    }
}

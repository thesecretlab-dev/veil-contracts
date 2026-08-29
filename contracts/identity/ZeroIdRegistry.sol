// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ZeroIdRegistry
/// @notice Companion-EVM uniqueness register for digest-bound ZER0ID 8004 passports.
///         Not Groth16. Groth16 stays in ZeroIdGate when wasm/zkey are served.
contract ZeroIdRegistry {
    mapping(bytes32 => bool) public usedNullifiers;
    mapping(bytes32 => bytes32) public credentialOf;
    mapping(bytes32 => bytes32) public commitmentOf;
    mapping(bytes32 => bytes32) public issuerSigOf;
    mapping(bytes32 => address) public walletOf;
    mapping(address => bytes32) public nullifierOf;
    uint256 public count;
    address public issuer;

    event Issued(bytes32 indexed nullifier, bytes32 commitment, bytes32 credentialHash, bytes32 issuerSig);
    event Bound(address indexed wallet, bytes32 indexed nullifier);

    error NotIssuer();
    error NullifierUsed();
    error UnknownNullifier();
    error AlreadyBound();
    error ZeroWallet();
    error ZeroHash();

    constructor() {
        issuer = msg.sender;
    }

    function issue(bytes32 nullifier, bytes32 commitment, bytes32 credentialHash, bytes32 issuerSig) external {
        if (msg.sender != issuer) revert NotIssuer();
        if (
            nullifier == bytes32(0) || commitment == bytes32(0) || credentialHash == bytes32(0)
                || issuerSig == bytes32(0)
        ) {
            revert ZeroHash();
        }
        if (usedNullifiers[nullifier]) revert NullifierUsed();
        usedNullifiers[nullifier] = true;
        commitmentOf[nullifier] = commitment;
        credentialOf[nullifier] = credentialHash;
        issuerSigOf[nullifier] = issuerSig;
        count += 1;
        emit Issued(nullifier, commitment, credentialHash, issuerSig);
    }

    function bind(bytes32 nullifier, address wallet) external {
        if (msg.sender != issuer) revert NotIssuer();
        if (!usedNullifiers[nullifier]) revert UnknownNullifier();
        if (wallet == address(0)) revert ZeroWallet();
        if (walletOf[nullifier] != address(0) || nullifierOf[wallet] != bytes32(0)) revert AlreadyBound();
        walletOf[nullifier] = wallet;
        nullifierOf[wallet] = nullifier;
        emit Bound(wallet, nullifier);
    }
}

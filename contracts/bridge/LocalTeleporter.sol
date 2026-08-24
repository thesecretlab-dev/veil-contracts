// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev LOCAL ANVIL ONLY. Not Avalanche ICTT / Teleporter.
/// Implements the messenger surface VeilBridgeMinter calls so we can deploy
/// the minter without pretending this is Fuji.

struct TeleporterFeeInfo {
    address feeTokenAddress;
    uint256 amount;
}

struct TeleporterMessageInput {
    bytes32 destinationBlockchainID;
    address destinationAddress;
    TeleporterFeeInfo feeInfo;
    uint256 requiredGasLimit;
    address[] allowedRelayerAddresses;
    bytes message;
}

contract LocalTeleporter {
    uint256 public nonce;

    event MockMessageSent(
        bytes32 indexed messageID,
        bytes32 indexed destinationBlockchainID,
        address indexed destinationAddress,
        bytes message
    );

    function sendCrossChainMessage(TeleporterMessageInput calldata messageInput)
        external
        returns (bytes32 messageID)
    {
        nonce += 1;
        messageID = keccak256(abi.encode(nonce, msg.sender, messageInput.destinationBlockchainID, messageInput.message));
        emit MockMessageSent(
            messageID,
            messageInput.destinationBlockchainID,
            messageInput.destinationAddress,
            messageInput.message
        );
    }
}

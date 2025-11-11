// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWinVerifier {
    function verifyWinProof(
        bytes calldata proof,
        bytes32 winnersRoot,
        uint256 sessionId,
        bytes32 paymentNullifier
    ) external view returns (bool);
}
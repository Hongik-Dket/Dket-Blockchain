// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVerifier {
    function verifyWinProof(
        uint256[24] calldata proof,
        uint256[3] calldata pubSignals
    ) external view returns (bool);

    function verifyOwnProof(
        uint256[24] calldata proof,
        uint256[3] calldata pubSignals
    ) external view returns (bool);
}
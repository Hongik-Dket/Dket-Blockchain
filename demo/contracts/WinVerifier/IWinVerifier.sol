// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWinVerifier {
    function verifyWinProof(
        uint256[24] calldata proof,
        uint256[3] calldata pubSignals
    ) external view returns (bool);
}
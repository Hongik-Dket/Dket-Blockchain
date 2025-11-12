// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IWinVerifier.sol";
import "./WinVerifier_plonk.sol";

contract WinVerifierAdapter is IWinVerifier {
    PlonkVerifier public immutable verifier;

    constructor(address _verifier) {
        verifier = PlonkVerifier(_verifier);
    }

    function verifyWinProof(
        uint256[24] calldata proof,
        uint256[3]  calldata pubSignals
    ) external view override returns (bool) {
        return verifier.verifyProof(proof, pubSignals);
    }
}
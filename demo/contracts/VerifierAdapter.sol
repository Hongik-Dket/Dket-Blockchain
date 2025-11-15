// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IVerifier.sol";
import {PlonkVerifier as WinPlonkVerifier} from "./winVerifier_plonk.sol";
import {PlonkVerifier as OwnPlonkVerifier} from "./ownVerifier_plonk.sol";

contract VerifierAdapter is IVerifier {
    WinPlonkVerifier public immutable winVerifier;
    OwnPlonkVerifier public immutable ownVerifier;

    constructor(address _winVerifier, address _ownVerifier) {
        winVerifier = WinPlonkVerifier(_winVerifier);
        ownVerifier = OwnPlonkVerifier(_ownVerifier);
    }

    function verifyWinProof(
        uint256[24] calldata proof,
        uint256[3]  calldata pubSignals
    ) external view override returns (bool) {
        return winVerifier.verifyProof(proof, pubSignals);
    }

    function verifyOwnProof(
        uint256[24] calldata proof,
        uint256[3]  calldata pubSignals
    ) external view override returns (bool) {
        return ownVerifier.verifyProof(proof, pubSignals);
    }
}
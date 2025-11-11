// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IWinVerifier.sol";
import "./WinVerifier_plonk.sol";

contract WinVerifierAdapter is IWinVerifier {
    VerifierPlonk public immutable verifier;

    constructor(address _verifier) {
        verifier = VerifierPlonk(_verifier);
    }

    function verifyWinProof(
        bytes calldata proofBytes,
        bytes32 winnersRoot,
        uint256 sessionId,
        bytes32 paymentNullifier
    ) external view override returns (bool) {
        uint256[24] memory proof = abi.decode(proofBytes, (uint256[24]));
        uint256[3] memory pub;
        pub[0] = sessionId;
        pub[1] = uint256(winnersRoot);
        pub[2] = uint256(paymentNullifier);
        return verifier.verifyProof(proof, pub);
    }
}
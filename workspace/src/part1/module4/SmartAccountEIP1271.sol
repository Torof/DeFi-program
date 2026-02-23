// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Smart Account with EIP-1271 Signature Validation
//
// Extend the simple smart account to support EIP-1271 contract signature
// verification. This enables the smart account to interact with protocols
// that require signature validation (like Permit2).
//
// Day 9: Integrate smart accounts with modern DeFi protocols.
//
// Run: forge test --match-contract SmartAccountEIP1271Test -vvv
// ============================================================================

import {SimpleSmartAccount, UserOperation, IAccount, IEntryPoint} from "./SimpleSmartAccount.sol";

// --- Custom Errors ---
error InvalidSignatureLength();

// =============================================================
//  EIP-1271 Interface
// =============================================================
interface IERC1271 {
    /// @notice Verifies that a signature is valid
    /// @param hash Hash of the data to be signed
    /// @param signature Signature byte array
    /// @return magicValue The magic value 0x1626ba7e if valid, 0xffffffff otherwise
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}

// =============================================================
//  TODO 1: Implement SmartAccountEIP1271
// =============================================================
/// @notice Smart account with EIP-1271 signature validation support.
contract SmartAccountEIP1271 is SimpleSmartAccount, IERC1271 {
    // EIP-1271 magic value
    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 private constant EIP1271_INVALID = 0xffffffff;

    constructor(address _entryPoint, address _owner) SimpleSmartAccount(_entryPoint, _owner) {}

    // =============================================================
    //  TODO 2: Implement isValidSignature (EIP-1271)
    // =============================================================
    /// @notice Validates a signature according to EIP-1271.
    /// @dev Called by external contracts (e.g., Permit2) to verify signatures.
    /// @param hash The hash that was signed
    /// @param signature The signature to validate (65 bytes: r, s, v)
    /// @return magicValue EIP1271_MAGIC_VALUE if valid, EIP1271_INVALID otherwise
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // TODO: Implement
        // 1. Check signature length is 65 bytes (revert InvalidSignatureLength() if not)
        // 2. Extract r, s, v from signature
        // 3. Recover signer using ecrecover(hash, v, r, s)
        // 4. If signer == owner, return EIP1271_MAGIC_VALUE
        // 5. Otherwise, return EIP1271_INVALID
        //
        // Hint: This is similar to _validateSignature from SimpleSmartAccount,
        //       but returns bytes4 instead of uint256
        revert("Not implemented");
    }
}

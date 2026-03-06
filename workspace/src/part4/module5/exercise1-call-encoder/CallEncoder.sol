// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title CallEncoder — Building External Calls by Hand
/// @notice Exercise for Module 5: External Calls in Assembly
/// @dev Practice the 4-step call lifecycle: encode calldata → make the call →
///      check success → decode return data. Each function uses a different
///      combination of CALL / STATICCALL, value forwarding, and return decoding.
///
/// Error Selectors (provided):
///   CallFailed()  → 0x3204506f
contract CallEncoder {
    // ================================================================
    // TODO 1: callWithValue(address target, address account, uint256 tag)
    // ================================================================
    // Encode calldata for `deposit(address,uint256)` and CALL with all
    // ETH attached to this call (msg.value).
    //
    // Steps:
    //   1. Compute the selector: bytes4(keccak256("deposit(address,uint256)"))
    //      → 0x47e7ef24
    //   2. Write calldata to scratch space (0x00):
    //      - mstore(0x00, shl(224, 0x47e7ef24))   ← selector in top 4 bytes
    //      - mstore(0x04, account)                  ← arg 1 at offset 0x04
    //      - mstore(0x24, tag)                      ← arg 2 at offset 0x24
    //   3. Make the call: call(gas(), target, callvalue(), 0x00, 0x44, 0, 0)
    //      - 0x44 = 68 bytes (4 selector + 32 arg1 + 32 arg2)
    //      - callvalue() forwards msg.value
    //   4. Check success — if it failed, bubble the revert data:
    //      - returndatacopy(0x00, 0, returndatasize())
    //      - revert(0x00, returndatasize())
    //
    // Opcodes: mstore, shl, call, callvalue, iszero, returndatasize,
    //          returndatacopy, revert
    // See: Module 5 > Encoding Calldata for External Calls (#encoding-calldata)
    // See: Module 5 > The Call Lifecycle (#call-lifecycle)
    function callWithValue(address target, address account, uint256 tag) external payable {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: staticRead(address target, address account)
    // ================================================================
    // Encode calldata for `getBalance(address)`, make a STATICCALL,
    // and return the decoded uint256.
    //
    // Steps:
    //   1. Compute the selector: bytes4(keccak256("getBalance(address)"))
    //      → 0xf8b2cb4f
    //   2. Write calldata to scratch space (0x00):
    //      - mstore(0x00, shl(224, 0xf8b2cb4f))
    //      - mstore(0x04, account)
    //   3. STATICCALL (6 args, no value): staticcall(gas(), target, 0x00, 0x24, 0x00, 0x20)
    //      - Input: 0x24 = 36 bytes (4 selector + 32 arg)
    //      - Output: write 32 bytes directly to 0x00 (overwrites scratch space)
    //   4. Check success — revert with CallFailed() if it fails:
    //      - mstore(0x00, shl(224, 0x3204506f))
    //      - revert(0x00, 0x04)
    //   5. Return the value: the result is already at 0x00 from the STATICCALL
    //
    // Opcodes: mstore, shl, staticcall, iszero, mload, revert
    // See: Module 5 > Encoding Calldata for External Calls (#encoding-calldata)
    // See: Module 5 > Decoding Return Data (#decoding-returndata)
    function staticRead(address target, address account) external view returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: multiRead(address target, uint256 x)
    // ================================================================
    // Encode calldata for `getTriple(uint256)`, make a STATICCALL,
    // and decode three uint256 return values.
    //
    // Steps:
    //   1. Compute the selector: bytes4(keccak256("getTriple(uint256)"))
    //      → 0xced75724
    //   2. Write calldata to scratch space (0x00):
    //      - mstore(0x00, shl(224, 0xced75724))
    //      - mstore(0x04, x)
    //   3. Allocate output space: use the free memory pointer (mload(0x40))
    //      - let fmp := mload(0x40)
    //      - STATICCALL: staticcall(gas(), target, 0x00, 0x24, fmp, 0x60)
    //        - 0x60 = 96 bytes for 3 × 32 return values
    //   4. Check success — revert with CallFailed() if it fails
    //   5. Decode: a = mload(fmp), b = mload(add(fmp, 0x20)), c = mload(add(fmp, 0x40))
    //
    // Why FMP and not scratch space?
    //   Three return values = 96 bytes. Scratch space is only 64 bytes (0x00-0x3F).
    //   Using FMP-allocated memory avoids overwriting the free memory pointer at 0x40.
    //
    // Opcodes: mstore, shl, staticcall, mload, add, iszero, revert
    // See: Module 5 > Decoding Return Data (#decoding-returndata)
    function multiRead(address target, uint256 x)
        external
        view
        returns (uint256 a, uint256 b, uint256 c)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

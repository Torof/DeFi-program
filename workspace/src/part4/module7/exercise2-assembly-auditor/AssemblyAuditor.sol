// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AssemblyAuditor — Find the Bug, Write the Fix
/// @notice Exercise for Module 7: Reading Production Assembly
/// @dev Three assembly functions contain subtle bugs from the audit checklist.
///      For each bug:
///        1. Read the buggy function and identify the vulnerability
///        2. Implement the fixed version in the corresponding TODO
///
///      Bug types (from Module 7 > The Audit Lens):
///        Bug 1: Unchecked call return value  (audit item #1)
///        Bug 2: Off-by-one in bit shift      (audit item #4)
///        Bug 3: Dirty memory / FMP corruption (audit item #3)
///
/// Error Selectors (provided):
///   ApproveFailed()  → 0x3e3f8f73
contract AssemblyAuditor {
    uint256 internal _packedSlot;

    constructor(uint128 a, uint128 b) {
        _packedSlot = uint256(a) | (uint256(b) << 128);
    }

    // ====================================================================
    // BUG 1: Unchecked call return value
    // ====================================================================
    // This function calls approve() on a token but has a critical flaw.
    // Compare it against the SafeERC20 patterns from Module 5.
    //
    // See: Module 7 > The Audit Lens, item #1
    // See: Module 5 > The SafeERC20 Pattern (#safe-erc20)

    function buggyApprove(address token, address spender, uint256 amount) external {
        assembly {
            mstore(0x00, shl(224, 0x095ea7b3)) // approve(address,uint256)
            mstore(0x04, spender)
            mstore(0x24, amount)
            // The call might fail or return false — but we never check!
            pop(call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20))
        }
    }

    // TODO 1: Implement the fixed version of buggyApprove
    // ================================================================
    // The fix should:
    //   - Make the call (same calldata encoding as above)
    //   - Check that call() returned 1 (didn't revert)
    //   - Check the return data: either no return data (USDT-style)
    //     OR return data decodes to true
    //   - Revert with ApproveFailed() (selector 0x3e3f8f73) if either check fails
    //
    // Pattern: and(success, or(iszero(returndatasize()), eq(mload(0x00), 1)))
    //
    // Hint: this is the exact same validation pattern from SafeTransferLib
    function fixedApprove(address token, address spender, uint256 amount) external {
        assembly {
            revert(0, 0) // TODO: replace with fixed implementation
        }
    }

    // ====================================================================
    // BUG 2: Off-by-one in bit shift
    // ====================================================================
    // This function reads two packed uint128 values from storage.
    // One of the shift amounts is wrong by 1 bit.
    //
    // See: Module 7 > The Audit Lens, item #4
    // See: Module 3 > Storage Packing (#packing-in-practice)

    function buggyUnpack() external view returns (uint128 low, uint128 high) {
        assembly {
            let data := sload(_packedSlot.slot)
            low := and(data, 0xffffffffffffffffffffffffffffffff)
            high := shr(127, data) // Bug: should be 128, not 127
        }
    }

    // TODO 2: Implement the fixed version of buggyUnpack
    // ================================================================
    // The fix is a single-bit change. But finding it requires understanding
    // exactly how bit-shifting extracts packed fields.
    //
    // Hint: if two uint128 values are packed into one uint256,
    //       the lower value occupies bits 0-127 and the upper value
    //       occupies bits 128-255. What shift amount isolates bits 128-255?
    function fixedUnpack() external view returns (uint128 low, uint128 high) {
        assembly {
            revert(0, 0) // TODO: replace with fixed implementation
        }
    }

    // ====================================================================
    // BUG 3: Dirty memory / FMP corruption
    // ====================================================================
    // This function stores a value in memory using assembly, then tries
    // to retrieve it after Solidity allocates a dynamic array. The
    // retrieved value is wrong because the FMP was never advanced.
    //
    // See: Module 7 > The Audit Lens, item #3
    // See: Module 6 > Memory Tricks (#memory-tricks)

    function buggyCache(uint256 x) external pure returns (uint256 cached, uint256 retrieved) {
        bytes32 savedPtr;

        // Store x at the free memory pointer location... but don't advance FMP
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, x)
            savedPtr := ptr
            // BUG: missing mstore(0x40, add(ptr, 0x20)) to advance FMP
        }

        cached = x;

        // Solidity allocates here — starts at the SAME ptr because FMP wasn't advanced.
        // The array length (1) overwrites our stored value at ptr.
        uint256[] memory dummy = new uint256[](1);
        dummy[0] = 0xDEAD;

        // Try to read back our "cached" value — but it's been overwritten
        assembly {
            retrieved := mload(savedPtr)
        }
    }

    // TODO 3: Implement the fixed version of buggyCache
    // ================================================================
    // The fix: advance the free memory pointer after writing to memory,
    // so that subsequent Solidity allocations don't overwrite your data.
    //
    // Steps:
    //   1. Read the current FMP: let ptr := mload(0x40)
    //   2. Store x at ptr: mstore(ptr, x)
    //   3. ADVANCE the FMP: mstore(0x40, add(ptr, 0x20))  ← this is the fix
    //   4. Save ptr for later retrieval
    //   5. Allow Solidity allocation (same dummy array as above)
    //   6. Read back from savedPtr — should still have x
    //
    // Alternative fix: use scratch space (0x00-0x1f) instead of FMP memory,
    // but that only works if you don't need the data to survive across
    // Solidity operations that use scratch space.
    function fixedCache(uint256 x) external pure returns (uint256 cached, uint256 retrieved) {
        assembly {
            revert(0, 0) // TODO: replace with fixed implementation
        }
    }
}

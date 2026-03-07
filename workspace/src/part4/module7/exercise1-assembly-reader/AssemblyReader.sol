// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AssemblyReader — Read Assembly, Write Solidity
/// @notice Exercise for Module 7: Reading Production Assembly
/// @dev Three assembly functions are provided with NO comments. Your job:
///      1. Read each mystery function and understand what it does
///      2. Implement a pure Solidity equivalent (solveA, solveB, solveC)
///      3. Tests verify your Solidity version matches the assembly version
///
///      Use the 5-step reading methodology from Module 7:
///        Step 1: Identify the pattern type
///        Step 2: Read the interface (inputs/outputs)
///        Step 3: Draw the data layout
///        Step 4: Trace one execution path
///        Step 5: Identify the tricks
contract AssemblyReader {
    uint256 internal _packedSlot;

    constructor(uint128 a, uint128 b) {
        _packedSlot = uint256(a) | (uint256(b) << 128);
    }

    // ====================================================================
    // PROVIDED — Read and understand. Do NOT modify.
    // ====================================================================

    function mysteryA() external view returns (uint128, uint128) {
        assembly {
            let data := sload(_packedSlot.slot)
            let lo := and(data, 0xffffffffffffffffffffffffffffffff)
            let hi := shr(128, data)
            mstore(0x00, lo)
            mstore(0x20, hi)
            return(0x00, 0x40)
        }
    }

    function mysteryB(uint256 x, uint256 lo, uint256 hi) external pure returns (uint256 result) {
        assembly {
            let tmp := xor(lo, mul(xor(x, lo), gt(x, lo)))
            result := xor(hi, mul(xor(tmp, hi), lt(tmp, hi)))
        }
    }

    function mysteryC(bytes calldata data) external pure returns (address who, uint128 amount, uint64 deadline) {
        assembly {
            let w1 := calldataload(data.offset)
            who := shr(96, w1)
            amount := shr(128, calldataload(add(data.offset, 20)))
            deadline := shr(192, calldataload(add(data.offset, 36)))
        }
    }

    // ====================================================================
    // TODO 1: Solidity equivalent of mysteryA
    // ====================================================================
    // Hints:
    //   - What storage layout pattern is this? (M3 skill)
    //   - How are two values packed into one uint256?
    //   - What Solidity casts extract the lower and upper halves?
    //
    // See: Module 7 > The Systematic Approach (#reading-methodology)
    // See: Module 3 > Storage Packing (#packing-in-practice)
    function solveA() external view returns (uint128, uint128) {
        revert(); // TODO: replace with Solidity implementation
    }

    // ====================================================================
    // TODO 2: Solidity equivalent of mysteryB
    // ====================================================================
    // Hints:
    //   - Trace with x=1, lo=3, hi=10 (x below range)
    //   - Trace with x=5, lo=3, hi=10 (x in range)
    //   - Trace with x=15, lo=3, hi=10 (x above range)
    //   - What common math operation does this perform?
    //   - Your Solidity version doesn't need to be branchless
    //
    // See: Module 7 > The Systematic Approach (#reading-methodology)
    // See: Module 6 > Branchless Patterns (#branchless)
    function solveB(uint256 x, uint256 lo, uint256 hi) external pure returns (uint256) {
        revert(); // TODO: replace with Solidity implementation
    }

    // ====================================================================
    // TODO 3: Solidity equivalent of mysteryC
    // ====================================================================
    // Hints:
    //   - What's the custom encoding format? (NOT ABI-encoded)
    //   - How many bytes does each type occupy?
    //     address = 20, uint128 = 16, uint64 = 8 → total = 44 bytes
    //   - How does calldataload + shr extract each field?
    //   - Solidity's bytes slicing + type casts can do the same thing
    //
    // See: Module 7 > The Systematic Approach (#reading-methodology)
    // See: Module 2 > Calldata Layout (#calldata-layout)
    function solveC(bytes calldata data) external pure returns (address, uint128, uint64) {
        revert(); // TODO: replace with Solidity implementation
    }
}

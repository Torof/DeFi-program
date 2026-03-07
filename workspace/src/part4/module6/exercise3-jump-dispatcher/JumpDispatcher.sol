// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title JumpDispatcher — Assembly-Based Function Dispatch
/// @notice Exercise for Module 6: Gas Optimization Patterns
/// @dev Build a hand-written dispatcher in the fallback() that responds to
///      the same 8 function selectors as LinearDispatcher, returning the
///      same values. The compiler's default dispatch uses a linear if-else
///      chain — your assembly version uses a direct switch, demonstrating
///      how dispatch optimization works at the opcode level.
///
/// Function selectors (same as LinearDispatcher):
///   getA() → 0xd46300fd      returns 1
///   getB() → 0xa1c51915      returns 2
///   getC() → 0xa2375d1e      returns 3
///   getD() → 0x1a14ff7a      returns 4
///   getE() → 0xb1cb267b      returns 5
///   getF() → 0x0c204dbc      returns 6
///   getG() → 0x04c09ce9      returns 7
///   getH() → 0x82529fdb      returns 8
///
/// Verify these with: cast sig "getA()" → 0xd46300fd (and so on)
contract JumpDispatcher {
    // ================================================================
    // TODO 1: Implement the fallback dispatcher
    // ================================================================
    // Build a hand-written dispatcher that handles all 8 function
    // selectors. The fallback receives raw calldata — you must extract
    // the selector and route to the correct handler.
    //
    // Steps:
    //   1. Extract the 4-byte function selector:
    //      - let sel := shr(224, calldataload(0))
    //        (shift right 224 bits = 28 bytes → leaves the 4-byte selector)
    //
    //   2. Dispatch using a switch statement:
    //      - switch sel
    //      - case 0xd46300fd { ... }   // getA → return 1
    //      - case 0xa1c51915 { ... }   // getB → return 2
    //      - ... (all 8 cases)
    //      - default { revert(0, 0) }  // unknown selector → revert
    //
    // ================================================================
    // TODO 2: Implement each handler
    // ================================================================
    // Each case in the switch must:
    //   1. Store the return value at memory offset 0x00:
    //      - mstore(0x00, VALUE)
    //   2. Return 32 bytes:
    //      - return(0x00, 0x20)
    //
    // Example handler for getA():
    //   case 0xd46300fd {
    //       mstore(0x00, 1)
    //       return(0x00, 0x20)
    //   }
    //
    // Why `return` instead of assigning a variable:
    //   The assembly `return` opcode sends raw bytes back to the caller
    //   and halts execution. This bypasses Solidity's ABI encoding,
    //   saving gas. The caller receives exactly 32 bytes that decode
    //   as a uint256 — identical to a normal function return.
    //
    // Why this is faster than the compiler's dispatch:
    //   The Solidity compiler generates an if-else chain that checks
    //   each selector sequentially. The last function in the chain
    //   pays for ALL prior comparisons. A switch statement compiles
    //   to a more efficient lookup. For 8 functions the difference
    //   is small; for 25+ functions it becomes significant.
    //
    // Opcodes: shr, calldataload, mstore, return, revert
    // See: Module 6 > Jump Table Dispatch (#jump-table)
    fallback() external payable {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Yul Basics
//
// Implement basic functions using ONLY inline assembly. No Solidity arithmetic,
// no Solidity if-statements — everything inside assembly { } blocks.
//
// This builds muscle memory for core Yul syntax: let, add, mul, gt, lt, eq,
// iszero, caller(), callvalue(), timestamp(), chainid(), calldataload(), shr().
//
// Concepts exercised:
//   - Yul variable declaration (let) and assignment (:=)
//   - Arithmetic opcodes (add, mul, sub)
//   - Comparison opcodes (gt, lt, eq, iszero)
//   - Conditional logic (if, switch/case)
//   - Context opcodes (caller, callvalue, timestamp, chainid)
//   - Calldata reading (calldataload, shr)
//
// Run: forge test --match-contract YulBasicsTest -vvv
// ============================================================================

contract YulBasics {
    // -------------------------------------------------------------------------
    // TODO 1: Add two numbers using assembly
    //
    // Use the `add` opcode. This is unchecked — it wraps on overflow (no revert).
    // Assign the result to the return variable.
    //
    // Opcodes: add
    // See: Module 1 > The Stack Machine (#stack-machine) — how ADD works
    // -------------------------------------------------------------------------
    function addNumbers(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Return the larger of two values
    //
    // Use `gt` (greater than) to compare, then conditionally assign.
    // You can use `if` or `switch` — both work.
    //
    // Opcodes: gt, if/switch
    // See: Module 1 > Your First Yul (#first-yul) — conditional syntax
    // -------------------------------------------------------------------------
    function max(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 3: Clamp a value to a range [min, max]
    //
    // If value < min, return min.
    // If value > max, return max.
    // Otherwise, return value.
    //
    // Opcodes: lt, gt, if/switch
    // See: Module 1 > Your First Yul (#first-yul) — conditional logic
    // -------------------------------------------------------------------------
    function clamp(uint256 value, uint256 minVal, uint256 maxVal) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 4: Read execution context using opcodes
    //
    // Return msg.sender, msg.value, block.timestamp, and block.chainid
    // by calling their corresponding Yul built-ins.
    //
    // Opcodes: caller, callvalue, timestamp, chainid
    // See: Module 1 > Execution Context (#execution-context) — opcode mapping
    // -------------------------------------------------------------------------
    function getContext()
        external
        payable
        returns (address sender, uint256 value, uint256 ts, uint256 chain)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Extract the function selector from arbitrary calldata
    //
    // The selector is the first 4 bytes of calldata. Since calldataload reads
    // 32 bytes, you need to shift right to isolate the top 4 bytes.
    //
    // Hint: 4 bytes = 32 bits, so shift right by 256 - 32 = 224 bits
    //
    // Opcodes: calldataload, shr
    // See: Module 1 > Execution Context (#execution-context) — calldata layout
    // -------------------------------------------------------------------------
    function extractSelector(bytes calldata data) external pure returns (bytes4 selector) {
        assembly {
            // For `bytes calldata` parameters, Solidity provides Yul accessors:
            //   data.offset — byte position in calldata where the bytes start
            //   data.length — number of bytes
            //
            // Use calldataload(data.offset) to read 32 bytes starting at the
            // data's position, then shift right to isolate the first 4 bytes.

            revert(0, 0) // TODO: replace with implementation
        }
    }
}

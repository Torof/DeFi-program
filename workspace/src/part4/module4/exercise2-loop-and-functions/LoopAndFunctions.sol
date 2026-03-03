// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LoopAndFunctions — Yul Functions & Loop Patterns
/// @notice Exercise for Module 4: Control Flow & Functions
/// @dev Practice defining Yul functions, writing gas-efficient loops,
///      and processing calldata arrays in assembly.
///
/// Unlike Exercise 1 (YulDispatcher), each function here has a Solidity
/// signature — you only need to implement the assembly body.
///
/// Storage Layout (DO NOT MODIFY):
///   Slot 0: owner (address) — set in constructor
///   Mapping base slot 1: balances (mapping(address => uint256))
///
/// Error Selectors (provided):
///   ArrayLengthMismatch()     → 0x3b800a46
///   InsufficientBalance()     → 0xf4d678b8
contract LoopAndFunctions {
    /// @dev Sets owner and gives them an initial balance for testing.
    constructor() {
        assembly {
            sstore(0, caller()) // slot 0 = owner

            // Give owner 1,000,000 tokens for batchTransfer testing
            // Compute balances[owner] slot: keccak256(abi.encode(caller(), 1))
            mstore(0x00, caller())
            mstore(0x20, 1) // mapping base slot
            let ownerBalSlot := keccak256(0x00, 0x40)
            sstore(ownerBalSlot, 1000000)
        }
    }

    // ================================================================
    // TODO 1: requireWithError(bool condition, bytes4 errorSelector)
    // ================================================================
    // Revert with the given error selector if condition is false.
    //
    // Steps:
    //   1. Check if condition is false: iszero(condition)
    //   2. If false, encode the error selector and revert:
    //      - mstore(0x00, shl(224, errorSelector))
    //      - revert(0x00, 0x04)
    //   3. If true, do nothing (function returns normally)
    //
    // Opcodes: iszero, shl, mstore, revert
    // See: Module 4 > Yul if — Conditional Execution (#yul-if)
    function requireWithError(bool condition, bytes4 errorSelector) public pure {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: min(uint256 a, uint256 b) and max(uint256 a, uint256 b)
    // ================================================================
    // Implement min and max using Yul functions inside the assembly block.
    //
    // For min:
    //   Define a Yul function: function yulMin(x, y) -> result { ... }
    //   Use: if lt(x, y) { result := x } else use switch or default
    //   Hint: result := y   then   if lt(x, y) { result := x }
    //
    // For max:
    //   Same pattern but with gt instead of lt
    //
    // Bonus (optional): Branchless version using xor/mul:
    //   min(a,b) = xor(b, mul(xor(a, b), lt(a, b)))
    //
    // Opcodes: lt, gt, if
    // See: Module 4 > Defining and Calling Yul Functions (#yul-functions)
    function min(uint256 a, uint256 b) public pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function max(uint256 a, uint256 b) public pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: sumArray(uint256[] calldata arr) → returns (uint256)
    // ================================================================
    // Loop through a calldata array and return the sum of all elements.
    //
    // Calldata array layout:
    //   arr.offset = byte offset in calldata where elements start
    //   arr.length = number of elements
    //   Element i is at: calldataload(add(arr.offset, mul(i, 0x20)))
    //
    // Steps:
    //   1. Get array offset and length from the Yul accessors:
    //      let offset := arr.offset
    //      let len := arr.length
    //   2. Initialize sum: let total := 0
    //   3. Loop from 0 to len:
    //      for { let i := 0 } lt(i, len) { i := add(i, 1) } {
    //          let element := calldataload(add(offset, mul(i, 0x20)))
    //          total := add(total, element)
    //      }
    //   4. Assign to the return variable: result := total
    //
    // Opcodes: calldataload, add, mul, lt, for
    // See: Module 4 > for Loops — Gas-Efficient Iteration (#yul-for)
    function sumArray(uint256[] calldata arr) public pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 4: findMax(uint256[] calldata arr) → returns (uint256)
    // ================================================================
    // Loop through a calldata array and return the maximum element.
    // Returns 0 for empty arrays.
    //
    // Steps:
    //   1. Get array offset and length
    //   2. Initialize: let currentMax := 0
    //   3. Loop through elements:
    //      - Load each element from calldata
    //      - If element > currentMax, update currentMax
    //   4. Return currentMax
    //
    // Hint: Use gt(element, currentMax) inside the loop
    //
    // Opcodes: calldataload, gt, if, for
    // See: Module 4 > for Loops (#yul-for)
    function findMax(uint256[] calldata arr) public pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 5: batchTransfer(address[] calldata recipients, uint256[] calldata amounts)
    // ================================================================
    // Transfer tokens from caller to multiple recipients in a single call.
    // This is the hardest TODO — it combines loops, storage, and validation.
    //
    // Steps:
    //   1. Validate array lengths match:
    //      if iszero(eq(recipients.length, amounts.length)) → revert ArrayLengthMismatch()
    //      Selector: 0x3b800a46
    //
    //   2. Compute caller's balance slot: keccak256(abi.encode(caller(), 1))
    //      (mapping base slot = 1)
    //
    //   3. Load caller's total balance: sload(senderBalSlot)
    //
    //   4. Loop through recipients:
    //      for { let i := 0 } lt(i, recipients.length) { i := add(i, 1) } {
    //        a. Load recipient: calldataload(add(recipients.offset, mul(i, 0x20)))
    //           Mask to address: and(recipient, 0xffffffffffffffffffffffffffffffffffffffff)
    //        b. Load amount: calldataload(add(amounts.offset, mul(i, 0x20)))
    //        c. Check sender has enough: if lt(senderBal, amount) → revert InsufficientBalance()
    //           Selector: 0xf4d678b8
    //        d. Subtract from sender: senderBal := sub(senderBal, amount)
    //        e. Compute recipient's balance slot: keccak256(abi.encode(recipient, 1))
    //        f. Add to recipient: sstore(recipientSlot, add(sload(recipientSlot), amount))
    //      }
    //
    //   5. Store sender's final balance: sstore(senderBalSlot, senderBal)
    //      (Write once at the end, not every iteration — gas optimization!)
    //
    // Opcodes: caller, mstore, keccak256, sload, sstore, calldataload, and, lt, eq, iszero, add, sub, for
    // See: Module 3 > Mapping Slot Computation (#mapping-slots)
    // See: Module 4 > for Loops (#yul-for)
    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) public {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // Helper: balanceOf (provided for testing, NOT a TODO)
    // ================================================================
    function balanceOf(address account) public view returns (uint256 result) {
        assembly {
            mstore(0x00, account)
            mstore(0x20, 1) // mapping base slot
            result := sload(keccak256(0x00, 0x40))
        }
    }
}

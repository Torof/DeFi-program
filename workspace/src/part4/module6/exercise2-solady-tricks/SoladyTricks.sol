// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SoladyTricks — Opcode-Level Optimization Patterns
/// @notice Exercise for Module 6: Gas Optimization Patterns
/// @dev Practice the branchless math and memory tricks from Topic Block 2:
///      branchless min/max, branchless abs, and efficient multi-transfer
///      with dirty memory and no FMP advancement.
///
/// Error Selectors (provided):
///   TransferFailed()  → 0x90b8ec18
///   LengthMismatch()  → 0xff633a38
contract SoladyTricks {
    // ================================================================
    // TODO 1: branchlessMin(uint256 a, uint256 b) → uint256 result
    // ================================================================
    // Return the smaller of a and b WITHOUT using JUMPI (no branching).
    //
    // The Solady formula:
    //   result = xor(b, mul(xor(a, b), lt(a, b)))
    //
    // Why it works — trace with a=3, b=7:
    //   xor(a, b) = xor(3, 7) = 4          ← the "diff" bits
    //   lt(a, b)  = lt(3, 7)  = 1           ← a IS less than b
    //   mul(4, 1) = 4                        ← keep the diff
    //   xor(b, 4) = xor(7, 4) = 3           ← flip b back to a ✓
    //
    // Trace with a=7, b=3:
    //   xor(a, b) = xor(7, 3) = 4
    //   lt(a, b)  = lt(7, 3)  = 0           ← a is NOT less than b
    //   mul(4, 0) = 0                        ← discard the diff
    //   xor(b, 0) = xor(3, 0) = 3           ← b is already the min ✓
    //
    // Opcodes: xor, mul, lt
    // See: Module 6 > Branchless Patterns (#branchless)
    function branchlessMin(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: branchlessMax(uint256 a, uint256 b) → uint256 result
    // ================================================================
    // Return the larger of a and b WITHOUT using JUMPI (no branching).
    //
    // The Solady formula:
    //   result = xor(b, mul(xor(a, b), gt(a, b)))
    //
    // Same pattern as min — just swap lt for gt.
    //
    // Trace with a=3, b=7:
    //   xor(a, b) = 4
    //   gt(a, b)  = gt(3, 7) = 0            ← a is NOT greater
    //   mul(4, 0) = 0
    //   xor(b, 0) = 7                        ← b is the max ✓
    //
    // Trace with a=7, b=3:
    //   xor(a, b) = 4
    //   gt(a, b)  = gt(7, 3) = 1            ← a IS greater
    //   mul(4, 1) = 4
    //   xor(b, 4) = xor(3, 4) = 7           ← flip b up to a ✓
    //
    // Opcodes: xor, mul, gt
    // See: Module 6 > Branchless Patterns (#branchless)
    function branchlessMax(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: branchlessAbs(int256 x) → uint256 result
    // ================================================================
    // Return the absolute value of x WITHOUT using JUMPI (no branching).
    //
    // The Solady formula:
    //   let mask := sar(255, x)    ← 0x00...00 if x ≥ 0, 0xFF...FF if x < 0
    //   result := xor(add(x, mask), mask)
    //
    // Why it works — negative case (x = -5):
    //   mask = sar(255, -5) = 0xFF...FF     (all 1s — sign extension)
    //   add(x, mask) = add(-5, -1) = -6     (in two's complement)
    //   xor(-6, mask) = xor(-6, -1)         (flips ALL bits)
    //                 = 5                     ← absolute value ✓
    //
    //   Bitwise: -6 in two's complement is ...11111010
    //            XOR with                     ...11111111
    //            =                            ...00000101 = 5 ✓
    //
    // Why it works — positive case (x = 5):
    //   mask = sar(255, 5) = 0x00...00      (all 0s)
    //   add(x, mask) = add(5, 0) = 5
    //   xor(5, 0) = 5                        ← unchanged ✓
    //
    // Opcodes: sar, add, xor
    // See: Module 6 > Branchless Patterns (#branchless)
    function branchlessAbs(int256 x) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 4: efficientMultiTransfer(address token, address[] calldata to,
    //         uint256[] calldata amounts)
    // ================================================================
    // Transfer `amounts[i]` of `token` to each `to[i]`. Uses the dirty
    // memory pattern: write calldata at scratch space (0x00), make the
    // call, and NEVER clean up or advance the free memory pointer.
    //
    // This is safe because no Solidity code runs after the assembly block
    // that would depend on the free memory pointer being correct.
    //
    // Steps:
    //   1. Check that to.length == amounts.length:
    //      - if iszero(eq(to.length, amounts.length)) → revert LengthMismatch()
    //   2. Store the transfer selector once (it doesn't change):
    //      - mstore(0x00, shl(224, 0xa9059cbb))
    //   3. Loop through each recipient:
    //      - for { let i := 0 } lt(i, to.length) { i := add(i, 1) }
    //      - Load to[i] from calldata: calldataload(add(to.offset, mul(i, 0x20)))
    //      - Load amounts[i] from calldata: calldataload(add(amounts.offset, mul(i, 0x20)))
    //      - mstore(0x04, recipient)
    //      - mstore(0x24, amt)
    //      - let ok := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
    //      - Check: and(ok, or(iszero(returndatasize()), eq(mload(0x00), 1)))
    //      - If check fails: revert TransferFailed()
    //
    // Why dirty memory is safe here:
    //   We write at 0x00-0x43 (scratch space + part of free memory area).
    //   This function returns void, so Solidity emits STOP after the
    //   assembly block — no memory allocation happens afterward, and
    //   the corrupted FMP at 0x40 is never read. You do NOT need an
    //   assembly `return` here — Solidity's STOP handles it.
    //
    // Why this is faster than Solidity:
    //   - No memory allocation per iteration (saves ~60 gas × N)
    //   - Selector stored once, not re-computed
    //   - No ABI encoding overhead for the inner call
    //
    // Opcodes: eq, iszero, shl, mstore, calldataload, add, mul, lt,
    //          call, returndatasize, mload, or, and, revert
    // See: Module 6 > Memory Tricks (#memory-tricks)
    function efficientMultiTransfer(address token, address[] calldata to, uint256[] calldata amounts) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

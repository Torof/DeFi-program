// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Gas Explorer
//
// Measure and compare gas costs at the opcode level. Some functions you'll
// implement in assembly, others combine Solidity and assembly to observe
// the cost differences between patterns.
//
// Concepts exercised:
//   - Using the `gas()` opcode to measure execution cost
//   - Cold vs warm storage access (EIP-2929)
//   - Checked vs unchecked arithmetic gas difference
//   - Memory vs storage cost comparison
//   - Writing simple assembly to observe opcode costs
//
// Run: forge test --match-contract GasExplorerTest -vvv
// ============================================================================

contract GasExplorer {
    // Storage slots used for gas measurement
    // Solidity assigns sequential slots: storedValue = slot 0, storedValueB = slot 1
    uint256 public storedValue;   // slot 0 — used by SLOAD measurements
    uint256 public storedValueB;  // slot 1 — used by SSTORE measurement (avoids slot 0 interference)

    // -------------------------------------------------------------------------
    // TODO 1: Measure the gas cost of a cold SLOAD
    //
    // Use the `gas()` opcode before and after an `sload()` to measure the cost.
    // This function should NOT be called after any other function that reads
    // `storedValue` in the same transaction (so the access is cold).
    //
    // Steps:
    //   1. Record gas before: let gasBefore := gas()
    //   2. Perform sload on the storedValue slot (slot 0)
    //   3. Record gas after: let gasAfter := gas()
    //   4. Return gasBefore - gasAfter (this includes the gas() opcode overhead,
    //      but the test accounts for that)
    //
    // Opcodes: gas, sload
    // See: Module 1 > EIP-2929 Warm/Cold Access (#warm-cold)
    // -------------------------------------------------------------------------
    function measureSloadCold() external view returns (uint256 gasUsed) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Measure the gas cost of a warm SLOAD
    //
    // Same pattern as TODO 1, but first perform an sload to "warm up" the slot,
    // then measure the second sload.
    //
    // Steps:
    //   1. Perform a throwaway sload(0) to warm the slot
    //   2. Record gas before
    //   3. Perform the measured sload(0)
    //   4. Record gas after
    //   5. Return the difference
    //
    // Opcodes: gas, sload
    // See: Module 1 > EIP-2929 Warm/Cold Access (#warm-cold)
    // -------------------------------------------------------------------------
    function measureSloadWarm() external view returns (uint256 gasUsed) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 3: Add two numbers using Solidity's checked arithmetic
    //
    // This is just a normal Solidity addition — it reverts on overflow.
    // The tests will compare its gas cost with addAssembly().
    //
    // No assembly needed here — just return a + b in Solidity.
    // -------------------------------------------------------------------------
    function addChecked(uint256 a, uint256 b) external pure returns (uint256) {
        revert("Not implemented");
    }

    // -------------------------------------------------------------------------
    // TODO 4: Add two numbers using assembly (unchecked)
    //
    // Use the `add` opcode in assembly. This wraps on overflow — no revert.
    // The tests will compare its gas cost with addChecked().
    //
    // Opcodes: add
    // -------------------------------------------------------------------------
    function addAssembly(uint256 a, uint256 b) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Write a value to memory and return gas used
    //
    // Use `gas()` before and after an `mstore` to measure memory write cost.
    //
    // Steps:
    //   1. Record gas before
    //   2. mstore(0x80, val) — write to a memory location
    //   3. Record gas after
    //   4. Return the difference
    //
    // Opcodes: gas, mstore
    // See: Module 1 > Gas Model (#gas-model) — memory costs
    // -------------------------------------------------------------------------
    function measureMemoryWrite(uint256 val) external pure returns (uint256 gasUsed) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 6: Write a value to storage and return gas used
    //
    // Same pattern as TODO 5 but using `sstore` instead of `mstore`.
    // Uses slot 1 (storedValueB) to avoid interfering with other measurements.
    //
    // Steps:
    //   1. Record gas before
    //   2. sstore(1, val) — write to storage slot 1
    //   3. Record gas after
    //   4. Return the difference
    //
    // Opcodes: gas, sstore
    // See: Module 1 > Gas Model (#gas-model) — storage costs
    // -------------------------------------------------------------------------
    function measureStorageWrite(uint256 val) external returns (uint256 gasUsed) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title GasBenchmark — Measuring Gas Costs
/// @notice Exercise for Module 6: Gas Optimization Patterns
/// @dev Practice the gas profiling skills from Topic Block 1:
///      measuring with gas() opcodes, comparing implementations,
///      and applying storage caching optimization.
contract GasBenchmark {
    // ================================================================
    // Storage for TODO 3
    // ================================================================

    /// @dev Prices array for the optimization exercise. Set by the test.
    uint256[] public prices;

    /// @dev Allows tests to push values into the prices array.
    function pushPrice(uint256 price) external {
        prices.push(price);
    }

    // ================================================================
    // TODO 1: measureTransferGas(address token, address to, uint256 amount)
    // ================================================================
    // Measure the gas cost of calling token.transfer(to, amount).
    // Return the gas consumed by the call itself.
    //
    // Steps:
    //   1. Record gas before: let before := gas()
    //   2. Make the call: call(gas(), token, 0, ..., ..., 0, 0)
    //      - Encode transfer(address,uint256) at scratch space:
    //        Selector: 0xa9059cbb
    //        mstore(0x00, shl(224, 0xa9059cbb))
    //        mstore(0x04, to)
    //        mstore(0x24, amount)
    //      - let ok := call(gas(), token, 0, 0x00, 0x44, 0, 0)
    //   3. Record gas after: let after := gas()
    //   4. Compute cost: gasUsed := sub(before, after)
    //   5. If the call failed, revert with MeasurementFailed()
    //
    // Why assembly gas() instead of Solidity gasleft()?
    //   They compile to the same opcode, but in assembly you control
    //   exactly where the measurements happen — no compiler-inserted
    //   code between your gas() calls and the operation.
    //
    // Error Selector: MeasurementFailed() → 0x569e9815
    //
    // Opcodes: gas, mstore, shl, call, sub, iszero, revert
    // See: Module 6 > Gas Profiling with Foundry (#gas-profiling)
    function measureTransferGas(address token, address to, uint256 amount)
        external
        returns (uint256 gasUsed)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 2: compareImplementations(address tokenA, address tokenB,
    //         address to, uint256 amount)
    // ================================================================
    // Call transfer(to, amount) on both tokens. Return the address
    // of the cheaper one (the one that used less gas).
    //
    // Steps:
    //   1. Encode transfer calldata once (same for both tokens):
    //      - mstore(0x00, shl(224, 0xa9059cbb))
    //      - mstore(0x04, to)
    //      - mstore(0x24, amount)
    //   2. Measure gas for tokenA:
    //      - let beforeA := gas()
    //      - let okA := call(gas(), tokenA, 0, 0x00, 0x44, 0, 0)
    //      - let gasA := sub(beforeA, gas())
    //   3. Measure gas for tokenB (calldata is still in memory):
    //      - let beforeB := gas()
    //      - let okB := call(gas(), tokenB, 0, 0x00, 0x44, 0, 0)
    //      - let gasB := sub(beforeB, gas())
    //   4. If either call failed, revert with MeasurementFailed()
    //   5. Compare: if lt(gasA, gasB) → cheaper = tokenA, else tokenB
    //
    // Note: both tokens get a warm call (second access) since the test
    // sets up balances before calling this function. The comparison is fair.
    //
    // Opcodes: gas, mstore, shl, call, sub, lt, iszero, revert
    // See: Module 6 > Gas Profiling with Foundry (#gas-profiling)
    function compareImplementations(address tokenA, address tokenB, address to, uint256 amount)
        external
        returns (address cheaper)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // ================================================================
    // TODO 3: sumPrices()
    // ================================================================
    // Compute the sum of all values in the `prices` storage array.
    // This is a gas optimization exercise: the NAIVE approach reads
    // prices.length from storage on every loop iteration (cold: 2100,
    // warm: 100 gas each). The OPTIMIZED approach caches it.
    //
    // Steps:
    //   1. Load the array length once and cache it:
    //      - Slot of prices.length is keccak256 of the slot number...
    //        Actually, for dynamic arrays, the length is at the slot
    //        itself. Data starts at keccak256(slot).
    //      - prices is at storage slot 0 (first state variable)
    //      - let len := sload(0x00)   ← cache the length
    //   2. Compute the data start slot:
    //      - mstore(0x00, 0x00)       ← prepare for keccak256
    //      - let dataSlot := keccak256(0x00, 0x20)
    //   3. Loop from 0 to len, loading each element:
    //      - for { let i := 0 } lt(i, len) { i := add(i, 1) }
    //      - let val := sload(add(dataSlot, i))
    //      - total := add(total, val)
    //   4. Assign: sum := total
    //
    // The key optimization: `len` is loaded ONCE from storage (step 1),
    // not re-read on every iteration. For an array of 100 elements,
    // this saves 99 × 100 = 9,900 gas (99 avoided warm SLOADs).
    //
    // Opcodes: sload, mstore, keccak256, add, lt, revert
    // See: Module 6 > When Assembly Is Worth It (#when-worth-it)
    function sumPrices() external view returns (uint256 sum) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

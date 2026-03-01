// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {GasExplorer} from
    "../../../../src/part4/module1/exercise2-gas-explorer/GasExplorer.sol";

/// @notice Tests for the GasExplorer exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module1/exercise2-gas-explorer/GasExplorer.sol instead.
contract GasExplorerTest is Test {
    GasExplorer internal explorer;

    function setUp() public {
        explorer = new GasExplorer();
    }

    // =========================================================================
    // TODO 1 & 2: Cold vs Warm SLOAD
    // =========================================================================

    function test_SloadCold_IsExpensive() public view {
        uint256 coldGas = explorer.measureSloadCold();
        // Cold SLOAD costs 2100 gas. With gas() opcode overhead, we expect
        // the measurement to be in the ballpark of 2100. We give a generous
        // range to account for overhead.
        assertTrue(coldGas > 2000, "Cold SLOAD should cost > 2000 gas");
        assertTrue(coldGas < 3000, "Cold SLOAD measurement should be < 3000 (sanity check)");
    }

    function test_SloadWarm_IsCheap() public view {
        uint256 warmGas = explorer.measureSloadWarm();
        // Warm SLOAD costs 100 gas. With overhead, expect roughly 100-200.
        assertTrue(warmGas > 50, "Warm SLOAD should cost > 50 gas");
        assertTrue(warmGas < 300, "Warm SLOAD should cost < 300 gas");
    }

    function test_SloadWarm_IsConsistentlyLow() public view {
        // Measure warm SLOAD multiple times — should be consistently low
        uint256 warmGas1 = explorer.measureSloadWarm();
        uint256 warmGas2 = explorer.measureSloadWarm();
        // Both measurements should be in a similar range
        assertTrue(warmGas1 < 300 && warmGas2 < 300, "Warm SLOAD should consistently be < 300 gas");
    }

    function test_ColdSload_MoreExpensive_ThanWarm() public view {
        uint256 coldGas = explorer.measureSloadCold();
        uint256 warmGas = explorer.measureSloadWarm();
        assertTrue(
            coldGas > warmGas * 5,
            "Cold SLOAD should be at least 5x more expensive than warm"
        );
    }

    // =========================================================================
    // TODO 3 & 4: Checked vs Assembly Addition
    // =========================================================================

    function test_AddChecked_Correctness() public view {
        assertEq(explorer.addChecked(3, 5), 8, "Checked: 3 + 5 = 8");
        assertEq(explorer.addChecked(0, 0), 0, "Checked: 0 + 0 = 0");
    }

    function test_AddChecked_RevertsOnOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        explorer.addChecked(type(uint256).max, 1);
    }

    function test_AddAssembly_Correctness() public view {
        assertEq(explorer.addAssembly(3, 5), 8, "Assembly: 3 + 5 = 8");
        assertEq(explorer.addAssembly(0, 0), 0, "Assembly: 0 + 0 = 0");
    }

    function test_AddAssembly_WrapsOnOverflow() public view {
        // Assembly add wraps, doesn't revert
        assertEq(
            explorer.addAssembly(type(uint256).max, 1),
            0,
            "Assembly add should wrap to 0"
        );
    }

    function test_AddAssembly_CheaperThanChecked() public {
        // Measure gas for both versions
        uint256 gasBefore = gasleft();
        explorer.addChecked(100, 200);
        uint256 checkedGas = gasBefore - gasleft();

        gasBefore = gasleft();
        explorer.addAssembly(100, 200);
        uint256 assemblyGas = gasBefore - gasleft();

        assertTrue(
            assemblyGas < checkedGas,
            "Assembly addition should use less gas than checked addition"
        );
    }

    function testFuzz_AddCheckedVsAssembly_SameResult(uint128 a, uint128 b) public view {
        // For values that don't overflow, both should return the same result
        assertEq(
            explorer.addChecked(uint256(a), uint256(b)),
            explorer.addAssembly(uint256(a), uint256(b)),
            "Checked and assembly should agree for non-overflowing inputs"
        );
    }

    // =========================================================================
    // TODO 5 & 6: Memory vs Storage Write
    // =========================================================================

    function test_MemoryWrite_IsCheap() public view {
        uint256 memGas = explorer.measureMemoryWrite(42);
        // mstore costs 3 gas base. With gas() overhead, expect roughly 3-50.
        assertTrue(memGas > 0, "Memory write should cost some gas");
        assertTrue(memGas < 100, "Memory write should cost < 100 gas");
    }

    function test_StorageWrite_IsExpensive() public {
        uint256 storageGas = explorer.measureStorageWrite(42);
        // sstore to a fresh slot costs 20000+ gas. We check for > 2000 to
        // account for warm updates (2900+) and overhead.
        assertTrue(storageGas > 2000, "Storage write should cost > 2000 gas");
    }

    function test_StorageWrite_MoreExpensive_ThanMemory() public {
        uint256 memGas = explorer.measureMemoryWrite(42);
        uint256 storageGas = explorer.measureStorageWrite(42);
        assertTrue(
            storageGas > memGas * 10,
            "Storage write should be at least 10x more expensive than memory write"
        );
    }
}

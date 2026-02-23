// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    TokenTransferUnoptimized,
    TokenTransferOptimized,
    StorageUnoptimized,
    StorageOptimized,
    CalldataUnoptimized,
    CalldataOptimized,
    LoopUnoptimized,
    LoopOptimized,
    ArithmeticUnoptimized,
    ArithmeticOptimized,
    ShortCircuitUnoptimized,
    ShortCircuitOptimized
} from "../../../src/part1/module5/GasOptimization.sol";

/// @notice Tests for gas optimization patterns.
/// @dev DO NOT MODIFY THIS FILE. Fill in GasOptimization.sol instead.
/// Run with: forge test --match-contract GasOptimizationTest --gas-report
/// Run with: forge snapshot --match-contract GasOptimizationTest
contract GasOptimizationTest is Test {
    // =============================================================
    //  Pattern 1: Custom Errors vs Require
    // =============================================================

    function test_TransferUnoptimized() public {
        TokenTransferUnoptimized token = new TokenTransferUnoptimized();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 100e18);

        assertEq(token.balances(bob), 100e18);
    }

    function test_TransferOptimized() public {
        TokenTransferOptimized token = new TokenTransferOptimized();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 100e18);

        assertEq(token.balances(bob), 100e18);
    }

    // =============================================================
    //  Pattern 2: Storage Packing
    // =============================================================

    function test_StorageUnoptimized() public {
        StorageUnoptimized s = new StorageUnoptimized();
        s.setValue(123, 456, 789, address(0x123));

        assertEq(s.value1(), 123);
        assertEq(s.value2(), 456);
        assertEq(s.value3(), 789);
        assertEq(s.owner(), address(0x123));
    }

    function test_StorageOptimized() public {
        StorageOptimized s = new StorageOptimized();
        s.setValue(123, 456, 789, address(0x123));

        assertEq(s.value1(), 123);
        assertEq(s.value2(), 456);
        assertEq(s.value3(), 789);
        assertEq(s.owner(), address(0x123));
    }

    // =============================================================
    //  Pattern 3: Calldata vs Memory
    // =============================================================

    function test_CalldataUnoptimized() public {
        CalldataUnoptimized c = new CalldataUnoptimized();
        uint256[] memory data = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            data[i] = i;
        }

        uint256 sum = c.processArray(data);
        assertEq(sum, 4950); // Sum of 0..99
    }

    function test_CalldataOptimized() public {
        CalldataOptimized c = new CalldataOptimized();
        uint256[] memory data = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            data[i] = i;
        }

        uint256 sum = c.processArray(data);
        assertEq(sum, 4950);
    }

    // =============================================================
    //  Pattern 4: Loop Optimization
    // =============================================================

    function test_LoopUnoptimized() public {
        LoopUnoptimized l = new LoopUnoptimized();
        uint256[] memory newValues = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            newValues[i] = i * 10;
        }

        l.addValues(newValues);
        uint256 sum = l.sumArray();

        assertEq(sum, 450); // Sum of 0,10,20,...,90
    }

    function test_LoopOptimized() public {
        LoopOptimized l = new LoopOptimized();
        uint256[] memory newValues = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            newValues[i] = i * 10;
        }

        l.addValues(newValues);
        uint256 sum = l.sumArray();

        assertEq(sum, 450);
    }

    // =============================================================
    //  Pattern 5: Unchecked Arithmetic
    // =============================================================

    function test_ArithmeticUnoptimized() public {
        ArithmeticUnoptimized a = new ArithmeticUnoptimized();
        uint256 sum = a.calculateSum(100, 200, 300);
        assertEq(sum, 600);

        uint256 result = a.decrementCounter(10);
        assertEq(result, 9);
    }

    function test_ArithmeticOptimized() public {
        ArithmeticOptimized a = new ArithmeticOptimized();
        uint256 sum = a.calculateSum(100, 200, 300);
        assertEq(sum, 600);

        uint256 result = a.decrementCounter(10);
        assertEq(result, 9);
    }

    // =============================================================
    //  Pattern 6: Short-Circuiting
    // =============================================================

    function test_ShortCircuitUnoptimized() public {
        ShortCircuitUnoptimized s = new ShortCircuitUnoptimized();
        address alice = makeAddr("alice");

        // Should return false (balance too low), but reads storage first
        bool canAccess = s.canAccess(alice, 50e18);
        assertFalse(canAccess);
    }

    function test_ShortCircuitOptimized() public {
        ShortCircuitOptimized s = new ShortCircuitOptimized();
        address alice = makeAddr("alice");

        // Should return false (balance too low) without reading storage
        bool canAccess = s.canAccess(alice, 50e18);
        assertFalse(canAccess);
    }

    // =============================================================
    //  Gas Comparison Tests
    // =============================================================

    function test_GasComparison_Errors() public {
        TokenTransferUnoptimized unopt = new TokenTransferUnoptimized();
        TokenTransferOptimized opt = new TokenTransferOptimized();

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        unopt.mint(alice, 1000e18);
        opt.mint(alice, 1000e18);

        // Measure unoptimized
        vm.prank(alice);
        uint256 gasStart = gasleft();
        unopt.transfer(bob, 100e18);
        uint256 gasUnopt = gasStart - gasleft();

        // Measure optimized
        vm.prank(alice);
        gasStart = gasleft();
        opt.transfer(bob, 100e18);
        uint256 gasOpt = gasStart - gasleft();

        console.log("Custom Errors vs Require:");
        console.log("  Unoptimized gas:", gasUnopt);
        console.log("  Optimized gas:  ", gasOpt);
        console.log("  Gas saved:      ", gasUnopt - gasOpt);

        // Optimized should use less gas
        assertLt(gasOpt, gasUnopt, "Optimized should use less gas");
    }

    function test_GasComparison_Storage() public {
        StorageUnoptimized unopt = new StorageUnoptimized();
        StorageOptimized opt = new StorageOptimized();

        // Measure unoptimized
        uint256 gasStart = gasleft();
        unopt.setValue(123, 456, 789, address(0x123));
        uint256 gasUnopt = gasStart - gasleft();

        // Measure optimized
        gasStart = gasleft();
        opt.setValue(123, 456, 789, address(0x123));
        uint256 gasOpt = gasStart - gasleft();

        console.log("Storage Packing:");
        console.log("  Unoptimized gas:", gasUnopt);
        console.log("  Optimized gas:  ", gasOpt);
        console.log("  Gas saved:      ", gasUnopt - gasOpt);

        assertLt(gasOpt, gasUnopt, "Optimized should use less gas");
    }
}

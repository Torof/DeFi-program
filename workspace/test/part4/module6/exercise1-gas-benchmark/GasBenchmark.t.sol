// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for GasBenchmark.
/// Your task is to implement the contract in GasBenchmark.sol so all tests pass.

import "forge-std/Test.sol";
import {GasBenchmark} from "../../../../src/part4/module6/exercise1-gas-benchmark/GasBenchmark.sol";
import {NaiveToken} from "../../../../src/part4/module6/mocks/NaiveToken.sol";
import {OptimizedToken} from "../../../../src/part4/module6/mocks/OptimizedToken.sol";

contract GasBenchmarkTest is Test {
    GasBenchmark internal bench;
    NaiveToken internal naive;
    OptimizedToken internal optimized;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        bench = new GasBenchmark();
        naive = new NaiveToken();
        optimized = new OptimizedToken();

        // Transfer tokens to the benchmark contract so it can call transfer().
        // This also warms the storage slots for fair comparison.
        naive.transfer(address(bench), 1_000_000 ether);
        optimized.transfer(address(bench), 1_000_000 ether);
    }

    // =========================================================================
    // TODO 1: measureTransferGas
    // =========================================================================

    function test_MeasureTransferGas_returnsNonZeroCost() public {
        uint256 gasUsed = bench.measureTransferGas(address(naive), alice, 100);

        assertGt(gasUsed, 0, "Gas measurement should be non-zero");
    }

    function test_MeasureTransferGas_transferActuallyHappens() public {
        bench.measureTransferGas(address(naive), alice, 500);

        assertEq(
            naive.balanceOf(alice),
            500,
            "Token transfer should actually execute"
        );
    }

    function test_MeasureTransferGas_costIsReasonable() public {
        // A warm ERC-20 transfer costs roughly 5,000–30,000 gas.
        // Our measurement includes the CALL overhead but not much else.
        uint256 gasUsed = bench.measureTransferGas(address(naive), alice, 100);

        assertGt(gasUsed, 2_000, "Gas should be at least 2,000 (warm transfer)");
        assertLt(gasUsed, 100_000, "Gas should be under 100,000 (no cold access)");
    }

    function test_MeasureTransferGas_revertsOnFailedCall() public {
        // Calling transfer on an EOA (no code) should fail → MeasurementFailed()
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x569e9815)));
        bench.measureTransferGas(alice, bob, 100);
    }

    function test_MeasureTransferGas_worksWithOptimizedToken() public {
        uint256 gasUsed = bench.measureTransferGas(address(optimized), alice, 100);

        assertGt(gasUsed, 0, "Optimized token measurement should be non-zero");
        assertEq(
            optimized.balanceOf(alice),
            100,
            "Optimized token transfer should execute"
        );
    }

    // =========================================================================
    // TODO 2: compareImplementations
    // =========================================================================

    function test_CompareImplementations_returnsAnAddress() public {
        address cheaper = bench.compareImplementations(
            address(naive), address(optimized), alice, 100
        );

        // Must be one of the two tokens
        assertTrue(
            cheaper == address(naive) || cheaper == address(optimized),
            "Cheaper must be one of the two tokens"
        );
    }

    function test_CompareImplementations_optimizedIsCheaper() public {
        // OptimizedToken uses custom errors + unchecked math → should be cheaper.
        address cheaper = bench.compareImplementations(
            address(naive), address(optimized), alice, 100
        );

        assertEq(
            cheaper,
            address(optimized),
            "OptimizedToken should be cheaper than NaiveToken"
        );
    }

    function test_CompareImplementations_orderDoesNotMatter() public {
        // Swapping the argument order should still identify the same winner.
        address cheaperAB = bench.compareImplementations(
            address(naive), address(optimized), alice, 50
        );
        address cheaperBA = bench.compareImplementations(
            address(optimized), address(naive), bob, 50
        );

        assertEq(
            cheaperAB,
            cheaperBA,
            "The cheaper token should be the same regardless of argument order"
        );
    }

    function test_CompareImplementations_bothTransfersExecute() public {
        bench.compareImplementations(
            address(naive), address(optimized), alice, 200
        );

        assertEq(
            naive.balanceOf(alice),
            200,
            "NaiveToken transfer should have executed"
        );
        assertEq(
            optimized.balanceOf(alice),
            200,
            "OptimizedToken transfer should have executed"
        );
    }

    function test_CompareImplementations_revertsOnFailedCall() public {
        // If tokenA is an EOA (no code), the call fails → MeasurementFailed()
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x569e9815)));
        bench.compareImplementations(alice, address(optimized), bob, 100);
    }

    // =========================================================================
    // TODO 3: sumPrices
    // =========================================================================

    function test_SumPrices_emptyArray() public view {
        uint256 sum = bench.sumPrices();
        assertEq(sum, 0, "Empty array should return 0");
    }

    function test_SumPrices_singleElement() public {
        bench.pushPrice(42);

        uint256 sum = bench.sumPrices();
        assertEq(sum, 42, "Single-element array should return that element");
    }

    function test_SumPrices_multipleElements() public {
        bench.pushPrice(100);
        bench.pushPrice(200);
        bench.pushPrice(300);

        uint256 sum = bench.sumPrices();
        assertEq(sum, 600, "Sum of [100, 200, 300] should be 600");
    }

    function test_SumPrices_tenElements() public {
        // Push 1..10 → sum = 55
        for (uint256 i = 1; i <= 10; i++) {
            bench.pushPrice(i);
        }

        uint256 sum = bench.sumPrices();
        assertEq(sum, 55, "Sum of 1..10 should be 55");
    }

    function test_SumPrices_largeValues() public {
        // Test with values that don't overflow
        bench.pushPrice(type(uint128).max);
        bench.pushPrice(type(uint128).max);

        uint256 sum = bench.sumPrices();
        assertEq(
            sum,
            uint256(type(uint128).max) * 2,
            "Should handle large values correctly"
        );
    }

    function testFuzz_SumPrices_matchesSoliditySum(uint256[5] memory vals) public {
        uint256 expected;
        for (uint256 i = 0; i < 5; i++) {
            // Bound each value to prevent overflow in the sum
            vals[i] = bound(vals[i], 0, type(uint256).max / 5);
            bench.pushPrice(vals[i]);
            expected += vals[i];
        }

        uint256 sum = bench.sumPrices();
        assertEq(sum, expected, "Assembly sum should match Solidity sum");
    }
}

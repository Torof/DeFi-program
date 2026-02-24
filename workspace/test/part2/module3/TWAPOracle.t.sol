// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the TWAPOracle
//  exercise. Implement TWAPOracle.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    TWAPOracle,
    InsufficientHistory,
    WindowTooShort,
    ObservationTooOld,
    ZeroPrice
} from "../../../src/part2/module3/TWAPOracle.sol";

contract TWAPOracleTest is Test {
    TWAPOracle oracle;

    uint256 constant STABLE_PRICE = 3000e18; // ETH at $3,000
    uint256 constant MIN_WINDOW = 300;       // 5 minutes

    function setUp() public {
        oracle = new TWAPOracle();
        // Start at a reasonable timestamp (not 0)
        vm.warp(1_700_000_000);
    }

    // =========================================================
    //  Helper: Record observations at regular intervals
    // =========================================================

    /// @dev Records n observations at `interval` seconds apart, all at the same price.
    function _recordStable(uint256 n, uint256 interval) internal {
        for (uint256 i = 0; i < n; i++) {
            oracle.recordObservation(STABLE_PRICE);
            if (i < n - 1) vm.warp(block.timestamp + interval);
        }
    }

    /// @dev Records a single observation and advances time.
    function _recordAndAdvance(uint256 price, uint256 interval) internal {
        oracle.recordObservation(price);
        vm.warp(block.timestamp + interval);
    }

    // =========================================================
    //  Recording Observations
    // =========================================================

    function test_FirstObservation_RecordsCorrectly() public {
        oracle.recordObservation(STABLE_PRICE);

        assertEq(oracle.observationCount(), 1, "Count should be 1 after first observation");
        assertEq(oracle.lastPrice(), STABLE_PRICE, "lastPrice should match recorded price");

        // First observation has cumulativePrice = 0
        (uint256 cumulative, uint32 ts) = oracle.observations(0);
        assertEq(cumulative, 0, "First observation cumulative should be 0");
        assertEq(ts, uint32(block.timestamp), "Timestamp should match block.timestamp");
    }

    function test_MultipleObservations_CumulativeGrows() public {
        // Record at price 100 for 60 seconds, then price 200
        _recordAndAdvance(100, 60);
        oracle.recordObservation(200);

        // Second observation cumulative = 0 + 100 * 60 = 6000
        (uint256 cumulative,) = oracle.observations(1);
        assertEq(cumulative, 6000, "Cumulative should be lastPrice * timeElapsed");
    }

    // =========================================================
    //  TWAP Computation
    // =========================================================

    function test_StablePrice_TWAPEqualsSpot() public {
        // Record same price 10 times, 60s apart (total 540s of history)
        // Then advance to make total window >= MIN_WINDOW
        for (uint256 i = 0; i < 10; i++) {
            oracle.recordObservation(STABLE_PRICE);
            vm.warp(block.timestamp + 60);
        }

        // Consult over 5 minutes (300s)
        uint256 twap = oracle.consult(MIN_WINDOW);

        assertEq(twap, STABLE_PRICE, "TWAP of constant price should equal that price");
    }

    function test_ChangingPrice_TWAPLags() public {
        // Phase 1: Price = 1000 for 300 seconds (5 observations, 60s apart)
        for (uint256 i = 0; i < 5; i++) {
            oracle.recordObservation(1000);
            vm.warp(block.timestamp + 60);
        }

        // Phase 2: Price jumps to 2000 for 300 seconds
        for (uint256 i = 0; i < 5; i++) {
            oracle.recordObservation(2000);
            vm.warp(block.timestamp + 60);
        }

        // Record one more to capture the last interval
        oracle.recordObservation(2000);

        // Consult over the full 600s window
        uint256 twap = oracle.consult(600);

        // TWAP should be between 1000 and 2000 (lagging behind the jump)
        assertGt(twap, 1000, "TWAP should be above old price after price increase");
        assertLt(twap, 2000, "TWAP should lag behind the new spot price");
    }

    function test_TWAPResistsSingleSpike() public {
        // Record 9 stable observations at 3000, one spike at 30000 (10x)
        for (uint256 i = 0; i < 9; i++) {
            _recordAndAdvance(STABLE_PRICE, 60);
        }
        // One extreme spike
        _recordAndAdvance(30000e18, 60);
        // One more stable to close the interval
        oracle.recordObservation(STABLE_PRICE);

        // TWAP over the full window (600s)
        uint256 twap = oracle.consult(600);

        // The spike lasted only 60s out of 600s (~10%), and was 10x the normal price.
        // TWAP should be well below the spike price.
        // Approximate: (3000 * 540 + 30000 * 60) / 600 = (1620000 + 1800000) / 600 = 5700
        // So TWAP ~ 5700e18, much closer to 3000e18 than 30000e18
        assertLt(twap, 10000e18, "Single spike should NOT dominate the TWAP");
        assertGt(twap, STABLE_PRICE, "TWAP should be slightly above stable due to spike");
    }

    function test_ConsultDifferentWindows() public {
        // Phase 1: Price = 1000 for 600s
        for (uint256 i = 0; i < 10; i++) {
            _recordAndAdvance(1000, 60);
        }
        // Phase 2: Price = 3000 for 300s
        for (uint256 i = 0; i < 5; i++) {
            _recordAndAdvance(3000, 60);
        }
        // Record final observation
        oracle.recordObservation(3000);

        // Short window (300s) — mostly captures the 3000 phase
        uint256 shortTwap = oracle.consult(MIN_WINDOW);

        // Long window (600s) — captures both phases
        uint256 longTwap = oracle.consult(600);

        // Short TWAP should be closer to 3000 than long TWAP
        assertGt(shortTwap, longTwap, "Shorter window should reflect recent (higher) prices more");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_WindowTooShort_Reverts() public {
        _recordStable(5, 60);

        vm.expectRevert(WindowTooShort.selector);
        oracle.consult(MIN_WINDOW - 1);
    }

    function test_InsufficientHistory_ZeroObservations_Reverts() public {
        vm.expectRevert(InsufficientHistory.selector);
        oracle.consult(MIN_WINDOW);
    }

    function test_InsufficientHistory_OneObservation_Reverts() public {
        oracle.recordObservation(STABLE_PRICE);

        vm.expectRevert(InsufficientHistory.selector);
        oracle.consult(MIN_WINDOW);
    }

    function test_ZeroPrice_Reverts() public {
        vm.expectRevert(ZeroPrice.selector);
        oracle.recordObservation(0);
    }

    function test_BufferWraparound() public {
        // Record more than MAX_OBSERVATIONS (100)
        // Use 60s intervals = 6000s of history
        for (uint256 i = 0; i < 110; i++) {
            oracle.recordObservation(STABLE_PRICE);
            vm.warp(block.timestamp + 60);
        }
        oracle.recordObservation(STABLE_PRICE);

        // observationCount should be capped at MAX_OBSERVATIONS
        assertEq(oracle.observationCount(), 100, "Count should cap at MAX_OBSERVATIONS");

        // TWAP should still work correctly after wraparound
        uint256 twap = oracle.consult(MIN_WINDOW);
        assertEq(twap, STABLE_PRICE, "TWAP should be correct after buffer wraps around");
    }

    // =========================================================
    //  Deviation
    // =========================================================

    function test_DeviationCalculation_KnownValues() public {
        // Fill with stable price
        for (uint256 i = 0; i < 10; i++) {
            _recordAndAdvance(1000, 60);
        }
        oracle.recordObservation(1000);

        // Spot = 1100, TWAP = 1000 → deviation = 10% = 1000 bps
        uint256 deviation = oracle.getDeviation(1100, MIN_WINDOW);
        assertEq(deviation, 1000, "10% deviation should be 1000 bps");
    }

    function test_ZeroDeviation() public {
        for (uint256 i = 0; i < 10; i++) {
            _recordAndAdvance(STABLE_PRICE, 60);
        }
        oracle.recordObservation(STABLE_PRICE);

        uint256 deviation = oracle.getDeviation(STABLE_PRICE, MIN_WINDOW);
        assertEq(deviation, 0, "Same spot and TWAP should give zero deviation");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_CumulativeMonotonicallyIncreases(uint256 price1, uint256 price2) public {
        price1 = bound(price1, 1, 1e36);
        price2 = bound(price2, 1, 1e36);

        _recordAndAdvance(price1, 60);
        oracle.recordObservation(price2);

        (uint256 cum0,) = oracle.observations(0);
        (uint256 cum1,) = oracle.observations(1);

        assertGe(cum1, cum0, "INVARIANT: cumulative price must never decrease");
    }
}

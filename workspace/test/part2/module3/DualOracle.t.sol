// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the DualOracle
//  exercise. Implement DualOracle.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {MockAggregatorV3} from "../../../src/part2/module3/mocks/MockAggregatorV3.sol";
import {TWAPOracle} from "../../../src/part2/module3/TWAPOracle.sol";
import {
    DualOracle,
    NoGoodPrice,
    InvalidConfiguration
} from "../../../src/part2/module3/DualOracle.sol";

contract DualOracleTest is Test {
    DualOracle dualOracle;
    MockAggregatorV3 chainlinkFeed;
    TWAPOracle twapOracle;

    uint256 constant MAX_STALENESS = 4500; // 1h15m
    uint256 constant TWAP_WINDOW = 300;    // 5 min
    uint256 constant MAX_DEVIATION = 500;  // 5% in bps

    // Prices in 18 decimals (the internal format)
    uint256 constant ETH_PRICE = 3000e18;

    // Chainlink price in 8 decimals (raw feed format)
    int256 constant CL_ETH_PRICE = 3000_00000000;

    function setUp() public {
        vm.warp(1_700_000_000);

        // Deploy Chainlink mock (8 decimals, like real ETH/USD)
        chainlinkFeed = new MockAggregatorV3(CL_ETH_PRICE, 8);

        // Deploy TWAP oracle and seed it with observations
        twapOracle = new TWAPOracle();
        _seedTWAP(ETH_PRICE, 10, 60); // 10 observations at $3000, 60s apart

        // Deploy dual oracle
        dualOracle = new DualOracle(
            address(chainlinkFeed),
            address(twapOracle),
            MAX_STALENESS,
            TWAP_WINDOW
        );
    }

    // =========================================================
    //  Helpers
    // =========================================================

    /// @dev Seeds the TWAP oracle with n observations at the given price.
    function _seedTWAP(uint256 price, uint256 n, uint256 interval) internal {
        for (uint256 i = 0; i < n; i++) {
            twapOracle.recordObservation(price);
            vm.warp(block.timestamp + interval);
        }
        // Record one more to finalize the last interval
        twapOracle.recordObservation(price);
    }

    /// @dev Makes the Chainlink feed stale by warping time.
    function _makeChainlinkStale() internal {
        vm.warp(block.timestamp + MAX_STALENESS + 1);
    }

    /// @dev Makes the TWAP oracle unavailable by deploying a fresh one (no observations).
    function _breakTWAP() internal {
        TWAPOracle freshTwap = new TWAPOracle();
        // Re-deploy dual oracle with the broken TWAP
        dualOracle = new DualOracle(
            address(chainlinkFeed),
            address(freshTwap),
            MAX_STALENESS,
            TWAP_WINDOW
        );
    }

    // =========================================================
    //  Normal Operation
    // =========================================================

    function test_NormalOperation_UsesPrimary() public {
        // Both oracles healthy, prices agree → should return primary price
        uint256 price = dualOracle.getPrice();

        assertApproxEqRel(
            price,
            ETH_PRICE,
            1e15, // 0.1% tolerance
            "Normal operation should return the primary (Chainlink) price"
        );
    }

    function test_InitialStatus_IsPrimary() public view {
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_PRIMARY),
            "Initial status should be USING_PRIMARY"
        );
    }

    function test_LastGoodPrice_UpdatedOnSuccess() public {
        dualOracle.getPrice();

        assertApproxEqRel(
            dualOracle.lastGoodPrice(),
            ETH_PRICE,
            1e15,
            "lastGoodPrice should be updated after successful read"
        );
    }

    // =========================================================
    //  Primary Failure → Fallback to Secondary
    // =========================================================

    function test_PrimaryStale_FallsBackToSecondary() public {
        // First call to establish lastGoodPrice
        dualOracle.getPrice();

        // Make Chainlink stale
        _makeChainlinkStale();

        // Feed fresh TWAP observation at current time
        twapOracle.recordObservation(ETH_PRICE);

        uint256 price = dualOracle.getPrice();

        assertApproxEqRel(
            price,
            ETH_PRICE,
            1e15,
            "Should fall back to TWAP when Chainlink is stale"
        );
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_SECONDARY),
            "Status should be USING_SECONDARY after primary failure"
        );
    }

    function test_PrimaryNegative_FallsBackToSecondary() public {
        // Chainlink returns negative price (invalid)
        chainlinkFeed.updateAnswer(-1);

        // Fresh TWAP
        twapOracle.recordObservation(ETH_PRICE);

        uint256 price = dualOracle.getPrice();

        assertApproxEqRel(
            price,
            ETH_PRICE,
            1e15,
            "Should fall back to TWAP when Chainlink returns negative price"
        );
    }

    // =========================================================
    //  Deviation Detection
    // =========================================================

    function test_DeviationDetected_SwitchesToSecondary() public {
        // Set Chainlink to $3000, but TWAP to $2800 (6.67% deviation > 5% threshold)
        // Need to seed a separate TWAP with different price
        TWAPOracle divergentTwap = new TWAPOracle();
        uint256 twapPrice = 2800e18;
        vm.warp(1_700_000_000); // reset time
        for (uint256 i = 0; i < 10; i++) {
            divergentTwap.recordObservation(twapPrice);
            vm.warp(block.timestamp + 60);
        }
        divergentTwap.recordObservation(twapPrice);

        // Redeploy dual oracle with divergent TWAP
        // Need fresh Chainlink too (at current timestamp)
        chainlinkFeed.updateAnswer(CL_ETH_PRICE);
        DualOracle divergentOracle = new DualOracle(
            address(chainlinkFeed),
            address(divergentTwap),
            MAX_STALENESS,
            TWAP_WINDOW
        );

        // Expect DeviationDetected event
        vm.expectEmit(false, false, false, true);
        emit DualOracle.DeviationDetected(3000e18, twapPrice, 666); // ~6.66% = 666 bps

        uint256 price = divergentOracle.getPrice();

        // Should use secondary (TWAP) when deviation detected
        assertApproxEqRel(
            price,
            twapPrice,
            1e15,
            "Should switch to secondary when prices deviate beyond threshold"
        );
        assertEq(
            uint256(divergentOracle.status()),
            uint256(DualOracle.OracleStatus.USING_SECONDARY),
            "Status should be USING_SECONDARY after deviation detected"
        );
    }

    function test_DeviationWithinBounds_UsesPrimary() public {
        // Set TWAP to $3100 (3.23% deviation < 5% threshold)
        TWAPOracle closeTwap = new TWAPOracle();
        uint256 twapPrice = 3100e18;
        vm.warp(1_700_000_000);
        for (uint256 i = 0; i < 10; i++) {
            closeTwap.recordObservation(twapPrice);
            vm.warp(block.timestamp + 60);
        }
        closeTwap.recordObservation(twapPrice);

        chainlinkFeed.updateAnswer(CL_ETH_PRICE);
        DualOracle closeOracle = new DualOracle(
            address(chainlinkFeed),
            address(closeTwap),
            MAX_STALENESS,
            TWAP_WINDOW
        );

        uint256 price = closeOracle.getPrice();

        // Should use primary because deviation is within bounds
        assertApproxEqRel(
            price,
            ETH_PRICE,
            1e15,
            "Should use primary when prices are within deviation bounds"
        );
        assertEq(
            uint256(closeOracle.status()),
            uint256(DualOracle.OracleStatus.USING_PRIMARY),
            "Status should remain USING_PRIMARY when deviation is acceptable"
        );
    }

    function test_DeviationEvent_EmitsCorrectly() public {
        // Set up divergent prices and verify event data
        TWAPOracle divergentTwap = new TWAPOracle();
        uint256 twapPrice = 2700e18; // 10% below Chainlink
        vm.warp(1_700_000_000);
        for (uint256 i = 0; i < 10; i++) {
            divergentTwap.recordObservation(twapPrice);
            vm.warp(block.timestamp + 60);
        }
        divergentTwap.recordObservation(twapPrice);

        chainlinkFeed.updateAnswer(CL_ETH_PRICE);
        DualOracle divergentOracle = new DualOracle(
            address(chainlinkFeed),
            address(divergentTwap),
            MAX_STALENESS,
            TWAP_WINDOW
        );

        // Should emit DeviationDetected with correct values
        // Deviation: |3000 - 2700| / 3000 = 300/3000 = 10% = 1000 bps
        vm.expectEmit(false, false, false, true);
        emit DualOracle.DeviationDetected(3000e18, twapPrice, 1000);

        divergentOracle.getPrice();
    }

    // =========================================================
    //  Recovery
    // =========================================================

    function test_PrimaryRecovers_SwitchesBack() public {
        // Step 1: Make primary fail → switches to secondary
        dualOracle.getPrice(); // establish baseline
        _makeChainlinkStale();
        twapOracle.recordObservation(ETH_PRICE);
        dualOracle.getPrice(); // now USING_SECONDARY

        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_SECONDARY)
        );

        // Step 2: Primary recovers (fresh update)
        chainlinkFeed.updateAnswer(CL_ETH_PRICE);
        twapOracle.recordObservation(ETH_PRICE);

        dualOracle.getPrice();

        // Should switch back to USING_PRIMARY
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_PRIMARY),
            "Should recover to USING_PRIMARY when Chainlink comes back with agreeing price"
        );
    }

    function test_RecoveryRequiresDeviationCheck() public {
        // Primary fails → secondary. Primary recovers but with different price.
        dualOracle.getPrice();
        _makeChainlinkStale();
        twapOracle.recordObservation(ETH_PRICE);
        dualOracle.getPrice(); // USING_SECONDARY

        // Primary recovers but at $2700 (10% off from TWAP's $3000)
        chainlinkFeed.updateAnswer(2700_00000000);
        twapOracle.recordObservation(ETH_PRICE);

        dualOracle.getPrice();

        // Should NOT switch back because prices disagree
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_SECONDARY),
            "Should NOT recover to primary if prices still disagree"
        );
    }

    // =========================================================
    //  Both Fail
    // =========================================================

    function test_BothFail_UsesLastGoodPrice() public {
        // Step 1: Establish lastGoodPrice with a successful call
        dualOracle.getPrice();
        uint256 lastGood = dualOracle.lastGoodPrice();
        assertGt(lastGood, 0, "lastGoodPrice should be set");

        // Step 2: Break BOTH oracles on the SAME DualOracle instance
        // Break primary: make Chainlink stale
        _makeChainlinkStale();

        // Break secondary: overwrite the TWAP circular buffer with 101 observations
        // 1 second apart. This gives only ~100s of history, less than MIN_WINDOW (300s),
        // so consult(300) will fail with ObservationTooOld.
        for (uint256 i = 0; i < 101; i++) {
            twapOracle.recordObservation(ETH_PRICE);
            vm.warp(block.timestamp + 1);
        }

        // Step 3: Both fail → should return lastGoodPrice, emit event, go BOTH_UNTRUSTED
        vm.expectEmit(false, false, false, true);
        emit DualOracle.FallbackToLastGoodPrice(lastGood);

        uint256 price = dualOracle.getPrice();

        assertEq(price, lastGood, "Should return lastGoodPrice when both oracles fail");
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.BOTH_UNTRUSTED),
            "Status should be BOTH_UNTRUSTED when both fail"
        );
    }

    function test_BothFail_NoLastGoodPrice_Reverts() public {
        // Fresh oracle with broken feeds, no previous successful call
        chainlinkFeed.setUpdatedAt(0); // broken
        TWAPOracle emptyTwap = new TWAPOracle(); // no observations

        DualOracle freshOracle = new DualOracle(
            address(chainlinkFeed),
            address(emptyTwap),
            MAX_STALENESS,
            TWAP_WINDOW
        );

        vm.expectRevert(NoGoodPrice.selector);
        freshOracle.getPrice();
    }

    function test_LastGoodPrice_NotUpdatedOnFailure() public {
        // Establish lastGoodPrice
        uint256 price = dualOracle.getPrice();
        uint256 lastGood = dualOracle.lastGoodPrice();
        assertGt(lastGood, 0);

        // Make primary fail, secondary still works
        _makeChainlinkStale();
        twapOracle.recordObservation(ETH_PRICE);

        // This should use secondary and update lastGoodPrice
        dualOracle.getPrice();
        uint256 afterSecondary = dualOracle.lastGoodPrice();
        assertGt(afterSecondary, 0, "lastGoodPrice should still be set after secondary fallback");
    }

    // =========================================================
    //  State Transitions — Full Cycle
    // =========================================================

    function test_StatusTransitions_FullCycle() public {
        // ── Stage 1: USING_PRIMARY (normal operation) ──
        assertEq(uint256(dualOracle.status()), uint256(DualOracle.OracleStatus.USING_PRIMARY));

        dualOracle.getPrice();
        assertEq(uint256(dualOracle.status()), uint256(DualOracle.OracleStatus.USING_PRIMARY));

        // ── Stage 2: PRIMARY → SECONDARY (primary fails) ──
        _makeChainlinkStale();
        twapOracle.recordObservation(ETH_PRICE);
        dualOracle.getPrice();
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_SECONDARY),
            "Should transition to USING_SECONDARY when primary fails"
        );

        // ── Stage 3: SECONDARY → BOTH_UNTRUSTED (both fail) ──
        // Break TWAP by overwriting buffer with very short intervals (100s < MIN_WINDOW 300s)
        for (uint256 i = 0; i < 101; i++) {
            twapOracle.recordObservation(ETH_PRICE);
            vm.warp(block.timestamp + 1);
        }
        // Chainlink is still stale from earlier _makeChainlinkStale()
        dualOracle.getPrice();
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.BOTH_UNTRUSTED),
            "Should transition to BOTH_UNTRUSTED when both oracles fail"
        );

        // ── Stage 4: BOTH_UNTRUSTED → USING_PRIMARY (full recovery) ──
        // Restore Chainlink with fresh data
        chainlinkFeed.updateAnswer(CL_ETH_PRICE);
        // Re-seed TWAP with enough history for a valid window
        for (uint256 i = 0; i < 10; i++) {
            twapOracle.recordObservation(ETH_PRICE);
            vm.warp(block.timestamp + 60);
        }
        twapOracle.recordObservation(ETH_PRICE);

        dualOracle.getPrice();
        assertEq(
            uint256(dualOracle.status()),
            uint256(DualOracle.OracleStatus.USING_PRIMARY),
            "Should recover to USING_PRIMARY after full cycle"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_GetPrice_NeverRevertsWithLastGoodPrice(int256 clPrice, uint256 twapPrice) public {
        // Once lastGoodPrice is established, getPrice() should NEVER revert —
        // it always has a fallback. This is the core reliability guarantee.
        clPrice = bound(clPrice, -1_000_00000000, 1_000_000_00000000); // -$1k to $1M at 8 dec
        twapPrice = bound(twapPrice, 0, 1_000_000e18); // 0 to $1M at 18 dec

        // Establish lastGoodPrice first
        dualOracle.getPrice();
        assertGt(dualOracle.lastGoodPrice(), 0);

        // Now set arbitrary Chainlink price (could be negative, zero, or valid)
        chainlinkFeed.updateAnswer(clPrice);

        // Feed the TWAP with arbitrary price (could be 0 → ZeroPrice revert in record)
        if (twapPrice > 0) {
            twapOracle.recordObservation(twapPrice);
        }

        // getPrice should NEVER revert once lastGoodPrice exists
        uint256 price = dualOracle.getPrice();
        assertGt(price, 0, "INVARIANT: getPrice must always return a positive price when lastGoodPrice exists");
    }

    function test_InvalidConfiguration_Reverts() public {
        vm.expectRevert(InvalidConfiguration.selector);
        new DualOracle(address(0), address(twapOracle), MAX_STALENESS, TWAP_WINDOW);

        vm.expectRevert(InvalidConfiguration.selector);
        new DualOracle(address(chainlinkFeed), address(0), MAX_STALENESS, TWAP_WINDOW);
    }
}

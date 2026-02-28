// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the L2OracleConsumer
//  exercise. Implement L2OracleConsumer.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    L2OracleConsumer,
    SequencerDown,
    GracePeriodNotPassed,
    StalePrice,
    InvalidPrice
} from "../../../../src/part3/module7/exercise1-l2-oracle/L2OracleConsumer.sol";
import {MockSequencerFeed} from "../../../../src/part3/module7/mocks/MockSequencerFeed.sol";
import {MockPriceFeed} from "../../../../src/part3/module7/mocks/MockPriceFeed.sol";

contract L2OracleTest is Test {
    L2OracleConsumer public oracle;
    MockSequencerFeed public sequencerFeed;
    MockPriceFeed public priceFeed;

    uint256 constant GRACE_PERIOD = 1 hours;
    uint256 constant STALENESS_THRESHOLD = 1 hours;
    int256 constant ETH_PRICE = 2000e8; // $2,000 in 8 decimals

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp

        sequencerFeed = new MockSequencerFeed();
        // Sequencer has been up since well before grace period
        sequencerFeed.setStatus(false, block.timestamp - 2 hours);
        priceFeed = new MockPriceFeed(ETH_PRICE);

        oracle = new L2OracleConsumer(
            address(sequencerFeed),
            address(priceFeed),
            GRACE_PERIOD,
            STALENESS_THRESHOLD
        );
    }

    // =========================================================
    //  isSequencerUp (TODO 1)
    // =========================================================

    function test_isSequencerUp_returnsTrue_whenUp() public view {
        assertTrue(oracle.isSequencerUp(), "Sequencer should be up initially");
    }

    function test_isSequencerUp_returnsFalse_whenDown() public {
        sequencerFeed.setStatus(true, block.timestamp); // down
        assertFalse(oracle.isSequencerUp(), "Should detect sequencer is down");
    }

    function test_isSequencerUp_detectsRestart() public {
        // Go down
        sequencerFeed.setStatus(true, block.timestamp);
        assertFalse(oracle.isSequencerUp(), "Should be down");

        // Come back up
        vm.warp(block.timestamp + 10 minutes);
        sequencerFeed.setStatus(false, block.timestamp);
        assertTrue(oracle.isSequencerUp(), "Should detect restart");
    }

    // =========================================================
    //  isGracePeriodPassed (TODO 2)
    // =========================================================

    function test_isGracePeriodPassed_true_afterGracePeriod() public {
        // Sequencer started at setUp time, now well past grace period
        vm.warp(block.timestamp + 2 hours);
        assertTrue(oracle.isGracePeriodPassed(), "Grace period should have passed");
    }

    function test_isGracePeriodPassed_false_duringGracePeriod() public {
        // Simulate restart: sequencer comes back at current time
        sequencerFeed.setStatus(false, block.timestamp);

        // 30 minutes later (still within 1-hour grace period)
        vm.warp(block.timestamp + 30 minutes);
        assertFalse(oracle.isGracePeriodPassed(), "Should still be in grace period");
    }

    function test_isGracePeriodPassed_true_atExactBoundary() public {
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + GRACE_PERIOD);
        assertTrue(oracle.isGracePeriodPassed(), "Should pass at exact boundary");
    }

    function test_isGracePeriodPassed_afterDowntimeAndRestart() public {
        // Sequencer goes down
        sequencerFeed.setStatus(true, block.timestamp);
        vm.warp(block.timestamp + 2 hours);

        // Sequencer comes back up
        sequencerFeed.setStatus(false, block.timestamp);

        // Only 30 min since restart
        vm.warp(block.timestamp + 30 minutes);
        assertFalse(oracle.isGracePeriodPassed(), "Grace period should reset on restart");

        // 1 hour since restart
        vm.warp(block.timestamp + 30 minutes);
        assertTrue(oracle.isGracePeriodPassed(), "Grace period should pass after 1 hour");
    }

    // =========================================================
    //  getPrice (TODO 3)
    // =========================================================

    function test_getPrice_returnsPrice_whenAllSafe() public view {
        uint256 price = oracle.getPrice();
        assertEq(price, uint256(ETH_PRICE), "Should return current price");
    }

    function test_getPrice_revertsWhenSequencerDown() public {
        sequencerFeed.setStatus(true, block.timestamp);
        vm.expectRevert(SequencerDown.selector);
        oracle.getPrice();
    }

    function test_getPrice_revertsWhenGracePeriodNotPassed() public {
        // Restart sequencer just now
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + 10 minutes); // within grace period

        // Update price to be fresh
        priceFeed.setPrice(ETH_PRICE);

        vm.expectRevert(GracePeriodNotPassed.selector);
        oracle.getPrice();
    }

    function test_getPrice_revertsWhenPriceStale() public {
        // Make price stale (older than staleness threshold)
        vm.warp(block.timestamp + STALENESS_THRESHOLD + 1);

        vm.expectRevert(StalePrice.selector);
        oracle.getPrice();
    }

    function test_getPrice_revertsWhenPriceZero() public {
        priceFeed.setPrice(0);
        vm.expectRevert(InvalidPrice.selector);
        oracle.getPrice();
    }

    function test_getPrice_revertsWhenPriceNegative() public {
        priceFeed.setPrice(-1);
        vm.expectRevert(InvalidPrice.selector);
        oracle.getPrice();
    }

    function test_getPrice_acceptsFreshPrice() public {
        // Advance time but keep price fresh
        vm.warp(block.timestamp + STALENESS_THRESHOLD - 1);
        priceFeed.setPrice(2500e8);
        uint256 price = oracle.getPrice();
        assertEq(price, 2500e8, "Should accept fresh price at boundary");
    }

    function test_getPrice_acceptsAtExactStalenessThreshold() public {
        // At exact staleness boundary (<=), price should still be accepted
        vm.warp(block.timestamp + STALENESS_THRESHOLD);
        priceFeed.setPrice(2500e8);
        uint256 price = oracle.getPrice();
        assertEq(price, 2500e8, "Should accept price at exact staleness boundary");
    }

    // =========================================================
    //  isLiquidationAllowed (TODO 4)
    // =========================================================

    function test_isLiquidationAllowed_true_normalOperation() public view {
        assertTrue(oracle.isLiquidationAllowed(), "Should allow liquidation in normal state");
    }

    function test_isLiquidationAllowed_false_sequencerDown() public {
        sequencerFeed.setStatus(true, block.timestamp);
        assertFalse(oracle.isLiquidationAllowed(), "Should block liquidation when sequencer down");
    }

    function test_isLiquidationAllowed_false_duringGracePeriod() public {
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + 30 minutes);
        assertFalse(oracle.isLiquidationAllowed(), "Should block liquidation during grace period");
    }

    function test_isLiquidationAllowed_true_afterGracePeriod() public {
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + GRACE_PERIOD);
        assertTrue(oracle.isLiquidationAllowed(), "Should allow liquidation after grace period");
    }

    // =========================================================
    //  isBorrowAllowed (TODO 5)
    // =========================================================

    function test_isBorrowAllowed_true_normalOperation() public view {
        assertTrue(oracle.isBorrowAllowed(), "Should allow borrowing in normal state");
    }

    function test_isBorrowAllowed_false_sequencerDown() public {
        sequencerFeed.setStatus(true, block.timestamp);
        assertFalse(oracle.isBorrowAllowed(), "Should block borrowing when sequencer down");
    }

    function test_isBorrowAllowed_false_duringGracePeriod() public {
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + 30 minutes);
        assertFalse(oracle.isBorrowAllowed(), "Should block borrowing during grace period");
    }

    // =========================================================
    //  Integration: Full Downtime Scenario
    // =========================================================

    function test_integration_fullDowntimeScenario() public {
        // Phase 1: Normal operation
        assertTrue(oracle.isLiquidationAllowed(), "Phase 1: liquidation allowed");
        assertTrue(oracle.isBorrowAllowed(), "Phase 1: borrow allowed");
        uint256 price = oracle.getPrice();
        assertEq(price, uint256(ETH_PRICE), "Phase 1: price available");

        // Phase 2: Sequencer goes down
        sequencerFeed.setStatus(true, block.timestamp);
        assertFalse(oracle.isLiquidationAllowed(), "Phase 2: liquidation blocked");
        assertFalse(oracle.isBorrowAllowed(), "Phase 2: borrow blocked");
        vm.expectRevert(SequencerDown.selector);
        oracle.getPrice();

        // Phase 3: Sequencer restarts (grace period)
        vm.warp(block.timestamp + 30 minutes);
        sequencerFeed.setStatus(false, block.timestamp);
        priceFeed.setPrice(1800e8); // Price moved during downtime
        assertFalse(oracle.isLiquidationAllowed(), "Phase 3: liquidation still blocked (grace)");

        // Phase 4: Grace period passes
        vm.warp(block.timestamp + GRACE_PERIOD);
        priceFeed.setPrice(1800e8); // Keep price fresh
        assertTrue(oracle.isLiquidationAllowed(), "Phase 4: liquidation allowed again");
        assertTrue(oracle.isBorrowAllowed(), "Phase 4: borrow allowed again");
        price = oracle.getPrice();
        assertEq(price, 1800e8, "Phase 4: new price available");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_gracePeriod_exactBehavior(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 10 hours);

        // Restart sequencer now
        sequencerFeed.setStatus(false, block.timestamp);
        vm.warp(block.timestamp + elapsed);

        bool passed = oracle.isGracePeriodPassed();

        if (elapsed >= GRACE_PERIOD) {
            assertTrue(passed, "INVARIANT: should pass when elapsed >= gracePeriod");
        } else {
            assertFalse(passed, "INVARIANT: should not pass when elapsed < gracePeriod");
        }
    }
}

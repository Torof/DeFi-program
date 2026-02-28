// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE - it is the test suite for the FundingRateEngine exercise.
//  Implement FundingRateEngine.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    FundingRateEngine,
    ZeroSize,
    PositionAlreadyExists,
    NoPosition
} from "../../../../src/part3/module2/exercise1-funding-rate-engine/FundingRateEngine.sol";

contract FundingRateEngineTest is Test {
    FundingRateEngine public engine;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    // Constants matching the engine
    uint256 constant SKEW_SCALE = 100_000_000e8; // $100M
    uint256 constant SECONDS_PER_DAY = 86_400;
    uint256 constant WAD = 1e18;

    function setUp() public {
        // Start at a realistic timestamp
        vm.warp(1_700_000_000);
        engine = new FundingRateEngine();
    }

    // =========================================================
    //  Funding Rate Calculation (TODO 1)
    // =========================================================

    function test_getCurrentFundingRate_zeroWithNoPositions() public view {
        int256 rate = engine.getCurrentFundingRate();
        assertEq(rate, 0, "Funding rate should be 0 with no open interest");
    }

    function test_getCurrentFundingRate_positiveWithNetLongSkew() public {
        // Open imbalanced positions: more longs than shorts
        vm.prank(alice);
        engine.openPosition(60_000_000e8, true); // $60M long

        vm.prank(bob);
        engine.openPosition(40_000_000e8, false); // $40M short

        // Skew = $60M - $40M = $20M net long
        // Rate = 20_000_000e8 * 1e18 / 100_000_000e8 = 0.2e18
        int256 rate = engine.getCurrentFundingRate();
        assertEq(rate, 0.2e18, "Rate should be 20% per day with $20M/$100M skew");
    }

    function test_getCurrentFundingRate_negativeWithNetShortSkew() public {
        vm.prank(alice);
        engine.openPosition(30_000_000e8, true); // $30M long

        vm.prank(bob);
        engine.openPosition(70_000_000e8, false); // $70M short

        // Skew = $30M - $70M = -$40M net short
        // Rate = -40_000_000e8 * 1e18 / 100_000_000e8 = -0.4e18
        int256 rate = engine.getCurrentFundingRate();
        assertEq(rate, -0.4e18, "Rate should be -40% per day with net short skew");
    }

    function test_getCurrentFundingRate_zeroWithBalancedOI() public {
        vm.prank(alice);
        engine.openPosition(50_000_000e8, true); // $50M long

        vm.prank(bob);
        engine.openPosition(50_000_000e8, false); // $50M short

        int256 rate = engine.getCurrentFundingRate();
        assertEq(rate, 0, "Rate should be 0 with balanced open interest");
    }

    // =========================================================
    //  Accumulator Update (TODO 2)
    // =========================================================

    function test_updateFunding_accumulatesOverTime() public {
        // Create a skew so there's a non-zero rate
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // $10M long, no shorts

        // Rate = 10_000_000e8 * WAD / SKEW_SCALE = 0.1e18 (10% per day)

        // Advance 1 day
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();

        // After 1 day at 10% per day: accumulator should be 0.1e18
        int256 acc = engine.cumulativeFundingPerUnit();
        assertEq(acc, 0.1e18, "Accumulator should be 0.1e18 after 1 day at 10% rate");
    }

    function test_updateFunding_partialDay() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // 10% per day rate

        // Advance 1 hour (3600 seconds)
        vm.warp(block.timestamp + 3600);
        engine.updateFunding();

        // 0.1e18 * 3600 / 86400 = 0.004166...e18
        int256 acc = engine.cumulativeFundingPerUnit();
        int256 expected = int256(0.1e18) * 3600 / int256(SECONDS_PER_DAY);
        assertEq(acc, expected, "Accumulator should reflect partial day correctly");
    }

    function test_updateFunding_noOpIfSameTimestamp() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        // Call updateFunding twice in same block
        engine.updateFunding();
        int256 acc1 = engine.cumulativeFundingPerUnit();

        engine.updateFunding();
        int256 acc2 = engine.cumulativeFundingPerUnit();

        assertEq(acc1, acc2, "Double update in same block should be a no-op");
    }

    function test_updateFunding_negativeAccumulation() public {
        // Net short skew
        vm.prank(alice);
        engine.openPosition(10_000_000e8, false); // $10M short, no longs

        // Rate = -0.1e18 (shorts pay longs)
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();

        int256 acc = engine.cumulativeFundingPerUnit();
        assertEq(acc, -0.1e18, "Accumulator should go negative with net short skew");
    }

    function test_updateFunding_multiplePeriodsAccumulate() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // 10% per day

        // Day 1
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();
        assertEq(engine.cumulativeFundingPerUnit(), 0.1e18, "Day 1");

        // Day 2 (same rate)
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();
        assertEq(engine.cumulativeFundingPerUnit(), 0.2e18, "Day 2");

        // Day 3
        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();
        assertEq(engine.cumulativeFundingPerUnit(), 0.3e18, "Day 3");
    }

    // =========================================================
    //  Open Position (TODO 3)
    // =========================================================

    function test_openPosition_storesCorrectData() public {
        vm.prank(alice);
        engine.openPosition(1_000_000e8, true);

        (uint256 size, bool isLong, int256 entryIdx) = engine.positions(alice);
        assertEq(size, 1_000_000e8, "Size should be stored");
        assertTrue(isLong, "Direction should be long");
        assertEq(entryIdx, 0, "Entry funding index should be 0 at start");
    }

    function test_openPosition_updatesOI() public {
        vm.prank(alice);
        engine.openPosition(5_000_000e8, true);

        assertEq(engine.longOpenInterest(), 5_000_000e8, "Long OI should increase");
        assertEq(engine.shortOpenInterest(), 0, "Short OI should remain 0");

        vm.prank(bob);
        engine.openPosition(3_000_000e8, false);

        assertEq(engine.longOpenInterest(), 5_000_000e8, "Long OI unchanged");
        assertEq(engine.shortOpenInterest(), 3_000_000e8, "Short OI should increase");
    }

    function test_openPosition_snapshotsFundingIndex() public {
        // Create skew and advance time to build accumulator
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.warp(block.timestamp + SECONDS_PER_DAY);
        engine.updateFunding();

        // Accumulator should now be non-zero
        int256 currentAcc = engine.cumulativeFundingPerUnit();
        assertGt(currentAcc, 0, "Accumulator should be positive");

        // Bob opens a position now - should snapshot the current accumulator
        vm.prank(bob);
        engine.openPosition(5_000_000e8, false);

        (, , int256 bobEntry) = engine.positions(bob);
        assertEq(bobEntry, currentAcc, "Bob's entry index should equal current accumulator");
    }

    function test_openPosition_revertsOnZeroSize() public {
        vm.expectRevert(ZeroSize.selector);
        vm.prank(alice);
        engine.openPosition(0, true);
    }

    function test_openPosition_revertsOnDuplicatePosition() public {
        vm.prank(alice);
        engine.openPosition(1_000_000e8, true);

        vm.expectRevert(PositionAlreadyExists.selector);
        vm.prank(alice);
        engine.openPosition(1_000_000e8, false);
    }

    // =========================================================
    //  Pending Funding (TODO 4)
    // =========================================================

    function test_getPendingFunding_longPaysDuringNetLong() public {
        // Alice opens long, creating net long skew
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // $10M long

        // Advance 1 day
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Rate = 10_000_000e8 * WAD / SKEW_SCALE = 0.1e18 (10% per day)
        // Accumulator after 1 day: 0.1e18
        // Alice's rawFunding = 10_000_000e8 * 0.1e18 / 1e18 = 1_000_000e8
        // Alice is LONG, so she PAYS: -1_000_000e8
        int256 funding = engine.getPendingFunding(alice);
        assertEq(funding, -1_000_000e8, "Long should pay funding during net long skew");
    }

    function test_getPendingFunding_shortReceivesDuringNetLong() public {
        // Create both sides but with net long skew
        vm.prank(alice);
        engine.openPosition(70_000_000e8, true); // $70M long

        vm.prank(bob);
        engine.openPosition(30_000_000e8, false); // $30M short

        // Skew = $40M net long, rate = 0.4e18 (40% per day)
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Bob's rawFunding = 30_000_000e8 * 0.4e18 / 1e18 = 12_000_000e8
        // Bob is SHORT, so he RECEIVES: +12_000_000e8
        int256 bobFunding = engine.getPendingFunding(bob);
        assertEq(bobFunding, 12_000_000e8, "Short should receive funding during net long skew");

        // Alice's rawFunding = 70_000_000e8 * 0.4e18 / 1e18 = 28_000_000e8
        // Alice is LONG, so she PAYS: -28_000_000e8
        int256 aliceFunding = engine.getPendingFunding(alice);
        assertEq(aliceFunding, -28_000_000e8, "Long should pay funding during net long skew");
    }

    function test_getPendingFunding_shortPaysDuringNetShort() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, false); // $10M short, no longs

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Rate = -0.1e18 (shorts pay)
        // Accumulator: -0.1e18
        // rawFunding = 10_000_000e8 * (-0.1e18) / 1e18 = -1_000_000e8
        // Short gets +rawFunding = -1_000_000e8 (she PAYS)
        int256 funding = engine.getPendingFunding(alice);
        assertEq(funding, -1_000_000e8, "Short should pay funding during net short skew");
    }

    function test_getPendingFunding_zeroWithBalancedOI() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.prank(bob);
        engine.openPosition(10_000_000e8, false);

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Balanced OI → rate = 0 → no funding
        assertEq(engine.getPendingFunding(alice), 0, "No funding with balanced OI (long)");
        assertEq(engine.getPendingFunding(bob), 0, "No funding with balanced OI (short)");
    }

    function test_getPendingFunding_revertsWithNoPosition() public {
        vm.expectRevert(NoPosition.selector);
        engine.getPendingFunding(alice);
    }

    function test_getPendingFunding_laterEntryPaysLess() public {
        // Alice opens at t=0
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        // Advance 1 day, then Bob opens
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        vm.prank(bob);
        engine.openPosition(10_000_000e8, true);

        // Advance another day
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        int256 aliceFunding = engine.getPendingFunding(alice);
        int256 bobFunding = engine.getPendingFunding(bob);

        // Alice has been exposed to 2 days of funding, Bob only 1 day
        // (rates differ after Bob opens because OI changes, but Alice's total should be larger)
        assertLt(aliceFunding, bobFunding, "Alice should pay MORE funding (opened earlier, longer exposure)");
        assertLt(aliceFunding, int256(0), "Alice should be paying (negative)");
        assertLt(bobFunding, int256(0), "Bob should also be paying (net long)");
    }

    // =========================================================
    //  Close Position (TODO 5)
    // =========================================================

    function test_closePosition_returnsCorrectFunding() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        vm.prank(alice);
        int256 funding = engine.closePosition();

        // Same as getPendingFunding test: -1_000_000e8
        assertEq(funding, -1_000_000e8, "Close should return the settled funding amount");
    }

    function test_closePosition_clearsPosition() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        vm.prank(alice);
        engine.closePosition();

        (uint256 size, , ) = engine.positions(alice);
        assertEq(size, 0, "Position should be cleared after close");
    }

    function test_closePosition_updatesOI() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.prank(bob);
        engine.openPosition(5_000_000e8, false);

        assertEq(engine.longOpenInterest(), 10_000_000e8);
        assertEq(engine.shortOpenInterest(), 5_000_000e8);

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        vm.prank(alice);
        engine.closePosition();

        assertEq(engine.longOpenInterest(), 0, "Long OI should decrease after close");
        assertEq(engine.shortOpenInterest(), 5_000_000e8, "Short OI should be unchanged");
    }

    function test_closePosition_revertsWithNoPosition() public {
        vm.expectRevert(NoPosition.selector);
        vm.prank(alice);
        engine.closePosition();
    }

    function test_closePosition_canReopenAfterClose() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        vm.prank(alice);
        engine.closePosition();

        // Should be able to open a new position
        vm.prank(alice);
        engine.openPosition(5_000_000e8, false); // different direction

        (uint256 size, bool isLong, ) = engine.positions(alice);
        assertEq(size, 5_000_000e8, "Should store new position");
        assertFalse(isLong, "Should store new direction");
    }

    // =========================================================
    //  Integration: Funding is Zero-Sum
    // =========================================================

    function test_fundingIsZeroSum_twoPositions() public {
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true);

        vm.prank(bob);
        engine.openPosition(10_000_000e8, false);

        // With balanced OI, rate starts at 0. But let's create skew first.
        // Actually, balanced OI means zero funding. Let's use unbalanced.

        // Reset: deploy fresh
        engine = new FundingRateEngine();

        vm.prank(alice);
        engine.openPosition(60_000_000e8, true); // $60M long

        vm.prank(bob);
        engine.openPosition(40_000_000e8, false); // $40M short

        vm.warp(block.timestamp + SECONDS_PER_DAY);

        int256 aliceFunding = engine.getPendingFunding(alice);
        int256 bobFunding = engine.getPendingFunding(bob);

        // Funding is zero-sum: what longs pay, shorts receive
        // But with different sizes, the SUM should equal zero only if
        // we consider the total flow: longs pay size*rate, shorts receive size*rate
        // Total long payment = 60M * rate
        // Total short receipt = 40M * rate
        // These are NOT equal (different sizes), but the RATE is the same.
        // The mismatch goes to/from the protocol (or LP pool in production).
        // For our simplified engine, we just verify the sign convention is correct.
        assertLt(aliceFunding, 0, "Alice (long) should pay funding");
        assertGt(bobFunding, 0, "Bob (short) should receive funding");
    }

    // =========================================================
    //  Integration: Rate Changes Mid-Position
    // =========================================================

    function test_rateChangeMidPosition() public {
        // Alice opens long
        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // 10% per day rate

        // Day 1: only Alice, rate = 10%
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Bob opens a large short — this changes the rate
        vm.prank(bob);
        engine.openPosition(20_000_000e8, false);

        // New rate: (10M - 20M) / 100M = -10% (shorts now pay)
        int256 newRate = engine.getCurrentFundingRate();
        assertEq(newRate, -0.1e18, "Rate should flip to negative after Bob's short");

        // Day 2: rate is now -10%
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Alice was long: Day 1 she paid 10%, Day 2 she RECEIVES 10%
        // These should roughly cancel out
        int256 aliceFunding = engine.getPendingFunding(alice);
        // Day 1 accumulator: +0.1e18, Day 2 accumulator: +0.1e18 + (-0.1e18) = 0
        // Alice's delta = 0 - 0 = 0 → funding ≈ 0
        assertEq(aliceFunding, 0, "Alice's funding should net to ~0 after rate reversal");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_fundingRateProportionalToSkew(uint256 longOI, uint256 shortOI) public {
        // Bound to reasonable ranges
        longOI = bound(longOI, 0, 50_000_000e8);
        shortOI = bound(shortOI, 0, 50_000_000e8);

        // We need at least one side to have OI to open a position
        vm.assume(longOI > 0 || shortOI > 0);

        if (longOI > 0) {
            vm.prank(alice);
            engine.openPosition(longOI, true);
        }
        if (shortOI > 0) {
            vm.prank(bob);
            engine.openPosition(shortOI, false);
        }

        int256 rate = engine.getCurrentFundingRate();
        int256 expectedRate = (int256(longOI) - int256(shortOI)) * int256(WAD) / int256(SKEW_SCALE);

        assertEq(rate, expectedRate, "Rate should be proportional to skew");
    }

    function testFuzz_accumulatorGrowsCorrectly(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 * SECONDS_PER_DAY); // up to 1 year

        vm.prank(alice);
        engine.openPosition(10_000_000e8, true); // 10% per day

        vm.warp(block.timestamp + elapsed);
        engine.updateFunding();

        int256 rate = int256(0.1e18); // 10% per day
        int256 expected = rate * int256(elapsed) / int256(SECONDS_PER_DAY);

        assertEq(
            engine.cumulativeFundingPerUnit(),
            expected,
            "Accumulator should grow linearly with time"
        );
    }
}

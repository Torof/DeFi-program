// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {PTRateOracle} from
    "../../../../src/part3/module3/exercise2-pt-rate-oracle/PTRateOracle.sol";

contract PTRateOracleTest is Test {
    PTRateOracle public oracle;

    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days; // 31_536_000 seconds
    uint256 constant START = 1_700_000_000;
    uint256 constant MATURITY = START + 180 days; // ~6 months

    function setUp() public {
        vm.warp(START);
        oracle = new PTRateOracle(MATURITY);
    }

    // =========================================================================
    //  getImpliedRate
    // =========================================================================

    function test_getImpliedRate_sixMonths() public view {
        // PT at 3% discount, 6 months to maturity
        uint256 ptPrice = 0.97e18;
        uint256 timeToMaturity = 180 days;

        uint256 rate = oracle.getImpliedRate(ptPrice, timeToMaturity);

        // Expected: (1 - 0.97) / 0.97 * 365/180 ≈ 6.27%
        // Exact: 0.03e18 * 31536000 * 1e18 / (0.97e18 * 15552000)
        //      = 946_080_000e18 / 15_085_440e18 ≈ 0.0627e18
        assertApproxEqRel(rate, 0.0627e18, 0.01e18, "Should be ~6.27% annual");
    }

    function test_getImpliedRate_threeMonths() public view {
        uint256 ptPrice = 0.9876e18;
        uint256 timeToMaturity = 91.25 days; // ~3 months

        uint256 rate = oracle.getImpliedRate(ptPrice, timeToMaturity);

        // (1 - 0.9876) / 0.9876 * 365/91.25 ≈ 5.02%
        assertApproxEqRel(rate, 0.0502e18, 0.01e18, "Should be ~5.02% annual");
    }

    function test_getImpliedRate_oneYear() public view {
        uint256 ptPrice = 0.93e18;
        uint256 timeToMaturity = YEAR;

        uint256 rate = oracle.getImpliedRate(ptPrice, timeToMaturity);

        // (1 - 0.93) / 0.93 * 1 = 7.527%
        assertApproxEqRel(rate, 0.07527e18, 0.001e18, "Should be ~7.53% annual");
    }

    function test_getImpliedRate_smallDiscount() public view {
        // PT very close to par (0.1% discount), 1 year
        uint256 ptPrice = 0.999e18;
        uint256 timeToMaturity = YEAR;

        uint256 rate = oracle.getImpliedRate(ptPrice, timeToMaturity);

        // (1 - 0.999) / 0.999 ≈ 0.1%
        assertApproxEqRel(rate, 0.001e18, 0.01e18, "Should be ~0.1% annual");
    }

    function test_getImpliedRate_revertZeroPrice() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroPTPrice()"));
        oracle.getImpliedRate(0, 180 days);
    }

    function test_getImpliedRate_revertAbovePar() public {
        vm.expectRevert(abi.encodeWithSignature("PTAbovePar()"));
        oracle.getImpliedRate(WAD, 180 days);

        vm.expectRevert(abi.encodeWithSignature("PTAbovePar()"));
        oracle.getImpliedRate(1.01e18, 180 days);
    }

    function test_getImpliedRate_revertZeroTime() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroTimeToMaturity()"));
        oracle.getImpliedRate(0.97e18, 0);
    }

    // =========================================================================
    //  getPTPrice (inverse)
    // =========================================================================

    function test_getPTPrice_fivePercentThreeMonths() public view {
        uint256 rate = 0.05e18; // 5% annual
        uint256 timeToMaturity = 91.25 days;

        uint256 ptPrice = oracle.getPTPrice(rate, timeToMaturity);

        // ptPrice = YEAR / (YEAR + 0.05 * 91.25days)
        // = 31536000 / (31536000 + 0.05 * 7884000) = 31536000 / 31930200 ≈ 0.98766
        assertApproxEqRel(ptPrice, 0.98766e18, 0.001e18, "Should be ~0.98766");
    }

    function test_getPTPrice_tenPercentSixMonths() public view {
        uint256 rate = 0.10e18; // 10% annual
        uint256 timeToMaturity = 180 days;

        uint256 ptPrice = oracle.getPTPrice(rate, timeToMaturity);

        // ptPrice = YEAR / (YEAR + 0.10 * 180days)
        // = 31536000 / (31536000 + 0.10 * 15552000) = 31536000 / 33091200 ≈ 0.95301
        assertApproxEqRel(ptPrice, 0.95301e18, 0.001e18, "Should be ~0.953");
    }

    function test_getPTPrice_zeroRate() public view {
        // Zero rate → PT at par
        uint256 ptPrice = oracle.getPTPrice(0, 180 days);
        assertEq(ptPrice, WAD, "Zero rate should give PT price = 1.0");
    }

    function test_getPTPrice_revertZeroTime() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroTimeToMaturity()"));
        oracle.getPTPrice(0.05e18, 0);
    }

    function test_getPTPrice_inverseOfImpliedRate() public view {
        // If we compute a rate from a price, then compute price from that rate,
        // we should get back the original price
        uint256 originalPrice = 0.95e18;
        uint256 timeToMaturity = 180 days;

        uint256 rate = oracle.getImpliedRate(originalPrice, timeToMaturity);
        uint256 recoveredPrice = oracle.getPTPrice(rate, timeToMaturity);

        assertApproxEqAbs(
            recoveredPrice,
            originalPrice,
            1e12, // small tolerance for fixed-point rounding
            "getPTPrice should be inverse of getImpliedRate"
        );
    }

    // =========================================================================
    //  recordObservation
    // =========================================================================

    function test_recordObservation_firstObservation() public {
        oracle.recordObservation(0.97e18);

        assertEq(oracle.observationCount(), 1, "Should have 1 observation");

        (uint256 ts, uint256 rate, uint256 cum) = oracle.observations(0);

        assertEq(ts, START, "Timestamp should be current");
        assertGt(rate, 0, "Rate should be positive");
        assertEq(cum, 0, "First cumulative should be 0 (no elapsed time)");
    }

    function test_recordObservation_cumulativeGrows() public {
        // Record at T=0
        oracle.recordObservation(0.97e18);

        // Advance 1 hour
        vm.warp(START + 1 hours);
        oracle.recordObservation(0.97e18);

        (,uint256 rate0,) = oracle.observations(0);
        (,, uint256 cum1) = oracle.observations(1);

        // cumulative[1] = rate0 * 3600 (1 hour in seconds)
        assertEq(cum1, rate0 * 3600, "Cumulative should equal rate * elapsed time");
    }

    function test_recordObservation_multipleObservations() public {
        // Record 3 observations at different times with different prices
        oracle.recordObservation(0.97e18); // T=0

        vm.warp(START + 1 hours);
        oracle.recordObservation(0.96e18); // T=1hr, different rate

        vm.warp(START + 3 hours);
        oracle.recordObservation(0.98e18); // T=3hr

        assertEq(oracle.observationCount(), 3, "Should have 3 observations");

        // Verify cumulative growth
        (,, uint256 cum0) = oracle.observations(0);
        (,uint256 rate1, uint256 cum1) = oracle.observations(1);
        (,, uint256 cum2) = oracle.observations(2);

        assertEq(cum0, 0, "First cumulative = 0");
        assertGt(cum1, 0, "Second cumulative > 0");
        // cum2 = cum1 + rate1 * (3hr - 1hr) = cum1 + rate1 * 7200
        assertEq(cum2, cum1 + rate1 * 7200, "Cumulative grows by rate * elapsed");
    }

    function test_recordObservation_revertAfterMaturity() public {
        vm.warp(MATURITY);

        vm.expectRevert(abi.encodeWithSignature("ZeroTimeToMaturity()"));
        oracle.recordObservation(0.97e18);
    }

    // =========================================================================
    //  getTimeWeightedRate (TWAR)
    // =========================================================================

    function test_getTimeWeightedRate_constantRate() public {
        // Same price at all observations → TWAR = that rate
        oracle.recordObservation(0.97e18);

        vm.warp(START + 1 hours);
        oracle.recordObservation(0.97e18);

        vm.warp(START + 2 hours);
        oracle.recordObservation(0.97e18);

        uint256 twar = oracle.getTimeWeightedRate(0, 2);

        // Should approximately equal the constant rate
        // (not exact because same PT price yields slightly different implied rates
        //  as timeToMaturity shrinks between observations)
        (,uint256 rate0,) = oracle.observations(0);
        assertApproxEqRel(twar, rate0, 0.001e18, "TWAR of constant price should approximate the rate");
    }

    function test_getTimeWeightedRate_changingRates() public {
        // Rate changes mid-period
        oracle.recordObservation(0.97e18); // rate_A

        vm.warp(START + 1 hours);
        oracle.recordObservation(0.96e18); // rate_B (higher discount → higher rate)

        vm.warp(START + 2 hours);
        oracle.recordObservation(0.97e18); // record to capture rate_B period

        // TWAR from obs[0] to obs[2]:
        // = (cum[2] - cum[0]) / (ts[2] - ts[0])
        // = (rate_A * 3600 + rate_B * 3600) / 7200
        // = (rate_A + rate_B) / 2 (simple average since equal periods)

        (,uint256 rateA,) = oracle.observations(0);
        (,uint256 rateB,) = oracle.observations(1);

        uint256 twar = oracle.getTimeWeightedRate(0, 2);
        uint256 expectedAvg = (rateA + rateB) / 2;

        assertEq(twar, expectedAvg, "TWAR should be time-weighted average");
    }

    function test_getTimeWeightedRate_unequalPeriods() public {
        // First rate held for 1 hour, second for 3 hours
        oracle.recordObservation(0.97e18); // rate_A, held for 1hr

        vm.warp(START + 1 hours);
        oracle.recordObservation(0.96e18); // rate_B, held for 3hr

        vm.warp(START + 4 hours);
        oracle.recordObservation(0.97e18); // just to capture rate_B period

        (,uint256 rateA,) = oracle.observations(0);
        (,uint256 rateB,) = oracle.observations(1);

        uint256 twar = oracle.getTimeWeightedRate(0, 2);

        // TWAR = (rateA * 3600 + rateB * 10800) / 14400
        // = (rateA * 1 + rateB * 3) / 4 (time-weighted, not simple average)
        uint256 expected = (rateA * 3600 + rateB * 10800) / 14400;
        assertEq(twar, expected, "TWAR should weight by time");

        // rateB should dominate since it was held 3x longer
        assertGt(twar, rateA, "TWAR should be pulled toward longer-held rate");
    }

    function test_getTimeWeightedRate_subRange() public {
        // Can query TWAR for a subset of observations
        oracle.recordObservation(0.97e18); // obs[0]

        vm.warp(START + 1 hours);
        oracle.recordObservation(0.96e18); // obs[1]

        vm.warp(START + 2 hours);
        oracle.recordObservation(0.95e18); // obs[2]

        vm.warp(START + 3 hours);
        oracle.recordObservation(0.96e18); // obs[3]

        // Query just obs[1] to obs[3]
        uint256 twarFull = oracle.getTimeWeightedRate(0, 3);
        uint256 twarSub = oracle.getTimeWeightedRate(1, 3);

        // They should be different (different time windows)
        assertFalse(twarFull == twarSub, "Full and sub-range TWAR should differ");
    }

    function test_getTimeWeightedRate_revertInsufficientObservations() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientObservations()"));
        oracle.getTimeWeightedRate(0, 1);

        oracle.recordObservation(0.97e18);

        vm.expectRevert(abi.encodeWithSignature("InsufficientObservations()"));
        oracle.getTimeWeightedRate(0, 1);
    }

    function test_getTimeWeightedRate_revertInvalidPeriod() public {
        oracle.recordObservation(0.97e18);
        vm.warp(START + 1 hours);
        oracle.recordObservation(0.97e18);

        // startIdx >= endIdx
        vm.expectRevert(abi.encodeWithSignature("InvalidPeriod()"));
        oracle.getTimeWeightedRate(1, 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidPeriod()"));
        oracle.getTimeWeightedRate(0, 0);
    }

    // =========================================================================
    //  getYTBreakEven
    // =========================================================================

    function test_getYTBreakEven_sixMonths() public view {
        // YT costs 0.03, 6 months to maturity
        uint256 ytPrice = 0.03e18;
        uint256 timeToMaturity = 180 days;

        uint256 breakEven = oracle.getYTBreakEven(ytPrice, timeToMaturity);

        // breakEven = 0.03 * 365/180 ≈ 6.08%
        assertApproxEqRel(breakEven, 0.0608e18, 0.01e18, "Should be ~6.08% annual");
    }

    function test_getYTBreakEven_oneYear() public view {
        // YT costs 0.05, 1 year to maturity
        uint256 ytPrice = 0.05e18;
        uint256 timeToMaturity = YEAR;

        uint256 breakEven = oracle.getYTBreakEven(ytPrice, timeToMaturity);

        // breakEven = 0.05 * 1 = 5%
        assertEq(breakEven, 0.05e18, "1-year YT at 0.05 needs 5% annual yield");
    }

    function test_getYTBreakEven_shortMaturity() public view {
        // YT costs 0.01, 30 days to maturity
        uint256 ytPrice = 0.01e18;
        uint256 timeToMaturity = 30 days;

        uint256 breakEven = oracle.getYTBreakEven(ytPrice, timeToMaturity);

        // breakEven = 0.01 * 365/30 ≈ 12.17%
        assertApproxEqRel(
            breakEven, 0.1217e18, 0.01e18,
            "Short maturity requires higher annual yield to break even"
        );
    }

    function test_getYTBreakEven_consistentWithImpliedRate() public view {
        // If PT + YT = 1, then ytPrice = 1 - ptPrice
        // The YT break-even should be close to the implied rate from ptPrice
        uint256 ptPrice = 0.97e18;
        uint256 ytPrice = WAD - ptPrice; // 0.03e18
        uint256 timeToMaturity = 180 days;

        uint256 impliedRate = oracle.getImpliedRate(ptPrice, timeToMaturity);
        uint256 breakEven = oracle.getYTBreakEven(ytPrice, timeToMaturity);

        // Guard: ensure breakEven is actually computed (not just default zero)
        assertGt(breakEven, 0, "Break-even should be positive");

        // These should be close (not exact due to simple vs precise compounding)
        // implied rate: (WAD-pt) * YEAR * WAD / (pt * time) — includes pt in denominator
        // break-even: yt * YEAR / time — linear approximation
        // For small discounts, they converge
        assertApproxEqRel(
            breakEven,
            impliedRate,
            0.05e18, // within 5% relative
            "Break-even should approximate implied rate"
        );
    }

    function test_getYTBreakEven_revertZeroTime() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroTimeToMaturity()"));
        oracle.getYTBreakEven(0.03e18, 0);
    }

    function test_getYTBreakEven_revertZeroPrice() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroPTPrice()"));
        oracle.getYTBreakEven(0, 180 days);
    }

    // =========================================================================
    //  Integration
    // =========================================================================

    function test_integration_rateTracking() public {
        // Simulate a market where PT price moves over time

        // Day 0: PT at 3% discount
        oracle.recordObservation(0.97e18);

        // Day 1: yield expectations rise → bigger discount
        vm.warp(START + 1 days);
        oracle.recordObservation(0.965e18);

        // Day 3: market stabilizes
        vm.warp(START + 3 days);
        oracle.recordObservation(0.968e18);

        // Day 7: yield drops → smaller discount
        vm.warp(START + 7 days);
        oracle.recordObservation(0.975e18);

        // TWAR over the full week
        uint256 twar = oracle.getTimeWeightedRate(0, 3);
        assertGt(twar, 0, "TWAR should be positive");

        // TWAR over last 4 days only
        uint256 twarRecent = oracle.getTimeWeightedRate(1, 3);
        assertGt(twarRecent, 0, "Recent TWAR should be positive");
    }

    // =========================================================================
    //  Fuzz tests
    // =========================================================================

    function testFuzz_getImpliedRate_alwaysPositive(
        uint256 ptPrice,
        uint256 timeToMaturity
    ) public view {
        ptPrice = bound(ptPrice, 0.5e18, WAD - 1); // 50% to 99.999...%
        timeToMaturity = bound(timeToMaturity, 1 days, YEAR);

        uint256 rate = oracle.getImpliedRate(ptPrice, timeToMaturity);
        assertGt(rate, 0, "Rate should always be positive for discounted PT");
    }

    function testFuzz_roundTrip_rateAndPrice(
        uint256 rate,
        uint256 timeToMaturity
    ) public view {
        rate = bound(rate, 0.001e18, 1e18); // 0.1% to 100%
        timeToMaturity = bound(timeToMaturity, 30 days, YEAR);

        uint256 ptPrice = oracle.getPTPrice(rate, timeToMaturity);
        uint256 recoveredRate = oracle.getImpliedRate(ptPrice, timeToMaturity);

        // Should round-trip within small tolerance
        assertApproxEqRel(
            recoveredRate,
            rate,
            0.001e18, // 0.1% relative tolerance
            "Rate should survive round-trip through price"
        );
    }

    function testFuzz_breakEvenIncreasesWithPrice(
        uint256 ytPrice1,
        uint256 ytPrice2,
        uint256 timeToMaturity
    ) public view {
        ytPrice1 = bound(ytPrice1, 0.001e18, 0.2e18);
        ytPrice2 = bound(ytPrice2, ytPrice1 + 1, 0.3e18);
        timeToMaturity = bound(timeToMaturity, 30 days, YEAR);

        uint256 be1 = oracle.getYTBreakEven(ytPrice1, timeToMaturity);
        uint256 be2 = oracle.getYTBreakEven(ytPrice2, timeToMaturity);

        assertGt(be2, be1, "Higher YT price should require higher break-even yield");
    }
}

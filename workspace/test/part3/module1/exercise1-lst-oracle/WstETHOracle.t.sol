// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the WstETHOracle exercise.
//  Implement WstETHOracle.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    WstETHOracle,
    InvalidPrice,
    StalePrice,
    ZeroAmount
} from "../../../../src/part3/module1/exercise1-lst-oracle/WstETHOracle.sol";
import {MockWstETH} from "../../../../src/part3/module1/mocks/MockWstETH.sol";
import {MockAggregatorV3} from "../../../../src/part3/module1/mocks/MockAggregatorV3.sol";

contract WstETHOracleTest is Test {
    // --- Contracts ---
    WstETHOracle public oracle;
    MockWstETH public wstETH;
    MockAggregatorV3 public ethUsdFeed;
    MockAggregatorV3 public stethEthFeed;

    // --- Constants matching the lesson's numeric examples ---

    /// @dev wstETH exchange rate: 1 wstETH = 1.19 stETH (approximate early 2026)
    uint256 constant EXCHANGE_RATE = 1.19e18;

    /// @dev ETH/USD price: $3,200 (Chainlink 8 decimals)
    int256 constant ETH_USD_PRICE = 3200e8;

    /// @dev stETH/ETH market price: 1.0 (normal peg, 18 decimals)
    int256 constant STETH_ETH_PRICE = 1e18;

    /// @dev stETH/ETH during de-peg: 0.93 (June 2022 scenario, 18 decimals)
    int256 constant STETH_ETH_DEPEG = 0.93e18;

    function setUp() public {
        // Warp to a realistic timestamp so staleness math doesn't underflow
        vm.warp(1_700_000_000); // ~ Nov 2023

        // Deploy mocks
        wstETH = new MockWstETH(EXCHANGE_RATE);
        ethUsdFeed = new MockAggregatorV3(ETH_USD_PRICE, 8);
        stethEthFeed = new MockAggregatorV3(STETH_ETH_PRICE, 18);

        // Deploy oracle
        oracle = new WstETHOracle(
            address(wstETH),
            address(ethUsdFeed),
            address(stethEthFeed)
        );
    }

    // =========================================================
    //  Basic Two-Step Pricing (TODO 1: getWstETHValueUSD)
    // =========================================================

    function test_getWstETHValueUSD_basicPricing() public view {
        // 10 wstETH at 1.19 rate and $3,200 ETH/USD
        // Step 1: 10e18 × 1.19e18 / 1e18 = 11.9e18 ETH equiv
        // Step 2: 11.9e18 × 3200e8 / 1e18 = 38_080e8
        uint256 value = oracle.getWstETHValueUSD(10e18);
        assertEq(value, 38_080e8, "10 wstETH should be worth $38,080 at 1.19 rate and $3,200 ETH");
    }

    function test_getWstETHValueUSD_singleToken() public view {
        // 1 wstETH = 1.19 ETH equiv × $3,200 = $3,808
        uint256 value = oracle.getWstETHValueUSD(1e18);
        assertEq(value, 3808e8, "1 wstETH should be worth $3,808");
    }

    function test_getWstETHValueUSD_fractionalAmount() public view {
        // 0.5 wstETH = 0.595 ETH equiv × $3,200 = $1,904
        uint256 value = oracle.getWstETHValueUSD(0.5e18);
        assertEq(value, 1904e8, "0.5 wstETH should be worth $1,904");
    }

    function test_getWstETHValueUSD_zeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        oracle.getWstETHValueUSD(0);
    }

    function test_getWstETHValueUSD_exchangeRateGrowth() public {
        // Simulate 1 year of staking rewards: rate grows from 1.19 to 1.2267
        uint256 newRate = 1.2267e18;
        wstETH.setExchangeRate(newRate);

        // 10 wstETH × 1.2267 × $3,200 = 12.267 × $3,200 = $39,254.4
        // In 8-decimal: 12.267e18 × 3200e8 / 1e18 = 39_254.4e8
        // Solidity truncates: 10e18 × 1.2267e18 / 1e18 = 12.267e18
        //                     12.267e18 × 3200e8 / 1e18 = 39_254_400_000_00 = 39254.4e8
        uint256 value = oracle.getWstETHValueUSD(10e18);
        uint256 expected = 10e18 * newRate / 1e18 * uint256(ETH_USD_PRICE) / 1e18;
        assertEq(value, expected, "Price should reflect the new exchange rate after staking rewards");
        assertGt(value, 38_080e8, "Value should increase as exchange rate grows");
    }

    function test_getWstETHValueUSD_differentEthPrice() public {
        // ETH drops to $2,000
        ethUsdFeed.updateAnswer(2000e8);

        // 10 wstETH = 11.9 ETH equiv × $2,000 = $23,800
        uint256 value = oracle.getWstETHValueUSD(10e18);
        assertEq(value, 23_800e8, "Should reflect ETH price change");
    }

    // =========================================================
    //  Staleness Checks (TODO 1)
    // =========================================================

    function test_getWstETHValueUSD_revertsOnStaleEthUsd() public {
        // Make ETH/USD feed stale (older than 3900 seconds)
        ethUsdFeed.setUpdatedAt(block.timestamp - 4000);

        vm.expectRevert(StalePrice.selector);
        oracle.getWstETHValueUSD(10e18);
    }

    function test_getWstETHValueUSD_revertsOnInvalidEthUsd() public {
        // Set ETH/USD price to zero
        ethUsdFeed.updateAnswer(0);

        vm.expectRevert(InvalidPrice.selector);
        oracle.getWstETHValueUSD(10e18);
    }

    function test_getWstETHValueUSD_revertsOnNegativeEthUsd() public {
        // Set ETH/USD price to negative
        ethUsdFeed.updateAnswer(-1);

        vm.expectRevert(InvalidPrice.selector);
        oracle.getWstETHValueUSD(10e18);
    }

    function test_getWstETHValueUSD_acceptsFreshPrice() public view {
        // Default setup: updatedAt = block.timestamp (perfectly fresh)
        // Should not revert
        uint256 value = oracle.getWstETHValueUSD(10e18);
        assertGt(value, 0, "Fresh price should return a valid value");
    }

    function test_getWstETHValueUSD_acceptsPriceAtStalenessEdge() public {
        // Set updatedAt to exactly ETH_USD_STALENESS seconds ago
        ethUsdFeed.setUpdatedAt(block.timestamp - oracle.ETH_USD_STALENESS());

        // Should NOT revert — at the boundary, not past it
        uint256 value = oracle.getWstETHValueUSD(10e18);
        assertGt(value, 0, "Price at staleness boundary should still be accepted");
    }

    // =========================================================
    //  Dual Oracle Pattern (TODO 2: getWstETHValueUSDSafe)
    // =========================================================

    function test_getWstETHValueUSDSafe_normalPeg() public view {
        // stETH/ETH = 1.0 (normal) — safe price should equal basic price
        uint256 basicValue = oracle.getWstETHValueUSD(10e18);
        uint256 safeValue = oracle.getWstETHValueUSDSafe(10e18);

        assertEq(safeValue, basicValue, "During normal peg, safe and basic pricing should be equal");
    }

    function test_getWstETHValueUSDSafe_depegScenario() public {
        // Simulate June 2022 de-peg: stETH/ETH drops to 0.93
        stethEthFeed.updateAnswer(STETH_ETH_DEPEG);

        uint256 basicValue = oracle.getWstETHValueUSD(10e18);
        uint256 safeValue = oracle.getWstETHValueUSDSafe(10e18);

        // Safe value should be ~7% less than basic value
        assertLt(safeValue, basicValue, "Safe value must be lower during de-peg");

        // Verify the actual safe value:
        // effectiveRate = 1.19e18 × 0.93e18 / 1e18 = 1.1067e18
        // ethEquiv = 10e18 × 1.1067e18 / 1e18 = 11.067e18
        // valueUSD = 11.067e18 × 3200e8 / 1e18 = 35_414.4e8
        // With Solidity truncation:
        uint256 effectiveRate = EXCHANGE_RATE * uint256(STETH_ETH_DEPEG) / 1e18;
        uint256 ethEquiv = 10e18 * effectiveRate / 1e18;
        uint256 expected = ethEquiv * uint256(ETH_USD_PRICE) / 1e18;
        assertEq(safeValue, expected, "Safe value should use the de-pegged market rate");
    }

    function test_getWstETHValueUSDSafe_mildDepeg() public {
        // stETH/ETH = 0.98 — mild de-peg
        stethEthFeed.updateAnswer(0.98e18);

        uint256 basicValue = oracle.getWstETHValueUSD(10e18);
        uint256 safeValue = oracle.getWstETHValueUSDSafe(10e18);

        assertLt(safeValue, basicValue, "Even mild de-peg should reduce safe value");

        uint256 effectiveRate = EXCHANGE_RATE * 0.98e18 / 1e18;
        uint256 ethEquiv = 10e18 * effectiveRate / 1e18;
        uint256 expected = ethEquiv * uint256(ETH_USD_PRICE) / 1e18;
        assertEq(safeValue, expected, "Safe value should reflect 2% de-peg discount");
    }

    function test_getWstETHValueUSDSafe_marketRateAboveOne() public {
        // Edge case: stETH/ETH slightly > 1.0 (can happen briefly on DEXes)
        // Should be capped at 1.0 — we never value stETH ABOVE protocol rate
        stethEthFeed.updateAnswer(1.02e18);

        uint256 basicValue = oracle.getWstETHValueUSD(10e18);
        uint256 safeValue = oracle.getWstETHValueUSDSafe(10e18);

        assertEq(
            safeValue,
            basicValue,
            "Market rate above 1.0 should be capped - safe value equals basic value"
        );
    }

    function test_getWstETHValueUSDSafe_zeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        oracle.getWstETHValueUSDSafe(0);
    }

    // =========================================================
    //  Dual Oracle — Staleness on stETH/ETH Feed (TODO 2)
    // =========================================================

    function test_getWstETHValueUSDSafe_revertsOnStaleStethEth() public {
        // Make stETH/ETH feed stale (older than 90,000 seconds)
        stethEthFeed.setUpdatedAt(block.timestamp - 91_000);

        vm.expectRevert(StalePrice.selector);
        oracle.getWstETHValueUSDSafe(10e18);
    }

    function test_getWstETHValueUSDSafe_revertsOnInvalidStethEth() public {
        // Set stETH/ETH price to zero
        stethEthFeed.updateAnswer(0);

        vm.expectRevert(InvalidPrice.selector);
        oracle.getWstETHValueUSDSafe(10e18);
    }

    function test_getWstETHValueUSDSafe_revertsOnStaleEthUsd() public {
        // Even the safe function checks ETH/USD staleness
        ethUsdFeed.setUpdatedAt(block.timestamp - 4000);

        vm.expectRevert(StalePrice.selector);
        oracle.getWstETHValueUSDSafe(10e18);
    }

    function test_getWstETHValueUSDSafe_acceptsStethEthAtBoundary() public {
        // Set updatedAt to exactly STETH_ETH_STALENESS seconds ago
        stethEthFeed.setUpdatedAt(block.timestamp - oracle.STETH_ETH_STALENESS());

        // Should NOT revert — at the boundary, not past it
        uint256 value = oracle.getWstETHValueUSDSafe(10e18);
        assertGt(value, 0, "stETH/ETH price at staleness boundary should be accepted");
    }

    // =========================================================
    //  Fuzz Tests — Properties
    // =========================================================

    function testFuzz_safePriceNeverExceedsBasic(uint256 wstETHAmount) public view {
        // Bound to reasonable range: 0.001 wstETH to 1M wstETH
        wstETHAmount = bound(wstETHAmount, 0.001e18, 1_000_000e18);

        uint256 basicValue = oracle.getWstETHValueUSD(wstETHAmount);
        uint256 safeValue = oracle.getWstETHValueUSDSafe(wstETHAmount);

        // INVARIANT: dual oracle is always <= basic (conservative)
        assertLe(
            safeValue,
            basicValue,
            "INVARIANT: Safe (dual oracle) price should never exceed basic (exchange-rate-only) price"
        );
    }

    function testFuzz_priceScalesLinearly(uint256 amount1, uint256 amount2) public view {
        // Bound to avoid overflow: both amounts small enough that sum doesn't overflow
        amount1 = bound(amount1, 1e15, 500_000e18);
        amount2 = bound(amount2, 1e15, 500_000e18);

        uint256 value1 = oracle.getWstETHValueUSD(amount1);
        uint256 value2 = oracle.getWstETHValueUSD(amount2);
        uint256 valueCombined = oracle.getWstETHValueUSD(amount1 + amount2);

        // INVARIANT: pricing should be (approximately) linear
        // Due to integer truncation, combined may differ by at most 1 unit
        uint256 sumOfParts = value1 + value2;
        uint256 diff = valueCombined > sumOfParts
            ? valueCombined - sumOfParts
            : sumOfParts - valueCombined;

        assertLe(diff, 1, "INVARIANT: Pricing should be linear (within rounding tolerance)");
    }

    function testFuzz_higherExchangeRateMeansHigherPrice(uint256 rate1, uint256 rate2) public {
        // Bound rates to realistic range: 1.0 to 2.0
        rate1 = bound(rate1, 1.0e18, 2.0e18);
        rate2 = bound(rate2, rate1, 2.0e18); // rate2 >= rate1

        wstETH.setExchangeRate(rate1);
        uint256 value1 = oracle.getWstETHValueUSD(10e18);

        wstETH.setExchangeRate(rate2);
        uint256 value2 = oracle.getWstETHValueUSD(10e18);

        // INVARIANT: higher exchange rate → higher or equal USD value
        assertGe(
            value2,
            value1,
            "INVARIANT: Higher exchange rate must produce higher or equal USD value"
        );
    }
}

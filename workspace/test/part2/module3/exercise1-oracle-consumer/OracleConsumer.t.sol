// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the OracleConsumer
//  exercise. Implement OracleConsumer.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {MockAggregatorV3} from "../../../../src/part2/module3/mocks/MockAggregatorV3.sol";
import {
    OracleConsumer,
    InvalidPrice,
    RoundNotComplete,
    StalePrice,
    StaleRound,
    SequencerDown,
    GracePeriodNotOver
} from "../../../../src/part2/module3/exercise1-oracle-consumer/OracleConsumer.sol";

contract OracleConsumerTest is Test {
    OracleConsumer consumer;
    MockAggregatorV3 ethUsdFeed;    // 8 decimals (standard)
    MockAggregatorV3 btcEthFeed;    // 18 decimals (ETH-denominated)
    MockAggregatorV3 eurUsdFeed;    // 8 decimals
    MockAggregatorV3 sequencerFeed; // L2 sequencer uptime feed

    uint256 constant MAX_STALENESS = 4500; // 1h15m (ETH/USD heartbeat + buffer)
    uint256 constant GRACE_PERIOD = 3600;  // 1 hour

    // Realistic prices:
    //   ETH/USD = $3,000.00 → 3000_00000000 (8 decimals)
    //   BTC/ETH = 15.5 ETH  → 15_500000000000000000 (18 decimals)
    //   EUR/USD = $1.08      → 1_08000000 (8 decimals)
    int256 constant ETH_USD_PRICE = 3000_00000000;
    int256 constant BTC_ETH_PRICE = 15_500000000000000000;
    int256 constant EUR_USD_PRICE = 1_08000000;

    function setUp() public {
        consumer = new OracleConsumer(MAX_STALENESS);

        ethUsdFeed = new MockAggregatorV3(ETH_USD_PRICE, 8);
        btcEthFeed = new MockAggregatorV3(BTC_ETH_PRICE, 18);
        eurUsdFeed = new MockAggregatorV3(EUR_USD_PRICE, 8);

        // Sequencer feed: answer=0 means UP, startedAt = old enough (past grace period)
        sequencerFeed = new MockAggregatorV3(int256(0), 0);
        sequencerFeed.setStartedAt(block.timestamp - GRACE_PERIOD - 1);
    }

    // =========================================================
    //  Basic Validation — The 4 Mandatory Checks
    // =========================================================

    function test_ValidPrice_ReturnsCorrectly() public view {
        uint256 price = consumer.getPrice(address(ethUsdFeed));
        assertEq(price, uint256(ETH_USD_PRICE), "Should return the raw price from the feed");
    }

    function test_NegativePrice_Reverts() public {
        ethUsdFeed.updateAnswer(-100);

        vm.expectRevert(InvalidPrice.selector);
        consumer.getPrice(address(ethUsdFeed));
    }

    function test_ZeroPrice_Reverts() public {
        ethUsdFeed.updateAnswer(0);

        vm.expectRevert(InvalidPrice.selector);
        consumer.getPrice(address(ethUsdFeed));
    }

    function test_RoundNotComplete_Reverts() public {
        // Set updatedAt = 0 to simulate incomplete round
        ethUsdFeed.setRoundData(1, ETH_USD_PRICE, block.timestamp, 0, 1);

        vm.expectRevert(RoundNotComplete.selector);
        consumer.getPrice(address(ethUsdFeed));
    }

    function test_StalePrice_Reverts() public {
        // Warp forward past staleness threshold
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        vm.expectRevert(StalePrice.selector);
        consumer.getPrice(address(ethUsdFeed));
    }

    function test_StaleRound_Reverts() public {
        // answeredInRound < roundId = stale round data
        ethUsdFeed.setRoundData(5, ETH_USD_PRICE, block.timestamp, block.timestamp, 3);

        vm.expectRevert(StaleRound.selector);
        consumer.getPrice(address(ethUsdFeed));
    }

    function test_PriceJustBeforeStaleness_Succeeds() public {
        // Warp to exactly maxStaleness - 1 second: should still be valid
        vm.warp(block.timestamp + MAX_STALENESS - 1);

        uint256 price = consumer.getPrice(address(ethUsdFeed));
        assertEq(price, uint256(ETH_USD_PRICE), "Price at boundary should still be valid");
    }

    // =========================================================
    //  Decimal Normalization
    // =========================================================

    function test_Normalize_8DecimalFeed() public view {
        // ETH/USD: 3000_00000000 (8 dec) → 3000_000000000000000000 (18 dec)
        uint256 normalized = consumer.getNormalizedPrice(address(ethUsdFeed));
        assertEq(normalized, 3000e18, "8-decimal feed should be scaled to 18 decimals");
    }

    function test_Normalize_18DecimalFeed() public view {
        // BTC/ETH: 15.5e18 (18 dec) → 15.5e18 (no change)
        uint256 normalized = consumer.getNormalizedPrice(address(btcEthFeed));
        assertEq(normalized, uint256(BTC_ETH_PRICE), "18-decimal feed should need no scaling");
    }

    function test_Normalize_6DecimalFeed() public {
        // USDC-style: price = 1_000000 (6 dec) → 1e18
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(1_000000, 6);
        uint256 normalized = consumer.getNormalizedPrice(address(usdcFeed));
        assertEq(normalized, 1e18, "6-decimal feed should be scaled to 18 decimals");
    }

    // =========================================================
    //  Derived Prices
    // =========================================================

    function test_DerivedPrice_ETH_EUR() public view {
        // ETH/EUR = ETH/USD / EUR/USD = 3000 / 1.08 ≈ 2777.78
        // At 8 target decimals: 2777_77777777 (truncated)
        uint256 derived = consumer.getDerivedPrice(
            address(ethUsdFeed),
            address(eurUsdFeed),
            8
        );

        // 3000e18 * 1e8 / 1.08e18 = 277777777777 (truncated from 277777777777.7...)
        assertApproxEqRel(
            derived,
            277777777777,
            1e15, // 0.1% tolerance for integer division rounding
            "ETH/EUR should be approximately 2777.78 at 8 decimals"
        );
    }

    function test_DerivedPrice_DifferentSourceDecimals() public view {
        // BTC/USD derived from BTC/ETH (18 dec) and ETH/USD (8 dec)
        // Both are normalized to 18 decimals internally
        // BTC/USD = BTC/ETH × ETH/USD... but our function divides A/B
        // So: ETH/USD ÷ BTC/ETH would give the inverse. Instead:
        // Let's derive ETH/BTC = ETH/USD ÷ BTC/USD (if we had BTC/USD feed)
        // Simpler: just verify the math works with different decimal inputs
        //
        // Use EUR/USD (8 dec) ÷ ETH/USD (8 dec) at 18 target decimals
        // = 1.08 / 3000 ≈ 0.00036 → 360000000000000 (18 dec)
        uint256 derived = consumer.getDerivedPrice(
            address(eurUsdFeed),
            address(ethUsdFeed),
            18
        );

        assertApproxEqRel(
            derived,
            360000000000000, // 0.00036e18
            1e15,
            "EUR/ETH should be approximately 0.00036 at 18 decimals"
        );
    }

    // =========================================================
    //  L2 Sequencer Checks
    // =========================================================

    function test_SequencerDown_Reverts() public {
        // Set sequencer answer = 1 (down)
        sequencerFeed.updateAnswer(int256(1));
        sequencerFeed.setStartedAt(block.timestamp);

        vm.expectRevert(SequencerDown.selector);
        consumer.getL2Price(address(ethUsdFeed), address(sequencerFeed));
    }

    function test_SequencerGracePeriod_Reverts() public {
        // Sequencer is up (answer=0) but just restarted (within grace period)
        sequencerFeed.updateAnswer(int256(0));
        sequencerFeed.setStartedAt(block.timestamp); // just restarted NOW

        vm.expectRevert(GracePeriodNotOver.selector);
        consumer.getL2Price(address(ethUsdFeed), address(sequencerFeed));
    }

    function test_L2Price_FullFlow() public view {
        // Sequencer up AND past grace period → should return normalized price
        uint256 price = consumer.getL2Price(address(ethUsdFeed), address(sequencerFeed));
        assertEq(price, 3000e18, "L2 price should return normalized price when sequencer is healthy");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_ValidPrice_AlwaysPositive(int256 answer) public {
        answer = int256(bound(uint256(answer), 1, uint256(type(int256).max)));

        MockAggregatorV3 feed = new MockAggregatorV3(answer, 8);
        uint256 price = consumer.getPrice(address(feed));

        assertGt(price, 0, "INVARIANT: validated price must always be positive");
    }
}

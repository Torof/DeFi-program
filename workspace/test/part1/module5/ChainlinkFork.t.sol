// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Chainlink Price Feed Fork Testing
//
// Learn to interact with Chainlink oracles on mainnet fork. This exercise
// demonstrates reading price data, verifying data freshness, and implementing
// basic staleness checks.
//
// Day 11: Master oracle integration patterns.
//
// Run: forge test --match-contract ChainlinkForkTest --fork-url $MAINNET_RPC_URL -vvv
// ============================================================================

import "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.sol";

// =============================================================
//  Chainlink Interface
// =============================================================
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// --- Custom Errors ---
error StalePrice();
error InvalidPrice();

// =============================================================
//  TODO 1: Implement ChainlinkForkTest
// =============================================================
/// @notice Fork tests for Chainlink price feed integration.
/// @dev Tests reading and validating oracle data.
contract ChainlinkForkTest is BaseTest {
    // Chainlink price feeds on mainnet
    AggregatorV3Interface constant ETH_USD_FEED =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    AggregatorV3Interface constant BTC_USD_FEED =
        AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

    AggregatorV3Interface constant USDC_USD_FEED =
        AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    // =============================================================
    //  TODO 2: Test Reading Latest Price
    // =============================================================
    /// @notice Verifies that we can read the latest ETH/USD price.
    function test_GetLatestETHPrice() public view {
        // TODO: Implement
        // 1. Call latestRoundData() on ETH_USD_FEED
        // 2. Extract the answer (price)
        // 3. Assert price > 0
        // 4. Assert price is within reasonable range (e.g., > $100 and < $100,000)
        // 5. Log the price:
        //    uint8 decimals = ETH_USD_FEED.decimals();
        //    console.log("ETH/USD Price:", uint256(answer));
        //    console.log("Decimals:", decimals);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Test Price Feed Metadata
    // =============================================================
    /// @notice Verifies price feed metadata (decimals, description).
    function test_PriceFeedMetadata() public view {
        // TODO: Implement
        // 1. Get decimals from ETH_USD_FEED
        // 2. Get description from ETH_USD_FEED
        // 3. Assert decimals == 8 (standard for USD feeds)
        // 4. Assert description contains "ETH" or "USD"
        // 5. Log the metadata
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Test Data Freshness
    // =============================================================
    /// @notice Verifies that price data is recent (not stale).
    function test_PriceDataFreshness() public view {
        // TODO: Implement
        // 1. Get latest round data
        // 2. Check updatedAt timestamp
        // 3. Calculate age: block.timestamp - updatedAt
        // 4. Assert age < 1 hour (3600 seconds)
        //    Note: Chainlink updates ETH/USD feed every ~1 hour or 0.5% price change
        // 5. Log the age:
        //    console.log("Price age (seconds):", age);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Test Multiple Price Feeds
    // =============================================================
    /// @notice Reads prices from multiple Chainlink feeds.
    function test_MultiplePriceFeeds() public view {
        // TODO: Implement
        // 1. Read ETH/USD price
        // 2. Read BTC/USD price
        // 3. Read USDC/USD price
        // 4. Assert all prices > 0
        // 5. Assert BTC > ETH (sanity check)
        // 6. Assert USDC ≈ $1 (within 5% tolerance)
        //    Hint: USDC has 8 decimals in the feed
        //    acceptable range: 0.95e8 to 1.05e8
        // 7. Log all prices
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Test Historical Round Data
    // =============================================================
    /// @notice Reads historical price data from a previous round.
    function test_HistoricalRoundData() public view {
        // TODO: Implement
        // 1. Get latest round data to get current roundId
        // 2. Get data from a previous round (roundId - 10)
        // 3. Assert historical price > 0
        // 4. Assert historical updatedAt < current updatedAt
        // 5. Compare historical price to current price
        // 6. Log both prices and the difference
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 7: Implement Safe Price Reading Function
    // =============================================================
    /// @notice Reads price with staleness check and validation.
    /// @param feed The Chainlink price feed
    /// @param maxStaleness Maximum acceptable age in seconds
    /// @return price The validated price
    function getSafePrice(AggregatorV3Interface feed, uint256 maxStaleness) internal view returns (uint256 price) {
        // TODO: Implement
        // 1. Call latestRoundData()
        // 2. Validate answer > 0 (revert InvalidPrice if not)
        // 3. Validate updatedAt > 0 (revert InvalidPrice if not)
        // 4. Check staleness: block.timestamp - updatedAt <= maxStaleness
        //    (revert StalePrice if stale)
        // 5. Return uint256(answer)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 8: Test Safe Price Function
    // =============================================================
    /// @notice Tests the safe price reading function.
    function test_SafePriceReading() public view {
        // TODO: Implement
        // 1. Call getSafePrice with 1 hour max staleness
        // 2. Assert price > 0
        // 3. Assert price is in reasonable range
        revert("Not implemented");
    }

    function test_SafePrice_RevertOnStaleness() public {
        // TODO: Implement
        // 1. Try to read price with very strict staleness (e.g., 1 second)
        // 2. Expect revert with StalePrice error
        //    vm.expectRevert(StalePrice.selector);
        //    getSafePrice(ETH_USD_FEED, 1);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 9: Calculate Derived Price
    // =============================================================
    /// @notice Calculates a derived price from two feeds (e.g., ETH/BTC).
    function test_DerivedPrice() public view {
        // TODO: Implement
        // 1. Get ETH/USD price
        // 2. Get BTC/USD price
        // 3. Calculate ETH/BTC = (ETH/USD) / (BTC/USD)
        //    Note: Both feeds have 8 decimals, so:
        //    ethBtcPrice = (ethUsdPrice * 1e8) / btcUsdPrice
        // 4. Assert 0 < ETH/BTC < 1 (ETH is cheaper than BTC)
        // 5. Log the derived price
        revert("Not implemented");
    }
}

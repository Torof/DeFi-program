// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

// ============================================================================
// EXERCISE: Safe Chainlink Consumer
//
// Build an oracle consumer that reads Chainlink price feeds with all the
// safety checks that production protocols implement. Then extend it to handle
// multi-feed price derivation and L2 sequencer uptime verification.
//
// This is the #1 practical oracle skill. Every DeFi protocol that touches
// price data needs these patterns. Protocols that skip them get exploited —
// Venus Protocol ($11M, 2023) skipped staleness checks, and attackers
// borrowed against stale collateral prices during BSC network issues.
//
// Concepts exercised:
//   - The 4 mandatory Chainlink safety checks
//   - Decimal normalization (never hardcode to 8!)
//   - Multi-feed price derivation (ETH/EUR from ETH/USD and EUR/USD)
//   - L2 sequencer uptime verification with grace period
//
// Key references:
//   - Chainlink Data Feeds: https://docs.chain.link/data-feeds/using-data-feeds
//   - L2 Sequencer Feeds: https://docs.chain.link/data-feeds/l2-sequencer-feeds
//   - Aave AaveOracle: https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol
//
// Run: forge test --match-contract OracleConsumerTest -vvv
// ============================================================================

// --- Custom Errors ---
error InvalidPrice();
error RoundNotComplete();
error StalePrice();
error StaleRound();
error SequencerDown();
error GracePeriodNotOver();
error InvalidStaleness();

/// @notice A safe Chainlink oracle consumer with all production-grade checks.
/// @dev In real Aave/Compound/Liquity, these checks live in a dedicated oracle
///      wrapper contract. Your core protocol never calls Chainlink directly —
///      it goes through this wrapper, which centralizes feed addresses,
///      decimal normalization, and validation logic.
contract OracleConsumer {
    // --- State ---

    /// @dev Maximum allowed age of a price update (in seconds).
    ///      Should be set to the feed's heartbeat + a buffer.
    ///      Example: ETH/USD heartbeat = 3600s → maxStaleness = 4500s (1h15m)
    uint256 public immutable maxStaleness;

    // --- Constants ---

    /// @dev Grace period after L2 sequencer restarts (in seconds).
    ///      When a sequencer comes back online, Chainlink feeds need time
    ///      to receive fresh data. During this window, prices may still be stale.
    ///      Aave V3 on Arbitrum uses this pattern.
    uint256 public constant GRACE_PERIOD = 3600; // 1 hour

    constructor(uint256 _maxStaleness) {
        if (_maxStaleness == 0) revert InvalidStaleness();
        maxStaleness = _maxStaleness;
    }

    // =============================================================
    //  TODO 1: Implement getPrice — the 4 mandatory Chainlink checks
    // =============================================================
    /// @notice Reads and validates a price from a Chainlink feed.
    /// @dev Every production protocol must perform these 4 checks before
    ///      using a Chainlink price. Skipping ANY of them is a vulnerability.
    ///
    ///      The checks (all are mandatory):
    ///        1. answer > 0       → price must be positive
    ///           Why: Some feeds CAN return negative values (e.g., interest rate feeds).
    ///           For price feeds, negative means something is very wrong.
    ///
    ///        2. updatedAt > 0    → the round must be complete
    ///           Why: If updatedAt == 0, the round hasn't been finalized yet.
    ///           Reading an incomplete round gives unreliable data.
    ///
    ///        3. block.timestamp - updatedAt < maxStaleness → data is fresh
    ///           Why: Chainlink updates on deviation OR heartbeat. Between updates,
    ///           the on-chain price can lag behind the real market price.
    ///           If the lag exceeds your threshold, the price is too old to trust.
    ///
    ///        4. answeredInRound >= roundId → round is finalized
    ///           Why: If the answer comes from a previous round, the current round
    ///           hasn't produced a result yet — the data may be outdated.
    ///
    /// Steps:
    ///   1. Cast feed address to IAggregatorV3 and call latestRoundData()
    ///   2. Apply all 4 checks, reverting with the appropriate custom error
    ///   3. Return the answer as uint256
    ///
    /// Hint: The return type of answer is int256 (Chainlink's choice — some feeds
    ///       support negative values). Cast to uint256 only AFTER verifying > 0.
    ///
    /// @param feed Address of the Chainlink price feed (proxy address)
    /// @return price The validated price (raw, with feed-specific decimals)
    function getPrice(address feed) public view returns (uint256 price) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement getNormalizedPrice — decimal normalization
    // =============================================================
    /// @notice Returns the feed price normalized to 18 decimals.
    /// @dev Different Chainlink feeds use different decimal precisions:
    ///        - Most USD feeds: 8 decimals  (ETH/USD: 300000000000 = $3,000.00)
    ///        - ETH-based feeds: 18 decimals (BTC/ETH: 15.5e18 = 15.5 ETH)
    ///
    ///      Hardcoding decimals to 8 is a common bug. If your protocol uses a
    ///      BTC/ETH feed (18 decimals) and assumes 8, you'll be off by 10^10.
    ///
    ///      Normalization formula:
    ///        normalizedPrice = rawPrice × 10^(18 - feedDecimals)
    ///
    /// Steps:
    ///   1. Get the validated price via getPrice(feed)
    ///   2. Read the feed's decimals via IAggregatorV3(feed).decimals()
    ///   3. Scale: price × 10^(18 - feedDecimals)
    ///
    /// Hint: All your internal protocol math should work in 18 decimals.
    ///       Normalize at the boundary (when reading from oracle), not in core logic.
    ///
    /// @param feed Address of the Chainlink price feed
    /// @return normalizedPrice The price scaled to 18 decimal places
    function getNormalizedPrice(address feed) public view returns (uint256 normalizedPrice) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement getDerivedPrice — multi-feed combination
    // =============================================================
    /// @notice Derives a cross-rate from two Chainlink feeds.
    /// @dev Many price pairs don't have a direct Chainlink feed. You derive them:
    ///
    ///      ETH/EUR = ETH/USD ÷ EUR/USD
    ///      BTC/ETH = BTC/USD ÷ ETH/USD
    ///
    ///      Both feeds are read and normalized to 18 decimals first, then
    ///      divided with proper scaling to produce the result in targetDecimals.
    ///
    ///      Example with real numbers:
    ///        ETH/USD = $3,000 (normalized: 3000e18)
    ///        EUR/USD = $1.08  (normalized: 1.08e18)
    ///        ETH/EUR = 3000e18 × 10^8 / 1.08e18 = ~2778e8 (at 8 decimals)
    ///
    /// Steps:
    ///   1. Get both normalized prices (18 decimals each) via getNormalizedPrice()
    ///   2. Compute: priceA × 10^targetDecimals / priceB
    ///
    /// Hint: Both inputs are already in 18 decimals from getNormalizedPrice().
    ///       Multiplying by 10^targetDecimals before dividing preserves precision.
    ///
    /// @param feedA The numerator feed (e.g., ETH/USD)
    /// @param feedB The denominator feed (e.g., EUR/USD)
    /// @param targetDecimals Desired decimal places in the result
    /// @return derivedPrice The cross-rate with targetDecimals precision
    function getDerivedPrice(
        address feedA,
        address feedB,
        uint8 targetDecimals
    ) external view returns (uint256 derivedPrice) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement _checkSequencerUp — L2 sequencer validation
    // =============================================================
    /// @notice Verifies the L2 sequencer is up and past the grace period.
    /// @dev On L2 networks (Arbitrum, Optimism, Base), transactions flow through
    ///      a centralized sequencer. If the sequencer goes down:
    ///        - No new transactions are processed on L2
    ///        - Chainlink nodes can't post updates to L2
    ///        - When the sequencer restarts, the "updatedAt" timestamps look fresh
    ///          (relative to L2 time) but prices may still reflect pre-downtime values
    ///
    ///      Chainlink provides Sequencer Uptime Feeds for L2s:
    ///        - answer == 0  → sequencer is UP
    ///        - answer == 1  → sequencer is DOWN
    ///        - startedAt    → timestamp when the sequencer last came back online
    ///
    ///      After the sequencer restarts, you MUST wait for a grace period before
    ///      trusting price feeds. This gives Chainlink nodes time to post fresh data.
    ///
    /// Steps:
    ///   1. Read latestRoundData() from the sequencer feed
    ///   2. If answer != 0 → revert SequencerDown
    ///   3. Compute timeSinceUp = block.timestamp - startedAt
    ///   4. If timeSinceUp <= GRACE_PERIOD → revert GracePeriodNotOver
    ///
    /// Hint: The grace period protects against a subtle attack: the sequencer
    ///       restarts, prices look "fresh" because updatedAt just changed, but
    ///       the underlying price data hasn't actually been refreshed yet.
    ///       Aave V3 on Arbitrum implements exactly this check.
    ///
    /// @param sequencerFeed Address of the L2 Sequencer Uptime Feed
    function _checkSequencerUp(address sequencerFeed) internal view {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement getL2Price — the full L2 pattern
    // =============================================================
    /// @notice Reads a price on L2 with sequencer verification.
    /// @dev This combines the sequencer check with the normalized price read.
    ///      The pattern: ALWAYS check the sequencer BEFORE reading any price on L2.
    ///
    ///      In production, this is the function your L2-deployed lending protocol
    ///      calls. On L1, you'd call getNormalizedPrice() directly.
    ///
    /// Steps:
    ///   1. Call _checkSequencerUp(sequencerFeed) — reverts if sequencer is down or in grace
    ///   2. Return getNormalizedPrice(feed)
    ///
    /// @param feed Address of the Chainlink price feed
    /// @param sequencerFeed Address of the L2 Sequencer Uptime Feed
    /// @return normalizedPrice The validated, normalized price
    function getL2Price(address feed, address sequencerFeed) external view returns (uint256 normalizedPrice) {
        revert("Not implemented");
    }
}

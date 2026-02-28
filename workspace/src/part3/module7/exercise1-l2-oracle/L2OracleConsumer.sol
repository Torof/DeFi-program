// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE 1: L2-Aware Oracle Consumer
//
// Build an oracle consumer that integrates Chainlink's L2 Sequencer Uptime
// Feed with a grace period, protecting a lending protocol from liquidations
// based on stale prices during sequencer downtime.
//
// This is the Aave V3 PriceOracleSentinel pattern — the gold standard for
// L2 lending safety. Without it, users can be liquidated while the sequencer
// is down and they can't defend their positions.
//
// Concepts exercised:
//   - Chainlink L2 sequencer uptime feed integration
//   - Grace period pattern (PriceOracleSentinel)
//   - Defense-in-depth: multiple safety conditions combined
//   - L2-specific risk handling that doesn't exist on L1
//
// Key references:
//   - Module 7 lesson: "Sequencer Uptime & Oracle Safety" section
//   - Module 7 lesson: PriceOracleSentinel code example
//   - Chainlink docs: L2 Sequencer Uptime Feeds
//   - Aave V3: PriceOracleSentinel.sol
//
// Run: forge test --match-contract L2OracleTest -vvv
// ============================================================================

error SequencerDown();
error GracePeriodNotPassed();
error StalePrice();
error InvalidPrice();

/// @notice Oracle consumer with L2 sequencer safety checks.
/// @dev Pre-built: constructor, state, interfaces.
///      Student implements: isSequencerUp, isGracePeriodPassed, getPrice,
///      isLiquidationAllowed, isBorrowAllowed.
contract L2OracleConsumer {
    // --- Interfaces (simplified) ---
    /// @dev Matches Chainlink AggregatorV3Interface.latestRoundData()
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    // --- State ---
    address public immutable sequencerFeed;  // L2 sequencer uptime feed
    address public immutable priceFeed;      // Asset price feed (e.g., ETH/USD)
    uint256 public immutable gracePeriod;    // Seconds to wait after sequencer restart
    uint256 public immutable stalenessThreshold; // Max age of price data in seconds

    constructor(
        address _sequencerFeed,
        address _priceFeed,
        uint256 _gracePeriod,
        uint256 _stalenessThreshold
    ) {
        sequencerFeed = _sequencerFeed;
        priceFeed = _priceFeed;
        gracePeriod = _gracePeriod;
        stalenessThreshold = _stalenessThreshold;
    }

    // =============================================================
    //  TODO 1: Implement isSequencerUp
    // =============================================================
    /// @notice Check if the L2 sequencer is currently operational.
    /// @dev Reads the Chainlink sequencer uptime feed:
    ///
    ///      The feed returns latestRoundData() where:
    ///        answer = 0 → sequencer is UP
    ///        answer = 1 → sequencer is DOWN
    ///
    ///      Steps:
    ///        1. Call latestRoundData() on sequencerFeed
    ///        2. Return true if answer == 0 (UP)
    ///
    ///      Hint: Cast sequencerFeed to call latestRoundData():
    ///        (, int256 answer,,,) = IFeed(sequencerFeed).latestRoundData();
    ///
    ///      The interface is the same as any Chainlink AggregatorV3.
    ///
    /// @return True if the sequencer is up
    function isSequencerUp() public view returns (bool) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement isGracePeriodPassed
    // =============================================================
    /// @notice Check if enough time has elapsed since the sequencer restarted.
    /// @dev After a sequencer comes back up, users need time to manage their
    ///      positions before liquidations are allowed. This is the "grace period."
    ///
    ///      From the lesson (Aave PriceOracleSentinel):
    ///        The sequencer feed's `startedAt` field tells us WHEN the current
    ///        status began. If the sequencer just came back up, startedAt is
    ///        the restart timestamp.
    ///
    ///      Steps:
    ///        1. Call latestRoundData() on sequencerFeed
    ///        2. Calculate elapsed = block.timestamp - startedAt
    ///        3. Return true if elapsed >= gracePeriod
    ///
    ///      Numeric example:
    ///        gracePeriod = 1 hour (3600 seconds)
    ///        Sequencer restarts at t=100
    ///        At t=3500: elapsed=3400 < 3600 → false (still in grace period)
    ///        At t=3800: elapsed=3700 > 3600 → true (grace period passed)
    ///
    /// @return True if the grace period has passed since last restart
    function isGracePeriodPassed() public view returns (bool) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement getPrice
    // =============================================================
    /// @notice Get the asset price with all safety checks.
    /// @dev Combines sequencer check + grace period + staleness check.
    ///      This is the function that all price-dependent operations should use.
    ///
    ///      Steps:
    ///        1. Check sequencer is up → revert SequencerDown() if not
    ///        2. Check grace period has passed → revert GracePeriodNotPassed() if not
    ///        3. Read price from priceFeed via latestRoundData()
    ///        4. Check price > 0 → revert InvalidPrice() if not
    ///        5. Check freshness: block.timestamp - updatedAt <= stalenessThreshold
    ///           → revert StalePrice() if stale
    ///        6. Return the price as uint256
    ///
    ///      This ordering matters: check sequencer FIRST because if it's down,
    ///      the price data might be stale anyway.
    ///
    /// @return price The current asset price (8 decimals for USD feeds)
    function getPrice() public view returns (uint256 price) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement isLiquidationAllowed
    // =============================================================
    /// @notice Check if liquidations are currently allowed.
    /// @dev Liquidations are BLOCKED when:
    ///        - Sequencer is down (users can't add collateral)
    ///        - Grace period hasn't passed (users need time to react)
    ///
    ///      Returns false (not revert) for UI-friendly status checking.
    ///
    ///      Steps:
    ///        1. Return isSequencerUp() AND isGracePeriodPassed()
    ///
    /// @return True if liquidations are safe to execute
    function isLiquidationAllowed() external view returns (bool) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement isBorrowAllowed
    // =============================================================
    /// @notice Check if new borrows are currently allowed.
    /// @dev New borrows are BLOCKED during the same conditions as liquidations.
    ///      If the sequencer is down or grace period hasn't passed, opening
    ///      new positions is risky because:
    ///        - Price data might be stale (bad collateral valuation)
    ///        - Users might not be able to manage the position if sequencer
    ///          goes down again
    ///
    ///      Note: Repayments and collateral deposits are ALWAYS allowed —
    ///      these reduce risk and should never be blocked.
    ///
    /// @return True if new borrows are safe to execute
    function isBorrowAllowed() external view returns (bool) {
        // YOUR CODE HERE
    }
}

/// @dev Minimal interface for Chainlink AggregatorV3 calls.
interface IFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: TWAP Oracle
//
// Build a Time-Weighted Average Price oracle from scratch. TWAP oracles
// record periodic price observations and compute the average price over a
// time window, making them resistant to single-block price manipulation.
//
// This is the same mechanism Uniswap V2 uses with its cumulative price
// accumulators (price0CumulativeLast / price1CumulativeLast). The key insight:
// a flash loan attacker can move the spot price for one block (~12 seconds),
// but that only contributes ~0.7% to a 30-minute TWAP. Sustaining the
// manipulation for the full window costs hundreds of thousands of dollars
// in losses to arbitrageurs.
//
// How cumulative price accumulators work:
//   - Each observation stores: (cumulativePrice, timestamp)
//   - cumulativePrice grows by: previousPrice × timeElapsed
//   - TWAP between two points = (cumulative2 - cumulative1) / (time2 - time1)
//   - This is exactly Uniswap V2's approach (UQ112.112 fixed-point)
//
// Concepts exercised:
//   - Cumulative price accumulators (the Uniswap V2 pattern)
//   - Circular buffer for bounded-memory observation storage
//   - Time-weighted average computation
//   - Minimum window enforcement (short windows degenerate to spot)
//   - Spot vs TWAP deviation (used by dual-oracle patterns)
//
// Key references:
//   - Uniswap V2 Oracle: https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/building-an-oracle
//   - Uniswap V3 Oracle: https://docs.uniswap.org/concepts/protocol/oracle
//   - samczsun on oracles: https://samczsun.com/so-you-want-to-use-a-price-oracle/
//
// Run: forge test --match-contract TWAPOracleTest -vvv
// ============================================================================

// --- Custom Errors ---
error InsufficientHistory();
error WindowTooShort();
error ObservationTooOld();
error ZeroPrice();

/// @notice A TWAP oracle using cumulative price accumulators in a circular buffer.
/// @dev Records price observations over time. Each observation stores the
///      cumulative price sum (Σ price_i × duration_i) and a timestamp.
///      The TWAP between any two observations is:
///        TWAP = (cumulative_new - cumulative_old) / (time_new - time_old)
///
///      This contract is designed to be called by an external keeper or hook
///      that provides spot price observations at regular intervals.
contract TWAPOracle {
    // --- Types ---

    /// @dev A single price observation in the circular buffer.
    ///      cumulativePrice = running sum of (price × time) from the start.
    ///      timestamp = block.timestamp when this observation was recorded.
    struct Observation {
        uint256 cumulativePrice;
        uint32 timestamp;
    }

    // --- State ---

    /// @dev Circular buffer of observations
    Observation[100] public observations;

    /// @dev Next write index in the circular buffer
    uint256 public observationIndex;

    /// @dev Total observations recorded (capped at MAX_OBSERVATIONS)
    uint256 public observationCount;

    /// @dev The last recorded spot price (used to compute cumulative delta)
    uint256 public lastPrice;

    /// @dev Timestamp of the last recorded observation
    uint32 public lastTimestamp;

    // --- Constants ---

    /// @dev Maximum observations stored (circular buffer size)
    uint256 public constant MAX_OBSERVATIONS = 100;

    /// @dev Minimum TWAP window in seconds (5 minutes).
    ///      Shorter windows approach spot price and lose manipulation resistance.
    ///      Production oracles typically use 30 minutes (1800s) minimum.
    uint256 public constant MIN_WINDOW = 300;

    // =============================================================
    //  TODO 1: Implement recordObservation
    // =============================================================
    /// @notice Records a new price observation into the circular buffer.
    /// @dev The cumulative price grows by: lastPrice × timeElapsed.
    ///
    ///      This is the same concept as Uniswap V2's cumulative price:
    ///        priceCumulative(t) = Σ(price_i × duration_i)
    ///
    ///      Visual (3 observations, prices P1=100, P2=150, P3=120):
    ///
    ///        Time:        0       60s      120s     180s
    ///        Spot price:  P1=100  P2=150   P3=120
    ///        Cumulative:  0       6000     15000    22200
    ///                     │       │        │        │
    ///                     │       │ +100×60│ +150×60│ +120×60
    ///                     │       │ =6000  │ =15000 │ =22200
    ///
    ///        TWAP(0→180) = (22200 - 0) / (180 - 0) = 123.3
    ///        TWAP(60→180) = (22200 - 6000) / (180 - 60) = 135.0
    ///
    /// Steps:
    ///   1. Require spotPrice > 0 (revert ZeroPrice)
    ///   2. If first observation (observationCount == 0):
    ///      - Store Observation(cumulativePrice: 0, timestamp: block.timestamp)
    ///      - Set lastPrice = spotPrice, lastTimestamp = block.timestamp
    ///      - Increment observationCount, advance observationIndex
    ///      - Return early
    ///   3. For subsequent observations:
    ///      - timeElapsed = uint32(block.timestamp) - lastTimestamp
    ///      - Get the previous latest observation's cumulativePrice
    ///      - newCumulative = prevCumulative + (lastPrice × timeElapsed)
    ///      - Store new Observation at observations[observationIndex]
    ///      - Advance observationIndex: (observationIndex + 1) % MAX_OBSERVATIONS
    ///      - Increment observationCount (cap at MAX_OBSERVATIONS)
    ///      - Update lastPrice = spotPrice, lastTimestamp = block.timestamp
    ///
    /// Hint: The key insight is that the cumulative price at time T includes
    ///       the PREVIOUS spot price multiplied by the elapsed time. The new
    ///       spotPrice only starts accumulating from NOW until the next observation.
    ///
    /// @param spotPrice The current spot price to record
    function recordObservation(uint256 spotPrice) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement _getLatestObservation
    // =============================================================
    /// @notice Returns the most recent observation from the buffer.
    /// @dev The observationIndex always points to the NEXT write position.
    ///      So the latest observation is one step BACK from observationIndex.
    ///
    ///      Example (MAX_OBSERVATIONS = 5):
    ///        After 3 observations: buffer = [O0, O1, O2, _, _], index = 3
    ///        Latest = observations[(3 + 5 - 1) % 5] = observations[2] ✓
    ///
    ///        After 6 observations (wrapped): buffer = [O5, O1, O2, O3, O4], index = 1
    ///        Latest = observations[(1 + 5 - 1) % 5] = observations[0] = O5 ✓
    ///
    /// Steps:
    ///   1. Require observationCount > 0 (revert InsufficientHistory)
    ///   2. Compute latestIndex = (observationIndex + MAX_OBSERVATIONS - 1) % MAX_OBSERVATIONS
    ///   3. Return observations[latestIndex]
    ///
    /// @return The most recently recorded Observation
    function _getLatestObservation() internal view returns (Observation memory) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement consult — compute the TWAP
    // =============================================================
    /// @notice Computes the TWAP over the specified time window.
    /// @dev The TWAP formula:
    ///        TWAP = (cumulative_latest - cumulative_old) / (time_latest - time_old)
    ///
    ///      This searches backward through the circular buffer to find an
    ///      observation at or before (latestTimestamp - window).
    ///
    ///      Important: The consult function reads the STORED observations but
    ///      the latest cumulative value may not include time since the last
    ///      recordObservation call. For simplicity, we compute the "extended"
    ///      cumulative at query time:
    ///        extendedCumulative = latest.cumulativePrice + lastPrice × (now - latest.timestamp)
    ///
    ///      This ensures the TWAP is always up-to-date even if recordObservation
    ///      hasn't been called recently.
    ///
    /// Steps:
    ///   1. Require window >= MIN_WINDOW (revert WindowTooShort)
    ///   2. Require observationCount >= 2 (revert InsufficientHistory)
    ///   3. Get the latest observation
    ///   4. Compute extendedCumulative:
    ///      latest.cumulativePrice + lastPrice × (block.timestamp - latest.timestamp)
    ///   5. Compute targetTimestamp = block.timestamp - window
    ///   6. Search backward through the buffer (starting from the observation
    ///      before latest) to find the newest observation at or before targetTimestamp
    ///      - Loop through min(observationCount - 1, MAX_OBSERVATIONS - 1) entries
    ///      - Use modular arithmetic to walk backward through the circular buffer
    ///      - If observation.timestamp <= targetTimestamp, use it as the "old" observation
    ///   7. If no suitable observation found: revert ObservationTooOld
    ///   8. TWAP = (extendedCumulative - old.cumulativePrice) / (block.timestamp - old.timestamp)
    ///   9. Return the TWAP
    ///
    /// Hint: Walking backward in a circular buffer:
    ///       Start at (latestIndex - 1 + MAX_OBSERVATIONS) % MAX_OBSERVATIONS
    ///       Then keep subtracting 1 (with modular wrap) for each step.
    ///
    /// @param window The time window in seconds to average over
    /// @return twapPrice The time-weighted average price over the window
    function consult(uint256 window) external view returns (uint256 twapPrice) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement getDeviation — spot vs TWAP comparison
    // =============================================================
    /// @notice Computes the deviation between a spot price and the TWAP, in basis points.
    /// @dev Used by dual-oracle patterns to detect when two price sources disagree.
    ///
    ///      deviation_bps = |spotPrice - twapPrice| × 10000 / twapPrice
    ///
    ///      Example:
    ///        spotPrice = 3300, twapPrice = 3000
    ///        deviation = |3300 - 3000| × 10000 / 3000 = 1000 bps (10%)
    ///
    /// Steps:
    ///   1. Get the TWAP via consult(window)
    ///   2. Compute absolute difference: |spotPrice - twapPrice|
    ///   3. deviation_bps = diff × 10000 / twapPrice
    ///   4. Return deviationBps
    ///
    /// Hint: For the absolute difference, check which is larger before subtracting
    ///       to avoid underflow.
    ///
    /// @param spotPrice The current spot price to compare against TWAP
    /// @param window The TWAP window to use
    /// @return deviationBps The deviation in basis points
    function getDeviation(uint256 spotPrice, uint256 window) external view returns (uint256 deviationBps) {
        revert("Not implemented");
    }
}

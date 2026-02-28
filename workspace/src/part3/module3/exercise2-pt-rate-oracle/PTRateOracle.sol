// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: PT Rate Oracle — Implied Rate Math & Time-Weighted Average Rate
//
// Build an oracle that computes, records, and averages implied rates
// from PT (Principal Token) prices. This exercises two key concepts:
//
// 1. Implied Rate Math — the fixed-point arithmetic behind yield tokenization:
//      impliedRate = (WAD - ptPrice) * YEAR * WAD / (ptPrice * timeToMaturity)
//      ptPrice = WAD * YEAR / (YEAR + rate * timeToMaturity / WAD)
//
// 2. TWAR (Time-Weighted Average Rate) — the same accumulator pattern as
//    Uniswap V2's TWAP oracle, applied to implied rates:
//      cumulativeRate += currentRate * timeElapsed
//      TWAR = (cumulative_end - cumulative_start) / (time_end - time_start)
//
// This combines:
//   - The rate math from Pendle's yield tokenization
//   - The oracle accumulator from Uniswap V2 (Part 2 Module 3)
//   - Fixed-point arithmetic (WAD precision)
//   - YT break-even analysis (yield speculation math)
//
// Run: forge test --match-contract PTRateOracleTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroTimeToMaturity();
error ZeroPTPrice();
error PTAbovePar();
error InsufficientObservations();
error InvalidPeriod();

/// @notice Oracle that computes and tracks implied rates from PT prices.
/// @dev Pre-built: constructor, state, Observation struct, constants.
///      Student implements: getImpliedRate, getPTPrice, recordObservation,
///                          getTimeWeightedRate, getYTBreakEven.
contract PTRateOracle {
    // --- Types ---

    struct Observation {
        uint256 timestamp;       // block.timestamp at recording
        uint256 impliedRateWad;  // implied annual rate at this observation (18 dec)
        uint256 cumulativeRate;  // cumulative rate × time (for TWAR)
    }

    // --- State ---

    /// @dev Maturity timestamp for the PT market being tracked.
    uint256 public immutable maturity;

    /// @dev All recorded rate observations.
    Observation[] public observations;

    // --- Constants ---

    /// @dev 1e18 — fixed-point precision.
    uint256 public constant WAD = 1e18;

    /// @dev Seconds per year (365 days).
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // --- Constructor ---

    constructor(uint256 maturity_) {
        maturity = maturity_;
    }

    /// @dev Helper to get the number of observations recorded.
    function observationCount() external view returns (uint256) {
        return observations.length;
    }

    // =============================================================
    //  TODO 1: Implement getImpliedRate
    // =============================================================
    /// @notice Calculate the implied annual rate from a PT price and time to maturity.
    /// @dev Formula (simple compounding):
    ///
    ///                  (WAD - ptPriceWad)   SECONDS_PER_YEAR
    ///   impliedRate = ──────────────────── × ─────────────────
    ///                     ptPriceWad         timeToMaturity
    ///
    ///   In fixed-point:
    ///     rate = (WAD - ptPriceWad) * SECONDS_PER_YEAR * WAD / (ptPriceWad * timeToMaturity)
    ///
    ///   Example:
    ///     ptPrice = 0.97e18, timeToMaturity = 182.5 days = 15_768_000 seconds
    ///     rate = (1e18 - 0.97e18) * 31_536_000 * 1e18 / (0.97e18 * 15_768_000)
    ///          = 0.03e18 * 31_536_000e18 / (0.97e18 * 15_768_000)
    ///          ≈ 0.06186e18 (6.19% annual)
    ///
    ///   Steps:
    ///     1. Revert with ZeroPTPrice if ptPriceWad == 0
    ///     2. Revert with PTAbovePar if ptPriceWad >= WAD (no discount = no rate)
    ///     3. Revert with ZeroTimeToMaturity if timeToMaturity == 0
    ///     4. Compute and return: (WAD - ptPriceWad) * SECONDS_PER_YEAR * WAD
    ///                            / (ptPriceWad * timeToMaturity)
    ///
    /// @param ptPriceWad PT price in WAD (e.g., 0.97e18 means 3% discount)
    /// @param timeToMaturity Seconds until maturity
    /// @return rateWad Implied annual rate in WAD (e.g., 0.0619e18 = 6.19%)
    function getImpliedRate(uint256 ptPriceWad, uint256 timeToMaturity)
        public
        pure
        returns (uint256 rateWad)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement getPTPrice
    // =============================================================
    /// @notice Calculate the PT price from a target annual rate and time to maturity.
    /// @dev This is the INVERSE of getImpliedRate. Given a desired rate,
    ///      what should the PT price be?
    ///
    ///   Formula:
    ///                       WAD × SECONDS_PER_YEAR
    ///     ptPrice = ──────────────────────────────────────────
    ///               SECONDS_PER_YEAR + rateWad × timeToMaturity / WAD
    ///
    ///   In fixed-point:
    ///     ptPrice = WAD * SECONDS_PER_YEAR * WAD
    ///              / (SECONDS_PER_YEAR * WAD + rateWad * timeToMaturity)
    ///
    ///   Example:
    ///     rate = 0.05e18 (5%), timeToMaturity = 91.25 days = 7_884_000 seconds
    ///     denom = 31_536_000e18 + 0.05e18 * 7_884_000 = 31_536_000e18 + 394_200e18
    ///           = 31_930_200e18
    ///     ptPrice = 1e18 * 31_536_000e18 / 31_930_200e18 ≈ 0.98766e18
    ///
    ///   Steps:
    ///     1. Revert with ZeroTimeToMaturity if timeToMaturity == 0
    ///     2. Compute denominator = SECONDS_PER_YEAR * WAD + rateWad * timeToMaturity
    ///     3. Return WAD * SECONDS_PER_YEAR * WAD / denominator
    ///
    ///   Note: if rateWad == 0, ptPrice == WAD (no discount).
    ///
    /// @param rateWad Target annual rate in WAD (e.g., 0.05e18 = 5%)
    /// @param timeToMaturity Seconds until maturity
    /// @return ptPriceWad PT price in WAD
    function getPTPrice(uint256 rateWad, uint256 timeToMaturity)
        public
        pure
        returns (uint256 ptPriceWad)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement recordObservation
    // =============================================================
    /// @notice Record a PT price observation, computing and storing the implied rate.
    /// @dev This builds the TWAR (Time-Weighted Average Rate) accumulator.
    ///      Each observation stores:
    ///        - timestamp
    ///        - impliedRate (computed from ptPrice and time to maturity)
    ///        - cumulativeRate (previous cumulative + rate × timeElapsed)
    ///
    ///      The cumulative rate is the key to efficient TWAR queries
    ///      (same pattern as Uniswap V2's price0CumulativeLast).
    ///
    ///      Steps:
    ///        1. Compute timeToMaturity = maturity - block.timestamp
    ///           (revert with ZeroTimeToMaturity if maturity <= block.timestamp)
    ///        2. Compute the implied rate via getImpliedRate(ptPriceWad, timeToMaturity)
    ///        3. Compute the new cumulativeRate:
    ///           - If this is the first observation: cumulativeRate = 0
    ///             (no elapsed time to accumulate over)
    ///           - Otherwise: get the last observation, compute timeElapsed,
    ///             and add: lastCumulative + lastRate * timeElapsed
    ///        4. Push a new Observation to the array
    ///
    ///      Hint: timeElapsed = block.timestamp - lastObservation.timestamp
    ///            cumulativeRate += lastObservation.impliedRateWad * timeElapsed
    ///            (We accumulate the PREVIOUS rate over the elapsed period,
    ///             not the current rate — same as Uniswap V2.)
    ///
    /// @param ptPriceWad Current PT price in WAD
    function recordObservation(uint256 ptPriceWad) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement getTimeWeightedRate
    // =============================================================
    /// @notice Get the time-weighted average rate between two observations.
    /// @dev Uses the cumulative rate accumulator for O(1) TWAR calculation.
    ///
    ///      Formula:
    ///        TWAR = (cumulative[endIdx] - cumulative[startIdx])
    ///               / (timestamp[endIdx] - timestamp[startIdx])
    ///
    ///      This is EXACTLY the same pattern as Uniswap V2's TWAP:
    ///        TWAP = (priceCumulative_end - priceCumulative_start)
    ///               / (timestamp_end - timestamp_start)
    ///
    ///      Steps:
    ///        1. Revert with InsufficientObservations if observations.length < 2
    ///        2. Revert with InvalidPeriod if startIdx >= endIdx
    ///        3. Get observations at startIdx and endIdx
    ///        4. Compute timeDelta = end.timestamp - start.timestamp
    ///        5. Revert with InvalidPeriod if timeDelta == 0
    ///        6. Compute rateDelta = end.cumulativeRate - start.cumulativeRate
    ///        7. Return rateDelta / timeDelta (this is the average rate in WAD)
    ///
    /// @param startIdx Index of the start observation
    /// @param endIdx Index of the end observation
    /// @return twarWad Time-weighted average rate in WAD
    function getTimeWeightedRate(uint256 startIdx, uint256 endIdx)
        external
        view
        returns (uint256 twarWad)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement getYTBreakEven
    // =============================================================
    /// @notice Calculate the break-even annual yield for a YT purchase.
    /// @dev If you buy YT at ytPriceWad, what average annual yield does the
    ///      underlying need to produce for you to break even?
    ///
    ///      Since PT + YT = 1 underlying, buying YT at 0.03 means you pay
    ///      0.03 per unit of yield entitlement. To break even, the actual
    ///      yield over the remaining period must equal your cost.
    ///
    ///      Formula:
    ///        breakEvenRate = ytPriceWad * SECONDS_PER_YEAR / timeToMaturity
    ///
    ///      Intuition: if YT costs 0.03 and there are 6 months to maturity,
    ///        you need 0.03 yield over 6 months = 6% annualized.
    ///
    ///      Example:
    ///        ytPrice = 0.03e18, timeToMaturity = 15_768_000 (182.5 days)
    ///        breakEven = 0.03e18 * 31_536_000 / 15_768_000
    ///                  = 0.06e18 (6% annual)
    ///
    ///      Steps:
    ///        1. Revert with ZeroTimeToMaturity if timeToMaturity == 0
    ///        2. Revert with ZeroPTPrice if ytPriceWad == 0 (would mean free YT)
    ///        3. Return ytPriceWad * SECONDS_PER_YEAR / timeToMaturity
    ///
    ///      Note: This is a simplified calculation using linear approximation.
    ///            It gives a good estimate for maturities < 1 year.
    ///
    /// @param ytPriceWad YT price in WAD (e.g., 0.03e18)
    /// @param timeToMaturity Seconds until maturity
    /// @return breakEvenRateWad Annualized break-even yield in WAD
    function getYTBreakEven(uint256 ytPriceWad, uint256 timeToMaturity)
        public
        pure
        returns (uint256 breakEvenRateWad)
    {
        // YOUR CODE HERE
    }
}

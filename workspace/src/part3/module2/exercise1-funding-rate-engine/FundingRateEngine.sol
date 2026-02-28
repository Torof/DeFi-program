// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Funding Rate Engine — The O(1) Accumulator Pattern
//
// Build the core funding rate mechanism used by every perpetual protocol.
// This is the SAME mathematical pattern as:
//   - Compound's borrowIndex
//   - Aave's liquidityIndex
//   - ERC-4626 share pricing
//   - Synthetix's debtEntryIndex
//
// The key idea: maintain a global counter that accumulates over time.
// Each position records the counter at open. The difference at close
// tells you the funding owed — O(1) per settlement, no iteration.
//
// This engine implements SKEW-BASED funding (Synthetix/GMX V2 style):
//   fundingRate = (longOpenInterest - shortOpenInterest) / skewScale
//   - Net long skew → positive rate → longs pay shorts
//   - Net short skew → negative rate → shorts pay longs
//   - Balanced OI → zero rate → no payments
//
// Concepts exercised:
//   - Global cumulative funding index (per-second continuous funding)
//   - Skew-based funding rate calculation
//   - Per-position funding settlement using the accumulator
//   - Correct signed math (int256) for bidirectional payments
//   - Time-weighted accumulation
//
// Key references:
//   - Module 2 lesson: part3/2-perpetuals.md#funding-accumulator
//   - Synthetix PerpsV2: skew-based funding model
//   - GMX V2: fundingFeeAmountPerSize accumulator
//
// Run: forge test --match-contract FundingRateEngineTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroSize();
error PositionAlreadyExists();
error NoPosition();

/// @notice Minimal funding rate engine demonstrating the accumulator pattern.
/// @dev Pre-built: constructor, state, position struct, OI tracking, view helpers.
///      Student implements: updateFunding, openPosition, closePosition, settlePosition,
///                          getCurrentFundingRate, getPendingFunding.
contract FundingRateEngine {
    // --- Types ---

    struct Position {
        uint256 size; // position size in USD (8 decimals)
        bool isLong; // true = long, false = short
        int256 entryFundingIndex; // snapshot of cumulativeFundingPerUnit at open
    }

    // --- State ---

    /// @dev Global cumulative funding per unit of position size (18 decimals).
    ///      Grows over time as funding accrues. Positive means longs have been
    ///      paying (net long skew historically).
    int256 public cumulativeFundingPerUnit;

    /// @dev Timestamp of last funding update.
    uint256 public lastFundingTimestamp;

    /// @dev Total long open interest in USD (8 decimals).
    uint256 public longOpenInterest;

    /// @dev Total short open interest in USD (8 decimals).
    uint256 public shortOpenInterest;

    /// @dev Per-user position. One position per address (simplified).
    mapping(address => Position) public positions;

    // --- Constants ---

    /// @dev Skew scale denominator — controls funding rate sensitivity.
    ///      A $100M skew scale means $1M net skew produces a 1% funding rate.
    ///      In production, this is a governance parameter tuned per market.
    uint256 public constant SKEW_SCALE = 100_000_000e8; // $100M in 8-decimal USD

    /// @dev Seconds per day — used to normalize funding rate to a per-day basis.
    uint256 public constant SECONDS_PER_DAY = 86_400;

    /// @dev 1e18 — fixed-point precision for the accumulator.
    uint256 private constant WAD = 1e18;

    constructor() {
        lastFundingTimestamp = block.timestamp;
    }

    // =============================================================
    //  TODO 1: Implement getCurrentFundingRate
    // =============================================================
    /// @notice Calculate the current instantaneous funding rate.
    /// @dev Skew-based: rate = (longOI - shortOI) * WAD / SKEW_SCALE
    ///
    ///      The rate is a signed value in 18-decimal fixed-point:
    ///        Positive → longs pay shorts (net long skew)
    ///        Negative → shorts pay longs (net short skew)
    ///        Zero → balanced OI, no funding
    ///
    ///      Example:
    ///        longOI  = 60_000_000e8 ($60M)
    ///        shortOI = 40_000_000e8 ($40M)
    ///        skew    = 20_000_000e8 ($20M net long)
    ///        rate    = 20_000_000e8 * 1e18 / 100_000_000e8
    ///                = 0.2e18 (20% per day — very high, just illustrative)
    ///
    ///      Steps:
    ///        1. Compute skew = int256(longOI) - int256(shortOI)
    ///        2. Return skew * int256(WAD) / int256(SKEW_SCALE)
    ///
    /// @return rate The funding rate in 18-decimal fixed-point (per day)
    function getCurrentFundingRate() public view returns (int256 rate) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement updateFunding
    // =============================================================
    /// @notice Update the global cumulative funding index.
    /// @dev This MUST be called before any position change (open, close, settle)
    ///      to ensure the accumulator reflects all elapsed time.
    ///
    ///      The math:
    ///        elapsed = block.timestamp - lastFundingTimestamp
    ///        fundingPerUnit = currentFundingRate * elapsed / SECONDS_PER_DAY
    ///        cumulativeFundingPerUnit += fundingPerUnit
    ///
    ///      We divide by SECONDS_PER_DAY because getCurrentFundingRate() returns
    ///      a per-day rate, and elapsed is in seconds. This converts to the
    ///      actual funding that accrued over the elapsed period.
    ///
    ///      Example:
    ///        Rate = 0.01e18 (1% per day)
    ///        Elapsed = 3600 seconds (1 hour)
    ///        fundingPerUnit = 0.01e18 * 3600 / 86400 = 0.000416...e18
    ///        This is the funding per unit of position size for the elapsed period.
    ///
    ///      Steps:
    ///        1. Calculate elapsed seconds since last update
    ///        2. If elapsed == 0, return early (nothing to do)
    ///        3. Get the current funding rate via getCurrentFundingRate()
    ///        4. Compute fundingPerUnit = rate * elapsed / SECONDS_PER_DAY
    ///        5. Add fundingPerUnit to cumulativeFundingPerUnit
    ///        6. Set lastFundingTimestamp = block.timestamp
    ///
    ///      Hint: All math is in int256 (signed) because the rate can be negative.
    ///            Cast elapsed to int256 for the multiplication.
    ///
    function updateFunding() public {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement openPosition
    // =============================================================
    /// @notice Open a new position and record the funding index snapshot.
    /// @dev This is where the "per-user snapshot" part of the accumulator
    ///      pattern happens. The position records the current value of
    ///      cumulativeFundingPerUnit, so later we can compute the diff.
    ///
    ///      Steps:
    ///        1. Revert with ZeroSize if size is 0
    ///        2. Revert with PositionAlreadyExists if user already has a position
    ///           (positions[msg.sender].size > 0)
    ///        3. Call updateFunding() to bring the accumulator current
    ///        4. Store the position:
    ///           - size = size
    ///           - isLong = isLong
    ///           - entryFundingIndex = cumulativeFundingPerUnit (snapshot!)
    ///        5. Update open interest:
    ///           - If long: longOpenInterest += size
    ///           - If short: shortOpenInterest += size
    ///
    ///      Note: In a real protocol, the user would transfer collateral here.
    ///            We skip that to focus purely on the funding math.
    ///
    /// @param size Position size in USD (8 decimals)
    /// @param isLong True for long, false for short
    function openPosition(uint256 size, bool isLong) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement getPendingFunding
    // =============================================================
    /// @notice Calculate the pending funding for a position WITHOUT updating state.
    /// @dev This is a view function — it shows what funding would be owed/earned
    ///      if settled right now, INCLUDING the unaccrued portion since the last
    ///      updateFunding() call.
    ///
    ///      The math:
    ///        1. Compute the "live" accumulator: current cumulativeFundingPerUnit
    ///           plus the funding that would accrue from lastFundingTimestamp to now.
    ///        2. delta = liveAccumulator - position.entryFundingIndex
    ///        3. rawFunding = position.size * delta / WAD
    ///        4. Apply sign convention:
    ///           - Longs: positive delta means longs pay → funding is NEGATIVE (cost)
    ///           - Shorts: positive delta means shorts receive → funding is POSITIVE (income)
    ///           So: longs return -rawFunding, shorts return +rawFunding
    ///
    ///      Sign convention summary:
    ///        Return > 0 → position RECEIVES funding (income)
    ///        Return < 0 → position PAYS funding (cost)
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position (size == 0)
    ///        2. Compute elapsed time since lastFundingTimestamp
    ///        3. Compute unaccrued funding: getCurrentFundingRate() * elapsed / SECONDS_PER_DAY
    ///        4. liveAccumulator = cumulativeFundingPerUnit + unaccrued
    ///        5. delta = liveAccumulator - position.entryFundingIndex
    ///        6. rawFunding = int256(position.size) * delta / int256(WAD)
    ///        7. If long: return -rawFunding (longs pay when delta is positive)
    ///           If short: return rawFunding (shorts receive when delta is positive)
    ///
    ///      Hint: Be careful with the sign convention. A positive cumulative
    ///            funding means the system has been net-long, so longs have been
    ///            paying. For a long position, accumulated funding is a COST.
    ///
    /// @param user The address to check
    /// @return funding Signed funding amount (8 decimals). Positive = receive, negative = pay.
    function getPendingFunding(address user) external view returns (int256 funding) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement closePosition
    // =============================================================
    /// @notice Close a position and return the settled funding amount.
    /// @dev Settles all pending funding, removes the position, and updates OI.
    ///
    ///      Steps:
    ///        1. Revert with NoPosition if user has no position (size == 0)
    ///        2. Call updateFunding() to bring the accumulator current
    ///        3. Compute funding delta: cumulativeFundingPerUnit - entryFundingIndex
    ///        4. Compute rawFunding: int256(size) * delta / int256(WAD)
    ///        5. Apply sign: longs get -rawFunding, shorts get +rawFunding
    ///        6. Update open interest:
    ///           - If long: longOpenInterest -= size
    ///           - If short: shortOpenInterest -= size
    ///        7. Delete the position (set size = 0)
    ///        8. Return the signed funding amount
    ///
    ///      Note: In a real protocol, this would adjust the trader's collateral
    ///            by the funding amount. We just return it here.
    ///
    /// @return funding Signed funding amount (8 decimals). Positive = receive, negative = pay.
    function closePosition() external returns (int256 funding) {
        // YOUR CODE HERE
    }
}

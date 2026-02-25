// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Interest Rate Model — Kinked Curve + Compound Interest
//
// Build the core math engine behind Aave/Compound interest rates.
//
// This is a PURE MATH exercise — no tokens, no protocol state, no transfers.
// You'll implement the same arithmetic that runs inside every lending protocol:
//
//   1. RAY arithmetic (27 decimals) — the industry standard for rate math
//   2. Utilization rate — how much of deposited capital is borrowed
//   3. Kinked borrow rate — the two-slope curve that incentivizes optimal utilization
//   4. Supply rate — what lenders earn (derived from borrow rate)
//   5. Compound interest — Taylor approximation used by Aave V3
//
// The kinked curve is the most important concept:
//
//   Rate
//    │            slope2 (steep)
//    │              ╱
//    │             ╱
//    │         ___╱ ← kink (optimal utilization)
//    │     ___╱  slope1 (gentle)
//    │ ___╱
//    │╱ base rate
//    └──────────────────────── Utilization
//    0%      optimal      100%
//
// Below optimal: gentle slope (slope1) encourages borrowing
// Above optimal: steep slope (slope2) discourages excess borrowing
//
// Real protocol references:
//   - Aave V3 DefaultReserveInterestRateStrategyV2.sol
//   - Compound III BaseInterestRateModel.sol
//   - Spark Protocol DaiInterestRateStrategy.sol
//
// Run: forge test --match-contract InterestRateModelTest -vvv
// ============================================================================

/// @notice Kinked interest rate model with compound interest calculation.
/// @dev All rates use RAY precision (1e27 = 100%). This matches Aave V3's
///      internal math. The kinked curve creates a two-slope system where
///      rates increase gently until optimal utilization, then steeply after.
contract InterestRateModel {
    // --- Constants ---
    uint256 public constant RAY = 1e27;
    uint256 public constant HALF_RAY = 0.5e27;

    // --- Immutables (set in constructor) ---
    /// @notice Minimum borrow rate (y-intercept of the curve)
    uint256 public immutable baseRateRay;
    /// @notice Rate slope below optimal utilization (gentle)
    uint256 public immutable slope1Ray;
    /// @notice Rate slope above optimal utilization (steep — the "kink")
    uint256 public immutable slope2Ray;
    /// @notice Target utilization ratio (the "kink point")
    uint256 public immutable optimalUtilizationRay;

    constructor(
        uint256 _baseRateRay,
        uint256 _slope1Ray,
        uint256 _slope2Ray,
        uint256 _optimalUtilizationRay
    ) {
        baseRateRay = _baseRateRay;
        slope1Ray = _slope1Ray;
        slope2Ray = _slope2Ray;
        optimalUtilizationRay = _optimalUtilizationRay;
    }

    // =============================================================
    //  PROVIDED: rayDiv — study this, then implement rayMul
    // =============================================================
    /// @notice Divides two RAY values with rounding to nearest.
    /// @dev Formula: (a * RAY + b/2) / b
    ///      The b/2 term provides "round to nearest" instead of "round down".
    ///
    ///      Example:
    ///        rayDiv(3e27, 2e27) = (3e27 * 1e27 + 1e27) / 2e27 = 1.5e27
    ///
    ///      In Aave V3: WadRayMath.rayDiv()
    function rayDiv(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }

    // =============================================================
    //  TODO 1: Implement rayMul
    // =============================================================
    /// @notice Multiplies two RAY values with rounding to nearest.
    /// @dev This is the bread-and-butter operation of all lending protocol math.
    ///      Every interest calculation, every index update, every rate computation
    ///      goes through rayMul.
    ///
    ///      Formula: (a * b + HALF_RAY) / RAY
    ///
    ///      Why HALF_RAY? Banker's rounding. Without it:
    ///        rayMul(1, 5e26) = (5e26) / 1e27 = 0  ← truncates to zero
    ///      With HALF_RAY:
    ///        rayMul(1, 5e26) = (5e26 + 5e26) / 1e27 = 1  ← rounds correctly
    ///
    ///      Examples:
    ///        rayMul(2e27, 3e27) = 6e27     (2 × 3 = 6)
    ///        rayMul(1e27, 0.5e27) = 0.5e27 (1 × 0.5 = 0.5)
    ///        rayMul(anything, 0) = 0
    ///
    ///      In Aave V3: WadRayMath.rayMul()
    ///
    /// @param a First RAY value
    /// @param b Second RAY value
    /// @return result The product in RAY
    function rayMul(uint256 a, uint256 b) public pure returns (uint256 result) {
        // solhint-disable-next-line no-unused-vars
        result; // silence unused variable warning
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement getUtilization
    // =============================================================
    /// @notice Calculates the utilization rate of the pool.
    /// @dev Utilization = totalBorrows / totalDeposits (in RAY)
    ///
    ///      This is the x-axis of the kinked curve diagram above.
    ///
    ///      Examples:
    ///        deposits=1000, borrows=500  → utilization = 0.5e27  (50%)
    ///        deposits=1000, borrows=800  → utilization = 0.8e27  (80%)
    ///        deposits=1000, borrows=1000 → utilization = 1.0e27  (100%)
    ///        deposits=0,    borrows=0    → utilization = 0       (empty pool)
    ///
    ///      Edge case: if totalDeposits == 0, return 0 (avoid division by zero).
    ///
    ///      In Aave V3: this is computed inline in calculateInterestRates()
    ///
    /// Steps:
    ///   1. If totalDeposits == 0, return 0
    ///   2. Return totalBorrows * RAY / totalDeposits
    ///
    /// @param totalDeposits Total deposits in the pool
    /// @param totalBorrows Total borrows from the pool
    /// @return utilization The utilization rate in RAY (0 to 1e27)
    function getUtilization(uint256 totalDeposits, uint256 totalBorrows)
        public
        pure
        returns (uint256 utilization)
    {
        // solhint-disable-next-line no-unused-vars
        utilization; // silence unused variable warning
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement getBorrowRate
    // =============================================================
    /// @notice Calculates the borrow rate using the kinked curve.
    /// @dev This is the core of the interest rate model — the two-slope
    ///      piecewise linear function that all major lending protocols use.
    ///
    ///      Below optimal (util ≤ optimal):
    ///        rate = baseRate + slope1 × (util / optimal)
    ///
    ///        The division by optimal normalizes utilization to [0, 1] within
    ///        the below-kink region. At util=optimal, the slope1 term = slope1.
    ///
    ///      Above optimal (util > optimal):
    ///        rate = baseRate + slope1 + slope2 × (util − optimal) / (1 − optimal)
    ///
    ///        The (util − optimal) / (1 − optimal) normalizes the excess
    ///        utilization to [0, 1] within the above-kink region.
    ///
    ///      Worked example (with our test params):
    ///        baseRate=0.02, slope1=0.08, slope2=1.00, optimal=0.80
    ///
    ///        At 40% utilization (below kink):
    ///          rate = 0.02 + 0.08 × (0.40/0.80) = 0.02 + 0.04 = 0.06 (6%)
    ///
    ///        At 80% utilization (at kink):
    ///          rate = 0.02 + 0.08 × (0.80/0.80) = 0.02 + 0.08 = 0.10 (10%)
    ///
    ///        At 90% utilization (above kink):
    ///          rate = 0.02 + 0.08 + 1.00 × (0.90−0.80)/(1−0.80)
    ///               = 0.10 + 1.00 × 0.50 = 0.60 (60%)  ← Steep!
    ///
    ///      Notice the dramatic jump from 10% to 60% — that's the kink in action.
    ///      It strongly incentivizes bringing utilization back below optimal.
    ///
    /// Steps:
    ///   1. Compute utilization via getUtilization()
    ///   2. If utilization <= optimalUtilizationRay:
    ///      return baseRateRay + rayMul(slope1Ray, rayDiv(utilization, optimalUtilizationRay))
    ///   3. Else:
    ///      excessUtilization = utilization - optimalUtilizationRay
    ///      maxExcess = RAY - optimalUtilizationRay
    ///      return baseRateRay + slope1Ray + rayMul(slope2Ray, rayDiv(excessUtilization, maxExcess))
    ///
    /// @param totalDeposits Total deposits in the pool
    /// @param totalBorrows Total borrows from the pool
    /// @return rate The annual borrow rate in RAY
    function getBorrowRate(uint256 totalDeposits, uint256 totalBorrows)
        public
        view
        returns (uint256 rate)
    {
        // solhint-disable-next-line no-unused-vars
        rate; // silence unused variable warning
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement getSupplyRate
    // =============================================================
    /// @notice Calculates the supply rate (what lenders earn).
    /// @dev Supply rate is derived from the borrow rate:
    ///
    ///      supplyRate = borrowRate × utilization × (1 − reserveFactor)
    ///
    ///      Why this formula?
    ///        - borrowRate × utilization: interest is paid only on borrowed capital,
    ///          but distributed across ALL deposited capital
    ///        - (1 − reserveFactor): protocol takes a cut (typically 10-20%)
    ///
    ///      Example:
    ///        borrowRate = 10%, utilization = 80%, reserveFactor = 15%
    ///        supplyRate = 0.10 × 0.80 × 0.85 = 0.068 = 6.8%
    ///
    ///      Borrowers pay 10% on their loans. But only 80% of deposits are
    ///      borrowed, so the effective rate spread across all deposits is 8%.
    ///      The protocol takes 15% of that, leaving lenders with 6.8%.
    ///
    ///      In Aave V3: ReserveLogic._updateInterestRatesAndVirtualBalance()
    ///
    /// Steps:
    ///   1. Compute borrowRate via getBorrowRate()
    ///   2. Compute utilization via getUtilization()
    ///   3. Return rayMul(rayMul(borrowRate, utilization), RAY - reserveFactorRay)
    ///
    /// @param totalDeposits Total deposits
    /// @param totalBorrows Total borrows
    /// @param reserveFactorRay Protocol's cut in RAY (e.g., 0.15e27 = 15%)
    /// @return rate The annual supply rate in RAY
    function getSupplyRate(uint256 totalDeposits, uint256 totalBorrows, uint256 reserveFactorRay)
        public
        view
        returns (uint256 rate)
    {
        // solhint-disable-next-line no-unused-vars
        rate; // silence unused variable warning
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement calculateCompoundInterest
    // =============================================================
    /// @notice Approximates compound interest using a 3-term Taylor expansion.
    /// @dev In continuous compounding: multiplier = e^(r × t)
    ///
    ///      The Taylor expansion of e^x = 1 + x + x²/2! + x³/3! + ...
    ///
    ///      For discrete compounding over `exp` periods at rate `rate`:
    ///        (1 + rate)^exp ≈ 1 + rate×exp + rate²×exp×(exp-1)/2 + rate³×exp×(exp-1)×(exp-2)/6
    ///
    ///      This is what Aave V3 uses in MathUtils.calculateCompoundedInterest().
    ///      The approximation is excellent because rate-per-second is tiny:
    ///
    ///      For 10% APR: ratePerSecond ≈ 3.17e-9 (3.17e18 in RAY)
    ///
    ///        Term magnitudes over 1 year (31.5M seconds):
    ///        ┌───────────┬────────────────────────────┐
    ///        │ Term 1    │ r×t         ≈ 0.10000      │  (the rate itself)
    ///        │ Term 2    │ r²×t²/2     ≈ 0.00500      │  (0.5% correction)
    ///        │ Term 3    │ r³×t³/6     ≈ 0.00017      │  (0.017% correction)
    ///        │ Term 4+   │ negligible  ≈ 0.0000004    │  (safely ignored)
    ///        └───────────┴────────────────────────────┘
    ///
    ///      So 3 terms gives accuracy to ~0.00004% — good enough for DeFi.
    ///
    /// Steps:
    ///   1. If exp == 0, return RAY (no time passed → no interest)
    ///   2. Compute term1: rate * exp (first Taylor term)
    ///   3. Compute term2: rayMul(rate, rate) * exp * expMinusOne / 2
    ///      ⚠️ Underflow guard: use expMinusOne = exp > 1 ? exp - 1 : 0
    ///      Note: exp * expMinusOne is a plain integer (not RAY), so use
    ///      plain multiplication — NOT rayMul. rayMul(rate, rate) gives rate²
    ///      in RAY, and multiplying by the integer time factors keeps it in RAY.
    ///   4. Compute term3: rayMul(rayMul(rate, rate), rate) * exp * expMinusOne * expMinusTwo / 6
    ///      ⚠️ Underflow guard: use expMinusTwo = exp > 2 ? exp - 2 : 0
    ///   5. Return RAY + term1 + term2 + term3
    ///
    /// @param rate The per-second interest rate in RAY
    /// @param exp The number of seconds elapsed
    /// @return multiplier The compound interest multiplier in RAY (≥ RAY)
    function calculateCompoundInterest(uint256 rate, uint256 exp)
        public
        pure
        returns (uint256 multiplier)
    {
        // solhint-disable-next-line no-unused-vars
        multiplier; // silence unused variable warning
        revert("Not implemented");
    }
}

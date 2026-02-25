// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
// EXERCISE: V3 Position Calculator
//
// Implement the math that computes how many tokens a Uniswap V3 concentrated
// liquidity position holds, given the current pool price and the position's
// price range.
//
// This is the core insight of V3: liquidity is deployed within a price range
// [P_lower, P_upper]. Depending on where the current price is relative to
// that range, the position holds different proportions of each token:
//
//   Price BELOW range  → 100% token0 (waiting to be bought)
//   Price ABOVE range  → 100% token1 (was fully converted)
//   Price WITHIN range → mix of both (active liquidity)
//
// All prices are encoded as sqrtPriceX96 = √P × 2^96 (Q96 fixed-point).
//
// Concepts exercised:
//   - Concentrated liquidity position math
//   - Q96 fixed-point arithmetic
//   - mulDiv for overflow-safe computation
//   - Three-case price range logic
//
// Key references:
//   - Uniswap V3 Whitepaper Section 6.2.1: https://uniswap.org/whitepaper-v3.pdf
//   - SqrtPriceMath.sol: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol
//   - LiquidityAmounts.sol: https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol
//
// Run: forge test --match-contract V3PositionCalculatorTest -vvv
// ============================================================================

// --- Custom Errors ---
error InvalidRange();
error ZeroLiquidity();

/// @notice Computes token amounts for a Uniswap V3 concentrated liquidity position.
/// @dev All sqrt prices are in Q96 format: sqrtPriceX96 = √P × 2^96
///      where P = price of token1 in terms of token0 (token0 per token1).
///
///      The math comes from V3's core insight: within a tick range, the pool
///      behaves like a "virtual" constant product AMM. The real token amounts
///      are the difference between the virtual amounts at the current price
///      and at the range boundaries.
library V3PositionCalculator {
    /// @dev 2^96 — the fixed-point scaling factor for sqrtPriceX96
    uint256 internal constant Q96 = 1 << 96;

    // =============================================================
    //  TODO 1: Implement getAmount0Delta
    // =============================================================
    /// @notice Computes the amount of token0 for a given liquidity and price range.
    /// @dev When the price drops BELOW a position's range, the position converts
    ///      entirely to token0. This function computes how much token0 that is.
    ///
    ///      Mathematical formula:
    ///        amount0 = L × (1/√P_lower - 1/√P_upper)
    ///
    ///      In Q96 fixed-point (to avoid division by fractional sqrt prices):
    ///        amount0 = L × 2^96 × (sqrtUpper - sqrtLower) / (sqrtLower × sqrtUpper)
    ///
    ///      To avoid overflow, split the computation into two steps:
    ///        Step 1: intermediate = mulDiv(L << 96, sqrtUpper - sqrtLower, sqrtUpper)
    ///        Step 2: amount0 = intermediate / sqrtLower
    ///
    ///      Why this works: mulDiv(a, b, c) computes (a × b) / c with a 512-bit
    ///      intermediate, preventing overflow. By dividing by sqrtUpper first and
    ///      sqrtLower second, we keep intermediate values within safe bounds.
    ///
    /// Hint: Use Math.mulDiv(a, b, c) from OpenZeppelin.
    ///       numerator = uint256(liquidity) << 96
    ///       diff = sqrtUpper - sqrtLower (cast to uint256 for safety)
    ///
    /// @param sqrtLowerX96 √P_lower × 2^96
    /// @param sqrtUpperX96 √P_upper × 2^96
    /// @param liquidity The position's liquidity (L)
    /// @return amount0 Token0 amount the position holds
    function getAmount0Delta(
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement getAmount1Delta
    // =============================================================
    /// @notice Computes the amount of token1 for a given liquidity and price range.
    /// @dev When the price rises ABOVE a position's range, the position converts
    ///      entirely to token1. This function computes how much token1 that is.
    ///
    ///      Mathematical formula:
    ///        amount1 = L × (√P_upper - √P_lower)
    ///
    ///      In Q96 fixed-point:
    ///        amount1 = L × (sqrtUpper - sqrtLower) / 2^96
    ///
    ///      This is simpler than amount0 because we multiply by the sqrt price
    ///      difference directly (no reciprocal needed).
    ///
    ///      Use: Math.mulDiv(liquidity, sqrtUpper - sqrtLower, Q96)
    ///
    /// Hint: Just one mulDiv call — simpler than getAmount0Delta.
    ///
    /// @param sqrtLowerX96 √P_lower × 2^96
    /// @param sqrtUpperX96 √P_upper × 2^96
    /// @param liquidity The position's liquidity (L)
    /// @return amount1 Token1 amount the position holds
    function getAmount1Delta(
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement getPositionAmounts — the three-case dispatcher
    // =============================================================
    /// @notice Computes the token0 and token1 amounts held by a position.
    /// @dev Three cases based on where the current price sits relative to
    ///      the position's range:
    ///
    ///      ┌─────────────────────────────────────────────────────┐
    ///      │                                                     │
    ///      │  Case 1           Case 3            Case 2          │
    ///      │  100% token0      Both tokens       100% token1     │
    ///      │                                                     │
    ///      │  ◄──────────┤ sqrtLower ├──────────┤ sqrtUpper ├──► │
    ///      │             │           │          │            │    │
    ///      │  price here │  price    │ here     │  price     │   │
    ///      │  ← all t0   │  = mix   │          │  → all t1  │   │
    ///      └─────────────────────────────────────────────────────┘
    ///
    ///      Case 1: sqrtPrice <= sqrtLower (price below range)
    ///        → amount0 = getAmount0Delta(sqrtLower, sqrtUpper, L)
    ///        → amount1 = 0
    ///
    ///      Case 2: sqrtPrice >= sqrtUpper (price above range)
    ///        → amount0 = 0
    ///        → amount1 = getAmount1Delta(sqrtLower, sqrtUpper, L)
    ///
    ///      Case 3: sqrtLower < sqrtPrice < sqrtUpper (price in range)
    ///        → amount0 = getAmount0Delta(sqrtPrice, sqrtUpper, L)
    ///        → amount1 = getAmount1Delta(sqrtLower, sqrtPrice, L)
    ///        (Split at current price: token0 from current→upper, token1 from lower→current)
    ///
    /// Hint: This is just an if/else dispatcher. The real logic is in
    ///       getAmount0Delta and getAmount1Delta.
    ///
    /// @param sqrtPriceX96 Current pool √P × 2^96
    /// @param sqrtLowerX96 Position's lower bound √P × 2^96
    /// @param sqrtUpperX96 Position's upper bound √P × 2^96
    /// @param liquidity Position's liquidity (L)
    /// @return amount0 Token0 amount
    /// @return amount1 Token1 amount
    function getPositionAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtLowerX96 >= sqrtUpperX96) revert InvalidRange();
        if (liquidity == 0) revert ZeroLiquidity();

        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4 (Extension): Implement getLiquidityForAmounts
    // =============================================================
    /// @notice Inverse of getPositionAmounts: given desired token amounts,
    ///         compute the maximum liquidity that can be provided.
    /// @dev Same three cases, but solving the formulas for L:
    ///
    ///      Case 1 (price below): L = amount0 × sqrtLower × sqrtUpper / (2^96 × (sqrtUpper - sqrtLower))
    ///      Case 2 (price above): L = amount1 × 2^96 / (sqrtUpper - sqrtLower)
    ///      Case 3 (price in range): L = min(L_from_amount0, L_from_amount1)
    ///
    ///      This is what the Uniswap V3 NonfungiblePositionManager uses when
    ///      you call mint() with desired token amounts — it computes the max
    ///      liquidity that fits within your budget.
    ///
    /// Reference: LiquidityAmounts.sol
    ///   https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol
    ///
    /// @param sqrtPriceX96 Current pool √P × 2^96
    /// @param sqrtLowerX96 Position's lower bound √P × 2^96
    /// @param sqrtUpperX96 Position's upper bound √P × 2^96
    /// @param amount0Desired Maximum token0 willing to deposit
    /// @param amount1Desired Maximum token1 willing to deposit
    /// @return liquidity Maximum liquidity achievable
    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal pure returns (uint128 liquidity) {
        if (sqrtLowerX96 >= sqrtUpperX96) revert InvalidRange();

        revert("Not implemented");
    }
}

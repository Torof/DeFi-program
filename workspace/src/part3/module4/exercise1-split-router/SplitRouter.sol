// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Split Router — Optimal Trade Splitting Across Two Pools
//
// Build a simple DEX router that demonstrates the core aggregation pattern:
// splitting a trade across two constant-product pools for better execution.
//
// This exercises the math from the curriculum:
//   - Constant-product output: out = reserveOut * amountIn / (reserveIn + amountIn)
//   - Optimal split approximation: δA/δB ≈ xA/xB (proportional to pool depth)
//   - The multi-call executor pattern (pull tokens, swap, verify output)
//
// Key insight: price impact is NONLINEAR. Doubling the trade size MORE than
// doubles the slippage. Splitting across pools reduces total slippage.
//
// Concepts exercised:
//   - AMM output formula applied to routing optimization
//   - Split order math (reserve-proportional splitting)
//   - Multi-call execution (the on-chain pattern every aggregator uses)
//   - Comparing single-pool vs split execution
//
// Run: forge test --match-contract SplitRouterTest -vvv
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal interface for the constant-product pools.
interface IPool {
    function swap(address tokenIn, uint256 amountIn, address to) external returns (uint256 amountOut);
    function getReserves(address tokenIn) external view returns (uint256 reserveIn, uint256 reserveOut);
}

// --- Custom Errors ---
error ZeroAmount();
error InsufficientOutput();
error InvalidPool();

/// @notice Simple router that splits trades across two constant-product pools.
/// @dev Pre-built: constructor, state, interfaces.
///      Student implements: getAmountOut, getOptimalSplit, splitSwap, singleSwap.
contract SplitRouter {
    // --- State ---

    /// @dev The two pools to route through (same token pair, different liquidity).
    IPool public immutable poolA;
    IPool public immutable poolB;

    // --- Constructor ---

    constructor(address poolA_, address poolB_) {
        poolA = IPool(poolA_);
        poolB = IPool(poolB_);
    }

    // =============================================================
    //  TODO 1: Implement getAmountOut
    // =============================================================
    /// @notice Calculate the output of a constant-product swap (no fee).
    /// @dev Formula:
    ///        amountOut = reserveOut * amountIn / (reserveIn + amountIn)
    ///
    ///      This is the same formula from Part 2 Module 2 (AMMs).
    ///      It's a refresher — you'll use it in getOptimalSplit.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amountIn == 0
    ///        2. Compute and return: reserveOut * amountIn / (reserveIn + amountIn)
    ///
    /// @param reserveIn  Input token reserve in the pool
    /// @param reserveOut Output token reserve in the pool
    /// @param amountIn   Amount of input token being swapped
    /// @return amountOut Amount of output token received
    function getAmountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn)
        public
        pure
        returns (uint256 amountOut)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement getOptimalSplit
    // =============================================================
    /// @notice Calculate the optimal split amounts for two pools.
    /// @dev Uses the reserve-proportional approximation from the curriculum:
    ///
    ///        δA / δB ≈ xA / xB
    ///
    ///      In other words, send more volume to the deeper pool.
    ///      If pool A has 2x the input reserves of pool B,
    ///      send 2x the amount through pool A.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if totalAmountIn == 0
    ///        2. Get reserves from both pools for the given tokenIn:
    ///           (reserveInA, _) = poolA.getReserves(tokenIn)
    ///           (reserveInB, _) = poolB.getReserves(tokenIn)
    ///        3. Compute amountToA = totalAmountIn * reserveInA / (reserveInA + reserveInB)
    ///        4. Compute amountToB = totalAmountIn - amountToA
    ///           (use subtraction, not division, to avoid rounding dust)
    ///        5. Return (amountToA, amountToB)
    ///
    ///      Note: This is an approximation that's exact when both pools have
    ///      the same spot price. For different prices, a more complex
    ///      optimization is needed — but this captures the key insight.
    ///
    /// @param tokenIn       Address of the input token
    /// @param totalAmountIn Total amount to split across both pools
    /// @return amountToA Amount to send to pool A
    /// @return amountToB Amount to send to pool B
    function getOptimalSplit(address tokenIn, uint256 totalAmountIn)
        public
        view
        returns (uint256 amountToA, uint256 amountToB)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement splitSwap
    // =============================================================
    /// @notice Execute a split trade across both pools.
    /// @dev This is the multi-call executor pattern — the core of every aggregator:
    ///      1. Pull tokens from the user
    ///      2. Split across pools
    ///      3. Swap through each pool
    ///      4. Verify minimum output
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amountIn == 0
    ///        2. Compute the split via getOptimalSplit(tokenIn, amountIn)
    ///        3. Pull amountIn of tokenIn from msg.sender to this contract
    ///           (use IERC20(tokenIn).transferFrom)
    ///        4. Transfer amountToA to address(poolA), then call poolA.swap
    ///           - Pass msg.sender as the `to` parameter (output goes directly to user)
    ///        5. Transfer amountToB to address(poolB), then call poolB.swap
    ///           - Pass msg.sender as the `to` parameter
    ///        6. Sum both outputs: totalOut = outA + outB
    ///        7. Revert with InsufficientOutput if totalOut < minAmountOut
    ///        8. Return totalOut
    ///
    ///      Note: Tokens go directly from router to pool, and pool sends output
    ///      directly to msg.sender. The router never holds output tokens.
    ///
    /// @param tokenIn     Address of the input token
    /// @param amountIn    Total amount of input token
    /// @param minAmountOut Minimum acceptable output (slippage protection)
    /// @return totalOut   Total output received across both pools
    function splitSwap(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 totalOut)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement singleSwap
    // =============================================================
    /// @notice Execute a trade through a single pool (for comparison).
    /// @dev Same pull-swap-verify pattern, but only one pool.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amountIn == 0
    ///        2. Revert with InvalidPool if pool is not poolA or poolB
    ///        3. Pull amountIn of tokenIn from msg.sender to this contract
    ///        4. Transfer amountIn to the pool, then call pool.swap
    ///           - Pass msg.sender as the `to` parameter
    ///        5. Revert with InsufficientOutput if amountOut < minAmountOut
    ///        6. Return amountOut
    ///
    /// @param pool        Address of the pool to use
    /// @param tokenIn     Address of the input token
    /// @param amountIn    Amount of input token
    /// @param minAmountOut Minimum acceptable output
    /// @return amountOut  Output received
    function singleSwap(address pool, address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut)
    {
        // YOUR CODE HERE
    }
}

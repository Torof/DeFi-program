// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHookCallback} from "../interfaces/IHookCallback.sol";

// ============================================================================
// EXERCISE: Dynamic Fee Hook
//
// Build a Uniswap V4-style hook that adjusts swap fees based on recent price
// volatility. When the market is calm, charge the standard 0.3% fee. When
// prices are swinging wildly, increase the fee to compensate LPs for the
// higher impermanent loss risk.
//
// This is a real V4 use case: dynamic fees are one of the most requested
// hook features, already implemented by protocols like Arrakis and Bunni.
//
// How this maps to real V4:
//   - In production, hooks extend BaseHook from v4-periphery
//   - Hook permissions are encoded in the hook CONTRACT ADDRESS (specific bits)
//   - The PoolManager calls hook.beforeSwap() during each swap
//   - The hook returns a fee override that applies to that swap
//   - This exercise uses a simplified IHookCallback interface instead
//
// Concepts exercised:
//   - Hook callback pattern (V4 lifecycle)
//   - Circular buffer for price tracking
//   - Volatility computation from price history
//   - Fee interpolation between bounds
//   - Access control (only pool manager can call)
//
// Key references:
//   - V4 Hooks overview: https://docs.uniswap.org/contracts/v4/concepts/hooks
//   - Hook development guide: https://docs.uniswap.org/contracts/v4/guides/hooks/your-first-hook
//   - Dynamic fee examples: https://github.com/fewwwww/awesome-uniswap-hooks
//
// Run: forge test --match-contract DynamicFeeHookTest -vvv
// ============================================================================

// --- Custom Errors ---
error OnlyPoolManager();
error WindowSizeTooSmall();

/// @notice A V4-style hook that returns higher swap fees during volatile markets.
/// @dev Tracks the last WINDOW_SIZE swap prices in a circular buffer. On each
///      swap, computes the max deviation from the mean price. If deviation
///      exceeds VOLATILITY_THRESHOLD, the fee scales linearly up to MAX_FEE.
///
///      Fee schedule:
///        volatility < VOLATILITY_THRESHOLD  → BASE_FEE (0.3%)
///        volatility >= MAX_VOLATILITY       → MAX_FEE (1.0%)
///        in between                         → linear interpolation
contract DynamicFeeHook is IHookCallback {
    // --- State ---

    /// @dev The authorized pool manager (only it can call beforeSwap)
    address public immutable poolManager;

    /// @dev Circular buffer of recent sqrtPriceX96 values
    uint160[10] public priceBuffer;

    /// @dev Next write index in the circular buffer (wraps around)
    uint256 public priceIndex;

    /// @dev Number of prices recorded so far (capped at WINDOW_SIZE)
    uint256 public priceCount;

    // --- Constants ---

    /// @dev Number of price observations to track
    uint256 public constant WINDOW_SIZE = 10;

    /// @dev Base fee: 0.3% = 3000 (in hundredths of a bip)
    uint24 public constant BASE_FEE = 3000;

    /// @dev Maximum fee: 1.0% = 10000
    uint24 public constant MAX_FEE = 10000;

    /// @dev Below this volatility (in bps), charge BASE_FEE
    ///      200 bps = 2% price deviation from mean
    uint256 public constant VOLATILITY_THRESHOLD = 200;

    /// @dev At or above this volatility (in bps), charge MAX_FEE
    ///      1000 bps = 10% price deviation from mean
    uint256 public constant MAX_VOLATILITY = 1000;

    constructor(address _poolManager) {
        poolManager = _poolManager;
    }

    // =============================================================
    //  TODO 1: Implement _recordPrice
    // =============================================================
    /// @notice Stores a new price in the circular buffer.
    /// @dev A circular buffer reuses array slots: when you reach the end,
    ///      you wrap around to the beginning. This keeps memory bounded
    ///      while always having the most recent WINDOW_SIZE observations.
    ///
    ///      Visual example (WINDOW_SIZE = 4):
    ///
    ///        Swap 1: [P1, _, _, _]  index=1, count=1
    ///        Swap 2: [P1, P2, _, _]  index=2, count=2
    ///        Swap 3: [P1, P2, P3, _]  index=3, count=3
    ///        Swap 4: [P1, P2, P3, P4]  index=0, count=4  (wraps!)
    ///        Swap 5: [P5, P2, P3, P4]  index=1, count=4  (overwrites P1)
    ///
    /// Steps:
    ///   1. Store sqrtPriceX96 at priceBuffer[priceIndex]
    ///   2. Advance priceIndex: (priceIndex + 1) % WINDOW_SIZE
    ///   3. Increment priceCount (but cap at WINDOW_SIZE — don't let it grow forever)
    ///
    /// @param sqrtPriceX96 The current pool price to record
    function _recordPrice(uint160 sqrtPriceX96) internal {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement _calculateMean
    // =============================================================
    /// @notice Computes the mean of all prices in the buffer.
    /// @dev Handle two cases:
    ///      - Partial window (priceCount < WINDOW_SIZE): only average the filled slots
    ///      - Full window: average all WINDOW_SIZE slots
    ///
    /// Steps:
    ///   1. Determine how many prices to average: min(priceCount, WINDOW_SIZE)
    ///   2. Sum all prices in the buffer (up to count)
    ///      ⚠️ Cast to uint256 before summing! uint160 values can overflow
    ///      when summed (10 × max_uint160 > max_uint256? No, but be safe)
    ///   3. Divide sum by count
    ///   4. Cast result back to uint160
    ///
    /// Hint: If priceCount == 0, return 0 (no data yet).
    ///
    /// @return mean The average sqrtPriceX96 in the buffer
    function _calculateMean() internal view returns (uint160 mean) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement _calculateVolatility
    // =============================================================
    /// @notice Computes the max deviation from mean, in basis points.
    /// @dev Volatility metric: find the price in the buffer that is FARTHEST
    ///      from the mean, express that distance as a percentage of the mean.
    ///
    ///      volatility_bps = max(|price_i - mean|) × 10000 / mean
    ///
    ///      Example:
    ///        mean = 100, prices = [95, 105, 98, 102]
    ///        deviations = [5, 5, 2, 2]
    ///        max deviation = 5
    ///        volatility_bps = 5 × 10000 / 100 = 500 bps (5%)
    ///
    /// Steps:
    ///   1. Calculate the mean using _calculateMean()
    ///   2. If mean == 0, return 0
    ///   3. Loop through the buffer (up to min(priceCount, WINDOW_SIZE))
    ///   4. For each price, compute |price - mean|:
    ///      - If price > mean: diff = price - mean
    ///      - If price <= mean: diff = mean - price
    ///   5. Track the maximum diff
    ///   6. Return: maxDiff × 10000 / mean
    ///
    /// @return volatilityBps Maximum deviation from mean in basis points
    function _calculateVolatility() internal view returns (uint256 volatilityBps) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement _computeFee
    // =============================================================
    /// @notice Maps volatility to a fee using linear interpolation.
    /// @dev The fee schedule:
    ///
    ///      Fee
    ///      (bps)
    ///      10000 ┤                     ┌──────────  MAX_FEE
    ///            │                    /
    ///            │                   /
    ///            │                  /   ← linear interpolation
    ///            │                 /
    ///       3000 ┤────────────────┘     BASE_FEE
    ///            │
    ///            └────────┬──────────┬──────────── Volatility (bps)
    ///                    200       1000
    ///                  THRESHOLD  MAX_VOL
    ///
    ///      Formula (for the linear region):
    ///        fee = BASE_FEE + (MAX_FEE - BASE_FEE) × (vol - THRESHOLD) / (MAX_VOL - THRESHOLD)
    ///
    /// Steps:
    ///   1. If volatilityBps <= VOLATILITY_THRESHOLD: return BASE_FEE
    ///   2. If volatilityBps >= MAX_VOLATILITY: return MAX_FEE
    ///   3. Otherwise: linear interpolation
    ///      - Use uint256 for the intermediate multiplication to avoid overflow
    ///      - Cast the result to uint24
    ///
    /// @param volatilityBps Current volatility in basis points
    /// @return fee The fee to charge, in hundredths of a bip
    function _computeFee(uint256 volatilityBps) internal pure returns (uint24 fee) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement beforeSwap — the main hook callback
    // =============================================================
    /// @notice Called by the pool manager before each swap.
    /// @dev This is the entry point. The pool manager passes swap context
    ///      and expects a fee in return.
    ///
    ///      In real V4:
    ///        - PoolManager calls this during swap() after unlock()
    ///        - The returned fee overrides the pool's default fee
    ///        - If the hook reverts, the entire swap reverts
    ///
    /// Steps:
    ///   1. Verify msg.sender == poolManager (revert OnlyPoolManager if not)
    ///   2. Record the current price: _recordPrice(params.sqrtPriceX96)
    ///   3. Calculate volatility: _calculateVolatility()
    ///   4. Compute and return fee: _computeFee(volatilityBps)
    ///
    /// @param params Swap context from the pool manager
    /// @return fee The dynamic fee for this swap
    function beforeSwap(SwapParams calldata params) external override returns (uint24 fee) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement getHookPermissions
    // =============================================================
    /// @notice Declares which hook callbacks this contract implements.
    /// @dev In real Uniswap V4, permissions are encoded in the hook's address:
    ///
    ///      Hook address: 0x...XXXX
    ///                          ^^^^ these bits encode permissions
    ///
    ///      Bit 0: beforeSwap
    ///      Bit 1: afterSwap
    ///      Bit 2: beforeAddLiquidity
    ///      etc.
    ///
    ///      Tools like CREATE2 with salt mining are used to find addresses with
    ///      the right bit pattern. See: Hooks.validateHookPermissions()
    ///
    ///      For this exercise, we use a struct instead. Return:
    ///        beforeSwap: true       (we adjust fees before each swap)
    ///        afterSwap: false
    ///        beforeAddLiquidity: false
    ///        afterAddLiquidity: false
    ///
    /// @return HookPermissions struct with enabled callbacks
    function getHookPermissions() external pure override returns (HookPermissions memory) {
        revert("Not implemented");
    }
}

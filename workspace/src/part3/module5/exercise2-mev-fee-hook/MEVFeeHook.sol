// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE 2: MEV-Aware Dynamic Fee Hook
//
// Implement a simplified Uniswap V4-style hook that detects potential sandwich
// patterns (opposite-direction swaps in the same block) and applies a dynamic
// fee surcharge. Normal users pay the base fee; suspected MEV bots pay more.
//
// The key insight: a sandwich attack requires a buy AND a sell of the SAME
// pair in the SAME block. If the second swap (the back-run) costs 3x the fee,
// the sandwich becomes unprofitable — the MEV is "internalized" by LPs.
//
// Concepts exercised:
//   - MEV detection heuristics (opposite-direction swaps in same block)
//   - Dynamic fee mechanism design (V4 hook pattern)
//   - The MEV internalization principle (capturing MEV for LPs)
//   - Per-block state tracking
//
// Key references:
//   - Module 5 lesson: "MEV-Aware Protocol Design" → Principle 3: Internalize MEV
//   - Module 5 lesson: MEVFeeHook code in "Uniswap V4 hooks — dynamic MEV fees"
//   - Uniswap V4 hooks documentation
//
// Run: forge test --match-contract MEVFeeHookTest -vvv
// ============================================================================

/// @notice Tracks swap activity per pool per block for MEV detection.
/// @dev Pre-built: struct, constants, events, view helpers.
///      Student implements: beforeSwap, isSandwichLikely.
///      Note: In V4, only the PoolManager can call hook functions. Simplified
///      here to focus on the MEV detection logic rather than V4 plumbing.
contract MEVFeeHook {
    // --- Types ---
    struct BlockSwapInfo {
        bool hasSwapZeroForOne;   // has a token0 → token1 swap happened?
        bool hasSwapOneForZero;   // has a token1 → token0 swap happened?
    }

    // --- State ---
    /// @dev poolId → blockNumber → swap activity tracking
    mapping(bytes32 => mapping(uint256 => BlockSwapInfo)) internal _blockSwaps;

    // --- Constants ---
    /// @dev Fee in hundredths of a bip: 3000 = 0.30%, 10000 = 1.00%
    uint24 public constant NORMAL_FEE = 3000;         // 0.30%
    uint24 public constant SUSPICIOUS_FEE = 10000;     // 1.00%

    // --- Events ---
    event SwapFeeApplied(
        bytes32 indexed poolId,
        bool zeroForOne,
        uint24 fee,
        bool suspicious
    );

    // =============================================================
    //  TODO 1: Implement beforeSwap
    // =============================================================
    /// @notice Called before each swap — detects suspicious patterns and returns fee.
    /// @dev This is the core of the MEV fee hook. The detection heuristic:
    ///
    ///      Sandwich signature:
    ///      ┌─────────────────────────────────────────────────┐
    ///      │  Block N:                                       │
    ///      │    tx 1: Attacker buys  A→B  (front-run)        │
    ///      │    tx 2: Victim buys   A→B  (target swap)       │
    ///      │    tx 3: Attacker sells B→A  (back-run) ← HERE  │
    ///      └─────────────────────────────────────────────────┘
    ///
    ///      When the back-run (tx 3) arrives, the hook sees that the OPPOSITE
    ///      direction (A→B) already happened this block → suspicious!
    ///
    ///      Logic:
    ///        1. Load the BlockSwapInfo for this pool and block.number
    ///        2. Check if the OPPOSITE direction already happened:
    ///           - If zeroForOne: check hasSwapOneForZero
    ///           - If !zeroForOne: check hasSwapZeroForOne
    ///        3. Record THIS swap's direction in the struct
    ///        4. Return SUSPICIOUS_FEE if opposite direction existed, NORMAL_FEE otherwise
    ///        5. Emit SwapFeeApplied event
    ///
    ///      Hint: The lesson code shows this exact pattern. The key insight is
    ///      checking the OPPOSITE direction flag, not the same direction.
    ///
    /// @param poolId Identifier of the pool being swapped on
    /// @param zeroForOne True if swapping token0 → token1, false if token1 → token0
    /// @return fee The dynamic fee to apply (in hundredths of a bip)
    function beforeSwap(bytes32 poolId, bool zeroForOne)
        external
        returns (uint24 fee)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement isSandwichLikely
    // =============================================================
    /// @notice Check if a full sandwich pattern has been detected for a pool.
    /// @dev A sandwich is "likely" when BOTH directions have been swapped in
    ///      the same block — that's the signature of front-run + back-run.
    ///
    ///      This is a view function for off-chain analysis or UI warnings.
    ///
    ///      Logic:
    ///        1. Load the BlockSwapInfo for this pool and block.number
    ///        2. Return true if BOTH hasSwapZeroForOne AND hasSwapOneForZero are true
    ///
    /// @param poolId Identifier of the pool to check
    /// @return True if both swap directions occurred in the current block
    function isSandwichLikely(bytes32 poolId) external view returns (bool) {
        // YOUR CODE HERE
    }

    // --- View helpers (pre-built) ---

    /// @notice Get the swap activity for a pool at a specific block.
    /// @dev Useful for off-chain analysis and debugging.
    function getBlockActivity(bytes32 poolId, uint256 blockNumber)
        external
        view
        returns (bool hasZeroForOne, bool hasOneForZero)
    {
        BlockSwapInfo storage info = _blockSwaps[poolId][blockNumber];
        return (info.hasSwapZeroForOne, info.hasSwapOneForZero);
    }
}

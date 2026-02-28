// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimplePool} from "./SimplePool.sol";

// ============================================================================
// EXERCISE 1 (continued): Sandwich Bot
//
// Implement the attacker side of a sandwich attack. This bot front-runs a
// victim's swap (pushing the price), then back-runs it (profiting from the
// price move). The test suite orchestrates the full 3-step sequence.
//
// This is NOT about learning to exploit — it's about understanding the
// attack mechanics so you can defend against them as a protocol designer.
//
// Concepts exercised:
//   - The three-step sandwich pattern (front-run → victim → back-run)
//   - Tracking attacker state across multiple transactions
//   - Understanding that profit comes from the price move between front/back runs
//
// Key references:
//   - Module 5 lesson: "Sandwich Attacks: Anatomy & Math" — the 3-step walkthrough
//   - Numeric example: 10,000 USDC front-run → 4.762 ETH → sell after victim → 11,940 USDC
//
// Run: forge test --match-contract SandwichSimTest -vvv
// ============================================================================

error NoPendingSandwich();

/// @notice Sandwich attack bot for educational demonstration.
/// @dev Pre-built: constructor, state tracking, approvals. Student implements: frontRun, backRun.
///      Note: No access control — in production, MEV bots use private mempools (Flashbots)
///      and ephemeral contracts, not persistent on-chain contracts. Simplified for the exercise.
contract SandwichBot {
    // --- State ---
    SimplePool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    // --- Sandwich tracking ---
    /// @dev Set during frontRun(), read during backRun()
    address public frontRunTokenIn;     // token the bot swapped IN during front-run
    uint256 public frontRunAmountIn;    // how much the bot spent
    uint256 public frontRunAmountOut;   // how much the bot received

    constructor(address _pool) {
        pool = SimplePool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();

        // Approve pool to spend both tokens (max approval for simplicity)
        token0.approve(_pool, type(uint256).max);
        token1.approve(_pool, type(uint256).max);
    }

    // =============================================================
    //  TODO 3: Implement frontRun
    // =============================================================
    /// @notice Front-run: swap in the SAME direction as the victim to push the price.
    /// @dev The front-run pushes the price against the victim. Example from lesson:
    ///        - Victim wants to buy ETH with USDC
    ///        - Bot also buys ETH with USDC FIRST → pushes ETH price UP
    ///        - Victim now pays more for their ETH
    ///
    ///      Steps:
    ///        1. Swap tokenIn for the other token on the pool
    ///           (use minAmountOut = 0 — bot controls ordering, no sandwich risk)
    ///        2. Store frontRunTokenIn, frontRunAmountIn, frontRunAmountOut
    ///           for profit tracking in backRun()
    ///
    ///      Hint: The bot doesn't need slippage protection because it controls
    ///      transaction ordering — no one can sandwich the sandwich bot.
    ///
    /// @param tokenIn The token to swap in (same token the victim will use)
    /// @param amountIn How much to front-run with
    function frontRun(address tokenIn, uint256 amountIn) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement backRun
    // =============================================================
    /// @notice Back-run: swap the received tokens back to capture profit.
    /// @dev After the victim's swap pushed the price further in the bot's favor:
    ///        - Bot sells the tokens received in frontRun back to the pool
    ///        - Because the victim's large swap moved the price, bot sells at a
    ///          better price than it bought
    ///
    ///      Numeric example (from lesson):
    ///        Front-run: 10,000 USDC → 4.762 ETH
    ///        (Victim swaps 20,000 USDC → 8.282 ETH — moves price further)
    ///        Back-run:  4.762 ETH → 11,940 USDC
    ///        Profit:    11,940 - 10,000 = 1,940 USDC
    ///
    ///      Steps:
    ///        1. Revert with NoPendingSandwich() if no front-run is pending
    ///           (frontRunAmountIn == 0 means no front-run happened)
    ///        2. Determine the "other" token (what the bot received in frontRun)
    ///        3. Swap ALL of that token back to frontRunTokenIn (minAmountOut = 0)
    ///        4. Calculate profit = backRunOutput - frontRunAmountIn
    ///           (In a real scenario with a victim swap, this is always positive.
    ///            Without a victim, this would underflow — that's fine for this exercise.)
    ///        5. Clear sandwich tracking state (set all to zero/address(0))
    ///
    ///      Hint: If frontRunTokenIn was token0, the bot received token1 in the
    ///      front-run. Now it swaps that token1 back to token0.
    ///
    /// @return profit The amount of profit in the original tokenIn
    function backRun() external returns (uint256 profit) {
        // YOUR CODE HERE
    }
}

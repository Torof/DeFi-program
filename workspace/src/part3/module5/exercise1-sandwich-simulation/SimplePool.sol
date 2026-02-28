// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// EXERCISE 1: Sandwich Simulation — Constant-Product Pool
//
// Build a minimal constant-product AMM and witness sandwich attacks firsthand.
// You'll implement the core swap math with slippage protection, then the test
// suite will show how an attacker exploits transaction ordering to extract
// value — and how tight slippage defeats it.
//
// Concepts exercised:
//   - Constant-product AMM formula (x * y = k)
//   - Price impact on finite-liquidity pools
//   - Slippage protection as a sandwich defense
//   - Adversarial thinking about transaction ordering
//
// Key references:
//   - Module 5 lesson: "Sandwich Attacks: Anatomy & Math"
//   - Part 2 Module 2: AMM fundamentals
//   - Pool math: amountOut = reserveOut * amountIn / (reserveIn + amountIn)
//
// Run: forge test --match-contract SandwichSimTest -vvv
// ============================================================================

error InvalidToken();
error ZeroAmount();
error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);

/// @notice Minimal constant-product pool (x * y = k) for sandwich attack demonstration.
/// @dev Pre-built: constructor, addLiquidity, state. Student implements: getAmountOut, swap.
contract SimplePool {
    // --- State ---
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    // --- Events ---
    event Swap(address indexed sender, address tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /// @notice Add initial liquidity (simplified — no LP tokens).
    /// @dev Pre-built. Transfers tokens from caller and sets reserves.
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        reserve0 += amount0;
        reserve1 += amount1;
    }

    // =============================================================
    //  TODO 1: Implement getAmountOut
    // =============================================================
    /// @notice Calculate swap output using the constant-product formula.
    /// @dev The constant-product invariant: x * y = k
    ///
    ///      After a swap of `amountIn` of tokenIn:
    ///        reserveIn_new  = reserveIn + amountIn
    ///        reserveOut_new = k / reserveIn_new
    ///        amountOut      = reserveOut - reserveOut_new
    ///
    ///      Simplified formula:
    ///        amountOut = reserveOut * amountIn / (reserveIn + amountIn)
    ///
    ///      Numeric example (from lesson):
    ///        Pool: 100 ETH / 200,000 USDC
    ///        User swaps 20,000 USDC → ETH
    ///        amountOut = 100 * 20,000 / (200,000 + 20,000) = 9.091 ETH
    ///
    ///      Steps:
    ///        1. Validate tokenIn is token0 or token1 (revert InvalidToken if not)
    ///        2. Validate amountIn > 0 (revert ZeroAmount if not)
    ///        3. Determine which reserve is "in" and which is "out"
    ///        4. Apply the constant-product formula
    ///
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of input token (18 decimals)
    /// @return amountOut Amount of output token (18 decimals)
    function getAmountOut(address tokenIn, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement swap
    // =============================================================
    /// @notice Execute a swap with slippage protection.
    /// @dev The minAmountOut parameter is the user's defense against sandwiches.
    ///
    ///      From the lesson — slippage as defense:
    ///        User's slippage = 0.5%  →  minOut close to expected  →  sandwich REVERTS
    ///        User's slippage = 10%   →  minOut far from expected  →  sandwich SUCCEEDS
    ///
    ///      Steps:
    ///        1. Calculate output via getAmountOut()
    ///        2. Check amountOut >= minAmountOut (revert InsufficientOutput if not)
    ///        3. Transfer tokenIn from caller to this contract
    ///        4. Transfer tokenOut from this contract to caller
    ///        5. Update reserves (increase reserveIn, decrease reserveOut)
    ///        6. Emit Swap event
    ///
    ///      Hint: Determine which token is "out" the same way you did in
    ///      getAmountOut. Remember to update BOTH reserves.
    ///
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of input token
    /// @param minAmountOut Minimum acceptable output (slippage protection)
    /// @return amountOut Actual output amount
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut)
    {
        // YOUR CODE HERE
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
// EXERCISE: Constant Product AMM
//
// Build a minimal constant-product automated market maker (x · y = k).
// This is the core math behind Uniswap V2 — the most widely forked
// contract in DeFi history.
//
// Concepts exercised:
//   - Constant product invariant (x · y = k)
//   - Geometric mean for initial LP token minting
//   - MINIMUM_LIQUIDITY lock to prevent price manipulation
//   - Proportional LP minting/burning
//   - Fee-inclusive swap math
//   - K invariant enforcement (fees only increase k)
//
// Run: forge test --match-contract ConstantProductPoolTest -vvv
// ============================================================================

// --- Custom Errors ---
error InsufficientLiquidityMinted();
error InsufficientLiquidityBurned();
error InsufficientOutputAmount();
error InsufficientLiquidity();
error InsufficientInputAmount();
error InvalidToken();
error KInvariantViolated();

/// @notice Minimal constant product AMM with 0.3% swap fee.
/// @dev LP tokens are ERC-20 (tradeable, composable with other protocols).
///
/// Key references:
///   - Uniswap V2 Pair: https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol
///   - Uniswap V2 Whitepaper: https://uniswap.org/whitepaper.pdf
///   - Constant product formula: dy = y · dx / (x + dx), with fee applied to dx
contract ConstantProductPool is ERC20 {
    using SafeERC20 for IERC20;

    // --- State ---
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    // --- Constants ---

    /// @dev Permanently locked on first deposit to prevent the pool from
    ///      ever having zero totalSupply. Without this, an attacker can
    ///      manipulate the LP token price to extreme values.
    ///      See: Uniswap V2 whitepaper section 3.4
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    /// @dev 0.3% fee: amountInWithFee = amountIn * 997 / 1000
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    // --- Events ---
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(
        address indexed sender,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(
        address _token0,
        address _token1
    ) ERC20("LP Token", "LP") {
        require(_token0 != _token1, "Identical tokens");
        require(_token0 != address(0) && _token1 != address(0), "Zero address");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    // =============================================================
    //  TODO 1: Implement _update — sync reserves from actual balances
    // =============================================================
    /// @notice Updates reserves to match the pool's actual token balances.
    /// @dev Called at the end of every state-changing function.
    ///      This pattern (reading actual balances rather than tracking
    ///      transfers) is how Uniswap V2 stays in sync even if someone
    ///      sends tokens directly to the pool contract.
    ///
    /// Steps:
    ///   1. Store balance0 and balance1 as reserve0 and reserve1
    ///      (cast to uint112 — safe because reserves can't exceed uint112.max
    ///       in practice, but you can add a check if you want)
    ///   2. Emit Sync(reserve0, reserve1)
    ///
    /// @param balance0 Current token0 balance of this contract
    /// @param balance1 Current token1 balance of this contract
    function _update(uint256 balance0, uint256 balance1) internal {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement addLiquidity
    // =============================================================
    /// @notice Deposits token0 and token1, mints LP tokens in return.
    /// @dev Two cases:
    ///
    ///   FIRST DEPOSIT (totalSupply == 0):
    ///     liquidity = √(amount0 × amount1) - MINIMUM_LIQUIDITY
    ///     The MINIMUM_LIQUIDITY is minted to address(0) and permanently locked.
    ///     This prevents the pool from having zero totalSupply, which would
    ///     enable LP token price manipulation.
    ///     Use: Math.sqrt(amount0 * amount1)
    ///
    ///   SUBSEQUENT DEPOSITS:
    ///     liquidity = min(
    ///       amount0 × totalSupply / reserve0,
    ///       amount1 × totalSupply / reserve1
    ///     )
    ///     Using min() means: if you deposit at the wrong ratio, you get
    ///     fewer LP tokens. The excess is a donation to existing LPs.
    ///
    /// Steps:
    ///   1. Transfer amount0 of token0 and amount1 of token1 from msg.sender
    ///   2. Read actual balances (balance0, balance1)
    ///   3. Compute actual amounts received (balance0 - reserve0, balance1 - reserve1)
    ///   4. Compute liquidity per the formula above
    ///   5. Require liquidity > 0 (revert InsufficientLiquidityMinted)
    ///   6. If first deposit, mint MINIMUM_LIQUIDITY to address(0)
    ///   7. Mint liquidity to msg.sender
    ///   8. Call _update(balance0, balance1)
    ///   9. Emit Mint event
    ///
    /// Hint: Use Math.sqrt from OpenZeppelin for the geometric mean.
    ///       Use Math.min for the subsequent deposit formula.
    ///       ⚠️ For the first deposit, compute the sqrt FIRST, then check
    ///       it's > MINIMUM_LIQUIDITY before subtracting. Otherwise
    ///       sqrt(0) - MINIMUM_LIQUIDITY underflows before your check.
    ///
    /// @param amount0 Desired amount of token0 to deposit
    /// @param amount1 Desired amount of token1 to deposit
    /// @return liquidity Amount of LP tokens minted
    function addLiquidity(uint256 amount0, uint256 amount1) external returns (uint256 liquidity) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement removeLiquidity
    // =============================================================
    /// @notice Burns LP tokens, returns proportional share of both reserves.
    /// @dev Formula:
    ///   amount0 = liquidity × reserve0 / totalSupply
    ///   amount1 = liquidity × reserve1 / totalSupply
    ///
    /// Steps:
    ///   1. Require liquidity > 0 (revert InsufficientLiquidityBurned)
    ///   2. Compute amount0 and amount1 (proportional share)
    ///   3. Require both amounts > 0 (revert InsufficientLiquidity)
    ///   4. Burn LP tokens from msg.sender
    ///   5. Transfer token0 and token1 to msg.sender
    ///   6. Call _update with new balances
    ///   7. Emit Burn event
    ///
    /// Hint: Burn before transfer (Checks-Effects-Interactions pattern).
    ///
    /// @param liquidity Amount of LP tokens to burn
    /// @return amount0 Token0 returned to the user
    /// @return amount1 Token1 returned to the user
    function removeLiquidity(uint256 liquidity) external returns (uint256 amount0, uint256 amount1) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement getAmountOut — the core swap math
    // =============================================================
    /// @notice Computes swap output given input amount and reserves.
    /// @dev This is THE constant product formula with fee:
    ///
    ///   amountInWithFee = amountIn × 997        (0.3% fee deducted)
    ///   numerator       = amountInWithFee × reserveOut
    ///   denominator     = reserveIn × 1000 + amountInWithFee
    ///   amountOut       = numerator / denominator
    ///
    ///   Why this works: After the swap, x_new × y_new >= x_old × y_old
    ///   because the fee keeps some input tokens in the pool.
    ///
    ///   Derivation (without fee): dy = y × dx / (x + dx)
    ///   With fee:                 dy = y × (dx × 0.997) / (x + dx × 0.997)
    ///   Multiply by 1000/1000:    dy = y × (dx × 997) / (x × 1000 + dx × 997)
    ///
    /// Used by: Uniswap V2 Router's getAmountOut()
    ///   https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L43
    ///
    /// @param amountIn Amount of input token
    /// @param reserveIn Current reserve of input token
    /// @param reserveOut Current reserve of output token
    /// @return amountOut Amount of output token
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5 & 6: Implement swap with k invariant check
    // =============================================================
    /// @notice Swaps one token for the other using the constant product formula.
    /// @dev Steps:
    ///   1. Validate tokenIn is token0 or token1 (revert InvalidToken)
    ///   2. Require amountIn > 0 (revert InsufficientInputAmount)
    ///   3. Determine which direction: is tokenIn == token0?
    ///   4. Load the correct reserveIn / reserveOut
    ///   5. Require reserveOut > 0 (revert InsufficientLiquidity)
    ///   6. Compute amountOut = getAmountOut(amountIn, reserveIn, reserveOut)
    ///   7. Require amountOut > 0 (revert InsufficientOutputAmount)
    ///   8. --- K INVARIANT (TODO 6) ---
    ///      Store k_before = uint256(reserve0) * uint256(reserve1)
    ///   9. Transfer tokenIn from msg.sender to this contract
    ///  10. Transfer tokenOut from this contract to msg.sender
    ///  11. Call _update with new balances
    ///  12. --- K INVARIANT CHECK (TODO 6) ---
    ///      Verify: uint256(reserve0) * uint256(reserve1) >= k_before
    ///      If not, revert KInvariantViolated()
    ///      (Fees should only INCREASE k — if k decreased, something is wrong)
    ///  13. Emit Swap event
    ///
    /// @param tokenIn Address of the token being sold
    /// @param amountIn Amount of tokenIn to swap
    /// @return amountOut Amount of the other token received
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        revert("Not implemented");
    }

    // --- View helpers (provided) ---

    /// @notice Returns the current spot price of token0 in terms of token1.
    /// @dev price = reserve1 / reserve0 (scaled by 1e18 for precision)
    function getSpotPrice() external view returns (uint256) {
        if (reserve0 == 0) return 0;
        return uint256(reserve1) * 1e18 / uint256(reserve0);
    }

    /// @notice Returns the current k value (reserve0 × reserve1).
    function getK() external view returns (uint256) {
        return uint256(reserve0) * uint256(reserve1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal constant-product pool for the SplitRouter exercise.
/// @dev Supports swap() and reserve queries. No fees for simplicity.
contract MockPool {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    constructor(address token0_, address token1_, uint256 reserve0_, uint256 reserve1_) {
        token0 = IERC20(token0_);
        token1 = IERC20(token1_);
        reserve0 = reserve0_;
        reserve1 = reserve1_;
    }

    /// @notice Swap tokenIn for tokenOut using constant-product formula.
    /// @dev Caller must have transferred `amountIn` of `tokenIn` to this contract first.
    function swap(address tokenIn, uint256 amountIn, address to) external returns (uint256 amountOut) {
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");

        (uint256 reserveIn, uint256 reserveOut, IERC20 tokenOut_) = tokenIn == address(token0)
            ? (reserve0, reserve1, token1)
            : (reserve1, reserve0, token0);

        // Constant-product: amountOut = reserveOut * amountIn / (reserveIn + amountIn)
        amountOut = reserveOut * amountIn / (reserveIn + amountIn);

        // Update reserves
        if (tokenIn == address(token0)) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        // Transfer output
        tokenOut_.transfer(to, amountOut);
    }

    /// @notice Get reserves for a given input token direction.
    function getReserves(address tokenIn)
        external
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        if (tokenIn == address(token0)) {
            return (reserve0, reserve1);
        } else {
            return (reserve1, reserve0);
        }
    }
}

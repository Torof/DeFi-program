// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal AMM pool mock for testing assembly external calls.
/// @dev Used by Exercise 3 (AssemblyRouter). Has a simple swap function that
///      applies a fixed 0.3% fee and returns the output amount.
contract MockPool {
    mapping(address => uint256) public reserves;

    error InsufficientLiquidity(uint256 requested, uint256 available);

    constructor(address tokenA, address tokenB, uint256 reserveA, uint256 reserveB) {
        reserves[tokenA] = reserveA;
        reserves[tokenB] = reserveB;
    }

    /// @notice Swap tokenIn for tokenOut using the constant product formula.
    /// @param tokenIn The token being sold.
    /// @param tokenOut The token being bought.
    /// @param amountIn The amount of tokenIn being sold.
    /// @return amountOut The amount of tokenOut received.
    function swap(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        uint256 reserveIn = reserves[tokenIn];
        uint256 reserveOut = reserves[tokenOut];

        // x * y = k with 0.3% fee
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        if (amountOut > reserveOut) {
            revert InsufficientLiquidity(amountOut, reserveOut);
        }

        reserves[tokenIn] = reserveIn + amountIn;
        reserves[tokenOut] = reserveOut - amountOut;
    }
}

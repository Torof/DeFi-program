// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal constant-product pool for the oracle attack lab.
/// @dev This is NOT a full AMM — no LP tokens, no MINIMUM_LIQUIDITY, no events.
///      It exists solely to provide a manipulable spot price source for Exercise 3.
///      The attack lab demonstrates why reading price from getReserves() is dangerous.
contract SimplePool {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    error InsufficientAmount();
    error InvalidToken();
    error InsufficientLiquidity();

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /// @notice Seed the pool with initial liquidity. No LP tokens minted.
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        reserve0 = uint112(token0.balanceOf(address(this)));
        reserve1 = uint112(token1.balanceOf(address(this)));
    }

    /// @notice Swap tokenIn for the other token using constant product with 0.3% fee.
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientAmount();

        bool zeroForOne = (tokenIn == address(token0));
        if (!zeroForOne && tokenIn != address(token1)) revert InvalidToken();

        (uint256 reserveIn, uint256 reserveOut) = zeroForOne
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        if (amountOut == 0) revert InsufficientLiquidity();

        // Transfer in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer out
        IERC20 tokenOut = zeroForOne ? token1 : token0;
        tokenOut.safeTransfer(msg.sender, amountOut);

        // Sync reserves
        reserve0 = uint112(token0.balanceOf(address(this)));
        reserve1 = uint112(token1.balanceOf(address(this)));
    }

    /// @notice Returns current reserves.
    function getReserves() external view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    /// @notice Returns the spot price of token0 in terms of token1 (18 decimals).
    /// @dev This is the price that flash loan attacks manipulate.
    function getSpotPrice() external view returns (uint256) {
        if (reserve0 == 0) return 0;
        return uint256(reserve1) * 1e18 / uint256(reserve0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built Uniswap V2-style AMM pair (constant product,
//  no fee). Used as infrastructure for the OracleManipulation exercise.
//
//  Key behavior: swap() changes reserves, which changes getSpotPrice().
//  This is the vulnerability — spot price = reserve ratio, trivially
//  manipulable with enough capital.
// ============================================================================

/// @notice Minimal constant-product AMM pair (no fees, no LP tokens).
/// @dev For exercise purposes only. Demonstrates how spot price is just
///      the ratio of reserves and can be manipulated by swapping.
contract MockPair {
    using SafeERC20 for IERC20;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    constructor(IERC20 tokenA_, IERC20 tokenB_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    /// @notice Add initial liquidity (no LP tokens — just fund the pair).
    function initialize(uint256 amountA, uint256 amountB) external {
        require(reserveA == 0 && reserveB == 0, "MockPair: already initialized");
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        reserveA = amountA;
        reserveB = amountB;
    }

    /// @notice Spot price of tokenA denominated in tokenB (18-decimal scaled).
    /// @dev spotPrice = reserveB / reserveA. This is what SpotPriceLending reads.
    function getSpotPrice() external view returns (uint256) {
        require(reserveA > 0, "MockPair: not initialized");
        return reserveB * 1e18 / reserveA;
    }

    /// @notice Get current reserves.
    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    /// @notice Swap tokenIn for the other token using constant product (x * y = k).
    /// @dev Caller must approve this contract for amountIn of tokenIn.
    ///      No fees — output is purely determined by the constant product formula.
    /// @param tokenIn Address of the input token (must be tokenA or tokenB).
    /// @param amountIn Amount of input token to swap.
    /// @return amountOut Amount of output token received.
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "MockPair: zero input");

        uint256 k = reserveA * reserveB;

        if (tokenIn == address(tokenA)) {
            tokenA.safeTransferFrom(msg.sender, address(this), amountIn);
            reserveA += amountIn;
            uint256 newReserveB = k / reserveA;
            amountOut = reserveB - newReserveB;
            reserveB = newReserveB;
            tokenB.safeTransfer(msg.sender, amountOut);
        } else {
            require(tokenIn == address(tokenB), "MockPair: invalid token");
            tokenB.safeTransferFrom(msg.sender, address(this), amountIn);
            reserveB += amountIn;
            uint256 newReserveA = k / reserveB;
            amountOut = reserveA - newReserveA;
            reserveA = newReserveA;
            tokenA.safeTransfer(msg.sender, amountOut);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Constant-price DEX mock with configurable swap fee.
/// @dev Pre-built — students do NOT modify this.
///
///      Based on Module 4's MockDEX with an added swap fee.
///      Behavior:
///        - Admin sets prices via setPrice(tokenA, tokenB, priceE18)
///        - swap() uses the constant price, applies feeBps, no AMM curve
///        - Mints output tokens (infinite liquidity)
///        - Burns input tokens (accepts any amount)
///
///      This lets the FlashLoanArbitrage exercise focus on the flash loan
///      composition and profitability math, not AMM mechanics.
contract MockDEX {
    using SafeERC20 for IERC20;

    // price[tokenA][tokenB] = how many tokenB per tokenA (18 decimals)
    mapping(address => mapping(address => uint256)) public prices;

    /// @notice Swap fee in basis points (e.g., 30 = 0.3%).
    uint256 public feeBps;

    error PriceNotSet();
    error ZeroAmount();

    constructor(uint256 feeBps_) {
        feeBps = feeBps_;
    }

    /// @notice Admin: set the exchange rate between two tokens.
    /// @param tokenA The input token
    /// @param tokenB The output token
    /// @param priceE18 How many tokenB per tokenA (18 decimals)
    ///        Example: 1 WETH = 2000 USDC → setPrice(weth, usdc, 2000e18)
    function setPrice(address tokenA, address tokenB, uint256 priceE18) external {
        prices[tokenA][tokenB] = priceE18;
    }

    /// @notice Swap tokenIn for tokenOut at the configured constant price, minus fee.
    /// @dev Burns input (transfers to this contract), mints output.
    ///      Price accounts for decimal differences via token decimals.
    /// @return amountOut The amount of tokenOut received (after fee).
    function swap(address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        uint256 price = prices[tokenIn][tokenOut];
        if (price == 0) revert PriceNotSet();

        // Get decimals for proper conversion
        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();

        // amountOut = amountIn * price / 1e18, adjusted for decimal differences
        amountOut = amountIn * price / 1e18;
        if (decimalsOut > decimalsIn) {
            amountOut = amountOut * (10 ** (decimalsOut - decimalsIn));
        } else if (decimalsIn > decimalsOut) {
            amountOut = amountOut / (10 ** (decimalsIn - decimalsOut));
        }

        // Apply swap fee
        amountOut = amountOut * (10_000 - feeBps) / 10_000;

        // Transfer in, mint out
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IMintable(tokenOut).mint(msg.sender, amountOut);
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

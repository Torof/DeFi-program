// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Constant-price DEX mock for the FlashLiquidator exercise.
/// @dev Pre-built — students do NOT modify this.
///
///      Behavior:
///        - Admin sets prices via setPrice(tokenA, tokenB, priceE18)
///        - swap() uses the constant price — no slippage, no AMM curve
///        - Mints output tokens (infinite liquidity)
///        - Burns input tokens (accepts any amount)
///
///      This simplification lets the FlashLiquidator exercise focus on
///      the flash loan + liquidation flow without AMM math.
contract MockDEX {
    using SafeERC20 for IERC20;

    // price[tokenA][tokenB] = how many tokenB per tokenA (18 decimals)
    mapping(address => mapping(address => uint256)) public prices;

    error PriceNotSet();
    error ZeroAmount();

    /// @notice Admin: set the exchange rate between two tokens.
    /// @param tokenA The input token
    /// @param tokenB The output token
    /// @param priceE18 How many tokenB per tokenA (18 decimals)
    ///        Example: 1 WETH = 2000 USDC → setPrice(weth, usdc, 2000e18)
    function setPrice(address tokenA, address tokenB, uint256 priceE18) external {
        prices[tokenA][tokenB] = priceE18;
    }

    /// @notice Swap tokenIn for tokenOut at the configured constant price.
    /// @dev Burns input (transfers to this contract), mints output.
    ///      Price accounts for decimal differences via token decimals.
    /// @return amountOut The amount of tokenOut received.
    function swap(address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        uint256 price = prices[tokenIn][tokenOut];
        if (price == 0) revert PriceNotSet();

        // Get decimals for proper conversion
        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();

        // amountOut = amountIn × price / 1e18, adjusted for decimal differences
        amountOut = amountIn * price / 1e18;
        // Adjust for decimal differences: multiply by 10^decimalsOut / 10^decimalsIn
        if (decimalsOut > decimalsIn) {
            amountOut = amountOut * (10 ** (decimalsOut - decimalsIn));
        } else if (decimalsIn > decimalsOut) {
            amountOut = amountOut / (10 ** (decimalsIn - decimalsOut));
        }

        // Transfer in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Mint out (infinite liquidity)
        IMintable(tokenOut).mint(msg.sender, amountOut);
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Uniswap V2 Fork Testing
//
// Learn to interact with real deployed DeFi protocols using fork tests.
// This exercise demonstrates reading pair reserves and verifying swap math
// against Uniswap V2 on mainnet.
//
// Day 11: Master fork testing with real protocols.
//
// Run: forge test --match-contract UniswapV2ForkTest --fork-url $MAINNET_RPC_URL -vvv
// ============================================================================

import "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// =============================================================
//  Uniswap V2 Interfaces
// =============================================================
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

// =============================================================
//  TODO 1: Implement UniswapV2ForkTest
// =============================================================
/// @notice Fork tests for Uniswap V2 protocol interaction.
/// @dev Tests reading reserves and verifying swap calculations.
contract UniswapV2ForkTest is BaseTest {
    IUniswapV2Factory constant FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    IUniswapV2Pair wethUsdcPair;

    function setUp() public override {
        super.setUp();

        // TODO: Get the WETH/USDC pair from factory
        // wethUsdcPair = IUniswapV2Pair(FACTORY.getPair(WETH, USDC));
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Test Getting Pair Reserves
    // =============================================================
    /// @notice Verifies that we can read pair reserves from Uniswap V2.
    function test_GetPairReserves() public view {
        // TODO: Implement
        // 1. Get reserves from the pair: (uint112 reserve0, uint112 reserve1,) = wethUsdcPair.getReserves()
        // 2. Assert that reserves are non-zero
        // 3. Log the reserves for visibility:
        //    console.log("Reserve0:", reserve0);
        //    console.log("Reserve1:", reserve1);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Test Identifying Token Order
    // =============================================================
    /// @notice Verifies correct identification of token0 and token1.
    function test_IdentifyTokenOrder() public view {
        // TODO: Implement
        // 1. Get token0 and token1 from the pair
        // 2. Determine which is WETH and which is USDC
        //    (token0 is the one with the lower address)
        // 3. Assert that both tokens are accounted for:
        //    assertTrue(token0 == WETH || token0 == USDC)
        //    assertTrue(token1 == WETH || token1 == USDC)
        //    assertTrue(token0 != token1)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Test Swap Amount Out Calculation
    // =============================================================
    /// @notice Calculates expected output for a swap and verifies the math.
    /// @dev Uses the constant product formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    function test_CalculateAmountOut() public view {
        // TODO: Implement
        // 1. Get reserves
        // 2. Choose an input amount (e.g., 1 WETH)
        // 3. Calculate expected output using the formula:
        //    amountInWithFee = amountIn * 997
        //    numerator = amountInWithFee * reserveOut
        //    denominator = reserveIn * 1000 + amountInWithFee
        //    amountOut = numerator / denominator
        // 4. Assert amountOut > 0
        // 5. Log the result:
        //    console.log("Swapping 1 WETH for USDC");
        //    console.log("Expected USDC out:", amountOut);
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Test Multiple Swap Calculations
    // =============================================================
    /// @notice Tests swap calculations for various input amounts.
    function test_MultipleSwapAmounts() public view {
        // TODO: Implement
        // 1. Get reserves and identify which is WETH, which is USDC
        // 2. Test calculations for multiple amounts:
        //    - 0.1 WETH
        //    - 1 WETH
        //    - 10 WETH
        // 3. For each amount, calculate expected USDC output
        // 4. Verify that output increases with input (but not proportionally due to price impact)
        // 5. Verify that larger swaps have worse rates (price impact)
        //    Hint: Compare (amountOut / amountIn) ratios
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Test Price Impact
    // =============================================================
    /// @notice Demonstrates price impact on large swaps.
    function test_PriceImpact() public view {
        // TODO: Implement
        // 1. Calculate spot price from reserves: price = reserveOut / reserveIn
        // 2. Calculate effective price for a 1 WETH swap: effectivePrice = amountOut / amountIn
        // 3. Calculate effective price for a 100 WETH swap
        // 4. Assert that larger swap has worse effective price
        // 5. Calculate price impact percentage:
        //    impact = ((spotPrice - effectivePrice) / spotPrice) * 100
        // 6. Log the price impact
        revert("Not implemented");
    }

    // =============================================================
    //  Helper Functions
    // =============================================================

    /// @notice Calculates amount out for a Uniswap V2 swap.
    /// @param amountIn Input amount
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @return amountOut Expected output amount
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        // TODO: Implement the Uniswap V2 formula
        // amountInWithFee = amountIn * 997
        // numerator = amountInWithFee * reserveOut
        // denominator = reserveIn * 1000 + amountInWithFee
        // amountOut = numerator / denominator
        revert("Not implemented");
    }
}

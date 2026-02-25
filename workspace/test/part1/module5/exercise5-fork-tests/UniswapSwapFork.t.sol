// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Full Uniswap V2 Swap Fork Test
//
// Perform a complete end-to-end swap on Uniswap V2 using mainnet fork.
// This demonstrates the full workflow: deal tokens, approve router, execute
// swap, and verify output matches expected amount.
//
// Day 13: Master real-world fork testing.
//
// Run: forge test --match-contract UniswapSwapForkTest --fork-url $MAINNET_RPC_URL -vvv
// ============================================================================

import "forge-std/Test.sol";
import {BaseTest} from "../exercise4-base-test/BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// =============================================================
//  Uniswap V2 Router Interface
// =============================================================
interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

// =============================================================
//  TODO 1: Implement UniswapSwapForkTest
// =============================================================
/// @notice Fork tests for performing actual swaps on Uniswap V2.
/// @dev Tests the complete swap workflow on mainnet fork.
contract UniswapSwapForkTest is BaseTest {
    IUniswapV2Router02 constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public override {
        super.setUp();
    }

    // =============================================================
    //  TODO 2: Test Swap Exact Tokens for Tokens
    // =============================================================
    /// @notice Performs a WETH → USDC swap using swapExactTokensForTokens.
    function test_SwapExactWETHForUSDC() public {
        // TODO: Implement
        // 1. Define swap amount (e.g., 1 WETH)
        // 2. Deal WETH to alice:
        //    dealToken(WETH, alice, swapAmount);
        // 3. Get expected USDC output using router.getAmountsOut:
        //    address[] memory path = new address[](2);
        //    path[0] = WETH;
        //    path[1] = USDC;
        //    uint256[] memory amountsOut = ROUTER.getAmountsOut(swapAmount, path);
        //    uint256 expectedUSDC = amountsOut[1];
        // 4. Execute swap as alice:
        //    vm.startPrank(alice);
        //    IERC20(WETH).approve(address(ROUTER), swapAmount);
        //    uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
        //        swapAmount,
        //        expectedUSDC * 99 / 100, // 1% slippage tolerance
        //        path,
        //        alice,
        //        block.timestamp + 1 hours
        //    );
        //    vm.stopPrank();
        // 5. Verify results:
        //    assertEq(amounts[0], swapAmount, "Input amount should match");
        //    assertEq(amounts[1], expectedUSDC, "Output should match expected");
        //    assertEq(IERC20(USDC).balanceOf(alice), expectedUSDC, "Alice should receive USDC");
        // 6. Log the results
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Test Swap Tokens for Exact Tokens
    // =============================================================
    /// @notice Performs a WETH → USDC swap using swapTokensForExactTokens.
    function test_SwapWETHForExactUSDC() public {
        // TODO: Implement
        // 1. Define desired USDC output (e.g., 1000 USDC = 1000e6)
        // 2. Get required WETH input using router.getAmountsIn
        // 3. Deal slightly more WETH to alice to account for slippage
        // 4. Execute swap with amountInMax
        // 5. Verify alice received exact USDC amount
        // 6. Verify alice has remaining WETH (if any)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Test Multi-Hop Swap
    // =============================================================
    /// @notice Performs a multi-hop swap: USDC → WETH → DAI.
    function test_MultiHopSwap() public {
        // TODO: Implement
        // 1. Define swap amount (e.g., 1000 USDC)
        // 2. Deal USDC to alice
        // 3. Create path: [USDC, WETH, DAI]
        // 4. Get expected output
        // 5. Execute swap
        // 6. Verify alice received DAI
        // 7. Compare gas cost to direct USDC → DAI swap (if pair exists)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Test Slippage Protection
    // =============================================================
    /// @notice Tests that swap reverts when slippage exceeds tolerance.
    function test_SwapRevertsOnExcessiveSlippage() public {
        // TODO: Implement
        // 1. Get expected output for 1 WETH → USDC
        // 2. Set amountOutMin to unreasonably high value (e.g., expectedUSDC * 2)
        // 3. Attempt swap
        // 4. Expect revert (Uniswap will revert with "INSUFFICIENT_OUTPUT_AMOUNT")
        //    vm.expectRevert();
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Test Swap and Verify Price Impact
    // =============================================================
    /// @notice Executes a swap and calculates the actual price impact.
    function test_SwapPriceImpact() public {
        // TODO: Implement
        // 1. Get pair reserves before swap
        // 2. Calculate spot price from reserves
        // 3. Execute a large swap (e.g., 100 WETH → USDC)
        // 4. Calculate effective price from amounts
        // 5. Calculate price impact: ((spotPrice - effectivePrice) / spotPrice) * 100
        // 6. Assert price impact > 0 (large swap should have impact)
        // 7. Get reserves after swap and verify they changed correctly
        // 8. Log price impact
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 7: Test Swap with Deadline
    // =============================================================
    /// @notice Tests that swap reverts when deadline is passed.
    function test_SwapRevertsAfterDeadline() public {
        // TODO: Implement
        // 1. Deal WETH to alice
        // 2. Set deadline to current timestamp (already passed)
        // 3. Attempt swap
        // 4. Expect revert with "EXPIRED" or similar
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 8: Integration Test - Full Workflow
    // =============================================================
    /// @notice Tests complete workflow: buy and sell back.
    function test_BuyAndSellBack() public {
        // TODO: Implement
        // 1. Start with 1 WETH
        // 2. Swap WETH → USDC
        // 3. Immediately swap USDC → WETH
        // 4. Calculate total WETH after round trip
        // 5. Assert final WETH < initial WETH (lost to fees ~0.6%)
        // 6. Calculate total fee paid: initialWETH - finalWETH
        // 7. Verify fee is approximately 0.6% (two 0.3% swaps)
        // 8. Log the results
        revert("Not implemented");
    }

    // =============================================================
    //  Helper Functions
    // =============================================================

    /// @notice Gets reserves for a pair and identifies token order.
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @return reserveA Reserve of tokenA
    /// @return reserveB Reserve of tokenB
    function getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        // TODO: Implement
        // 1. Get pair from factory
        // 2. Get reserves
        // 3. Get token0
        // 4. If tokenA == token0: return (reserve0, reserve1)
        //    Else: return (reserve1, reserve0)
        revert("Not implemented");
    }

    /// @notice Calculates spot price from reserves.
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @return price Spot price (scaled by 1e18)
    function getSpotPrice(uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 price) {
        // TODO: Implement
        // price = (reserveOut * 1e18) / reserveIn
        revert("Not implemented");
    }
}

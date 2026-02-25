// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the ConstantProductPool
//  exercise. Implement ConstantProductPool.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    ConstantProductPool,
    InsufficientLiquidityMinted,
    InsufficientLiquidityBurned,
    InsufficientOutputAmount,
    InsufficientLiquidity,
    InsufficientInputAmount,
    InvalidToken,
    KInvariantViolated
} from "../../../../src/part2/module2/exercise1-constant-product/ConstantProductPool.sol";
import {MockERC20} from "../../../../src/part2/module2/mocks/MockERC20.sol";

contract ConstantProductPoolTest is Test {
    ConstantProductPool pool;
    MockERC20 tokenA;
    MockERC20 tokenB;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        pool = new ConstantProductPool(address(tokenA), address(tokenB));

        // Fund users
        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 1_000_000e18);
        tokenA.mint(bob, 1_000_000e18);
        tokenB.mint(bob, 1_000_000e18);

        // Approve pool
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // =========================================================
    //  Initial Liquidity
    // =========================================================

    function test_InitialLiquidity_GeometricMean() public {
        // Deposit 100 tokenA + 400 tokenB
        // Expected: sqrt(100 * 400) - MINIMUM_LIQUIDITY = 200e18 - 1000
        vm.prank(alice);
        uint256 lp = pool.addLiquidity(100e18, 400e18);

        uint256 expected = Math.sqrt(100e18 * 400e18) - MINIMUM_LIQUIDITY;
        assertEq(lp, expected, "First deposit LP = sqrt(a0 * a1) - MINIMUM_LIQUIDITY");
    }

    function test_InitialLiquidity_MinLiquidityBurned() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        assertEq(
            pool.balanceOf(address(0)),
            MINIMUM_LIQUIDITY,
            "MINIMUM_LIQUIDITY must be permanently locked at address(0)"
        );
    }

    function test_InitialLiquidity_ReservesUpdated() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        assertEq(pool.reserve0(), 100e18, "reserve0 should match deposited amount");
        assertEq(pool.reserve1(), 400e18, "reserve1 should match deposited amount");
    }

    // =========================================================
    //  Subsequent Liquidity
    // =========================================================

    function test_AddLiquidity_ProportionalMint() public {
        // First deposit: 100 + 400 (ratio 1:4)
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);
        uint256 totalBefore = pool.totalSupply();

        // Second deposit at same ratio: 50 + 200
        vm.prank(bob);
        uint256 lp = pool.addLiquidity(50e18, 200e18);

        // Expected: min(50 * total / 100, 200 * total / 400) = 50% of totalBefore
        uint256 expected = Math.min(
            50e18 * totalBefore / 100e18,
            200e18 * totalBefore / 400e18
        );
        assertEq(lp, expected, "Proportional deposit should mint proportional LP tokens");
    }

    function test_AddLiquidity_ImbalancedPenalty() public {
        // First deposit: 100 + 100 (ratio 1:1)
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);
        uint256 totalBefore = pool.totalSupply();

        // Imbalanced deposit: 100 + 50 (too little token1)
        vm.prank(bob);
        uint256 lp = pool.addLiquidity(100e18, 50e18);

        // min() picks the LOWER ratio → uses token1's ratio (50/100 = 50%)
        // Bob gets LP based on 50% of pool, even though he deposited 100% more tokenA
        uint256 expected = Math.min(
            100e18 * totalBefore / 100e18,
            50e18 * totalBefore / 100e18
        );
        assertEq(lp, expected, "Imbalanced deposit should be penalized via min()");

        // The excess tokenA (50e18 worth) is effectively donated to existing LPs
        uint256 lpIfBalanced = 100e18 * totalBefore / 100e18;
        assertLt(lp, lpIfBalanced, "Imbalanced deposit gets fewer LP tokens than balanced");
    }

    function test_AddLiquidity_MultipleProviders() public {
        // Alice adds initial liquidity
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);

        // Bob adds equal amount
        vm.prank(bob);
        pool.addLiquidity(100e18, 100e18);

        // Both should have proportional LP tokens
        // Alice has slightly more due to MINIMUM_LIQUIDITY being burned
        // But relative to each other, their shares reflect deposits
        uint256 aliceLP = pool.balanceOf(alice);
        uint256 bobLP = pool.balanceOf(bob);

        // Bob's LP should equal Alice's LP minus the MINIMUM_LIQUIDITY penalty
        // (Alice paid the min liquidity cost, Bob didn't)
        assertEq(
            bobLP,
            aliceLP + MINIMUM_LIQUIDITY,
            "Second depositor gets slightly more LP (no MINIMUM_LIQUIDITY cost)"
        );
    }

    // =========================================================
    //  Remove Liquidity
    // =========================================================

    function test_RemoveLiquidity_ProportionalShare() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        uint256 aliceLP = pool.balanceOf(alice);
        uint256 halfLP = aliceLP / 2;

        uint256 aliceA_before = tokenA.balanceOf(alice);
        uint256 aliceB_before = tokenB.balanceOf(alice);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(halfLP);

        // Should get roughly half the reserves (minus rounding)
        uint256 aliceA_after = tokenA.balanceOf(alice);
        uint256 aliceB_after = tokenB.balanceOf(alice);

        assertEq(aliceA_after - aliceA_before, amount0, "Token A received matches returned amount0");
        assertEq(aliceB_after - aliceB_before, amount1, "Token B received matches returned amount1");

        // Proportional: halfLP / totalSupply * reserve
        assertApproxEqAbs(amount0, 50e18, 1e15, "Should receive ~50% of tokenA reserve");
        assertApproxEqAbs(amount1, 200e18, 1e15, "Should receive ~50% of tokenB reserve");
    }

    function test_RemoveLiquidity_FullWithdraw() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        uint256 aliceLP = pool.balanceOf(alice);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(aliceLP);

        // Can't get everything back — MINIMUM_LIQUIDITY is locked
        assertLt(amount0, 100e18, "Can't withdraw full deposit (MINIMUM_LIQUIDITY locked)");
        assertLt(amount1, 400e18, "Can't withdraw full deposit (MINIMUM_LIQUIDITY locked)");

        // But should get almost everything
        assertGt(amount0, 99e18, "Should get most of tokenA back");
        assertGt(amount1, 399e18, "Should get most of tokenB back");
    }

    function test_RemoveLiquidity_ReservesDecrease() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        uint256 r0_before = pool.reserve0();
        uint256 r1_before = pool.reserve1();
        uint256 aliceLP = pool.balanceOf(alice);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(aliceLP / 4);

        assertEq(
            uint256(pool.reserve0()),
            r0_before - amount0,
            "reserve0 should decrease by withdrawn amount"
        );
        assertEq(
            uint256(pool.reserve1()),
            r1_before - amount1,
            "reserve1 should decrease by withdrawn amount"
        );
    }

    // =========================================================
    //  getAmountOut
    // =========================================================

    function test_GetAmountOut_MatchesFormula() public {
        // Pool: 100 tokenA, 400 tokenB
        // Swap 10 tokenA in
        // amountInWithFee = 10e18 * 997 = 9970e18
        // numerator = 9970e18 * 400e18
        // denominator = 100e18 * 1000 + 9970e18
        // amountOut = (9970e18 * 400e18) / (100000e18 + 9970e18)
        //           = 3988000e36 / 109970e18
        //           ≈ 36.264e18

        uint256 amountIn = 10e18;
        uint256 reserveIn = 100e18;
        uint256 reserveOut = 400e18;

        // Hand-compute the expected output from the formula
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        uint256 expected = numerator / denominator;

        uint256 result = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        assertEq(result, expected, "getAmountOut must match the constant product formula");
    }

    function test_GetAmountOut_ZeroInput_Reverts() public {
        vm.expectRevert(InsufficientInputAmount.selector);
        pool.getAmountOut(0, 100e18, 400e18);
    }

    // =========================================================
    //  Swap
    // =========================================================

    function test_Swap_CorrectOutput() public {
        // Setup: 100:400 pool
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        // Bob swaps 10 tokenA → tokenB
        uint256 expectedOut = pool.getAmountOut(10e18, 100e18, 400e18);

        uint256 bobB_before = tokenB.balanceOf(bob);
        vm.prank(bob);
        uint256 amountOut = pool.swap(address(tokenA), 10e18);
        uint256 bobB_after = tokenB.balanceOf(bob);

        assertEq(amountOut, expectedOut, "Swap output should match getAmountOut");
        assertEq(
            bobB_after - bobB_before,
            amountOut,
            "Bob should receive exactly amountOut tokens"
        );
    }

    function test_Swap_FeeStaysInPool() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        uint256 k_before = pool.getK();

        vm.prank(bob);
        pool.swap(address(tokenA), 10e18);

        uint256 k_after = pool.getK();

        assertGt(
            k_after,
            k_before,
            "k must INCREASE after swap (fee stays in pool)"
        );
    }

    function test_Swap_PriceImpact() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        // Small swap: 1 tokenA
        uint256 smallOut = pool.getAmountOut(1e18, 100e18, 400e18);
        uint256 smallRate = smallOut; // output per 1e18 input

        // Large swap: 50 tokenA (half the reserve)
        uint256 largeOut = pool.getAmountOut(50e18, 100e18, 400e18);
        uint256 largeRate = largeOut * 1e18 / 50e18; // output per input

        assertGt(
            smallRate,
            largeRate,
            "Large swaps should get a worse rate (price impact)"
        );
    }

    function test_Swap_BothDirections() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        // Swap tokenA → tokenB
        vm.prank(bob);
        uint256 outB = pool.swap(address(tokenA), 10e18);
        assertGt(outB, 0, "Should receive tokenB");

        // Swap tokenB → tokenA
        vm.prank(bob);
        uint256 outA = pool.swap(address(tokenB), 10e18);
        assertGt(outA, 0, "Should receive tokenA");
    }

    function test_Swap_SequentialSwaps_PriceMoves() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);

        uint256 priceBefore = pool.getSpotPrice();

        // Buy tokenB (swap tokenA → tokenB) three times
        vm.startPrank(bob);
        pool.swap(address(tokenA), 5e18);
        pool.swap(address(tokenA), 5e18);
        pool.swap(address(tokenA), 5e18);
        vm.stopPrank();

        uint256 priceAfter = pool.getSpotPrice();

        // tokenB became scarcer → price (reserve1/reserve0) should DECREASE
        // because we added tokenA (reserve0 up) and removed tokenB (reserve1 down)
        assertLt(
            priceAfter,
            priceBefore,
            "Sequential buys of tokenB should decrease tokenB/tokenA spot price"
        );
    }

    // =========================================================
    //  Edge Cases & Reverts
    // =========================================================

    function test_Revert_SwapInvalidToken() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);

        address fakeToken = makeAddr("fakeToken");
        vm.prank(bob);
        vm.expectRevert(InvalidToken.selector);
        pool.swap(fakeToken, 10e18);
    }

    function test_Revert_AddLiquidityZero() public {
        // Trying to add zero should fail (no liquidity minted)
        vm.prank(alice);
        vm.expectRevert(InsufficientLiquidityMinted.selector);
        pool.addLiquidity(0, 0);
    }

    function test_Revert_RemoveLiquidityZero() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);

        vm.prank(alice);
        vm.expectRevert(InsufficientLiquidityBurned.selector);
        pool.removeLiquidity(0);
    }

    function test_Revert_SwapZeroInput() public {
        vm.prank(alice);
        pool.addLiquidity(100e18, 100e18);

        vm.prank(bob);
        vm.expectRevert(InsufficientInputAmount.selector);
        pool.swap(address(tokenA), 0);
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_KInvariant(uint256 amountIn) public {
        // Setup pool
        vm.prank(alice);
        pool.addLiquidity(100e18, 400e18);

        // Bound to reasonable swap amounts (not more than reserve)
        amountIn = bound(amountIn, 1e15, 50e18);

        uint256 k_before = pool.getK();

        vm.prank(bob);
        pool.swap(address(tokenA), amountIn);

        uint256 k_after = pool.getK();
        assertGe(k_after, k_before, "INVARIANT: k must never decrease after a swap");
    }

    function testFuzz_AddRemoveRoundtrip(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e18, 100_000e18);
        amount1 = bound(amount1, 1e18, 100_000e18);

        // Alice provides initial liquidity
        vm.prank(alice);
        pool.addLiquidity(amount0, amount1);

        // Bob adds and immediately removes
        uint256 deposit0 = bound(amount0, 1e18, 50_000e18);
        uint256 deposit1 = deposit0 * amount1 / amount0; // match ratio
        if (deposit1 == 0) deposit1 = 1e18;

        vm.prank(bob);
        uint256 lp = pool.addLiquidity(deposit0, deposit1);

        vm.prank(bob);
        (uint256 out0, uint256 out1) = pool.removeLiquidity(lp);

        // Should never get MORE than deposited (no free tokens)
        assertLe(
            out0,
            deposit0 + 1, // +1 for rounding
            "INVARIANT: cannot withdraw more token0 than deposited"
        );
        assertLe(
            out1,
            deposit1 + 1,
            "INVARIANT: cannot withdraw more token1 than deposited"
        );
    }

    function testFuzz_SwapOutputSublinear(uint256 amountIn) public {
        vm.prank(alice);
        pool.addLiquidity(1000e18, 1000e18);

        amountIn = bound(amountIn, 1e18, 100e18);

        // Single swap of 2x the amount
        uint256 bigOut = pool.getAmountOut(amountIn * 2, 1000e18, 1000e18);
        // Two swaps of 1x each would get less total due to price impact
        uint256 smallOut = pool.getAmountOut(amountIn, 1000e18, 1000e18);

        assertLt(
            bigOut,
            smallOut * 2,
            "INVARIANT: doubling input should give less than double output (sublinear)"
        );
    }
}

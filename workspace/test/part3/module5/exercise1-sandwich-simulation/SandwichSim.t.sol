// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the Sandwich Simulation
//  exercise. Implement SimplePool.sol and SandwichBot.sol to make these pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    SimplePool,
    InvalidToken,
    ZeroAmount,
    InsufficientOutput
} from "../../../../src/part3/module5/exercise1-sandwich-simulation/SimplePool.sol";
import {
    SandwichBot,
    NoPendingSandwich
} from "../../../../src/part3/module5/exercise1-sandwich-simulation/SandwichBot.sol";
import {MockERC20} from "../../../../src/part3/module5/mocks/MockERC20.sol";

contract SandwichSimTest is Test {
    // --- Contracts ---
    SimplePool public pool;
    SandwichBot public bot;
    MockERC20 public weth;
    MockERC20 public usdc;

    // --- Actors ---
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");
    address lp = makeAddr("lp");

    // --- Constants matching lesson: 100 ETH / 200,000 USDC ---
    uint256 constant INITIAL_ETH = 100e18;
    uint256 constant INITIAL_USDC = 200_000e18;

    // Lesson swap sizes
    uint256 constant USER_SWAP_AMOUNT = 20_000e18;  // User swaps 20,000 USDC
    uint256 constant FRONTRUN_AMOUNT = 10_000e18;   // Attacker front-runs with 10,000 USDC

    function setUp() public {
        // Deploy tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // Deploy pool
        pool = new SimplePool(address(weth), address(usdc));

        // Add initial liquidity: 100 ETH / 200,000 USDC
        weth.mint(lp, INITIAL_ETH);
        usdc.mint(lp, INITIAL_USDC);
        vm.startPrank(lp);
        weth.approve(address(pool), INITIAL_ETH);
        usdc.approve(address(pool), INITIAL_USDC);
        pool.addLiquidity(INITIAL_ETH, INITIAL_USDC);
        vm.stopPrank();

        // Fund user with USDC for swapping
        usdc.mint(user, USER_SWAP_AMOUNT);
        vm.prank(user);
        usdc.approve(address(pool), USER_SWAP_AMOUNT);

        // Fund attacker and deploy bot
        usdc.mint(attacker, FRONTRUN_AMOUNT);
        vm.startPrank(attacker);
        bot = new SandwichBot(address(pool));
        usdc.transfer(address(bot), FRONTRUN_AMOUNT);
        vm.stopPrank();
    }

    // =========================================================
    //  getAmountOut (TODO 1)
    // =========================================================

    function test_getAmountOut_matchesLessonExample() public view {
        // Lesson: 100 ETH / 200,000 USDC pool, swap 20,000 USDC → ETH
        // amountOut = 100 * 20,000 / (200,000 + 20,000) = 9.0909... ETH
        uint256 out = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);
        uint256 expected = INITIAL_ETH * USER_SWAP_AMOUNT / (INITIAL_USDC + USER_SWAP_AMOUNT);
        assertEq(out, expected, "Should match constant-product formula exactly");
    }

    function test_getAmountOut_smallTrade_lowSlippage() public view {
        // 100 USDC into 200k USDC pool — negligible price impact
        uint256 out = pool.getAmountOut(address(usdc), 100e18);
        // Expected: 100 * 100 / (200,000 + 100) = 0.04998... ETH ≈ $1999.9/ETH
        uint256 expected = INITIAL_ETH * 100e18 / (INITIAL_USDC + 100e18);
        assertEq(out, expected, "Small trade should have minimal slippage");
    }

    function test_getAmountOut_reverseDirection() public view {
        // Swap ETH → USDC (opposite direction)
        uint256 out = pool.getAmountOut(address(weth), 10e18);
        uint256 expected = INITIAL_USDC * 10e18 / (INITIAL_ETH + 10e18);
        assertEq(out, expected, "Reverse direction should use correct reserves");
    }

    function test_getAmountOut_revertsOnInvalidToken() public {
        vm.expectRevert(InvalidToken.selector);
        pool.getAmountOut(makeAddr("fake"), 1e18);
    }

    function test_getAmountOut_revertsOnZeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        pool.getAmountOut(address(usdc), 0);
    }

    // =========================================================
    //  swap (TODO 2)
    // =========================================================

    function test_swap_transfersTokensCorrectly() public {
        uint256 userUsdcBefore = usdc.balanceOf(user);

        vm.prank(user);
        uint256 out = pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        // User spent USDC
        assertEq(usdc.balanceOf(user), userUsdcBefore - USER_SWAP_AMOUNT, "User should spend USDC");
        // User received WETH
        assertEq(weth.balanceOf(user), out, "User should receive WETH");
    }

    function test_swap_updatesReserves() public {
        vm.prank(user);
        uint256 out = pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        assertEq(pool.reserve0(), INITIAL_ETH - out, "WETH reserve should decrease by output");
        assertEq(pool.reserve1(), INITIAL_USDC + USER_SWAP_AMOUNT, "USDC reserve should increase by input");
    }

    function test_swap_emitsEvent() public {
        uint256 expectedOut = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        vm.prank(user);
        vm.expectEmit(true, false, false, true, address(pool));
        emit SimplePool.Swap(user, address(usdc), USER_SWAP_AMOUNT, expectedOut);
        pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);
    }

    function test_swap_passesWithExactMinOutput() public {
        uint256 expectedOut = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        vm.prank(user);
        uint256 out = pool.swap(address(usdc), USER_SWAP_AMOUNT, expectedOut);
        assertEq(out, expectedOut, "Should succeed when minAmountOut equals actual output");
    }

    function test_swap_revertsWhenBelowMinOutput() public {
        uint256 expectedOut = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientOutput.selector, expectedOut, expectedOut + 1)
        );
        pool.swap(address(usdc), USER_SWAP_AMOUNT, expectedOut + 1);
    }

    // =========================================================
    //  frontRun (TODO 3)
    // =========================================================

    function test_frontRun_executesSwap() public {
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        // Bot should have swapped USDC → WETH
        assertEq(usdc.balanceOf(address(bot)), 0, "Bot should have spent all USDC");
        assertGt(weth.balanceOf(address(bot)), 0, "Bot should have received WETH");
    }

    function test_frontRun_tracksState() public {
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        assertEq(bot.frontRunTokenIn(), address(usdc), "Should track tokenIn");
        assertEq(bot.frontRunAmountIn(), FRONTRUN_AMOUNT, "Should track amountIn");
        // Lesson: 10,000 USDC → ~4.762 ETH
        uint256 expectedOut = INITIAL_ETH * FRONTRUN_AMOUNT / (INITIAL_USDC + FRONTRUN_AMOUNT);
        assertEq(bot.frontRunAmountOut(), expectedOut, "Should track amountOut");
    }

    function test_frontRun_pushesPrice() public {
        // User's output BEFORE front-run
        uint256 outputBefore = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        // Front-run pushes ETH price up
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        // User's output AFTER front-run — should be worse
        uint256 outputAfter = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        assertLt(outputAfter, outputBefore, "Front-run should worsen user's price");
    }

    // =========================================================
    //  backRun (TODO 4)
    // =========================================================

    function test_backRun_revertsWithoutFrontRun() public {
        vm.prank(attacker);
        vm.expectRevert(NoPendingSandwich.selector);
        bot.backRun();
    }

    function test_backRun_clearsState() public {
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        // User swap
        vm.prank(user);
        pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        // Back-run
        vm.prank(attacker);
        bot.backRun();

        // State should be cleared
        assertEq(bot.frontRunTokenIn(), address(0), "Should clear frontRunTokenIn");
        assertEq(bot.frontRunAmountIn(), 0, "Should clear frontRunAmountIn");
        assertEq(bot.frontRunAmountOut(), 0, "Should clear frontRunAmountOut");
    }

    // =========================================================
    //  Full Sandwich Sequence
    // =========================================================

    function test_sandwich_fullSequence_matchesLessonMath() public {
        // --- Clean swap output for comparison ---
        uint256 cleanOutput = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);
        // Lesson: 100 * 20,000 / (200,000 + 20,000) = 9.0909... ETH

        // --- Step 1: Front-run ---
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);
        // Lesson: 100 * 10,000 / (200,000 + 10,000) = 4.7619... ETH
        uint256 frontRunOut = bot.frontRunAmountOut();
        uint256 expectedFrontRunOut = INITIAL_ETH * FRONTRUN_AMOUNT / (INITIAL_USDC + FRONTRUN_AMOUNT);
        assertEq(frontRunOut, expectedFrontRunOut, "Front-run should match lesson: ~4.762 ETH");

        // --- Step 2: User swap (sandwiched) ---
        vm.prank(user);
        uint256 userOutput = pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        // User gets LESS than clean swap
        assertLt(userOutput, cleanOutput, "Sandwiched user must get less than clean swap");

        // --- Step 3: Back-run ---
        vm.prank(attacker);
        uint256 profit = bot.backRun();

        // Attacker made profit
        assertGt(profit, 0, "Attacker should profit from sandwich");

        // Verify user loss is significant
        uint256 userLoss = cleanOutput - userOutput;
        assertGt(userLoss, 0.5e18, "User should lose > 0.5 ETH to sandwich");
    }

    function test_sandwich_userLoss_matchesLesson() public {
        // Clean swap output
        uint256 cleanOutput = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        // Execute sandwich
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        vm.prank(user);
        uint256 sandwichedOutput = pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        // Lesson: user loss = 9.091 - 8.282 ≈ 0.809 ETH
        uint256 userLoss = cleanOutput - sandwichedOutput;
        assertApproxEqRel(userLoss, 0.809e18, 0.01e18, "User loss should be ~0.809 ETH");
    }

    function test_sandwich_attackerProfit_matchesLesson() public {
        // Execute full sandwich
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        vm.prank(user);
        pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        vm.prank(attacker);
        uint256 profit = bot.backRun();

        // Lesson: attacker profit = 11,940 - 10,000 = 1,940 USDC
        assertApproxEqRel(profit, 1_940e18, 0.01e18, "Attacker profit should be ~1,940 USDC");
    }

    function test_sandwich_botEndsWithMoreThanStarted() public {
        uint256 botUsdcBefore = usdc.balanceOf(address(bot));

        // Full sandwich
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        vm.prank(user);
        pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        vm.prank(attacker);
        bot.backRun();

        uint256 botUsdcAfter = usdc.balanceOf(address(bot));
        assertGt(botUsdcAfter, botUsdcBefore, "Bot should end with more USDC than it started");
    }

    // =========================================================
    //  Slippage Defense
    // =========================================================

    function test_slippage_tightSlippage_defeatsSandwich() public {
        // User calculates expected output BEFORE any front-run
        uint256 expectedOutput = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);
        // Tight slippage: 0.5% tolerance
        uint256 minOutput = expectedOutput * 995 / 1000;

        // Front-run pushes price
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        // User's swap REVERTS because output < minOutput
        vm.prank(user);
        vm.expectRevert(); // InsufficientOutput
        pool.swap(address(usdc), USER_SWAP_AMOUNT, minOutput);
    }

    function test_slippage_looseSlippage_sandwichSucceeds() public {
        // User sets loose slippage: 10% tolerance
        uint256 expectedOutput = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);
        uint256 minOutput = expectedOutput * 90 / 100;

        // Front-run
        vm.prank(attacker);
        bot.frontRun(address(usdc), FRONTRUN_AMOUNT);

        // User's swap SUCCEEDS — slippage is too loose to protect
        vm.prank(user);
        uint256 out = pool.swap(address(usdc), USER_SWAP_AMOUNT, minOutput);
        assertGe(out, minOutput, "Swap should succeed with loose slippage");
        assertLt(out, expectedOutput, "But user got worse execution than expected");
    }

    // =========================================================
    //  Small Trade Analysis
    // =========================================================

    function test_sandwich_smallTrade_negligibleProfit() public {
        // Small user trade: 100 USDC (vs 20,000 in lesson)
        uint256 smallAmount = 100e18;
        // Proportional front-run: 50 USDC (same 0.5x ratio as lesson: 10k/20k)
        uint256 smallFrontRun = 50e18;

        address smallUser = makeAddr("smallUser");
        usdc.mint(smallUser, smallAmount);
        vm.prank(smallUser);
        usdc.approve(address(pool), smallAmount);

        // Deploy a fresh bot for small trade scenario
        usdc.mint(attacker, smallFrontRun);
        vm.startPrank(attacker);
        SandwichBot smallBot = new SandwichBot(address(pool));
        usdc.transfer(address(smallBot), smallFrontRun);
        vm.stopPrank();

        // Full sandwich on the small trade
        vm.prank(attacker);
        smallBot.frontRun(address(usdc), smallFrontRun);

        vm.prank(smallUser);
        pool.swap(address(usdc), smallAmount, 0);

        vm.prank(attacker);
        uint256 profit = smallBot.backRun();

        // Profit should be negligible — less than $1 on a 100 USDC trade
        // (Compare to ~$1,940 on a 20,000 USDC trade in the lesson)
        assertLt(profit, 1e18, "Sandwich profit on 100 USDC trade should be < 1 USDC");
    }

    // =========================================================
    //  Fuzz Tests — Invariants
    // =========================================================

    function testFuzz_sandwichedUser_alwaysGetsLess(uint256 frontRunAmt) public {
        // Bound: meaningful front-run but less than pool reserves
        frontRunAmt = bound(frontRunAmt, 100e18, 50_000e18);

        // Clean output (snapshot before any manipulation)
        uint256 cleanOutput = pool.getAmountOut(address(usdc), USER_SWAP_AMOUNT);

        // Fund bot with additional USDC for the front-run
        usdc.mint(address(bot), frontRunAmt);

        // Front-run
        vm.prank(attacker);
        bot.frontRun(address(usdc), frontRunAmt);

        // User swap (sandwiched)
        vm.prank(user);
        uint256 sandwichedOutput = pool.swap(address(usdc), USER_SWAP_AMOUNT, 0);

        // INVARIANT: sandwich ALWAYS worsens user's execution
        assertLt(
            sandwichedOutput,
            cleanOutput,
            "INVARIANT: Sandwiched user always gets less output"
        );
    }

    function testFuzz_constantProduct_preserved(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 50_000e18);

        uint256 kBefore = pool.reserve0() * pool.reserve1();

        // Fund and swap
        usdc.mint(user, amountIn);
        vm.startPrank(user);
        usdc.approve(address(pool), amountIn);
        pool.swap(address(usdc), amountIn, 0);
        vm.stopPrank();

        uint256 kAfter = pool.reserve0() * pool.reserve1();

        // k should increase or stay the same (no fees = stays same; rounding = can increase)
        assertGe(kAfter, kBefore, "INVARIANT: k should never decrease after a swap");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SplitRouter exercise.
//  Implement SplitRouter.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    SplitRouter,
    ZeroAmount,
    InsufficientOutput,
    InvalidPool
} from "../../../../src/part3/module4/exercise1-split-router/SplitRouter.sol";
import {MockPool} from "../../../../src/part3/module4/mocks/MockPool.sol";

/// @dev Simple mintable ERC-20 for testing.
contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SplitRouterTest is Test {
    TestToken public weth;
    TestToken public usdc;

    MockPool public poolA; // Deep pool:   1000 ETH / 2,000,000 USDC
    MockPool public poolB; // Shallow pool:  500 ETH / 1,000,000 USDC

    SplitRouter public router;

    address alice = makeAddr("alice");

    // Matching the curriculum's worked example
    uint256 constant POOL_A_ETH = 1000e18;
    uint256 constant POOL_A_USDC = 2_000_000e18;
    uint256 constant POOL_B_ETH = 500e18;
    uint256 constant POOL_B_USDC = 1_000_000e18;

    function setUp() public {
        // Deploy tokens
        weth = new TestToken("Wrapped Ether", "WETH");
        usdc = new TestToken("USD Coin", "USDC");

        // Deploy pools with reserves (mint tokens to pools)
        poolA = new MockPool(address(weth), address(usdc), POOL_A_ETH, POOL_A_USDC);
        usdc.mint(address(poolA), POOL_A_USDC);
        weth.mint(address(poolA), POOL_A_ETH);

        poolB = new MockPool(address(weth), address(usdc), POOL_B_ETH, POOL_B_USDC);
        usdc.mint(address(poolB), POOL_B_USDC);
        weth.mint(address(poolB), POOL_B_ETH);

        // Deploy router
        router = new SplitRouter(address(poolA), address(poolB));

        // Give alice some ETH tokens to trade
        weth.mint(alice, 200e18);
        vm.prank(alice);
        weth.approve(address(router), type(uint256).max);
    }

    // =========================================================
    //  getAmountOut (TODO 1)
    // =========================================================

    function test_getAmountOut_basicCalculation() public view {
        // 10 ETH into pool A: 2,000,000 * 10 / (1000 + 10) = 19,801.98...
        uint256 out = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, 10e18);
        // 2_000_000e18 * 10e18 / (1000e18 + 10e18) = 19_801_980198019801980198
        uint256 expected = POOL_A_USDC * 10e18 / (POOL_A_ETH + 10e18);
        assertEq(out, expected, "getAmountOut should match constant-product formula");
    }

    function test_getAmountOut_largeTradeHighSlippage() public view {
        // 100 ETH into pool A: 2,000,000 * 100 / (1000 + 100) = 181,818.18...
        uint256 out = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, 100e18);
        uint256 expected = POOL_A_USDC * 100e18 / (POOL_A_ETH + 100e18);
        assertEq(out, expected, "Large trade should have high price impact");
        // Effective price ~$1818 vs spot $2000 — that's 9.1% slippage
        assertLt(out, 182_000e18, "100 ETH should get less than 182k USDC (>9% slippage)");
    }

    function test_getAmountOut_smallTradeLowSlippage() public view {
        // 1 ETH into pool A: 2,000,000 * 1 / (1000 + 1) = 1998.00...
        uint256 out = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, 1e18);
        // Should be very close to spot price ($2000)
        assertGt(out, 1997e18, "1 ETH should get ~$1998 (minimal slippage)");
    }

    function test_getAmountOut_revertsOnZeroInput() public {
        vm.expectRevert(ZeroAmount.selector);
        router.getAmountOut(POOL_A_ETH, POOL_A_USDC, 0);
    }

    function testFuzz_getAmountOut_neverExceedsReserve(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 amountIn
    ) public view {
        reserveIn = bound(reserveIn, 1e18, 1e30);
        reserveOut = bound(reserveOut, 1e18, 1e30);
        amountIn = bound(amountIn, 1, reserveIn * 10); // up to 10x reserve

        uint256 out = router.getAmountOut(reserveIn, reserveOut, amountIn);
        assertLt(out, reserveOut, "Output must never exceed reserve (asymptotic)");
    }

    // =========================================================
    //  getOptimalSplit (TODO 2)
    // =========================================================

    function test_getOptimalSplit_proportionalToReserves() public view {
        // Pool A has 1000 ETH, Pool B has 500 ETH → 2:1 ratio
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), 150e18);

        // Expected: 150 * 1000 / 1500 = 100 to A, 50 to B
        assertEq(toA, 100e18, "Should send 2/3 to deeper pool A");
        assertEq(toB, 50e18, "Should send 1/3 to shallower pool B");
    }

    function test_getOptimalSplit_sumsToTotal() public view {
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), 77e18);
        assertEq(toA + toB, 77e18, "Split amounts must sum to total input");
    }

    function test_getOptimalSplit_reverseDirection() public view {
        // Splitting USDC → WETH: pool A has 2M USDC, pool B has 1M USDC → 2:1
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(usdc), 300_000e18);

        // Expected: 300k * 2M / 3M = 200k to A, 100k to B
        assertEq(toA, 200_000e18, "USDC split should be proportional to USDC reserves");
        assertEq(toB, 100_000e18, "Remainder to pool B");
    }

    function test_getOptimalSplit_revertsOnZero() public {
        vm.expectRevert(ZeroAmount.selector);
        router.getOptimalSplit(address(weth), 0);
    }

    function testFuzz_getOptimalSplit_alwaysSumsToTotal(uint256 amount) public view {
        amount = bound(amount, 1, 1e30);
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), amount);
        assertEq(toA + toB, amount, "Split must always sum to total");
    }

    // =========================================================
    //  splitSwap (TODO 3)
    // =========================================================

    function test_splitSwap_executesCorrectly() public {
        uint256 amountIn = 100e18;

        // Compute expected split
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), amountIn);

        // Compute expected outputs
        (uint256 rInA, uint256 rOutA) = poolA.getReserves(address(weth));
        (uint256 rInB, uint256 rOutB) = poolB.getReserves(address(weth));
        uint256 expectedOutA = router.getAmountOut(rInA, rOutA, toA);
        uint256 expectedOutB = router.getAmountOut(rInB, rOutB, toB);
        uint256 expectedTotal = expectedOutA + expectedOutB;

        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 totalOut = router.splitSwap(address(weth), amountIn, 0);

        assertEq(totalOut, expectedTotal, "Total output should match expected");
        assertEq(
            usdc.balanceOf(alice) - balBefore,
            expectedTotal,
            "Alice should receive the output tokens"
        );
    }

    function test_splitSwap_betterThanSinglePool() public {
        // This is THE key test — proves splitting beats single-pool execution.
        uint256 amountIn = 100e18;

        // --- Single pool output (all to pool A) ---
        uint256 singleOut = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, amountIn);

        // --- Split output ---
        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), amountIn);
        uint256 splitOutA = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, toA);
        uint256 splitOutB = router.getAmountOut(POOL_B_ETH, POOL_B_USDC, toB);
        uint256 splitTotal = splitOutA + splitOutB;

        assertGt(
            splitTotal,
            singleOut,
            "Split trade MUST produce more output than single-pool trade"
        );

        // The improvement should be meaningful for a 100 ETH trade
        uint256 improvement = splitTotal - singleOut;
        assertGt(improvement, 1000e18, "Improvement should be > 1000 USDC for 100 ETH");
    }

    function test_splitSwap_pullsTokensFromUser() public {
        uint256 balBefore = weth.balanceOf(alice);
        uint256 amountIn = 50e18;

        vm.prank(alice);
        router.splitSwap(address(weth), amountIn, 0);

        assertEq(
            weth.balanceOf(alice),
            balBefore - amountIn,
            "Should pull exactly amountIn from user"
        );
    }

    function test_splitSwap_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        router.splitSwap(address(weth), 0, 0);
    }

    function test_splitSwap_revertsOnInsufficientOutput() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientOutput.selector);
        // Ask for way more than possible
        router.splitSwap(address(weth), 10e18, 100_000_000e18);
    }

    function test_splitSwap_updatesPoolReserves() public {
        uint256 amountIn = 20e18;
        (uint256 toA,) = router.getOptimalSplit(address(weth), amountIn);

        vm.prank(alice);
        router.splitSwap(address(weth), amountIn, 0);

        // Pool A should have more WETH now
        (uint256 newReserveIn,) = poolA.getReserves(address(weth));
        assertEq(newReserveIn, POOL_A_ETH + toA, "Pool A reserves should increase by amountToA");
    }

    // =========================================================
    //  singleSwap (TODO 4)
    // =========================================================

    function test_singleSwap_executesCorrectly() public {
        uint256 amountIn = 10e18;

        (uint256 rIn, uint256 rOut) = poolA.getReserves(address(weth));
        uint256 expectedOut = router.getAmountOut(rIn, rOut, amountIn);

        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 out = router.singleSwap(address(poolA), address(weth), amountIn, 0);

        assertEq(out, expectedOut, "Output should match constant-product formula");
        assertEq(usdc.balanceOf(alice) - balBefore, expectedOut, "Alice receives output");
    }

    function test_singleSwap_poolB() public {
        uint256 amountIn = 10e18;

        (uint256 rIn, uint256 rOut) = poolB.getReserves(address(weth));
        uint256 expectedOut = router.getAmountOut(rIn, rOut, amountIn);

        vm.prank(alice);
        uint256 out = router.singleSwap(address(poolB), address(weth), amountIn, 0);

        assertEq(out, expectedOut, "Pool B swap should work correctly");
    }

    function test_singleSwap_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        router.singleSwap(address(poolA), address(weth), 0, 0);
    }

    function test_singleSwap_revertsOnInvalidPool() public {
        vm.prank(alice);
        vm.expectRevert(InvalidPool.selector);
        router.singleSwap(address(0xdead), address(weth), 10e18, 0);
    }

    function test_singleSwap_revertsOnInsufficientOutput() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientOutput.selector);
        router.singleSwap(address(poolA), address(weth), 10e18, 100_000_000e18);
    }

    // =========================================================
    //  Integration: split vs single comparison
    // =========================================================

    function test_integration_splitAlwaysBetterForLargeTrades() public {
        // For any trade > ~1% of pool reserves, splitting should win
        uint256[] memory sizes = new uint256[](3);
        sizes[0] = 50e18;   // 5% of pool A
        sizes[1] = 100e18;  // 10% of pool A
        sizes[2] = 200e18;  // 20% of pool A

        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 amountIn = sizes[i];

            // Single pool (pool A — the deeper one, best single option)
            uint256 singleOut = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, amountIn);

            // Split
            (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), amountIn);
            uint256 splitA = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, toA);
            uint256 splitB = router.getAmountOut(POOL_B_ETH, POOL_B_USDC, toB);

            assertGt(
                splitA + splitB,
                singleOut,
                string.concat("Split should beat single for size index ", vm.toString(i))
            );
        }
    }

    function test_integration_smallTradeMinimalImprovement() public view {
        // For tiny trades, the improvement is negligible (< 0.1%)
        uint256 amountIn = 1e18; // 1 ETH — tiny relative to 1000 ETH reserve

        uint256 singleOut = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, amountIn);

        (uint256 toA, uint256 toB) = router.getOptimalSplit(address(weth), amountIn);
        uint256 splitA = router.getAmountOut(POOL_A_ETH, POOL_A_USDC, toA);
        uint256 splitB = router.getAmountOut(POOL_B_ETH, POOL_B_USDC, toB);

        uint256 improvement = (splitA + splitB) - singleOut;
        // Improvement should be very small for 1 ETH trade
        assertLt(improvement, 1e18, "1 ETH trade should have < $1 improvement from splitting");
    }
}

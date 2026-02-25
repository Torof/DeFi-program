// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: V2 Extensions — Flash Swaps, Multi-Hop Routing, TWAP
//
// These exercises extend the ConstantProductPool you built in Exercise 1.
// They explore three patterns from Uniswap V2 that are critical for DeFi
// composability:
//
//   1. Flash swaps — borrow tokens, use them, repay in the same tx
//   2. Multi-hop routing — chain swaps across multiple pools (A→B→C)
//   3. TWAP oracle — time-weighted average price from cumulative accumulators
//
// This is a TEST-ONLY exercise. You'll implement the test scenarios and
// helper contracts directly in this file. No separate scaffold needed.
//
// Run: forge test --match-contract V2ExtensionsTest -vvv
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConstantProductPool} from "../../../../src/part2/module2/exercise1-constant-product/ConstantProductPool.sol";
import {MockERC20} from "../../../../src/part2/module2/mocks/MockERC20.sol";

// =============================================================
//  TODO 1: Flash Swap Consumer
// =============================================================
// A flash swap borrows tokens from the pool, uses them (e.g., for
// arbitrage), and repays with fee — all in one transaction.
//
// In Uniswap V2, the pool optimistically transfers tokens OUT, then
// calls a callback on the receiver, then checks the k invariant.
// If k is satisfied (tokens repaid + fee), the tx succeeds.
//
// Your ConstantProductPool doesn't have a flash swap callback, so
// we'll simulate the pattern: borrow via a swap that overpays.
//
// Implement a FlashSwapConsumer contract that:
//   - Receives tokens from the pool (via a normal swap)
//   - "Uses" them (just holds them for the duration)
//   - The test verifies the pool's k invariant still holds
//
// Hint: The simplest approach is to show that you can swap tokenA→tokenB,
//       then immediately swap tokenB→tokenA in the same transaction,
//       demonstrating the atomic round-trip pattern that flash swaps enable.
//       Track the profit/loss from fees.

/// @notice Demonstrates atomic round-trip swaps (flash swap pattern).
/// @dev TODO: Implement the executeFlashSwap function.
///      The contract should:
///        1. Swap tokenA → tokenB on the pool
///        2. Swap tokenB → tokenA on the pool (return trip)
///        3. The caller ends up with slightly less tokenA (paid fees both ways)
///      This simulates what a flash swap does: borrow, use, repay.
contract FlashSwapConsumer {
    ConstantProductPool public pool;
    IERC20 public tokenA;
    IERC20 public tokenB;

    constructor(address _pool, address _tokenA, address _tokenB) {
        pool = ConstantProductPool(_pool);
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        // Approve pool for both tokens
        tokenA.approve(_pool, type(uint256).max);
        tokenB.approve(_pool, type(uint256).max);
    }

    /// @notice Executes an atomic round-trip swap (simulating flash swap).
    /// @dev TODO: Implement this function.
    ///   1. Record starting tokenA balance
    ///   2. Swap amountIn of tokenA → tokenB
    ///   3. Swap ALL received tokenB → tokenA
    ///   4. Return the amount of tokenA lost to fees (should be > 0)
    ///
    /// @param amountIn Amount of tokenA to "flash borrow" via swap
    /// @return feePaid The amount of tokenA lost to round-trip fees
    function executeFlashSwap(uint256 amountIn) external returns (uint256 feePaid) {
        // TODO: Implement
        revert("Not implemented");
    }
}

// =============================================================
//  TODO 2: Simple Router (Multi-Hop)
// =============================================================
// In practice, you often need to swap A→C but only pools A/B and B/C
// exist. A router chains the swaps: A→B on pool1, then B→C on pool2.
//
// Implement a SimpleRouter that:
//   - Takes two pool addresses and executes a two-hop swap
//   - Transfers tokenIn from the user, swaps through both pools,
//     and transfers tokenOut to the user

/// @notice Minimal two-hop router for chaining swaps across pools.
/// @dev TODO: Implement the swapExactIn function.
///      The router should:
///        1. Transfer tokenIn from msg.sender
///        2. Swap tokenIn → intermediate token on pool1
///        3. Swap intermediate → tokenOut on pool2
///        4. Transfer tokenOut to msg.sender
///        5. Return the final output amount
contract SimpleRouter {
    /// @notice Executes a two-hop swap: tokenIn → mid (pool1) → tokenOut (pool2).
    /// @dev TODO: Implement this function.
    ///   1. Transfer amountIn of tokenIn from msg.sender to this contract
    ///   2. Approve pool1 for tokenIn, then swap tokenIn on pool1
    ///   3. Approve pool2 for the intermediate token, then swap on pool2
    ///   4. Transfer the final output token to msg.sender
    ///   5. Return the output amount
    ///
    /// Hint: After swap on pool1, check this contract's balance of the
    ///       intermediate token to know how much to swap on pool2.
    ///
    /// @param pool1 First pool (tokenIn/midToken pair)
    /// @param pool2 Second pool (midToken/tokenOut pair)
    /// @param tokenIn Token being sold
    /// @param midToken Intermediate token (output of pool1, input to pool2)
    /// @param tokenOut Token being bought
    /// @param amountIn Amount of tokenIn to sell
    /// @return amountOut Amount of tokenOut received
    function swapExactIn(
        address pool1,
        address pool2,
        address tokenIn,
        address midToken,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // TODO: Implement
        revert("Not implemented");
    }
}

contract V2ExtensionsTest is Test {
    // --- Tokens ---
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;

    // --- Pools ---
    ConstantProductPool poolAB; // tokenA / tokenB
    ConstantProductPool poolBC; // tokenB / tokenC

    // --- Actors ---
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        tokenC = new MockERC20("Token C", "TKC", 18);

        // Deploy pools
        poolAB = new ConstantProductPool(address(tokenA), address(tokenB));
        poolBC = new ConstantProductPool(address(tokenB), address(tokenC));

        // Fund alice (liquidity provider)
        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 2_000_000e18); // extra B for both pools
        tokenC.mint(alice, 1_000_000e18);

        // Fund bob (swapper)
        tokenA.mint(bob, 100_000e18);
        tokenB.mint(bob, 100_000e18);
        tokenC.mint(bob, 100_000e18);

        // Alice provides liquidity to both pools
        vm.startPrank(alice);
        tokenA.approve(address(poolAB), type(uint256).max);
        tokenB.approve(address(poolAB), type(uint256).max);
        tokenB.approve(address(poolBC), type(uint256).max);
        tokenC.approve(address(poolBC), type(uint256).max);

        // Pool AB: 100k A + 100k B (1:1 price)
        poolAB.addLiquidity(100_000e18, 100_000e18);
        // Pool BC: 100k B + 200k C (1 B = 2 C)
        poolBC.addLiquidity(100_000e18, 200_000e18);
        vm.stopPrank();

        // Bob approves pools
        vm.startPrank(bob);
        tokenA.approve(address(poolAB), type(uint256).max);
        tokenB.approve(address(poolAB), type(uint256).max);
        tokenB.approve(address(poolBC), type(uint256).max);
        tokenC.approve(address(poolBC), type(uint256).max);
        vm.stopPrank();
    }

    // =========================================================
    //  Flash Swap Tests
    // =========================================================

    function test_FlashSwap_RoundTrip_PaysFees() public {
        FlashSwapConsumer consumer = new FlashSwapConsumer(
            address(poolAB), address(tokenA), address(tokenB)
        );

        // Fund the consumer
        uint256 startAmount = 10_000e18;
        tokenA.mint(address(consumer), startAmount);

        uint256 balBefore = tokenA.balanceOf(address(consumer));
        uint256 feePaid = consumer.executeFlashSwap(1_000e18);
        uint256 balAfter = tokenA.balanceOf(address(consumer));

        // Round-trip should cost fees (0.3% each way ≈ 0.6% total)
        assertGt(feePaid, 0, "Round-trip swap must cost fees");
        assertEq(balBefore - balAfter, feePaid, "Fee paid should match balance difference");

        // Fee should be roughly 0.6% of 1000 = ~6 tokens (but slightly more due to price impact)
        assertGt(feePaid, 5e18, "Fee should be at least ~0.5% of swap amount");
        assertLt(feePaid, 20e18, "Fee should be less than 2% (sanity check)");
    }

    function test_FlashSwap_KInvariant_StillHolds() public {
        uint256 kBefore = poolAB.getK();

        FlashSwapConsumer consumer = new FlashSwapConsumer(
            address(poolAB), address(tokenA), address(tokenB)
        );
        tokenA.mint(address(consumer), 10_000e18);

        consumer.executeFlashSwap(1_000e18);

        uint256 kAfter = poolAB.getK();
        assertGe(kAfter, kBefore, "K invariant must hold after round-trip (fees increase k)");
    }

    // =========================================================
    //  Multi-Hop Routing Tests
    // =========================================================

    function test_MultiHop_A_to_C_ThroughB() public {
        SimpleRouter router = new SimpleRouter();

        // Bob wants to swap A → C, but no A/C pool exists
        // Route: A → B (poolAB) → C (poolBC)
        uint256 amountIn = 1_000e18;

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);

        uint256 bobC_before = tokenC.balanceOf(bob);

        uint256 amountOut = router.swapExactIn(
            address(poolAB),
            address(poolBC),
            address(tokenA),
            address(tokenB),
            address(tokenC),
            amountIn
        );
        vm.stopPrank();

        uint256 bobC_after = tokenC.balanceOf(bob);

        assertGt(amountOut, 0, "Should receive tokenC");
        assertEq(bobC_after - bobC_before, amountOut, "Balance change should match returned amount");
    }

    function test_MultiHop_OutputMatchesManualSwaps() public {
        // Compare: router multi-hop vs doing two manual swaps
        // They should produce the same result (same pool state at start)

        // --- Manual path: swap A→B on poolAB, then B→C on poolBC ---
        uint256 amountIn = 1_000e18;

        // Calculate expected output from manual hops
        uint256 expectedMidAmount = poolAB.getAmountOut(
            amountIn, poolAB.reserve0(), poolAB.reserve1()
        );
        uint256 expectedFinalAmount = poolBC.getAmountOut(
            expectedMidAmount, poolBC.reserve0(), poolBC.reserve1()
        );

        // --- Router path ---
        SimpleRouter router = new SimpleRouter();

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);

        uint256 routerOut = router.swapExactIn(
            address(poolAB),
            address(poolBC),
            address(tokenA),
            address(tokenB),
            address(tokenC),
            amountIn
        );
        vm.stopPrank();

        assertEq(routerOut, expectedFinalAmount, "Router output must match manual two-hop calculation");
    }

    function test_MultiHop_PriceImpact_WorsensThroughHops() public {
        // A large multi-hop swap should have compounding price impact
        SimpleRouter router = new SimpleRouter();

        // Small swap
        uint256 smallIn = 100e18;
        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        uint256 smallOut = router.swapExactIn(
            address(poolAB), address(poolBC),
            address(tokenA), address(tokenB), address(tokenC),
            smallIn
        );
        vm.stopPrank();
        uint256 smallRate = smallOut * 1e18 / smallIn;

        // Reset pool state for fair comparison
        setUp();
        router = new SimpleRouter();

        // Large swap (10x)
        uint256 largeIn = 1_000e18;
        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        uint256 largeOut = router.swapExactIn(
            address(poolAB), address(poolBC),
            address(tokenA), address(tokenB), address(tokenC),
            largeIn
        );
        vm.stopPrank();
        uint256 largeRate = largeOut * 1e18 / largeIn;

        assertGt(smallRate, largeRate, "Larger swaps should get worse rate (compounding price impact)");
    }

    // =========================================================
    //  TWAP Oracle Tests
    // =========================================================
    // These tests demonstrate why spot price is dangerous as an oracle
    // and how time-weighted averaging smooths manipulation.
    //
    // We don't build a full Uniswap V2 price accumulator here (the pool
    // doesn't have one). Instead, we simulate the TWAP concept:
    //   - Record spot prices at regular intervals
    //   - Compute the time-weighted average
    //   - Show it resists single-block manipulation

    function test_TWAP_SpotPriceMovesAfterSwap() public {
        uint256 priceBefore = poolAB.getSpotPrice();

        // Bob buys tokenB (sells tokenA) — should move price
        vm.prank(bob);
        poolAB.swap(address(tokenA), 10_000e18);

        uint256 priceAfter = poolAB.getSpotPrice();

        // tokenA reserve increased, tokenB reserve decreased → price (B/A) decreased
        assertLt(priceAfter, priceBefore, "Spot price should move after swap");
    }

    function test_TWAP_AverageResistsSingleSwap() public {
        // Simulate TWAP by recording prices over time
        // Record 5 "observations" 1 hour apart, with a manipulation at observation 3

        uint256[] memory prices = new uint256[](5);
        uint256[] memory timestamps = new uint256[](5);

        // Observation 0: initial price
        prices[0] = poolAB.getSpotPrice();
        timestamps[0] = block.timestamp;

        // Observation 1: 1 hour later, no trades
        vm.warp(block.timestamp + 1 hours);
        prices[1] = poolAB.getSpotPrice();
        timestamps[1] = block.timestamp;

        // Observation 2: 1 hour later, no trades
        vm.warp(block.timestamp + 1 hours);
        prices[2] = poolAB.getSpotPrice();
        timestamps[2] = block.timestamp;

        // Observation 3: MANIPULATION — huge swap moves the price
        vm.warp(block.timestamp + 1 hours);
        vm.prank(bob);
        poolAB.swap(address(tokenA), 30_000e18); // large swap
        prices[3] = poolAB.getSpotPrice();
        timestamps[3] = block.timestamp;

        // Observation 4: 1 hour later (price stays manipulated in this simple model)
        vm.warp(block.timestamp + 1 hours);
        prices[4] = poolAB.getSpotPrice();
        timestamps[4] = block.timestamp;

        // Compute TWAP over all 5 observations
        uint256 twap = _computeTWAP(prices, timestamps);

        // The manipulated spot price (observation 3)
        uint256 manipulatedSpot = prices[3];

        // TWAP should be between the initial price and the manipulated price
        // (it averages the manipulation away)
        assertGt(twap, manipulatedSpot, "TWAP should be higher than manipulated spot (manipulation pushed price down)");
        assertLt(twap, prices[0], "TWAP should be lower than initial price (some manipulation effect)");

        // The key insight: TWAP only reflects 2/5 of the manipulation window
        // An attacker would need to sustain the manipulation for the FULL window
        // to fully move the TWAP — which costs capital to arbitrageurs
    }

    function test_TWAP_LongerWindowMoreResistant() public {
        uint256 initialPrice = poolAB.getSpotPrice();

        // Short window: 2 observations (before + after manipulation)
        uint256[] memory shortPrices = new uint256[](2);
        uint256[] memory shortTimestamps = new uint256[](2);

        shortPrices[0] = initialPrice;
        shortTimestamps[0] = block.timestamp;

        vm.warp(block.timestamp + 1 hours);
        vm.prank(bob);
        poolAB.swap(address(tokenA), 30_000e18);
        shortPrices[1] = poolAB.getSpotPrice();
        shortTimestamps[1] = block.timestamp;

        uint256 shortTWAP = _computeTWAP(shortPrices, shortTimestamps);

        // Reset for long window test
        setUp();

        // Long window: 5 observations, manipulation only at the end
        uint256[] memory longPrices = new uint256[](5);
        uint256[] memory longTimestamps = new uint256[](5);

        for (uint256 i = 0; i < 4; i++) {
            longPrices[i] = poolAB.getSpotPrice();
            longTimestamps[i] = block.timestamp;
            vm.warp(block.timestamp + 1 hours);
        }
        vm.prank(bob);
        poolAB.swap(address(tokenA), 30_000e18);
        longPrices[4] = poolAB.getSpotPrice();
        longTimestamps[4] = block.timestamp;

        uint256 longTWAP = _computeTWAP(longPrices, longTimestamps);

        // Long TWAP should be closer to the real price (more resistant)
        uint256 shortDeviation = initialPrice > shortTWAP
            ? initialPrice - shortTWAP
            : shortTWAP - initialPrice;
        uint256 longDeviation = initialPrice > longTWAP
            ? initialPrice - longTWAP
            : longTWAP - initialPrice;

        assertLt(longDeviation, shortDeviation, "Longer TWAP window should be more resistant to manipulation");
    }

    // --- TWAP helper ---

    /// @dev Computes a simple time-weighted average price from observations.
    ///      TWAP = Σ(price_i × duration_i) / Σ(duration_i)
    function _computeTWAP(
        uint256[] memory prices,
        uint256[] memory timestamps
    ) internal pure returns (uint256) {
        require(prices.length == timestamps.length && prices.length >= 2, "Need >= 2 observations");

        uint256 weightedSum;
        uint256 totalDuration;

        for (uint256 i = 0; i < prices.length - 1; i++) {
            uint256 duration = timestamps[i + 1] - timestamps[i];
            weightedSum += prices[i] * duration;
            totalDuration += duration;
        }

        return weightedSum / totalDuration;
    }
}

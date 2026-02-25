// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the V3PositionCalculator
//  exercise. Implement V3PositionCalculator.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    V3PositionCalculator,
    InvalidRange,
    ZeroLiquidity
} from "../../../../src/part2/module2/exercise2-v3-position/V3PositionCalculator.sol";

/// @dev Wrapper contract to expose the library's internal functions for testing.
contract V3CalcHarness {
    function getAmount0Delta(
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) external pure returns (uint256) {
        return V3PositionCalculator.getAmount0Delta(sqrtLowerX96, sqrtUpperX96, liquidity);
    }

    function getAmount1Delta(
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) external pure returns (uint256) {
        return V3PositionCalculator.getAmount1Delta(sqrtLowerX96, sqrtUpperX96, liquidity);
    }

    function getPositionAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        return V3PositionCalculator.getPositionAmounts(sqrtPriceX96, sqrtLowerX96, sqrtUpperX96, liquidity);
    }

    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external pure returns (uint128) {
        return V3PositionCalculator.getLiquidityForAmounts(
            sqrtPriceX96, sqrtLowerX96, sqrtUpperX96, amount0Desired, amount1Desired
        );
    }
}

contract V3PositionCalculatorTest is Test {
    V3CalcHarness calc;

    uint256 constant Q96 = 1 << 96;

    // =========================================================
    //  Pre-computed sqrtPriceX96 values for testing
    // =========================================================
    //
    //  sqrtPriceX96 = √P × 2^96 where P = price of token1 in token0 terms
    //
    //  For two 18-decimal tokens:
    //    P = 1.0  → sqrtPriceX96 = 1.0 × 2^96   = 79228162514264337593543950336
    //    P = 2.0  → sqrtPriceX96 = √2 × 2^96     ≈ 112045541949572279837463876454
    //    P = 4.0  → sqrtPriceX96 = 2.0 × 2^96    = 158456325028528675187087900672
    //    P = 0.5  → sqrtPriceX96 = √0.5 × 2^96   ≈ 56022770974786139918731938227
    //    P = 0.25 → sqrtPriceX96 = 0.5 × 2^96    = 39614081257132168796771975168
    //    P = 9.0  → sqrtPriceX96 = 3.0 × 2^96    = 237684487542793012780631851008
    //
    //  These correspond to Uniswap V3 ticks:
    //    P=1.0 → tick 0,  P=2.0 → tick ~6931,  P=4.0 → tick ~13863
    //    P=0.5 → tick ~-6932, P=0.25 → tick ~-13863
    // =========================================================

    // Price = 1.0 (tick 0)
    uint160 constant SQRT_P_1_0 = 79228162514264337593543950336;
    // Price = 2.0 (tick ~6931)
    uint160 constant SQRT_P_2_0 = 112045541949572279837463876454;
    // Price = 4.0 (tick ~13863)
    uint160 constant SQRT_P_4_0 = 158456325028528675187087900672;
    // Price = 0.5 (tick ~-6932)
    uint160 constant SQRT_P_0_5 = 56022770974786139918731938227;
    // Price = 0.25 (tick ~-13863)
    uint160 constant SQRT_P_0_25 = 39614081257132168796771975168;
    // Price = 9.0 (tick ~21972)
    uint160 constant SQRT_P_9_0 = 237684487542793012780631851008;
    // Price = 3.0 (tick ~10986) — √3 × 2^96
    uint160 constant SQRT_P_3_0 = 137241674691498528759045199872;

    // Standard test liquidity
    uint128 constant L = 1e18;

    function setUp() public {
        calc = new V3CalcHarness();
    }

    // =========================================================
    //  Core: Three Cases
    // =========================================================

    function test_BelowRange_AllToken0() public view {
        // Current price = 0.5, range = [1.0, 4.0]
        // Price is BELOW the range → position is 100% token0
        (uint256 amount0, uint256 amount1) = calc.getPositionAmounts(
            SQRT_P_0_5,  // current price below range
            SQRT_P_1_0,  // lower bound: price 1.0
            SQRT_P_4_0,  // upper bound: price 4.0
            L
        );

        assertGt(amount0, 0, "Below range: should hold token0");
        assertEq(amount1, 0, "Below range: should hold ZERO token1");
    }

    function test_AboveRange_AllToken1() public view {
        // Current price = 9.0, range = [1.0, 4.0]
        // Price is ABOVE the range → position is 100% token1
        (uint256 amount0, uint256 amount1) = calc.getPositionAmounts(
            SQRT_P_9_0,  // current price above range
            SQRT_P_1_0,  // lower bound
            SQRT_P_4_0,  // upper bound
            L
        );

        assertEq(amount0, 0, "Above range: should hold ZERO token0");
        assertGt(amount1, 0, "Above range: should hold token1");
    }

    function test_WithinRange_BothTokens() public view {
        // Current price = 2.0, range = [1.0, 4.0]
        // Price is WITHIN range → holds both tokens
        (uint256 amount0, uint256 amount1) = calc.getPositionAmounts(
            SQRT_P_2_0,  // current price in range
            SQRT_P_1_0,  // lower bound
            SQRT_P_4_0,  // upper bound
            L
        );

        assertGt(amount0, 0, "In range: should hold some token0");
        assertGt(amount1, 0, "In range: should hold some token1");
    }

    // =========================================================
    //  Boundary Cases
    // =========================================================

    function test_AtLowerBound_AllToken0() public view {
        // Current price exactly at lower bound → all token0 (no token1 earned yet)
        (uint256 amount0, uint256 amount1) = calc.getPositionAmounts(
            SQRT_P_1_0,  // current = lower bound
            SQRT_P_1_0,
            SQRT_P_4_0,
            L
        );

        assertGt(amount0, 0, "At lower bound: should hold token0");
        assertEq(amount1, 0, "At lower bound: should hold ZERO token1");
    }

    function test_AtUpperBound_AllToken1() public view {
        // Current price exactly at upper bound → all token1 (fully converted)
        (uint256 amount0, uint256 amount1) = calc.getPositionAmounts(
            SQRT_P_4_0,  // current = upper bound
            SQRT_P_1_0,
            SQRT_P_4_0,
            L
        );

        assertEq(amount0, 0, "At upper bound: should hold ZERO token0");
        assertGt(amount1, 0, "At upper bound: should hold token1");
    }

    // =========================================================
    //  Properties
    // =========================================================

    function test_NarrowRange_MoreConcentrated() public view {
        // Same liquidity in narrow range [1.0, 2.0] vs wide range [0.25, 9.0]
        // At price 1.5 (between both ranges), narrow range provides more tokens
        uint160 sqrtP_1_5 = uint160(Math.sqrt(15e17) * Q96 / Math.sqrt(1e18));

        (uint256 narrow0, uint256 narrow1) = calc.getPositionAmounts(
            sqrtP_1_5,
            SQRT_P_1_0,  // narrow: [1.0, 2.0]
            SQRT_P_2_0,
            L
        );

        (uint256 wide0, uint256 wide1) = calc.getPositionAmounts(
            sqrtP_1_5,
            SQRT_P_0_25, // wide: [0.25, 9.0]
            SQRT_P_9_0,
            L
        );

        // For the SAME liquidity L, a wide range requires MORE total tokens
        // to fill. But the narrow range is more CAPITAL EFFICIENT — it provides
        // more depth (better prices) per dollar deposited. The test verifies
        // that wide range needs more tokens, proving narrow range is more efficient.
        assertLt(
            narrow0 + narrow1,
            wide0 + wide1,
            "Narrow range should need FEWER tokens for same L (more capital efficient)"
        );
    }

    function test_Amount0Delta_KnownValues() public view {
        // For range [1.0, 4.0] with L = 1e18:
        // amount0 = L × 2^96 × (sqrt(4) - sqrt(1)) / (sqrt(1) × sqrt(4))
        //         = L × 2^96 × (2 - 1) / (1 × 2)
        //         = L × 2^96 / 2 / 2^96  ... wait, let's trace carefully:
        //         = L × 2^96 × (sqrtUpper - sqrtLower) / sqrtUpper / sqrtLower
        //         = 1e18 × 2^96 × (2×2^96 - 1×2^96) / (2×2^96) / (1×2^96)
        //         = 1e18 × 2^96 × 2^96 / (2×2^96) / 2^96
        //         = 1e18 × 2^96 / (2×2^96)
        //         = 1e18 / 2
        //         = 5e17
        uint256 amount0 = calc.getAmount0Delta(SQRT_P_1_0, SQRT_P_4_0, L);

        assertApproxEqRel(
            amount0,
            5e17,
            1e15, // 0.1% tolerance for rounding
            "amount0 for L=1e18, range [1.0, 4.0] should be ~0.5e18"
        );
    }

    function test_Amount1Delta_KnownValues() public view {
        // For range [1.0, 4.0] with L = 1e18:
        // amount1 = L × (sqrtUpper - sqrtLower) / 2^96
        //         = 1e18 × (2×2^96 - 1×2^96) / 2^96
        //         = 1e18 × 2^96 / 2^96
        //         = 1e18
        uint256 amount1 = calc.getAmount1Delta(SQRT_P_1_0, SQRT_P_4_0, L);

        assertApproxEqRel(
            amount1,
            1e18,
            1e15,
            "amount1 for L=1e18, range [1.0, 4.0] should be ~1e18"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_MoreLiquidity_MoreTokens(uint128 liquidity) public view {
        liquidity = uint128(bound(uint256(liquidity), 1e15, 1e25));

        (uint256 a0_base, uint256 a1_base) = calc.getPositionAmounts(
            SQRT_P_2_0, SQRT_P_1_0, SQRT_P_4_0, uint128(1e18)
        );

        (uint256 a0_more, uint256 a1_more) = calc.getPositionAmounts(
            SQRT_P_2_0, SQRT_P_1_0, SQRT_P_4_0, liquidity
        );

        if (liquidity > 1e18) {
            assertGe(a0_more, a0_base, "INVARIANT: more liquidity means more token0");
            assertGe(a1_more, a1_base, "INVARIANT: more liquidity means more token1");
        } else if (liquidity < 1e18) {
            assertLe(a0_more, a0_base, "INVARIANT: less liquidity means less token0");
            assertLe(a1_more, a1_base, "INVARIANT: less liquidity means less token1");
        }
    }

    function testFuzz_DoubleLiquidity_DoubleTokens(uint128 liquidity) public view {
        liquidity = uint128(bound(uint256(liquidity), 1e15, type(uint64).max));

        (uint256 a0_single, uint256 a1_single) = calc.getPositionAmounts(
            SQRT_P_2_0, SQRT_P_1_0, SQRT_P_4_0, liquidity
        );

        (uint256 a0_double, uint256 a1_double) = calc.getPositionAmounts(
            SQRT_P_2_0, SQRT_P_1_0, SQRT_P_4_0, liquidity * 2
        );

        // Doubling liquidity should exactly double token amounts (linear relationship)
        assertApproxEqAbs(
            a0_double,
            a0_single * 2,
            2, // at most 2 wei rounding error
            "INVARIANT: doubling liquidity should double token0 amount"
        );
        assertApproxEqAbs(
            a1_double,
            a1_single * 2,
            2,
            "INVARIANT: doubling liquidity should double token1 amount"
        );
    }

    function testFuzz_GetAmount0_NeverOverflows(uint128 liquidity) public view {
        liquidity = uint128(bound(uint256(liquidity), 1, type(uint128).max));

        // Should not revert for any valid liquidity
        calc.getAmount0Delta(SQRT_P_1_0, SQRT_P_4_0, liquidity);
    }

    // =========================================================
    //  Error Cases
    // =========================================================

    function test_Revert_InvalidRange() public {
        vm.expectRevert(InvalidRange.selector);
        calc.getPositionAmounts(SQRT_P_2_0, SQRT_P_4_0, SQRT_P_1_0, L); // lower > upper
    }

    function test_Revert_ZeroLiquidity() public {
        vm.expectRevert(ZeroLiquidity.selector);
        calc.getPositionAmounts(SQRT_P_2_0, SQRT_P_1_0, SQRT_P_4_0, 0);
    }
}

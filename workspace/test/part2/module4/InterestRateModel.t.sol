// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the InterestRateModel
//  exercise. Implement InterestRateModel.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {InterestRateModel} from "../../../src/part2/module4/InterestRateModel.sol";

contract InterestRateModelTest is Test {
    InterestRateModel model;

    uint256 constant RAY = 1e27;

    // Curve parameters (matching Aave V3 typical config):
    //   base=2%, slope1=8%, slope2=100%, optimal=80%
    uint256 constant BASE_RATE = 0.02e27;
    uint256 constant SLOPE1 = 0.08e27;
    uint256 constant SLOPE2 = 1.00e27;
    uint256 constant OPTIMAL = 0.80e27;

    function setUp() public {
        model = new InterestRateModel(BASE_RATE, SLOPE1, SLOPE2, OPTIMAL);
    }

    // =========================================================
    //  RAY Multiplication
    // =========================================================

    function test_RayMul_KnownValues() public view {
        // 2 × 3 = 6
        assertEq(model.rayMul(2e27, 3e27), 6e27, "2 RAY * 3 RAY should equal 6 RAY");
    }

    function test_RayMul_Fractional() public view {
        // 1 × 0.5 = 0.5
        assertEq(model.rayMul(1e27, 0.5e27), 0.5e27, "1 RAY * 0.5 RAY should equal 0.5 RAY");
    }

    function test_RayMul_Zero() public view {
        assertEq(model.rayMul(5e27, 0), 0, "Anything times zero should be zero");
        assertEq(model.rayMul(0, 5e27), 0, "Zero times anything should be zero");
    }

    function test_RayMul_Identity() public view {
        // Multiplying by RAY (1.0) should return the same value
        assertEq(model.rayMul(12345e27, RAY), 12345e27, "Multiplying by RAY should be identity");
    }

    // =========================================================
    //  Utilization Rate
    // =========================================================

    function test_Utilization_ZeroDeposits() public view {
        // No deposits → 0 utilization (avoid div by zero)
        assertEq(model.getUtilization(0, 0), 0, "Zero deposits should return 0 utilization");
    }

    function test_Utilization_ZeroBorrows() public view {
        assertEq(model.getUtilization(1000e18, 0), 0, "Zero borrows should be 0% utilization");
    }

    function test_Utilization_Fifty_Percent() public view {
        uint256 util = model.getUtilization(1000e18, 500e18);
        assertEq(util, 0.5e27, "500/1000 should be 50% (0.5e27)");
    }

    function test_Utilization_AtOptimal() public view {
        uint256 util = model.getUtilization(1000e18, 800e18);
        assertEq(util, 0.8e27, "800/1000 should be 80% (0.8e27)");
    }

    function test_Utilization_Full() public view {
        uint256 util = model.getUtilization(1000e18, 1000e18);
        assertEq(util, RAY, "1000/1000 should be 100% (1e27)");
    }

    function testFuzz_Utilization_NeverExceedsRay(uint256 deposits, uint256 borrows) public view {
        deposits = bound(deposits, 1, type(uint128).max);
        borrows = bound(borrows, 0, deposits); // borrows <= deposits in a healthy pool
        uint256 util = model.getUtilization(deposits, borrows);
        assertLe(util, RAY, "Utilization should never exceed RAY (100%)");
    }

    // =========================================================
    //  Borrow Rate (Kinked Curve)
    // =========================================================

    function test_BorrowRate_ZeroUtilization() public view {
        // At 0% utilization: rate = base = 2%
        uint256 rate = model.getBorrowRate(1000e18, 0);
        assertEq(rate, BASE_RATE, "At 0% util, rate should equal base rate (2%)");
    }

    function test_BorrowRate_BelowKink_40Percent() public view {
        // At 40% utilization: rate = 0.02 + 0.08 × (0.40/0.80) = 0.02 + 0.04 = 0.06
        uint256 rate = model.getBorrowRate(1000e18, 400e18);
        assertEq(rate, 0.06e27, "At 40% util, rate should be 6%");
    }

    function test_BorrowRate_AtKink_80Percent() public view {
        // At 80% utilization (the kink): rate = 0.02 + 0.08 = 0.10
        uint256 rate = model.getBorrowRate(1000e18, 800e18);
        assertEq(rate, 0.10e27, "At 80% util (kink), rate should be 10%");
    }

    function test_BorrowRate_AboveKink_90Percent() public view {
        // At 90% utilization: rate = 0.02 + 0.08 + 1.00 × (0.10/0.20) = 0.10 + 0.50 = 0.60
        uint256 rate = model.getBorrowRate(1000e18, 900e18);
        assertEq(rate, 0.60e27, "At 90% util, rate should jump to 60%");
    }

    function test_BorrowRate_Full_100Percent() public view {
        // At 100% utilization: rate = 0.02 + 0.08 + 1.00 × (0.20/0.20) = 0.10 + 1.00 = 1.10
        uint256 rate = model.getBorrowRate(1000e18, 1000e18);
        assertEq(rate, 1.10e27, "At 100% util, rate should be 110%");
    }

    function test_BorrowRate_EmptyPool() public view {
        // No deposits, no borrows → 0 utilization → base rate
        uint256 rate = model.getBorrowRate(0, 0);
        assertEq(rate, BASE_RATE, "Empty pool should return base rate");
    }

    // =========================================================
    //  Supply Rate
    // =========================================================

    function test_SupplyRate_WithReserveFactor() public view {
        // At 80% util: borrowRate = 10%, reserveFactor = 15%
        // supplyRate = 0.10 × 0.80 × (1 - 0.15) = 0.10 × 0.80 × 0.85 = 0.068 (6.8%)
        uint256 rate = model.getSupplyRate(1000e18, 800e18, 0.15e27);
        assertEq(rate, 0.068e27, "Supply rate at 80% util with 15% reserve factor should be 6.8%");
    }

    function test_SupplyRate_ZeroReserveFactor() public view {
        // No protocol cut: supplyRate = borrowRate × utilization
        // At 80% util: 0.10 × 0.80 = 0.08 (8%)
        uint256 rate = model.getSupplyRate(1000e18, 800e18, 0);
        assertEq(rate, 0.08e27, "Supply rate with 0% reserve factor should be borrowRate * util");
    }

    function test_SupplyRate_AlwaysLessThanBorrowRate() public view {
        // Supply rate must always be ≤ borrow rate (protocol takes a cut + spread across all deposits)
        uint256 borrowRate = model.getBorrowRate(1000e18, 800e18);
        uint256 supplyRate = model.getSupplyRate(1000e18, 800e18, 0.10e27);
        assertLt(supplyRate, borrowRate, "Supply rate should always be less than borrow rate");
    }

    // =========================================================
    //  Compound Interest (Taylor Approximation)
    // =========================================================

    function test_CompoundInterest_ZeroTime() public view {
        // No time elapsed → multiplier = RAY (no interest)
        uint256 multiplier = model.calculateCompoundInterest(3e18, 0);
        assertEq(multiplier, RAY, "Zero time should return RAY (no interest)");
    }

    function test_CompoundInterest_OneSecond() public view {
        // After 1 second at rate r: ≈ RAY + r (Taylor term1 dominates)
        uint256 rate = 3170979198e9; // ~10% APR per second (in RAY: 3.17e18)
        uint256 multiplier = model.calculateCompoundInterest(rate, 1);

        // After 1 second, should be very close to RAY + rate
        // Term2 and term3 are ~0 for 1 second (expMinusOne=0)
        assertEq(multiplier, RAY + rate, "After 1 second, compound ~= simple (RAY + rate)");
    }

    function test_CompoundInterest_GreaterThanSimple() public view {
        // Over longer periods, compound interest > simple interest
        // Simple: RAY + rate × time
        // Compound: RAY + rate×time + rate²×time×(time-1)/2 + ...
        uint256 rate = 3170979198e9; // ~10% APR per second (in RAY: 3.17e18)
        uint256 oneYear = 365.25 days;

        uint256 compound = model.calculateCompoundInterest(rate, oneYear);
        uint256 simple = RAY + rate * oneYear;

        assertGt(
            compound,
            simple,
            "Compound interest should exceed simple interest over a year"
        );
    }

    function test_CompoundInterest_ReasonableOneYear() public view {
        // At 10% APR compounded continuously: e^0.10 ≈ 1.10517
        // Our 3-term Taylor should be close
        uint256 rate = 3170979198e9; // ~10% APR per second (in RAY: 3.17e18)
        uint256 oneYear = 365.25 days;

        uint256 multiplier = model.calculateCompoundInterest(rate, oneYear);

        // Should be approximately 1.105e27 (within 0.01% tolerance)
        assertApproxEqRel(
            multiplier,
            1.10517e27,
            1e24, // 0.1% tolerance (accounts for Taylor approximation error)
            "10% APR compounded over 1 year should be ~1.10517"
        );
    }
}

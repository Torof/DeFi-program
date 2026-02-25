// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimpleJug exercise.
//  Implement SimpleJug.sol to make these tests pass.
//
//  NOTE: rpow tests work independently. drip tests require a working
//        SimpleVat (Exercise 1) — implement SimpleVat first.
// ============================================================================

import "forge-std/Test.sol";

import {SimpleVat} from "../../../../src/part2/module6/exercise1-simple-vat/SimpleVat.sol";
import {SimpleJug} from "../../../../src/part2/module6/exercise2-simple-jug/SimpleJug.sol";

/// @dev Test harness that exposes SimpleJug's internal rpow for direct testing.
///      This is a common Foundry pattern: inherit the contract, add a public
///      wrapper around the internal function, deploy the harness in tests.
contract SimpleJugHarness is SimpleJug {
    constructor(address vat_, address vow_) SimpleJug(vat_, vow_) {}

    function rpow_exposed(uint256 x, uint256 n, uint256 b) external pure returns (uint256) {
        return rpow(x, n, b);
    }
}

contract SimpleJugTest is Test {
    SimpleVat vat;
    SimpleJugHarness jug;

    address alice = makeAddr("alice");
    address vow = makeAddr("vow");

    bytes32 constant ILK_ETH = "ETH-A";

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    // ETH price: $2,000, LR: 150% → spot = 2000/1.5 = 1333.33 (RAY)
    uint256 constant SPOT = 1_333_333_333_333_333_333_333_333_333_333;
    uint256 constant CEILING = 1_000_000 * RAD;

    /// @dev Per-second rate for ~5% annual stability fee.
    ///      1.05^(1/31,557,600) ≈ 1.000000001547125957863212448
    uint256 constant DUTY_5PCT = 1_000_000_001_547_125_957_863_212_448;

    /// @dev Seconds in a year (365.25 days).
    uint256 constant YEAR = 31_557_600;

    function setUp() public {
        // --- Deploy and configure Vat ---
        // (Uses only pre-built Vat functions — no frob/fold/grab needed here)
        vat = new SimpleVat();
        vat.init(ILK_ETH);
        vat.file(ILK_ETH, "spot", SPOT);
        vat.file(ILK_ETH, "line", CEILING);
        vat.file(ILK_ETH, "dust", 0); // no dust for Jug tests
        vat.file("Line", CEILING);

        // --- Deploy Jug (harness for rpow testing) ---
        jug = new SimpleJugHarness(address(vat), vow);
        vat.rely(address(jug));
        jug.init(ILK_ETH);
        jug.file(ILK_ETH, "duty", DUTY_5PCT);
    }

    /// @dev Open a vault for drip tests. Requires working Vat (Exercise 1).
    function _openVault() internal {
        vat.slip(ILK_ETH, alice, int256(10 ether));
        vm.prank(alice);
        vat.frob(ILK_ETH, int256(10 ether), int256(10_000 * WAD));
    }

    // =========================================================
    //  rpow — Exponentiation by Squaring
    //  (These tests work with ONLY rpow implemented — no Vat needed)
    // =========================================================

    function test_Rpow_ZeroToZero() public view {
        // 0^0 = 1.0 (base)
        assertEq(jug.rpow_exposed(0, 0, RAY), RAY, "0^0 should equal base (1.0 RAY)");
    }

    function test_Rpow_ZeroToPositive() public view {
        // 0^5 = 0
        assertEq(jug.rpow_exposed(0, 5, RAY), 0, "0^n should be 0 for n > 0");
    }

    function test_Rpow_AnyToZero() public view {
        // x^0 = 1.0 (base) for any x
        assertEq(jug.rpow_exposed(5 * RAY, 0, RAY), RAY, "x^0 should equal base (1.0 RAY)");
        assertEq(jug.rpow_exposed(DUTY_5PCT, 0, RAY), RAY, "duty^0 should equal base");
    }

    function test_Rpow_ExactPower() public view {
        // (2 RAY)^10 = 1024 RAY (exact — no rounding needed)
        uint256 result = jug.rpow_exposed(2 * RAY, 10, RAY);
        assertEq(result, 1024 * RAY, "(2 RAY)^10 should be exactly 1024 RAY");
    }

    function test_Rpow_IdentityBase() public view {
        // (1 RAY)^n = 1 RAY for any n (1.0 raised to any power = 1.0)
        assertEq(jug.rpow_exposed(RAY, 1_000_000, RAY), RAY, "1.0^n should always equal 1.0 RAY");
    }

    function test_Rpow_RealisticAnnualRate() public view {
        // duty^(1 year in seconds) ≈ 1.05 RAY (5% annual)
        uint256 result = jug.rpow_exposed(DUTY_5PCT, YEAR, RAY);
        uint256 expected = 1_050_000_000_000_000_000_000_000_000; // 1.05 RAY

        // Allow 0.01% tolerance for fixed-point truncation across ~25 iterations
        assertApproxEqRel(
            result,
            expected,
            1e14, // 0.01%
            "duty^year should be approximately 1.05 RAY (5% annual)"
        );
    }

    // =========================================================
    //  drip — Stability Fee Compounding
    //  (These tests require a working SimpleVat — Exercise 1)
    // =========================================================

    function test_Drip_UpdatesRateAndGeneratesDai() public {
        _openVault();

        // Warp 1 year forward
        vm.warp(block.timestamp + YEAR);

        uint256 debtBefore = vat.debt();

        // Call drip — should compound 1 year of 5% stability fee
        uint256 returnedRate = jug.drip(ILK_ETH);

        // Rate should be approximately 1.05 RAY
        (, uint256 newRate,,,) = vat.ilks(ILK_ETH);
        assertApproxEqRel(
            newRate,
            1_050_000_000_000_000_000_000_000_000,
            1e14,
            "Rate should be ~1.05 RAY after 1 year of 5% fee"
        );

        // Return value should match the Vat's new rate
        assertEq(returnedRate, newRate, "drip() should return the new rate");

        // Vow should receive ~500 DAI of stability fee revenue
        // drad = Art × drate = 10,000 WAD × 0.05 RAY ≈ 500 RAD
        assertApproxEqRel(
            vat.dai(vow),
            500 * RAD,
            1e14,
            "Vow should receive ~500 DAI of stability fees"
        );

        // Total debt should increase by the fee amount
        assertApproxEqRel(
            vat.debt(),
            debtBefore + 500 * RAD,
            1e14,
            "Total debt should increase by ~500 RAD"
        );

        // rho should be updated
        (, uint256 rho) = jug.ilks(ILK_ETH);
        assertEq(rho, block.timestamp, "rho should be updated to current timestamp");
    }

    function test_Drip_NoOpWhenNoTimeElapsed() public {
        _openVault();

        // Call drip immediately (0 seconds elapsed since init)
        (, uint256 rateBefore,,,) = vat.ilks(ILK_ETH);
        uint256 daiBefore = vat.dai(vow);

        uint256 returnedRate = jug.drip(ILK_ETH);

        (, uint256 rateAfter,,,) = vat.ilks(ILK_ETH);
        assertEq(rateAfter, rateBefore, "Rate should not change when no time elapsed");
        assertEq(vat.dai(vow), daiBefore, "No dai should be generated when no time elapsed");
        assertEq(returnedRate, rateBefore, "Returned rate should equal unchanged rate");
    }

    function test_Drip_ConsecutiveCallsCompound() public {
        _openVault();

        uint256 halfYear = YEAR / 2;

        // --- First drip: 6 months ---
        vm.warp(block.timestamp + halfYear);
        jug.drip(ILK_ETH);

        (, uint256 rateAfterFirst,,,) = vat.ilks(ILK_ETH);
        assertGt(rateAfterFirst, RAY, "Rate should increase after first drip");
        assertLt(rateAfterFirst, 1_050_000_000_000_000_000_000_000_000, "Rate should be less than 1.05 after only 6 months");

        uint256 daiAfterFirst = vat.dai(vow);
        assertGt(daiAfterFirst, 0, "Some dai should be generated after first drip");

        // --- Second drip: another 6 months ---
        vm.warp(block.timestamp + halfYear);
        jug.drip(ILK_ETH);

        (, uint256 rateAfterSecond,,,) = vat.ilks(ILK_ETH);
        assertGt(rateAfterSecond, rateAfterFirst, "Rate should increase further after second drip");

        // Total after 1 year (two 6-month compounds) ≈ 1.05 RAY
        assertApproxEqRel(
            rateAfterSecond,
            1_050_000_000_000_000_000_000_000_000,
            1e14,
            "Two half-year drips should compound to ~1.05 RAY"
        );

        // Total dai to vow ≈ 500 RAD (same as single 1-year drip)
        assertApproxEqRel(
            vat.dai(vow),
            500 * RAD,
            1e14,
            "Total stability fees should be ~500 DAI after full year"
        );
    }
}

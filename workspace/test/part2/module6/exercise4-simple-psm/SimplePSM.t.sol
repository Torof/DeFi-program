// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimplePSM exercise.
//  Implement SimplePSM.sol to make these tests pass.
//
//  NOTE: This exercise is independent — no SimpleVat dependency required.
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module6/mocks/MockERC20.sol";
import {SimpleStablecoin} from "../../../../src/part2/module6/shared/SimpleStablecoin.sol";
import {SimplePSM} from "../../../../src/part2/module6/exercise4-simple-psm/SimplePSM.sol";

contract SimplePSMTest is Test {
    MockERC20 usdc;
    SimpleStablecoin dai;
    SimplePSM psm;

    address alice = makeAddr("alice");
    address vow = makeAddr("vow");

    uint256 constant WAD = 10 ** 18;

    /// @dev 1% fee for clean integer math. 1000 USDC × 1% = 10 DAI fee.
    uint256 constant TIN = 10_000_000_000_000_000;   // 0.01 WAD = 1%
    uint256 constant TOUT = 10_000_000_000_000_000;  // 0.01 WAD = 1%

    function setUp() public {
        // --- Deploy tokens ---
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new SimpleStablecoin("Simple DAI", "sDAI");

        // --- Deploy PSM (USDC has 6 decimals) ---
        psm = new SimplePSM(address(usdc), address(dai), vow, 6);

        // --- Authorize PSM to mint/burn stablecoin ---
        dai.rely(address(psm));

        // --- Configure fees ---
        psm.file("tin", TIN);
        psm.file("tout", TOUT);
    }

    // =========================================================
    //  sellGem — Deposit USDC, receive stablecoin
    // =========================================================

    function test_SellGem_SwapsWithFee() public {
        // Give Alice 1000 USDC and approve PSM
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(address(psm), 1000e6);

        // Alice sells 1000 USDC
        vm.prank(alice);
        psm.sellGem(alice, 1000e6);

        // --- Alice receives 990 DAI (1000 - 1% fee) ---
        assertEq(
            dai.balanceOf(alice),
            990 * WAD,
            "Alice should receive 990 DAI (1000 minus 1% fee)"
        );

        // --- Vow receives 10 DAI fee revenue ---
        assertEq(
            dai.balanceOf(vow),
            10 * WAD,
            "Vow should receive 10 DAI as fee revenue"
        );

        // --- PSM holds 1000 USDC as reserves ---
        assertEq(
            usdc.balanceOf(address(psm)),
            1000e6,
            "PSM should hold 1000 USDC as reserves"
        );

        // --- Alice has no remaining USDC ---
        assertEq(
            usdc.balanceOf(alice),
            0,
            "Alice should have 0 USDC remaining"
        );
    }

    function test_SellGem_ZeroFeeIsOneToOne() public {
        // Set tin to 0 — pure 1:1 swap
        psm.file("tin", 0);

        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(address(psm), 1000e6);

        vm.prank(alice);
        psm.sellGem(alice, 1000e6);

        // --- Exact 1:1 — no fee ---
        assertEq(
            dai.balanceOf(alice),
            1000 * WAD,
            "Alice should receive exactly 1000 DAI (no fee)"
        );
        assertEq(
            dai.balanceOf(vow),
            0,
            "Vow should receive 0 DAI when fee is 0"
        );
    }

    // =========================================================
    //  buyGem — Pay stablecoin, receive USDC
    // =========================================================

    function test_BuyGem_SwapsWithFee() public {
        // Setup: PSM holds 1000 USDC reserves, Alice has 1010 DAI
        usdc.mint(address(psm), 1000e6);
        dai.mint(alice, 1010 * WAD);

        // Alice buys 1000 USDC
        vm.prank(alice);
        psm.buyGem(alice, 1000e6);

        // --- Alice paid 1010 DAI (1000 base + 10 fee) ---
        assertEq(
            dai.balanceOf(alice),
            0,
            "Alice should have 0 DAI remaining (paid 1010)"
        );

        // --- Alice received 1000 USDC ---
        assertEq(
            usdc.balanceOf(alice),
            1000e6,
            "Alice should receive 1000 USDC"
        );

        // --- Vow receives 10 DAI fee revenue ---
        assertEq(
            dai.balanceOf(vow),
            10 * WAD,
            "Vow should receive 10 DAI as fee revenue"
        );

        // --- PSM has 0 USDC remaining ---
        assertEq(
            usdc.balanceOf(address(psm)),
            0,
            "PSM should have 0 USDC remaining"
        );
    }

    function test_BuyGem_ZeroFeeIsOneToOne() public {
        // Set tout to 0 — pure 1:1 swap
        psm.file("tout", 0);

        usdc.mint(address(psm), 1000e6);
        dai.mint(alice, 1000 * WAD);

        vm.prank(alice);
        psm.buyGem(alice, 1000e6);

        // --- Exact 1:1 — no fee ---
        assertEq(
            dai.balanceOf(alice),
            0,
            "Alice should have 0 DAI remaining (paid exactly 1000)"
        );
        assertEq(
            usdc.balanceOf(alice),
            1000e6,
            "Alice should receive 1000 USDC"
        );
        assertEq(
            dai.balanceOf(vow),
            0,
            "Vow should receive 0 DAI when fee is 0"
        );
    }

    // =========================================================
    //  Decimal conversion — 6 → 18
    // =========================================================

    function test_SellGem_DecimalConversion() public {
        // Set tin to 0 for clean 1:1 test
        psm.file("tin", 0);

        // 1 USDC = 1e6 (6 decimals) should produce 1 DAI = 1e18 (18 decimals)
        usdc.mint(alice, 1e6);
        vm.prank(alice);
        usdc.approve(address(psm), 1e6);

        vm.prank(alice);
        psm.sellGem(alice, 1e6);

        assertEq(
            dai.balanceOf(alice),
            1e18,
            "1 USDC (1e6) should produce exactly 1 DAI (1e18)"
        );
    }
}

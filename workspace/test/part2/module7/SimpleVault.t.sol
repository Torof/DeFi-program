// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimpleVault exercise.
//  Implement SimpleVault.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../src/part2/module7/mocks/MockERC20.sol";
import {SimpleVault} from "../../../src/part2/module7/SimpleVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleVaultTest is Test {
    MockERC20 token;
    SimpleVault vault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK", 18);
        vault = new SimpleVault(IERC20(address(token)), "Vault Token", "vMTK");
    }

    // =========================================================
    //  deposit — First depositor gets 1:1 ratio
    // =========================================================

    function test_Deposit_FirstDeposit() public {
        // Alice is the first depositor — empty vault means 1:1 ratio
        token.mint(alice, 1000e18);
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, alice);
        vm.stopPrank();

        // --- 1:1 ratio on first deposit ---
        assertEq(shares, 1000e18, "First deposit should mint shares 1:1");
        assertEq(vault.balanceOf(alice), 1000e18, "Alice should hold 1000 shares");
        assertEq(vault.totalAssets(), 1000e18, "Vault should hold 1000 assets");
        assertEq(vault.totalSupply(), 1000e18, "Total supply should be 1000 shares");
    }

    // =========================================================
    //  deposit — After yield, new deposit gets fewer shares
    // =========================================================

    function test_Deposit_AfterYield() public {
        // Setup: Alice and Bob deposit, then yield accrues
        _setupMultiUser();

        // State: totalAssets = 3300e18, totalSupply = 3000e18, rate = 1.1
        // Carol deposits 1100 assets:
        //   shares = 1100 × 3000 / 3300 = 1000 (exact)
        token.mint(carol, 1100e18);
        vm.startPrank(carol);
        token.approve(address(vault), 1100e18);
        uint256 shares = vault.deposit(1100e18, carol);
        vm.stopPrank();

        assertEq(shares, 1000e18, "Carol should receive 1000 shares at rate 1.1");
        assertEq(vault.balanceOf(carol), 1000e18, "Carol should hold 1000 shares");
        assertEq(vault.totalAssets(), 4400e18, "Vault should hold 4400 assets total");
        assertEq(vault.totalSupply(), 4000e18, "Total supply should be 4000 shares");
    }

    // =========================================================
    //  mint — Specify shares, pay correct assets
    // =========================================================

    function test_Mint_PullsCorrectAssets() public {
        // Setup: rate = 1.1
        _setupMultiUser();

        // Carol mints 1000 shares at rate 1.1:
        //   assets = 1000 × 3300 / 3000 = 1100 (Ceil, exact here)
        token.mint(carol, 1100e18);
        vm.startPrank(carol);
        token.approve(address(vault), 1100e18);
        uint256 assets = vault.mint(1000e18, carol);
        vm.stopPrank();

        assertEq(assets, 1100e18, "Minting 1000 shares should cost 1100 assets at rate 1.1");
        assertEq(vault.balanceOf(carol), 1000e18, "Carol should hold 1000 shares");
        assertEq(token.balanceOf(carol), 0, "Carol should have 0 tokens remaining");
    }

    // =========================================================
    //  withdraw — Specify assets, burn correct shares
    // =========================================================

    function test_Withdraw_BurnsCorrectShares() public {
        // Setup: rate = 1.1, Alice has 1000 shares
        _setupMultiUser();

        // Alice withdraws 1100 assets (her full value):
        //   shares = 1100 × 3000 / 3300 = 1000 (Ceil, exact here)
        vm.prank(alice);
        uint256 shares = vault.withdraw(1100e18, alice, alice);

        assertEq(shares, 1000e18, "Withdrawing 1100 assets should burn 1000 shares");
        assertEq(vault.balanceOf(alice), 0, "Alice should have 0 shares remaining");
        assertEq(token.balanceOf(alice), 1100e18, "Alice should receive 1100 assets");
    }

    // =========================================================
    //  redeem — Redeem shares, receive assets including yield
    // =========================================================

    function test_Redeem_WithProfit() public {
        // Setup: rate = 1.1, Alice has 1000 shares
        _setupMultiUser();

        // Alice redeems all 1000 shares:
        //   assets = 1000 × 3300 / 3000 = 1100 (Floor, exact here)
        vm.prank(alice);
        uint256 assets = vault.redeem(1000e18, alice, alice);

        assertEq(assets, 1100e18, "Redeeming 1000 shares should return 1100 assets (10% yield)");
        assertEq(vault.balanceOf(alice), 0, "Alice should have 0 shares after redeem");
        assertEq(token.balanceOf(alice), 1100e18, "Alice should receive 1100 assets");

        // Rate unchanged for remaining holders
        // Remaining: totalAssets = 2200, totalSupply = 2000, rate = 1.1
        assertEq(vault.totalAssets(), 2200e18, "Remaining assets should be 2200");
        assertEq(vault.totalSupply(), 2000e18, "Remaining supply should be 2000");
    }

    // =========================================================
    //  Rounding — Always favors the vault
    // =========================================================

    function test_Rounding_FavorsVault() public {
        // Create a rate where division doesn't divide evenly.
        // Rate = 3:1 (totalAssets = 3 × totalSupply)
        token.mint(alice, 1e18);
        vm.startPrank(alice);
        token.approve(address(vault), 1e18);
        vault.deposit(1e18, alice);
        vm.stopPrank();

        // Donate 2e18 → totalAssets = 3e18, totalSupply = 1e18
        token.mint(address(vault), 2e18);

        // At rate 3:1, converting 1e18 assets to shares:
        //   exact = 1e18 × 1e18 / 3e18 = 0.333...e18
        //   Floor = 333333333333333333
        //   Ceil  = 333333333333333334
        uint256 depositShares = vault.previewDeposit(1e18);
        uint256 withdrawShares = vault.previewWithdraw(1e18);

        // deposit rounds DOWN — user gets fewer shares
        assertEq(
            depositShares,
            333333333333333333,
            "previewDeposit should round DOWN (Floor)"
        );

        // withdraw rounds UP — user burns more shares
        assertEq(
            withdrawShares,
            333333333333333334,
            "previewWithdraw should round UP (Ceil)"
        );

        // The vault always wins: withdraw costs more shares than deposit gives
        assertGt(
            withdrawShares,
            depositShares,
            "Withdraw should burn more shares than deposit mints (vault-favorable)"
        );
    }

    // =========================================================
    //  Multi-user full cycle — curriculum walkthrough
    // =========================================================

    function test_MultiUser_FullCycle() public {
        // Reproduces the Module 7 curriculum walkthrough exactly.

        // ── Step 1: Alice deposits 1000 ──
        token.mint(alice, 1000e18);
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1000e18, "Step 1: totalAssets = 1000");
        assertEq(vault.totalSupply(), 1000e18, "Step 1: totalSupply = 1000");
        assertEq(vault.balanceOf(alice), 1000e18, "Step 1: Alice holds 1000 shares");

        // ── Step 2: Bob deposits 2000 ──
        token.mint(bob, 2000e18);
        vm.startPrank(bob);
        token.approve(address(vault), 2000e18);
        vault.deposit(2000e18, bob);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 3000e18, "Step 2: totalAssets = 3000");
        assertEq(vault.totalSupply(), 3000e18, "Step 2: totalSupply = 3000");
        assertEq(vault.balanceOf(bob), 2000e18, "Step 2: Bob holds 2000 shares");

        // ── Step 3: Vault earns 300 yield (simulated via donation) ──
        token.mint(address(vault), 300e18);

        assertEq(vault.totalAssets(), 3300e18, "Step 3: totalAssets = 3300 (after yield)");
        assertEq(vault.totalSupply(), 3000e18, "Step 3: totalSupply unchanged at 3000");

        // Verify each user's value at rate 1.1:
        //   Alice: 1000 shares × 1.1 = 1100 assets
        //   Bob:   2000 shares × 1.1 = 2200 assets
        assertEq(vault.convertToAssets(1000e18), 1100e18, "Step 3: 1000 shares = 1100 assets");
        assertEq(vault.convertToAssets(2000e18), 2200e18, "Step 3: 2000 shares = 2200 assets");

        // ── Step 4: Carol deposits 1100 (buys in at rate 1.1) ──
        token.mint(carol, 1100e18);
        vm.startPrank(carol);
        token.approve(address(vault), 1100e18);
        uint256 carolShares = vault.deposit(1100e18, carol);
        vm.stopPrank();

        assertEq(carolShares, 1000e18, "Step 4: Carol gets 1000 shares for 1100 assets");
        assertEq(vault.totalAssets(), 4400e18, "Step 4: totalAssets = 4400");
        assertEq(vault.totalSupply(), 4000e18, "Step 4: totalSupply = 4000");

        // ── Step 5: Alice redeems all shares ──
        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(1000e18, alice, alice);

        assertEq(aliceAssets, 1100e18, "Step 5: Alice gets 1100 (deposited 1000, earned 100)");
        assertEq(vault.totalAssets(), 3300e18, "Step 5: totalAssets = 3300");
        assertEq(vault.totalSupply(), 3000e18, "Step 5: totalSupply = 3000");

        // Rate unchanged for remaining holders
        assertEq(
            vault.convertToAssets(2000e18),
            2200e18,
            "Step 5: Bob's 2000 shares still worth 2200 (rate unchanged)"
        );
        assertEq(
            vault.convertToAssets(1000e18),
            1100e18,
            "Step 5: Carol's 1000 shares still worth 1100 (rate unchanged)"
        );
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Sets up the multi-user state from the curriculum walkthrough:
    ///      Alice deposits 1000, Bob deposits 2000, 300 yield accrues.
    ///      State: totalAssets = 3300e18, totalSupply = 3000e18, rate = 1.1
    function _setupMultiUser() internal {
        // Alice deposits 1000
        token.mint(alice, 1000e18);
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        // Bob deposits 2000
        token.mint(bob, 2000e18);
        vm.startPrank(bob);
        token.approve(address(vault), 2000e18);
        vault.deposit(2000e18, bob);
        vm.stopPrank();

        // Simulate 300 yield
        token.mint(address(vault), 300e18);
    }
}

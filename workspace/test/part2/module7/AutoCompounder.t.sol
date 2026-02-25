// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the AutoCompounder
//  exercise. Implement AutoCompounder.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../src/part2/module7/mocks/MockERC20.sol";
import {MockSwap} from "../../../src/part2/module7/MockSwap.sol";
import {AutoCompounder} from "../../../src/part2/module7/AutoCompounder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AutoCompounderTest is Test {
    MockERC20 usdc;
    MockERC20 reward;
    MockSwap swapRouter;
    AutoCompounder vault;

    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    uint256 constant UNLOCK_TIME = 21_600; // 6 hours in seconds

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 18);
        reward = new MockERC20("Reward Token", "RWD", 18);
        swapRouter = new MockSwap();

        vault = new AutoCompounder(
            IERC20(address(usdc)),
            IERC20(address(reward)),
            swapRouter,
            UNLOCK_TIME,
            "Auto Compounder",
            "acUSDC"
        );

        // Fund Alice
        usdc.mint(alice, 10_000e18);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // =========================================================
    //  Deposit — Standard 1:1 first deposit
    // =========================================================

    function test_Deposit_FirstDeposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10_000e18, alice);

        assertEq(shares, 10_000e18, "First deposit should mint shares 1:1");
        assertEq(vault.balanceOf(alice), 10_000e18, "Alice should hold 10,000 shares");
        assertEq(vault.totalAssets(), 10_000e18, "totalAssets should be 10,000");
    }

    // =========================================================
    //  Harvest — Profit locked immediately (totalAssets unchanged)
    // =========================================================

    function test_Harvest_ProfitLockedImmediately() public {
        _depositAlice();
        _setupHarvest(600e18);

        // --- Before harvest ---
        assertEq(vault.totalAssets(), 10_000e18, "totalAssets before harvest = 10,000");

        // --- Harvest: swap 600 REWARD → 600 USDC ---
        vault.harvest();

        // Actual balance increased (tokens received from swap)
        assertEq(
            usdc.balanceOf(address(vault)),
            10_600e18,
            "Vault balance should be 10,600 after harvest"
        );

        // But totalAssets is UNCHANGED — profit is fully locked
        assertEq(
            vault.totalAssets(),
            10_000e18,
            "totalAssets should be unchanged (profit locked)"
        );

        // Share price unchanged — sandwich attacker gets nothing
        assertEq(
            vault.lockedProfitAtHarvest(),
            600e18,
            "lockedProfitAtHarvest should be 600"
        );
    }

    // =========================================================
    //  Profit unlocks linearly — 50% at halfway point
    // =========================================================

    function test_ProfitUnlocks_Linearly() public {
        _depositAlice();
        _setupHarvest(600e18);
        vault.harvest();

        // --- Warp 3 hours (50% of unlock period) ---
        vm.warp(block.timestamp + UNLOCK_TIME / 2);

        // 50% of 600 unlocked → 300 still locked
        // totalAssets = 10,600 - 300 = 10,300
        assertEq(
            vault.totalAssets(),
            10_300e18,
            "totalAssets at 50% unlock = 10,300"
        );
    }

    // =========================================================
    //  Profit fully unlocked — share price reflects all yield
    // =========================================================

    function test_ProfitFullyUnlocked() public {
        _depositAlice();
        _setupHarvest(600e18);
        vault.harvest();

        // --- Warp 6 hours (full unlock period) ---
        vm.warp(block.timestamp + UNLOCK_TIME);

        // All profit unlocked → totalAssets = full balance
        assertEq(
            vault.totalAssets(),
            10_600e18,
            "totalAssets after full unlock = 10,600"
        );

        // Alice's shares are now worth more: rate = 10,600 / 10,000 = 1.06
        vm.prank(alice);
        uint256 assets = vault.redeem(10_000e18, alice, alice);

        assertEq(
            assets,
            10_600e18,
            "Alice should get 10,600 (original 10,000 + 600 yield)"
        );
    }

    // =========================================================
    //  Sandwich attack is unprofitable with profit unlocking
    // =========================================================

    function test_Sandwich_Unprofitable() public {
        _depositAlice();

        // --- Attacker front-runs: deposits 10,000 ---
        usdc.mint(attacker, 10_000e18);
        vm.startPrank(attacker);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e18, attacker);
        vm.stopPrank();

        // State: balance=20,000, supply=20,000, rate=1.0
        assertEq(vault.totalAssets(), 20_000e18, "totalAssets = 20,000 with both depositors");

        // --- Harvest executes (600 REWARD → 600 USDC) ---
        _setupHarvest(600e18);
        vault.harvest();

        // Profit locked → totalAssets unchanged at 20,000, rate still 1.0
        assertEq(
            vault.totalAssets(),
            20_000e18,
            "totalAssets unchanged after harvest (profit locked)"
        );

        // --- Attacker back-runs: redeems immediately ---
        vm.prank(attacker);
        uint256 attackerReceived = vault.redeem(10_000e18, attacker, attacker);

        // Attacker gets exactly what they deposited — ZERO profit
        assertEq(
            attackerReceived,
            10_000e18,
            "Attacker should receive exactly 10,000 (no profit from sandwich)"
        );

        // --- After 6 hours, Alice gets ALL the yield ---
        vm.warp(block.timestamp + UNLOCK_TIME);

        // Remaining: balance=10,600, supply=10,000
        assertEq(
            vault.totalAssets(),
            10_600e18,
            "After unlock, remaining totalAssets = 10,600 (all yield to Alice)"
        );

        vm.prank(alice);
        uint256 aliceReceived = vault.redeem(10_000e18, alice, alice);

        assertEq(
            aliceReceived,
            10_600e18,
            "Alice should get 10,600 (all 600 yield went to her)"
        );
    }

    // =========================================================
    //  Consecutive harvests — remaining locked profit carries over
    // =========================================================

    function test_ConsecutiveHarvests() public {
        _depositAlice();

        // --- Harvest #1 at T=0: 600 REWARD ---
        _setupHarvest(600e18);
        vault.harvest();

        assertEq(vault.totalAssets(), 10_000e18, "After harvest 1: totalAssets = 10,000");

        // --- Warp 3 hours (50% of unlock) ---
        vm.warp(block.timestamp + UNLOCK_TIME / 2);

        // 300 unlocked, 300 still locked
        assertEq(vault.totalAssets(), 10_300e18, "At 50% unlock: totalAssets = 10,300");

        // --- Harvest #2 at T=3h: 400 REWARD ---
        _setupHarvest(400e18);
        vault.harvest();

        // New locked = 400 (new) + 300 (remaining from harvest 1) = 700
        assertEq(
            vault.lockedProfitAtHarvest(),
            700e18,
            "lockedProfitAtHarvest should combine: 400 new + 300 remaining = 700"
        );

        // totalAssets unchanged at harvest moment:
        // balance = 10,000 + 600 + 400 = 11,000
        // locked = 700
        // totalAssets = 11,000 - 700 = 10,300
        assertEq(
            vault.totalAssets(),
            10_300e18,
            "totalAssets unchanged at harvest moment (10,300)"
        );

        // --- Warp 6 hours after harvest #2 (full unlock) ---
        vm.warp(block.timestamp + UNLOCK_TIME);

        // All profit unlocked
        assertEq(
            vault.totalAssets(),
            11_000e18,
            "After full unlock: totalAssets = 11,000 (all profit available)"
        );

        // Rate = 11,000 / 10,000 = 1.1
        vm.prank(alice);
        uint256 assets = vault.redeem(10_000e18, alice, alice);

        assertEq(
            assets,
            11_000e18,
            "Alice should get 11,000 (10,000 + 600 + 400 yield)"
        );
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Alice deposits 10,000 USDC into the vault.
    function _depositAlice() internal {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);
    }

    /// @dev Mint reward tokens to vault and fund swap router with USDC.
    ///      After calling this, vault.harvest() will swap rewards for USDC.
    function _setupHarvest(uint256 rewardAmount) internal {
        // Rewards accumulate in the vault (simulating earned rewards)
        reward.mint(address(vault), rewardAmount);
        // Fund swap router so it can pay out USDC
        usdc.mint(address(swapRouter), rewardAmount);
    }
}

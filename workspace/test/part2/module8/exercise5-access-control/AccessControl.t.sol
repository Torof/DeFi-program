// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE -- it is the test suite for the AccessControl
//  exercise. Implement AccessControlAttack.sol and DefendedVault.sol to make
//  the tests pass.
//
//  Test 1: Demonstrates re-initialization bug (no student code needed).
//  Test 2: Verifies AccessControlAttack drains the vault.
//  Test 3: Verifies DefendedVault blocks re-initialization.
//  Test 4: Verifies DefendedVault blocks unauthorized emergencyWithdraw.
//  Test 5: Verifies DefendedVault allows owner to call emergencyWithdraw.
//
//  Run:
//    forge test --match-path "test/part2/module8/exercise5*" -vvv
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module8/mocks/MockERC20.sol";
import {VulnerableVault} from "../../../../src/part2/module8/exercise5-access-control/VulnerableVault.sol";
import {DefendedVault} from "../../../../src/part2/module8/exercise5-access-control/DefendedVault.sol";
import {AccessControlAttack} from "../../../../src/part2/module8/exercise5-access-control/AccessControlAttack.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// =============================================
//  Part A: Vulnerable vault + exploit tests
// =============================================

contract AccessControlAttackTest is Test {
    MockERC20 token;
    VulnerableVault vault;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    uint256 constant DEPOSIT_AMOUNT = 10_000e18;

    function setUp() public {
        token = new MockERC20("Vault Token", "VTK", 18);

        // Vulnerable vault: deployed and initialized by deployer
        vault = new VulnerableVault();
        vault.initialize(IERC20(address(token)), deployer);

        // Alice deposits 10,000 tokens
        token.mint(alice, DEPOSIT_AMOUNT);
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // =========================================================
    //  Demonstrates re-initialization bug (no student code)
    // =========================================================

    function test_VulnerableVault_CanBeReinitialized() public {
        // Verify deployer is currently owner
        assertEq(
            vault.owner(),
            deployer,
            "Deployer should be owner after first initialize"
        );

        // Attacker re-initializes - no guard prevents this
        vm.prank(attacker);
        vault.initialize(IERC20(address(token)), attacker);

        // Attacker is now owner
        assertEq(
            vault.owner(),
            attacker,
            "Attacker should be owner after re-initialization"
        );
    }

    // =========================================================
    //  AccessControlAttack drains the vault
    // =========================================================

    function test_Attack_DrainsVulnerableVault() public {
        // Deploy attack contract
        vm.prank(attacker);
        AccessControlAttack attackContract = new AccessControlAttack(
            vault, IERC20(address(token))
        );

        // Vault holds Alice's 10,000 tokens
        assertEq(
            token.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "Vault should hold 10,000 tokens before attack"
        );

        // Execute attack
        vm.prank(attacker);
        attackContract.attack();

        // Attack contract drained all tokens
        assertEq(
            token.balanceOf(address(attackContract)),
            DEPOSIT_AMOUNT,
            "Attack contract should hold all 10,000 tokens after attack"
        );

        // Vault is empty
        assertEq(
            token.balanceOf(address(vault)),
            0,
            "Vault should be empty after attack"
        );

        // Alice's balance record still shows 10,000 but the tokens are gone
        assertEq(
            vault.balances(alice),
            DEPOSIT_AMOUNT,
            "Alice's balance record is unchanged (but tokens are gone)"
        );
    }
}

// =============================================
//  Part B: Defended vault tests
// =============================================

contract AccessControlDefenseTest is Test {
    MockERC20 token;
    DefendedVault vault;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    uint256 constant DEPOSIT_AMOUNT = 10_000e18;

    function setUp() public {
        token = new MockERC20("Vault Token", "VTK", 18);

        // Defended vault: deployed and initialized by deployer
        vault = new DefendedVault();
        vm.prank(deployer);
        vault.initialize(IERC20(address(token)), deployer);

        // If this fails, implement initialize() in DefendedVault.sol first
        assertEq(
            address(vault.token()),
            address(token),
            "DefendedVault.initialize() not implemented yet -- implement it first!"
        );

        // Alice deposits 10,000 tokens
        token.mint(alice, DEPOSIT_AMOUNT);
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // =========================================================
    //  DefendedVault blocks re-initialization
    // =========================================================

    function test_DefendedVault_BlocksReinitialize() public {
        // Verify deployer is owner
        assertEq(
            vault.owner(),
            deployer,
            "Deployer should be owner"
        );

        // Attacker tries to re-initialize
        vm.prank(attacker);
        vm.expectRevert("already initialized");
        vault.initialize(IERC20(address(token)), attacker);

        // Owner unchanged
        assertEq(
            vault.owner(),
            deployer,
            "Owner should still be deployer after failed re-initialization"
        );
    }

    // =========================================================
    //  DefendedVault blocks unauthorized emergencyWithdraw
    // =========================================================

    function test_DefendedVault_BlocksUnauthorizedEmergency() public {
        // Attacker tries to call emergencyWithdraw directly
        vm.prank(attacker);
        vm.expectRevert("not owner");
        vault.emergencyWithdraw();

        // Vault still holds tokens
        assertEq(
            token.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "Vault should still hold tokens after blocked emergency"
        );
    }

    // =========================================================
    //  DefendedVault allows owner to emergencyWithdraw
    // =========================================================

    function test_DefendedVault_OwnerCanEmergencyWithdraw() public {
        // Owner calls emergencyWithdraw
        vm.prank(deployer);
        vault.emergencyWithdraw();

        // Owner received all tokens
        assertEq(
            token.balanceOf(deployer),
            DEPOSIT_AMOUNT,
            "Owner should receive all tokens from emergency withdraw"
        );

        // Vault is empty
        assertEq(
            token.balanceOf(address(vault)),
            0,
            "Vault should be empty after owner emergency withdraw"
        );
    }
}

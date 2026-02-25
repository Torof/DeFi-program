// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the ReadOnlyReentrancy
//  exercise. Implement ReentrancyAttack.sol and DefendedLending.sol to make
//  the tests pass.
//
//  Test 1: Verifies getSharePrice() is inflated during callback (no student code).
//  Test 2: Uses ReentrancyAttack — student implements attack + callback.
//  Test 3: Uses DefendedLending — student adds reentrancy check.
//  Test 4: Verifies DefendedLending works normally (no callback involved).
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module8/mocks/MockERC20.sol";
import {VulnerableVault, IDepositCallback} from "../../../../src/part2/module8/exercise1-reentrancy/VulnerableVault.sol";
import {NaiveLending} from "../../../../src/part2/module8/exercise1-reentrancy/NaiveLending.sol";
import {DefendedLending} from "../../../../src/part2/module8/exercise1-reentrancy/DefendedLending.sol";
import {ReentrancyAttack} from "../../../../src/part2/module8/exercise1-reentrancy/ReentrancyAttack.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Helper that records getSharePrice() during a vault deposit callback.
///      Used by test 1 — no student code needed.
contract PriceRecorder is IDepositCallback {
    VulnerableVault public vault;
    uint256 public priceduringCallback;

    constructor(VulnerableVault vault_) {
        vault = vault_;
    }

    function onDeposit(address, uint256) external override {
        priceduringCallback = vault.getSharePrice();
    }
}

contract ReadOnlyReentrancyTest is Test {
    MockERC20 token;
    VulnerableVault vault;
    NaiveLending naiveLending;
    DefendedLending defendedLending;

    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK", 18);
        vault = new VulnerableVault(IERC20(address(token)), "Vault Token", "vMTK");

        naiveLending = new NaiveLending(vault, IERC20(address(token)));
        defendedLending = new DefendedLending(vault, IERC20(address(token)));

        // --- Establish vault state: 10,000 tokens / 10,000 shares (price = 1.0) ---
        token.mint(alice, 10_000e18);
        vm.startPrank(alice);
        token.approve(address(vault), 10_000e18);
        vault.deposit(10_000e18);
        vm.stopPrank();

        assertEq(vault.getSharePrice(), 1e18, "Initial share price should be 1.0");

        // --- Attacker deposits 1,000 to get vault shares ---
        token.mint(attacker, 1_000e18);
        vm.startPrank(attacker);
        token.approve(address(vault), 1_000e18);
        vault.deposit(1_000e18);
        vm.stopPrank();

        // Vault: 11,000 tokens, 11,000 shares, price = 1.0
        assertEq(vault.getSharePrice(), 1e18, "Price should still be 1.0 after attacker deposit");

        // --- Fund lending protocols so they can issue loans ---
        token.mint(address(naiveLending), 5_000e18);
        token.mint(address(defendedLending), 5_000e18);
    }

    // =========================================================
    //  getSharePrice is inflated during vault deposit callback
    // =========================================================

    function test_SharePrice_InflatedDuringCallback() public {
        // Use PriceRecorder helper (no student code) to capture price during callback
        PriceRecorder recorder = new PriceRecorder(vault);

        // Fund recorder with 11,000 tokens (to match vault's 11,000 supply)
        token.mint(address(recorder), 11_000e18);
        vm.startPrank(address(recorder));
        token.approve(address(vault), 11_000e18);

        // Deposit 11,000 with callback — during callback, balance = 22,000, supply = 11,000
        vault.deposit(11_000e18, address(recorder));
        vm.stopPrank();

        // --- During callback: price = 22,000 / 11,000 = 2.0 ---
        assertEq(
            recorder.priceduringCallback(),
            2e18,
            "Share price should be 2.0 during callback (inflated!)"
        );

        // --- After callback: price normalizes (shares minted) ---
        // Vault: 22,000 tokens, 22,000 shares
        assertEq(
            vault.getSharePrice(),
            1e18,
            "Share price should return to 1.0 after deposit completes"
        );
    }

    // =========================================================
    //  Attack on NaiveLending — attacker borrows 1,000 (vs fair 500)
    // =========================================================

    function test_Attack_NaiveLending_Succeeds() public {
        // Deploy attack contract targeting NaiveLending
        ReentrancyAttack attackContract = new ReentrancyAttack(vault, naiveLending, IERC20(address(token)));

        // Transfer attacker's 1,000 vault shares to attack contract
        vm.prank(attacker);
        IERC20(address(vault)).transfer(address(attackContract), 1_000e18);

        // Fund attack contract with 11,000 tokens for the manipulation deposit
        token.mint(address(attackContract), 11_000e18);

        // --- Execute attack ---
        attackContract.attack(11_000e18);

        // --- Attacker borrowed 1,000 (should only be able to borrow 500) ---
        assertEq(
            naiveLending.borrowed(address(attackContract)),
            1_000e18,
            "Attacker should have borrowed 1,000 (exploiting inflated price)"
        );

        // --- Collateral is only worth 1,000 at fair price, backing 1,000 debt ---
        // Under-collateralized! (100% vs required 200%)
        assertEq(
            naiveLending.collateral(address(attackContract)),
            1_000e18,
            "Attack contract deposited 1,000 shares as collateral"
        );

        // --- Fair borrow capacity was only 500 ---
        // Stolen: 1,000 - 500 = 500 tokens
        uint256 fairMaxBorrow = 1_000e18 * 1e18 / naiveLending.COLLATERAL_RATIO();
        assertEq(fairMaxBorrow, 500e18, "Fair max borrow should be 500");
        assertGt(
            naiveLending.borrowed(address(attackContract)),
            fairMaxBorrow,
            "Attacker borrowed more than fair max (attack succeeded)"
        );
    }

    // =========================================================
    //  Same attack on DefendedLending — REVERTS
    // =========================================================

    function test_Attack_DefendedLending_Reverts() public {
        // Deploy attack contract targeting DefendedLending (via NaiveLending interface)
        // We need a version that targets DefendedLending — use a helper
        DefendedAttack attackContract = new DefendedAttack(vault, defendedLending, IERC20(address(token)));

        // Transfer attacker's vault shares to attack contract
        // (Attacker already used their shares in the previous test? No — each test is independent)
        vm.prank(attacker);
        IERC20(address(vault)).transfer(address(attackContract), 1_000e18);

        // Fund attack contract
        token.mint(address(attackContract), 11_000e18);

        // --- Attack should revert ---
        vm.expectRevert();
        attackContract.attack(11_000e18);
    }

    // =========================================================
    //  DefendedLending works normally (no callback = not locked)
    // =========================================================

    function test_DefendedLending_NormalBorrow_Works() public {
        // Attacker deposits vault shares as collateral normally (no attack)
        vm.startPrank(attacker);
        IERC20(address(vault)).approve(address(defendedLending), 1_000e18);
        defendedLending.depositCollateral(1_000e18);

        // Borrow 500 at fair price — should succeed
        uint256 maxBorrow = 1_000e18 * 1e18 / defendedLending.COLLATERAL_RATIO();
        defendedLending.borrow(maxBorrow);
        vm.stopPrank();

        assertEq(
            defendedLending.borrowed(attacker),
            500e18,
            "Normal borrow of 500 should succeed on DefendedLending"
        );

        assertEq(
            token.balanceOf(attacker),
            500e18,
            "Attacker should have received 500 tokens"
        );
    }
}

// ── Helper: Attack contract targeting DefendedLending ────────────────────────
// Same logic as ReentrancyAttack but calls DefendedLending instead of NaiveLending.
// This is pre-built — the student doesn't implement this.

contract DefendedAttack is IDepositCallback {
    using SafeERC20 for IERC20;

    VulnerableVault public vault;
    DefendedLending public lending;
    IERC20 public token;
    uint256 public sharesToDeposit;

    constructor(VulnerableVault vault_, DefendedLending lending_, IERC20 token_) {
        vault = vault_;
        lending = lending_;
        token = token_;
    }

    function attack(uint256 amount) external {
        sharesToDeposit = IERC20(address(vault)).balanceOf(address(this));
        token.approve(address(vault), amount);
        IERC20(address(vault)).approve(address(lending), sharesToDeposit);
        vault.deposit(amount, address(this));
    }

    function onDeposit(address, uint256) external override {
        lending.depositCollateral(sharesToDeposit);
        uint256 price = vault.getSharePrice();
        uint256 collateralValue = sharesToDeposit * price / 1e18;
        uint256 maxBorrow = collateralValue * 1e18 / lending.COLLATERAL_RATIO();
        lending.borrow(maxBorrow);
    }
}

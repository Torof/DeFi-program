// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SimpleVault, ZeroAmount, InsufficientShares, InsufficientAssets} from "../../../../src/part1/module5/exercise1-simple-vault/SimpleVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Tests for SimpleVault with fuzz testing.
/// @dev DO NOT MODIFY THIS FILE. Fill in SimpleVault.sol instead.
contract SimpleVaultTest is Test {
    SimpleVault vault;
    MockToken token;

    address alice;
    address bob;

    function setUp() public {
        token = new MockToken();
        vault = new SimpleVault(IERC20(address(token)));

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Mint tokens to test users
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);
    }

    // =========================================================
    //  Basic Unit Tests
    // =========================================================

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(shares, depositAmount, "First deposit should be 1:1");
        assertEq(vault.balanceOf(alice), depositAmount, "Alice should have shares");
        assertEq(vault.totalSupply(), depositAmount, "Total supply should match");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should match");
    }

    function test_Withdraw() public {
        // Setup: Alice deposits
        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Withdraw half
        uint256 sharesToWithdraw = 500e18;
        uint256 assets = vault.withdraw(sharesToWithdraw);
        vm.stopPrank();

        assertEq(assets, 500e18, "Should withdraw half");
        assertEq(vault.balanceOf(alice), 500e18, "Alice should have remaining shares");
        assertEq(token.balanceOf(alice), 1_000_000e18 - 500e18, "Alice should receive assets");
    }

    function test_MultipleDepositors() public {
        // Alice deposits 1000
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18);
        vm.stopPrank();

        // Bob deposits 1000
        vm.startPrank(bob);
        token.approve(address(vault), 1000e18);
        vault.deposit(1000e18);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 2000e18, "Total assets should be 2000");
        assertEq(vault.totalSupply(), 2000e18, "Total supply should be 2000");
    }

    function test_DepositRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_WithdrawRevertInsufficientShares() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientShares.selector);
        vault.withdraw(1000e18);
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    /// @notice Fuzz test: deposit should always increase total supply.
    function testFuzz_DepositIncreasesTotalSupply(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        uint256 supplyBefore = vault.totalSupply();

        vm.startPrank(alice);
        token.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertGt(vault.totalSupply(), supplyBefore, "Supply should increase");
    }

    /// @notice Fuzz test: shares should match assets for first deposit.
    function testFuzz_FirstDepositIsOneToOne(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        vm.startPrank(alice);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount);
        vm.stopPrank();

        assertEq(shares, amount, "First deposit should be 1:1");
    }

    /// @notice Fuzz test: withdraw should never give more than deposited.
    function testFuzz_WithdrawNeverExceedsDeposit(uint256 depositAmount, uint256 withdrawShares) public {
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        withdrawShares = bound(withdrawShares, 1, depositAmount);

        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount);

        // Withdraw some shares
        uint256 assetsReceived = vault.withdraw(withdrawShares);
        vm.stopPrank();

        // Assets received should not exceed original deposit
        assertLe(assetsReceived, depositAmount, "Cannot withdraw more than deposited");
    }

    /// @notice Fuzz test: convertToShares and convertToAssets should be consistent.
    function testFuzz_ConversionConsistency(uint256 depositAmount, uint256 testAmount) public {
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        testAmount = bound(testAmount, 1, depositAmount);

        // Setup: make a deposit to establish exchange rate
        vm.startPrank(alice);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Test conversions
        uint256 shares = vault.convertToShares(testAmount);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Due to rounding, assetsBack might be slightly less than testAmount
        // but should be very close (within 1 wei per share)
        assertApproxEqAbs(assetsBack, testAmount, vault.totalSupply(), "Conversion should be consistent");
    }

    /// @notice Fuzz test: total assets should always equal token balance.
    function testFuzz_TotalAssetsMatchesBalance(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, 500_000e18);
        amount2 = bound(amount2, 1e18, 500_000e18);

        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(vault), amount1);
        vault.deposit(amount1);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        token.approve(address(vault), amount2);
        vault.deposit(amount2);
        vm.stopPrank();

        assertEq(vault.totalAssets(), token.balanceOf(address(vault)), "Total assets should match balance");
    }

    /// @notice Fuzz test: shares after second deposit should be proportional.
    function testFuzz_SecondDepositProportional(uint256 firstDeposit, uint256 secondDeposit) public {
        firstDeposit = bound(firstDeposit, 1e18, 500_000e18);
        secondDeposit = bound(secondDeposit, 1e18, 500_000e18);

        // Alice makes first deposit
        vm.startPrank(alice);
        token.approve(address(vault), firstDeposit);
        uint256 sharesAlice = vault.deposit(firstDeposit);
        vm.stopPrank();

        // Bob makes second deposit
        vm.startPrank(bob);
        token.approve(address(vault), secondDeposit);
        uint256 sharesBob = vault.deposit(secondDeposit);
        vm.stopPrank();

        // Ratio of shares should match ratio of deposits (with rounding tolerance)
        uint256 depositRatio = (secondDeposit * 1e18) / firstDeposit;
        uint256 sharesRatio = (sharesBob * 1e18) / sharesAlice;

        assertApproxEqRel(sharesRatio, depositRatio, 0.0001e18, "Share ratio should match deposit ratio");
    }
}

// =============================================================
//  Mock Token
// =============================================================
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DefensiveVault, ZeroDeposit, InsufficientBalance} from "../../../../src/part2/module1/exercise1-defensive-vault/DefensiveVault.sol";
import {MockERC20} from "../../../../src/part2/module1/mocks/MockERC20.sol";
import {FeeOnTransferToken} from "../../../../src/part2/module1/mocks/FeeOnTransferToken.sol";
import {NoReturnToken} from "../../../../src/part2/module1/mocks/NoReturnToken.sol";

/// @notice Tests for the DefensiveVault exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part2/module1/DefensiveVault.sol instead.
contract DefensiveVaultTest is Test {
    address alice;
    address bob;

    // =========================================================
    //  Standard ERC-20 Tests
    // =========================================================

    MockERC20 standardToken;
    DefensiveVault standardVault;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Standard token vault
        standardToken = new MockERC20("Standard", "STD", 18);
        standardVault = new DefensiveVault(address(standardToken));

        // Fund alice
        standardToken.mint(alice, 1000e18);
    }

    function test_StandardToken_Deposit() public {
        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 100e18);
        standardVault.deposit(100e18);
        vm.stopPrank();

        assertEq(standardVault.balanceOf(alice), 100e18, "Alice should have 100 tokens credited");
        assertEq(standardVault.totalTracked(), 100e18, "Total tracked should be 100");
        assertEq(standardToken.balanceOf(address(standardVault)), 100e18, "Vault should hold 100 tokens");
    }

    function test_StandardToken_DepositAndWithdraw() public {
        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 100e18);
        standardVault.deposit(100e18);
        standardVault.withdraw(60e18);
        vm.stopPrank();

        assertEq(standardVault.balanceOf(alice), 40e18, "Alice should have 40 tokens remaining");
        assertEq(standardVault.totalTracked(), 40e18, "Total tracked should be 40");
        assertEq(standardToken.balanceOf(alice), 960e18, "Alice should have 960 tokens in wallet");
    }

    function test_StandardToken_MultipleUsers() public {
        standardToken.mint(bob, 500e18);

        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 200e18);
        standardVault.deposit(200e18);
        vm.stopPrank();

        vm.startPrank(bob);
        standardToken.approve(address(standardVault), 300e18);
        standardVault.deposit(300e18);
        vm.stopPrank();

        assertEq(standardVault.balanceOf(alice), 200e18, "Alice balance");
        assertEq(standardVault.balanceOf(bob), 300e18, "Bob balance");
        assertEq(standardVault.totalTracked(), 500e18, "Total tracked");
    }

    function test_Revert_ZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(ZeroDeposit.selector);
        standardVault.deposit(0);
    }

    function test_Revert_WithdrawMoreThanBalance() public {
        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 100e18);
        standardVault.deposit(100e18);

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientBalance.selector, 200e18, 100e18)
        );
        standardVault.withdraw(200e18);
        vm.stopPrank();
    }

    function test_Revert_WithdrawWithNoDeposit() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientBalance.selector, 1e18, 0)
        );
        standardVault.withdraw(1e18);
    }

    // =========================================================
    //  Deposit Event Test
    // =========================================================

    function test_EmitsDepositEvent() public {
        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 50e18);

        vm.expectEmit(true, false, false, true);
        emit DefensiveVault.Deposit(alice, 50e18);
        standardVault.deposit(50e18);
        vm.stopPrank();
    }

    function test_EmitsWithdrawEvent() public {
        vm.startPrank(alice);
        standardToken.approve(address(standardVault), 50e18);
        standardVault.deposit(50e18);

        vm.expectEmit(true, false, false, true);
        emit DefensiveVault.Withdraw(alice, 30e18);
        standardVault.withdraw(30e18);
        vm.stopPrank();
    }

    // =========================================================
    //  Fee-on-Transfer Token Tests
    // =========================================================

    function test_FeeToken_CreditsActualReceived() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        DefensiveVault feeVault = new DefensiveVault(address(feeToken));

        feeToken.mint(alice, 1000e18);

        vm.startPrank(alice);
        feeToken.approve(address(feeVault), 100e18);
        feeVault.deposit(100e18);
        vm.stopPrank();

        // 1% fee → vault receives 99e18, NOT 100e18
        uint256 expectedReceived = 99e18;

        assertEq(
            feeVault.balanceOf(alice),
            expectedReceived,
            "Vault must credit ACTUAL received amount (99), not requested (100)"
        );
        assertEq(
            feeVault.totalTracked(),
            expectedReceived,
            "Total tracked must match actual received"
        );
        assertEq(
            feeToken.balanceOf(address(feeVault)),
            expectedReceived,
            "Vault token balance must match tracked amount"
        );
    }

    function test_FeeToken_WithdrawFullBalance() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        DefensiveVault feeVault = new DefensiveVault(address(feeToken));

        feeToken.mint(alice, 1000e18);

        vm.startPrank(alice);
        feeToken.approve(address(feeVault), 100e18);
        feeVault.deposit(100e18);

        // Alice can withdraw her actual credited balance (99e18)
        uint256 credited = feeVault.balanceOf(alice);
        feeVault.withdraw(credited);
        vm.stopPrank();

        assertEq(feeVault.balanceOf(alice), 0, "Balance should be zero after full withdraw");
        assertEq(feeVault.totalTracked(), 0, "Total tracked should be zero");
    }

    function test_FeeToken_VaultSolvency() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        DefensiveVault feeVault = new DefensiveVault(address(feeToken));

        feeToken.mint(alice, 1000e18);
        feeToken.mint(bob, 1000e18);

        // Both users deposit
        vm.startPrank(alice);
        feeToken.approve(address(feeVault), 500e18);
        feeVault.deposit(500e18);
        vm.stopPrank();

        vm.startPrank(bob);
        feeToken.approve(address(feeVault), 300e18);
        feeVault.deposit(300e18);
        vm.stopPrank();

        // Vault must always hold enough to cover all tracked balances
        uint256 totalTracked = feeVault.totalTracked();
        uint256 vaultBalance = feeToken.balanceOf(address(feeVault));

        assertGe(
            vaultBalance,
            totalTracked,
            "SOLVENCY: vault must hold at least as much as it tracks"
        );
    }

    // =========================================================
    //  No-Return-Value Token Tests (USDT-style)
    // =========================================================

    function test_NoReturnToken_DepositDoesNotRevert() public {
        NoReturnToken nrt = new NoReturnToken();
        DefensiveVault nrtVault = new DefensiveVault(address(nrt));

        nrt.mint(alice, 1000e18);

        vm.startPrank(alice);
        // Must use IERC20 interface to approve since NoReturnToken.approve has no return
        (bool ok,) = address(nrt).call(abi.encodeWithSignature("approve(address,uint256)", address(nrtVault), 100e18));
        require(ok, "approve failed");

        // This would revert without SafeERC20:
        // Solidity tries to decode empty returndata as bool → revert
        nrtVault.deposit(100e18);
        vm.stopPrank();

        assertEq(nrtVault.balanceOf(alice), 100e18, "Should credit full amount (no fee)");
    }

    function test_NoReturnToken_WithdrawDoesNotRevert() public {
        NoReturnToken nrt = new NoReturnToken();
        DefensiveVault nrtVault = new DefensiveVault(address(nrt));

        nrt.mint(alice, 1000e18);

        vm.startPrank(alice);
        (bool ok,) = address(nrt).call(abi.encodeWithSignature("approve(address,uint256)", address(nrtVault), 100e18));
        require(ok, "approve failed");

        nrtVault.deposit(100e18);
        nrtVault.withdraw(50e18);
        vm.stopPrank();

        assertEq(nrtVault.balanceOf(alice), 50e18, "Should have 50 remaining");
        assertEq(nrt.balanceOf(alice), 950e18, "Alice wallet should have 950");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_StandardRoundtrip(uint256 amount) public {
        amount = bound(amount, 1, 500e18);

        vm.startPrank(alice);
        standardToken.approve(address(standardVault), amount);
        standardVault.deposit(amount);

        assertEq(standardVault.balanceOf(alice), amount, "Credited should equal deposited for standard token");

        standardVault.withdraw(amount);
        vm.stopPrank();

        assertEq(standardVault.balanceOf(alice), 0, "Balance should be zero after full withdraw");
        assertEq(standardToken.balanceOf(alice), 1000e18, "Alice should have original balance back");
    }

    function testFuzz_FeeTokenNeverOvercredits(uint256 amount) public {
        amount = bound(amount, 100, 500e18); // min 100 so fee is at least 1

        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        DefensiveVault feeVault = new DefensiveVault(address(feeToken));

        feeToken.mint(alice, amount);

        vm.startPrank(alice);
        feeToken.approve(address(feeVault), amount);
        feeVault.deposit(amount);
        vm.stopPrank();

        // Core invariant: vault must never credit more than it received
        assertLe(
            feeVault.balanceOf(alice),
            feeToken.balanceOf(address(feeVault)),
            "INVARIANT: credited balance must not exceed vault's actual token balance"
        );

        // Credited should be less than requested (fee was taken)
        assertLt(
            feeVault.balanceOf(alice),
            amount,
            "Credited should be less than requested for fee-on-transfer"
        );
    }
}

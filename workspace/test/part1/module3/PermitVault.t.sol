// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    PermitVault,
    PermitToken,
    IERC20Permit,
    InsufficientBalance,
    TransferFailed,
    InvalidDeadline
} from "../../../src/part1/module3/PermitVault.sol";

/// @notice Tests for EIP-2612 Permit Vault exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module3/PermitVault.sol instead.
contract PermitVaultTest is Test {
    PermitVault vault;
    PermitToken token;

    address alice;
    uint256 alicePrivateKey;

    address bob;
    uint256 bobPrivateKey;

    function setUp() public {
        vault = new PermitVault();
        token = new PermitToken();

        // Create test users with known private keys
        alicePrivateKey = 0xA11CE;
        alice = vm.addr(alicePrivateKey);

        bobPrivateKey = 0xB0B;
        bob = vm.addr(bobPrivateKey);

        // Mint tokens to test users
        token.mint(alice, 10_000 * 1e18);
        token.mint(bob, 10_000 * 1e18);
    }

    // =========================================================
    //  Standard Deposit Tests (without permit)
    // =========================================================

    function test_StandardDeposit() public {
        uint256 depositAmount = 1000 * 1e18;

        // Alice approves the vault
        vm.prank(alice);
        token.approve(address(vault), depositAmount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(address(token), depositAmount);

        assertEq(vault.getBalance(alice, address(token)), depositAmount, "Alice should have deposited");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Vault should hold tokens");
    }

    function test_StandardDepositMultipleUsers() public {
        // Alice deposits
        vm.prank(alice);
        token.approve(address(vault), 1000 * 1e18);
        vm.prank(alice);
        vault.deposit(address(token), 1000 * 1e18);

        // Bob deposits
        vm.prank(bob);
        token.approve(address(vault), 2000 * 1e18);
        vm.prank(bob);
        vault.deposit(address(token), 2000 * 1e18);

        assertEq(vault.getBalance(alice, address(token)), 1000 * 1e18, "Alice balance");
        assertEq(vault.getBalance(bob, address(token)), 2000 * 1e18, "Bob balance");
        assertEq(token.balanceOf(address(vault)), 3000 * 1e18, "Total vault balance");
    }

    // =========================================================
    //  Permit Deposit Tests
    // =========================================================

    function test_DepositWithPermit() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Build the permit signature
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );

        // Alice deposits using permit (single transaction)
        vm.prank(alice);
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);

        assertEq(vault.getBalance(alice, address(token)), depositAmount, "Alice should have deposited");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Vault should hold tokens");
    }

    function test_DepositWithPermit_MultipleDeposits() public {
        uint256 deadline = block.timestamp + 1 hours;

        // First deposit: 1000 tokens
        (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            1000 * 1e18,
            deadline
        );
        vm.prank(alice);
        vault.depositWithPermit(address(token), 1000 * 1e18, deadline, v1, r1, s1);

        // Second deposit: 500 tokens (nonce incremented)
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            500 * 1e18,
            deadline
        );
        vm.prank(alice);
        vault.depositWithPermit(address(token), 500 * 1e18, deadline, v2, r2, s2);

        assertEq(vault.getBalance(alice, address(token)), 1500 * 1e18, "Total deposited should be 1500");
    }

    function test_DepositWithPermit_RevertOnExpiredDeadline() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp - 1; // Expired

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );

        vm.prank(alice);
        vm.expectRevert(InvalidDeadline.selector);
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);
    }

    function test_DepositWithPermit_RevertOnInvalidSignature() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with Alice's key
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );

        // Try to use the signature as Bob
        vm.prank(bob);
        vm.expectRevert(); // ERC20Permit reverts on invalid signature
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);
    }

    function test_DepositWithPermit_RevertOnReplayAttack() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );

        // First deposit succeeds
        vm.prank(alice);
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);

        // Try to replay the same signature
        vm.prank(alice);
        vm.expectRevert(); // Nonce already used
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);
    }

    // =========================================================
    //  Withdrawal Tests
    // =========================================================

    function test_Withdraw() public {
        // Deposit first
        vm.prank(alice);
        token.approve(address(vault), 1000 * 1e18);
        vm.prank(alice);
        vault.deposit(address(token), 1000 * 1e18);

        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Withdraw
        vm.prank(alice);
        vault.withdraw(address(token), 500 * 1e18);

        assertEq(vault.getBalance(alice, address(token)), 500 * 1e18, "Remaining balance");
        assertEq(token.balanceOf(alice), aliceBalanceBefore + 500 * 1e18, "Alice should receive tokens");
    }

    function test_WithdrawAll() public {
        // Deposit
        vm.prank(alice);
        token.approve(address(vault), 1000 * 1e18);
        vm.prank(alice);
        vault.deposit(address(token), 1000 * 1e18);

        // Withdraw all
        vm.prank(alice);
        vault.withdraw(address(token), 1000 * 1e18);

        assertEq(vault.getBalance(alice, address(token)), 0, "Balance should be zero");
        assertEq(token.balanceOf(address(vault)), 0, "Vault should be empty");
    }

    function test_RevertWithdrawInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientBalance.selector);
        vault.withdraw(address(token), 100 * 1e18);
    }

    function test_RevertWithdrawMoreThanBalance() public {
        // Deposit 1000
        vm.prank(alice);
        token.approve(address(vault), 1000 * 1e18);
        vm.prank(alice);
        vault.deposit(address(token), 1000 * 1e18);

        // Try to withdraw 1001
        vm.prank(alice);
        vm.expectRevert(InsufficientBalance.selector);
        vault.withdraw(address(token), 1001 * 1e18);
    }

    // =========================================================
    //  Integration Tests
    // =========================================================

    function test_PermitDepositAndWithdraw() public {
        uint256 depositAmount = 2000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Deposit with permit
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );
        vm.prank(alice);
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);

        // Withdraw half
        vm.prank(alice);
        vault.withdraw(address(token), 1000 * 1e18);

        assertEq(vault.getBalance(alice, address(token)), 1000 * 1e18, "Remaining balance");
    }

    function test_MixedDepositMethods() public {
        // Standard deposit
        vm.prank(alice);
        token.approve(address(vault), 1000 * 1e18);
        vm.prank(alice);
        vault.deposit(address(token), 1000 * 1e18);

        // Permit deposit
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            500 * 1e18,
            deadline
        );
        vm.prank(alice);
        vault.depositWithPermit(address(token), 500 * 1e18, deadline, v, r, s);

        // Total should be 1500
        assertEq(vault.getBalance(alice, address(token)), 1500 * 1e18, "Total balance");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_DepositZeroAmount() public {
        vm.prank(alice);
        token.approve(address(vault), 0);
        vm.prank(alice);
        vault.deposit(address(token), 0);

        assertEq(vault.getBalance(alice, address(token)), 0, "Zero deposit should work");
    }

    function test_NonceIncrementsCorrectly() public {
        uint256 nonceBefore = token.nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            1000 * 1e18,
            deadline
        );
        vm.prank(alice);
        vault.depositWithPermit(address(token), 1000 * 1e18, deadline, v, r, s);

        uint256 nonceAfter = token.nonces(alice);
        assertEq(nonceAfter, nonceBefore + 1, "Nonce should increment");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_DepositWithPermit(uint256 depositAmount) public {
        // Bound to reasonable range
        depositAmount = bound(depositAmount, 1, 10_000 * 1e18);

        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(vault),
            depositAmount,
            deadline
        );

        vm.prank(alice);
        vault.depositWithPermit(address(token), depositAmount, deadline, v, r, s);

        assertEq(vault.getBalance(alice, address(token)), depositAmount, "Deposit should match");
    }

    // =========================================================
    //  Helper Functions
    // =========================================================

    /// @notice Signs an EIP-2612 permit message.
    function _signPermit(
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (v, r, s) = vm.sign(ownerPrivateKey, digest);
    }
}

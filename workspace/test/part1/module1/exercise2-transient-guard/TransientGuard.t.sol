// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {
    TransientGuardedVault,
    AssemblyGuardedVault,
    StorageGuardedVault,
    UnguardedVault,
    ReentrancyAttacker
} from "../../../../src/part1/module1/exercise2-transient-guard/TransientGuard.sol";

/// @notice Tests for the transient reentrancy guard exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module1/TransientGuard.sol instead.
contract TransientGuardTest is Test {
    uint256 constant VICTIM_DEPOSIT = 10 ether;
    uint256 constant ATTACKER_DEPOSIT = 1 ether;
    uint256 constant MAX_REENTRIES = 5;

    address victim;

    function setUp() public {
        victim = makeAddr("victim");
        deal(victim, VICTIM_DEPOSIT);
        deal(address(this), 100 ether);
    }

    // =========================================================
    //  Baseline: Unguarded vault IS vulnerable
    // =========================================================

    function test_UnguardedVault_IsVulnerable() public {
        UnguardedVault vault = new UnguardedVault();
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(vault), MAX_REENTRIES);

        // Victim deposits
        vm.prank(victim);
        vault.deposit{value: VICTIM_DEPOSIT}();

        // Attacker strikes
        attacker.attack{value: ATTACKER_DEPOSIT}();

        // Attacker should have profited (drained more than their deposit)
        assertGt(
            address(attacker).balance,
            ATTACKER_DEPOSIT,
            "Attacker should profit from reentrancy"
        );

        // Vault should be partially drained
        assertLt(
            address(vault).balance,
            VICTIM_DEPOSIT + ATTACKER_DEPOSIT,
            "Vault should be partially drained"
        );
    }

    // =========================================================
    //  Guard tests: reentrancy should be BLOCKED
    // =========================================================

    function test_TransientGuard_BlocksReentrancy() public {
        TransientGuardedVault vault = new TransientGuardedVault();
        _assertGuardWorks(address(vault));
    }

    function test_AssemblyGuard_BlocksReentrancy() public {
        AssemblyGuardedVault vault = new AssemblyGuardedVault();
        _assertGuardWorks(address(vault));
    }

    function test_StorageGuard_BlocksReentrancy() public {
        StorageGuardedVault vault = new StorageGuardedVault();
        _assertGuardWorks(address(vault));
    }

    // =========================================================
    //  Normal operation: guards don't block legitimate use
    // =========================================================

    function test_TransientGuard_NormalWithdraw() public {
        TransientGuardedVault vault = new TransientGuardedVault();
        _assertNormalWithdrawWorks(address(vault));
    }

    function test_AssemblyGuard_NormalWithdraw() public {
        AssemblyGuardedVault vault = new AssemblyGuardedVault();
        _assertNormalWithdrawWorks(address(vault));
    }

    function test_StorageGuard_NormalWithdraw() public {
        StorageGuardedVault vault = new StorageGuardedVault();
        _assertNormalWithdrawWorks(address(vault));
    }

    // =========================================================
    //  Gas comparison
    // =========================================================

    function test_GasComparison() public {
        TransientGuardedVault tVault = new TransientGuardedVault();
        AssemblyGuardedVault aVault = new AssemblyGuardedVault();
        StorageGuardedVault sVault = new StorageGuardedVault();

        // Deposit into each vault
        tVault.deposit{value: 1 ether}();
        aVault.deposit{value: 1 ether}();
        sVault.deposit{value: 1 ether}();

        // Measure withdraw gas for each guard type
        uint256 g;

        g = gasleft();
        tVault.withdraw();
        uint256 transientGas = g - gasleft();

        g = gasleft();
        aVault.withdraw();
        uint256 assemblyGas = g - gasleft();

        g = gasleft();
        sVault.withdraw();
        uint256 storageGas = g - gasleft();

        emit log_named_uint("Transient keyword guard gas", transientGas);
        emit log_named_uint("Assembly tstore/tload guard gas", assemblyGas);
        emit log_named_uint("Classic storage guard gas", storageGas);

        // NOTE: In a single-transaction test, all storage slots are "warm"
        // after first access, so SLOAD costs only 100 gas (same as TLOAD).
        // The real savings from transient storage appear in production where
        // the first SLOAD/SSTORE in a transaction is "cold" (2100+ gas).
        //
        // This test logs the values so you can compare. Run with -vv to see
        // the gas breakdown. The key insight: transient storage provides
        // predictable, low-cost access regardless of cold/warm state.

        // Sanity check: transient guard should not be significantly more
        // expensive than storage guard (even in warm-slot test conditions)
        assertTrue(
            transientGas <= storageGas + 5000,
            "Transient guard should not be significantly more expensive than storage"
        );
    }

    // =========================================================
    //  Sequential operations: guard resets properly
    // =========================================================

    function test_TransientGuard_AllowsSequentialOperations() public {
        TransientGuardedVault vault = new TransientGuardedVault();
        address user = makeAddr("sequential");
        deal(user, 10 ether);

        vm.startPrank(user);

        // First cycle: deposit + withdraw
        vault.deposit{value: 5 ether}();
        vault.withdraw();

        // Second cycle: guard resets properly, not permanently locked
        vault.deposit{value: 5 ether}();
        vault.withdraw();

        vm.stopPrank();

        assertEq(user.balance, 10 ether, "User should recover all ETH after two cycles");
    }

    // =========================================================
    //  Helpers
    // =========================================================

    function _assertGuardWorks(address vault) internal {
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault, MAX_REENTRIES);

        // Victim deposits
        vm.prank(victim);
        (bool ok,) = vault.call{value: VICTIM_DEPOSIT}(
            abi.encodeWithSignature("deposit()")
        );
        require(ok, "Victim deposit failed");

        // Attacker tries reentrancy
        attacker.attack{value: ATTACKER_DEPOSIT}();

        // Attacker should only get their deposit back (no profit)
        assertEq(
            address(attacker).balance,
            ATTACKER_DEPOSIT,
            "Attacker should not profit - guard should block reentrancy"
        );

        // Vault should still hold victim's deposit
        assertEq(
            vault.balance,
            VICTIM_DEPOSIT,
            "Vault should still hold victim's funds"
        );

        // Attacker should have attempted re-entry (proves attack was tried)
        assertGt(
            attacker.reentrantCalls(),
            0,
            "Attacker should have attempted at least one re-entry"
        );
    }

    function _assertNormalWithdrawWorks(address vault) internal {
        // Deposit
        address user = makeAddr("user");
        deal(user, 5 ether);

        vm.prank(user);
        (bool ok,) = vault.call{value: 5 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(ok, "Deposit failed");

        // Withdraw normally (no reentrancy)
        vm.prank(user);
        (ok,) = vault.call(abi.encodeWithSignature("withdraw()"));
        assertTrue(ok, "Normal withdraw should succeed");

        // User should have their ETH back
        assertEq(user.balance, 5 ether, "User should get their ETH back");
        assertEq(vault.balance, 0, "Vault should be empty");
    }

    receive() external payable {}
}

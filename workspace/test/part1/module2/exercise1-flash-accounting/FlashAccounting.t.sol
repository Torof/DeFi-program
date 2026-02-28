// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {
    FlashAccounting,
    FlashAccountingUser,
    NotLocked,
    AlreadyLocked,
    NotSettled,
    Unauthorized
} from "../../../../src/part1/module2/exercise1-flash-accounting/FlashAccounting.sol";

/// @notice Tests for the flash accounting exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module2/FlashAccounting.sol instead.
contract FlashAccountingTest is Test {
    FlashAccounting accounting;
    FlashAccountingUser user;

    address alice;
    address bob;

    address constant TOKEN_A = address(0xA);
    address constant TOKEN_B = address(0xB);
    address constant TOKEN_C = address(0xC);
    address constant NATIVE = address(0); // Using address(0) for native token

    function setUp() public {
        accounting = new FlashAccounting();
        user = new FlashAccountingUser(payable(address(accounting)));

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Fund test accounts
        deal(alice, 100 ether);
        deal(bob, 100 ether);
        deal(address(accounting), 50 ether); // Fund the accounting contract for settlements
    }

    // =========================================================
    //  Lock/Unlock Tests
    // =========================================================

    function test_LockUnlock() public {
        assertFalse(accounting.isLocked(), "Should start unlocked");

        accounting.lock();
        assertTrue(accounting.isLocked(), "Should be locked after lock()");

        accounting.unlock();
        assertFalse(accounting.isLocked(), "Should be unlocked after unlock()");
    }

    function test_RevertOnDoubleLock() public {
        accounting.lock();

        vm.expectRevert(AlreadyLocked.selector);
        accounting.lock();
    }

    function test_RevertOnOperationWhenNotLocked() public {
        vm.expectRevert(NotLocked.selector);
        accounting.accountDelta(alice, TOKEN_A, 100);
    }

    function test_TransientStoragePersistsWithinTransaction() public {
        // Lock and record a delta
        accounting.lock();
        accounting.accountDelta(alice, TOKEN_A, 1000);

        int256 delta = accounting.getDelta(alice, TOKEN_A);
        assertEq(delta, 1000, "Delta should be recorded");

        accounting.unlock();

        // Within the SAME transaction, transient storage persists across
        // lock/unlock cycles. EIP-1153 only clears transient storage at
        // transaction boundaries — not on lock/unlock.
        // In production, each user transaction is separate, so deltas
        // ARE wiped between sessions. Foundry test functions run as a
        // single transaction, so we verify persistence here.
        accounting.lock();
        int256 persistedDelta = accounting.getDelta(alice, TOKEN_A);
        assertEq(persistedDelta, 1000, "Delta persists within same transaction");
        accounting.unlock();
    }

    // =========================================================
    //  Delta Accounting Tests
    // =========================================================

    function test_AccountSingleDelta() public {
        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, 500);

        int256 delta = accounting.getDelta(alice, TOKEN_A);
        assertEq(delta, 500, "Alice should have +500 delta for TOKEN_A");

        accounting.unlock();
    }

    function test_AccountMultipleDeltas() public {
        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, 100);
        accounting.accountDelta(alice, TOKEN_A, 200);
        accounting.accountDelta(alice, TOKEN_A, -50);

        int256 delta = accounting.getDelta(alice, TOKEN_A);
        assertEq(delta, 250, "Alice should have net +250 delta (100+200-50)");

        accounting.unlock();
    }

    function test_SeparateDeltasPerUserAndToken() public {
        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, 100);
        accounting.accountDelta(alice, TOKEN_B, 200);
        accounting.accountDelta(bob, TOKEN_A, 300);

        assertEq(accounting.getDelta(alice, TOKEN_A), 100, "Alice TOKEN_A delta");
        assertEq(accounting.getDelta(alice, TOKEN_B), 200, "Alice TOKEN_B delta");
        assertEq(accounting.getDelta(bob, TOKEN_A), 300, "Bob TOKEN_A delta");
        assertEq(accounting.getDelta(bob, TOKEN_B), 0, "Bob TOKEN_B delta should be 0");

        accounting.unlock();
    }

    function test_NegativeDeltas() public {
        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, -500);

        int256 delta = accounting.getDelta(alice, TOKEN_A);
        assertEq(delta, -500, "Alice should owe 500");

        accounting.unlock();
    }

    // =========================================================
    //  Settlement Tests
    // =========================================================

    function test_SettlePositiveDelta() public {
        // Setup: Contract owes alice 1 ether
        accounting.lock();
        accounting.accountDelta(alice, NATIVE, 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        accounting.settle(alice);

        uint256 aliceBalanceAfter = alice.balance;
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 1 ether, "Alice should receive 1 ether");

        int256 deltaAfter = accounting.getDelta(alice, NATIVE);
        assertEq(deltaAfter, 0, "Delta should be cleared after settlement");

        accounting.unlock();
    }

    function test_SettleNegativeDelta() public {
        // Setup: Alice owes contract 2 ether
        accounting.lock();
        accounting.accountDelta(alice, NATIVE, -2 ether);

        uint256 contractBalanceBefore = address(accounting).balance;

        // Alice pays the debt
        vm.prank(alice);
        accounting.settle{value: 2 ether}(alice);

        uint256 contractBalanceAfter = address(accounting).balance;
        assertEq(contractBalanceAfter - contractBalanceBefore, 2 ether, "Contract should receive 2 ether");

        int256 deltaAfter = accounting.getDelta(alice, NATIVE);
        assertEq(deltaAfter, 0, "Delta should be cleared after settlement");

        accounting.unlock();
    }

    function test_RevertSettleNegativeDeltaWithWrongAmount() public {
        accounting.lock();
        accounting.accountDelta(alice, NATIVE, -1 ether);

        // Try to settle with wrong amount
        vm.prank(alice);
        vm.expectRevert(NotSettled.selector);
        accounting.settle{value: 0.5 ether}(alice); // Sending too little

        accounting.unlock();
    }

    // =========================================================
    //  Integration: FlashAccountingUser Tests
    // =========================================================

    function test_SingleSwap() public {
        accounting.lock();

        user.executeSwap(alice, TOKEN_A, TOKEN_B, 100, 95);

        // Alice should owe 100 TOKEN_A and be owed 95 TOKEN_B
        assertEq(accounting.getDelta(alice, TOKEN_A), -100, "Alice owes 100 TOKEN_A");
        assertEq(accounting.getDelta(alice, TOKEN_B), 95, "Alice receives 95 TOKEN_B");

        accounting.unlock();
    }

    function test_BatchSwapsWithCancellation() public {
        accounting.lock();

        // Execute batch: A->B->C
        // Alice pays 1000 A, receives 950 B
        // Alice pays 950 B, receives 900 C
        // Net: Alice pays 1000 A, receives 900 C (B cancels out)
        user.executeBatchSwaps(alice, TOKEN_A, TOKEN_B, TOKEN_C, 1000, 950, 900);

        assertEq(accounting.getDelta(alice, TOKEN_A), -1000, "Alice owes 1000 TOKEN_A");
        assertEq(accounting.getDelta(alice, TOKEN_B), 0, "TOKEN_B should cancel out");
        assertEq(accounting.getDelta(alice, TOKEN_C), 900, "Alice receives 900 TOKEN_C");

        accounting.unlock();
    }

    function test_FullFlowWithSettlement() public {
        // Fund accounting contract so it can pay out
        vm.deal(address(accounting), 10 ether);

        accounting.lock();

        // Simulate a swap where Alice ends up with a net positive delta
        accounting.accountDelta(alice, NATIVE, 1 ether);

        // Settle alice's position
        uint256 aliceBalanceBefore = alice.balance;
        accounting.settle(alice);
        uint256 aliceBalanceAfter = alice.balance;

        assertEq(aliceBalanceAfter - aliceBalanceBefore, 1 ether, "Alice should receive 1 ether");
        assertEq(accounting.getDelta(alice, NATIVE), 0, "Alice's delta should be cleared");

        accounting.unlock();
    }

    function test_SettlePositiveDeltaRejectsExtraETH() public {
        // If the contract owes alice, alice should NOT need to send msg.value.
        // Sending ETH when the contract owes you is likely a mistake.
        accounting.lock();
        accounting.accountDelta(alice, NATIVE, 1 ether);

        // Alice sends ETH even though she's owed — should revert
        vm.prank(alice);
        vm.expectRevert(NotSettled.selector);
        accounting.settle{value: 1 ether}(alice);

        accounting.unlock();
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_SettleZeroDelta() public {
        accounting.lock();

        // Alice has no delta
        accounting.settle(alice); // Should succeed (no-op)

        assertEq(accounting.getDelta(alice, NATIVE), 0, "Delta should remain 0");

        accounting.unlock();
    }

    function test_MultipleUsersIndependentDeltas() public {
        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, 100);
        accounting.accountDelta(bob, TOKEN_A, -50);

        assertEq(accounting.getDelta(alice, TOKEN_A), 100, "Alice delta");
        assertEq(accounting.getDelta(bob, TOKEN_A), -50, "Bob delta");

        // Deltas are independent
        accounting.accountDelta(alice, TOKEN_A, 50);
        assertEq(accounting.getDelta(alice, TOKEN_A), 150, "Alice delta updated");
        assertEq(accounting.getDelta(bob, TOKEN_A), -50, "Bob delta unchanged");

        accounting.unlock();
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_DeltaAccumulation(int256 delta1, int256 delta2, int256 delta3) public {
        // Bound to prevent overflow
        delta1 = bound(delta1, type(int256).min / 3, type(int256).max / 3);
        delta2 = bound(delta2, type(int256).min / 3, type(int256).max / 3);
        delta3 = bound(delta3, type(int256).min / 3, type(int256).max / 3);

        accounting.lock();

        accounting.accountDelta(alice, TOKEN_A, delta1);
        accounting.accountDelta(alice, TOKEN_A, delta2);
        accounting.accountDelta(alice, TOKEN_A, delta3);

        int256 expectedDelta = delta1 + delta2 + delta3;
        int256 actualDelta = accounting.getDelta(alice, TOKEN_A);

        assertEq(actualDelta, expectedDelta, "Deltas should accumulate correctly");

        accounting.unlock();
    }
}

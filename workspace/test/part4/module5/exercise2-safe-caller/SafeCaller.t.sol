// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for SafeCaller.
/// Your task is to implement the contract in SafeCaller.sol so all tests pass.

import "forge-std/Test.sol";
import {SafeCaller} from "../../../../src/part4/module5/exercise2-safe-caller/SafeCaller.sol";
import {MockERC20} from "../../../../src/part4/module5/mocks/MockERC20.sol";
import {MockNoReturnToken} from "../../../../src/part4/module5/mocks/MockNoReturnToken.sol";
import {MockReturnBomb} from "../../../../src/part4/module5/mocks/MockReturnBomb.sol";
import {MockTarget} from "../../../../src/part4/module5/mocks/MockTarget.sol";

/// @dev Token that always returns false from transfer/transferFrom.
contract MockFalseToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract SafeCallerTest is Test {
    SafeCaller internal caller;
    MockERC20 internal token;
    MockNoReturnToken internal usdt;
    MockTarget internal target;

    address internal alice = makeAddr("alice");

    function setUp() public {
        caller = new SafeCaller();
        target = new MockTarget();

        // Deploy standard token — deployer (this test contract) gets max supply
        token = new MockERC20();
        // Transfer tokens to the SafeCaller contract so it can call safeTransfer
        token.transfer(address(caller), 1_000_000e18);

        // Deploy USDT-style token — deployer gets max supply
        usdt = new MockNoReturnToken();
        // Transfer tokens to SafeCaller
        usdt.transfer(address(caller), 1_000_000e18);
    }

    // =========================================================================
    // TODO 1: bubbleRevert
    // =========================================================================

    function test_BubbleRevert_successfulCallDoesNotRevert() public {
        // Call deposit(alice, 0) on target — should succeed
        bytes memory data = abi.encodeWithSelector(
            MockTarget.deposit.selector,
            alice,
            uint256(0)
        );
        caller.bubbleRevert(address(target), data);

        // Verify the call actually executed
        assertEq(target.balances(alice), 0, "Deposit with 0 value should record 0");
    }

    function test_BubbleRevert_bubblesCustomError() public {
        // alwaysReverts(999) reverts with InsufficientBalance(999, 0)
        bytes memory data = abi.encodeWithSelector(
            MockTarget.alwaysReverts.selector,
            uint256(999)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                MockTarget.InsufficientBalance.selector,
                uint256(999),
                uint256(0)
            )
        );
        caller.bubbleRevert(address(target), data);
    }

    function test_BubbleRevert_bubblesRequireMessage() public {
        // Call transfer on a token with insufficient balance —
        // reverts with "insufficient" require message
        MockERC20 emptyToken = new MockERC20();
        // emptyToken deployer (this) has tokens, but SafeCaller does not

        bytes memory data = abi.encodeWithSelector(
            bytes4(0xa9059cbb), // transfer(address,uint256)
            alice,
            uint256(1)
        );

        vm.expectRevert(bytes("insufficient"));
        caller.bubbleRevert(address(emptyToken), data);
    }

    // =========================================================================
    // TODO 2: safeTransfer — standard token (returns bool)
    // =========================================================================

    function test_SafeTransfer_standardToken() public {
        caller.safeTransfer(address(token), alice, 100e18);

        assertEq(
            token.balanceOf(alice),
            100e18,
            "Alice should receive 100 tokens from standard token"
        );
    }

    function test_SafeTransfer_standardToken_multipleTransfers() public {
        caller.safeTransfer(address(token), alice, 50e18);
        caller.safeTransfer(address(token), alice, 30e18);

        assertEq(
            token.balanceOf(alice),
            80e18,
            "Multiple transfers should accumulate"
        );
    }

    // =========================================================================
    // TODO 2: safeTransfer — non-returning token (USDT-style)
    // =========================================================================

    function test_SafeTransfer_noReturnToken() public {
        caller.safeTransfer(address(usdt), alice, 100e18);

        assertEq(
            usdt.balanceOf(alice),
            100e18,
            "Alice should receive 100 tokens from USDT-style token"
        );
    }

    function test_SafeTransfer_noReturnToken_multipleTransfers() public {
        caller.safeTransfer(address(usdt), alice, 50e18);
        caller.safeTransfer(address(usdt), alice, 30e18);

        assertEq(
            usdt.balanceOf(alice),
            80e18,
            "Multiple transfers on USDT-style token should accumulate"
        );
    }

    // =========================================================================
    // TODO 2: safeTransfer — failure cases
    // =========================================================================

    function test_SafeTransfer_revertsOnFalseReturn() public {
        // A token that returns false (transfer silently fails)
        MockFalseToken falseToken = new MockFalseToken();

        vm.expectRevert(abi.encodeWithSelector(bytes4(0x90b8ec18))); // TransferFailed()
        caller.safeTransfer(address(falseToken), alice, 1);
    }

    function test_SafeTransfer_revertsOnCallFailure() public {
        // Call safeTransfer on a contract with no transfer function
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x90b8ec18))); // TransferFailed()
        caller.safeTransfer(address(caller), alice, 1);
    }

    // =========================================================================
    // TODO 3: safeTransferFrom — standard token
    // =========================================================================

    function test_SafeTransferFrom_standardToken() public {
        address bob = makeAddr("bob");

        // Give bob tokens and approve SafeCaller
        token.transfer(bob, 500e18);
        vm.prank(bob);
        token.approve(address(caller), 500e18);

        caller.safeTransferFrom(address(token), bob, alice, 200e18);

        assertEq(
            token.balanceOf(alice),
            200e18,
            "Alice should receive 200 tokens via transferFrom"
        );
        assertEq(
            token.balanceOf(bob),
            300e18,
            "Bob should have 300 remaining"
        );
    }

    // =========================================================================
    // TODO 3: safeTransferFrom — non-returning token (USDT-style)
    // =========================================================================

    function test_SafeTransferFrom_noReturnToken() public {
        address bob = makeAddr("bob");

        // Give bob USDT-style tokens and approve SafeCaller
        usdt.transfer(bob, 500e18);
        vm.prank(bob);
        usdt.approve(address(caller), 500e18);

        caller.safeTransferFrom(address(usdt), bob, alice, 200e18);

        assertEq(
            usdt.balanceOf(alice),
            200e18,
            "Alice should receive 200 USDT-style tokens via transferFrom"
        );
    }

    // =========================================================================
    // TODO 3: safeTransferFrom — failure cases
    // =========================================================================

    function test_SafeTransferFrom_revertsOnFalseReturn() public {
        MockFalseToken falseToken = new MockFalseToken();

        vm.expectRevert(abi.encodeWithSelector(bytes4(0x7939f424))); // TransferFromFailed()
        caller.safeTransferFrom(address(falseToken), alice, address(caller), 1);
    }

    function test_SafeTransferFrom_revertsOnCallFailure() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x7939f424))); // TransferFromFailed()
        caller.safeTransferFrom(address(caller), alice, address(caller), 1);
    }

    // =========================================================================
    // TODO 4: boundedCall — returnbomb defense
    // =========================================================================

    function test_BoundedCall_successfulCallReturnsData() public {
        // Call getBalance(alice) on target — returns uint256(0)
        bytes memory data = abi.encodeWithSelector(
            MockTarget.getBalance.selector,
            alice
        );

        // Use low-level call because boundedCall uses assembly `return`,
        // which bypasses Solidity's ABI encoding (same pattern as proxyForward)
        (bool ok, bytes memory result) = address(caller).call(
            abi.encodeWithSelector(
                SafeCaller.boundedCall.selector,
                address(target),
                data
            )
        );
        assertTrue(ok, "boundedCall should succeed");

        // The raw return is the getBalance return data (32 bytes for uint256)
        assertEq(result.length, 32, "Should return 32 bytes for uint256");
        assertEq(abi.decode(result, (uint256)), 0, "Balance should be 0");
    }

    function test_BoundedCall_survivesReturnBomb() public {
        // MockReturnBomb returns 10,000 bytes on any call.
        // Without the 256-byte cap, copying all 10,000 bytes would cost
        // massive gas for memory expansion. With the cap, only 256 bytes
        // are copied — the call should succeed without running out of gas.
        MockReturnBomb bomb = new MockReturnBomb();

        bytes memory data = hex"deadbeef"; // arbitrary selector

        // Use low-level call because boundedCall uses assembly `return`
        (bool ok, bytes memory result) = address(caller).call(
            abi.encodeWithSelector(
                SafeCaller.boundedCall.selector,
                address(bomb),
                data
            )
        );
        assertTrue(ok, "boundedCall should succeed against returnbomb");

        // Return data should be capped at 256 bytes
        assertLe(
            result.length,
            256,
            "Return data should be capped at 256 bytes (returnbomb defense)"
        );
    }

    function test_BoundedCall_bubblesRevertBounded() public {
        // Call alwaysReverts — the revert data should be bubbled but capped
        bytes memory data = abi.encodeWithSelector(
            MockTarget.alwaysReverts.selector,
            uint256(42)
        );

        // InsufficientBalance(42, 0) = 4 + 32 + 32 = 68 bytes (well under 256)
        vm.expectRevert(
            abi.encodeWithSelector(
                MockTarget.InsufficientBalance.selector,
                uint256(42),
                uint256(0)
            )
        );
        caller.boundedCall(address(target), data);
    }

    function test_BoundedCall_gasUsageReasonable() public {
        // Verify the returnbomb defense actually saves gas.
        // Calling the bomb with bounded copy should use reasonable gas,
        // not the millions that unbounded copy would cost.
        MockReturnBomb bomb = new MockReturnBomb();

        bytes memory payload = abi.encodeWithSelector(
            SafeCaller.boundedCall.selector,
            address(bomb),
            hex"deadbeef"
        );
        uint256 gasBefore = gasleft();
        (bool ok,) = address(caller).call(payload);
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(ok, "boundedCall should succeed");

        // Unbounded copy of 10,000 bytes would cost ~300,000+ gas for memory expansion.
        // Bounded copy of 256 bytes should use well under 100,000 total.
        assertLt(
            gasUsed,
            100_000,
            "Bounded call should use reasonable gas (returnbomb defense working)"
        );
    }
}

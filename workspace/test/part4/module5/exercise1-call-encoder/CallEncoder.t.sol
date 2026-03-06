// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for CallEncoder.
/// Your task is to implement the contract in CallEncoder.sol so all tests pass.

import "forge-std/Test.sol";
import {CallEncoder} from "../../../../src/part4/module5/exercise1-call-encoder/CallEncoder.sol";
import {MockTarget} from "../../../../src/part4/module5/mocks/MockTarget.sol";

/// @dev A target whose deposit() always reverts — used to test error bubbling.
contract RevertingTarget {
    error DepositBlocked(address account, uint256 tag);

    function deposit(address account, uint256 tag) external payable {
        revert DepositBlocked(account, tag);
    }
}

contract CallEncoderTest is Test {
    CallEncoder internal encoder;
    MockTarget internal target;

    address internal alice = makeAddr("alice");

    function setUp() public {
        encoder = new CallEncoder();
        target = new MockTarget();
        vm.deal(address(encoder), 10 ether);
    }

    // =========================================================================
    // TODO 1: callWithValue
    // =========================================================================

    function test_CallWithValue_depositsEthForAccount() public {
        encoder.callWithValue{value: 1 ether}(address(target), alice, 42);

        assertEq(
            target.balances(alice),
            1 ether,
            "Target should record 1 ether deposited for alice"
        );
    }

    function test_CallWithValue_zeroValue() public {
        encoder.callWithValue{value: 0}(address(target), alice, 0);

        assertEq(
            target.balances(alice),
            0,
            "Zero-value call should succeed and record 0 balance"
        );
    }

    function test_CallWithValue_multipleDeposits() public {
        encoder.callWithValue{value: 0.5 ether}(address(target), alice, 1);
        encoder.callWithValue{value: 0.3 ether}(address(target), alice, 2);

        assertEq(
            target.balances(alice),
            0.8 ether,
            "Multiple deposits should accumulate"
        );
    }

    function test_CallWithValue_bubblesRevertData() public {
        // Call a target whose deposit() always reverts with DepositBlocked.
        // The exact revert data should bubble up through callWithValue.
        RevertingTarget bad = new RevertingTarget();

        vm.expectRevert(
            abi.encodeWithSelector(
                RevertingTarget.DepositBlocked.selector,
                alice,
                uint256(999)
            )
        );
        encoder.callWithValue{value: 0}(address(bad), alice, 999);
    }

    function test_CallWithValue_revertsOnBadTarget() public {
        // Calling deposit() on a contract without that function should revert.
        // The encoder contract itself has no deposit function.
        vm.expectRevert();
        encoder.callWithValue{value: 0}(address(encoder), alice, 0);
    }

    // =========================================================================
    // TODO 2: staticRead
    // =========================================================================

    function test_StaticRead_returnsZeroForUnknownAccount() public view {
        uint256 balance = encoder.staticRead(address(target), alice);
        assertEq(balance, 0, "Unknown account should have 0 balance");
    }

    function test_StaticRead_returnsCorrectBalance() public {
        target.deposit{value: 2 ether}(alice, 0);

        uint256 balance = encoder.staticRead(address(target), alice);
        assertEq(balance, 2 ether, "Should read alice's deposited balance");
    }

    function test_StaticRead_multipleAccounts() public {
        address bob = makeAddr("bob");

        target.deposit{value: 1 ether}(alice, 0);
        target.deposit{value: 3 ether}(bob, 0);

        assertEq(
            encoder.staticRead(address(target), alice),
            1 ether,
            "Alice balance should be 1 ether"
        );
        assertEq(
            encoder.staticRead(address(target), bob),
            3 ether,
            "Bob balance should be 3 ether"
        );
    }

    function test_StaticRead_revertsOnFailedCall() public {
        // STATICCALL to a contract that reverts on this selector.
        // The encoder itself doesn't have getBalance, so staticcall fails.
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x3204506f))); // CallFailed()
        encoder.staticRead(address(encoder), alice);
    }

    // =========================================================================
    // TODO 3: multiRead
    // =========================================================================

    function test_MultiRead_decodesThreeValues() public view {
        (uint256 a, uint256 b, uint256 c) = encoder.multiRead(address(target), 10);

        assertEq(a, 10, "First return value should be x (10)");
        assertEq(b, 20, "Second return value should be x*2 (20)");
        assertEq(c, 30, "Third return value should be x*3 (30)");
    }

    function test_MultiRead_zeroInput() public view {
        (uint256 a, uint256 b, uint256 c) = encoder.multiRead(address(target), 0);

        assertEq(a, 0, "getTriple(0) first value should be 0");
        assertEq(b, 0, "getTriple(0) second value should be 0");
        assertEq(c, 0, "getTriple(0) third value should be 0");
    }

    function test_MultiRead_largeInput() public view {
        uint256 x = 1e18;
        (uint256 a, uint256 b, uint256 c) = encoder.multiRead(address(target), x);

        assertEq(a, x, "First value should equal input");
        assertEq(b, x * 2, "Second value should be 2x");
        assertEq(c, x * 3, "Third value should be 3x");
    }

    function testFuzz_MultiRead_properties(uint256 x) public view {
        x = bound(x, 0, type(uint256).max / 3); // avoid overflow in x*3

        (uint256 a, uint256 b, uint256 c) = encoder.multiRead(address(target), x);

        assertEq(a, x, "a should equal x");
        assertEq(b, x * 2, "b should equal 2x");
        assertEq(c, x * 3, "c should equal 3x");
    }

    function test_MultiRead_revertsOnFailedCall() public {
        // Calling a target that doesn't have getTriple should revert with CallFailed()
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x3204506f))); // CallFailed()
        encoder.multiRead(address(encoder), 1);
    }
}

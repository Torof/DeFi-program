// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for LoopAndFunctions.
/// Your task is to implement the contract in LoopAndFunctions.sol so all tests pass.

import "forge-std/Test.sol";
import {LoopAndFunctions} from "../../../../src/part4/module4/exercise2-loop-and-functions/LoopAndFunctions.sol";

contract LoopAndFunctionsTest is Test {
    LoopAndFunctions internal exercise;

    address internal owner;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    function setUp() public {
        owner = address(this);
        exercise = new LoopAndFunctions();
    }

    // =========================================================================
    // TODO 1: requireWithError
    // =========================================================================

    function test_RequireWithError_trueDoesNotRevert() public view {
        // Should not revert when condition is true
        exercise.requireWithError(true, bytes4(0xdeadbeef));
    }

    function test_RequireWithError_falseRevertsWithSelector() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(0xdeadbeef)));
        exercise.requireWithError(false, bytes4(0xdeadbeef));
    }

    function testFuzz_RequireWithError_falseAlwaysReverts(bytes4 selector) public {
        vm.expectRevert(abi.encodeWithSelector(selector));
        exercise.requireWithError(false, selector);
    }

    // =========================================================================
    // TODO 2: min and max
    // =========================================================================

    function test_Min_basicValues() public view {
        assertEq(exercise.min(3, 7), 3, "min(3, 7) should be 3");
        assertEq(exercise.min(7, 3), 3, "min(7, 3) should be 3");
    }

    function test_Min_equalValues() public view {
        assertEq(exercise.min(5, 5), 5, "min(5, 5) should be 5");
    }

    function test_Max_basicValues() public view {
        assertEq(exercise.max(3, 7), 7, "max(3, 7) should be 7");
        assertEq(exercise.max(7, 3), 7, "max(7, 3) should be 7");
    }

    function test_Max_equalValues() public view {
        assertEq(exercise.max(5, 5), 5, "max(5, 5) should be 5");
    }

    function testFuzz_MinMax_properties(uint256 a, uint256 b) public view {
        uint256 minVal = exercise.min(a, b);
        uint256 maxVal = exercise.max(a, b);

        assertTrue(minVal <= maxVal, "min should be <= max");
        assertTrue(minVal == a || minVal == b, "min should be one of the inputs");
        assertTrue(maxVal == a || maxVal == b, "max should be one of the inputs");
    }

    // =========================================================================
    // TODO 3: sumArray
    // =========================================================================

    function test_SumArray_singleElement() public view {
        uint256[] memory arr = new uint256[](1);
        arr[0] = 42;
        assertEq(exercise.sumArray(arr), 42, "Sum of [42] should be 42");
    }

    function test_SumArray_multipleElements() public view {
        uint256[] memory arr = new uint256[](4);
        arr[0] = 10;
        arr[1] = 20;
        arr[2] = 30;
        arr[3] = 40;
        assertEq(exercise.sumArray(arr), 100, "Sum of [10,20,30,40] should be 100");
    }

    function test_SumArray_emptyArray() public view {
        uint256[] memory arr = new uint256[](0);
        assertEq(exercise.sumArray(arr), 0, "Sum of empty array should be 0");
    }

    // =========================================================================
    // TODO 4: findMax
    // =========================================================================

    function test_FindMax_singleElement() public view {
        uint256[] memory arr = new uint256[](1);
        arr[0] = 99;
        assertEq(exercise.findMax(arr), 99, "Max of [99] should be 99");
    }

    function test_FindMax_multipleElements() public view {
        uint256[] memory arr = new uint256[](5);
        arr[0] = 10;
        arr[1] = 50;
        arr[2] = 30;
        arr[3] = 50;
        arr[4] = 20;
        assertEq(exercise.findMax(arr), 50, "Max of [10,50,30,50,20] should be 50");
    }

    function test_FindMax_emptyArray() public view {
        uint256[] memory arr = new uint256[](0);
        assertEq(exercise.findMax(arr), 0, "Max of empty array should be 0");
    }

    // =========================================================================
    // TODO 5: batchTransfer
    // =========================================================================

    function test_BatchTransfer_basic() public {
        // Owner has 1,000,000 tokens from constructor
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 300;
        amounts[1] = 500;

        exercise.batchTransfer(recipients, amounts);

        assertEq(exercise.balanceOf(alice), 300, "Alice should receive 300");
        assertEq(exercise.balanceOf(bob), 500, "Bob should receive 500");
        assertEq(exercise.balanceOf(owner), 1000000 - 800, "Owner balance should decrease by total");
    }

    function test_BatchTransfer_arrayLengthMismatchReverts() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(bytes4(0x3b800a46))); // ArrayLengthMismatch()
        exercise.batchTransfer(recipients, amounts);
    }

    function test_BatchTransfer_insufficientBalanceReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2000000; // more than owner's 1,000,000

        vm.expectRevert(abi.encodeWithSelector(bytes4(0xf4d678b8))); // InsufficientBalance()
        exercise.batchTransfer(recipients, amounts);
    }

    function test_BatchTransfer_emptyArrays() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        uint256 balBefore = exercise.balanceOf(owner);
        exercise.batchTransfer(recipients, amounts);
        assertEq(exercise.balanceOf(owner), balBefore, "Empty batch should not change balance");
    }
}

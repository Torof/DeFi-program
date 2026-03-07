// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for SoladyTricks.
/// Your task is to implement the contract in SoladyTricks.sol so all tests pass.

import "forge-std/Test.sol";
import {SoladyTricks} from "../../../../src/part4/module6/exercise2-solady-tricks/SoladyTricks.sol";
import {OptimizedToken} from "../../../../src/part4/module6/mocks/OptimizedToken.sol";
import {MockNoReturnToken} from "../../../../src/part4/module5/mocks/MockNoReturnToken.sol"; // USDT-style (M5 mock)

contract SoladyTricksTest is Test {
    SoladyTricks internal tricks;
    OptimizedToken internal token;
    MockNoReturnToken internal noReturnToken;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        tricks = new SoladyTricks();
        token = new OptimizedToken();
        noReturnToken = new MockNoReturnToken();

        // Fund the tricks contract for multi-transfer tests.
        token.transfer(address(tricks), 1_000_000 ether);
        noReturnToken.transfer(address(tricks), 1_000_000 ether);
    }

    // =========================================================================
    // TODO 1: branchlessMin
    // =========================================================================

    function test_BranchlessMin_aLessThanB() public view {
        assertEq(tricks.branchlessMin(3, 7), 3, "min(3, 7) should be 3");
    }

    function test_BranchlessMin_aGreaterThanB() public view {
        assertEq(tricks.branchlessMin(7, 3), 3, "min(7, 3) should be 3");
    }

    function test_BranchlessMin_equal() public view {
        assertEq(tricks.branchlessMin(5, 5), 5, "min(5, 5) should be 5");
    }

    function test_BranchlessMin_zeroAndNonZero() public view {
        assertEq(tricks.branchlessMin(0, 42), 0, "min(0, 42) should be 0");
        assertEq(tricks.branchlessMin(42, 0), 0, "min(42, 0) should be 0");
    }

    function test_BranchlessMin_maxValue() public view {
        assertEq(
            tricks.branchlessMin(type(uint256).max, 1),
            1,
            "min(MAX, 1) should be 1"
        );
        assertEq(
            tricks.branchlessMin(1, type(uint256).max),
            1,
            "min(1, MAX) should be 1"
        );
    }

    function testFuzz_BranchlessMin_matchesSolidity(uint256 a, uint256 b) public view {
        uint256 expected = a < b ? a : b;
        assertEq(tricks.branchlessMin(a, b), expected, "Branchless min should match Solidity");
    }

    // =========================================================================
    // TODO 2: branchlessMax
    // =========================================================================

    function test_BranchlessMax_aLessThanB() public view {
        assertEq(tricks.branchlessMax(3, 7), 7, "max(3, 7) should be 7");
    }

    function test_BranchlessMax_aGreaterThanB() public view {
        assertEq(tricks.branchlessMax(7, 3), 7, "max(7, 3) should be 7");
    }

    function test_BranchlessMax_equal() public view {
        assertEq(tricks.branchlessMax(5, 5), 5, "max(5, 5) should be 5");
    }

    function test_BranchlessMax_zeroAndNonZero() public view {
        assertEq(tricks.branchlessMax(0, 42), 42, "max(0, 42) should be 42");
        assertEq(tricks.branchlessMax(42, 0), 42, "max(42, 0) should be 42");
    }

    function test_BranchlessMax_maxValue() public view {
        assertEq(
            tricks.branchlessMax(type(uint256).max, 1),
            type(uint256).max,
            "max(MAX, 1) should be MAX"
        );
    }

    function testFuzz_BranchlessMax_matchesSolidity(uint256 a, uint256 b) public view {
        uint256 expected = a > b ? a : b;
        assertEq(tricks.branchlessMax(a, b), expected, "Branchless max should match Solidity");
    }

    // =========================================================================
    // TODO 3: branchlessAbs
    // =========================================================================

    function test_BranchlessAbs_positive() public view {
        assertEq(tricks.branchlessAbs(5), 5, "abs(5) should be 5");
    }

    function test_BranchlessAbs_negative() public view {
        assertEq(tricks.branchlessAbs(-5), 5, "abs(-5) should be 5");
    }

    function test_BranchlessAbs_zero() public view {
        assertEq(tricks.branchlessAbs(0), 0, "abs(0) should be 0");
    }

    function test_BranchlessAbs_one() public view {
        assertEq(tricks.branchlessAbs(1), 1, "abs(1) should be 1");
        assertEq(tricks.branchlessAbs(-1), 1, "abs(-1) should be 1");
    }

    function test_BranchlessAbs_maxPositive() public view {
        assertEq(
            tricks.branchlessAbs(type(int256).max),
            uint256(type(int256).max),
            "abs(INT256_MAX) should be INT256_MAX"
        );
    }

    function test_BranchlessAbs_minNegative() public view {
        // abs(type(int256).min) = 2^255 (overflows int256 but fits uint256)
        // type(int256).min = -2^255
        // The branchless formula produces: xor(add(-2^255, -1), -1) = 2^255
        assertEq(
            tricks.branchlessAbs(type(int256).min),
            uint256(type(int256).max) + 1,
            "abs(INT256_MIN) should be 2^255"
        );
    }

    function testFuzz_BranchlessAbs_matchesSolidity(int256 x) public view {
        uint256 expected;
        if (x == type(int256).min) {
            expected = uint256(type(int256).max) + 1;
        } else {
            expected = x >= 0 ? uint256(x) : uint256(-x);
        }
        assertEq(tricks.branchlessAbs(x), expected, "Branchless abs should match Solidity");
    }

    // =========================================================================
    // TODO 4: efficientMultiTransfer
    // =========================================================================

    function test_MultiTransfer_singleRecipient() public {
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        to[0] = alice;
        amounts[0] = 100;

        tricks.efficientMultiTransfer(address(token), to, amounts);

        assertEq(token.balanceOf(alice), 100, "Alice should receive 100 tokens");
    }

    function test_MultiTransfer_multipleRecipients() public {
        address[] memory to = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        to[0] = alice;     amounts[0] = 100;
        to[1] = bob;       amounts[1] = 200;
        to[2] = carol;     amounts[2] = 300;

        tricks.efficientMultiTransfer(address(token), to, amounts);

        assertEq(token.balanceOf(alice), 100, "Alice should receive 100");
        assertEq(token.balanceOf(bob), 200, "Bob should receive 200");
        assertEq(token.balanceOf(carol), 300, "Carol should receive 300");
    }

    function test_MultiTransfer_worksWithNoReturnToken() public {
        // USDT-style token that returns nothing on success.
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = alice;   amounts[0] = 50;
        to[1] = bob;     amounts[1] = 75;

        tricks.efficientMultiTransfer(address(noReturnToken), to, amounts);

        assertEq(noReturnToken.balanceOf(alice), 50, "Alice should receive 50 (no-return token)");
        assertEq(noReturnToken.balanceOf(bob), 75, "Bob should receive 75 (no-return token)");
    }

    function test_MultiTransfer_emptyArrays() public {
        address[] memory to = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        // Should succeed without doing anything.
        tricks.efficientMultiTransfer(address(token), to, amounts);
    }

    function test_MultiTransfer_revertsOnLengthMismatch() public {
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](3);
        to[0] = alice;      amounts[0] = 100;
        to[1] = bob;        amounts[1] = 200;
                             amounts[2] = 300;

        vm.expectRevert(abi.encodeWithSelector(bytes4(0xff633a38))); // LengthMismatch()
        tricks.efficientMultiTransfer(address(token), to, amounts);
    }

    function test_MultiTransfer_revertsOnFailedTransfer() public {
        // Transfer more tokens than the tricks contract holds → token reverts → TransferFailed()
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        to[0] = alice;
        amounts[0] = 2_000_000 ether; // tricks only holds 1M

        vm.expectRevert(abi.encodeWithSelector(bytes4(0x90b8ec18))); // TransferFailed()
        tricks.efficientMultiTransfer(address(token), to, amounts);
    }
}

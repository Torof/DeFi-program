// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {YulBasics} from
    "../../../../src/part4/module1/exercise1-yul-basics/YulBasics.sol";

/// @notice Tests for the YulBasics exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module1/exercise1-yul-basics/YulBasics.sol instead.
contract YulBasicsTest is Test {
    YulBasics internal basics;

    function setUp() public {
        basics = new YulBasics();
    }

    // =========================================================================
    // TODO 1: addNumbers
    // =========================================================================

    function test_AddNumbers_BasicAddition() public view {
        assertEq(basics.addNumbers(3, 5), 8, "3 + 5 should equal 8");
    }

    function test_AddNumbers_Zero() public view {
        assertEq(basics.addNumbers(0, 0), 0, "0 + 0 should equal 0");
        assertEq(basics.addNumbers(42, 0), 42, "42 + 0 should equal 42");
        assertEq(basics.addNumbers(0, 42), 42, "0 + 42 should equal 42");
    }

    function test_AddNumbers_WrapsOnOverflow() public view {
        // Assembly add wraps — no revert on overflow
        uint256 maxVal = type(uint256).max;
        assertEq(basics.addNumbers(maxVal, 1), 0, "uint256.max + 1 should wrap to 0");
        assertEq(basics.addNumbers(maxVal, 2), 1, "uint256.max + 2 should wrap to 1");
    }

    function testFuzz_AddNumbers(uint128 a, uint128 b) public view {
        // Use uint128 to avoid overflow, verify correctness
        uint256 expected = uint256(a) + uint256(b);
        assertEq(basics.addNumbers(uint256(a), uint256(b)), expected);
    }

    // =========================================================================
    // TODO 2: max
    // =========================================================================

    function test_Max_BasicComparison() public view {
        assertEq(basics.max(3, 5), 5, "max(3, 5) should be 5");
        assertEq(basics.max(10, 2), 10, "max(10, 2) should be 10");
    }

    function test_Max_EqualValues() public view {
        assertEq(basics.max(7, 7), 7, "max(7, 7) should be 7");
        assertEq(basics.max(0, 0), 0, "max(0, 0) should be 0");
    }

    function test_Max_ExtremeValues() public view {
        uint256 maxVal = type(uint256).max;
        assertEq(basics.max(0, maxVal), maxVal, "max(0, uint256.max) should be uint256.max");
        assertEq(basics.max(maxVal, 0), maxVal, "max(uint256.max, 0) should be uint256.max");
    }

    function testFuzz_Max(uint256 a, uint256 b) public view {
        uint256 result = basics.max(a, b);
        assertTrue(result >= a && result >= b, "Result must be >= both inputs");
        assertTrue(result == a || result == b, "Result must be one of the inputs");
    }

    // =========================================================================
    // TODO 3: clamp
    // =========================================================================

    function test_Clamp_WithinRange() public view {
        assertEq(basics.clamp(5, 1, 10), 5, "5 is within [1, 10]");
        assertEq(basics.clamp(1, 1, 10), 1, "1 is the lower bound");
        assertEq(basics.clamp(10, 1, 10), 10, "10 is the upper bound");
    }

    function test_Clamp_BelowRange() public view {
        assertEq(basics.clamp(0, 5, 10), 5, "0 below [5, 10] should clamp to 5");
        assertEq(basics.clamp(3, 5, 10), 5, "3 below [5, 10] should clamp to 5");
    }

    function test_Clamp_AboveRange() public view {
        assertEq(basics.clamp(15, 5, 10), 10, "15 above [5, 10] should clamp to 10");
        assertEq(basics.clamp(100, 5, 10), 10, "100 above [5, 10] should clamp to 10");
    }

    function test_Clamp_SingleValueRange() public view {
        assertEq(basics.clamp(0, 5, 5), 5, "Below single-value range [5,5]");
        assertEq(basics.clamp(5, 5, 5), 5, "At single-value range [5,5]");
        assertEq(basics.clamp(10, 5, 5), 5, "Above single-value range [5,5]");
    }

    function test_Clamp_ZeroRange() public view {
        assertEq(basics.clamp(0, 0, 0), 0, "clamp(0, 0, 0) should be 0");
        assertEq(basics.clamp(1, 0, 0), 0, "Above zero range [0,0] should clamp to 0");
    }

    function testFuzz_Clamp(uint256 value, uint256 lo, uint256 hi) public view {
        // Ensure lo <= hi
        if (lo > hi) (lo, hi) = (hi, lo);

        uint256 result = basics.clamp(value, lo, hi);
        assertTrue(result >= lo, "Clamped result must be >= min");
        assertTrue(result <= hi, "Clamped result must be <= max");
    }

    // =========================================================================
    // TODO 4: getContext
    // =========================================================================

    function test_GetContext_Sender() public {
        address expectedSender = address(this);
        (address sender,,,) = basics.getContext();
        assertEq(sender, expectedSender, "sender should be the caller");
    }

    function test_GetContext_Value() public {
        deal(address(this), 10 ether);
        (, uint256 value,,) = basics.getContext{value: 1 ether}();
        assertEq(value, 1 ether, "value should be 1 ether");
    }

    function test_GetContext_Timestamp() public {
        vm.warp(1_700_000_000);
        (,, uint256 ts,) = basics.getContext();
        assertEq(ts, 1_700_000_000, "timestamp should match warped value");
    }

    function test_GetContext_ChainId() public {
        (, ,, uint256 chain) = basics.getContext();
        assertEq(chain, block.chainid, "chainid should match current chain");
    }

    function test_GetContext_ZeroValue() public {
        (, uint256 value,,) = basics.getContext{value: 0}();
        assertEq(value, 0, "value should be 0 when no ETH sent");
    }

    function test_GetContext_FromDifferentSender() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        (address sender,,,) = basics.getContext();
        assertEq(sender, alice, "caller() should return the pranked address");
    }

    // =========================================================================
    // TODO 5: extractSelector
    // =========================================================================

    function test_ExtractSelector_TransferSignature() public view {
        // transfer(address,uint256) selector = 0xa9059cbb
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(0xdead),
            100
        );
        bytes4 selector = basics.extractSelector(data);
        assertEq(selector, bytes4(0xa9059cbb), "Should extract transfer selector");
    }

    function test_ExtractSelector_ApproveSignature() public view {
        // approve(address,uint256) selector = 0x095ea7b3
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(0xdead),
            100
        );
        bytes4 selector = basics.extractSelector(data);
        assertEq(selector, bytes4(0x095ea7b3), "Should extract approve selector");
    }

    function test_ExtractSelector_MinimalData() public view {
        // Just 4 bytes — a bare selector with no arguments
        bytes memory data = hex"deadbeef";
        bytes4 selector = basics.extractSelector(data);
        assertEq(selector, bytes4(0xdeadbeef), "Should extract selector from 4 bytes");
    }

    function testFuzz_ExtractSelector(bytes4 expected) public view {
        // Build calldata with a known selector
        bytes memory data = abi.encodePacked(expected, uint256(42));
        bytes4 selector = basics.extractSelector(data);
        assertEq(selector, expected, "Should extract any 4-byte selector");
    }

    // Allow this contract to receive ETH for context tests
    receive() external payable {}
}

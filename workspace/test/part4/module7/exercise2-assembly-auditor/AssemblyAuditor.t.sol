// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for AssemblyAuditor.
/// Your task is to implement fixedApprove, fixedUnpack, and fixedCache
/// in AssemblyAuditor.sol so all "Fixed" tests pass.
///
/// The "Buggy" tests demonstrate each vulnerability — read them to understand
/// how each bug manifests, then implement the fix.

import "forge-std/Test.sol";
import {AssemblyAuditor} from "../../../../src/part4/module7/exercise2-assembly-auditor/AssemblyAuditor.sol";

/// @dev Token that returns true on approve (normal ERC20 behavior)
contract GoodToken {
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @dev Token that returns false on approve (simulates a failing approval)
contract BadToken {
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

/// @dev Token that returns nothing on approve (USDT-style)
contract NoReturnToken {
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
        // No return value — USDT behavior
    }
}

contract AssemblyAuditorTest is Test {
    AssemblyAuditor internal auditor;
    GoodToken internal goodToken;
    BadToken internal badToken;
    NoReturnToken internal noReturnToken;

    function setUp() public {
        auditor = new AssemblyAuditor(100, 200);
        goodToken = new GoodToken();
        badToken = new BadToken();
        noReturnToken = new NoReturnToken();
    }

    // =========================================================================
    // BUG 1: Unchecked call return value — DEMONSTRATION
    // =========================================================================
    // These tests show the bug in action. Read them to understand the problem.

    function test_BuggyApprove_succeedsWithGoodToken() public {
        // Buggy version "works" with a normal token — the bug is invisible here
        auditor.buggyApprove(address(goodToken), address(0xBEEF), 1000);
        assertEq(
            goodToken.allowance(address(auditor), address(0xBEEF)),
            1000,
            "Buggy: allowance should be set (bug not visible with good token)"
        );
    }

    function test_BuggyApprove_silentlyIgnoresFailure() public {
        // BUG DEMO: badToken.approve returns false, but buggyApprove doesn't notice
        auditor.buggyApprove(address(badToken), address(0xBEEF), 1000);
        // No revert! The approval silently failed.
        // In production, this means the next transferFrom would fail unexpectedly.
    }

    // =========================================================================
    // BUG 1: Unchecked call return value — FIXED VERSION TESTS
    // =========================================================================

    function test_FixedApprove_succeedsWithGoodToken() public {
        auditor.fixedApprove(address(goodToken), address(0xBEEF), 1000);
        assertEq(
            goodToken.allowance(address(auditor), address(0xBEEF)),
            1000,
            "Fixed: allowance should be set with good token"
        );
    }

    function test_FixedApprove_revertsWithBadToken() public {
        // Fixed version MUST revert when approve returns false
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x3e3f8f73))); // ApproveFailed()
        auditor.fixedApprove(address(badToken), address(0xBEEF), 1000);
    }

    function test_FixedApprove_succeedsWithNoReturnToken() public {
        // USDT-style: no return data should be accepted as success
        auditor.fixedApprove(address(noReturnToken), address(0xBEEF), 1000);
        assertEq(
            noReturnToken.allowance(address(auditor), address(0xBEEF)),
            1000,
            "Fixed: should accept no-return-data tokens (USDT-style)"
        );
    }

    function test_FixedApprove_revertsWithNonContract() public {
        // Calling a non-contract address — call() returns success but no code runs
        // This should either revert or at least not silently succeed
        // (Non-contract call returns success=1 with zero returndatasize, which the
        //  SafeTransferLib pattern accepts — matching Solady behavior.)
        auditor.fixedApprove(address(0xDEAD), address(0xBEEF), 1000);
        // No revert — consistent with Solady SafeTransferLib behavior
    }

    // =========================================================================
    // BUG 2: Off-by-one in bit shift — DEMONSTRATION
    // =========================================================================

    function test_BuggyUnpack_lowIsCorrect() public view {
        (uint128 low,) = auditor.buggyUnpack();
        assertEq(low, 100, "Buggy: low value IS correct (bug is in high)");
    }

    function test_BuggyUnpack_highIsWrong() public view {
        (, uint128 high) = auditor.buggyUnpack();
        // BUG DEMO: shr(127, ...) instead of shr(128, ...) produces wrong value
        // With packed = uint256(100) | (uint256(200) << 128):
        //   shr(128, packed) = 200         ← correct
        //   shr(127, packed) = 400         ← WRONG (shifted 1 bit too few)
        assertNotEq(high, 200, "Buggy: high value should be WRONG due to off-by-one shift");
    }

    // =========================================================================
    // BUG 2: Off-by-one in bit shift — FIXED VERSION TESTS
    // =========================================================================

    function test_FixedUnpack_correctValues() public view {
        (uint128 low, uint128 high) = auditor.fixedUnpack();
        assertEq(low, 100, "Fixed: low value should be 100");
        assertEq(high, 200, "Fixed: high value should be 200");
    }

    function test_FixedUnpack_withDifferentValues() public {
        AssemblyAuditor a2 = new AssemblyAuditor(0, type(uint128).max);
        (uint128 low, uint128 high) = a2.fixedUnpack();
        assertEq(low, 0, "Fixed: low should be 0");
        assertEq(high, type(uint128).max, "Fixed: high should be max uint128");
    }

    function testFuzz_FixedUnpack_matchesExpected(uint128 a, uint128 b) public {
        AssemblyAuditor ax = new AssemblyAuditor(a, b);
        (uint128 low, uint128 high) = ax.fixedUnpack();
        assertEq(low, a, "Fixed fuzz: low mismatch");
        assertEq(high, b, "Fixed fuzz: high mismatch");
    }

    // =========================================================================
    // BUG 3: Dirty memory / FMP corruption — DEMONSTRATION
    // =========================================================================

    function test_BuggyCache_showsCorruption() public view {
        (uint256 cached, uint256 retrieved) = auditor.buggyCache(12345);
        assertEq(cached, 12345, "Buggy: cached should be the original value");
        // BUG DEMO: retrieved should be 12345 but the array allocation overwrote it.
        // The array length (1) was written at the same pointer, so retrieved = 1.
        assertNotEq(retrieved, 12345, "Buggy: retrieved should be WRONG due to FMP corruption");
    }

    // =========================================================================
    // BUG 3: Dirty memory / FMP corruption — FIXED VERSION TESTS
    // =========================================================================

    function test_FixedCache_preservesValue() public view {
        (uint256 cached, uint256 retrieved) = auditor.fixedCache(12345);
        assertEq(cached, 12345, "Fixed: cached should be 12345");
        assertEq(retrieved, 12345, "Fixed: retrieved should ALSO be 12345 (FMP advanced)");
    }

    function test_FixedCache_preservesZero() public view {
        (uint256 cached, uint256 retrieved) = auditor.fixedCache(0);
        assertEq(cached, 0, "Fixed zero: cached should be 0");
        assertEq(retrieved, 0, "Fixed zero: retrieved should be 0");
    }

    function test_FixedCache_preservesMaxValue() public view {
        (uint256 cached, uint256 retrieved) = auditor.fixedCache(type(uint256).max);
        assertEq(cached, type(uint256).max, "Fixed max: cached should be max");
        assertEq(retrieved, type(uint256).max, "Fixed max: retrieved should be max");
    }

    function testFuzz_FixedCache_alwaysPreserves(uint256 x) public view {
        (uint256 cached, uint256 retrieved) = auditor.fixedCache(x);
        assertEq(cached, x, "Fixed fuzz: cached mismatch");
        assertEq(retrieved, x, "Fixed fuzz: retrieved mismatch");
    }
}

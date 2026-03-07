// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for AssemblyReader.
/// Your task is to implement solveA, solveB, and solveC in AssemblyReader.sol
/// so that they produce the same output as the corresponding mystery functions.

import "forge-std/Test.sol";
import {AssemblyReader} from "../../../../src/part4/module7/exercise1-assembly-reader/AssemblyReader.sol";

contract AssemblyReaderTest is Test {
    AssemblyReader internal reader;

    function setUp() public {
        reader = new AssemblyReader(42, 1337);
    }

    // =========================================================================
    // TODO 1: solveA — packed storage read
    // =========================================================================

    function test_SolveA_matchesMysteryA() public view {
        (uint128 asmLo, uint128 asmHi) = reader.mysteryA();
        (uint128 solLo, uint128 solHi) = reader.solveA();
        assertEq(solLo, asmLo, "solveA: low value should match mysteryA");
        assertEq(solHi, asmHi, "solveA: high value should match mysteryA");
    }

    function test_SolveA_correctValues() public view {
        (uint128 lo, uint128 hi) = reader.solveA();
        assertEq(lo, 42, "solveA: low value should be 42");
        assertEq(hi, 1337, "solveA: high value should be 1337");
    }

    function test_SolveA_withDifferentValues() public {
        AssemblyReader r2 = new AssemblyReader(0, type(uint128).max);
        (uint128 lo, uint128 hi) = r2.solveA();
        assertEq(lo, 0, "solveA: low should be 0");
        assertEq(hi, type(uint128).max, "solveA: high should be max uint128");
    }

    function testFuzz_SolveA_matchesMysteryA(uint128 a, uint128 b) public {
        AssemblyReader r = new AssemblyReader(a, b);
        (uint128 asmLo, uint128 asmHi) = r.mysteryA();
        (uint128 solLo, uint128 solHi) = r.solveA();
        assertEq(solLo, asmLo, "solveA fuzz: low value mismatch");
        assertEq(solHi, asmHi, "solveA fuzz: high value mismatch");
    }

    // =========================================================================
    // TODO 2: solveB — branchless clamp
    // =========================================================================

    function test_SolveB_valueInRange() public view {
        assertEq(
            reader.solveB(5, 3, 10),
            reader.mysteryB(5, 3, 10),
            "solveB: value in range should pass through"
        );
    }

    function test_SolveB_valueBelowRange() public view {
        assertEq(
            reader.solveB(1, 3, 10),
            reader.mysteryB(1, 3, 10),
            "solveB: value below range should clamp up"
        );
    }

    function test_SolveB_valueAboveRange() public view {
        assertEq(
            reader.solveB(15, 3, 10),
            reader.mysteryB(15, 3, 10),
            "solveB: value above range should clamp down"
        );
    }

    function test_SolveB_valueAtBoundaries() public view {
        assertEq(reader.solveB(3, 3, 10), reader.mysteryB(3, 3, 10), "solveB: at lower bound");
        assertEq(reader.solveB(10, 3, 10), reader.mysteryB(10, 3, 10), "solveB: at upper bound");
    }

    function test_SolveB_sameLoHi() public view {
        assertEq(reader.solveB(0, 5, 5), reader.mysteryB(0, 5, 5), "solveB: lo==hi, below");
        assertEq(reader.solveB(5, 5, 5), reader.mysteryB(5, 5, 5), "solveB: lo==hi, equal");
        assertEq(reader.solveB(10, 5, 5), reader.mysteryB(10, 5, 5), "solveB: lo==hi, above");
    }

    function test_SolveB_zeroRange() public view {
        assertEq(reader.solveB(0, 0, 0), reader.mysteryB(0, 0, 0), "solveB: all zeros");
    }

    function testFuzz_SolveB_matchesMysteryB(uint256 x, uint256 lo, uint256 hi) public view {
        // Ensure lo <= hi for a valid range
        if (lo > hi) (lo, hi) = (hi, lo);
        assertEq(
            reader.solveB(x, lo, hi),
            reader.mysteryB(x, lo, hi),
            "solveB fuzz: should match mysteryB"
        );
    }

    // =========================================================================
    // TODO 3: solveC — custom calldata decoding
    // =========================================================================

    function test_SolveC_basicDecode() public view {
        // Pack: address(0xABCD...) + uint128(1000) + uint64(block.timestamp)
        address addr = address(0xABCDabcdABcDabcDaBCDAbcdABcdAbCdABcDABCd);
        uint128 amount = 1000;
        uint64 deadline = 1700000000;

        bytes memory packed = abi.encodePacked(addr, amount, deadline);

        (address solAddr, uint128 solAmt, uint64 solDeadline) = reader.solveC(packed);
        (address asmAddr, uint128 asmAmt, uint64 asmDeadline) = reader.mysteryC(packed);

        assertEq(solAddr, asmAddr, "solveC: address mismatch");
        assertEq(solAmt, asmAmt, "solveC: amount mismatch");
        assertEq(solDeadline, asmDeadline, "solveC: deadline mismatch");
    }

    function test_SolveC_zeroValues() public view {
        bytes memory packed = abi.encodePacked(address(0), uint128(0), uint64(0));

        (address solAddr, uint128 solAmt, uint64 solDeadline) = reader.solveC(packed);
        (address asmAddr, uint128 asmAmt, uint64 asmDeadline) = reader.mysteryC(packed);

        assertEq(solAddr, asmAddr, "solveC zero: address mismatch");
        assertEq(solAmt, asmAmt, "solveC zero: amount mismatch");
        assertEq(solDeadline, asmDeadline, "solveC zero: deadline mismatch");
    }

    function test_SolveC_maxValues() public view {
        bytes memory packed = abi.encodePacked(
            address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF),
            type(uint128).max,
            type(uint64).max
        );

        (address solAddr, uint128 solAmt, uint64 solDeadline) = reader.solveC(packed);
        (address asmAddr, uint128 asmAmt, uint64 asmDeadline) = reader.mysteryC(packed);

        assertEq(solAddr, asmAddr, "solveC max: address mismatch");
        assertEq(solAmt, asmAmt, "solveC max: amount mismatch");
        assertEq(solDeadline, asmDeadline, "solveC max: deadline mismatch");
    }

    function testFuzz_SolveC_matchesMysteryC(address addr, uint128 amount, uint64 deadline) public view {
        bytes memory packed = abi.encodePacked(addr, amount, deadline);

        (address solAddr, uint128 solAmt, uint64 solDeadline) = reader.solveC(packed);
        (address asmAddr, uint128 asmAmt, uint64 asmDeadline) = reader.mysteryC(packed);

        assertEq(solAddr, asmAddr, "solveC fuzz: address mismatch");
        assertEq(solAmt, asmAmt, "solveC fuzz: amount mismatch");
        assertEq(solDeadline, asmDeadline, "solveC fuzz: deadline mismatch");
    }
}

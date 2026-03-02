// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MemoryLab} from
    "../../../../src/part4/module2/exercise1-memory-lab/MemoryLab.sol";

/// @notice Tests for the MemoryLab exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module2/exercise1-memory-lab/MemoryLab.sol instead.
contract MemoryLabTest is Test {
    MemoryLab internal lab;

    function setUp() public {
        lab = new MemoryLab();
    }

    // =========================================================================
    // TODO 1: Read Free Memory Pointer
    // =========================================================================

    function test_ReadFreeMemPtr_Returns0x80() public view {
        // Solidity initialises FMP to 0x80 at the start of every external call.
        // With no prior allocations, readFreeMemPtr should return 0x80.
        uint256 fmp = lab.readFreeMemPtr();
        assertEq(fmp, 0x80, "FMP should be 0x80 at start of call");
    }

    // =========================================================================
    // TODO 2: Allocate Memory
    // =========================================================================

    function test_Allocate_ReturnsOldPointer() public view {
        // allocate(64) should return 0x80 (the current FMP before bumping).
        uint256 ptr = lab.allocate(64);
        assertEq(ptr, 0x80, "allocate should return old FMP (0x80)");
    }

    function test_Allocate_BumpsFMP() public view {
        // Each external call resets memory, so we can't call allocate then
        // readFreeMemPtr in separate calls. Instead, allocateTwice() does two
        // sequential allocations *within one call* — if the FMP bump works,
        // the second pointer starts after the first allocation.
        (uint256 ptrA, uint256 ptrB) = lab.allocateTwice(64, 32);
        assertEq(ptrA, 0x80, "First allocation should start at 0x80");
        assertEq(ptrB, 0x80 + 64, "Second allocation should start after first (0x80 + 64 = 0xC0)");
    }

    function test_Allocate_ZeroSize() public view {
        // Allocating 0 bytes should still return the current FMP without error.
        uint256 ptr = lab.allocate(0);
        assertEq(ptr, 0x80, "Zero-size allocation should still return current FMP");
    }

    function testFuzz_Allocate_ReturnsConsistentPointer(uint256 size) public view {
        // For any size, allocate should return 0x80 (fresh call = fresh memory).
        size = bound(size, 0, 10_000); // keep reasonable
        uint256 ptr = lab.allocate(size);
        assertEq(ptr, 0x80, "allocate should always return 0x80 in a fresh call");
    }

    // =========================================================================
    // TODO 3: Write and Read
    // =========================================================================

    function test_WriteAndRead_RoundTrip() public view {
        uint256 result = lab.writeAndRead(42);
        assertEq(result, 42, "writeAndRead should return the value written");
    }

    function test_WriteAndRead_Zero() public view {
        uint256 result = lab.writeAndRead(0);
        assertEq(result, 0, "writeAndRead should handle zero");
    }

    function test_WriteAndRead_MaxUint() public view {
        uint256 result = lab.writeAndRead(type(uint256).max);
        assertEq(result, type(uint256).max, "writeAndRead should handle max uint256");
    }

    function testFuzz_WriteAndRead(uint256 value) public view {
        uint256 result = lab.writeAndRead(value);
        assertEq(result, value, "writeAndRead should round-trip any value");
    }

    // =========================================================================
    // TODO 4: Build bytes memory (uint256)
    // =========================================================================

    function test_BuildUint256Bytes_Length() public view {
        bytes memory data = lab.buildUint256Bytes(123);
        assertEq(data.length, 32, "buildUint256Bytes should return 32-byte blob");
    }

    function test_BuildUint256Bytes_Content() public view {
        bytes memory data = lab.buildUint256Bytes(0xDEAD);
        // The 32 bytes should be the big-endian encoding of 0xDEAD.
        uint256 decoded;
        assembly {
            decoded := mload(add(data, 0x20))
        }
        assertEq(decoded, 0xDEAD, "buildUint256Bytes data should encode the value");
    }

    function test_BuildUint256Bytes_Zero() public view {
        bytes memory data = lab.buildUint256Bytes(0);
        assertEq(data.length, 32, "Zero value should still be 32 bytes");
        uint256 decoded;
        assembly {
            decoded := mload(add(data, 0x20))
        }
        assertEq(decoded, 0, "Zero value should decode to 0");
    }

    function testFuzz_BuildUint256Bytes(uint256 val) public view {
        bytes memory data = lab.buildUint256Bytes(val);
        assertEq(data.length, 32, "Length should always be 32");
        uint256 decoded;
        assembly {
            decoded := mload(add(data, 0x20))
        }
        assertEq(decoded, val, "Decoded value should match input");
    }

    function test_BuildUint256Bytes_MatchesAbiEncode() public view {
        // abi.encode(uint256) produces the same 32-byte encoding.
        uint256 val = 999;
        bytes memory fromAssembly = lab.buildUint256Bytes(val);
        bytes memory fromAbi = abi.encode(val);
        assertEq(
            keccak256(fromAssembly),
            keccak256(fromAbi),
            "Assembly-built bytes should match abi.encode"
        );
    }

    // =========================================================================
    // TODO 5: Read Zero Slot
    // =========================================================================

    function test_ReadZeroSlot_IsZero() public view {
        uint256 result = lab.readZeroSlot();
        assertEq(result, 0, "Zero slot (0x60) should always be zero");
    }

    // =========================================================================
    // TODO 6: Hash Pair (scratch space)
    // =========================================================================

    function test_HashPair_KnownValues() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));
        bytes32 result = lab.hashPair(a, b);
        // Expected: keccak256(abi.encodePacked(a, b))
        bytes32 expected = keccak256(abi.encodePacked(a, b));
        assertEq(result, expected, "hashPair should match keccak256(a, b)");
    }

    function test_HashPair_OrderMatters() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));
        bytes32 hashAB = lab.hashPair(a, b);
        bytes32 hashBA = lab.hashPair(b, a);
        assertTrue(hashAB != hashBA, "hashPair(a,b) != hashPair(b,a) -- order matters");
    }

    function test_HashPair_ZeroInputs() public view {
        bytes32 result = lab.hashPair(bytes32(0), bytes32(0));
        bytes32 expected = keccak256(abi.encodePacked(bytes32(0), bytes32(0)));
        assertEq(result, expected, "hashPair should work with zero inputs");
    }

    function testFuzz_HashPair(bytes32 a, bytes32 b) public view {
        bytes32 result = lab.hashPair(a, b);
        bytes32 expected = keccak256(abi.encodePacked(a, b));
        assertEq(result, expected, "hashPair should match keccak256(abi.encodePacked(a,b))");
    }
}

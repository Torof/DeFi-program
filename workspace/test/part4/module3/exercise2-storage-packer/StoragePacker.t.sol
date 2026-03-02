// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StoragePacker} from
    "../../../../src/part4/module3/exercise2-storage-packer/StoragePacker.sol";

/// @notice Tests for the StoragePacker exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module3/exercise2-storage-packer/StoragePacker.sol instead.
contract StoragePackerTest is Test {
    StoragePacker internal packer;

    function setUp() public {
        packer = new StoragePacker();
    }

    // =========================================================================
    // TODO 1: Pack Two uint128 Values
    // =========================================================================

    function test_PackTwo_BasicValues() public {
        packer.packTwo(10, 20);
        uint256 raw = packer.packedSlot();
        // high=10 at bits 255-128, low=20 at bits 127-0
        uint256 expected = (uint256(10) << 128) | uint256(20);
        assertEq(raw, expected, "packedSlot should contain high=10, low=20");
    }

    function test_PackTwo_MaxValues() public {
        packer.packTwo(type(uint128).max, type(uint128).max);
        uint256 raw = packer.packedSlot();
        assertEq(raw, type(uint256).max, "Both max uint128 should fill all 256 bits");
    }

    function test_PackTwo_ZeroValues() public {
        packer.packTwo(0, 0);
        uint256 raw = packer.packedSlot();
        assertEq(raw, 0, "Packing zeros should produce zero");
    }

    function testFuzz_PackTwo(uint128 high, uint128 low) public {
        packer.packTwo(high, low);
        uint256 raw = packer.packedSlot();
        uint256 expected = (uint256(high) << 128) | uint256(low);
        assertEq(raw, expected, "Packed value should match expected bit layout");
    }

    // =========================================================================
    // TODO 2: Read Individual Packed Fields
    // =========================================================================

    function test_ReadLow_AfterPack() public {
        packer.packTwo(100, 200);
        uint128 low = packer.readLow();
        assertEq(low, 200, "readLow should return the low uint128");
    }

    function test_ReadHigh_AfterPack() public {
        packer.packTwo(100, 200);
        uint128 high = packer.readHigh();
        assertEq(high, 100, "readHigh should return the high uint128");
    }

    function test_ReadFields_MaxValues() public {
        packer.packTwo(type(uint128).max, type(uint128).max);
        assertEq(packer.readLow(), type(uint128).max, "readLow should handle max");
        assertEq(packer.readHigh(), type(uint128).max, "readHigh should handle max");
    }

    function testFuzz_ReadFields(uint128 high, uint128 low) public {
        packer.packTwo(high, low);
        assertEq(packer.readLow(), low, "readLow should match packed low value");
        assertEq(packer.readHigh(), high, "readHigh should match packed high value");
    }

    // =========================================================================
    // TODO 3: Update One Field Without Corrupting the Other
    // =========================================================================

    function test_UpdateLow_PreservesHigh() public {
        packer.packTwo(100, 200);
        packer.updateLow(999);
        assertEq(packer.readLow(), 999, "Low should be updated to 999");
        assertEq(packer.readHigh(), 100, "High should be preserved at 100");
    }

    function test_UpdateHigh_PreservesLow() public {
        packer.packTwo(100, 200);
        packer.updateHigh(888);
        assertEq(packer.readHigh(), 888, "High should be updated to 888");
        assertEq(packer.readLow(), 200, "Low should be preserved at 200");
    }

    function test_UpdateLow_ToZero() public {
        packer.packTwo(100, 200);
        packer.updateLow(0);
        assertEq(packer.readLow(), 0, "Low should be zeroed");
        assertEq(packer.readHigh(), 100, "High should be preserved");
    }

    function test_UpdateHigh_ToZero() public {
        packer.packTwo(100, 200);
        packer.updateHigh(0);
        assertEq(packer.readHigh(), 0, "High should be zeroed");
        assertEq(packer.readLow(), 200, "Low should be preserved");
    }

    function testFuzz_UpdateLow_PreservesHigh(uint128 high, uint128 low, uint128 newLow) public {
        packer.packTwo(high, low);
        packer.updateLow(newLow);
        assertEq(packer.readLow(), newLow, "Low should be updated to newLow");
        assertEq(packer.readHigh(), high, "High must be preserved after updateLow");
    }

    function testFuzz_UpdateHigh_PreservesLow(uint128 high, uint128 low, uint128 newHigh) public {
        packer.packTwo(high, low);
        packer.updateHigh(newHigh);
        assertEq(packer.readHigh(), newHigh, "High should be updated to newHigh");
        assertEq(packer.readLow(), low, "Low must be preserved after updateHigh");
    }

    // =========================================================================
    // TODO 4: Pack Address + uint96
    // =========================================================================

    function test_PackMixed_BasicValues() public {
        address addr = address(0xBEEF);
        uint96 val = 42;
        packer.packMixed(addr, val);
        assertEq(packer.readAddr(), addr, "readAddr should return the packed address");
        assertEq(packer.readUint96(), val, "readUint96 should return the packed uint96");
    }

    function test_PackMixed_FullAddress() public {
        address addr = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik.eth
        uint96 val = type(uint96).max;
        packer.packMixed(addr, val);
        assertEq(packer.readAddr(), addr, "Should handle full 20-byte address");
        assertEq(packer.readUint96(), val, "Should handle max uint96");
    }

    function test_PackMixed_ZeroAddress() public {
        packer.packMixed(address(0), 0);
        assertEq(packer.readAddr(), address(0), "Should handle zero address");
        assertEq(packer.readUint96(), 0, "Should handle zero uint96");
    }

    function testFuzz_PackMixed(address addr, uint96 val) public {
        packer.packMixed(addr, val);
        assertEq(packer.readAddr(), addr, "readAddr should match packed address");
        assertEq(packer.readUint96(), val, "readUint96 should match packed uint96");
    }

    // =========================================================================
    // TODO 5: Triple-Packed Slot (init + incrementCounter)
    // =========================================================================

    function test_InitTriple_PacksCorrectly() public {
        packer.initTriple(1, 2, 3);
        uint256 raw = packer.tripleSlot();
        uint256 expected = (uint256(1) << 192) | (uint256(2) << 128) | uint256(3);
        assertEq(raw, expected, "initTriple should pack counter=1, balance=2, data=3");
    }

    function test_IncrementCounter_Basic() public {
        packer.initTriple(5, 100, 999);
        packer.incrementCounter();
        uint256 raw = packer.tripleSlot();
        uint256 expected = (uint256(6) << 192) | (uint256(100) << 128) | uint256(999);
        assertEq(raw, expected, "Counter should be 6 after increment, balance and data unchanged");
    }

    function test_IncrementCounter_PreservesBalance() public {
        packer.initTriple(0, type(uint64).max, 0);
        packer.incrementCounter();
        uint256 raw = packer.tripleSlot();
        // Extract balance (bits 191-128)
        uint64 balance = uint64(raw >> 128);
        assertEq(balance, type(uint64).max, "Balance must be preserved after incrementCounter");
    }

    function test_IncrementCounter_PreservesData() public {
        packer.initTriple(0, 0, type(uint128).max);
        packer.incrementCounter();
        uint256 raw = packer.tripleSlot();
        // Extract data (bits 127-0)
        uint128 data = uint128(raw);
        assertEq(data, type(uint128).max, "Data must be preserved after incrementCounter");
    }

    function test_IncrementCounter_Twice() public {
        packer.initTriple(10, 50, 1000);
        packer.incrementCounter();
        packer.incrementCounter();
        uint256 raw = packer.tripleSlot();
        uint256 expected = (uint256(12) << 192) | (uint256(50) << 128) | uint256(1000);
        assertEq(raw, expected, "Counter should be 12 after two increments");
    }

    function testFuzz_IncrementCounter_PreservesFields(uint64 counter, uint64 balance, uint128 data) public {
        // Avoid overflow: counter must be less than max so increment doesn't wrap
        vm.assume(counter < type(uint64).max);
        packer.initTriple(counter, balance, data);
        packer.incrementCounter();
        uint256 raw = packer.tripleSlot();

        // Verify counter incremented
        uint64 newCounter = uint64(raw >> 192);
        assertEq(newCounter, counter + 1, "Counter should be incremented by 1");

        // Verify balance preserved
        uint64 newBalance = uint64(raw >> 128);
        assertEq(newBalance, balance, "Balance must be preserved");

        // Verify data preserved
        uint128 newData = uint128(raw);
        assertEq(newData, data, "Data must be preserved");
    }
}

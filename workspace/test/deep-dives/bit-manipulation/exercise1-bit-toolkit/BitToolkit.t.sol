// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {BitToolkit} from
    "../../../../src/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.sol";

/// @notice Tests for the BitToolkit exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/deep-dives/bit-manipulation/exercise1-bit-toolkit/BitToolkit.sol instead.
contract BitToolkitTest is Test {
    using BitToolkit for uint256;

    // =========================================================
    //  TODO 1: extractField
    // =========================================================

    function test_extractField_lowerByte() public pure {
        // Word: 0x00...00AABBCCDD
        // Extract bits 0-7 (lower byte) → 0xDD
        uint256 word = 0xAABBCCDD;
        uint256 result = BitToolkit.extractField(word, 0, 8);
        assertEq(result, 0xDD, "Lower 8 bits should be 0xDD");
    }

    function test_extractField_middleField() public pure {
        // Word: 0x00...00AABBCCDD
        // Extract bits 8-15 (second byte) → 0xCC
        uint256 word = 0xAABBCCDD;
        uint256 result = BitToolkit.extractField(word, 8, 8);
        assertEq(result, 0xCC, "Bits 8-15 should be 0xCC");
    }

    function test_extractField_upperHalf() public pure {
        // Pack two 128-bit values: upper = 42, lower = 99
        uint256 word = (uint256(42) << 128) | 99;
        uint256 upper = BitToolkit.extractField(word, 128, 128);
        uint256 lower = BitToolkit.extractField(word, 0, 128);
        assertEq(upper, 42, "Upper 128 bits should be 42");
        assertEq(lower, 99, "Lower 128 bits should be 99");
    }

    function test_extractField_singleBit() public pure {
        // Bit 5 is set in 0x20 (0b_0010_0000)
        uint256 word = 0x20;
        assertEq(BitToolkit.extractField(word, 5, 1), 1, "Bit 5 should be 1");
        assertEq(BitToolkit.extractField(word, 4, 1), 0, "Bit 4 should be 0");
        assertEq(BitToolkit.extractField(word, 6, 1), 0, "Bit 6 should be 0");
    }

    function testFuzz_extractField_roundTrip(uint256 value, uint8 rawOffset) public pure {
        // Constrain: offset 0-191, width 64 (so offset+width <= 255)
        uint256 offset = uint256(rawOffset) % 192;
        uint256 width = 64;
        uint256 masked = value & ((uint256(1) << width) - 1);

        // Pack the value at the offset
        uint256 word = masked << offset;

        // Extract it back
        uint256 extracted = BitToolkit.extractField(word, offset, width);
        assertEq(extracted, masked, "Extracted value should match packed value");
    }

    // =========================================================
    //  TODO 2: setField
    // =========================================================

    function test_setField_writeLowerByte() public pure {
        // Start with 0xAABBCCDD, set lower byte to 0xFF
        uint256 word = 0xAABBCCDD;
        uint256 result = BitToolkit.setField(word, 0, 8, 0xFF);
        assertEq(result, 0xAABBCCFF, "Lower byte should be 0xFF");
    }

    function test_setField_writeMiddleByte() public pure {
        // Start with 0xAABBCCDD, set byte at offset 8 to 0x11
        uint256 word = 0xAABBCCDD;
        uint256 result = BitToolkit.setField(word, 8, 8, 0x11);
        assertEq(result, 0xAABB11DD, "Middle byte should be 0x11");
    }

    function test_setField_preservesOtherBits() public pure {
        // Set bits 16-31 to 0xBEEF, verify everything else unchanged
        uint256 word = 0xDEAD0000CAFE;
        uint256 result = BitToolkit.setField(word, 16, 16, 0xBEEF);
        assertEq(result & 0xFFFF, 0xCAFE, "Lower 16 bits should be preserved");
        assertEq((result >> 32) & 0xFFFF, 0xDEAD, "Upper bits should be preserved");
        assertEq((result >> 16) & 0xFFFF, 0xBEEF, "Field should be 0xBEEF");
    }

    function test_setField_clearAndWrite() public pure {
        // Field already has a value — setField should overwrite completely
        uint256 word = 0xFF00;
        uint256 result = BitToolkit.setField(word, 8, 8, 0x42);
        assertEq(result, 0x4200, "Should overwrite existing field value");
    }

    function testFuzz_setField_roundTrip(uint256 original, uint256 value, uint8 rawOffset) public pure {
        uint256 offset = uint256(rawOffset) % 192;
        uint256 width = 64;
        uint256 masked = value & ((uint256(1) << width) - 1);

        // Set field, then extract — should get the value back
        uint256 updated = BitToolkit.setField(original, offset, width, masked);
        uint256 extracted = BitToolkit.extractField(updated, offset, width);
        assertEq(extracted, masked, "Set then extract should round-trip");
    }

    // =========================================================
    //  TODO 3-5: bitmapAdd / bitmapRemove / bitmapContains
    // =========================================================

    function test_bitmap_addAndContains() public pure {
        uint256 bitmap = 0;

        bitmap = BitToolkit.bitmapAdd(bitmap, 0);
        bitmap = BitToolkit.bitmapAdd(bitmap, 5);
        bitmap = BitToolkit.bitmapAdd(bitmap, 255);

        assertTrue(BitToolkit.bitmapContains(bitmap, 0), "Element 0 should be present");
        assertTrue(BitToolkit.bitmapContains(bitmap, 5), "Element 5 should be present");
        assertTrue(BitToolkit.bitmapContains(bitmap, 255), "Element 255 should be present");
        assertFalse(BitToolkit.bitmapContains(bitmap, 1), "Element 1 should be absent");
        assertFalse(BitToolkit.bitmapContains(bitmap, 254), "Element 254 should be absent");
    }

    function test_bitmap_addIsIdempotent() public pure {
        uint256 bitmap = 0;
        bitmap = BitToolkit.bitmapAdd(bitmap, 42);
        uint256 after1 = bitmap;
        bitmap = BitToolkit.bitmapAdd(bitmap, 42);
        assertEq(bitmap, after1, "Adding same element twice should not change bitmap");
    }

    function test_bitmap_remove() public pure {
        uint256 bitmap = 0;
        bitmap = BitToolkit.bitmapAdd(bitmap, 10);
        bitmap = BitToolkit.bitmapAdd(bitmap, 20);

        assertTrue(BitToolkit.bitmapContains(bitmap, 10), "10 should be present");
        assertTrue(BitToolkit.bitmapContains(bitmap, 20), "20 should be present");

        bitmap = BitToolkit.bitmapRemove(bitmap, 10);
        assertFalse(BitToolkit.bitmapContains(bitmap, 10), "10 should be removed");
        assertTrue(BitToolkit.bitmapContains(bitmap, 20), "20 should still be present");
    }

    function test_bitmap_removeFromEmpty() public pure {
        uint256 bitmap = 0;
        bitmap = BitToolkit.bitmapRemove(bitmap, 42);
        assertEq(bitmap, 0, "Removing from empty bitmap should stay empty");
    }

    function test_bitmap_containsOnEmpty() public pure {
        assertFalse(BitToolkit.bitmapContains(0, 0), "Empty bitmap should contain nothing");
        assertFalse(BitToolkit.bitmapContains(0, 128), "Empty bitmap should contain nothing");
    }

    function testFuzz_bitmap_addRemoveRoundTrip(uint256 bitmap, uint8 index) public pure {
        uint256 added = BitToolkit.bitmapAdd(bitmap, index);
        assertTrue(BitToolkit.bitmapContains(added, index), "Element should be present after add");

        uint256 removed = BitToolkit.bitmapRemove(added, index);
        assertFalse(BitToolkit.bitmapContains(removed, index), "Element should be absent after remove");
    }

    // =========================================================
    //  TODO 6: popcount
    // =========================================================

    function test_popcount_zero() public pure {
        assertEq(BitToolkit.popcount(0), 0, "Zero has no set bits");
    }

    function test_popcount_one() public pure {
        assertEq(BitToolkit.popcount(1), 1, "1 has one set bit");
    }

    function test_popcount_allOnes() public pure {
        assertEq(BitToolkit.popcount(type(uint256).max), 256, "All bits set = 256");
    }

    function test_popcount_powersOfTwo() public pure {
        assertEq(BitToolkit.popcount(1 << 0), 1, "2^0 has 1 bit");
        assertEq(BitToolkit.popcount(1 << 127), 1, "2^127 has 1 bit");
        assertEq(BitToolkit.popcount(1 << 255), 1, "2^255 has 1 bit");
    }

    function test_popcount_knownValues() public pure {
        // 0xFF = 8 bits set
        assertEq(BitToolkit.popcount(0xFF), 8, "0xFF has 8 set bits");

        // 0xAAAA = 1010_1010_1010_1010 = 8 bits set
        assertEq(BitToolkit.popcount(0xAAAA), 8, "0xAAAA has 8 set bits");

        // 0x0F0F = 0000_1111_0000_1111 = 8 bits set
        assertEq(BitToolkit.popcount(0x0F0F), 8, "0x0F0F has 8 set bits");
    }

    function test_popcount_scattered() public pure {
        // bits at positions 0, 100, 200, 255 = 4 bits
        uint256 x = (uint256(1) << 0) | (uint256(1) << 100) | (uint256(1) << 200) | (uint256(1) << 255);
        assertEq(BitToolkit.popcount(x), 4, "Four scattered bits");
    }

    // =========================================================
    //  TODO 7: isolateLSB
    // =========================================================

    function test_isolateLSB_zero() public pure {
        assertEq(BitToolkit.isolateLSB(0), 0, "LSB of zero is zero");
    }

    function test_isolateLSB_one() public pure {
        assertEq(BitToolkit.isolateLSB(1), 1, "LSB of 1 is 1");
    }

    function test_isolateLSB_powerOfTwo() public pure {
        // A power of 2 is its own LSB
        assertEq(BitToolkit.isolateLSB(1 << 128), 1 << 128, "2^128 is its own LSB");
    }

    function test_isolateLSB_multipleSetBits() public pure {
        // 0b_1010_1100 = 0xAC → lowest set bit at position 2 → 0x04
        assertEq(BitToolkit.isolateLSB(0xAC), 0x04, "LSB of 0xAC should be 0x04");
    }

    function test_isolateLSB_highBit() public pure {
        // Only bit 255 set
        uint256 x = uint256(1) << 255;
        assertEq(BitToolkit.isolateLSB(x), x, "Single high bit is its own LSB");
    }

    function testFuzz_isolateLSB_isPowerOfTwo(uint256 x) public pure {
        vm.assume(x != 0);
        uint256 lsb = BitToolkit.isolateLSB(x);
        // Result should be a power of 2
        assertTrue(lsb != 0 && (lsb & (lsb - 1)) == 0, "Isolated LSB should be a power of 2");
        // Result should be a subset of x
        assertEq(lsb & x, lsb, "LSB should be a bit that was set in x");
    }

    // =========================================================
    //  TODO 8: isPowerOfTwo
    // =========================================================

    function test_isPowerOfTwo_zero() public pure {
        assertFalse(BitToolkit.isPowerOfTwo(0), "Zero is not a power of 2");
    }

    function test_isPowerOfTwo_one() public pure {
        assertTrue(BitToolkit.isPowerOfTwo(1), "1 = 2^0 is a power of 2");
    }

    function test_isPowerOfTwo_knownPowers() public pure {
        assertTrue(BitToolkit.isPowerOfTwo(2), "2 is a power of 2");
        assertTrue(BitToolkit.isPowerOfTwo(4), "4 is a power of 2");
        assertTrue(BitToolkit.isPowerOfTwo(256), "256 is a power of 2");
        assertTrue(BitToolkit.isPowerOfTwo(1 << 128), "2^128 is a power of 2");
        assertTrue(BitToolkit.isPowerOfTwo(1 << 255), "2^255 is a power of 2");
    }

    function test_isPowerOfTwo_notPowers() public pure {
        assertFalse(BitToolkit.isPowerOfTwo(3), "3 is not a power of 2");
        assertFalse(BitToolkit.isPowerOfTwo(6), "6 is not a power of 2");
        assertFalse(BitToolkit.isPowerOfTwo(255), "255 is not a power of 2");
        assertFalse(BitToolkit.isPowerOfTwo(type(uint256).max), "Max uint is not a power of 2");
    }

    function testFuzz_isPowerOfTwo_singleBit(uint8 bit) public pure {
        uint256 x = uint256(1) << bit;
        assertTrue(BitToolkit.isPowerOfTwo(x), "Any single bit should be a power of 2");
    }

    function testFuzz_isPowerOfTwo_twoBits(uint8 bit1, uint8 bit2) public pure {
        vm.assume(bit1 != bit2);
        uint256 x = (uint256(1) << bit1) | (uint256(1) << bit2);
        assertFalse(BitToolkit.isPowerOfTwo(x), "Two set bits is not a power of 2");
    }

    // =========================================================
    //  TODO 9: branchlessSelect
    // =========================================================

    function test_branchlessSelect_selectA() public pure {
        uint256 result = BitToolkit.branchlessSelect(true, 42, 99);
        assertEq(result, 42, "true should select a");
    }

    function test_branchlessSelect_selectB() public pure {
        uint256 result = BitToolkit.branchlessSelect(false, 42, 99);
        assertEq(result, 99, "false should select b");
    }

    function test_branchlessSelect_sameValue() public pure {
        uint256 result = BitToolkit.branchlessSelect(true, 7, 7);
        assertEq(result, 7, "Same value should return that value regardless of condition");
        result = BitToolkit.branchlessSelect(false, 7, 7);
        assertEq(result, 7, "Same value should return that value regardless of condition");
    }

    function test_branchlessSelect_extremeValues() public pure {
        uint256 result = BitToolkit.branchlessSelect(true, type(uint256).max, 0);
        assertEq(result, type(uint256).max, "Should handle max uint");
        result = BitToolkit.branchlessSelect(false, type(uint256).max, 0);
        assertEq(result, 0, "Should handle zero");
    }

    function testFuzz_branchlessSelect(bool condition, uint256 a, uint256 b) public pure {
        uint256 result = BitToolkit.branchlessSelect(condition, a, b);
        uint256 expected = condition ? a : b;
        assertEq(result, expected, "Should match ternary operator");
    }

    // =========================================================
    //  Integration: combine multiple operations
    // =========================================================

    function test_integration_packExtractMultipleFields() public pure {
        // Pack 4 fields: [uint64 D | uint64 C | uint64 B | uint64 A]
        uint256 word = 0;
        word = BitToolkit.setField(word, 0, 64, 111);
        word = BitToolkit.setField(word, 64, 64, 222);
        word = BitToolkit.setField(word, 128, 64, 333);
        word = BitToolkit.setField(word, 192, 64, 444);

        assertEq(BitToolkit.extractField(word, 0, 64), 111, "Field A");
        assertEq(BitToolkit.extractField(word, 64, 64), 222, "Field B");
        assertEq(BitToolkit.extractField(word, 128, 64), 333, "Field C");
        assertEq(BitToolkit.extractField(word, 192, 64), 444, "Field D");
    }

    function test_integration_bitmapPopcount() public pure {
        uint256 bitmap = 0;
        bitmap = BitToolkit.bitmapAdd(bitmap, 1);
        bitmap = BitToolkit.bitmapAdd(bitmap, 50);
        bitmap = BitToolkit.bitmapAdd(bitmap, 100);
        bitmap = BitToolkit.bitmapAdd(bitmap, 200);
        bitmap = BitToolkit.bitmapAdd(bitmap, 255);

        assertEq(BitToolkit.popcount(bitmap), 5, "5 elements added = 5 bits set");

        bitmap = BitToolkit.bitmapRemove(bitmap, 100);
        assertEq(BitToolkit.popcount(bitmap), 4, "After removing 1 element = 4 bits set");
    }

    function test_integration_isolateLSBAndPopcount() public pure {
        uint256 x = 0xAC; // 0b_1010_1100 → bits at positions 2, 3, 5, 7
        assertEq(BitToolkit.popcount(x), 4, "0xAC has 4 set bits");

        uint256 lsb = BitToolkit.isolateLSB(x);
        assertEq(lsb, 4, "Lowest set bit of 0xAC is at position 2 (value 4)");
        assertTrue(BitToolkit.isPowerOfTwo(lsb), "Isolated LSB should be a power of 2");
    }
}

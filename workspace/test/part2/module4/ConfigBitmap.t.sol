// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE -- it is the test suite for the ConfigBitmap
//  exercise. Implement ConfigBitmap.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {ConfigBitmap} from "../../../src/part2/module4/ConfigBitmap.sol";

/// @notice Wrapper to expose internal library functions for testing.
contract ConfigBitmapWrapper {
    function setLtv(uint256 bitmap, uint256 ltv) external pure returns (uint256) {
        return ConfigBitmap.setLtv(bitmap, ltv);
    }

    function getLtv(uint256 bitmap) external pure returns (uint256) {
        return ConfigBitmap.getLtv(bitmap);
    }

    function setLiquidationThreshold(uint256 bitmap, uint256 threshold) external pure returns (uint256) {
        return ConfigBitmap.setLiquidationThreshold(bitmap, threshold);
    }

    function getLiquidationThreshold(uint256 bitmap) external pure returns (uint256) {
        return ConfigBitmap.getLiquidationThreshold(bitmap);
    }

    function setLiquidationBonus(uint256 bitmap, uint256 bonus) external pure returns (uint256) {
        return ConfigBitmap.setLiquidationBonus(bitmap, bonus);
    }

    function getLiquidationBonus(uint256 bitmap) external pure returns (uint256) {
        return ConfigBitmap.getLiquidationBonus(bitmap);
    }

    function setDecimals(uint256 bitmap, uint256 decimals) external pure returns (uint256) {
        return ConfigBitmap.setDecimals(bitmap, decimals);
    }

    function getDecimals(uint256 bitmap) external pure returns (uint256) {
        return ConfigBitmap.getDecimals(bitmap);
    }

    function setFlag(uint256 bitmap, uint256 bitPosition, bool value) external pure returns (uint256) {
        return ConfigBitmap.setFlag(bitmap, bitPosition, value);
    }

    function getFlag(uint256 bitmap, uint256 bitPosition) external pure returns (bool) {
        return ConfigBitmap.getFlag(bitmap, bitPosition);
    }
}

contract ConfigBitmapTest is Test {
    ConfigBitmapWrapper wrapper;

    function setUp() public {
        wrapper = new ConfigBitmapWrapper();
    }

    // =========================================================
    //  LTV (bits 0-15)
    // =========================================================

    function test_SetGetLtv_Basic() public view {
        uint256 bitmap = wrapper.setLtv(0, 8000); // 80%
        assertEq(wrapper.getLtv(bitmap), 8000, "LTV should be 8000");
    }

    function test_SetGetLtv_Max() public view {
        uint256 bitmap = wrapper.setLtv(0, 65535); // Max 16-bit value
        assertEq(wrapper.getLtv(bitmap), 65535, "LTV should support max uint16 value");
    }

    function test_SetGetLtv_Zero() public view {
        // Set then clear
        uint256 bitmap = wrapper.setLtv(0, 8000);
        bitmap = wrapper.setLtv(bitmap, 0);
        assertEq(wrapper.getLtv(bitmap), 0, "LTV should be clearable to 0");
    }

    // =========================================================
    //  Liquidation Threshold (bits 16-31)
    // =========================================================

    function test_SetGetLiqThreshold_Basic() public view {
        uint256 bitmap = wrapper.setLiquidationThreshold(0, 8250); // 82.5%
        assertEq(wrapper.getLiquidationThreshold(bitmap), 8250, "LiqThreshold should be 8250");
    }

    function test_SetGetLiqThreshold_Max() public view {
        uint256 bitmap = wrapper.setLiquidationThreshold(0, 65535);
        assertEq(wrapper.getLiquidationThreshold(bitmap), 65535, "LiqThreshold should support max uint16");
    }

    // =========================================================
    //  Flags (single bits)
    // =========================================================

    function test_SetGetFlag_Active() public view {
        uint256 bitmap = wrapper.setFlag(0, 56, true);
        assertTrue(wrapper.getFlag(bitmap, 56), "Active flag should be true");
        assertFalse(wrapper.getFlag(bitmap, 57), "Frozen flag should still be false");
    }

    function test_SetGetFlag_Frozen() public view {
        uint256 bitmap = wrapper.setFlag(0, 57, true);
        assertTrue(wrapper.getFlag(bitmap, 57), "Frozen flag should be true");
    }

    function test_SetGetFlag_BorrowEnabled() public view {
        uint256 bitmap = wrapper.setFlag(0, 58, true);
        assertTrue(wrapper.getFlag(bitmap, 58), "Borrow enabled flag should be true");
    }

    function test_SetGetFlag_ClearFlag() public view {
        uint256 bitmap = wrapper.setFlag(0, 56, true);
        bitmap = wrapper.setFlag(bitmap, 56, false);
        assertFalse(wrapper.getFlag(bitmap, 56), "Flag should be clearable");
    }

    // =========================================================
    //  Field Independence (the whole point of packing!)
    // =========================================================

    function test_FieldIndependence_SetLtvDoesNotCorruptThreshold() public view {
        // Set threshold first, then set LTV — threshold should be unchanged
        uint256 bitmap = wrapper.setLiquidationThreshold(0, 8250);
        bitmap = wrapper.setLtv(bitmap, 7700);

        assertEq(wrapper.getLtv(bitmap), 7700, "LTV should be 7700");
        assertEq(wrapper.getLiquidationThreshold(bitmap), 8250, "LiqThreshold should still be 8250");
    }

    function test_FieldIndependence_FlagDoesNotCorruptFields() public view {
        uint256 bitmap = wrapper.setLtv(0, 8000);
        bitmap = wrapper.setLiquidationThreshold(bitmap, 8250);
        bitmap = wrapper.setFlag(bitmap, 56, true); // Active flag

        assertEq(wrapper.getLtv(bitmap), 8000, "LTV should be preserved");
        assertEq(wrapper.getLiquidationThreshold(bitmap), 8250, "LiqThreshold should be preserved");
        assertTrue(wrapper.getFlag(bitmap, 56), "Active flag should be set");
    }

    // =========================================================
    //  Full Roundtrip (all fields at once)
    // =========================================================

    function test_Roundtrip_AllFields() public view {
        uint256 bitmap = 0;

        // Set every field
        bitmap = wrapper.setLtv(bitmap, 7700);                     // 77%
        bitmap = wrapper.setLiquidationThreshold(bitmap, 8000);    // 80%
        bitmap = wrapper.setLiquidationBonus(bitmap, 10450);       // 104.5%
        bitmap = wrapper.setDecimals(bitmap, 6);                   // USDC
        bitmap = wrapper.setFlag(bitmap, 56, true);                // Active
        bitmap = wrapper.setFlag(bitmap, 57, false);               // Not frozen
        bitmap = wrapper.setFlag(bitmap, 58, true);                // Borrow enabled

        // Read back every field — nothing should be corrupted
        assertEq(wrapper.getLtv(bitmap), 7700, "LTV roundtrip");
        assertEq(wrapper.getLiquidationThreshold(bitmap), 8000, "LiqThreshold roundtrip");
        assertEq(wrapper.getLiquidationBonus(bitmap), 10450, "LiqBonus roundtrip");
        assertEq(wrapper.getDecimals(bitmap), 6, "Decimals roundtrip");
        assertTrue(wrapper.getFlag(bitmap, 56), "Active flag roundtrip");
        assertFalse(wrapper.getFlag(bitmap, 57), "Frozen flag roundtrip");
        assertTrue(wrapper.getFlag(bitmap, 58), "Borrow enabled flag roundtrip");
    }

    // =========================================================
    //  Real-World Configs
    // =========================================================

    function test_RealWorldConfig_USDC() public view {
        // Aave V3 USDC config (approximate)
        uint256 bitmap = 0;
        bitmap = wrapper.setLtv(bitmap, 7700);
        bitmap = wrapper.setLiquidationThreshold(bitmap, 8000);
        bitmap = wrapper.setLiquidationBonus(bitmap, 10450);
        bitmap = wrapper.setDecimals(bitmap, 6);
        bitmap = wrapper.setFlag(bitmap, 56, true);  // Active
        bitmap = wrapper.setFlag(bitmap, 58, true);  // Borrow enabled

        assertEq(wrapper.getLtv(bitmap), 7700, "USDC LTV");
        assertEq(wrapper.getDecimals(bitmap), 6, "USDC decimals");
        assertTrue(wrapper.getFlag(bitmap, 56), "USDC active");
    }

    function test_RealWorldConfig_ETH() public view {
        // Aave V3 WETH config (approximate)
        uint256 bitmap = 0;
        bitmap = wrapper.setLtv(bitmap, 8050);
        bitmap = wrapper.setLiquidationThreshold(bitmap, 8250);
        bitmap = wrapper.setLiquidationBonus(bitmap, 10500);
        bitmap = wrapper.setDecimals(bitmap, 18);
        bitmap = wrapper.setFlag(bitmap, 56, true);  // Active
        bitmap = wrapper.setFlag(bitmap, 58, true);  // Borrow enabled

        assertEq(wrapper.getLtv(bitmap), 8050, "WETH LTV");
        assertEq(wrapper.getLiquidationThreshold(bitmap), 8250, "WETH LiqThreshold");
        assertEq(wrapper.getLiquidationBonus(bitmap), 10500, "WETH LiqBonus");
        assertEq(wrapper.getDecimals(bitmap), 18, "WETH decimals");
    }

    // =========================================================
    //  Fuzz
    // =========================================================

    function testFuzz_SetGetLtv_Roundtrip(uint16 ltv) public view {
        uint256 bitmap = wrapper.setLtv(0, uint256(ltv));
        assertEq(wrapper.getLtv(bitmap), uint256(ltv), "Fuzz: LTV set/get should roundtrip");
    }

    function testFuzz_SetGetLiqThreshold_Roundtrip(uint16 threshold) public view {
        uint256 bitmap = wrapper.setLiquidationThreshold(0, uint256(threshold));
        assertEq(
            wrapper.getLiquidationThreshold(bitmap),
            uint256(threshold),
            "Fuzz: LiqThreshold set/get should roundtrip"
        );
    }

    function testFuzz_FieldIndependence(uint16 ltv, uint16 threshold, uint16 bonus) public view {
        uint256 bitmap = 0;
        bitmap = wrapper.setLtv(bitmap, uint256(ltv));
        bitmap = wrapper.setLiquidationThreshold(bitmap, uint256(threshold));
        bitmap = wrapper.setLiquidationBonus(bitmap, uint256(bonus));

        assertEq(wrapper.getLtv(bitmap), uint256(ltv), "Fuzz: LTV independence");
        assertEq(wrapper.getLiquidationThreshold(bitmap), uint256(threshold), "Fuzz: LiqThreshold independence");
        assertEq(wrapper.getLiquidationBonus(bitmap), uint256(bonus), "Fuzz: LiqBonus independence");
    }
}

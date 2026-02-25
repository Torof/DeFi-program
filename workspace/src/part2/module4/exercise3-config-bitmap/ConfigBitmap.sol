// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Aave-Style Configuration Bitmap
//
// Pack multiple risk parameters into a single uint256 using bit manipulation.
//
// WHY THIS MATTERS:
//   Aave V3 stores ~20 configuration fields for each reserve in a single
//   uint256. Without packing, reading all config for one reserve would cost
//   ~20 SLOADs (20 × 2100 gas = 42,000 gas). With packing, it's 1 SLOAD
//   (2,100 gas). That's a 20x gas reduction — and it happens on EVERY
//   interaction (supply, borrow, liquidate).
//
//   This exercise teaches you the exact bit manipulation pattern used in
//   Aave V3's ReserveConfiguration library.
//
// THE BITMAP LAYOUT (simplified from Aave V3):
//
//   Bit position:
//   ┌────────┬────────┬────────┬────────┬────┬────┬────┬────┬────┬──────────┐
//   │  0-15  │ 16-31  │ 32-47  │ 48-55  │ 56 │ 57 │ 58 │ 59 │ 60 │ 61-255  │
//   ├────────┼────────┼────────┼────────┼────┼────┼────┼────┼────┼──────────┤
//   │  LTV   │ LiqTH  │ LiqBon │  Dec   │ Ac │ Fr │ Bo │ St │ Pa │ Reserved │
//   └────────┴────────┴────────┴────────┴────┴────┴────┴────┴────┴──────────┘
//
//   LTV (0-15):            Loan-to-Value ratio in basis points (0-65535)
//   LiqTH (16-31):         Liquidation threshold in basis points
//   LiqBon (32-47):        Liquidation bonus in basis points
//   Dec (48-55):           Asset decimals (0-255)
//   Ac (56):               Active flag
//   Fr (57):               Frozen flag
//   Bo (58):               Borrowing enabled flag
//   St (59):               Stable rate borrowing enabled flag
//   Pa (60):               Paused flag
//   Reserved (61-255):     Reserved for future use
//
// THE PATTERN — for every field:
//
//   SET (write a value into the bitmap):
//     1. Create a MASK that covers the field's bits (all 1s in the field position)
//     2. CLEAR the field: bitmap & ~mask  (AND with inverted mask → zeros out the field)
//     3. WRITE the value: | (value << offset)  (OR with shifted value → fills in the field)
//
//   GET (read a value from the bitmap):
//     1. SHIFT right to move the field to bit 0
//     2. MASK with the field's max value to isolate it
//
// REFERENCE IMPLEMENTATIONS are provided below for LiquidationBonus (bits 32-47)
// and Decimals (bits 48-55). Study these carefully before implementing your TODOs.
//
// Real protocol reference:
//   - Aave V3 ReserveConfiguration.sol (the exact same pattern!)
//     https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol
//
// Run: forge test --match-contract ConfigBitmapTest -vvv
// ============================================================================

/// @notice Aave-style bitmap library for packing reserve configuration.
/// @dev All functions are pure — they take a bitmap value and return a new one.
///      No storage is read or written here. The calling contract stores the uint256.
library ConfigBitmap {
    // =====================================================================
    //  Constants: masks and offsets for each field
    // =====================================================================

    // --- LTV: bits 0-15 (16 bits) ---
    uint256 internal constant LTV_MASK = 0xFFFF; // 16 bits of 1s at position 0
    // No offset needed — LTV starts at bit 0

    // --- Liquidation Threshold: bits 16-31 (16 bits) ---
    uint256 internal constant LIQ_THRESHOLD_MASK = 0xFFFF;
    uint256 internal constant LIQ_THRESHOLD_OFFSET = 16;

    // --- Liquidation Bonus: bits 32-47 (16 bits) ---
    uint256 internal constant LIQ_BONUS_MASK = 0xFFFF;
    uint256 internal constant LIQ_BONUS_OFFSET = 32;

    // --- Decimals: bits 48-55 (8 bits) ---
    uint256 internal constant DECIMALS_MASK = 0xFF;
    uint256 internal constant DECIMALS_OFFSET = 48;

    // --- Flags: single bits ---
    uint256 internal constant ACTIVE_FLAG_BIT = 56;
    uint256 internal constant FROZEN_FLAG_BIT = 57;
    uint256 internal constant BORROW_FLAG_BIT = 58;
    uint256 internal constant STABLE_RATE_FLAG_BIT = 59;
    uint256 internal constant PAUSED_FLAG_BIT = 60;

    // =====================================================================
    //  PROVIDED: setLiquidationBonus — REFERENCE IMPLEMENTATION
    // =====================================================================
    /// @notice Sets the liquidation bonus field (bits 32-47).
    /// @dev Study this implementation carefully — your TODOs follow the exact
    ///      same pattern with different offsets and masks.
    ///
    ///      Step-by-step with example:
    ///        bitmap = 0x...0000_0000   (all zeros for clarity)
    ///        bonus = 10500 (105% = 5% bonus over collateral)
    ///
    ///        1. Create positioned mask: LIQ_BONUS_MASK << LIQ_BONUS_OFFSET
    ///           = 0xFFFF << 32 = 0x0000_FFFF_0000_0000
    ///
    ///        2. Clear the field: bitmap & ~(positioned mask)
    ///           = bitmap & 0xFFFF_0000_FFFF_FFFF  (zeros out bits 32-47)
    ///
    ///        3. Write the value: | (bonus << LIQ_BONUS_OFFSET)
    ///           = | (10500 << 32) = | 0x0000_2904_0000_0000
    ///
    ///        Result: bits 32-47 contain 10500, all other bits preserved.
    function setLiquidationBonus(uint256 bitmap, uint256 bonus) internal pure returns (uint256) {
        return (bitmap & ~(LIQ_BONUS_MASK << LIQ_BONUS_OFFSET)) | (bonus << LIQ_BONUS_OFFSET);
    }

    // =====================================================================
    //  PROVIDED: getLiquidationBonus — REFERENCE IMPLEMENTATION
    // =====================================================================
    /// @notice Gets the liquidation bonus field (bits 32-47).
    /// @dev Step-by-step:
    ///        bitmap = 0x0000_2904_1F40_1E14  (contains LTV=7700, LT=8000, LB=10500)
    ///
    ///        1. Shift right by offset: bitmap >> 32
    ///           = 0x0000_0000_0000_2904  (bonus is now at bit 0)
    ///
    ///        2. Mask with field size: & 0xFFFF
    ///           = 0x2904 = 10500  ← the liquidation bonus!
    function getLiquidationBonus(uint256 bitmap) internal pure returns (uint256) {
        return (bitmap >> LIQ_BONUS_OFFSET) & LIQ_BONUS_MASK;
    }

    // =====================================================================
    //  PROVIDED: setDecimals — REFERENCE IMPLEMENTATION (8-bit field)
    // =====================================================================
    /// @notice Sets the decimals field (bits 48-55).
    /// @dev Same pattern as setLiquidationBonus, but with 8-bit mask (0xFF)
    ///      and offset 48. Decimals range: 0-255 (though typically 6 or 18).
    function setDecimals(uint256 bitmap, uint256 decimals) internal pure returns (uint256) {
        return (bitmap & ~(DECIMALS_MASK << DECIMALS_OFFSET)) | (decimals << DECIMALS_OFFSET);
    }

    // =====================================================================
    //  PROVIDED: getDecimals — REFERENCE IMPLEMENTATION (8-bit field)
    // =====================================================================
    /// @notice Gets the decimals field (bits 48-55).
    function getDecimals(uint256 bitmap) internal pure returns (uint256) {
        return (bitmap >> DECIMALS_OFFSET) & DECIMALS_MASK;
    }

    // =====================================================================
    //  TODO 1: Implement setLtv
    // =====================================================================
    /// @notice Sets the LTV field (bits 0-15).
    /// @dev This is the EASIEST setter because LTV starts at bit 0.
    ///      That means the value doesn't need to be shifted before OR-ing!
    ///
    ///      The clear step still needs the mask though:
    ///        bitmap & ~LTV_MASK  (clears bits 0-15, preserves everything else)
    ///
    ///      Then OR with the value (no shift needed):
    ///        | ltv
    ///
    ///      Compare with setLiquidationBonus — same pattern, simpler because offset=0.
    ///
    /// @param bitmap The current configuration bitmap
    /// @param ltv The LTV value in basis points (e.g., 8000 = 80%)
    /// @return The updated bitmap
    function setLtv(uint256 bitmap, uint256 ltv) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =====================================================================
    //  TODO 2: Implement getLtv
    // =====================================================================
    /// @notice Gets the LTV field (bits 0-15).
    /// @dev Since LTV starts at bit 0, no right-shift is needed!
    ///      Just mask: bitmap & LTV_MASK
    ///
    ///      Compare with getLiquidationBonus — same pattern, simpler because offset=0.
    ///
    /// @param bitmap The configuration bitmap
    /// @return The LTV value in basis points
    function getLtv(uint256 bitmap) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =====================================================================
    //  TODO 3: Implement setLiquidationThreshold
    // =====================================================================
    /// @notice Sets the liquidation threshold field (bits 16-31).
    /// @dev Same pattern as setLiquidationBonus (which is provided above).
    ///      Use LIQ_THRESHOLD_MASK and LIQ_THRESHOLD_OFFSET.
    ///
    ///      Steps (same as the reference implementation):
    ///        1. Clear: bitmap & ~(LIQ_THRESHOLD_MASK << LIQ_THRESHOLD_OFFSET)
    ///        2. Write: | (threshold << LIQ_THRESHOLD_OFFSET)
    ///
    /// @param bitmap The current configuration bitmap
    /// @param threshold The liquidation threshold in basis points (e.g., 8250 = 82.5%)
    /// @return The updated bitmap
    function setLiquidationThreshold(uint256 bitmap, uint256 threshold) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =====================================================================
    //  TODO 4: Implement getLiquidationThreshold
    // =====================================================================
    /// @notice Gets the liquidation threshold field (bits 16-31).
    /// @dev Same pattern as getLiquidationBonus.
    ///      Use LIQ_THRESHOLD_OFFSET and LIQ_THRESHOLD_MASK.
    ///
    ///      Steps:
    ///        1. Shift: bitmap >> LIQ_THRESHOLD_OFFSET
    ///        2. Mask: & LIQ_THRESHOLD_MASK
    ///
    /// @param bitmap The configuration bitmap
    /// @return The liquidation threshold in basis points
    function getLiquidationThreshold(uint256 bitmap) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =====================================================================
    //  TODO 5: Implement setFlag
    // =====================================================================
    /// @notice Sets or clears a single-bit flag at the given position.
    /// @dev This is the GENERALIZED pattern for boolean flags.
    ///      Aave V3 has separate functions for each flag, but they all
    ///      follow this same logic. One function to rule them all.
    ///
    ///      To SET a bit (value = true):
    ///        bitmap | (1 << bitPosition)
    ///        Example: bitmap = 0b0000, bitPosition = 2
    ///        Result:            0b0100  (bit 2 is now 1)
    ///
    ///      To CLEAR a bit (value = false):
    ///        bitmap & ~(1 << bitPosition)
    ///        Example: bitmap = 0b0100, bitPosition = 2
    ///        Result:            0b0000  (bit 2 is now 0)
    ///
    ///      Hint: Use a conditional (if/else) based on the value parameter.
    ///
    /// @param bitmap The current configuration bitmap
    /// @param bitPosition The bit position to set/clear (e.g., 56 for active)
    /// @param value True to set, false to clear
    /// @return The updated bitmap
    function setFlag(uint256 bitmap, uint256 bitPosition, bool value) internal pure returns (uint256) {
        revert("Not implemented");
    }

    // =====================================================================
    //  TODO 6: Implement getFlag
    // =====================================================================
    /// @notice Reads a single-bit flag at the given position.
    /// @dev Pattern:
    ///        (bitmap >> bitPosition) & 1
    ///      Returns 0 or 1, which we cast to bool.
    ///
    ///      Alternative (equally valid):
    ///        bitmap & (1 << bitPosition) != 0
    ///
    /// @param bitmap The configuration bitmap
    /// @param bitPosition The bit position to read
    /// @return True if the bit is set, false otherwise
    function getFlag(uint256 bitmap, uint256 bitPosition) internal pure returns (bool) {
        revert("Not implemented");
    }
}

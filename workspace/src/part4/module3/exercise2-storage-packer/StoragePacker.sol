// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Storage Packer
//
// Pack, unpack, and update fields within packed storage slots using bit
// operations in assembly. Practice the read-modify-write pattern that
// production protocols (Aave V3, Uniswap V3) use for gas-efficient storage.
//
// Concepts exercised:
//   - shl / or to pack multiple values into one slot
//   - shr / and to extract individual fields
//   - Read-modify-write: load → clear → shift → or → store
//   - Address + uint96 packing
//   - Multi-field (3 fields) packed slot manipulation
//
// Run: FOUNDRY_PROFILE=part4 forge test --match-contract StoragePackerTest -vvv
// ============================================================================

contract StoragePacker {
    // ---- Storage slots (DO NOT MODIFY) ----
    //
    // Slot 0: packedSlot — two uint128 fields
    //   Layout: high (bits 255-128) | low (bits 127-0)
    uint256 public packedSlot;

    // Slot 1: mixedSlot — address + uint96
    //   Layout: address (bits 255-96) | uint96 (bits 95-0)
    uint256 public mixedSlot;

    // Slot 2: tripleSlot — three fields
    //   Layout: counter uint64 (bits 255-192) | balance uint64 (bits 191-128) | data uint128 (bits 127-0)
    uint256 public tripleSlot;

    // -------------------------------------------------------------------------
    // TODO 1: Pack two uint128 values into one slot
    //
    // Shift `high` left by 128 bits, then OR with `low` to combine them
    // into a single 256-bit word. Store the result in slot 0 (packedSlot).
    //
    // Steps:
    //   1. let packed := or(shl(128, high), and(low, 0xffffffffffffffffffffffffffffffff))
    //   2. sstore(0, packed)
    //
    // Opcodes: shl, or, and, sstore
    // See: Module 3 > Manual Pack/Unpack with Bit Operations (#manual-packing)
    // -------------------------------------------------------------------------
    function packTwo(uint128 high, uint128 low) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Read individual packed fields
    //
    // Extract the low and high uint128 values from packedSlot (slot 0).
    //
    // readLow:  AND the packed value with a 128-bit mask
    //   result := and(sload(0), 0xffffffffffffffffffffffffffffffff)
    //
    // readHigh: Shift right by 128 bits
    //   result := shr(128, sload(0))
    //
    // Opcodes: sload, and, shr
    // See: Module 3 > Manual Pack/Unpack with Bit Operations (#manual-packing)
    // -------------------------------------------------------------------------
    function readLow() external view returns (uint128 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function readHigh() external view returns (uint128 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 3: Update one packed field without touching the other
    //
    // Read-modify-write pattern:
    //   1. Load the current packed value: let packed := sload(0)
    //   2. Clear the target field using AND with an inverted mask
    //   3. Shift the new value into position (if needed)
    //   4. OR the cleared value with the new value
    //   5. Store the result: sstore(0, updated)
    //
    // updateLow:
    //   mask = 0xffffffffffffffffffffffffffffffff (128 low bits)
    //   cleared = and(packed, not(mask))    — zeros out low 128 bits
    //   updated = or(cleared, and(newLow, mask))
    //
    // updateHigh:
    //   mask = not(0xffffffffffffffffffffffffffffffff)  — high 128 bits set
    //   To clear high bits: and(packed, 0xffffffffffffffffffffffffffffffff)
    //   To set new high: or(cleared, shl(128, newHigh))
    //
    // Opcodes: sload, and, not, shl, or, sstore
    // See: Module 3 > Read-Modify-Write Pattern (#read-modify-write)
    // -------------------------------------------------------------------------
    function updateLow(uint128 newLow) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function updateHigh(uint128 newHigh) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 4: Pack address (20 bytes) + uint96 into one slot
    //
    // Layout: address in high 160 bits, uint96 in low 96 bits.
    //
    // packMixed:
    //   packed = or(shl(96, addr), and(value, 0xffffffffffffffffffffffff))
    //   sstore(1, packed)
    //
    // readAddr: shift right 96 to extract the address
    //   result := shr(96, sload(1))
    //
    // readUint96: mask low 96 bits
    //   result := and(sload(1), 0xffffffffffffffffffffffff)
    //
    // Hint: 0xffffffffffffffffffffffff is 24 hex chars = 96 bits.
    //
    // Opcodes: shl, shr, or, and, sload, sstore
    // See: Module 3 > Manual Pack/Unpack with Bit Operations (#manual-packing)
    // -------------------------------------------------------------------------
    function packMixed(address addr, uint96 value) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function readAddr() external view returns (address result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function readUint96() external view returns (uint96 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Read-modify-write on a triple-packed slot
    //
    // tripleSlot (slot 2) layout:
    //   counter  — uint64 at bits 255-192
    //   balance  — uint64 at bits 191-128
    //   data     — uint128 at bits 127-0
    //
    // initTriple: pack all three fields into slot 2.
    //   packed = or(or(shl(192, counter), shl(128, balance)),
    //              and(data, 0xffffffffffffffffffffffffffffffff))
    //   sstore(2, packed)
    //
    // incrementCounter: read slot 2, extract the counter (bits 255-192),
    //   add 1, write it back WITHOUT changing balance or data.
    //
    //   Steps:
    //     1. let packed := sload(2)
    //     2. Extract counter: let ctr := shr(192, packed)
    //     3. Increment: ctr := add(ctr, 1)
    //     4. Clear counter field: let cleared := and(packed, COUNTER_CLEAR_MASK)
    //        COUNTER_CLEAR_MASK = not(shl(192, 0xffffffffffffffff))
    //        This is: bits 191-0 are 1, bits 255-192 are 0
    //     5. Set new counter: let updated := or(cleared, shl(192, ctr))
    //     6. sstore(2, updated)
    //
    // Hint: 0xffffffffffffffff = 16 hex chars = 64 bits (uint64 max).
    //
    // Opcodes: sload, shr, add, and, not, shl, or, sstore
    // See: Module 3 > Read-Modify-Write Pattern (#read-modify-write)
    // -------------------------------------------------------------------------
    function initTriple(uint64 counter, uint64 balance, uint128 data) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    function incrementCounter() external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

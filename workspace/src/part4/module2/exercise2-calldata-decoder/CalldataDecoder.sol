// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Calldata Decoder
//
// Parse calldata and encode errors using inline assembly. You'll extract
// values at specific offsets, mask addresses, follow ABI offset pointers
// for dynamic types, encode a custom revert, and forward raw calldata.
//
// Concepts exercised:
//   - calldataload at computed offsets
//   - Address masking (20 bytes from a 32-byte word)
//   - ABI dynamic type decoding (offset → length → calldatacopy)
//   - Custom error encoding with the 0x1c offset trick
//   - calldatacopy for raw calldata forwarding
//
// Run: FOUNDRY_PROFILE=part4 forge test --match-contract CalldataDecoderTest -vvv
// ============================================================================

contract CalldataDecoder {
    /// @dev Custom error used by TODO 4. Selector: bytes4(keccak256("CustomError(uint256)"))
    error CustomError(uint256 code);

    // -------------------------------------------------------------------------
    // TODO 1: Extract a uint256 from calldata at a given word index
    //
    // Given a `bytes calldata` blob and a word index (0-based), read the
    // 32-byte word at that position. Word 0 starts at `data.offset`,
    // word 1 at `data.offset + 32`, etc.
    //
    // Steps:
    //   1. Compute the byte offset: add(data.offset, mul(index, 32))
    //   2. calldataload at that offset
    //   3. Assign to result
    //
    // Opcodes: calldataload, add, mul
    // See: Module 2 > Calldata Layout (#calldata-layout)
    // -------------------------------------------------------------------------
    function extractUint(bytes calldata data, uint256 index) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Extract an address from the first 32-byte word of calldata
    //
    // An ABI-encoded address is right-aligned in a 32-byte word (the high
    // 12 bytes are zero-padded). Load the word, then mask it to keep only
    // the low 20 bytes.
    //
    // Steps:
    //   1. Load the first word: let word := calldataload(data.offset)
    //   2. Mask to 20 bytes: result := and(word, 0xffffffffffffffffffffffffffffffffffffffff)
    //      Or equivalently: shr(96, shl(96, word))
    //
    // Opcodes: calldataload, and (or shr/shl)
    // See: Module 2 > ABI Encoding at the Byte Level (#abi-encoding)
    // -------------------------------------------------------------------------
    function extractAddress(bytes calldata data) external pure returns (address result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 3: Decode a dynamic `bytes` from ABI-encoded calldata
    //
    // ABI encoding for dynamic types uses the head/tail pattern:
    //   - Head region: a 32-byte offset pointing to where the data starts
    //   - Tail region: length (32 bytes) followed by the actual bytes
    //
    // The `data` parameter contains ABI-encoded (uint256, bytes):
    //   Word 0: the uint256 value (ignored here)
    //   Word 1: offset to the bytes data (relative to data.offset)
    //   At that offset: 32-byte length, then the raw bytes
    //
    // Steps:
    //   1. Read the offset pointer: let offset := calldataload(add(data.offset, 0x20))
    //   2. Compute absolute position: let absPos := add(data.offset, offset)
    //   3. Read the byte length: let len := calldataload(absPos)
    //   4. Allocate memory for the bytes:
    //      a. let ptr := mload(0x40)             — current FMP
    //      b. mstore(ptr, len)                   — store length
    //      c. calldatacopy(add(ptr, 0x20), add(absPos, 0x20), len)  — copy data
    //      d. Bump FMP past length word + padded data:
    //         mstore(0x40, add(ptr, add(0x20, and(add(len, 0x1f), not(0x1f)))))
    //         This is: ptr + 32 (length word) + round_up(len, 32)
    //   5. Assign: result := ptr
    //
    // Opcodes: calldataload, calldatacopy, mload, mstore, add
    // See: Module 2 > Calldata Layout (#head-tail) — Deep Dive
    // -------------------------------------------------------------------------
    function extractDynamicBytes(bytes calldata data) external pure returns (bytes memory result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 4: Revert with CustomError(uint256)
    //
    // Encode the error manually and revert. The error encoding is:
    //   [4-byte selector][32-byte uint256 argument]
    //
    // The 0x1c trick: when you mstore a 4-byte selector at offset 0x00,
    // it's right-aligned in the 32-byte word (at bytes 28-31). So the
    // selector actually starts at byte 0x1c (28). Use revert(0x1c, 0x24)
    // to emit exactly 36 bytes: 4 (selector) + 32 (uint256).
    //
    // Steps:
    //   1. Compute the selector yourself with: cast sig "CustomError(uint256)"
    //      Or use the constant: 0x110b3655
    //      Store it: mstore(0x00, 0x110b3655)
    //      mstore right-aligns small values, so the 4-byte selector lands at
    //      bytes 28-31 (offset 0x1c) of the 32-byte word.
    //   2. Store the argument: mstore(0x20, code)
    //      This places the uint256 in the next 32-byte word.
    //      (NOT mstore(0x04, code) — that would write 32 bytes starting at 0x04,
    //       overwriting bytes 0x04-0x23 and misaligning the parameter.)
    //   3. Revert: revert(0x1c, 0x24) — emit 36 bytes starting from the selector
    //
    // Opcodes: mstore, revert
    // See: Module 2 > Return Values & Error Encoding (#return-errors) — 0x1c Explained
    // -------------------------------------------------------------------------
    function encodeRevert(uint256 code) external pure {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Copy all calldata to memory and return it as bytes
    //
    // This is the pattern used by proxy contracts to forward calldata.
    // Copy the entire msg.data into memory and return it.
    //
    // Steps:
    //   1. Get calldata size: let size := calldatasize()
    //   2. Allocate memory:
    //      a. let ptr := mload(0x40)
    //      b. mstore(ptr, size)                   — store length prefix
    //      c. calldatacopy(add(ptr, 0x20), 0, size) — copy all calldata
    //      d. Bump FMP: mstore(0x40, add(ptr, add(0x20, and(add(size, 0x1f), not(0x1f)))))
    //         This rounds up size to the next 32-byte boundary for proper alignment.
    //         (For this exercise, size=4, so the FMP moves to ptr + 0x40.)
    //   3. Assign: result := ptr
    //
    // Opcodes: calldatasize, calldatacopy, mload, mstore
    // See: Module 2 > Proxy Forwarding Preview (#proxy-preview)
    // -------------------------------------------------------------------------
    function forwardCalldata() external pure returns (bytes memory result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Memory Lab
//
// Explore EVM memory at the opcode level. You'll read the free memory pointer,
// allocate memory manually, write/read values, build a `bytes memory` object,
// and use scratch space for hashing.
//
// Concepts exercised:
//   - Reading the free memory pointer (mload(0x40))
//   - Manual memory allocation (bump the FMP)
//   - mstore / mload round-trip
//   - Building a `bytes memory` value in assembly (length + data + FMP bump)
//   - Reading the zero slot (0x60-0x7f)
//   - Using scratch space (0x00-0x3f) for keccak256
//
// Run: FOUNDRY_PROFILE=part4 forge test --match-contract MemoryLabTest -vvv
// ============================================================================

contract MemoryLab {
    // -------------------------------------------------------------------------
    // TODO 1: Read the free memory pointer
    //
    // The free memory pointer lives at byte offset 0x40 in memory. Solidity
    // initialises it to 0x80 at the start of every call (the first 128 bytes
    // are reserved). Use mload to read it and return the value.
    //
    // Steps:
    //   1. result := mload(0x40)
    //
    // Opcodes: mload
    // See: Module 2 > Memory Layout (#memory-layout)
    // -------------------------------------------------------------------------
    function readFreeMemPtr() external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Allocate `size` bytes of memory
    //
    // Manual allocation means: read the current FMP, bump it by `size`, and
    // write the new value back. Return the OLD pointer (that's where the
    // caller's freshly allocated region starts).
    //
    // Steps:
    //   1. Read FMP: let ptr := mload(0x40)
    //   2. Bump FMP: mstore(0x40, add(ptr, size))
    //   3. Return the old pointer: result := ptr
    //
    // Opcodes: mload, mstore, add
    // See: Module 2 > The Free Memory Pointer (#free-memory-pointer)
    // -------------------------------------------------------------------------
    function allocate(uint256 size) public pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    /// @dev Pre-implemented helper — calls allocate() twice in one call frame
    ///      so the test can verify the FMP bump (external calls reset memory).
    ///      DO NOT MODIFY — this delegates to your allocate() implementation above.
    function allocateTwice(uint256 sizeA, uint256 sizeB) external pure returns (uint256 ptrA, uint256 ptrB) {
        ptrA = allocate(sizeA);
        ptrB = allocate(sizeB);
    }

    // -------------------------------------------------------------------------
    // TODO 3: Write a value to memory offset 0x80 and read it back
    //
    // This is a simple mstore → mload round-trip. It proves that memory is
    // byte-addressable and that mstore/mload operate on 32-byte words.
    //
    // Steps:
    //   1. mstore(0x80, value)
    //   2. result := mload(0x80)
    //
    // Opcodes: mstore, mload
    // See: Module 2 > Memory Layout (#memory-layout) — Deep Dive
    // -------------------------------------------------------------------------
    function writeAndRead(uint256 value) external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 4: Build a `bytes memory` containing a single uint256
    //
    // In Solidity's ABI, a `bytes memory` is laid out as:
    //   [ptr]      → length  (32 bytes, value = number of data bytes)
    //   [ptr+0x20] → data    (the actual bytes, here a uint256 = 32 bytes)
    //
    // To return `bytes memory` from assembly, you store the pointer to this
    // structure in the return variable. The caller (Solidity ABI decoder)
    // interprets it as an offset to the length-prefixed blob.
    //
    // Steps:
    //   1. Read the current FMP: let ptr := mload(0x40)
    //   2. Store the length at ptr: mstore(ptr, 32)          — 32 data bytes
    //   3. Store the data after the length: mstore(add(ptr, 0x20), val)
    //   4. Bump FMP past length + data: mstore(0x40, add(ptr, 0x40))
    //   5. Point the return variable at the structure: result := ptr
    //
    // Opcodes: mload, mstore, add
    // See: Module 2 > The Free Memory Pointer (#free-memory-pointer) — Intermediate Example
    // -------------------------------------------------------------------------
    function buildUint256Bytes(uint256 val) external pure returns (bytes memory result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Read the zero slot
    //
    // The zero slot (0x60-0x7f) is guaranteed to contain zero. Solidity uses
    // it as the initial value for empty dynamic memory arrays and strings.
    // Read and return it to verify it's zero.
    //
    // Steps:
    //   1. result := mload(0x60)
    //
    // Opcodes: mload
    // See: Module 2 > Memory Layout (#memory-layout)
    // -------------------------------------------------------------------------
    function readZeroSlot() external pure returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 6: Hash a pair of bytes32 values using scratch space
    //
    // Scratch space (0x00-0x3f) is free to use for temporary data. This is
    // cheaper than allocating memory because you don't need to bump the FMP.
    //
    // Bonus: Annotate this assembly block as memory-safe with
    // `/// @solidity memory-safe-assembly` since it only touches scratch space.
    //
    // Steps:
    //   1. mstore(0x00, a)       — write `a` to scratch word 1
    //   2. mstore(0x20, b)       — write `b` to scratch word 2
    //   3. result := keccak256(0x00, 0x40) — hash 64 bytes
    //
    // Opcodes: mstore, keccak256
    // See: Module 2 > Scratch Space for Hashing (#scratch-hashing)
    // -------------------------------------------------------------------------
    function hashPair(bytes32 a, bytes32 b) external pure returns (bytes32 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Slot Explorer
//
// Compute and read storage slots using inline assembly. The contract has
// pre-populated state — your assembly must find and read the correct slots
// by applying the slot computation formulas from Module 3.
//
// Concepts exercised:
//   - sload at known slot numbers
//   - Mapping slot computation: keccak256(abi.encode(key, baseSlot))
//   - Dynamic array slot computation: keccak256(abi.encode(baseSlot)) + index
//   - Nested mapping chained hashing
//   - sstore at a computed slot
//
// Run: FOUNDRY_PROFILE=part4 forge test --match-contract SlotExplorerTest -vvv
// ============================================================================

contract SlotExplorer {
    // ---- Pre-defined storage layout (DO NOT MODIFY) ----
    uint256 public simpleValue;                                      // slot 0
    mapping(address => uint256) public balances;                     // slot 1
    uint256[] public data;                                           // slot 2
    mapping(address => mapping(uint256 => uint256)) public nested;   // slot 3

    constructor() {
        simpleValue = 42;
        balances[address(0xBEEF)] = 100;
        data.push(111);
        data.push(222);
        data.push(333);
        nested[address(0xCAFE)][7] = 999;
    }

    // -------------------------------------------------------------------------
    // TODO 1: Read a state variable via sload
    //
    // `simpleValue` is at slot 0. Read it directly with sload.
    //
    // Steps:
    //   1. result := sload(0)
    //
    // Opcodes: sload
    // See: Module 3 > SLOAD & SSTORE in Yul (#sload-sstore-yul)
    // -------------------------------------------------------------------------
    function readSimpleSlot() external view returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 2: Compute and read a mapping slot
    //
    // `balances` is a mapping at slot 1. To read balances[key]:
    //   slot = keccak256(abi.encode(key, 1))
    //
    // Use scratch space (0x00-0x3f) to build the hash input:
    //   - Store key at 0x00 (left-padded to 32 bytes automatically for address)
    //   - Store base slot (1) at 0x20
    //   - Hash 64 bytes starting at 0x00
    //
    // Steps:
    //   1. mstore(0x00, key)
    //   2. mstore(0x20, 1)               — base slot of balances mapping
    //   3. let slot := keccak256(0x00, 0x40)
    //   4. result := sload(slot)
    //
    // Opcodes: mstore, keccak256, sload
    // See: Module 3 > Mapping Slot Computation (#mapping-slots)
    // -------------------------------------------------------------------------
    function readMappingSlot(address key) external view returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 3: Compute and read a dynamic array element slot
    //
    // `data` is a dynamic array at slot 2.
    //   - data.length is stored at sload(2)
    //   - data[i] is at sload(keccak256(abi.encode(2)) + i)
    //
    // Note: array slot computation hashes only 32 bytes (the base slot),
    // unlike mappings which hash 64 bytes (key + base slot).
    //
    // Steps:
    //   1. mstore(0x00, 2)               — base slot of data array
    //   2. let dataStart := keccak256(0x00, 0x20)  — hash 32 bytes
    //   3. result := sload(add(dataStart, index))
    //
    // Opcodes: mstore, keccak256, add, sload
    // See: Module 3 > Dynamic Array Slot Computation (#array-slots)
    // -------------------------------------------------------------------------
    function readArraySlot(uint256 index) external view returns (uint256 result) {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 4: Compute a nested mapping slot
    //
    // `nested` is mapping(address => mapping(uint256 => uint256)) at slot 3.
    // To read nested[outerKey][innerKey], chain two keccak256 computations:
    //
    //   level1 = keccak256(abi.encode(outerKey, 3))         — outer mapping
    //   finalSlot = keccak256(abi.encode(innerKey, level1)) — inner mapping
    //
    // Steps:
    //   1. mstore(0x00, outerKey)
    //   2. mstore(0x20, 3)                — base slot of nested mapping
    //   3. let level1 := keccak256(0x00, 0x40)
    //   4. mstore(0x00, innerKey)
    //   5. mstore(0x20, level1)           — use level1 as the base for inner
    //   6. let finalSlot := keccak256(0x00, 0x40)
    //   7. result := sload(finalSlot)
    //
    // Opcodes: mstore, keccak256, sload
    // See: Module 3 > Nested Structures (#nested-slots)
    // -------------------------------------------------------------------------
    function readNestedMappingSlot(address outerKey, uint256 innerKey)
        external
        view
        returns (uint256 result)
    {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }

    // -------------------------------------------------------------------------
    // TODO 5: Write to a computed mapping slot
    //
    // Compute the slot for balances[key] (same as TODO 2), then sstore
    // the new value. After this call, the Solidity getter balances(key)
    // should return newValue — proving your slot computation is correct.
    //
    // Steps:
    //   1. mstore(0x00, key)
    //   2. mstore(0x20, 1)
    //   3. let slot := keccak256(0x00, 0x40)
    //   4. sstore(slot, newValue)
    //
    // Opcodes: mstore, keccak256, sstore
    // See: Module 3 > SLOAD & SSTORE in Yul (#sload-sstore-yul)
    // -------------------------------------------------------------------------
    function writeToMappingSlot(address key, uint256 newValue) external {
        assembly {
            revert(0, 0) // TODO: replace with implementation
        }
    }
}

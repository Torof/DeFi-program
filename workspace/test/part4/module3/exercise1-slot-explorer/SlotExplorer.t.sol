// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SlotExplorer} from
    "../../../../src/part4/module3/exercise1-slot-explorer/SlotExplorer.sol";

/// @notice Tests for the SlotExplorer exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module3/exercise1-slot-explorer/SlotExplorer.sol instead.
contract SlotExplorerTest is Test {
    SlotExplorer internal explorer;

    function setUp() public {
        explorer = new SlotExplorer();
    }

    // =========================================================================
    // TODO 1: Read Simple Slot
    // =========================================================================

    function test_ReadSimpleSlot_ReturnsValue() public view {
        uint256 result = explorer.readSimpleSlot();
        assertEq(result, 42, "readSimpleSlot should return 42 (set in constructor)");
    }

    function test_ReadSimpleSlot_MatchesSolidityGetter() public view {
        uint256 fromAssembly = explorer.readSimpleSlot();
        uint256 fromGetter = explorer.simpleValue();
        assertEq(fromAssembly, fromGetter, "Assembly read should match Solidity getter");
    }

    // =========================================================================
    // TODO 2: Read Mapping Slot
    // =========================================================================

    function test_ReadMappingSlot_KnownAddress() public view {
        uint256 result = explorer.readMappingSlot(address(0xBEEF));
        assertEq(result, 100, "balances[0xBEEF] should be 100");
    }

    function test_ReadMappingSlot_UnknownAddress() public view {
        uint256 result = explorer.readMappingSlot(address(0xDEAD));
        assertEq(result, 0, "balances[unknown] should be 0 (default)");
    }

    function test_ReadMappingSlot_MatchesSolidityGetter() public view {
        uint256 fromAssembly = explorer.readMappingSlot(address(0xBEEF));
        uint256 fromGetter = explorer.balances(address(0xBEEF));
        assertEq(fromAssembly, fromGetter, "Assembly read should match Solidity getter");
    }

    function testFuzz_ReadMappingSlot_MatchesGetter(address key) public {
        // Write a value via the writeToMappingSlot function first is not possible
        // in scaffold state, so we test that uninitialized keys return 0.
        // After TODO 5 is implemented, the fuzz test below covers arbitrary values.
        uint256 fromAssembly = explorer.readMappingSlot(key);
        uint256 fromGetter = explorer.balances(key);
        assertEq(fromAssembly, fromGetter, "Assembly read should match getter for any key");
    }

    // =========================================================================
    // TODO 3: Read Array Slot
    // =========================================================================

    function test_ReadArraySlot_FirstElement() public view {
        uint256 result = explorer.readArraySlot(0);
        assertEq(result, 111, "data[0] should be 111");
    }

    function test_ReadArraySlot_SecondElement() public view {
        uint256 result = explorer.readArraySlot(1);
        assertEq(result, 222, "data[1] should be 222");
    }

    function test_ReadArraySlot_LastElement() public view {
        uint256 result = explorer.readArraySlot(2);
        assertEq(result, 333, "data[2] should be 333");
    }

    function test_ReadArraySlot_MatchesSolidityGetter() public view {
        for (uint256 i = 0; i < 3; i++) {
            uint256 fromAssembly = explorer.readArraySlot(i);
            uint256 fromGetter = explorer.data(i);
            assertEq(fromAssembly, fromGetter, "Assembly read should match getter for all indices");
        }
    }

    // =========================================================================
    // TODO 4: Read Nested Mapping Slot
    // =========================================================================

    function test_ReadNestedMapping_KnownValue() public view {
        uint256 result = explorer.readNestedMappingSlot(address(0xCAFE), 7);
        assertEq(result, 999, "nested[0xCAFE][7] should be 999");
    }

    function test_ReadNestedMapping_UnknownOuterKey() public view {
        uint256 result = explorer.readNestedMappingSlot(address(0xDEAD), 7);
        assertEq(result, 0, "nested[unknown][7] should be 0");
    }

    function test_ReadNestedMapping_UnknownInnerKey() public view {
        uint256 result = explorer.readNestedMappingSlot(address(0xCAFE), 99);
        assertEq(result, 0, "nested[0xCAFE][unknown] should be 0");
    }

    function test_ReadNestedMapping_MatchesSolidityGetter() public view {
        uint256 fromAssembly = explorer.readNestedMappingSlot(address(0xCAFE), 7);
        uint256 fromGetter = explorer.nested(address(0xCAFE), 7);
        assertEq(fromAssembly, fromGetter, "Assembly read should match Solidity getter");
    }

    // =========================================================================
    // TODO 5: Write to Mapping Slot
    // =========================================================================

    function test_WriteToMapping_UpdatesValue() public {
        explorer.writeToMappingSlot(address(0xBEEF), 500);
        uint256 result = explorer.balances(address(0xBEEF));
        assertEq(result, 500, "balances[0xBEEF] should be 500 after write");
    }

    function test_WriteToMapping_NewKey() public {
        explorer.writeToMappingSlot(address(0x1234), 777);
        uint256 result = explorer.balances(address(0x1234));
        assertEq(result, 777, "balances[0x1234] should be 777 after write");
    }

    function test_WriteToMapping_VerifyViaAssemblyRead() public {
        explorer.writeToMappingSlot(address(0xFACE), 42);
        uint256 result = explorer.readMappingSlot(address(0xFACE));
        assertEq(result, 42, "Assembly read should see the assembly-written value");
    }

    function testFuzz_WriteToMapping(address key, uint256 val) public {
        explorer.writeToMappingSlot(key, val);
        uint256 fromGetter = explorer.balances(key);
        assertEq(fromGetter, val, "Solidity getter should return the assembly-written value");
    }
}

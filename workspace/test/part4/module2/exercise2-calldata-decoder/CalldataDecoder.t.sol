// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {CalldataDecoder} from
    "../../../../src/part4/module2/exercise2-calldata-decoder/CalldataDecoder.sol";

/// @notice Tests for the CalldataDecoder exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module2/exercise2-calldata-decoder/CalldataDecoder.sol instead.
contract CalldataDecoderTest is Test {
    CalldataDecoder internal decoder;

    function setUp() public {
        decoder = new CalldataDecoder();
    }

    // =========================================================================
    // TODO 1: Extract uint256 at word index
    // =========================================================================

    function test_ExtractUint_FirstWord() public view {
        // Encode two uint256 values and extract word 0.
        bytes memory data = abi.encode(uint256(111), uint256(222));
        uint256 result = decoder.extractUint(data, 0);
        assertEq(result, 111, "Word 0 should be 111");
    }

    function test_ExtractUint_SecondWord() public view {
        bytes memory data = abi.encode(uint256(111), uint256(222));
        uint256 result = decoder.extractUint(data, 1);
        assertEq(result, 222, "Word 1 should be 222");
    }

    function test_ExtractUint_ThirdWord() public view {
        bytes memory data = abi.encode(uint256(10), uint256(20), uint256(30));
        uint256 result = decoder.extractUint(data, 2);
        assertEq(result, 30, "Word 2 should be 30");
    }

    function testFuzz_ExtractUint_FirstWord(uint256 val) public view {
        bytes memory data = abi.encode(val);
        uint256 result = decoder.extractUint(data, 0);
        assertEq(result, val, "Should extract any uint256 at index 0");
    }

    // =========================================================================
    // TODO 2: Extract address
    // =========================================================================

    function test_ExtractAddress_Simple() public view {
        address expected = address(0xdead);
        bytes memory data = abi.encode(expected);
        address result = decoder.extractAddress(data);
        assertEq(result, expected, "Should extract address 0xdead");
    }

    function test_ExtractAddress_FullAddress() public view {
        address expected = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik.eth
        bytes memory data = abi.encode(expected);
        address result = decoder.extractAddress(data);
        assertEq(result, expected, "Should extract full 20-byte address");
    }

    function test_ExtractAddress_Zero() public view {
        bytes memory data = abi.encode(address(0));
        address result = decoder.extractAddress(data);
        assertEq(result, address(0), "Should extract zero address");
    }

    function testFuzz_ExtractAddress(address expected) public view {
        bytes memory data = abi.encode(expected);
        address result = decoder.extractAddress(data);
        assertEq(result, expected, "Should extract any address");
    }

    // =========================================================================
    // TODO 3: Decode dynamic bytes
    // =========================================================================

    function test_ExtractDynamicBytes_Short() public view {
        // Encode (uint256, bytes) — the function reads the bytes portion.
        bytes memory inner = hex"DEADBEEF";
        bytes memory data = abi.encode(uint256(42), inner);
        bytes memory result = decoder.extractDynamicBytes(data);
        assertEq(result.length, 4, "Extracted bytes should be 4 bytes long");
        assertEq(keccak256(result), keccak256(inner), "Extracted bytes should match DEADBEEF");
    }

    function test_ExtractDynamicBytes_Empty() public view {
        bytes memory inner = "";
        bytes memory data = abi.encode(uint256(0), inner);
        bytes memory result = decoder.extractDynamicBytes(data);
        assertEq(result.length, 0, "Empty bytes should return length 0");
    }

    function test_ExtractDynamicBytes_32Bytes() public view {
        bytes memory inner = abi.encode(uint256(0xCAFE));
        bytes memory data = abi.encode(uint256(1), inner);
        bytes memory result = decoder.extractDynamicBytes(data);
        assertEq(result.length, 32, "Should extract 32-byte payload");
        assertEq(keccak256(result), keccak256(inner), "32-byte payload should match");
    }

    function test_ExtractDynamicBytes_LargerPayload() public view {
        // 64 bytes of data
        bytes memory inner = abi.encode(uint256(1), uint256(2));
        bytes memory data = abi.encode(uint256(999), inner);
        bytes memory result = decoder.extractDynamicBytes(data);
        assertEq(result.length, 64, "Should extract 64-byte payload");
        assertEq(keccak256(result), keccak256(inner), "64-byte payload should match");
    }

    // =========================================================================
    // TODO 4: Encode revert with CustomError(uint256)
    // =========================================================================

    function test_EncodeRevert_RevertsWithSelector() public {
        // CustomError(uint256) selector: bytes4(keccak256("CustomError(uint256)"))
        vm.expectRevert(abi.encodeWithSelector(CalldataDecoder.CustomError.selector, uint256(42)));
        decoder.encodeRevert(42);
    }

    function test_EncodeRevert_ZeroCode() public {
        vm.expectRevert(abi.encodeWithSelector(CalldataDecoder.CustomError.selector, uint256(0)));
        decoder.encodeRevert(0);
    }

    function test_EncodeRevert_MaxCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(CalldataDecoder.CustomError.selector, type(uint256).max)
        );
        decoder.encodeRevert(type(uint256).max);
    }

    function testFuzz_EncodeRevert(uint256 code) public {
        vm.expectRevert(abi.encodeWithSelector(CalldataDecoder.CustomError.selector, code));
        decoder.encodeRevert(code);
    }

    // =========================================================================
    // TODO 5: Forward calldata
    // =========================================================================

    function test_ForwardCalldata_ContainsSelector() public view {
        bytes memory result = decoder.forwardCalldata();
        // forwardCalldata() has no params, so calldata is just the 4-byte selector.
        assertEq(result.length, 4, "forwardCalldata with no args should return 4 bytes");
    }

    function test_ForwardCalldata_SelectorMatches() public view {
        bytes memory result = decoder.forwardCalldata();
        // The returned bytes should be the selector of forwardCalldata()
        bytes4 expected = CalldataDecoder.forwardCalldata.selector;
        bytes4 actual;
        assembly {
            actual := mload(add(result, 0x20))
        }
        assertEq(actual, expected, "Returned calldata should start with forwardCalldata selector");
    }

    function test_ForwardCalldata_CapturesExtraData() public {
        // Call forwardCalldata via low-level call with extra calldata appended.
        // This verifies calldatasize() is used (not a hardcoded 4).
        bytes memory callData = abi.encodePacked(
            CalldataDecoder.forwardCalldata.selector,
            uint256(0xDEAD) // extra 32 bytes
        );
        (bool success, bytes memory returnData) = address(decoder).staticcall(callData);
        assertTrue(success, "forwardCalldata should succeed with extra data");
        // Decode the returned bytes memory from the ABI-encoded return data
        bytes memory result = abi.decode(returnData, (bytes));
        assertEq(result.length, 36, "Should capture selector (4) + extra data (32) = 36 bytes");
    }
}

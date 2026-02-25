// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SmartAccountEIP1271, InvalidSignatureLength} from "../../../../src/part1/module4/exercise2-smart-account-eip1271/SmartAccountEIP1271.sol";
import {MockEntryPoint} from "../../../../src/part1/module4/exercise1-simple-smart-account/SimpleSmartAccount.sol";

/// @notice Tests for Smart Account with EIP-1271 support.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module4/SmartAccountEIP1271.sol instead.
contract SmartAccountEIP1271Test is Test {
    MockEntryPoint entryPoint;
    SmartAccountEIP1271 account;

    address owner;
    uint256 ownerPrivateKey;

    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant EIP1271_INVALID = 0xffffffff;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        entryPoint = new MockEntryPoint();
        account = new SmartAccountEIP1271(address(entryPoint), owner);
    }

    function test_IsValidSignature_Valid() public view {
        bytes32 hash = keccak256("Test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = account.isValidSignature(hash, signature);
        assertEq(result, EIP1271_MAGIC_VALUE, "Should return magic value");
    }

    function test_IsValidSignature_Invalid() public view {
        bytes32 hash = keccak256("Test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, hash); // Wrong key
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = account.isValidSignature(hash, signature);
        assertEq(result, EIP1271_INVALID, "Should return invalid");
    }

    function test_IsValidSignature_RevertInvalidLength() public {
        bytes32 hash = keccak256("Test");
        bytes memory shortSig = abi.encodePacked(bytes32(0), bytes32(0)); // Only 64 bytes

        vm.expectRevert(InvalidSignatureLength.selector);
        account.isValidSignature(hash, shortSig);
    }
}

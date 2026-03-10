// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {
    ErrorHandler,
    ErrorType,
    Call,
    Result,
    NotAStringError
} from "../../../../src/deep-dives/errors/exercise1-error-handler/ErrorHandler.sol";

// ============================================================================
// Helper contracts — various revert behaviours for testing
// ============================================================================

/// @dev Reverts with a custom error
error Unauthorized(address caller);
contract Reverter {
    function revertWithString(string calldata message) external pure {
        revert(message);
    }

    function revertWithCustomError() external view {
        revert Unauthorized(msg.sender);
    }

    function revertBare() external pure {
        revert();
    }

    function revertWithPanic() external pure {
        uint256 x = 1;
        uint256 y = 0;
        x / y; // Panic(0x12) — division by zero
    }

    function succeed() external pure returns (uint256) {
        return 42;
    }

    function succeedWithArgs(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }
}

/// @notice Tests for the ErrorHandler exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/deep-dives/errors/exercise1-error-handler/ErrorHandler.sol instead.
contract ErrorHandlerTest is Test {
    ErrorHandler handler;
    Reverter reverter;

    function setUp() public {
        handler = new ErrorHandler();
        reverter = new Reverter();
    }

    // =========================================================
    //  TODO 1: tryCall
    // =========================================================

    function test_tryCall_successReturnsData() public {
        (bool success, bytes memory data) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.succeed, ())
        );
        assertTrue(success, "Should succeed");
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 42, "Should return 42");
    }

    function test_tryCall_successWithArgs() public {
        (bool success, bytes memory data) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.succeedWithArgs, (10, 32))
        );
        assertTrue(success, "Should succeed");
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 42, "10 + 32 = 42");
    }

    function test_tryCall_failureReturnsRevertData() public {
        (bool success, bytes memory data) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertWithString, ("access denied"))
        );
        assertFalse(success, "Should fail");
        // Verify we got Error(string) revert data
        assertGt(data.length, 4, "Should contain error data");
        // First 4 bytes should be Error(string) selector
        bytes4 selector;
        assembly {
            selector := mload(add(data, 0x20))
        }
        assertEq(selector, bytes4(0x08c379a0), "Should be Error(string) selector");
    }

    function test_tryCall_bareRevertReturnsEmpty() public {
        (bool success, bytes memory data) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertBare, ())
        );
        assertFalse(success, "Should fail");
        assertEq(data.length, 0, "Bare revert has no data");
    }

    function test_tryCall_customErrorReturnsSelector() public {
        (bool success, bytes memory data) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertWithCustomError, ())
        );
        assertFalse(success, "Should fail");
        bytes4 selector;
        assembly {
            selector := mload(add(data, 0x20))
        }
        assertEq(selector, Unauthorized.selector, "Should be Unauthorized selector");
    }

    // =========================================================
    //  TODO 2: multicallStrict
    // =========================================================

    function test_multicallStrict_allSucceed() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));
        calls[1] = Call(address(reverter), abi.encodeCall(Reverter.succeedWithArgs, (5, 10)));

        bytes[] memory results = handler.multicallStrict(calls);

        assertEq(results.length, 2, "Should return 2 results");
        assertEq(abi.decode(results[0], (uint256)), 42, "First call returns 42");
        assertEq(abi.decode(results[1], (uint256)), 15, "Second call returns 15");
    }

    function test_multicallStrict_revertsOnFailure() public {
        Call[] memory calls = new Call[](3);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));
        calls[1] = Call(address(reverter), abi.encodeCall(Reverter.revertWithString, ("call failed")));
        calls[2] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ())); // never reached

        // Should bubble the Error(string) from call[1]
        vm.expectRevert("call failed");
        handler.multicallStrict(calls);
    }

    function test_multicallStrict_bubblesCustomError() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));
        calls[1] = Call(address(reverter), abi.encodeCall(Reverter.revertWithCustomError, ()));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(handler)));
        handler.multicallStrict(calls);
    }

    function test_multicallStrict_emptyArrayReturnsEmpty() public {
        Call[] memory calls = new Call[](0);
        bytes[] memory results = handler.multicallStrict(calls);
        assertEq(results.length, 0, "Empty input returns empty output");
    }

    // =========================================================
    //  TODO 3: multicallLenient
    // =========================================================

    function test_multicallLenient_allSucceed() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));
        calls[1] = Call(address(reverter), abi.encodeCall(Reverter.succeedWithArgs, (3, 7)));

        Result[] memory results = handler.multicallLenient(calls);

        assertEq(results.length, 2, "Should return 2 results");
        assertTrue(results[0].success, "First call succeeds");
        assertTrue(results[1].success, "Second call succeeds");
        assertEq(abi.decode(results[0].returnData, (uint256)), 42);
        assertEq(abi.decode(results[1].returnData, (uint256)), 10);
    }

    function test_multicallLenient_neverReverts() public {
        Call[] memory calls = new Call[](3);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));
        calls[1] = Call(address(reverter), abi.encodeCall(Reverter.revertWithString, ("oops")));
        calls[2] = Call(address(reverter), abi.encodeCall(Reverter.succeed, ()));

        // Should NOT revert — all calls recorded
        Result[] memory results = handler.multicallLenient(calls);

        assertTrue(results[0].success, "First call succeeds");
        assertFalse(results[1].success, "Second call fails");
        assertTrue(results[2].success, "Third call still runs");
    }

    function test_multicallLenient_capturesRevertData() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call(address(reverter), abi.encodeCall(Reverter.revertWithCustomError, ()));

        Result[] memory results = handler.multicallLenient(calls);

        assertFalse(results[0].success, "Call failed");
        // Verify the revert data contains the Unauthorized selector
        bytes memory revertData = results[0].returnData;
        assertGe(revertData.length, 4, "Should have at least a selector");
        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 0x20))
        }
        assertEq(selector, Unauthorized.selector, "Should capture Unauthorized error");
    }

    function test_multicallLenient_emptyArrayReturnsEmpty() public {
        Call[] memory calls = new Call[](0);
        Result[] memory results = handler.multicallLenient(calls);
        assertEq(results.length, 0, "Empty input returns empty output");
    }

    // =========================================================
    //  TODO 4: classifyError
    // =========================================================

    function test_classifyError_empty() public view {
        bytes memory data = "";
        assertEq(uint256(handler.classifyError(data)), uint256(ErrorType.EMPTY), "Empty = EMPTY");
    }

    function test_classifyError_stringError() public view {
        // Error(string) encoding for "test"
        bytes memory data = abi.encodeWithSignature("Error(string)", "test");
        assertEq(
            uint256(handler.classifyError(data)),
            uint256(ErrorType.STRING_ERROR),
            "Error(string) = STRING_ERROR"
        );
    }

    function test_classifyError_panic() public view {
        // Panic(uint256) encoding for arithmetic overflow
        bytes memory data = abi.encodeWithSignature("Panic(uint256)", uint256(0x11));
        assertEq(uint256(handler.classifyError(data)), uint256(ErrorType.PANIC), "Panic = PANIC");
    }

    function test_classifyError_customError() public view {
        bytes memory data = abi.encodeWithSelector(Unauthorized.selector, address(this));
        assertEq(uint256(handler.classifyError(data)), uint256(ErrorType.CUSTOM), "Custom = CUSTOM");
    }

    function test_classifyError_unknownShortData() public view {
        // 1-3 bytes — not enough for a selector
        bytes memory data1 = hex"ab";
        assertEq(uint256(handler.classifyError(data1)), uint256(ErrorType.UNKNOWN), "1 byte = UNKNOWN");

        bytes memory data2 = hex"abcd";
        assertEq(uint256(handler.classifyError(data2)), uint256(ErrorType.UNKNOWN), "2 bytes = UNKNOWN");

        bytes memory data3 = hex"abcdef";
        assertEq(uint256(handler.classifyError(data3)), uint256(ErrorType.UNKNOWN), "3 bytes = UNKNOWN");
    }

    function test_classifyError_exactlyFourBytes() public view {
        // 4 bytes that aren't Error(string) or Panic — should be CUSTOM
        bytes memory data = hex"deadbeef";
        assertEq(
            uint256(handler.classifyError(data)),
            uint256(ErrorType.CUSTOM),
            "4 unknown bytes = CUSTOM"
        );
    }

    function test_classifyError_selectorOnlyPanic() public view {
        // Just the Panic selector, no uint256 parameter (still classifiable)
        bytes memory data = abi.encodePacked(bytes4(0x4e487b71));
        assertEq(uint256(handler.classifyError(data)), uint256(ErrorType.PANIC), "Panic selector only = PANIC");
    }

    // =========================================================
    //  TODO 5: decodeStringError
    // =========================================================

    function test_decodeStringError_basic() public view {
        bytes memory data = abi.encodeWithSignature("Error(string)", "access denied");
        string memory message = handler.decodeStringError(data);
        assertEq(message, "access denied", "Should decode the string");
    }

    function test_decodeStringError_emptyString() public view {
        bytes memory data = abi.encodeWithSignature("Error(string)", "");
        string memory message = handler.decodeStringError(data);
        assertEq(message, "", "Should decode empty string");
    }

    function test_decodeStringError_longString() public view {
        string memory longMsg = "This is a much longer error message that spans multiple words and tests decoding of larger strings";
        bytes memory data = abi.encodeWithSignature("Error(string)", longMsg);
        string memory message = handler.decodeStringError(data);
        assertEq(message, longMsg, "Should decode long string");
    }

    function test_decodeStringError_revertsOnCustomError() public {
        bytes memory data = abi.encodeWithSelector(Unauthorized.selector, address(this));
        vm.expectRevert(NotAStringError.selector);
        handler.decodeStringError(data);
    }

    function test_decodeStringError_revertsOnPanic() public {
        bytes memory data = abi.encodeWithSignature("Panic(uint256)", uint256(0x01));
        vm.expectRevert(NotAStringError.selector);
        handler.decodeStringError(data);
    }

    function test_decodeStringError_revertsOnEmptyData() public {
        bytes memory data = "";
        vm.expectRevert(NotAStringError.selector);
        handler.decodeStringError(data);
    }

    // =========================================================
    //  Integration: tryCall + classifyError
    // =========================================================

    function test_integration_tryCallThenClassify() public {
        // Make a call that reverts with a string
        (bool success, bytes memory revertData) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertWithString, ("integration test"))
        );
        assertFalse(success, "Call should fail");

        // Classify the error
        ErrorType errType = handler.classifyError(revertData);
        assertEq(uint256(errType), uint256(ErrorType.STRING_ERROR), "Should be STRING_ERROR");

        // Decode the message
        string memory message = handler.decodeStringError(revertData);
        assertEq(message, "integration test", "Should decode the message");
    }

    function test_integration_tryCallThenClassifyCustom() public {
        (bool success, bytes memory revertData) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertWithCustomError, ())
        );
        assertFalse(success, "Call should fail");

        ErrorType errType = handler.classifyError(revertData);
        assertEq(uint256(errType), uint256(ErrorType.CUSTOM), "Should be CUSTOM");

        // Attempting to decode as string should revert
        vm.expectRevert(NotAStringError.selector);
        handler.decodeStringError(revertData);
    }

    function test_integration_tryCallThenClassifyPanic() public {
        (bool success, bytes memory revertData) = handler.tryCall(
            address(reverter),
            abi.encodeCall(Reverter.revertWithPanic, ())
        );
        assertFalse(success, "Call should fail");

        ErrorType errType = handler.classifyError(revertData);
        assertEq(uint256(errType), uint256(ErrorType.PANIC), "Should be PANIC");
    }
}

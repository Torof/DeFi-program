// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Error Handler
//
// Production-level error handling patterns used in multicall contracts,
// aggregators, and liquidation bots. Fill in the TODOs to make all tests pass.
//
// Concepts exercised:
//   - Low-level call error handling
//   - Assembly error bubbling (revert with raw bytes)
//   - Error classification by selector
//   - ABI decoding of error data
//
// Run: forge test --match-contract ErrorHandlerTest -vvv
// ============================================================================

// --- Custom Errors ---
error NotAStringError();

// --- Types ---
enum ErrorType {
    EMPTY,        // No revert data (bare revert or out-of-gas)
    STRING_ERROR, // Error(string) — selector 0x08c379a0
    PANIC,        // Panic(uint256) — selector 0x4e487b71
    CUSTOM,       // Any other 4+ byte selector
    UNKNOWN       // 1-3 bytes of data (malformed)
}

struct Call {
    address target;
    bytes data;
}

struct Result {
    bool success;
    bytes returnData;
}

/// @notice Demonstrates production error handling patterns.
/// @dev Exercise for Deep Dives: Errors
contract ErrorHandler {
    // Well-known selectors for classification
    bytes4 private constant _ERROR_STRING_SELECTOR = 0x08c379a0; // Error(string)
    bytes4 private constant _PANIC_SELECTOR = 0x4e487b71;        // Panic(uint256)

    // =============================================================
    //  TODO 1: Implement tryCall
    // =============================================================
    /// @notice Execute a low-level call and return the raw result.
    /// @dev Do NOT revert on failure — return (false, revertData) instead.
    /// Hint: Use a low-level call and return both the success flag and the
    ///       raw bytes (return data on success, revert data on failure).
    /// See: Deep Dives > Errors > Low-Level Calls — Manual Error Handling
    function tryCall(address target, bytes calldata data)
        external
        returns (bool success, bytes memory returnData)
    {
        // TODO: Execute low-level call, return success and raw bytes
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement multicallStrict
    // =============================================================
    /// @notice Execute calls sequentially. Revert on first failure,
    ///         bubbling the original error data using assembly.
    /// @dev On failure, the raw revert bytes from the failed call must be
    ///      forwarded exactly — no wrapping, no re-encoding.
    /// Hint: Use assembly { revert(add(result, 0x20), mload(result)) }
    ///       to bubble raw bytes. add(result, 0x20) skips the length prefix,
    ///       mload(result) reads the length.
    /// See: Deep Dives > Errors > Multicall Error Strategies
    function multicallStrict(Call[] calldata calls)
        external
        returns (bytes[] memory results)
    {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            // TODO: Execute each call. On failure, bubble the revert data
            //       using assembly. On success, store the result.
            revert("Not implemented");
        }
    }

    // =============================================================
    //  TODO 3: Implement multicallLenient
    // =============================================================
    /// @notice Execute calls sequentially. Never revert.
    ///         Return a Result struct for each call with success status
    ///         and return/revert data.
    /// See: Deep Dives > Errors > Multicall Error Strategies
    function multicallLenient(Call[] calldata calls)
        external
        returns (Result[] memory results)
    {
        results = new Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            // TODO: Execute each call. Store success and raw bytes
            //       in results[i]. Never revert.
            revert("Not implemented");
        }
    }

    // =============================================================
    //  TODO 4: Implement classifyError
    // =============================================================
    /// @notice Classify raw revert data by its selector.
    /// @dev Rules:
    ///   - Empty data (length 0) → ErrorType.EMPTY
    ///   - Length 1-3 (has data but no full selector) → ErrorType.UNKNOWN
    ///   - Selector == 0x08c379a0 → ErrorType.STRING_ERROR
    ///   - Selector == 0x4e487b71 → ErrorType.PANIC
    ///   - Any other selector (length >= 4) → ErrorType.CUSTOM
    /// Hint: Extract the selector using assembly:
    ///       assembly { selector := mload(add(errorData, 0x20)) }
    ///       This loads the first 32 bytes — but bytes4 only keeps the top 4.
    /// See: Deep Dives > Errors > Decoding Raw Revert Data
    function classifyError(bytes memory errorData)
        external
        pure
        returns (ErrorType)
    {
        // TODO: Implement the classification logic
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement decodeStringError
    // =============================================================
    /// @notice Decode Error(string) revert data into the string message.
    /// @dev Steps:
    ///   1. Verify the selector matches Error(string) — revert NotAStringError() if not
    ///   2. Strip the 4-byte selector from the data
    ///   3. ABI-decode the remaining bytes as (string)
    /// Hint: Use assembly to skip the 4-byte selector:
    ///       assembly { let len := mload(errorData)
    ///                  errorData := add(errorData, 0x04)
    ///                  mstore(errorData, sub(len, 4)) }
    ///       then `abi.decode(errorData, (string))` to get the message.
    /// See: Deep Dives > Errors > Decoding Raw Revert Data
    function decodeStringError(bytes memory errorData)
        external
        pure
        returns (string memory)
    {
        // TODO: Verify selector, strip it, decode and return the string
        revert("Not implemented");
    }
}

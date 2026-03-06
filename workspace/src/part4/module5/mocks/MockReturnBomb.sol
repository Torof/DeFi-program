// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice A malicious contract that returns an enormous amount of data on any call.
/// @dev Used by Exercise 2 (SafeCaller) to test the returnbomb defense.
///      Without bounded RETURNDATACOPY, copying this return data would cause
///      quadratic memory expansion costs, potentially exhausting the caller's gas.
contract MockReturnBomb {
    /// @dev Returns 10,000 bytes of data on any call via the fallback.
    fallback() external payable {
        assembly {
            // Return 10,000 bytes of zeros. The caller must NOT blindly copy
            // all of this with returndatacopy(0, 0, returndatasize()) — that's
            // the returnbomb attack. The bounded copy defense caps the copy size.
            return(0, 10000)
        }
    }
}

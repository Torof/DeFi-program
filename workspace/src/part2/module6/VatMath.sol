// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Signed arithmetic helpers for MakerDAO-style Vat accounting.
/// @dev Pre-built — students do NOT modify this.
///
///      The Vat uses `int256` deltas (dink, dart, drate) to modify `uint256`
///      state (ink, art, rate, dai). These helpers safely handle the
///      uint256 + int256 addition/subtraction without overflow.
///
///      Pattern: _add(uint256, int256) returns uint256
///        - If delta > 0: result = x + uint256(delta)
///        - If delta < 0: result = x - uint256(-delta)
///        - Reverts on underflow (result < 0) or overflow (result > type(uint256).max)
library VatMath {
    error MathOverflow();

    /// @notice Add a signed delta to an unsigned value.
    /// @dev Used for: ink += dink, art += dart, dai += drad, etc.
    function _add(uint256 x, int256 y) internal pure returns (uint256 z) {
        if (y >= 0) {
            z = x + uint256(y);
            if (z < x) revert MathOverflow();
        } else {
            z = x - uint256(-y);
            if (z > x) revert MathOverflow(); // underflow
        }
    }

    /// @notice Multiply uint256 by int256, returning int256.
    /// @dev Used for computing drad = rate * dart (both can be large).
    ///      rate is RAY (uint256), dart is WAD (int256), result is RAD (int256).
    function _mul(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        if (int256(x) < 0) revert MathOverflow(); // x too large for int256
        if (y != 0 && z / y != int256(x)) revert MathOverflow();
    }
}

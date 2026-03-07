// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Standard Solidity contract with 8 functions — uses the compiler's
///         default dispatch (linear if-else chain on selectors).
/// @dev Used by Exercise 3 tests for gas comparison against JumpDispatcher.
///      The compiler generates approximately O(n) dispatch code for these
///      8 functions. Your JumpDispatcher should match the return values.
contract LinearDispatcher {
    function getA() external pure returns (uint256) { return 1; }
    function getB() external pure returns (uint256) { return 2; }
    function getC() external pure returns (uint256) { return 3; }
    function getD() external pure returns (uint256) { return 4; }
    function getE() external pure returns (uint256) { return 5; }
    function getF() external pure returns (uint256) { return 6; }
    function getG() external pure returns (uint256) { return 7; }
    function getH() external pure returns (uint256) { return 8; }
}

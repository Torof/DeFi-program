// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Simple target contract for testing external calls in assembly.
/// @dev Used by Exercise 1 (CallEncoder) and Exercise 2 (SafeCaller).
contract MockTarget {
    mapping(address => uint256) public balances;

    event Deposited(address indexed account, uint256 amount);

    error InsufficientBalance(uint256 requested, uint256 available);

    /// @notice Deposit ETH for a given account. Two args: (address account, uint256 tag).
    /// @dev The tag is ignored — it exists to test 2-arg calldata encoding.
    function deposit(address account, uint256 tag) external payable {
        balances[account] += msg.value;
        emit Deposited(account, tag);
    }

    /// @notice Returns a single uint256 value — the balance of `account`.
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @notice Returns three uint256 values for testing multi-value decoding.
    function getTriple(uint256 x) external pure returns (uint256 a, uint256 b, uint256 c) {
        a = x;
        b = x * 2;
        c = x * 3;
    }

    /// @notice Always reverts with a custom error for testing error bubbling.
    function alwaysReverts(uint256 requested) external view {
        revert InsufficientBalance(requested, balances[msg.sender]);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Gas-optimized ERC-20 for benchmarking comparison.
/// @dev Used by Exercise 1 (GasBenchmark). Uses custom errors and
///      standard Solidity optimizations (no assembly) — the baseline
///      a competent Solidity dev would write.
contract OptimizedToken {
    error InsufficientBalance();
    error InsufficientAllowance();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = type(uint256).max;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] -= amount;
        }
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] < amount) revert InsufficientAllowance();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        unchecked {
            allowance[from][msg.sender] -= amount;
            balanceOf[from] -= amount;
        }
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

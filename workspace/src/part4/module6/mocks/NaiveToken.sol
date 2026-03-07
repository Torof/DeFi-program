// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Deliberately inefficient ERC-20 for gas benchmarking.
/// @dev Used by Exercise 1 (GasBenchmark). This token uses string revert
///      messages and uncached storage reads — the patterns you'd fix in
///      production code.
contract NaiveToken {
    string public name = "NaiveToken";
    string public symbol = "NAIVE";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor() {
        balanceOf[msg.sender] = type(uint256).max;
        totalSupply = type(uint256).max;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "NaiveToken: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "NaiveToken: insufficient allowance");
        require(balanceOf[from] >= amount, "NaiveToken: insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

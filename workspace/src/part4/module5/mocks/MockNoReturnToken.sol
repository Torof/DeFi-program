// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice ERC-20 that does NOT return bool from transfer/transferFrom (USDT-style).
/// @dev Used by Exercise 2 (SafeCaller) to test the non-returning token path.
///      The SafeERC20 pattern must handle this — the ABI decoder would revert
///      expecting 32 bytes of return data but getting 0.
contract MockNoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = type(uint256).max;
    }

    /// @dev No return value — like USDT's transfer().
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        // No return statement!
    }

    /// @dev No return value — like USDT's transferFrom().
    function transferFrom(address from, address to, uint256 amount) external {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "insufficient");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        // No return statement!
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

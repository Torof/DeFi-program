// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: EIP-2612 Permit Vault
//
// Build a vault that accepts deposits via EIP-2612 permit signatures,
// enabling single-transaction deposit flows without prior approve() calls.
//
// This demonstrates how modern DeFi protocols use permit to improve UX by
// eliminating the two-step approve → deposit pattern.
//
// Run: forge test --match-contract PermitVaultTest -vvv
// ============================================================================

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// --- Custom Errors ---
error InsufficientBalance();
error TransferFailed();
error InvalidDeadline();

// =============================================================
//  PROVIDED — PermitToken (ERC20 with EIP-2612 support)
// =============================================================
/// @notice Simple ERC-20 token with EIP-2612 permit functionality.
/// @dev Extends OpenZeppelin's ERC20Permit which handles all permit logic.
contract PermitToken is ERC20Permit {
    constructor() ERC20("Permit Token", "PTKN") ERC20Permit("Permit Token") {
        // Mint initial supply to deployer for testing
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    /// @notice Public mint function for testing.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// =============================================================
//  TODO 1: Implement PermitVault
// =============================================================
/// @notice Vault that accepts ERC-20 deposits using EIP-2612 permits.
/// @dev Demonstrates the single-transaction deposit pattern via permit.
// See: Module 3 > EIP-2612 — Permit (#eip-2612-permit)
// See: Module 3 > OpenZeppelin ERC20Permit (#openzeppelin-erc20permit)
contract PermitVault {
    // TODO: Add state variables
    // Hint: mapping(address user => mapping(address token => uint256 balance)) public balances;
    // Hint: You might want to track total deposits per token too

    // =============================================================
    //  TODO 2: Implement standard deposit (without permit)
    // =============================================================
    /// @notice Deposits tokens using the traditional approve → transferFrom pattern.
    /// @dev Requires the user to have called token.approve(address(this), amount) beforehand.
    /// @param token The ERC-20 token address
    /// @param amount The amount to deposit
    function deposit(address token, uint256 amount) external {
        // TODO: Implement
        // 1. Transfer tokens from msg.sender to this contract using IERC20(token).transferFrom()
        // 2. Update balances[msg.sender][token] += amount
        // 3. Emit a Deposit event (define the event)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement depositWithPermit
    // =============================================================
    /// @notice Deposits tokens using an EIP-2612 permit signature.
    /// @dev Executes permit() then transferFrom() in a single transaction.
    /// @param token The ERC-20 token address (must implement EIP-2612)
    /// @param amount The amount to deposit
    /// @param deadline The permit expiration timestamp
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // TODO: Implement
        // 1. Check that deadline >= block.timestamp (revert InvalidDeadline() if expired)
        // 2. Call IERC20Permit(token).permit(msg.sender, address(this), amount, deadline, v, r, s)
        // 3. Transfer tokens using IERC20(token).transferFrom(msg.sender, address(this), amount)
        // 4. Update balances[msg.sender][token] += amount
        // 5. Emit a Deposit event
        //
        // Hint: Cast to IERC20Permit for the permit call:
        //       IERC20Permit(token).permit(...)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement withdraw
    // =============================================================
    /// @notice Withdraws deposited tokens.
    /// @param token The token address
    /// @param amount The amount to withdraw
    function withdraw(address token, uint256 amount) external {
        // TODO: Implement
        // 1. Check that balances[msg.sender][token] >= amount (revert InsufficientBalance() if not)
        // 2. Update balances[msg.sender][token] -= amount
        // 3. Transfer tokens to msg.sender using IERC20(token).transfer(msg.sender, amount)
        // 4. Check that transfer succeeded (revert TransferFailed() if it returned false)
        // 5. Emit a Withdrawal event (define the event)
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement view functions
    // =============================================================

    /// @notice Gets the user's balance for a specific token.
    function getBalance(address user, address token) external view returns (uint256) {
        // TODO: Return balances[user][token]
        revert("Not implemented");
    }

    // TODO: Define events
    // event Deposit(address indexed user, address indexed token, uint256 amount);
    // event Withdrawal(address indexed user, address indexed token, uint256 amount);
}

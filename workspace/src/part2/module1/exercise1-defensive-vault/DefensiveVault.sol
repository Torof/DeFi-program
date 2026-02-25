// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// EXERCISE: Defensive Vault
//
// Build a vault that correctly handles deposits and withdrawals for ANY
// ERC-20 token — including fee-on-transfer tokens (like STA, PAXG) and
// tokens that don't return a bool (like USDT).
//
// Concepts exercised:
//   - SafeERC20 for no-return-value tokens
//   - Balance-before-after pattern for fee-on-transfer tokens
//   - Per-user balance tracking
//   - Custom errors
//
// Run: forge test --match-contract DefensiveVaultTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroDeposit();
error InsufficientBalance(uint256 requested, uint256 available);

/// @notice A vault that safely handles deposits/withdrawals for any ERC-20.
/// @dev Must work with standard tokens, fee-on-transfer tokens, and
///      tokens that don't return a bool from transfer/transferFrom.
contract DefensiveVault {
    IERC20 public immutable token;

    /// @notice Per-user deposited balance (tracks actual tokens received, not requested)
    mapping(address => uint256) public balanceOf;

    /// @notice Total tokens the vault is tracking across all users
    uint256 public totalTracked;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(address _token) {
        token = IERC20(_token);
    }

    // =============================================================
    //  TODO 1: Import and apply SafeERC20
    // =============================================================
    // SafeERC20 wraps token calls to handle tokens that don't return
    // a bool (like USDT). Without it, transferFrom on USDT will revert
    // because Solidity expects return data to decode as bool.
    //
    // Hint: import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    //       using SafeERC20 for IERC20;
    //
    // Then use token.safeTransferFrom(...) and token.safeTransfer(...)
    // instead of token.transferFrom(...) and token.transfer(...)

    // =============================================================
    //  TODO 2: Implement deposit with balance-before-after
    // =============================================================
    /// @notice Deposit tokens into the vault.
    /// @param amount The amount the user wants to deposit (may differ from received).
    /// @dev For fee-on-transfer tokens, the vault receives less than `amount`.
    ///      You MUST credit the user with what was actually received, not what
    ///      they requested. This is the balance-before-after pattern.
    ///
    /// Steps:
    ///   1. Revert with ZeroDeposit() if amount is 0
    ///   2. Record the vault's token balance BEFORE the transfer
    ///   3. Transfer tokens from msg.sender to the vault (use safe version!)
    ///   4. Record the vault's token balance AFTER the transfer
    ///   5. The actual received amount = after - before
    ///   6. Credit the user's balance with the received amount
    ///   7. Update totalTracked
    ///   8. Emit Deposit with the received amount
    function deposit(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement withdraw
    // =============================================================
    /// @notice Withdraw tokens from the vault.
    /// @param amount The amount the user wants to withdraw.
    /// @dev Reverts if the user doesn't have enough balance.
    ///
    /// Steps:
    ///   1. Check user has sufficient balance, revert with InsufficientBalance if not
    ///   2. Decrease user's balance
    ///   3. Decrease totalTracked
    ///   4. Transfer tokens to user (use safe version!)
    ///   5. Emit Withdraw
    function withdraw(uint256 amount) external {
        revert("Not implemented");
    }
}

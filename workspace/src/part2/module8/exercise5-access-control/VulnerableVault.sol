// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built vault with access control vulnerabilities.
//
//  This vault has TWO common access control bugs:
//
//  Bug 1 — Missing initializer guard:
//    initialize() can be called by anyone, at any time, to overwrite the
//    owner. In a proxy setup, someone can call initialize() on the
//    implementation directly, or re-call it on the proxy.
//
//  Bug 2 — Unprotected emergency function:
//    emergencyWithdraw() sends all tokens to the owner but has no access
//    control — anyone can call it. Combined with Bug 1 (re-initialize to
//    become owner), this drains the vault.
//
//  Your job:
//    1. Build AccessControlAttack.sol — exploit both bugs to drain the vault
//    2. Build DefendedVault.sol — fix both bugs
// ============================================================================

/// @notice Vault with missing access control on critical functions.
/// @dev Used as the target for the AccessControlTest exercise.
contract VulnerableVault {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public owner;
    bool public paused;

    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    /// @notice Initialize the vault. BUG: no guard — can be called repeatedly.
    function initialize(IERC20 token_, address owner_) external {
        // BUG: no check for "already initialized" — anyone can re-call this
        // to overwrite the owner and token address.
        token = token_;
        owner = owner_;
    }

    /// @notice Deposit tokens into the vault.
    function deposit(uint256 amount) external {
        require(!paused, "paused");
        token.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        totalDeposits += amount;
    }

    /// @notice Withdraw your deposited tokens.
    function withdraw(uint256 amount) external {
        require(!paused, "paused");
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        totalDeposits -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    /// @notice Pause deposits/withdrawals. Only owner.
    function pause() external {
        require(msg.sender == owner, "not owner");
        paused = true;
    }

    /// @notice Emergency: send all tokens to owner.
    /// BUG: no access control — anyone can call this.
    function emergencyWithdraw() external {
        // BUG: should require(msg.sender == owner), but it doesn't.
        // Combined with re-initialization, attacker becomes owner and drains.
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner, balance);
    }
}

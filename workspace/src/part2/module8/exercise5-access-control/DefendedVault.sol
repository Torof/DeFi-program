// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  EXERCISE: DefendedVault — Fix the Access Control Vulnerabilities
// ============================================================================
//
//  VulnerableVault has two bugs:
//    1. initialize() can be re-called — overwrites owner
//    2. emergencyWithdraw() has no access control — anyone can call it
//
//  Your task: fix both bugs.
//
//  Fix 1 — Add initialization guard:
//    Use a boolean `initialized` flag. Check it at the top of initialize()
//    and set it to true. This prevents re-initialization.
//    (In production, use OpenZeppelin's Initializable — here we do it
//    manually to understand the pattern.)
//
//  Fix 2 — Add owner check to emergencyWithdraw:
//    require(msg.sender == owner) — simple but critical.
//
//  Run:
//    forge test --match-contract AccessControlTest -vvv
//
// ============================================================================

/// @notice Vault with proper access control.
/// @dev Exercise for Module 8: DeFi Security (Access Control).
///      Student implements: initialize(), emergencyWithdraw().
///      Pre-built: deposit(), withdraw(), pause().
contract DefendedVault {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public owner;
    bool public paused;
    bool public initialized;

    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    // =============================================================
    //  TODO 1: Implement initialize — with re-initialization guard
    // =============================================================
    /// @notice Initialize the vault (can only be called once).
    /// @dev Steps:
    ///   1. Check not already initialized:
    ///      require(!initialized, "already initialized");
    ///
    ///   2. Set the initialized flag:
    ///      initialized = true;
    ///
    ///   3. Set token and owner:
    ///      token = token_;
    ///      owner = owner_;
    ///
    /// Why this works:
    ///   After the first call, initialized = true. Any subsequent call
    ///   reverts at the require. The owner cannot be overwritten.
    ///
    /// Production note: OpenZeppelin's Initializable base contract
    ///   provides this pattern (plus version tracking for re-initialization
    ///   in upgradeable contracts). Use it in production — this manual
    ///   pattern is for learning.
    ///
    /// See: Module 8 — "Access Control Vulnerabilities"
    function initialize(IERC20 token_, address owner_) external {
        // TODO: implement
    }

    // =============================================================
    //  TODO 2: Implement emergencyWithdraw — with owner check
    // =============================================================
    /// @notice Emergency: send all tokens to owner. Owner only.
    /// @dev Steps:
    ///   1. Check caller is owner:
    ///      require(msg.sender == owner, "not owner");
    ///
    ///   2. Transfer all tokens to owner:
    ///      uint256 balance = token.balanceOf(address(this));
    ///      token.safeTransfer(owner, balance);
    ///
    /// See: Module 8 — "Access Control Vulnerabilities"
    function emergencyWithdraw() external {
        // TODO: implement
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
}

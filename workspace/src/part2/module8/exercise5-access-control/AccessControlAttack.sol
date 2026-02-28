// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VulnerableVault} from "./VulnerableVault.sol";

// ============================================================================
//  EXERCISE: AccessControlAttack — Exploit Missing Access Control
// ============================================================================
//
//  VulnerableVault has two bugs:
//    1. initialize() has no guard — can be re-called to overwrite owner
//    2. emergencyWithdraw() has no access control — anyone can call it
//
//  Attack strategy:
//    1. Re-call initialize() to set yourself as owner
//    2. Call emergencyWithdraw() — sends all tokens to the new owner (you)
//
//  The attack is a single transaction — no flash loans, no complex setup.
//  This is OWASP Smart Contract Top 10 #1 (Access Control) for a reason:
//  it's devastatingly simple and extremely common.
//
//  Run:
//    forge test --match-contract AccessControlTest -vvv
//
// ============================================================================

/// @notice Exploit contract for the access control vulnerability.
/// @dev Exercise for Module 8: DeFi Security (Access Control).
///      Student implements: attack().
///      Pre-built: constructor.
contract AccessControlAttack {
    VulnerableVault public vault;
    IERC20 public token;

    constructor(VulnerableVault vault_, IERC20 token_) {
        vault = vault_;
        token = token_;
    }

    // =============================================================
    //  TODO: Implement attack — exploit re-initialization + unprotected drain
    // =============================================================
    /// @notice Execute the access control exploit to drain the vault.
    /// @dev Hint: Call the uninitialized implementation's initialize function,
    ///   then drain its funds. That's it. Two lines. This is why access
    ///   control is OWASP #1.
    ///
    /// See: Module 8 — "Access Control Vulnerabilities"
    function attack() external {
        // TODO: implement
    }
}

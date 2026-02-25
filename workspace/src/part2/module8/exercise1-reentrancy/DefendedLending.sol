// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VulnerableVault} from "./VulnerableVault.sol";

// ============================================================================
//  EXERCISE: DefendedLending — Fix the Read-Only Reentrancy Vulnerability
// ============================================================================
//
//  NaiveLending is vulnerable because it trusts vault.getSharePrice()
//  without checking if the vault is mid-transaction. During a vault
//  deposit callback, getSharePrice() returns an inflated value.
//
//  Your task: add ONE LINE to borrow() that checks the vault's reentrancy
//  state before reading getSharePrice().
//
//  The defense pattern:
//    Before reading any external view function, verify the source contract
//    isn't in an inconsistent state. In production (e.g., Balancer), you'd
//    call a function like manageUserBalance([]) that reverts if the vault
//    is locked. Here, the vault exposes a public `locked` flag.
//
//  Run:
//    forge test --match-contract ReadOnlyReentrancyTest -vvv
//
// ============================================================================

/// @notice Lending protocol defended against read-only reentrancy.
/// @dev Exercise for Module 8: DeFi Security.
///      Student implements: reentrancy check in borrow().
///      Pre-built: everything else (same as NaiveLending).
contract DefendedLending {
    using SafeERC20 for IERC20;

    VulnerableVault public immutable vault;
    IERC20 public immutable loanToken;

    uint256 public constant COLLATERAL_RATIO = 2e18;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public borrowed;

    constructor(VulnerableVault vault_, IERC20 loanToken_) {
        vault = vault_;
        loanToken = loanToken_;
    }

    /// @notice Deposit vault shares as collateral (same as NaiveLending).
    function depositCollateral(uint256 shares) external {
        IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), shares);
        collateral[msg.sender] += shares;
    }

    // =============================================================
    //  TODO: Fix borrow — add reentrancy check before reading price
    // =============================================================
    /// @notice Borrow tokens against deposited vault-share collateral.
    /// @dev Add ONE LINE at the top of this function to check the vault's
    ///      reentrancy state before reading getSharePrice().
    ///
    ///   The fix:
    ///     require(!vault.locked(), "DefendedLending: vault is mid-transaction")
    ///
    ///   Why this works:
    ///     During a vault deposit callback, vault.locked() == true.
    ///     This means getSharePrice() is unreliable (inconsistent state).
    ///     By reverting when locked, we refuse to value collateral during
    ///     the vulnerability window.
    ///
    ///   In production (Balancer example):
    ///     You'd call IVault(balancerVault).manageUserBalance([]) — a no-op
    ///     that reverts if the vault's reentrancy lock is active. Same idea,
    ///     different implementation.
    ///
    /// See: Module 8 — "Read-Only Reentrancy — The fix"
    function borrow(uint256 amount) external {
        // TODO: Add reentrancy check here — one line

        uint256 price = vault.getSharePrice();
        uint256 collateralValue = collateral[msg.sender] * price / 1e18;
        uint256 maxBorrow = collateralValue * 1e18 / COLLATERAL_RATIO;

        require(
            borrowed[msg.sender] + amount <= maxBorrow,
            "DefendedLending: insufficient collateral"
        );

        borrowed[msg.sender] += amount;
        loanToken.safeTransfer(msg.sender, amount);
    }
}

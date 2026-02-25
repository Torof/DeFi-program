// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VulnerableVault, IDepositCallback} from "./VulnerableVault.sol";
import {NaiveLending} from "./NaiveLending.sol";

// ============================================================================
//  EXERCISE: ReentrancyAttack — Exploit Read-Only Reentrancy
// ============================================================================
//
//  Read-only reentrancy is the most subtle reentrancy variant. You don't
//  need to modify state — just READ at the wrong time.
//
//  The setup:
//    - VulnerableVault has deposit() that transfers tokens → callback → mints shares
//    - During the callback, getSharePrice() returns an INFLATED value
//      (balance is up, but shares haven't been minted yet)
//    - NaiveLending reads getSharePrice() to value vault-share collateral
//
//  Your task: exploit this by depositing overvalued collateral during the
//  callback and borrowing more than you should.
//
//  Attack flow:
//    1. You hold some vault shares (pre-deposited)
//    2. Call vault.deposit(largeAmount, address(this)) — triggers callback
//    3. During callback: getSharePrice() is inflated (2x in this exercise)
//    4. Deposit your vault shares as collateral into NaiveLending
//    5. Borrow against the inflated collateral value
//    6. After callback: vault mints shares, price normalizes
//    7. You borrowed more than your collateral is actually worth!
//
//  Run:
//    forge test --match-contract ReadOnlyReentrancyTest -vvv
//
// ============================================================================

/// @notice Attack contract that exploits read-only reentrancy on NaiveLending.
/// @dev Exercise for Module 8: DeFi Security (Read-Only Reentrancy).
///      Students implement: attack, onDeposit callback.
///      Pre-built: constructor, state variables.
contract ReentrancyAttack is IDepositCallback {
    using SafeERC20 for IERC20;

    VulnerableVault public immutable vault;
    NaiveLending public immutable lending;
    IERC20 public immutable token;

    /// @notice Amount of vault shares this contract holds (for use as collateral).
    uint256 public sharesToDeposit;

    constructor(VulnerableVault vault_, NaiveLending lending_, IERC20 token_) {
        vault = vault_;
        lending = lending_;
        token = token_;
    }

    // =============================================================
    //  TODO 1: Implement attack — trigger the read-only reentrancy
    // =============================================================
    /// @notice Initiate the attack by depositing into the vault with a callback.
    /// @dev This is the entry point. When vault.deposit() calls back into
    ///      onDeposit(), getSharePrice() will be inflated.
    ///
    ///   Steps:
    ///     1. Record how many vault shares this contract holds:
    ///        sharesToDeposit = IERC20(address(vault)).balanceOf(address(this))
    ///
    ///     2. Approve the vault to pull tokens for the large deposit:
    ///        token.approve(address(vault), amount)
    ///
    ///     3. Approve the lending protocol to pull our vault shares:
    ///        IERC20(address(vault)).approve(address(lending), sharesToDeposit)
    ///
    ///     4. Deposit into vault WITH callback (this triggers onDeposit):
    ///        vault.deposit(amount, address(this))
    ///
    /// See: Module 8 — "Read-Only Reentrancy"
    ///
    /// @param amount The amount of tokens to deposit into the vault
    ///               (large enough to significantly inflate getSharePrice).
    function attack(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement onDeposit — the exploit callback
    // =============================================================
    /// @notice Called by VulnerableVault during deposit, BEFORE shares are minted.
    /// @dev At this point, vault.getSharePrice() is INFLATED because:
    ///      - Token balance is UP (vault received the deposit tokens)
    ///      - Share supply is UNCHANGED (shares not yet minted)
    ///
    ///   This is the vulnerability window. Exploit it:
    ///
    ///     1. Deposit vault shares as collateral into NaiveLending:
    ///        lending.depositCollateral(sharesToDeposit)
    ///        NaiveLending reads getSharePrice() → sees inflated value.
    ///
    ///     2. Borrow the maximum allowed amount:
    ///        uint256 price = vault.getSharePrice();
    ///        uint256 collateralValue = sharesToDeposit * price / 1e18;
    ///        uint256 maxBorrow = collateralValue * 1e18 / lending.COLLATERAL_RATIO();
    ///        lending.borrow(maxBorrow);
    ///
    ///   Why this works:
    ///     Normal price = 1e18 → 1,000 shares worth 1,000 → borrow max 500
    ///     Inflated price = 2e18 → 1,000 shares worth 2,000 → borrow max 1,000
    ///     You borrow 1,000 instead of 500 — the excess is stolen.
    ///
    /// See: Module 8 — "Read-Only Reentrancy — Numeric Walkthrough"
    ///
    /// @param depositor The address that initiated the vault deposit.
    /// @param amount The amount of tokens being deposited into the vault.
    function onDeposit(address depositor, uint256 amount) external override {
        revert("Not implemented");
    }
}

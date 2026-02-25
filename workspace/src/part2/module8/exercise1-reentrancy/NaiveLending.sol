// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VulnerableVault} from "./VulnerableVault.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built lending protocol that is VULNERABLE to
//  read-only reentrancy. It trusts vault.getSharePrice() without checking
//  whether the vault is mid-transaction.
//
//  The vulnerability: borrow() reads getSharePrice() to value collateral.
//  During a vault deposit callback, this price is inflated, letting the
//  attacker borrow more than their collateral is actually worth.
// ============================================================================

/// @notice Minimal lending protocol — accepts vault shares as collateral.
/// @dev VULNERABLE: reads getSharePrice() without checking vault.locked().
contract NaiveLending {
    using SafeERC20 for IERC20;

    VulnerableVault public immutable vault;
    IERC20 public immutable loanToken;

    /// @notice Collateralization ratio: 200% (2e18). Must deposit $200 of
    ///         collateral to borrow $100.
    uint256 public constant COLLATERAL_RATIO = 2e18;

    /// @notice Vault shares deposited as collateral, per user.
    mapping(address => uint256) public collateral;

    /// @notice Tokens borrowed, per user.
    mapping(address => uint256) public borrowed;

    constructor(VulnerableVault vault_, IERC20 loanToken_) {
        vault = vault_;
        loanToken = loanToken_;
    }

    /// @notice Deposit vault shares as collateral.
    function depositCollateral(uint256 shares) external {
        IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), shares);
        collateral[msg.sender] += shares;
    }

    /// @notice Borrow tokens against deposited vault-share collateral.
    /// @dev VULNERABLE: reads vault.getSharePrice() which can be inflated
    ///      during a vault deposit callback (read-only reentrancy).
    function borrow(uint256 amount) external {
        uint256 price = vault.getSharePrice();
        uint256 collateralValue = collateral[msg.sender] * price / 1e18;
        uint256 maxBorrow = collateralValue * 1e18 / COLLATERAL_RATIO;

        require(
            borrowed[msg.sender] + amount <= maxBorrow,
            "NaiveLending: insufficient collateral"
        );

        borrowed[msg.sender] += amount;
        loanToken.safeTransfer(msg.sender, amount);
    }
}

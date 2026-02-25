// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built vault that is intentionally VULNERABLE to
//  read-only reentrancy. Study it, then implement ReentrancyAttack.sol.
//
//  The vulnerability: deposit() transfers tokens BEFORE minting shares.
//  During the callback between these two operations, getSharePrice()
//  reads an inconsistent state (balance up, supply unchanged) and returns
//  an inflated price.
// ============================================================================

/// @notice Callback interface for vault deposit hooks.
interface IDepositCallback {
    function onDeposit(address depositor, uint256 amount) external;
}

/// @notice Minimal vault with a deposit callback — vulnerable to read-only reentrancy.
/// @dev The locked flag is public so DefendedLending can check it.
contract VulnerableVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    /// @notice True while deposit() is executing (between transfer and mint).
    /// @dev DefendedLending checks this to reject reads during inconsistent state.
    bool public locked;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        asset = asset_;
    }

    /// @notice Share price = totalAssets / totalSupply, scaled to 1e18.
    /// @dev Returns 1e18 when vault is empty. THIS IS THE READ-ONLY TARGET.
    ///      During deposit(), balance is inflated but supply hasn't changed,
    ///      so this returns an artificially high price.
    function getSharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return asset.balanceOf(address(this)) * 1e18 / supply;
    }

    /// @notice Deposit with optional callback — THE VULNERABILITY.
    /// @dev Order of operations creates the read-only reentrancy window:
    ///      1. Transfer tokens in (balance increases)
    ///      2. Callback (getSharePrice() inflated here!)
    ///      3. Mint shares (supply catches up — price normalizes)
    function deposit(uint256 amount, address callbackTarget) external {
        locked = true;

        // Step 1: Pull tokens — balance increases
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Step 2: Callback — vulnerability window!
        // getSharePrice() now returns inflated value because balance is up
        // but totalSupply hasn't changed yet.
        if (callbackTarget != address(0)) {
            IDepositCallback(callbackTarget).onDeposit(msg.sender, amount);
        }

        // Step 3: Mint shares — price normalizes (1:1 ratio)
        _mint(msg.sender, amount);

        locked = false;
    }

    /// @notice Standard deposit without callback (safe).
    function deposit(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }
}

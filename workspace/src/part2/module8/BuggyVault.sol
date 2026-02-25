// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built vault with a subtle bug in withdraw().
//  Your job is to write invariant tests (VaultHandler + invariants) that
//  FIND this bug automatically.
//
//  The bug is a common DeFi vulnerability — ordering of state changes
//  matters. Study the deposit() and withdraw() functions carefully.
//
//  Hint: compare the order of _burn vs amount calculation in withdraw()
//  with the order of _mint vs share calculation in deposit().
// ============================================================================

/// @notice Minimal share-based vault with a subtle ordering bug.
/// @dev Used as the target for the VaultInvariantTest exercise.
contract BuggyVault is ERC20 {
    IERC20 public immutable asset;

    constructor(IERC20 asset_) ERC20("Vault Token", "vTKN") {
        asset = asset_;
    }

    /// @notice Deposit tokens, receive shares. (Correct implementation.)
    function deposit(uint256 amount) external returns (uint256 shares) {
        shares = totalSupply() == 0
            ? amount
            : amount * totalSupply() / asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, shares);
    }

    /// @notice Burn shares, receive tokens. (Contains a bug.)
    function withdraw(uint256 shares) external returns (uint256 amount) {
        _burn(msg.sender, shares);
        // BUG: totalSupply() is already REDUCED by _burn above.
        // This means each share redeems MORE than it should.
        // The correct order: calculate amount FIRST, then burn.
        amount = shares * asset.balanceOf(address(this)) / totalSupply();
        asset.transfer(msg.sender, amount);
    }
}

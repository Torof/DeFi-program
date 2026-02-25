// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
//  EXERCISE: SimpleVault — Minimal ERC-4626 Tokenized Vault
// ============================================================================
//
//  Build a minimal ERC-4626 vault from scratch (no OpenZeppelin ERC4626).
//  The vault accepts deposits of an underlying ERC-20 token ("asset") and
//  mints proportional shares to depositors. As yield accrues (totalAssets
//  increases), each share becomes worth more assets.
//
//  What you'll learn:
//    - The shares/assets abstraction: shares × rate = assets
//    - Safe division with Math.mulDiv and explicit rounding direction
//    - Why rounding ALWAYS favors the vault (against the user)
//    - The 4 entry points: deposit, mint, withdraw, redeem
//
//  Rounding rules (critical for security):
//    - deposit:  rounds shares DOWN → user gets fewer shares
//    - mint:     rounds assets UP   → user pays more assets
//    - withdraw: rounds shares UP   → user burns more shares
//    - redeem:   rounds assets DOWN → user gets fewer assets
//    All four round AGAINST the user, preventing vault drain via rounding.
//
//  Share math:
//    shares = assets × totalSupply / totalAssets    (deposits)
//    assets = shares × totalAssets / totalSupply     (redemptions)
//    Empty vault (totalSupply == 0): first deposit is 1:1.
//
//  This exercise uses asset.balanceOf(address(this)) for totalAssets().
//  This is the simplest approach but is vulnerable to the inflation attack
//  (donation attack). Exercise 2 (InflationAttack) explores this weakness
//  and its defenses.
//
//  Run:
//    forge test --match-contract SimpleVaultTest -vvv
//
// ============================================================================

/// @notice Minimal ERC-4626 tokenized vault — shares represent proportional
///         ownership of pooled assets.
/// @dev Exercise for Module 7: Vaults & Yield.
///      Students implement: _convertToShares, _convertToAssets, deposit, withdraw.
///      Pre-built: mint, redeem, all preview/convert/max functions.
contract SimpleVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        asset = asset_;
    }

    // ── totalAssets ─────────────────────────────────────────────────────
    // Naive approach: read the vault's actual token balance.
    // Simple, but vulnerable to donation attacks (see Exercise 2).

    /// @notice Total underlying assets the vault holds.
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // ── Preview / Convert / Max (pre-built wrappers) ────────────────────
    // These all route through _convertToShares / _convertToAssets.
    // Once you implement the TODO conversions, these all work automatically.

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    // =============================================================
    //  TODO 1: Implement _convertToShares — assets → shares
    // =============================================================
    /// @notice Convert an asset amount to shares, with explicit rounding.
    /// @dev This is the mathematical core of the vault.
    ///
    /// Logic:
    ///   1. Read totalSupply (supply) and totalAssets (assets in vault).
    ///
    ///   2. If supply == 0 (empty vault), return assets directly (1:1 ratio).
    ///      → First depositor: 1000 assets → 1000 shares.
    ///
    ///   3. Otherwise, use Math.mulDiv with rounding:
    ///      shares = Math.mulDiv(assets, supply, totalAssets(), rounding)
    ///
    ///      Math.mulDiv(a, b, c, rounding) computes (a × b / c) with full
    ///      512-bit intermediate precision. The rounding parameter controls
    ///      whether the result rounds down (Floor) or up (Ceil).
    ///
    ///   Example at rate 1.1 (totalAssets=3300, totalSupply=3000):
    ///      _convertToShares(1100, Floor) = mulDiv(1100, 3000, 3300, Floor) = 1000
    ///
    /// See: Module 7 — "The Share Math"
    ///
    /// @param assets The amount of underlying assets.
    /// @param rounding Floor for deposit (fewer shares), Ceil for withdraw (more shares burned).
    /// @return shares The equivalent amount of vault shares.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement _convertToAssets — shares → assets
    // =============================================================
    /// @notice Convert a share amount to assets, with explicit rounding.
    /// @dev Inverse of _convertToShares.
    ///
    /// Logic:
    ///   1. Read totalSupply (supply) and totalAssets (total in vault).
    ///
    ///   2. If supply == 0 (empty vault), return shares directly (1:1 ratio).
    ///
    ///   3. Otherwise, use Math.mulDiv with rounding:
    ///      assets = Math.mulDiv(shares, totalAssets(), supply, rounding)
    ///
    ///   Example at rate 1.1 (totalAssets=3300, totalSupply=3000):
    ///      _convertToAssets(1000, Floor) = mulDiv(1000, 3300, 3000, Floor) = 1100
    ///
    ///   Rounding direction:
    ///      Floor for redeem (user gets fewer assets)
    ///      Ceil for mint (user pays more assets)
    ///
    /// See: Module 7 — "The Share Math"
    ///
    /// @param shares The amount of vault shares.
    /// @param rounding Floor for redeem (fewer assets), Ceil for mint (more assets paid).
    /// @return assets The equivalent amount of underlying assets.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement deposit — deposit assets, receive shares
    // =============================================================
    /// @notice Deposit exact assets, receive proportional shares.
    /// @dev The caller must have approved this contract to spend their assets.
    ///
    /// Steps:
    ///   1. Compute shares using previewDeposit(assets):
    ///      shares = previewDeposit(assets)
    ///      → Uses _convertToShares with Floor rounding (fewer shares = vault-favorable)
    ///
    ///   2. Transfer assets from caller to vault:
    ///      asset.safeTransferFrom(msg.sender, address(this), assets)
    ///
    ///   3. Mint shares to receiver:
    ///      _mint(receiver, shares)
    ///
    ///   4. Return shares.
    ///
    ///   Order matters: compute shares BEFORE transferring assets, because
    ///   totalAssets() changes after the transfer (it reads balanceOf).
    ///
    ///   Example (empty vault):
    ///      deposit(1000e18, alice) → transfers 1000 tokens, mints 1000 shares
    ///
    ///   Example (rate 1.1):
    ///      deposit(1100e18, alice) → transfers 1100 tokens, mints 1000 shares
    ///
    /// See: Module 7 — "Deposit flow (assets → shares)"
    ///
    /// @param assets The exact amount of underlying assets to deposit.
    /// @param receiver The address to receive the minted shares.
    /// @return shares The amount of shares minted to the receiver.
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement withdraw — withdraw assets, burn shares
    // =============================================================
    /// @notice Withdraw exact assets by burning proportional shares.
    /// @dev Only the owner can withdraw their own shares (simplified — no allowance).
    ///
    /// Steps:
    ///   1. Require msg.sender == owner (simplified access control).
    ///
    ///   2. Compute shares to burn using previewWithdraw(assets):
    ///      shares = previewWithdraw(assets)
    ///      → Uses _convertToShares with Ceil rounding (more shares burned = vault-favorable)
    ///
    ///   3. Burn shares from owner:
    ///      _burn(owner, shares)
    ///
    ///   4. Transfer assets to receiver:
    ///      asset.safeTransfer(receiver, assets)
    ///
    ///   5. Return shares.
    ///
    ///   Note the rounding difference vs deposit:
    ///      deposit  → _convertToShares(Floor) → user gets FEWER shares
    ///      withdraw → _convertToShares(Ceil)  → user burns MORE shares
    ///   Both favor the vault. This is the vault's "bid/ask spread."
    ///
    ///   Example (rate 1.1, totalAssets=3300, totalSupply=3000):
    ///      withdraw(1100e18, alice, alice) → burns 1000 shares, transfers 1100 tokens
    ///
    /// See: Module 7 — "Withdraw flow (shares → assets)"
    ///
    /// @param assets The exact amount of underlying assets to withdraw.
    /// @param receiver The address to receive the withdrawn assets.
    /// @param owner The address whose shares will be burned.
    /// @return shares The amount of shares burned from the owner.
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        revert("Not implemented");
    }

    // ── Pre-built: mint and redeem ──────────────────────────────────────
    // These use your conversion functions. Once TODOs 1-2 are done, these work.
    // Study them to see the other rounding directions:
    //   mint  → _convertToAssets(Ceil)  → user pays MORE assets
    //   redeem → _convertToAssets(Floor) → user gets FEWER assets

    /// @notice Mint exact shares by depositing proportional assets.
    /// @dev Inverse of deposit: specify shares, compute assets.
    ///      Uses Ceil rounding → user pays more assets (vault-favorable).
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @notice Redeem exact shares for proportional assets.
    /// @dev Inverse of withdraw: specify shares, compute assets.
    ///      Uses Floor rounding → user gets fewer assets (vault-favorable).
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        require(msg.sender == owner, "SimpleVault: not owner");
        assets = previewRedeem(shares);
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }
}

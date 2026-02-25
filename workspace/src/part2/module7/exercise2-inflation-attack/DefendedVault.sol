// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ============================================================================
//  EXERCISE: DefendedVault — Virtual Shares Inflation Defense
// ============================================================================
//
//  The NaiveVault is vulnerable to the inflation (first-depositor) attack:
//    1. Attacker deposits 1 wei → gets 1 share
//    2. Attacker donates 10,000 USDC directly via transfer()
//    3. Victim deposits 20,000 USDC → gets only 1 share (rounded down)
//    4. Attacker redeems → steals ~5,000 USDC from the victim
//
//  Your task: implement OpenZeppelin's virtual shares defense.
//
//  The idea: add "virtual" shares and assets to the conversion formula so
//  that even an empty vault behaves as if it already has deposits. This
//  dilutes the attacker's donation across the virtual shares, making the
//  attack unprofitable.
//
//  Standard formula (NaiveVault):
//    shares = assets × totalSupply / totalAssets
//
//  Defended formula (with virtual shares):
//    shares = assets × (totalSupply + virtualShareOffset) / (totalAssets + 1)
//    assets = shares × (totalAssets + 1) / (totalSupply + virtualShareOffset)
//
//  With decimalsOffset = 3 → virtualShareOffset = 10^3 = 1000.
//  The attacker's donation is spread across 1000 virtual shares, not just 1
//  real share, so the victim still gets a fair number of shares.
//
//  Key insight: NO empty-vault special case is needed! When totalSupply = 0
//  and totalAssets = 0, the formula gives:
//    shares = assets × (0 + 1000) / (0 + 1) = assets × 1000
//  The first depositor gets assets × 1000 shares — a scaling factor, but
//  the rates still work correctly for subsequent deposits and redemptions.
//
//  Run:
//    forge test --match-contract InflationAttackTest -vvv
//
// ============================================================================

/// @notice ERC-4626-style vault with virtual shares inflation defense.
/// @dev Exercise for Module 7: Vaults & Yield (Inflation Attack).
///      Students implement: _convertToShares, _convertToAssets.
///      Pre-built: deposit, redeem, constructor, totalAssets.
contract DefendedVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    uint256 public immutable virtualShareOffset; // 10 ** decimalsOffset

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint8 decimalsOffset_
    ) ERC20(name_, symbol_) {
        asset = asset_;
        virtualShareOffset = 10 ** decimalsOffset_;
    }

    /// @notice Total assets = actual token balance (same as NaiveVault).
    /// @dev The defense is in the conversion math, not in totalAssets().
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // =============================================================
    //  TODO 1: Implement _convertToShares — with virtual shares
    // =============================================================
    /// @notice Convert assets to shares using the virtual shares formula.
    /// @dev Compare with NaiveVault's formula:
    ///
    ///   NaiveVault (vulnerable):
    ///      shares = mulDiv(assets, totalSupply, totalAssets)
    ///
    ///   DefendedVault (your implementation):
    ///      shares = mulDiv(assets, totalSupply() + virtualShareOffset, totalAssets() + 1, rounding)
    ///
    ///   The + virtualShareOffset adds "phantom" shares to the numerator.
    ///   The + 1 adds a "phantom" asset to the denominator.
    ///   Together they ensure the conversion ratio is never trivially small,
    ///   even when totalSupply = 0.
    ///
    ///   Why it works:
    ///     After attacker donates 10,000 USDC (totalAssets ≈ 10,000e6, supply = 1000):
    ///     Victim deposits 20,000e6:
    ///       shares = 20,000e6 × (1000 + 1000) / (10,000e6 + 1) ≈ 4,000,000
    ///     Victim gets ~4M shares vs attacker's 1000 — attack is unprofitable!
    ///
    ///   No empty-vault special case needed:
    ///     First deposit: mulDiv(assets, 0 + 1000, 0 + 1) = assets × 1000
    ///
    /// See: Module 7 — "Defense 1: Virtual Shares and Assets"
    ///      OpenZeppelin ERC4626._convertToShares()
    ///
    /// @param assets The amount of underlying assets.
    /// @param rounding Floor for deposit, Ceil for withdraw.
    /// @return The equivalent amount of vault shares.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement _convertToAssets — with virtual shares
    // =============================================================
    /// @notice Convert shares to assets using the virtual shares formula.
    /// @dev The inverse of _convertToShares:
    ///
    ///   assets = mulDiv(shares, totalAssets() + 1, totalSupply() + virtualShareOffset, rounding)
    ///
    ///   Note the + 1 and + virtualShareOffset are swapped compared to
    ///   _convertToShares (numerator ↔ denominator).
    ///
    /// See: Module 7 — "Defense 1: Virtual Shares and Assets"
    ///
    /// @param shares The amount of vault shares.
    /// @param rounding Floor for redeem, Ceil for mint.
    /// @return The equivalent amount of underlying assets.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        revert("Not implemented");
    }

    // ── Pre-built: deposit and redeem ───────────────────────────────────
    // These call your conversion functions. Once TODOs 1-2 are done, they work.

    /// @notice Deposit assets, receive shares. Uses _convertToShares (Floor).
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Floor);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @notice Redeem shares for assets. Uses _convertToAssets (Floor).
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "DefendedVault: not owner");
        assets = _convertToAssets(shares, Math.Rounding.Floor);
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }
}

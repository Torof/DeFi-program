// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Intentionally vulnerable vault — students do NOT modify this.
/// @dev Uses balanceOf for totalAssets (vulnerable to donation attacks).
///      No virtual shares/assets offset (the ERC-4626 defense is missing).
///
///      The vulnerability: anyone can transfer tokens directly to this contract,
///      inflating totalAssets() without minting shares. When subsequent depositors
///      deposit, their shares round to 0 (stolen by existing shareholders).
///
///      This is the simplified version of the vulnerability that led to real
///      exploits in production vaults. The defense (virtual shares/assets offset)
///      is covered in Module 7 (Yield/Vaults).
contract VulnerableVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    /// @notice Deposit tokens and receive shares.
    /// @dev VULNERABLE: When totalAssets is inflated by donation,
    ///      new deposits can round to 0 shares. A safe vault would
    ///      revert when shares == 0, or use virtual shares/assets.
    function deposit(uint256 assets) external returns (uint256 shares) {
        if (totalShares == 0) {
            shares = assets; // First deposit: 1:1
        } else {
            // BUG: totalAssets() uses balanceOf — can be inflated via donation
            // BUG: No check for shares > 0 — depositor can lose funds
            shares = assets * totalShares / totalAssets();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
        sharesOf[msg.sender] += shares;
        totalShares += shares;
    }

    /// @notice Withdraw shares and receive tokens.
    function withdraw(uint256 shares) external returns (uint256 assets) {
        require(shares > 0 && shares <= sharesOf[msg.sender], "Invalid shares");

        assets = shares * totalAssets() / totalShares;

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;

        asset.safeTransfer(msg.sender, assets);
    }

    /// @notice Total assets in the vault.
    /// @dev VULNERABLE: Uses balanceOf instead of internal accounting.
    ///      Anyone can inflate this by transferring tokens directly.
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

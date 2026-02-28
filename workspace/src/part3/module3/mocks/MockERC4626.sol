// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal ERC-4626-like vault mock for yield tokenization exercises.
/// @dev Has a controllable exchange rate via `setExchangeRate()`.
///      The exchange rate represents how many underlying tokens each share is worth.
///      Starts at 1:1 (1e18). Test helper increases it to simulate yield accrual.
///      Simplified: no actual deposit/withdraw of underlying — just mint/burn shares
///      and track exchange rate for yield math.
contract MockERC4626 is ERC20 {
    IERC20 public immutable asset;
    uint256 private _exchangeRate; // WAD (1e18 = 1:1)

    constructor(address asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        asset = IERC20(asset_);
        _exchangeRate = 1e18; // Start at 1:1
    }

    // --- ERC-4626-like interface ---

    /// @notice How many underlying tokens `shares` vault shares are worth.
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * _exchangeRate / 1e18;
    }

    /// @notice How many vault shares you'd get for `assets` underlying tokens.
    function convertToShares(uint256 assets) external view returns (uint256) {
        return assets * 1e18 / _exchangeRate;
    }

    /// @notice Current exchange rate (underlying per share), 18 decimals.
    function exchangeRate() external view returns (uint256) {
        return _exchangeRate;
    }

    // --- Test helpers ---

    /// @notice Set the exchange rate to simulate yield accrual.
    /// @param newRate New rate in WAD (e.g., 1.05e18 = 5% yield accrued)
    function setExchangeRate(uint256 newRate) external {
        _exchangeRate = newRate;
    }

    /// @notice Mint vault shares to an address (for test setup).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn vault shares from an address.
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

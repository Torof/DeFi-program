// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Naive yield harvester that deposits pending tokens into a vault.
/// @dev Pre-built — students do NOT modify this.
///
///      Represents an auto-compounder or yield aggregator that periodically
///      deposits accumulated yield into a vault. The harvest() function is
///      callable by anyone (common pattern for keeper bots).
///
///      VULNERABILITY: If the vault's share price is inflated before harvest()
///      is called, the deposited tokens receive 0 shares (rounding attack).
///      The attacker can then withdraw the harvester's tokens.
contract YieldHarvester {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public immutable vault;

    constructor(address asset_, address vault_) {
        asset = IERC20(asset_);
        vault = vault_;
    }

    /// @notice Deposit all pending tokens into the vault.
    /// @dev Anyone can call this (common for keeper-triggered auto-compounders).
    function harvest() external {
        uint256 pending = asset.balanceOf(address(this));
        if (pending > 0) {
            asset.forceApprove(vault, pending);
            IVault(vault).deposit(pending);
        }
    }
}

interface IVault {
    function deposit(uint256 assets) external returns (uint256 shares);
}

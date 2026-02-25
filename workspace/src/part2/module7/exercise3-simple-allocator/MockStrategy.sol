// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built mock strategy for the SimpleAllocator exercise.
//  A minimal strategy that holds tokens and reports its balance as totalValue.
//  Yield is simulated in tests by minting tokens directly to this contract.
// ============================================================================

/// @notice Minimal strategy mock — holds assets, reports balance as value.
/// @dev Used by SimpleAllocator tests. NOT an ERC-4626 vault — just a
///      deposit/withdraw wrapper around token holding.
contract MockStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    /// @notice Total value of assets held by this strategy.
    /// @dev Simply returns the token balance. Yield is simulated by minting
    ///      tokens to this contract in tests.
    function totalValue() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Deposit assets into the strategy.
    /// @dev Pulls tokens from caller via safeTransferFrom.
    function deposit(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw assets from the strategy.
    /// @dev Sends tokens to caller.
    function withdraw(uint256 amount) external {
        asset.safeTransfer(msg.sender, amount);
    }
}

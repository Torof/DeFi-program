// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Simple Vault with Fuzz and Invariant Testing
//
// Build a basic ERC-4626-style vault that accepts deposits of a single token
// and issues shares. This exercise focuses on testing patterns (fuzz and
// invariant) rather than advanced vault features.
//
// Day 12: Master fuzz and invariant testing.
//
// Run: forge test --match-contract SimpleVaultTest -vvv
// Run: forge test --match-test invariant -vvv
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Custom Errors ---
error ZeroAmount();
error ZeroAddress();
error InsufficientShares();
error InsufficientAssets();
error TransferFailed();

// =============================================================
//  TODO 1: Implement SimpleVault
// =============================================================
/// @notice Simple vault that accepts ERC-20 deposits and issues shares.
/// @dev Simplified ERC-4626 pattern for testing exercises.
// See: Module 5 > Fuzz Testing (#fuzz-testing)
// See: Module 5 > Invariant Testing (#invariant-testing)
contract SimpleVault {
    IERC20 public immutable asset;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 shares, uint256 assets);

    constructor(IERC20 _asset) {
        if (_asset == IERC20(address(0))) revert ZeroAddress();
        asset = _asset;
    }

    // =============================================================
    //  TODO 2: Implement deposit
    // =============================================================
    /// @notice Deposits assets and mints shares.
    /// @param assets Amount of assets to deposit
    /// @return shares Amount of shares minted
    function deposit(uint256 assets) external returns (uint256 shares) {
        // TODO: Implement
        // 1. Validate assets > 0 (revert ZeroAmount if not)
        // 2. Calculate shares to mint:
        //    - If totalSupply == 0: shares = assets (1:1 initial rate)
        //    - Else: shares = (assets * totalSupply) / totalAssets()
        // 3. Mint shares: balanceOf[msg.sender] += shares
        // 4. Increment totalSupply by shares
        // 5. Transfer assets from user: asset.transferFrom(msg.sender, address(this), assets)
        //    Validate transfer succeeded (revert TransferFailed if not)
        // 6. Emit Deposit event
        // 7. Return shares
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement withdraw
    // =============================================================
    /// @notice Burns shares and withdraws assets.
    /// @param shares Amount of shares to burn
    /// @return assets Amount of assets withdrawn
    function withdraw(uint256 shares) external returns (uint256 assets) {
        // TODO: Implement
        // 1. Validate shares > 0 (revert ZeroAmount if not)
        // 2. Validate user has enough shares: balanceOf[msg.sender] >= shares
        //    (revert InsufficientShares if not)
        // 3. Calculate assets to return:
        //    assets = (shares * totalAssets()) / totalSupply
        // 4. Validate assets > 0 (revert InsufficientAssets if not)
        // 5. Burn shares: balanceOf[msg.sender] -= shares
        // 6. Decrement totalSupply by shares
        // 7. Transfer assets to user: asset.transfer(msg.sender, assets)
        //    Validate transfer succeeded (revert TransferFailed if not)
        // 8. Emit Withdraw event
        // 9. Return assets
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement view functions
    // =============================================================

    /// @notice Returns total assets held by vault.
    function totalAssets() public view returns (uint256) {
        // TODO: Return asset.balanceOf(address(this))
        revert("Not implemented");
    }

    /// @notice Converts assets to shares.
    /// @param assets Amount of assets
    /// @return shares Equivalent shares
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        // TODO: Implement
        // If totalSupply == 0: return assets
        // Else: return (assets * totalSupply) / totalAssets()
        revert("Not implemented");
    }

    /// @notice Converts shares to assets.
    /// @param shares Amount of shares
    /// @return assets Equivalent assets
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        // TODO: Implement
        // If totalSupply == 0: return 0
        // Else: return (shares * totalAssets()) / totalSupply
        revert("Not implemented");
    }

    /// @notice Preview deposit (how many shares for given assets).
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        // TODO: Return convertToShares(assets)
        revert("Not implemented");
    }

    /// @notice Preview withdraw (how many assets for given shares).
    function previewWithdraw(uint256 shares) external view returns (uint256 assets) {
        // TODO: Return convertToAssets(shares)
        revert("Not implemented");
    }
}

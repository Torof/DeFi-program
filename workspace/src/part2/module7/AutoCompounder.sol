// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockSwap} from "./MockSwap.sol";

// ============================================================================
//  EXERCISE: AutoCompounder — Harvest + Profit Unlocking
// ============================================================================
//
//  Build an ERC-4626-style vault that earns rewards in a separate token,
//  harvests them (swap → underlying asset), and UNLOCKS profit linearly
//  over time to prevent sandwich attacks.
//
//  The problem (without profit unlocking):
//    1. Vault has 10,000 USDC, 10,000 shares (rate = 1.0)
//    2. Strategy earned 600 USDC in rewards (not yet harvested)
//    3. Attacker deposits 10,000 USDC → gets 10,000 shares
//    4. harvest() executes → totalAssets jumps to 20,600
//    5. Attacker redeems → gets 10,300 USDC (profit = 300!)
//    Attacker captured 50% of the yield by holding for ONE BLOCK.
//
//  The solution (profit unlocking):
//    After harvest, the new profit is LOCKED. It unlocks linearly over
//    profitUnlockTime (e.g., 6 hours). totalAssets() subtracts the still-
//    locked portion, so the share price rises gradually — not instantly.
//
//    Same attack with profit unlocking:
//    1. Attacker deposits 10,000 → 10,000 shares (rate 1.0)
//    2. harvest() → profit locked, totalAssets unchanged, rate still 1.0
//    3. Attacker redeems → gets 10,000 USDC (profit = 0!)
//    Only depositors who STAY earn the gradually-unlocking yield.
//
//  The mechanism:
//    totalAssets() = asset.balanceOf(this) - _lockedProfit()
//
//    _lockedProfit() decreases linearly from lockedProfitAtHarvest to 0
//    over profitUnlockTime seconds. As locked profit decreases, totalAssets
//    increases, and share price rises smoothly.
//
//  Run:
//    forge test --match-contract AutoCompounderTest -vvv
//
// ============================================================================

/// @notice ERC-4626-style vault with harvest + linear profit unlocking.
/// @dev Exercise for Module 7: Vaults & Yield (Auto-Compounding).
///      Students implement: _lockedProfit, totalAssets, harvest.
///      Pre-built: deposit, redeem, _convertToShares, _convertToAssets.
contract AutoCompounder is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    IERC20 public immutable rewardToken;
    MockSwap public immutable swapRouter;

    /// @notice Duration over which harvested profit unlocks linearly.
    uint256 public immutable profitUnlockTime;

    /// @notice Timestamp of the last harvest() call.
    uint256 public lastHarvestTimestamp;

    /// @notice Profit that was locked at the last harvest.
    /// @dev Decreases linearly over profitUnlockTime via _lockedProfit().
    uint256 public lockedProfitAtHarvest;

    constructor(
        IERC20 asset_,
        IERC20 rewardToken_,
        MockSwap swapRouter_,
        uint256 profitUnlockTime_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        asset = asset_;
        rewardToken = rewardToken_;
        swapRouter = swapRouter_;
        profitUnlockTime = profitUnlockTime_;
    }

    // =============================================================
    //  TODO 1: Implement _lockedProfit — linear unlock calculation
    // =============================================================
    /// @notice How much harvested profit is still locked (not yet in totalAssets).
    /// @dev The profit unlocks linearly from lockedProfitAtHarvest to 0
    ///      over profitUnlockTime seconds since lastHarvestTimestamp.
    ///
    ///   Steps:
    ///     1. Compute elapsed time since last harvest:
    ///        elapsed = block.timestamp - lastHarvestTimestamp
    ///
    ///     2. If elapsed >= profitUnlockTime → return 0 (fully unlocked).
    ///        This also handles the case where no harvest has happened yet
    ///        (lastHarvestTimestamp = 0, elapsed is very large → return 0).
    ///
    ///     3. Otherwise, compute remaining locked profit:
    ///        lockedProfitAtHarvest × (profitUnlockTime - elapsed) / profitUnlockTime
    ///
    ///   Example (profitUnlockTime = 6 hours = 21,600s):
    ///     lockedProfitAtHarvest = 600e18, elapsed = 3 hours (10,800s):
    ///       locked = 600e18 × (21,600 - 10,800) / 21,600 = 300e18
    ///     After 6 hours: elapsed >= 21,600 → locked = 0 (fully unlocked)
    ///
    ///   The linear decrease means totalAssets() increases smoothly over time,
    ///   creating a gradual share price rise instead of a sudden jump.
    ///
    /// See: Module 7 — "Profit Unlocking — Numeric Walkthrough"
    ///
    /// @return The amount of profit still locked.
    function _lockedProfit() internal view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement totalAssets — balance minus locked profit
    // =============================================================
    /// @notice Total assets available to shareholders.
    /// @dev Unlike SimpleVault (which returns raw balanceOf), this vault
    ///      SUBTRACTS locked profit so the share price rises gradually.
    ///
    ///   Formula:
    ///     asset.balanceOf(address(this)) - _lockedProfit()
    ///
    ///   Why this works:
    ///     After harvest, the actual balance jumps (tokens received from swap),
    ///     but _lockedProfit() equals the new profit — so totalAssets() stays
    ///     the same as before harvest. Over profitUnlockTime, _lockedProfit()
    ///     decreases to 0, and totalAssets() gradually rises to the full balance.
    ///
    ///   Timeline after harvest of 600 profit (vault had 10,000):
    ///     T=0h: balance=10,600 | locked=600 | totalAssets=10,000 (unchanged!)
    ///     T=3h: balance=10,600 | locked=300 | totalAssets=10,300
    ///     T=6h: balance=10,600 | locked=0   | totalAssets=10,600 (fully unlocked)
    ///
    /// See: Module 7 — "How the unlock works mechanically"
    ///
    /// @return The total assets backing all outstanding shares.
    function totalAssets() public view returns (uint256) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement harvest — swap rewards + record profit
    // =============================================================
    /// @notice Harvest accumulated reward tokens: swap to asset, lock profit.
    /// @dev This is the auto-compounding step. Anyone can call it (keeper bot).
    ///
    ///   Steps:
    ///     1. Get reward token balance:
    ///        uint256 rewardBalance = rewardToken.balanceOf(address(this))
    ///
    ///     2. Require rewardBalance > 0 (nothing to harvest otherwise).
    ///
    ///     3. Approve swap router and swap rewards for asset:
    ///        rewardToken.approve(address(swapRouter), rewardBalance)
    ///        received = swapRouter.swap(rewardToken, asset, rewardBalance)
    ///
    ///     4. Lock the profit — COMBINE with any still-locked profit:
    ///        lockedProfitAtHarvest = received + _lockedProfit()
    ///
    ///        Why combine? If a second harvest happens before the first fully
    ///        unlocks, the remaining locked profit carries over. This prevents
    ///        a gap where some profit "disappears" from the accounting.
    ///
    ///        Example:
    ///          T=0: Harvest 600 → locked = 600
    ///          T=3h: _lockedProfit() = 300 (half unlocked)
    ///          T=3h: Harvest 400 → locked = 400 + 300 = 700
    ///          The 300 already unlocked stays in totalAssets.
    ///          The 700 (new 400 + remaining 300) restarts the unlock timer.
    ///
    ///     5. Record harvest timestamp:
    ///        lastHarvestTimestamp = block.timestamp
    ///
    /// See: Module 7 — "Pattern 1: Auto-Compounding"
    ///
    /// @return received The amount of asset received from the swap.
    function harvest() external returns (uint256 received) {
        revert("Not implemented");
    }

    // ── Pre-built: deposit, redeem, conversions ───────────────────────────

    /// @notice Deposit assets, receive shares. First deposit is 1:1.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Floor);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// @notice Redeem shares for assets.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "AutoCompounder: not owner");
        assets = _convertToAssets(shares, Math.Rounding.Floor);
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }

    /// @notice Convert assets to shares.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets(), rounding);
    }

    /// @notice Convert shares to assets.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : Math.mulDiv(shares, totalAssets(), supply, rounding);
    }
}

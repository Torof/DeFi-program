// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  EXERCISE: DefendedRewardPool — Fix the Precision Loss Vulnerability
// ============================================================================
//
//  NaiveRewardPool loses rewards because rewardPerTokenStored is unscaled:
//    rewardPerTokenStored += rewardAmount / totalStaked    ← truncates!
//
//  The fix: scale the accumulator by 1e18 BEFORE dividing:
//    rewardPerTokenStored += rewardAmount * 1e18 / totalStaked   ← precise!
//
//  Then when calculating earned(), divide by 1e18:
//    earned = staked * (rewardPerToken - paid) / 1e18
//
//  This is the standard Synthetix StakingRewards pattern — used by virtually
//  every production reward pool in DeFi.
//
//  Your task: implement notifyReward() and earned() with scaled math.
//
//  Run:
//    forge test --match-contract PrecisionLossTest -vvv
//
// ============================================================================

/// @notice Staking pool with precision-safe reward distribution.
/// @dev Exercise for Module 8: DeFi Security (Precision Loss).
///      Student implements: notifyReward(), earned().
///      Pre-built: stake(), unstake(), claimReward(), _updateReward().
contract DefendedRewardPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public totalStaked;
    mapping(address => uint256) public staked;

    /// @dev SCALED accumulator — stores rewardPerToken * 1e18.
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public owner;

    uint256 internal constant PRECISION = 1e18;

    constructor(IERC20 stakingToken_, IERC20 rewardToken_) {
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement notifyReward — with scaled accumulator
    // =============================================================
    /// @notice Distribute rewards with precision-safe math.
    /// @dev Scale the accumulator by PRECISION (1e18) before dividing:
    ///
    ///   require(msg.sender == owner, "not owner");
    ///   if (totalStaked > 0) {
    ///       rewardPerTokenStored += rewardAmount * PRECISION / totalStaked;
    ///   }
    ///
    /// Why this works:
    ///   Without scaling: 10_000 / 5000e18 = 0  (truncated)
    ///   With scaling:    10_000 * 1e18 / 5000e18 = 1e22 / 5e21 = 2 (preserved!)
    ///   earned = 5000e18 * 2 / 1e18 = 10_000  (full reward recovered)
    ///
    /// See: Module 8 — "Precision Loss and Rounding Exploits"
    ///      Synthetix StakingRewards: https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
    function notifyReward(uint256 rewardAmount) external {
        // TODO: implement
    }

    // =============================================================
    //  TODO 2: Implement earned — with scaled math
    // =============================================================
    /// @notice View: pending reward for a user (precision-safe).
    /// @dev Since rewardPerTokenStored is scaled by 1e18, divide by
    ///      PRECISION when calculating the actual reward:
    ///
    ///   return staked[account]
    ///       * (rewardPerTokenStored - userRewardPerTokenPaid[account])
    ///       / PRECISION
    ///       + rewards[account];
    ///
    /// See: Synthetix StakingRewards earned() function
    function earned(address account) public view returns (uint256) {
        // TODO: implement
        return 0;
    }

    /// @notice Stake tokens into the pool.
    function stake(uint256 amount) external {
        _updateReward(msg.sender);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        totalStaked += amount;
    }

    /// @notice Unstake tokens from the pool.
    function unstake(uint256 amount) external {
        _updateReward(msg.sender);
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
    }

    /// @notice Claim accumulated rewards.
    function claimReward() external {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
        }
    }

    function _updateReward(address account) internal {
        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
}

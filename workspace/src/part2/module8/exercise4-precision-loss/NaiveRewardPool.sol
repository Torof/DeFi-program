// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built reward pool with a precision loss vulnerability.
//
//  This pool distributes rewards proportionally to stakers via a
//  rewardPerTokenStored accumulator. The bug: the accumulator is NOT scaled,
//  so when totalStaked is large relative to the reward amount, the division
//  truncates to zero and rewards are silently lost.
//
//  Example: 100 wei reward / 1000e18 totalStaked = 0 (truncated!)
//  Those 100 wei are stuck in the contract forever.
//
//  Your job:
//    1. Build RoundingExploit.sol — exploit the truncation to steal rewards
//    2. Build DefendedRewardPool.sol — fix it with scaled math
// ============================================================================

/// @notice Staking pool with a precision loss bug in reward distribution.
/// @dev The rewardPerTokenStored accumulator is unscaled — division truncates
///      when totalStaked >> rewardAmount.
contract NaiveRewardPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public totalStaked;
    mapping(address => uint256) public staked;

    /// @dev UNSCALED accumulator — this is the bug.
    /// rewardPerTokenStored += rewardAmount / totalStaked
    /// When totalStaked > rewardAmount, this truncates to 0.
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public owner;

    constructor(IERC20 stakingToken_, IERC20 rewardToken_) {
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        owner = msg.sender;
    }

    /// @notice Distribute rewards — called by owner after transferring reward tokens.
    /// @dev BUG: rewardAmount / totalStaked truncates when totalStaked is large.
    function notifyReward(uint256 rewardAmount) external {
        require(msg.sender == owner, "not owner");
        if (totalStaked > 0) {
            // BUG: no scaling factor — truncates to 0 when totalStaked > rewardAmount
            rewardPerTokenStored += rewardAmount / totalStaked;
        }
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

    /// @notice View: pending reward for a user.
    function earned(address account) public view returns (uint256) {
        return staked[account] * (rewardPerTokenStored - userRewardPerTokenPaid[account])
            + rewards[account];
    }

    function _updateReward(address account) internal {
        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the PrecisionLoss
//  exercise. Implement RoundingExploit.sol and DefendedRewardPool.sol to make
//  the tests pass.
//
//  Test 1: Demonstrates the truncation bug in NaiveRewardPool.
//  Test 2: Verifies RoundingExploit captures rewards via tiny stake.
//  Test 3: Verifies DefendedRewardPool distributes rewards precisely.
//  Test 4: Verifies DefendedRewardPool handles small rewards + large stakes.
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module8/mocks/MockERC20.sol";
import {NaiveRewardPool} from "../../../../src/part2/module8/exercise4-precision-loss/NaiveRewardPool.sol";
import {DefendedRewardPool} from "../../../../src/part2/module8/exercise4-precision-loss/DefendedRewardPool.sol";
import {RoundingExploit} from "../../../../src/part2/module8/exercise4-precision-loss/RoundingExploit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PrecisionLossTest is Test {
    MockERC20 stakingToken;
    MockERC20 rewardToken;
    NaiveRewardPool naivePool;
    DefendedRewardPool defendedPool;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant REWARD_AMOUNT = 1_000e18;

    function setUp() public {
        stakingToken = new MockERC20("Staking Token", "STK", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);

        naivePool = new NaiveRewardPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken))
        );

        defendedPool = new DefendedRewardPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken))
        );

        // Fund pools with reward tokens
        rewardToken.mint(address(naivePool), 10_000e18);
        rewardToken.mint(address(defendedPool), 10_000e18);

        // Fund users with staking tokens
        stakingToken.mint(alice, 10_000e18);
        stakingToken.mint(bob, 10_000e18);

        // Approve staking
        vm.prank(alice);
        stakingToken.approve(address(naivePool), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(naivePool), type(uint256).max);

        vm.prank(alice);
        stakingToken.approve(address(defendedPool), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(defendedPool), type(uint256).max);
    }

    // =========================================================
    //  Demonstrates the truncation bug (no student code needed)
    // =========================================================

    function test_NaivePool_RewardsTruncatedToZero() public {
        // Alice and Bob both stake 5,000 tokens
        vm.prank(alice);
        naivePool.stake(5_000e18);
        vm.prank(bob);
        naivePool.stake(5_000e18);
        // totalStaked = 10,000e18

        // Distribute 100 wei of rewards (tiny amount)
        // rewardPerToken += 100 / 10_000e18 = 0  (TRUNCATED!)
        naivePool.notifyReward(100);

        // Neither user earned anything — 100 wei of rewards are stuck forever
        assertEq(
            naivePool.earned(alice),
            0,
            "Alice earned 0 - reward truncated to nothing"
        );
        assertEq(
            naivePool.earned(bob),
            0,
            "Bob earned 0 - reward truncated to nothing"
        );

        // The reward tokens are stuck in the contract — nobody can claim them
        assertEq(
            rewardToken.balanceOf(address(naivePool)),
            10_000e18,
            "Pool still holds all reward tokens (100 wei lost to truncation)"
        );
    }

    // =========================================================
    //  RoundingExploit: attacker captures rewards via tiny stake
    // =========================================================

    function test_RoundingExploit_CapturesRewards() public {
        // Deploy exploit contract
        RoundingExploit exploit = new RoundingExploit(
            naivePool,
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken))
        );

        // Fund attacker with just 1 wei of staking token
        stakingToken.mint(address(exploit), 1);

        // Step 1: Attacker stakes 1 wei (only staker → totalStaked = 1)
        exploit.attack(1);
        // After attack(): attacker is staked with 1 wei

        // Step 2: Owner distributes 1,000e18 reward tokens
        // rewardPerToken += 1000e18 / 1 = 1000e18 (NO truncation!)
        naivePool.notifyReward(REWARD_AMOUNT);

        // Step 3: Attacker claims and unstakes
        exploit.claimAndUnstake();

        // Attacker captured the full 1,000e18 reward with just 1 wei staked
        assertEq(
            rewardToken.balanceOf(address(exploit)),
            REWARD_AMOUNT,
            "Attacker should capture the full 1,000e18 reward"
        );

        // Attacker got their 1 wei stake back
        assertEq(
            stakingToken.balanceOf(address(exploit)),
            1,
            "Attacker should get staking token back"
        );

        // Now Alice stakes a large amount and more rewards are distributed
        vm.prank(alice);
        naivePool.stake(5_000e18);

        // Distribute another small reward: 100 wei
        // rewardPerToken += 100 / 5000e18 = 0 (TRUNCATED — Alice gets nothing)
        naivePool.notifyReward(100);

        assertEq(
            naivePool.earned(alice),
            0,
            "Alice earned 0 - small reward truncated with large totalStaked"
        );
    }

    // =========================================================
    //  DefendedRewardPool distributes rewards precisely
    // =========================================================

    function test_DefendedPool_DistributesRewardsPrecisely() public {
        // Alice and Bob both stake 5,000 tokens
        vm.prank(alice);
        defendedPool.stake(5_000e18);
        vm.prank(bob);
        defendedPool.stake(5_000e18);
        // totalStaked = 10,000e18

        // Distribute 1,000e18 rewards
        defendedPool.notifyReward(REWARD_AMOUNT);

        // Each user staked 50% → each should earn 500e18
        uint256 aliceEarned = defendedPool.earned(alice);
        uint256 bobEarned = defendedPool.earned(bob);

        assertEq(
            aliceEarned,
            500e18,
            "Alice should earn 500e18 (50% of 1,000e18 rewards)"
        );
        assertEq(
            bobEarned,
            500e18,
            "Bob should earn 500e18 (50% of 1,000e18 rewards)"
        );

        // Alice claims her reward
        vm.prank(alice);
        defendedPool.claimReward();

        assertEq(
            rewardToken.balanceOf(alice),
            500e18,
            "Alice should have received 500e18 reward tokens"
        );
    }

    // =========================================================
    //  DefendedRewardPool handles small rewards + large stakes
    // =========================================================

    function test_DefendedPool_HandlesSmallRewards() public {
        // Alice stakes 5,000e18
        vm.prank(alice);
        defendedPool.stake(5_000e18);

        // Distribute a tiny reward: 10,000 wei
        // Naive pool: 10_000 / 5000e18 = 0 (truncated)
        // Defended:   10_000 * 1e18 / 5000e18 = 1e22 / 5e21 = 2 (preserved!)
        defendedPool.notifyReward(10_000);

        // Alice should earn the 10,000 wei (she's the only staker)
        // earned = 5000e18 * 2 / 1e18 = 10_000
        uint256 aliceEarned = defendedPool.earned(alice);
        assertEq(
            aliceEarned,
            10_000,
            "Defended pool should preserve 10,000 wei reward (not truncate)"
        );

        // Bob joins and both get proportional rewards
        vm.prank(bob);
        defendedPool.stake(5_000e18);

        // Another 1,000e18 reward distributed — 50/50 split
        defendedPool.notifyReward(REWARD_AMOUNT);

        // Alice: 10_000 (from first) + 500e18 (from second)
        // Bob: 0 (wasn't staked for first) + 500e18 (from second)
        uint256 aliceTotal = defendedPool.earned(alice);
        uint256 bobTotal = defendedPool.earned(bob);

        assertEq(
            aliceTotal,
            500e18 + 10_000,
            "Alice should earn 10,000 wei + 500e18"
        );
        assertEq(
            bobTotal,
            500e18,
            "Bob should earn 500e18 (missed first reward)"
        );
    }
}

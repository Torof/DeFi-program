// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE - it is the test suite for the SimpleVoteEscrow
//  exercise. Implement SimpleVoteEscrow.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    SimpleVoteEscrow,
    ZeroAmount,
    LockTooShort,
    LockTooLong,
    LockAlreadyExists,
    NoLockFound,
    LockNotExpired,
    LockExpired,
    MustExtendLock,
    GaugeWeightExceeded
} from "../../../../src/part3/module8/exercise2-vote-escrow/SimpleVoteEscrow.sol";
import {MockERC20} from "../../../../src/part3/module5/mocks/MockERC20.sol";

contract SimpleVoteEscrowTest is Test {
    SimpleVoteEscrow public ve;
    MockERC20 public token;

    // Actors
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Gauges
    address gaugeA = makeAddr("gaugeA");
    address gaugeB = makeAddr("gaugeB");
    address gaugeC = makeAddr("gaugeC");

    uint256 constant LOCK_AMOUNT = 1000e18;
    uint256 constant MAX_LOCK = 4 * 365 days;

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp

        token = new MockERC20("Governance Token", "GOV", 18);
        ve = new SimpleVoteEscrow(address(token));

        // Give users tokens and approve
        token.mint(alice, 10_000e18);
        token.mint(bob, 10_000e18);

        vm.prank(alice);
        token.approve(address(ve), type(uint256).max);
        vm.prank(bob);
        token.approve(address(ve), type(uint256).max);
    }

    // =========================================================
    //  createLock (TODO 1)
    // =========================================================

    function test_createLock_storesCorrectly() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        (uint256 amount, uint256 end) = ve.locked(alice);
        assertEq(amount, LOCK_AMOUNT, "Locked amount should match");
        assertEq(end, block.timestamp + MAX_LOCK, "Lock end should be timestamp + duration");
    }

    function test_createLock_transfersTokens() public {
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        assertEq(token.balanceOf(alice), balanceBefore - LOCK_AMOUNT, "Tokens should transfer from user");
        assertEq(token.balanceOf(address(ve)), LOCK_AMOUNT, "Tokens should be held by escrow");
    }

    function test_createLock_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(ve));
        emit SimpleVoteEscrow.Locked(alice, LOCK_AMOUNT, block.timestamp + MAX_LOCK);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
    }

    function test_createLock_revertsForZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        ve.createLock(0, MAX_LOCK);
    }

    function test_createLock_revertsForTooShortDuration() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LockTooShort.selector, 1 days, 1 weeks));
        ve.createLock(LOCK_AMOUNT, 1 days);
    }

    function test_createLock_revertsForTooLongDuration() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LockTooLong.selector, MAX_LOCK + 1, MAX_LOCK));
        ve.createLock(LOCK_AMOUNT, MAX_LOCK + 1);
    }

    function test_createLock_revertsIfAlreadyLocked() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        vm.expectRevert(LockAlreadyExists.selector);
        ve.createLock(LOCK_AMOUNT, 1 weeks);
        vm.stopPrank();
    }

    function test_createLock_minimumDuration() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        (uint256 amount, uint256 end) = ve.locked(alice);
        assertEq(amount, LOCK_AMOUNT, "Should accept minimum duration");
        assertEq(end, block.timestamp + 1 weeks, "End time should be 1 week from now");
    }

    // =========================================================
    //  votingPower (TODO 2)
    // =========================================================

    function test_votingPower_maxAtMaxLock() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        uint256 power = ve.votingPower(alice);
        // At max lock, remaining = MAX_LOCK, so power = amount * MAX_LOCK / MAX_LOCK = amount
        assertEq(power, LOCK_AMOUNT, "Max lock should give max voting power");
    }

    function test_votingPower_halfDecay() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        // Advance half the lock period
        vm.warp(block.timestamp + MAX_LOCK / 2);

        uint256 power = ve.votingPower(alice);
        // remaining = MAX_LOCK / 2, power = amount * (MAX_LOCK/2) / MAX_LOCK = amount/2
        assertEq(power, LOCK_AMOUNT / 2, "Half decay should give half voting power");
    }

    function test_votingPower_zeroWhenExpired() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        // Advance past lock end
        vm.warp(block.timestamp + 2 weeks);

        uint256 power = ve.votingPower(alice);
        assertEq(power, 0, "Expired lock should have zero voting power");
    }

    function test_votingPower_zeroForNoLock() public view {
        uint256 power = ve.votingPower(bob);
        assertEq(power, 0, "No lock should have zero voting power");
    }

    function test_votingPower_proportionalToAmount() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        vm.prank(bob);
        ve.createLock(LOCK_AMOUNT * 2, MAX_LOCK);

        uint256 alicePower = ve.votingPower(alice);
        uint256 bobPower = ve.votingPower(bob);
        assertEq(bobPower, alicePower * 2, "Double amount at same duration = double power");
    }

    function test_votingPower_shortLockLessThanLongLock() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        vm.prank(bob);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        uint256 alicePower = ve.votingPower(alice);
        uint256 bobPower = ve.votingPower(bob);
        assertGt(bobPower, alicePower, "Longer lock should have more voting power");
    }

    // =========================================================
    //  increaseAmount (TODO 3)
    // =========================================================

    function test_increaseAmount_addsTokens() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.increaseAmount(500e18);
        vm.stopPrank();

        (uint256 amount,) = ve.locked(alice);
        assertEq(amount, LOCK_AMOUNT + 500e18, "Amount should increase");
    }

    function test_increaseAmount_preservesEndTime() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        (, uint256 endBefore) = ve.locked(alice);

        vm.warp(block.timestamp + 30 days);
        ve.increaseAmount(500e18);
        vm.stopPrank();

        (, uint256 endAfter) = ve.locked(alice);
        assertEq(endAfter, endBefore, "End time should not change");
    }

    function test_increaseAmount_increasesVotingPower() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        uint256 powerBefore = ve.votingPower(alice);

        ve.increaseAmount(500e18);
        uint256 powerAfter = ve.votingPower(alice);
        vm.stopPrank();

        assertGt(powerAfter, powerBefore, "Voting power should increase after adding tokens");
    }

    function test_increaseAmount_transfersTokens() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        uint256 balanceBefore = token.balanceOf(alice);
        ve.increaseAmount(500e18);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), balanceBefore - 500e18, "Additional tokens should transfer");
    }

    function test_increaseAmount_emitsEvent() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        vm.expectEmit(true, false, false, true, address(ve));
        emit SimpleVoteEscrow.AmountIncreased(alice, 500e18, LOCK_AMOUNT + 500e18);
        ve.increaseAmount(500e18);
        vm.stopPrank();
    }

    function test_increaseAmount_revertsIfNoLock() public {
        vm.prank(alice);
        vm.expectRevert(NoLockFound.selector);
        ve.increaseAmount(100e18);
    }

    function test_increaseAmount_revertsForZeroAmount() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        vm.expectRevert(ZeroAmount.selector);
        ve.increaseAmount(0);
        vm.stopPrank();
    }

    function test_increaseAmount_revertsIfLockExpired() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(alice);
        vm.expectRevert(LockExpired.selector);
        ve.increaseAmount(100e18);
    }

    // =========================================================
    //  increaseUnlockTime (TODO 4)
    // =========================================================

    function test_increaseUnlockTime_extendsLock() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, 1 * 365 days); // 1 year lock

        // After 6 months, extend to 3 years from now
        vm.warp(block.timestamp + 180 days);
        ve.increaseUnlockTime(3 * 365 days);
        vm.stopPrank();

        (, uint256 end) = ve.locked(alice);
        assertEq(end, block.timestamp + 3 * 365 days, "Lock end should update to new duration");
    }

    function test_increaseUnlockTime_increasesVotingPower() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, 1 * 365 days);

        vm.warp(block.timestamp + 180 days);
        uint256 powerBefore = ve.votingPower(alice);

        ve.increaseUnlockTime(3 * 365 days);
        uint256 powerAfter = ve.votingPower(alice);
        vm.stopPrank();

        assertGt(powerAfter, powerBefore, "Extending lock should increase voting power");
    }

    function test_increaseUnlockTime_emitsEvent() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, 1 * 365 days);

        vm.warp(block.timestamp + 180 days);
        uint256 newEnd = block.timestamp + 3 * 365 days;

        vm.expectEmit(true, false, false, true, address(ve));
        emit SimpleVoteEscrow.LockExtended(alice, newEnd);
        ve.increaseUnlockTime(3 * 365 days);
        vm.stopPrank();
    }

    function test_increaseUnlockTime_revertsIfNoLock() public {
        vm.prank(alice);
        vm.expectRevert(NoLockFound.selector);
        ve.increaseUnlockTime(2 * 365 days);
    }

    function test_increaseUnlockTime_revertsIfShorterThanCurrent() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, 2 * 365 days); // 2 year lock

        // Try to "extend" to 1 year from now (shorter than remaining ~2 years)
        uint256 newEnd = block.timestamp + 1 * 365 days;
        (, uint256 currentEnd) = ve.locked(alice);

        vm.expectRevert(abi.encodeWithSelector(MustExtendLock.selector, newEnd, currentEnd));
        ve.increaseUnlockTime(1 * 365 days);
        vm.stopPrank();
    }

    function test_increaseUnlockTime_revertsIfExceedsMaxLock() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, 1 * 365 days);

        vm.expectRevert(abi.encodeWithSelector(LockTooLong.selector, MAX_LOCK + 1, MAX_LOCK));
        ve.increaseUnlockTime(MAX_LOCK + 1);
        vm.stopPrank();
    }

    function test_increaseUnlockTime_revertsIfLockExpired() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(alice);
        vm.expectRevert(LockExpired.selector);
        ve.increaseUnlockTime(2 * 365 days);
    }

    // =========================================================
    //  voteForGauge (TODO 5)
    // =========================================================

    function test_voteForGauge_allocatesWeight() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 5000); // 50%
        vm.stopPrank();

        assertEq(ve.gaugeVotes(alice, gaugeA), 5000, "Should store gauge weight");
        assertEq(ve.userTotalGaugeWeight(alice), 5000, "Total weight should update");
    }

    function test_voteForGauge_multipleGauges() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 6000); // 60%
        ve.voteForGauge(gaugeB, 4000); // 40%
        vm.stopPrank();

        assertEq(ve.gaugeVotes(alice, gaugeA), 6000, "Gauge A = 60%");
        assertEq(ve.gaugeVotes(alice, gaugeB), 4000, "Gauge B = 40%");
        assertEq(ve.userTotalGaugeWeight(alice), 10_000, "Total = 100%");
    }

    function test_voteForGauge_emitsEvent() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        vm.expectEmit(true, true, false, true, address(ve));
        emit SimpleVoteEscrow.GaugeVoted(alice, gaugeA, 5000);
        ve.voteForGauge(gaugeA, 5000);
        vm.stopPrank();
    }

    function test_voteForGauge_revertsIfExceeds100Percent() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 6000); // 60%
        ve.voteForGauge(gaugeB, 4000); // 40% (total 100%)

        // Adding a third gauge would exceed 100%
        vm.expectRevert(abi.encodeWithSelector(GaugeWeightExceeded.selector, 11_000, 10_000));
        ve.voteForGauge(gaugeC, 1000);
        vm.stopPrank();
    }

    function test_voteForGauge_canUpdateExistingVote() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 6000); // 60%

        // Update gauge A from 60% to 30%
        ve.voteForGauge(gaugeA, 3000);
        vm.stopPrank();

        assertEq(ve.gaugeVotes(alice, gaugeA), 3000, "Should update to new weight");
        assertEq(ve.userTotalGaugeWeight(alice), 3000, "Total should reflect update");
    }

    function test_voteForGauge_canReallocateAfterUpdate() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 6000); // 60%
        ve.voteForGauge(gaugeB, 4000); // 40% (total 100%)

        // Reduce gauge A to 30%, freeing up 30%
        ve.voteForGauge(gaugeA, 3000);

        // Now allocate 30% to gauge C
        ve.voteForGauge(gaugeC, 3000);
        vm.stopPrank();

        assertEq(ve.userTotalGaugeWeight(alice), 10_000, "Total should be 100% again");
    }

    function test_voteForGauge_revertsIfNoLock() public {
        vm.prank(alice);
        vm.expectRevert(NoLockFound.selector);
        ve.voteForGauge(gaugeA, 5000);
    }

    function test_voteForGauge_canSetToZero() public {
        vm.startPrank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);
        ve.voteForGauge(gaugeA, 5000);

        // Remove vote by setting to 0
        ve.voteForGauge(gaugeA, 0);
        vm.stopPrank();

        assertEq(ve.gaugeVotes(alice, gaugeA), 0, "Should allow setting to zero");
        assertEq(ve.userTotalGaugeWeight(alice), 0, "Total should be zero");
    }

    // =========================================================
    //  withdraw (TODO 6)
    // =========================================================

    function test_withdraw_returnsTokens() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        // Advance past lock end
        vm.warp(block.timestamp + 2 weeks);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        ve.withdraw();

        assertEq(token.balanceOf(alice), balanceBefore + LOCK_AMOUNT, "Should return locked tokens");
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(ve));
        emit SimpleVoteEscrow.Withdrawn(alice, LOCK_AMOUNT);
        ve.withdraw();
    }

    function test_withdraw_clearsLockState() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(alice);
        ve.withdraw();

        (uint256 amount, uint256 end) = ve.locked(alice);
        assertEq(amount, 0, "Lock amount should be cleared");
        assertEq(end, 0, "Lock end should be cleared");
    }

    function test_withdraw_revertsBeforeExpiry() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        (, uint256 lockEnd) = ve.locked(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LockNotExpired.selector, lockEnd));
        ve.withdraw();
    }

    function test_withdraw_revertsIfNoLock() public {
        vm.prank(alice);
        vm.expectRevert(NoLockFound.selector);
        ve.withdraw();
    }

    function test_withdraw_atExactExpiry() public {
        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, 1 weeks);

        // Advance to exact expiry
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(alice);
        ve.withdraw(); // Should succeed at exact boundary

        (uint256 amount,) = ve.locked(alice);
        assertEq(amount, 0, "Should be able to withdraw at exact expiry");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_votingPowerNeverExceedsAmount(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1e18, 10_000e18);
        duration = bound(duration, 1 weeks, MAX_LOCK);

        token.mint(alice, amount);
        vm.startPrank(alice);
        token.approve(address(ve), amount);
        ve.createLock(amount, duration);
        vm.stopPrank();

        uint256 power = ve.votingPower(alice);
        assertLe(power, amount, "INVARIANT: voting power never exceeds locked amount");
    }

    function testFuzz_votingPowerDecaysOverTime(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, MAX_LOCK);

        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, MAX_LOCK);

        uint256 powerBefore = ve.votingPower(alice);
        vm.warp(block.timestamp + elapsed);
        uint256 powerAfter = ve.votingPower(alice);

        assertLe(
            powerAfter,
            powerBefore,
            "INVARIANT: voting power should never increase over time (only decay)"
        );
    }

    function testFuzz_withdrawOnlyAfterExpiry(uint256 duration, uint256 elapsed) public {
        duration = bound(duration, 1 weeks, MAX_LOCK);
        elapsed = bound(elapsed, 0, MAX_LOCK * 2);

        vm.prank(alice);
        ve.createLock(LOCK_AMOUNT, duration);

        vm.warp(block.timestamp + elapsed);

        if (elapsed >= duration) {
            // Should succeed
            vm.prank(alice);
            ve.withdraw();
            (uint256 amount,) = ve.locked(alice);
            assertEq(amount, 0, "Should withdraw after expiry");
        } else {
            // Should revert
            vm.prank(alice);
            vm.expectRevert(); // LockNotExpired
            ve.withdraw();
        }
    }
}

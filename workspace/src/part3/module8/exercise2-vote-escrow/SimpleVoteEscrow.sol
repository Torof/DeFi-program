// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// EXERCISE 2: Simplified Vote-Escrow Token
//
// Build a simplified ve-token (vote-escrow) with time-weighted voting power,
// linear decay, and gauge-style emission allocation. This is the Curve veCRV
// pattern -- the most influential governance mechanism in DeFi.
//
// The core insight: longer lock = more voting power. Power decays linearly
// as the lock approaches expiry, creating genuine "skin in the game."
//
// Concepts exercised:
//   - Vote-escrow mechanics (lock -> power -> decay)
//   - Linear decay formula: amount * (lockEnd - now) / MAX_LOCK
//   - Lock management (create, increase amount, extend time)
//   - Gauge voting and weight allocation (basis points)
//   - Why time-locking prevents governance manipulation
//
// Key references:
//   - Module 8 lesson: "ve-Tokenomics" section
//   - Module 8 lesson: Linear decay formula and diagram
//   - Curve Finance: VotingEscrow.vy
//
// Run: forge test --match-contract SimpleVoteEscrowTest -vvv
// ============================================================================

error ZeroAmount();
error LockTooShort(uint256 duration, uint256 minimum);
error LockTooLong(uint256 duration, uint256 maximum);
error LockAlreadyExists();
error NoLockFound();
error LockNotExpired(uint256 lockEnd);
error LockExpired();
error MustExtendLock(uint256 newEnd, uint256 currentEnd);
error GaugeWeightExceeded(uint256 totalWeight, uint256 maximum);

/// @notice Simplified vote-escrow with linear decay and gauge voting.
/// @dev Pre-built: state, types, constants, constructor, events.
///      Student implements: createLock, votingPower, increaseAmount,
///      increaseUnlockTime, voteForGauge, withdraw.
contract SimpleVoteEscrow {
    // --- Types ---
    struct LockedBalance {
        uint256 amount;   // tokens locked
        uint256 end;      // lock expiry timestamp
    }

    // --- Constants ---
    uint256 public constant MAX_LOCK = 4 * 365 days;           // 4 years
    uint256 public constant MIN_LOCK = 1 weeks;                 // minimum 1 week
    uint256 public constant MAX_GAUGE_WEIGHT = 10_000;          // 100% in basis points

    // --- State ---
    IERC20 public immutable token;
    mapping(address => LockedBalance) public locked;

    /// @dev user => gauge => weight (in basis points, 0-10000)
    mapping(address => mapping(address => uint256)) public gaugeVotes;

    /// @dev user => total gauge weight allocated (sum of all gaugeVotes, max 10000)
    mapping(address => uint256) public userTotalGaugeWeight;

    // --- Events ---
    event Locked(address indexed user, uint256 amount, uint256 lockEnd);
    event AmountIncreased(address indexed user, uint256 additionalAmount, uint256 newTotal);
    event LockExtended(address indexed user, uint256 newEnd);
    event Withdrawn(address indexed user, uint256 amount);
    event GaugeVoted(address indexed user, address indexed gauge, uint256 weight);

    constructor(address _token) {
        token = IERC20(_token);
    }

    // =============================================================
    //  TODO 1: Implement createLock
    // =============================================================
    /// @notice Lock tokens for a specified duration to receive voting power.
    /// @dev This is the entry point for ve-tokenomics. Longer locks = more power.
    ///
    ///      Steps:
    ///        1. Check amount > 0 -> revert ZeroAmount()
    ///        2. Check duration >= MIN_LOCK -> revert LockTooShort(duration, MIN_LOCK)
    ///        3. Check duration <= MAX_LOCK -> revert LockTooLong(duration, MAX_LOCK)
    ///        4. Check user doesn't already have a lock (locked[msg.sender].amount == 0)
    ///           -> revert LockAlreadyExists()
    ///        5. Store the lock:
    ///           locked[msg.sender] = LockedBalance(amount, block.timestamp + duration)
    ///        6. Transfer tokens from user to this contract:
    ///           token.transferFrom(msg.sender, address(this), amount)
    ///        7. Emit Locked event
    ///
    ///      Numeric example:
    ///        createLock(1000e18, 4 years)
    ///        -> locked = { amount: 1000e18, end: now + 4 years }
    ///        -> votingPower = 1000e18 * 4yr / 4yr = 1000e18 (max power)
    ///
    /// @param amount Number of tokens to lock
    /// @param duration Lock duration in seconds
    function createLock(uint256 amount, uint256 duration) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement votingPower
    // =============================================================
    /// @notice Calculate current voting power with linear decay.
    /// @dev The core formula from the lesson:
    ///
    ///      votingPower = amount * (lockEnd - now) / MAX_LOCK
    ///
    ///      Visual: Power decays linearly as time passes
    ///
    ///      Power
    ///      1000 |*
    ///       750 | *
    ///       500 |  *
    ///       250 |   *
    ///         0 |    *-------
    ///           +-----|------> time
    ///           lock  expiry
    ///           start
    ///
    ///      Steps:
    ///        1. Load the user's lock
    ///        2. If no lock (amount == 0) or lock expired (block.timestamp >= end):
    ///           return 0
    ///        3. Calculate remaining time: lock.end - block.timestamp
    ///        4. Return: lock.amount * remaining / MAX_LOCK
    ///
    ///      Numeric example:
    ///        amount = 1000e18, locked for 4 years
    ///        After 2 years: remaining = 2 years
    ///        power = 1000e18 * 2yr / 4yr = 500e18 (half power)
    ///
    /// @param user The address to check
    /// @return The user's current voting power
    function votingPower(address user) public view returns (uint256) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement increaseAmount
    // =============================================================
    /// @notice Add more tokens to an existing lock without changing the end time.
    /// @dev This increases voting power proportionally (more tokens at same decay).
    ///
    ///      Steps:
    ///        1. Check additionalAmount > 0 -> revert ZeroAmount()
    ///        2. Check lock exists (locked[msg.sender].amount > 0) -> revert NoLockFound()
    ///        3. Check lock hasn't expired (block.timestamp < lock.end) -> revert LockExpired()
    ///        4. Add to locked amount: locked[msg.sender].amount += additionalAmount
    ///        5. Transfer additional tokens from user to this contract
    ///        6. Emit AmountIncreased event
    ///
    ///      Note: The end time stays the same. Only the amount changes.
    ///
    /// @param additionalAmount Extra tokens to add to the lock
    function increaseAmount(uint256 additionalAmount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement increaseUnlockTime
    // =============================================================
    /// @notice Extend the lock duration to increase voting power.
    /// @dev This increases voting power by extending the decay timeline.
    ///
    ///      Steps:
    ///        1. Check lock exists (amount > 0) -> revert NoLockFound()
    ///        2. Check lock hasn't expired -> revert LockExpired()
    ///        3. Calculate new end: block.timestamp + newDuration
    ///        4. Check new end > current lock.end -> revert MustExtendLock(newEnd, lock.end)
    ///        5. Check newDuration <= MAX_LOCK -> revert LockTooLong(newDuration, MAX_LOCK)
    ///        6. Update lock.end = newEnd
    ///        7. Emit LockExtended event
    ///
    ///      Numeric example:
    ///        Original: locked 2 years, 1 year remaining
    ///        increaseUnlockTime(3 years) -> new end = now + 3 years
    ///        Power increases from amount * 1yr/4yr to amount * 3yr/4yr
    ///
    /// @param newDuration New lock duration from now (in seconds)
    function increaseUnlockTime(uint256 newDuration) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement voteForGauge
    // =============================================================
    /// @notice Allocate voting power percentage to a gauge (emission target).
    /// @dev In Curve, gauges control where CRV emissions go. Each user splits
    ///      their voting power across gauges using basis point weights.
    ///
    ///      Steps:
    ///        1. Check lock exists (amount > 0) -> revert NoLockFound()
    ///        2. Get old weight for this gauge: gaugeVotes[msg.sender][gauge]
    ///        3. Update total weight:
    ///           userTotalGaugeWeight[msg.sender] =
    ///             userTotalGaugeWeight[msg.sender] - oldWeight + weight
    ///        4. Check total <= MAX_GAUGE_WEIGHT (10000)
    ///           -> revert GaugeWeightExceeded(total, MAX_GAUGE_WEIGHT)
    ///        5. Store: gaugeVotes[msg.sender][gauge] = weight
    ///        6. Emit GaugeVoted event
    ///
    ///      Numeric example:
    ///        User has 1000e18 voting power
    ///        voteForGauge(gaugeA, 6000) -> 60% to gauge A
    ///        voteForGauge(gaugeB, 4000) -> 40% to gauge B
    ///        Total = 10000 (100%) - OK
    ///        voteForGauge(gaugeC, 1000) -> would make total 11000 - REVERT
    ///
    /// @param gauge The gauge address to allocate weight to
    /// @param weight Weight in basis points (0-10000)
    function voteForGauge(address gauge, uint256 weight) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 6: Implement withdraw
    // =============================================================
    /// @notice Reclaim tokens after the lock has expired.
    /// @dev Can only withdraw after the lock end time has passed.
    ///
    ///      Steps:
    ///        1. Load the lock
    ///        2. Check lock exists (amount > 0) -> revert NoLockFound()
    ///        3. Check lock has expired (block.timestamp >= lock.end)
    ///           -> revert LockNotExpired(lock.end) if not
    ///        4. Store amount before deleting
    ///        5. Delete the lock: delete locked[msg.sender]
    ///        6. Transfer tokens back to user
    ///        7. Emit Withdrawn event
    ///
    /// @dev Note: gauge votes are NOT cleaned up. They become stale
    ///      (votingPower = 0 means gauge allocations have no effect).
    ///
    function withdraw() external {
        // YOUR CODE HERE
    }
}

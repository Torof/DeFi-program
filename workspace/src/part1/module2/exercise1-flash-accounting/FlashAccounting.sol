// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// EXERCISE: Flash Accounting
//
// Build the core pattern behind Uniswap V4's architecture: use transient
// storage to track balance deltas across multiple operations, then settle
// the net difference at the end of the transaction.
//
// This is a simplified version that demonstrates the concept. In production
// (Uniswap V4), this pattern enables efficient batching, flash accounting,
// and hooks without intermediate token transfers.
//
// Run: forge test --match-contract FlashAccountingTest -vvv
// ============================================================================

// --- Custom Errors ---
error NotLocked();
error AlreadyLocked();
error NotSettled();
error Unauthorized();

// =============================================================
//  TODO 1: Implement FlashAccounting contract
// =============================================================
/// @notice Flash accounting system using transient storage.
/// @dev Tracks balance deltas during a "locked" session, then enforces
///      settlement (all deltas must net to zero or be paid) before unlock.
// See: Module 2 > Transient Storage Deep Dive (#transient-storage-deep-dive)
// See: Module 2 > Flash Accounting intermediate example
contract FlashAccounting {
    /// @dev Transient storage slot 0: lock flag (0 = unlocked, 1 = locked)
    /// @dev Transient storage slot for user delta: keccak256(abi.encode(user, token))
    ///      Stores the net balance delta (positive = owed to user, negative = user owes)

    // TODO: Implement using assembly tstore/tload
    // Hint: slot 0 for lock flag
    // Hint: keccak256(abi.encode(user, token)) for per-user-token delta

    modifier onlyLocked() {
        // TODO: Revert with NotLocked() if not locked
        // Hint: assembly { if iszero(tload(0)) { ... } }
        _;
    }

    /// @notice Locks the accounting session.
    /// @dev Only one session can be active per transaction.
    function lock() external {
        // TODO: Implement
        // 1. Check that not already locked (revert AlreadyLocked())
        // 2. Set lock flag to 1 in transient storage slot 0
        revert("Not implemented");
    }

    /// @notice Unlocks the accounting session.
    /// @dev Can only be called when all deltas are settled (net to zero).
    function unlock() external onlyLocked {
        // TODO: Implement
        // 1. Set lock flag to 0 in transient storage slot 0
        // Note: The caller is responsible for ensuring settlement before unlock.
        //       In production, you'd verify all deltas == 0 here.
        revert("Not implemented");
    }

    /// @notice Records a balance delta for a user-token pair.
    /// @param user The user address
    /// @param token The token address
    /// @param delta The delta amount (positive = user receives, negative = user pays)
    /// @dev Warning: the unchecked int256 addition can overflow with extreme values.
    ///      In production, you'd use SafeCast or bound inputs. Here we trust callers
    ///      to stay within reasonable DeFi ranges.
    function accountDelta(address user, address token, int256 delta) external onlyLocked {
        // TODO: Implement
        // 1. Compute storage slot: keccak256(abi.encode(user, token))
        // 2. Load current delta from transient storage
        // 3. Add the new delta
        // 4. Store the updated delta back to transient storage
        // Hint: Use assembly tload/tstore with the computed slot
        revert("Not implemented");
    }

    /// @notice Settles a user's delta by transferring tokens (simulated with ETH here).
    /// @dev In production, this would use ERC-20 transfers. Here we use ETH for simplicity.
    /// @param user The user to settle
    function settle(address user) external payable onlyLocked {
        // TODO: Implement
        // 1. Compute the slot for this user's delta: keccak256(abi.encode(user, address(0)))
        //    (using address(0) as a placeholder for "native token")
        // 2. Load the current delta from transient storage
        // 3. If delta is negative (user owes):
        //    - User must send abs(delta) ETH with this call
        //    - Verify msg.value == abs(delta)
        // 4. If delta is positive (user is owed):
        //    - Contract sends delta ETH to user
        // 5. Set the delta to 0 in transient storage
        // 6. Revert with NotSettled() if msg.value doesn't match requirement
        revert("Not implemented");
    }

    /// @notice Gets the current delta for a user-token pair.
    /// @dev Only callable when locked (otherwise transient storage is wiped).
    ///      Note: This function is `view` even though it reads transient storage via tload.
    ///      tload is a read-only operation (like sload), so `view` is correct here.
    ///      The Solidity compiler treats transient reads the same as storage reads
    ///      for mutability purposes.
    function getDelta(address user, address token) external view onlyLocked returns (int256) {
        // TODO: Implement
        // 1. Compute slot: keccak256(abi.encode(user, token))
        // 2. Load and return the delta from transient storage
        revert("Not implemented");
    }

    /// @notice Checks if currently locked.
    function isLocked() external view returns (bool) {
        // TODO: Implement
        // Return true if lock flag (slot 0) is 1
        revert("Not implemented");
    }

    // Allow contract to receive ETH
    receive() external payable {}
}

// =============================================================
//  TODO 2: Implement FlashAccountingUser (example user contract)
// =============================================================
/// @notice Example contract that uses flash accounting to perform operations.
/// @dev This demonstrates how external contracts interact with the flash accounting system.
// See: Module 2 > Intermediate Example: Building a Simple Flash Accounting System
contract FlashAccountingUser {
    FlashAccounting public immutable accounting;

    constructor(address payable _accounting) {
        accounting = FlashAccounting(_accounting);
    }

    /// @notice Executes a simple swap: takes tokenIn, gives tokenOut
    /// @dev Records deltas but doesn't transfer tokens immediately.
    function executeSwap(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        // TODO: Implement
        // 1. Record negative delta for user's tokenIn (user pays amountIn)
        // 2. Record positive delta for user's tokenOut (user receives amountOut)
        // Hint: Call accounting.accountDelta() twice
        revert("Not implemented");
    }

    /// @notice Executes multiple swaps in one transaction.
    function executeBatchSwaps(
        address user,
        address tokenA,
        address tokenB,
        address tokenC,
        uint256 amountA,
        uint256 amountB,
        uint256 amountC
    ) external {
        // TODO: Implement a sequence of swaps:
        // Swap 1: User pays amountA of tokenA, receives amountB of tokenB
        // Swap 2: User pays amountB of tokenB, receives amountC of tokenC
        // Net effect: User pays amountA of tokenA, receives amountC of tokenC
        // (tokenB deltas cancel out)
        revert("Not implemented");
    }
}

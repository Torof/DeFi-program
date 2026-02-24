// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: FlashLoanReceiver
// ============================================================================
//
//  Build an Aave V3-style flash loan receiver that borrows tokens, handles
//  the callback, and repays with the premium.
//
//  What you'll learn:
//    - The flash loan callback flow: borrow -> callback -> repay
//    - Security: validating msg.sender and initiator in the callback
//    - Repayment: the approve pattern (Aave pulls tokens after your callback)
//    - The "never store funds" principle for flash loan receivers
//
//  The flow inside a single transaction:
//
//    +-- Your Contract -------------------- Flash Loan Pool --------------+
//    |                                                                    |
//    |  requestFlashLoan(asset, amount)                                   |
//    |       |                                                            |
//    |       +---- pool.flashLoanSimple(this, asset, amount, ...) --->    |
//    |       |                                                            |
//    |       |     pool transfers `amount` tokens to your contract        |
//    |       |<----------------------------------------------------       |
//    |       |                                                            |
//    |       |     pool calls executeOperation(asset, amount, premium)    |
//    |       |<----------------------------------------------------       |
//    |       |                                                            |
//    |       |     YOUR CODE: validate, approve amount+premium            |
//    |       |                                                            |
//    |       |     pool pulls amount + premium via transferFrom           |
//    |       |---------------------------------------------------->       |
//    |       |                                                            |
//    |       |     Repaid -> tx succeeds                                  |
//    |       |     Short  -> ENTIRE TX REVERTS                            |
//    +--------------------------------------------------------------------+
//
//  Run:
//    forge test --match-contract FlashLoanReceiverTest -vvv
//
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanPool, IFlashLoanSimpleReceiver} from "./interfaces/IFlashLoanSimple.sol";

/// @notice Thrown when executeOperation is called by an address other than the Pool.
error NotPool();

/// @notice Thrown when the flash loan was initiated by an address other than this contract.
error NotInitiator();

/// @notice Thrown when a restricted function is called by a non-owner.
error NotOwner();

/// @notice A minimal Aave V3-style flash loan receiver.
/// @dev Exercise for Module 5: Flash Loans — Flash Loan Mechanics.
contract FlashLoanReceiver is IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    /// @notice The flash loan pool (Aave V3-style).
    IFlashLoanPool public immutable POOL;

    /// @notice The contract owner (can request flash loans and rescue tokens).
    address public immutable owner;

    /// @notice Running total of premiums paid across all flash loans.
    uint256 public totalPremiumsPaid;

    constructor(address pool_) {
        POOL = IFlashLoanPool(pool_);
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement requestFlashLoan — initiate a flash loan
    // =============================================================
    /// @notice Request a flash loan from the Pool.
    /// @dev Only the contract owner should be able to call this.
    ///
    ///      This function kicks off the entire flash loan flow:
    ///        1. You call Pool.flashLoanSimple(...)
    ///        2. The Pool transfers tokens to this contract
    ///        3. The Pool calls executeOperation() on this contract
    ///        4. executeOperation() approves repayment
    ///        5. The Pool pulls amount + premium from this contract
    ///
    ///      The `params` bytes are forwarded to your callback — you can encode
    ///      any data your strategy needs (addresses, amounts, routing info).
    ///      For this exercise, empty bytes are fine.
    ///
    /// Steps:
    ///   1. Check that only the owner can call this function
    ///   2. Call POOL.flashLoanSimple() with this contract as receiver
    ///
    /// Hint: flashLoanSimple(receiverAddress, asset, amount, params, referralCode)
    ///       Use address(this) as receiver, "" as params, 0 as referralCode.
    /// See: Module 5 — "The Atomic Guarantee" and "Flash Loan Providers"
    ///
    /// @param asset The token to flash-borrow.
    /// @param amount The amount to flash-borrow.
    function requestFlashLoan(address asset, uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement executeOperation — the flash loan callback
    // =============================================================
    /// @notice Called by the Pool after transferring the flash-loaned amount.
    /// @dev This is the core of the flash loan pattern. When this function
    ///      is called, this contract already holds `amount` tokens from the Pool.
    ///      You must ensure that `amount + premium` is available for the Pool
    ///      to pull via transferFrom when this function returns.
    ///
    ///      Security checks (BOTH are required):
    ///        - msg.sender must be the Pool — otherwise anyone could call
    ///          this function directly and manipulate your contract's state
    ///        - initiator must be this contract — otherwise someone else
    ///          could initiate a flash loan using your contract as the target,
    ///          potentially draining any stored funds
    ///
    ///      Repayment (Aave-style):
    ///        Aave uses transferFrom to pull repayment AFTER your callback returns.
    ///        This means you must approve the Pool for amount + premium.
    ///        (Contrast with Balancer, where you transfer directly to the Vault
    ///        inside the callback — different pattern!)
    ///
    /// Steps:
    ///   1. Validate msg.sender is the Pool (revert NotPool if not)
    ///   2. Validate initiator is this contract (revert NotInitiator if not)
    ///   3. Calculate totalOwed = amount + premium
    ///   4. Track the premium in totalPremiumsPaid
    ///   5. Approve the Pool to pull totalOwed
    ///   6. Return true
    ///
    /// Hint: Use IERC20(asset).approve(address(POOL), totalOwed) for step 5.
    ///       The Pool calls transferFrom immediately after this returns.
    /// See: Module 5 — "Deep Dive: The Flash Loan Callback Flow"
    ///
    /// @param asset The address of the flash-borrowed token.
    /// @param amount The amount that was flash-borrowed.
    /// @param premium The fee owed to the Pool.
    /// @param initiator The address that called flashLoanSimple on the Pool.
    /// @param params Arbitrary bytes forwarded from requestFlashLoan (unused here).
    /// @return True if the operation was successful.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement rescueTokens — sweep any stuck tokens
    // =============================================================
    /// @notice Rescue tokens accidentally sent to this contract.
    /// @dev Flash loan receivers should NEVER hold funds between transactions.
    ///
    ///      Why? If your contract holds tokens, an attacker could potentially:
    ///        1. Initiate a flash loan targeting YOUR contract as receiver
    ///        2. Your executeOperation callback runs with attacker-controlled params
    ///        3. Even with initiator checks, stored funds create attack surface
    ///
    ///      This rescue function is a safety net — but the real defense is
    ///      ensuring the contract balance is always 0 after each transaction.
    ///
    /// Steps:
    ///   1. Check that only the owner can call this
    ///   2. Transfer the full balance of `asset` from this contract to `to`
    ///
    /// Hint: Use IERC20(asset).balanceOf(address(this)) to get the balance,
    ///       then safeTransfer to send it.
    /// See: Module 5 — "Common Mistakes" (Mistake 2: Storing funds)
    ///
    /// @param asset The token to rescue.
    /// @param to The address to send rescued tokens to.
    function rescueTokens(address asset, address to) external {
        revert("Not implemented");
    }
}

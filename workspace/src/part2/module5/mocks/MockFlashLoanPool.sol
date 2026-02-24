// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanPool, IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimple.sol";

/// @notice Mock flash loan pool that simulates Aave V3's flash loan behavior.
/// @dev Follows the exact Aave V3 flow:
///      1. Transfer tokens to receiver
///      2. Call receiver.executeOperation()
///      3. Pull amount + premium from receiver via transferFrom
///
///      The pool must be funded with tokens before flash loans can be executed.
contract MockFlashLoanPool is IFlashLoanPool {
    using SafeERC20 for IERC20;

    /// @notice Flash loan premium in basis points (5 bps = 0.05%, matches Aave V3).
    uint128 public constant FLASHLOAN_PREMIUM_TOTAL = 5;

    error InvalidReceiver();
    error CallbackFailed();
    error InsufficientLiquidity();

    /// @inheritdoc IFlashLoanPool
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 /* referralCode */
    ) external override {
        if (receiverAddress == address(0)) revert InvalidReceiver();

        uint256 available = IERC20(asset).balanceOf(address(this));
        if (available < amount) revert InsufficientLiquidity();

        // Calculate premium (same formula as Aave V3)
        uint256 premium = (amount * FLASHLOAN_PREMIUM_TOTAL) / 10_000;

        // Step 1: Transfer flash-loaned tokens to receiver
        IERC20(asset).safeTransfer(receiverAddress, amount);

        // Step 2: Call the receiver's callback
        //         initiator = msg.sender (whoever called flashLoanSimple)
        bool success = IFlashLoanSimpleReceiver(receiverAddress).executeOperation(
            asset,
            amount,
            premium,
            msg.sender,
            params
        );
        if (!success) revert CallbackFailed();

        // Step 3: Pull amount + premium from receiver (Aave-style: uses transferFrom)
        IERC20(asset).safeTransferFrom(receiverAddress, address(this), amount + premium);
    }
}

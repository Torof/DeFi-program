// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ============================================================================
//  DO NOT MODIFY — Pre-built 0-fee flash lender (Balancer-style).
//  Used as infrastructure for the OracleManipulation exercise.
//
//  Provides unlimited capital for a single transaction. The borrower
//  must repay the full amount before the callback returns.
// ============================================================================

/// @notice Callback interface for flash loan borrowers.
interface IFlashBorrower {
    function onFlashLoan(address token, uint256 amount) external;
}

/// @notice Minimal 0-fee flash lender. Must be pre-funded with tokens.
contract MockFlashLender {
    using SafeERC20 for IERC20;

    /// @notice Execute a flash loan — send tokens, callback, verify repayment.
    /// @param token The token to flash-borrow.
    /// @param amount The amount to borrow.
    function flashLoan(address token, uint256 amount) external {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        IERC20(token).safeTransfer(msg.sender, amount);
        IFlashBorrower(msg.sender).onFlashLoan(token, amount);

        require(
            IERC20(token).balanceOf(address(this)) >= balanceBefore,
            "MockFlashLender: loan not repaid"
        );
    }
}

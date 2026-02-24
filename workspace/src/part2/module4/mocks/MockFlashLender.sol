// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

/// @notice ERC-3156 flash lender mock for the FlashLiquidator exercise.
/// @dev Pre-built — students do NOT modify this.
///
///      Behavior:
///        - Mints tokens to the borrower (simulates lending from infinite reserves)
///        - Calls onFlashLoan on the borrower
///        - Pulls back principal + fee
///        - Fee: 9 basis points (0.09%) — matches Aave V3 flash loan fee
contract MockFlashLender is IERC3156FlashLender {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_BPS = 9; // 0.09%

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    error FlashLoanFailed();

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address, uint256 amount) external pure override returns (uint256) {
        return amount * FEE_BPS / 10000;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        uint256 fee = amount * FEE_BPS / 10000;

        // Mint tokens to borrower (simulates lending)
        IMintable(token).mint(address(receiver), amount);

        // Callback
        bytes32 result = receiver.onFlashLoan(msg.sender, token, amount, fee, data);
        if (result != CALLBACK_SUCCESS) revert FlashLoanFailed();

        // Pull back principal + fee
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount + fee);

        return true;
    }
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

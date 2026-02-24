// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

// ============================================================================
// EXERCISE: Flash Loan Liquidation Bot
//
// Build a zero-capital liquidation bot using ERC-3156 flash loans.
//
// This is the "attack lab" of the lending module — you'll wire together:
//   1. A flash loan provider (borrows capital with zero upfront cost)
//   2. A lending pool (has an underwater position to liquidate)
//   3. A DEX (converts seized collateral back to the debt token)
//
// The flow:
//   ┌──────────────┐
//   │ FlashLiquidator │
//   └──────┬───────┘
//          │ 1. Request flash loan (USDC)
//          ▼
//   ┌──────────────┐
//   │ FlashLender   │ ─── mints USDC to FlashLiquidator
//   └──────┬───────┘
//          │ 2. Callback: onFlashLoan()
//          ▼
//   ┌──────────────┐
//   │ LendingPool   │ ─── FlashLiquidator repays debt, seizes collateral (+5% bonus)
//   └──────┬───────┘
//          │ 3. Sell collateral
//          ▼
//   ┌──────────────┐
//   │ DEX           │ ─── WETH → USDC at market price
//   └──────┬───────┘
//          │ 4. Repay flash loan (principal + 0.09% fee)
//          ▼
//   ┌──────────────┐
//   │ FlashLender   │ ─── pulls USDC back
//   └──────────────┘
//
//   Profit = collateral bonus (5%) − flash loan fee (0.09%) ≈ 4.91%
//
// All 4 mocks are pre-built. Your job is to wire them together in the
// FlashLiquidator contract. This teaches the composability pattern that
// every MEV bot and liquidation bot uses in production.
//
// Real protocol references:
//   - Aave V3 LiquidationLogic.sol
//   - ERC-3156: https://eips.ethereum.org/EIPS/eip-3156
//   - Liquidation bots: https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol
//
// Run: forge test --match-contract FlashLiquidatorTest -vvv
// ============================================================================

/// @notice Interface for the mock lending pool's liquidate function.
interface ILendingPool {
    function liquidate(
        address borrower,
        address debtAsset,
        uint256 debtToCover,
        address collateralAsset
    ) external returns (uint256 collateralSeized);
}

/// @notice Interface for the mock DEX's swap function.
interface IDEX {
    function swap(address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut);
}

// --- Custom Errors ---
error NotFlashLender();
error NotSelf();
error LiquidationUnprofitable();

/// @notice Zero-capital flash loan liquidation bot.
/// @dev Implements ERC-3156 FlashBorrower to execute liquidations without
///      any upfront capital. The entire flow happens atomically in one tx.
contract FlashLiquidator is IERC3156FlashBorrower {
    using SafeERC20 for IERC20;

    IERC3156FlashLender public immutable lender;
    ILendingPool public immutable pool;
    IDEX public immutable dex;
    address public immutable owner;

    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address _lender, address _pool, address _dex) {
        lender = IERC3156FlashLender(_lender);
        pool = ILendingPool(_pool);
        dex = IDEX(_dex);
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement liquidate (entry point)
    // =============================================================
    /// @notice Initiates a flash loan liquidation of an underwater position.
    /// @dev This is the external entry point. It:
    ///        1. Encodes the liquidation parameters into bytes
    ///        2. Requests a flash loan from the lender
    ///
    ///      The flash loan callback (onFlashLoan) does the actual work.
    ///
    ///      The encoded data must contain: borrower, collateralToken
    ///      (the debtToken and amount are already flash loan parameters).
    ///
    /// Steps:
    ///   1. Encode (borrower, collateralToken) using abi.encode
    ///   2. Call lender.flashLoan(this, debtToken, debtAmount, encodedData)
    ///
    /// @param borrower The underwater borrower to liquidate
    /// @param debtToken The debt token to repay
    /// @param debtAmount The amount of debt to cover
    /// @param collateralToken The collateral token to seize
    function liquidate(
        address borrower,
        address debtToken,
        uint256 debtAmount,
        address collateralToken
    ) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement onFlashLoan (callback)
    // =============================================================
    /// @notice ERC-3156 callback — executes the liquidation with flash-borrowed funds.
    /// @dev This is called by the flash lender after sending us the tokens.
    ///      SECURITY IS CRITICAL here — two checks are mandatory:
    ///
    ///        1. msg.sender == address(lender)  — only the lender can call this
    ///           Without this check, anyone could call onFlashLoan() and trick
    ///           the contract into executing arbitrary operations.
    ///
    ///        2. initiator == address(this) — only self-initiated flash loans
    ///           Without this check, someone could request a flash loan on our
    ///           behalf and make us execute a callback we didn't initiate.
    ///
    /// Steps:
    ///   1. Require msg.sender == address(lender) (revert NotFlashLender)
    ///   2. Require initiator == address(this) (revert NotSelf)
    ///   3. Decode data → (borrower, collateralToken)
    ///   4. Approve lending pool to spend `amount` of `token` (for debt repayment)
    ///   5. Call pool.liquidate(borrower, token, amount, collateralToken) → get collateralSeized
    ///   6. Sell the seized collateral: _sellCollateral(collateralToken, collateralSeized, token)
    ///   7. Verify profit: _verifyProfit(token, amount, fee)
    ///   8. Approve lender to pull back amount + fee
    ///   9. Return CALLBACK_SUCCESS
    ///
    /// @param initiator The address that initiated the flash loan
    /// @param token The flash-borrowed token
    /// @param amount The amount borrowed
    /// @param fee The flash loan fee
    /// @param data Encoded (borrower, collateralToken)
    /// @return The CALLBACK_SUCCESS hash
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        // solhint-disable-next-line no-unused-vars
        initiator; token; amount; fee; data; // silence warnings
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement _sellCollateral
    // =============================================================
    /// @notice Sells seized collateral on the DEX for debt tokens.
    /// @dev Simple: approve the DEX, call swap, return the proceeds.
    ///
    /// Steps:
    ///   1. Approve DEX to spend `amount` of `collateralToken`
    ///   2. Call dex.swap(collateralToken, amount, debtToken) → proceeds
    ///   3. Return proceeds
    ///
    /// @param collateralToken The token to sell
    /// @param amount The amount to sell
    /// @param debtToken The token to receive
    /// @return proceeds The amount of debtToken received
    function _sellCollateral(address collateralToken, uint256 amount, address debtToken)
        internal
        returns (uint256 proceeds)
    {
        // solhint-disable-next-line no-unused-vars
        proceeds; // silence warning
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement _verifyProfit
    // =============================================================
    /// @notice Verifies the liquidation was profitable.
    /// @dev After selling collateral, we must have enough to repay the flash
    ///      loan (principal + fee) AND have some profit left over.
    ///
    ///      If unprofitable, revert the entire transaction — no point in
    ///      executing a liquidation that loses money.
    ///
    /// Steps:
    ///   1. Compute repayment = flashAmount + flashFee
    ///   2. Get our current balance of debtToken
    ///   3. If balance < repayment, revert LiquidationUnprofitable
    ///
    /// @param debtToken The token we need to repay
    /// @param flashAmount The principal amount of the flash loan
    /// @param flashFee The fee owed to the flash lender
    function _verifyProfit(address debtToken, uint256 flashAmount, uint256 flashFee) internal view {
        revert("Not implemented");
    }

    // =============================================================
    //  PROVIDED: Withdraw profits
    // =============================================================

    /// @notice Allows the owner to withdraw accumulated profits.
    function withdrawProfit(address token) external {
        require(msg.sender == owner, "Not owner");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner, balance);
    }
}

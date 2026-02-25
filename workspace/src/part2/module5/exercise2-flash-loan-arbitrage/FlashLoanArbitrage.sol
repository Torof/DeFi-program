// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: FlashLoanArbitrage
// ============================================================================
//
//  Build a flash loan arbitrage contract that captures price discrepancies
//  between two DEXs.
//
//  What you'll learn:
//    - Composing flash loans with DEX swaps inside the callback
//    - Encoding/decoding strategy params through the flash loan `params` bytes
//    - Profitability math: when does the spread cover fees?
//    - Sweeping profit to the caller (never store funds)
//
//  The flow inside a single transaction:
//
//    +-------------------------------------------------------------------+
//    |                     Single Transaction                            |
//    |                                                                   |
//    |  1. Flash-borrow tokenA from Pool                                 |
//    |  2. Swap tokenA -> tokenB on buyDex  (tokenB is cheap here)       |
//    |  3. Swap tokenB -> tokenA on sellDex (tokenB is pricey here)      |
//    |  4. Verify profit >= minProfit                                    |
//    |  5. Repay tokenA + premium to Pool                                |
//    |  6. Send remaining tokenA (profit) to caller                      |
//    |                                                                   |
//    |  If profit < minProfit -> revert (atomic guarantee)               |
//    +-------------------------------------------------------------------+
//
//  Example (1% discrepancy, 0.3% DEX fee, 0.05% flash premium):
//    Flash borrow 100K USDC -> buy 49.85 WETH on DEX1 (2000 USDC/WETH)
//    -> sell 49.85 WETH on DEX2 (2020 USDC/WETH) -> get ~100,395 USDC
//    -> repay 100,050 USDC -> profit ~345 USDC
//
//  Run:
//    forge test --match-contract FlashLoanArbitrageTest -vvv
//
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanPool, IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimple.sol";

/// @notice Interface for the mock DEX's swap function.
interface IDEX {
    function swap(address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut);
}

/// @notice Thrown when executeOperation is called by an address other than the Pool.
error NotPool();

/// @notice Thrown when the flash loan was initiated by an address other than this contract.
error NotInitiator();

/// @notice Thrown when a restricted function is called by a non-owner.
error NotOwner();

/// @notice Thrown when the arbitrage profit is below the required minimum.
error InsufficientProfit();

/// @notice Flash loan arbitrage contract that captures price discrepancies between DEXs.
/// @dev Exercise for Module 5: Flash Loans — Composing Flash Loan Strategies.
contract FlashLoanArbitrage is IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    /// @notice The flash loan pool (Aave V3-style).
    IFlashLoanPool public immutable POOL;

    /// @notice The contract owner.
    address public immutable owner;

    constructor(address pool_) {
        POOL = IFlashLoanPool(pool_);
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement executeArbitrage — initiate the flash loan
    // =============================================================
    /// @notice Execute a flash loan arbitrage between two DEXs.
    /// @dev Only the owner can call this. The flow:
    ///        1. Encode strategy params into bytes (for the callback)
    ///        2. Request flash loan from Pool
    ///        3. After flash loan completes, sweep profit to caller
    ///
    ///      The `params` bytes are the bridge between this function and the
    ///      callback. You encode the strategy data here, and decode it in
    ///      executeOperation. This is how every real flash loan strategy
    ///      passes information to the callback.
    ///
    /// Steps:
    ///   1. Check that only the owner can call this (revert NotOwner)
    ///   2. Encode the strategy params: (buyDex, sellDex, tokenB, minProfit)
    ///      into a bytes variable using abi.encode()
    ///   3. Call POOL.flashLoanSimple(address(this), tokenA, borrowAmount, params, 0)
    ///   4. After flashLoanSimple returns, any remaining tokenA balance is profit.
    ///      Transfer it to msg.sender using safeTransfer.
    ///
    /// Hint: bytes memory params = abi.encode(buyDex, sellDex, tokenB, minProfit);
    ///       After the flash loan, use IERC20(tokenA).balanceOf(address(this))
    ///       to get the profit amount, then safeTransfer to msg.sender.
    /// See: Module 5 — "Strategy 1: DEX Arbitrage"
    ///
    /// @param tokenA The token to flash-borrow (base token, e.g., USDC).
    /// @param borrowAmount How much tokenA to flash-borrow.
    /// @param buyDex DEX where tokenB is cheap (buy tokenB here).
    /// @param sellDex DEX where tokenB is expensive (sell tokenB here).
    /// @param tokenB The intermediate token (e.g., WETH).
    /// @param minProfit Minimum profit required (reverts if less).
    function executeArbitrage(
        address tokenA,
        uint256 borrowAmount,
        address buyDex,
        address sellDex,
        address tokenB,
        uint256 minProfit
    ) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement executeOperation — the arbitrage callback
    // =============================================================
    /// @notice Called by the Pool after transferring the flash-loaned tokens.
    /// @dev This is where the arbitrage happens. When called, this contract
    ///      holds `amount` of the flash-borrowed token. You must:
    ///        - Do the two swaps to capture the price discrepancy
    ///        - Verify the profit covers fees and meets the minimum
    ///        - Approve the Pool for repayment
    ///
    ///      Swap pattern (same for both DEXs):
    ///        1. Approve the DEX to spend your tokens
    ///        2. Call IDEX(dex).swap(tokenIn, amountIn, tokenOut)
    ///        3. The DEX pulls tokenIn via transferFrom, sends you tokenOut
    ///
    /// Steps:
    ///   1. Validate msg.sender is the Pool (revert NotPool)
    ///   2. Validate initiator is this contract (revert NotInitiator)
    ///   3. Decode params: (buyDex, sellDex, tokenB, minProfit) = abi.decode(...)
    ///   4. Approve buyDex to spend `amount` of asset, then swap asset -> tokenB
    ///   5. Get tokenB balance, approve sellDex, then swap tokenB -> asset
    ///   6. Check profitability: balance of asset must be >= amount + premium + minProfit
    ///      If not, revert InsufficientProfit()
    ///   7. Approve the Pool to pull amount + premium
    ///   8. Return true
    ///
    /// Hint: To decode: (address buyDex, address sellDex, address tokenB, uint256 minProfit)
    ///         = abi.decode(params, (address, address, address, uint256));
    ///       For step 6, calculate totalOwed = amount + premium, then check
    ///         IERC20(asset).balanceOf(address(this)) >= totalOwed + minProfit
    /// See: Module 5 — "Deep Dive: Arbitrage Profit Calculation"
    ///
    /// @param asset The flash-borrowed token address.
    /// @param amount The flash-borrowed amount.
    /// @param premium The fee owed to the Pool.
    /// @param initiator The address that initiated the flash loan.
    /// @param params Encoded strategy data from executeArbitrage.
    /// @return True if the operation succeeded.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        revert("Not implemented");
    }
}

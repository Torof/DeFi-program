// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: CollateralSwap
// ============================================================================
//
//  Build a flash loan-powered collateral swap: switch a user's lending position
//  from one collateral token to another — without closing the position.
//
//  What you'll learn:
//    - Complex multi-step flash loan composition (6 steps in one callback)
//    - Aave's credit delegation pattern (borrow on behalf of another user)
//    - aToken mechanics (supply mints aTokens, withdraw burns aTokens)
//    - Integrating lending pool + DEX operations in a single atomic tx
//
//  The flow inside a single transaction:
//
//    +-------------------------------------------------------------------+
//    |                     Single Transaction                            |
//    |                                                                   |
//    |  User's position BEFORE: 10 WETH collateral, 10,000 USDC debt    |
//    |                                                                   |
//    |  1. Flash-borrow USDC equal to user's debt                       |
//    |  2. Repay user's entire USDC debt on lending pool                |
//    |  3. Pull user's aTokens, then withdraw old collateral (WETH)     |
//    |  4. Swap old collateral → new collateral on DEX (WETH → WBTC)   |
//    |  5. Deposit new collateral into lending pool for user            |
//    |  6. Borrow USDC on behalf of user (credit delegation)            |
//    |  7. Approve flash pool to pull repayment (amount + premium)      |
//    |                                                                   |
//    |  User's position AFTER: 0.3988 WBTC collateral, 10,005 USDC debt|
//    |                                                                   |
//    |  Prerequisites (user must do before calling):                     |
//    |    - aToken.approve(this, amount) for collateral withdrawal      |
//    |    - lendingPool.approveDelegation(debtAsset, this, amount)      |
//    |      for borrowing on their behalf                               |
//    +-------------------------------------------------------------------+
//
//  Example (0.3% DEX fee, 0.05% flash premium):
//    Flash borrow 10K USDC → repay debt → withdraw 10 WETH
//    → swap to 0.3988 WBTC → deposit → borrow 10,005 USDC → repay flash
//
//  Run:
//    forge test --match-contract CollateralSwapTest -vvv
//
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanPool, IFlashLoanSimpleReceiver} from "./interfaces/IFlashLoanSimple.sol";

/// @notice Interface for the mock lending pool's core operations.
/// @dev Mirrors the subset of Aave V3's IPool needed for collateral swaps.
///      In production, you'd import Aave's IPool directly.
interface ILendingPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 rateMode, uint16 referralCode, address onBehalfOf) external;
    function aTokenOf(address asset) external view returns (address);
}

/// @notice Interface for the mock DEX's swap function.
interface IDEX {
    function swap(address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut);
}

/// @notice Thrown when executeOperation is called by an address other than the flash pool.
error NotPool();

/// @notice Thrown when the flash loan was initiated by an address other than this contract.
error NotInitiator();

/// @notice Collateral swap parameters.
/// @dev Encodes all the information needed to execute the swap inside the callback.
struct SwapParams {
    address user;           // Position owner (must have set up delegations beforehand)
    address oldCollateral;  // Token to withdraw (e.g., WETH)
    address newCollateral;  // Token to deposit (e.g., WBTC)
    address debtAsset;      // The borrowed token (e.g., USDC)
    uint256 debtAmount;     // Debt to repay (flash borrow this exact amount)
}

/// @notice Flash loan-powered collateral swap contract.
/// @dev Exercise for Module 5: Flash Loans — Complex Composition.
///
///      This is Aave's "liquidity switch" pattern — one of the primary
///      production uses of flash loans. The user's risk is controlled
///      by their delegation limits, not by access control on this contract.
contract CollateralSwap is IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    /// @notice The flash loan pool (Aave V3-style).
    IFlashLoanPool public immutable FLASH_POOL;

    /// @notice The lending pool where the user's position lives.
    ILendingPool public immutable LENDING_POOL;

    /// @notice The DEX used for swapping collateral tokens.
    IDEX public immutable DEX;

    constructor(address flashPool_, address lendingPool_, address dex_) {
        FLASH_POOL = IFlashLoanPool(flashPool_);
        LENDING_POOL = ILendingPool(lendingPool_);
        DEX = IDEX(dex_);
    }

    // =============================================================
    //  TODO 1: Implement swapCollateral — initiate the flash loan
    // =============================================================
    /// @notice Initiate a collateral swap via flash loan.
    /// @dev The flow:
    ///        1. Encode the SwapParams into bytes (for the callback)
    ///        2. Request flash loan of debtAsset for debtAmount
    ///
    ///      No access control here — security comes from the user's
    ///      delegation limits. The user controls their risk by choosing
    ///      how much aToken allowance and credit delegation they grant.
    ///
    /// Steps:
    ///   1. Encode the entire SwapParams struct into bytes using abi.encode()
    ///   2. Call FLASH_POOL.flashLoanSimple(address(this), p.debtAsset, p.debtAmount, params, 0)
    ///
    /// Hint: bytes memory params = abi.encode(p);
    /// See: Module 5 — "Strategy 3: Collateral Swap"
    ///
    /// @param p The swap parameters (user, tokens, debt amount).
    function swapCollateral(SwapParams calldata p) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement executeOperation — the 6-step callback
    // =============================================================
    /// @notice Called by the flash pool after transferring the loaned tokens.
    /// @dev This is where the collateral swap happens. When called, this contract
    ///      holds `amount` of the debt asset (e.g., USDC). You must execute 6 steps
    ///      to complete the swap, then approve the flash pool for repayment.
    ///
    /// Steps:
    ///   1. Validate msg.sender is FLASH_POOL (revert NotPool)
    ///   2. Validate initiator is address(this) (revert NotInitiator)
    ///   3. Decode params: SwapParams memory p = abi.decode(params, (SwapParams))
    ///
    ///   --- Step 1: Repay user's debt ---
    ///   4. Approve LENDING_POOL to spend `amount` of `asset`
    ///   5. Call LENDING_POOL.repay(asset, amount, 2, p.user)
    ///      (rateMode=2 means variable rate in Aave)
    ///
    ///   --- Step 2: Withdraw old collateral ---
    ///   6. Get the aToken address: LENDING_POOL.aTokenOf(p.oldCollateral)
    ///   7. Get the user's aToken balance
    ///   8. Transfer aTokens from user to this contract (safeTransferFrom)
    ///      Note: User must have called aToken.approve(this, amount) beforehand
    ///   9. Call LENDING_POOL.withdraw(p.oldCollateral, type(uint256).max, address(this))
    ///      Note: withdraw burns aTokens from msg.sender — so we must hold them first
    ///
    ///   --- Step 3: Swap collateral on DEX ---
    ///   10. Get the withdrawn amount: IERC20(p.oldCollateral).balanceOf(address(this))
    ///   11. Approve DEX to spend the old collateral
    ///   12. Call DEX.swap(p.oldCollateral, withdrawnAmount, p.newCollateral)
    ///
    ///   --- Step 4: Deposit new collateral for user ---
    ///   13. Get the swapped amount: IERC20(p.newCollateral).balanceOf(address(this))
    ///   14. Approve LENDING_POOL to spend new collateral
    ///   15. Call LENDING_POOL.supply(p.newCollateral, swappedAmount, p.user, 0)
    ///       Note: supply deposits FOR p.user — they receive the aTokens
    ///
    ///   --- Step 5: Borrow to repay flash loan ---
    ///   16. Calculate totalOwed = amount + premium
    ///   17. Call LENDING_POOL.borrow(asset, totalOwed, 2, 0, p.user)
    ///       Note: This borrows on behalf of p.user (credit delegation required).
    ///       Tokens are sent to msg.sender (this contract), debt goes to p.user.
    ///
    ///   --- Step 6: Approve flash pool for repayment ---
    ///   18. Approve address(FLASH_POOL) to pull totalOwed of asset
    ///   19. Return true
    ///
    /// Hint: For step 8, the user must have called aToken.approve(this, amount) beforehand.
    ///       For step 17, the user must have called lendingPool.approveDelegation(...).
    ///       These two delegations are the key security pattern for collateral swaps.
    /// See: Module 5 — "Strategy 3: Collateral Swap"
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

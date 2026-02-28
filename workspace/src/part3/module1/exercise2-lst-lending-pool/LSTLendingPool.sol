// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WstETHOracle} from "../exercise1-lst-oracle/WstETHOracle.sol";

// ============================================================================
// EXERCISE: LST Collateral Lending Pool
//
// Build a simplified lending pool that accepts wstETH as collateral and lets
// users borrow a stablecoin against it. This exercises the core integration
// patterns from the lesson:
//
//   - LST pricing via the dual oracle pattern (Exercise 1's WstETHOracle)
//   - Health factor calculation using safe (dual oracle) collateral valuation
//   - E-Mode for correlated assets (higher LTV when borrowing ETH-denominated)
//   - Liquidation mechanics with collateral seizure and bonus
//
// This mirrors what Aave V3, Morpho, and every lending protocol does when
// listing wstETH. The key insight: health factor must use the SAFE oracle
// (dual oracle) to correctly trigger liquidations during de-peg events.
//
// If you use the basic oracle (exchange-rate-only), a 7% de-peg means
// positions that should be liquidated still appear healthy — exactly what
// happened to some protocols during June 2022.
//
// Concepts exercised:
//   - Collateral deposit / withdrawal with health checks
//   - Borrow / repay lifecycle
//   - Health factor = (collateral × LT) / debt
//   - E-Mode toggle for correlated-asset efficiency
//   - Liquidation with bonus (incentivized liquidator)
//   - Debt ceiling enforcement
//
// Key references:
//   - Aave V3 wstETH parameters: LTV 80%, LT 83%, E-Mode LTV 93%, E-Mode LT 95%
//   - Module 1 lesson: part3/1-liquid-staking.md#lst-collateral
//   - P2M4 (Lending): Health factor and liquidation patterns
//
// Run: forge test --match-contract LSTLendingPoolTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroAmount();
error HealthFactorTooLow();
error PositionHealthy();
error ExceedsDebtCeiling();
error InsufficientCollateral();
error InsufficientDebt();

/// @notice Simplified lending pool accepting wstETH collateral.
/// @dev Pre-built: constructor, state, constants, E-Mode setter, view helpers.
///      Student implements: deposit, borrow, repay, withdraw, liquidate, getHealthFactor.
contract LSTLendingPool {
    // --- State ---

    /// @dev Oracle for pricing wstETH in USD (uses dual oracle pattern).
    WstETHOracle public immutable oracle;

    /// @dev The wstETH token used as collateral.
    IERC20 public immutable wstETH;

    /// @dev The stablecoin token that users borrow.
    ///      In a real protocol this would be a mintable stablecoin.
    ///      For simplicity, this pool must hold stablecoin reserves.
    IERC20 public immutable stablecoin;

    /// @dev User collateral balances (wstETH amount deposited).
    mapping(address => uint256) public collateral;

    /// @dev User debt balances (stablecoin amount borrowed).
    mapping(address => uint256) public debt;

    /// @dev Whether a user has E-Mode enabled.
    mapping(address => bool) public eModeEnabled;

    /// @dev Total stablecoin debt across all users (for debt ceiling check).
    uint256 public totalDebt;

    // --- Constants (modeled after Aave V3 wstETH parameters) ---

    /// @dev Normal mode: Loan-to-Value ratio (80% = can borrow up to 80% of collateral value)
    uint256 public constant LTV = 8000; // basis points (80%)

    /// @dev Normal mode: Liquidation Threshold (83% = liquidatable when debt > 83% of collateral)
    uint256 public constant LIQUIDATION_THRESHOLD = 8300; // basis points (83%)

    /// @dev E-Mode: Higher LTV for correlated assets
    uint256 public constant EMODE_LTV = 9300; // basis points (93%)

    /// @dev E-Mode: Higher Liquidation Threshold for correlated assets
    uint256 public constant EMODE_LIQUIDATION_THRESHOLD = 9500; // basis points (95%)

    /// @dev Liquidation bonus: liquidator receives collateral at 5% discount
    uint256 public constant LIQUIDATION_BONUS = 500; // basis points (5%)

    /// @dev Maximum total debt allowed (simple debt ceiling)
    uint256 public constant DEBT_CEILING = 10_000_000e8; // $10M in 8-decimal USD

    /// @dev Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @dev Minimum health factor (1.0 in 18-decimal fixed-point)
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    /// @dev 1e18 for fixed-point math
    uint256 private constant WAD = 1e18;

    constructor(address _oracle, address _wstETH, address _stablecoin) {
        oracle = WstETHOracle(_oracle);
        wstETH = IERC20(_wstETH);
        stablecoin = IERC20(_stablecoin);
    }

    // --- Pre-built: E-Mode Toggle ---

    /// @notice Toggle E-Mode for the caller.
    /// @dev E-Mode allows higher LTV/LT when both collateral and debt are
    ///      ETH-correlated. In Aave V3, this is an "efficiency mode" category.
    ///      For this exercise, E-Mode simply uses higher constants.
    ///
    ///      After disabling E-Mode, the position must still be healthy at normal LT.
    function setEMode(bool enabled) external {
        eModeEnabled[msg.sender] = enabled;

        // If disabling E-Mode, ensure position is still healthy at normal thresholds
        if (!enabled && debt[msg.sender] > 0) {
            uint256 hf = getHealthFactor(msg.sender);
            if (hf < MIN_HEALTH_FACTOR) revert HealthFactorTooLow();
        }
    }

    // --- Pre-built: View Helpers ---

    /// @notice Returns the active LTV for a user (depends on E-Mode).
    function getUserLTV(address user) public view returns (uint256) {
        return eModeEnabled[user] ? EMODE_LTV : LTV;
    }

    /// @notice Returns the active Liquidation Threshold for a user.
    function getUserLiquidationThreshold(address user) public view returns (uint256) {
        return eModeEnabled[user] ? EMODE_LIQUIDATION_THRESHOLD : LIQUIDATION_THRESHOLD;
    }

    // =============================================================
    //  TODO 1: Implement depositCollateral
    // =============================================================
    /// @notice Deposit wstETH as collateral.
    /// @dev Transfer wstETH from the caller to this contract and track
    ///      the collateral balance.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amount is 0
    ///        2. Transfer wstETH from msg.sender to this contract
    ///        3. Increase the user's collateral balance
    ///
    ///      Hint: Use IERC20.transferFrom(). The user must have approved
    ///            this contract beforehand.
    ///
    /// @param amount The amount of wstETH to deposit (18 decimals)
    function depositCollateral(uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement borrow
    // =============================================================
    /// @notice Borrow stablecoin against deposited wstETH collateral.
    /// @dev The maximum borrowable amount depends on collateral value × LTV.
    ///      The health factor must remain >= 1.0 after borrowing.
    ///
    ///      The math:
    ///        collateralValueUSD = oracle.getWstETHValueUSDSafe(collateral[user])
    ///        maxBorrow = collateralValueUSD × LTV / BPS
    ///        After borrowing, HF must be >= MIN_HEALTH_FACTOR
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amount is 0
    ///        2. Increase user's debt
    ///        3. Increase totalDebt
    ///        4. Check totalDebt <= DEBT_CEILING (revert ExceedsDebtCeiling)
    ///        5. Check health factor >= MIN_HEALTH_FACTOR (revert HealthFactorTooLow)
    ///        6. Transfer stablecoin from this contract to msg.sender
    ///
    ///      Note: The stablecoin amount is in 8 decimals (matching the oracle's
    ///            USD output). In a real protocol, you'd normalize decimals;
    ///            here both oracle output and stablecoin use 8 decimals.
    ///
    ///      Note: In production Aave V3, there's a separate LTV check
    ///            (debt <= collateral × LTV) in addition to the HF check.
    ///            Our simplified version uses only the HF check (which uses LT).
    ///            The LTV and getUserLTV() constants are provided for reference.
    ///
    ///      Hint: Update state BEFORE checking health factor — the check
    ///            should reflect the new debt.
    ///
    /// @param amount The stablecoin amount to borrow (8 decimals)
    function borrow(uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement repay
    // =============================================================
    /// @notice Repay borrowed stablecoin.
    /// @dev Reduces the user's debt and totalDebt.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amount is 0
    ///        2. Revert with InsufficientDebt if amount > user's debt
    ///        3. Transfer stablecoin from msg.sender to this contract
    ///        4. Decrease user's debt
    ///        5. Decrease totalDebt
    ///
    /// @param amount The stablecoin amount to repay (8 decimals)
    function repay(uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement withdrawCollateral
    // =============================================================
    /// @notice Withdraw wstETH collateral.
    /// @dev The user can withdraw collateral as long as health factor stays >= 1.0.
    ///      If the user has no debt, any amount up to their balance can be withdrawn.
    ///
    ///      Steps:
    ///        1. Revert with ZeroAmount if amount is 0
    ///        2. Revert with InsufficientCollateral if amount > user's collateral
    ///        3. Decrease user's collateral
    ///        4. If user has outstanding debt, check HF >= MIN_HEALTH_FACTOR
    ///           (revert HealthFactorTooLow if not)
    ///        5. Transfer wstETH from this contract to msg.sender
    ///
    ///      Hint: Decrease collateral BEFORE checking health factor, so the
    ///            check reflects the reduced collateral.
    ///
    /// @param amount The amount of wstETH to withdraw (18 decimals)
    function withdrawCollateral(uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement liquidate
    // =============================================================
    /// @notice Liquidate an unhealthy position.
    /// @dev Anyone can call this to liquidate a user whose health factor < 1.0.
    ///      The liquidator repays the user's FULL debt and receives the user's
    ///      collateral plus a liquidation bonus.
    ///
    ///      Liquidation math:
    ///        debtUSD = debt[user]  (already in 8-decimal USD)
    ///        debtInWstETH = debtUSD × WAD / wstETHPriceUSD
    ///          where wstETHPriceUSD = oracle.getWstETHValueUSDSafe(1e18)
    ///        collateralSeized = debtInWstETH × (BPS + LIQUIDATION_BONUS) / BPS
    ///          (liquidator gets 5% bonus on top of the debt value)
    ///
    ///      If collateralSeized > user's collateral, seize all collateral
    ///      (partial bad debt — in production this goes to a safety module).
    ///
    ///      Steps:
    ///        1. Check that the user's health factor < MIN_HEALTH_FACTOR
    ///           (revert PositionHealthy if >= 1.0)
    ///        2. Cache the user's debt and collateral
    ///        3. Calculate collateralSeized (debt value + bonus, in wstETH terms)
    ///        4. Cap collateralSeized at user's total collateral
    ///        5. Transfer stablecoin from liquidator to this contract (full debt)
    ///        6. Transfer wstETH from this contract to liquidator (seized collateral)
    ///        7. Clear user's debt (set to 0) and reduce totalDebt
    ///        8. Reduce user's collateral by the seized amount
    ///
    ///      Hint: To convert USD debt to wstETH amount, you need the price of
    ///            1 wstETH in USD from the safe oracle. Then:
    ///            wstETHAmount = debtUSD × WAD / pricePerWstETH
    ///
    /// @param user The address of the user to liquidate
    function liquidate(address user) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 6: Implement getHealthFactor
    // =============================================================
    /// @notice Calculate a user's health factor.
    /// @dev Health Factor = (collateralValueUSD × liquidationThreshold / BPS) / debtUSD
    ///
    ///      The formula (in 18-decimal fixed-point):
    ///        HF = collateralUSD × LT × WAD / (BPS × debtUSD)
    ///
    ///      Where:
    ///        collateralUSD = oracle.getWstETHValueUSDSafe(collateral[user])
    ///        LT = getUserLiquidationThreshold(user) (in basis points)
    ///        debtUSD = debt[user] (in 8-decimal USD)
    ///
    ///      HF > 1e18 → healthy
    ///      HF < 1e18 → liquidatable
    ///      HF = type(uint256).max if no debt (convention: infinite health)
    ///
    ///      Example:
    ///        collateral = 10 wstETH, rate = 1.19, ETH = $3,200
    ///        collateralUSD = 38_080e8 (from oracle)
    ///        LT = 8300 (83%)
    ///        debt = 30_000e8 ($30,000)
    ///
    ///        HF = 38_080e8 × 8300 × 1e18 / (10_000 × 30_000e8)
    ///           = 316_064_000e8 × 1e18 / 300_000_000e8
    ///           = 1.053546...e18  → healthy (> 1.0)
    ///
    ///      Steps:
    ///        1. If user has no debt, return type(uint256).max
    ///        2. Get collateral value in USD via oracle.getWstETHValueUSDSafe()
    ///        3. Get the user's liquidation threshold
    ///        4. Compute HF = collateralUSD × LT × WAD / (BPS × debtUSD)
    ///
    ///      Hint: Use the SAFE oracle (getWstETHValueUSDSafe) so that during
    ///            a de-peg, the health factor correctly drops and triggers
    ///            liquidation. This is the whole point of the dual oracle.
    ///
    /// @param user The address to check
    /// @return healthFactor The health factor in 18-decimal fixed-point
    function getHealthFactor(address user) public view returns (uint256 healthFactor) {
        // YOUR CODE HERE
    }
}

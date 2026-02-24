// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3} from "../module3/interfaces/IAggregatorV3.sol";

// ============================================================================
// EXERCISE: Simplified Lending Pool
//
// Build a minimal lending protocol that teaches the core mechanics of
// Aave V3 and Compound V3 — without the complexity of a full protocol.
//
// What you'll implement:
//   1. Supply/withdraw — deposit USDC, earn interest
//   2. Deposit collateral — post WETH as collateral (no interest)
//   3. Borrow/repay — borrow USDC against collateral
//   4. Interest accrual — index-based system (Aave's approach)
//   5. Health factor — multi-collateral risk assessment
//
// The key insight is INDEX-BASED INTEREST:
//
//   Instead of updating every user's balance each second, the protocol
//   maintains a global "index" that grows over time. User balances are
//   stored as "scaled" values:
//
//     scaledDeposit = actualDeposit × RAY / liquidityIndex
//     actualBalance = scaledDeposit × liquidityIndex / RAY
//
//   When interest accrues, ONLY the index changes. All user balances
//   automatically reflect the new interest through the index.
//
//   This is why Aave can have millions of users but only update ONE
//   storage slot per accrual (the index), not one per user.
//
// Simplifications vs production Aave V3:
//   - Single underlying asset (USDC) instead of multi-asset
//   - Fixed linear interest rate instead of kinked curve
//   - No aTokens / debt tokens
//   - No flash loans, no isolation mode, no e-mode
//   - Simplified health factor (no e-mode categories)
//
// Real protocol references:
//   - Aave V3 Pool.sol: supply(), borrow(), withdraw(), repay()
//   - Aave V3 ReserveLogic.sol: updateState() (index accrual)
//   - Aave V3 GenericLogic.sol: calculateUserAccountData() (health factor)
//
// Run: forge test --match-contract LendingPoolTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroAmount();
error InsufficientBalance();
error InsufficientCollateral();
error UnsupportedCollateral();
error HealthFactorBelowOne();

/// @notice Simplified lending pool with index-based interest accrual.
/// @dev Single underlying asset (USDC) with multi-collateral support.
///      Uses a constant interest rate per second for simplicity.
contract LendingPool {
    using SafeERC20 for IERC20;

    // --- Constants ---
    uint256 public constant RAY = 1e27;
    uint256 public constant HALF_RAY = 0.5e27;
    uint256 public constant HEALTH_FACTOR_ONE = 1e18;

    // --- Immutables ---
    IERC20 public immutable underlying; // The asset being lent/borrowed (USDC)
    uint256 public immutable ratePerSecond; // Fixed interest rate per second (RAY)
    uint8 public immutable underlyingDecimals; // Decimals of the underlying token (e.g., 6 for USDC)

    // --- Interest Indices ---
    /// @notice Cumulative interest multiplier for deposits. Starts at RAY (1.0).
    /// @dev Every time accrueInterest() runs, this grows:
    ///      liquidityIndex = liquidityIndex × (1 + rate × elapsed) / RAY
    ///
    ///      A user who deposited when liquidityIndex = 1.0e27 and withdraws
    ///      when liquidityIndex = 1.05e27 has earned 5% interest.
    uint256 public liquidityIndex;

    /// @notice Cumulative interest multiplier for borrows. Starts at RAY (1.0).
    /// @dev Same growth mechanism as liquidityIndex, but tracks what borrowers owe.
    ///      In a real protocol, borrowIndex often grows faster than liquidityIndex
    ///      because of the reserve factor (protocol's cut).
    ///
    ///      Simplified here: both indices grow at the same rate.
    uint256 public borrowIndex;

    /// @notice Last time interest was accrued.
    uint256 public lastUpdateTimestamp;

    // --- Aggregate Accounting ---
    uint256 public totalScaledDeposits;
    uint256 public totalScaledBorrows;

    // --- User State ---
    /// @notice Scaled deposit balance per user.
    /// @dev Actual balance = scaledDeposits[user] × liquidityIndex / RAY
    mapping(address => uint256) public scaledDeposits;

    /// @notice Scaled borrow balance per user.
    /// @dev Actual debt = scaledBorrows[user] × borrowIndex / RAY
    mapping(address => uint256) public scaledBorrows;

    /// @notice Collateral balances per user per token.
    /// @dev collateralBalances[user][token] = amount deposited
    ///      No index math for collateral — it doesn't earn interest.
    ///      (In Aave V3, collateral IS the aToken, so it does earn. We simplify.)
    mapping(address => mapping(address => uint256)) public collateralBalances;

    // --- Collateral Configuration ---
    /// @notice Risk parameters for each collateral token.
    /// @dev In Aave V3, these live in a packed bitmap (see ConfigBitmap exercise).
    ///      Here we use a simple struct for clarity.
    struct CollateralConfig {
        IAggregatorV3 oracle;             // Chainlink price feed
        uint256 ltvBps;                   // Max borrow power (basis points, e.g., 8000 = 80%)
        uint256 liquidationThresholdBps;  // Liquidation trigger (e.g., 8250 = 82.5%)
        uint256 liquidationBonusBps;      // Bonus for liquidator (e.g., 500 = 5%)
        uint8 tokenDecimals;              // Token decimals (e.g., 18 for WETH)
        uint8 oracleDecimals;             // Oracle decimals (e.g., 8 for Chainlink USD)
    }

    /// @notice Registered collateral configs. Set by admin via addCollateral().
    mapping(address => CollateralConfig) public collateralConfigs;

    /// @notice List of supported collateral tokens (for iterating in health factor).
    address[] public collateralTokens;

    // --- Events ---
    event Supply(address indexed user, uint256 amount, uint256 scaledAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 scaledAmount);
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, uint256 amount, uint256 scaledAmount);
    event Repay(address indexed user, uint256 amount, uint256 scaledAmount);
    event InterestAccrued(uint256 newLiquidityIndex, uint256 newBorrowIndex, uint256 timestamp);

    constructor(address _underlying, uint256 _ratePerSecond, uint8 _underlyingDecimals) {
        underlying = IERC20(_underlying);
        ratePerSecond = _ratePerSecond;
        underlyingDecimals = _underlyingDecimals;
        liquidityIndex = RAY;
        borrowIndex = RAY;
        lastUpdateTimestamp = block.timestamp;
    }

    // =============================================================
    //  PROVIDED: RAY math helpers
    // =============================================================

    function rayMul(uint256 a, uint256 b) public pure returns (uint256) {
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }

    // =============================================================
    //  PROVIDED: Admin function to register collateral types
    // =============================================================

    function addCollateral(
        address token,
        address oracle,
        uint256 ltvBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps,
        uint8 tokenDecimals,
        uint8 oracleDecimals
    ) external {
        // Only push to array if this is a new token (prevent double-counting in HF loop)
        if (collateralConfigs[token].ltvBps == 0) {
            collateralTokens.push(token);
        }
        collateralConfigs[token] = CollateralConfig({
            oracle: IAggregatorV3(oracle),
            ltvBps: ltvBps,
            liquidationThresholdBps: liquidationThresholdBps,
            liquidationBonusBps: liquidationBonusBps,
            tokenDecimals: tokenDecimals,
            oracleDecimals: oracleDecimals
        });
    }

    // =============================================================
    //  TODO 1: Implement supply
    // =============================================================
    /// @notice Deposits underlying tokens into the pool to earn interest.
    /// @dev The deposit is stored as a "scaled" amount that doesn't change
    ///      when interest accrues. The actual balance grows automatically
    ///      because the liquidityIndex grows.
    ///
    ///      Scaled deposit = amount × RAY / liquidityIndex
    ///
    ///      Example:
    ///        liquidityIndex = 1.05e27 (pool has accrued 5% total interest)
    ///        User deposits 1000 USDC
    ///        scaledDeposit = 1000 × 1e27 / 1.05e27 ≈ 952.38
    ///        Later, when liquidityIndex = 1.10e27:
    ///        actualBalance = 952.38 × 1.10e27 / 1e27 ≈ 1047.62
    ///        Interest earned = 1047.62 - 1000 = 47.62 USDC
    ///
    ///      In Aave V3: Pool.supply() → ReserveLogic.updateState() → mint aTokens
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Call accrueInterest() — always accrue BEFORE state changes
    ///   3. Compute scaledAmount = rayDiv(amount, liquidityIndex)
    ///   4. Add scaledAmount to scaledDeposits[msg.sender]
    ///   5. Add scaledAmount to totalScaledDeposits
    ///   6. Transfer underlying from msg.sender to this contract
    ///   7. Emit Supply event
    ///
    /// @param amount The amount of underlying to deposit (in underlying decimals)
    function supply(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement withdraw
    // =============================================================
    /// @notice Withdraws underlying tokens plus accrued interest.
    /// @dev Converts scaled balance back to actual amount:
    ///      actualBalance = scaledDeposit × liquidityIndex / RAY
    ///
    ///      The difference between actualBalance and the original deposit
    ///      is the interest earned — no per-user tracking needed.
    ///
    ///      In Aave V3: Pool.withdraw() → burn aTokens → transfer underlying
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Call accrueInterest()
    ///   3. Compute scaledAmount = rayDiv(amount, liquidityIndex)
    ///   4. Require scaledDeposits[msg.sender] >= scaledAmount (revert InsufficientBalance)
    ///   5. Subtract scaledAmount from scaledDeposits[msg.sender]
    ///   6. Subtract scaledAmount from totalScaledDeposits
    ///   7. Transfer underlying from this contract to msg.sender
    ///   8. Emit Withdraw event
    ///
    /// @param amount The amount of underlying to withdraw (in underlying decimals)
    function withdraw(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement depositCollateral
    // =============================================================
    /// @notice Deposits collateral tokens to use as borrow backing.
    /// @dev Collateral does NOT earn interest in this simplified model.
    ///      It's simply held by the pool and counted toward the health factor.
    ///
    ///      In Aave V3, collateral IS the aToken (so it earns interest).
    ///      We separate them here to keep the concepts clear.
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Require token is a supported collateral (collateralConfigs[token].ltvBps > 0,
    ///      revert UnsupportedCollateral)
    ///   3. Transfer token from msg.sender to this contract
    ///   4. Add amount to collateralBalances[msg.sender][token]
    ///   5. Emit CollateralDeposited event
    ///
    /// @param token The collateral token address
    /// @param amount The amount of collateral to deposit
    function depositCollateral(address token, uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement borrow
    // =============================================================
    /// @notice Borrows underlying tokens against deposited collateral.
    /// @dev Borrow is stored as scaled debt (like deposits, but using borrowIndex).
    ///      The health factor must remain >= 1.0 AFTER the borrow.
    ///
    ///      Scaled debt = amount × RAY / borrowIndex
    ///
    ///      Critical ordering: record the debt FIRST, then check health factor.
    ///      This ensures the new debt is included in the HF calculation.
    ///      If HF < 1 after recording, revert — no partial borrows.
    ///
    ///      In Aave V3: Pool.borrow() → mint debt tokens → check HF
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Call accrueInterest()
    ///   3. Compute scaledAmount = rayDiv(amount, borrowIndex)
    ///   4. Add scaledAmount to scaledBorrows[msg.sender]
    ///   5. Add scaledAmount to totalScaledBorrows
    ///   6. Check getHealthFactor(msg.sender) >= HEALTH_FACTOR_ONE (revert HealthFactorBelowOne)
    ///   7. Transfer underlying from this contract to msg.sender
    ///   8. Emit Borrow event
    ///
    /// @param amount The amount of underlying to borrow
    function borrow(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement repay
    // =============================================================
    /// @notice Repays borrowed tokens (partial or full).
    /// @dev If amount exceeds actual debt, cap at the actual debt.
    ///      This prevents overpayment.
    ///
    ///      Actual debt = scaledBorrows[user] × borrowIndex / RAY
    ///
    ///      In Aave V3: Pool.repay() → burn debt tokens
    ///
    /// Steps:
    ///   1. Require amount > 0 (revert ZeroAmount)
    ///   2. Call accrueInterest()
    ///   3. Compute actualDebt = rayMul(scaledBorrows[msg.sender], borrowIndex)
    ///   4. Cap: repayAmount = min(amount, actualDebt)
    ///   5. Compute scaledRepay = rayDiv(repayAmount, borrowIndex)
    ///   6. Subtract scaledRepay from scaledBorrows[msg.sender]
    ///   7. Subtract scaledRepay from totalScaledBorrows
    ///   8. Transfer repayAmount from msg.sender to this contract
    ///   9. Emit Repay event with repayAmount (not original amount)
    ///
    /// @param amount The amount to repay (capped at actual debt)
    function repay(uint256 amount) external {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement accrueInterest
    // =============================================================
    /// @notice Updates the interest indices based on time elapsed.
    /// @dev This is the heart of the protocol. Instead of updating every user's
    ///      balance, we update TWO numbers (liquidityIndex, borrowIndex) and
    ///      every user's balance changes implicitly.
    ///
    ///      The multiplier for each second of elapsed time:
    ///        multiplier = RAY + ratePerSecond × elapsed
    ///
    ///      This is LINEAR interest (not compound). For compound interest,
    ///      you'd use the Taylor expansion from Exercise 1. We simplify here
    ///      to keep focus on the index mechanics.
    ///
    ///      Example:
    ///        ratePerSecond = 1585489599e9 (≈5% APR)
    ///        elapsed = 86400 (1 day)
    ///        multiplier = 1e27 + 1585489599e9 × 86400 = 1.000137e27
    ///        newIndex = oldIndex × 1.000137e27 / 1e27
    ///
    ///      After 365 days: index ≈ 1.05e27 (5% growth)
    ///
    ///      Idempotent: if called twice in the same block, the second call
    ///      should be a no-op (elapsed = 0 → multiplier = RAY → index unchanged).
    ///
    ///      In Aave V3: ReserveLogic.updateState() → _updateIndexes()
    ///
    /// Steps:
    ///   1. Compute elapsed = block.timestamp - lastUpdateTimestamp
    ///   2. If elapsed == 0, return early (no-op)
    ///   3. Compute multiplier = RAY + ratePerSecond * elapsed
    ///   4. liquidityIndex = rayMul(liquidityIndex, multiplier)
    ///   5. borrowIndex = rayMul(borrowIndex, multiplier)
    ///   6. Update lastUpdateTimestamp = block.timestamp
    ///   7. Emit InterestAccrued event
    function accrueInterest() public {
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 7: Implement getHealthFactor
    // =============================================================
    /// @notice Calculates the health factor for a user.
    /// @dev Health Factor = total collateral value (weighted by liquidation threshold)
    ///                    / total debt value
    ///
    ///      HF > 1.0: safe (cannot be liquidated)
    ///      HF < 1.0: underwater (can be liquidated)
    ///      HF = type(uint256).max: no debt (infinitely healthy)
    ///
    ///      For each collateral token:
    ///        value = balance × oraclePrice × liquidationThreshold / 10000
    ///        (normalized to 18 decimals)
    ///
    ///      The normalization formula:
    ///        valueE18 = balance × price × 10^18 / (10^tokenDecimals × 10^oracleDecimals)
    ///
    ///      Why liquidationThreshold and not LTV?
    ///        LTV controls how much you CAN borrow (prevents over-borrowing).
    ///        LiquidationThreshold controls when you GET LIQUIDATED (higher threshold
    ///        = more buffer before liquidation). LT > LTV always, giving a safety margin.
    ///
    ///      In Aave V3: GenericLogic.calculateUserAccountData()
    ///
    /// Steps:
    ///   1. Compute totalDebt = rayMul(scaledBorrows[user], borrowIndex)
    ///   2. If totalDebt == 0, return type(uint256).max
    ///   3. Normalize debt to 18 decimals:
    ///      totalDebtE18 = totalDebt * 10^(18 - underlyingDecimals)
    ///      (e.g., for USDC: 1000e6 * 1e12 = 1000e18)
    ///   4. For each collateral token:
    ///      a. Get balance = collateralBalances[user][token]
    ///      b. If balance == 0, skip
    ///      c. Get oracle price: call latestRoundData(), use the answer
    ///      d. Normalize to 18 decimals:
    ///         valueE18 = balance * uint256(price) * 1e18 / (10^tokenDecimals * 10^oracleDecimals)
    ///      e. Apply liquidation threshold: weighted = valueE18 * liquidationThresholdBps / 10000
    ///      f. Add to totalCollateralValue
    ///   5. Return totalCollateralValue * 1e18 / totalDebtE18
    ///      (result in 18 decimals: 1e18 = health factor of exactly 1.0)
    ///
    /// @param user The address to check
    /// @return healthFactor The health factor (18 decimals)
    function getHealthFactor(address user) public view returns (uint256 healthFactor) {
        // solhint-disable-next-line no-unused-vars
        healthFactor; // silence unused variable warning
        revert("Not implemented");
    }

    // =============================================================
    //  VIEW HELPERS (provided)
    // =============================================================

    /// @notice Returns the actual (non-scaled) deposit balance including interest.
    function getActualDeposit(address user) external view returns (uint256) {
        return rayMul(scaledDeposits[user], liquidityIndex);
    }

    /// @notice Returns the actual (non-scaled) borrow balance including interest.
    function getActualDebt(address user) external view returns (uint256) {
        return rayMul(scaledBorrows[user], borrowIndex);
    }
}

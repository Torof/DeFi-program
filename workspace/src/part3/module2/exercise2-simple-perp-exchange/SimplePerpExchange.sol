// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// EXERCISE: Simplified Perpetual Exchange
//
// Build a perpetual exchange that combines ALL Module 2 concepts:
//   - Oracle-based pricing (mock price feed)
//   - Position lifecycle (open, close with PnL)
//   - Funding rate accumulator (skew-based, from Exercise 1)
//   - Leverage enforcement (max leverage check)
//   - Margin tracking (collateral + PnL + funding = remaining margin)
//   - Keeper-triggered liquidation with incentive fee
//   - LP pool as counterparty (deposit/withdraw liquidity)
//
// This mirrors the GMX pool model: traders trade against an LP pool.
// LPs deposit USDC, earn fees, and take the other side of every trade.
// The LP pool must remain solvent: it must hold enough to cover all
// potential trader profits.
//
// Simplifications vs production:
//   - Single market (ETH/USD) with one collateral token (USDC)
//   - No price impact fees (Exercise 1's funding handles skew incentives)
//   - No borrow fees (only funding)
//   - One position per user
//   - Full liquidation only (no partial)
//   - No two-step execution (direct oracle price)
//
// Concepts exercised:
//   - Everything from Exercise 1 (funding accumulator)
//   - PnL calculation for longs and shorts
//   - Margin/leverage math (initial margin, maintenance margin)
//   - Liquidation mechanics (keeper incentive, insurance fund)
//   - LP pool accounting (deposits, withdrawals, solvency)
//
// Key references:
//   - Module 2 lesson: part3/2-perpetuals.md (all topics)
//   - Exercise 1: FundingRateEngine (funding accumulator pattern)
//   - GMX V2: pool-as-counterparty model
//
// Run: forge test --match-contract SimplePerpExchangeTest -vvv
// ============================================================================

// --- Custom Errors ---
error ZeroAmount();
error ZeroSize();
error PositionAlreadyExists();
error NoPosition();
error ExceedsMaxLeverage();
error PositionHealthy();
error InsufficientPoolLiquidity();

/// @notice Simplified perpetual exchange with LP pool counterparty.
/// @dev Pre-built: constructor, state, types, constants, view helpers, LP functions.
///      Student implements: openPosition, closePosition, liquidate,
///                          getUnrealizedPnL, getRemainingMargin, isLiquidatable,
///                          _updateFunding (reuse Exercise 1 pattern).
contract SimplePerpExchange {
    // --- Types ---

    struct Position {
        uint256 sizeUsd;           // position size in USD (8 decimals)
        uint256 collateral;        // collateral deposited in USDC (6 decimals)
        uint256 entryPrice;        // entry price in USD (8 decimals)
        bool isLong;               // true = long, false = short
        int256 entryFundingIndex;  // snapshot of cumulative funding at open
    }

    // --- State ---

    /// @dev The USDC token used for collateral and LP deposits.
    IERC20 public immutable usdc;

    /// @dev Current ETH/USD price (8 decimals). Updated by the owner/oracle.
    ///      In production this would come from Chainlink. Here we use a simple
    ///      setter for testing flexibility.
    uint256 public ethPrice;

    /// @dev Per-user position. One position per address.
    mapping(address => Position) public positions;

    /// @dev Total long open interest in USD (8 decimals).
    uint256 public longOpenInterest;

    /// @dev Total short open interest in USD (8 decimals).
    uint256 public shortOpenInterest;

    /// @dev Global cumulative funding per unit of position size (18 decimals).
    int256 public cumulativeFundingPerUnit;

    /// @dev Timestamp of last funding update.
    uint256 public lastFundingTimestamp;

    /// @dev LP pool balance in USDC (6 decimals). This is the counterparty capital.
    uint256 public poolBalance;

    /// @dev Insurance fund in USDC (6 decimals). Absorbs bad debt from underwater liquidations.
    uint256 public insuranceFund;

    // --- Constants ---

    /// @dev Maximum leverage allowed (e.g., 20x).
    ///      Initial margin = sizeUsd / MAX_LEVERAGE
    uint256 public constant MAX_LEVERAGE = 20;

    /// @dev Maintenance margin in basis points (5% = 500 BPS).
    ///      If remaining margin < sizeUsd * MAINTENANCE_MARGIN_BPS / BPS,
    ///      the position is liquidatable.
    uint256 public constant MAINTENANCE_MARGIN_BPS = 500;

    /// @dev Liquidation fee in basis points (1% = 100 BPS).
    ///      Paid to the keeper (liquidator) as incentive.
    uint256 public constant LIQUIDATION_FEE_BPS = 100;

    /// @dev Basis points denominator.
    uint256 public constant BPS = 10_000;

    /// @dev Skew scale for funding rate (same as Exercise 1).
    uint256 public constant SKEW_SCALE = 100_000_000e8; // $100M

    /// @dev Seconds per day.
    uint256 public constant SECONDS_PER_DAY = 86_400;

    /// @dev 1e18 fixed-point precision.
    uint256 private constant WAD = 1e18;

    /// @dev USDC has 6 decimals; prices have 8 decimals.
    ///      To convert USD (8 dec) to USDC (6 dec): divide by 100
    ///      To convert USDC (6 dec) to USD (8 dec): multiply by 100
    uint256 private constant USD_TO_USDC = 100;

    constructor(address _usdc, uint256 _initialEthPrice) {
        usdc = IERC20(_usdc);
        ethPrice = _initialEthPrice;
        lastFundingTimestamp = block.timestamp;
    }

    // --- Pre-built: Price setter (simulates oracle) ---

    /// @notice Set the ETH price (simulates oracle update).
    /// @dev In production, this would be a Chainlink oracle read.
    function setEthPrice(uint256 newPrice) external {
        ethPrice = newPrice;
    }

    // --- Pre-built: LP Pool Functions ---

    /// @notice Deposit USDC into the LP pool.
    /// @dev LPs provide counterparty liquidity. Their funds back trader positions.
    function depositLiquidity(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        usdc.transferFrom(msg.sender, address(this), amount);
        poolBalance += amount;
    }

    /// @notice Withdraw USDC from the LP pool.
    /// @dev LPs can withdraw as long as the pool retains enough to cover open positions.
    ///      Simplified: we just check poolBalance >= amount.
    function withdrawLiquidity(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > poolBalance) revert InsufficientPoolLiquidity();
        poolBalance -= amount;
        usdc.transfer(msg.sender, amount);
    }

    // =============================================================
    //  TODO 1: Implement _updateFunding (internal)
    // =============================================================
    /// @notice Update the global funding accumulator (same pattern as Exercise 1).
    /// @dev Must be called before any position change.
    ///
    ///      Steps:
    ///        1. Calculate elapsed = block.timestamp - lastFundingTimestamp
    ///        2. If elapsed == 0, return
    ///        3. Compute funding rate: (longOI - shortOI) * WAD / SKEW_SCALE
    ///        4. Compute increment: rate * elapsed / SECONDS_PER_DAY
    ///        5. Add increment to cumulativeFundingPerUnit
    ///        6. Update lastFundingTimestamp
    ///
    ///      This is identical to Exercise 1's updateFunding + getCurrentFundingRate
    ///      combined into one internal function.
    ///
    function _updateFunding() internal {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement openPosition
    // =============================================================
    /// @notice Open a leveraged long or short position.
    /// @dev The user deposits USDC collateral and specifies a position size.
    ///      The leverage is checked: sizeUsd / (collateral * USD_TO_USDC) <= MAX_LEVERAGE.
    ///
    ///      Steps:
    ///        1. Revert ZeroSize if sizeUsd is 0
    ///        2. Revert ZeroAmount if collateral is 0
    ///        3. Revert PositionAlreadyExists if user already has a position
    ///        4. Check leverage: sizeUsd <= collateral * USD_TO_USDC * MAX_LEVERAGE
    ///           Revert ExceedsMaxLeverage if exceeded
    ///           (collateral is in USDC 6-dec, sizeUsd is in USD 8-dec,
    ///            so collateral * USD_TO_USDC converts USDC to USD 8-dec)
    ///        5. Call _updateFunding()
    ///        6. Transfer collateral (USDC) from user to this contract
    ///        7. Store the position:
    ///           - sizeUsd, collateral, entryPrice = ethPrice, isLong
    ///           - entryFundingIndex = cumulativeFundingPerUnit
    ///        8. Update OI: longOpenInterest or shortOpenInterest += sizeUsd
    ///
    ///      Note: Collateral goes to the contract (not the pool). The pool is the
    ///            counterparty — it backs the potential PnL payout to traders.
    ///
    /// @param sizeUsd Position size in USD (8 decimals)
    /// @param collateral Collateral in USDC (6 decimals)
    /// @param isLong True for long, false for short
    function openPosition(uint256 sizeUsd, uint256 collateral, bool isLong) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement getUnrealizedPnL
    // =============================================================
    /// @notice Calculate unrealized PnL for a position in USD (8 decimals).
    /// @dev The formula depends on direction:
    ///      Long:  PnL = sizeUsd * (currentPrice - entryPrice) / entryPrice
    ///      Short: PnL = sizeUsd * (entryPrice - currentPrice) / entryPrice
    ///
    ///      The result is signed: positive = profit, negative = loss.
    ///
    ///      Steps:
    ///        1. Revert NoPosition if user has no position
    ///        2. Read position's sizeUsd, entryPrice, isLong
    ///        3. Compute PnL based on direction using current ethPrice
    ///
    ///      Hint: Use int256 casts for the arithmetic since PnL can be negative.
    ///            sizeUsd and prices are uint256, but the difference
    ///            (currentPrice - entryPrice) can be negative for longs.
    ///
    /// @param user The address to check
    /// @return pnl Signed PnL in USD (8 decimals)
    function getUnrealizedPnL(address user) public view returns (int256 pnl) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement getRemainingMargin
    // =============================================================
    /// @notice Calculate remaining margin for a position in USDC (6 decimals).
    /// @dev Remaining margin = collateral + PnL (in USDC) + funding (in USDC)
    ///
    ///      Conversion: PnL and funding are in USD (8 dec). USDC is 6 dec.
    ///      To convert: usdcAmount = usdAmount / USD_TO_USDC
    ///      BUT be careful with signed division — we want truncation toward zero.
    ///
    ///      Steps:
    ///        1. Revert NoPosition if user has no position
    ///        2. Get unrealized PnL via getUnrealizedPnL(user)
    ///        3. Get pending funding:
    ///           a. Compute live accumulator (same as Exercise 1's getPendingFunding):
    ///              elapsed = block.timestamp - lastFundingTimestamp
    ///              unaccrued = rate * elapsed / SECONDS_PER_DAY
    ///              liveAcc = cumulativeFundingPerUnit + unaccrued
    ///           b. delta = liveAcc - entryFundingIndex
    ///           c. rawFunding = int256(sizeUsd) * delta / int256(WAD)
    ///           d. If long: funding = -rawFunding; if short: funding = +rawFunding
    ///        4. Convert PnL and funding from USD (8 dec) to USDC (6 dec):
    ///           pnlUsdc = pnl / int256(USD_TO_USDC)
    ///           fundingUsdc = funding / int256(USD_TO_USDC)
    ///        5. remainingMargin = int256(collateral) + pnlUsdc + fundingUsdc
    ///        6. If remainingMargin < 0, return 0 (margin can't go negative in uint)
    ///        7. Return uint256(remainingMargin)
    ///
    ///      Note: This function should NOT update state (it's a view).
    ///            To get accurate live funding, compute the unaccrued portion
    ///            manually (like getPendingFunding in Exercise 1).
    ///
    /// @param user The address to check
    /// @return margin Remaining margin in USDC (6 decimals)
    function getRemainingMargin(address user) public view returns (uint256 margin) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement isLiquidatable
    // =============================================================
    /// @notice Check if a position can be liquidated.
    /// @dev A position is liquidatable when:
    ///      remainingMargin < maintenanceMarginUsdc
    ///
    ///      Where:
    ///        maintenanceMarginUsd = sizeUsd * MAINTENANCE_MARGIN_BPS / BPS
    ///        maintenanceMarginUsdc = maintenanceMarginUsd / USD_TO_USDC
    ///
    ///      Steps:
    ///        1. Revert NoPosition if user has no position
    ///        2. Get remainingMargin via getRemainingMargin(user)
    ///        3. Compute maintenance margin in USDC
    ///        4. Return remainingMargin < maintenanceMarginUsdc
    ///
    /// @param user The address to check
    /// @return True if the position can be liquidated
    function isLiquidatable(address user) public view returns (bool) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 6: Implement closePosition
    // =============================================================
    /// @notice Close the caller's position, settling PnL and funding.
    /// @dev The trader receives their collateral +/- PnL +/- funding.
    ///      If the position is profitable, the LP pool pays the profit.
    ///      If the position is losing, the loss stays in the contract (LP pool benefits).
    ///
    ///      Steps:
    ///        1. Revert NoPosition if caller has no position
    ///        2. Call _updateFunding()
    ///        3. Compute PnL (using getUnrealizedPnL) and funding:
    ///           a. delta = cumulativeFundingPerUnit - entryFundingIndex
    ///           b. rawFunding = int256(sizeUsd) * delta / int256(WAD)
    ///           c. funding = long ? -rawFunding : rawFunding
    ///        4. Convert PnL and funding to USDC (divide by USD_TO_USDC)
    ///        5. Compute payout = int256(collateral) + pnlUsdc + fundingUsdc
    ///        6. If payout < 0, set payout = 0 (trader loses everything)
    ///        7. If payout > int256(collateral):
    ///           The trader profits. The profit portion comes from the pool.
    ///           profitUsdc = uint256(payout) - collateral
    ///           Revert InsufficientPoolLiquidity if profitUsdc > poolBalance
    ///           poolBalance -= profitUsdc
    ///        8. If payout < int256(collateral):
    ///           The trader lost money. The loss stays in the contract.
    ///           (The LP pool implicitly benefits — funds remain in the contract)
    ///        9. Update OI (decrease longOpenInterest or shortOpenInterest)
    ///       10. Delete the position
    ///       11. Transfer uint256(payout) USDC to the trader (if > 0)
    ///
    /// @return payout The USDC amount returned to the trader (6 decimals)
    function closePosition() external returns (uint256 payout) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 7: Implement liquidate
    // =============================================================
    /// @notice Liquidate an unhealthy position.
    /// @dev Anyone can call this. The liquidator (keeper) receives a fee
    ///      from the remaining margin. The rest goes to the insurance fund.
    ///
    ///      Steps:
    ///        1. Revert PositionHealthy if !isLiquidatable(user)
    ///        2. Call _updateFunding()
    ///        3. Get the remaining margin (getRemainingMargin but we need
    ///           the post-update version; since _updateFunding was just called
    ///           and getRemainingMargin is a view, it should be accurate now)
    ///        4. Compute liquidation fee:
    ///           liquidationFeeUsdc = position.sizeUsd * LIQUIDATION_FEE_BPS / BPS / USD_TO_USDC
    ///        5. If remainingMargin > 0:
    ///           a. keeperFee = min(liquidationFeeUsdc, remainingMargin)
    ///           b. toInsurance = remainingMargin - keeperFee
    ///           c. Transfer keeperFee USDC to msg.sender (liquidator)
    ///           d. insuranceFund += toInsurance
    ///        6. If remainingMargin == 0 (underwater):
    ///           No fees to distribute (bad debt absorbed by insurance fund)
    ///           In our simplified model, the bad debt is implicit — the pool
    ///           already "lost" the amount when the position went underwater.
    ///        7. Update OI
    ///        8. Delete the position
    ///
    ///      Note: The liquidated trader's collateral is already in the contract.
    ///            We just redistribute it (fee to keeper, rest to insurance).
    ///            The trader receives nothing.
    ///
    /// @param user The address to liquidate
    function liquidate(address user) external {
        // YOUR CODE HERE
    }
}

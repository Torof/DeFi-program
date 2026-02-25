// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Liquidation Cascade & Bad Debt Scenarios
//
// These exercises explore what happens when markets crash. You'll simulate:
//
//   1. Cascading liquidations — one liquidation triggers the next
//   2. Bad debt — prices crash too fast for liquidation to help
//   3. Bad debt socialization — how protocols spread losses across suppliers
//
// This is a TEST-ONLY exercise. You'll implement test scenarios using the
// existing MockLendingPool from Exercise 4 (FlashLiquidator).
//
// Why this matters:
//   - March 2020 "Black Thursday" — MakerDAO accrued $6M in bad debt when
//     ETH crashed 40% in hours and liquidations failed
//   - Cascading liquidations can create a death spiral: liquidation → sell
//     collateral → price drops further → more liquidations
//   - Understanding these dynamics is critical for protocol design
//
// Run: forge test --match-contract LiquidationScenariosTest -vvv
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockLendingPool} from "../../../../src/part2/module4/mocks/MockLendingPool.sol";
import {MockERC20} from "../../../../src/part2/module4/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../../../src/part2/module3/mocks/MockAggregatorV3.sol";

// =============================================================
//  TODO: Implement BadDebtPool
// =============================================================
/// @notice Extended lending pool that can handle bad debt socialization.
/// @dev TODO: Implement the handleBadDebt function.
///
///      When a position has more debt than collateral value (even after
///      seizing everything), the protocol has "bad debt" — a loss that
///      must be absorbed somehow.
///
///      Strategies:
///        a) Socialize across suppliers — reduce everyone's deposits proportionally
///        b) Use a reserve fund / treasury
///        c) Issue governance tokens to cover (MakerDAO's MKR dilution)
///
///      For this exercise, implement option (a): socialize the loss.
///
///      The key insight: bad debt = borrower's remaining debt after all
///      collateral is seized. This amount is owed to suppliers but can
///      never be recovered. Each supplier absorbs a share proportional
///      to their deposit.
contract BadDebtPool is MockLendingPool {
    // Track total supply pool (simplified — sum of all deposits)
    uint256 public totalDeposits;
    mapping(address => uint256) public deposits;

    /// @notice Deposit into the supply pool.
    function deposit(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
    }

    /// @notice Handle bad debt by socializing the loss across all depositors.
    /// @dev TODO: Implement this function.
    ///
    ///   After a liquidation where collateral < debt, the borrower still has
    ///   remaining debt. This function:
    ///     1. Computes the bad debt amount for the borrower
    ///        (remaining debtAmount in their position after all collateral is seized)
    ///     2. Clears the borrower's remaining debt (write it off)
    ///     3. Reduces totalDeposits by the bad debt amount
    ///        (suppliers collectively absorb the loss)
    ///     4. Returns the bad debt amount
    ///
    ///   In practice, each supplier's share of the pool decreases proportionally.
    ///   If you deposited 10% of the pool, you absorb 10% of the bad debt.
    ///
    /// @param borrower The address with bad debt
    /// @return badDebt The amount of unrecoverable debt
    function handleBadDebt(address borrower) external returns (uint256 badDebt) {
        // TODO: Implement
        revert("Not implemented");
    }
}

contract LiquidationScenariosTest is Test {
    MockLendingPool pool;
    BadDebtPool badDebtPool;
    MockERC20 usdc;
    MockERC20 weth;
    MockAggregatorV3 ethOracle;
    MockAggregatorV3 usdcOracle;

    address liquidator = makeAddr("liquidator");
    address supplier1 = makeAddr("supplier1");
    address supplier2 = makeAddr("supplier2");

    // Borrowers with progressively tighter positions
    address borrower1 = makeAddr("borrower1");
    address borrower2 = makeAddr("borrower2");
    address borrower3 = makeAddr("borrower3");
    address borrower4 = makeAddr("borrower4");
    address borrower5 = makeAddr("borrower5");

    int256 constant INITIAL_ETH_PRICE = 2000e8; // $2,000
    int256 constant USDC_PRICE = 1e8;            // $1

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);

        // Deploy oracles
        ethOracle = new MockAggregatorV3(INITIAL_ETH_PRICE, 8);
        usdcOracle = new MockAggregatorV3(USDC_PRICE, 8);

        // Deploy pools
        pool = new MockLendingPool();
        badDebtPool = new BadDebtPool();

        // Configure oracles
        pool.setOracle(address(weth), address(ethOracle));
        pool.setOracle(address(usdc), address(usdcOracle));
        badDebtPool.setOracle(address(weth), address(ethOracle));
        badDebtPool.setOracle(address(usdc), address(usdcOracle));

        // Fund the pool with WETH for collateral transfers
        weth.mint(address(pool), 1_000e18);
        usdc.mint(address(pool), 10_000_000e6);

        // Fund liquidator with USDC to repay debts
        usdc.mint(liquidator, 10_000_000e6);
        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
    }

    // =========================================================
    //  Test 1: Cascading Liquidations
    // =========================================================
    // Set up 5 borrowers at progressively tighter health factors.
    // Drop the price in steps. After each drop, check which
    // borrowers become liquidatable. Liquidate them and observe
    // how the system evolves.

    function test_Cascade_SetupProgressiveHealthFactors() public {
        // All borrowers deposit 1 ETH as collateral ($2,000 at initial price)
        // They borrow different amounts of USDC:
        //   borrower1: $1,200 debt → HF = 2000/1200 ≈ 1.67 (very safe)
        //   borrower2: $1,500 debt → HF = 2000/1500 ≈ 1.33 (safe)
        //   borrower3: $1,700 debt → HF = 2000/1700 ≈ 1.18 (tight)
        //   borrower4: $1,850 debt → HF = 2000/1850 ≈ 1.08 (very tight)
        //   borrower5: $1,950 debt → HF = 2000/1950 ≈ 1.03 (barely safe)

        _setupBorrowers();

        // Verify all are healthy at $2,000
        assertGe(pool.getHealthFactor(borrower1), 1e18, "Borrower 1 should be safe");
        assertGe(pool.getHealthFactor(borrower2), 1e18, "Borrower 2 should be safe");
        assertGe(pool.getHealthFactor(borrower3), 1e18, "Borrower 3 should be safe");
        assertGe(pool.getHealthFactor(borrower4), 1e18, "Borrower 4 should be safe");
        assertGe(pool.getHealthFactor(borrower5), 1e18, "Borrower 5 should be safe");
    }

    function test_Cascade_FirstPriceDrop_OnlyWeakestLiquidated() public {
        _setupBorrowers();

        // Price drops 5%: $2,000 → $1,900
        ethOracle.updateAnswer(1900e8);

        // borrower5 ($1,950 debt): HF = 1900/1950 ≈ 0.97 → LIQUIDATABLE
        // borrower4 ($1,850 debt): HF = 1900/1850 ≈ 1.03 → still safe
        assertLt(pool.getHealthFactor(borrower5), 1e18, "Borrower 5 should be liquidatable after 5% drop");
        assertGe(pool.getHealthFactor(borrower4), 1e18, "Borrower 4 should still be safe");

        // Liquidate borrower5
        vm.prank(liquidator);
        pool.liquidate(borrower5, address(usdc), 1950e6, address(weth));

        // After liquidation, borrower5's position should be cleared/reduced
        uint256 hfAfter = pool.getHealthFactor(borrower5);
        assertTrue(
            hfAfter >= 1e18 || hfAfter == type(uint256).max,
            "Borrower 5 should be healthy or debt-free after liquidation"
        );
    }

    function test_Cascade_SecondDrop_MoreBorrowersFall() public {
        _setupBorrowers();

        // First drop: 5%
        ethOracle.updateAnswer(1900e8);
        vm.prank(liquidator);
        pool.liquidate(borrower5, address(usdc), 1950e6, address(weth));

        // Second drop: another 5% → $1,805
        ethOracle.updateAnswer(1805e8);

        // borrower4 ($1,850 debt): HF = 1805/1850 ≈ 0.976 → LIQUIDATABLE
        // borrower3 ($1,700 debt): HF = 1805/1700 ≈ 1.06 → still safe
        assertLt(pool.getHealthFactor(borrower4), 1e18, "Borrower 4 should be liquidatable after 10% total drop");
        assertGe(pool.getHealthFactor(borrower3), 1e18, "Borrower 3 should still be safe");

        vm.prank(liquidator);
        pool.liquidate(borrower4, address(usdc), 1850e6, address(weth));
    }

    function test_Cascade_SevereDropLiquidatesMultiple() public {
        _setupBorrowers();

        // Severe crash: 15% → $1,700
        ethOracle.updateAnswer(1700e8);

        // Count how many are liquidatable
        uint256 liquidatableCount;
        address[5] memory borrowers = [borrower1, borrower2, borrower3, borrower4, borrower5];
        for (uint256 i = 0; i < 5; i++) {
            if (pool.getHealthFactor(borrowers[i]) < 1e18) {
                liquidatableCount++;
            }
        }

        // At $1,700: borrower5 ($1,950), borrower4 ($1,850), borrower3 ($1,700) all at or below
        assertGe(liquidatableCount, 2, "At least 2 borrowers should be liquidatable after 15% drop");

        // Liquidate all underwater positions
        for (uint256 i = 4; i > 0; i--) {
            if (pool.getHealthFactor(borrowers[i]) < 1e18) {
                (, , , uint256 debtAmount) = pool.positions(borrowers[i]);
                vm.prank(liquidator);
                pool.liquidate(borrowers[i], address(usdc), debtAmount, address(weth));
            }
        }
        // Also check borrower at index 0
        if (pool.getHealthFactor(borrowers[0]) < 1e18) {
            (, , , uint256 debtAmount) = pool.positions(borrowers[0]);
            vm.prank(liquidator);
            pool.liquidate(borrowers[0], address(usdc), debtAmount, address(weth));
        }
    }

    // =========================================================
    //  Test 2: Bad Debt Scenario
    // =========================================================
    // When price crashes too fast (>50% in one block), there's no
    // time to liquidate. Collateral becomes worth less than debt.

    function test_BadDebt_FlashCrashCreatesBadDebt() public {
        // Borrower has 1 ETH ($2,000) collateral, $1,800 debt
        pool.setPosition(borrower1, address(weth), 1e18, address(usdc), 1800e6);

        // Verify healthy
        assertGe(pool.getHealthFactor(borrower1), 1e18, "Should be healthy before crash");

        // Flash crash: 50% → $1,000
        ethOracle.updateAnswer(1000e8);

        // HF = 1000/1800 ≈ 0.56 → deeply underwater
        uint256 hf = pool.getHealthFactor(borrower1);
        assertLt(hf, 1e18, "Should be deeply underwater");

        // Even after liquidating ALL collateral:
        // Collateral value = 1 ETH × $1,000 = $1,000
        // Debt = $1,800
        // Shortfall = $800 → this is BAD DEBT (unrecoverable)

        // Liquidate everything
        vm.prank(liquidator);
        uint256 collateralSeized = pool.liquidate(borrower1, address(usdc), 1800e6, address(weth));

        // The collateral seized covers only part of the debt value
        // (the mock pool may clear the full debt but that's a simplification)
        // The key insight: 1 ETH at $1,000 doesn't cover $1,800 of debt
        uint256 collateralValueUsd = collateralSeized * 1000 / 1e18; // value in whole dollars
        assertLt(collateralValueUsd * 1e6, 1800e6, "Collateral value should be less than debt (bad debt exists)");
    }

    // =========================================================
    //  Test 3: Bad Debt Socialization
    // =========================================================

    function test_BadDebt_SocializationReducesDeposits() public {
        // Setup: suppliers deposit into the bad debt pool
        usdc.mint(supplier1, 50_000e6);
        usdc.mint(supplier2, 50_000e6);
        weth.mint(address(badDebtPool), 100e18);
        usdc.mint(address(badDebtPool), 10_000_000e6);

        vm.prank(supplier1);
        usdc.approve(address(badDebtPool), type(uint256).max);
        vm.prank(supplier1);
        badDebtPool.deposit(address(usdc), 50_000e6);

        vm.prank(supplier2);
        usdc.approve(address(badDebtPool), type(uint256).max);
        vm.prank(supplier2);
        badDebtPool.deposit(address(usdc), 50_000e6);

        // Total deposits = $100,000
        assertEq(badDebtPool.totalDeposits(), 100_000e6, "Total deposits should be $100k");

        // Borrower has 1 ETH, $1,800 debt
        badDebtPool.setPosition(borrower1, address(weth), 1e18, address(usdc), 1800e6);

        // Flash crash
        ethOracle.updateAnswer(1000e8);

        // Liquidate (seize all collateral, but debt remains)
        usdc.mint(liquidator, 2000e6);
        vm.prank(liquidator);
        usdc.approve(address(badDebtPool), type(uint256).max);
        vm.prank(liquidator);
        badDebtPool.liquidate(borrower1, address(usdc), 1800e6, address(weth));

        // Handle the bad debt
        uint256 badDebt = badDebtPool.handleBadDebt(borrower1);

        // The bad debt amount should be written off from total deposits
        // Suppliers collectively absorb the loss
        uint256 depositsAfter = badDebtPool.totalDeposits();
        assertEq(depositsAfter, 100_000e6 - badDebt, "Total deposits should decrease by bad debt amount");

        // Each supplier's proportional share decreases
        // (In this simplified model, we just track total. In practice,
        // each supplier's share of the smaller pool is their loss.)
    }

    // =========================================================
    //  Helpers
    // =========================================================

    function _setupBorrowers() internal {
        // All borrowers: 1 ETH collateral, varying debt
        pool.setPosition(borrower1, address(weth), 1e18, address(usdc), 1200e6);
        pool.setPosition(borrower2, address(weth), 1e18, address(usdc), 1500e6);
        pool.setPosition(borrower3, address(weth), 1e18, address(usdc), 1700e6);
        pool.setPosition(borrower4, address(weth), 1e18, address(usdc), 1850e6);
        pool.setPosition(borrower5, address(weth), 1e18, address(usdc), 1950e6);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE - it is the test suite for the LSTLendingPool exercise.
//  Implement LSTLendingPool.sol (and WstETHOracle.sol from Exercise 1) to make
//  these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    LSTLendingPool,
    ZeroAmount,
    HealthFactorTooLow,
    PositionHealthy,
    ExceedsDebtCeiling,
    InsufficientCollateral,
    InsufficientDebt
} from "../../../../src/part3/module1/exercise2-lst-lending-pool/LSTLendingPool.sol";
import {WstETHOracle} from "../../../../src/part3/module1/exercise1-lst-oracle/WstETHOracle.sol";
import {MockWstETH} from "../../../../src/part3/module1/mocks/MockWstETH.sol";
import {MockAggregatorV3} from "../../../../src/part3/module1/mocks/MockAggregatorV3.sol";
import {MockERC20} from "../../../../src/part3/module1/mocks/MockERC20.sol";

contract LSTLendingPoolTest is Test {
    // --- Contracts ---
    LSTLendingPool public pool;
    WstETHOracle public oracle;
    MockWstETH public wstETH;
    MockAggregatorV3 public ethUsdFeed;
    MockAggregatorV3 public stethEthFeed;
    MockERC20 public stablecoin;

    // --- Actors ---
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");

    // --- Constants ---

    /// @dev wstETH exchange rate: 1 wstETH = 1.19 stETH
    uint256 constant EXCHANGE_RATE = 1.19e18;

    /// @dev ETH/USD: $3,200 (8 decimals)
    int256 constant ETH_USD_PRICE = 3200e8;

    /// @dev stETH/ETH: 1.0 (normal peg, 18 decimals)
    int256 constant STETH_ETH_PRICE = 1e18;

    /// @dev Standard collateral for Alice: 10 wstETH
    uint256 constant ALICE_COLLATERAL = 10e18;

    /// @dev 10 wstETH at 1.19 rate and $3,200 = $38,080 (8 decimals)
    uint256 constant ALICE_COLLATERAL_VALUE_USD = 38_080e8;

    function setUp() public {
        // Warp to realistic timestamp
        vm.warp(1_700_000_000);

        // Deploy mocks
        wstETH = new MockWstETH(EXCHANGE_RATE);
        ethUsdFeed = new MockAggregatorV3(ETH_USD_PRICE, 8);
        stethEthFeed = new MockAggregatorV3(STETH_ETH_PRICE, 18);
        stablecoin = new MockERC20("USD Stablecoin", "USDX", 8);

        // Deploy oracle
        oracle = new WstETHOracle(
            address(wstETH),
            address(ethUsdFeed),
            address(stethEthFeed)
        );

        // Deploy lending pool
        pool = new LSTLendingPool(
            address(oracle),
            address(wstETH),
            address(stablecoin)
        );

        // --- Setup Alice: 10 wstETH, approved ---
        wstETH.mint(alice, ALICE_COLLATERAL);
        vm.prank(alice);
        wstETH.approve(address(pool), type(uint256).max);

        // --- Setup Bob: 5 wstETH, approved ---
        wstETH.mint(bob, 5e18);
        vm.prank(bob);
        wstETH.approve(address(pool), type(uint256).max);

        // --- Fund pool with stablecoin reserves (for borrowing) ---
        stablecoin.mint(address(pool), 5_000_000e8); // $5M reserves

        // --- Setup liquidator: stablecoin for repaying debts ---
        stablecoin.mint(liquidator, 1_000_000e8);
        vm.prank(liquidator);
        stablecoin.approve(address(pool), type(uint256).max);

        // --- Setup Alice and Bob stablecoin approvals (for repay) ---
        vm.prank(alice);
        stablecoin.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        stablecoin.approve(address(pool), type(uint256).max);
    }

    // =========================================================
    //  Deposit Collateral (TODO 1)
    // =========================================================

    function test_depositCollateral_basic() public {
        vm.prank(alice);
        pool.depositCollateral(ALICE_COLLATERAL);

        assertEq(pool.collateral(alice), ALICE_COLLATERAL, "Alice should have 10 wstETH collateral");
        assertEq(wstETH.balanceOf(address(pool)), ALICE_COLLATERAL, "Pool should hold the wstETH");
        assertEq(wstETH.balanceOf(alice), 0, "Alice should have 0 wstETH remaining");
    }

    function test_depositCollateral_multiple() public {
        vm.startPrank(alice);
        pool.depositCollateral(5e18);
        pool.depositCollateral(5e18);
        vm.stopPrank();

        assertEq(pool.collateral(alice), ALICE_COLLATERAL, "Two deposits should sum correctly");
    }

    function test_depositCollateral_zeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(alice);
        pool.depositCollateral(0);
    }

    // =========================================================
    //  Borrow (TODO 2)
    // =========================================================

    function test_borrow_basic() public {
        _depositAlice();

        // Alice borrows $20,000 against $38,080 collateral
        // At 80% LTV, max borrow = $38,080 × 0.80 = $30,464
        // $20,000 is well under max
        vm.prank(alice);
        pool.borrow(20_000e8);

        assertEq(pool.debt(alice), 20_000e8, "Alice should have $20,000 debt");
        assertEq(pool.totalDebt(), 20_000e8, "Total debt should be $20,000");
        assertEq(stablecoin.balanceOf(alice), 20_000e8, "Alice should receive $20,000 stablecoin");
    }

    function test_borrow_zeroAmount() public {
        _depositAlice();

        vm.expectRevert(ZeroAmount.selector);
        vm.prank(alice);
        pool.borrow(0);
    }

    function test_borrow_exceedsLTV() public {
        _depositAlice();

        // Collateral value = $38,080
        // At 83% LT: $38,080 × 0.83 = $31,606.4
        // Borrowing $32,000 → HF = 31,606.4 / 32,000 = 0.987... < 1.0
        vm.expectRevert(HealthFactorTooLow.selector);
        vm.prank(alice);
        pool.borrow(32_000e8);
    }

    function test_borrow_exceedsDebtCeiling() public {
        // Give Alice enough collateral for a huge borrow
        wstETH.mint(alice, 10_000e18);
        vm.prank(alice);
        pool.depositCollateral(10_010e18);

        // Fund pool with more reserves
        stablecoin.mint(address(pool), 100_000_000e8);

        // Try to borrow above the $10M ceiling
        vm.expectRevert(ExceedsDebtCeiling.selector);
        vm.prank(alice);
        pool.borrow(10_000_001e8);
    }

    function test_borrow_multipleBorrows() public {
        _depositAlice();

        vm.startPrank(alice);
        pool.borrow(10_000e8);
        pool.borrow(10_000e8);
        vm.stopPrank();

        assertEq(pool.debt(alice), 20_000e8, "Multiple borrows should accumulate debt");
        assertEq(pool.totalDebt(), 20_000e8, "Total debt should reflect both borrows");
    }

    // =========================================================
    //  Repay (TODO 3)
    // =========================================================

    function test_repay_full() public {
        _depositAndBorrowAlice(20_000e8);

        // Give Alice stablecoin to repay (she already has 20_000e8 from borrow)
        vm.prank(alice);
        pool.repay(20_000e8);

        assertEq(pool.debt(alice), 0, "Debt should be zero after full repay");
        assertEq(pool.totalDebt(), 0, "Total debt should be zero");
    }

    function test_repay_partial() public {
        _depositAndBorrowAlice(20_000e8);

        vm.prank(alice);
        pool.repay(5_000e8);

        assertEq(pool.debt(alice), 15_000e8, "Debt should decrease by repaid amount");
        assertEq(pool.totalDebt(), 15_000e8, "Total debt should decrease");
    }

    function test_repay_zeroAmount() public {
        _depositAndBorrowAlice(20_000e8);

        vm.expectRevert(ZeroAmount.selector);
        vm.prank(alice);
        pool.repay(0);
    }

    function test_repay_exceedsDebt() public {
        _depositAndBorrowAlice(20_000e8);

        vm.expectRevert(InsufficientDebt.selector);
        vm.prank(alice);
        pool.repay(20_001e8);
    }

    // =========================================================
    //  Withdraw Collateral (TODO 4)
    // =========================================================

    function test_withdrawCollateral_noDebt() public {
        _depositAlice();

        // No debt: can withdraw everything
        vm.prank(alice);
        pool.withdrawCollateral(ALICE_COLLATERAL);

        assertEq(pool.collateral(alice), 0, "Collateral should be zero after full withdrawal");
        assertEq(wstETH.balanceOf(alice), ALICE_COLLATERAL, "Alice should receive all wstETH back");
    }

    function test_withdrawCollateral_withDebtHealthy() public {
        _depositAndBorrowAlice(20_000e8);

        // Withdraw 1 wstETH (collateral drops to 9 wstETH)
        // New collateral value = 9 × 1.19 × 3200 = $34,272
        // HF = 34,272 × 0.83 / 20,000 = 1.422 → healthy
        vm.prank(alice);
        pool.withdrawCollateral(1e18);

        assertEq(pool.collateral(alice), 9e18, "Collateral should decrease by 1 wstETH");
    }

    function test_withdrawCollateral_wouldBreakHealthFactor() public {
        _depositAndBorrowAlice(30_000e8);

        // Collateral value = $38,080, debt = $30,000
        // HF = 38,080 × 0.83 / 30,000 = 1.053 → barely healthy
        // Withdrawing 2 wstETH → collateral = 8 wstETH = $30,464
        // HF = 30,464 × 0.83 / 30,000 = 0.842 → unhealthy!
        vm.expectRevert(HealthFactorTooLow.selector);
        vm.prank(alice);
        pool.withdrawCollateral(2e18);
    }

    function test_withdrawCollateral_zeroAmount() public {
        _depositAlice();

        vm.expectRevert(ZeroAmount.selector);
        vm.prank(alice);
        pool.withdrawCollateral(0);
    }

    function test_withdrawCollateral_exceedsBalance() public {
        _depositAlice();

        vm.expectRevert(InsufficientCollateral.selector);
        vm.prank(alice);
        pool.withdrawCollateral(ALICE_COLLATERAL + 1);
    }

    // =========================================================
    //  Health Factor (TODO 6)
    // =========================================================

    function test_getHealthFactor_noDebt() public {
        _depositAlice();

        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max, "No debt should return max uint256 (infinite health)");
    }

    function test_getHealthFactor_healthy() public {
        _depositAndBorrowAlice(20_000e8);

        // collateralUSD = $38,080
        // HF = 38,080 × 8300 × 1e18 / (10,000 × 20,000e8)
        //    = 316,064,000e8 × 1e18 / 200,000,000e8
        //    = 1.580320e18
        uint256 hf = pool.getHealthFactor(alice);
        uint256 expected = uint256(ALICE_COLLATERAL_VALUE_USD) * 8300 * 1e18 / (10_000 * 20_000e8);
        assertEq(hf, expected, "Health factor should match manual calculation");
        assertGt(hf, 1e18, "Health factor should be above 1.0 (healthy)");
    }

    function test_getHealthFactor_nearLiquidation() public {
        _depositAndBorrowAlice(30_000e8);

        // HF = 38,080 × 8300 × 1e18 / (10,000 × 30,000e8)
        //    = 316,064,000e8 × 1e18 / 300,000,000e8
        //    = 1.053546...e18 → barely healthy
        uint256 hf = pool.getHealthFactor(alice);
        assertGt(hf, 1e18, "Should still be healthy at $30,000 debt");
        assertLt(hf, 1.1e18, "But barely - HF should be close to 1.0");
    }

    function test_getHealthFactor_increasesWithExchangeRate() public {
        _depositAndBorrowAlice(20_000e8);

        uint256 hfBefore = pool.getHealthFactor(alice);

        // Simulate 1 year of staking rewards: rate 1.19 → 1.2267
        wstETH.setExchangeRate(1.2267e18);

        uint256 hfAfter = pool.getHealthFactor(alice);

        assertGt(
            hfAfter,
            hfBefore,
            "Health factor should increase as wstETH exchange rate grows (staking rewards)"
        );
    }

    // =========================================================
    //  De-Peg Scenario (Health Factor + Liquidation)
    // =========================================================

    function test_depeg_healthFactorDrops() public {
        _depositAndBorrowAlice(30_000e8);

        uint256 hfBefore = pool.getHealthFactor(alice);
        assertGt(hfBefore, 1e18, "Should be healthy before de-peg");

        // Simulate stETH/ETH de-peg to 0.93
        stethEthFeed.updateAnswer(0.93e18);

        uint256 hfAfter = pool.getHealthFactor(alice);
        assertLt(hfAfter, 1e18, "Should be liquidatable after 7% de-peg");
    }

    function test_depeg_enablesLiquidation() public {
        _depositAndBorrowAlice(30_000e8);

        // Before de-peg: position is healthy, cannot liquidate
        vm.expectRevert(PositionHealthy.selector);
        vm.prank(liquidator);
        pool.liquidate(alice);

        // Trigger de-peg
        stethEthFeed.updateAnswer(0.93e18);

        // Now liquidation should succeed
        uint256 liquidatorWstETHBefore = wstETH.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        // Alice's debt should be cleared
        assertEq(pool.debt(alice), 0, "Alice's debt should be zero after liquidation");

        // Liquidator should have received wstETH
        uint256 liquidatorWstETHAfter = wstETH.balanceOf(liquidator);
        assertGt(
            liquidatorWstETHAfter,
            liquidatorWstETHBefore,
            "Liquidator should receive wstETH collateral"
        );
    }

    // =========================================================
    //  Liquidation (TODO 5)
    // =========================================================

    function test_liquidate_healthyPositionReverts() public {
        _depositAndBorrowAlice(20_000e8);

        vm.expectRevert(PositionHealthy.selector);
        vm.prank(liquidator);
        pool.liquidate(alice);
    }

    function test_liquidate_collateralTransfer() public {
        _depositAndBorrowAlice(30_000e8);
        stethEthFeed.updateAnswer(0.93e18);

        uint256 aliceCollateralBefore = pool.collateral(alice);
        uint256 liquidatorWstBefore = wstETH.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        uint256 aliceCollateralAfter = pool.collateral(alice);
        uint256 liquidatorWstAfter = wstETH.balanceOf(liquidator);

        // Alice should have less collateral
        assertLt(aliceCollateralAfter, aliceCollateralBefore, "Alice's collateral should decrease");

        // Liquidator should have more wstETH
        uint256 liquidatorReceived = liquidatorWstAfter - liquidatorWstBefore;
        assertGt(liquidatorReceived, 0, "Liquidator should receive wstETH");
    }

    function test_liquidate_liquidatorPaysDebt() public {
        _depositAndBorrowAlice(30_000e8);
        stethEthFeed.updateAnswer(0.93e18);

        uint256 liquidatorStableBefore = stablecoin.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        uint256 liquidatorStableAfter = stablecoin.balanceOf(liquidator);

        // Liquidator should have paid Alice's full debt
        assertEq(
            liquidatorStableBefore - liquidatorStableAfter,
            30_000e8,
            "Liquidator should pay the full debt amount"
        );
    }

    function test_liquidate_bonusApplied() public {
        _depositAndBorrowAlice(30_000e8);
        stethEthFeed.updateAnswer(0.93e18);

        // Calculate expected seized collateral:
        // debt = $30,000 (30_000e8)
        // wstETH price (safe) during de-peg:
        //   effectiveRate = 1.19e18 × 0.93e18 / 1e18 = 1.1067e18
        //   pricePerWstETH = 1.1067e18 × 3200e8 / 1e18 = 3541.44e8
        // debtInWstETH = 30_000e8 × 1e18 / 3541.44e8
        // collateralSeized = debtInWstETH × (10_000 + 500) / 10_000 (5% bonus)
        uint256 effectiveRate = EXCHANGE_RATE * uint256(int256(0.93e18)) / 1e18;
        uint256 pricePerWstETH = effectiveRate * uint256(ETH_USD_PRICE) / 1e18;
        uint256 debtInWstETH = uint256(30_000e8) * 1e18 / pricePerWstETH;
        uint256 expectedSeized = debtInWstETH * 10_500 / 10_000;

        uint256 liquidatorWstBefore = wstETH.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        uint256 liquidatorReceived = wstETH.balanceOf(liquidator) - liquidatorWstBefore;

        assertEq(
            liquidatorReceived,
            expectedSeized,
            "Liquidator should receive debt value + 5% bonus in wstETH"
        );
    }

    function test_liquidate_clearsDebt() public {
        _depositAndBorrowAlice(30_000e8);
        stethEthFeed.updateAnswer(0.93e18);

        vm.prank(liquidator);
        pool.liquidate(alice);

        assertEq(pool.debt(alice), 0, "Alice's debt should be fully cleared");
        assertEq(pool.totalDebt(), 0, "Total debt should decrease by Alice's debt");
    }

    // =========================================================
    //  E-Mode (Higher LTV for Correlated Assets)
    // =========================================================

    function test_eMode_allowsHigherBorrow() public {
        _depositAlice();

        // Normal LTV: max borrow = $38,080 × 80% = $30,464
        // E-Mode LTV: max borrow = $38,080 × 93% = $35,414.4
        // Borrow $32,000 — should fail in normal mode
        vm.startPrank(alice);

        // First try without E-Mode — should fail (HF too low at normal LT)
        // At normal LT (83%): HF = 38,080 × 0.83 / 32,000 = 0.987 → unhealthy
        vm.expectRevert(HealthFactorTooLow.selector);
        pool.borrow(32_000e8);

        // Enable E-Mode and try again
        pool.setEMode(true);
        pool.borrow(32_000e8);

        vm.stopPrank();

        assertEq(pool.debt(alice), 32_000e8, "Should be able to borrow more with E-Mode");
    }

    function test_eMode_higherHealthFactor() public {
        _depositAndBorrowAlice(20_000e8);

        uint256 hfNormal = pool.getHealthFactor(alice);

        vm.prank(alice);
        pool.setEMode(true);

        uint256 hfEMode = pool.getHealthFactor(alice);

        assertGt(hfEMode, hfNormal, "E-Mode should increase health factor (higher LT)");
    }

    function test_eMode_disableChecksHealth() public {
        _depositAlice();

        vm.startPrank(alice);

        // Enable E-Mode and borrow at high LTV
        pool.setEMode(true);
        pool.borrow(35_000e8);

        // Try to disable E-Mode — would drop HF below 1.0 at normal LT
        // HF at normal LT: 38,080 × 0.83 / 35,000 = 0.903 → unhealthy
        vm.expectRevert(HealthFactorTooLow.selector);
        pool.setEMode(false);

        vm.stopPrank();
    }

    // =========================================================
    //  Full Lifecycle
    // =========================================================

    function test_fullLifecycle_depositBorrowRepayWithdraw() public {
        vm.startPrank(alice);

        // 1. Deposit
        pool.depositCollateral(ALICE_COLLATERAL);
        assertEq(pool.collateral(alice), ALICE_COLLATERAL);

        // 2. Borrow
        pool.borrow(20_000e8);
        assertEq(pool.debt(alice), 20_000e8);
        assertEq(stablecoin.balanceOf(alice), 20_000e8);

        // 3. Repay
        pool.repay(20_000e8);
        assertEq(pool.debt(alice), 0);

        // 4. Withdraw
        pool.withdrawCollateral(ALICE_COLLATERAL);
        assertEq(pool.collateral(alice), 0);
        assertEq(wstETH.balanceOf(alice), ALICE_COLLATERAL);

        vm.stopPrank();
    }

    function test_multipleUsers() public {
        // Alice deposits 10 wstETH, borrows $20,000
        _depositAndBorrowAlice(20_000e8);

        // Bob deposits 5 wstETH, borrows $10,000
        vm.startPrank(bob);
        pool.depositCollateral(5e18);
        pool.borrow(10_000e8);
        vm.stopPrank();

        assertEq(pool.totalDebt(), 30_000e8, "Total debt should reflect both users");
        assertEq(pool.debt(alice), 20_000e8, "Alice's debt tracked independently");
        assertEq(pool.debt(bob), 10_000e8, "Bob's debt tracked independently");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_depositAndWithdrawBalanced(uint256 amount) public {
        amount = bound(amount, 1, ALICE_COLLATERAL);

        vm.startPrank(alice);
        pool.depositCollateral(amount);

        uint256 poolBalance = wstETH.balanceOf(address(pool));
        assertEq(poolBalance, amount, "INVARIANT: Pool balance should equal deposited amount");

        pool.withdrawCollateral(amount);
        vm.stopPrank();

        assertEq(pool.collateral(alice), 0, "INVARIANT: Collateral should be zero after full withdraw");
        assertEq(wstETH.balanceOf(alice), ALICE_COLLATERAL, "INVARIANT: Alice should get all tokens back");
    }

    function testFuzz_borrowRepayBalanced(uint256 borrowAmount) public {
        _depositAlice();

        // Bound to safe borrow range (well under LTV limit)
        // Max safe borrow at 83% LT: 38_080 × 83% = ~31,606 → use 30,000 as safe max
        borrowAmount = bound(borrowAmount, 1e8, 30_000e8);

        vm.startPrank(alice);
        pool.borrow(borrowAmount);

        // Repay the exact amount borrowed
        pool.repay(borrowAmount);
        vm.stopPrank();

        assertEq(pool.debt(alice), 0, "INVARIANT: Debt should be zero after full repay");
        assertEq(pool.totalDebt(), 0, "INVARIANT: Total debt should be zero");
    }

    // =========================================================
    //  Internal Helpers
    // =========================================================

    /// @dev Alice deposits her full 10 wstETH collateral.
    function _depositAlice() internal {
        vm.prank(alice);
        pool.depositCollateral(ALICE_COLLATERAL);
    }

    /// @dev Alice deposits 10 wstETH and borrows the specified stablecoin amount.
    function _depositAndBorrowAlice(uint256 borrowAmount) internal {
        vm.startPrank(alice);
        pool.depositCollateral(ALICE_COLLATERAL);
        pool.borrow(borrowAmount);
        vm.stopPrank();
    }
}

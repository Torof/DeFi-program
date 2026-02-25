// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE -- it is the test suite for the LendingPool
//  exercise. Implement LendingPool.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../../../src/part2/module4/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../../../src/part2/module3/mocks/MockAggregatorV3.sol";
import {
    LendingPool,
    ZeroAmount,
    InsufficientBalance,
    HealthFactorBelowOne,
    UnsupportedCollateral
} from "../../../../src/part2/module4/exercise2-lending-pool/LendingPool.sol";

contract LendingPoolTest is Test {
    LendingPool pool;
    MockERC20 usdc;
    MockERC20 weth;
    MockAggregatorV3 ethOracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant RAY = 1e27;

    // ~5% APR: 0.05 / 31_536_000 seconds ≈ 1.585e-9 per second
    // In RAY: 1_585_489_599e9
    uint256 constant RATE_PER_SECOND = 1_585_489_599e9;

    // Collateral config: WETH
    uint256 constant LTV_BPS = 8000;            // 80% LTV
    uint256 constant LIQ_THRESHOLD_BPS = 8250;  // 82.5% liquidation threshold
    uint256 constant LIQ_BONUS_BPS = 500;       // 5% bonus
    uint8 constant WETH_DECIMALS = 18;
    uint8 constant ORACLE_DECIMALS = 8;

    int256 constant ETH_PRICE = 2000_00000000; // $2,000 with 8 decimals

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);

        // Deploy oracle
        ethOracle = new MockAggregatorV3(ETH_PRICE, ORACLE_DECIMALS);

        // Deploy lending pool (USDC as underlying, 6 decimals)
        pool = new LendingPool(address(usdc), RATE_PER_SECOND, 6);

        // Register WETH as collateral
        pool.addCollateral(
            address(weth),
            address(ethOracle),
            LTV_BPS,
            LIQ_THRESHOLD_BPS,
            LIQ_BONUS_BPS,
            WETH_DECIMALS,
            ORACLE_DECIMALS
        );

        // Fund alice: 10,000 USDC for supplying + 10 WETH for collateral
        usdc.mint(alice, 10_000e6);
        weth.mint(alice, 10e18);

        // Fund bob: 10,000 USDC for supplying + 5 WETH for collateral
        usdc.mint(bob, 10_000e6);
        weth.mint(bob, 5e18);
    }

    // =========================================================
    //  Supply & Withdraw
    // =========================================================

    function test_Supply_Basic() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e6);
        pool.supply(1000e6);
        vm.stopPrank();

        // Scaled deposit should equal amount at index=RAY (initial state)
        assertEq(pool.scaledDeposits(alice), 1000e6, "Scaled deposit should equal amount when index is RAY");
        assertEq(pool.totalScaledDeposits(), 1000e6, "Total scaled deposits should update");
        assertEq(usdc.balanceOf(address(pool)), 1000e6, "Pool should hold the USDC");
    }

    function test_Supply_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        pool.supply(0);
    }

    function test_Withdraw_Basic() public {
        // Supply first
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e6);
        pool.supply(1000e6);

        // Withdraw immediately (no time elapsed → no interest)
        pool.withdraw(1000e6);
        vm.stopPrank();

        assertEq(pool.scaledDeposits(alice), 0, "Scaled deposits should be 0 after full withdrawal");
        assertEq(usdc.balanceOf(alice), 10_000e6, "Alice should have all her USDC back");
    }

    function test_Withdraw_WithInterest() public {
        // Supply
        vm.startPrank(alice);
        usdc.approve(address(pool), 5000e6);
        pool.supply(5000e6);
        vm.stopPrank();

        // Warp 1 year
        vm.warp(block.timestamp + 365.25 days);
        pool.accrueInterest(); // Update indices so view helpers return fresh values

        // After ~5% APR for 1 year, balance should be ~5250 USDC
        uint256 actualBalance = pool.getActualDeposit(alice);
        assertGt(actualBalance, 5000e6, "Balance should have grown with interest");
        assertApproxEqRel(
            actualBalance,
            5250e6,
            0.01e18, // 1% tolerance (linear vs compound)
            "~5% APR should yield ~5250 after 1 year"
        );
    }

    function test_Withdraw_InsufficientBalance_Reverts() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e6);
        pool.supply(1000e6);

        vm.expectRevert(InsufficientBalance.selector);
        pool.withdraw(1001e6);
        vm.stopPrank();
    }

    function test_Withdraw_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        pool.withdraw(0);
    }

    // =========================================================
    //  Deposit Collateral
    // =========================================================

    function test_DepositCollateral_Basic() public {
        vm.startPrank(alice);
        weth.approve(address(pool), 2e18);
        pool.depositCollateral(address(weth), 2e18);
        vm.stopPrank();

        assertEq(
            pool.collateralBalances(alice, address(weth)),
            2e18,
            "Collateral balance should be recorded"
        );
        assertEq(weth.balanceOf(address(pool)), 2e18, "Pool should hold the WETH");
    }

    function test_DepositCollateral_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        pool.depositCollateral(address(weth), 0);
    }

    function test_DepositCollateral_UnsupportedToken_Reverts() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(alice, 1e18);

        vm.startPrank(alice);
        randomToken.approve(address(pool), 1e18);
        vm.expectRevert(UnsupportedCollateral.selector);
        pool.depositCollateral(address(randomToken), 1e18);
        vm.stopPrank();
    }

    // =========================================================
    //  Borrow & Repay
    // =========================================================

    function test_Borrow_Basic() public {
        // Supply USDC liquidity (bob provides the borrowable funds)
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        // Alice deposits collateral and borrows
        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);

        // 5 ETH * $2000 * 80% LTV = $8,000 max borrow
        // Borrow $1,000 — well within limits
        pool.borrow(1000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 11_000e6, "Alice should have original + borrowed USDC");
        assertGt(pool.scaledBorrows(alice), 0, "Scaled borrows should be recorded");
    }

    function test_Borrow_ExceedsCapacity_Reverts() public {
        // Supply liquidity
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        // Alice deposits 1 ETH ($2000) collateral
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.depositCollateral(address(weth), 1e18);

        // 1 ETH * $2000 * 82.5% LT = $1,650 health factor threshold
        // Borrow $2,000 → HF < 1
        vm.expectRevert(HealthFactorBelowOne.selector);
        pool.borrow(2000e6);
        vm.stopPrank();
    }

    function test_Borrow_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        pool.borrow(0);
    }

    function test_Repay_Full() public {
        // Setup: supply + collateral + borrow
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);
        pool.borrow(1000e6);

        // Repay in full
        usdc.approve(address(pool), 1000e6);
        pool.repay(1000e6);
        vm.stopPrank();

        assertEq(pool.scaledBorrows(alice), 0, "Debt should be fully repaid");
    }

    function test_Repay_Partial() public {
        // Setup: supply + collateral + borrow
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);
        pool.borrow(1000e6);

        // Repay 500 (half)
        usdc.approve(address(pool), 500e6);
        pool.repay(500e6);
        vm.stopPrank();

        // Should have ~500 debt remaining
        uint256 remainingDebt = pool.getActualDebt(alice);
        assertApproxEqAbs(remainingDebt, 500e6, 1, "Should have ~500 USDC debt remaining");
    }

    function test_Repay_CapsAtDebt() public {
        // Setup: supply + collateral + borrow 500
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);
        pool.borrow(500e6);

        // Try to repay 1000 (more than debt) — should only take 500
        uint256 balanceBefore = usdc.balanceOf(alice);
        usdc.approve(address(pool), 1000e6);
        pool.repay(1000e6);
        uint256 balanceAfter = usdc.balanceOf(alice);
        vm.stopPrank();

        // Should only have transferred 500, not 1000
        assertEq(balanceBefore - balanceAfter, 500e6, "Should only repay the actual debt, not the excess");
        assertEq(pool.scaledBorrows(alice), 0, "Debt should be fully repaid");
    }

    function test_Repay_WithInterest() public {
        // Setup
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);
        pool.borrow(1000e6);
        vm.stopPrank();

        // Warp 1 year
        vm.warp(block.timestamp + 365.25 days);
        pool.accrueInterest(); // Update indices so view helpers return fresh values

        // Debt should have grown ~5%
        uint256 debt = pool.getActualDebt(alice);
        assertGt(debt, 1000e6, "Debt should grow with interest");
        assertApproxEqRel(debt, 1050e6, 0.01e18, "~5% APR debt growth over 1 year");
    }

    function test_Repay_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        pool.repay(0);
    }

    // =========================================================
    //  Interest Accrual
    // =========================================================

    function test_AccrueInterest_IndexGrows() public {
        uint256 indexBefore = pool.liquidityIndex();

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);
        pool.accrueInterest();

        uint256 indexAfter = pool.liquidityIndex();
        assertGt(indexAfter, indexBefore, "Liquidity index should grow after time passes");
    }

    function test_AccrueInterest_Idempotent() public {
        // Warp and accrue
        vm.warp(block.timestamp + 1 days);
        pool.accrueInterest();

        uint256 indexAfter1 = pool.liquidityIndex();

        // Call again in same block — should be no-op
        pool.accrueInterest();

        uint256 indexAfter2 = pool.liquidityIndex();
        assertEq(indexAfter1, indexAfter2, "Accrual in same block should be idempotent");
    }

    function test_AccrueInterest_BothIndicesGrow() public {
        vm.warp(block.timestamp + 30 days);
        pool.accrueInterest();

        assertGt(pool.liquidityIndex(), RAY, "Liquidity index should exceed RAY");
        assertGt(pool.borrowIndex(), RAY, "Borrow index should exceed RAY");
    }

    // =========================================================
    //  Health Factor
    // =========================================================

    function test_HealthFactor_NoDebt() public view {
        // No debt → max health factor
        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max, "No debt should return max health factor");
    }

    function test_HealthFactor_Safe() public {
        // Supply liquidity
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        // Alice: 5 ETH collateral ($10,000), borrow $1,000
        vm.startPrank(alice);
        weth.approve(address(pool), 5e18);
        pool.depositCollateral(address(weth), 5e18);
        pool.borrow(1000e6);
        vm.stopPrank();

        // HF = (5 * 2000 * 0.825) / 1000 = 8250/1000 = 8.25
        uint256 hf = pool.getHealthFactor(alice);
        assertApproxEqRel(hf, 8.25e18, 0.001e18, "Health factor should be ~8.25");
    }

    function test_HealthFactor_Underwater() public {
        // Supply liquidity
        vm.startPrank(bob);
        usdc.approve(address(pool), 10_000e6);
        pool.supply(10_000e6);
        vm.stopPrank();

        // Alice: 1 ETH ($2000), borrow close to max
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.depositCollateral(address(weth), 1e18);
        pool.borrow(1600e6); // HF = (1 * 2000 * 0.825) / 1600 = 1.03125
        vm.stopPrank();

        // Price drops to $1000
        ethOracle.updateAnswer(1000_00000000);

        // HF = (1 * 1000 * 0.825) / 1600 = 0.515625 — underwater!
        uint256 hf = pool.getHealthFactor(alice);
        assertLt(hf, 1e18, "Health factor should be below 1 after price drop");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_MultipleSuppliers_IndependentBalances() public {
        // Alice supplies 5000
        vm.startPrank(alice);
        usdc.approve(address(pool), 5000e6);
        pool.supply(5000e6);
        vm.stopPrank();

        // Bob supplies 3000
        vm.startPrank(bob);
        usdc.approve(address(pool), 3000e6);
        pool.supply(3000e6);
        vm.stopPrank();

        assertEq(pool.scaledDeposits(alice), 5000e6, "Alice scaled deposit should be 5000");
        assertEq(pool.scaledDeposits(bob), 3000e6, "Bob scaled deposit should be 3000");
        assertEq(pool.totalScaledDeposits(), 8000e6, "Total should be sum of both");
    }
}

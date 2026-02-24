// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE -- it is the test suite for the FlashLiquidator
//  exercise. Implement FlashLiquidator.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../../src/part2/module4/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../../src/part2/module3/mocks/MockAggregatorV3.sol";
import {MockLendingPool} from "../../../src/part2/module4/mocks/MockLendingPool.sol";
import {MockFlashLender} from "../../../src/part2/module4/mocks/MockFlashLender.sol";
import {MockDEX} from "../../../src/part2/module4/mocks/MockDEX.sol";
import {
    FlashLiquidator,
    NotFlashLender,
    NotSelf,
    LiquidationUnprofitable
} from "../../../src/part2/module4/FlashLiquidator.sol";

contract FlashLiquidatorTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockAggregatorV3 ethOracle;
    MockAggregatorV3 usdcOracle;
    MockLendingPool lendingPool;
    MockFlashLender flashLender;
    MockDEX dex;
    FlashLiquidator liquidator;

    address alice = makeAddr("alice"); // Underwater borrower
    address bot = makeAddr("bot");     // Liquidation bot operator

    // ETH = $2000, USDC = $1
    int256 constant ETH_PRICE = 2000_00000000;  // 8 decimals
    int256 constant USDC_PRICE = 1_00000000;    // 8 decimals

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);

        // Deploy oracles
        ethOracle = new MockAggregatorV3(ETH_PRICE, 8);
        usdcOracle = new MockAggregatorV3(USDC_PRICE, 8);

        // Deploy infrastructure
        lendingPool = new MockLendingPool();
        flashLender = new MockFlashLender();
        dex = new MockDEX();

        // Configure lending pool oracles
        lendingPool.setOracle(address(weth), address(ethOracle));
        lendingPool.setOracle(address(usdc), address(usdcOracle));

        // Configure DEX prices (1 WETH = 2000 USDC, bidirectional)
        dex.setPrice(address(weth), address(usdc), 2000e18);
        dex.setPrice(address(usdc), address(weth), 0.0005e18); // 1/2000

        // Deploy liquidator (bot is the deployer/owner)
        vm.prank(bot);
        liquidator = new FlashLiquidator(
            address(flashLender),
            address(lendingPool),
            address(dex)
        );

        // Setup Alice's underwater position:
        //   Collateral: 1 WETH ($2000)
        //   Debt: 1800 USDC
        //   HF = $2000 / $1800 = 1.111... → will be made underwater by price drop
        _setupAlicePosition(1e18, 1800e6);

        // Fund lending pool with collateral (so it can transfer to liquidator)
        weth.mint(address(lendingPool), 100e18);
    }

    // =========================================================
    //  Happy Path
    // =========================================================

    function test_Liquidation_HappyPath() public {
        // Drop ETH price to $1500 → HF = 1500/1800 = 0.833 → underwater
        ethOracle.updateAnswer(1500_00000000);

        // HF < 0.95 → 100% close factor → can liquidate full debt
        vm.prank(bot);
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));

        // Liquidator should have profit remaining
        uint256 profit = usdc.balanceOf(address(liquidator));
        assertGt(profit, 0, "Liquidation should be profitable");
    }

    function test_Liquidation_ExactProfit() public {
        // ETH = $1500, Alice: 1 WETH, 1800 USDC debt
        ethOracle.updateAnswer(1500_00000000);
        dex.setPrice(address(weth), address(usdc), 1500e18);

        vm.prank(bot);
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));

        // Expected: liquidate 1800 USDC debt
        //   Collateral seized = 1800 * 1.05 / 1500 = 1.26 WETH
        //   Sell 1.26 WETH at $1500 = 1890 USDC
        //   Flash fee = 1800 * 0.0009 = 1.62 USDC
        //   Repay = 1800 + 1.62 = 1801.62 USDC
        //   Profit = 1890 - 1801.62 = 88.38 USDC
        uint256 profit = usdc.balanceOf(address(liquidator));
        assertApproxEqAbs(profit, 88.38e6, 0.01e6, "Profit should be ~88.38 USDC (5% bonus - 0.09% fee)");
    }

    // =========================================================
    //  Close Factor
    // =========================================================

    function test_CloseFactor_50Percent() public {
        // HF = 0.96 (between 0.95 and 1.0) → only 50% can be liquidated
        // Need: collateral_value / debt = 0.96
        // 1 WETH at $X, debt 1800 USDC → $X / $1800 = 0.96 → X = 1728
        ethOracle.updateAnswer(1728_00000000);
        dex.setPrice(address(weth), address(usdc), 1728e18);

        // Try liquidating full debt — should fail (exceeds 50% close factor)
        vm.prank(bot);
        vm.expectRevert(); // MockLendingPool.ExceedsCloseFactor
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));

        // Liquidate half (900 USDC) — should succeed
        vm.prank(bot);
        liquidator.liquidate(alice, address(usdc), 900e6, address(weth));

        uint256 profit = usdc.balanceOf(address(liquidator));
        assertGt(profit, 0, "50% liquidation should still be profitable");
    }

    function test_CloseFactor_100Percent() public {
        // HF = 0.90 (< 0.95) → 100% close factor
        // $X / $1800 = 0.90 → X = 1620
        ethOracle.updateAnswer(1620_00000000);
        dex.setPrice(address(weth), address(usdc), 1620e18);

        // Liquidate full debt — should succeed
        vm.prank(bot);
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));

        assertGt(usdc.balanceOf(address(liquidator)), 0, "Full liquidation should succeed");
    }

    // =========================================================
    //  Unprofitable Liquidation
    // =========================================================

    function test_Unprofitable_Reverts() public {
        // ETH crashed to $1500 but DEX only offers $1400 (bad slippage)
        ethOracle.updateAnswer(1500_00000000);
        dex.setPrice(address(weth), address(usdc), 1400e18); // Below oracle

        // Collateral seized at oracle price, sold at DEX price → loss
        // The proceeds from selling won't cover the flash loan + fee
        vm.prank(bot);
        vm.expectRevert(LiquidationUnprofitable.selector);
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));
    }

    // =========================================================
    //  Callback Security
    // =========================================================

    function test_OnFlashLoan_WrongCaller_Reverts() public {
        // Random address calls onFlashLoan directly
        vm.prank(makeAddr("random"));
        vm.expectRevert(NotFlashLender.selector);
        liquidator.onFlashLoan(
            address(liquidator),
            address(usdc),
            1000e6,
            1e6,
            abi.encode(alice, address(weth))
        );
    }

    function test_OnFlashLoan_WrongInitiator_Reverts() public {
        // Flash lender calls but with wrong initiator
        vm.prank(address(flashLender));
        vm.expectRevert(NotSelf.selector);
        liquidator.onFlashLoan(
            makeAddr("attacker"), // Not address(liquidator)
            address(usdc),
            1000e6,
            1e6,
            abi.encode(alice, address(weth))
        );
    }

    // =========================================================
    //  Healthy Position (should revert)
    // =========================================================

    function test_HealthyPosition_Reverts() public {
        // Alice is healthy (HF > 1) — liquidation should fail at the pool level
        vm.prank(bot);
        vm.expectRevert(); // MockLendingPool.HealthyPosition
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));
    }

    // =========================================================
    //  Profit Withdrawal
    // =========================================================

    function test_WithdrawProfit() public {
        // Execute a profitable liquidation
        ethOracle.updateAnswer(1500_00000000);
        dex.setPrice(address(weth), address(usdc), 1500e18);

        vm.prank(bot);
        liquidator.liquidate(alice, address(usdc), 1800e6, address(weth));

        uint256 profit = usdc.balanceOf(address(liquidator));
        assertGt(profit, 0, "Should have profit to withdraw");

        // Bot withdraws profit
        uint256 botBalanceBefore = usdc.balanceOf(bot);
        vm.prank(bot);
        liquidator.withdrawProfit(address(usdc));

        assertEq(usdc.balanceOf(bot), botBalanceBefore + profit, "Bot should receive all profit");
        assertEq(usdc.balanceOf(address(liquidator)), 0, "Liquidator should be empty after withdrawal");
    }

    // =========================================================
    //  Helpers
    // =========================================================

    function _setupAlicePosition(uint256 collateral, uint256 debt) internal {
        lendingPool.setPosition(
            alice,
            address(weth),
            collateral,
            address(usdc),
            debt
        );
    }
}

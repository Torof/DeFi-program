// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the FlashLoanArbitrage
//  exercise. Implement FlashLoanArbitrage.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {FlashLoanArbitrage} from "../../../src/part2/module5/FlashLoanArbitrage.sol";
import {NotPool, NotInitiator, NotOwner, InsufficientProfit} from "../../../src/part2/module5/FlashLoanArbitrage.sol";
import {MockERC20} from "../../../src/part2/module5/mocks/MockERC20.sol";
import {MockFlashLoanPool} from "../../../src/part2/module5/mocks/MockFlashLoanPool.sol";
import {MockDEX} from "../../../src/part2/module5/mocks/MockDEX.sol";

contract FlashLoanArbitrageTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockFlashLoanPool pool;
    MockDEX buyDex;     // WETH is cheap here (2000 USDC/WETH)
    MockDEX sellDex;    // WETH is expensive here (2020 USDC/WETH, 1% discrepancy)
    FlashLoanArbitrage arbitrage;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    /// @dev Pool has 10M USDC liquidity for flash loans.
    uint256 constant POOL_LIQUIDITY = 10_000_000e6;

    /// @dev DEX swap fee: 0.3% (30 bps), matching Uniswap V2/V3.
    uint256 constant DEX_FEE_BPS = 30;

    /// @dev Flash loan premium: 0.05% (5 bps), matching Aave V3.
    uint128 constant FLASH_PREMIUM_BPS = 5;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        pool = new MockFlashLoanPool();
        buyDex = new MockDEX(DEX_FEE_BPS);
        sellDex = new MockDEX(DEX_FEE_BPS);

        // Fund the pool with USDC liquidity
        usdc.mint(address(pool), POOL_LIQUIDITY);

        // buyDex: WETH is cheap (2000 USDC per WETH)
        // Price: 1 USDC = 0.0005 WETH → priceE18 = 5e14
        buyDex.setPrice(address(usdc), address(weth), 5e14);

        // sellDex: WETH is expensive (2020 USDC per WETH, 1% above buyDex)
        // Price: 1 WETH = 2020 USDC → priceE18 = 2020e18
        sellDex.setPrice(address(weth), address(usdc), 2020e18);

        // Deploy arbitrage contract as owner
        vm.prank(owner);
        arbitrage = new FlashLoanArbitrage(address(pool));
    }

    // =========================================================
    //  Happy Path
    // =========================================================

    function test_Arbitrage_HappyPath() public {
        // Arb: flash borrow 100K USDC → buy WETH (cheap) → sell WETH (expensive) → repay → profit
        //
        // Step 1: 100,000 USDC → WETH on buyDex (2000 USDC/WETH, 0.3% fee)
        //   raw WETH = 50e18, after fee = 49.85e18
        //
        // Step 2: 49.85 WETH → USDC on sellDex (2020 USDC/WETH, 0.3% fee)
        //   raw USDC = 100,697e6, after fee = 100,394.909e6
        //
        // Repay: 100,000e6 + 50e6 premium = 100,050e6
        // Profit: 100,394.909e6 - 100,050e6 = 344.909e6 ≈ $344.91

        uint256 borrowAmount = 100_000e6;
        uint256 expectedPremium = 50_000_000; // 50 USDC
        uint256 expectedProfit = 344_909_000; // ~344.91 USDC

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        uint256 poolBalanceBefore = usdc.balanceOf(address(pool));

        vm.prank(owner);
        arbitrage.executeArbitrage(
            address(usdc),
            borrowAmount,
            address(buyDex),
            address(sellDex),
            address(weth),
            0 // minProfit = 0 (just verify it works)
        );

        // Profit should be transferred to caller
        assertEq(
            usdc.balanceOf(owner) - ownerBalanceBefore,
            expectedProfit,
            "Owner should receive the arbitrage profit (~344.91 USDC)"
        );

        // Arbitrage contract should have zero balance
        assertEq(
            usdc.balanceOf(address(arbitrage)),
            0,
            "Arbitrage contract should have zero balance after (never store funds)"
        );

        // Pool should have gained the premium
        assertEq(
            usdc.balanceOf(address(pool)) - poolBalanceBefore,
            expectedPremium,
            "Pool should gain exactly the premium (50 USDC)"
        );
    }

    function test_Arbitrage_WithMinProfit() public {
        // Same arb as happy path, but require minProfit = 300 USDC (below actual ~345)
        vm.prank(owner);
        arbitrage.executeArbitrage(
            address(usdc),
            100_000e6,
            address(buyDex),
            address(sellDex),
            address(weth),
            300e6 // actual profit ~345 USDC > 300 USDC → should succeed
        );

        assertGt(
            usdc.balanceOf(owner),
            0,
            "Owner should have received profit"
        );
    }

    // =========================================================
    //  Profitability Checks
    // =========================================================

    function test_Arbitrage_RevertWhen_MinProfitNotMet() public {
        // Actual profit is ~344.91 USDC. Setting minProfit to 500 USDC should revert.
        vm.prank(owner);
        vm.expectRevert(InsufficientProfit.selector);
        arbitrage.executeArbitrage(
            address(usdc),
            100_000e6,
            address(buyDex),
            address(sellDex),
            address(weth),
            500e6 // minProfit = 500 USDC > actual ~345 USDC
        );
    }

    function test_Arbitrage_RevertWhen_Unprofitable() public {
        // Set up DEXs with tiny spread (0.15%) that doesn't cover 2x 0.3% swap fees
        MockDEX tinyBuyDex = new MockDEX(DEX_FEE_BPS);
        MockDEX tinySellDex = new MockDEX(DEX_FEE_BPS);

        // buyDex: 2000 USDC/WETH (same)
        tinyBuyDex.setPrice(address(usdc), address(weth), 5e14);
        // sellDex: 2003 USDC/WETH (only 0.15% above — fees eat the spread)
        tinySellDex.setPrice(address(weth), address(usdc), 2003e18);

        vm.prank(owner);
        vm.expectRevert(); // Reverts: can't repay flash loan (fees exceed spread)
        arbitrage.executeArbitrage(
            address(usdc),
            100_000e6,
            address(tinyBuyDex),
            address(tinySellDex),
            address(weth),
            0
        );
    }

    // =========================================================
    //  Security: Callback Validation
    // =========================================================

    function test_ExecuteOperation_RevertWhen_CallerNotPool() public {
        vm.prank(alice);
        vm.expectRevert(NotPool.selector);
        arbitrage.executeOperation(
            address(usdc),
            1_000e6,
            50,
            address(arbitrage),
            ""
        );
    }

    function test_ExecuteOperation_RevertWhen_WrongInitiator() public {
        vm.prank(address(pool));
        vm.expectRevert(NotInitiator.selector);
        arbitrage.executeOperation(
            address(usdc),
            1_000e6,
            50,
            alice, // wrong initiator
            ""
        );
    }

    // =========================================================
    //  Access Control
    // =========================================================

    function test_Arbitrage_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(NotOwner.selector);
        arbitrage.executeArbitrage(
            address(usdc),
            100_000e6,
            address(buyDex),
            address(sellDex),
            address(weth),
            0
        );
    }

    // =========================================================
    //  Fuzz
    // =========================================================

    function testFuzz_Arbitrage_ProfitableWithVaryingAmounts(uint256 borrowAmount) public {
        // Bound to reasonable range: 1K USDC to 1M USDC
        borrowAmount = bound(borrowAmount, 1_000e6, 1_000_000e6);

        vm.prank(owner);
        arbitrage.executeArbitrage(
            address(usdc),
            borrowAmount,
            address(buyDex),
            address(sellDex),
            address(weth),
            0
        );

        // With 1% spread and 0.3% fee per swap + 0.05% flash premium,
        // the arb should always be profitable
        assertGt(
            usdc.balanceOf(owner),
            0,
            "Arb should be profitable for any amount with 1% spread"
        );

        // Contract should never hold funds
        assertEq(
            usdc.balanceOf(address(arbitrage)),
            0,
            "Arbitrage contract should have zero balance"
        );
    }
}

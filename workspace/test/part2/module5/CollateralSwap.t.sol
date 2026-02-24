// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the CollateralSwap
//  exercise. Implement CollateralSwap.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {CollateralSwap, SwapParams} from "../../../src/part2/module5/CollateralSwap.sol";
import {NotPool, NotInitiator} from "../../../src/part2/module5/CollateralSwap.sol";
import {MockERC20} from "../../../src/part2/module5/mocks/MockERC20.sol";
import {MockFlashLoanPool} from "../../../src/part2/module5/mocks/MockFlashLoanPool.sol";
import {MockLendingPool} from "../../../src/part2/module5/mocks/MockLendingPool.sol";
import {MockDEX} from "../../../src/part2/module5/mocks/MockDEX.sol";

contract CollateralSwapTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockERC20 wbtc;
    MockERC20 aWeth;
    MockERC20 aWbtc;

    MockFlashLoanPool flashPool;
    MockLendingPool lendingPool;
    MockDEX dex;
    CollateralSwap collateralSwap;

    address alice = makeAddr("alice");

    /// @dev Flash pool has 100K USDC liquidity for flash loans.
    uint256 constant FLASH_POOL_LIQUIDITY = 100_000e6;

    /// @dev Lending pool has 100K USDC for borrow operations.
    uint256 constant LENDING_POOL_USDC = 100_000e6;

    /// @dev DEX swap fee: 0.3% (30 bps).
    uint256 constant DEX_FEE_BPS = 30;

    /// @dev Flash loan premium: 0.05% (5 bps).
    uint128 constant FLASH_PREMIUM_BPS = 5;

    /// @dev Alice's starting position.
    uint256 constant ALICE_WETH_COLLATERAL = 10e18;   // 10 WETH
    uint256 constant ALICE_USDC_DEBT = 10_000e6;       // 10,000 USDC

    function setUp() public {
        // --- Deploy tokens ---
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        aWeth = new MockERC20("Aave WETH", "aWETH", 18);
        aWbtc = new MockERC20("Aave WBTC", "aWBTC", 8);

        // --- Deploy infrastructure ---
        flashPool = new MockFlashLoanPool();
        lendingPool = new MockLendingPool();
        dex = new MockDEX(DEX_FEE_BPS);

        // --- Configure lending pool ---
        lendingPool.setAToken(address(weth), address(aWeth));
        lendingPool.setAToken(address(wbtc), address(aWbtc));

        // --- Set up Alice's existing lending position ---
        //   Collateral: 10 WETH deposited (represented by 10 aWETH)
        aWeth.mint(alice, ALICE_WETH_COLLATERAL);
        //   The lending pool holds the underlying WETH
        weth.mint(address(lendingPool), ALICE_WETH_COLLATERAL);
        //   Debt: 10,000 USDC borrowed
        lendingPool.setDebt(alice, address(usdc), ALICE_USDC_DEBT);

        // --- Fund pools ---
        usdc.mint(address(flashPool), FLASH_POOL_LIQUIDITY);
        usdc.mint(address(lendingPool), LENDING_POOL_USDC);

        // --- Configure DEX ---
        // WETH → WBTC: 1 WETH ($2,000) = 0.04 WBTC ($50,000 per BTC)
        // priceE18 = 0.04 × 1e18 = 4e16
        dex.setPrice(address(weth), address(wbtc), 4e16);

        // --- Deploy CollateralSwap ---
        collateralSwap = new CollateralSwap(
            address(flashPool),
            address(lendingPool),
            address(dex)
        );
    }

    // =========================================================
    //  Helper: set up Alice's prerequisites
    // =========================================================

    /// @dev Alice approves the CollateralSwap contract to:
    ///      1. Pull her aTokens (needed for collateral withdrawal)
    ///      2. Borrow USDC on her behalf (credit delegation)
    function _setupAliceDelegations(uint256 delegationAmount) internal {
        vm.startPrank(alice);
        aWeth.approve(address(collateralSwap), type(uint256).max);
        lendingPool.approveDelegation(address(usdc), address(collateralSwap), delegationAmount);
        vm.stopPrank();
    }

    // =========================================================
    //  Happy Path
    // =========================================================

    function test_CollateralSwap_HappyPath() public {
        // Alice swaps her lending position: 10 WETH collateral → WBTC collateral
        //
        // Flow inside the callback:
        //   1. Flash borrow 10,000 USDC
        //   2. Repay 10,000 USDC debt → Alice's debt = 0
        //   3. Pull 10 aWETH from Alice, withdraw → get 10 WETH
        //   4. Swap 10 WETH → WBTC on DEX (0.04 WBTC/WETH, 0.3% fee)
        //      Raw:  10 × 0.04 = 0.4 WBTC = 40,000,000 (8 decimals)
        //      Fee:  40,000,000 × 9970/10000 = 39,880,000
        //   5. Deposit 39,880,000 WBTC → Alice gets 39,880,000 aWBTC
        //   6. Borrow 10,005 USDC on Alice's behalf (amount + 5 USDC premium)
        //   7. Approve flash pool → flash pool pulls repayment
        //
        // Result:
        //   Alice: 0 aWETH, 39,880,000 aWBTC (~0.3988 WBTC), 10,005 USDC debt
        //   CollateralSwap: 0 balance of everything (never store funds)
        //   Flash pool: gained 5 USDC premium

        uint256 expectedWbtcCollateral = 39_880_000; // 0.3988 WBTC (8 decimals)
        uint256 expectedNewDebt = 10_005e6;           // original debt + 5 USDC flash premium
        uint256 expectedPremium = 5e6;                // 5 USDC

        // Alice sets up both delegations
        _setupAliceDelegations(expectedNewDebt);

        uint256 flashPoolBefore = usdc.balanceOf(address(flashPool));

        // Execute the collateral swap
        SwapParams memory params = SwapParams({
            user: alice,
            oldCollateral: address(weth),
            newCollateral: address(wbtc),
            debtAsset: address(usdc),
            debtAmount: ALICE_USDC_DEBT
        });
        collateralSwap.swapCollateral(params);

        // --- Verify Alice's new position ---

        assertEq(
            aWeth.balanceOf(alice),
            0,
            "Alice should have 0 aWETH (old collateral fully withdrawn)"
        );

        assertEq(
            aWbtc.balanceOf(alice),
            expectedWbtcCollateral,
            "Alice should have ~0.3988 aWBTC (39,880,000 in 8 decimals)"
        );

        assertEq(
            lendingPool.debtOf(alice, address(usdc)),
            expectedNewDebt,
            "Alice's debt should be 10,005 USDC (original 10,000 + 5 premium)"
        );

        // --- Verify no funds stuck in contract ---

        assertEq(
            usdc.balanceOf(address(collateralSwap)),
            0,
            "CollateralSwap should have 0 USDC (never store funds)"
        );
        assertEq(
            weth.balanceOf(address(collateralSwap)),
            0,
            "CollateralSwap should have 0 WETH"
        );
        assertEq(
            wbtc.balanceOf(address(collateralSwap)),
            0,
            "CollateralSwap should have 0 WBTC"
        );
        assertEq(
            aWeth.balanceOf(address(collateralSwap)),
            0,
            "CollateralSwap should have 0 aWETH"
        );

        // --- Verify flash pool gained premium ---

        assertEq(
            usdc.balanceOf(address(flashPool)) - flashPoolBefore,
            expectedPremium,
            "Flash pool should gain exactly 5 USDC premium"
        );
    }

    // =========================================================
    //  Security: Callback Validation
    // =========================================================

    function test_ExecuteOperation_RevertWhen_CallerNotPool() public {
        vm.prank(alice);
        vm.expectRevert(NotPool.selector);
        collateralSwap.executeOperation(
            address(usdc),
            10_000e6,
            5e6,
            address(collateralSwap),
            ""
        );
    }

    function test_ExecuteOperation_RevertWhen_WrongInitiator() public {
        vm.prank(address(flashPool));
        vm.expectRevert(NotInitiator.selector);
        collateralSwap.executeOperation(
            address(usdc),
            10_000e6,
            5e6,
            alice, // wrong initiator — should be the contract itself
            ""
        );
    }

    // =========================================================
    //  Prerequisites: Delegation Checks
    // =========================================================

    function test_CollateralSwap_RevertWhen_NoCreditDelegation() public {
        // Alice approves aToken transfer but NOT credit delegation.
        // The swap will execute steps 1-5 successfully, then revert at step 6
        // (borrow) because the lending pool has no delegation allowance.
        vm.prank(alice);
        aWeth.approve(address(collateralSwap), type(uint256).max);

        SwapParams memory params = SwapParams({
            user: alice,
            oldCollateral: address(weth),
            newCollateral: address(wbtc),
            debtAsset: address(usdc),
            debtAmount: ALICE_USDC_DEBT
        });

        vm.expectRevert(); // InsufficientDelegation from lending pool's borrow()
        collateralSwap.swapCollateral(params);
    }

    function test_CollateralSwap_RevertWhen_NoATokenApproval() public {
        // Alice approves credit delegation but NOT aToken transfer.
        // The swap will repay debt (step 1), then revert at step 2
        // when trying to transferFrom aTokens without approval.
        vm.prank(alice);
        lendingPool.approveDelegation(address(usdc), address(collateralSwap), 10_005e6);

        SwapParams memory params = SwapParams({
            user: alice,
            oldCollateral: address(weth),
            newCollateral: address(wbtc),
            debtAsset: address(usdc),
            debtAmount: ALICE_USDC_DEBT
        });

        vm.expectRevert(); // ERC20 transferFrom reverts — no aToken approval
        collateralSwap.swapCollateral(params);
    }
}

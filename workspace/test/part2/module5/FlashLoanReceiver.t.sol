// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the FlashLoanReceiver
//  exercise. Implement FlashLoanReceiver.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {FlashLoanReceiver} from "../../../src/part2/module5/FlashLoanReceiver.sol";
import {NotPool, NotInitiator, NotOwner} from "../../../src/part2/module5/FlashLoanReceiver.sol";
import {MockERC20} from "../../../src/part2/module5/mocks/MockERC20.sol";
import {MockFlashLoanPool} from "../../../src/part2/module5/mocks/MockFlashLoanPool.sol";

contract FlashLoanReceiverTest is Test {
    MockERC20 usdc;
    MockFlashLoanPool pool;
    FlashLoanReceiver receiver;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    /// @dev Pool has 10M USDC liquidity available for flash loans.
    uint256 constant POOL_LIQUIDITY = 10_000_000e6;

    /// @dev Premium = 5 bps (0.05%), matching Aave V3.
    uint128 constant PREMIUM_BPS = 5;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        pool = new MockFlashLoanPool();

        // Fund the pool with liquidity
        usdc.mint(address(pool), POOL_LIQUIDITY);

        // Deploy receiver as owner
        vm.prank(owner);
        receiver = new FlashLoanReceiver(address(pool));
    }

    // =========================================================
    //  Constructor
    // =========================================================

    function test_Constructor_SetsPoolAndOwner() public view {
        assertEq(
            address(receiver.POOL()),
            address(pool),
            "POOL should be set to the pool address"
        );
        assertEq(receiver.owner(), owner, "Owner should be the deployer");
    }

    // =========================================================
    //  Happy Path
    // =========================================================

    function test_FlashLoan_BasicBorrowAndRepay() public {
        uint256 borrowAmount = 1_000_000e6; // 1M USDC
        uint256 expectedPremium = (borrowAmount * PREMIUM_BPS) / 10_000; // 500 USDC

        // Fund receiver with enough to cover premium
        usdc.mint(address(receiver), expectedPremium);

        uint256 poolBalanceBefore = usdc.balanceOf(address(pool));

        vm.prank(owner);
        receiver.requestFlashLoan(address(usdc), borrowAmount);

        // Pool should have received the premium
        assertEq(
            usdc.balanceOf(address(pool)) - poolBalanceBefore,
            expectedPremium,
            "Pool should gain exactly the premium amount"
        );

        // Receiver should have zero balance (never store funds!)
        assertEq(
            usdc.balanceOf(address(receiver)),
            0,
            "Receiver should have zero balance after flash loan"
        );
    }

    function test_FlashLoan_PremiumTracking() public {
        uint256 borrowAmount = 500_000e6; // 500K USDC
        uint256 expectedPremium = (borrowAmount * PREMIUM_BPS) / 10_000; // 250 USDC

        usdc.mint(address(receiver), expectedPremium);

        vm.prank(owner);
        receiver.requestFlashLoan(address(usdc), borrowAmount);

        assertEq(
            receiver.totalPremiumsPaid(),
            expectedPremium,
            "totalPremiumsPaid should track the premium"
        );
    }

    function test_FlashLoan_MultipleBorrows_CumulativePremium() public {
        uint256 borrow1 = 1_000_000e6;
        uint256 borrow2 = 2_000_000e6;
        uint256 premium1 = (borrow1 * PREMIUM_BPS) / 10_000;
        uint256 premium2 = (borrow2 * PREMIUM_BPS) / 10_000;

        // Fund for both premiums
        usdc.mint(address(receiver), premium1 + premium2);

        vm.startPrank(owner);
        receiver.requestFlashLoan(address(usdc), borrow1);
        receiver.requestFlashLoan(address(usdc), borrow2);
        vm.stopPrank();

        assertEq(
            receiver.totalPremiumsPaid(),
            premium1 + premium2,
            "totalPremiumsPaid should accumulate across multiple loans"
        );

        assertEq(
            usdc.balanceOf(address(receiver)),
            0,
            "Receiver should have zero balance after all loans"
        );
    }

    function test_FlashLoan_LargeAmount() public {
        uint256 borrowAmount = 5_000_000e6; // 5M USDC (half the pool)
        uint256 expectedPremium = (borrowAmount * PREMIUM_BPS) / 10_000;

        usdc.mint(address(receiver), expectedPremium);

        vm.prank(owner);
        receiver.requestFlashLoan(address(usdc), borrowAmount);

        assertEq(
            receiver.totalPremiumsPaid(),
            expectedPremium,
            "Premium should be correct for large borrow"
        );
    }

    // =========================================================
    //  Security: Callback Validation
    // =========================================================

    function test_ExecuteOperation_RevertWhen_CallerNotPool() public {
        // Someone calls executeOperation directly (not the Pool)
        vm.prank(alice);
        vm.expectRevert(NotPool.selector);
        receiver.executeOperation(
            address(usdc),
            1_000e6,
            50, // premium
            address(receiver),
            ""
        );
    }

    function test_ExecuteOperation_RevertWhen_WrongInitiator() public {
        // Pool calls executeOperation but with wrong initiator.
        // This simulates: someone else initiated a flash loan targeting this receiver.
        vm.prank(address(pool));
        vm.expectRevert(NotInitiator.selector);
        receiver.executeOperation(
            address(usdc),
            1_000e6,
            50,
            alice, // wrong initiator — alice, not the receiver itself
            ""
        );
    }

    // =========================================================
    //  Access Control
    // =========================================================

    function test_RequestFlashLoan_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(NotOwner.selector);
        receiver.requestFlashLoan(address(usdc), 1_000e6);
    }

    // =========================================================
    //  Rescue Function
    // =========================================================

    function test_RescueTokens_SweepsBalance() public {
        uint256 stuckAmount = 1_000e6;
        usdc.mint(address(receiver), stuckAmount);

        vm.prank(owner);
        receiver.rescueTokens(address(usdc), owner);

        assertEq(
            usdc.balanceOf(address(receiver)),
            0,
            "Receiver should have zero balance after rescue"
        );
        assertEq(
            usdc.balanceOf(owner),
            stuckAmount,
            "Owner should receive the rescued tokens"
        );
    }

    function test_RescueTokens_RevertWhen_NotOwner() public {
        usdc.mint(address(receiver), 1_000e6);

        vm.prank(alice);
        vm.expectRevert(NotOwner.selector);
        receiver.rescueTokens(address(usdc), alice);
    }

    // =========================================================
    //  Pool State
    // =========================================================

    function test_Pool_PremiumRate() public view {
        assertEq(
            pool.FLASHLOAN_PREMIUM_TOTAL(),
            PREMIUM_BPS,
            "Pool premium should be 5 bps"
        );
    }

    // =========================================================
    //  Fuzz
    // =========================================================

    function testFuzz_FlashLoan_PremiumCalculation(uint256 borrowAmount) public {
        // Bound to reasonable range: 1 USDC to pool liquidity
        borrowAmount = bound(borrowAmount, 1e6, POOL_LIQUIDITY);
        uint256 expectedPremium = (borrowAmount * PREMIUM_BPS) / 10_000;

        usdc.mint(address(receiver), expectedPremium);

        vm.prank(owner);
        receiver.requestFlashLoan(address(usdc), borrowAmount);

        assertEq(
            receiver.totalPremiumsPaid(),
            expectedPremium,
            "Premium should match expected calculation for any borrow amount"
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimpleAllocator
//  exercise. Implement SimpleAllocator.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module7/mocks/MockERC20.sol";
import {MockStrategy} from "../../../../src/part2/module7/exercise3-simple-allocator/MockStrategy.sol";
import {SimpleAllocator} from "../../../../src/part2/module7/exercise3-simple-allocator/SimpleAllocator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAllocatorTest is Test {
    MockERC20 token;
    MockStrategy strategyA;
    MockStrategy strategyB;
    SimpleAllocator allocator;

    address alice = makeAddr("alice");

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK", 18);

        strategyA = new MockStrategy(IERC20(address(token)));
        strategyB = new MockStrategy(IERC20(address(token)));

        MockStrategy[] memory strats = new MockStrategy[](2);
        strats[0] = strategyA;
        strats[1] = strategyB;

        allocator = new SimpleAllocator(
            IERC20(address(token)), "Allocator Vault", "avMTK", strats
        );

        // Fund Alice
        token.mint(alice, 10_000e18);
        vm.startPrank(alice);
        token.approve(address(allocator), type(uint256).max);
        vm.stopPrank();
    }

    // =========================================================
    //  Deposit — First depositor gets 1:1 ratio, all idle
    // =========================================================

    function test_Deposit_FirstDeposit() public {
        vm.prank(alice);
        uint256 shares = allocator.deposit(10_000e18, alice);

        // --- 1:1 on first deposit ---
        assertEq(shares, 10_000e18, "First deposit should mint shares 1:1");
        assertEq(allocator.balanceOf(alice), 10_000e18, "Alice should hold 10,000 shares");

        // --- All funds sit idle (not yet allocated) ---
        assertEq(allocator.totalAssets(), 10_000e18, "totalAssets should be 10,000");
        assertEq(allocator.idle(), 10_000e18, "All funds should be idle");
        assertEq(strategyA.totalValue(), 0, "Strategy A should be empty");
        assertEq(strategyB.totalValue(), 0, "Strategy B should be empty");
    }

    // =========================================================
    //  Allocate — Moves idle funds to strategies, tracks debt
    // =========================================================

    function test_Allocate_MovesToStrategy() public {
        _depositAlice();

        // --- Allocate 5,000 to A, 3,000 to B ---
        allocator.allocate(address(strategyA), 5_000e18);
        allocator.allocate(address(strategyB), 3_000e18);

        // Idle decreased
        assertEq(allocator.idle(), 2_000e18, "Idle should be 2,000 after allocation");

        // Strategies received funds
        assertEq(strategyA.totalValue(), 5_000e18, "Strategy A should hold 5,000");
        assertEq(strategyB.totalValue(), 3_000e18, "Strategy B should hold 3,000");

        // Debt tracks allocation
        assertEq(allocator.debt(address(strategyA)), 5_000e18, "Debt to A should be 5,000");
        assertEq(allocator.debt(address(strategyB)), 3_000e18, "Debt to B should be 3,000");

        // totalAssets unchanged — funds moved, not created
        assertEq(allocator.totalAssets(), 10_000e18, "totalAssets should be unchanged at 10,000");
    }

    // =========================================================
    //  Allocate — Reverts if exceeding idle balance
    // =========================================================

    function test_Allocate_RevertsExceedingIdle() public {
        _depositAlice();

        // Allocate 8,000 → idle = 2,000
        allocator.allocate(address(strategyA), 8_000e18);

        // Try to allocate 3,000 when only 2,000 idle → should revert
        vm.expectRevert();
        allocator.allocate(address(strategyB), 3_000e18);
    }

    // =========================================================
    //  Deallocate — Returns funds from strategy to idle
    // =========================================================

    function test_Deallocate_ReturnsToIdle() public {
        _depositAlice();
        allocator.allocate(address(strategyA), 5_000e18);

        // State: idle = 5,000, A = 5,000, debt[A] = 5,000

        // --- Deallocate 2,000 from A ---
        allocator.deallocate(address(strategyA), 2_000e18);

        assertEq(allocator.idle(), 7_000e18, "Idle should increase to 7,000");
        assertEq(strategyA.totalValue(), 3_000e18, "Strategy A should hold 3,000");
        assertEq(allocator.debt(address(strategyA)), 3_000e18, "Debt to A should decrease to 3,000");
        assertEq(allocator.totalAssets(), 10_000e18, "totalAssets should be unchanged at 10,000");
    }

    // =========================================================
    //  Redeem — Withdrawal queue: idle first, then strategies
    // =========================================================

    function test_Redeem_WithdrawalQueue() public {
        _depositAlice();

        // Allocate: 5,000 to A, 3,000 to B, 2,000 idle
        allocator.allocate(address(strategyA), 5_000e18);
        allocator.allocate(address(strategyB), 3_000e18);

        // Simulate yield: A earns 500, B earns 300
        token.mint(address(strategyA), 500e18);
        token.mint(address(strategyB), 300e18);

        // State: idle=2,000 | A=5,500 | B=3,300 | totalAssets=10,800
        assertEq(allocator.totalAssets(), 10_800e18, "totalAssets should reflect yield (10,800)");

        // Rate = 10,800/10,000 = 1.08
        // Redeem 8,000 shares → assets = 8,000 × 10,800 / 10,000 = 8,640
        vm.prank(alice);
        uint256 assets = allocator.redeem(8_000e18, alice, alice);

        assertEq(assets, 8_640e18, "Should receive 8,640 assets (8,000 shares at rate 1.08)");

        // Withdrawal queue pulled: idle(2,000) + A(5,500) + B(1,140) = 8,640
        // After: idle=0, A=0, B=2,160
        assertEq(allocator.idle(), 0, "Idle should be fully drained");
        assertEq(strategyA.totalValue(), 0, "Strategy A should be fully drained");
        assertEq(strategyB.totalValue(), 2_160e18, "Strategy B should have 2,160 remaining");

        // Remaining: 2,000 shares, totalAssets = 2,160, rate = 1.08
        assertEq(allocator.balanceOf(alice), 2_000e18, "Alice should have 2,000 shares remaining");
        assertEq(allocator.totalAssets(), 2_160e18, "Remaining totalAssets should be 2,160");

        // Alice received her tokens
        assertEq(token.balanceOf(alice), 8_640e18, "Alice should hold 8,640 tokens");
    }

    // =========================================================
    //  TotalAssets — Reflects yield earned in strategies
    // =========================================================

    function test_TotalAssets_ReflectsYield() public {
        _depositAlice();

        // Allocate: 5,000 to A, 3,000 to B, 2,000 idle
        allocator.allocate(address(strategyA), 5_000e18);
        allocator.allocate(address(strategyB), 3_000e18);

        assertEq(allocator.totalAssets(), 10_000e18, "totalAssets before yield = 10,000");

        // Simulate yield: A earns 500, B earns 300
        token.mint(address(strategyA), 500e18);
        token.mint(address(strategyB), 300e18);

        // totalAssets should reflect yield immediately (live-query)
        assertEq(allocator.totalAssets(), 10_800e18, "totalAssets after yield = 10,800");

        // Shares are now worth more: rate = 10,800 / 10,000 = 1.08
        // Verify: debt still tracks original allocation (not yield)
        assertEq(allocator.debt(address(strategyA)), 5_000e18, "Debt to A unchanged (tracks allocation, not yield)");
        assertEq(allocator.debt(address(strategyB)), 3_000e18, "Debt to B unchanged (tracks allocation, not yield)");

        // Profit = totalValue - debt
        assertEq(
            strategyA.totalValue() - allocator.debt(address(strategyA)),
            500e18,
            "Strategy A profit should be 500"
        );
        assertEq(
            strategyB.totalValue() - allocator.debt(address(strategyB)),
            300e18,
            "Strategy B profit should be 300"
        );
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Alice deposits 10,000 tokens. Called from test contract (not Alice)
    ///      for allocate/deallocate calls to come from the deployer.
    function _depositAlice() internal {
        vm.prank(alice);
        allocator.deposit(10_000e18, alice);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the DynamicFeeHook
//  exercise. Implement DynamicFeeHook.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {IHookCallback} from "../../../src/part2/module2/interfaces/IHookCallback.sol";
import {MockPoolManager} from "../../../src/part2/module2/mocks/MockPoolManager.sol";
import {
    DynamicFeeHook,
    OnlyPoolManager,
    WindowSizeTooSmall
} from "../../../src/part2/module2/DynamicFeeHook.sol";

contract DynamicFeeHookTest is Test {
    DynamicFeeHook hook;
    MockPoolManager manager;

    address pool = makeAddr("pool");

    // Constants from the hook contract
    uint24 constant BASE_FEE = 3000;
    uint24 constant MAX_FEE = 10000;
    uint256 constant VOLATILITY_THRESHOLD = 200;   // 2% deviation
    uint256 constant MAX_VOLATILITY = 1000;        // 10% deviation
    uint256 constant WINDOW_SIZE = 10;

    // Stable price: sqrtPriceX96 for price ~1.0
    uint160 constant STABLE_PRICE = 79228162514264337593543950336;

    function setUp() public {
        // Deploy hook first (need address for manager)
        // Use CREATE2 pattern to predict address, or just deploy then wire
        hook = new DynamicFeeHook(address(0)); // temporary
        manager = new MockPoolManager(address(hook));
        // Re-deploy hook with correct manager address
        hook = new DynamicFeeHook(address(manager));
        manager = new MockPoolManager(address(hook));
    }

    // =========================================================
    //  Helper: Execute a swap through the manager
    // =========================================================

    function _swap(uint160 sqrtPriceX96) internal returns (uint24 fee) {
        return manager.executeSwap(pool, true, 1e18, sqrtPriceX96);
    }

    function _swapN(uint160 sqrtPriceX96, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _swap(sqrtPriceX96);
        }
    }

    // =========================================================
    //  Basic Fee Behavior
    // =========================================================

    function test_FirstSwap_ReturnsBaseFee() public {
        // Very first swap: only 1 price in the buffer, no volatility possible
        uint24 fee = _swap(STABLE_PRICE);

        assertEq(
            fee,
            BASE_FEE,
            "First swap should return BASE_FEE (no price history to compute volatility)"
        );
    }

    function test_StablePrices_BaseFee() public {
        // Fill the window with identical prices → zero volatility → BASE_FEE
        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(STABLE_PRICE);
        }

        // Next swap should still be BASE_FEE
        uint24 fee = _swap(STABLE_PRICE);

        assertEq(
            fee,
            BASE_FEE,
            "Stable prices (zero volatility) should always return BASE_FEE"
        );
    }

    // =========================================================
    //  Volatile Price Behavior
    // =========================================================

    function test_VolatilePrices_IncreasedFee() public {
        // Alternate between high and low prices (5% swings on sqrtPriceX96)
        // Since sqrtPriceX96 = sqrtPrice × 2^96, a ±5% change in sqrtPriceX96
        // corresponds to a ±5% change in sqrtPrice (i.e., ~±10% in price P).
        uint160 highPrice = STABLE_PRICE * 105 / 100; // +5%
        uint160 lowPrice = STABLE_PRICE * 95 / 100;   // -5%

        // Fill window with alternating prices
        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(i % 2 == 0 ? highPrice : lowPrice);
        }

        // Next swap should have elevated fee
        uint24 fee = _swap(STABLE_PRICE);

        assertGt(
            fee,
            BASE_FEE,
            "Volatile prices should produce a fee ABOVE BASE_FEE"
        );
    }

    function test_ExtremeVolatility_MaxFee() public {
        // Wild price swings: ±15% (well above MAX_VOLATILITY threshold)
        uint160 highPrice = STABLE_PRICE * 115 / 100; // +15%
        uint160 lowPrice = STABLE_PRICE * 85 / 100;   // -15%

        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(i % 2 == 0 ? highPrice : lowPrice);
        }

        uint24 fee = _swap(STABLE_PRICE);

        assertEq(
            fee,
            MAX_FEE,
            "Extreme volatility (>MAX_VOLATILITY) should return MAX_FEE"
        );
    }

    // =========================================================
    //  Fee Bounds
    // =========================================================

    function testFuzz_FeeNeverBelowBase(uint160 price) public {
        price = uint160(bound(uint256(price), 1, type(uint160).max));

        // Do a few swaps to build history
        _swapN(STABLE_PRICE, 5);

        uint24 fee = _swap(price);

        assertGe(
            fee,
            BASE_FEE,
            "INVARIANT: fee must never be below BASE_FEE regardless of price"
        );
    }

    function testFuzz_FeeNeverAboveMax(uint160 price) public {
        price = uint160(bound(uint256(price), 1, type(uint160).max));

        // Fill window with alternating extreme prices
        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(i % 2 == 0 ? price : STABLE_PRICE);
        }

        uint24 fee = _swap(price);

        assertLe(
            fee,
            MAX_FEE,
            "INVARIANT: fee must never exceed MAX_FEE regardless of volatility"
        );
    }

    // =========================================================
    //  Window Behavior
    // =========================================================

    function test_WindowRollover_OldPricesDropOut() public {
        // Fill window with volatile prices
        uint160 highPrice = STABLE_PRICE * 110 / 100;
        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(i % 2 == 0 ? highPrice : STABLE_PRICE);
        }

        uint24 volatileFee = _swap(STABLE_PRICE);
        assertGt(volatileFee, BASE_FEE, "Volatile window should have elevated fee");

        // Now push WINDOW_SIZE+1 stable prices → volatile prices should be gone
        for (uint256 i = 0; i < WINDOW_SIZE + 1; i++) {
            _swap(STABLE_PRICE);
        }

        uint24 stableFee = _swap(STABLE_PRICE);
        assertEq(
            stableFee,
            BASE_FEE,
            "After full window of stable prices, volatile history should be gone"
        );
    }

    function test_VolatilityDecays() public {
        // Phase 1: Volatile period
        uint160 highPrice = STABLE_PRICE * 108 / 100;
        uint160 lowPrice = STABLE_PRICE * 92 / 100;
        for (uint256 i = 0; i < WINDOW_SIZE; i++) {
            _swap(i % 2 == 0 ? highPrice : lowPrice);
        }
        uint24 peakFee = _swap(STABLE_PRICE);

        // Phase 2: Stabilize — push 5 stable prices (half the window)
        for (uint256 i = 0; i < 5; i++) {
            _swap(STABLE_PRICE);
        }
        uint24 decayedFee = _swap(STABLE_PRICE);

        // Fee should have decreased as volatile prices leave the window
        assertLt(
            decayedFee,
            peakFee,
            "Fee should decay as volatile prices are pushed out of the window"
        );
    }

    // =========================================================
    //  Access Control
    // =========================================================

    function test_OnlyPoolManager_CanCall() public {
        IHookCallback.SwapParams memory params = IHookCallback.SwapParams({
            pool: pool,
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceX96: STABLE_PRICE
        });

        // Direct call from non-manager should revert
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(OnlyPoolManager.selector);
        hook.beforeSwap(params);
    }

    // =========================================================
    //  Permissions
    // =========================================================

    function test_Permissions_OnlyBeforeSwap() public view {
        IHookCallback.HookPermissions memory perms = hook.getHookPermissions();

        assertTrue(perms.beforeSwap, "beforeSwap must be enabled");
        assertFalse(perms.afterSwap, "afterSwap must be disabled");
        assertFalse(perms.beforeAddLiquidity, "beforeAddLiquidity must be disabled");
        assertFalse(perms.afterAddLiquidity, "afterAddLiquidity must be disabled");
    }

    // =========================================================
    //  Fee Interpolation Accuracy
    // =========================================================

    function test_FeeInterpolation_Midpoint() public {
        // Create volatility exactly at midpoint between THRESHOLD and MAX
        // midpoint volatility = (200 + 1000) / 2 = 600 bps
        // We need prices that produce ~600 bps max deviation from mean
        // With a mean of STABLE_PRICE, 6% deviation = price * 1.06

        uint160 highPrice = STABLE_PRICE * 106 / 100; // +6% from stable
        // Fill with mostly stable, one high to get ~6% max deviation
        for (uint256 i = 0; i < WINDOW_SIZE - 1; i++) {
            _swap(STABLE_PRICE);
        }
        _swap(highPrice);

        uint24 fee = _swap(STABLE_PRICE);

        // At 600 bps volatility (midpoint):
        // fee = 3000 + (10000 - 3000) × (600 - 200) / (1000 - 200)
        //     = 3000 + 7000 × 400 / 800
        //     = 3000 + 3500
        //     = 6500
        // Allow some tolerance since exact volatility depends on mean calculation
        assertGt(fee, BASE_FEE, "Mid-volatility should be above BASE_FEE");
        assertLt(fee, MAX_FEE, "Mid-volatility should be below MAX_FEE");
    }
}

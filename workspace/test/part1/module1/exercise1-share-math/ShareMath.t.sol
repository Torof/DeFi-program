// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    Assets,
    Shares,
    ShareCalculator,
    toShares,
    toAssets,
    ZeroAssets,
    ZeroShares,
    ZeroTotalSupply,
    ZeroTotalAssets
} from "../../../../src/part1/module1/exercise1-share-math/ShareMath.sol";

/// @notice Tests for the vault share calculator exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module1/ShareMath.sol instead.
contract ShareMathTest is Test {
    ShareCalculator calculator;

    function setUp() public {
        calculator = new ShareCalculator();
    }

    // =========================================================
    //  UDVT Operator Tests
    // =========================================================

    function test_AssetsAddition() public {
        Assets a = Assets.wrap(100);
        Assets b = Assets.wrap(200);
        Assets result = a + b;
        assertEq(Assets.unwrap(result), 300, "100 + 200 = 300");
    }

    function test_AssetsSubtraction() public {
        Assets a = Assets.wrap(300);
        Assets b = Assets.wrap(100);
        Assets result = a - b;
        assertEq(Assets.unwrap(result), 200, "300 - 100 = 200");
    }

    function test_SharesAddition() public {
        Shares a = Shares.wrap(500);
        Shares b = Shares.wrap(300);
        Shares result = a + b;
        assertEq(Shares.unwrap(result), 800, "500 + 300 = 800");
    }

    function test_SharesSubtraction() public {
        Shares a = Shares.wrap(500);
        Shares b = Shares.wrap(300);
        Shares result = a - b;
        assertEq(Shares.unwrap(result), 200, "500 - 300 = 200");
    }

    // =========================================================
    //  Conversion Tests
    // =========================================================

    function test_FirstDeposit_OneToOne() public {
        // First deposit: no existing assets or shares → 1:1 ratio
        Shares shares = toShares(
            Assets.wrap(1000),
            Assets.wrap(0),
            Shares.wrap(0)
        );
        assertEq(Shares.unwrap(shares), 1000, "First deposit should be 1:1");
    }

    function test_SubsequentDeposit() public {
        // Deposit 1000 assets when totalAssets=5000, totalSupply=3000
        // Expected: (1000 * 3000) / 5000 = 600 shares
        Shares shares = toShares(
            Assets.wrap(1000),
            Assets.wrap(5000),
            Shares.wrap(3000)
        );
        assertEq(Shares.unwrap(shares), 600, "Should get 600 shares");
    }

    function test_SharesToAssets() public {
        // After the deposit above: totalAssets=6000, totalSupply=3600
        // Convert 600 shares back: (600 * 6000) / 3600 = 1000 assets
        Assets assets = toAssets(
            Shares.wrap(600),
            Assets.wrap(6000),
            Shares.wrap(3600)
        );
        assertEq(Assets.unwrap(assets), 1000, "600 shares should be worth 1000 assets");
    }

    function test_RoundingFavorsVault() public {
        // 1000 assets when totalAssets=3000, totalSupply=1000
        // Exact: (1000 * 1000) / 3000 = 333.333... → rounds down to 333
        Shares shares = toShares(
            Assets.wrap(1000),
            Assets.wrap(3000),
            Shares.wrap(1000)
        );
        assertEq(Shares.unwrap(shares), 333, "Should round down to 333 shares");
    }

    function test_Roundtrip_WithinOneWei() public {
        // Deposit → get shares → redeem shares → should get back <= original
        Assets deposited = Assets.wrap(1000);
        Assets totalAssets = Assets.wrap(5000);
        Shares totalSupply = Shares.wrap(3000);

        // Convert to shares
        Shares shares = toShares(deposited, totalAssets, totalSupply);

        // Update totals after deposit
        Assets newTotalAssets = Assets.wrap(
            Assets.unwrap(totalAssets) + Assets.unwrap(deposited)
        );
        Shares newTotalSupply = Shares.wrap(
            Shares.unwrap(totalSupply) + Shares.unwrap(shares)
        );

        // Convert back to assets
        Assets redeemed = toAssets(shares, newTotalAssets, newTotalSupply);

        // Rounding favors the vault: redeemed <= deposited
        assertLe(
            Assets.unwrap(redeemed),
            Assets.unwrap(deposited),
            "Redeemed should not exceed deposited"
        );
        // But within 1 wei
        assertGe(
            Assets.unwrap(redeemed),
            Assets.unwrap(deposited) - 1,
            "Redeemed should be within 1 wei of deposited"
        );
    }

    // =========================================================
    //  Custom Error Tests
    // =========================================================

    function test_RevertOnZeroAssets() public {
        vm.expectRevert(ZeroAssets.selector);
        calculator.convertToShares(
            Assets.wrap(0),
            Assets.wrap(5000),
            Shares.wrap(3000)
        );
    }

    function test_RevertOnZeroShares() public {
        vm.expectRevert(ZeroShares.selector);
        calculator.convertToAssets(
            Shares.wrap(0),
            Assets.wrap(5000),
            Shares.wrap(3000)
        );
    }

    function test_RevertOnZeroTotalSupply() public {
        vm.expectRevert(ZeroTotalSupply.selector);
        calculator.convertToAssets(
            Shares.wrap(100),
            Assets.wrap(5000),
            Shares.wrap(0)
        );
    }

    function test_RevertOnZeroTotalAssets() public {
        // totalAssets=0 but totalSupply>0: shares exist but all assets were
        // drained (e.g., donation attack, slashing). The naive formula would
        // divide by zero (panic). A production vault must handle this explicitly.
        vm.expectRevert(ZeroTotalAssets.selector);
        calculator.convertToShares(
            Assets.wrap(1000),
            Assets.wrap(0),
            Shares.wrap(1000)
        );
    }

    // =========================================================
    //  abi.encodeCall Test
    // =========================================================

    function test_AbiEncodeCall() public {
        // abi.encodeCall provides type-safe encoding — the compiler verifies
        // argument types match the function signature. Compare to
        // abi.encodeWithSelector which does no type checking.
        //
        // Try uncommenting this to see the compile-time safety in action:
        //
        // bytes memory broken = abi.encodeCall(
        //     ShareCalculator.convertToShares,
        //     (Shares.wrap(1000), Assets.wrap(5000), Shares.wrap(3000))
        //     // ^^^^^^^^^^^^^^ Wrong type! First arg should be Assets, not Shares
        //     // Compiler error: cannot convert Shares to Assets
        // );
        //
        // abi.encodeWithSelector would silently accept this — same underlying
        // uint256, wrong semantic meaning. That's the bug class encodeCall prevents.

        bytes memory data = abi.encodeCall(
            ShareCalculator.convertToShares,
            (Assets.wrap(1000), Assets.wrap(5000), Shares.wrap(3000))
        );

        // Execute via low-level call
        (bool success, bytes memory result) = address(calculator).call(data);
        assertTrue(success, "Low-level call should succeed");

        // Decode and verify
        Shares shares = abi.decode(result, (Shares));
        assertEq(Shares.unwrap(shares), 600, "abi.encodeCall should produce correct result");
    }

    // =========================================================
    //  Fuzz Test
    // =========================================================

    function testFuzz_RoundtripNeverProfitable(
        uint256 depositAmount,
        uint256 existingAssets,
        uint256 existingShares
    ) public {
        // Bound to realistic DeFi ranges (18-decimal tokens)
        depositAmount = bound(depositAmount, 1, 1e18);
        existingAssets = bound(existingAssets, 1, 1e18);
        existingShares = bound(existingShares, 1, 1e18);

        Assets deposited = Assets.wrap(depositAmount);
        Assets totalAssets = Assets.wrap(existingAssets);
        Shares totalSupply = Shares.wrap(existingShares);

        // Convert to shares
        Shares shares = toShares(deposited, totalAssets, totalSupply);

        // Skip if extreme rounding produces zero shares
        if (Shares.unwrap(shares) == 0) return;

        // Update totals after deposit
        Assets newTotalAssets = Assets.wrap(existingAssets + depositAmount);
        Shares newTotalSupply = Shares.wrap(existingShares + Shares.unwrap(shares));

        // Convert back to assets
        Assets redeemed = toAssets(shares, newTotalAssets, newTotalSupply);

        // Core invariant: depositor should NEVER profit from a roundtrip
        assertLe(
            Assets.unwrap(redeemed),
            depositAmount,
            "Roundtrip should never be profitable"
        );
    }

    /// @dev Extended fuzz with larger bounds — tests the roundtrip invariant
    /// at production scale where vault TVL and share supply can be substantial.
    function testFuzz_LargeBoundsRoundtrip(
        uint256 depositAmount,
        uint256 existingAssets,
        uint256 existingShares
    ) public {
        depositAmount = bound(depositAmount, 1, type(uint128).max);
        existingAssets = bound(existingAssets, 1, type(uint128).max);
        existingShares = bound(existingShares, 1, type(uint128).max);

        Shares shares = toShares(
            Assets.wrap(depositAmount),
            Assets.wrap(existingAssets),
            Shares.wrap(existingShares)
        );
        if (Shares.unwrap(shares) == 0) return;

        uint256 newAssets = existingAssets + depositAmount;
        uint256 newShares = existingShares + Shares.unwrap(shares);
        // Skip if addition overflows (not the concern of this test)
        if (newAssets < existingAssets || newShares < existingShares) return;

        try calculator.convertToAssets(
            shares,
            Assets.wrap(newAssets),
            Shares.wrap(newShares)
        ) returns (Assets redeemed) {
            assertLe(
                Assets.unwrap(redeemed),
                depositAmount,
                "Roundtrip invariant holds at production scale"
            );
        } catch {
            fail("Reverse calculation overflowed at production scale -- check what ShareMath.sol already imports");
        }
    }

    function test_HighTVLConversions() public {
        // High TVL vault with large balances
        uint256 largeAmount = 1 << 200;

        try calculator.convertToShares(
            Assets.wrap(largeAmount),
            Assets.wrap(largeAmount),
            Shares.wrap(largeAmount)
        ) returns (Shares shares) {
            assertEq(Shares.unwrap(shares), largeAmount, "Equal ratio should return input amount");
        } catch {
            fail("toShares overflowed on large values -- check what ShareMath.sol already imports");
        }

        try calculator.convertToAssets(
            Shares.wrap(largeAmount),
            Assets.wrap(largeAmount),
            Shares.wrap(largeAmount)
        ) returns (Assets assets) {
            assertEq(Assets.unwrap(assets), largeAmount, "Equal ratio should return input amount");
        } catch {
            fail("toAssets overflowed on large values -- check what ShareMath.sol already imports");
        }
    }
}

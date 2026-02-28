// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the MEVFeeHook exercise.
//  Implement MEVFeeHook.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {MEVFeeHook} from "../../../../src/part3/module5/exercise2-mev-fee-hook/MEVFeeHook.sol";

contract MEVFeeHookTest is Test {
    MEVFeeHook public hook;

    // Pool identifiers for testing
    bytes32 constant POOL_ETH_USDC = keccak256("ETH/USDC");
    bytes32 constant POOL_WBTC_ETH = keccak256("WBTC/ETH");

    function setUp() public {
        hook = new MEVFeeHook();
    }

    // =========================================================
    //  beforeSwap — Normal Swaps (TODO 1)
    // =========================================================

    function test_beforeSwap_firstSwap_returnsNormalFee() public {
        // Very first swap on a pool in a block — always normal
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, true);
        assertEq(fee, hook.NORMAL_FEE(), "First swap should get normal fee (3000)");
    }

    function test_beforeSwap_sameDirection_returnsNormalFee() public {
        // Two swaps in the same direction — NOT a sandwich
        hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1 again
        assertEq(fee, hook.NORMAL_FEE(), "Same-direction repeat should get normal fee");
    }

    function test_beforeSwap_differentPools_independent() public {
        // Swap on pool A doesn't affect pool B
        hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1 on ETH/USDC
        uint24 fee = hook.beforeSwap(POOL_WBTC_ETH, false); // 1→0 on WBTC/ETH
        assertEq(fee, hook.NORMAL_FEE(), "Different pools should be tracked independently");
    }

    // =========================================================
    //  beforeSwap — Suspicious Swaps (TODO 1)
    // =========================================================

    function test_beforeSwap_oppositeDirection_returnsSuspiciousFee() public {
        // Swap 0→1, then 1→0 in same block — sandwich pattern!
        hook.beforeSwap(POOL_ETH_USDC, true);   // 0→1 (front-run)
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, false); // 1→0 (back-run)
        assertEq(fee, hook.SUSPICIOUS_FEE(), "Opposite direction should get suspicious fee (10000)");
    }

    function test_beforeSwap_oppositeDirection_reverseOrder() public {
        // Works in both directions: 1→0 first, then 0→1
        hook.beforeSwap(POOL_ETH_USDC, false);  // 1→0
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1
        assertEq(fee, hook.SUSPICIOUS_FEE(), "Should detect regardless of which direction comes first");
    }

    function test_beforeSwap_thirdSwap_alsoSuspicious() public {
        // Once both directions recorded, ALL subsequent swaps are suspicious
        hook.beforeSwap(POOL_ETH_USDC, true);   // 0→1 — normal
        hook.beforeSwap(POOL_ETH_USDC, false);  // 1→0 — suspicious
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1 again
        assertEq(fee, hook.SUSPICIOUS_FEE(), "After both directions seen, any swap is suspicious");
    }

    // =========================================================
    //  beforeSwap — Block Boundaries (TODO 1)
    // =========================================================

    function test_beforeSwap_newBlock_resetsTracking() public {
        // Swap in block N
        hook.beforeSwap(POOL_ETH_USDC, true);  // 0→1

        // Advance to next block
        vm.roll(block.number + 1);

        // Opposite direction in new block — fresh start, NOT suspicious
        uint24 fee = hook.beforeSwap(POOL_ETH_USDC, false); // 1→0
        assertEq(fee, hook.NORMAL_FEE(), "New block should reset - no sandwich across blocks");
    }

    function test_beforeSwap_multipleBlocks_independentTracking() public {
        // Block N: 0→1
        hook.beforeSwap(POOL_ETH_USDC, true);

        // Block N+1: 0→1 (same direction, different block)
        vm.roll(block.number + 1);
        uint24 fee1 = hook.beforeSwap(POOL_ETH_USDC, true);
        assertEq(fee1, hook.NORMAL_FEE(), "Same direction in new block = normal");

        // Block N+1: 1→0 (opposite in same block N+1)
        uint24 fee2 = hook.beforeSwap(POOL_ETH_USDC, false);
        assertEq(fee2, hook.SUSPICIOUS_FEE(), "Opposite direction in same block = suspicious");
    }

    // =========================================================
    //  beforeSwap — Events (TODO 1)
    // =========================================================

    function test_beforeSwap_emitsEvent_normalSwap() public {
        vm.expectEmit(true, false, false, true, address(hook));
        emit MEVFeeHook.SwapFeeApplied(POOL_ETH_USDC, true, hook.NORMAL_FEE(), false);
        hook.beforeSwap(POOL_ETH_USDC, true);
    }

    function test_beforeSwap_emitsEvent_suspiciousSwap() public {
        hook.beforeSwap(POOL_ETH_USDC, true); // setup

        vm.expectEmit(true, false, false, true, address(hook));
        emit MEVFeeHook.SwapFeeApplied(POOL_ETH_USDC, false, hook.SUSPICIOUS_FEE(), true);
        hook.beforeSwap(POOL_ETH_USDC, false);
    }

    // =========================================================
    //  isSandwichLikely (TODO 2)
    // =========================================================

    function test_isSandwichLikely_noSwaps_false() public view {
        assertFalse(hook.isSandwichLikely(POOL_ETH_USDC), "No swaps = no sandwich");
    }

    function test_isSandwichLikely_oneDirection_false() public {
        hook.beforeSwap(POOL_ETH_USDC, true);
        assertFalse(hook.isSandwichLikely(POOL_ETH_USDC), "One direction only = not a sandwich");
    }

    function test_isSandwichLikely_bothDirections_true() public {
        hook.beforeSwap(POOL_ETH_USDC, true);
        hook.beforeSwap(POOL_ETH_USDC, false);
        assertTrue(hook.isSandwichLikely(POOL_ETH_USDC), "Both directions = sandwich likely");
    }

    function test_isSandwichLikely_newBlock_resets() public {
        hook.beforeSwap(POOL_ETH_USDC, true);
        hook.beforeSwap(POOL_ETH_USDC, false);
        assertTrue(hook.isSandwichLikely(POOL_ETH_USDC), "Should be true in current block");

        vm.roll(block.number + 1);
        assertFalse(hook.isSandwichLikely(POOL_ETH_USDC), "New block should reset detection");
    }

    function test_isSandwichLikely_differentPools_independent() public {
        hook.beforeSwap(POOL_ETH_USDC, true);
        hook.beforeSwap(POOL_ETH_USDC, false);

        // ETH/USDC has sandwich pattern, WBTC/ETH does not
        assertTrue(hook.isSandwichLikely(POOL_ETH_USDC), "ETH/USDC should show sandwich");
        assertFalse(hook.isSandwichLikely(POOL_WBTC_ETH), "WBTC/ETH should not");
    }

    // =========================================================
    //  getBlockActivity (pre-built view helper)
    // =========================================================

    function test_getBlockActivity_tracksCorrectly() public {
        (bool has01, bool has10) = hook.getBlockActivity(POOL_ETH_USDC, block.number);
        assertFalse(has01, "Should start empty");
        assertFalse(has10, "Should start empty");

        hook.beforeSwap(POOL_ETH_USDC, true);
        (has01, has10) = hook.getBlockActivity(POOL_ETH_USDC, block.number);
        assertTrue(has01, "Should record 0-to-1");
        assertFalse(has10, "Should not record 1-to-0 yet");

        hook.beforeSwap(POOL_ETH_USDC, false);
        (has01, has10) = hook.getBlockActivity(POOL_ETH_USDC, block.number);
        assertTrue(has01, "0-to-1 still recorded");
        assertTrue(has10, "1-to-0 now recorded");
    }

    // =========================================================
    //  Fee Impact Demonstration
    // =========================================================

    function test_feeImpact_sandwichBecomesUnprofitable() public {
        // Scenario: Attacker has $10,000 MEV opportunity
        // Normal fee: 0.3% on $10,000 = $30 cost
        // Suspicious fee: 1.0% on $10,000 = $100 cost
        //
        // If the sandwich profit was $50 (typical for moderate trades):
        //   Normal fee:     $50 - $30 = $20 profit ← sandwich IS profitable
        //   Suspicious fee: $50 - $100 = -$50 loss ← sandwich NOT profitable
        //
        // The extra $70 in fees goes to LPs — MEV internalized!

        uint256 swapAmount = 10_000e18; // $10,000 swap

        // Normal user: one direction, pays 0.3%
        uint24 normalFee = hook.beforeSwap(POOL_ETH_USDC, true);
        uint256 normalFeeCost = swapAmount * normalFee / 1_000_000;

        // Attacker back-run: opposite direction, pays 1.0%
        uint24 suspiciousFee = hook.beforeSwap(POOL_ETH_USDC, false);
        uint256 suspiciousFeeCost = swapAmount * suspiciousFee / 1_000_000;

        // Suspicious fee is 3.33x the normal fee
        assertGt(suspiciousFeeCost, normalFeeCost * 3, "Suspicious fee should be >3x normal fee");
        assertEq(normalFeeCost, 30e18, "Normal fee on $10k = $30");
        assertEq(suspiciousFeeCost, 100e18, "Suspicious fee on $10k = $100");
    }

    // =========================================================
    //  Fuzz Tests — Invariants
    // =========================================================

    function testFuzz_fee_alwaysValidValue(bytes32 poolId, bool zeroForOne) public {
        uint24 fee = hook.beforeSwap(poolId, zeroForOne);
        assertTrue(
            fee == hook.NORMAL_FEE() || fee == hook.SUSPICIOUS_FEE(),
            "INVARIANT: Fee must be either NORMAL_FEE or SUSPICIOUS_FEE"
        );
    }

    function testFuzz_sameDirection_alwaysNormal(bytes32 poolId, uint8 numSwaps) public {
        numSwaps = uint8(bound(numSwaps, 1, 10));

        for (uint256 i = 0; i < numSwaps; i++) {
            uint24 fee = hook.beforeSwap(poolId, true); // always same direction
            assertEq(
                fee,
                hook.NORMAL_FEE(),
                "INVARIANT: Same-direction swaps should always get normal fee"
            );
        }
    }

    function testFuzz_oppositeDirection_alwaysSuspicious(bytes32 poolId) public {
        hook.beforeSwap(poolId, true); // first direction
        uint24 fee = hook.beforeSwap(poolId, false); // opposite
        assertEq(
            fee,
            hook.SUSPICIOUS_FEE(),
            "INVARIANT: Opposite direction in same block always suspicious"
        );
    }
}

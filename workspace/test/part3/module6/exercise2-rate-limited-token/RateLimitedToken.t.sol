// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the RateLimitedToken
//  exercise. Implement RateLimitedToken.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    RateLimitedToken,
    NotOwner,
    NotAuthorizedBridge,
    MintLimitExceeded,
    BurnLimitExceeded
} from "../../../../src/part3/module6/exercise2-rate-limited-token/RateLimitedToken.sol";

contract RateLimitedTokenTest is Test {
    RateLimitedToken public token;

    // Actors
    address owner = makeAddr("owner");
    address bridgeA = makeAddr("bridgeA");
    address bridgeB = makeAddr("bridgeB");
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    // Limits matching lesson example: 1M tokens/day
    uint256 constant MINT_LIMIT = 1_000_000e18;
    uint256 constant BURN_LIMIT = 500_000e18;

    // Derived rate: 1M / 86400 = 11.574... tokens/sec
    uint256 constant RATE_PER_SECOND = MINT_LIMIT / 1 days;

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp

        vm.prank(owner);
        token = new RateLimitedToken("Cross Chain Token", "xTOKEN");
    }

    // --- Helpers ---

    function _setupBridgeA() internal {
        vm.prank(owner);
        token.setLimits(bridgeA, MINT_LIMIT, BURN_LIMIT);
    }

    function _setupBothBridges() internal {
        vm.startPrank(owner);
        token.setLimits(bridgeA, MINT_LIMIT, BURN_LIMIT);
        token.setLimits(bridgeB, 2_000_000e18, 1_000_000e18);
        vm.stopPrank();
    }

    // =========================================================
    //  setLimits (TODO 1)
    // =========================================================

    function test_setLimits_storesCorrectly() public {
        _setupBridgeA();

        (uint256 maxLimit, uint256 currentLimit, uint256 lastRefresh, uint256 rate) =
            token.mintingLimits(bridgeA);

        assertEq(maxLimit, MINT_LIMIT, "maxLimit should match");
        assertEq(currentLimit, MINT_LIMIT, "currentLimit should start full");
        assertEq(lastRefresh, block.timestamp, "lastRefreshTime should be now");
        assertEq(rate, RATE_PER_SECOND, "ratePerSecond should be maxLimit / 1 day");
    }

    function test_setLimits_storesBurnLimits() public {
        _setupBridgeA();

        (uint256 maxLimit, uint256 currentLimit,,) = token.burningLimits(bridgeA);
        assertEq(maxLimit, BURN_LIMIT, "Burn maxLimit should match");
        assertEq(currentLimit, BURN_LIMIT, "Burn currentLimit should start full");
    }

    function test_setLimits_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(token));
        emit RateLimitedToken.BridgeLimitsSet(bridgeA, MINT_LIMIT, BURN_LIMIT);
        token.setLimits(bridgeA, MINT_LIMIT, BURN_LIMIT);
    }

    function test_setLimits_revertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(NotOwner.selector);
        token.setLimits(bridgeA, MINT_LIMIT, BURN_LIMIT);
    }

    function test_setLimits_multipleBridges() public {
        _setupBothBridges();

        (uint256 maxA,,,) = token.mintingLimits(bridgeA);
        (uint256 maxB,,,) = token.mintingLimits(bridgeB);
        assertEq(maxA, MINT_LIMIT, "Bridge A limit");
        assertEq(maxB, 2_000_000e18, "Bridge B limit");
    }

    // =========================================================
    //  mint (TODO 2)
    // =========================================================

    function test_mint_mintsTokens() public {
        _setupBridgeA();
        uint256 amount = 100_000e18;

        vm.prank(bridgeA);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount, "User should receive tokens");
        assertEq(token.totalSupply(), amount, "Total supply should increase");
    }

    function test_mint_deductsFromLimit() public {
        _setupBridgeA();
        uint256 amount = 100_000e18;

        vm.prank(bridgeA);
        token.mint(user, amount);

        uint256 remaining = token.mintingCurrentLimitOf(bridgeA);
        assertEq(remaining, MINT_LIMIT - amount, "Remaining limit should decrease");
    }

    function test_mint_emitsEvent() public {
        _setupBridgeA();

        vm.prank(bridgeA);
        vm.expectEmit(true, true, false, true, address(token));
        emit RateLimitedToken.BridgeMint(bridgeA, user, 50_000e18);
        token.mint(user, 50_000e18);
    }

    function test_mint_revertsForUnauthorizedBridge() public {
        // attacker is not an authorized bridge (no limits set)
        vm.prank(attacker);
        vm.expectRevert(NotAuthorizedBridge.selector);
        token.mint(user, 1e18);
    }

    function test_mint_revertsWhenExceedsLimit() public {
        _setupBridgeA();

        vm.prank(bridgeA);
        vm.expectRevert(
            abi.encodeWithSelector(MintLimitExceeded.selector, MINT_LIMIT + 1, MINT_LIMIT)
        );
        token.mint(user, MINT_LIMIT + 1);
    }

    function test_mint_canMintUpToExactLimit() public {
        _setupBridgeA();

        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        assertEq(token.balanceOf(user), MINT_LIMIT, "Should allow minting up to exact limit");
    }

    function test_mint_revertsAfterLimitExhausted() public {
        _setupBridgeA();

        // Use up the full limit
        vm.startPrank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Next mint should fail (limit = 0)
        vm.expectRevert(
            abi.encodeWithSelector(MintLimitExceeded.selector, 1, 0)
        );
        token.mint(user, 1);
        vm.stopPrank();
    }

    // =========================================================
    //  burn (TODO 3)
    // =========================================================

    function test_burn_burnsTokens() public {
        _setupBridgeA();

        // First mint some tokens
        vm.prank(bridgeA);
        token.mint(user, 100_000e18);

        // Bridge burns (authorized bridges have privileged burn access — no user approval needed)
        vm.prank(bridgeA);
        token.burn(user, 50_000e18);

        assertEq(token.balanceOf(user), 50_000e18, "Balance should decrease");
    }

    function test_burn_deductsFromBurnLimit() public {
        _setupBridgeA();
        uint256 amount = 50_000e18;

        // Mint first
        vm.prank(bridgeA);
        token.mint(user, amount);

        vm.prank(bridgeA);
        token.burn(user, amount);

        uint256 remaining = token.burningCurrentLimitOf(bridgeA);
        assertEq(remaining, BURN_LIMIT - amount, "Burn limit should decrease");
    }

    function test_burn_revertsForUnauthorizedBridge() public {
        vm.prank(attacker);
        vm.expectRevert(NotAuthorizedBridge.selector);
        token.burn(user, 1e18);
    }

    function test_burn_revertsWhenExceedsBurnLimit() public {
        _setupBridgeA();

        // Mint a lot
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        vm.prank(bridgeA);
        vm.expectRevert(
            abi.encodeWithSelector(BurnLimitExceeded.selector, BURN_LIMIT + 1, BURN_LIMIT)
        );
        token.burn(user, BURN_LIMIT + 1);
    }

    // =========================================================
    //  Rate Limiting & Refill (TODOs 4, 5, 6)
    // =========================================================

    function test_refill_limitRefillsOverTime() public {
        _setupBridgeA();

        // Exhaust the full limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Immediately: no capacity
        assertEq(token.mintingCurrentLimitOf(bridgeA), 0, "Should be empty after full use");

        // Advance 1 hour
        vm.warp(block.timestamp + 1 hours);

        // Should have refilled: 1h * ratePerSecond = 3600 * (1M/86400) = 41,666.66...
        uint256 expected = 3600 * RATE_PER_SECOND;
        assertEq(token.mintingCurrentLimitOf(bridgeA), expected, "Should refill proportionally");
    }

    function test_refill_capsAtMaxLimit() public {
        _setupBridgeA();

        // Use half the limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT / 2);

        // Advance 2 full days (more than enough to refill)
        vm.warp(block.timestamp + 2 days);

        // Should cap at maxLimit, not exceed it
        assertEq(
            token.mintingCurrentLimitOf(bridgeA),
            MINT_LIMIT,
            "Refill should cap at maxLimit"
        );
    }

    function test_refill_partialRefillAllowsPartialMint() public {
        _setupBridgeA();

        // Exhaust limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Advance 1 hour — partial refill
        vm.warp(block.timestamp + 1 hours);
        uint256 refilled = 3600 * RATE_PER_SECOND;

        // Should be able to mint up to refilled amount
        vm.prank(bridgeA);
        token.mint(user, refilled);

        // Should NOT be able to mint more
        vm.prank(bridgeA);
        vm.expectRevert(abi.encodeWithSelector(MintLimitExceeded.selector, 1, 0));
        token.mint(user, 1);
    }

    function test_refill_fullDayFullRefill() public {
        _setupBridgeA();

        // Exhaust limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Advance exactly 1 day
        vm.warp(block.timestamp + 1 days);

        // Should be fully refilled (within rounding — integer division of rate loses ~6400 wei)
        uint256 available = token.mintingCurrentLimitOf(bridgeA);
        assertApproxEqRel(available, MINT_LIMIT, 0.0001e18, "Full day should fully refill the bucket");
    }

    function test_refill_burnLimitRefillsIndependently() public {
        _setupBridgeA();

        // Mint enough tokens to cover the burn
        vm.prank(bridgeA);
        token.mint(user, BURN_LIMIT + 200_000e18);

        vm.prank(bridgeA);
        token.burn(user, BURN_LIMIT);

        // Burn limit exhausted
        assertEq(token.burningCurrentLimitOf(bridgeA), 0, "Burn limit should be exhausted");

        // Mint limit partially used (minted BURN_LIMIT + 200k = 700k)
        assertEq(
            token.mintingCurrentLimitOf(bridgeA),
            MINT_LIMIT - (BURN_LIMIT + 200_000e18),
            "Mint limit tracks independently from burn limit"
        );
    }

    // =========================================================
    //  Bridge Independence
    // =========================================================

    function test_bridges_independentLimits() public {
        _setupBothBridges();

        // Bridge A mints its full limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Bridge B should still have its full limit
        assertEq(
            token.mintingCurrentLimitOf(bridgeB),
            2_000_000e18,
            "Bridge B's limit should be unaffected by Bridge A's usage"
        );

        // Bridge B can still mint
        vm.prank(bridgeB);
        token.mint(user, 1_000_000e18);
        assertEq(token.balanceOf(user), MINT_LIMIT + 1_000_000e18, "Both bridges mint independently");
    }

    function test_bridges_compromisedBridgeBounded() public {
        _setupBothBridges();

        // Simulate Bridge A compromise: attacker mints maximum
        vm.prank(bridgeA);
        token.mint(attacker, MINT_LIMIT);

        // Attacker tries to mint more — blocked by rate limit
        vm.prank(bridgeA);
        vm.expectRevert(abi.encodeWithSelector(MintLimitExceeded.selector, 1, 0));
        token.mint(attacker, 1);

        // Damage is bounded at 1M tokens, not unlimited
        assertEq(
            token.balanceOf(attacker),
            MINT_LIMIT,
            "Compromised bridge damage bounded at rate limit"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_mintNeverExceedsLimit(uint256 amount) public {
        _setupBridgeA();
        amount = bound(amount, 1, MINT_LIMIT);

        vm.prank(bridgeA);
        token.mint(user, amount);

        uint256 remaining = token.mintingCurrentLimitOf(bridgeA);
        assertEq(remaining, MINT_LIMIT - amount, "INVARIANT: remaining = max - minted");
    }

    function testFuzz_refillNeverExceedsMax(uint256 elapsed) public {
        _setupBridgeA();
        elapsed = bound(elapsed, 0, 30 days);

        // Exhaust limit
        vm.prank(bridgeA);
        token.mint(user, MINT_LIMIT);

        // Advance time
        vm.warp(block.timestamp + elapsed);

        uint256 available = token.mintingCurrentLimitOf(bridgeA);
        assertLe(available, MINT_LIMIT, "INVARIANT: available never exceeds maxLimit");
    }

    function testFuzz_mintThenRefillThenMint(uint256 firstMint, uint256 elapsed) public {
        _setupBridgeA();
        firstMint = bound(firstMint, 1e18, MINT_LIMIT);
        elapsed = bound(elapsed, 1, 2 days);

        // First mint
        vm.prank(bridgeA);
        token.mint(user, firstMint);

        // Wait
        vm.warp(block.timestamp + elapsed);

        // Available should be: min(maxLimit, (maxLimit - firstMint) + elapsed * rate)
        uint256 available = token.mintingCurrentLimitOf(bridgeA);
        assertLe(available, MINT_LIMIT, "Available should never exceed max");
        assertGe(available, MINT_LIMIT - firstMint, "Available should be at least the unspent portion");
    }
}

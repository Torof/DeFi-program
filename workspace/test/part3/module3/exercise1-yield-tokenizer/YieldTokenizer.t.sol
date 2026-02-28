// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {YieldTokenizer} from
    "../../../../src/part3/module3/exercise1-yield-tokenizer/YieldTokenizer.sol";
import {MockERC4626} from "../../../../src/part3/module3/mocks/MockERC4626.sol";
import {MockERC20} from "../../../../src/part3/module1/mocks/MockERC20.sol";

contract YieldTokenizerTest is Test {
    YieldTokenizer public tokenizer;
    MockERC4626 public vault;
    MockERC20 public underlying;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant WAD = 1e18;
    uint256 constant MATURITY = 1_700_000_000 + 180 days; // ~6 months from start

    function setUp() public {
        vm.warp(1_700_000_000);

        // Deploy underlying token and vault
        underlying = new MockERC20("Underlying", "UND", 18);
        vault = new MockERC4626(address(underlying), "Vault Share", "vUND");

        // Deploy tokenizer with 6-month maturity
        tokenizer = new YieldTokenizer(address(vault), MATURITY);

        // Give alice and bob vault shares
        vault.mint(alice, 1000e18);
        vault.mint(bob, 500e18);

        // Approve tokenizer
        vm.prank(alice);
        vault.approve(address(tokenizer), type(uint256).max);
        vm.prank(bob);
        vault.approve(address(tokenizer), type(uint256).max);
    }

    // =========================================================================
    //  Tokenize (splitting)
    // =========================================================================

    function test_tokenize_basic() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        (uint256 sharesLocked, uint256 principalValue, uint256 ptBal, uint256 ytBal,) =
            tokenizer.positions(alice);

        assertEq(sharesLocked, 100e18, "Should lock 100 shares");
        // At rate 1.0, 100 shares = 100 underlying
        assertEq(principalValue, 100e18, "Principal should be 100 underlying");
        assertEq(ptBal, 100e18, "PT balance should equal principal");
        assertEq(ytBal, 100e18, "YT balance should equal principal");
    }

    function test_tokenize_transfersShares() public {
        uint256 balBefore = vault.balanceOf(alice);

        vm.prank(alice);
        tokenizer.tokenize(100e18);

        assertEq(vault.balanceOf(alice), balBefore - 100e18, "Should transfer shares from user");
        assertEq(vault.balanceOf(address(tokenizer)), 100e18, "Tokenizer should hold shares");
    }

    function test_tokenize_withHigherExchangeRate() public {
        // Vault has already earned yield before tokenization
        vault.setExchangeRate(1.1e18); // 1 share = 1.1 underlying

        vm.prank(alice);
        tokenizer.tokenize(100e18);

        (, uint256 principalValue, uint256 ptBal, uint256 ytBal,) =
            tokenizer.positions(alice);

        // 100 shares * 1.1 = 110 underlying
        assertEq(principalValue, 110e18, "Principal = shares * rate");
        assertEq(ptBal, 110e18, "PT = principal value");
        assertEq(ytBal, 110e18, "YT = principal value");
    }

    function test_tokenize_snapshotsExchangeRate() public {
        vault.setExchangeRate(1.05e18);

        vm.prank(alice);
        tokenizer.tokenize(100e18);

        (,,,, uint256 lastClaimedRate) = tokenizer.positions(alice);
        assertEq(lastClaimedRate, 1.05e18, "Should snapshot current exchange rate");
    }

    function test_tokenize_revertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tokenizer.tokenize(0);
    }

    function test_tokenize_revertDuplicate() public {
        vm.startPrank(alice);
        tokenizer.tokenize(50e18);

        vm.expectRevert(abi.encodeWithSignature("PositionAlreadyExists()"));
        tokenizer.tokenize(50e18);
        vm.stopPrank();
    }

    function test_tokenize_revertAfterMaturity() public {
        vm.warp(MATURITY);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyMatured()"));
        tokenizer.tokenize(100e18);
    }

    // =========================================================================
    //  Accrued Yield
    // =========================================================================

    function test_getAccruedYield_noYieldYet() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // No rate change → no yield
        uint256 yield_ = tokenizer.getAccruedYield(alice);
        assertEq(yield_, 0, "No yield when rate hasn't changed");
    }

    function test_getAccruedYield_afterRateIncrease() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Rate goes from 1.0 to 1.05 (5% yield)
        vault.setExchangeRate(1.05e18);

        uint256 yield_ = tokenizer.getAccruedYield(alice);
        // 100 shares * 1.05 = 105 underlying, principal = 100
        // yield = 105 - 100 = 5
        assertEq(yield_, 5e18, "Should accrue 5 underlying of yield");
    }

    function test_getAccruedYield_proportionalToShares() public {
        vm.prank(alice);
        tokenizer.tokenize(200e18);

        vm.prank(bob);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.1e18); // 10% yield

        uint256 aliceYield = tokenizer.getAccruedYield(alice);
        uint256 bobYield = tokenizer.getAccruedYield(bob);

        // Alice has 2x the shares → 2x the yield
        assertEq(aliceYield, 20e18, "Alice: 200 * 1.1 - 200 = 20");
        assertEq(bobYield, 10e18, "Bob: 100 * 1.1 - 100 = 10");
        assertEq(aliceYield, bobYield * 2, "Yield proportional to shares");
    }

    function test_getAccruedYield_revertNoPosition() public {
        vm.expectRevert(abi.encodeWithSignature("NoPosition()"));
        tokenizer.getAccruedYield(alice);
    }

    function test_getAccruedYield_differentEntryRates() public {
        // Alice enters at rate 1.0
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Rate increases to 1.05
        vault.setExchangeRate(1.05e18);

        // Bob enters at rate 1.05
        vm.prank(bob);
        tokenizer.tokenize(100e18);

        // Rate increases to 1.1
        vault.setExchangeRate(1.1e18);

        uint256 aliceYield = tokenizer.getAccruedYield(alice);
        uint256 bobYield = tokenizer.getAccruedYield(bob);

        // Alice: 100 * 1.1 - 100 = 10 underlying
        assertEq(aliceYield, 10e18, "Alice yield from 1.0 to 1.1");
        // Bob: 100 * 1.1 - 105 = 5 underlying
        assertEq(bobYield, 5e18, "Bob yield from 1.05 to 1.1");
    }

    // =========================================================================
    //  Claim Yield
    // =========================================================================

    function test_claimYield_basic() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.05e18);

        uint256 balBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 claimed = tokenizer.claimYield();

        // Yield = 5 underlying = 5 * WAD / 1.05e18 ≈ 4.761904... shares
        assertEq(claimed, 5e18, "Should claim 5 underlying worth of yield");

        uint256 balAfter = vault.balanceOf(alice);
        uint256 sharesReceived = balAfter - balBefore;

        // 5e18 * 1e18 / 1.05e18 = 4_761904761904761904
        assertApproxEqAbs(
            sharesReceived,
            4_761904761904761904,
            1, // 1 wei tolerance for rounding
            "Should receive ~4.76 shares (5 underlying at rate 1.05)"
        );
    }

    function test_claimYield_reducesSharesLocked() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.05e18);

        vm.prank(alice);
        tokenizer.claimYield();

        (uint256 sharesLocked, uint256 principalValue,,,) =
            tokenizer.positions(alice);

        // Shares reduced by yield payout
        // yieldShares = 5e18 * WAD / 1.05e18 ≈ 4.7619e18
        assertApproxEqAbs(
            sharesLocked,
            100e18 - 4_761904761904761904,
            1,
            "sharesLocked should decrease by yield shares"
        );
        // Principal unchanged
        assertEq(principalValue, 100e18, "Principal must not change after claim");
    }

    function test_claimYield_remainingSharesBackPrincipal() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.05e18);

        vm.prank(alice);
        tokenizer.claimYield();

        (uint256 sharesLocked, uint256 principalValue,,,) =
            tokenizer.positions(alice);

        // Verify: remaining shares * current rate ≈ principal
        uint256 remainingValue = sharesLocked * 1.05e18 / WAD;
        assertApproxEqAbs(
            remainingValue,
            principalValue,
            2, // tiny rounding tolerance
            "Remaining shares should back the principal value"
        );
    }

    function test_claimYield_updatesLastClaimedRate() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.05e18);

        vm.prank(alice);
        tokenizer.claimYield();

        (,,,, uint256 lastClaimedRate) = tokenizer.positions(alice);
        assertEq(lastClaimedRate, 1.05e18, "Should update lastClaimedRate");
    }

    function test_claimYield_secondClaimOnlyNewYield() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // First yield accrual
        vault.setExchangeRate(1.05e18);
        vm.prank(alice);
        uint256 claimed1 = tokenizer.claimYield();

        // Second yield accrual
        vault.setExchangeRate(1.10e18);
        vm.prank(alice);
        uint256 claimed2 = tokenizer.claimYield();

        assertEq(claimed1, 5e18, "First claim: 5 underlying");
        // After first claim, remaining shares ≈ 95.238 at rate 1.1 ≈ 104.76 underlying
        // Principal = 100, so new yield ≈ 4.76 underlying
        // (This is slightly less than 5 because we have fewer shares)
        assertApproxEqAbs(
            claimed2,
            4_761904761904761904, // ~4.76 underlying
            2,
            "Second claim should only include new yield"
        );
    }

    function test_claimYield_noYieldReturnsZero() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // No rate change
        vm.prank(alice);
        uint256 claimed = tokenizer.claimYield();
        assertEq(claimed, 0, "Should return 0 when no yield");
    }

    function test_claimYield_revertNoPosition() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NoPosition()"));
        tokenizer.claimYield();
    }

    // =========================================================================
    //  Redeem at Maturity
    // =========================================================================

    function test_redeemAtMaturity_basic() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Yield accrues
        vault.setExchangeRate(1.1e18);

        // Warp to maturity
        vm.warp(MATURITY);

        uint256 balBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = tokenizer.redeemAtMaturity();

        uint256 balAfter = vault.balanceOf(alice);

        // Should get ALL remaining shares (100 shares, no yield claimed)
        assertEq(shares, 100e18, "Should return all locked shares");
        assertEq(balAfter - balBefore, 100e18, "Should transfer all shares");
    }

    function test_redeemAtMaturity_afterYieldClaim() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vault.setExchangeRate(1.05e18);

        // Claim yield first
        vm.prank(alice);
        tokenizer.claimYield();

        // More yield accrues
        vault.setExchangeRate(1.10e18);

        // Warp to maturity
        vm.warp(MATURITY);

        vm.prank(alice);
        uint256 shares = tokenizer.redeemAtMaturity();

        (uint256 sharesLocked,,,,) = tokenizer.positions(alice);

        // Should get remaining shares (includes unclaimed yield from 1.05→1.10)
        assertGt(shares, 0, "Should return remaining shares");
        assertEq(sharesLocked, 0, "Position should be cleared");
    }

    function test_redeemAtMaturity_deletesPosition() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vm.warp(MATURITY);

        vm.prank(alice);
        tokenizer.redeemAtMaturity();

        (uint256 sharesLocked, uint256 principal, uint256 pt, uint256 yt,) =
            tokenizer.positions(alice);

        assertEq(sharesLocked, 0, "sharesLocked should be 0");
        assertEq(principal, 0, "principalValue should be 0");
        assertEq(pt, 0, "ptBalance should be 0");
        assertEq(yt, 0, "ytBalance should be 0");
    }

    function test_redeemAtMaturity_revertBeforeMaturity() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Still before maturity
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotMatured()"));
        tokenizer.redeemAtMaturity();
    }

    function test_redeemAtMaturity_revertNoPosition() public {
        vm.warp(MATURITY);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NoPosition()"));
        tokenizer.redeemAtMaturity();
    }

    // =========================================================================
    //  Redeem Before Maturity (unsplit)
    // =========================================================================

    function test_redeemBeforeMaturity_basic() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Some yield accrued
        vault.setExchangeRate(1.03e18);

        uint256 balBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = tokenizer.redeemBeforeMaturity();

        uint256 balAfter = vault.balanceOf(alice);

        // Returns ALL shares (principal + yield)
        assertEq(shares, 100e18, "Should return all 100 shares");
        assertEq(balAfter - balBefore, 100e18, "Should transfer all shares");
    }

    function test_redeemBeforeMaturity_deletesPosition() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vm.prank(alice);
        tokenizer.redeemBeforeMaturity();

        (uint256 sharesLocked, uint256 principal, uint256 pt, uint256 yt,) =
            tokenizer.positions(alice);

        assertEq(sharesLocked, 0, "All fields should be zeroed");
        assertEq(principal, 0);
        assertEq(pt, 0);
        assertEq(yt, 0);
    }

    function test_redeemBeforeMaturity_revertAfterMaturity() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        vm.warp(MATURITY);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyMatured()"));
        tokenizer.redeemBeforeMaturity();
    }

    function test_redeemBeforeMaturity_revertNoPosition() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NoPosition()"));
        tokenizer.redeemBeforeMaturity();
    }

    // =========================================================================
    //  Integration: Full lifecycle
    // =========================================================================

    function test_fullLifecycle_tokenizeClaimRedeem() public {
        // 1. Tokenize at rate 1.0
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // 2. Yield accrues (5%)
        vault.setExchangeRate(1.05e18);

        // 3. Claim yield
        vm.prank(alice);
        uint256 claimed = tokenizer.claimYield();
        assertEq(claimed, 5e18, "Should claim 5 underlying");

        // 4. More yield accrues (total 10% from start)
        vault.setExchangeRate(1.10e18);

        // 5. Warp to maturity and redeem
        vm.warp(MATURITY);
        vm.prank(alice);
        uint256 redeemed = tokenizer.redeemAtMaturity();

        // Alice should have received:
        // - ~4.76 shares from yield claim (step 3)
        // - remaining shares from redemption (step 5)
        // Total value should be ≈ 110 underlying (100 principal + 10 yield)
        uint256 totalShares = vault.balanceOf(alice);
        // Started with 1000, deposited 100, got back ~4.76 + remaining
        uint256 totalValue = totalShares * 1.10e18 / WAD;

        // Alice started with 1000 shares worth 1000 underlying
        // After: has more underlying value due to yield
        // Original 900 unstaked shares = 990 underlying at rate 1.1
        // Plus claimed + redeemed ≈ 110 underlying
        // Total ≈ 1100 underlying
        assertApproxEqAbs(
            totalValue,
            1100e18,
            10, // small rounding tolerance
            "Total value should reflect all yield earned"
        );
    }

    function test_fullLifecycle_twoUsersIndependent() public {
        // Alice tokenizes at rate 1.0
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Rate goes to 1.05
        vault.setExchangeRate(1.05e18);

        // Bob tokenizes at rate 1.05
        vm.prank(bob);
        tokenizer.tokenize(100e18);

        // Rate goes to 1.15
        vault.setExchangeRate(1.15e18);

        // Both check yield
        uint256 aliceYield = tokenizer.getAccruedYield(alice);
        uint256 bobYield = tokenizer.getAccruedYield(bob);

        // Alice: 100 * 1.15 - 100 = 15 underlying
        assertEq(aliceYield, 15e18, "Alice yield from 1.0 to 1.15");

        // Bob: 100 * 1.15 - 105 = 10 underlying
        assertEq(bobYield, 10e18, "Bob yield from 1.05 to 1.15");
    }

    function test_unsplitReturnsExactShares() public {
        vm.prank(alice);
        tokenizer.tokenize(100e18);

        // Even after yield accrues, unsplit returns the original share count
        vault.setExchangeRate(1.2e18);

        uint256 balBefore = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 shares = tokenizer.redeemBeforeMaturity();

        assertEq(shares, 100e18, "Unsplit should return exact shares deposited");
        assertEq(
            vault.balanceOf(alice) - balBefore,
            100e18,
            "Balance should increase by exact shares"
        );
    }

    // =========================================================================
    //  Fuzz tests
    // =========================================================================

    function testFuzz_yieldNeverExceedsValueGrowth(
        uint256 shares,
        uint256 rateIncreaseBps
    ) public {
        shares = bound(shares, 1e18, 500e18);
        rateIncreaseBps = bound(rateIncreaseBps, 1, 5000); // 0.01% to 50%

        vm.prank(alice);
        tokenizer.tokenize(shares);

        uint256 newRate = WAD + (WAD * rateIncreaseBps / 10_000);
        vault.setExchangeRate(newRate);

        uint256 yield_ = tokenizer.getAccruedYield(alice);
        uint256 currentValue = shares * newRate / WAD;
        uint256 principalValue = shares; // entry rate was 1.0

        // Yield should equal the value growth above principal
        assertEq(
            yield_,
            currentValue - principalValue,
            "Yield should equal value growth"
        );
    }

    function testFuzz_claimThenRedeemCoversEverything(
        uint256 shares,
        uint256 rateIncreaseBps
    ) public {
        shares = bound(shares, 1e18, 500e18);
        rateIncreaseBps = bound(rateIncreaseBps, 100, 5000); // 1% to 50%

        vm.prank(alice);
        tokenizer.tokenize(shares);

        uint256 newRate = WAD + (WAD * rateIncreaseBps / 10_000);
        vault.setExchangeRate(newRate);

        // Claim yield
        vm.prank(alice);
        tokenizer.claimYield();

        // Redeem at maturity
        vm.warp(MATURITY);
        vm.prank(alice);
        tokenizer.redeemAtMaturity();

        // Tokenizer should have no shares left for this user
        assertEq(
            vault.balanceOf(address(tokenizer)),
            0,
            "Tokenizer should hold 0 shares after full withdrawal"
        );
    }
}

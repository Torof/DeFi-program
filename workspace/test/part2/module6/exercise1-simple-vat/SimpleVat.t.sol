// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimpleVat exercise.
//  Implement SimpleVat.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {SimpleVat} from "../../../../src/part2/module6/exercise1-simple-vat/SimpleVat.sol";
import {VaultUnsafe, CeilingExceeded, GlobalCeilingExceeded, DustViolation} from "../../../../src/part2/module6/exercise1-simple-vat/SimpleVat.sol";
import {SimpleGemJoin} from "../../../../src/part2/module6/shared/SimpleGemJoin.sol";
import {SimpleDaiJoin} from "../../../../src/part2/module6/shared/SimpleDaiJoin.sol";
import {SimpleStablecoin} from "../../../../src/part2/module6/shared/SimpleStablecoin.sol";
import {MockERC20} from "../../../../src/part2/module6/mocks/MockERC20.sol";

contract SimpleVatTest is Test {
    SimpleVat vat;
    MockERC20 weth;
    SimpleStablecoin stablecoin;
    SimpleGemJoin gemJoin;
    SimpleDaiJoin daiJoin;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address vow = makeAddr("vow"); // protocol surplus address

    bytes32 constant ILK_ETH = "ETH-A";

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    // --- Configuration ---
    // ETH price: $2,000, LR: 150% → spot = 2000/1.5 = 1333.33 (RAY)
    uint256 constant SPOT = 1_333_333_333_333_333_333_333_333_333_333; // ~1333.33 RAY
    uint256 constant CEILING = 1_000_000 * RAD;    // 1M DAI per-ilk ceiling
    uint256 constant GLOBAL_CEILING = 5_000_000 * RAD; // 5M DAI global ceiling
    uint256 constant DUST = 100 * RAD;             // 100 DAI minimum debt

    function setUp() public {
        // Deploy core
        vat = new SimpleVat();
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        stablecoin = new SimpleStablecoin("Simple DAI", "sDAI");

        // Deploy join adapters
        gemJoin = new SimpleGemJoin(address(vat), ILK_ETH, address(weth));
        daiJoin = new SimpleDaiJoin(address(vat), address(stablecoin));

        // Authorize join adapters
        vat.rely(address(gemJoin));
        vat.rely(address(daiJoin));

        // Authorize stablecoin minting by DaiJoin
        stablecoin.rely(address(daiJoin));

        // Initialize ETH-A collateral type
        vat.init(ILK_ETH);
        vat.file(ILK_ETH, "spot", SPOT);
        vat.file(ILK_ETH, "line", CEILING);
        vat.file(ILK_ETH, "dust", DUST);
        vat.file("Line", GLOBAL_CEILING);

        // Allow DaiJoin to pull dai from Alice's Vat balance
        vm.prank(alice);
        vat.hope(address(daiJoin));
    }

    // ── Helper: deposit collateral and lock in vault ─────────────────

    /// @dev Mint WETH to `user`, join it into the Vat as gem, then frob to lock + borrow.
    function _openVault(address user, uint256 collateralWad, int256 dink, int256 dart) internal {
        weth.mint(user, collateralWad);

        vm.startPrank(user);
        weth.approve(address(gemJoin), collateralWad);
        gemJoin.join(user, collateralWad);
        vat.frob(ILK_ETH, dink, dart);
        vm.stopPrank();
    }

    // =========================================================
    //  frob — Happy Path
    // =========================================================

    function test_Frob_LockCollateralAndGenerateDai() public {
        // Alice deposits 10 WETH and borrows 10,000 DAI
        // Safety: 10 × 1333.33 = 13,333 ≥ 10,000 × 1.0 = 10,000 ✓
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Check vault state
        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 10 ether, "ink should be 10 WETH");
        assertEq(art, 10_000 * WAD, "art should be 10,000");

        // Check dai balance (10,000 DAI in RAD)
        assertEq(vat.dai(alice), 10_000 * RAD, "Alice should have 10,000 DAI (RAD)");

        // Check global state
        (uint256 Art,,,,) = vat.ilks(ILK_ETH);
        assertEq(Art, 10_000 * WAD, "Total Art should be 10,000");
        assertEq(vat.debt(), 10_000 * RAD, "System debt should be 10,000 DAI (RAD)");

        // Check gem was consumed
        assertEq(vat.gem(ILK_ETH, alice), 0, "Alice's unlocked gem should be 0");
    }

    function test_Frob_RepayAndUnlockCollateral() public {
        // Open vault: 10 WETH, borrow 10,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Repay 5,000 DAI and unlock 3 WETH
        vm.prank(alice);
        vat.frob(ILK_ETH, -int256(3 ether), -int256(5_000 * WAD));

        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 7 ether, "ink should be 7 WETH after unlocking 3");
        assertEq(art, 5_000 * WAD, "art should be 5,000 after repaying 5,000");

        // Check dai was consumed
        assertEq(vat.dai(alice), 5_000 * RAD, "Alice should have 5,000 DAI left (RAD)");

        // Check gem was returned
        assertEq(vat.gem(ILK_ETH, alice), 3 ether, "Alice should have 3 WETH unlocked gem");
    }

    function test_Frob_FullRepayAndExit() public {
        // Open vault: 10 WETH, borrow 5,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(5_000 * WAD));

        // Fully repay and unlock all collateral
        vm.prank(alice);
        vat.frob(ILK_ETH, -int256(10 ether), -int256(5_000 * WAD));

        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 0, "ink should be 0 after full unlock");
        assertEq(art, 0, "art should be 0 after full repay");
        assertEq(vat.dai(alice), 0, "Alice should have 0 DAI");
        assertEq(vat.debt(), 0, "System debt should be 0");
    }

    function test_Frob_LockOnlyNoDebt() public {
        // Lock 5 WETH without borrowing (dart = 0)
        _openVault(alice, 5 ether, int256(5 ether), 0);

        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 5 ether, "ink should be 5 WETH");
        assertEq(art, 0, "art should be 0 (no debt)");
        assertEq(vat.dai(alice), 0, "Alice should have 0 DAI");
    }

    // =========================================================
    //  frob — Full Lifecycle with Join Adapters
    // =========================================================

    function test_Frob_FullLifecycleWithJoins() public {
        // 1. Join 10 WETH collateral
        weth.mint(alice, 10 ether);
        vm.startPrank(alice);
        weth.approve(address(gemJoin), 10 ether);
        gemJoin.join(alice, 10 ether);

        // 2. Lock collateral and generate 5,000 DAI
        vat.frob(ILK_ETH, int256(10 ether), int256(5_000 * WAD));

        // 3. Exit DAI as ERC-20
        daiJoin.exit(alice, 5_000 * WAD);
        assertEq(stablecoin.balanceOf(alice), 5_000 * WAD, "Alice should hold 5,000 sDAI tokens");
        assertEq(vat.dai(alice), 0, "Internal dai should be 0 after exit");

        // 4. Rejoin DAI for repayment
        stablecoin.approve(address(daiJoin), 5_000 * WAD);
        daiJoin.join(alice, 5_000 * WAD);

        // 5. Repay all debt and unlock collateral
        vat.frob(ILK_ETH, -int256(10 ether), -int256(5_000 * WAD));

        // 6. Exit WETH
        gemJoin.exit(alice, 10 ether);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), 10 ether, "Alice should have 10 WETH back");
        assertEq(stablecoin.balanceOf(alice), 0, "Alice should have 0 sDAI");
        assertEq(vat.debt(), 0, "System debt should be 0");
    }

    // =========================================================
    //  frob — Safety Checks
    // =========================================================

    function test_Frob_RevertWhen_VaultUnsafe() public {
        // 10 WETH at spot 1333.33 → max debt ~13,333 DAI
        // Try to borrow 14,000 DAI → should fail
        weth.mint(alice, 10 ether);
        vm.startPrank(alice);
        weth.approve(address(gemJoin), 10 ether);
        gemJoin.join(alice, 10 ether);

        vm.expectRevert(VaultUnsafe.selector);
        vat.frob(ILK_ETH, int256(10 ether), int256(14_000 * WAD));
        vm.stopPrank();
    }

    function test_Frob_RevertWhen_UnlockMakesUnsafe() public {
        // Open a vault at the edge: 10 WETH, 13,000 DAI
        // (10 × 1333.33 = 13,333 ≥ 13,000 ✓)
        _openVault(alice, 10 ether, int256(10 ether), int256(13_000 * WAD));

        // Try to unlock 1 WETH → 9 × 1333.33 = 12,000 < 13,000 → unsafe
        vm.prank(alice);
        vm.expectRevert(VaultUnsafe.selector);
        vat.frob(ILK_ETH, -int256(1 ether), 0);
    }

    function test_Frob_AllowDecreasingRiskWithoutSafetyCheck() public {
        // Open vault: 10 WETH, 10,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Drop spot so the vault is now underwater
        // New spot: $800 / 1.5 = 533 RAY (way below what's needed)
        vat.file(ILK_ETH, "spot", 533 * RAY);

        // Repaying debt (dart < 0) should succeed even though vault is unsafe
        // because we're REDUCING risk, not increasing it
        vm.prank(alice);
        vat.frob(ILK_ETH, int256(0), -int256(2_000 * WAD));

        (, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(art, 8_000 * WAD, "Should allow repayment even when underwater");
    }

    function test_Frob_RevertWhen_CeilingExceeded() public {
        // Set a small per-ilk ceiling: 5,000 DAI
        vat.file(ILK_ETH, "line", 5_000 * RAD);

        // Try to borrow 6,000 DAI → exceeds ceiling
        weth.mint(alice, 10 ether);
        vm.startPrank(alice);
        weth.approve(address(gemJoin), 10 ether);
        gemJoin.join(alice, 10 ether);

        vm.expectRevert(CeilingExceeded.selector);
        vat.frob(ILK_ETH, int256(10 ether), int256(6_000 * WAD));
        vm.stopPrank();
    }

    function test_Frob_RevertWhen_GlobalCeilingExceeded() public {
        // Set global ceiling to 5,000 DAI (lower than per-ilk ceiling)
        vat.file("Line", 5_000 * RAD);

        weth.mint(alice, 10 ether);
        vm.startPrank(alice);
        weth.approve(address(gemJoin), 10 ether);
        gemJoin.join(alice, 10 ether);

        vm.expectRevert(GlobalCeilingExceeded.selector);
        vat.frob(ILK_ETH, int256(10 ether), int256(6_000 * WAD));
        vm.stopPrank();
    }

    function test_Frob_RevertWhen_DustViolation() public {
        // dust = 100 DAI (RAD), try to leave vault with only 50 DAI debt
        weth.mint(alice, 10 ether);
        vm.startPrank(alice);
        weth.approve(address(gemJoin), 10 ether);
        gemJoin.join(alice, 10 ether);

        vm.expectRevert(DustViolation.selector);
        vat.frob(ILK_ETH, int256(10 ether), int256(50 * WAD));
        vm.stopPrank();
    }

    function test_Frob_DustAllowsFullRepay() public {
        // Dust shouldn't prevent fully closing a vault (art = 0)
        _openVault(alice, 10 ether, int256(10 ether), int256(5_000 * WAD));

        vm.prank(alice);
        vat.frob(ILK_ETH, -int256(10 ether), -int256(5_000 * WAD));

        (, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(art, 0, "Should allow full repay despite dust threshold");
    }

    // =========================================================
    //  frob — Multi-user
    // =========================================================

    function test_Frob_MultipleUsers() public {
        // Alice: 10 WETH, 5,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(5_000 * WAD));

        // Bob: 20 WETH, 10,000 DAI
        _openVault(bob, 20 ether, int256(20 ether), int256(10_000 * WAD));

        (uint256 Art,,,,) = vat.ilks(ILK_ETH);
        assertEq(Art, 15_000 * WAD, "Total Art should be 15,000");
        assertEq(vat.debt(), 15_000 * RAD, "System debt should be 15,000 DAI");

        (uint256 inkA, uint256 artA) = vat.urns(ILK_ETH, alice);
        assertEq(inkA, 10 ether, "Alice ink = 10");
        assertEq(artA, 5_000 * WAD, "Alice art = 5,000");

        (uint256 inkB, uint256 artB) = vat.urns(ILK_ETH, bob);
        assertEq(inkB, 20 ether, "Bob ink = 20");
        assertEq(artB, 10_000 * WAD, "Bob art = 10,000");
    }

    // =========================================================
    //  fold — Stability Fee Accumulator
    // =========================================================

    function test_Fold_UpdateRate() public {
        // Open vault: 10 WETH, 10,000 DAI (rate = 1.0 RAY)
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Simulate 5% stability fee: rate goes from 1.0 → 1.05
        // drate = 0.05 RAY = 5e25
        int256 drate = int256(RAY * 5 / 100);
        vat.fold(ILK_ETH, vow, drate);

        // Check rate updated
        (, uint256 rate,,,) = vat.ilks(ILK_ETH);
        assertEq(rate, RAY + uint256(drate), "Rate should be 1.05 RAY");

        // Check new dai generated to vow
        // drad = Art × drate = 10,000 WAD × 0.05 RAY = 500 RAD
        uint256 expectedNewDai = 10_000 * WAD * uint256(drate); // 500 RAD
        assertEq(vat.dai(vow), expectedNewDai, "Vow should receive 500 DAI worth of stability fees");

        // Check system debt increased
        assertEq(vat.debt(), 10_000 * RAD + expectedNewDai, "Debt should increase by stability fee amount");
    }

    function test_Fold_ActualDebtIncreasesWithRate() public {
        // Open vault: 10 WETH, 10,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Apply 5% rate increase
        vat.fold(ILK_ETH, vow, int256(RAY * 5 / 100));

        // Alice's art (normalized debt) is unchanged
        (, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(art, 10_000 * WAD, "Normalized debt unchanged");

        // But actual debt is now art × rate = 10,000 × 1.05 = 10,500 DAI
        (, uint256 rate,,,) = vat.ilks(ILK_ETH);
        uint256 actualDebt = art * rate; // RAD
        assertEq(actualDebt, 10_500 * RAD, "Actual debt should be 10,500 DAI after 5% fee");
    }

    function test_Fold_VaultBecomeUnsafeAfterRateIncrease() public {
        // Open vault right at the edge: 10 WETH, 13,000 DAI
        // ink × spot = 10 × 1333.33 = 13,333 ≥ 13,000 × 1.0 = 13,000 ✓ (safe)
        _openVault(alice, 10 ether, int256(10 ether), int256(13_000 * WAD));

        // Apply 5% rate increase: rate → 1.05
        // Now: ink × spot = 13,333 vs art × rate = 13,000 × 1.05 = 13,650 → UNSAFE
        vat.fold(ILK_ETH, vow, int256(RAY * 5 / 100));

        // Alice can't borrow more (increasing risk on an unsafe vault)
        vm.prank(alice);
        vm.expectRevert(VaultUnsafe.selector);
        vat.frob(ILK_ETH, 0, int256(1 * WAD));
    }

    // =========================================================
    //  grab — Liquidation Seizure
    // =========================================================

    function test_Grab_SeizeCollateralAndDebt() public {
        // Open vault: 10 WETH, 10,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Liquidation seizes all collateral and debt
        // dink = -10 ether, dart = -10,000 WAD
        address liquidator = makeAddr("liquidator");
        vat.grab(
            ILK_ETH,
            alice,          // u: vault owner
            liquidator,     // v: receives seized collateral as gem
            vow,            // w: receives sin (bad debt)
            -int256(10 ether),
            -int256(10_000 * WAD)
        );

        // Vault should be empty
        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 0, "Vault ink should be 0 after grab");
        assertEq(art, 0, "Vault art should be 0 after grab");

        // Liquidator receives collateral as gem
        assertEq(vat.gem(ILK_ETH, liquidator), 10 ether, "Liquidator should have 10 WETH as gem");

        // Vow receives sin (bad debt)
        // sin = art × rate = 10,000 WAD × 1.0 RAY = 10,000 RAD
        assertEq(vat.sin(vow), 10_000 * RAD, "Vow should have 10,000 DAI of sin");
        assertEq(vat.vice(), 10_000 * RAD, "Vice should be 10,000 DAI");

        // Total Art decreased
        (uint256 Art,,,,) = vat.ilks(ILK_ETH);
        assertEq(Art, 0, "Total Art should be 0 after full grab");

        // Alice still has her dai (she already received it via frob)
        assertEq(vat.dai(alice), 10_000 * RAD, "Alice keeps her generated dai");
    }

    function test_Grab_PartialSeizure() public {
        // Open vault: 10 WETH, 10,000 DAI
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        // Seize only half: 5 WETH and 5,000 debt
        address liquidator = makeAddr("liquidator");
        vat.grab(
            ILK_ETH,
            alice,
            liquidator,
            vow,
            -int256(5 ether),
            -int256(5_000 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 5 ether, "Vault should have 5 WETH remaining");
        assertEq(art, 5_000 * WAD, "Vault should have 5,000 art remaining");

        assertEq(vat.gem(ILK_ETH, liquidator), 5 ether, "Liquidator gets 5 WETH");
        assertEq(vat.sin(vow), 5_000 * RAD, "Vow gets 5,000 sin");
    }

    // =========================================================
    //  frob — Fuzz: vault always safe within bounds
    // =========================================================

    /// @dev Fuzz test: any (ink, dart) within safe bounds should produce a safe vault.
    ///      Bounds: ink in [1, 1000] ETH, dart capped so that art × rate ≤ ink × spot.
    ///      This verifies the safety check never falsely reverts for valid inputs.
    function testFuzz_Frob_AlwaysSafeWithinBounds(uint256 ink, uint256 dart) public {
        // Bound collateral to a reasonable range: 1 to 1,000 ETH
        ink = bound(ink, 1 ether, 1_000 ether);

        // Max safe debt (WAD): ink × spot / rate = ink × SPOT / RAY
        // rate starts at RAY (1.0), so maxDebt = ink × SPOT / RAY
        uint256 maxDebtWad = ink * SPOT / RAY;

        // Must also respect dust: if maxDebtWad < dust/RAY then dart = 0
        uint256 dustWad = DUST / RAY; // 100 WAD

        // Bound dart: either 0, or [dustWad, maxDebtWad]
        if (maxDebtWad < dustWad) {
            dart = 0; // Can't borrow above dust, so just lock collateral
        } else {
            dart = bound(dart, dustWad, maxDebtWad);
        }

        // Fund and open vault
        _openVault(alice, ink, int256(ink), int256(dart));

        // Verify vault state
        (uint256 actualInk, uint256 actualArt) = vat.urns(ILK_ETH, alice);
        assertEq(actualInk, ink, "Fuzz: ink should match deposited amount");
        assertEq(actualArt, dart, "Fuzz: art should match borrowed amount");

        // Verify safety invariant: ink × spot >= art × rate
        (, uint256 rate, uint256 spot,,) = vat.ilks(ILK_ETH);
        assertTrue(
            actualInk * spot >= actualArt * rate,
            "Fuzz: vault should always be safe within bounded inputs"
        );
    }

    // =========================================================
    //  grab — Liquidation Seizure
    // =========================================================

    function test_Grab_ThenHealClearsBadDebt() public {
        // Open vault, grab, then simulate auction recovery + heal
        _openVault(alice, 10 ether, int256(10 ether), int256(10_000 * WAD));

        vat.grab(ILK_ETH, alice, vow, vow, -int256(10 ether), -int256(10_000 * WAD));

        // Simulate: auction recovered 10,000 DAI → vow now has both dai and sin
        // In reality, the auction would give dai to vow. We simulate by moving Alice's dai.
        vm.prank(alice);
        vat.move(alice, vow, 10_000 * RAD);

        // Heal: cancel equal amounts of dai and sin
        vm.prank(vow);
        vat.heal(10_000 * RAD);

        assertEq(vat.dai(vow), 0, "Vow dai should be 0 after heal");
        assertEq(vat.sin(vow), 0, "Vow sin should be 0 after heal");
        assertEq(vat.vice(), 0, "Vice should be 0 after heal");
        assertEq(vat.debt(), 0, "Total debt should be 0 after heal");
    }
}

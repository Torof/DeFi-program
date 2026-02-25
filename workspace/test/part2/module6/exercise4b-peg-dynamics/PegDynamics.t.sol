// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Peg Stability Dynamics
//
// These exercises explore how stablecoin peg mechanisms work under stress.
// Using your SimplePSM and SimpleJug, you'll simulate:
//
//   1. PSM peg restoration — how the PSM absorbs selling pressure and
//      restores 1:1 peg through arbitrage
//   2. PSM reserve depletion — what happens when USDC reserves run out
//   3. Stability fee as monetary policy — how raising/lowering the fee
//      affects vault behavior and stablecoin supply
//
// This is a TEST-ONLY exercise. You implement the test scenarios to build
// intuition about decentralized monetary policy.
//
// Why this matters:
//   - Understanding peg mechanics is critical for stablecoin protocol design
//   - March 2023: USDC depegged to $0.87 — DAI followed briefly because
//     MakerDAO's PSM held billions in USDC reserves
//   - The stability fee is the main "interest rate lever" for CDP protocols
//
// Prerequisites: SimplePSM and SimpleJug must be implemented.
//
// Run: forge test --match-contract PegDynamicsTest -vvv
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module6/mocks/MockERC20.sol";
import {SimpleStablecoin} from "../../../../src/part2/module6/shared/SimpleStablecoin.sol";
import {SimplePSM} from "../../../../src/part2/module6/exercise4-simple-psm/SimplePSM.sol";
import {SimpleVat} from "../../../../src/part2/module6/exercise1-simple-vat/SimpleVat.sol";
import {SimpleJug} from "../../../../src/part2/module6/exercise2-simple-jug/SimpleJug.sol";
import {SimpleGemJoin} from "../../../../src/part2/module6/shared/SimpleGemJoin.sol";
import {SimpleDaiJoin} from "../../../../src/part2/module6/shared/SimpleDaiJoin.sol";

contract PegDynamicsTest is Test {
    // --- Core contracts ---
    SimpleVat vat;
    SimpleJug jug;
    SimplePSM psm;
    SimpleStablecoin dai;
    SimpleGemJoin gemJoin;
    SimpleDaiJoin daiJoin;

    // --- Tokens ---
    MockERC20 usdc;
    MockERC20 weth;

    // --- Actors ---
    address alice = makeAddr("alice");   // vault owner
    address bob = makeAddr("bob");       // arbitrageur
    address charlie = makeAddr("charlie"); // stablecoin seller
    address vow = makeAddr("vow");       // protocol surplus

    // --- Constants ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    bytes32 constant ILK_ETH = "ETH-A";

    // 1% PSM fee
    uint256 constant TIN = 0.01e18;  // 1% fee for selling gem (USDC → DAI)
    uint256 constant TOUT = 0.01e18; // 1% fee for buying gem  (DAI → USDC)

    function setUp() public {
        // --- Deploy tokens ---
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        dai = new SimpleStablecoin("Simple DAI", "sDAI");

        // --- Deploy core ---
        vat = new SimpleVat();
        jug = new SimpleJug(address(vat), vow);

        // --- Deploy adapters ---
        gemJoin = new SimpleGemJoin(address(vat), ILK_ETH, address(weth));
        daiJoin = new SimpleDaiJoin(address(vat), address(dai));

        // --- Deploy PSM ---
        psm = new SimplePSM(address(usdc), address(dai), vow, 6);

        // --- Authorization chain ---
        vat.rely(address(gemJoin));
        vat.rely(address(daiJoin));
        vat.rely(address(jug));
        dai.rely(address(daiJoin));
        dai.rely(address(psm));

        // --- Configure collateral in Vat ---
        vat.init(ILK_ETH);
        vat.file(ILK_ETH, "spot", 2000 * RAY); // $2,000 per ETH
        vat.file(ILK_ETH, "line", 1_000_000 * RAD); // 1M debt ceiling
        vat.file("Line", 10_000_000 * RAD); // 10M global ceiling

        // --- Configure stability fees in Jug ---
        jug.init(ILK_ETH);
        // 5% annual ≈ 1.0000000015854895991... per second
        // For simplicity, start with RAY (0% fee) and adjust in tests
        jug.file(ILK_ETH, "duty", RAY); // 0% initially

        // --- Configure PSM fees ---
        psm.file("tin", TIN);
        psm.file("tout", TOUT);

        // --- Seed USDC into PSM (simulating existing reserves) ---
        usdc.mint(address(psm), 500_000e6); // 500k USDC reserves

        // --- Fund users ---
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(charlie, 100_000e6);
        weth.mint(alice, 100e18);
        dai.mint(bob, 1_000_000e18); // Bob has DAI for arbitrage
    }

    // =========================================================
    //  Test 1: PSM Peg Restoration — USDC → DAI
    // =========================================================
    // When DAI trades above $1, arbitrageurs sell USDC to the PSM
    // for DAI, increasing DAI supply and pushing price back to $1.

    function test_PSM_SellGem_IncreasesDAISupply() public {
        uint256 daiSupplyBefore = dai.totalSupply();

        // Bob arbitrages: sells 10,000 USDC → receives DAI
        vm.startPrank(bob);
        usdc.approve(address(psm), 10_000e6);
        psm.sellGem(bob, 10_000e6);
        vm.stopPrank();

        uint256 daiSupplyAfter = dai.totalSupply();

        // DAI supply should increase (by 10,000 - 1% fee to bob + 1% fee to vow = net 10,000)
        assertGt(daiSupplyAfter, daiSupplyBefore, "DAI supply should increase after sellGem");

        // Bob receives 9,900 DAI (10,000 - 1% fee)
        assertEq(
            dai.balanceOf(bob),
            1_000_000e18 + 9_900e18,
            "Bob should receive 9900 DAI (10000 minus 1% fee)"
        );

        // Total minted = 10,000 DAI (9,900 to bob + 100 to vow)
        assertEq(daiSupplyAfter - daiSupplyBefore, 10_000e18, "Total DAI minted should equal USDC deposited");
    }

    // =========================================================
    //  Test 2: PSM Peg Restoration — DAI → USDC
    // =========================================================
    // When DAI trades below $1, arbitrageurs buy USDC from the PSM
    // with DAI, decreasing DAI supply and pushing price back to $1.

    function test_PSM_BuyGem_DecreasesDAISupply() public {
        uint256 daiSupplyBefore = dai.totalSupply();
        uint256 psmUsdcBefore = usdc.balanceOf(address(psm));

        // Bob arbitrages: buys 10,000 USDC by paying DAI
        vm.startPrank(bob);
        dai.approve(address(psm), type(uint256).max);
        psm.buyGem(bob, 10_000e6);
        vm.stopPrank();

        uint256 daiSupplyAfter = dai.totalSupply();

        // DAI supply should decrease (net burn: 10,000 DAI from bob, 100 minted to vow)
        assertLt(daiSupplyAfter, daiSupplyBefore, "DAI supply should decrease after buyGem");

        // PSM USDC reserves should decrease
        uint256 psmUsdcAfter = usdc.balanceOf(address(psm));
        assertEq(psmUsdcBefore - psmUsdcAfter, 10_000e6, "PSM should release 10,000 USDC");
    }

    // =========================================================
    //  Test 3: PSM Reserve Depletion
    // =========================================================
    // If everyone wants DAI → USDC and reserves run out, the PSM
    // can't absorb more pressure. DAI would trade above $1.

    function test_PSM_ReserveDepletion_RevertsWhenEmpty() public {
        uint256 psmReserves = usdc.balanceOf(address(psm));

        // Bob tries to buy ALL USDC from the PSM
        vm.startPrank(bob);
        dai.approve(address(psm), type(uint256).max);

        // Should succeed for available reserves
        psm.buyGem(bob, uint256(psmReserves / 2));

        // After buying half, reserves are depleted to 250k
        uint256 remainingReserves = usdc.balanceOf(address(psm));
        assertEq(remainingReserves, psmReserves / 2, "Half reserves should remain");

        // Buy the rest
        psm.buyGem(bob, remainingReserves);

        // PSM is now empty
        assertEq(usdc.balanceOf(address(psm)), 0, "PSM should have zero USDC reserves");

        // Any further buyGem should revert (no USDC to send)
        vm.expectRevert();
        psm.buyGem(bob, 1e6);
        vm.stopPrank();
    }

    // =========================================================
    //  Test 4: Stability Fee — Higher Fee Discourages Borrowing
    // =========================================================
    // When stability fee is high, vault debt grows faster.
    // Rational users close vaults sooner → DAI supply decreases.

    function test_StabilityFee_HighFeeIncreasesDebtFaster() public {
        // Alice opens a vault: 10 ETH collateral, 10,000 DAI debt
        _openVault(alice, 10e18, 10_000 * WAD);

        // Set a high stability fee: ~50% annual
        // 50% annual ≈ 1.000000013 per second (approximate)
        uint256 highDuty = 1_000_000_013_000_000_000_000_000_000; // ~50% APR
        jug.file(ILK_ETH, "duty", highDuty);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Drip to update rates
        uint256 newRate = jug.drip(ILK_ETH);

        // Rate should have grown significantly
        assertGt(newRate, RAY, "Rate should grow above 1.0 RAY after 1 year with high fee");

        // The rate increase means Alice's actual debt is now > 10,000 DAI
        // Actual debt = art (normalized) × rate
        // With ~50% fee, debt should be ~15,000 DAI
        (, uint256 rate, , , ) = vat.ilks(ILK_ETH);
        assertGt(rate, 1.3e27, "Rate should be at least 1.3 RAY after 1 year at ~50% APR");
    }

    // =========================================================
    //  Test 5: Stability Fee — Zero Fee Means No Debt Growth
    // =========================================================

    function test_StabilityFee_ZeroFeeNoDebtGrowth() public {
        // Fee is already 0% (duty = RAY) from setUp
        _openVault(alice, 10e18, 10_000 * WAD);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Drip — should be a no-op (duty = RAY → RAY^n = RAY)
        uint256 rate = jug.drip(ILK_ETH);

        // Rate should remain exactly RAY
        assertEq(rate, RAY, "Rate should remain 1.0 RAY with zero stability fee");
    }

    // =========================================================
    //  Test 6: Fee Change Impact — Raise and Lower
    // =========================================================

    function test_StabilityFee_RaiseThenLowerAffectsAccrual() public {
        _openVault(alice, 10e18, 10_000 * WAD);

        // Phase 1: High fee for 6 months
        uint256 highDuty = 1_000_000_013_000_000_000_000_000_000; // ~50% APR
        jug.file(ILK_ETH, "duty", highDuty);
        vm.warp(block.timestamp + 182 days);
        jug.drip(ILK_ETH);

        (, uint256 rateAfterHigh, , , ) = vat.ilks(ILK_ETH);

        // Phase 2: Lower fee to ~5% for next 6 months
        uint256 lowDuty = 1_000_000_001_500_000_000_000_000_000; // ~5% APR
        jug.file(ILK_ETH, "duty", lowDuty);
        vm.warp(block.timestamp + 183 days);
        jug.drip(ILK_ETH);

        (, uint256 rateAfterLow, , , ) = vat.ilks(ILK_ETH);

        // Rate should have grown more in the first half
        uint256 firstHalfGrowth = rateAfterHigh - RAY;
        uint256 secondHalfGrowth = rateAfterLow - rateAfterHigh;

        assertGt(
            firstHalfGrowth,
            secondHalfGrowth,
            "Higher fee period should accrue more debt than lower fee period"
        );
    }

    // =========================================================
    //  Test 7: PSM + Fee Interaction
    // =========================================================
    // High fees drive vault closures → DAI supply shrinks.
    // If supply shrinks enough, DAI price goes above $1.
    // PSM sellGem (USDC → DAI) then brings it back.
    //
    // This test demonstrates the feedback loop:
    //   high fee → vaults close → supply down → price up → PSM mints → price stabilized

    function test_PegFeedbackLoop_FeeAndPSM() public {
        // Initial state: 10,000 DAI minted via vault
        _openVault(alice, 10e18, 10_000 * WAD);

        // Alice exits DAI to ERC-20 (through daiJoin)
        vm.startPrank(alice);
        vat.hope(address(daiJoin));
        daiJoin.exit(alice, 10_000e18);
        vm.stopPrank();

        uint256 daiSupplyBeforeClose = dai.totalSupply();

        // "Closing a vault" = burn DAI → repay debt
        // Alice repays by sending DAI back through daiJoin + frob
        vm.startPrank(alice);
        dai.approve(address(daiJoin), 10_000e18);
        daiJoin.join(alice, 10_000e18);
        vat.frob(ILK_ETH, 0, -int256(10_000 * WAD)); // repay all debt
        vm.stopPrank();

        uint256 daiSupplyAfterClose = dai.totalSupply();

        // DAI supply decreased
        assertLt(daiSupplyAfterClose, daiSupplyBeforeClose, "Vault closure should reduce DAI supply");

        // Now Bob uses PSM to mint more DAI (simulating arbitrage when price > $1)
        vm.startPrank(bob);
        usdc.approve(address(psm), 10_000e6);
        psm.sellGem(bob, 10_000e6);
        vm.stopPrank();

        uint256 daiSupplyAfterPSM = dai.totalSupply();

        // DAI supply restored via PSM
        assertGt(daiSupplyAfterPSM, daiSupplyAfterClose, "PSM should restore DAI supply");
    }

    // =========================================================
    //  Helpers
    // =========================================================

    /// @dev Opens a vault for a user: deposits collateral and draws debt.
    function _openVault(address user, uint256 ethAmount, uint256 daiAmount) internal {
        // Approve and join collateral
        vm.startPrank(user);
        weth.approve(address(gemJoin), ethAmount);
        gemJoin.join(user, ethAmount);

        // Lock collateral + draw debt
        vat.frob(ILK_ETH, int256(ethAmount), int256(daiAmount));
        vm.stopPrank();
    }
}

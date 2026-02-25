// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the SimpleDog exercise.
//  Implement SimpleDog.sol to make these tests pass.
//
//  NOTE: All tests require a working SimpleVat (Exercise 1) — implement
//        SimpleVat first. bark() calls Vat.grab(), take() calls Vat.move()
//        and Vat.slip().
// ============================================================================

import "forge-std/Test.sol";

import {SimpleVat} from "../../../../src/part2/module6/exercise1-simple-vat/SimpleVat.sol";
import {
    SimpleDog,
    VaultIsSafe,
    AuctionExpired,
    PriceTooHigh,
    AuctionNotFound
} from "../../../../src/part2/module6/exercise3-simple-dog/SimpleDog.sol";

contract SimpleDogTest is Test {
    SimpleVat vat;
    SimpleDog dog;

    address alice = makeAddr("alice");
    address keeper = makeAddr("keeper");
    address vow = makeAddr("vow");

    bytes32 constant ILK_ETH = "ETH-A";

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    // Normal: ETH $2,000, LR 150% → spot = 1333.33 RAY
    uint256 constant SPOT_NORMAL = 1_333_333_333_333_333_333_333_333_333_333;
    // Crash: ETH $1,350, LR 150% → spot = 900 RAY
    uint256 constant SPOT_CRASH = 900 * RAY;

    uint256 constant CEILING = 1_000_000 * RAD;

    /// @dev Liquidation penalty: 8% → chop = 1.08 WAD.
    uint256 constant CHOP = 1_080_000_000_000_000_000;
    /// @dev Starting price buffer: 2× spot.
    uint256 constant BUF = 2 * RAY;
    /// @dev Auction duration: 1 hour.
    uint256 constant TAIL = 3600;

    /// @dev Alice's vault: 10 ETH collateral, 10,000 DAI debt.
    uint256 constant ALICE_INK = 10 ether;
    uint256 constant ALICE_DART = 10_000 * WAD;

    function setUp() public {
        // --- Deploy and configure Vat (uses only pre-built functions) ---
        vat = new SimpleVat();
        vat.init(ILK_ETH);
        vat.file(ILK_ETH, "spot", SPOT_NORMAL);
        vat.file(ILK_ETH, "line", CEILING);
        vat.file(ILK_ETH, "dust", 0);
        vat.file("Line", CEILING);

        // --- Deploy Dog ---
        dog = new SimpleDog(address(vat), vow);
        vat.rely(address(dog));     // Dog needs auth for grab() and slip()
        dog.file(ILK_ETH, "chop", CHOP);
        dog.file(ILK_ETH, "buf", BUF);
        dog.file("tail", TAIL);
    }

    /// @dev Open Alice's vault. Requires working SimpleVat (Exercise 1).
    function _openAliceVault() internal {
        vat.slip(ILK_ETH, alice, int256(ALICE_INK));
        vm.prank(alice);
        vat.frob(ILK_ETH, int256(ALICE_INK), int256(ALICE_DART));
    }

    /// @dev Give keeper internal dai by opening a heavily overcollateralized vault.
    ///      100 ETH / 20,000 DAI → safe even after crash (100 × 900 = 90,000 >> 20,000).
    ///      Also approves Dog to move keeper's dai (required for take()).
    function _setupKeeper() internal {
        vat.slip(ILK_ETH, keeper, int256(100 ether));
        vm.prank(keeper);
        vat.frob(ILK_ETH, int256(100 ether), int256(20_000 * WAD));
        vm.prank(keeper);
        vat.hope(address(dog));
    }

    /// @dev Simulate ETH price crash by lowering spot.
    function _crashPrice() internal {
        vat.file(ILK_ETH, "spot", SPOT_CRASH);
    }

    // =========================================================
    //  bark — Liquidation Trigger
    // =========================================================

    function test_Bark_SeizesUnsafeVault() public {
        _openAliceVault();
        _crashPrice();

        // Alice's vault is now unsafe: 10 × 900 = 9,000 < 10,000 × 1 = 10,000
        uint256 id = dog.bark(ILK_ETH, alice);

        // --- Auction created correctly ---
        assertEq(id, 1, "First auction should have ID 1");

        (
            bytes32 saleIlk,
            uint256 tab,
            uint256 lot,
            address usr,
            uint256 tic,
            uint256 top
        ) = dog.sales(id);

        assertEq(saleIlk, ILK_ETH, "Sale ilk should be ETH-A");
        // tab = 10,000 WAD × 1 RAY × 1.08 WAD / WAD = 10,800 RAD
        assertEq(tab, 10_800 * RAD, "Tab should be 10,800 RAD (debt + 8% penalty)");
        assertEq(lot, ALICE_INK, "Lot should be all of Alice's collateral");
        assertEq(usr, alice, "Usr should be Alice (for refund)");
        assertEq(tic, block.timestamp, "Tic should be current timestamp");
        // top = 900 RAY × 2 RAY / RAY = 1800 RAY
        assertEq(top, 1800 * RAY, "Top should be spot * buf = 1800 RAY");

        // --- Vault emptied ---
        (uint256 ink, uint256 art) = vat.urns(ILK_ETH, alice);
        assertEq(ink, 0, "Alice's vault ink should be 0 after liquidation");
        assertEq(art, 0, "Alice's vault art should be 0 after liquidation");

        // --- Seized collateral in Dog's gem balance ---
        assertEq(
            vat.gem(ILK_ETH, address(dog)),
            ALICE_INK,
            "Dog should hold the seized collateral"
        );

        // --- Sin created at vow ---
        // sin = art × rate = 10,000 WAD × 1 RAY = 10,000 RAD
        assertEq(vat.sin(vow), 10_000 * RAD, "Sin at vow should equal the actual debt");
        assertEq(vat.vice(), 10_000 * RAD, "Vice should increase by the debt amount");
    }

    function test_Bark_RevertsOnSafeVault() public {
        _openAliceVault();
        // At normal spot, Alice's vault is safe:
        // 10 × 1333.33 = 13,333 > 10,000 × 1 = 10,000
        vm.expectRevert(VaultIsSafe.selector);
        dog.bark(ILK_ETH, alice);
    }

    // =========================================================
    //  take — Dutch Auction Purchase
    // =========================================================

    function test_Take_FullLiquidationWithRefund() public {
        _openAliceVault();
        _crashPrice();
        _setupKeeper();
        dog.bark(ILK_ETH, alice);

        // At t=0, price = 1800 RAY (starting price)
        // Keeper wants all 10 ETH → owe = 10 × 1800 = 18,000 RAD
        // 18,000 > tab (10,800) → capped:
        //   owe  = 10,800 RAD
        //   slice = 10,800 RAD / 1800 RAY = 6 WAD (6 ETH)
        //   refund = 4 ETH to Alice

        uint256 keeperDaiBefore = vat.dai(keeper);

        vm.prank(keeper);
        dog.take(1, ALICE_INK, type(uint256).max);

        // --- Keeper paid 10,800 RAD ---
        assertEq(
            vat.dai(keeper),
            keeperDaiBefore - 10_800 * RAD,
            "Keeper should pay 10,800 RAD"
        );

        // --- Keeper received 6 ETH as gem ---
        assertEq(
            vat.gem(ILK_ETH, keeper),
            6 ether,
            "Keeper should receive 6 ETH of collateral"
        );

        // --- Alice receives 4 ETH refund ---
        assertEq(
            vat.gem(ILK_ETH, alice),
            4 ether,
            "Alice should receive 4 ETH refund"
        );

        // --- Vow receives DAI (to offset sin) ---
        assertEq(
            vat.dai(vow),
            10_800 * RAD,
            "Vow should receive 10,800 RAD from liquidation"
        );

        // --- Dog's gem balance is 0 ---
        assertEq(
            vat.gem(ILK_ETH, address(dog)),
            0,
            "Dog should have no remaining collateral"
        );

        // --- Auction deleted ---
        (, uint256 tabAfter,,,,) = dog.sales(1);
        assertEq(tabAfter, 0, "Auction should be deleted after completion");
    }

    function test_Take_PartialPurchase() public {
        _openAliceVault();
        _crashPrice();
        _setupKeeper();
        dog.bark(ILK_ETH, alice);

        // At t=0, price = 1800 RAY
        // Keeper buys 3 ETH: owe = 3 × 1800 = 5,400 RAD < 10,800 → no cap
        vm.prank(keeper);
        dog.take(1, 3 ether, type(uint256).max);

        // --- Auction continues ---
        (, uint256 tab, uint256 lot, address usr,,) = dog.sales(1);
        assertEq(tab, 5_400 * RAD, "Tab should decrease to 5,400 RAD");
        assertEq(lot, 7 ether, "Lot should decrease to 7 ETH");
        assertEq(usr, alice, "Usr should still be Alice");

        // --- Keeper received 3 ETH ---
        assertEq(
            vat.gem(ILK_ETH, keeper),
            3 ether,
            "Keeper should receive 3 ETH"
        );

        // --- Dog still holds remaining 7 ETH ---
        assertEq(
            vat.gem(ILK_ETH, address(dog)),
            7 ether,
            "Dog should hold 7 ETH remaining"
        );
    }

    function test_Take_PriceDecreasesOverTime() public {
        _openAliceVault();
        _crashPrice();
        _setupKeeper();
        dog.bark(ILK_ETH, alice);

        // Warp 1800 seconds (half the auction)
        // price = 1800 × (3600 - 1800) / 3600 = 900 RAY
        vm.warp(block.timestamp + 1800);

        // Buy 5 ETH at price 900: owe = 5 × 900 = 4,500 RAD < 10,800 → no cap
        vm.prank(keeper);
        dog.take(1, 5 ether, type(uint256).max);

        // --- Keeper gets 5 ETH for 4,500 RAD (cheaper than at t=0) ---
        assertEq(
            vat.gem(ILK_ETH, keeper),
            5 ether,
            "Keeper should receive 5 ETH"
        );

        // Keeper started with 20,000 RAD, paid 4,500
        assertEq(
            vat.dai(keeper),
            20_000 * RAD - 4_500 * RAD,
            "Keeper should pay only 4,500 RAD at the lower price"
        );

        // --- Auction continues with updated state ---
        (, uint256 tab, uint256 lot,,,) = dog.sales(1);
        assertEq(tab, 6_300 * RAD, "Remaining tab = 10,800 - 4,500 = 6,300 RAD");
        assertEq(lot, 5 ether, "Remaining lot = 10 - 5 = 5 ETH");
    }

    function test_Take_RevertsOnExpiredAuction() public {
        _openAliceVault();
        _crashPrice();
        _setupKeeper();
        dog.bark(ILK_ETH, alice);

        // Warp past tail → auction expired
        vm.warp(block.timestamp + TAIL);

        vm.expectRevert(AuctionExpired.selector);
        vm.prank(keeper);
        dog.take(1, ALICE_INK, type(uint256).max);
    }

    function test_Take_RevertsIfMaxPriceTooLow() public {
        _openAliceVault();
        _crashPrice();
        _setupKeeper();
        dog.bark(ILK_ETH, alice);

        // At t=0, price = 1800 RAY
        // Set max = 1000 RAY → current price exceeds max → revert
        vm.expectRevert(PriceTooHigh.selector);
        vm.prank(keeper);
        dog.take(1, ALICE_INK, 1000 * RAY);
    }
}

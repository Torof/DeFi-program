// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the OracleManipulation
//  exercise. Implement OracleAttack.sol and SecureLending.sol to make the
//  tests pass.
//
//  Test 1: Verifies spot price inflates after a big swap (no student code).
//  Test 2: Uses OracleAttack — student implements full flash loan exploit.
//  Test 3: Verifies SecureLending blocks overborrow after price manipulation.
//  Test 4: Verifies SecureLending works normally (no manipulation).
// ============================================================================

import "forge-std/Test.sol";

import {MockERC20} from "../../../../src/part2/module8/mocks/MockERC20.sol";
import {MockChainlinkFeed} from "../../../../src/part2/module8/mocks/MockChainlinkFeed.sol";
import {MockPair} from "../../../../src/part2/module8/exercise2-oracle/MockPair.sol";
import {MockFlashLender} from "../../../../src/part2/module8/exercise2-oracle/MockFlashLender.sol";
import {SpotPriceLending} from "../../../../src/part2/module8/exercise2-oracle/SpotPriceLending.sol";
import {SecureLending} from "../../../../src/part2/module8/exercise2-oracle/SecureLending.sol";
import {OracleAttack} from "../../../../src/part2/module8/exercise2-oracle/OracleAttack.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OracleManipulationTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockPair pair;
    MockFlashLender flashLender;
    MockChainlinkFeed priceFeed;
    SpotPriceLending spotLending;
    SecureLending secureLending;

    address attacker = makeAddr("attacker");
    address manipulator = makeAddr("manipulator");

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        // --- Deploy AMM pair: 10,000 A / 10,000 B (spot price = 1.0) ---
        pair = new MockPair(IERC20(address(tokenA)), IERC20(address(tokenB)));
        tokenA.mint(address(this), 10_000e18);
        tokenB.mint(address(this), 10_000e18);
        tokenA.approve(address(pair), 10_000e18);
        tokenB.approve(address(pair), 10_000e18);
        pair.initialize(10_000e18, 10_000e18);

        assertEq(pair.getSpotPrice(), 1e18, "Initial spot price should be 1.0");

        // --- Chainlink feed: 1e8 = $1.00 at 8 decimals ---
        priceFeed = new MockChainlinkFeed(1e8, 8);

        // --- Flash lender funded with 10,000 tokenB ---
        flashLender = new MockFlashLender();
        tokenB.mint(address(flashLender), 10_000e18);

        // --- Lending protocols funded with 5,000 tokenB each ---
        spotLending = new SpotPriceLending(pair, IERC20(address(tokenA)), IERC20(address(tokenB)));
        secureLending = new SecureLending(pair, priceFeed, IERC20(address(tokenA)), IERC20(address(tokenB)));
        tokenB.mint(address(spotLending), 5_000e18);
        tokenB.mint(address(secureLending), 5_000e18);
    }

    // =========================================================
    //  Spot price inflates after a big swap (no student code)
    // =========================================================

    function test_SpotPrice_InflatedAfterSwap() public {
        // Swap 10,000 B → A: reserves shift from 10k/10k to 5k/20k
        tokenB.mint(address(this), 10_000e18);
        tokenB.approve(address(pair), 10_000e18);
        uint256 receivedA = pair.swap(address(tokenB), 10_000e18);

        // Received 5,000 A (constant product: k=100M, new A = 100M/20k = 5k)
        assertEq(receivedA, 5_000e18, "Should receive 5,000 tokenA from swap");

        // Spot price inflated: 20,000 / 5,000 = 4.0
        assertEq(pair.getSpotPrice(), 4e18, "Spot price should be 4.0 after swap");
    }

    // =========================================================
    //  Attack on SpotPriceLending — full flash loan exploit
    // =========================================================

    function test_Attack_SpotPriceLending_Succeeds() public {
        // Deploy attack contract (no pre-funding — flash loan provides capital)
        OracleAttack attackContract = new OracleAttack(
            pair, spotLending, flashLender, IERC20(address(tokenA)), IERC20(address(tokenB))
        );

        // --- Execute attack: flash 10,000 B, deposit 2,000 A as collateral ---
        attackContract.attack(10_000e18, 2_000e18);

        // --- Attacker borrowed 4,000 (inflated: 2,000 A * 4.0 / 200% = 4,000) ---
        assertEq(
            spotLending.borrowed(address(attackContract)),
            4_000e18,
            "Attacker should have borrowed 4,000 (exploiting inflated spot price)"
        );

        // --- Collateral deposited: 2,000 A ---
        assertEq(
            spotLending.collateral(address(attackContract)),
            2_000e18,
            "Attack contract deposited 2,000 tokenA as collateral"
        );

        // --- Profit: 1,500 B remaining after repaying flash loan ---
        // Total B: 4,000 (borrowed) + 7,500 (second swap) = 11,500
        // Repaid: 10,000 flash loan. Kept: 1,500
        assertEq(
            tokenB.balanceOf(address(attackContract)),
            1_500e18,
            "Attack contract should hold 1,500 tokenB profit"
        );

        // --- Flash lender made whole ---
        assertEq(
            tokenB.balanceOf(address(flashLender)),
            10_000e18,
            "Flash lender should have its 10,000 tokenB back"
        );

        // --- Fair max borrow was only 1,000 ---
        uint256 fairMaxBorrow = 2_000e18 * 1e18 / spotLending.COLLATERAL_RATIO();
        assertEq(fairMaxBorrow, 1_000e18, "Fair max borrow should be 1,000");
        assertGt(
            spotLending.borrowed(address(attackContract)),
            fairMaxBorrow,
            "Attacker borrowed more than fair max (attack succeeded)"
        );
    }

    // =========================================================
    //  SecureLending blocks overborrow after price manipulation
    // =========================================================

    function test_SecureLending_BlocksOverborrow() public {
        // Manipulate spot price (done by test, not by student)
        tokenB.mint(manipulator, 10_000e18);
        vm.startPrank(manipulator);
        tokenB.approve(address(pair), 10_000e18);
        pair.swap(address(tokenB), 10_000e18);
        // Spot price now 4e18, Chainlink still 1e8 (= 1.0)

        // Manipulator got 5,000 A from swap — deposit 2,000 as collateral
        tokenA.approve(address(secureLending), 2_000e18);
        secureLending.depositCollateral(2_000e18);

        // Try to borrow at inflated value: 2,000 * 4.0 / 2.0 = 4,000
        uint256 inflatedPrice = pair.getSpotPrice();
        uint256 inflatedValue = 2_000e18 * inflatedPrice / 1e18;
        uint256 inflatedMaxBorrow = inflatedValue * 1e18 / secureLending.COLLATERAL_RATIO();
        assertEq(inflatedMaxBorrow, 4_000e18, "Inflated max borrow should be 4,000");

        // SecureLending reads Chainlink (1e18) not spot (4e18)
        // Real max borrow: 2,000 * 1.0 / 2.0 = 1,000
        // Trying to borrow 4,000 > 1,000 — should revert
        vm.expectRevert();
        secureLending.borrow(inflatedMaxBorrow);
        vm.stopPrank();
    }

    // =========================================================
    //  SecureLending works normally (no manipulation)
    // =========================================================

    function test_SecureLending_NormalBorrow_Works() public {
        // Deposit 2,000 A as collateral (no price manipulation)
        tokenA.mint(attacker, 2_000e18);
        vm.startPrank(attacker);
        tokenA.approve(address(secureLending), 2_000e18);
        secureLending.depositCollateral(2_000e18);

        // Borrow 1,000 at fair price — should succeed
        // Price = 1.0, collateral value = 2,000, max = 2,000 / 2 = 1,000
        uint256 maxBorrow = 2_000e18 * 1e18 / secureLending.COLLATERAL_RATIO();
        secureLending.borrow(maxBorrow);
        vm.stopPrank();

        assertEq(
            secureLending.borrowed(attacker),
            1_000e18,
            "Normal borrow of 1,000 should succeed on SecureLending"
        );

        assertEq(
            tokenB.balanceOf(attacker),
            1_000e18,
            "Attacker should have received 1,000 tokenB"
        );
    }
}

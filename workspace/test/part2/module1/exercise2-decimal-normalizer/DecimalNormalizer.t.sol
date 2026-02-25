// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    DecimalNormalizer,
    TokenNotRegistered,
    ZeroAmount,
    InsufficientNormalizedBalance
} from "../../../../src/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.sol";
import {MockERC20} from "../../../../src/part2/module1/mocks/MockERC20.sol";

/// @notice Tests for the DecimalNormalizer exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part2/module1/DecimalNormalizer.sol instead.
contract DecimalNormalizerTest is Test {
    DecimalNormalizer normalizer;
    MockERC20 usdc;  // 6 decimals
    MockERC20 wbtc;  // 8 decimals
    MockERC20 dai;   // 18 decimals

    address alice;
    address bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        normalizer = new DecimalNormalizer();

        // Create tokens with different decimal places
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Register all tokens
        normalizer.registerToken(address(usdc));
        normalizer.registerToken(address(wbtc));
        normalizer.registerToken(address(dai));

        // Fund alice
        usdc.mint(alice, 10_000e6);     // 10,000 USDC
        wbtc.mint(alice, 1e8);          // 1 WBTC
        dai.mint(alice, 10_000e18);     // 10,000 DAI

        // Fund bob
        usdc.mint(bob, 5_000e6);
        dai.mint(bob, 5_000e18);
    }

    // =========================================================
    //  Registration Tests
    // =========================================================

    function test_RegisterToken() public view {
        assertTrue(normalizer.isRegistered(address(usdc)), "USDC should be registered");
        assertEq(normalizer.tokenDecimals(address(usdc)), 6, "USDC decimals should be 6");

        assertTrue(normalizer.isRegistered(address(wbtc)), "WBTC should be registered");
        assertEq(normalizer.tokenDecimals(address(wbtc)), 8, "WBTC decimals should be 8");

        assertTrue(normalizer.isRegistered(address(dai)), "DAI should be registered");
        assertEq(normalizer.tokenDecimals(address(dai)), 18, "DAI decimals should be 18");
    }

    function test_Revert_DepositUnregisteredToken() public {
        MockERC20 unknown = new MockERC20("Unknown", "UNK", 18);
        unknown.mint(alice, 100e18);

        vm.startPrank(alice);
        unknown.approve(address(normalizer), 100e18);

        vm.expectRevert(abi.encodeWithSelector(TokenNotRegistered.selector, address(unknown)));
        normalizer.deposit(address(unknown), 100e18);
        vm.stopPrank();
    }

    // =========================================================
    //  USDC (6 decimals) Tests
    // =========================================================

    function test_USDC_DepositNormalizes() public {
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6); // 1000 USDC
        vm.stopPrank();

        // 1000 USDC (1000e6) should normalize to 1000e18
        assertEq(
            normalizer.normalizedBalanceOf(alice, address(usdc)),
            1000e18,
            "1000 USDC should normalize to 1000e18"
        );
    }

    function test_USDC_WithdrawDenormalizes() public {
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6);

        // Withdraw 500e18 normalized = 500 USDC = 500e6 raw
        normalizer.withdraw(address(usdc), 500e18);
        vm.stopPrank();

        assertEq(
            normalizer.normalizedBalanceOf(alice, address(usdc)),
            500e18,
            "Should have 500e18 normalized remaining"
        );
        assertEq(
            usdc.balanceOf(alice),
            9_500e6,
            "Alice should have 9500 USDC (started with 10000, deposited 1000, withdrew 500)"
        );
    }

    // =========================================================
    //  WBTC (8 decimals) Tests
    // =========================================================

    function test_WBTC_DepositNormalizes() public {
        vm.startPrank(alice);
        wbtc.approve(address(normalizer), 1e8);
        normalizer.deposit(address(wbtc), 1e8); // 1 WBTC
        vm.stopPrank();

        // 1 WBTC (1e8) should normalize to 1e18
        assertEq(
            normalizer.normalizedBalanceOf(alice, address(wbtc)),
            1e18,
            "1 WBTC should normalize to 1e18"
        );
    }

    function test_WBTC_SmallAmount() public {
        vm.startPrank(alice);
        wbtc.approve(address(normalizer), 1); // 0.00000001 WBTC (1 satoshi)
        normalizer.deposit(address(wbtc), 1);
        vm.stopPrank();

        // 1 raw unit of WBTC = 1e10 normalized
        assertEq(
            normalizer.normalizedBalanceOf(alice, address(wbtc)),
            1e10,
            "1 satoshi WBTC should normalize to 1e10"
        );
    }

    // =========================================================
    //  DAI (18 decimals) Tests
    // =========================================================

    function test_DAI_DepositNoChange() public {
        vm.startPrank(alice);
        dai.approve(address(normalizer), 1000e18);
        normalizer.deposit(address(dai), 1000e18);
        vm.stopPrank();

        // 18-decimal token: no scaling needed
        assertEq(
            normalizer.normalizedBalanceOf(alice, address(dai)),
            1000e18,
            "DAI (18 dec) should not change during normalization"
        );
    }

    // =========================================================
    //  Total Value Tests (Cross-Token)
    // =========================================================

    function test_TotalValueNormalized_SingleToken() public {
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        assertEq(normalizer.totalValueNormalized(), 1000e18, "Total should be 1000e18");
    }

    function test_TotalValueNormalized_MultipleTokens() public {
        vm.startPrank(alice);

        // Deposit 1000 USDC
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6);

        // Deposit 0.5 WBTC
        wbtc.approve(address(normalizer), 0.5e8);
        normalizer.deposit(address(wbtc), 0.5e8);

        // Deposit 2000 DAI
        dai.approve(address(normalizer), 2000e18);
        normalizer.deposit(address(dai), 2000e18);

        vm.stopPrank();

        // Total = 1000e18 + 0.5e18 + 2000e18 = 3000.5e18
        uint256 expected = 1000e18 + 0.5e18 + 2000e18;
        assertEq(
            normalizer.totalValueNormalized(),
            expected,
            "Total normalized value should sum across all tokens"
        );
    }

    function test_TotalValueNormalized_MultipleUsers() public {
        // Alice deposits 1000 USDC
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        // Bob deposits 500 DAI
        vm.startPrank(bob);
        dai.approve(address(normalizer), 500e18);
        normalizer.deposit(address(dai), 500e18);
        vm.stopPrank();

        assertEq(
            normalizer.totalValueNormalized(),
            1500e18,
            "Total should sum across users: 1000 USDC + 500 DAI = 1500e18"
        );
    }

    function test_TotalValueNormalized_DecreasesOnWithdraw() public {
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 1000e6);
        normalizer.deposit(address(usdc), 1000e6);

        normalizer.withdraw(address(usdc), 400e18);
        vm.stopPrank();

        assertEq(
            normalizer.totalValueNormalized(),
            600e18,
            "Total should decrease by withdrawn normalized amount"
        );
    }

    // =========================================================
    //  Error Cases
    // =========================================================

    function test_Revert_ZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        normalizer.deposit(address(usdc), 0);
    }

    function test_Revert_WithdrawExceedsBalance() public {
        vm.startPrank(alice);
        usdc.approve(address(normalizer), 100e6);
        normalizer.deposit(address(usdc), 100e6);

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientNormalizedBalance.selector, 200e18, 100e18)
        );
        normalizer.withdraw(address(usdc), 200e18);
        vm.stopPrank();
    }

    function test_Revert_WithdrawUnregisteredToken() public {
        MockERC20 unknown = new MockERC20("Unknown", "UNK", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenNotRegistered.selector, address(unknown)));
        normalizer.withdraw(address(unknown), 100e18);
    }

    // =========================================================
    //  Roundtrip Tests
    // =========================================================

    function test_USDC_FullRoundtrip() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        usdc.approve(address(normalizer), depositAmount);
        normalizer.deposit(address(usdc), depositAmount);

        // Withdraw the full normalized balance
        uint256 normalizedBal = normalizer.normalizedBalanceOf(alice, address(usdc));
        normalizer.withdraw(address(usdc), normalizedBal);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 10_000e6, "Alice should have all USDC back after roundtrip");
        assertEq(normalizer.normalizedBalanceOf(alice, address(usdc)), 0, "Normalized balance should be zero");
        assertEq(normalizer.totalValueNormalized(), 0, "Total should be zero");
    }

    function test_WBTC_FullRoundtrip() public {
        uint256 depositAmount = 0.5e8;

        vm.startPrank(alice);
        wbtc.approve(address(normalizer), depositAmount);
        normalizer.deposit(address(wbtc), depositAmount);

        uint256 normalizedBal = normalizer.normalizedBalanceOf(alice, address(wbtc));
        normalizer.withdraw(address(wbtc), normalizedBal);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(alice), 1e8, "Alice should have all WBTC back after roundtrip");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_NormalizeDenormalizeRoundtrip_USDC(uint256 amount) public {
        // USDC: 6 decimals. Bound to realistic range.
        amount = bound(amount, 1, 1_000_000_000e6); // 1 wei to 1 billion USDC

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(normalizer), amount);
        normalizer.deposit(address(usdc), amount);

        uint256 normalizedBal = normalizer.normalizedBalanceOf(alice, address(usdc));
        normalizer.withdraw(address(usdc), normalizedBal);
        vm.stopPrank();

        // For 6-decimal tokens, normalize then denormalize should be lossless
        // because we scale up by 10^12 then divide by 10^12 — exact for any integer input
        assertEq(
            usdc.balanceOf(alice),
            10_000e6 + amount, // setUp amount + minted amount
            "USDC roundtrip should be lossless"
        );
    }

    function testFuzz_NormalizeDenormalizeRoundtrip_DAI(uint256 amount) public {
        // DAI: 18 decimals. No scaling happens.
        amount = bound(amount, 1, 1_000_000_000e18);

        dai.mint(alice, amount);

        vm.startPrank(alice);
        dai.approve(address(normalizer), amount);
        normalizer.deposit(address(dai), amount);

        uint256 normalizedBal = normalizer.normalizedBalanceOf(alice, address(dai));
        normalizer.withdraw(address(dai), normalizedBal);
        vm.stopPrank();

        assertEq(
            dai.balanceOf(alice),
            10_000e18 + amount,
            "DAI roundtrip should be lossless (no scaling)"
        );
    }

    function testFuzz_TotalNeverExceedsSumOfDeposits(
        uint256 usdcAmount,
        uint256 daiAmount
    ) public {
        usdcAmount = bound(usdcAmount, 1, 1_000_000e6);
        daiAmount = bound(daiAmount, 1, 1_000_000e18);

        usdc.mint(alice, usdcAmount);
        dai.mint(bob, daiAmount);

        vm.startPrank(alice);
        usdc.approve(address(normalizer), usdcAmount);
        normalizer.deposit(address(usdc), usdcAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        dai.approve(address(normalizer), daiAmount);
        normalizer.deposit(address(dai), daiAmount);
        vm.stopPrank();

        uint256 aliceNormalized = normalizer.normalizedBalanceOf(alice, address(usdc));
        uint256 bobNormalized = normalizer.normalizedBalanceOf(bob, address(dai));

        assertEq(
            normalizer.totalValueNormalized(),
            aliceNormalized + bobNormalized,
            "INVARIANT: total must equal sum of all individual balances"
        );
    }
}

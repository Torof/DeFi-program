// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {VaultV1, VaultV2, ZeroAmount, InsufficientBalance, ExcessiveFee} from "../../../src/part1/module6/UUPSVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Tests for UUPS upgradeable vault.
/// @dev DO NOT MODIFY THIS FILE. Fill in UUPSVault.sol instead.
contract UUPSVaultTest is Test {
    VaultV1 implementation;
    VaultV1 proxy;
    MockToken token;

    address owner;
    address alice;
    address bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy token
        token = new MockToken();

        // Deploy implementation
        implementation = new VaultV1();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            VaultV1.initialize.selector,
            address(token),
            owner
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = VaultV1(address(proxyContract));

        // Fund users
        token.mint(alice, 10000e18);
        token.mint(bob, 10000e18);
    }

    // =========================================================
    //  Initialization Tests
    // =========================================================

    function test_Initialize() public view {
        assertEq(address(proxy.token()), address(token), "Token should be set");
        assertEq(proxy.owner(), owner, "Owner should be set");
        assertEq(proxy.version(), 1, "Version should be 1");
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        proxy.initialize(address(token), alice);
    }

    // =========================================================
    //  V1 Deposit Tests
    // =========================================================

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        token.approve(address(proxy), depositAmount);
        proxy.deposit(depositAmount);
        vm.stopPrank();

        assertEq(proxy.balances(alice), depositAmount, "Alice balance should be updated");
        assertEq(proxy.totalDeposits(), depositAmount, "Total deposits should be updated");
        assertEq(token.balanceOf(address(proxy)), depositAmount, "Proxy should hold tokens");
    }

    function test_MultipleDeposits() public {
        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(proxy), 1000e18);
        proxy.deposit(1000e18);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        token.approve(address(proxy), 2000e18);
        proxy.deposit(2000e18);
        vm.stopPrank();

        assertEq(proxy.balances(alice), 1000e18, "Alice balance");
        assertEq(proxy.balances(bob), 2000e18, "Bob balance");
        assertEq(proxy.totalDeposits(), 3000e18, "Total deposits");
    }

    function test_DepositRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        proxy.deposit(0);
    }

    // =========================================================
    //  V1 Withdraw Tests
    // =========================================================

    function test_Withdraw() public {
        // Setup: Alice deposits
        vm.startPrank(alice);
        token.approve(address(proxy), 1000e18);
        proxy.deposit(1000e18);

        // Withdraw
        uint256 aliceBalBefore = token.balanceOf(alice);
        proxy.withdraw(600e18);
        vm.stopPrank();

        assertEq(proxy.balances(alice), 400e18, "Remaining balance");
        assertEq(proxy.totalDeposits(), 400e18, "Total deposits after withdraw");
        assertEq(token.balanceOf(alice), aliceBalBefore + 600e18, "Alice should receive tokens");
    }

    function test_WithdrawRevertInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientBalance.selector);
        proxy.withdraw(100e18);
    }

    // =========================================================
    //  Upgrade to V2 Tests
    // =========================================================

    function test_UpgradeToV2() public {
        // Deploy V2 implementation
        VaultV2 implementationV2 = new VaultV2();

        // Upgrade (as owner)
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100) // 1% fee
        );

        // Verify upgrade
        VaultV2 proxyV2 = VaultV2(address(proxy));
        assertEq(proxyV2.version(), 2, "Version should be 2");
        assertEq(proxyV2.withdrawalFeeBps(), 100, "Fee should be set");
    }

    function test_UpgradeRevertNonOwner() public {
        VaultV2 implementationV2 = new VaultV2();

        vm.prank(alice);
        vm.expectRevert();
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100)
        );
    }

    function test_StoragePersistsAcrossUpgrade() public {
        // Alice deposits in V1
        vm.startPrank(alice);
        token.approve(address(proxy), 1000e18);
        proxy.deposit(1000e18);
        vm.stopPrank();

        // Bob deposits in V1
        vm.startPrank(bob);
        token.approve(address(proxy), 2000e18);
        proxy.deposit(2000e18);
        vm.stopPrank();

        uint256 totalBeforeUpgrade = proxy.totalDeposits();

        // Upgrade to V2
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100)
        );

        // Verify storage persisted
        VaultV2 proxyV2 = VaultV2(address(proxy));
        assertEq(proxyV2.balances(alice), 1000e18, "Alice balance should persist");
        assertEq(proxyV2.balances(bob), 2000e18, "Bob balance should persist");
        assertEq(proxyV2.totalDeposits(), totalBeforeUpgrade, "Total deposits should persist");
        assertEq(proxyV2.owner(), owner, "Owner should persist");
        assertEq(address(proxyV2.token()), address(token), "Token should persist");
    }

    // =========================================================
    //  V2 Fee Logic Tests
    // =========================================================

    function test_V2_WithdrawWithFee() public {
        // Upgrade to V2 with 1% fee
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100) // 1%
        );
        VaultV2 proxyV2 = VaultV2(address(proxy));

        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(proxy), 1000e18);
        proxyV2.deposit(1000e18);

        // Alice withdraws (should deduct 1% fee)
        uint256 aliceBalBefore = token.balanceOf(alice);
        proxyV2.withdraw(1000e18);
        vm.stopPrank();

        uint256 expectedFee = 10e18; // 1% of 1000e18
        uint256 expectedNet = 990e18; // 1000e18 - 10e18

        assertEq(token.balanceOf(alice), aliceBalBefore + expectedNet, "Alice should receive net amount");
        assertEq(proxyV2.collectedFees(), expectedFee, "Fees should be collected");
        assertEq(proxyV2.balances(alice), 0, "Alice balance should be zero");
    }

    function test_V2_SetWithdrawalFee() public {
        // Upgrade to V2
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100)
        );
        VaultV2 proxyV2 = VaultV2(address(proxy));

        // Update fee
        vm.prank(owner);
        proxyV2.setWithdrawalFee(200); // 2%

        assertEq(proxyV2.withdrawalFeeBps(), 200, "Fee should be updated");
    }

    function test_V2_SetWithdrawalFeeRevertExcessive() public {
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100)
        );
        VaultV2 proxyV2 = VaultV2(address(proxy));

        vm.prank(owner);
        vm.expectRevert(ExcessiveFee.selector);
        proxyV2.setWithdrawalFee(1001); // >10%
    }

    function test_V2_CollectFees() public {
        // Upgrade and setup
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 100)
        );
        VaultV2 proxyV2 = VaultV2(address(proxy));

        // Generate fees
        vm.startPrank(alice);
        token.approve(address(proxy), 1000e18);
        proxyV2.deposit(1000e18);
        proxyV2.withdraw(1000e18);
        vm.stopPrank();

        uint256 fees = proxyV2.collectedFees();
        assertGt(fees, 0, "Should have collected fees");

        // Collect fees
        uint256 ownerBalBefore = token.balanceOf(owner);
        vm.prank(owner);
        proxyV2.collectFees();

        assertEq(token.balanceOf(owner), ownerBalBefore + fees, "Owner should receive fees");
        assertEq(proxyV2.collectedFees(), 0, "Collected fees should be reset");
    }

    // =========================================================
    //  Integration Test
    // =========================================================

    function test_FullUpgradeWorkflow() public {
        // V1: Multiple users deposit
        vm.startPrank(alice);
        token.approve(address(proxy), 5000e18);
        proxy.deposit(5000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(proxy), 3000e18);
        proxy.deposit(3000e18);
        vm.stopPrank();

        // Verify V1 state
        assertEq(proxy.totalDeposits(), 8000e18, "V1 total deposits");

        // Upgrade to V2
        VaultV2 implementationV2 = new VaultV2();
        vm.prank(owner);
        VaultV1(address(proxy)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeWithSelector(VaultV2.initializeV2.selector, 50) // 0.5% fee
        );
        VaultV2 proxyV2 = VaultV2(address(proxy));

        // Verify upgrade
        assertEq(proxyV2.version(), 2, "Should be V2");
        assertEq(proxyV2.totalDeposits(), 8000e18, "Storage persisted");

        // Alice withdraws with fee
        vm.prank(alice);
        proxyV2.withdraw(2000e18);

        uint256 expectedFee = 10e18; // 0.5% of 2000e18
        assertEq(proxyV2.collectedFees(), expectedFee, "Fee collected");
        assertEq(proxyV2.balances(alice), 3000e18, "Alice remaining balance");

        // Owner collects fees
        vm.prank(owner);
        proxyV2.collectFees();
        assertEq(proxyV2.collectedFees(), 0, "Fees withdrawn");
    }
}

// =============================================================
//  Mock Token
// =============================================================
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

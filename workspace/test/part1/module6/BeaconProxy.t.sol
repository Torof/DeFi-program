// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    UpgradeableBeacon,
    BeaconProxy,
    TokenVaultV1,
    TokenVaultV2,
    ZeroAddress,
    Unauthorized
} from "../../../src/part1/module6/BeaconProxy.sol";

/// @notice Tests for beacon proxy pattern.
/// @dev DO NOT MODIFY THIS FILE. Fill in BeaconProxy.sol instead.
contract BeaconProxyTest is Test {
    UpgradeableBeacon beacon;
    TokenVaultV1 implementationV1;
    TokenVaultV2 implementationV2;

    BeaconProxy proxyA;
    BeaconProxy proxyB;
    BeaconProxy proxyC;

    address owner;
    address alice;
    address bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy V1 implementation
        implementationV1 = new TokenVaultV1();

        // Deploy beacon pointing to V1
        vm.prank(owner);
        beacon = new UpgradeableBeacon(address(implementationV1));
    }

    // =========================================================
    //  Beacon Tests
    // =========================================================

    function test_Beacon_Deployment() public view {
        assertEq(beacon.implementation(), address(implementationV1), "Implementation should be V1");
        assertEq(beacon.owner(), owner, "Owner should be set");
    }

    function test_Beacon_UpgradeTo() public {
        implementationV2 = new TokenVaultV2();

        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        assertEq(beacon.implementation(), address(implementationV2), "Implementation should be V2");
    }

    function test_Beacon_UpgradeRevertNonOwner() public {
        implementationV2 = new TokenVaultV2();

        vm.prank(alice);
        vm.expectRevert(Unauthorized.selector);
        beacon.upgradeTo(address(implementationV2));
    }

    function test_Beacon_UpgradeRevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        beacon.upgradeTo(address(0));
    }

    function test_Beacon_TransferOwnership() public {
        vm.prank(owner);
        beacon.transferOwnership(alice);

        assertEq(beacon.owner(), alice, "Owner should be transferred");

        // New owner can upgrade
        implementationV2 = new TokenVaultV2();
        vm.prank(alice);
        beacon.upgradeTo(address(implementationV2));

        assertEq(beacon.implementation(), address(implementationV2), "New owner can upgrade");
    }

    // =========================================================
    //  Single Proxy Tests
    // =========================================================

    function test_Proxy_Deployment() public {
        bytes memory initData = abi.encodeWithSelector(
            TokenVaultV1.initialize.selector,
            "VaultA",
            alice
        );
        proxyA = new BeaconProxy(address(beacon), initData);

        TokenVaultV1 vaultA = TokenVaultV1(address(proxyA));

        assertEq(vaultA.name(), "VaultA", "Name should be set");
        assertEq(vaultA.owner(), alice, "Owner should be set");
        assertEq(vaultA.version(), 1, "Should be V1");
    }

    function test_Proxy_DepositWithdraw() public {
        bytes memory initData = abi.encodeWithSelector(
            TokenVaultV1.initialize.selector,
            "VaultA",
            alice
        );
        proxyA = new BeaconProxy(address(beacon), initData);
        TokenVaultV1 vaultA = TokenVaultV1(address(proxyA));

        // Alice deposits
        vm.prank(alice);
        vaultA.deposit(1000);

        assertEq(vaultA.balances(alice), 1000, "Alice balance");
        assertEq(vaultA.totalDeposits(), 1000, "Total deposits");

        // Alice withdraws
        vm.prank(alice);
        vaultA.withdraw(600);

        assertEq(vaultA.balances(alice), 400, "Alice balance after withdraw");
        assertEq(vaultA.totalDeposits(), 400, "Total deposits after withdraw");
    }

    // =========================================================
    //  Multiple Proxies Tests
    // =========================================================

    function test_MultipleProxies_IndependentState() public {
        // Deploy 3 proxies, each with different name and owner
        bytes memory initDataA = abi.encodeWithSelector(
            TokenVaultV1.initialize.selector,
            "VaultA",
            alice
        );
        proxyA = new BeaconProxy(address(beacon), initDataA);

        bytes memory initDataB = abi.encodeWithSelector(
            TokenVaultV1.initialize.selector,
            "VaultB",
            bob
        );
        proxyB = new BeaconProxy(address(beacon), initDataB);

        bytes memory initDataC = abi.encodeWithSelector(
            TokenVaultV1.initialize.selector,
            "VaultC",
            owner
        );
        proxyC = new BeaconProxy(address(beacon), initDataC);

        // Cast to implementation
        TokenVaultV1 vaultA = TokenVaultV1(address(proxyA));
        TokenVaultV1 vaultB = TokenVaultV1(address(proxyB));
        TokenVaultV1 vaultC = TokenVaultV1(address(proxyC));

        // Verify independent state
        assertEq(vaultA.name(), "VaultA", "VaultA name");
        assertEq(vaultB.name(), "VaultB", "VaultB name");
        assertEq(vaultC.name(), "VaultC", "VaultC name");

        assertEq(vaultA.owner(), alice, "VaultA owner");
        assertEq(vaultB.owner(), bob, "VaultB owner");
        assertEq(vaultC.owner(), owner, "VaultC owner");

        // Different deposits
        vm.prank(alice);
        vaultA.deposit(100);

        vm.prank(bob);
        vaultB.deposit(200);

        vm.prank(owner);
        vaultC.deposit(300);

        assertEq(vaultA.totalDeposits(), 100, "VaultA deposits");
        assertEq(vaultB.totalDeposits(), 200, "VaultB deposits");
        assertEq(vaultC.totalDeposits(), 300, "VaultC deposits");
    }

    // =========================================================
    //  Beacon Upgrade Tests (All Proxies)
    // =========================================================

    function test_BeaconUpgrade_AllProxiesUpgrade() public {
        // Deploy 3 proxies with V1
        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultA", alice
        ));
        proxyB = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultB", bob
        ));
        proxyC = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultC", owner
        ));

        // All are V1
        assertEq(TokenVaultV1(address(proxyA)).version(), 1, "ProxyA V1");
        assertEq(TokenVaultV1(address(proxyB)).version(), 1, "ProxyB V1");
        assertEq(TokenVaultV1(address(proxyC)).version(), 1, "ProxyC V1");

        // Upgrade beacon to V2
        implementationV2 = new TokenVaultV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        // All proxies are now V2
        assertEq(TokenVaultV2(address(proxyA)).version(), 2, "ProxyA V2");
        assertEq(TokenVaultV2(address(proxyB)).version(), 2, "ProxyB V2");
        assertEq(TokenVaultV2(address(proxyC)).version(), 2, "ProxyC V2");
    }

    function test_BeaconUpgrade_StoragePersists() public {
        // Deploy proxy and add deposits in V1
        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultA", alice
        ));
        TokenVaultV1 vaultV1 = TokenVaultV1(address(proxyA));

        vm.prank(alice);
        vaultV1.deposit(5000);

        assertEq(vaultV1.totalDeposits(), 5000, "V1 deposits");
        assertEq(vaultV1.name(), "VaultA", "V1 name");

        // Upgrade beacon to V2
        implementationV2 = new TokenVaultV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        // Storage persists
        TokenVaultV2 vaultV2 = TokenVaultV2(address(proxyA));
        assertEq(vaultV2.totalDeposits(), 5000, "V2 deposits persisted");
        assertEq(vaultV2.name(), "VaultA", "V2 name persisted");
        assertEq(vaultV2.owner(), alice, "V2 owner persisted");
    }

    function test_BeaconUpgrade_NewFunctionality() public {
        // Setup: Deploy proxy with V1
        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultA", alice
        ));

        vm.prank(alice);
        TokenVaultV1(address(proxyA)).deposit(1000);

        // Upgrade to V2
        implementationV2 = new TokenVaultV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        TokenVaultV2 vaultV2 = TokenVaultV2(address(proxyA));

        // Set fee
        vm.prank(alice);
        vaultV2.setFeePercentage(100); // 1%

        // Withdraw with fee
        vm.prank(alice);
        vaultV2.withdraw(1000);

        uint256 expectedFee = 10; // 1% of 1000
        assertEq(vaultV2.collectedFees(), expectedFee, "Fee collected");
        assertEq(vaultV2.balances(alice), 0, "Alice balance after withdraw");
    }

    // =========================================================
    //  Integration Test: Aave-like Pattern
    // =========================================================

    function test_Integration_AavePattern() public {
        // Simulate Aave's aToken pattern:
        // - Multiple aTokens (aUSDC, aWETH, aDAI)
        // - All share same implementation via beacon
        // - Each has independent state (balances, name)
        // - Upgrade all at once via beacon

        // Deploy 3 "aTokens"
        BeaconProxy aUSDC = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "aUSDC", owner
        ));
        BeaconProxy aWETH = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "aWETH", owner
        ));
        BeaconProxy aDAI = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "aDAI", owner
        ));

        // Users deposit into different aTokens
        vm.prank(alice);
        TokenVaultV1(address(aUSDC)).deposit(1000);

        vm.prank(bob);
        TokenVaultV1(address(aWETH)).deposit(2000);

        vm.prank(alice);
        TokenVaultV1(address(aDAI)).deposit(1500);

        // All use V1
        assertEq(TokenVaultV1(address(aUSDC)).version(), 1, "aUSDC V1");
        assertEq(TokenVaultV1(address(aWETH)).version(), 1, "aWETH V1");
        assertEq(TokenVaultV1(address(aDAI)).version(), 1, "aDAI V1");

        // Aave governance upgrades the beacon (single transaction!)
        implementationV2 = new TokenVaultV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        // All aTokens now V2
        assertEq(TokenVaultV2(address(aUSDC)).version(), 2, "aUSDC V2");
        assertEq(TokenVaultV2(address(aWETH)).version(), 2, "aWETH V2");
        assertEq(TokenVaultV2(address(aDAI)).version(), 2, "aDAI V2");

        // All maintain their independent state
        assertEq(TokenVaultV2(address(aUSDC)).totalDeposits(), 1000, "aUSDC deposits");
        assertEq(TokenVaultV2(address(aWETH)).totalDeposits(), 2000, "aWETH deposits");
        assertEq(TokenVaultV2(address(aDAI)).totalDeposits(), 1500, "aDAI deposits");

        // New V2 features work on all
        vm.prank(owner);
        TokenVaultV2(address(aUSDC)).setFeePercentage(50); // 0.5%

        vm.prank(owner);
        TokenVaultV2(address(aWETH)).setFeePercentage(30); // 0.3%

        // Different fees can be set per aToken
        assertEq(TokenVaultV2(address(aUSDC)).feePercentage(), 50, "aUSDC fee");
        assertEq(TokenVaultV2(address(aWETH)).feePercentage(), 30, "aWETH fee");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_Proxy_BeaconAddress() public {
        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultA", alice
        ));

        assertEq(proxyA.beacon(), address(beacon), "Beacon address should be correct");
    }

    function test_MultipleUpgrades() public {
        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSelector(
            TokenVaultV1.initialize.selector, "VaultA", alice
        ));

        // Upgrade to V2
        implementationV2 = new TokenVaultV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        assertEq(TokenVaultV2(address(proxyA)).version(), 2, "Should be V2");

        // Could upgrade to V3 (or back to V1)
        TokenVaultV1 newImplementation = new TokenVaultV1();
        vm.prank(owner);
        beacon.upgradeTo(address(newImplementation));

        assertEq(TokenVaultV1(address(proxyA)).version(), 1, "Back to V1");
    }
}

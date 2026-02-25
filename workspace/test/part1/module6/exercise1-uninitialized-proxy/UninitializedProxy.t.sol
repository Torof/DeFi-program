// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {VulnerableVault, SecureVault, VaultWithReinitializer} from "../../../../src/part1/module6/exercise1-uninitialized-proxy/UninitializedProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Tests for uninitialized proxy attacks and fixes.
/// @dev DO NOT MODIFY THIS FILE. Fill in UninitializedProxy.sol instead.
contract UninitializedProxyTest is Test {
    address owner;
    address attacker;
    address alice;

    function setUp() public {
        owner = makeAddr("owner");
        attacker = makeAddr("attacker");
        alice = makeAddr("alice");
    }

    // =========================================================
    //  Vulnerable Vault Tests
    // =========================================================

    function test_VulnerableVault_InitializationWorks() public {
        VulnerableVault implementation = new VulnerableVault();

        bytes memory initData = abi.encodeWithSelector(
            VulnerableVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VulnerableVault vault = VulnerableVault(address(proxy));

        assertEq(vault.owner(), owner, "Owner should be set");
    }

    function test_VulnerableVault_AttackerCanReinitialize() public {
        VulnerableVault implementation = new VulnerableVault();

        bytes memory initData = abi.encodeWithSelector(
            VulnerableVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VulnerableVault vault = VulnerableVault(address(proxy));

        // Verify initial owner
        assertEq(vault.owner(), owner, "Initial owner should be set");

        // ATTACK: Attacker calls initialize again
        vm.prank(attacker);
        vault.initialize(attacker);

        // Attacker is now the owner!
        assertEq(vault.owner(), attacker, "Attacker has taken ownership");

        // Attacker can now call owner-only functions
        vm.prank(attacker);
        bool result = vault.ownerOnlyFunction();
        assertTrue(result, "Attacker can call owner-only functions");

        // Original owner is locked out
        vm.prank(owner);
        vm.expectRevert();
        vault.ownerOnlyFunction();
    }

    function test_VulnerableVault_AttackerCanInitializeImplementation() public {
        VulnerableVault implementation = new VulnerableVault();

        // ATTACK: Attacker initializes the implementation contract directly
        vm.prank(attacker);
        implementation.initialize(attacker);

        // Attacker owns the implementation
        assertEq(implementation.owner(), attacker, "Attacker owns implementation");

        // While this doesn't affect the proxy, it's still a vulnerability
        // In some proxy patterns, this could be exploited
        vm.prank(attacker);
        assertTrue(implementation.ownerOnlyFunction(), "Attacker controls implementation");
    }

    // =========================================================
    //  Secure Vault Tests
    // =========================================================

    function test_SecureVault_InitializationWorks() public {
        SecureVault implementation = new SecureVault();

        bytes memory initData = abi.encodeWithSelector(
            SecureVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        SecureVault vault = SecureVault(address(proxy));

        assertEq(vault.owner(), owner, "Owner should be set");
    }

    function test_SecureVault_CannotReinitialize() public {
        SecureVault implementation = new SecureVault();

        bytes memory initData = abi.encodeWithSelector(
            SecureVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        SecureVault vault = SecureVault(address(proxy));

        // Attempt to reinitialize
        vm.prank(attacker);
        vm.expectRevert(); // Should revert with "Initializable: contract is already initialized"
        vault.initialize(attacker);

        // Owner unchanged
        assertEq(vault.owner(), owner, "Owner should remain unchanged");
    }

    function test_SecureVault_ImplementationCannotBeInitialized() public {
        SecureVault implementation = new SecureVault();

        // Attempt to initialize the implementation
        vm.prank(attacker);
        vm.expectRevert(); // Should revert because _disableInitializers() was called
        implementation.initialize(attacker);
    }

    function test_SecureVault_OnlyOwnerCanCallOwnerFunctions() public {
        SecureVault implementation = new SecureVault();

        bytes memory initData = abi.encodeWithSelector(
            SecureVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        SecureVault vault = SecureVault(address(proxy));

        // Owner can call
        vm.prank(owner);
        assertTrue(vault.ownerOnlyFunction(), "Owner can call");

        // Attacker cannot
        vm.prank(attacker);
        vm.expectRevert();
        vault.ownerOnlyFunction();
    }

    // =========================================================
    //  Reinitializer Tests
    // =========================================================

    function test_Reinitializer_V1Initialization() public {
        VaultWithReinitializer implementation = new VaultWithReinitializer();

        bytes memory initData = abi.encodeWithSelector(
            VaultWithReinitializer.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultWithReinitializer vault = VaultWithReinitializer(address(proxy));

        assertEq(vault.owner(), owner, "Owner should be set");
        assertEq(vault.newFeature(), 0, "New feature should be unset");
    }

    function test_Reinitializer_V2Reinitialization() public {
        VaultWithReinitializer implementation = new VaultWithReinitializer();

        bytes memory initData = abi.encodeWithSelector(
            VaultWithReinitializer.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultWithReinitializer vault = VaultWithReinitializer(address(proxy));

        // Reinitialize for V2
        vm.prank(owner);
        vault.reinitializeV2(42);

        assertEq(vault.newFeature(), 42, "New feature should be set");
        assertEq(vault.owner(), owner, "Owner should persist");
    }

    function test_Reinitializer_CannotReinitializeV2Twice() public {
        VaultWithReinitializer implementation = new VaultWithReinitializer();

        bytes memory initData = abi.encodeWithSelector(
            VaultWithReinitializer.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultWithReinitializer vault = VaultWithReinitializer(address(proxy));

        // First reinitializeV2 works
        vault.reinitializeV2(42);

        // Second attempt fails
        vm.expectRevert();
        vault.reinitializeV2(99);

        assertEq(vault.newFeature(), 42, "Value should not change");
    }

    function test_Reinitializer_CannotCallV1InitAgain() public {
        VaultWithReinitializer implementation = new VaultWithReinitializer();

        bytes memory initData = abi.encodeWithSelector(
            VaultWithReinitializer.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultWithReinitializer vault = VaultWithReinitializer(address(proxy));

        // Attempt to call V1 init again
        vm.expectRevert();
        vault.initialize(alice);

        assertEq(vault.owner(), owner, "Owner should not change");
    }

    // =========================================================
    //  Attack Scenario Tests
    // =========================================================

    function test_AttackScenario_VulnerableVaultTakeover() public {
        // Scenario: Protocol deploys proxy but forgets to initialize it immediately

        VulnerableVault implementation = new VulnerableVault();

        // Deploy proxy WITHOUT initialization
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        VulnerableVault vault = VulnerableVault(address(proxy));

        // Attacker front-runs the protocol's initialize transaction
        vm.prank(attacker);
        vault.initialize(attacker);

        // Attacker now owns the vault
        assertEq(vault.owner(), attacker, "Attacker owns the vault");

        // Protocol can also call initialize (no initializer guard!)
        vm.prank(owner);
        vault.initialize(owner);
        assertEq(vault.owner(), owner, "Protocol takes ownership back");

        // But attacker can always re-take ownership — endless race condition!
        vm.prank(attacker);
        vault.initialize(attacker);
        assertEq(vault.owner(), attacker, "Attacker takes ownership again");
    }

    function test_DefenseScenario_SecureVaultProtected() public {
        // Same scenario with SecureVault

        SecureVault implementation = new SecureVault();

        // Deploy proxy WITHOUT initialization
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        SecureVault vault = SecureVault(address(proxy));

        // Attacker tries to initialize
        vm.prank(attacker);
        vault.initialize(attacker);

        // Attacker becomes owner (first call succeeds)
        assertEq(vault.owner(), attacker, "First initialize succeeds");

        // But protocol's initialize call fails
        vm.prank(owner);
        vm.expectRevert();
        vault.initialize(owner);

        // Solution: Protocol should initialize in the same transaction as proxy deployment
        // (using constructor with initData like in previous tests)
    }

    function test_BestPractice_AtomicDeploymentAndInit() public {
        SecureVault implementation = new SecureVault();

        // BEST PRACTICE: Initialize in deployment transaction
        bytes memory initData = abi.encodeWithSelector(
            SecureVault.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        SecureVault vault = SecureVault(address(proxy));

        // Vault is immediately initialized to correct owner
        assertEq(vault.owner(), owner, "Owner set atomically");

        // Attacker cannot take over
        vm.prank(attacker);
        vm.expectRevert();
        vault.initialize(attacker);

        assertEq(vault.owner(), owner, "Owner remains secure");
    }
}

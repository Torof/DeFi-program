// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    VaultV1,
    VaultV2Wrong,
    VaultV2Correct,
    VaultWithGap,
    VaultWithGapV2
} from "../../../src/part1/module6/StorageCollision.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Tests demonstrating storage collisions and correct patterns.
/// @dev DO NOT MODIFY THIS FILE. Fill in StorageCollision.sol instead.
contract StorageCollisionTest is Test {
    address owner;
    address alice;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
    }

    // =========================================================
    //  V1 Baseline Tests
    // =========================================================

    function test_V1_DepositUpdatesStorage() public {
        VaultV1 implementation = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultV1 vault = VaultV1(address(proxy));

        // Deposit 1000
        vault.deposit(1000);

        assertEq(vault.totalDeposits(), 1000, "Total deposits should be 1000");
    }

    function test_V1_StorageSlotInspection() public {
        VaultV1 implementation = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultV1 vault = VaultV1(address(proxy));

        // Deposit 1234
        vault.deposit(1234);

        // Read storage slot 0 (where totalDeposits should be)
        bytes32 slot0 = vm.load(address(vault), bytes32(uint256(0)));
        assertEq(uint256(slot0), 1234, "Slot 0 should contain totalDeposits");
    }

    // =========================================================
    //  V2 Wrong - Storage Collision Tests
    // =========================================================

    function test_V2Wrong_StorageCollision() public {
        // Deploy and initialize V1
        VaultV1 implementationV1 = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        VaultV1 vaultV1 = VaultV1(address(proxy));

        // Deposit 5000 in V1
        vaultV1.deposit(5000);
        assertEq(vaultV1.totalDeposits(), 5000, "V1 totalDeposits should be 5000");

        // Upgrade to V2Wrong
        VaultV2Wrong implementationV2Wrong = new VaultV2Wrong();
        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2Wrong), "");

        VaultV2Wrong vaultV2Wrong = VaultV2Wrong(address(proxy));

        // BUG: VaultV2Wrong redefines storage layout — slot 0 is now newOwner, not totalDeposits!
        // The old totalDeposits value (5000) gets interpreted as an address
        uint256 corruptedDeposits = vaultV2Wrong.totalDeposits();
        address corruptedOwner = vaultV2Wrong.newOwner();

        console.log("V2Wrong totalDeposits (corrupted):", corruptedDeposits);
        console.log("Expected: 5000, Got:", corruptedDeposits);
        console.log("V2Wrong newOwner (corrupted - old totalDeposits as address):");
        console.log(corruptedOwner);

        // Storage collision causes data corruption:
        // - totalDeposits reads slot 1 (__gap[0] from V1) → 0, not 5000
        // - newOwner reads slot 0 (old totalDeposits) → address(5000)
        assertNotEq(corruptedDeposits, 5000, "totalDeposits corrupted by storage collision");
    }

    function test_V2Wrong_RawStorageInspection() public {
        VaultV1 implementationV1 = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        VaultV1 vaultV1 = VaultV1(address(proxy));

        // Deposit 9999
        vaultV1.deposit(9999);

        // Read slot 0 before upgrade
        bytes32 slot0Before = vm.load(address(proxy), bytes32(uint256(0)));
        console.log("Slot 0 before upgrade (totalDeposits):");
        console.logBytes32(slot0Before);

        // Upgrade to V2Wrong
        VaultV2Wrong implementationV2Wrong = new VaultV2Wrong();
        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2Wrong), "");

        // Read slot 0 after upgrade (now interpreted as newOwner)
        bytes32 slot0After = vm.load(address(proxy), bytes32(uint256(0)));
        console.log("Slot 0 after upgrade (newOwner - corrupted):");
        console.logBytes32(slot0After);

        // The data is still there, but interpreted wrongly
        assertEq(slot0Before, slot0After, "Raw storage unchanged");

        // But the interpretation is wrong
        VaultV2Wrong vaultV2Wrong = VaultV2Wrong(address(proxy));
        console.log("newOwner address (should be 0, but corrupted):");
        console.log(vaultV2Wrong.newOwner());
    }

    // =========================================================
    //  V2 Correct - Append Only Tests
    // =========================================================

    function test_V2Correct_NoStorageCollision() public {
        // Deploy and initialize V1
        VaultV1 implementationV1 = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        VaultV1 vaultV1 = VaultV1(address(proxy));

        // Deposit 7777 in V1
        vaultV1.deposit(7777);
        assertEq(vaultV1.totalDeposits(), 7777, "V1 totalDeposits should be 7777");

        // Upgrade to V2Correct
        VaultV2Correct implementationV2Correct = new VaultV2Correct();
        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2Correct), "");

        VaultV2Correct vaultV2Correct = VaultV2Correct(address(proxy));

        // CORRECT: totalDeposits persists correctly
        assertEq(vaultV2Correct.totalDeposits(), 7777, "totalDeposits should persist");

        // New owner is unset (at new slot)
        assertEq(vaultV2Correct.newOwner(), address(0), "newOwner should be unset");

        // Can set new owner
        vm.prank(owner);
        vaultV2Correct.setNewOwner(alice);
        assertEq(vaultV2Correct.newOwner(), alice, "newOwner should be set");

        // Original data still intact
        assertEq(vaultV2Correct.totalDeposits(), 7777, "totalDeposits unchanged");
    }

    function test_V2Correct_StorageLayout() public {
        VaultV1 implementationV1 = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        VaultV1 vaultV1 = VaultV1(address(proxy));

        vaultV1.deposit(8888);

        // Upgrade
        VaultV2Correct implementationV2Correct = new VaultV2Correct();
        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2Correct), "");

        VaultV2Correct vaultV2Correct = VaultV2Correct(address(proxy));

        // Set new owner
        vm.prank(owner);
        vaultV2Correct.setNewOwner(alice);

        // Inspect storage slots
        // VaultV1 layout: slot 0 = totalDeposits, slots 1-49 = __gap[49]
        // VaultV2Correct appends newOwner AFTER inherited storage → slot 50
        bytes32 slot0 = vaultV2Correct.getStorageSlot(0);
        bytes32 slot50 = vaultV2Correct.getStorageSlot(50);

        console.log("Slot 0 (totalDeposits):");
        console.logBytes32(slot0);
        assertEq(uint256(slot0), 8888, "Slot 0 should be totalDeposits");

        console.log("Slot 50 (newOwner - after 49-slot __gap):");
        console.logBytes32(slot50);
        assertEq(address(uint160(uint256(slot50))), alice, "Slot 50 should be newOwner (after gap)");
    }

    // =========================================================
    //  Storage Gap Tests
    // =========================================================

    function test_WithGap_V1Deployment() public {
        VaultWithGap implementation = new VaultWithGap();

        bytes memory initData = abi.encodeWithSelector(VaultWithGap.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        VaultWithGap vault = VaultWithGap(address(proxy));

        vault.deposit(3333);

        assertEq(vault.totalDeposits(), 3333, "Should work like normal");
    }

    function test_WithGap_UpgradeToV2() public {
        VaultWithGap implementationV1 = new VaultWithGap();

        bytes memory initData = abi.encodeWithSelector(VaultWithGap.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        VaultWithGap vaultV1 = VaultWithGap(address(proxy));

        vaultV1.deposit(4444);

        // Upgrade to V2
        VaultWithGapV2 implementationV2 = new VaultWithGapV2();
        vm.prank(owner);
        vaultV1.upgradeToAndCall(address(implementationV2), "");

        VaultWithGapV2 vaultV2 = VaultWithGapV2(address(proxy));

        // Original data persists
        assertEq(vaultV2.totalDeposits(), 4444, "totalDeposits should persist");

        // New features work
        vm.startPrank(owner);
        vaultV2.setFeeCollector(alice);
        vaultV2.setFeeBps(100);
        vm.stopPrank();

        assertEq(vaultV2.feeCollector(), alice, "feeCollector should be set");
        assertEq(vaultV2.feeBps(), 100, "feeBps should be set");
    }

    // =========================================================
    //  Comparison Test: Wrong vs Correct
    // =========================================================

    function test_Comparison_WrongVsCorrect() public {
        // Setup two identical V1 proxies
        VaultV1 implV1Wrong = new VaultV1();
        VaultV1 implV1Correct = new VaultV1();

        bytes memory initData = abi.encodeWithSelector(VaultV1.initialize.selector, owner);

        ERC1967Proxy proxyWrong = new ERC1967Proxy(address(implV1Wrong), initData);
        ERC1967Proxy proxyCorrect = new ERC1967Proxy(address(implV1Correct), initData);

        VaultV1 vaultWrong = VaultV1(address(proxyWrong));
        VaultV1 vaultCorrect = VaultV1(address(proxyCorrect));

        // Both deposit same amount
        vaultWrong.deposit(12345);
        vaultCorrect.deposit(12345);

        assertEq(vaultWrong.totalDeposits(), 12345, "Wrong V1");
        assertEq(vaultCorrect.totalDeposits(), 12345, "Correct V1");

        // Upgrade to V2Wrong
        VaultV2Wrong implV2Wrong = new VaultV2Wrong();
        vm.prank(owner);
        vaultWrong.upgradeToAndCall(address(implV2Wrong), "");

        // Upgrade to V2Correct
        VaultV2Correct implV2Correct = new VaultV2Correct();
        vm.prank(owner);
        vaultCorrect.upgradeToAndCall(address(implV2Correct), "");

        // Compare results
        VaultV2Wrong v2Wrong = VaultV2Wrong(address(proxyWrong));
        VaultV2Correct v2Correct = VaultV2Correct(address(proxyCorrect));

        console.log("=== Comparison ===");
        console.log("V2Wrong totalDeposits:", v2Wrong.totalDeposits());
        console.log("V2Correct totalDeposits:", v2Correct.totalDeposits());

        // V2Correct should preserve the value (proper inheritance)
        assertEq(v2Correct.totalDeposits(), 12345, "V2Correct preserves data");

        // V2Wrong has corrupted data (wrong storage layout)
        assertNotEq(v2Wrong.totalDeposits(), 12345, "V2Wrong data is corrupted");
    }
}

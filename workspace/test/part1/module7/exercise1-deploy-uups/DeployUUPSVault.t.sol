// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {DeployUUPSVault, DeployMultiNetwork} from "../../../../script/DeployUUPSVault.s.sol";
import {VaultV1, VaultV2} from "../../../../src/part1/module6/exercise4-uups-vault/UUPSVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev PREREQUISITE: Complete Module 6, Exercise 4 (UUPSVault.sol) before running these tests.
/// These tests depend on VaultV1 and VaultV2 implementations from Module 6.

/// @notice Tests for deployment scripts.
/// @dev DO NOT MODIFY THIS FILE. Fill in DeployUUPSVault.s.sol instead.
contract DeployUUPSVaultTest is Test {
    DeployUUPSVault deployScript;
    MockToken token;

    address deployer;
    uint256 deployerKey;

    address safe;

    function setUp() public {
        deployScript = new DeployUUPSVault();

        // Create deployer
        deployerKey = 0xDEADBEEF;
        deployer = vm.addr(deployerKey);

        // Deploy mock token
        token = new MockToken();

        // Create mock Safe multisig
        safe = makeAddr("safe");
        // Give Safe some code to simulate a contract
        vm.etch(safe, hex"60");

        // Set environment variables for the script
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));
        vm.setEnv("VAULT_TOKEN", vm.toString(address(token)));
        vm.setEnv("INITIAL_OWNER", vm.toString(deployer));

        // Fund deployer
        vm.deal(deployer, 100 ether);
    }

    // =========================================================
    //  Main Deployment Tests
    // =========================================================

    function test_Deploy_Success() public {
        // Run deployment script
        deployScript.run();

        // Verify deployment occurred
        // Note: In a real test, you'd capture the deployed addresses
        // For now, we verify the script doesn't revert
    }

    // =========================================================
    //  Ownership Transfer Tests
    // =========================================================

    function test_TransferToSafe_Success() public {
        // First deploy a vault
        VaultV1 implementation = new VaultV1();
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (address(token), deployer)
        );

        vm.prank(deployer);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Transfer to Safe
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));
        deployScript.transferToSafe(address(proxy), safe);

        // Verify ownership transferred
        VaultV1 vault = VaultV1(address(proxy));
        assertEq(vault.owner(), safe, "Owner should be Safe");
    }

    function test_TransferToSafe_RevertNonContract() public {
        VaultV1 implementation = new VaultV1();
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (address(token), deployer)
        );

        vm.prank(deployer);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Try to transfer to EOA (should revert)
        address eoa = makeAddr("eoa");

        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));
        // Expects revert because safe address is not a contract (EOA)
        vm.expectRevert(); // Safe validation should reject non-contract address
        deployScript.transferToSafe(address(proxy), eoa);
    }

    // =========================================================
    //  Upgrade Tests
    // =========================================================

    function test_UpgradeToV2_Success() public {
        // Deploy V1
        vm.startPrank(deployer);
        VaultV1 implementation = new VaultV1();
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (address(token), deployer)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vm.stopPrank();

        VaultV1 vault = VaultV1(address(proxy));
        assertEq(vault.version(), 1, "Should start as V1");

        // Upgrade to V2
        vm.setEnv("OWNER_PRIVATE_KEY", vm.toString(deployerKey));
        deployScript.upgradeToV2(address(proxy));

        // Verify upgrade
        VaultV2 vaultV2 = VaultV2(address(proxy));
        assertEq(vaultV2.version(), 2, "Should be V2 after upgrade");
        assertEq(vaultV2.withdrawalFeeBps(), 100, "Fee should be set");
    }

    function test_UpgradeToV2_StoragePersists() public {
        // Deploy V1 and add some state
        token.mint(deployer, 10000);

        vm.startPrank(deployer);
        VaultV1 implementation = new VaultV1();
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (address(token), deployer)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        VaultV1 vault = VaultV1(address(proxy));
        token.approve(address(proxy), 1000);
        vault.deposit(1000);
        vm.stopPrank();

        uint256 depositsBefore = vault.totalDeposits();

        // Upgrade
        vm.setEnv("OWNER_PRIVATE_KEY", vm.toString(deployerKey));
        deployScript.upgradeToV2(address(proxy));

        // Verify storage persisted
        VaultV2 vaultV2 = VaultV2(address(proxy));
        assertEq(vaultV2.totalDeposits(), depositsBefore, "Deposits should persist");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    // Note: This test passes initially because run() reverts with "Not implemented".
    // After implementing run(), it should pass because empty env vars cause vm.envUint to revert.
    function test_Deploy_WithoutEnvVars() public {
        // Clear env vars
        vm.setEnv("PRIVATE_KEY", "");
        vm.setEnv("VAULT_TOKEN", "");

        // Should revert when trying to load missing env vars
        vm.expectRevert();
        deployScript.run();
    }

    function test_VerifyDeployment_DetectsMismatch() public {
        // Deploy with correct config
        vm.startPrank(deployer);
        VaultV1 implementation = new VaultV1();
        bytes memory initData = abi.encodeCall(
            VaultV1.initialize,
            (address(token), deployer)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vm.stopPrank();

        // Try to verify with wrong expected values
        address wrongToken = makeAddr("wrongToken");

        // Expects revert because token address does not match the deployed vault's token
        vm.expectRevert(); // _verifyDeployment should require(token == expectedToken)
        deployScript._verifyDeployment(address(proxy), wrongToken, deployer);
    }
}

// =============================================================
//  Helper Contracts
// =============================================================

contract MockToken is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Import proxy for testing
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

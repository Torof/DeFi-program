// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Production Deployment Script
//
// Build a complete deployment script that handles:
// - Deploying UUPS proxy and implementation
// - Post-deployment verification
// - Ownership transfer to Safe multisig
// - Comprehensive logging for production use
//
// Master production deployment workflows.
//
// Simulate: forge script script/DeployUUPSVault.s.sol --rpc-url $SEPOLIA_RPC
// Deploy:   forge script script/DeployUUPSVault.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
// ============================================================================

import "forge-std/Script.sol";
import {VaultV1, VaultV2} from "../src/part1/module6/UUPSVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// =============================================================
//  TODO 1: Implement DeployUUPSVault Script
// =============================================================
/// @notice Complete deployment script for UUPS upgradeable vault.
/// @dev Handles implementation, proxy, verification, and ownership transfer.
contract DeployUUPSVault is Script {
    // =============================================================
    //  Deployment Configuration
    // =============================================================
    // TODO: Define deployment parameters
    // These can be overridden via environment variables

    // Mainnet addresses (for mainnet deployment)
    // address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Sepolia addresses (for testnet deployment)
    // address constant USDC_SEPOLIA = 0x...;  // Deploy a mock USDC for testing

    // =============================================================
    //  TODO 2: Implement Main Deployment Function
    // =============================================================
    /// @notice Main deployment function.
    function run() external {
        // TODO: Implement
        // 1. Load configuration from environment:
        //    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        //    address tokenAddress = vm.envOr("VAULT_TOKEN", USDC_SEPOLIA);
        //    address initialOwner = vm.envOr("INITIAL_OWNER", vm.addr(deployerKey));
        //
        // 2. Log pre-deployment info:
        //    console.log("=== UUPS Vault Deployment ===");
        //    console.log("Network:", block.chainid);
        //    console.log("Deployer:", vm.addr(deployerKey));
        //    console.log("Token:", tokenAddress);
        //    console.log("Initial Owner:", initialOwner);
        //
        // 3. Start broadcasting transactions:
        //    vm.startBroadcast(deployerKey);
        //
        // 4. Deploy implementation:
        //    VaultV1 implementation = new VaultV1();
        //    console.log("Implementation deployed:", address(implementation));
        //
        // 5. Deploy proxy with initialization:
        //    bytes memory initData = abi.encodeWithSelector(
        //        VaultV1.initialize.selector,
        //        tokenAddress,
        //        initialOwner
        //    );
        //    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        //    console.log("Proxy deployed:", address(proxy));
        //
        // 6. Stop broadcasting:
        //    vm.stopBroadcast();
        //
        // 7. Verify deployment (off-chain):
        //    _verifyDeployment(address(proxy), tokenAddress, initialOwner);
        //
        // 8. Log post-deployment instructions:
        //    _logPostDeployment(address(implementation), address(proxy));

        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement Deployment Verification
    // =============================================================
    /// @notice Verifies the deployment succeeded correctly.
    /// @param proxyAddress Address of deployed proxy
    /// @param expectedToken Expected token address
    /// @param expectedOwner Expected owner address
    function _verifyDeployment(
        address proxyAddress,
        address expectedToken,
        address expectedOwner
    ) public view {
        // TODO: Implement
        // 1. Create vault interface: VaultV1 vault = VaultV1(proxyAddress);
        // 2. Verify token: require(address(vault.token()) == expectedToken, "Token mismatch");
        // 3. Verify owner: require(vault.owner() == expectedOwner, "Owner mismatch");
        // 4. Verify version: require(vault.version() == 1, "Version mismatch");
        // 5. Log success:
        //    console.log("✓ Deployment verified");
        //    console.log("  Token:", address(vault.token()));
        //    console.log("  Owner:", vault.owner());
        //    console.log("  Version:", vault.version());
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement Post-Deployment Instructions
    // =============================================================
    /// @notice Logs instructions for post-deployment steps.
    function _logPostDeployment(address implementation, address proxy) internal view {
        // TODO: Implement comprehensive logging
        // console.log("\n=== Deployment Complete ===");
        // console.log("Implementation:", implementation);
        // console.log("Proxy:", proxy);
        // console.log("\n=== Next Steps ===");
        // console.log("1. Verify contracts on Etherscan:");
        // console.log("   forge verify-contract", implementation, "src/part1/module6/UUPSVault.sol:VaultV1 --chain sepolia");
        // console.log("2. Test the vault:");
        // console.log("   cast call", proxy, "\"owner()\" --rpc-url $SEPOLIA_RPC");
        // console.log("3. Transfer ownership to Safe multisig (if needed):");
        // console.log("   cast send", proxy, "\"transferOwnership(address)\" <SAFE_ADDRESS> --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY");
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement Ownership Transfer Helper
    // =============================================================
    /// @notice Helper function to transfer ownership to Safe multisig.
    /// @param proxyAddress Address of the proxy
    /// @param safeAddress Address of the Safe multisig
    function transferToSafe(address proxyAddress, address safeAddress) external {
        // TODO: Implement
        // 1. Load deployer key: uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        // 2. Verify safeAddress is a contract:
        //    require(safeAddress.code.length > 0, "Safe must be a contract");
        // 3. Start broadcast:
        //    vm.startBroadcast(deployerKey);
        // 4. Transfer ownership:
        //    VaultV1 vault = VaultV1(proxyAddress);
        //    vault.transferOwnership(safeAddress);
        // 5. Stop broadcast:
        //    vm.stopBroadcast();
        // 6. Log:
        //    console.log("Ownership transferred to Safe:", safeAddress);
        //    console.log("Please confirm the transfer from the Safe UI");
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement Upgrade Script
    // =============================================================
    /// @notice Upgrades the vault to V2.
    /// @param proxyAddress Address of the proxy to upgrade
    function upgradeToV2(address proxyAddress) external {
        // TODO: Implement (VaultV2 is already imported at the top of this file)
        // 1. Load owner key: uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");
        // 3. Start broadcast:
        //    vm.startBroadcast(ownerKey);
        // 4. Deploy V2 implementation:
        //    VaultV2 implementationV2 = new VaultV2();
        //    console.log("V2 Implementation:", address(implementationV2));
        // 5. Upgrade proxy:
        //    VaultV1 vault = VaultV1(proxyAddress);
        //    vault.upgradeToAndCall(
        //        address(implementationV2),
        //        abi.encodeWithSelector(VaultV2.initializeV2.selector, 100) // 1% fee
        //    );
        // 6. Stop broadcast:
        //    vm.stopBroadcast();
        // 7. Verify upgrade:
        //    VaultV2 vaultV2 = VaultV2(proxyAddress);
        //    require(vaultV2.version() == 2, "Upgrade failed");
        //    console.log("✓ Upgraded to V2");
        revert("Not implemented");
    }
}

// =============================================================
//  TODO 7: Implement Multi-Network Deployment Script
// =============================================================
/// @notice Deployment script that handles multiple networks.
contract DeployMultiNetwork is Script {
    // Network configurations
    struct NetworkConfig {
        address token;
        address initialOwner;
    }

    mapping(uint256 => NetworkConfig) public configs;

    constructor() {
        // TODO: Initialize network configs
        // Mainnet (chainid 1)
        // configs[1] = NetworkConfig({
        //     token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        //     initialOwner: 0x... // Production Safe multisig
        // });
        //
        // Sepolia (chainid 11155111)
        // configs[11155111] = NetworkConfig({
        //     token: 0x..., // Test USDC
        //     initialOwner: msg.sender // For testing
        // });
    }

    /// @notice Deploys to the current network.
    function run() external {
        // TODO: Implement
        // 1. Get network config:
        //    NetworkConfig memory config = configs[block.chainid];
        //    require(config.token != address(0), "Network not configured");
        // 2. Deploy using config:
        //    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        //    vm.startBroadcast(deployerKey);
        //    VaultV1 implementation = new VaultV1();
        //    ERC1967Proxy proxy = new ERC1967Proxy(
        //        address(implementation),
        //        abi.encodeWithSelector(VaultV1.initialize.selector, config.token, config.initialOwner)
        //    );
        //    vm.stopBroadcast();
        // 3. Log deployment:
        //    console.log("Deployed to network:", block.chainid);
        //    console.log("Proxy:", address(proxy));
        revert("Not implemented");
    }
}

// =============================================================
//  Example .env file:
// =============================================================
// # Deployment
// PRIVATE_KEY=0x...
// OWNER_PRIVATE_KEY=0x...  # For upgrades (can be same as PRIVATE_KEY for testing)
//
// # Network RPCs
// SEPOLIA_RPC=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
// MAINNET_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
//
// # Contract Configuration
// VAULT_TOKEN=0x...  # Token address for the vault
// INITIAL_OWNER=0x... # Initial owner address
//
// # Verification
// ETHERSCAN_API_KEY=YOUR_KEY
//
// # Safe Multisig (optional)
// SAFE_ADDRESS=0x...
//
// # Usage Examples:
// # Deploy to Sepolia:
// forge script script/DeployUUPSVault.s.sol:DeployUUPSVault --rpc-url $SEPOLIA_RPC --broadcast --verify
//
// # Transfer to Safe:
// forge script script/DeployUUPSVault.s.sol:DeployUUPSVault --sig "transferToSafe(address,address)" <PROXY> <SAFE> --rpc-url $SEPOLIA_RPC --broadcast
//
// # Upgrade to V2:
// forge script script/DeployUUPSVault.s.sol:DeployUUPSVault --sig "upgradeToV2(address)" <PROXY> --rpc-url $SEPOLIA_RPC --broadcast

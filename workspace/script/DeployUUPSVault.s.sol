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
// See: Module 7 > Deployment Scripts (#deployment-scripts)
//
// Simulate: forge script script/DeployUUPSVault.s.sol --rpc-url $SEPOLIA_RPC
// Deploy:   forge script script/DeployUUPSVault.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
// ============================================================================

import "forge-std/Script.sol";
import {VaultV1, VaultV2} from "../src/part1/module6/exercise4-uups-vault/UUPSVault.sol";
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
        // 1. Load deployment configuration from environment
        //    Read: PRIVATE_KEY, VAULT_TOKEN address, and INITIAL_OWNER address
        //    Use vm.envUint and vm.envAddress to read environment variables
        //    Start the broadcast with vm.startBroadcast(deployerPrivateKey)
        //
        // 2. Log pre-deployment info (network, deployer, token, owner)
        //    Use console.log to print deployment context
        //
        // 3. Deploy the VaultV1 implementation contract
        //
        // 4. Deploy an ERC1967Proxy pointing to the implementation
        //    Encode the initialization call using abi.encodeCall
        //    Pass token address and initial owner as initialize() args
        //
        // 5. Stop broadcasting and verify the deployment
        //    Call _verifyDeployment and _logPostDeployment helpers

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
        // 1. Cast proxyAddress to a VaultV1 interface
        // 2. Use require() to verify the vault's token, owner, and version
        //    match the expected values
        // 3. Log verification results with console.log
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement Post-Deployment Instructions
    // =============================================================
    /// @notice Logs instructions for post-deployment steps.
    function _logPostDeployment(address implementation, address proxy) internal view {
        // TODO: Implement comprehensive logging
        // Log the deployed addresses (implementation + proxy)
        // Log next steps: verify on Etherscan, test with cast call, transfer ownership
        // Hint: Use console.log to print each step as a guide for the operator
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement Ownership Transfer Helper
    // =============================================================
    // See: Module 7 > Safe Multisig (#safe-multisig)
    /// @notice Helper function to transfer ownership to Safe multisig.
    /// @param proxyAddress Address of the proxy
    /// @param safeAddress Address of the Safe multisig
    function transferToSafe(address proxyAddress, address safeAddress) external {
        // TODO: Implement
        // 1. Load deployer private key from environment
        // 2. Verify safeAddress has code deployed (it must be a contract, not an EOA)
        // 3. Start broadcast, call transferOwnership on the vault, stop broadcast
        // 4. Log the transfer and remind operator to confirm from Safe UI
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 6: Implement Upgrade Script
    // =============================================================
    // See: Module 6 > UUPS Proxy Pattern
    /// @notice Upgrades the vault to V2.
    /// @param proxyAddress Address of the proxy to upgrade
    function upgradeToV2(address proxyAddress) external {
        // TODO: Implement (VaultV2 is already imported at the top of this file)
        // 1. Load owner private key from OWNER_PRIVATE_KEY env var
        // 2. Start broadcast as the owner
        // 3. Deploy a new VaultV2 implementation contract
        // 4. Call upgradeToAndCall on the proxy (cast as VaultV1) to point
        //    at the new implementation. Use abi.encodeCall to encode the
        //    VaultV2.initializeV2 call with a fee parameter (e.g., 100 for 1%)
        // 5. Stop broadcast and verify the upgrade succeeded
        //    (version should now be 2)
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
        // Populate configs mapping for each supported chain (e.g., chainid 1 for mainnet,
        // 11155111 for Sepolia). Each entry needs a token address and an initial owner.
        // Use real addresses for mainnet, test addresses for testnets.
    }

    /// @notice Deploys to the current network.
    function run() external {
        // TODO: Implement
        // 1. Look up the NetworkConfig for the current block.chainid
        //    Revert if the network is not configured (token == address(0))
        // 2. Load deployer key, start broadcast, deploy VaultV1 + ERC1967Proxy
        //    Use abi.encodeCall to encode the initialize call with config values
        // 3. Stop broadcast and log deployment info (chain ID, proxy address)
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

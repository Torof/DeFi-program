// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Deployment Script
//
// Learn to write deployment scripts using Foundry's scripting system.
// Scripts are written in Solidity and can be simulated or broadcast to
// actual networks.
//
// Day 13: Master deployment workflows.
//
// Simulate: forge script script/DeploySimpleVault.s.sol --rpc-url $RPC_URL
// Deploy:   forge script script/DeploySimpleVault.s.sol --rpc-url $RPC_URL --broadcast --verify
// ============================================================================

import "forge-std/Script.sol";
import {SimpleVault} from "../src/part1/module5/SimpleVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deployment script for SimpleVault.
contract DeploySimpleVault is Script {
    // =============================================================
    //  TODO 1: Define Deployment Parameters
    // =============================================================

    // TODO: Define the token address for the vault
    // For mainnet deployment:
    // address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //
    // For testnet deployment, use appropriate testnet token addresses

    // =============================================================
    //  TODO 2: Implement Main Deployment Function
    // =============================================================

    /// @notice Main deployment function.
    /// @dev Called by `forge script`.
    function run() external {
        // TODO: Implement
        // 1. Get deployer private key from environment:
        //    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        //
        // 2. Get token address (could also be from env var):
        //    address tokenAddress = vm.envAddress("VAULT_TOKEN");
        //    // Or use constant: address tokenAddress = USDC;
        //
        // 3. Start broadcasting transactions:
        //    vm.startBroadcast(deployerPrivateKey);
        //
        // 4. Deploy the vault:
        //    SimpleVault vault = new SimpleVault(IERC20(tokenAddress));
        //
        // 5. Stop broadcasting:
        //    vm.stopBroadcast();
        //
        // 6. Log deployment info:
        //    console.log("SimpleVault deployed at:", address(vault));
        //    console.log("Asset token:", address(vault.asset()));
        //
        // 7. Optional: Verify deployment worked
        //    require(address(vault) != address(0), "Deployment failed");
        //    require(address(vault.asset()) == tokenAddress, "Wrong asset");

        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement Deployment with Constructor Args from Env
    // =============================================================

    /// @notice Alternative deployment that reads all config from env.
    function runFromEnv() external {
        // TODO: Implement
        // 1. Read private key: vm.envUint("PRIVATE_KEY")
        // 2. Read token address: vm.envAddress("VAULT_TOKEN")
        // 3. Deploy vault
        // 4. Log results
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 4: Implement Multi-Contract Deployment
    // =============================================================

    /// @notice Deploys multiple vaults for different tokens.
    function deployMultiple() external {
        // TODO: Implement
        // 1. Define array of token addresses
        // 2. Get deployer key
        // 3. Start broadcast
        // 4. Loop through tokens and deploy a vault for each:
        //    for (uint256 i = 0; i < tokens.length; i++) {
        //        SimpleVault vault = new SimpleVault(IERC20(tokens[i]));
        //        console.log("Vault", i, "deployed at:", address(vault));
        //    }
        // 5. Stop broadcast
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 5: Implement Deployment Verification
    // =============================================================

    /// @notice Verifies a deployed vault contract.
    /// @param vaultAddress Address of deployed vault
    function verify(address vaultAddress) external view {
        // TODO: Implement
        // 1. Create vault instance: SimpleVault vault = SimpleVault(vaultAddress)
        // 2. Verify contract has code: require(vaultAddress.code.length > 0, "Not deployed")
        // 3. Verify vault properties:
        //    - Check that asset is set
        //    - Check that totalSupply is 0 (new vault)
        //    - Check that totalAssets is 0
        // 4. Log verification results
        revert("Not implemented");
    }
}

// =============================================================
//  Example .env file for this script:
// =============================================================
// PRIVATE_KEY=0x...
// MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
// SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
// ETHERSCAN_API_KEY=YOUR_KEY
// VAULT_TOKEN=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
//
// Usage:
// forge script script/DeploySimpleVault.s.sol:DeploySimpleVault --rpc-url $MAINNET_RPC_URL --broadcast --verify

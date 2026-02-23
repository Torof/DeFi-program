// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Base Test Contract with Fork Configuration
//
// Create a reusable base test contract that sets up common DeFi testing
// infrastructure: mainnet fork, test users with private keys, and commonly
// used protocol addresses.
//
// This will be used throughout Part 2 as the foundation for all fork tests.
//
// Day 11: Master Foundry essentials for DeFi development.
//
// Run: forge test --match-contract BaseTest -vvv
// ============================================================================

import "forge-std/Test.sol";

// =============================================================
//  TODO 1: Implement BaseTest
// =============================================================
/// @notice Base test contract with mainnet fork and common test infrastructure.
/// @dev Extend this contract in Part 2 modules for consistent test setup.
abstract contract BaseTest is Test {
    // =============================================================
    //  Common Protocol Addresses (Mainnet)
    // =============================================================
    // TODO: Define constants for commonly used addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // =============================================================
    //  Test Users
    // =============================================================
    // TODO: Populate these in setUp using makeAddrAndKey
    address public alice;
    uint256 public aliceKey;
    address public bob;
    uint256 public bobKey;
    address public charlie;
    uint256 public charlieKey;

    // =============================================================
    //  TODO 2: Implement setUp
    // =============================================================
    /// @notice Sets up the test environment with mainnet fork and test users.
    /// @dev This is virtual so child contracts can extend it.
    function setUp() public virtual {
        // TODO: Implement
        // 1. Create a mainnet fork: vm.createSelectFork("mainnet")
        //    Note: This requires MAINNET_RPC_URL in your .env file
        // 2. Create test users with private keys:
        //    (alice, aliceKey) = makeAddrAndKey("alice");
        //    (bob, bobKey) = makeAddrAndKey("bob");
        //    (charlie, charlieKey) = makeAddrAndKey("charlie");
        // 3. Label the addresses for better trace output:
        //    vm.label(alice, "Alice");
        //    vm.label(bob, "Bob");
        //    vm.label(charlie, "Charlie");
        //    vm.label(WETH, "WETH");
        //    vm.label(USDC, "USDC");
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement Helper Functions
    // =============================================================

    /// @notice Deals ETH to an address.
    /// @param to Address to receive ETH
    /// @param amount Amount of ETH to deal (in wei)
    function dealETH(address to, uint256 amount) internal {
        // TODO: Implement using vm.deal
        revert("Not implemented");
    }

    /// @notice Deals ERC20 tokens to an address.
    /// @param token Token address
    /// @param to Address to receive tokens
    /// @param amount Amount of tokens to deal
    function dealToken(address token, address to, uint256 amount) internal {
        // TODO: Implement using deal(address, address, uint256)
        revert("Not implemented");
    }

    /// @notice Creates a signature for EIP-712 typed data.
    /// @param privateKey Private key to sign with
    /// @param digest Hash to sign
    /// @return v Signature recovery id
    /// @return r Signature r component
    /// @return s Signature s component
    function signTypedData(uint256 privateKey, bytes32 digest)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // TODO: Implement using vm.sign
        // return vm.sign(privateKey, digest);
        revert("Not implemented");
    }

    /// @notice Advances block timestamp by a given duration.
    /// @param duration Time to advance (in seconds)
    function skip(uint256 duration) internal override {
        // TODO: Implement using vm.warp
        // vm.warp(block.timestamp + duration);
        revert("Not implemented");
    }

    /// @notice Advances block number by a given count.
    /// @param blocks Number of blocks to advance
    function skipBlocks(uint256 blocks) internal {
        // TODO: Implement using vm.roll
        // vm.roll(block.number + blocks);
        revert("Not implemented");
    }
}

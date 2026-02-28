// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Vault Invariant Testing
//
// Invariant tests define properties that must ALWAYS hold true, no matter
// what sequence of operations is performed. The fuzzer generates random
// sequences of deposits and withdrawals and verifies the invariants.
//
// This is the most powerful testing technique for finding edge cases in
// DeFi protocols.
//
// Day 12: Master invariant testing for DeFi.
//
// Run: forge test --match-test invariant -vvv
// ============================================================================

import "forge-std/Test.sol";
import {SimpleVault} from "../../../../src/part1/module5/exercise1-simple-vault/SimpleVault.sol";
import {VaultHandler} from "./VaultHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Invariant tests for SimpleVault.
/// @dev DO NOT MODIFY THIS FILE. Fill in VaultHandler.sol and SimpleVault.sol instead.
contract VaultInvariantTest is Test {
    SimpleVault vault;
    MockToken token;
    VaultHandler handler;

    function setUp() public {
        // Deploy token and vault
        token = new MockToken();
        vault = new SimpleVault(IERC20(address(token)));

        // Deploy handler
        handler = new VaultHandler(vault, IERC20(address(token)));

        // Tell Foundry to call the handler (not the vault directly)
        targetContract(address(handler));

        // Only call these functions on the handler
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.addYield.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // =============================================================
    //  Invariant Tests
    // =============================================================

    /// @notice INVARIANT: Vault's total assets must equal its token balance.
    /// @dev This is a conservation invariant - no assets should disappear.
    function invariant_totalAssetsMatchesBalance() public view {
        assertEq(
            vault.totalAssets(),
            token.balanceOf(address(vault)),
            "Invariant violated: totalAssets != token balance"
        );
    }

    /// @notice INVARIANT: Sum of all user shares must equal total supply.
    /// @dev This is a consistency invariant - accounting must be correct.
    function invariant_sharesAccountingConsistent() public view {
        uint256 sumOfShares = handler.getTotalActorShares();
        assertEq(sumOfShares, vault.totalSupply(), "Invariant violated: sum of shares != totalSupply");
    }

    /// @notice INVARIANT: Vault must always be solvent.
    /// @dev The vault must have enough assets to cover all shares at current rate.
    function invariant_solvency() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply == 0) {
            // If no shares, vault can have any amount of assets (donations)
            return;
        }

        // Every share should be redeemable for some assets
        // Total assets should be >= what all shares can withdraw
        uint256 assetsNeeded = vault.convertToAssets(totalSupply);
        assertGe(totalAssets, assetsNeeded, "Invariant violated: vault is insolvent");
    }

    /// @notice INVARIANT: Share price should never decrease (in the absence of losses).
    /// @dev This test assumes no losses - only deposits, withdrawals, and potential yield.
    function invariant_sharePriceNeverDecreases() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply == 0) {
            // No shares minted yet
            return;
        }

        // Share price = totalAssets / totalSupply
        // On first deposit, it's 1:1
        // It should never go below 1:1 (each share worth at least 1 wei of asset)
        // Note: This can fail if there are withdrawal rounding issues
        assertGe(totalAssets, totalSupply, "Invariant violated: share price decreased below 1:1");
    }

    /// @notice INVARIANT: No individual user balance should exceed total supply.
    /// @dev A user's share balance can never be greater than the total shares issued.
    function invariant_noUserExceedsSupply() public view {
        uint256 supply = vault.totalSupply();
        uint256 count = handler.getActorCount();
        for (uint256 i = 0; i < count; i++) {
            address actor = handler.actors(i);
            assertLe(vault.balanceOf(actor), supply, "No user should have more shares than total supply");
        }
    }

    /// @notice INVARIANT: Conversions should be consistent.
    /// @dev Converting assets→shares→assets should return similar value (within rounding).
    function invariant_conversionConsistency() public view {
        if (vault.totalSupply() == 0) {
            return; // No meaningful conversions without shares
        }

        // Test with a reasonable amount
        uint256 testAmount = 1000e18;
        if (testAmount > vault.totalAssets()) {
            testAmount = vault.totalAssets() / 2;
        }

        if (testAmount == 0) {
            return;
        }

        uint256 shares = vault.convertToShares(testAmount);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Allow rounding error of 1 wei per share
        uint256 tolerance = vault.totalSupply() > 0 ? vault.totalSupply() : 1;
        assertApproxEqAbs(
            assetsBack, testAmount, tolerance, "Invariant violated: conversion not consistent (too much rounding error)"
        );
    }

    /// @notice INVARIANT: No free money - ghost variables should be consistent.
    /// @dev Uses conservation of value: total value out <= total value in.
    ///      Value in = deposits + yield. Value out = withdrawals + current vault balance.
    ///      Rounding losses mean value out may be slightly less than value in.
    function invariant_noFreeMoney() public view {
        uint256 totalValueIn = handler.ghost_depositSum() + handler.ghost_yieldSum();
        uint256 totalValueOut = handler.ghost_withdrawSum() + vault.totalAssets();

        // Total value out should never exceed total value in
        // (any difference is rounding losses from integer division in share math)
        assertLe(
            totalValueOut,
            totalValueIn,
            "Invariant violated: value created from nothing"
        );
    }

    // =============================================================
    //  Teardown: Call Summary
    // =============================================================

    /// @notice Called after invariant tests to show call summary.
    function invariant_callSummary() public view {
        handler.callSummary();
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

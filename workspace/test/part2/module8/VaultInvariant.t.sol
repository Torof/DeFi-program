// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  EXERCISE: VaultInvariant — Write Invariant Tests That Find a Bug
// ============================================================================
//
//  This exercise is DIFFERENT from the others. Instead of implementing
//  protocol code, you implement TESTS that find a bug.
//
//  BuggyVault has a subtle ordering bug in withdraw(). Your invariant
//  tests should find it automatically by exploring random call sequences.
//
//  SUCCESS CRITERIA:
//    - test_HandlerDepositsWork → PASSES (your handler works correctly)
//    - invariant_solvency → FAILS with counter-example (found the bug!)
//    - invariant_noActorProfits → FAILS with counter-example (found the bug!)
//
//  The invariant FAILURES are the goal — they prove your tests caught
//  the bug that unit tests would miss.
//
//  Implement:
//    1. VaultHandler: deposit() + withdraw() (in VaultHandler.sol)
//    2. invariant_solvency + invariant_noActorProfits (in this file)
//
//  Required foundry.toml config:
//    [invariant]
//    runs = 256
//    depth = 15
//    fail_on_revert = false
//
//  Run:
//    forge test --match-contract BuggyVaultInvariantTest -vvv
//
// ============================================================================

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {MockERC20} from "../../../src/part2/module8/mocks/MockERC20.sol";
import {BuggyVault} from "../../../src/part2/module8/BuggyVault.sol";
import {VaultHandler} from "../../../src/part2/module8/VaultHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BuggyVaultInvariantTest is StdInvariant, Test {
    MockERC20 token;
    BuggyVault vault;
    VaultHandler handler;

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK", 18);
        vault = new BuggyVault(IERC20(address(token)));
        handler = new VaultHandler(vault, token);

        // Tell Foundry to only call functions on the handler
        targetContract(address(handler));
    }

    // =========================================================
    //  Pre-built: verifies your handler deposit works correctly
    // =========================================================

    function test_HandlerDepositsWork() public {
        // Call handler deposit as actor 0 with 1,000 tokens
        handler.deposit(1_000e18, 0);

        // Vault should have received tokens and minted shares
        assertGt(
            vault.totalSupply(),
            0,
            "Handler deposit should have minted shares"
        );

        // Ghost variable should track the deposit
        address actor0 = handler.actors(0);
        assertEq(
            handler.ghost_deposited(actor0),
            1_000e18,
            "Ghost variable should track deposited amount"
        );
    }

    // =========================================================
    //  TODO 3: Invariant — solvency
    // =========================================================
    /// @notice A vault with outstanding shares must hold tokens.
    /// @dev If totalSupply > 0 but the vault's token balance is 0,
    ///      shareholders are holding worthless shares — the vault
    ///      is insolvent.
    ///
    ///   Implementation:
    ///     uint256 supply = vault.totalSupply();
    ///     if (supply == 0) return;   // empty vault, nothing to check
    ///     assertGt(
    ///         token.balanceOf(address(vault)),
    ///         0,
    ///         "Solvency: vault with shares must hold tokens"
    ///     );
    ///
    /// See: Module 8 — "What Invariants to Test for Each DeFi Primitive"
    function invariant_solvency() public view {
        revert("Not implemented");
    }

    // =========================================================
    //  TODO 4: Invariant — no actor profits (fairness)
    // =========================================================
    /// @notice No actor should withdraw more than they deposited.
    /// @dev This vault has no yield mechanism, so any withdrawal
    ///      exceeding the deposit amount is a fairness violation —
    ///      one user is stealing from others.
    ///
    ///   Implementation:
    ///     for (uint256 i = 0; i < handler.actorCount(); i++) {
    ///         address actor = handler.actors(i);
    ///         uint256 withdrawn = handler.ghost_withdrawn(actor);
    ///         uint256 deposited = handler.ghost_deposited(actor);
    ///         assertLe(
    ///             withdrawn,
    ///             deposited,
    ///             "Fairness: actor withdrew more than deposited"
    ///         );
    ///     }
    ///
    /// See: Module 8 — "Quick Try: Invariant Testing Catches a Bug"
    function invariant_noActorProfits() public view {
        revert("Not implemented");
    }
}

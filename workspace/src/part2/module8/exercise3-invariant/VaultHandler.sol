// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BuggyVault} from "./BuggyVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
//  EXERCISE: VaultHandler — Handler Contract for Invariant Testing
// ============================================================================
//
//  A handler wraps protocol functions with bounded inputs and realistic
//  constraints. It tracks cumulative state via "ghost variables" that
//  enable invariant checks the protocol itself doesn't store.
//
//  The handler simulates multiple users (actors) interacting with the
//  vault in random sequences. Foundry's invariant fuzzer calls these
//  functions in random order with random inputs.
//
//  Your task: implement deposit() and withdraw() with:
//    - Actor selection via bound()
//    - Input bounding to realistic ranges
//    - Ghost variable tracking for per-actor deposits/withdrawals
//
//  Run:
//    forge test --match-contract BuggyVaultInvariantTest -vvv
//
// ============================================================================

/// @notice Handler contract for invariant testing BuggyVault.
/// @dev Exercise for Module 8: DeFi Security (Invariant Testing).
///      Students implement: deposit(), withdraw().
///      Pre-built: constructor, actor management, ghost variable declarations.
contract VaultHandler is Test {
    BuggyVault public vault;
    MockERC20 public token;

    /// @notice Pool of simulated users.
    address[] public actors;

    /// @notice Ghost variable: cumulative tokens deposited, per actor.
    mapping(address => uint256) public ghost_deposited;

    /// @notice Ghost variable: cumulative tokens withdrawn, per actor.
    mapping(address => uint256) public ghost_withdrawn;

    constructor(BuggyVault vault_, MockERC20 token_) {
        vault = vault_;
        token = token_;

        // Create 3 actors, each with 100,000 tokens and max approval
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            token.mint(actor, 100_000e18);
            vm.prank(actor);
            token.approve(address(vault), type(uint256).max);
        }
    }

    /// @notice Number of actors in the pool.
    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =============================================================
    //  TODO 1: Implement deposit — bounded deposit with ghost tracking
    // =============================================================
    /// @notice Deposit tokens into the vault as a random actor.
    /// @dev Foundry calls this with random amount and actorSeed.
    ///
    ///   Steps:
    ///     1. Select an actor using bound():
    ///        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
    ///
    ///     2. Check actor has tokens (skip if empty):
    ///        uint256 balance = token.balanceOf(actor);
    ///        if (balance == 0) return;
    ///
    ///     3. Bound amount to realistic range [1, balance]:
    ///        amount = bound(amount, 1, balance);
    ///
    ///     4. Prank as actor and deposit:
    ///        vm.prank(actor);
    ///        vault.deposit(amount);
    ///
    ///     5. Update ghost variable:
    ///        ghost_deposited[actor] += amount;
    ///
    /// See: Module 8 — "Handler Contracts"
    function deposit(uint256 amount, uint256 actorSeed) external {
        // TODO: implement
    }

    // =============================================================
    //  TODO 2: Implement withdraw — bounded withdraw with ghost tracking
    // =============================================================
    /// @notice Withdraw tokens from the vault as a random actor.
    /// @dev Track ACTUAL tokens received (balAfter - balBefore), not the
    ///      expected amount. This is critical — the bug causes the actual
    ///      amount to differ from the expected amount.
    ///
    ///   Steps:
    ///     1. Select an actor:
    ///        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
    ///
    ///     2. Bound shares to [0, actor's vault balance] (skip if 0):
    ///        uint256 bal = vault.balanceOf(actor);
    ///        shares = bound(shares, 0, bal);
    ///        if (shares == 0) return;
    ///
    ///     3. Record token balance before withdrawal:
    ///        uint256 balBefore = token.balanceOf(actor);
    ///
    ///     4. Prank as actor and withdraw:
    ///        vm.prank(actor);
    ///        vault.withdraw(shares);
    ///
    ///     5. Track ACTUAL tokens received (not calculated amount):
    ///        uint256 balAfter = token.balanceOf(actor);
    ///        ghost_withdrawn[actor] += (balAfter - balBefore);
    ///
    /// See: Module 8 — "Handler Contracts" + "Ghost Variables"
    function withdraw(uint256 shares, uint256 actorSeed) external {
        // TODO: implement
    }
}

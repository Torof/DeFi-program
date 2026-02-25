// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================
// EXERCISE: Vault Handler for Invariant Testing
//
// The Handler constrains how the fuzzer interacts with the vault. Without it,
// the fuzzer would call functions with completely random parameters that
// would almost always revert, making invariant testing useless.
//
// The Handler ensures that all function calls are valid while still exploring
// a wide range of states.
//
// Day 12: Master the Handler pattern for invariant testing.
// ============================================================================

import "forge-std/Test.sol";
import {SimpleVault} from "../../../../src/part1/module5/exercise1-simple-vault/SimpleVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// =============================================================
//  TODO 1: Implement VaultHandler
// =============================================================
/// @notice Handler contract that constrains fuzzer interactions with the vault.
/// @dev The fuzzer will call functions on this contract, which then calls the vault.
contract VaultHandler is Test {
    SimpleVault public vault;
    IERC20 public token;

    // Ghost variables to track cumulative operations
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_sharesSum;
    uint256 public ghost_yieldSum;

    // Actor management
    address[] public actors;
    mapping(address => bool) public isActor;

    modifier useActor(uint256 actorIndexSeed) {
        // TODO: Select an actor from the actors array using the seed
        // address actor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        // vm.startPrank(actor);
        _;
        // vm.stopPrank();
    }

    constructor(SimpleVault _vault, IERC20 _token) {
        vault = _vault;
        token = _token;

        // TODO: Create 3 actors and fund them with tokens
        // for (uint256 i = 0; i < 3; i++) {
        //     address actor = makeAddr(string(abi.encodePacked("actor", i)));
        //     actors.push(actor);
        //     isActor[actor] = true;
        //     // Fund actor with tokens
        //     deal(address(token), actor, 1_000_000e18);
        // }
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 2: Implement deposit handler
    // =============================================================
    /// @notice Handler for deposit operations.
    /// @param actorSeed Seed to select which actor performs the deposit
    /// @param assets Amount to deposit
    function deposit(uint256 actorSeed, uint256 assets) external useActor(actorSeed) {
        // TODO: Implement
        // 1. Bound assets to valid range (use `actor` from the modifier, NOT msg.sender):
        //    assets = bound(assets, 0, token.balanceOf(actor))
        //    Note: Allow 0 to test edge case, vault should revert
        // 2. If assets == 0, return early (vault will revert)
        // 3. Approve vault to spend tokens
        // 4. Try to deposit (use try/catch to handle reverts gracefully):
        //    try vault.deposit(assets) returns (uint256 shares) {
        //        ghost_depositSum += assets;
        //        ghost_sharesSum += shares;
        //    } catch {}
        revert("Not implemented");
    }

    // =============================================================
    //  TODO 3: Implement withdraw handler
    // =============================================================
    /// @notice Handler for withdraw operations.
    /// @param actorSeed Seed to select which actor performs the withdrawal
    /// @param shares Amount of shares to withdraw
    function withdraw(uint256 actorSeed, uint256 shares) external useActor(actorSeed) {
        // TODO: Implement
        // 1. Bound shares to valid range (use `actor` from the modifier, NOT msg.sender):
        //    shares = bound(shares, 0, vault.balanceOf(actor))
        // 2. If shares == 0, return early
        // 3. Try to withdraw:
        //    try vault.withdraw(shares) returns (uint256 assets) {
        //        ghost_withdrawSum += assets;
        //        ghost_sharesSum -= shares;
        //    } catch {}
        revert("Not implemented");
    }

    // =============================================================
    //  Helper: Force a yield event (for advanced testing)
    // =============================================================
    /// @notice Simulates vault earning yield by sending tokens directly.
    /// @param amount Amount of yield to add
    function addYield(uint256 amount) external {
        // TODO: Implement
        // 1. Bound amount: amount = bound(amount, 0, 1000e18)
        // 2. If amount == 0, return
        // 3. Deal tokens to vault: deal(address(token), address(vault), token.balanceOf(address(vault)) + amount)
        // 4. Track yield: ghost_yieldSum += amount
        // Note: This simulates external yield generation
        revert("Not implemented");
    }

    // =============================================================
    //  View Helpers
    // =============================================================

    /// @notice Returns number of actors.
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Returns total shares held by all actors.
    function getTotalActorShares() external view returns (uint256 total) {
        // TODO: Implement
        // Loop through actors and sum their balances:
        // for (uint256 i = 0; i < actors.length; i++) {
        //     total += vault.balanceOf(actors[i]);
        // }
        revert("Not implemented");
    }

    /// @notice Reduces handler to call summary (for Foundry's call summary feature).
    /// @dev Override this to see which functions were called during invariant testing.
    function callSummary() external view {
        console.log("------- Call Summary -------");
        console.log("Total deposits:", ghost_depositSum);
        console.log("Total withdrawals:", ghost_withdrawSum);
        console.log("Net shares:", ghost_sharesSum);
        console.log("Vault total supply:", vault.totalSupply());
        console.log("Vault total assets:", vault.totalAssets());
    }
}

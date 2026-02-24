// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the VaultDonationAttack
//  exercise. Implement VaultDonationAttack.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";

import {VaultDonationAttack} from "../../../src/part2/module5/VaultDonationAttack.sol";
import {NotPool, NotInitiator, NotOwner} from "../../../src/part2/module5/VaultDonationAttack.sol";
import {MockERC20} from "../../../src/part2/module5/mocks/MockERC20.sol";
import {MockFlashLoanPool} from "../../../src/part2/module5/mocks/MockFlashLoanPool.sol";
import {VulnerableVault} from "../../../src/part2/module5/mocks/VulnerableVault.sol";
import {YieldHarvester} from "../../../src/part2/module5/mocks/YieldHarvester.sol";

contract VaultDonationAttackTest is Test {
    MockERC20 usdc;
    MockFlashLoanPool flashPool;
    VulnerableVault vault;
    YieldHarvester harvester;
    VaultDonationAttack attack;

    address attacker = makeAddr("attacker");
    address alice = makeAddr("alice");

    /// @dev Flash pool has 100K USDC liquidity for flash loans.
    uint256 constant FLASH_POOL_LIQUIDITY = 100_000e6;

    /// @dev Harvester holds 5,000 USDC of pending yield (the victim's funds).
    uint256 constant HARVESTER_PENDING = 5_000e6;

    /// @dev Attacker borrows 10,000 USDC (must exceed harvester's balance).
    uint256 constant BORROW_AMOUNT = 10_000e6;

    /// @dev Flash loan premium: 0.05% (5 bps).
    uint128 constant FLASH_PREMIUM_BPS = 5;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        flashPool = new MockFlashLoanPool();
        vault = new VulnerableVault(address(usdc));
        harvester = new YieldHarvester(address(usdc), address(vault));

        // Fund flash pool with liquidity
        usdc.mint(address(flashPool), FLASH_POOL_LIQUIDITY);

        // Fund harvester with pending yield (the target)
        usdc.mint(address(harvester), HARVESTER_PENDING);

        // Deploy attack contract as attacker
        vm.prank(attacker);
        attack = new VaultDonationAttack(address(flashPool));
    }

    // =========================================================
    //  Happy Path
    // =========================================================

    function test_DonationAttack_HappyPath() public {
        // Attack: flash borrow 10K → deposit 1 → donate 9,999.999999
        //         → harvest → withdraw → repay → profit
        //
        // Step-by-step math:
        //   1. Deposit 1 wei → 1 share (first depositor, 1:1)
        //   2. Donate 9,999,999,999 → vault has 10,000,000,000, 1 share
        //      Share price: 10,000,000,000 / 1 = 10 billion per share
        //   3. Harvester deposits 5,000,000,000 USDC
        //      → shares = 5,000,000,000 * 1 / 10,000,000,000 = 0 (rounds down!)
        //      → vault has 15,000,000,000 USDC, still 1 share
        //   4. Withdraw 1 share → get 15,000,000,000 USDC
        //   5. Repay flash loan: 10,000,000,000 + 5,000,000 = 10,005,000,000
        //   6. Profit: 15,000,000,000 - 10,005,000,000 = 4,995,000,000
        //      ≈ $4,995 USDC (victim's 5K minus 5 USDC premium)

        uint256 expectedProfit = 4_995e6;  // 4,995 USDC
        uint256 expectedPremium = 5e6;     // 5 USDC

        uint256 attackerBefore = usdc.balanceOf(attacker);
        uint256 flashPoolBefore = usdc.balanceOf(address(flashPool));

        vm.prank(attacker);
        attack.executeAttack(
            address(usdc),
            BORROW_AMOUNT,
            address(vault),
            address(harvester)
        );

        // --- Attacker profits ---
        assertEq(
            usdc.balanceOf(attacker) - attackerBefore,
            expectedProfit,
            "Attacker should profit ~4,995 USDC (victim's 5K minus 5 USDC premium)"
        );

        // --- Victim lost everything ---
        assertEq(
            usdc.balanceOf(address(harvester)),
            0,
            "Harvester should have 0 USDC (all funds deposited into inflated vault)"
        );
        assertEq(
            vault.sharesOf(address(harvester)),
            0,
            "Harvester should have 0 vault shares (deposit rounded to 0)"
        );

        // --- Vault is empty ---
        assertEq(
            vault.totalShares(),
            0,
            "Vault should have 0 total shares (attacker withdrew everything)"
        );
        assertEq(
            vault.totalAssets(),
            0,
            "Vault should have 0 total assets"
        );

        // --- Attack contract holds nothing ---
        assertEq(
            usdc.balanceOf(address(attack)),
            0,
            "Attack contract should have 0 balance (never store funds)"
        );

        // --- Flash pool gained premium ---
        assertEq(
            usdc.balanceOf(address(flashPool)) - flashPoolBefore,
            expectedPremium,
            "Flash pool should gain exactly 5 USDC premium"
        );
    }

    // =========================================================
    //  Access Control
    // =========================================================

    function test_ExecuteAttack_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(NotOwner.selector);
        attack.executeAttack(
            address(usdc),
            BORROW_AMOUNT,
            address(vault),
            address(harvester)
        );
    }

    // =========================================================
    //  Security: Callback Validation
    // =========================================================

    function test_ExecuteOperation_RevertWhen_CallerNotPool() public {
        vm.prank(alice);
        vm.expectRevert(NotPool.selector);
        attack.executeOperation(
            address(usdc),
            BORROW_AMOUNT,
            5e6,
            address(attack),
            ""
        );
    }

    function test_ExecuteOperation_RevertWhen_WrongInitiator() public {
        vm.prank(address(flashPool));
        vm.expectRevert(NotInitiator.selector);
        attack.executeOperation(
            address(usdc),
            BORROW_AMOUNT,
            5e6,
            attacker, // wrong initiator — should be the contract itself
            ""
        );
    }
}

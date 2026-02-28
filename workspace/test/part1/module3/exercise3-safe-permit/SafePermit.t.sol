// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    SafePermitVault,
    NonPermitToken,
    InsufficientAllowance,
    TransferFailed,
    PermitPhishingDemo
} from "../../../../src/part1/module3/exercise3-safe-permit/SafePermit.sol";
import {PermitToken, IERC20Permit} from "../../../../src/part1/module3/exercise1-permit-vault/PermitVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests for Safe Permit wrapper exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module3/SafePermit.sol instead.
contract SafePermitTest is Test {
    SafePermitVault vault;
    PermitToken permitToken;
    NonPermitToken nonPermitToken;

    address alice;
    uint256 alicePrivateKey;

    address bob;
    uint256 bobPrivateKey;

    address frontRunner;

    function setUp() public {
        vault = new SafePermitVault();
        permitToken = new PermitToken();
        nonPermitToken = new NonPermitToken();

        // Create test users
        alicePrivateKey = 0xA11CE;
        alice = vm.addr(alicePrivateKey);

        bobPrivateKey = 0xB0B;
        bob = vm.addr(bobPrivateKey);

        frontRunner = makeAddr("frontRunner");

        // Mint tokens
        permitToken.mint(alice, 100_000 * 1e18);
        nonPermitToken.mint(alice, 100_000 * 1e18);
    }

    // =========================================================
    //  Normal Permit Deposit Tests
    // =========================================================

    function test_SafeDepositWithPermit_Success() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            depositAmount,
            deadline
        );

        vm.prank(alice);
        vault.safeDepositWithPermit(address(permitToken), depositAmount, deadline, v, r, s);

        assertEq(vault.getBalance(alice, address(permitToken)), depositAmount, "Deposit successful");
    }

    // =========================================================
    //  Front-Running Protection Tests
    // =========================================================

    function test_SafeDepositWithPermit_HandlesFrontRun() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Alice signs a permit
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            depositAmount,
            deadline
        );

        // Front-runner extracts the signature from mempool and uses it first
        vm.prank(frontRunner);
        permitToken.permit(alice, address(vault), depositAmount, deadline, v, r, s);

        // Alice's transaction still succeeds because safeDepositWithPermit
        // checks allowance when permit fails
        vm.prank(alice);
        vault.safeDepositWithPermit(address(permitToken), depositAmount, deadline, v, r, s);

        assertEq(vault.getBalance(alice, address(permitToken)), depositAmount, "Deposit works despite front-run");
    }

    function test_SafeDepositWithPermit_RevertOnNoAllowanceAfterPermitFail() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Sign permit with wrong amount
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            depositAmount,
            deadline
        );

        // Permit will fail (amount mismatch → invalid signer), and there's no allowance
        vm.prank(alice);
        vm.expectRevert(InsufficientAllowance.selector);
        vault.safeDepositWithPermit(address(permitToken), depositAmount + 1, deadline, v, r, s);
    }

    // =========================================================
    //  Fallback to Standard Approve Tests
    // =========================================================

    function test_DepositWithFallback_PermitToken() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            depositAmount,
            deadline
        );

        vm.prank(alice);
        vault.depositWithFallback(address(permitToken), depositAmount, deadline, v, r, s, true);

        assertEq(vault.getBalance(alice, address(permitToken)), depositAmount, "Deposit with permit");
    }

    function test_DepositWithFallback_NonPermitToken() public {
        uint256 depositAmount = 1000 * 1e18;

        // Alice approves the vault (standard approve)
        vm.prank(alice);
        nonPermitToken.approve(address(vault), depositAmount);

        // Deposit without using permit (usePermit = false)
        vm.prank(alice);
        vault.depositWithFallback(
            address(nonPermitToken),
            depositAmount,
            0, // deadline (ignored)
            0, // v (ignored)
            0, // r (ignored)
            0, // s (ignored)
            false // don't attempt permit
        );

        assertEq(vault.getBalance(alice, address(nonPermitToken)), depositAmount, "Deposit without permit");
    }

    function test_DepositWithFallback_NonPermitTokenAutoDetect() public {
        uint256 depositAmount = 1000 * 1e18;

        // Alice approves the vault
        vm.prank(alice);
        nonPermitToken.approve(address(vault), depositAmount);

        // Try to use permit (will fail), should fall back to allowance
        vm.prank(alice);
        vault.depositWithFallback(
            address(nonPermitToken),
            depositAmount,
            block.timestamp + 1 hours,
            0, 0, 0, // Invalid signature
            true // attempt permit
        );

        assertEq(vault.getBalance(alice, address(nonPermitToken)), depositAmount, "Fallback to approve");
    }

    // =========================================================
    //  Helper Function Tests
    // =========================================================

    function test_TryPermit_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            amount,
            deadline
        );

        bool success = vault.tryPermit(
            address(permitToken),
            alice,
            address(vault),
            amount,
            deadline,
            v, r, s
        );

        assertTrue(success, "tryPermit should succeed");
    }

    function test_TryPermit_Failure() public {
        // Invalid signature
        bool success = vault.tryPermit(
            address(permitToken),
            alice,
            address(vault),
            1000 * 1e18,
            block.timestamp + 1 hours,
            0, 0, 0 // Invalid signature
        );

        assertFalse(success, "tryPermit should fail with invalid signature");
    }

    function test_SupportsPermit_PermitToken() public view {
        bool supported = vault.supportsPermit(address(permitToken));
        assertTrue(supported, "PermitToken should support permit");
    }

    function test_SupportsPermit_NonPermitToken() public view {
        bool supported = vault.supportsPermit(address(nonPermitToken));
        assertFalse(supported, "NonPermitToken should not support permit");
    }

    function test_SupportsPermit_EOA() public view {
        bool supported = vault.supportsPermit(alice);
        assertFalse(supported, "EOA should not support permit");
    }

    // =========================================================
    //  Withdrawal Tests
    // =========================================================

    function test_Withdraw() public {
        // Deposit first
        uint256 depositAmount = 1000 * 1e18;
        vm.prank(alice);
        permitToken.approve(address(vault), depositAmount);

        vm.prank(alice);
        // Deposit via fallback without permit
        vault.depositWithFallback(address(permitToken), depositAmount, 0, 0, 0, 0, false);

        // Withdraw
        uint256 aliceBalanceBefore = permitToken.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(address(permitToken), 500 * 1e18);

        assertEq(vault.getBalance(alice, address(permitToken)), 500 * 1e18, "Remaining balance");
        assertEq(permitToken.balanceOf(alice), aliceBalanceBefore + 500 * 1e18, "Alice received tokens");
    }

    // =========================================================
    //  Integration Tests
    // =========================================================

    function test_MixedTokenTypes() public {
        uint256 permitAmount = 1000 * 1e18;
        uint256 nonPermitAmount = 500 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Deposit permit token
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            permitAmount,
            deadline
        );
        vm.prank(alice);
        vault.safeDepositWithPermit(address(permitToken), permitAmount, deadline, v, r, s);

        // Deposit non-permit token (approve first)
        vm.prank(alice);
        nonPermitToken.approve(address(vault), nonPermitAmount);
        vm.prank(alice);
        vault.depositWithFallback(address(nonPermitToken), nonPermitAmount, 0, 0, 0, 0, false);

        assertEq(vault.getBalance(alice, address(permitToken)), permitAmount, "Permit token balance");
        assertEq(vault.getBalance(alice, address(nonPermitToken)), nonPermitAmount, "Non-permit token balance");
    }

    function test_FrontRunScenario_RealWorld() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Alice signs permit
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            address(vault),
            depositAmount,
            deadline
        );

        // Simulate front-runner seeing the permit in mempool
        // Front-runner calls permit directly (stealing the signature)
        vm.prank(frontRunner);
        permitToken.permit(alice, address(vault), depositAmount, deadline, v, r, s);

        // Alice's transaction is next (permit already consumed)
        // But safeDepositWithPermit handles this gracefully
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit SafePermitVault.FallbackToApprove(alice, address(permitToken));
        vault.safeDepositWithPermit(address(permitToken), depositAmount, deadline, v, r, s);

        // Deposit should still succeed
        assertEq(vault.getBalance(alice, address(permitToken)), depositAmount, "Deposit succeeded despite front-run");
    }

    // =========================================================
    //  Phishing Demonstration
    // =========================================================

    function test_PhishingAttack_Demonstration() public {
        // EDUCATIONAL: This demonstrates how permit phishing works.
        // The attack vector: a malicious website tricks Alice into signing
        // a permit where the spender is the attacker, not a legitimate vault.

        PermitPhishingDemo phishingContract = new PermitPhishingDemo(frontRunner);

        // Step 1: Attacker's fake website asks Alice to sign a "deposit" permit.
        // The UI shows "Approve deposit to Vault" but the actual spender is the attacker.
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            alicePrivateKey,
            address(permitToken),
            frontRunner, // <-- The spender is the ATTACKER, not the vault!
            1000 * 1e18,
            block.timestamp + 1 hours
        );

        // Step 2: Alice calls the phishing contract's "fakeDeposit"
        vm.prank(alice);
        phishingContract.fakeDeposit(
            address(permitToken), 1000 * 1e18, block.timestamp + 1 hours, v, r, s
        );

        // Step 3: Attacker now has allowance and drains Alice's tokens
        uint256 allowance = permitToken.allowance(alice, frontRunner);
        assertEq(allowance, 1000 * 1e18, "Attacker has allowance from phishing");

        vm.prank(frontRunner);
        permitToken.transferFrom(alice, frontRunner, 1000 * 1e18);
        assertEq(permitToken.balanceOf(frontRunner), 1000 * 1e18, "Attacker stole tokens via phishing");

        // LESSON: Wallet UIs MUST clearly display the spender address.
        // If "spender" doesn't match the expected protocol address, DON'T sign.
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_SafeDepositWithPermit(uint256 depositAmount) public {
        // Bound to reasonable range
        depositAmount = bound(depositAmount, 1, 100_000 * 1e18);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice, alicePrivateKey, address(permitToken), address(vault), depositAmount, deadline
        );

        vm.prank(alice);
        vault.safeDepositWithPermit(address(permitToken), depositAmount, deadline, v, r, s);

        assertEq(vault.getBalance(alice, address(permitToken)), depositAmount, "Deposit should match");
    }

    // =========================================================
    //  Helper Functions
    // =========================================================

    function _signPermit(
        address owner,
        uint256 ownerPrivateKey,
        address token,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        PermitToken permitTkn = PermitToken(token);

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                permitTkn.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permitTkn.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (v, r, s) = vm.sign(ownerPrivateKey, digest);
    }
}

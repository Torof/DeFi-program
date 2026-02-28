// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    Permit2Vault,
    IPermit2,
    ISignatureTransfer,
    IAllowanceTransfer,
    InsufficientBalance,
    TransferFailed,
    InvalidWitnessData
} from "../../../../src/part1/module3/exercise2-permit2-vault/Permit2Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests for Permit2 integration exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module3/Permit2Vault.sol instead.
/// @dev Requires mainnet fork: forge test --match-contract Permit2VaultTest --fork-url $MAINNET_RPC_URL
contract Permit2VaultTest is Test {
    // Deployed Permit2 address on mainnet
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Using USDC as test token (has sufficient liquidity)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IPermit2 permit2;
    Permit2Vault vault;
    IERC20 usdc;

    address alice;
    uint256 alicePrivateKey;

    // Pinned block for reproducible fork tests (Jan 2024, well after Permit2 deployment)
    uint256 constant FORK_BLOCK = 19_000_000;

    function setUp() public {
        // Fork mainnet at a pinned block for deterministic results.
        // Set MAINNET_RPC_URL in your environment (e.g. from Alchemy, Infura, or a local node).
        // The demo URL below may be rate-limited or unavailable — get your own free key:
        //   Alchemy: https://www.alchemy.com/ | Infura: https://www.infura.io/
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth-mainnet.g.alchemy.com/v2/demo"));
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        // Get deployed Permit2 contract
        permit2 = IPermit2(PERMIT2_ADDRESS);

        // Deploy our vault
        vault = new Permit2Vault(PERMIT2_ADDRESS);

        // Setup test accounts
        alicePrivateKey = 0xA11CE;
        alice = vm.addr(alicePrivateKey);

        // Get USDC instance
        usdc = IERC20(USDC);

        // Use Foundry's deal cheatcode to set USDC balance directly
        // (avoids depending on a whale address that may change over time)
        uint256 testAmount = 10_000 * 1e6; // 10,000 USDC (6 decimals)
        deal(address(usdc), alice, testAmount);

        // Alice approves Permit2 (one-time approval for all future permits)
        vm.prank(alice);
        usdc.approve(PERMIT2_ADDRESS, type(uint256).max);
    }

    // =========================================================
    //  SignatureTransfer Tests
    // =========================================================

    function test_DepositWithSignatureTransfer() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        // Build and sign the permit
        bytes memory signature = _signPermitTransferFrom(
            alice,
            alicePrivateKey,
            address(usdc),
            depositAmount,
            nonce,
            deadline
        );

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        // Deposit via SignatureTransfer
        vm.prank(alice);
        vault.depositWithSignatureTransfer(
            address(usdc),
            depositAmount,
            nonce,
            deadline,
            signature
        );

        assertEq(vault.getBalance(alice, address(usdc)), depositAmount, "Vault balance");
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore - depositAmount, "Alice balance decreased");
        assertEq(usdc.balanceOf(address(vault)), depositAmount, "Vault holds tokens");
    }

    function test_SignatureTransfer_MultipleDepositsWithDifferentNonces() public {
        uint256 deadline = block.timestamp + 1 hours;

        // First deposit with nonce 0
        // Note: Permit2 uses BITMAP nonces, not sequential nonces like EIP-2612.
        // Nonce 0 = word 0, bit 0. Nonce 1 = word 0, bit 1. They're independent bits
        // in the same 256-bit word, so they can be consumed in ANY order.
        bytes memory sig1 = _signPermitTransferFrom(alice, alicePrivateKey, address(usdc), 1000 * 1e6, 0, deadline);
        vm.prank(alice);
        vault.depositWithSignatureTransfer(address(usdc), 1000 * 1e6, 0, deadline, sig1);

        // Second deposit with nonce 1 (different bit in same bitmap word — works independently)
        bytes memory sig2 = _signPermitTransferFrom(alice, alicePrivateKey, address(usdc), 500 * 1e6, 1, deadline);
        vm.prank(alice);
        vault.depositWithSignatureTransfer(address(usdc), 500 * 1e6, 1, deadline, sig2);

        assertEq(vault.getBalance(alice, address(usdc)), 1500 * 1e6, "Total deposited");
    }

    function test_SignatureTransfer_RevertOnReusedNonce() public {
        uint256 depositAmount = 1000 * 1e6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermitTransferFrom(
            alice,
            alicePrivateKey,
            address(usdc),
            depositAmount,
            nonce,
            deadline
        );

        // First deposit succeeds
        vm.prank(alice);
        vault.depositWithSignatureTransfer(address(usdc), depositAmount, nonce, deadline, signature);

        // Reusing the same nonce should fail
        vm.prank(alice);
        vm.expectRevert(); // Permit2 reverts on used nonce
        vault.depositWithSignatureTransfer(address(usdc), depositAmount, nonce, deadline, signature);
    }

    // =========================================================
    //  SignatureTransfer with Witness Tests
    // =========================================================

    function test_DepositWithSignatureTransferWitness() public {
        uint256 depositAmount = 1000 * 1e6;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 depositId = 12345; // Specific deposit identifier

        bytes memory signature = _signPermitWitnessTransferFrom(
            alice,
            alicePrivateKey,
            address(usdc),
            depositAmount,
            nonce,
            deadline,
            depositId
        );

        vm.prank(alice);
        vault.depositWithSignatureTransferWitness(
            address(usdc),
            depositAmount,
            nonce,
            deadline,
            depositId,
            signature
        );

        assertEq(vault.getBalance(alice, address(usdc)), depositAmount, "Deposit with witness successful");
    }

    function test_SignatureTransferWitness_DifferentDepositIds() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Deposit 1 with depositId = 100
        bytes memory sig1 = _signPermitWitnessTransferFrom(
            alice, alicePrivateKey, address(usdc), 1000 * 1e6, 0, deadline, 100
        );
        vm.prank(alice);
        vault.depositWithSignatureTransferWitness(address(usdc), 1000 * 1e6, 0, deadline, 100, sig1);

        // Deposit 2 with depositId = 200
        bytes memory sig2 = _signPermitWitnessTransferFrom(
            alice, alicePrivateKey, address(usdc), 500 * 1e6, 1, deadline, 200
        );
        vm.prank(alice);
        vault.depositWithSignatureTransferWitness(address(usdc), 500 * 1e6, 1, deadline, 200, sig2);

        assertEq(vault.getBalance(alice, address(usdc)), 1500 * 1e6, "Multiple witness deposits");
    }

    // =========================================================
    //  AllowanceTransfer Tests
    // =========================================================

    function test_PermitAndDepositWithAllowanceTransfer() public {
        uint160 allowanceAmount = 5000 * 1e6; // 5000 USDC allowance
        uint48 expiration = uint48(block.timestamp + 7 days);
        uint48 nonce = 0;
        uint256 sigDeadline = block.timestamp + 1 hours;
        uint160 depositAmount = 1000 * 1e6; // Deposit 1000 from the 5000 allowance

        bytes memory signature = _signPermitAllowance(
            alice,
            alicePrivateKey,
            address(usdc),
            allowanceAmount,
            expiration,
            nonce,
            sigDeadline
        );

        vm.prank(alice);
        vault.permitAndDepositWithAllowanceTransfer(
            address(usdc),
            allowanceAmount,
            expiration,
            nonce,
            sigDeadline,
            signature,
            depositAmount
        );

        assertEq(vault.getBalance(alice, address(usdc)), depositAmount, "Deposit successful");
    }

    function test_AllowanceTransfer_MultipleDepositsFromSameAllowance() public {
        uint160 allowanceAmount = 5000 * 1e6;
        uint48 expiration = uint48(block.timestamp + 7 days);
        uint48 nonce = 0;
        uint256 sigDeadline = block.timestamp + 1 hours;

        // Set allowance via permit
        bytes memory signature = _signPermitAllowance(
            alice, alicePrivateKey, address(usdc), allowanceAmount, expiration, nonce, sigDeadline
        );
        vm.prank(alice);
        vault.permitAndDepositWithAllowanceTransfer(
            address(usdc), allowanceAmount, expiration, nonce, sigDeadline, signature, 1000 * 1e6
        );

        // Make additional deposits using the allowance (no new signature needed)
        vm.prank(alice);
        vault.depositWithAllowanceTransfer(address(usdc), 500 * 1e6);

        vm.prank(alice);
        vault.depositWithAllowanceTransfer(address(usdc), 300 * 1e6);

        assertEq(vault.getBalance(alice, address(usdc)), 1800 * 1e6, "Multiple deposits from allowance");
    }

    // =========================================================
    //  Withdrawal Tests
    // =========================================================

    function test_WithdrawAfterSignatureTransferDeposit() public {
        // Deposit
        uint256 depositAmount = 2000 * 1e6;
        bytes memory signature = _signPermitTransferFrom(
            alice, alicePrivateKey, address(usdc), depositAmount, 0, block.timestamp + 1 hours
        );
        vm.prank(alice);
        vault.depositWithSignatureTransfer(address(usdc), depositAmount, 0, block.timestamp + 1 hours, signature);

        // Withdraw
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(address(usdc), 1000 * 1e6);

        assertEq(vault.getBalance(alice, address(usdc)), 1000 * 1e6, "Remaining balance");
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + 1000 * 1e6, "Alice received withdrawal");
    }

    function test_RevertWithdrawInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(InsufficientBalance.selector);
        vault.withdraw(address(usdc), 100 * 1e6);
    }

    // =========================================================
    //  Gas Comparison
    // =========================================================

    function test_GasComparison_Permit2VsTraditional() public {
        uint256 depositAmount = 1000 * 1e6;

        // Traditional approach requires TWO on-chain transactions:
        //   Tx 1: approve()        → ~46,000 gas (21k base + ~25k execution)
        //   Tx 2: vault.deposit()  → vault-specific gas
        // With Permit2, the user only pays for ONE transaction (signature is free/off-chain).

        // Measure Permit2 SignatureTransfer deposit gas
        bytes memory signature = _signPermitTransferFrom(
            alice, alicePrivateKey, address(usdc), depositAmount, 0, block.timestamp + 1 hours
        );
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        vault.depositWithSignatureTransfer(address(usdc), depositAmount, 0, block.timestamp + 1 hours, signature);
        uint256 gasUsed = gasBefore - gasleft();

        // The key insight: Permit2 eliminates the approve transaction entirely.
        // The signature is created off-chain (free), so the user only pays for the
        // deposit tx. Traditional approve+deposit requires ~46k extra gas for the
        // separate approve transaction.
        assertGt(gasUsed, 0, "Gas should be measured");
        assertEq(vault.getBalance(alice, address(usdc)), depositAmount, "Deposit succeeded");
    }

    // =========================================================
    //  Helper Functions: Signature Generation
    // =========================================================

    function _signPermitTransferFrom(
        address, /* owner — unused, Permit2 recovers it from the signature */
        uint256 ownerPrivateKey,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );
        bytes32 TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

        bytes32 tokenPermissions = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, token, amount));
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, address(vault), nonce, deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signPermitWitnessTransferFrom(
        address, /* owner */
        uint256 ownerPrivateKey,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 depositId
    ) internal view returns (bytes memory) {
        // witnessTypeString completes Permit2's STUB:
        // STUB = "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,"
        // Full EIP-712 type = STUB + witnessTypeString
        // Format: "<WitnessType> <fieldName>)<WitnessTypeDef><TokenPermissionsTypeDef>"
        string memory witnessTypeString = "Deposit witness)Deposit(uint256 depositId)TokenPermissions(address token,uint256 amount)";
        bytes32 witness = keccak256(abi.encode(keccak256("Deposit(uint256 depositId)"), depositId));

        bytes32 PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH = keccak256(
            abi.encodePacked(
                "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
                witnessTypeString
            )
        );
        bytes32 TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

        bytes32 tokenPermissions = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, token, amount));
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH, tokenPermissions, address(vault), nonce, deadline, witness)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signPermitAllowance(
        address, /* owner */
        uint256 ownerPrivateKey,
        address token,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 sigDeadline
    ) internal view returns (bytes memory) {
        bytes32 PERMIT_DETAILS_TYPEHASH = keccak256(
            "PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );
        bytes32 PERMIT_SINGLE_TYPEHASH = keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

        bytes32 permitDetails = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, token, amount, expiration, nonce));
        bytes32 structHash = keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, permitDetails, address(vault), sigDeadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

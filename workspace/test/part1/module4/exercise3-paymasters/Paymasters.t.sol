// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    VerifyingPaymaster,
    ERC20Paymaster,
    MockToken,
    InvalidSignature,
    InsufficientTokenBalance,
    TransferFailed,
    IPaymaster
} from "../../../../src/part1/module4/exercise3-paymasters/Paymasters.sol";
import {UserOperation, UserOpHelper, MockEntryPoint} from "../../../../src/part1/module4/exercise1-simple-smart-account/SimpleSmartAccount.sol";

/// @notice Tests for Paymasters exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module4/Paymasters.sol instead.
contract PaymastersTest is Test {
    MockEntryPoint entryPoint;
    VerifyingPaymaster verifyingPaymaster;
    ERC20Paymaster erc20Paymaster;
    MockToken token;

    address verifyingSigner;
    uint256 signerPrivateKey;

    address user;

    uint256 constant TOKEN_TO_ETH_RATE = 2000 * 1e18; // 2000 tokens per 1 ETH

    function setUp() public {
        entryPoint = new MockEntryPoint();

        signerPrivateKey = 0x5161;
        verifyingSigner = vm.addr(signerPrivateKey);

        user = makeAddr("user");

        verifyingPaymaster = new VerifyingPaymaster(address(entryPoint), verifyingSigner);

        token = new MockToken();
        erc20Paymaster = new ERC20Paymaster(address(entryPoint), address(token), TOKEN_TO_ETH_RATE);

        // Fund paymasters
        vm.deal(address(verifyingPaymaster), 10 ether);
        vm.deal(address(erc20Paymaster), 10 ether);

        // Give user tokens
        token.mint(user, 100_000 * 1e18);
    }

    // =========================================================
    //  VerifyingPaymaster Tests
    // =========================================================

    function test_VerifyingPaymaster_ValidSignature() public {
        UserOperation memory userOp = _createUserOp(user);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 0.01 ether;

        // Sign for paymaster
        bytes32 hash = keccak256(abi.encode(userOpHash, maxCost));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        userOp.paymasterAndData = abi.encodePacked(address(verifyingPaymaster), signature);

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = verifyingPaymaster.validatePaymasterUserOp(
            userOp, userOpHash, maxCost
        );

        assertEq(validationData, 0, "Should validate successfully");
    }

    function test_VerifyingPaymaster_InvalidSignature() public {
        UserOperation memory userOp = _createUserOp(user);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 0.01 ether;

        // Sign with wrong key
        bytes32 hash = keccak256(abi.encode(userOpHash, maxCost));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        userOp.paymasterAndData = abi.encodePacked(address(verifyingPaymaster), signature);

        vm.prank(address(entryPoint));
        vm.expectRevert(InvalidSignature.selector);
        verifyingPaymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    // =========================================================
    //  ERC20Paymaster Tests
    // =========================================================

    function test_ERC20Paymaster_ValidateWithSufficientTokens() public {
        UserOperation memory userOp = _createUserOp(user);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 0.01 ether;

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = erc20Paymaster.validatePaymasterUserOp(
            userOp, userOpHash, maxCost
        );

        assertEq(validationData, 0, "Should validate");
        (address sender, uint256 maxTokens) = abi.decode(context, (address, uint256));
        assertEq(sender, user, "Context should contain user address");
        uint256 expectedTokens = (maxCost * TOKEN_TO_ETH_RATE) / 1e18;
        assertEq(maxTokens, expectedTokens, "Token amount should match formula: (maxCost * rate) / 1e18");
    }

    function test_ERC20Paymaster_RevertInsufficientTokens() public {
        address poorUser = makeAddr("poorUser");
        UserOperation memory userOp = _createUserOp(poorUser);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 100 ether; // Requires more tokens than user has

        vm.prank(address(entryPoint));
        vm.expectRevert(InsufficientTokenBalance.selector);
        erc20Paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function test_ERC20Paymaster_PostOp() public {
        UserOperation memory userOp = _createUserOp(user);
        uint256 maxCost = 0.01 ether;
        uint256 requiredTokens = (maxCost * TOKEN_TO_ETH_RATE) / 1e18;

        bytes memory context = abi.encode(user, requiredTokens);
        uint256 actualGasCost = 0.005 ether;

        // User approves paymaster to spend tokens
        vm.prank(user);
        token.approve(address(erc20Paymaster), requiredTokens);

        uint256 userBalanceBefore = token.balanceOf(user);

        vm.prank(address(entryPoint));
        erc20Paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost, 0);

        uint256 userBalanceAfter = token.balanceOf(user);
        uint256 actualTokenCost = (actualGasCost * TOKEN_TO_ETH_RATE) / 1e18;

        assertEq(userBalanceBefore - userBalanceAfter, actualTokenCost, "Tokens should be charged");
    }

    function test_ERC20Paymaster_PostOp_DifferentGasCosts() public {
        uint256 maxCost = 0.01 ether;
        uint256 requiredTokens = (maxCost * TOKEN_TO_ETH_RATE) / 1e18;
        bytes memory context = abi.encode(user, requiredTokens);

        // User approves paymaster
        vm.prank(user);
        token.approve(address(erc20Paymaster), requiredTokens);

        // Actual gas cost is less than max
        uint256 actualGasCost = 0.002 ether;
        uint256 expectedTokenCost = (actualGasCost * TOKEN_TO_ETH_RATE) / 1e18;

        uint256 userBalanceBefore = token.balanceOf(user);

        vm.prank(address(entryPoint));
        erc20Paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost, 0);

        uint256 charged = userBalanceBefore - token.balanceOf(user);
        assertEq(charged, expectedTokenCost, "Should charge based on actual gas, not max");
        assertLt(charged, requiredTokens, "Actual charge should be less than max");
    }

    function test_ERC20Paymaster_PostOp_OpReverted() public {
        // Even if the UserOp execution reverts, postOp should still charge
        uint256 maxCost = 0.01 ether;
        uint256 requiredTokens = (maxCost * TOKEN_TO_ETH_RATE) / 1e18;
        bytes memory context = abi.encode(user, requiredTokens);
        uint256 actualGasCost = 0.005 ether;

        vm.prank(user);
        token.approve(address(erc20Paymaster), requiredTokens);

        uint256 userBalanceBefore = token.balanceOf(user);

        // PostOpMode.opReverted — execution failed, but paymaster still charges
        vm.prank(address(entryPoint));
        erc20Paymaster.postOp(IPaymaster.PostOpMode.opReverted, context, actualGasCost, 0);

        uint256 actualTokenCost = (actualGasCost * TOKEN_TO_ETH_RATE) / 1e18;
        assertEq(userBalanceBefore - token.balanceOf(user), actualTokenCost, "Should charge even on opReverted");
    }

    // =========================================================
    //  Helper Functions
    // =========================================================

    function _createUserOp(address sender) internal pure returns (UserOperation memory) {
        return UserOpHelper.createUserOp(sender, 0, "", "");
    }
}

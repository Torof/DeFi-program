// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    SimpleSmartAccount,
    MockEntryPoint,
    UserOperation,
    UserOpHelper,
    NotEntryPoint,
    NotOwner,
    InvalidSignature,
    CallFailed
} from "../../../../src/part1/module4/exercise1-simple-smart-account/SimpleSmartAccount.sol";

/// @notice Tests for Simple Smart Account (ERC-4337) exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module4/SimpleSmartAccount.sol instead.
contract SimpleSmartAccountTest is Test {
    MockEntryPoint entryPoint;
    SimpleSmartAccount account;

    address owner;
    uint256 ownerPrivateKey;

    address user;

    MockTarget target;

    function setUp() public {
        // Create owner with known private key
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        user = makeAddr("user");

        // Deploy EntryPoint and Account
        entryPoint = new MockEntryPoint();
        account = new SimpleSmartAccount(address(entryPoint), owner);

        // Deploy mock target for testing executions
        target = new MockTarget();

        // Fund account with ETH
        vm.deal(address(account), 10 ether);
        vm.deal(owner, 10 ether);
    }

    // =========================================================
    //  Initialization Tests
    // =========================================================

    function test_Initialization() public view {
        assertEq(account.owner(), owner, "Owner should be set");
        assertEq(account.entryPoint(), address(entryPoint), "EntryPoint should be set");
        assertEq(account.nonce(), 0, "Nonce should start at 0");
    }

    // =========================================================
    //  Signature Validation Tests
    // =========================================================

    function test_ValidateUserOp_ValidSignature() public {
        bytes memory callData = abi.encodeWithSelector(
            SimpleSmartAccount.execute.selector,
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 42)
        );

        UserOperation memory userOp = UserOpHelper.createUserOp(
            address(account),
            0,
            callData,
            ""
        );

        // Sign the userOp
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes memory signature = _signUserOp(userOpHash, ownerPrivateKey);
        userOp.signature = signature;

        // Validate from EntryPoint
        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0, "Validation should succeed");
    }

    function test_ValidateUserOp_InvalidSignature() public {
        UserOperation memory userOp = UserOpHelper.createUserOp(
            address(account),
            0,
            "",
            ""
        );

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Sign with wrong private key
        uint256 wrongKey = 0xBAD;
        bytes memory signature = _signUserOp(userOpHash, wrongKey);
        userOp.signature = signature;

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1, "Validation should fail (SIG_VALIDATION_FAILED)");
    }

    function test_ValidateUserOp_RevertNotEntryPoint() public {
        UserOperation memory userOp = UserOpHelper.createUserOp(address(account), 0, "", "");
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Try to call validateUserOp directly (not from EntryPoint)
        vm.prank(user);
        vm.expectRevert(NotEntryPoint.selector);
        account.validateUserOp(userOp, userOpHash, 0);
    }

    // =========================================================
    //  Execute Tests
    // =========================================================

    function test_Execute() public {
        vm.prank(address(entryPoint));
        account.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 123)
        );

        assertEq(target.value(), 123, "Target value should be updated");
        assertEq(account.nonce(), 1, "Nonce should increment");
    }

    function test_ExecuteWithValue() public {
        vm.prank(address(entryPoint));
        account.execute(
            address(target),
            1 ether,
            abi.encodeWithSelector(MockTarget.setValue.selector, 999)
        );

        assertEq(target.value(), 999, "Target value should be updated");
        assertEq(address(target).balance, 1 ether, "Target should receive ETH");
    }

    function test_Execute_RevertNotEntryPoint() public {
        vm.prank(user);
        vm.expectRevert(NotEntryPoint.selector);
        account.execute(address(target), 0, "");
    }

    function test_Execute_RevertOnFailedCall() public {
        vm.prank(address(entryPoint));
        vm.expectRevert(CallFailed.selector);
        account.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.revertWithMessage.selector)
        );
    }

    // =========================================================
    //  Batch Execute Tests
    // =========================================================

    function test_ExecuteBatch() public {
        address[] memory dest = new address[](3);
        uint256[] memory value = new uint256[](3);
        bytes[] memory func = new bytes[](3);

        dest[0] = address(target);
        value[0] = 0;
        func[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 100);

        dest[1] = address(target);
        value[1] = 0;
        func[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 200);

        dest[2] = address(target);
        value[2] = 0;
        func[2] = abi.encodeWithSelector(MockTarget.setValue.selector, 300);

        vm.prank(address(entryPoint));
        account.executeBatch(dest, value, func);

        assertEq(target.value(), 300, "Final value should be 300");
        assertEq(account.nonce(), 1, "Nonce should increment once per batch");
    }

    // =========================================================
    //  Integration: Full UserOperation Flow
    // =========================================================

    function test_FullUserOperationFlow() public {
        // Create UserOperation to set target value to 777
        bytes memory callData = abi.encodeWithSelector(
            SimpleSmartAccount.execute.selector,
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 777)
        );

        UserOperation memory userOp = UserOpHelper.createUserOp(
            address(account),
            0,
            callData,
            ""
        );

        // Sign it
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes memory signature = _signUserOp(userOpHash, ownerPrivateKey);
        userOp.signature = signature;

        // Submit to EntryPoint
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        entryPoint.handleOps(ops, payable(owner));

        // Verify execution
        assertEq(target.value(), 777, "Target value should be updated via UserOp");
        assertEq(account.nonce(), 1, "Nonce should increment");
    }

    function test_MultipleBatchedUserOperations() public {
        // Create two UserOperations
        UserOperation[] memory ops = new UserOperation[](2);

        // First UserOp: set value to 111
        bytes memory callData1 = abi.encodeWithSelector(
            SimpleSmartAccount.execute.selector,
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 111)
        );
        ops[0] = UserOpHelper.createUserOp(address(account), 0, callData1, "");
        bytes32 hash1 = keccak256(abi.encode(ops[0]));
        ops[0].signature = _signUserOp(hash1, ownerPrivateKey);

        // Second UserOp: set value to 222 (with incremented nonce)
        bytes memory callData2 = abi.encodeWithSelector(
            SimpleSmartAccount.execute.selector,
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 222)
        );
        ops[1] = UserOpHelper.createUserOp(address(account), 1, callData2, "");
        bytes32 hash2 = keccak256(abi.encode(ops[1]));
        ops[1].signature = _signUserOp(hash2, ownerPrivateKey);

        // Submit batch
        entryPoint.handleOps(ops, payable(owner));

        // Final value should be 222 (second op)
        assertEq(target.value(), 222, "Final value should be from second UserOp");
        assertEq(account.nonce(), 2, "Nonce should be 2 after two operations");
    }

    // =========================================================
    //  Helper Functions Tests
    // =========================================================

    function test_GetNonce() public view {
        uint256 nonce = account.getNonce();
        assertEq(nonce, 0, "Initial nonce should be 0");
    }

    function test_GetUserOpHash() public view {
        UserOperation memory userOp = UserOpHelper.createUserOp(address(account), 0, "", "");
        bytes32 hash = account.getUserOpHash(userOp);
        bytes32 expectedHash = keccak256(abi.encode(userOp));
        assertEq(hash, expectedHash, "UserOp hash should match");
    }

    function test_ReceiveETH() public {
        vm.deal(user, 5 ether);

        vm.prank(user);
        (bool success,) = address(account).call{value: 1 ether}("");

        assertTrue(success, "Account should accept ETH");
        assertEq(address(account).balance, 11 ether, "Balance should update");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_InvalidSignatureSkipsExecution() public {
        UserOperation memory userOp = UserOpHelper.createUserOp(
            address(account),
            0,
            abi.encodeWithSelector(
                SimpleSmartAccount.execute.selector,
                address(target),
                0,
                abi.encodeWithSelector(MockTarget.setValue.selector, 999)
            ),
            ""
        );

        // Sign with wrong key
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        userOp.signature = _signUserOp(userOpHash, 0xBAD);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        entryPoint.handleOps(ops, payable(owner));

        // Execution should be skipped
        assertEq(target.value(), 0, "Value should not change (execution skipped)");
        assertEq(account.nonce(), 0, "Nonce should not increment");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_ValidateUserOp_RejectsRandomSignatures(uint256 randomKey) public {
        // Ensure randomKey is a valid private key and not the owner's key
        vm.assume(randomKey > 0 && randomKey < type(uint248).max);
        vm.assume(vm.addr(randomKey) != owner);

        UserOperation memory userOp = UserOpHelper.createUserOp(address(account), 0, "", "");
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes memory signature = _signUserOp(userOpHash, randomKey);
        userOp.signature = signature;

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1, "Random key should fail validation");
    }

    // =========================================================
    //  Helper Functions
    // =========================================================

    function _signUserOp(bytes32 hash, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}

// =============================================================
//  Mock Target Contract
// =============================================================
contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external payable {
        value = _value;
    }

    function revertWithMessage() external pure {
        revert("Intentional revert");
    }

    receive() external payable {}
}

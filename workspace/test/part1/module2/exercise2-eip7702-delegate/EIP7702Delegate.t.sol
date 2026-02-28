// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {
    SimpleAccount,
    EIP1271Account,
    Call,
    MockERC20,
    MockTarget,
    InvalidSignature,
    CallFailed,
    Unauthorized,
    AlreadyInitialized
} from "../../../../src/part1/module2/exercise2-eip7702-delegate/EIP7702Delegate.sol";

/// @notice Tests for EIP-7702 delegation exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part1/module2/EIP7702Delegate.sol instead.
contract EIP7702DelegateTest is Test {
    SimpleAccount simpleImpl;
    EIP1271Account eip1271Impl;

    MockTarget target;
    MockERC20 token;

    address owner;
    address user;

    uint256 ownerPrivateKey;

    function setUp() public {
        // Deploy implementation contracts
        simpleImpl = new SimpleAccount();
        eip1271Impl = new EIP1271Account();

        // Deploy mock contracts
        target = new MockTarget();
        token = new MockERC20();

        // Create test accounts
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        user = makeAddr("user");

        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
    }

    // =========================================================
    //  SimpleAccount: Initialization Tests
    // =========================================================

    function test_SimpleAccount_Initialize() public {
        simpleImpl.initialize(owner);

        assertEq(simpleImpl.owner(), owner, "Owner should be set");
    }

    function test_SimpleAccount_PreventReInitialize() public {
        simpleImpl.initialize(owner);

        // Try to re-initialize with different owner — should revert with AlreadyInitialized
        vm.expectRevert(AlreadyInitialized.selector);
        simpleImpl.initialize(user);

        // Owner should remain unchanged
        assertEq(simpleImpl.owner(), owner, "Owner should not change");
    }

    // =========================================================
    //  SimpleAccount: Single Execute Tests
    // =========================================================

    function test_SimpleAccount_Execute() public {
        simpleImpl.initialize(owner);

        // Owner executes a call
        vm.prank(owner);
        bytes memory returnData = simpleImpl.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 42)
        );

        assertEq(target.value(), 42, "Target value should be updated");
        assertEq(target.sender(), address(simpleImpl), "Sender should be the account");
    }

    function test_SimpleAccount_ExecuteWithValue() public {
        simpleImpl.initialize(owner);
        vm.deal(address(simpleImpl), 10 ether);

        // Execute with ETH value
        vm.prank(owner);
        simpleImpl.execute{value: 1 ether}(
            address(target),
            1 ether,
            abi.encodeWithSelector(MockTarget.setValue.selector, 100)
        );

        assertEq(target.value(), 100, "Target value should be updated");
        assertEq(target.msgValue(), 1 ether, "Target should receive 1 ETH");
    }

    function test_SimpleAccount_RevertOnUnauthorized() public {
        simpleImpl.initialize(owner);

        // Non-owner tries to execute
        vm.prank(user);
        vm.expectRevert(Unauthorized.selector);
        simpleImpl.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 42)
        );
    }

    function test_SimpleAccount_RevertOnFailedCall() public {
        simpleImpl.initialize(owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(
            CallFailed.selector,
            0,
            abi.encodeWithSignature("Error(string)", "Intentional revert")
        ));
        simpleImpl.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.revertWithMessage.selector)
        );
    }

    // =========================================================
    //  SimpleAccount: Batch Execute Tests
    // =========================================================

    function test_SimpleAccount_ExecuteBatch() public {
        simpleImpl.initialize(owner);

        // Prepare batch calls
        Call[] memory calls = new Call[](3);
        calls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 10)
        });
        calls[1] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 20)
        });
        calls[2] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 30)
        });

        vm.prank(owner);
        bytes[] memory results = simpleImpl.executeBatch(calls);

        assertEq(results.length, 3, "Should return 3 results");
        assertEq(target.value(), 30, "Final value should be 30");
    }

    function test_SimpleAccount_BatchWithTokenTransfers() public {
        simpleImpl.initialize(owner);

        // Mint tokens to the account
        token.mint(address(simpleImpl), 1000);

        // Batch: transfer to 3 different recipients
        Call[] memory calls = new Call[](3);
        calls[0] = Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(token.transfer.selector, user, 100)
        });
        calls[1] = Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(token.transfer.selector, owner, 200)
        });
        calls[2] = Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(token.transfer.selector, address(target), 300)
        });

        vm.prank(owner);
        simpleImpl.executeBatch(calls);

        assertEq(token.balanceOf(user), 100, "User should have 100 tokens");
        assertEq(token.balanceOf(owner), 200, "Owner should have 200 tokens");
        assertEq(token.balanceOf(address(target)), 300, "Target should have 300 tokens");
        assertEq(token.balanceOf(address(simpleImpl)), 400, "Account should have 400 tokens left");
    }

    function test_SimpleAccount_BatchRevertOnFailedCall() public {
        simpleImpl.initialize(owner);

        Call[] memory calls = new Call[](3);
        calls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 10)
        });
        calls[1] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.revertWithMessage.selector)
        });
        calls[2] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 30)
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(
            CallFailed.selector,
            1,
            abi.encodeWithSignature("Error(string)", "Intentional revert")
        ));
        simpleImpl.executeBatch(calls);
    }

    // =========================================================
    //  EIP1271Account: Signature Validation Tests
    // =========================================================

    function test_EIP1271Account_ValidSignature() public {
        eip1271Impl.initialize(owner);

        bytes32 hash = keccak256("Test message");

        // Sign the hash with owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate signature
        bytes4 result = eip1271Impl.isValidSignature(hash, signature);

        assertEq(result, bytes4(0x1626ba7e), "Should return EIP-1271 magic value");
    }

    function test_EIP1271Account_InvalidSignature_WrongSigner() public {
        eip1271Impl.initialize(owner);

        bytes32 hash = keccak256("Test message");

        // Sign with a different private key
        uint256 wrongPrivateKey = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate signature
        bytes4 result = eip1271Impl.isValidSignature(hash, signature);

        assertEq(result, bytes4(0xffffffff), "Should return invalid signature marker");
    }

    function test_EIP1271Account_Execute() public {
        eip1271Impl.initialize(owner);

        vm.prank(owner);
        eip1271Impl.execute(
            address(target),
            0,
            abi.encodeWithSelector(MockTarget.setValue.selector, 99)
        );

        assertEq(target.value(), 99, "Target value should be updated");
    }

    // =========================================================
    //  Integration: Simulating EIP-7702 via DELEGATECALL
    // =========================================================

    function test_SimulatedDelegation_EOA_GainsSmartAccountCapabilities() public {
        // Simulate what happens when an EOA delegates to SimpleAccount

        // Deploy a "proxy" that simulates the EOA with delegated code
        EOASimulator eoaSimulator = new EOASimulator(address(simpleImpl));

        // Initialize the delegated storage (happens in EOA's storage space)
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(SimpleAccount.initialize.selector, owner)
        );

        // Now the EOA can execute via the delegated implementation
        vm.prank(owner);
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(target),
                0,
                abi.encodeWithSelector(MockTarget.setValue.selector, 777)
            )
        );

        assertEq(target.value(), 777, "EOA should be able to execute via delegation");
        assertEq(target.sender(), address(eoaSimulator), "Sender should be the EOA address");
    }

    function test_SimulatedDelegation_EOA_CanBatch() public {
        EOASimulator eoaSimulator = new EOASimulator(address(simpleImpl));
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(SimpleAccount.initialize.selector, owner)
        );

        // Create batch calls
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 100)
        });
        calls[1] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, 200)
        });

        vm.prank(owner);
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(SimpleAccount.executeBatch.selector, calls)
        );

        assertEq(target.value(), 200, "Batch execution should work via delegation");
    }

    // =========================================================
    //  Edge Cases
    // =========================================================

    function test_SimpleAccount_ReceiveETH() public {
        vm.deal(user, 5 ether);

        vm.prank(user);
        (bool success,) = address(simpleImpl).call{value: 1 ether}("");

        assertTrue(success, "Account should accept ETH");
        assertEq(address(simpleImpl).balance, 1 ether, "Account balance should be 1 ETH");
    }

    function test_EmptyBatch() public {
        simpleImpl.initialize(owner);

        Call[] memory calls = new Call[](0);

        vm.prank(owner);
        bytes[] memory results = simpleImpl.executeBatch(calls);

        assertEq(results.length, 0, "Empty batch should return empty results");
    }

    // =========================================================
    //  tx.origin Bypass Test (EIP-7702 Security)
    // =========================================================

    function test_TxOriginBypass_DelegatedEOA() public {
        // Demonstrates why tx.origin checks are dangerous with EIP-7702.
        // When an EOA delegates to a batch executor, tx.origin == msg.sender
        // for direct calls, but in a batch the inner calls have
        // tx.origin == EOA while msg.sender == the batch executor.
        // This test shows the pattern is broken.

        TxOriginTarget originTarget = new TxOriginTarget();

        EOASimulator eoaSimulator = new EOASimulator(address(simpleImpl));
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(SimpleAccount.initialize.selector, owner)
        );

        // Direct call: tx.origin == msg.sender (passes naive check)
        // But via delegation + batch, the target's msg.sender is the EOA simulator,
        // while tx.origin is still the test contract. They differ!
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(originTarget),
            value: 0,
            data: abi.encodeWithSelector(TxOriginTarget.doSomething.selector)
        });

        // Owner calls via delegation — msg.sender to originTarget will be
        // the eoaSimulator, but tx.origin is the owner (or test contract).
        // This proves tx.origin != msg.sender in delegated context.
        vm.prank(owner);
        eoaSimulator.delegateCall(
            abi.encodeWithSelector(SimpleAccount.executeBatch.selector, calls)
        );

        // The target received a call where msg.sender != tx.origin
        // This is exactly the pattern that breaks tx.origin-based auth
        assertNotEq(
            originTarget.lastSender(),
            originTarget.lastOrigin(),
            "tx.origin should differ from msg.sender in delegated batch calls"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_EIP1271_SignatureValidation(bytes32 hash) public {
        eip1271Impl.initialize(owner);

        // Sign any hash with owner's key — should always validate
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = eip1271Impl.isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e), "Valid signature for any hash");
    }

    function testFuzz_EIP1271_InvalidSignature(bytes32 hash, uint256 wrongKey) public {
        eip1271Impl.initialize(owner);

        // Bound to valid private key range and ensure it's not the owner's key
        wrongKey = bound(wrongKey, 1, type(uint128).max);
        vm.assume(wrongKey != ownerPrivateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = eip1271Impl.isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff), "Wrong signer should return invalid");
    }

    function testFuzz_BatchExecution(uint256 value1, uint256 value2) public {
        value1 = bound(value1, 1, 1000);
        value2 = bound(value2, 1, 1000);

        simpleImpl.initialize(owner);

        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, value1)
        });
        calls[1] = Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.setValue.selector, value2)
        });

        vm.prank(owner);
        bytes[] memory results = simpleImpl.executeBatch(calls);

        assertEq(results.length, 2, "Should return 2 results");
        // Last call wins
        assertEq(target.value(), value2, "Final value should be value2");
    }

    // =========================================================
    //  Signature Edge Case: eth_sign prefix
    // =========================================================

    function test_EIP1271_EthSignPrefixedHash() public {
        eip1271Impl.initialize(owner);

        // eth_sign prefixes with "\x19Ethereum Signed Message:\n32"
        // This tests that the contract validates against the RAW hash,
        // not the prefixed version. The caller is responsible for hashing.
        bytes32 rawHash = keccak256("Test message");
        bytes32 ethSignHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash)
        );

        // Sign the raw hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, rawHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate against raw hash — should pass
        bytes4 result1 = eip1271Impl.isValidSignature(rawHash, signature);
        assertEq(result1, bytes4(0x1626ba7e), "Raw hash validation should pass");

        // Validate against eth_sign hash — should fail (different hash)
        bytes4 result2 = eip1271Impl.isValidSignature(ethSignHash, signature);
        assertEq(result2, bytes4(0xffffffff), "eth_sign prefixed hash should fail with raw signature");
    }
}

// =============================================================
//  Helper: tx.origin test target
// =============================================================
/// @notice Records msg.sender and tx.origin for verification.
contract TxOriginTarget {
    address public lastSender;
    address public lastOrigin;

    function doSomething() external {
        lastSender = msg.sender;
        lastOrigin = tx.origin;
    }
}

// =============================================================
//  Helper: EOA Simulator
// =============================================================
/// @notice Simulates an EOA that has delegated to an implementation contract.
/// @dev Uses DELEGATECALL to simulate EIP-7702 delegation semantics.
contract EOASimulator {
    address public implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function delegateCall(bytes memory data) public payable returns (bytes memory) {
        (bool success, bytes memory returnData) = implementation.delegatecall(data);
        require(success, "Delegate call failed");
        return returnData;
    }

    receive() external payable {}
}

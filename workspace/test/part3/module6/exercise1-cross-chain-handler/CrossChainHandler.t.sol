// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the CrossChainHandler
//  exercise. Implement CrossChainHandler.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    CrossChainHandler,
    NotOwner,
    NotMessagingProtocol,
    UntrustedSource,
    MessageAlreadyProcessed,
    UnknownMessageType
} from "../../../../src/part3/module6/exercise1-cross-chain-handler/CrossChainHandler.sol";

contract CrossChainHandlerTest is Test {
    CrossChainHandler public handler;

    // Actors
    address owner = makeAddr("owner");
    address bridge = makeAddr("bridge"); // the messaging protocol endpoint
    address attacker = makeAddr("attacker");

    // Chain config
    uint32 constant ETHEREUM = 1;
    uint32 constant ARBITRUM = 42161;
    uint32 constant OPTIMISM = 10;

    // Trusted source addresses (contracts deployed on other chains)
    address constant TRUSTED_ETH = address(0xAAA);
    address constant TRUSTED_ARB = address(0xBBB);

    function setUp() public {
        vm.prank(owner);
        handler = new CrossChainHandler(bridge);
    }

    // --- Helpers ---

    function _transferPayload(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), abi.encode(to, amount));
    }

    function _governancePayload(bytes32 actionId, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(1), abi.encode(actionId, data));
    }

    function _setupTrustedSources() internal {
        vm.startPrank(owner);
        handler.setTrustedSource(ETHEREUM, TRUSTED_ETH);
        handler.setTrustedSource(ARBITRUM, TRUSTED_ARB);
        vm.stopPrank();
    }

    // =========================================================
    //  setTrustedSource (TODO 1)
    // =========================================================

    function test_setTrustedSource_storesCorrectly() public {
        vm.prank(owner);
        handler.setTrustedSource(ETHEREUM, TRUSTED_ETH);
        assertEq(handler.trustedSources(ETHEREUM), TRUSTED_ETH, "Should store trusted source");
    }

    function test_setTrustedSource_multipleSources() public {
        _setupTrustedSources();
        assertEq(handler.trustedSources(ETHEREUM), TRUSTED_ETH, "Ethereum source");
        assertEq(handler.trustedSources(ARBITRUM), TRUSTED_ARB, "Arbitrum source");
    }

    function test_setTrustedSource_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(handler));
        emit CrossChainHandler.TrustedSourceSet(ETHEREUM, TRUSTED_ETH);
        handler.setTrustedSource(ETHEREUM, TRUSTED_ETH);
    }

    function test_setTrustedSource_revertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(NotOwner.selector);
        handler.setTrustedSource(ETHEREUM, TRUSTED_ETH);
    }

    function test_setTrustedSource_canUpdate() public {
        vm.startPrank(owner);
        handler.setTrustedSource(ETHEREUM, TRUSTED_ETH);
        address newSource = address(0xCCC);
        handler.setTrustedSource(ETHEREUM, newSource);
        vm.stopPrank();

        assertEq(handler.trustedSources(ETHEREUM), newSource, "Should allow updating trusted source");
    }

    // =========================================================
    //  handleMessage — Source Verification (TODO 2)
    // =========================================================

    function test_handleMessage_revertsOnUntrustedSource() public {
        _setupTrustedSources();

        vm.prank(bridge);
        vm.expectRevert(
            abi.encodeWithSelector(UntrustedSource.selector, ETHEREUM, attacker)
        );
        handler.handleMessage(
            ETHEREUM,
            attacker, // not the trusted source
            keccak256("msg1"),
            _transferPayload(address(0x123), 100e18)
        );
    }

    function test_handleMessage_revertsOnUnconfiguredChain() public {
        _setupTrustedSources();

        vm.prank(bridge);
        vm.expectRevert(
            abi.encodeWithSelector(UntrustedSource.selector, OPTIMISM, address(0xDDD))
        );
        handler.handleMessage(
            OPTIMISM, // no trusted source set for this chain
            address(0xDDD),
            keccak256("msg1"),
            _transferPayload(address(0x123), 100e18)
        );
    }

    function test_handleMessage_revertsIfNotMessagingProtocol() public {
        _setupTrustedSources();

        vm.prank(attacker); // not the bridge
        vm.expectRevert(NotMessagingProtocol.selector);
        handler.handleMessage(
            ETHEREUM,
            TRUSTED_ETH,
            keccak256("msg1"),
            _transferPayload(address(0x123), 100e18)
        );
    }

    // =========================================================
    //  handleMessage — Replay Protection (TODO 2)
    // =========================================================

    function test_handleMessage_marksAsProcessed() public {
        _setupTrustedSources();
        bytes32 msgId = keccak256("msg1");

        vm.prank(bridge);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, msgId, _transferPayload(address(0x123), 100e18));

        assertTrue(handler.processedMessages(msgId), "Message should be marked as processed");
    }

    function test_handleMessage_revertsOnReplay() public {
        _setupTrustedSources();
        bytes32 msgId = keccak256("msg1");

        vm.prank(bridge);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, msgId, _transferPayload(address(0x123), 100e18));

        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSelector(MessageAlreadyProcessed.selector, msgId));
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, msgId, _transferPayload(address(0x123), 100e18));
    }

    function test_handleMessage_differentIdsNotReplayed() public {
        _setupTrustedSources();

        vm.startPrank(bridge);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, keccak256("msg1"), _transferPayload(address(0x123), 100e18));
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, keccak256("msg2"), _transferPayload(address(0x456), 200e18));
        vm.stopPrank();

        assertEq(handler.totalTransfers(), 2, "Both messages should be processed");
    }

    // =========================================================
    //  handleMessage — Dispatch (TODO 2)
    // =========================================================

    function test_handleMessage_revertsOnUnknownType() public {
        _setupTrustedSources();

        // Unknown type = 99
        bytes memory badPayload = abi.encodePacked(uint8(99), abi.encode(uint256(0)));

        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSelector(UnknownMessageType.selector, uint8(99)));
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, keccak256("msg1"), badPayload);
    }

    // =========================================================
    //  _handleTransfer (TODO 3)
    // =========================================================

    function test_handleTransfer_decodesCorrectly() public {
        _setupTrustedSources();
        address recipient = address(0x123);
        uint256 amount = 50e18;

        vm.prank(bridge);
        handler.handleMessage(
            ETHEREUM,
            TRUSTED_ETH,
            keccak256("transfer1"),
            _transferPayload(recipient, amount)
        );

        (address to, uint256 amt) = handler.lastTransfer();
        assertEq(to, recipient, "Should decode transfer recipient");
        assertEq(amt, amount, "Should decode transfer amount");
    }

    function test_handleTransfer_incrementsCounter() public {
        _setupTrustedSources();

        vm.startPrank(bridge);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, keccak256("t1"), _transferPayload(address(0x1), 10e18));
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, keccak256("t2"), _transferPayload(address(0x2), 20e18));
        handler.handleMessage(ARBITRUM, TRUSTED_ARB, keccak256("t3"), _transferPayload(address(0x3), 30e18));
        vm.stopPrank();

        assertEq(handler.totalTransfers(), 3, "Should count all transfers");
    }

    function test_handleTransfer_emitsEvent() public {
        _setupTrustedSources();
        address recipient = address(0x123);
        uint256 amount = 75e18;
        bytes32 msgId = keccak256("transfer-event");

        vm.prank(bridge);
        vm.expectEmit(true, false, false, true, address(handler));
        emit CrossChainHandler.TransferReceived(ETHEREUM, recipient, amount, msgId);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, msgId, _transferPayload(recipient, amount));
    }

    // =========================================================
    //  _handleGovernance (TODO 4)
    // =========================================================

    function test_handleGovernance_decodesCorrectly() public {
        _setupTrustedSources();
        bytes32 actionId = keccak256("SET_FEE");
        bytes memory actionData = abi.encode(uint256(500)); // new fee = 5%

        vm.prank(bridge);
        handler.handleMessage(
            ETHEREUM,
            TRUSTED_ETH,
            keccak256("gov1"),
            _governancePayload(actionId, actionData)
        );

        (bytes32 id, bytes memory data) = handler.lastGovernance();
        assertEq(id, actionId, "Should decode governance actionId");
        assertEq(keccak256(data), keccak256(actionData), "Should decode governance data");
    }

    function test_handleGovernance_incrementsCounter() public {
        _setupTrustedSources();

        vm.startPrank(bridge);
        handler.handleMessage(
            ETHEREUM, TRUSTED_ETH, keccak256("g1"),
            _governancePayload(keccak256("ACTION_1"), "")
        );
        handler.handleMessage(
            ETHEREUM, TRUSTED_ETH, keccak256("g2"),
            _governancePayload(keccak256("ACTION_2"), "")
        );
        vm.stopPrank();

        assertEq(handler.totalGovernanceActions(), 2, "Should count governance actions");
    }

    function test_handleGovernance_emitsEvent() public {
        _setupTrustedSources();
        bytes32 actionId = keccak256("UPGRADE");
        bytes32 msgId = keccak256("gov-event");

        vm.prank(bridge);
        vm.expectEmit(true, false, false, true, address(handler));
        emit CrossChainHandler.GovernanceReceived(ETHEREUM, actionId, msgId);
        handler.handleMessage(
            ETHEREUM, TRUSTED_ETH, msgId,
            _governancePayload(actionId, abi.encode(address(0x999)))
        );
    }

    // =========================================================
    //  Integration
    // =========================================================

    function test_integration_mixedMessageTypes() public {
        _setupTrustedSources();

        vm.startPrank(bridge);
        // Transfer from Ethereum
        handler.handleMessage(
            ETHEREUM, TRUSTED_ETH, keccak256("m1"),
            _transferPayload(address(0x111), 100e18)
        );
        // Governance from Ethereum
        handler.handleMessage(
            ETHEREUM, TRUSTED_ETH, keccak256("m2"),
            _governancePayload(keccak256("SET_PARAM"), abi.encode(uint256(42)))
        );
        // Transfer from Arbitrum
        handler.handleMessage(
            ARBITRUM, TRUSTED_ARB, keccak256("m3"),
            _transferPayload(address(0x222), 200e18)
        );
        vm.stopPrank();

        assertEq(handler.totalTransfers(), 2, "2 transfers processed");
        assertEq(handler.totalGovernanceActions(), 1, "1 governance action processed");

        // Last transfer should be the Arbitrum one
        (address to, uint256 amt) = handler.lastTransfer();
        assertEq(to, address(0x222), "Last transfer should be from Arbitrum");
        assertEq(amt, 200e18, "Last transfer amount");
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_replayProtection_uniqueIds(bytes32 id1, bytes32 id2) public {
        vm.assume(id1 != id2);
        _setupTrustedSources();

        vm.startPrank(bridge);
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, id1, _transferPayload(address(0x1), 1e18));
        handler.handleMessage(ETHEREUM, TRUSTED_ETH, id2, _transferPayload(address(0x2), 2e18));
        vm.stopPrank();

        assertTrue(handler.processedMessages(id1), "id1 should be processed");
        assertTrue(handler.processedMessages(id2), "id2 should be processed");
        assertEq(handler.totalTransfers(), 2, "Both unique messages processed");
    }

    function testFuzz_untrustedSource_alwaysReverts(address randomSender) public {
        vm.assume(randomSender != TRUSTED_ETH);
        _setupTrustedSources();

        vm.prank(bridge);
        vm.expectRevert(
            abi.encodeWithSelector(UntrustedSource.selector, ETHEREUM, randomSender)
        );
        handler.handleMessage(
            ETHEREUM, randomSender, keccak256("fuzz"),
            _transferPayload(address(0x1), 1e18)
        );
    }
}

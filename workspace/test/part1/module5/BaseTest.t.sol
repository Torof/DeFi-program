// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests for BaseTest contract.
/// @dev DO NOT MODIFY THIS FILE. Fill in BaseTest.sol instead.
contract BaseTestTest is Test {
    // We need to inherit from BaseTest to test it
    TestableBaseTest baseTest;

    function setUp() public {
        baseTest = new TestableBaseTest();
        baseTest.setUp();
    }

    // =========================================================
    //  Initialization Tests
    // =========================================================

    function test_SetupCreatesTestUsers() public view {
        assertTrue(baseTest.alice() != address(0), "Alice should be created");
        assertTrue(baseTest.bob() != address(0), "Bob should be created");
        assertTrue(baseTest.charlie() != address(0), "Charlie should be created");
        assertTrue(baseTest.aliceKey() != 0, "Alice key should be set");
        assertTrue(baseTest.bobKey() != 0, "Bob key should be set");
        assertTrue(baseTest.charlieKey() != 0, "Charlie key should be set");
    }

    function test_TestUsersAreUnique() public view {
        assertTrue(baseTest.alice() != baseTest.bob(), "Alice and Bob should be different");
        assertTrue(baseTest.alice() != baseTest.charlie(), "Alice and Charlie should be different");
        assertTrue(baseTest.bob() != baseTest.charlie(), "Bob and Charlie should be different");
    }

    function test_CommonAddressesAreDefined() public view {
        assertTrue(baseTest.WETH() != address(0), "WETH should be defined");
        assertTrue(baseTest.USDC() != address(0), "USDC should be defined");
        assertTrue(baseTest.DAI() != address(0), "DAI should be defined");
        assertTrue(baseTest.PERMIT2() != address(0), "PERMIT2 should be defined");
    }

    // =========================================================
    //  Fork Tests
    // =========================================================

    function test_ForkIsMainnet() public {
        // Verify we're on mainnet fork by checking known contract
        bytes memory code = baseTest.WETH().code;
        assertTrue(code.length > 0, "WETH should have code on mainnet fork");
    }

    function test_CommonTokensExist() public {
        // Verify tokens have code (deployed contracts)
        assertTrue(baseTest.WETH().code.length > 0, "WETH should exist");
        assertTrue(baseTest.USDC().code.length > 0, "USDC should exist");
        assertTrue(baseTest.DAI().code.length > 0, "DAI should exist");
    }

    // =========================================================
    //  Helper Function Tests
    // =========================================================

    function test_DealETH() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 100 ether;

        baseTest.exposedDealETH(recipient, amount);

        assertEq(recipient.balance, amount, "Should receive ETH");
    }

    function test_DealToken() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 1000e6; // 1000 USDC (6 decimals)

        baseTest.exposedDealToken(baseTest.USDC(), recipient, amount);

        assertEq(IERC20(baseTest.USDC()).balanceOf(recipient), amount, "Should receive tokens");
    }

    function test_Skip() public {
        uint256 initialTimestamp = block.timestamp;
        uint256 duration = 7 days;

        baseTest.exposedSkip(duration);

        assertEq(block.timestamp, initialTimestamp + duration, "Should advance time");
    }

    function test_SkipBlocks() public {
        uint256 initialBlock = block.number;
        uint256 blocksToAdvance = 100;

        baseTest.exposedSkipBlocks(blocksToAdvance);

        assertEq(block.number, initialBlock + blocksToAdvance, "Should advance blocks");
    }

    function test_SignTypedData() public view {
        bytes32 digest = keccak256("test message");

        (uint8 v, bytes32 r, bytes32 s) = baseTest.exposedSignTypedData(baseTest.aliceKey(), digest);

        // Verify signature components are non-zero
        assertTrue(v == 27 || v == 28, "v should be 27 or 28");
        assertTrue(r != bytes32(0), "r should be non-zero");
        assertTrue(s != bytes32(0), "s should be non-zero");

        // Verify signature recovers to alice
        address recovered = ecrecover(digest, v, r, s);
        assertEq(recovered, baseTest.alice(), "Signature should recover to Alice");
    }

    // =========================================================
    //  Integration Tests
    // =========================================================

    function test_FullWorkflow() public {
        // Deal ETH and tokens to alice
        baseTest.exposedDealETH(baseTest.alice(), 10 ether);
        baseTest.exposedDealToken(baseTest.USDC(), baseTest.alice(), 1000e6);

        // Verify balances
        assertEq(baseTest.alice().balance, 10 ether, "Alice should have ETH");
        assertEq(IERC20(baseTest.USDC()).balanceOf(baseTest.alice()), 1000e6, "Alice should have USDC");

        // Advance time
        uint256 initialTime = block.timestamp;
        baseTest.exposedSkip(1 days);
        assertEq(block.timestamp, initialTime + 1 days, "Time should advance");

        // Sign a message
        bytes32 message = keccak256("Hello, DeFi!");
        (uint8 v, bytes32 r, bytes32 s) = baseTest.exposedSignTypedData(baseTest.aliceKey(), message);
        address recovered = ecrecover(message, v, r, s);
        assertEq(recovered, baseTest.alice(), "Signature should be valid");
    }
}

// =============================================================
//  Testable Wrapper (exposes BaseTest functionality)
// =============================================================
/// @dev Wrapper to test BaseTest since it's abstract
contract TestableBaseTest is BaseTest {
    // Constants (WETH, USDC, DAI, PERMIT2) and state variables
    // (alice, bob, charlie, aliceKey, bobKey, charlieKey) are inherited
    // as public from BaseTest, so auto-generated getters are available.

    // Expose internal helper functions for testing
    function exposedDealETH(address to, uint256 amount) external {
        dealETH(to, amount);
    }

    function exposedDealToken(address token, address to, uint256 amount) external {
        dealToken(token, to, amount);
    }

    function exposedSignTypedData(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return signTypedData(privateKey, digest);
    }

    function exposedSkip(uint256 duration) external {
        skip(duration);
    }

    function exposedSkipBlocks(uint256 blocks) external {
        skipBlocks(blocks);
    }
}

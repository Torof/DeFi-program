// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev DO NOT MODIFY THIS FILE — this is the test suite for AssemblyRouter.
/// Your task is to implement the contract in AssemblyRouter.sol so all tests pass.

import "forge-std/Test.sol";
import {AssemblyRouter} from
    "../../../../src/part4/module5/exercise3-assembly-router/AssemblyRouter.sol";
import {MockPool} from "../../../../src/part4/module5/exercise3-assembly-router/MockPool.sol";

/// @dev Simple implementation for testing proxyForward via DELEGATECALL.
///      Pure/view functions avoid storage collision with the router.
contract MockImplementation {
    function add(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }

    function getContext() external view returns (address self, address sender) {
        return (address(this), msg.sender);
    }

    function mustRevert() external pure {
        revert("implementation reverted");
    }
}

contract AssemblyRouterTest is Test {
    AssemblyRouter internal router;
    MockPool internal pool;
    MockImplementation internal impl;

    address internal tokenA = makeAddr("tokenA");
    address internal tokenB = makeAddr("tokenB");
    address internal alice = makeAddr("alice");

    function setUp() public {
        router = new AssemblyRouter();
        impl = new MockImplementation();
        // Pool with 100,000 of each token
        pool = new MockPool(tokenA, tokenB, 100_000e18, 100_000e18);
    }

    // =========================================================================
    // TODO 1: proxyForward
    // =========================================================================

    function test_ProxyForward_returnsData() public {
        // Delegate add(3, 4) to impl — should return 7
        bytes memory innerCall = abi.encodeWithSelector(
            MockImplementation.add.selector,
            uint256(3),
            uint256(4)
        );

        // Use low-level call because proxyForward uses assembly `return`
        // which bypasses Solidity's ABI encoding
        (bool ok, bytes memory result) = address(router).call(
            abi.encodeWithSelector(
                AssemblyRouter.proxyForward.selector,
                address(impl),
                innerCall
            )
        );
        assertTrue(ok, "proxyForward should succeed");
        assertEq(
            abi.decode(result, (uint256)),
            7,
            "add(3, 4) should return 7 via DELEGATECALL"
        );
    }

    function test_ProxyForward_preservesDelegatecallContext() public {
        // getContext() returns (address(this), msg.sender)
        // Under DELEGATECALL: address(this) = router, msg.sender = alice
        bytes memory innerCall = abi.encodeWithSelector(
            MockImplementation.getContext.selector
        );

        vm.prank(alice);
        (bool ok, bytes memory result) = address(router).call(
            abi.encodeWithSelector(
                AssemblyRouter.proxyForward.selector,
                address(impl),
                innerCall
            )
        );
        assertTrue(ok, "proxyForward should succeed");

        (address self, address sender) = abi.decode(result, (address, address));
        assertEq(
            self,
            address(router),
            "address(this) should be the router (DELEGATECALL context)"
        );
        assertEq(
            sender,
            alice,
            "msg.sender should be alice (DELEGATECALL preserves sender)"
        );
    }

    function test_ProxyForward_bubblesRevert() public {
        bytes memory innerCall = abi.encodeWithSelector(
            MockImplementation.mustRevert.selector
        );

        vm.expectRevert(bytes("implementation reverted"));
        router.proxyForward(address(impl), innerCall);
    }

    // =========================================================================
    // TODO 2: swapExactIn
    // =========================================================================

    function test_SwapExactIn_returnsAmountOut() public {
        uint256 amountIn = 1_000e18;

        uint256 amountOut = router.swapExactIn(
            address(pool), tokenA, tokenB, amountIn
        );

        // Constant product with 0.3% fee — output < input
        assertTrue(amountOut > 0, "Should receive non-zero output");
        assertTrue(amountOut < amountIn, "Output should be less than input (fees)");
    }

    function test_SwapExactIn_updatesReserves() public {
        uint256 amountIn = 1_000e18;

        uint256 amountOut = router.swapExactIn(
            address(pool), tokenA, tokenB, amountIn
        );

        assertEq(
            pool.reserves(tokenA),
            100_000e18 + amountIn,
            "tokenA reserves should increase by amountIn"
        );
        assertEq(
            pool.reserves(tokenB),
            100_000e18 - amountOut,
            "tokenB reserves should decrease by amountOut"
        );
    }

    function test_SwapExactIn_revertsOnBadPool() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x81ceff30))); // SwapFailed()
        router.swapExactIn(address(router), tokenA, tokenB, 100);
    }

    function test_SwapExactIn_smallSwap() public {
        uint256 amountOut = router.swapExactIn(
            address(pool), tokenA, tokenB, 1e18
        );

        assertTrue(amountOut > 0, "Even small swaps should produce output");
        // For a very small swap relative to reserves, output ≈ input * 0.997
        assertTrue(
            amountOut > 0.99e18 && amountOut < 1e18,
            "Small swap output should be close to input minus fee"
        );
    }

    // =========================================================================
    // TODO 3: recoverSigner
    // =========================================================================

    function test_RecoverSigner_validSignature() public {
        (address signer, uint256 privateKey) = makeAddrAndKey("signer");

        bytes32 hash = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        address recovered = router.recoverSigner(hash, v, r, s);
        assertEq(recovered, signer, "Should recover the correct signer");
    }

    function test_RecoverSigner_differentMessages() public {
        (address signer, uint256 privateKey) = makeAddrAndKey("signer2");

        bytes32 hash1 = keccak256("message1");
        bytes32 hash2 = keccak256("message2");

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(privateKey, hash1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(privateKey, hash2);

        assertEq(
            router.recoverSigner(hash1, v1, r1, s1),
            signer,
            "First message should recover signer"
        );
        assertEq(
            router.recoverSigner(hash2, v2, r2, s2),
            signer,
            "Second message should recover same signer"
        );
    }

    function test_RecoverSigner_revertsOnInvalidSignature() public {
        // v=0, r=0, s=0 → ecrecover returns address(0) → should revert
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x74e6fd08))); // RecoverFailed()
        router.recoverSigner(bytes32(0), 0, bytes32(0), bytes32(0));
    }

    function test_RecoverSigner_revertsOnBadV() public {
        // Invalid v value (not 27 or 28) → ecrecover returns address(0)
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x74e6fd08))); // RecoverFailed()
        router.recoverSigner(
            bytes32(uint256(1)),
            uint8(99),
            bytes32(uint256(1)),
            bytes32(uint256(1))
        );
    }

    // =========================================================================
    // TODO 4: multiCall
    // =========================================================================

    function test_MultiCall_singleCall() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(42));

        bytes[] memory results = router.multiCall(calls);

        assertEq(results.length, 1, "Should return 1 result");
        assertEq(
            abi.decode(results[0], (uint256)),
            42,
            "echo(42) should return 42"
        );
    }

    function test_MultiCall_multipleCalls() public {
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(10));
        calls[1] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(20));
        calls[2] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(30));

        bytes[] memory results = router.multiCall(calls);

        assertEq(results.length, 3, "Should return 3 results");
        assertEq(abi.decode(results[0], (uint256)), 10, "First result should be 10");
        assertEq(abi.decode(results[1], (uint256)), 20, "Second result should be 20");
        assertEq(abi.decode(results[2], (uint256)), 30, "Third result should be 30");
    }

    function test_MultiCall_preservesMsgSender() public {
        // getSender() returns msg.sender. DELEGATECALL to self preserves
        // the original caller, not the contract.
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(AssemblyRouter.getSender.selector);

        vm.prank(alice);
        bytes[] memory results = router.multiCall(calls);

        address sender = abi.decode(results[0], (address));
        assertEq(sender, alice, "DELEGATECALL should preserve msg.sender");
    }

    function test_MultiCall_revertsWithIndex() public {
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(1));
        calls[1] = hex"deadbeef"; // unknown selector — will revert
        calls[2] = abi.encodeWithSelector(AssemblyRouter.echo.selector, uint256(3));

        // Should revert with MultiCallFailed(1) — index of the failing call
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(0x5c7b055c), uint256(1))
        );
        router.multiCall(calls);
    }

    function test_MultiCall_emptyArray() public {
        bytes[] memory calls = new bytes[](0);

        bytes[] memory results = router.multiCall(calls);

        assertEq(results.length, 0, "Empty multicall should return empty results");
    }
}

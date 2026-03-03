// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {YulDispatcher} from
    "../../../../src/part4/module4/exercise1-yul-dispatcher/YulDispatcher.sol";

/// @notice Tests for the YulDispatcher exercise.
/// @dev DO NOT MODIFY THIS FILE. Fill in src/part4/module4/exercise1-yul-dispatcher/YulDispatcher.sol instead.

interface IYulDispatcher {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function owner() external view returns (address);
}

contract YulDispatcherTest is Test {
    YulDispatcher internal dispatcher;
    IYulDispatcher internal token;

    address internal deployer;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        deployer = address(this);
        dispatcher = new YulDispatcher();
        token = IYulDispatcher(address(dispatcher));
    }

    // =========================================================================
    // Selector Verification
    // =========================================================================

    function test_Selector_totalSupply() public pure {
        assertEq(IYulDispatcher.totalSupply.selector, bytes4(0x18160ddd), "totalSupply selector mismatch");
    }

    function test_Selector_balanceOf() public pure {
        assertEq(IYulDispatcher.balanceOf.selector, bytes4(0x70a08231), "balanceOf selector mismatch");
    }

    function test_Selector_transfer() public pure {
        assertEq(IYulDispatcher.transfer.selector, bytes4(0xa9059cbb), "transfer selector mismatch");
    }

    function test_Selector_mint() public pure {
        assertEq(IYulDispatcher.mint.selector, bytes4(0x40c10f19), "mint selector mismatch");
    }

    // =========================================================================
    // TODO 1: Dispatch
    // =========================================================================

    function test_Dispatch_unknownSelectorReverts() public {
        // Call with a random selector that doesn't match any function
        (bool success,) = address(dispatcher).call(abi.encodeWithSelector(bytes4(0xdeadbeef)));
        assertFalse(success, "Unknown selector should revert");
    }

    function test_Dispatch_emptyCalldataReverts() public {
        // Empty calldata should revert (no receive function, no matching selector)
        (bool success,) = address(dispatcher).call("");
        assertFalse(success, "Empty calldata should revert");
    }

    // =========================================================================
    // TODO 2: totalSupply
    // =========================================================================

    function test_TotalSupply_initiallyZero() public view {
        assertEq(token.totalSupply(), 0, "Initial totalSupply should be 0");
    }

    function test_TotalSupply_afterMint() public {
        token.mint(alice, 1000);
        assertEq(token.totalSupply(), 1000, "totalSupply should reflect minted amount");
    }

    // =========================================================================
    // TODO 3: balanceOf
    // =========================================================================

    function test_BalanceOf_unknownAddressReturnsZero() public view {
        assertEq(token.balanceOf(alice), 0, "Unknown address should have 0 balance");
    }

    function test_BalanceOf_afterMint() public {
        token.mint(alice, 500);
        assertEq(token.balanceOf(alice), 500, "balanceOf should return minted amount");
    }

    function testFuzz_BalanceOf_afterMint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount < type(uint128).max); // avoid overflow in totalSupply
        token.mint(to, amount);
        assertEq(token.balanceOf(to), amount, "balanceOf should match minted amount");
    }

    // =========================================================================
    // TODO 4: transfer
    // =========================================================================

    function test_Transfer_basic() public {
        token.mint(alice, 1000);

        vm.prank(alice);
        bool success = token.transfer(bob, 300);

        assertTrue(success, "transfer should return true");
        assertEq(token.balanceOf(alice), 700, "Sender balance should decrease");
        assertEq(token.balanceOf(bob), 300, "Recipient balance should increase");
    }

    function test_Transfer_insufficientBalanceReverts() public {
        token.mint(alice, 100);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(0xf4d678b8))); // InsufficientBalance()
        token.transfer(bob, 200);
    }

    function test_Transfer_zeroAmount() public {
        token.mint(alice, 1000);

        vm.prank(alice);
        bool success = token.transfer(bob, 0);

        assertTrue(success, "Zero transfer should succeed");
        assertEq(token.balanceOf(alice), 1000, "Sender balance unchanged after zero transfer");
        assertEq(token.balanceOf(bob), 0, "Recipient balance unchanged after zero transfer");
    }

    function test_Transfer_selfTransfer() public {
        token.mint(alice, 1000);

        vm.prank(alice);
        bool success = token.transfer(alice, 300);

        assertTrue(success, "Self-transfer should succeed");
        assertEq(token.balanceOf(alice), 1000, "Self-transfer should not change balance");
    }

    function test_Transfer_preservesTotalSupply() public {
        token.mint(alice, 1000);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        token.transfer(bob, 300);

        assertEq(token.totalSupply(), supplyBefore, "Transfer should not change totalSupply");
    }

    function testFuzz_Transfer_preservesTotal(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(transferAmount <= mintAmount);

        token.mint(alice, mintAmount);

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(
            token.balanceOf(alice) + token.balanceOf(bob),
            mintAmount,
            "Sum of balances should equal minted amount"
        );
    }

    // =========================================================================
    // TODO 5: mint
    // =========================================================================

    function test_Mint_onlyOwner() public {
        vm.prank(alice); // alice is not the owner
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x82b42900))); // Unauthorized()
        token.mint(alice, 1000);
    }

    function test_Mint_updatesBalance() public {
        token.mint(alice, 500);
        assertEq(token.balanceOf(alice), 500, "Mint should update recipient balance");
    }

    function test_Mint_updatesTotalSupply() public {
        token.mint(alice, 500);
        token.mint(bob, 300);
        assertEq(token.totalSupply(), 800, "totalSupply should be sum of all mints");
    }

    function test_Mint_multipleMintsSameAddress() public {
        token.mint(alice, 500);
        token.mint(alice, 300);
        assertEq(token.balanceOf(alice), 800, "Multiple mints should accumulate");
    }

    // =========================================================================
    // owner() — provided reference implementation
    // =========================================================================

    function test_Owner_returnsDeployer() public view {
        assertEq(token.owner(), deployer, "owner() should return the deployer");
    }
}

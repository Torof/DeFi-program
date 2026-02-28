// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE — it is the test suite for the IntentSettlement exercise.
//  Implement IntentSettlement.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    IntentSettlement,
    InvalidSignature,
    OrderExpired,
    OrderAlreadyFilled,
    InsufficientOutput
} from "../../../../src/part3/module4/exercise2-intent-settlement/IntentSettlement.sol";

/// @dev Simple mintable ERC-20 for testing.
contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract IntentSettlementTest is Test {
    IntentSettlement public settlement;

    TestToken public weth;
    TestToken public usdc;

    // User (offerer) — known private key for signing
    uint256 constant USER_PK = 0xA11CE;
    address user;

    // Solver (filler)
    address solver = makeAddr("solver");

    // Default order parameters
    uint256 constant INPUT_AMOUNT = 1e18;        // 1 WETH
    uint256 constant START_AMOUNT = 1950e18;      // Dutch auction start: 1950 USDC
    uint256 constant END_AMOUNT = 1900e18;        // Dutch auction end: 1900 USDC
    uint256 constant DECAY_DURATION = 90;         // 90 seconds

    function setUp() public {
        vm.warp(1_700_000_000);

        user = vm.addr(USER_PK);

        // Deploy contracts
        settlement = new IntentSettlement();
        weth = new TestToken("Wrapped Ether", "WETH");
        usdc = new TestToken("USD Coin", "USDC");

        // Fund accounts
        weth.mint(user, 100e18);
        usdc.mint(solver, 1_000_000e18);

        // Approvals
        vm.prank(user);
        weth.approve(address(settlement), type(uint256).max);

        vm.prank(solver);
        usdc.approve(address(settlement), type(uint256).max);
    }

    // =========================================================
    //  Helpers
    // =========================================================

    function _makeOrder(uint256 nonce) internal view returns (IntentSettlement.Order memory) {
        return IntentSettlement.Order({
            offerer: user,
            inputToken: address(weth),
            inputAmount: INPUT_AMOUNT,
            outputToken: address(usdc),
            startAmount: START_AMOUNT,
            endAmount: END_AMOUNT,
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + DECAY_DURATION,
            recipient: user,
            nonce: nonce
        });
    }

    function _signOrder(IntentSettlement.Order memory order)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 digest = settlement.getDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    // =========================================================
    //  hashOrder (TODO 1)
    // =========================================================

    function test_hashOrder_deterministic() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes32 hash1 = settlement.hashOrder(order);
        bytes32 hash2 = settlement.hashOrder(order);
        assertEq(hash1, hash2, "Same order should produce same hash");
    }

    function test_hashOrder_differentNonceDifferentHash() public view {
        IntentSettlement.Order memory order0 = _makeOrder(0);
        IntentSettlement.Order memory order1 = _makeOrder(1);
        assertNotEq(
            settlement.hashOrder(order0),
            settlement.hashOrder(order1),
            "Different nonces should produce different hashes"
        );
    }

    function test_hashOrder_differentAmountDifferentHash() public view {
        IntentSettlement.Order memory orderA = _makeOrder(0);
        IntentSettlement.Order memory orderB = _makeOrder(0);
        orderB.inputAmount = 2e18;
        assertNotEq(
            settlement.hashOrder(orderA),
            settlement.hashOrder(orderB),
            "Different input amounts should produce different hashes"
        );
    }

    function test_hashOrder_includesAllFields() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes32 baseHash = settlement.hashOrder(order);

        // Modify each field and verify the hash changes
        IntentSettlement.Order memory modified;

        modified = _makeOrder(0);
        modified.offerer = address(0xdead);
        assertNotEq(settlement.hashOrder(modified), baseHash, "offerer should affect hash");

        modified = _makeOrder(0);
        modified.recipient = address(0xbeef);
        assertNotEq(settlement.hashOrder(modified), baseHash, "recipient should affect hash");

        modified = _makeOrder(0);
        modified.startAmount = 9999e18;
        assertNotEq(settlement.hashOrder(modified), baseHash, "startAmount should affect hash");

        modified = _makeOrder(0);
        modified.endAmount = 1e18;
        assertNotEq(settlement.hashOrder(modified), baseHash, "endAmount should affect hash");

        modified = _makeOrder(0);
        modified.decayStartTime = 999;
        assertNotEq(settlement.hashOrder(modified), baseHash, "decayStartTime should affect hash");
    }

    // =========================================================
    //  getDigest (TODO 2)
    // =========================================================

    function test_getDigest_recoversCorrectSigner() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes32 digest = settlement.getDigest(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PK, digest);
        address recovered = ecrecover(digest, v, r, s);
        assertEq(recovered, user, "Digest should recover to the correct signer");
    }

    function test_getDigest_differentFromStructHash() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes32 structHash = settlement.hashOrder(order);
        bytes32 digest = settlement.getDigest(order);
        assertNotEq(digest, structHash, "Digest should include domain separator");
    }

    function test_getDigest_deterministic() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes32 d1 = settlement.getDigest(order);
        bytes32 d2 = settlement.getDigest(order);
        assertEq(d1, d2, "Same order should produce same digest");
    }

    // =========================================================
    //  resolveDecay (TODO 3)
    // =========================================================

    function test_resolveDecay_atStart() public view {
        IntentSettlement.Order memory order = _makeOrder(0);
        uint256 output = settlement.resolveDecay(order);
        assertEq(output, START_AMOUNT, "At decay start, output should equal startAmount");
    }

    function test_resolveDecay_atEnd() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        vm.warp(order.decayEndTime);
        uint256 output = settlement.resolveDecay(order);
        assertEq(output, END_AMOUNT, "At decay end, output should equal endAmount");
    }

    function test_resolveDecay_afterEnd() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        vm.warp(order.decayEndTime + 1000);
        uint256 output = settlement.resolveDecay(order);
        assertEq(output, END_AMOUNT, "After decay end, output should be clamped to endAmount");
    }

    function test_resolveDecay_beforeStart() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        order.decayStartTime = block.timestamp + 100;
        order.decayEndTime = block.timestamp + 200;
        uint256 output = settlement.resolveDecay(order);
        assertEq(output, START_AMOUNT, "Before decay start, output should equal startAmount");
    }

    function test_resolveDecay_midpoint() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        // Warp to exactly halfway: 45 seconds into 90-second decay
        vm.warp(order.decayStartTime + DECAY_DURATION / 2);
        uint256 output = settlement.resolveDecay(order);
        // midpoint: 1950 - (1950-1900) * 45/90 = 1950 - 25 = 1925
        assertEq(output, 1925e18, "At midpoint, output should be average of start and end");
    }

    function test_resolveDecay_oneThird() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        // Warp to 1/3: 30 seconds into 90-second decay
        vm.warp(order.decayStartTime + 30);
        uint256 output = settlement.resolveDecay(order);
        // 1950 - 50 * 30/90 = 1950 - 16.666... = 1933.333...
        // Integer: (50e18 * 30) / 90 = 1500e18 / 90 = 16.666...e18
        uint256 expected = START_AMOUNT - (START_AMOUNT - END_AMOUNT) * 30 / DECAY_DURATION;
        assertEq(output, expected, "At 1/3 decay, output should be correctly interpolated");
    }

    function test_resolveDecay_linearInterpolation() public {
        IntentSettlement.Order memory order = _makeOrder(0);

        // Check multiple points along the decay curve
        uint256 prevOutput = START_AMOUNT;
        for (uint256 t = 10; t <= DECAY_DURATION; t += 10) {
            vm.warp(order.decayStartTime + t);
            uint256 output = settlement.resolveDecay(order);

            // Output should be monotonically decreasing
            assertLe(output, prevOutput, "Output must decrease or stay flat over time");

            // Should be between start and end
            assertGe(output, END_AMOUNT, "Output must be >= endAmount");
            assertLe(output, START_AMOUNT, "Output must be <= startAmount");

            prevOutput = output;
        }
    }

    // =========================================================
    //  fill (TODO 4)
    // =========================================================

    function test_fill_basicSuccess() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        uint256 userWethBefore = weth.balanceOf(user);
        uint256 userUsdcBefore = usdc.balanceOf(user);
        uint256 solverWethBefore = weth.balanceOf(solver);
        uint256 solverUsdcBefore = usdc.balanceOf(solver);

        uint256 fillAmount = START_AMOUNT; // Fill at auction start = max output

        vm.prank(solver);
        settlement.fill(order, sig, fillAmount);

        // User sold WETH, received USDC
        assertEq(weth.balanceOf(user), userWethBefore - INPUT_AMOUNT, "User should send WETH");
        assertEq(usdc.balanceOf(user), userUsdcBefore + fillAmount, "User should receive USDC");

        // Solver received WETH, sent USDC
        assertEq(weth.balanceOf(solver), solverWethBefore + INPUT_AMOUNT, "Solver should receive WETH");
        assertEq(usdc.balanceOf(solver), solverUsdcBefore - fillAmount, "Solver should send USDC");
    }

    function test_fill_atDecayMidpoint() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Warp to midpoint
        vm.warp(order.decayStartTime + DECAY_DURATION / 2);

        // Required output at midpoint: 1925 USDC
        uint256 required = settlement.resolveDecay(order);
        assertEq(required, 1925e18, "Required should be 1925 at midpoint");

        // Solver fills at exactly the required amount
        vm.prank(solver);
        settlement.fill(order, sig, required);

        assertEq(usdc.balanceOf(user), required, "User should receive the decayed amount");
    }

    function test_fill_solverCanOverpay() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Solver provides MORE than required (competing for fill)
        uint256 overpay = START_AMOUNT + 100e18;

        vm.prank(solver);
        settlement.fill(order, sig, overpay);

        assertEq(usdc.balanceOf(user), overpay, "User receives the full overpay amount");
    }

    function test_fill_revertsOnInvalidSignature() public {
        IntentSettlement.Order memory order = _makeOrder(0);

        // Sign with wrong key
        uint256 wrongPK = 0xBAD;
        bytes32 digest = settlement.getDigest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPK, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(solver);
        vm.expectRevert(InvalidSignature.selector);
        settlement.fill(order, badSig, START_AMOUNT);
    }

    function test_fill_revertsOnExpiredOrder() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Warp past the decay end
        vm.warp(order.decayEndTime + 1);

        vm.prank(solver);
        vm.expectRevert(OrderExpired.selector);
        settlement.fill(order, sig, END_AMOUNT);
    }

    function test_fill_revertsOnReplay() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // First fill succeeds
        vm.prank(solver);
        settlement.fill(order, sig, START_AMOUNT);

        // Second fill with same nonce should revert
        vm.prank(solver);
        vm.expectRevert(OrderAlreadyFilled.selector);
        settlement.fill(order, sig, START_AMOUNT);
    }

    function test_fill_revertsOnInsufficientOutput() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Try to fill with less than required (at start, required = 1950)
        uint256 tooLow = START_AMOUNT - 1;

        vm.prank(solver);
        vm.expectRevert(InsufficientOutput.selector);
        settlement.fill(order, sig, tooLow);
    }

    function test_fill_differentNoncesAreIndependent() public {
        // Fill order with nonce 0
        IntentSettlement.Order memory order0 = _makeOrder(0);
        bytes memory sig0 = _signOrder(order0);

        vm.prank(solver);
        settlement.fill(order0, sig0, START_AMOUNT);

        // Fill order with nonce 1 should still work
        IntentSettlement.Order memory order1 = _makeOrder(1);
        bytes memory sig1 = _signOrder(order1);

        vm.prank(solver);
        settlement.fill(order1, sig1, START_AMOUNT);

        // User should have sold 2 WETH total and received 2 * START_AMOUNT USDC
        assertEq(weth.balanceOf(user), 100e18 - 2 * INPUT_AMOUNT, "Two fills should take 2 WETH");
    }

    function test_fill_nonceMarkedUsed() public {
        IntentSettlement.Order memory order = _makeOrder(42);
        bytes memory sig = _signOrder(order);

        assertFalse(settlement.nonces(user, 42), "Nonce should be unused before fill");

        vm.prank(solver);
        settlement.fill(order, sig, START_AMOUNT);

        assertTrue(settlement.nonces(user, 42), "Nonce should be marked used after fill");
    }

    function test_fill_toCustomRecipient() public {
        address recipient = makeAddr("recipient");

        IntentSettlement.Order memory order = _makeOrder(0);
        order.recipient = recipient;
        bytes memory sig = _signOrder(order);

        vm.prank(solver);
        settlement.fill(order, sig, START_AMOUNT);

        // Output goes to recipient, not the offerer
        assertEq(usdc.balanceOf(recipient), START_AMOUNT, "Output should go to recipient");
        assertEq(usdc.balanceOf(user), 0, "Offerer should not receive output");
    }

    // =========================================================
    //  Integration: full Dutch auction flow
    // =========================================================

    function test_integration_dutchAuctionFlow() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Simulate waiting for the auction to become profitable for the solver
        // Solver waits until 60s into the 90s decay
        vm.warp(order.decayStartTime + 60);

        uint256 required = settlement.resolveDecay(order);
        // 1950 - 50 * 60/90 = 1950 - 33.33... = 1916.66...
        uint256 expected = START_AMOUNT - (START_AMOUNT - END_AMOUNT) * 60 / DECAY_DURATION;
        assertEq(required, expected, "Required output at t=60s");

        // Solver fills at exactly the required amount
        vm.prank(solver);
        settlement.fill(order, sig, required);

        // Verify the trade executed
        assertEq(weth.balanceOf(solver), INPUT_AMOUNT, "Solver got the WETH");
        assertEq(usdc.balanceOf(user), required, "User got the decayed USDC amount");
    }

    function test_integration_fillAtEndOfAuction() public {
        IntentSettlement.Order memory order = _makeOrder(0);
        bytes memory sig = _signOrder(order);

        // Fill at exact end of auction (last moment before expiry)
        vm.warp(order.decayEndTime);

        uint256 required = settlement.resolveDecay(order);
        assertEq(required, END_AMOUNT, "At end, required should be endAmount");

        vm.prank(solver);
        settlement.fill(order, sig, required);

        assertEq(usdc.balanceOf(user), END_AMOUNT, "User gets the minimum at auction end");
    }
}

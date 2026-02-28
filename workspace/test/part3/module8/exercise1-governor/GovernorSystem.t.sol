// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
//  DO NOT MODIFY THIS FILE - it is the test suite for the GovernorSystem
//  exercise. Implement GovernorSystem.sol to make these tests pass.
// ============================================================================

import "forge-std/Test.sol";
import {
    GovernorSystem,
    IVotesToken,
    InsufficientVotingPower,
    ProposalNotActive,
    AlreadyVoted,
    ProposalNotSucceeded,
    NoVotingPower
} from "../../../../src/part3/module8/exercise1-governor/GovernorSystem.sol";
import {GovernanceToken} from "../../../../src/part3/module8/shared/GovernanceToken.sol";

contract GovernorSystemTest is Test {
    GovernanceToken public token;
    GovernorSystem public governor;

    // Actors
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    // Supply
    uint256 constant TOTAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        vm.startPrank(owner);
        token = new GovernanceToken(TOTAL_SUPPLY);
        governor = new GovernorSystem(address(token));

        // Distribute tokens
        token.transfer(alice, 200_000e18);
        token.transfer(bob, 150_000e18);
        vm.stopPrank();

        // Alice and Bob delegate to themselves (activates checkpointing)
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Advance 1 block so delegations create checkpoints
        vm.roll(block.number + 1);
    }

    // --- Helpers ---

    function _propose() internal returns (uint256 proposalId) {
        vm.prank(alice);
        proposalId = governor.propose();
    }

    function _proposeAndStartVoting() internal returns (uint256 proposalId) {
        proposalId = _propose();
        vm.roll(block.number + governor.VOTING_DELAY() + 1);
    }

    function _proposeVoteAndFinish() internal returns (uint256 proposalId) {
        proposalId = _proposeAndStartVoting();
        // Alice and Bob both vote FOR (350k >= 100k quorum)
        vm.prank(alice);
        governor.castVote(proposalId, true);
        vm.prank(bob);
        governor.castVote(proposalId, true);
        // Advance past voting period
        vm.roll(block.number + governor.VOTING_PERIOD());
    }

    // =========================================================
    //  propose (TODO 1)
    // =========================================================

    function test_propose_createsProposal() public {
        uint256 proposalId = _propose();
        assertEq(proposalId, 1, "First proposal should be ID 1");
        assertEq(governor.proposalCount(), 1, "Proposal count should be 1");
    }

    function test_propose_setsCorrectSnapshotBlock() public {
        uint256 blockBefore = block.number;
        uint256 proposalId = _propose();

        (uint256 snapshot, uint256 voteStart, uint256 voteEnd,,,) =
            governor.proposals(proposalId);

        assertEq(snapshot, blockBefore, "Snapshot should be creation block");
        assertEq(voteStart, blockBefore + governor.VOTING_DELAY(), "Vote start = creation + delay");
        assertEq(voteEnd, voteStart + governor.VOTING_PERIOD(), "Vote end = start + period");
    }

    function test_propose_emitsEvent() public {
        uint256 expectedId = 1;
        uint256 expectedSnapshot = block.number;
        uint256 expectedStart = block.number + governor.VOTING_DELAY();
        uint256 expectedEnd = expectedStart + governor.VOTING_PERIOD();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(governor));
        emit GovernorSystem.ProposalCreated(
            expectedId, alice, expectedSnapshot, expectedStart, expectedEnd
        );
        governor.propose();
    }

    function test_propose_revertsIfBelowThreshold() public {
        // Attacker has 0 tokens
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientVotingPower.selector, 0, governor.PROPOSAL_THRESHOLD())
        );
        governor.propose();
    }

    function test_propose_revertsIfTokensNotDelegated() public {
        // Owner has 650k tokens but never delegated — getVotes returns 0
        // This is a critical ERC20Votes gotcha: must delegate (even to yourself) to activate checkpoints
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientVotingPower.selector, 0, governor.PROPOSAL_THRESHOLD())
        );
        governor.propose();
    }

    function test_propose_multipleProposals() public {
        vm.startPrank(alice);
        uint256 id1 = governor.propose();
        uint256 id2 = governor.propose();
        vm.stopPrank();

        assertEq(id1, 1, "First proposal ID");
        assertEq(id2, 2, "Second proposal ID");
        assertEq(governor.proposalCount(), 2, "Two proposals total");
    }

    // =========================================================
    //  castVote (TODO 2)
    // =========================================================

    function test_castVote_recordsForVote() public {
        uint256 proposalId = _proposeAndStartVoting();

        vm.prank(alice);
        governor.castVote(proposalId, true);

        (,,, uint256 forVotes, uint256 againstVotes,) = governor.proposals(proposalId);
        assertEq(forVotes, 200_000e18, "Alice's 200k should be counted as FOR");
        assertEq(againstVotes, 0, "No against votes");
    }

    function test_castVote_recordsAgainstVote() public {
        uint256 proposalId = _proposeAndStartVoting();

        vm.prank(bob);
        governor.castVote(proposalId, false);

        (,,, uint256 forVotes, uint256 againstVotes,) = governor.proposals(proposalId);
        assertEq(forVotes, 0, "No for votes");
        assertEq(againstVotes, 150_000e18, "Bob's 150k should be counted as AGAINST");
    }

    function test_castVote_multipleVoters() public {
        uint256 proposalId = _proposeAndStartVoting();

        vm.prank(alice);
        governor.castVote(proposalId, true);
        vm.prank(bob);
        governor.castVote(proposalId, false);

        (,,, uint256 forVotes, uint256 againstVotes,) = governor.proposals(proposalId);
        assertEq(forVotes, 200_000e18, "Alice votes FOR");
        assertEq(againstVotes, 150_000e18, "Bob votes AGAINST");
    }

    function test_castVote_emitsEvent() public {
        uint256 proposalId = _proposeAndStartVoting();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(governor));
        emit GovernorSystem.VoteCast(proposalId, alice, true, 200_000e18);
        governor.castVote(proposalId, true);
    }

    function test_castVote_revertsBeforeVotingStarts() public {
        uint256 proposalId = _propose();
        // Don't advance past voting delay

        vm.prank(alice);
        vm.expectRevert(ProposalNotActive.selector);
        governor.castVote(proposalId, true);
    }

    function test_castVote_revertsAfterVotingEnds() public {
        uint256 proposalId = _proposeAndStartVoting();

        // Advance past voting period
        vm.roll(block.number + governor.VOTING_PERIOD() + 1);

        vm.prank(alice);
        vm.expectRevert(ProposalNotActive.selector);
        governor.castVote(proposalId, true);
    }

    function test_castVote_revertsIfAlreadyVoted() public {
        uint256 proposalId = _proposeAndStartVoting();

        vm.startPrank(alice);
        governor.castVote(proposalId, true);

        vm.expectRevert(abi.encodeWithSelector(AlreadyVoted.selector, alice));
        governor.castVote(proposalId, false);
        vm.stopPrank();
    }

    function test_castVote_revertsIfNoVotingPower() public {
        uint256 proposalId = _proposeAndStartVoting();

        // Attacker has no tokens and no delegated voting power
        vm.prank(attacker);
        vm.expectRevert(NoVotingPower.selector);
        governor.castVote(proposalId, true);
    }

    // =========================================================
    //  getState (TODO 3)
    // =========================================================

    function test_getState_pendingBeforeVoteStart() public {
        uint256 proposalId = _propose();
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Pending),
            "Should be Pending before voting starts"
        );
    }

    function test_getState_activeDuringVotingPeriod() public {
        uint256 proposalId = _proposeAndStartVoting();
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Active),
            "Should be Active during voting"
        );
    }

    function test_getState_succeededWithQuorum() public {
        uint256 proposalId = _proposeVoteAndFinish();

        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Succeeded),
            "Should be Succeeded with quorum met and FOR > AGAINST"
        );
    }

    function test_getState_defeatedWithoutQuorum() public {
        uint256 proposalId = _proposeAndStartVoting();

        // Nobody votes -> forVotes + againstVotes = 0 < QUORUM -> Defeated
        vm.roll(block.number + governor.VOTING_PERIOD());

        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Defeated),
            "Should be Defeated with no votes (quorum not met)"
        );
    }

    function test_getState_defeatedMoreAgainst() public {
        uint256 proposalId = _proposeAndStartVoting();

        // Alice votes FOR (200k), Bob votes AGAINST (150k)
        // Total = 350k >= 100k quorum, but we need AGAINST > FOR
        // Swap: Alice against, Bob for -> 200k against, 150k for -> Defeated
        vm.prank(alice);
        governor.castVote(proposalId, false); // 200k AGAINST
        vm.prank(bob);
        governor.castVote(proposalId, true); // 150k FOR

        vm.roll(block.number + governor.VOTING_PERIOD());

        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Defeated),
            "Should be Defeated when AGAINST > FOR"
        );
    }

    function test_getState_defeatedOnTie() public {
        // Give bob same amount as alice for a tie
        vm.prank(owner);
        token.transfer(bob, 50_000e18); // bob now has 200k
        vm.prank(bob);
        token.delegate(bob);
        vm.roll(block.number + 1);

        uint256 proposalId = _proposeAndStartVoting();

        vm.prank(alice);
        governor.castVote(proposalId, true); // 200k FOR
        vm.prank(bob);
        governor.castVote(proposalId, false); // 200k AGAINST

        vm.roll(block.number + governor.VOTING_PERIOD());

        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Defeated),
            "Tie should be Defeated (FOR must be strictly greater)"
        );
    }

    function test_getState_executedAfterExecution() public {
        uint256 proposalId = _proposeVoteAndFinish();
        governor.execute(proposalId);

        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Executed),
            "Should be Executed after execution"
        );
    }

    // =========================================================
    //  execute (TODO 4)
    // =========================================================

    function test_execute_marksProposalExecuted() public {
        uint256 proposalId = _proposeVoteAndFinish();
        governor.execute(proposalId);

        (,,,,, bool executed) = governor.proposals(proposalId);
        assertTrue(executed, "Proposal should be marked executed");
    }

    function test_execute_emitsEvent() public {
        uint256 proposalId = _proposeVoteAndFinish();

        vm.expectEmit(true, false, false, false, address(governor));
        emit GovernorSystem.ProposalExecuted(proposalId);
        governor.execute(proposalId);
    }

    function test_execute_revertsIfNotSucceeded() public {
        uint256 proposalId = _proposeAndStartVoting();
        // Still active, not succeeded

        vm.expectRevert(ProposalNotSucceeded.selector);
        governor.execute(proposalId);
    }

    function test_execute_revertsIfDefeated() public {
        uint256 proposalId = _proposeAndStartVoting();
        // No votes -> advance past voting
        vm.roll(block.number + governor.VOTING_PERIOD());

        vm.expectRevert(ProposalNotSucceeded.selector);
        governor.execute(proposalId);
    }

    function test_execute_revertsIfAlreadyExecuted() public {
        uint256 proposalId = _proposeVoteAndFinish();
        governor.execute(proposalId);

        // Try to execute again
        vm.expectRevert(ProposalNotSucceeded.selector);
        governor.execute(proposalId);
    }

    // =========================================================
    //  Flash Loan Defense (THE KEY TEST)
    // =========================================================

    function test_flashLoan_tokensAcquiredAfterSnapshotHaveNoPower() public {
        // Step 1: Alice proposes at block N (snapshot = N)
        vm.prank(alice);
        uint256 proposalId = governor.propose();
        uint256 snapshotBlock = block.number;

        // Step 2: Advance 1 block
        vm.roll(block.number + 1);

        // Step 3: Attacker acquires tokens AFTER the snapshot
        vm.prank(owner);
        token.transfer(attacker, 200_000e18);
        vm.prank(attacker);
        token.delegate(attacker);

        // Step 4: Advance to create checkpoint
        vm.roll(block.number + 1);

        // VERIFY: attacker HAS current voting power
        assertGt(token.getVotes(attacker), 0, "Attacker should have current voting power");

        // VERIFY: at the snapshot block, attacker has ZERO power
        assertEq(
            token.getPastVotes(attacker, snapshotBlock),
            0,
            "Attacker should have zero power at snapshot (flash loan defense)"
        );

        // Step 5: Attacker tries to vote - BLOCKED by snapshot
        vm.prank(attacker);
        vm.expectRevert(NoVotingPower.selector);
        governor.castVote(proposalId, true);
    }

    // =========================================================
    //  Integration: Full Governance Lifecycle
    // =========================================================

    function test_integration_fullLifecycle() public {
        // Phase 1: Create proposal
        vm.prank(alice);
        uint256 proposalId = governor.propose();
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Pending),
            "Phase 1: Pending"
        );

        // Phase 2: Advance to voting
        vm.roll(block.number + governor.VOTING_DELAY() + 1);
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Active),
            "Phase 2: Active"
        );

        // Phase 3: Cast votes
        vm.prank(alice);
        governor.castVote(proposalId, true); // 200k FOR
        vm.prank(bob);
        governor.castVote(proposalId, true); // 150k FOR

        // Phase 4: Advance past voting
        vm.roll(block.number + governor.VOTING_PERIOD());
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Succeeded),
            "Phase 4: Succeeded"
        );

        // Phase 5: Execute
        governor.execute(proposalId);
        assertEq(
            uint256(governor.getState(proposalId)),
            uint256(GovernorSystem.ProposalState.Executed),
            "Phase 5: Executed"
        );
    }

    // =========================================================
    //  Fuzz Tests
    // =========================================================

    function testFuzz_voteWeightMatchesSnapshot(uint256 aliceAmount) public {
        aliceAmount = bound(aliceAmount, governor.PROPOSAL_THRESHOLD(), TOTAL_SUPPLY / 2);

        // Fresh setup with custom amount
        GovernanceToken freshToken = new GovernanceToken(TOTAL_SUPPLY);
        GovernorSystem freshGov = new GovernorSystem(address(freshToken));

        freshToken.transfer(alice, aliceAmount);
        vm.prank(alice);
        freshToken.delegate(alice);
        vm.roll(block.number + 1);

        // Propose
        vm.prank(alice);
        uint256 proposalId = freshGov.propose();
        uint256 snapshot = block.number;

        // Advance to voting
        vm.roll(block.number + freshGov.VOTING_DELAY() + 1);

        // Vote
        vm.prank(alice);
        freshGov.castVote(proposalId, true);

        // Verify vote weight matches snapshot
        (,,, uint256 forVotes,,) = freshGov.proposals(proposalId);
        assertEq(
            forVotes,
            freshToken.getPastVotes(alice, snapshot),
            "INVARIANT: vote weight must match snapshot voting power"
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE 1: Simple Governor with Snapshot Voting
//
// Build a simplified on-chain governance system that uses ERC20Votes checkpoints
// to determine voting power at proposal creation time (the "snapshot" block).
// This is the core mechanism that makes governance secure against flash loan
// attacks -- tokens acquired AFTER the snapshot have zero voting power.
//
// Concepts exercised:
//   - Snapshot-based voting with getPastVotes
//   - Proposal lifecycle: Pending -> Active -> Succeeded/Defeated -> Executed
//   - Voting delay and voting period timing (block-based)
//   - Quorum and threshold enforcement
//   - Flash loan defense through checkpointed voting power
//
// Key references:
//   - Module 8 lesson: "On-Chain Governance" -> Governor framework
//   - Module 8 lesson: "Governance Security" — Beanstalk Attack
//   - OpenZeppelin Governor pattern
//
// Run: forge test --match-contract GovernorSystemTest -vvv
// ============================================================================

error InsufficientVotingPower(uint256 available, uint256 required);
error ProposalNotActive();
error AlreadyVoted(address voter);
error ProposalNotSucceeded();
error NoVotingPower();

/// @notice Minimal interface for ERC20Votes tokens.
interface IVotesToken {
    function getVotes(address account) external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
}

/// @notice Simple governor with snapshot-based voting.
/// @dev Pre-built: state, types, constants, constructor, events.
///      Student implements: propose, castVote, getState, execute.
contract GovernorSystem {
    // --- Types ---
    enum ProposalState { Pending, Active, Succeeded, Defeated, Executed }

    struct Proposal {
        uint256 snapshotBlock;   // block at which voting power is measured
        uint256 voteStart;       // block at which voting begins
        uint256 voteEnd;         // block at which voting ends
        uint256 forVotes;        // total votes in favor
        uint256 againstVotes;    // total votes against
        bool executed;           // has the proposal been executed?
    }

    // --- Constants ---
    /// @dev Number of blocks after proposing before voting begins
    uint256 public constant VOTING_DELAY = 1;

    /// @dev Number of blocks that voting lasts (short for testing)
    uint256 public constant VOTING_PERIOD = 100;

    /// @dev Minimum total votes (for + against) for a proposal to pass
    uint256 public constant QUORUM = 100_000e18;

    /// @dev Minimum voting power needed to create a proposal
    uint256 public constant PROPOSAL_THRESHOLD = 10_000e18;

    // --- State ---
    IVotesToken public immutable token;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    // --- Events ---
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 snapshotBlock,
        uint256 voteStart,
        uint256 voteEnd
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _token) {
        token = IVotesToken(_token);
    }

    // =============================================================
    //  TODO 1: Implement propose
    // =============================================================
    /// @notice Create a new governance proposal.
    /// @dev The snapshot block = block.number at proposal creation.
    ///      This is THE key security mechanism: voting power is frozen at
    ///      this block, so tokens acquired later (e.g., via flash loan) have
    ///      zero weight.
    ///
    ///      Steps:
    ///        1. Check msg.sender has >= PROPOSAL_THRESHOLD voting power
    ///           Use token.getVotes(msg.sender) for CURRENT power
    ///           Revert with InsufficientVotingPower(available, required) if not
    ///        2. Increment proposalCount to get the new proposal ID
    ///           proposalId = ++proposalCount
    ///        3. Store the proposal:
    ///           - snapshotBlock = block.number
    ///           - voteStart = block.number + VOTING_DELAY
    ///           - voteEnd = voteStart + VOTING_PERIOD
    ///           - forVotes = 0, againstVotes = 0, executed = false
    ///        4. Emit ProposalCreated event
    ///        5. Return proposalId
    ///
    ///      From the lesson:
    ///        "The proposal snapshots voting power at creation block.
    ///         This is what makes flash loan attacks fail -- tokens
    ///         borrowed AFTER this block have zero voting weight."
    ///
    /// @return proposalId The ID of the newly created proposal
    function propose() external returns (uint256 proposalId) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement castVote
    // =============================================================
    /// @notice Cast a vote on an active proposal.
    /// @dev This is where snapshot voting power comes into play.
    ///
    ///      The CRITICAL line is:
    ///        uint256 weight = token.getPastVotes(msg.sender, proposal.snapshotBlock);
    ///
    ///      This reads the voter's HISTORICAL balance at the snapshot block,
    ///      NOT their current balance. This is the flash loan defense.
    ///
    ///      Steps:
    ///        1. Load the proposal from storage
    ///        2. Check that the proposal is Active:
    ///           - block.number >= voteStart AND block.number <= voteEnd
    ///           - Revert ProposalNotActive() if not
    ///        3. Check voter hasn't already voted
    ///           - Revert AlreadyVoted(msg.sender) if true
    ///        4. Get voting weight at snapshot:
    ///           token.getPastVotes(msg.sender, proposal.snapshotBlock)
    ///        5. Require weight > 0 - revert NoVotingPower() if zero
    ///        6. Mark hasVoted[proposalId][msg.sender] = true
    ///        7. Add weight to forVotes (if support=true) or againstVotes
    ///        8. Emit VoteCast event
    ///
    /// @param proposalId The proposal to vote on
    /// @param support True = vote FOR, False = vote AGAINST
    function castVote(uint256 proposalId, bool support) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement getState
    // =============================================================
    /// @notice Get the current state of a proposal.
    /// @dev The proposal state machine:
    ///
    ///      +---------+     +--------+     +-----------+     +----------+
    ///      | Pending | --> | Active | --> | Succeeded | --> | Executed |
    ///      +---------+     +--------+     +-----------+     +----------+
    ///                                      |
    ///                                      +---> +----------+
    ///                                            | Defeated |
    ///                                            +----------+
    ///
    ///      Logic (check in this order):
    ///        1. If proposal.executed == true -> Executed
    ///        2. If block.number < voteStart -> Pending
    ///        3. If block.number <= voteEnd -> Active
    ///        4. If forVotes > againstVotes AND (forVotes + againstVotes) >= QUORUM
    ///           -> Succeeded
    ///        5. Otherwise -> Defeated
    ///
    ///      A proposal is Defeated if:
    ///        - Not enough total votes (quorum not met)
    ///        - More against votes than for votes
    ///        - Equal for and against (tie = defeated)
    ///
    /// @param proposalId The proposal to check
    /// @return The current ProposalState
    function getState(uint256 proposalId) public view returns (ProposalState) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement execute
    // =============================================================
    /// @notice Execute a succeeded proposal.
    /// @dev In a real governor, this would call target contracts via a timelock.
    ///      In this exercise, it just marks the proposal as executed.
    ///
    ///      Steps:
    ///        1. Check getState(proposalId) == Succeeded
    ///           Revert ProposalNotSucceeded() if not
    ///        2. Set proposal.executed = true
    ///        3. Emit ProposalExecuted event
    ///
    ///      Note: If already executed, getState returns Executed (not Succeeded),
    ///      so step 1 catches double-execution automatically.
    ///
    /// @param proposalId The proposal to execute
    function execute(uint256 proposalId) external {
        // YOUR CODE HERE
    }
}

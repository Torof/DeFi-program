# Part 3 — Module 8: Governance & DAOs

> **Prerequisites:** Part 2 — Modules 1 (Token Mechanics), 6 (Stablecoins & CDPs) | Part 3 — Modules 6 (Cross-Chain), 7 (L2-Specific DeFi)

## 📚 Table of Contents

1. [On-Chain Governance](#on-chain-governance)
2. [OpenZeppelin Governor in Practice](#oz-governor)
3. [ve-Tokenomics & the Curve Wars](#ve-tokenomics)
4. [Governance Security](#governance-security)
5. [Governance Minimization](#governance-minimization)
6. [Interview Prep](#interview-prep)
7. [Exercises](#exercises)
8. [Resources](#resources)

---

## Overview

Every major DeFi protocol needs a mechanism for parameter updates, upgrades, and strategic decisions. Governance is how protocols evolve after deployment — and also one of the most exploited attack surfaces in DeFi.

**Why this matters for you:**
- Every DeFi protocol you work on will have governance — understanding the lifecycle and security is essential
- ve-tokenomics (Curve, Velodrome) is one of the most important DeFi innovations — it reshapes protocol economics
- The Beanstalk attack ($182M) shows what happens when governance security is wrong
- Governance design is a frequent interview topic — "how would you design governance for X protocol?"
- Connection to Module 7: cross-chain governance (vote on L1, execute on L2) is the multi-chain standard
- Connection to Part 2 Module 9: your capstone's immutable design was itself a governance choice

---

<a id="on-chain-governance"></a>
## On-Chain Governance

### 💡 Why Governance Exists

Protocols need to change after deployment:
- **Risk parameters**: LTV ratios, interest rate curves, collateral types (Part 2 Module 4)
- **Fee management**: swap fees, protocol revenue distribution
- **Treasury**: fund allocation, grants, strategic investments
- **Upgrades**: proxy implementations, new features (Part 1 Module 5)
- **Emergency**: pause, parameter adjustment, shutdown (Part 2 Module 6 ESM)

**The fundamental tension:** Decentralization vs operational agility. A multisig can act in minutes; full on-chain governance takes 1-2 weeks. The right answer depends on what's being governed and the protocol's maturity stage.

### The Proposal Lifecycle

Every on-chain governance system follows the same flow:

```
 PROPOSE        DELAY          VOTE          QUEUE         EXECUTE
───────── → ─────────── → ─────────── → ─────────── → ───────────
 Proposer     Community      Token         Timelock       Anyone
 submits      reviews        holders       enforces       triggers
 on-chain     proposal       vote          delay          execution
             (1-2 days)    (3-7 days)    (24-48h)

Total: 5-14 days from proposal to execution
```

**Why each step exists:**
- **Delay** — prevents surprise proposals; community can review before voting starts
- **Vote** — democratic decision with quorum requirements
- **Queue/Timelock** — critical safety net: users who disagree can exit before changes take effect. If governance passes a malicious proposal, the timelock gives users time to withdraw.

### Voting Power Mechanisms

| Mechanism | Formula | Pros | Cons | Used By |
|---|---|---|---|---|
| **Token-weighted** | 1 token = 1 vote | Simple, transparent | Plutocratic | Uniswap, Aave, Compound |
| **Delegation** | Delegates accumulate voting power | Reduces voter apathy | Delegation centralization | All major governors |
| **Vote-escrow (ve)** | Lock duration × amount | Aligns long-term incentives | Complex, illiquid | Curve, Velodrome |
| **Quadratic** | √tokens = votes | More egalitarian | Sybil-vulnerable | Gitcoin (off-chain) |

---

<a id="oz-governor"></a>
## OpenZeppelin Governor in Practice

### 💡 The Standard Governance Stack

OpenZeppelin Governor is the industry standard — used by most new DeFi protocols. Understanding its code is essential.

**The three contracts:**

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  ERC20Votes      │     │  Governor        │     │  Timelock        │
│                  │     │                  │     │  Controller      │
│  • delegate()    │────→│  • propose()     │────→│  • schedule()    │
│  • getVotes()    │     │  • castVote()    │     │  • execute()     │
│  • getPastVotes()│     │  • queue()       │     │  • cancel()      │
│                  │     │  • execute()     │     │                  │
│  Checkpointing:  │     │                  │     │  Roles:          │
│  records balance │     │  Checks quorum,  │     │  PROPOSER_ROLE   │
│  at each block   │     │  threshold,      │     │  EXECUTOR_ROLE   │
│                  │     │  voting period   │     │  CANCELLER_ROLE  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### The ERC20Votes Token

```solidity
// Key concept: delegation activates voting power
// Holding tokens alone does NOT give voting power — you must delegate

import { ERC20, ERC20Votes, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract GovernanceToken is ERC20, ERC20Votes, ERC20Permit {
    constructor() ERC20("GovToken", "GOV") ERC20Permit("GovToken") {
        _mint(msg.sender, 1_000_000e18);
    }

    // Required overrides for ERC20Votes
    function _update(address from, address to, uint256 value)
        internal override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public view override(ERC20Permit, Nonces) returns (uint256)
    {
        return super.nonces(owner);
    }
}
```

**Critical detail — checkpointing:**

```solidity
// ERC20Votes stores voting power snapshots at each block
// This is what prevents flash loan attacks

// When alice delegates to herself:
token.delegate(alice);  // at block 100

// Alice's voting power at block 100+: 1000 tokens
// If alice gets more tokens at block 200 (via flash loan):
// Her voting power at block 100 is still 1000 (historical snapshot)

// Governor uses getPastVotes(alice, proposalSnapshot):
uint256 votes = token.getPastVotes(alice, proposalSnapshot);
// proposalSnapshot = block when proposal was created
// Flash-borrowed tokens at block 200 don't count for a proposal created at block 100
```

### Governor + Timelock Integration

```solidity
import { Governor } from "@openzeppelin/contracts/governance/Governor.sol";
import { GovernorVotes } from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import { GovernorCountingSimple } from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import { GovernorTimelockControl } from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract MyGovernor is Governor, GovernorVotes, GovernorCountingSimple, GovernorTimelockControl {

    constructor(IVotes _token, TimelockController _timelock)
        Governor("MyGovernor")
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
    {}

    // Governance parameters — these define the security model
    function votingDelay() public pure override returns (uint256) {
        return 7200;    // ~1 day (in blocks, 12s/block)
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50400;   // ~1 week
    }

    function proposalThreshold() public pure override returns (uint256) {
        return 10_000e18;  // need 10k tokens to propose
    }

    function quorum(uint256) public pure override returns (uint256) {
        return 100_000e18;  // 100k tokens must participate (10% of 1M supply)
    }
}
```

### The Full Lifecycle in Code

```solidity
// 1. PROPOSE — submit targets + values + calldatas + description
address[] memory targets = new address[](1);
targets[0] = address(myProtocol);
uint256[] memory values = new uint256[](1);
values[0] = 0;
bytes[] memory calldatas = new bytes[](1);
calldatas[0] = abi.encodeCall(MyProtocol.setFee, (500)); // set fee to 5%

uint256 proposalId = governor.propose(
    targets, values, calldatas,
    "Proposal #1: Increase fee to 5%"
);
// Snapshot taken at this block — only current token holders can vote

// 2. VOTE — after votingDelay() blocks
governor.castVote(proposalId, 1);  // 0 = against, 1 = for, 2 = abstain

// 3. QUEUE — after votingPeriod() ends + quorum met + majority for
governor.queue(targets, values, calldatas, descriptionHash);
// → Queued in TimelockController with delay

// 4. EXECUTE — after timelock delay expires
governor.execute(targets, values, calldatas, descriptionHash);
// → TimelockController calls myProtocol.setFee(500)
```

💻 **Quick Try:**

In Foundry, you can test the full governance lifecycle:

```solidity
// In your test file:
function test_GovernanceLifecycle() public {
    // Setup: give alice tokens and have her delegate to herself
    token.transfer(alice, 200_000e18);
    vm.prank(alice);
    token.delegate(alice);
    vm.roll(block.number + 1); // checkpoint needs 1 block

    // Propose
    uint256 proposalId = governor.propose(targets, values, calldatas, "Set fee");

    // Advance past voting delay
    vm.roll(block.number + governor.votingDelay() + 1);

    // Vote
    vm.prank(alice);
    governor.castVote(proposalId, 1); // vote FOR

    // Advance past voting period
    vm.roll(block.number + governor.votingPeriod() + 1);

    // Queue in timelock
    governor.queue(targets, values, calldatas, keccak256("Set fee"));

    // Advance past timelock delay
    vm.warp(block.timestamp + timelock.getMinDelay() + 1);

    // Execute
    governor.execute(targets, values, calldatas, keccak256("Set fee"));

    // Verify the parameter changed
    assertEq(myProtocol.fee(), 500);
}
```

This test pattern is exactly what your Exercise 1 will use.

### 📖 How to Study: OpenZeppelin Governor

1. Start with `ERC20Votes.sol` — understand delegation and `_checkpoints` mapping
2. Read `Governor.propose()` — how a proposal is created and the snapshot is taken
3. Trace `castVote()` → `_countVote()` — how votes are recorded and counted
4. Follow `queue()` → `TimelockController.schedule()` — how execution is delayed
5. Study `execute()` → `TimelockController.execute()` — how the timelock calls the target
6. Read the access control: who can propose (threshold), who can execute (anyone after timelock)

> 🔍 **Code:** [OpenZeppelin Governor](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/governance)

---

<a id="ve-tokenomics"></a>
## ve-Tokenomics & the Curve Wars

### 💡 Vote-Escrow: Locking for Influence

The ve (vote-escrow) model is one of DeFi's most influential innovations. It transforms a governance token from a speculative asset into an incentive-alignment tool.

### The veCRV Model

```
Lock CRV tokens for 1-4 years → receive veCRV (non-transferable)

  Lock duration    veCRV per CRV
  ────────────     ─────────────
  4 years          1.00 veCRV      (maximum)
  2 years          0.50 veCRV
  1 year           0.25 veCRV
  1 week           0.0048 veCRV    (minimum)
```

### 🔍 Deep Dive: veCRV Decay Math

The core formula — voting power decays linearly toward zero as the lock approaches expiry:

```
votingPower = lockedAmount × (lockEnd - now) / MAX_LOCK_TIME

Where:
  lockedAmount = CRV tokens locked
  lockEnd = timestamp when lock expires
  MAX_LOCK_TIME = 4 years (126,144,000 seconds)
  now = current timestamp
```

**Worked example:**

```
Alice locks 10,000 CRV for 4 years:
  t = 0:   votingPower = 10,000 × (4y - 0) / 4y = 10,000 veCRV
  t = 1y:  votingPower = 10,000 × (4y - 1y) / 4y = 7,500 veCRV
  t = 2y:  votingPower = 10,000 × (4y - 2y) / 4y = 5,000 veCRV
  t = 3y:  votingPower = 10,000 × (4y - 3y) / 4y = 2,500 veCRV
  t = 4y:  votingPower = 10,000 × (4y - 4y) / 4y = 0 veCRV (expired)

         veCRV
10,000 │ ●
       │   ●
 7,500 │     ●
       │       ●
 5,000 │         ●
       │           ●
 2,500 │             ●
       │               ●
     0 │─────────────────●──── time
       0    1y   2y   3y   4y
```

**Why linear decay matters:** It forces continuous re-locking. To maintain maximum voting power, you must keep extending your lock. This ensures that voters have ongoing skin in the game — they can't vote and then immediately unlock.

**In Solidity (simplified from Curve's VotingEscrow.vy):**

```solidity
contract SimpleVotingEscrow {
    struct LockedBalance {
        uint256 amount;
        uint256 end;      // lock expiry timestamp
    }

    uint256 public constant MAX_LOCK = 4 * 365 days;
    mapping(address => LockedBalance) public locked;

    function createLock(uint256 amount, uint256 duration) external {
        require(duration >= 1 weeks && duration <= MAX_LOCK, "Invalid duration");
        require(locked[msg.sender].amount == 0, "Already locked");

        locked[msg.sender] = LockedBalance({
            amount: amount,
            end: block.timestamp + duration
        });

        token.transferFrom(msg.sender, address(this), amount);
    }

    function votingPower(address user) public view returns (uint256) {
        LockedBalance memory lock = locked[user];
        if (block.timestamp >= lock.end) return 0;
        return lock.amount * (lock.end - block.timestamp) / MAX_LOCK;
    }

    function withdraw() external {
        require(block.timestamp >= locked[msg.sender].end, "Still locked");
        uint256 amount = locked[msg.sender].amount;
        delete locked[msg.sender];
        token.transfer(msg.sender, amount);
    }
}
```

### Three Powers of veCRV

**1. Gauge voting — directing emissions:**

```
Each Curve pool has a "gauge" that receives CRV emissions.
veCRV holders vote weekly on how to distribute emissions:

  Pool A (3CRV):     40% of votes → 40% of weekly CRV emissions
  Pool B (stETH/ETH): 35% of votes → 35% of weekly CRV emissions
  Pool C (FRAX/USDC):  25% of votes → 25% of weekly CRV emissions

More emissions → more rewards for LPs → more liquidity → deeper pool
```

**2. Boosted LP rewards — up to 2.5x:**

```
Base LP yield: 5% APR
With max boost (sufficient veCRV): 12.5% APR (2.5x)

Boost formula (simplified):
  boost = min(2.5, (0.4 * userLiquidity + 0.6 * totalLiquidity * (userVeCRV / totalVeCRV)) / userLiquidity)

Translation: your boost depends on your share of veCRV relative to your share of the pool
```

**3. Protocol fee sharing — 50% of trading fees:**

veCRV holders receive 50% of all Curve trading fees, distributed in 3CRV (the stablecoin LP token).

### The Curve Wars

The gauge voting power creates a competitive market:

```
Protocol wants deep liquidity for its token pair on Curve
  → Needs CRV emissions directed to its pool's gauge
  → Options:
    1. Buy CRV, lock as veCRV, vote for own pool (expensive)
    2. Bribe existing veCRV holders to vote for their pool (cheaper!)

Enter Convex Finance:
  → Aggregates CRV from thousands of users
  → Locks ALL of it as veCRV (permanently!)
  → vlCVX holders vote on how Convex directs its massive veCRV position
  → Meta-governance: controlling Convex = controlling Curve emissions

The bribery market:
  Protocol pays $1 in bribes to vlCVX holders
  → Those voters direct $1.50+ of CRV emissions to the protocol's pool
  → Protocol gets $1.50 of liquidity incentives for $1 spent
  → Voters earn $1 for voting (which is free for them)
  → Everyone wins — the "Curve Wars" flywheel

  Bribe platforms: Votium, Hidden Hand, Paladin
```

**Why this matters:** The Curve Wars demonstrate that governance is not just about "voting on proposals" — it's an economic game where voting power has direct monetary value. Understanding this is essential for designing tokenomics.

### Velodrome/Aerodrome: ve(3,3)

The ve(3,3) model fixes Curve's incentive misalignment:

```
Curve's problem:
  veCRV holders earn fees from ALL pools, regardless of which pools they vote for
  → Misaligned: voters can vote for bribed pools even if those pools generate no fees

Velodrome's fix:
  veVELO holders earn fees ONLY from pools they vote for
  → Direct alignment: vote for high-volume pools = earn more fees
  → No need for bribes on high-volume pools — the fees ARE the incentive
  → Bribes only needed for new/low-volume pools that need bootstrapping
```

**Anti-dilution:** Voters receive proportional new emissions as a rebase. Non-voters get diluted over time. This incentivizes continuous participation.

**Result:** Velodrome is the dominant DEX on Optimism; Aerodrome is the dominant DEX on Base. The ve(3,3) model works especially well on L2s (Module 7 connection) because the cheap gas makes weekly voting/claiming practical for all users, not just whales.

### 🔗 DeFi Pattern Connection

**Governance tokenomics across the curriculum:**

| Pattern | Where It Appears | Module |
|---|---|---|
| Token-weighted voting | Uniswap, Aave, Compound governance | This module |
| Vote-escrow (ve) | Curve, Velodrome, Aerodrome | This module |
| Gauge emissions | Directing liquidity incentives | This module, P2M2 |
| Protocol-owned liquidity | Treasury as strategic asset | This module |
| Immutable governance | Liquity zero-governance | This module, P2M9 capstone |
| Cross-chain governance | Vote on L1, execute on L2 | Modules 6, 7 |
| Emergency shutdown | MakerDAO ESM | Part 2 Module 6 |

---

<a id="governance-security"></a>
## Governance Security

### 💡 When Governance Itself Is the Attack Surface

### The Beanstalk Attack ($182M, April 2022)

The most expensive governance attack in DeFi history — and entirely preventable.

**What happened:**

```
Beanstalk's governance had NO voting delay and NO timelock.
A proposal could be created, voted on, and executed in ONE transaction.

Attack:
1. Attacker flash-borrowed massive governance tokens from Aave + SushiSwap
2. Created a malicious proposal: "Transfer entire treasury to attacker"
3. Voted FOR with flash-borrowed tokens (overwhelming majority)
4. Proposal passed immediately (no quorum issues — massive tokens)
5. Executed the proposal in the SAME transaction
6. Returned flash-borrowed tokens
7. Kept $182M of drained treasury

Total time: 1 Ethereum transaction (~13 seconds)
```

**Why it worked:** No voting delay meant tokens acquired in the same block could vote. No timelock meant the proposal executed immediately. Flash loans provided unlimited temporary capital.

**What would have prevented it:**

```
Defense 1: SNAPSHOT-BASED VOTING (OpenZeppelin default)
  → Voting power recorded at proposal creation block
  → Tokens acquired AFTER snapshot don't count
  → Flash-borrowed tokens are acquired after the proposal exists
  → Attack fails: flash tokens have zero voting power

Defense 2: VOTING DELAY (1+ blocks)
  → Gap between proposal creation and voting start
  → Flash loan must span multiple blocks (impossible — single-tx only)
  → Attack fails: can't vote in the proposal creation transaction

Defense 3: TIMELOCK
  → Even if proposal passes, execution delayed 24-48h
  → Community can review and respond
  → Users can exit before malicious changes take effect
  → Attack fails: treasury drain is visible and can be countered

Production protocols use ALL THREE. Beanstalk had NONE.
```

💻 **Quick Try:**

In Foundry, prove that snapshot voting defeats flash loans:

```solidity
contract FlashLoanDefenseDemo {
    // ERC20Votes token uses checkpoints — votes are recorded per block

    function test_flashLoanCantVote() public {
        // Block 100: proposal created, snapshot = block 100
        uint256 proposalId = governor.propose(...);

        // Block 100 (same block): attacker flash-borrows tokens
        // attacker's balance at block 100 BEFORE the borrow = 0
        // getPastVotes(attacker, block 100) = 0  ← checkpoint was 0!

        // Advance to voting period
        vm.roll(block.number + governor.votingDelay() + 1);

        // Attacker tries to vote — but has 0 votes at snapshot
        vm.prank(attacker);
        // governor.castVote(proposalId, 1);  ← would have 0 weight

        // Defense works: tokens acquired after snapshot have no power
    }
}
```

### Other Governance Attack Vectors

**Delegation attacks:**
- Accumulate delegated voting power from many small holders through social engineering
- Vote maliciously before delegators can react and re-delegate
- Defense: delegation monitoring, delegation caps, delegation lockup periods

**Low-quorum exploitation:**
- Wait for low participation period (holidays, market crisis)
- Pass controversial proposal with minimal opposition
- Defense: adequate quorum thresholds, emergency guardian pause

**Governance extraction:**
- Whale accumulates enough voting power to pass self-serving proposals
- Example: redirect treasury funds to themselves, change fee structure
- Defense: timelock (users can exit), guardian multisig (can veto), vote-escrow (long-term alignment)

### Emergency Mechanisms

Production protocols combine governance with fast-response capabilities:

```solidity
/// @notice Emergency guardian — can pause but NOT upgrade
contract EmergencyGuardian {
    address public guardian;  // multisig (e.g., 3/5 team members)
    IProtocol public protocol;

    // Guardian can PAUSE — immediate response to exploits
    function pause() external onlyGuardian {
        protocol.pause();
    }

    // Guardian can UNPAUSE — resume normal operation
    function unpause() external onlyGuardian {
        protocol.unpause();
    }

    // Guardian CANNOT: upgrade contracts, change parameters, move funds
    // Those require full governance (Governor + Timelock)
}
```

**The pattern used by major protocols:**

```
Aave:
  Guardian multisig → can pause markets (fast, centralized)
  Governor + Timelock → parameter changes, upgrades (slow, decentralized)

MakerDAO:
  Emergency Shutdown Module (ESM) → anyone can trigger with enough MKR
  Governance → parameter changes, new collateral types
  (Requires depositing MKR into ESM — tokens are burned, so it's costly to trigger)

Compound:
  Pause Guardian → can pause individual markets
  Governor Bravo → all parameter and upgrade changes
```

---

<a id="governance-minimization"></a>
## Governance Minimization

### 💡 Less Governance Can Be Better

Every governable parameter is an attack surface. The more things governance can change, the more ways the protocol can be exploited or manipulated.

### The Spectrum

```
FULL GOVERNANCE ──────────────────────────────── IMMUTABLE
  │                    │                    │            │
  Multisig          Governor +           Minimal       Zero
  (most agile)      Timelock            governance    governance
  │                    │                    │            │
  Team controls     Token holders       Only critical  Nothing
  everything        decide              params         changeable

  Risk: rug pull    Risk: slow to       Risk: can't    Risk: can't
                    respond             adapt quickly  fix bugs

  Example:          Example:            Example:       Example:
  Early protocols   Aave, Compound      Uniswap V2     Liquity
```

### Liquity: Zero Governance

```
Liquity's approach:
  ✓ All parameters hardcoded at deployment
  ✓ Contracts are immutable (no proxy, no admin key)
  ✓ Minimum collateral ratio: always 110%
  ✓ Borrowing fee: algorithmic (not governed)
  ✓ No admin, no multisig, no governance token

  Advantage: maximum trustlessness — "code is law" fully realized
  Disadvantage: can't fix bugs, can't adapt to market changes

  When this works: simple protocols with well-tested parameters
  When this doesn't: complex protocols that need ongoing tuning
```

**Connection to Part 2 Module 9:** Your capstone stablecoin was designed as immutable — no admin keys, no governance. This was a deliberate design choice that eliminates governance attack surfaces at the cost of adaptability.

### Progressive Decentralization

Most protocols follow a maturation path:

```
Phase 1: MULTISIG (launch)
  Team controls everything via 3/5 or 4/7 multisig
  Fast iteration, bug fixes, parameter tuning
  Users must trust the team

Phase 2: GOVERNOR + TIMELOCK (growth)
  Token holders vote on changes
  Timelock gives users exit rights
  Team retains emergency guardian role

Phase 3: MINIMIZE GOVERNANCE (maturity)
  Reduce governable parameters over time
  Hardcode well-tested values
  Remove upgrade capability where possible
  Eventually: only emergency pause + critical parameters remain

Compound's progression:
  Admin key → Governor Alpha → Governor Bravo → community governance
  Each step reduced team control and increased decentralization
```

**The right question isn't "governance or not" — it's "what SHOULD be governable?"**

```
SHOULD be governable:
  ✓ Risk parameters (LTV, liquidation thresholds) — markets change
  ✓ Fee levels — competitive dynamics
  ✓ New asset listings — protocol growth
  ✓ Emergency pause — security response

SHOULD NOT be governable (hardcode):
  ✗ Core accounting math — getting this wrong breaks everything
  ✗ Access control invariants — "only the borrower can repay their loan"
  ✗ Token supply (usually) — governance shouldn't be able to inflate supply
```

---

<a id="interview-prep"></a>
## 💼 Interview Prep

### 1. "Walk through the lifecycle of an on-chain governance proposal."

**Good answer:** "Someone proposes a change, token holders vote for or against, if it passes it goes through a timelock, then anyone can execute it."

**Great answer:** "Five phases: (1) Propose — the proposer submits targets, values, calldatas, and a description on-chain. They need a minimum token balance (proposal threshold) to prevent spam. At this moment, a snapshot of all voting power is recorded. (2) Voting delay — typically 1-2 days, giving the community time to review. (3) Active voting — token holders cast for/against/abstain using their voting power at the snapshot block, not their current balance. This prevents flash loan attacks. (4) Queue — if quorum is met and majority votes for, the proposal is queued in a TimelockController with a mandatory delay (24-48 hours). This is the safety net — users who disagree can exit. (5) Execute — after the timelock expires, anyone can trigger execution. The TimelockController calls the target contracts with the encoded function calls. Total time: 5-14 days depending on configuration."

### 2. "How does vote-escrow prevent governance manipulation?"

**Good answer:** "Users lock tokens for a period, which means they can't flash-borrow or quickly acquire and dump voting power."

**Great answer:** "Vote-escrow adds three layers of manipulation resistance: (1) Time commitment — tokens are locked for 1-4 years, making it impossible to flash-borrow voting power. An attacker would need to buy tokens on the market AND lock them up, creating massive economic exposure. (2) Linear decay — voting power decreases as the lock approaches expiry, forcing continuous re-locking. An attacker can't lock once and maintain power indefinitely. (3) Incentive alignment — because voters earn protocol fees (in Curve) or pool-specific fees (in Velodrome), voting against the protocol's interest reduces the voter's own revenue. The economic formula is: votingPower = lockedAmount × (lockEnd - now) / maxLockTime. This means 10,000 tokens locked for 4 years gives the same power as 40,000 tokens locked for 1 year — the market prices this, creating a real economic cost to governance influence."

### 3. "Explain the Curve Wars — what are protocols competing for?"

**Good answer:** "Protocols compete for veCRV votes that direct CRV emissions to their pools, attracting liquidity."

**Great answer:** "The Curve Wars are a meta-governance competition for liquidity. Curve emits CRV tokens to liquidity providers, but the allocation depends on weekly gauge votes by veCRV holders. More emissions to a pool means higher LP rewards, which attracts more liquidity, which means deeper trading for that token pair. For stablecoin protocols, deep Curve liquidity is existential — it's where peg stability comes from. So protocols compete for veCRV votes through bribes. Convex Finance aggregates CRV from thousands of users and locks it permanently as veCRV. The vlCVX token controls Convex's votes, creating a meta-governance layer. On platforms like Votium, protocols pay $1 in bribes to vlCVX holders, which typically directs $1.50+ of CRV emissions — a profitable arbitrage that sustains the entire flywheel. The key insight: governance voting power has quantifiable economic value, and a market naturally forms around it."

### 4. "How did the Beanstalk governance attack work, and how would you prevent it?"

**Good answer:** "The attacker flash-borrowed tokens, voted on a malicious proposal, and executed it all in one transaction. Prevention: snapshot voting and timelocks."

**Great answer:** "Beanstalk had three fatal governance design flaws: no snapshot-based voting (tokens acquired in the same block could vote), no voting delay (voting started immediately), and no timelock (proposals executed instantly). The attacker flash-borrowed $1B of tokens from Aave and SushiSwap, created a malicious proposal to drain the treasury, voted FOR with overwhelming power, and executed it — all in a single transaction. The $182M loss was entirely preventable with standard OpenZeppelin Governor defaults: snapshot voting means tokens must be held BEFORE the proposal is created; voting delay means voting can't start in the same block; timelock means execution is delayed 24-48 hours. These three defenses together make flash loan governance attacks economically impossible. The lesson isn't just technical — it's that governance security is as critical as smart contract security."

### 5. "What are the tradeoffs between governance and immutability?"

**Good answer:** "Governance allows protocols to adapt but introduces attack surfaces. Immutability is more trustless but can't fix bugs."

**Great answer:** "The spectrum runs from full governance (multisig) through token-based governance (Governor + Timelock) to zero governance (Liquity). Full governance enables rapid response to bugs, market changes, and competitive pressure — but every governable parameter is an attack surface. Governance can be bought, bribed, or exploited. Zero governance eliminates these risks entirely — Liquity has no admin keys, no governance token, no upgradability. But it also can't fix bugs, adapt interest rates to market conditions, or add new collateral types. The optimal approach is progressive decentralization: start with a multisig for rapid iteration, transition to token-based governance as the protocol matures, then systematically reduce what's governable over time. The key principle: only make governable what MUST change. Core accounting math should be immutable; risk parameters should be governable; somewhere in between, the protocol designer makes judgment calls."

**Interview red flags:**
- ❌ Not knowing about snapshot-based voting and flash loan prevention
- ❌ Thinking governance is "just voting" (it's a complex security + economic system)
- ❌ Not understanding why timelocks exist (user exit rights, not just delay)
- ❌ Treating all governance as good or all governance as bad (it's a spectrum)
- ❌ Not knowing the Beanstalk attack (the most important governance case study)

**Pro tip:** In interviews, showing awareness that governance is both a feature AND an attack surface immediately sets you apart. Most candidates think about governance from the "how do we vote" perspective. Senior candidates think about it from the "how can this be exploited, and how do we minimize the attack surface" perspective.

---

<a id="exercises"></a>
## 🎯 Module 8 Exercises

**Workspace:** `workspace/src/part3/module8/`

### Exercise 1: Governor + Timelock System

Build a complete on-chain governance system using OpenZeppelin Governor with TimelockController, and demonstrate that snapshot-based voting defeats flash loan attacks.

**What you'll implement:**
- `GovernanceToken` — ERC20Votes with delegation and checkpointing
- `MyGovernor` — Governor with configurable voting delay, period, quorum, and threshold
- Full proposal lifecycle: propose → vote → queue → execute
- Flash loan defense: prove snapshot voting blocks tokens acquired after proposal creation

**Concepts exercised:**
- OpenZeppelin Governor framework integration
- ERC20Votes delegation and checkpointing
- TimelockController role configuration
- The full governance lifecycle in code
- Flash loan attack vector and why snapshots prevent it

**🎯 Goal:** Build production-standard governance and prove it's secure against flash loan manipulation.

Run: `forge test --match-contract GovernorTest -vvv`

### Exercise 2: Simplified Vote-Escrow Token

Build a simplified ve-token with time-weighted voting power, linear decay, and gauge-style emission allocation.

**What you'll implement:**
- `createLock()` — lock tokens for a specified duration (1 week to 4 years)
- `votingPower()` — calculate current voting power with linear decay
- `increaseAmount()` — add more tokens to an existing lock
- `increaseUnlockTime()` — extend lock duration
- `voteForGauge()` — allocate voting power to a gauge (emission target)
- `withdraw()` — reclaim tokens after lock expires

**Concepts exercised:**
- Vote-escrow mechanics (lock → power → decay)
- Linear decay formula: `amount × (lockEnd - now) / maxLock`
- Gauge voting and weight allocation
- The incentive structure that makes ve-tokenomics work
- Why time-locking prevents governance manipulation

**🎯 Goal:** Build the core of a Curve-style vote-escrow system and understand why lock duration creates genuine skin-in-the-game for governance participants.

Run: `forge test --match-contract VoteEscrowTest -vvv`

---

## 📋 Summary

**✓ Covered:**
- On-chain governance: why it exists, the fundamental tension of decentralization vs agility
- OpenZeppelin Governor: ERC20Votes, Governor, TimelockController — the full stack with code
- Proposal lifecycle: propose → delay → vote → queue → execute
- ve-tokenomics: veCRV model with decay math, gauge voting, boost, fee sharing
- The Curve Wars: Convex meta-governance, bribery markets, the economics of voting power
- Velodrome/Aerodrome ve(3,3): the incentive-alignment fix to Curve's model
- Governance security: Beanstalk attack deep dive, flash loan defenses, emergency mechanisms
- Governance minimization: the spectrum from multisig to immutable, progressive decentralization

**Next:** [Module 9 — Capstone: Perpetual Exchange →](9-capstone.md) — build a perpetual exchange that integrates concepts from across Part 3.

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [OpenZeppelin Governor](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/governance) — Governor, GovernorVotes, TimelockController
- [Compound Governor Bravo](https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/GovernorBravoDelegate.sol) — the original DeFi governor
- [Curve VotingEscrow](https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy) — the original ve-token (Vyper)
- [Velodrome V2](https://github.com/velodrome-finance/contracts) — ve(3,3) implementation
- [Aerodrome](https://github.com/aerodrome-finance/contracts) — ve(3,3) on Base

### Documentation
- [OpenZeppelin Governor Guide](https://docs.openzeppelin.com/contracts/5.x/governance) — step-by-step setup
- [Curve DAO Documentation](https://resources.curve.fi/crv-token/overview/) — veCRV mechanics
- [Velodrome Docs](https://docs.velodrome.finance/) — ve(3,3) model

### Key Reading
- [Vitalik: Moving Beyond Coin Voting Governance](https://vitalik.eth.limo/general/2021/08/16/voting3.html) — fundamental critique and alternative designs
- [a16z: Governance Minimization](https://a16zcrypto.com/posts/article/governance-minimization/) — the case for reducing governable surface
- [Beanstalk Governance Attack Post-Mortem](https://rekt.news/beanstalk-rekt/) — detailed exploit analysis
- [Curve Wars Explainer](https://every.to/almanack/curve-wars) — the economics of governance competition

### 📖 How to Study: DeFi Governance

1. Start with [OpenZeppelin Governor Guide](https://docs.openzeppelin.com/contracts/5.x/governance) — deploy a test governor in Foundry
2. Read `ERC20Votes.sol` — understand checkpointing (this is what prevents flash loan attacks)
3. Study the [Beanstalk post-mortem](https://rekt.news/beanstalk-rekt/) — the most important governance attack
4. Read [Vitalik's governance post](https://vitalik.eth.limo/general/2021/08/16/voting3.html) — understand the limitations of token voting
5. Explore [Curve DAO docs](https://resources.curve.fi/crv-token/overview/) — understand ve-tokenomics
6. Read [a16z governance minimization](https://a16zcrypto.com/posts/article/governance-minimization/) — the design philosophy

---

**Navigation:** [← Module 7: L2-Specific DeFi](7-l2-defi.md) | [Part 3 Overview](README.md) | [Next: Module 9 — Capstone →](9-capstone.md)

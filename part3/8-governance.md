# Part 3 — Module 8: Governance & DAOs (~3 days)

> **Prerequisites:** Part 2 — Modules 1 (Token Mechanics), 6 (Stablecoins & CDPs)

## Overview

Every major DeFi protocol needs a mechanism for parameter updates, upgrades, and strategic decisions. Governance is how protocols evolve after deployment. This module covers on-chain governance mechanics (OpenZeppelin Governor), advanced tokenomics models (ve-tokenomics, the Curve Wars), and governance security — including how governance itself becomes an attack surface.

---

## Day 1: On-Chain Governance

### Why Governance Matters in DeFi
- Protocols need to update risk parameters (LTV, interest rates, collateral types)
- Smart contract upgrades require authorization
- Treasury management and fund allocation
- Fee changes and protocol revenue distribution
- The tension: decentralization vs operational agility

### OpenZeppelin Governor Framework
- **GovernorVotes** — voting power from ERC-20Votes token
  - Token holders must delegate to activate voting power (even to themselves)
  - Snapshot-based: voting power recorded at proposal creation block
  - Prevents flash loan voting attacks (must hold tokens before proposal)
- **GovernorTimelockControl** — execution delay after vote passes
  - Proposal passes → queued in timelock → executable after delay
  - Users can exit before changes take effect (protective delay)
  - Minimum delay: typically 24h-48h for major protocols
- **GovernorCountingSimple** — for/against/abstain counting
  - Quorum: minimum participation threshold (% of total supply)
  - Proposal threshold: minimum tokens to create proposal

### Proposal Lifecycle
```
1. Propose  → Submit on-chain (proposer needs threshold tokens)
2. Delay    → Voting delay period (typically 1 block - 2 days)
3. Vote     → Active voting period (typically 3-7 days)
4. Succeed  → Quorum reached + majority for
5. Queue    → Queued in timelock (mandatory delay)
6. Execute  → Anyone can trigger execution after timelock
```
- Total time from proposal to execution: typically 5-14 days
- Emergency proposals: shorter timelock for critical fixes (multisig override)

### Voting Power Mechanisms

**Token-Weighted (Standard)**
- 1 token = 1 vote
- Simple, transparent
- Plutocratic: large holders dominate
- Used by: most DeFi governance (Uniswap, Aave, Compound)

**Delegation**
- Token holders delegate to active participants
- Delegates vote on behalf of delegators
- Can be re-delegated at any time
- Creates "governance representatives" — reduces voter apathy

**Quadratic Voting (Awareness)**
- Voting power = sqrt(tokens)
- More egalitarian: 100 tokens = 10 votes, not 100
- Sybil-resistant version requires identity verification
- Used by: Gitcoin Grants (off-chain), experimental in DAOs

**Conviction Voting (Awareness)**
- Voting power increases the longer you stake your vote
- Rewards long-term conviction over flash decisions
- Used by: 1Hive, Gardens framework

### 📖 Read: OpenZeppelin Governor
- `Governor.sol` — core governance logic
- `GovernorVotes.sol` — snapshot voting power from ERC20Votes
- `GovernorTimelockControl.sol` — timelock integration
- `TimelockController.sol` — delayed execution with roles
- `ERC20Votes.sol` — delegation and checkpointing

### 📖 Code Reading Strategy
1. Start with `ERC20Votes` — understand delegation and checkpointing
2. Read `Governor.propose()` — what happens when a proposal is created
3. Trace `castVote()` — how votes are counted
4. Follow `execute()` → `TimelockController` — execution flow
5. Study access control: who can propose, who can execute

---

## Day 2: Advanced Tokenomics

### ve-Tokenomics Deep Dive

**Curve veCRV: The Original Model**
- Lock CRV for 1-4 years → receive veCRV (non-transferable)
- Longer lock = more veCRV (linear: 4 years = 1:1, 1 year = 0.25:1)
- veCRV decays linearly toward 0 as lock approaches expiry
- **Gauge voting:** veCRV holders vote on CRV emission allocation
  - Each pool has a "gauge" that receives CRV emissions
  - More votes for a gauge → more CRV rewards for that pool's LPs
  - Voting happens weekly (epoch-based)
- **Boosted rewards:** veCRV holders get up to 2.5x boost on LP rewards
- **Revenue sharing:** veCRV holders receive protocol trading fees

**The Curve Wars**
- Protocols compete for veCRV votes to direct emissions to their pools
- More emissions → more LP rewards → more liquidity → better trading experience
- **Convex Finance:** aggregates veCRV voting power
  - Users deposit CRV → Convex locks as veCRV
  - vlCVX holders control Convex's veCRV votes
  - Meta-governance: vote on where Convex directs its votes
- **Bribery markets:** protocols pay veCRV/vlCVX holders to vote for their pools
  - Votium — bribe marketplace for vlCVX votes
  - Hidden Hand — broader bribe marketplace
  - Paladin — vote lending platform
- **Economics:** $1 of bribes often buys > $1 of emissions → profitable for protocols

### Velodrome/Aerodrome: ve(3,3)
- Combines ve model + Olympus (3,3) game theory
- **Key innovation:** voters earn 100% of trading fees from pools they vote for
  - Curve: fees go to all veCRV holders regardless of vote
  - Velodrome: fees go only to voters of that specific pool
  - Direct incentive alignment: vote for high-volume pools = more fees
- **Anti-dilution:** voters receive proportional new emissions (rebase)
  - Non-voters get diluted over time
  - Incentivizes continuous participation
- **Weekly epoch cycle:**
  1. Voting period: veVELO holders vote for pools
  2. Emission distribution based on votes
  3. Trading generates fees for voters
  4. Cycle repeats
- **Dominant model on L2s:** Aerodrome (Base), Velodrome (Optimism)

### Protocol-Owned Liquidity (POL)

**The Liquidity Rental Problem**
- Protocols rent liquidity through emissions (liquidity mining)
- When emissions decrease → LPs leave → liquidity drops
- Mercenary capital: LPs chase highest yield, no loyalty
- Emissions are inflationary: dilute token holders

**Olympus/OHM: Bonding Model**
- Users sell LP tokens to protocol at discount
- Protocol accumulates its own LP positions
- "Protocol-Owned Liquidity" — treasury owns the liquidity
- Advantages: permanent liquidity, no emissions needed
- **What happened:** worked initially, but (3,3) game theory broke down in bear market
- OHM price collapsed but the POL model concept survived

**Modern POL Approaches**
- Protocol treasuries as strategic assets
- Bond mechanisms (Olympus V2, Bond Protocol)
- Treasury diversification: ETH, stables, productive assets
- Balancer boosted pools: treasury assets earning yield

---

## Day 3: Governance Security & Build

### Flash Loan Governance Attacks

**The Attack:**
1. Flash-borrow governance tokens
2. Create or vote on malicious proposal
3. Return tokens in same transaction
4. If successful: drain treasury, change parameters, grant access

**Beanstalk Attack ($182M, April 2022):**
- Attacker flash-borrowed tokens across multiple protocols
- Accumulated enough voting power to pass malicious proposal
- Proposal drained entire Beanstalk treasury
- No voting delay — proposal + vote + execution in one transaction

**Defenses:**
- **Snapshot voting power** — use balance at proposal creation block (OpenZeppelin default)
  - Tokens acquired after snapshot don't count
  - Flash loans can't affect historical snapshots
- **Vote escrow (ve)** — tokens must be locked to vote
  - Can't flash-borrow locked tokens
  - Time commitment required
- **Voting delay** — gap between proposal creation and voting start
  - Gives community time to review
  - Can't propose + vote atomically
- **Timelock** — delay between vote passing and execution
  - Users can exit before malicious changes take effect

### Delegation Attacks
- Accumulate delegated voting power → vote maliciously
- Defense: delegators can re-delegate or withdraw
- Social engineering risk: convincing delegators to delegate to attacker

### Governance Minimization
- **Why less governance can be better:**
  - Fewer attack vectors
  - More predictable protocol behavior
  - Users can trust immutable rules
- **Liquity model:** zero governance
  - All parameters hardcoded
  - Contract is immutable
  - Trade-off: can't fix bugs or adapt to market changes
- **Progressive decentralization:**
  - Start with multisig (fast, flexible)
  - Transition to Governor + timelock (decentralized)
  - Eventually: minimize governable parameters
  - Compound example: started with admin key → Governor Alpha → Governor Bravo
- **Parameter governance vs code governance:**
  - Parameter changes (risk settings, fees): lower risk, more frequent
  - Code upgrades (proxy upgrades): higher risk, less frequent
  - Some protocols: governance for parameters, immutable code

### Emergency Mechanisms
- **Guardian multisig** — can pause protocol in emergency
  - Doesn't have upgrade power — only pause/unpause
  - Fast response to exploits
  - Aave Guardian, Compound pause guardian
- **Emergency shutdown** — protocol-wide circuit breaker
  - MakerDAO Emergency Shutdown Module (ESM)
  - Requires governance threshold to trigger
  - Settles all positions, returns collateral
- **Timelock bypass for emergencies** — shorter delay for critical fixes
  - Careful: reduces the protection timelock provides

### Build: Governor + Timelock System
- Deploy ERC20Votes token
- Deploy Governor with configurable parameters
- Deploy TimelockController
- Create proposal → vote → queue → execute lifecycle
- Test: flash loan attack prevention (snapshot-based voting)
- Test: timelock delay enforcement
- Test: delegation and vote weight

---

## 🎯 Module 8 Exercises

**Workspace:** `workspace/src/part3/module8/`

### Exercise 1: Governance System
- Implement ERC20Votes token with delegation
- Deploy OZ Governor with TimelockController
- Full proposal lifecycle: propose → vote → queue → execute
- Test: proposal that changes a protocol parameter via timelock
- Test: failed quorum, rejected proposal
- Test: flash loan attack prevention (demonstrate snapshot safety)

### Exercise 2: Vote-Escrow Token (Simplified)
- Implement simplified ve-token: lock ERC-20 for 1-4 "periods"
- Voting power proportional to lock duration
- Linear decay of voting power over time
- Gauge-style voting to allocate "emissions" to different targets
- Test: lock/unlock lifecycle, voting power decay, gauge allocation

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding OpenZeppelin Governor framework and proposal lifecycle
- Familiarity with ve-tokenomics (Curve, Velodrome models)
- Awareness of governance attack vectors and defenses
- Ability to reason about governance minimization trade-offs

**Common interview topics:**
- "Walk through the lifecycle of an on-chain governance proposal"
- "How does vote escrow prevent governance manipulation?"
- "What are the trade-offs between governance and immutability?"
- "Explain the Curve Wars — what are protocols competing for?"
- "How did the Beanstalk governance attack work?"

---

## 📚 Resources

### Production Code
- [OpenZeppelin Governor](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/governance)
- [Compound Governor Bravo](https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/GovernorBravoDelegate.sol)
- [Curve VotingEscrow](https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
- [Velodrome](https://github.com/velodrome-finance/contracts)
- [Aerodrome](https://github.com/aerodrome-finance/contracts)

### Documentation
- [OpenZeppelin Governor guide](https://docs.openzeppelin.com/contracts/5.x/governance)
- [Curve DAO docs](https://resources.curve.fi/crv-token/overview/)
- [Velodrome docs](https://docs.velodrome.finance/)

### Further Reading
- [Vitalik: Moving beyond coin voting governance](https://vitalik.eth.limo/general/2021/08/16/voting3.html)
- [a]16z: Governance Minimization](https://a16zcrypto.com/)
- [Beanstalk governance attack postmortem](https://rekt.news/beanstalk-rekt/)
- [Curve Wars explainer](https://every.to/almanack/curve-wars)

---

**Navigation:** [← Module 7: L2-Specific DeFi](7-l2-defi.md) | [Part 3 Overview](README.md) | [Next: Module 9 — Capstone →](9-capstone.md)

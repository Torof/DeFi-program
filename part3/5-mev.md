# Part 3 — Module 5: MEV Deep Dive (~4 days)

> **Prerequisites:** Part 2 — Modules 2 (AMMs), 5 (Flash Loans) + Part 3 Module 4 (DEX Aggregation)

## Overview

Maximal Extractable Value (MEV) is the invisible tax on every DeFi transaction. Understanding MEV is essential for both protocol designers (minimizing it) and DeFi developers (protecting users from it). This module goes deep on the MEV supply chain post-Merge, attack taxonomy, protection mechanisms, and how to design MEV-aware protocols. The AMMs module (P2M2) introduced sandwich attacks — here we cover the full picture.

---

## Day 1: MEV Taxonomy

### What is MEV?
- Originally "Miner Extractable Value" — now "Maximal Extractable Value"
- Value that can be extracted by anyone who controls transaction ordering
- Post-Merge: validators propose blocks, but builders construct them
- MEV exists because transaction ordering affects outcomes

### Types of MEV

**Arbitrage (Generally Benign)**
- Price differences between DEXes → bot corrects the discrepancy
- Improves price efficiency across markets
- Example: ETH is $1900 on Uniswap, $1905 on SushiSwap → bot buys low, sells high
- Legitimate value: keeps prices consistent
- Often uses flash loans for capital-free execution

**Liquidation MEV (Useful)**
- Racing to liquidate undercollateralized positions
- First bot to call `liquidate()` captures the liquidation bonus
- Keeps lending protocols solvent — socially useful
- Gas priority auctions between liquidation bots
- Connection to P2M4 (Lending) and P3M2 (Perpetuals)

**Sandwich Attacks (Harmful)**
- Frontrun + backrun a user's swap
- Frontrun: buy before user, push price up
- User's swap executes at worse price
- Backrun: sell after user, capture the price difference
- User pays the "sandwich tax" — receives fewer tokens
- Covered briefly in P2M2, deeper analysis here

**Frontrunning (Harmful)**
- Copying a profitable transaction and submitting with higher gas
- Example: user finds arbitrage → bot copies and outbids
- "Generalized frontrunning" — bots simulate any pending tx

**Backrunning (Mixed)**
- Placing transaction immediately after a target transaction
- Example: large swap creates price impact → backrunner arbitrages back
- Less harmful than sandwich (doesn't affect target tx)
- Often captures leftover value from price impact

**JIT Liquidity (Covered in P2M2)**
- Flash add/remove concentrated liquidity around a swap
- Captures fees from a single trade
- V4 hooks can potentially address this

**Cross-Domain MEV**
- MEV spanning L1 ↔ L2 or L2 ↔ L2
- Arbitrage between mainnet and rollup prices
- Sequencer ordering creates L2-specific MEV
- Shared sequencing proposals aim to address this

### Quantifying MEV
- Flashbots MEV-Explore: historical MEV data
- Billions of dollars extracted since DeFi Summer (2020)
- Majority is arbitrage and liquidation — "good MEV"
- Sandwich attacks: significant but smaller portion
- Growing with DeFi volume

---

## Day 2: The MEV Supply Chain (Post-Merge)

### Pre-Merge vs Post-Merge
- **Pre-Merge:** Miners ordered transactions → direct MEV extraction
- **Post-Merge:** Proposer-Builder Separation (PBS) — distinct roles

### The Supply Chain

```
Users → Transactions → Mempool
                          ↓
                      Searchers (find MEV opportunities)
                          ↓
                      Bundles (ordered transaction sets)
                          ↓
                      Builders (construct full blocks)
                          ↓
                      Relays (connect builders ↔ proposers)
                          ↓
                      Proposers/Validators (select highest-value block)
```

### Searchers
- Bots that scan the mempool for MEV opportunities
- Write smart contracts that atomically capture value
- Submit bundles to builders (not to public mempool)
- Competitive: many searchers compete for same opportunity
- Revenue: MEV profit minus gas and builder tips

### Builders
- Construct complete blocks from user txs + searcher bundles
- Optimize for total block value
- Bid to proposer: "My block is worth X ETH to you"
- Top builders: Flashbots, BeaverBuild, Titan, rsync
- Centralization concern: few builders construct most blocks

### Relays
- Trusted intermediaries between builders and proposers
- Proposer can't see block contents until they commit
- Prevents proposer from stealing MEV
- MEV-Boost relay ecosystem
- Relay trust: must honestly report block value

### Proposers (Validators)
- Select the block with highest bid via MEV-Boost
- Don't need to understand MEV — just pick highest bid
- Receive: base fee revenue + builder bid
- Effectively outsource block construction to builders

### 📖 Read: Flashbots Architecture
- MEV-Boost: how validators connect to the relay network
- Bundle format: how searchers submit bundles
- Builder API: how builders submit blocks
- Relay API: how relays connect builders to proposers

### Centralization Concerns
- Builder centralization: top 3 builders produce majority of blocks
- Relay centralization: few relays handle most traffic
- Censorship risk: builders/relays can exclude transactions
- OFAC compliance and the censorship debate
- Inclusion lists (EIP-7547): validators force-include transactions

---

## Day 3: MEV Protection Mechanisms

### For Users: Transaction Privacy

**Flashbots Protect**
- Submit transactions to private mempool (not public)
- Transactions go directly to Flashbots builder
- Not visible to sandwich bots
- Trade-off: reliance on Flashbots, possibly slower inclusion

**MEV Blocker (by CoW Protocol)**
- Similar private submission
- Searchers bid for backrun rights
- User receives kickback from backrun profit (rebate)

**Private RPCs**
- Various RPC providers offer private submission
- Transactions not broadcast to public mempool
- Different trust assumptions per provider

### For Users: Application-Level

**Slippage limits**
- Set maximum acceptable price impact
- Sandwich becomes unprofitable if slippage too tight
- Trade-off: too tight → transaction reverts on normal volatility

**DEX aggregator protection**
- Aggregators can route through MEV-resistant paths
- Intent-based systems (UniswapX, CoW) — solver absorbs MEV risk

### For Protocols: Order Flow Auctions (OFA)

**MEV-Share (Flashbots)**
- Users send tx to MEV-Share → searchers bid for backrun rights
- Winning searcher's bundle includes user tx + backrun
- User gets portion of MEV as rebate
- User captures some of the value that would otherwise be extracted

**How it works:**
1. User sends tx to MEV-Share (private)
2. MEV-Share shares partial tx info with searchers (not full details)
3. Searchers bid for right to backrun
4. Winning bundle: user tx → searcher backrun
5. User receives configured % of searcher's profit

### For Protocols: Cryptographic

**Threshold Encryption (Shutter Network)**
- Transactions encrypted until block inclusion is committed
- Decryption key revealed after block position is locked
- Prevents all forms of frontrunning (can't read what you can't see)
- Trade-off: added latency, decryption committee trust

**Commit-Reveal Schemes**
- Phase 1: submit hash of action
- Phase 2: reveal action after commitment period
- Prevents frontrunning of specific actions (governance votes, etc.)
- Added complexity and latency

### For Protocols: Auction Design

**Batch Auctions (CoW Protocol model)**
- Collect orders over time window
- Execute at uniform clearing price
- No individual transaction to frontrun
- Natural MEV resistance

**Frequent Batch Auctions**
- Academic proposal for exchanges
- Discrete time intervals instead of continuous
- Reduces speed advantage of MEV bots

---

## Day 4: MEV-Aware Protocol Design

### Design Principles
1. **Minimize information leakage** — less visible = less extractable
2. **Reduce ordering dependence** — batch operations where possible
3. **Internalize MEV** — capture value for users/LPs instead of searchers
4. **Time-weight operations** — TWAPs, time-delayed actions reduce instantaneous manipulation

### Uniswap V4 Hooks for MEV Mitigation
- `beforeSwap` hook can implement dynamic fees
- Detect MEV-extracting swaps (high gas, sandwich patterns)
- Charge higher fees on MEV → redistribute to LPs
- Example: if swap happens in same block as opposite swap → increase fee
- MEV taxes: fee proportional to MEV extracted

### Oracle-Based Execution (GMX Model)
- Trades execute at oracle price, not AMM price
- Can't frontrun because price isn't determined by order flow
- Keeper delay between order submission and execution
- Trade-off: relies on oracle quality, potential for oracle manipulation

### Protocol-Level MEV Redistribution
- Instead of eliminating MEV → capture and redistribute
- LPs receive MEV that would otherwise go to searchers
- Examples: MEV-aware AMMs, auction-based fee mechanisms
- Osmosis: ProtoRev (on-chain backrunning, revenue to protocol)

### The Long-Term Vision
- **Encrypted mempools** — prevent all forms of frontrunning
- **MEV-Burn** — redirect MEV revenue from validators to ETH burn
- **Decentralized builders** — reduce builder centralization
- **Application-specific sequencing** — protocols control their own tx ordering

### Build: MEV Simulation
- Create a sandwich attack scenario in Foundry fork test
- Measure the MEV extracted
- Implement defense: slippage protection
- Implement defense: intent-based order (compare outcomes)

---

## 🎯 Module 5 Exercises

**Workspace:** `workspace/src/part3/module5/`

### Exercise 1: Sandwich Attack Simulation
- Fork mainnet, simulate a sandwich attack on a Uniswap V2 swap
- Frontrun tx: buy token to inflate price
- Target tx: user swap at worse price
- Backrun tx: sell to capture difference
- Measure: user's loss, attacker's profit, gas costs
- Test: slippage protection preventing the sandwich

### Exercise 2: MEV-Aware Hook (V4 Style)
- Implement a simple `beforeSwap` hook that detects potential MEV
- Track swaps per block — flag if same token pair swapped in both directions
- Apply dynamic fee surcharge on suspected MEV swaps
- Test: normal swap (low fee) vs sandwich-pattern swap (high fee)

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding the full MEV supply chain (searchers → builders → relays → proposers)
- Ability to identify MEV vectors in protocol designs
- Familiarity with protection mechanisms (private mempools, OFA, intents)
- Awareness of the centralization concerns in block building

**Common interview topics:**
- "Explain how a sandwich attack works and how to prevent it"
- "What is Proposer-Builder Separation and why does it exist?"
- "How would you design a protocol to minimize MEV extraction?"
- "What are the trade-offs between private mempools and batch auctions for MEV protection?"

---

## 📚 Resources

### Production Code
- [Flashbots MEV-Share](https://github.com/flashbots/mev-share)
- [MEV-Boost](https://github.com/flashbots/mev-boost)
- [CoW Protocol solver](https://github.com/cowprotocol/solver)

### Documentation
- [Flashbots docs](https://docs.flashbots.net/)
- [MEV-Share docs](https://docs.flashbots.net/flashbots-mev-share/overview)
- [Ethereum.org: MEV](https://ethereum.org/en/developers/docs/mev/)

### Further Reading
- [Flashbots: MEV and Me](https://writings.flashbots.net/)
- [Paradigm: MEV taxes](https://www.paradigm.xyz/)
- [Frontier Research: MEV supply chain](https://frontier.tech/)
- [MEV-Explore (data)](https://explore.flashbots.net/)
- [Tim Roughgarden: Transaction Fee Mechanism Design](https://timroughgarden.org/)

---

**Navigation:** [← Module 4: DEX Aggregation](4-dex-aggregation.md) | [Part 3 Overview](README.md) | [Next: Module 6 — Cross-Chain & Bridges →](6-cross-chain.md)

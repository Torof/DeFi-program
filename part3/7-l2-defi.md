# Part 3 — Module 7: L2-Specific DeFi (~3 days)

> **Prerequisites:** Part 2 — Modules 3 (Oracles), 4 (Lending) + Part 3 Module 6 (Cross-Chain)

## Overview

Most DeFi activity has migrated to L2s — Arbitrum, Base, and Optimism collectively host more DeFi transactions than Ethereum mainnet. But L2s aren't just "cheap Ethereum" — they have distinct sequencer behavior, gas models, finality properties, and design constraints that affect every protocol deployed on them. This module covers what DeFi developers need to know to build correctly on L2s.

---

## Day 1: L2 Architecture for DeFi Developers

### Rollup Types Refresh
- **Optimistic rollups (Arbitrum, Optimism, Base):**
  - Transactions assumed valid
  - 7-day challenge window for fraud proofs
  - L2 → L1 withdrawals take 7 days (without fast exit)
  - Mature, battle-tested
- **ZK rollups (zkSync Era, Scroll, Linea, Starknet):**
  - Validity proofs mathematically guarantee correctness
  - Faster finality (hours, once proof submitted)
  - More complex, newer technology
  - Different EVM compatibility levels (zkEVM types)

### The Sequencer
- Single entity ordering transactions on most L2s
- Centralization point: sequencer decides tx ordering
- **Revenue model:** base fee + priority fee (L2 execution gas)
- **Soft confirmation:** sequencer confirms tx in ~250ms (Arbitrum)
- **Hard finality:** only when batch posted to L1 and finalized
- **Forced inclusion:** if sequencer censors, users can submit tx directly to L1
  - Arbitrum: delayed inbox after ~24h
  - Optimism: L1 deposit contract
  - Guarantee: sequencer can delay but not permanently censor

### Gas Model: Two Components
- **L2 execution gas:** running the EVM on the rollup (cheap)
- **L1 data posting cost:** submitting transaction data to Ethereum (main expense)
- Pre-EIP-4844: calldata posting to L1 (~16 gas per byte)
- Post-EIP-4844: blob posting (~much cheaper, variable pricing)
- **Impact on protocol economics:**
  - Calldata-heavy operations (large inputs) are proportionally more expensive
  - Storage operations are cheaper than on L1 (relative to other costs)
  - Batch operations that reduce per-tx L1 data are valuable

### Block Properties on L2
- `block.timestamp` — L2 block timestamp (may differ from L1)
- `block.number` — L2 block number (different from L1 block number)
- Arbitrum: 250ms block time (~4x faster than L1)
- Optimism/Base: 2-second block time
- **Implication:** time-based logic must account for different block times
- **L1 block info:** available via precompiles on some L2s

### 🔍 Deep Dive: EIP-4844 Impact on L2 Economics
- Before 4844: Arbitrum txs cost ~$0.10-1.00 (mostly L1 data cost)
- After 4844: Arbitrum txs cost ~$0.001-0.01 (blob space much cheaper)
- Variable blob pricing: supply/demand based (EIP-1559 style for blobs)
- Protocol implications: batch operations become less necessary
- More complex tx paths become viable (aggregator routing, multi-hop)

---

## Day 2: L2-Specific Concerns for DeFi

### Sequencer Uptime and Oracle Staleness

**The Problem:**
- Sequencer goes down → no new L2 blocks → oracle prices freeze
- Sequencer comes back → stale prices used for liquidation/borrowing
- Users can't interact during downtime → can't add collateral

**Chainlink L2 Sequencer Uptime Feed**
- Dedicated feed that reports sequencer status (up/down)
- Reports how long the sequencer has been back up
- Protocols must check sequencer status before using price feeds

**The Grace Period Pattern (Aave PriceOracleSentinel):**
```
1. Check: Is sequencer up?
2. Check: Has sequencer been up for > GRACE_PERIOD?
3. If no to either → block liquidations and new borrows
4. If yes → normal operation
```
- Grace period gives users time to manage positions after sequencer restart
- Typically 1-2 hours

**Why This Matters:**
- Arbitrum had sequencer downtime in June 2023 (~1 hour)
- Without grace period: bots liquidate immediately on restart with stale prices
- With grace period: users can add collateral before liquidation resumes

### Transaction Ordering on L2
- **Arbitrum:** First-come-first-served (FCFS) ordering
  - No priority fees influence ordering (historically)
  - Timeboost: new auction-based priority system
  - MEV is less severe but emerging
- **Optimism/Base:** Priority fee ordering (like L1)
  - Standard MEV dynamics apply
  - Sequencer can frontrun (theoretical, reputational risk)
- **Shared sequencing (future):**
  - Multiple L2s share a sequencer
  - Cross-L2 atomic transactions
  - Espresso, Astria proposals

### Withdrawal Delays and Capital Efficiency
- 7-day optimistic withdrawal: capital locked for a week
- Impact on LP capital efficiency
- Fast exit services: LP fronts L1 tokens, gets repaid from bridge after 7 days
- ZK rollups: withdrawal in hours (once proof submitted)
- Protocol design: account for withdrawal delay in yield calculations

### L2-Specific Precompiles and System Contracts
- **Arbitrum:**
  - `ArbSys` — L2 → L1 messaging, block number info
  - `ArbRetryableTx` — retryable ticket system
  - `ArbGasInfo` — gas pricing information
  - `NodeInterface` — gas estimation utilities
- **Optimism/Base:**
  - `L2CrossDomainMessenger` — L2 → L1 messaging
  - `L2ToL1MessagePasser` — withdrawal initiation
  - `GasPriceOracle` — L1 data cost estimation
- **Using these in DeFi:**
  - Gas cost estimation for batch operations
  - Cross-layer message sending
  - L1 block info for time-sensitive operations

---

## Day 3: L2-Native Protocol Design & Build

### L2-Native Protocols

**Aerodrome (Base)**
- ve(3,3) DEX designed for L2 (low gas enables more frequent operations)
- Concentrated liquidity with governance incentives
- Weekly epoch: vote → emit → swap → fee distribution
- Low gas makes frequent rebalancing viable for LPs
- Dominant DEX on Base by TVL and volume

**GMX on Arbitrum**
- Leveraging low gas for keeper operations
- Keeper execution: create order → keeper fills (two-tx model feasible because cheap)
- High-frequency position updates
- Wouldn't be viable on L1 due to gas costs

### Design Patterns for L2

**What L2 enables (cheap gas):**
- Auto-compounding vaults with frequent harvests
- More aggressive rebalancing for LP positions
- Complex multi-hop aggregation routes
- Keeper networks with lower profitability thresholds
- On-chain order books become more feasible

**What L2 changes (different constraints):**
- Storage operations are relatively cheaper → less need for calldata packing
- But L1 data cost still matters for calldata-heavy operations
- Block times are faster → time-based logic needs adjustment
- Sequencer dependency → must handle downtime gracefully
- Finality is delayed → cross-chain composability needs care

### Multi-Chain Deployment Strategy
- Same protocol, different parameters per chain
  - Different gas optimization priorities
  - Different oracle configurations (sequencer checks on L2)
  - Different liquidation parameters (sequencer risk)
- CREATE2 for deterministic addresses across chains
- Shared governance vs chain-specific governance
  - Cross-chain governance: vote on L1, execute on L2
  - Chain-specific: separate governance per deployment
- Deployment scripts that work across chains (Foundry)

### Build: L2-Aware Oracle Consumer
- Oracle consumer with Chainlink L2 sequencer uptime check
- Grace period enforcement
- Fallback behavior during sequencer downtime
- Test with mock sequencer status feed

---

## 🎯 Module 7 Exercises

**Workspace:** `workspace/src/part3/module7/`

### Exercise 1: L2-Aware Oracle
- Implement oracle consumer with sequencer uptime check
- Grace period logic: block liquidations for N seconds after restart
- Proper error handling for stale sequencer feed
- Test scenarios: sequencer up, sequencer down, just restarted, grace period expired

### Exercise 2: L2 Gas Estimator
- Build a utility that estimates L1 data cost for a transaction
- Compare: single swap vs split swap gas costs on L2
- Calculate: break-even point for splitting trades on L2 vs L1
- Test with mock gas oracle (Optimism GasPriceOracle pattern)

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding L2 gas model (L2 execution + L1 data posting)
- Ability to handle sequencer uptime checks in oracle-dependent code
- Awareness of L2-specific design patterns (what L2 enables, what it changes)
- Familiarity with at least one L2 ecosystem (Arbitrum or Optimism/Base)

**Common interview topics:**
- "How does EIP-4844 affect L2 protocol economics?"
- "What should a lending protocol do when the L2 sequencer goes down?"
- "How would you design differently for L2 vs L1?"
- "What are the risks of relying on the sequencer for transaction ordering?"

---

## 📚 Resources

### Production Code
- [Aave PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol)
- [Chainlink L2 Sequencer Feed](https://docs.chain.link/data-feeds/l2-sequencer-feeds)
- [Aerodrome](https://github.com/aerodrome-finance/contracts)
- [Arbitrum ArbSys](https://github.com/OffchainLabs/nitro-contracts)

### Documentation
- [Arbitrum developer docs](https://docs.arbitrum.io/)
- [Optimism developer docs](https://docs.optimism.io/)
- [Base developer docs](https://docs.base.org/)

### Further Reading
- [L2Beat — L2 risk analysis](https://l2beat.com/)
- [Arbitrum: Timeboost explainer](https://docs.arbitrum.io/)
- [Vitalik: Different types of L2s](https://vitalik.eth.limo/)
- [EIP-4844 FAQ](https://www.eip4844.com/)

---

**Navigation:** [← Module 6: Cross-Chain & Bridges](6-cross-chain.md) | [Part 3 Overview](README.md) | [Next: Module 8 — Governance & DAOs →](8-governance.md)

# Part 3 — Module 4: DEX Aggregation & Intents (~4 days)

> **Prerequisites:** Part 2 — Modules 2 (AMMs), 5 (Flash Loans)

## Overview

In practice, no single DEX has the best price for every trade. DEX aggregators solve the routing problem — finding optimal execution across fragmented liquidity. More recently, intent-based trading is replacing explicit transaction construction: users sign *what* they want, and solvers compete to figure out *how* to fill it. This module covers both models, from traditional routing to the emerging intent/solver paradigm.

---

## Day 1: The Aggregation Problem

### Why Not Just Use One DEX?
- Liquidity is fragmented across dozens of pools (Uniswap V2, V3, V4, Curve, Balancer, SushiSwap, etc.)
- Best price for ETH/USDC might be split: 60% through V3, 40% through Curve
- Larger trades need deeper liquidity — single pool = more slippage
- Some token pairs only have liquidity on specific DEXes
- Multi-hop routing: A → B → C when no direct A → C pool exists

### The Routing Problem
- **Input:** token A, token B, amount
- **Output:** optimal path(s) across all available pools
- **Constraints:**
  - Gas cost of each additional pool hop
  - Slippage on each pool
  - Price impact of splitting across pools
  - MEV exposure from complex routes
- NP-hard optimization in general → heuristic solutions

### Split Orders
- Large trade: split across multiple pools for less total slippage
- Example: 100 ETH → USDC
  - All through Uniswap V3: $189,500 (high slippage on single pool)
  - 60% V3 + 40% Curve: $189,800 (less slippage per pool)
  - But: extra gas cost for second pool interaction
- Break-even point: when gas cost of split < slippage savings

### Quote vs Execution
- Off-chain quote: simulated at block N
- On-chain execution: happens at block N+1 (or later)
- Price can move between quote and execution
- Slippage tolerance protects against adverse movement
- MEV bots watch pending transactions (sandwich risk)

### Gas-Aware Routing
- Sometimes a single pool is better despite worse price — lower gas
- On L2: gas is cheap → more splits are viable
- On L1: gas is expensive → fewer hops preferred
- Aggregators factor gas cost into route optimization

---

## Day 2: Aggregator Architecture

### 1inch Architecture
- **Pathfinder** — off-chain routing engine
  - Queries all DEX pools for quotes
  - Runs optimization algorithm (split routing, multi-hop)
  - Returns calldata for on-chain execution
- **AggregationRouterV6** — on-chain executor
  - Receives calldata from Pathfinder
  - Executes swaps across pools in sequence
  - Handles partial fills
  - Remaining token handling (dust return)
- **Limit orders** — signed off-chain orders filled by anyone
  - Gasless for maker
  - Taker pays gas to fill

### Paraswap
- Similar architecture: off-chain router + on-chain executor
- Augustus (executor contract) — handles multi-DEX routing
- SimpleSwap (direct pool access) vs MultiSwap (multi-hop)
- DeltaSwap (split across pools)

### 0x API / RFQ
- **Request for Quote (RFQ)** — ask professional market makers for quotes
- Market makers provide better prices for large trades (no AMM slippage)
- Hybrid: AMM routing + RFQ for best execution
- Gasless for takers (market maker submits tx)

### 📖 Read: Aggregator Contracts
- 1inch AggregationRouterV6 — `swap()`, `unoswap()`, `uniswapV3Swap()`
- How calldata encodes the route (pools, amounts, directions)
- Token approval flow: user approves router, router calls pools
- Error handling: what happens when a pool call fails mid-route

### 📖 Code Reading Strategy
1. Start with the simplest path: single-pool swap (`unoswap`)
2. Read multi-hop: how the router chains pool calls
3. Study split routing: how amounts are divided
4. Understand the calldata encoding (compact representations for gas savings)

---

## Day 3: Intent-Based Trading

### The Paradigm Shift
- **Traditional:** User constructs transaction → signs → submits to mempool
- **Intent-based:** User signs *what* they want → solvers compete to fill
- User doesn't specify route, pools, or execution path
- Solvers have private liquidity, CEX access, cross-chain paths
- Better prices + MEV protection (solver absorbs MEV risk)

### UniswapX
- User signs an **order** (intent): "I want to sell 1 ETH for at least 1900 USDC"
- **Dutch auction decay:** price starts favorable for filler, decays toward user's limit
  - At t=0: filler gets 1 ETH, must provide 1950 USDC (bad for filler)
  - At t=30s: must provide 1930 USDC
  - At t=60s: must provide 1910 USDC
  - Eventually: someone fills when it's profitable
- **Fillers/solvers** compete to fill orders
  - Can use any liquidity source (AMMs, CEX, private inventory)
  - First valid fill wins
- **Reactor contracts** — on-chain settlement
  - Verify order signature
  - Execute swap atomically
  - Ensure user receives minimum amount
- **Cross-chain swaps** — intent model extends naturally across chains

### CoW Protocol (Coincidence of Wants)
- **Batch auction model** — orders collected over a window (~30 seconds)
- **Coincidence of Wants** — direct P2P matching when possible
  - User A wants to sell ETH for USDC
  - User B wants to sell USDC for ETH
  - Match directly: no AMM needed, no slippage, no LP fees
- **Solver competition** — solvers propose batch solutions
  - Must satisfy all orders in the batch
  - Compete on price quality
  - Winner's solution executed on-chain
- **MEV protection by design** — batch execution prevents sandwiching
  - All orders in batch get uniform clearing price
  - No individual transaction to frontrun
- **GPv2Settlement** — on-chain settlement contract

### 1inch Fusion
- Similar intent model: user signs order, resolvers compete to fill
- Resolver staking for quality of service
- Dutch auction price decay
- Auction parameters tunable per order

### 🔗 DeFi Pattern Connection
- Aggregator routing → AMM module (P2M2)
- MEV protection in intents → MEV module (P3M5)
- Cross-chain intents → Cross-chain module (P3M6)
- Order signing → Permit/EIP-712 (P1S3)

---

## Day 4: Build Exercise

### Build: Simple Intent System
- **SignedOrder** — EIP-712 signed intent (sell token, buy token, amounts, deadline)
- **DutchAuction** — price decay over time
- **SimpleSolver** — fills orders using Uniswap V2 pool as liquidity source
- **Settlement** — verifies signature, executes swap, ensures minimum output

### Test Suite
- Order signing and verification
- Dutch auction price decay over time
- Solver fills at correct price
- Expired order rejection
- Insufficient output revert
- Multiple solvers competing (first valid fill wins)
- Fork test: solver routing through real Uniswap pool

---

## 🎯 Module 4 Exercises

**Workspace:** `workspace/src/part3/module4/`

### Exercise 1: DEX Aggregator Router
- Build a simple router that can split a trade across two pools
- Compare: single pool execution vs split execution
- Calculate break-even gas cost for splitting
- Test with mock pools of different depths

### Exercise 2: Intent Settlement System
- EIP-712 order signing
- Dutch auction price decay mechanism
- Solver fills orders from AMM liquidity
- Settlement contract with signature verification
- Test full lifecycle: sign → decay → fill → settle

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding why aggregation exists and how routing works
- Familiarity with the intent/solver model (UniswapX, CoW Protocol)
- Ability to reason about MEV implications of different execution models
- Understanding the shift from "user constructs tx" to "user signs intent"

**Common interview topics:**
- "How does a DEX aggregator find the optimal route?"
- "Explain the UniswapX Dutch auction mechanism"
- "What are the advantages of intent-based trading over traditional swaps?"
- "How does CoW Protocol's batch auction protect against MEV?"

---

## 📚 Resources

### Production Code
- [UniswapX](https://github.com/Uniswap/UniswapX)
- [CoW Protocol (GPv2)](https://github.com/cowprotocol/contracts)
- [1inch Aggregation Router](https://github.com/1inch/1inch-v6-aggregation-router)

### Documentation
- [UniswapX docs](https://docs.uniswap.org/contracts/uniswapx/overview)
- [CoW Protocol docs](https://docs.cow.fi/)
- [1inch docs](https://docs.1inch.io/)

### Further Reading
- [Paradigm: An Analysis of Intent-Based Markets](https://www.paradigm.xyz/)
- [Flashbots: The Future of MEV is SUAVE](https://writings.flashbots.net/)
- [Anoma: Intent-centric architectures](https://anoma.net/)

---

**Navigation:** [← Module 3: Yield Tokenization](3-yield-tokenization.md) | [Part 3 Overview](README.md) | [Next: Module 5 — MEV Deep Dive →](5-mev.md)

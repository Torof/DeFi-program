# Part 3 — Module 9: Capstone — Perpetual Exchange

> **Difficulty:** Advanced
>
> **Estimated reading time:** ~50 minutes | **Exercises:** ~15-20 hours (open-ended)

---

## 📚 Table of Contents

**Overview & Design Philosophy**
- [Why a Perpetual Exchange Capstone](#why-capstone)
- [The Perp Exchange Landscape](#perp-landscape)
- [Design Principles: Oracle-Based, L2-Native, Bounded Governance](#design-principles)

**Architecture Design**
- [Contract Structure: The 5 Core Contracts](#contract-structure)
- [Core Data Structures](#data-structures)
- [Design Decisions You'll Make](#design-decisions)
- [Deployment & Authorization](#deployment-authorization)
- [Storage Layout Considerations](#storage-layout)

**PerpEngine & Position Lifecycle**
- [The PerpEngine Contract](#engine-contract)
- [Multi-Collateral Margin: ETH and wstETH](#multi-collateral-margin)
- [The Position Lifecycle](#position-lifecycle)

**LiquidityPool & LP Economics**
- [The LiquidityPool Contract](#lp-pool)
- [PnL Settlement Between Traders and the Pool](#pnl-settlement)
- [Utilization & Open Interest Tracking](#utilization)

**Oracle, Sequencer & Risk Management**
- [The PriceFeed Contract](#price-feed)
- [Operational States](#operational-states)
- [Risk Management Parameters](#risk-params)
- [Parameter Governance](#parameter-governance)

**Liquidation Design**
- [Designing Your Liquidation System](#liquidation-design)
- [Keeper Incentive Sizing & MEV](#keeper-incentives)
- [Insurance Fund Design](#insurance-fund-design)
- [MEV-Aware Liquidation Flow](#mev-aware-liquidation)

**Testing & Hardening**
- [Fuzz and Fork Testing](#fuzz-fork)

**Suggested Build Order**

**Self-Assessment Checklist**

---

## 💡 Overview & Design Philosophy

<a id="why-capstone"></a>
### 💡 Concept: Why a Perpetual Exchange Capstone

You've spent 8 modules studying individual DeFi verticals — liquid staking, perpetual mechanics, yield tokenization, aggregation, MEV, cross-chain, L2 design, governance. A perpetual exchange is where the most critical of these converge into a single system under real production constraints. It's the highest-volume DeFi vertical, and building one demonstrates the kind of systems thinking that protocol teams hire for.

Your capstone integrates concepts from across Part 3:

- **Liquid staking (M1)** — wstETH as position collateral, requiring dual oracle pricing and de-peg risk awareness
- **Perpetual mechanics (M2)** — the entire foundation: funding rates, mark/index price, PnL calculation, margin, leverage, liquidation. M2 taught the primitives; this capstone assembles them into a production architecture
- **DEX aggregation (M4)** — the keeper/solver execution pattern: users create intents (orders), keepers fulfill them at valid oracle prices. The same intent model underlies GMX V2's two-step execution
- **MEV (M5)** — MEV-aware liquidation design: sizing keeper incentives, preventing gas wars, understanding that the liquidation fee IS the MEV bounty
- **L2 DeFi (M7)** — sequencer uptime checks, grace periods after restart, L2 gas model assumptions. Almost every production perp DEX runs on L2
- **Governance (M8)** — bounded parameter governance for risk parameters (max leverage, OI caps, fee rates) with timelock and hardcoded bounds

In Module 2's Exercise 2, you built a `SimplePerpExchange` — a single contract handling positions, liquidation, funding, and LP pool in one file. That was a learning exercise. This capstone decomposes the same system into 5 contracts with clear boundaries, explicit design decisions, and production-level concerns that a single-contract prototype glosses over.

**This is not a guided exercise.** You built scaffolded exercises in M1-M8. This is different — you'll design the architecture, make trade-offs, and own every decision. The curriculum provides architectural guidance, design considerations, and deep dives on new concepts. The implementation is yours.

**Connection to Part 2 Capstone:** Your P2 stablecoin could serve as the settlement asset for this exchange — a stablecoin backed by ETH and vault shares, settling perpetual contracts denominated in that same stablecoin. The two capstones together form a complete DeFi stack.

<a id="perp-landscape"></a>
### 💡 Concept: The Perp Exchange Landscape: Where Your Protocol Sits

Before designing, understand the field you're entering.

| Protocol | Architecture | Pricing | Liquidation | Runs On |
|---|---|---|---|---|
| **GMX V2** | Oracle-based pool (isolated GM markets) | Chainlink + signed prices | Keeper-triggered, partial | Arbitrum, Avalanche |
| **Synthetix Perps V2** | Debt pool + skew-based | Chainlink + Pyth | Keeper-triggered (Gelato) | Optimism |
| **dYdX V4** | Off-chain orderbook (Cosmos appchain) | Off-chain matching engine | Off-chain engine | dYdX Chain |
| **Hyperliquid** | Off-chain orderbook (custom L1) | Off-chain matching engine | Off-chain engine | Hyperliquid L1 |
| **Your protocol** | Oracle-based pool (isolated markets) | Chainlink + wstETH dual oracle | MEV-aware keeper, partial | L2 (Arbitrum/Base) |

Your protocol's design position: **oracle-based pool model like GMX V2, with multi-collateral margin (ETH + wstETH), MEV-aware liquidation with keeper incentives, L2-native with sequencer awareness, and bounded parameter governance.** Each of these choices has a rationale you'll be able to articulate in an interview.

**Why oracle-based pool, not orderbook?** The highest-volume perp DEXes (Hyperliquid, dYdX V4) use orderbooks — but their matching engines run off-chain, outside of Solidity smart contracts. You cannot build a production orderbook matching engine in Solidity; the gas costs and throughput constraints make it impractical. The oracle-based pool model (GMX, Gains Network) is where all the interesting on-chain Solidity lives: position management, funding rate engines, liquidation logic, oracle integration, LP economics — all verifiable on-chain. For a Solidity capstone, this is the right architecture.

**The 2025-2026 landscape context:** The perp DEX space is bifurcating. On one track: appchains and custom L1s with off-chain matching (Hyperliquid, dYdX, Lighter) capturing most volume through CeFi-like UX. On the other: EVM-native protocols on L2s (GMX V2, Synthetix, Gains Network) prioritizing composability, permissionlessness, and on-chain verifiability. Your protocol sits on the second track — and this is where EVM protocol engineering jobs exist.

**Historical lessons baked into your design:**
- **GMX V1's GLP risk:** A single shared pool (GLP) backing all markets meant a catastrophic loss in one market could drain the entire pool. GMX V2 moved to isolated per-market pools (GM) to contain risk. Your protocol uses isolated pools from day one.
- **Synthetix V2 oracle exploitation:** Front-running oracle updates enabled profitable "free trades" — open position, wait for oracle update, close at new price. GMX V2 solved this with keeper-executed orders: the user submits an order, a keeper executes it 1-2 blocks later at a fresh oracle price, eliminating the front-running window.
- **KiloEx exploit ($7.4M, April 2025):** A price oracle manipulation via access control vulnerability — the attacker changed the oracle price, opened a position, restored the price, and closed at profit. Your protocol uses Chainlink's decentralized oracle network, not a single updatable price source.

> 📖 **Study these:** Before you start building, spend time reading [GMX V2 Synthetics](https://github.com/gmx-io/gmx-synthetics) (the reference implementation for oracle-based perps) and [Synthetix Perps V2](https://github.com/Synthetixio/synthetix-v2/tree/develop/contracts/PerpsV2) (the debt-pool alternative). Module 2's code reading strategy for GMX V2 (lines 726-758) is your starting point.

<a id="design-principles"></a>
### 💡 Concept: Design Principles: Oracle-Based, L2-Native, Bounded Governance

Three principles define every design decision in your protocol.

**1. Oracle-based, LP-counterparty — Traders trade against the pool**

Traders don't match with other traders. They open positions against a liquidity pool at the oracle price. The pool is the counterparty — when a trader profits, the pool pays; when a trader loses, the pool receives. LPs deposit assets, earn fees and trader losses, and absorb trader profits.

Why: all the interesting contract logic is on-chain and in Solidity. Position management, funding rates, liquidation, LP economics — everything is verifiable. An orderbook matching engine would push the core logic off-chain, defeating the purpose of a Solidity capstone.

Trade-off: the pool takes directional risk. If traders are collectively profitable, the pool loses money. Risk management (OI caps, dynamic fees, funding rates) exists to keep this risk bounded.

**2. L2-native with sequencer awareness — Designed for Arbitrum/Base, not mainnet**

Almost every production perp DEX runs on L2. Your protocol is designed for L2 from the start, which means:
- **Sequencer uptime checks** — if the L2 sequencer goes down, oracle prices become stale and positions can't be managed. Your PriceFeed integrates Chainlink's Sequencer Uptime Feed (Module 7).
- **L2 gas assumptions** — on L2, calldata is the dominant cost, storage is relatively cheap. This inverts some mainnet optimization assumptions.
- **Block time awareness** — Arbitrum produces blocks every ~250ms, Optimism every 2 seconds. Your funding rate uses `block.timestamp` for accumulation, which works regardless of block time, but you should be aware of the resolution.

**3. Bounded governance — Governable risk parameters with hardcoded limits**

Unlike your Part 2 stablecoin capstone (fully immutable), this protocol has governable parameters. Perpetual markets are more dynamic than stablecoins — new markets need listing, max leverage needs tuning based on liquidity depth, OI caps need adjustment as the pool grows. Full immutability would cripple the protocol.

But governance is bounded. Every governable parameter has a hardcoded minimum and maximum range in the contract — even governance cannot set max leverage to 1000x or OI caps to infinity. Core accounting math (PnL formulas, funding rate accumulator logic, liquidation threshold calculations) is immutable.

Trade-off vs full immutability: you gain adaptability at the cost of a governance attack surface. The bounded pattern limits the damage — a governance attacker can move parameters within their ranges, but cannot break core invariants. Module 8's governance minimization philosophy applies: govern what you must, make immutable what you can.

<a id="prerequisite-map"></a>
#### 🔗 Cross-Module Prerequisite Map

Before you start, verify you're comfortable with these concepts from earlier modules. Each one directly maps to a component you'll build.

| Module | Concept | Where You'll Use It |
|---|---|---|
| **M1** | wstETH/ETH exchange rate, `stEthPerToken()` | PriceFeed — wstETH collateral valuation |
| **M1** | Dual oracle pattern (exchange rate vs market price) | PriceFeed — conservative collateral pricing |
| **M1** | De-peg risk scenarios (June 2022 stETH) | Risk parameters — margin buffer for LST collateral |
| **M2** | Funding rate accumulator pattern (Exercise 1) | FundingRate contract — per-second continuous accrual |
| **M2** | PnL formulas, margin math, liquidation price | PerpEngine — position lifecycle |
| **M2** | GMX V2 architecture (GM pools, two-step execution) | Overall architecture inspiration |
| **M2** | Insurance fund, ADL concepts | Liquidator — backstop design |
| **M4** | Intent/solver execution pattern | Design decision: two-step keeper execution |
| **M5** | MEV-aware protocol design, keeper incentives | Liquidator — keeper fee sizing, gas war prevention |
| **M5** | Commit-reveal, batch execution patterns | Liquidation MEV mitigation |
| **M7** | Chainlink Sequencer Uptime Feed, grace periods | PriceFeed — operational states |
| **M7** | L2 gas model (calldata-dominant cost) | Storage layout, gas optimization |
| **M8** | Governor + Timelock, governance minimization | Parameter governance with bounded ranges |
| **M8** | Emergency guardian pattern | Emergency pause (no parameter changes) |
| **P2 M3** | Chainlink `latestRoundData()`, staleness checks | PriceFeed — oracle integration basics |
| **P2 M4** | Utilization curve pattern (lending) | LiquidityPool — dynamic borrow fee scaling |
| **P2 M6** | MakerDAO `frob()` pattern (vault state changes) | PerpEngine — position modification pattern |
| **P2 M8** | Invariant testing, handler + ghost variable pattern | Testing — 6 critical invariants |

If any of these feel fuzzy, revisit the module before starting. This capstone assumes you've internalized them.

## 📋 Key Takeaways: Overview & Design Philosophy

After this section, you should be able to:

- Explain why a perpetual exchange is the ideal Part 3 integration project: it combines liquid staking (collateral), perpetual mechanics (core), MEV (liquidation design), L2 awareness (sequencer uptime), and governance (parameter management) into a single production architecture
- Position your protocol in the perp DEX landscape vs GMX V2, Synthetix, dYdX, and Hyperliquid, and articulate why oracle-based pool is the right model for an EVM Solidity capstone
- Map 18 specific prerequisite concepts across Part 2 and Part 3 modules to the exchange components where they'll be applied

---

## 💡 Architecture Design

<a id="contract-structure"></a>
### 💡 Concept: Contract Structure: The 5 Core Contracts

Your protocol has five contracts with clear responsibilities and clean interfaces between them.

```
                    ┌───────────────────┐
                    │   PriceFeed.sol    │
                    │ (Oracle + Seq.)    │
                    └────────┬──────────┘
                             │ getPrice()
          ┌──────────────────┼──────────────────┐
          │                  │                  │
┌─────────┴──────────┐  ┌───┴───────────────┐  │
│  FundingRate.sol    │  │  PerpEngine.sol   │  │
│ (Rate Accumulator) │──│  (Position Core)  │  │
└────────────────────┘  ├───────────────────┤  │
   updateFunding()      │ • Position storage │  │
                        │ • Margin math      │  │
                        │ • PnL calculation  │  │
                        │ • Open/Close/Modify│  │
                        └──┬────────────┬───┘  │
                           │            │      │
              ┌────────────┴──┐  ┌──────┴──────┴──────┐
              │ LiquidityPool │  │  Liquidator.sol     │
              │  (LP + Fees)  │  │ (Keeper Execution)  │
              └───────────────┘  └─────────────────────┘
                settlePnL()       liquidate()
```

**PerpEngine.sol** — The core. Stores all position state: size, collateral, entry price, funding index snapshots. Handles the complete position lifecycle: open, increase, decrease, close. Calls FundingRate to settle pending funding before any position change. Calls PriceFeed for oracle prices. Calls LiquidityPool to settle trader PnL on position close. Exposes view functions for remaining margin and liquidation eligibility that the Liquidator reads.

**LiquidityPool.sol** — The counterparty. LP deposits and withdrawals mint/burn pool share tokens. When a trader closes at a profit, the pool pays. When a trader closes at a loss, the pool receives. Tracks total deposits, accrued fees, and unrealized trader PnL. Enforces a reserve constraint — LPs cannot withdraw if it would leave the pool unable to cover maximum possible trader payout.

**FundingRate.sol** — Global funding accumulator with per-second continuous accrual. The instantaneous funding rate is derived from open interest skew: `fundingRatePerSecond = (longOI - shortOI) / (longOI + shortOI) × maxFundingRatePerSecond`. When longs dominate, the rate is positive (longs pay shorts); when shorts dominate, it's negative (shorts pay longs); when balanced, the rate is zero. This rate feeds a cumulative funding index (a fractional accumulator, scaled by precision) that PerpEngine snapshots on position open and settles on position close: `fundingOwed = (currentIndex - entryIndex) × sizeInUsd / PRECISION`. This is the same accumulator pattern from M2 Exercise 1 (lines 161-250, 478-505), extracted into its own contract.

**Liquidator.sol** — Checks if positions are undercollateralized (remaining margin below maintenance). Keeper-triggered execution: anyone can call `liquidate(positionId)` to close an underwater position. Handles partial liquidation (close only enough to restore margin) and full liquidation (position deeply underwater). Distributes remaining margin: keeper fee, insurance fund contribution, remainder to trader. When bad debt occurs (collateral doesn't cover losses), the Liquidator calls the LiquidityPool to draw from the insurance fund — the fund's balance lives in the pool (Design Decision 7), but the Liquidator triggers payouts.

**PriceFeed.sol** — Oracle integration with two pricing paths. Path 1 (ETH): Chainlink ETH/USD with staleness check. Path 2 (wstETH): dual oracle — wstETH/ETH exchange rate from the Lido contract + stETH/ETH market price via Chainlink, use the minimum (Module 1's dual oracle pattern), then multiply by ETH/USD. Integrates Chainlink's L2 Sequencer Uptime Feed with three operational states (Module 7's PriceOracleSentinel pattern). Returns prices in a consistent decimal base (30 decimals, matching GMX V2's convention).

> **🔗 Connection:** In M2's Exercise 2, you built a `SimplePerpExchange` — everything in one contract. This capstone decomposes that monolith into 5 contracts with explicit boundaries. It's the same architectural evolution as P2 M9's 4-contract stablecoin: you learn the mechanics in a single contract, then learn the engineering in a multi-contract system.

<a id="data-structures"></a>
### 💡 Concept: Core Data Structures

These are the key structs you'll design. Think carefully about what goes where — per-position vs per-market vs global.

**Per-position state:**

```solidity
struct Position {
    address account;              // position owner
    address collateralToken;      // ETH or wstETH
    uint256 sizeInUsd;            // [30 decimals] position size in USD
    uint256 sizeInTokens;         // [token decimals] position size in index tokens
    uint256 collateralAmount;     // [token decimals] margin deposited
    uint256 entryPrice;           // [30 decimals] oracle price at open
    int256  entryFundingIndex;    // [30 decimals] cumulative funding at open
    bool    isLong;               // long or short
}
```

Design considerations:
- **Why `sizeInUsd` AND `sizeInTokens`?** GMX V2 stores both. When a trader opens 1 ETH long at $3,000, `sizeInUsd = 3000e30` and `sizeInTokens = 1e18`. On close, PnL is calculated from the USD size (`sizeInUsd × (exitPrice - entryPrice) / entryPrice` for longs), while token-denominated calculations use `sizeInTokens`. Storing both avoids rounding errors from converting between them at different prices.
- **Why `entryFundingIndex` is `int256`?** The cumulative funding index can be negative (when shorts pay longs over time). Signed arithmetic is required.
- **Why no `entryBorrowIndex`?** Borrow fees (the utilization-based fee LPs charge for their capital being used) can be handled the same way — with a cumulative borrow index. If you add it, include `int256 entryBorrowIndex` here. For the core capstone, funding alone is sufficient; borrow fees are a stretch goal.

**Per-market state:**

```solidity
struct Market {
    // Pool reference
    address pool;                   // LiquidityPool for this market

    // Open interest tracking
    uint256 longOpenInterestUsd;    // [30 decimals] total long position size
    uint256 shortOpenInterestUsd;   // [30 decimals] total short position size

    // Risk parameters (governable within bounds)
    uint256 maxLongOpenInterest;    // [30 decimals] OI cap for longs
    uint256 maxShortOpenInterest;   // [30 decimals] OI cap for shorts
    uint256 maxLeverage;            // [×100] e.g., 5000 = 50x leverage
    uint256 maintenanceMarginBps;   // [BPS] e.g., 100 = 1%
    uint256 liquidationFeeBps;      // [BPS] keeper incentive
    uint256 openCloseFeeBps;        // [BPS] trading fee
}
```

Design considerations:
- **Why isolated markets?** Each market (ETH/USD, BTC/USD, etc.) has its own OI tracking and risk parameters. A catastrophic loss in one market doesn't affect another. This is GMX V2's isolated pool model — the lesson from V1's shared GLP risk.
- **Why BPS for risk parameters?** Basis points (1 BPS = 0.01%) give sufficient precision for percentage parameters while fitting neatly in `uint16` for storage packing. Note that `maxLeverage` uses a different scale: it's stored as leverage × 100 (so 5000 = 50x, 200 = 2x). This is NOT basis points — it's a multiplier with two decimal places of precision. The distinction matters: `maintenanceMarginBps = 100` means 1% margin, while `maxLeverage = 5000` means 50x leverage. Both fit in `uint16` for packing.

**Collateral configuration:**

```solidity
struct CollateralConfig {
    address token;                // WETH or wstETH
    address chainlinkFeed;        // ETH/USD or stETH/ETH feed
    bool    isWstETH;             // true = needs dual oracle pricing
    uint8   tokenDecimals;        // cached decimals
}
```

This is minimal by design. Each collateral type accepted as position margin needs a pricing path. The `isWstETH` flag tells PriceFeed to use the dual oracle pipeline from Module 1 instead of a single Chainlink lookup.

<a id="design-decisions"></a>
### 💡 Concept: Design Decisions You'll Make

These are real architectural choices with trade-offs. Think through each one before coding. There's no single right answer — what matters is that you can explain *why* you chose what you chose.

**Decision 1: Isolated or shared liquidity pool?**

- **Isolated (one pool per market, recommended):** Each market (ETH/USD, BTC/USD) has its own LiquidityPool. LP deposits go to a specific market. Risk is contained.
  - Pro: A catastrophic loss in ETH/USD doesn't drain the BTC/USD pool. GMX V2 moved to this model specifically to fix GLP's shared risk.
  - Con: Liquidity is fragmented. Less popular markets have thin pools.
- **Shared (one pool backs all markets):** GMX V1's GLP model. One pool, more liquidity per market, but contagion risk across all markets.
  - Pro: Deeper liquidity. Simpler LP experience.
  - Con: One bad market event can affect all LPs.

**Decision 2: Full or partial liquidation?**

- **Partial (recommended):** Close only enough of the position to restore the margin ratio above maintenance. Preserves trader capital and reduces cascade risk.
  - Pro: Capital-efficient, less PnL impact on the pool, reduces cascading liquidation risk (M2, lines 1183-1238).
  - Con: More complex to implement — need to calculate the exact amount to close.
- **Full:** Close the entire position. Simpler, but wastes margin on positions that just dipped below threshold.
  - Pro: Simple. Con: Aggressive — traders lose their entire position for a minor margin breach.

**Decision 3: Keeper incentive model — flat fee or percentage?**

- **Flat fee:** Fixed reward per liquidation (e.g., 5 USD worth of collateral). Predictable for keepers, minimal MEV.
  - Pro: Gas wars are bounded — the profit is fixed regardless of position size. MEV extractable value is capped (Module 5).
  - Con: May be insufficient for large, complex liquidations. Not profitable for keepers on L1 with high gas.
- **Percentage (e.g., 5% of liquidated size):** Proportional to position size. Creates larger incentive for large positions.
  - Pro: Always profitable to liquidate, scales with position size.
  - Con: **The liquidation fee IS the MEV bounty** (Module 5). A 5% fee on a $1M position is $50K — searchers will bid up priority fees to capture it. The excess profit beyond gas costs leaks to validators.

> Think about this in the context of your L2 deployment: on Arbitrum/Base, gas is cheap ($0.01-0.10 per tx), so even a small flat fee covers gas costs comfortably. The calculus is different from L1 where gas alone might cost $5-50.

**Decision 4: Funding rate — per-second continuous or periodic?**

- **Per-second continuous (recommended):** Use the rate accumulator pattern from M2 Exercise 1 (lines 161-250). Update a global cumulative index. Each position stores its entry index. Settlement = `(currentIndex - entryIndex) × positionSize`.
  - Pro: Gas-efficient (O(1) per update), precise, no periodic cron jobs needed. You already built this.
  - Con: Small overhead per position interaction (must settle before any change).
- **Periodic (classic 8-hour model):** Calculate and apply funding every 8 hours.
  - Pro: Simpler mental model. Con: Requires external trigger every 8 hours, discontinuous payments, unfair to positions that open/close between periods.

**Decision 5: Oracle model — Chainlink only or Chainlink + Pyth?**

- **Chainlink only (recommended for capstone):** Well-tested, decentralized, Foundry-friendly with mock feeds. Staleness checks with heartbeat timeouts.
  - Pro: Simpler integration, established in Part 2 (M3), easy to fork-test.
  - Con: Update frequency is slower (heartbeat-based, not per-block).
- **Chainlink + Pyth:** Higher frequency from Pyth's pull-based model. GMX V2 uses this dual approach.
  - Pro: More responsive pricing. Con: More complex integration, Pyth's pull model requires the caller to submit the price update (extra calldata, extra gas).

**Decision 6: Two-step keeper execution or direct execution?**

- **Direct execution with slippage protection (recommended for core):** User calls `openPosition()` directly with an `acceptablePrice` parameter. The function executes at the current oracle price if it's within the acceptable range.
  - Pro: Simpler, fewer contracts, immediate execution.
  - Con: Susceptible to oracle front-running (user sees oracle price, submits tx, oracle updates before inclusion).
- **Two-step keeper execution (stretch goal):** User creates an order (stored on-chain), keeper executes it 1-2 blocks later at a fresh oracle price. This is GMX V2's model and maps to M4's intent/solver pattern.
  - Pro: Eliminates oracle front-running. The keeper is the "solver" executing the user's "intent."
  - Con: More complex — needs an OrderVault contract, keeper infrastructure, order expiry.

**Decision 7: Insurance fund — separate contract or tracked within LiquidityPool?**

- **Within LiquidityPool (recommended):** Track `insuranceFundBalance` as a state variable in the pool. Funded by a portion of liquidation fees and trading fees.
  - Pro: Fewer cross-contract calls. Simpler accounting.
  - Con: Less transparent — insurance fund mixed with LP assets.
- **Separate contract:** A standalone InsuranceFund that receives fees and pays out bad debt.
  - Pro: Clean separation, transparent balance. Con: Extra contract, extra calls.

> Think through these before writing code. Your answers shape the entire architecture. Write them down — they become your Architecture Decision Record for the portfolio.

<a id="deployment-authorization"></a>
### 💡 Concept: Deployment & Authorization

Your 5 contracts have mutual dependencies. Think about deployment order and how contracts authorize each other:

- **PriceFeed** is standalone — deploy first (no protocol dependencies)
- **FundingRate** needs to know which contract can update it (PerpEngine)
- **LiquidityPool** needs to know which contract can settle PnL against it (PerpEngine)
- **PerpEngine** needs PriceFeed, FundingRate, and LiquidityPool addresses
- **Liquidator** needs PerpEngine (to check margin and close positions)

Deployment order: PriceFeed → FundingRate → LiquidityPool → PerpEngine (with all three addresses) → Liquidator. Use constructor arguments for immutable wiring — since risk parameters are governable but contract addresses are permanent, use `immutable` for cross-contract references.

This is simpler than the P2 capstone's deployment (which needed CREATE2 for circular dependencies between Engine and Stablecoin). Here the dependency graph is acyclic — each contract only references contracts deployed before it.

<a id="storage-layout"></a>
### 💡 Concept: Storage Layout Considerations

For gas optimization on the hot path (margin checks happen on every position change), think about how your structs pack into storage slots:

- **Position hot path reads:** `sizeInUsd`, `sizeInTokens`, `collateralAmount`, `entryPrice`, `entryFundingIndex` — these are all `uint256`/`int256`, each taking a full slot. No packing opportunity here, but they're all needed together, so sequential slot access benefits from warm storage.
- **Market risk parameters:** `maintenanceMarginBps`, `liquidationFeeBps`, `openCloseFeeBps` are BPS values, and `maxLeverage` is stored as leverage × 100 (see Data Structures). As `uint16` (max 65,535 — more than enough for all four), they pack into a single 32-byte slot, saving 3 SLOADs on every liquidation check.
- **30-decimal USD values:** Following GMX V2's convention, USD-denominated values use 30 decimals (e.g., $3,000 = `3000 * 10^30`). This provides ample precision for large positions while keeping the math consistent across different token decimal scales.

## 📋 Key Takeaways: Architecture Design

After this section, you should be able to:

- Sketch the 5-contract architecture from memory (PerpEngine, LiquidityPool, FundingRate, Liquidator, PriceFeed) with clear responsibilities and data flow between them
- Define the core data structures (Position per-position, Market per-market, CollateralConfig per-collateral) and explain why GMX V2 stores both `sizeInUsd` and `sizeInTokens`
- Articulate a position on each of the 7 design decisions with trade-off reasoning, especially the keeper incentive model and its MEV implications

> **🧭 Checkpoint — Before Moving On:**
> Can you sketch the 5-contract architecture from memory? Can you name the 7 design decisions and articulate a preference (with rationale) for each? If you can't, re-read the Architecture Design material above — the architecture IS the project, and changing it mid-build is expensive.

---

## 💡 PerpEngine & Position Lifecycle

<a id="engine-contract"></a>
### 💡 Concept: The PerpEngine Contract

PerpEngine is the heart of the exchange. Every position change flows through it.

**External functions — the position lifecycle:**

```solidity
interface IPerpEngine {
    // Position lifecycle
    function openPosition(
        bytes32 marketId,
        address collateralToken,
        uint256 collateralAmount,
        uint256 sizeDeltaUsd,
        bool isLong,
        uint256 acceptablePrice
    ) external;

    function increasePosition(bytes32 positionKey, uint256 collateralDelta, uint256 sizeDeltaUsd) external;
    function decreasePosition(bytes32 positionKey, uint256 sizeDeltaUsd, uint256 acceptablePrice) external;
    function closePosition(bytes32 positionKey, uint256 acceptablePrice) external;

    // Margin management
    function addMargin(bytes32 positionKey, uint256 amount) external;
    function removeMargin(bytes32 positionKey, uint256 amount) external;

    // View functions — used by Liquidator and UI
    function getPositionPnL(bytes32 positionKey) external view returns (int256 pnlUsd);
    function getRemainingMargin(bytes32 positionKey) external view returns (int256 marginUsd);
    function isLiquidatable(bytes32 positionKey) external view returns (bool);

    // Called by Liquidator only
    function liquidatePosition(bytes32 positionKey, uint256 closeAmount) external returns (uint256 remainingCollateral);
}
```

**The `positionKey` pattern:** Positions are identified by `keccak256(abi.encode(account, marketId, collateralToken, isLong))`. This means one position per (account, market, collateral, direction) combination. A trader can have both a long and a short in the same market — but not two separate longs. Note that `collateralToken` is part of the key: a trader with an ETH-margined long and a wstETH-margined long in the same market has two separate positions (different keys), each with its own margin and PnL.

> **🔗 Connection:** Compare to M2 Exercise 2's `SimplePerpExchange` where `openPosition()` lived in the same contract as `liquidate()`, `depositLiquidity()`, and `updateFunding()`. The responsibilities are the same; the boundaries are now explicit. This is also analogous to P2 M9's StablecoinEngine — the core contract that all others depend on, holding the key state and enforcing the key invariants.

**The critical rule — update funding before every position change:**

Every function that reads or modifies position state must first call `FundingRate.updateFunding(marketId)` to bring the global accumulator current, and then settle the position's pending funding payment. This is the perp equivalent of P2 M9's "call `drip()` before every debt-reading operation."

If you skip this: a position opened 3 days ago has accumulated funding that hasn't been applied to its collateral. The remaining margin calculation will be wrong. The position might appear healthy when it's actually underwater (or vice versa). Every state-changing function must follow this pattern:

```solidity
function _beforePositionChange(bytes32 positionKey, bytes32 marketId) internal {
    // 1. Update global funding accumulator to current timestamp
    fundingRate.updateFunding(marketId);

    // 2. Settle this position's pending funding
    int256 fundingOwed = _calculatePendingFunding(positionKey);
    _applyFunding(positionKey, fundingOwed);

    // 3. Now position state is current — safe to read/modify
}
```

<a id="margin-math"></a>
#### 🔍 Deep Dive: Margin Math with Multi-Collateral Pricing

The margin calculation is the most cross-cutting computation in your exchange. It touches PerpEngine (position state), PriceFeed (oracle prices), and FundingRate (pending funding) — all three in a single view call.

**The formula:**

```
remainingMargin = collateralValueUSD + unrealizedPnL - pendingFunding - accruedFees
```

Where:
- `collateralValueUSD` = collateral amount × collateral price (from PriceFeed — different path for ETH vs wstETH)
- `unrealizedPnL` = the trading profit/loss at current oracle price (Module 2's formulas)
- `pendingFunding` = funding accrued since last settlement (positive = owes, negative = receives)
- `accruedFees` = position open/close fees, borrow fees if implemented

**Liquidation check:** `remainingMargin < maintenanceMargin` where `maintenanceMargin = positionSizeUSD × maintenanceMarginBps / BPS`

**Walkthrough 1: ETH collateral, long position, healthy**

Setup: Trader opens 10x long ETH at $3,000 with 1 ETH collateral ($3,000 margin for $30,000 position).

```
Position:
  sizeInUsd      = 30,000e30          (= $30,000)
  sizeInTokens   = 10e18              (= 10 ETH)
  collateral     = 1e18               (= 1 ETH)
  entryPrice     = 3,000e30
  isLong         = true

Current state:
  ETH price      = $3,150 (5% up)
  Pending funding = -$20 (longs RECEIVE $20 — shorts are paying)
  Accrued fees    = $30 (open fee)
  Maintenance BPS = 100 (1%)

Step 1: Collateral value
  1 ETH × $3,150 = $3,150

Step 2: Unrealized PnL (long)
  $30,000 × ($3,150 - $3,000) / $3,000 = $30,000 × 0.05 = +$1,500

Step 3: Pending funding
  -$20 (negative = position RECEIVES funding, so this ADDS to margin)

Step 4: Accrued fees
  $30

Step 5: Remaining margin
  $3,150 + $1,500 - (-$20) - $30 = $4,640

Step 6: Maintenance margin
  $30,000 × 1% = $300

Result: $4,640 >> $300 — position is healthy ✓
```

**Walkthrough 2: wstETH collateral, short position, approaching liquidation**

Setup: Trader opens ~20x short ETH at $3,000 with 1 wstETH collateral. wstETH exchange rate is 1.15 (1 wstETH = 1.15 stETH). At entry, 1 wstETH ≈ $3,450, so a $69,000 position gives ~20x leverage. This is where the multi-collateral pricing pipeline kicks in.

```
Position:
  sizeInUsd      = 69,000e30         (= $69,000)
  collateral     = 1e18              (= 1 wstETH, ~$3,450 at entry → ~20x leverage)
  entryPrice     = 3,000e30
  isLong         = false

Current state:
  ETH price       = $3,100 (3.33% up — bad for shorts)
  wstETH rate     = 1.15 stETH per wstETH
  stETH/ETH       = 0.97 (3% de-peg — market stress)
  Pending funding = +$150 (shorts OWE $150 — longs are dominant)
  Accrued fees    = $69
  Maintenance BPS = 100 (1%)

Step 1: Collateral value (wstETH dual oracle — Module 1 pattern)
  Exchange-rate path: 1 × 1.15 × $3,100 = $3,565
  Market-price path: 1 × 1.15 × 0.97 × $3,100 = $3,458
  Use MINIMUM (conservative): $3,458

Step 2: Unrealized PnL (short — price went up, losing money)
  $69,000 × ($3,000 - $3,100) / $3,000 = $69,000 × (-0.0333) = -$2,300

Step 3: Pending funding
  +$150 (positive = position OWES funding, so this SUBTRACTS from margin)

Step 4: Accrued fees
  $69

Step 5: Remaining margin
  $3,458 + (-$2,300) - $150 - $69 = $939

Step 6: Maintenance margin
  $69,000 × 1% = $690

Result: $939 vs $690 — barely above maintenance, approaching liquidation ⚠️
```

Notice the dual oracle impact: the exchange-rate path valued the collateral at $3,565, but the market-price path (accounting for the 3% de-peg) valued it at $3,458 — a $107 difference. At 20x leverage, that difference is meaningful: it pushed remaining margin from $1,046 (exchange-rate only) down to $939. Using the minimum protects the protocol. A deeper de-peg (5-7% like June 2022) combined with the price move would push this position below maintenance.

> **🔗 Connection:** This dual oracle pattern comes directly from Module 1 (liquid staking, lines 904-927). The principle: during market stress, collateral valuations must be conservative. The June 2022 stETH de-peg saw a 5-7% discount — at 20x leverage, that de-peg alone could liquidate positions if the oracle didn't account for it.

<a id="multi-collateral-margin"></a>
### 💡 Concept: Multi-Collateral Margin: ETH and wstETH

Your exchange accepts two types of position collateral, each with a different pricing pipeline.

```
ETH Collateral:                    wstETH Collateral:

  ┌─────────────┐                    ┌─────────────┐
  │  Chainlink   │                    │   wstETH     │
  │  ETH/USD     │                    │  contract    │
  └──────┬──────┘                    └──────┬──────┘
         │                                  │ stEthPerToken()
         │ latestRoundData()                │
         │                           ┌──────┴──────┐
         │                           │ Exchange     │
         │                           │ Rate Price   │
         │                           └──────┬──────┘
         │                                  │
         │                           ┌──────┴──────┐    ┌─────────────┐
         │                           │             │    │  Chainlink   │
         │                           │   min( )    │◄───│  stETH/ETH   │
         │                           │             │    └─────────────┘
         │                           └──────┬──────┘
         │                                  │
         │                           ┌──────┴──────┐
         │                           │  × ETH/USD  │
         │                           └──────┬──────┘
         │                                  │
    ┌────┴────┐                       ┌─────┴─────┐
    │  USD    │                       │   USD     │
    │  value  │                       │   value   │
    └─────────┘                       └───────────┘
```

**ETH pricing** — single Chainlink lookup: `collateralAmount × ETH_USD_price`. Simple. This is the same oracle integration from Part 2 Module 3.

**wstETH pricing** — dual oracle pipeline (Module 1):

1. **Exchange rate path:** `wstETH.stEthPerToken()` returns the protocol-level exchange rate (e.g., 1.15). This rate only increases (barring slashing) and is set by Lido's trusted oracle committee — it's NOT manipulable by market trading.

2. **Market price path:** Chainlink's stETH/ETH feed reflects the actual market price. During normal conditions, stETH trades at or very near 1:1 with ETH. During stress (like June 2022), it can de-peg to 0.93-0.95.

3. **Use the minimum:** `min(exchangeRate × ETH_price, marketRate × ETH_price)`. The exchange rate path gives the "fair" value; the market price path gives the "right now" value. Using the minimum ensures conservative collateral valuation.

**Why not just use the exchange rate?** Because during a de-peg, wstETH collateral can't actually be sold at the exchange rate. If a liquidation needs to sell wstETH to recover funds, the market price is what matters. Using only the exchange rate would overvalue the collateral, potentially allowing undercollateralized positions to persist.

**Why not just use the market price?** Because the market price could temporarily diverge *upward* — an erroneously high Chainlink stETH/ETH reading (feed bug, manipulation) would overvalue collateral, allowing undercollateralized positions to appear healthy. The exchange rate path caps the valuation at the protocol's known-good rate, acting as a ceiling. Note that during downward moves (flash crash or real de-peg), min() always picks the lower market path — it does NOT dampen downward volatility. That's the correct behavior for protocol safety: conservative collateral valuation during stress, even if it means some positions get liquidated during brief noise. Smoothing (e.g., TWAP) could dampen false liquidations but adds oracle complexity beyond the core capstone scope.

```solidity
function getWstETHPrice() internal view returns (uint256 priceUsd) {
    // Path 1: Exchange rate — assumes stETH = ETH at par (protocol-theoretical value)
    // wstETH → stETH (protocol rate) → ETH (1:1 assumption) → USD
    uint256 stEthPerWstETH = IWstETH(wstETH).stEthPerToken();
    uint256 ethUsdPrice = _getChainlinkPrice(ethUsdFeed);
    uint256 exchangeRatePrice = stEthPerWstETH * ethUsdPrice / 1e18;

    // Path 2: Market rate — uses actual stETH/ETH market price (can diverge during de-peg)
    // wstETH → stETH (protocol rate) → ETH (Chainlink market rate) → USD
    // Note: stETH/ETH Chainlink feed uses 18 decimals (not 8 like most USD feeds)
    uint256 stEthEthRate = _getChainlinkPrice(stEthEthFeed);  // returns 30 decimals
    // stEthPerWstETH (18 dec) × stEthEthRate (30 dec) = 48 dec → /1e18 = 30 dec
    // then × ethUsdPrice (30 dec) = 60 dec → /1e30 = 30 dec
    uint256 marketPrice = stEthPerWstETH * stEthEthRate / 1e18 * ethUsdPrice / 1e30;

    // Conservative: use minimum — Path 1 is always >= Path 2 during a de-peg
    priceUsd = exchangeRatePrice < marketPrice ? exchangeRatePrice : marketPrice;
}
```

> **🔗 Connection:** This is Module 1's dual oracle pattern (lines 904-927) applied to a concrete use case. In M1, you studied it conceptually. Here, you implement it as a critical component of your exchange's margin system.

<a id="position-lifecycle"></a>
### 💡 Concept: The Position Lifecycle

Every position follows this lifecycle. At each step, understand what changes in storage and which cross-contract calls happen.

```
┌─────────┐     ┌───────────────┐     ┌───────────────┐     ┌──────────┐
│  OPEN   │────►│    MODIFY     │────►│    CLOSE      │────►│  SETTLED │
│         │     │               │     │               │     │          │
│ deposit  │     │ add margin    │     │ voluntary     │     │ PnL paid │
│ collat.  │     │ remove margin │     │ (trader)      │     │ or recv  │
│ set size │     │ increase size │     │ or forced     │     │ from pool│
│ snapshot │     │ decrease size │     │ (liquidation) │     │          │
│ funding  │     │               │     │               │     │          │
└─────────┘     └───────────────┘     └───────────────┘     └──────────┘
```

**Open — what happens:**
1. Call `_beforePositionChange()` — update global funding, settle any existing position's funding (relevant if adding to an existing position)
2. Transfer collateral from trader to PerpEngine
3. Get oracle price from PriceFeed (check `acceptablePrice` slippage)
4. Validate leverage: `sizeInUsd / collateralValueUsd ≤ maxLeverage`
5. Create Position struct with current funding index snapshot
6. Update Market OI totals: `longOpenInterestUsd += sizeDeltaUsd` (or short)
7. Check OI cap: `longOpenInterestUsd ≤ maxLongOpenInterest`
8. Charge open fee: deduct from collateral, send to pool

**Increase — what happens (non-obvious: weighted average entry price):**
1. Call `_beforePositionChange()` — settle pending funding at the OLD entry index
2. Get oracle price from PriceFeed
3. Update `sizeInUsd` and `sizeInTokens` first, then derive the new entry price:
   - `sizeInUsd += sizeDeltaUsd`
   - `sizeInTokens += sizeDeltaUsd / currentPrice`
   - `newEntryPrice = newSizeInUsd / newSizeInTokens`
   This is a harmonic weighted average — weighted by token amounts, not USD amounts. An arithmetic USD-weighted average (`(oldSize × oldEntry + delta × price) / newSize`) gives the wrong result and breaks PnL math.
   Example: Alice is long $30K at $3,000 (10 ETH). She increases by $30K at $3,200 (9.375 ETH). New sizeInTokens = 19.375 ETH, new sizeInUsd = $60K. New entry = $60K / 19.375 = $3,096.77.
4. (sizeInTokens already updated in step 3)
5. Re-snapshot the funding index — store the CURRENT cumulative index as the new `entryFundingIndex` (funding up to this point was already settled in step 1)
6. If collateral was added, update `collateralAmount`
7. Re-validate leverage: `newSizeInUsd / collateralValueUsd ≤ maxLeverage`
8. Update Market OI totals, check OI cap
9. Charge fee on the increased portion

Getting the weighted average entry wrong is a common bug — if you just overwrite `entryPrice` with the current price, the PnL calculation for the original portion breaks. And if you forget to re-snapshot the funding index after settling, the next settlement will double-count the funding already paid.

**Close — what happens:**
1. Call `_beforePositionChange()` — update and settle funding
2. Get oracle price from PriceFeed (check `acceptablePrice` slippage)
3. Calculate PnL: `sizeInUsd × (exitPrice - entryPrice) / entryPrice` for longs (for shorts: `sizeInUsd × (entryPrice - exitPrice) / entryPrice`)
4. Calculate remaining margin: `collateralValueUsd + pnl - funding - fees`
5. Settle with pool: if PnL > 0, pool pays trader; if PnL < 0, trader pays pool
6. Update Market OI totals: `longOpenInterestUsd -= sizeInUsd`
7. Transfer remaining collateral back to trader
8. Delete position from storage

**Liquidation close** follows the same flow as a voluntary close, except:
- Triggered by the Liquidator contract, not the trader
- No `acceptablePrice` check (liquidation happens at oracle price regardless)
- Remaining margin is distributed: keeper fee → insurance fund → trader (if anything remains)

#### ⚠️ Common Mistakes

**Mistake 1: Not settling funding before PnL calculation**

```solidity
// WRONG — funding hasn't been settled, remaining margin is stale
function closePosition(bytes32 key) external {
    int256 pnl = _calculatePnL(key);            // ← uses stale funding
    int256 margin = collateralValue + pnl;       // ← wrong margin
    // ...
}

// CORRECT — settle funding first
function closePosition(bytes32 key) external {
    _beforePositionChange(key, marketId);        // ← settles funding
    int256 pnl = _calculatePnL(key);             // ← now includes settled funding
    int256 margin = collateralValue + pnl;       // ← correct margin
    // ...
}
```

**Mistake 2: Allowing position size increase without re-checking leverage**

After increasing size, the effective leverage changes. If a trader has a 10x position and increases size without adding collateral, they might end up at 20x — potentially above `maxLeverage`. Always re-validate leverage after any size change.

**Mistake 3: Not updating OI totals on partial close**

When decreasing position size (not closing fully), update `longOpenInterestUsd` (or short) by the exact `sizeDeltaUsd` being removed. If you forget, the OI tracking diverges from reality — the OI Consistency invariant (Section 8) will catch this.

**Mistake 4: Using stale oracle price after sequencer downtime**

If the sequencer was down and just restarted, the oracle price may not have updated yet. Your PriceFeed should revert during the grace period for position opens (see Section 6). If you don't check, traders could open positions at stale prices and immediately profit when the oracle updates.

**Mistake 5: Forgetting fees when calculating remaining margin on close**

The close fee is deducted from the remaining margin. If remaining margin is $100 and the close fee is $30, the trader receives $70, not $100. This seems obvious, but in the code path it's easy to calculate PnL → settle with pool → return collateral — and forget that the fee hasn't been deducted yet.

## 📋 Key Takeaways: PerpEngine & Position Lifecycle

After this section, you should be able to:

- Describe the PerpEngine's external interface and explain the `positionKey` pattern for position identification
- Walk through the complete margin calculation formula with all four components (collateral value, unrealized PnL, pending funding, accrued fees) and the cross-contract calls involved
- Explain the wstETH dual oracle pricing pipeline and why using `min(exchangeRate, marketPrice)` protects both the protocol (de-peg risk) and the trader (flash crash overreaction)
- Trace the position lifecycle (open → modify → close) with state changes and cross-contract calls at each step
- Identify all 5 common mistakes and explain why each one breaks the system

---

## 💡 LiquidityPool & LP Economics

Module 2 described the concept of LPs as the counterparty to traders. This section covers the mechanics you'll actually implement — deposit/withdrawal math, PnL settlement flows, and the constraints that keep the pool solvent.

<a id="lp-pool"></a>
### 💡 Concept: The LiquidityPool Contract

The LiquidityPool has a dual role: it's the counterparty to every trade AND the fee recipient. When a trader profits, the pool pays. When a trader loses, the pool receives. LPs earn trading fees, funding fees, and borrow fees — in exchange for taking the other side of every position.

**Pool structure (per market):** Each market has its own isolated LiquidityPool (Design Decision 1). The pool holds the same collateral tokens that traders deposit — ETH and wstETH. LPs deposit ETH (or wstETH) into the pool; their deposits back all positions in that market regardless of direction. This differs from GMX V2's GM pools, which hold separate long and short tokens (e.g., ETH + USDC). Your simpler single-denomination approach means all PnL settles in the collateral token — when a trader profits, the pool pays in ETH/wstETH; when a trader loses, their ETH/wstETH collateral flows to the pool. LP deposits mint share tokens; LP withdrawals burn them.

**The key insight — share pricing can go DOWN:**

This looks like ERC-4626, and the share math is similar, but there's a critical difference. In a standard ERC-4626 vault (P2 Module 7), `totalAssets()` only goes up (barring hacks) because the vault earns yield. In a perp LP pool, `totalAssets()` can go down — because when traders are collectively profitable, the pool is paying them. LP share value can decrease.

```
poolValue = totalDeposits + totalFeesAccrued - netTraderPnL
```

Where `netTraderPnL` is the sum of all open positions' unrealized PnL. When traders are winning, `netTraderPnL` is positive — pool value drops. When traders are losing, `netTraderPnL` is negative — pool value rises. LPs are effectively selling volatility exposure to traders.

> **🔗 Connection:** Module 2 (lines 513-559) described this LP risk profile: "LPs are effectively selling options to traders." Here you implement the accounting that makes that abstraction concrete.

<a id="lp-deposit-withdrawal"></a>
#### 🔍 Deep Dive: LP Deposit & Withdrawal Math

**LP deposit — numeric walkthrough:** (all values in USD-equivalent for clarity; actual deposits are in the pool's collateral tokens — ETH or wstETH)

```
Starting state:
  Pool total assets  = $1,000,000
  Pool shares issued = 1,000,000 shares
  Share price        = $1.00

LP deposits $100,000:
  New shares = depositAmount × totalShares / totalAssets
             = $100,000 × 1,000,000 / $1,000,000
             = 100,000 shares

After deposit:
  Pool total assets  = $1,100,000
  Pool shares issued = 1,100,000 shares
  Share price        = $1.00 (unchanged — correct, deposit shouldn't change price)
```

**Traders profit — LP share value drops:**

```
Traders collectively profit $50,000 (net unrealized PnL across all positions):

  Pool effective value = $1,100,000 - $50,000 = $1,050,000
  Share price          = $1,050,000 / 1,100,000 = $0.9545

The LP's 100,000 shares are now worth:
  100,000 × $0.9545 = $95,454

They deposited $100,000, lost $4,546 to trader PnL.
This is the LP risk — when traders win, LPs lose.
```

**Traders lose — LP share value rises:**

```
Later, traders collectively lose $80,000 on their positions:

  Pool effective value = $1,100,000 + $80,000 = $1,180,000
  Share price          = $1,180,000 / 1,100,000 = $1.0727

The LP's 100,000 shares are now worth:
  100,000 × $1.0727 = $107,272

Plus the LP earns a share of trading fees and funding fees.
This is the LP reward — when traders lose, LPs profit.
```

**LP withdrawal constraint — reserved liquidity:**

LPs cannot withdraw if it would leave the pool unable to cover maximum possible trader payout. The constraint:

```
poolValueAfterWithdrawal ≥ maxPossibleTraderPnL
```

Where `maxPossibleTraderPnL` is a conservative estimate of the maximum payout across all open positions. In practice, this is approximated by the total open interest — if all traders were maximally profitable, the pool would need to pay up to the total OI (though this is a worst case that never actually happens because longs and shorts partially cancel).

A simpler approach: enforce a minimum utilization ratio. If more than (say) 80% of the pool is backing open positions, block withdrawals until utilization drops. This prevents a bank run where LPs withdraw en masse after a big trader win, leaving the pool unable to settle remaining positions.

<a id="pnl-settlement"></a>
### 💡 Concept: PnL Settlement Between Traders and the Pool

When a trader closes a position, the PnL settles against the pool atomically.

**Trader profits ($1,500 PnL):**
1. PerpEngine calls `LiquidityPool.settlePnL(+$1,500)`
2. Pool transfers $1,500 worth of assets to PerpEngine
3. PerpEngine transfers collateral + $1,500 to the trader
4. Pool's `totalAssets` decreases by $1,500

**Trader loses ($1,500 PnL):**
1. PerpEngine calls `LiquidityPool.settlePnL(-$1,500)`
2. PerpEngine transfers $1,500 worth of the trader's collateral to the pool
3. Remaining collateral returned to trader
4. Pool's `totalAssets` increases by $1,500

**All settlement is in the collateral token.** Both longs and shorts deposit ETH or wstETH as margin. PnL settles in that same collateral token — when a short profits (price dropped), the pool pays them in ETH/wstETH; when a short loses (price rose), their ETH/wstETH collateral flows to the pool. The "$1,500 worth" above means $1,500 of ETH or wstETH at the current oracle price. There is no stablecoin in the system unless you choose to add one as a third collateral type.

**The layered backstop:**

What if a position is so underwater that the trader's collateral doesn't cover the loss? This is bad debt, and it flows through a layered protection system:

```
┌──────────────────────────────────────────────────────┐
│ Layer 1: TRADER MARGIN                               │
│ First line of defense. The trader's collateral       │
│ absorbs losses until exhausted.                      │
├──────────────────────────────────────────────────────┤
│ Layer 2: INSURANCE FUND                              │
│ Funded by portion of liquidation fees and trading    │
│ fees. Absorbs bad debt when trader margin isn't      │
│ enough. Designed to handle most scenarios.           │
├──────────────────────────────────────────────────────┤
│ Layer 3: LP POOL                                     │
│ If insurance fund is depleted, the pool absorbs      │
│ remaining bad debt. This reduces LP share value.     │
├──────────────────────────────────────────────────────┤
│ Layer 4: AUTO-DELEVERAGING (ADL)                     │
│ Last resort. Force-close the most profitable         │
│ opposing positions to reduce system exposure.        │
│ Controversial but necessary for solvency.            │
└──────────────────────────────────────────────────────┘
```

> **🔗 Connection:** Module 2 (lines 1108-1182) explained insurance fund and ADL concepts. Here you design the actual flow between contracts. The Liquidator manages Layer 1-2, the pool absorbs Layer 3, and ADL (stretch goal) is an emergency function in PerpEngine.

<a id="utilization"></a>
### 💡 Concept: Utilization & Open Interest Tracking

**Open Interest (OI)** — the total USD value of all open positions — is the most important risk metric in your exchange.

```
Net exposure = longOpenInterestUsd - shortOpenInterestUsd
```

When net exposure is zero, long and short positions cancel each other out — the pool has no directional risk, and LP share value is unaffected by price movements (LPs only earn fees). When net exposure is highly positive (long-heavy), the pool is effectively short — if the price goes up, the pool pays.

**OI drives three things:**

1. **Funding rate:** The skew (long OI vs short OI) determines the funding rate direction and magnitude. When longs dominate, the funding rate is positive (longs pay shorts), incentivizing shorts to open and balance the skew. This is the self-correcting mechanism from Module 2 (lines 99-160).

2. **OI caps:** Each market has `maxLongOpenInterest` and `maxShortOpenInterest`. New positions that would push OI above the cap are rejected. Caps limit the pool's maximum exposure and cascade risk.

3. **Dynamic borrow fees:** A utilization-based fee that increases as the pool's assets are more heavily used. At low utilization, the borrow fee is low (attracting traders). At high utilization, the fee increases (discouraging new positions and incentivizing position closure). This is the same utilization curve pattern used in lending protocols (P2 Module 4).

**Utilization formula:**

```
utilization = totalOpenInterestUsd / poolTotalAssets
```

The borrow fee rate scales with utilization:

| Utilization | Borrow Rate (annualized) | Effect |
|---|---|---|
| 0-50% | 1-5% | Low cost, attract traders |
| 50-80% | 5-20% | Moderate cost, sustainable |
| 80-100% | 20-100%+ | High cost, discourages new positions |

These rates are per-second, applied via a borrow fee accumulator (same pattern as the funding rate accumulator). If you implement borrow fees (stretch goal), each position stores an `entryBorrowIndex` alongside `entryFundingIndex`.

## 📋 Key Takeaways: LiquidityPool & LP Economics

After this section, you should be able to:

- Explain the LP share pricing formula (`poolValue = deposits + fees - netTraderPnL`) and why LP share value can decrease, unlike standard ERC-4626 vaults
- Walk through the deposit/withdrawal math with concrete numbers, including the withdrawal constraint that prevents bank runs
- Describe the PnL settlement flow between PerpEngine and LiquidityPool, and the 4-layer backstop (margin → insurance fund → LP pool → ADL) for bad debt
- Explain how open interest drives funding rate, OI caps, and dynamic borrow fees — three different risk management tools from one metric

> **🧭 Checkpoint — Before Moving On:**
> Can you explain what happens to LP share value when traders collectively profit $100K against a $1M pool? Can you trace a PnL settlement from position close through to pool accounting? If not, re-read the walkthrough — LP economics is what makes the exchange sustainable.

---

## 💡 Oracle, Sequencer & Risk Management

This section is where Module 1 (dual oracle), Module 7 (sequencer uptime), and Module 8 (governance) converge into a single system. PriceFeed is not just an oracle wrapper — it's the risk control layer that determines when the exchange can operate and when it must pause.

<a id="price-feed"></a>
### 💡 Concept: The PriceFeed Contract

PriceFeed serves two roles: **price provider** (what is the current price?) and **operational gatekeeper** (is it safe to operate right now?).

**Two pricing paths** (already detailed in Section 4's multi-collateral margin):

```solidity
function getPrice(address token) external view returns (uint256 priceUsd) {
    // Gate 1: Sequencer uptime check (see next subsection)
    _checkSequencerUptime();

    if (token == weth) {
        // Path 1: ETH — single Chainlink lookup
        priceUsd = _getChainlinkPrice(ethUsdFeed);
    } else if (token == wstETH) {
        // Path 2: wstETH — dual oracle (Module 1 pattern)
        priceUsd = _getWstETHPrice();
    } else {
        revert UnsupportedCollateral();
    }
}
```

**Staleness checks:** Every Chainlink call checks that the price is fresh:

```solidity
function _getChainlinkPrice(address feed) internal view returns (uint256) {
    (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();

    if (answer <= 0) revert InvalidPrice();
    if (block.timestamp - updatedAt > HEARTBEAT_TIMEOUT) revert StalePrice();

    return uint256(answer) * PRICE_PRECISION / CHAINLINK_PRECISION;
}
```

The `HEARTBEAT_TIMEOUT` should match the feed's heartbeat (e.g., 3600 seconds for ETH/USD on Arbitrum). If the oracle hasn't updated within this window, something is wrong — better to revert than use a stale price.

> **🔗 Connection:** This is the same Chainlink integration pattern from Part 2 Module 3 (oracles). The dual oracle for wstETH extends it with Module 1's pattern.

<a id="sequencer-awareness"></a>
#### 🔍 Deep Dive: Sequencer Awareness for L2 Deployment

Almost every production perp DEX runs on L2 (GMX on Arbitrum, Synthetix on Optimism). Your protocol is L2-native, which means it must handle a failure mode that L1 protocols don't face: **the sequencer going down**.

**What happens when the L2 sequencer goes down:**
1. No new transactions are processed on the L2
2. Users cannot interact with the exchange — no opening, closing, or liquidating positions
3. Oracle prices freeze at their last update (Chainlink can't push updates if the sequencer won't process them)
4. When the sequencer comes back up, oracle prices jump to current values — potentially large moves for positions that were frozen

**Why this is especially dangerous for perps:** In a lending protocol, a 1-hour sequencer outage matters, but positions move slowly (interest accrues at basis points per day). In a perp exchange with 50x leverage, a 3% price move during a 1-hour outage can liquidate positions. Traders couldn't add margin during the outage. Immediate liquidation on restart — before traders can react — is unfair.

**Chainlink's L2 Sequencer Uptime Feed** (Module 7, lines 368-440) solves this:

```solidity
function _checkSequencerUptime() internal view {
    (, int256 answer,, uint256 startedAt,) =
        AggregatorV3Interface(sequencerUptimeFeed).latestRoundData();

    bool isSequencerUp = answer == 0;
    uint256 timeSinceUp = block.timestamp - startedAt;

    if (!isSequencerUp) revert SequencerDown();
    if (timeSinceUp < GRACE_PERIOD) revert GracePeriodNotOver();
}
```

The feed returns `answer = 0` when the sequencer is up, `answer = 1` when it's down. `startedAt` is when the current status began — so after a restart, `block.timestamp - startedAt` tells you how long the sequencer has been back up.

<a id="operational-states"></a>
### 💡 Concept: Operational States

Your exchange operates in three states, determined by the sequencer uptime feed:

```
┌────────────┐     restart     ┌────────────────┐     grace expires     ┌────────────┐
│ SEQUENCER  │────────────────►│  GRACE PERIOD  │──────────────────────►│  NORMAL    │
│   DOWN     │                 │  (e.g., 1 hour)│                       │ OPERATION  │
│            │◄────────────────│                │◄──────────────────────│            │
└────────────┘    goes down    └────────────────┘       goes down       └────────────┘
```

| Operation | Sequencer Down | Grace Period | Normal |
|---|---|---|---|
| Open position | Blocked | Blocked | Allowed |
| Close position | Blocked (no blocks processed) | Allowed | Allowed |
| Add margin | Blocked (no blocks processed) | Allowed | Allowed |
| Remove margin | Blocked (no blocks processed) | Blocked | Allowed |
| Liquidation | Blocked | Blocked | Allowed |
| LP deposit | Blocked (no blocks processed) | Allowed | Allowed |
| LP withdrawal | Blocked (no blocks processed) | Blocked | Allowed |

**Key design insight for perps:** The grace period must be tuned for leverage, not just for lending.

Module 7's Aave PriceOracleSentinel uses a grace period of 1 hour — generous enough for lending positions that move slowly. For a perp exchange, consider: at 50x leverage, a 2% price move wipes out a trader's margin. If ETH moves 2% during a 1-hour grace period, and the trader can't be liquidated during that time, the pool absorbs the loss.

Options:
- **Short grace period (5-15 minutes):** Allows less time for traders to react, but limits the protocol's exposure to stale-to-current price jumps.
- **Long grace period (1 hour):** More fair to traders, but the protocol takes more risk from unliquidatable positions during this window.
- **Dynamic grace period:** Shorter for higher-leverage markets, longer for lower-leverage. More complex but more precise.

This is a genuine design trade-off — there's no universally right answer. Document your choice and rationale.

**Funding rate during sequencer downtime:**

If the sequencer is down for 1 hour, should the funding rate accumulate retroactively on restart?

- **Option A: Retroactive accumulation.** When the sequencer comes back, `block.timestamp` has jumped forward by 1 hour. The next `updateFunding()` call applies 1 hour's worth of funding at once. Pro: mathematically consistent. Con: creates a sudden large funding payment that traders didn't expect.
- **Option B: Cap accumulation.** Limit the maximum time delta per `updateFunding()` call (e.g., max 10 minutes). If the sequencer was down for 1 hour, it takes 6 calls to catch up, spreading the funding over multiple blocks. Pro: smoother. Con: inaccurate during the catch-up period.
- **Option C: Freeze funding.** Don't accumulate funding during downtime. Reset `lastUpdateTime` on restart. Pro: fair. Con: breaks the zero-sum funding invariant — the time gap means less funding was collected than should have been.

Each option has trade-offs. Document your choice.

<a id="risk-params"></a>
### 💡 Concept: Risk Management Parameters

Your exchange's risk profile is defined by a set of interconnected parameters. Understanding their interactions is more important than the individual values.

| Parameter | What It Controls | Typical Range |
|---|---|---|
| `maxLeverage` | Maximum allowed leverage per market | 20x - 100x |
| `maintenanceMarginBps` | Threshold below which positions are liquidatable | 50 - 200 BPS (0.5% - 2%) |
| `maxLongOpenInterest` | OI cap for long positions per market | Depends on pool size |
| `maxShortOpenInterest` | OI cap for short positions per market | Depends on pool size |
| `liquidationFeeBps` | Keeper incentive for liquidation | 50 - 500 BPS |
| `openCloseFeeBps` | Trading fee charged on position open/close | 5 - 30 BPS (0.05% - 0.3%) |
| `borrowFeeFactor` | Utilization-based fee for using pool capital (stretch goal) | Variable |
| `insuranceFundTarget` | Target size for the insurance fund | 1-5% of pool |
| `gracePeriod` | Time after sequencer restart before liquidations resume | 300 - 3600 seconds |

**Parameter interactions — why you can't tune them independently:**

**Max leverage ↔ OI caps:** Higher max leverage means each position uses less collateral relative to its size — the pool's exposure per unit of collateral increases. If you raise `maxLeverage` from 50x to 100x, you should lower OI caps proportionally, or the pool faces double the risk.

**Max leverage ↔ Maintenance margin:** At 100x leverage, the collateral equals 1% of position size. If `maintenanceMarginBps` is also 100 (1%), the position is liquidatable the moment it opens. There must be a buffer: `initialMargin > maintenanceMargin`. Rule of thumb: `maintenanceMarginBps ≤ maxLeverage denominator / 2` (at 50x, maintenance ≤ 1%).

**Liquidation fee ↔ MEV landscape:** The liquidation fee is the MEV bounty (Module 5). Setting it too high creates gas wars. Setting it too low means no one liquidates. On L2 with cheap gas, even a small flat fee is profitable. See Section 7 for the full MEV analysis.

**OI caps ↔ Pool size:** OI caps should scale with pool size. A $10M pool shouldn't back $100M of open interest — a 10% adverse move would wipe out the entire pool. Rule of thumb: `maxOI ≤ poolSize × maxOIFactor` where `maxOIFactor` is 2-5x depending on risk appetite.

<a id="parameter-governance"></a>
### 💡 Concept: Parameter Governance

Module 8 taught governance minimization: govern what you must, make immutable what you can. Here's how that applies to your exchange.

**Governable (with timelock + bounds):**

```solidity
// Bounded parameter setter — governance can only adjust within hardcoded limits
function setMaxLeverage(bytes32 marketId, uint256 newMaxLeverage)
    external
    onlyGovernance
    timelocked
{
    require(
        newMaxLeverage >= MIN_MAX_LEVERAGE && newMaxLeverage <= MAX_MAX_LEVERAGE,
        "out of bounds"
    );
    markets[marketId].maxLeverage = newMaxLeverage;
}

// Hardcoded bounds — no governance action can exceed these
uint256 constant MIN_MAX_LEVERAGE = 200;    // 2x minimum
uint256 constant MAX_MAX_LEVERAGE = 10000;  // 100x maximum
```

Parameters that need governance:
- OI caps (must grow with pool size)
- Max leverage per market (new markets may need different limits)
- Fee rates (competitive tuning)
- Insurance fund target
- Grace period duration
- Adding new markets
- Adding new collateral types

**Immutable (no governance):**
- PnL calculation formulas
- Funding rate accumulator logic
- Liquidation threshold formula (the comparison, not the parameters)
- Oracle integration logic
- Cross-contract authorization (addresses set at deployment)

**Why bounded governance matters:**

A governance attacker who captures the timelock can change parameters — but within bounds. They could set `maxLeverage` to 100x (the maximum bound) to increase system risk, but they cannot set it to infinity. They could set OI caps very high, but not to `type(uint256).max`. The bounds limit the blast radius of a governance attack.

This is Module 8's progressive decentralization in practice: start with a team multisig as governor, add a timelock (24-48 hours), hardcode bounds on every parameter, and eventually transition to on-chain governance if the protocol matures.

**Emergency pause:**

A separate guardian (multisig) can pause the exchange — block all new positions and withdrawals. The guardian CANNOT change parameters, move funds, or bypass the timelock. This is Module 8's emergency guardian pattern (lines 674-691): limited powers for rapid response, without the ability to extract value.

## 📋 Key Takeaways: Oracle, Sequencer & Risk Management

After this section, you should be able to:

- Implement the PriceFeed with both pricing paths (ETH direct, wstETH dual oracle) and staleness checks
- Explain the three operational states (sequencer down, grace period, normal) and which exchange operations are allowed in each
- Analyze the funding rate accumulation problem during sequencer downtime and articulate a design choice with trade-offs
- Describe the interactions between risk parameters (why raising max leverage requires lowering OI caps) and why they can't be tuned independently
- Classify every exchange parameter as governable (with bounded ranges) or immutable, and explain the bounded governance pattern that limits governance attack blast radius

> **🧭 Checkpoint — Before Moving On:**
> Can you draw the three operational states and list which operations are blocked in each? Can you explain why the grace period matters more for perps than for lending? If not, re-read the sequencer awareness section — this is a production-critical concern that many L2 protocols get wrong.

---

## 💡 Liquidation Design

Module 2 taught what liquidation is and why it exists. This section covers how you design the system — partial vs full, keeper incentive economics, MEV implications, and the complete flow across contracts.

<a id="liquidation-design"></a>
### 💡 Concept: Designing Your Liquidation System

**How perp liquidation differs from your P2 stablecoin capstone:**

In the stablecoin capstone, liquidation meant auctioning collateral — starting a Dutch auction where bidders compete to buy the collateral at a declining price. The Liquidator was complex because it managed auction state, price decay, partial fills, and bad debt.

Perp liquidation is conceptually simpler: the Liquidator closes the position at the current oracle price. There's no auction. The position is marked to market, PnL is settled against the pool, and remaining margin is distributed. The complexity comes from:
1. **Partial vs full liquidation** — how much of the position to close
2. **Keeper incentives** — making liquidation profitable without creating excessive MEV
3. **Insurance fund management** — handling bad debt when collateral doesn't cover losses
4. **Sequencer-aware gating** — not liquidating during grace period

**The liquidation flow:**

```
Keeper detects undercollateralized position
         │
         ▼
Liquidator.liquidate(positionKey)
         │
         ├─── PriceFeed.getPrice() — check sequencer uptime + get oracle price
         │
         ├─── PerpEngine.isLiquidatable(positionKey) — verify margin breach
         │
         ├─── Determine partial vs full liquidation amount
         │
         ├─── PerpEngine.liquidatePosition(positionKey, closeAmount)
         │         │
         │         ├─── Settle funding
         │         ├─── Calculate PnL on closed portion
         │         ├─── Settle PnL with LiquidityPool
         │         ├─── Update OI totals
         │         └─── Return remaining collateral to Liquidator
         │
         ├─── Distribute remaining collateral:
         │         ├─── Keeper fee → keeper
         │         ├─── Insurance contribution → insurance fund
         │         └─── Remainder → trader (if any)
         │
         └─── If bad debt (collateral < 0 after PnL):
                   └─── Insurance fund absorbs it
```

<a id="partial-liquidation"></a>
#### 🔍 Deep Dive: Partial vs Full Liquidation

When a position's remaining margin drops below maintenance, you don't necessarily need to close the entire thing. Partial liquidation closes just enough to restore the margin ratio above maintenance.

**When to use partial liquidation:**
- Remaining margin is below maintenance but still positive
- Closing a portion of the position would bring the ratio back above maintenance
- This is more capital-efficient for the trader and reduces cascade risk

**When to use full liquidation:**
- Remaining margin is zero or negative (bad debt scenario)
- The position is so deeply underwater that partial liquidation can't restore health
- As a simplification: if remaining margin is below (say) 50% of maintenance, do full liquidation

**Partial liquidation math:**

The goal: close enough position size so that after closing, `remainingMargin / positionSize ≥ maintenanceMarginRatio`.

```
The position currently has:
  remainingMargin = M    (below maintenance)
  positionSize    = S    (in USD)
  maintenanceRate = r    (e.g., 0.01 for 1%)
  liquidationFee  = f    (e.g., 0.005 for 0.5%)

We need to find closeAmount (in USD) such that after closing:
  (M - closeAmount × f) / (S - closeAmount) ≥ r

Why: when we close a portion:
  1. The closed portion's PnL is realized (already reflected in M)
  2. The position size decreases by closeAmount
  3. The keeper fee (closeAmount × f) is deducted from margin

Solving for closeAmount:
  M - closeAmount × f ≥ r × (S - closeAmount)
  M - closeAmount × f ≥ r × S - r × closeAmount
  r × closeAmount - closeAmount × f ≥ r × S - M
  closeAmount × (r - f) ≥ S × r - M
  closeAmount = (S × r - M) / (r - f)
```

**Numeric walkthrough:**

```
Position:
  Size          = $100,000
  Margin        = $800     (remaining after PnL and funding)
  Maintenance   = 1%       (= $1,000 required)
  Liq. fee      = 0.5%

Problem: $800 < $1,000 — position is liquidatable

Close amount = ($100,000 × 0.01 - $800) / (0.01 - 0.005)
             = ($1,000 - $800) / 0.005
             = $200 / 0.005
             = $40,000

Close $40,000 of the position:
  Remaining size  = $60,000
  New maintenance = $60,000 × 1% = $600
  Keeper fee      = $40,000 × 0.5% = $200
  New margin      = $800 - $200 (fee) = $600

Check: $600 / $60,000 = 1% = maintenanceRate ✓

The trader keeps a $60,000 position instead of losing everything.
```

> **🔗 Connection:** Module 2 (lines 1030-1106) showed the liquidation engine flow with full liquidation. Partial liquidation is an extension — close a calculated portion instead of the whole thing. The concept was mentioned in M2 but not detailed.

<a id="keeper-incentives"></a>
### 💡 Concept: Keeper Incentive Sizing & MEV

This is where Module 5 (MEV) directly applies to your exchange design.

**The fundamental tension:** The keeper fee must be:
- **High enough** that keepers are willing to spend gas to liquidate (otherwise bad debt accumulates)
- **Low enough** that it doesn't create excessive MEV extraction (otherwise keepers compete via gas wars, and the surplus flows to validators instead of staying in the system)

**The key insight from Module 5:** "The liquidation fee IS the MEV bounty." If your liquidation fee is 5% of position size, every undercollateralized $1M position is a $50K profit opportunity. On L1, multiple searchers would bid up priority fees to capture that $50K — most of the profit leaks to validators through priority gas auctions (Module 5, lines 338-355). On L2, the sequencer has ordering power, which changes the dynamics but doesn't eliminate the issue.

**Three approaches to keeper incentive design:**

**Approach 1: Flat fee (simplest)**

A fixed USD reward per liquidation (e.g., $5-10 in ETH), regardless of position size.

```solidity
uint256 constant KEEPER_FEE_USD = 5e30; // $5 in 30-decimal format

function _distributeMargin(uint256 remainingCollateral, uint256 collateralPrice) internal {
    uint256 keeperFee = KEEPER_FEE_USD * PRECISION / collateralPrice;
    // ... transfer keeperFee to keeper
}
```

Pro: MEV is bounded — the maximum extractable value is $5 per liquidation, regardless of position size. No gas wars.
Con: Doesn't scale with position complexity. A large, multi-collateral position is harder to liquidate but pays the same fee.

**Approach 2: Percentage with cap**

A percentage of the liquidated amount (e.g., 0.5%) with a maximum cap (e.g., $1,000).

Pro: Scales with position size up to the cap, then flattens. Large positions are worth liquidating, but the cap prevents extreme MEV bounties.
Con: Still creates MEV up to the cap.

**Approach 3: Decaying keeper fee (most MEV-resistant)**

The keeper fee starts high and decreases over time after the position becomes liquidatable. The first block after liquidation eligibility pays the highest fee. Each subsequent block, the fee drops.

```
Block 0 (liquidation eligible): Fee = 2% of position
Block 1: Fee = 1.8%
Block 2: Fee = 1.6%
...
Block 10: Fee = 0%
```

Pro: No gas wars — there's no rush to be first. Each keeper enters at their own threshold of acceptable profit. Natural price discovery for keeper services.
Con: More complex to implement. Risk that the fee decays to zero before anyone liquidates (if gas costs are high).

> **🔗 Connection:** This decaying fee pattern is the liquidation equivalent of your P2 capstone's Dutch auction — both use declining prices to eliminate gas wars and allow natural entry points. Module 5's MEV-aware protocol design principles (lines 561-587) apply directly here.

**On L2, the math is different.** On Arbitrum/Base, gas costs are $0.01-0.10 per transaction. Even a $1 keeper fee is profitable. The MEV concern shifts from gas wars to sequencer ordering — the sequencer could prioritize its own liquidation transactions. But this is an infrastructure-level concern, not something your contract can solve. A flat fee of $5-10 is a practical choice for L2 deployment.

<a id="insurance-fund-design"></a>
### 💡 Concept: Insurance Fund Design

The insurance fund sits between trader margin and the LP pool in the backstop hierarchy. Its job: absorb bad debt so LPs don't have to.

**Funding sources:**
- Portion of liquidation fees (e.g., 50% of keeper fee goes to insurance)
- Portion of trading fees (e.g., 10% of open/close fees)
- Portion of borrow fees (if implemented)

**When it pays out:**
- A liquidation results in bad debt (position's remaining margin is negative after PnL)
- The insurance fund covers the shortfall up to its balance
- If the insurance fund is insufficient, the remaining bad debt hits the LP pool (LP share value drops)

**Sizing target:** The insurance fund should be large enough to cover a 2-3 standard deviation price move across the maximum OI. For example: if max OI is $10M and a 3-sigma daily move is 15%, the max bad debt in an extreme event is ~$1.5M. The insurance fund target should be at least $1.5M, or 15% of max OI.

In practice, the fund starts small and grows over time from fee revenue. Early on, the protocol is more vulnerable — this is an accepted risk in most perp protocols.

**ADL (Auto-Deleveraging)** — the last resort:

If the insurance fund is depleted AND the LP pool can't absorb more bad debt, ADL kicks in. ADL force-closes the most profitable opposing positions to reduce system exposure. Module 2 (lines 1139-1182) explained the concept; implementing it is a stretch goal for this capstone. At minimum, your system should track when bad debt exceeds insurance fund capacity and emit events indicating ADL would be needed.

<a id="mev-aware-liquidation"></a>
### 💡 Concept: MEV-Aware Liquidation Flow

Putting all the protection layers together — here's how a well-designed liquidation flow resists MEV extraction and handles edge cases:

```
1. SEQUENCER CHECK
   └─ PriceFeed verifies sequencer is up AND past grace period
      └─ If not → revert (no liquidations during downtime/grace)

2. ORACLE FRESHNESS
   └─ PriceFeed checks Chainlink staleness (heartbeat timeout)
      └─ If stale → revert (no liquidating on old prices)

3. MARGIN VERIFICATION
   └─ PerpEngine settles funding, calculates remaining margin
      └─ If above maintenance → revert (position is healthy)

4. PARTIAL LIQUIDATION CALCULATION
   └─ Determine close amount to restore health (or full if deeply underwater)
      └─ Close only what's needed — reduce cascade risk

5. POSITION CLOSURE AT ORACLE PRICE
   └─ PnL settled at current (fresh) oracle price — no auction, no bidding
      └─ This eliminates the gas war over auction bids

6. MARGIN DISTRIBUTION
   └─ Keeper fee → keeper (flat or capped — bounded MEV)
   └─ Insurance contribution → fund
   └─ Remainder → trader

7. BAD DEBT HANDLING
   └─ If remaining margin < 0 after PnL:
      └─ Insurance fund absorbs → if insufficient → LP pool absorbs
```

Each layer addresses a specific risk: (1-2) stale/missing data, (3) false liquidation, (4) over-liquidation, (5) auction gaming, (6) MEV extraction, (7) insolvency.

<a id="liquidation-walkthrough"></a>
#### 🔍 Deep Dive: Full Liquidation Walkthrough

End-to-end walkthrough with concrete numbers, tracing the cross-contract calls.

**Setup:**

```
Position:
  Account     = Alice
  Market      = ETH/USD
  Direction   = Long
  Collateral  = 5 wstETH (wstETH margin)
  Size        = $150,000 (~9x leverage at $3,000 entry)
  Entry price = $3,000
  Entry funding index = 1.005000 (30-decimal scaled)

At entry: 5 × 1.15 × $3,000 = $17,250 collateral → $150,000 / $17,250 ≈ 8.7x leverage.

Current state:
  ETH price       = $2,920 (2.67% drop)
  wstETH rate     = 1.15 stETH per wstETH
  stETH/ETH       = 1.0 (no de-peg)
  Funding index   = 1.023000 (longs have been paying)
  Maintenance     = 1% (100 BPS)
  Liquidation fee = 0.5% (50 BPS)
```

**Step 1: Keeper calls `Liquidator.liquidate(alicePositionKey)`**

**Step 2: Sequencer + Oracle check**
- PriceFeed checks sequencer uptime feed → sequencer is up, past grace period ✓
- PriceFeed checks Chainlink staleness → ETH/USD updated 30 seconds ago ✓
- PriceFeed returns ETH price = $2,920

**Step 3: Settle funding**
- FundingRate.updateFunding(ethUsdMarket) — brings accumulator to current
- Funding owed = (currentIndex - entryIndex) × sizeInUsd = (1.023 - 1.005) × $150,000 = 0.018 × $150,000 = $2,700
- Alice owes $2,700 in funding (longs have been paying shorts)

**Step 4: Calculate remaining margin**
```
Collateral value (wstETH dual oracle):
  5 × 1.15 × min(1.0, 1.0) × $2,920 = $16,790

Unrealized PnL (long, price dropped):
  $150,000 × ($2,920 - $3,000) / $3,000 = $150,000 × (-0.0267) = -$4,000

Pending funding: -$2,700 (owed)
Open fee (already deducted): $0

Remaining margin = $16,790 + (-$4,000) - $2,700 = $10,090
Maintenance margin = $150,000 × 1% = $1,500
```

$10,090 > $1,500 — Alice is NOT liquidatable yet. The keeper's transaction reverts.

**Where is the liquidation trigger?** Let's find the exact price. Remaining margin depends on ETH price (P):

```
remainingMargin = (5 × 1.15 × P) + $150,000 × (P - $3,000) / $3,000 - $2,700
               = 5.75P + 50P - 150,000 - 2,700
               = 55.75P - 152,700

Set remainingMargin = $1,500 (maintenance):
  55.75P = 154,200
  P = $2,766

So liquidation triggers at ETH ≈ $2,766 — a 7.8% drop from entry.
```

**Let's move the price to exactly the trigger: ETH = $2,766**

```
Collateral value: 5 × 1.15 × $2,766 = $15,907
Unrealized PnL: $150,000 × ($2,766 - $3,000) / $3,000 = -$11,700
Funding owed: $2,700

Remaining margin = $15,907 - $11,700 - $2,700 = $1,507
Maintenance margin = $1,500

$1,507 ≈ $1,500 — right at the threshold. A keeper can now liquidate. ✓
```

In a well-functioning system, keepers liquidate here: there's still $1,507 in remaining margin to cover the keeper fee ($750 at 0.5% of $150K), the insurance fund contribution, and return the remainder to Alice. This is the healthy path.

**But what if price moves too fast? ETH = $2,700 (10% drop, gap risk)**

```
Collateral value: 5 × 1.15 × $2,700 = $15,525
Unrealized PnL: $150,000 × ($2,700 - $3,000) / $3,000 = -$15,000
Funding owed: $2,700

Remaining margin = $15,525 + (-$15,000) - $2,700 = -$2,175
```

Remaining margin is NEGATIVE — bad debt scenario. No keeper liquidated between $2,766 and $2,700. Full liquidation.

**Step 5: Close position at oracle price ($2,700)**
- PnL = -$15,000, settled against pool (pool receives $15,000 worth of value)
- All collateral goes to cover the loss

**Step 6: Margin distribution**
- Remaining after PnL + funding = $15,525 - $15,000 - $2,700 = -$2,175
- Bad debt = $2,175
- Keeper fee is paid from the insurance fund (to incentivize liquidation even in bad debt scenarios)
- Insurance fund absorbs $2,175 of bad debt + pays keeper fee

**Step 7: Post-liquidation state**
- Alice's position is deleted from storage
- ETH/USD market `longOpenInterestUsd` decreased by $150,000
- Insurance fund balance decreased by $2,175 + keeper fee
- LP pool received $15,000 from the losing trade
- Keeper received a flat fee from the insurance fund

> **🧭 Note:** The gap between $2,766 (liquidation trigger) and $2,700 (bad debt) is only $66 — about 2.4%. At ~9x leverage, there's a reasonable buffer for keepers to act. At higher leverage (50x+), the buffer shrinks proportionally, making gap-risk bad debt far more likely. This is why `maintenanceMarginBps` must be larger for higher-leverage markets.

## 📋 Key Takeaways: Liquidation Design

After this section, you should be able to:

- Contrast perp liquidation (close at oracle price) with the stablecoin capstone's Dutch auction and explain why perps don't need auctions
- Calculate the partial liquidation amount needed to restore a position's margin ratio, and explain when full liquidation is necessary
- Analyze the keeper incentive as an MEV bounty (Module 5) and compare three approaches: flat fee, percentage with cap, and decaying fee
- Trace a complete liquidation through all 7 protection layers (sequencer check → oracle freshness → margin verification → partial calculation → closure → distribution → bad debt handling)

---

## 💡 Testing & Hardening

<a id="critical-invariants"></a>
#### 🔍 Deep Dive: The 6 Critical Invariants

Invariant testing (Part 2 Module 8, lines 522-620) is where you prove your protocol works under arbitrary sequences of operations. These 6 invariants are your protocol's correctness properties.

**Invariant 1: Solvency**

```
Pool assets ≥ maximum possible payout to all open positions
```

Why: the pool must always be able to pay traders who close at a profit. If this breaks, the last traders to close can't get paid — a bank run scenario. Note: this is an approximation — the "maximum possible payout" for unlimited-upside positions (longs) is theoretically infinite, so in practice you bound it by the position sizes and a reasonable price range.

Handler operations that test it: `openPosition`, `closePosition`, `moveOraclePrice`, `lpDeposit`, `lpWithdraw`.

**Invariant 2: Conservation**

```
ERC20(collateralToken).balanceOf(engine) + ERC20(collateralToken).balanceOf(pool)
  + ERC20(collateralToken).balanceOf(liquidator)
  == sum(position.collateralAmount for all positions) + poolReserves + insuranceFundBalance
```

Why: tokens must be accounted for across all contracts that hold them. No tokens created or destroyed outside of expected flows. If this breaks, collateral is leaking. This is the perp equivalent of P2 M9's Conservation invariant.

Handler operations that test it: all operations that move tokens between contracts.

**Invariant 3: Funding Balance (Zero-Sum)**

```
sum(fundingPaid by longs) == sum(fundingReceived by shorts)  (and vice versa)
```

Why: funding is a transfer between longs and shorts — it should never create or destroy value. If total funding paid ≠ total funding received, the accumulator math is broken. This is unique to perp protocols and has no equivalent in the stablecoin capstone.

Caveat: rounding errors in per-position settlement can cause tiny imbalances (1-2 wei). Allow a small epsilon in the invariant check.

Handler operations that test it: `openPosition`, `closePosition`, `advanceTime` (triggers funding accrual).

**Invariant 4: OI Consistency**

```
Market.longOpenInterestUsd == sum(position.sizeInUsd for all long positions in that market)
Market.shortOpenInterestUsd == sum(position.sizeInUsd for all short positions in that market)
```

Why: the market's tracked OI must match the sum of individual positions. If this diverges, OI cap enforcement is wrong — the protocol might allow more OI than it thinks it has. This mirrors P2 M9's Accounting invariant (per-type totalNormalizedDebt == sum of individual vaults).

Handler operations that test it: `openPosition`, `closePosition`, `increasePosition`, `decreasePosition`, `liquidate`.

**Invariant 5: Margin Safety**

```
For every open position:
  getRemainingMargin(positionKey) ≥ maintenanceMargin
  OR the position is currently being liquidated
```

Why: unhealthy positions should not persist. If this breaks, the protocol is failing to protect itself. Same concept as P2 M9's Health invariant.

Caveat: this invariant can temporarily fail after a `moveOraclePrice` handler call makes positions underwater before the fuzzer calls `liquidate`. To handle this: either check the invariant only after a `liquidate` call has been given a chance to run, or track "positions known to be underwater" as ghost state in the handler.

Handler operations that test it: `moveOraclePrice`, `advanceTime`, `liquidate`.

**Invariant 6: Position Integrity**

```
For every position in storage:
  position.sizeInUsd > 0
  position.collateralAmount > 0
  position.entryPrice > 0
```

Why: no ghost positions should exist with zero size but nonzero collateral (or vice versa). If a position is fully closed or fully liquidated, it should be deleted from storage. Ghost positions waste gas on iteration and can cause accounting errors.

Handler operations that test it: `closePosition`, `liquidate`.

**Handler design:**

```solidity
contract SystemHandler is Test {
    // Bounded operations — each wraps protocol calls with realistic inputs
    function openPosition(uint256 seed, uint256 collateral, uint256 size, bool isLong) external;
    function closePosition(uint256 seed) external;
    function increasePosition(uint256 seed, uint256 sizeDelta) external;
    function decreasePosition(uint256 seed, uint256 sizeDelta) external;
    function addMargin(uint256 seed, uint256 amount) external;
    function removeMargin(uint256 seed, uint256 amount) external;
    function moveOraclePrice(uint256 seed, int256 deltaBps) external;  // bounded: ±20%
    function advanceTime(uint256 seconds_) external;                    // bounded: 1-86400
    function liquidate(uint256 seed) external;                          // picks a random position
    function lpDeposit(uint256 seed, uint256 amount) external;
    function lpWithdraw(uint256 seed, uint256 amount) external;
    function toggleSequencer(bool isUp) external;                       // test operational states
}
```

> **🔗 Connection:** This is the same handler + ghost variable + invariant assertion pattern from Part 2 Module 8's VaultInvariantTest exercise. Same methodology, bigger system, new invariants (funding balance, OI consistency).

<a id="fuzz-fork"></a>
### 💡 Concept: Fuzz and Fork Testing

**Fuzz tests:** Beyond invariants, write targeted fuzz tests:
- Random open/close sequences should never leave ghost positions in storage
- `addMargin(amount) → removeMargin(amount)` should leave position unchanged (round-trip)
- Random price movements followed by margin checks should match manual calculation
- Funding settlement on close should match `(currentIndex - entryIndex) × size` exactly (or within 1 wei)
- LP deposit followed by immediate withdrawal should return approximately the deposited amount (minus fees if any)

**Fork tests:** Deploy on an Arbitrum fork:
- Use real Chainlink ETH/USD feed — verify staleness checks work with actual feed behavior
- Use real wstETH contract — verify `stEthPerToken()` returns expected values and the dual oracle pipeline works with live data
- Use Chainlink's L2 Sequencer Uptime Feed — verify the operational state logic with real feed responses
- Measure gas for key operations. Rough ballpark targets for L2 (will vary with your implementation):

| Operation | Estimated Gas | Notes |
|---|---|---|
| Open position | 150-250K | Multiple SSTOREs (position, OI updates), oracle call |
| Close position | 120-200K | Similar to open, plus PnL settlement with pool |
| Add/remove margin | 50-80K | Single position update |
| Funding update | 30-60K | Accumulator SSTORE + timestamp |
| Liquidation check (view) | 20-40K | Read-only, no state changes |
| Liquidation execution | 200-350K | Close + margin distribution + insurance fund |
| LP deposit/withdraw | 80-120K | Share mint/burn + pool accounting |

Compare to GMX V2's gas profile on Arbitrum — your numbers should be in the same order of magnitude.

<a id="edge-cases"></a>
#### ⚠️ Edge Cases to Explore

**Cascading liquidation:** Set up 5 long positions at 50x leverage with tight margin. Drop the price 3%. The first liquidation closes a position and settles PnL against the pool. Does this affect the pool's ability to pay the other positions? (It shouldn't directly — oracle-based pricing means liquidation doesn't move the market price. But it does reduce pool assets.)

**Sequencer downtime + restart:** Sequencer goes down for 2 hours. Positions have been accruing funding during this time (or not, depending on your design choice). On restart, oracle prices jump 5%. During the grace period, traders add margin to protect their positions. After grace period, 3 positions are liquidatable. Test the full flow.

**wstETH de-peg event:** Simulate a 5% stETH de-peg (set mock stETH/ETH Chainlink to 0.95). Positions with wstETH collateral see their margin drop suddenly as the dual oracle switches from exchange-rate pricing to market pricing. Multiple positions become liquidatable simultaneously. Does your system handle a flood of liquidations?

**Same-block open and liquidation:** Trader opens a 100x position (if allowed). In the same block, price drops 1.5%. Is the position liquidatable? If so, the trader lost money in one block with no chance to react. Consider whether your system should enforce a minimum position age before liquidation.

**LP withdrawal during high utilization:** Pool has $1M assets, $800K in open interest. LP tries to withdraw $300K. This would leave $700K in assets backing $800K in OI — potentially insolvent. Your withdrawal constraint should block this. Test the boundary precisely.

**Insurance fund depletion:** Three positions go into bad debt simultaneously. The insurance fund covers the first two but is depleted on the third. The remaining bad debt hits the LP pool. LP share value drops. Test that the accounting remains consistent through the entire chain.

**Dust positions:** Open a position with 1 wei of collateral and minimum possible size. Does the margin calculation work? Does liquidation work? Can the position exist indefinitely because it's too small for keepers to profitably liquidate?

**Funding rate at extreme skew:** Set long OI to 100x short OI. The funding rate should be very high (longs paying a lot to shorts). Does the accumulator handle this without overflow? With 30-decimal precision and `int256`, the maximum value is ~5.7 × 10^76 — large, but do the math: at an extreme rate of 100% per day (1e30 per day in 30-decimal), the accumulator grows by ~3.65 × 10^32 per year. It would take ~10^44 years to overflow — safe in practice. The real risk is the intermediate multiplication: `(currentIndex - entryIndex) × positionSize` where both operands are 30-decimal. Use `mulDiv` or careful scaling to avoid overflow in the product.

#### 💼 Portfolio & Interview Positioning

<a id="portfolio"></a>

**What This Project Proves:**

- You can **design a multi-contract DeFi protocol** from scratch — 5 contracts with clear boundaries, not fill in TODOs
- You understand **perpetual exchange mechanics deeply** — funding rates, margin math, LP economics, liquidation design
- You can handle **multi-collateral pricing** with LST dual oracle integration (wstETH pricing pipeline)
- You designed **MEV-aware liquidation** and can articulate the keeper incentive trade-offs (Module 5 applied)
- You built **L2-native infrastructure** with sequencer uptime awareness (Module 7 applied)
- You can write **production-quality invariant tests** including the zero-sum funding balance property

**Interview Questions This Prepares For:**

**1. "Walk me through building a perpetual exchange from scratch."**
- Good: Describe the 5 contracts and their responsibilities.
- Great: Explain the design *decisions* — why oracle-based pool, why isolated markets, why partial liquidation. Show you understand the trade-off space, not just the implementation.

**2. "How would you handle wstETH as position collateral?"**
- Good: Use the exchange rate from the Lido contract.
- Great: Explain the dual oracle pattern — exchange rate vs market price, use the minimum. Identify de-peg risk (June 2022 stETH traded at 0.93 ETH). Explain why the exchange rate alone isn't enough (can't sell at exchange rate during de-peg).

**3. "How would you design liquidation to minimize cascading risk?"**
- Good: Use partial liquidation to preserve positions.
- Great: Explain the full cascade prevention stack: partial liquidation (reduce position size gradually), OI caps (limit total exposure), dynamic funding (rebalance skew), insurance fund (absorb bad debt before it hits LPs), and ADL as the last resort.

**4. "What happens when the L2 sequencer goes down and your exchange has open positions?"**
- Good: "We check the Chainlink sequencer uptime feed and pause operations."
- Great: Describe the three operational states, which operations are blocked in each, why the grace period matters more for perps than lending (leverage amplifies the damage), and how you handle funding rate accumulation during downtime.

**5. "How do you size a keeper incentive to attract liquidators without creating excessive MEV?"**
- Good: "Set a reasonable percentage fee."
- Great: Explain that the liquidation fee IS the MEV bounty (Module 5). Compare flat fee, percentage with cap, and decaying fee. Note that on L2 with cheap gas, a small flat fee is sufficient, and the MEV dynamics are different from L1 because the sequencer has ordering power.

**6. "What invariants would you test for a perpetual exchange?"**
- Good: "Total supply, solvency."
- Great: List all 6 invariants (solvency, conservation, funding balance, OI consistency, margin safety, position integrity), explain what failure of each would mean, and describe the handler with 12 bounded operations.

**7. "Compare your oracle-based pool model with an orderbook DEX. When would you choose each?"**
- Good: "Oracle pools are simpler, orderbooks are faster."
- Great: Oracle-based pools keep all logic on-chain (verifiable), use LP capital efficiently (no need for individual market makers), and are composable with other DeFi protocols. Orderbooks offer better price discovery, tighter spreads, and handle high-frequency trading — but the matching engine runs off-chain (Hyperliquid, dYdX). For an EVM Solidity system, oracle-based is the pragmatic choice; for maximum performance, you'd build an appchain with an off-chain engine.

**Interview Red Flags** — things that signal surface-level understanding in a perp interview:
- Not knowing the difference between isolated margin and cross margin
- Describing liquidation without mentioning partial liquidation or cascading risk
- Not considering sequencer downtime for L2-deployed perps
- Saying "just use Chainlink" without discussing staleness, heartbeat, or sequencer uptime checks
- Not being able to explain why funding rate is zero-sum

**Pro tip:** In interviews, lead with the system design, not the implementation details. "I chose oracle-based pool over orderbook because all the core logic stays on-chain and verifiable. I chose isolated markets because GMX V1's shared pool created contagion risk. I chose partial liquidation because full liquidation amplifies cascading risk." This signals protocol design thinking — teams want architects, not just coders.

**Pro tip:** Show your invariant test results. Most candidates can't name more than 1-2 invariants for a complex system. Listing 6 with handler designs signals a level of testing maturity that separates senior from mid-level.

**How to Present This:**

- Push to a public GitHub repo with a clear README
- Include the 5-contract architecture diagram (the ASCII diagram from this doc, or a nicer one)
- Include a comparison: your protocol vs GMX V2 (what's similar, what's different, why)
- Include gas benchmarks for core operations
- Show your invariant test results — this signals testing maturity
- Write a brief Architecture Decision Record: the 7 design decisions and your rationale
- If you built the P2 stablecoin capstone, show how the two systems connect (stablecoin as settlement asset)

## 📋 Key Takeaways: Testing & Hardening

After this section, you should be able to:

- List all 6 critical invariants (solvency, conservation, funding balance, OI consistency, margin safety, position integrity) and explain what failure of each would mean for the exchange
- Design an invariant test handler with 12 bounded operations that explores realistic action sequences across multiple traders, price movements, funding accrual, and sequencer state changes
- Write fork tests against real Chainlink feeds, real wstETH contracts, and real sequencer uptime feeds on Arbitrum to verify behavior under production conditions
- Test edge cases that break naive implementations: cascading liquidations, sequencer downtime, de-peg events, dust positions, insurance fund depletion

> **🧭 Checkpoint — Before Starting to Build:**
> Can you list all 6 invariants from memory and explain what failure of each one would mean for the exchange? Can you describe at least 6 handler operations and how they interact with the invariants? If yes, you understand the system well enough to build it. If not, re-read the invariants — they are the specification you're implementing against.

---

<a id="build-order"></a>
## 📖 Suggested Build Order

This is guidance, not prescription. Adapt to your working style — but if you're not sure where to start, this sequence builds from simple to complex with testable milestones at each phase.

**Phase 1: PriceFeed (~half day)**

Build `PriceFeed.sol` first. It has no dependencies on other protocol contracts. Two pricing paths: ETH via Chainlink, wstETH via dual oracle. Add the sequencer uptime check. Test with mock Chainlink feeds and a mock wstETH contract.

> **Checkpoint:** Mock Chainlink returns $3,000. Mock wstETH returns 1.15 rate. Verify both pricing paths return correct USD values. Simulate a stETH de-peg (mock stETH/ETH at 0.95) — verify the dual oracle switches to the lower price. Simulate sequencer downtime — verify revert.

**Phase 2: FundingRate (~half day)**

Build `FundingRate.sol` next. This is the accumulator from M2 Exercise 1 (lines 161-250) adapted to its own contract. Per-second continuous accrual, skew-based rate calculation. Test with time warps and varying OI skew.

> **Checkpoint:** Set up skewed OI (70% long, 30% short). Warp time 1 hour. Verify accumulator growth matches expected rate. Open a position, warp time, close position — verify funding settlement matches `(currentIndex - entryIndex) × positionSize`.

**Phase 3: LiquidityPool (~1 day)**

Build `LiquidityPool.sol`. LP deposits/withdrawals with share accounting. PnL settlement function (stub it to accept direct calls for now — PerpEngine isn't built yet). Utilization tracking and withdrawal constraints.

> **Checkpoint:** Deposit $100K, verify 100K shares minted. Simulate trader profit of $10K (direct call to settlement) — verify share value drops to $0.90. Attempt withdrawal that would violate reserve constraint — verify revert.

**Phase 4: PerpEngine (~2-3 days)**

Build `PerpEngine.sol` — the core. This is the bulk of the work. Start with the simplest flow (open ETH-collateral long position, close it) and build outward: add short positions, add wstETH collateral, add margin modifications, wire funding settlement. Leave `liquidatePosition()` as a stub initially.

> **Checkpoint:** Full position lifecycle with ETH collateral: open 10x long → warp time → close at profit → verify trader received correct payout and pool paid correctly. Then repeat with wstETH collateral. Then test margin additions and removals. Verify funding is settled correctly on every position change.

**Phase 5: Liquidator + Integration (~1-2 days)**

Build `Liquidator.sol`. Wire it to PerpEngine's `liquidatePosition()`. Implement partial liquidation logic, keeper fee distribution, insurance fund management. Wire everything together and write invariant tests.

> **Checkpoint:** Create a position, drop the oracle price, verify liquidation triggers. Verify partial liquidation restores margin ratio. Test bad debt path — verify insurance fund absorbs it. All 6 invariants pass with depth ≥ 50, runs ≥ 256. Fork test works on Arbitrum. Gas benchmarks logged.

---

<a id="common-mistakes"></a>
#### ⚠️ Common Mistakes

These are production-level pitfalls beyond the per-function mistakes listed in Section 4:

1. **Not updating funding before EVERY position change.** This is the single most common bug. The `_beforePositionChange()` pattern must be called at the start of every function that reads or modifies position state. If you forget it in one function (e.g., `removeMargin`), the margin calculation will be wrong for positions with pending funding.

2. **Integer overflow in PnL calculation at high leverage.** At 100x leverage, `sizeInUsd` is 100× the collateral. With 30-decimal precision, a $1M position at 100x is `100_000_000e30` — that's 10^38. Multiplying by a price ratio can overflow `uint256` (max ~1.15 × 10^77). Use `mulDiv` or intermediate scaling.

3. **Allowing LP withdrawal below reserve threshold.** If the pool has $1M in assets and $900K in open interest, a $200K withdrawal would leave $800K backing $900K — potentially insolvent. The withdrawal must check `poolAssetsAfterWithdrawal ≥ totalOI × reserveFactor`.

4. **Not tracking realized vs unrealized PnL separately in the pool.** The pool needs to distinguish between PnL that has been settled (tokens actually moved) and PnL that is unrealized (open positions that haven't closed yet). LP share value depends on both, but only realized PnL involves token transfers.

5. **Forgetting to settle funding on liquidation.** When the Liquidator closes a position, it MUST settle pending funding first — just like a normal close. Otherwise, the funding balance invariant breaks (funding was owed but never paid).

6. **Using `block.number` instead of `block.timestamp` for funding accrual.** On L2, block times are variable (Arbitrum: ~250ms, Optimism: 2s). Use `block.timestamp` for time-based calculations — it's consistent regardless of block time.

---

<a id="study-gmx"></a>
#### 📖 How to Study GMX V2

GMX V2's codebase (`gmx-io/gmx-synthetics`) is large (~50+ contracts), but it follows clear patterns. This decoder table maps their names to your protocol's equivalents:

| GMX V2 | Your Protocol | What It Is |
|---|---|---|
| `Position.Props` | Position struct | Per-position state (size, collateral, entry price) |
| `Market.Props` | Market struct | Per-market configuration and OI tracking |
| `ExchangeRouter` | (external entry point) | User-facing transaction routing |
| `OrderHandler` | PerpEngine (if two-step) | Keeper-executed order processing |
| `IncreasePositionUtils` | PerpEngine.openPosition | Open/increase position logic |
| `DecreasePositionUtils` | PerpEngine.closePosition | Close/decrease position logic |
| `PositionPricingUtils` | PerpEngine._calculateFees | Fee calculations |
| `MarketUtils` | LiquidityPool | Pool accounting, deposit/withdrawal |
| `FundingFeeUtils` | FundingRate | Funding accumulator logic |
| `LiquidationUtils` | Liquidator | Margin check + liquidation execution |
| `AdlUtils` | (stretch goal) | Auto-deleveraging emergency logic |
| `GasUtils` | (not needed) | GMX-specific gas refund logic |
| `DataStore` | (you use struct storage) | GMX's key-value store pattern |

**Reading order for GMX V2:**

1. **Start with `Position.Props`** — understand the data model. Map each field to your Position struct.
2. **Read `Market.Props`** — understand how per-market state is organized.
3. **Trace `createOrder`** in `ExchangeRouter` — follow a market order from user submission to storage.
4. **Trace `executeOrder`** in `OrderHandler` — follow keeper execution. This is the two-step pattern.
5. **Read `IncreasePositionUtils.increasePosition()`** — the core open/increase logic. Note how it calls pricing utils, market utils, and stores the position.
6. **Read `DecreasePositionUtils.decreasePosition()`** — the close logic. Note PnL calculation and pool settlement.
7. **Read `FundingFeeUtils`** — the accumulator pattern. Compare to your FundingRate contract.
8. **Read `LiquidationUtils`** — margin check and liquidation flow.
9. **Read the tests** — `test/position/` directory shows full lifecycle tests.

**Don't get stuck on:** GMX's `DataStore` pattern (they use a key-value store instead of structs — an unusual design choice for flexibility), the `RoleStore`/`RoleModule` authorization system (their access control — your protocol uses simpler patterns), the `GasUtils` gas refund logic (GMX-specific), or the `Callback` contracts (GMX-specific hooks for composability). These are important for understanding GMX, but not for building your protocol.

> **🔗 Connection:** Module 2 (lines 726-758) already provided a GMX V2 code reading strategy. This expands it with the name decoder table for mapping GMX concepts to your protocol.

---

<a id="self-assessment"></a>
## ✅ Self-Assessment Checklist

### Architecture
- [ ] 5-contract structure designed and implemented (PerpEngine, LiquidityPool, FundingRate, Liquidator, PriceFeed)
- [ ] Clear separation of concerns — PerpEngine doesn't know about keeper incentives, Liquidator doesn't know about funding math
- [ ] Design decisions documented with rationale (your Architecture Decision Record)

### PerpEngine
- [ ] Position lifecycle works end-to-end: open → modify → close
- [ ] Margin math correct for ETH collateral (single Chainlink lookup)
- [ ] Margin math correct for wstETH collateral (dual oracle pricing pipeline)
- [ ] Funding settled before every position state change
- [ ] PnL calculation correct for both longs and shorts
- [ ] OI totals updated on every position change (open, close, increase, decrease, liquidation)
- [ ] `acceptablePrice` slippage protection on open and close

### LiquidityPool
- [ ] LP share pricing correct: `poolValue = deposits + fees - netTraderPnL`
- [ ] LP deposit mints correct share amount based on current pool value
- [ ] LP withdrawal burns shares and returns proportional assets
- [ ] Withdrawal constraint enforced (reserve for max trader payout)
- [ ] PnL settlement from PerpEngine works for both profit and loss scenarios

### PriceFeed
- [ ] ETH pricing via Chainlink with staleness check
- [ ] wstETH dual oracle pricing (exchange rate + market price, use minimum)
- [ ] Sequencer uptime check with grace period
- [ ] All three operational states enforced (down, grace, normal)

### Liquidation
- [ ] Partial liquidation calculates correct close amount to restore margin ratio
- [ ] Full liquidation triggers when position is deeply underwater
- [ ] Keeper fee distributed correctly from remaining margin
- [ ] Insurance fund receives its share of fees and absorbs bad debt
- [ ] Liquidation blocked during sequencer downtime and grace period

### FundingRate
- [ ] Per-second continuous accumulator updates correctly with time warps
- [ ] Skew-based rate calculation responds to OI imbalance
- [ ] Zero-sum property holds: total funding paid by longs == total received by shorts (within rounding)

### Governance
- [ ] Bounded parameter setters with hardcoded min/max ranges
- [ ] Timelock on parameter changes
- [ ] Core math remains immutable (PnL formulas, funding accumulator, liquidation formula)

### Testing
- [ ] Unit tests for every function and error path
- [ ] Fuzz tests with random amounts, prices, and operation sequences
- [ ] All 6 critical invariants implemented and passing (depth ≥ 50, runs ≥ 256)
- [ ] Fork test with real Chainlink ETH/USD, real wstETH contract, and real sequencer uptime feed
- [ ] Gas benchmarks for core operations logged

### Stretch Goals
- [ ] Two-step keeper execution for position orders (GMX V2 model)
- [ ] Borrow fee with utilization-based rate and accumulator
- [ ] Auto-deleveraging (ADL) implementation
- [ ] Price impact fees based on position size relative to OI
- [ ] Dynamic keeper fee that decays over blocks (Dutch auction on the fee)
- [ ] Foundry deployment script showing correct 5-contract wiring order

---

## 📚 Resources

**Reference Implementations:**
- [GMX V2 Synthetics](https://github.com/gmx-io/gmx-synthetics) — Oracle-based perp exchange, primary reference architecture
- [Synthetix Perps V2](https://github.com/Synthetixio/synthetix-v2/tree/develop/contracts/PerpsV2) — Debt pool alternative model
- [Gains Network (gTrade)](https://github.com/GainsNetwork/gTrade-v6.1) — Oracle-based perp with synthetic architecture

**Oracle & L2 Infrastructure:**
- [Chainlink L2 Sequencer Uptime Feeds](https://docs.chain.link/data-feeds/l2-sequencer-feeds) — Official docs for sequencer uptime integration
- [Chainlink Data Feeds](https://docs.chain.link/data-feeds) — ETH/USD, stETH/ETH feed addresses and heartbeats

**Research & Analysis:**
- [GMX V2 Technical Overview](https://gmx-io.notion.site/gmx-io/GMX-Technical-Overview-47fc5ed832e243afb9e97e8a4a036353) — Official technical docs
- [KiloEx Post-Mortem (April 2025)](https://rekt.news/) — Oracle manipulation exploit, relevant to PriceFeed design
- [Ethena Labs USDe](https://ethena.fi/) — Delta-neutral yield on perp funding rates (funding rate economics in practice)

**Testing & Security:**
- [Foundry Invariant Testing](https://book.getfoundry.sh/forge/invariant-testing) — Handler pattern, target configuration, failure shrinking
- [Trail of Bits — Properties for DeFi](https://blog.trailofbits.com/2023/02/27/using-echidna-to-test-a-bridge/) — Invariant property design patterns

---

*This completes Part 3: Modern DeFi Stack. You've gone from individual DeFi verticals (liquid staking, perpetuals, yield tokenization, aggregation, MEV, cross-chain, L2, governance) to designing and building a complete perpetual exchange. The exchange you built integrates the most critical concepts from Modules 1-8 into a cohesive, production-style system — with oracle-based pricing, multi-collateral margin, MEV-aware liquidation, sequencer uptime awareness, and bounded governance. Together with the Part 2 stablecoin capstone, you now have two portfolio projects that demonstrate full-stack DeFi protocol engineering.*

---

**Navigation:** [← Module 8: Governance & DAOs](8-governance.md) | [Part 4: EVM Deep Dive →](../part4/1-evm-fundamentals.md)

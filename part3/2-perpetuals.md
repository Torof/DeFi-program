# Part 3 — Module 2: Perpetuals & Derivatives (~5 days)

**Prerequisites:** Part 2 — Modules 2 (AMMs), 3 (Oracles), 4 (Lending & Borrowing)
**Pattern:** Fundamentals → Protocol architecture → Alternative models → Liquidation → Hands-on
**Builds on:** Chainlink oracle integration (P2M3), liquidation mechanics (P2M4), funding/stability pools (P2M6), keeper patterns (P2M4/M5)
**Used by:** Module 5 (MEV — perp frontrunning and liquidation MEV), Module 9 (Capstone — perpetual exchange)

---

## 📚 Table of Contents

**Perpetual Futures Fundamentals**
- [What is a Perpetual?](#what-is-a-perpetual)
- [Mark Price vs Index Price](#mark-vs-index)
- [Deep Dive: Funding Rate Mechanics](#funding-rate-mechanics)
- [Deep Dive: Funding Rate Accumulator Pattern](#funding-accumulator)
- [Margin and Leverage](#margin-and-leverage)
- [Deep Dive: PnL Calculation with Worked Examples](#pnl-calculation)
- [Deep Dive: Liquidation Price Derivation](#liquidation-price)

**GMX Architecture**
- [The GMX Model: Liquidity Pool as Counterparty](#gmx-model)
- [GMX V2: GM Pools and Position Tracking](#gmx-v2)
- [Deep Dive: Two-Step Keeper Execution](#keeper-execution)
- [Deep Dive: Fee Structure and Price Impact](#fee-structure)
- [Code Reading Strategy: GMX V2](#gmx-code-reading)

**Synthetix & Alternative Models**
- [Synthetix: The Debt Pool Model](#synthetix-debt-pool)
- [Deep Dive: Debt Pool Math with Worked Example](#debt-pool-math)
- [Synthetix Perps V2: Skew-Based Funding](#synthetix-perps-v2)
- [dYdX: Order Book Model](#dydx)
- [Hyperliquid](#hyperliquid)
- [Architecture Comparison](#architecture-comparison)

**Liquidation in Perpetuals**
- [Why Perp Liquidation Differs from Lending](#perp-vs-lending-liquidation)
- [Deep Dive: Liquidation Engine Flow](#liquidation-engine)
- [Insurance Fund](#insurance-fund)
- [Auto-Deleveraging (ADL)](#adl)
- [Cascading Liquidation](#cascading-liquidation)

**Wrap Up**
- [DeFi Pattern Connections](#pattern-connections)
- [Job Market Context](#job-market)
- [Module Exercises](#exercises)
- [Resources](#resources)

---

## Perpetual Futures Fundamentals

<a id="what-is-a-perpetual"></a>
### 💡 What is a Perpetual?

**Why this matters:** Perpetual futures are the highest-volume DeFi instrument. On many days, perp volume exceeds spot DEX volume across all chains. If you're building DeFi infrastructure, you will encounter perp protocols — either directly (GMX, Synthetix, dYdX) or through their downstream effects on oracle prices, liquidation cascading, and MEV.

**Traditional futures vs perpetuals:**

Traditional futures contracts have an expiry date. You agree to buy 1 ETH at $3,000 on March 31st. When expiry arrives, the contract settles at the spot price, and the difference from your entry price is your profit or loss. The problem: expiry creates fragmented liquidity across contract months, and traders must "roll" positions (close the expiring contract, open a new one) — paying fees and crossing spreads each time.

Perpetual futures (invented by BitMEX in 2016) solve this by removing the expiry entirely. Your position stays open indefinitely. But without expiry, there's no natural mechanism forcing the contract price to converge to the underlying spot price. That's where the funding rate comes in.

```
Traditional Future:                    Perpetual Future:

  Entry ──────── Expiry                  Entry ──────────────────────── ∞
  $3,000         Settles at spot         $3,000   Funding rate keeps
                                                   price tracking spot
  │               │
  │  Fixed term   │                      No expiry. No rolling.
  │  Must roll    │                      Funding rate = the "glue"
  │               │                      that binds mark to index.
  ▼               ▼
```

**Key terminology:**
- **Index price** — the spot price of the underlying asset, sourced from oracles (Chainlink, Pyth, or aggregated from multiple exchanges)
- **Mark price** — the current trading price of the perpetual contract itself
- **Funding rate** — periodic payment between longs and shorts that keeps mark price tracking the index price
- **Open interest** — total value of all open positions (a measure of how much leverage is in the system)

<a id="mark-vs-index"></a>
### 💡 Mark Price vs Index Price

Understanding the relationship between mark and index price is fundamental to how perpetuals work.

**Index price** is the "truth" — the actual spot price, typically an oracle-derived aggregate of exchange prices. This is what the perpetual is trying to track.

**Mark price** is the perpetual's own trading price, determined by supply and demand on the perp venue itself. When more traders want to go long than short, the mark price gets pushed above the index. When more want to short, mark drops below index.

```
                    Mark Price (what the perp trades at)
                    ┌─────────────────────────────────────┐
 Price ($)          │     ╱╲                              │
   ▲                │    ╱  ╲    ╱╲                       │
   │                │   ╱    ╲  ╱  ╲         ╱╲          │
   │                │──╱──────╲╱────╲───────╱──╲──────── │ ← Index Price (oracle)
   │                │ ╱                ╲   ╱    ╲  ╱     │
   │                │╱                  ╲ ╱      ╲╱      │
   │                └─────────────────────────────────────┘
   └──────────────────────────────────────────────► Time
                    │← Longs   │← Shorts  │← Longs
                    │  pay      │  pay      │  pay
                    │  shorts   │  longs    │  shorts
```

**Why mark, not index, is used for liquidation:** Mark price reflects the price at which positions would actually close. If you're liquidated, the protocol must close your position at the prevailing market price (mark), not the theoretical oracle price (index). Using mark for liquidation ensures the protocol can actually execute the close at a price close to what it used for the margin check.

> In GMX's oracle-based model, mark price effectively equals index price (because trades execute at oracle price). The distinction matters more for order-book perps (dYdX, Hyperliquid) where mark can diverge significantly from index during volatile periods.

<a id="funding-rate-mechanics"></a>
### 🔍 Deep Dive: Funding Rate Mechanics

**The problem it solves:** Without expiry, nothing forces the perpetual's price to match spot. Traders could bid the perp to 10% above spot and leave it there. The funding rate creates an economic incentive that continuously pulls the mark price toward the index price.

**The mechanism:**
- When mark > index (too many longs), longs pay shorts
- When mark < index (too many shorts), shorts pay longs
- Payments are proportional to your position size

**Basic formula:**

```
Funding Rate = (Mark Price - Index Price) / Index Price

Funding Payment = Position Size × Funding Rate
```

**Worked example — 8-hour periodic funding:**

```
Scenario: ETH spot (index) = $3,000, ETH perp (mark) = $3,060

Funding Rate = ($3,060 - $3,000) / $3,000 = 0.02 = 2%

Alice has a $30,000 long position (10 ETH at 1x):
  Funding Payment = $30,000 × 2% = $600 paid TO shorts

Bob has a $15,000 short position (5 ETH at 1x):
  Funding Payment = $15,000 × 2% = $300 received FROM longs

Effect: Holding a long is expensive (paying 2% every 8h).
        Traders close longs or open shorts → mark falls toward index.
```

**Why this is self-correcting:**

```
  High Funding Rate (mark >> index)
         │
         ▼
  Expensive to hold longs
         │
         ▼
  Longs close / new shorts enter
         │
         ▼
  Selling pressure → mark falls
         │
         ▼
  Mark approaches index
         │
         ▼
  Funding rate approaches 0
```

**Annualized funding rates:** In volatile bull markets, annualized funding rates can reach 50-100%+. This creates the basis for **delta-neutral yield strategies**: open a spot long + perp short, collect funding with no directional exposure. This is the core mechanism behind Ethena's USDe — a delta-neutral yield product built on perp funding rates.

**Funding rate as a market signal:**
- Persistently positive funding → market is bullish (lots of longs), but crowded trades are expensive to hold
- Persistently negative funding → market is bearish or hedgers dominate
- Funding rate spikes often precede liquidation cascades — watch for this pattern

<a id="funding-accumulator"></a>
### 🔍 Deep Dive: Funding Rate Accumulator Pattern

**The problem:** If funding is paid every 8 hours, a protocol must iterate over every open position to calculate and deduct payments. With thousands of positions, this is O(n) per funding period — too expensive on-chain.

**The solution: Global accumulator (O(1) updates).** This is the same pattern you saw in Aave's interest rate accumulator (P2M4) and Lido's shares accounting. The protocol maintains a single global counter that grows over time. Each position records the counter value at open. When the position is settled, the difference between the current counter and the stored value tells you how much funding that position owes or is owed.

```
Global Accumulator (grows over time):
─────────────────────────────────────────────────────────
t=0: accumulator = 0
t=1: rate = +0.001, accumulator = 0.001
t=2: rate = +0.002, accumulator = 0.003
t=3: rate = -0.001, accumulator = 0.002
t=4: rate = +0.001, accumulator = 0.003
─────────────────────────────────────────────────────────

Position A opens at t=1 (stores accumulator = 0.001)
Position B opens at t=3 (stores accumulator = 0.002)

At t=4, settle both positions:
  A's funding = (0.003 - 0.001) × positionSize = 0.002 × size
  B's funding = (0.003 - 0.002) × positionSize = 0.001 × size

No iteration needed. O(1) per settlement.
```

**In Solidity, the pattern looks like this:**

```solidity
// Global state — updated whenever funding is applied
int256 public cumulativeFundingPerUnit;  // grows over time
uint256 public lastFundingTimestamp;

// Per-position state — recorded at open
struct Position {
    uint256 size;
    uint256 collateral;
    uint256 entryPrice;
    bool    isLong;
    int256  entryFundingIndex;  // ← snapshot of cumulative at open
}

// Update global accumulator (called before any position change)
function _updateFunding(int256 currentFundingRate) internal {
    uint256 elapsed = block.timestamp - lastFundingTimestamp;
    // Accumulate: rate per second × elapsed seconds
    cumulativeFundingPerUnit += currentFundingRate * int256(elapsed);
    lastFundingTimestamp = block.timestamp;
}

// Calculate funding owed by a specific position
function _pendingFunding(Position memory pos) internal view returns (int256) {
    int256 delta = cumulativeFundingPerUnit - pos.entryFundingIndex;
    // Longs pay positive funding, shorts receive it (sign convention)
    return pos.isLong
        ? int256(pos.size) * delta / 1e18
        : -int256(pos.size) * delta / 1e18;
}
```

**Key insight:** This is the exact same mathematical technique as Compound's `borrowIndex`, Aave's `liquidityIndex`, and ERC-4626 share pricing — a global accumulator that grows over time, with per-user snapshots. Once you internalize this pattern, you'll see it everywhere in DeFi.

#### 🔗 DeFi Pattern Connection

| Protocol | Accumulator | Per-user snapshot | What it tracks |
|----------|-------------|-------------------|----------------|
| Compound | `borrowIndex` | `borrowIndex` at borrow time | Interest owed |
| Aave V3 | `liquidityIndex` / `variableBorrowIndex` | Scaled balance | Interest earned/owed |
| ERC-4626 | `totalAssets / totalSupply` | Share balance | Yield earned |
| Perps | `cumulativeFundingPerUnit` | `entryFundingIndex` | Funding owed/earned |
| Synthetix | `debtRatio` | `debtEntryIndex` | Share of debt pool |

💻 **Quick Try:**

Deploy this minimal funding accumulator in [Remix](https://remix.ethereum.org/) to feel the pattern:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MiniFunding {
    int256 public cumulative;      // global accumulator
    uint256 public lastUpdate;
    int256 public rate = 1e16;     // 1% per day (simplified)

    constructor() { lastUpdate = block.timestamp; }

    function update() public {
        uint256 elapsed = block.timestamp - lastUpdate;
        cumulative += rate * int256(elapsed) / 86400;
        lastUpdate = block.timestamp;
    }

    // Snapshot at "open", then call pending() later to see the diff
    function snapshot() external view returns (int256) { return cumulative; }

    function pending(int256 entryIndex, uint256 size) external view returns (int256) {
        return int256(size) * (cumulative - entryIndex) / 1e18;
    }
}
```

Deploy, call `update()` a few times (wait a few seconds between calls), and watch `cumulative` grow. Then note a `snapshot()` value, wait, call `update()` again, and compute `pending()` — you'll see how the delta captures exactly the funding accrued since your snapshot. This is the pattern that makes O(1) settlement possible.

<a id="margin-and-leverage"></a>
### 💡 Margin and Leverage

**Margin** is the collateral you deposit to back a leveraged position. **Leverage** amplifies your exposure: with 10x leverage, a $100 deposit controls a $1,000 position.

**Key margin concepts:**

- **Initial margin** — collateral required to open a position. At 10x max leverage: initial margin = 10% of position size.
- **Maintenance margin** — minimum collateral to keep a position open. Typically lower than initial margin (e.g., 1% for 100x max leverage, 5% for 20x). If remaining margin falls below this, the position is liquidatable.
- **Remaining margin** — initial margin + unrealized PnL + accumulated funding. This changes every second.

```
Example: Opening a 10x Long on ETH at $3,000

Position size: $30,000 (10 ETH)
Collateral:    $3,000  (initial margin = 10%)
Leverage:      10x

Maintenance margin: 1% = $300

If ETH drops to $2,700 (−10%):
  Unrealized PnL = 10 × ($2,700 − $3,000) = −$3,000
  Remaining margin = $3,000 − $3,000 = $0 ← liquidatable

If ETH drops to $2,730 (−9%):
  Unrealized PnL = 10 × ($2,730 − $3,000) = −$2,700
  Remaining margin = $3,000 − $2,700 = $300 = maintenance margin ← liquidation threshold
```

**Isolated vs cross margin:**

| Mode | How it works | Risk | Used when |
|------|-------------|------|-----------|
| **Isolated** | Each position has its own collateral pool | Loss limited to that position's margin | Speculative trades, higher-risk bets |
| **Cross** | All positions share a single collateral pool | One losing position can eat into another's margin | Professional trading, hedged portfolios |

Most DeFi perpetual protocols (GMX, Synthetix Perps) use isolated margin. Cross margin is more common in CeFi and dYdX V4.

<a id="pnl-calculation"></a>
### 🔍 Deep Dive: PnL Calculation with Worked Examples

**Core PnL formulas:**

For longs (profit when price goes up):
```
PnL = Position Size × (Exit Price - Entry Price) / Entry Price
```

For shorts (profit when price goes down):
```
PnL = Position Size × (Entry Price - Exit Price) / Entry Price
```

**Complete PnL including fees and funding:**
```
Realized PnL = Trading PnL + Funding Received - Funding Paid - Open Fee - Close Fee - Borrow Fee
```

**Worked example — Long position lifecycle:**

```
1. Open long: 5 ETH at $3,000 with 5x leverage
   Position size:   $15,000 (5 ETH × $3,000)
   Collateral:      $3,000  (initial margin = 20%)
   Open fee (0.1%): $15     (0.001 × $15,000)

2. Time passes: 24 hours, funding rate = +0.01% per 8h (longs pay shorts)
   Funding paid:    $15,000 × 0.01% × 3 periods = $4.50

3. Close at $3,300 (+10%)
   Trading PnL:     $15,000 × ($3,300 - $3,000) / $3,000 = $1,500
   Close fee:       $15 (0.1% × $15,000)

4. Net PnL:
   +$1,500.00  trading PnL
   -$4.50      funding paid
   -$15.00     open fee
   -$15.00     close fee
   ─────────
   +$1,465.50  net profit

   Return on collateral: $1,465.50 / $3,000 = 48.85%
   (vs 10% if unleveraged → 5x leverage amplified the return ~5x)
```

**Worked example — Short position that gets liquidated:**

```
1. Open short: 10 ETH at $3,000 with 20x leverage
   Position size:    $30,000 (10 ETH × $3,000)
   Collateral:       $1,500  (initial margin = 5%)
   Maintenance margin: $300  (1% of $30,000)

2. ETH pumps to $3,120 (+4%)
   Unrealized PnL:   $30,000 × ($3,000 - $3,120) / $3,000 = -$1,200
   Remaining margin:  $1,500 - $1,200 = $300 = maintenance margin
   → LIQUIDATION TRIGGERED

3. After liquidation:
   Liquidation penalty (e.g., 0.5%): $150
   Remaining to trader: $300 - $150 = $150 returned (or $0 if underwater)
   $150 penalty → insurance fund
```

**Why PnL is divided by entry price:** The formula `size × (exit - entry) / entry` gives the return in the **denomination currency** (USD). This is a percentage return scaled by position size. Some protocols instead track position size in the base asset (ETH) and compute PnL differently — be aware of which convention a protocol uses when reading their code.

<a id="liquidation-price"></a>
### 🔍 Deep Dive: Liquidation Price Derivation

**The question:** At what price will my position be liquidated?

Liquidation occurs when remaining margin equals maintenance margin:

```
Remaining Margin = Initial Margin + Unrealized PnL = Maintenance Margin
```

**For a long position:**

```
Let:
  E = Entry Price
  C = Collateral (Initial Margin)
  S = Position Size (in base asset, e.g., 10 ETH)
  M = Maintenance Margin (in USD)
  L = Liquidation Price

Unrealized PnL (long) = S × (L - E)

At liquidation:
  C + S × (L - E) = M

Solve for L:
  S × (L - E) = M - C
  L - E = (M - C) / S
  L = E + (M - C) / S
  L = E - (C - M) / S        ← rearranged: entry price MINUS a buffer
```

**Step-by-step with numbers:**

```
Entry Price (E):     $3,000
Position Size:       10 ETH ($30,000 at 10x leverage)
Collateral (C):      $3,000
Maintenance Margin:  1% of $30,000 = $300

L = $3,000 - ($3,000 - $300) / 10
L = $3,000 - $270
L = $2,730

Verify: at $2,730, PnL = 10 × ($2,730 - $3,000) = -$2,700
Remaining margin = $3,000 - $2,700 = $300 = maintenance margin ✓
```

**For a short position (mirror formula):**

```
At liquidation:
  C + S × (E - L) = M        ← PnL sign is reversed for shorts
  L = E + (C - M) / S

Short example at 10x leverage:
  L = $3,000 + ($3,000 - $300) / 10
  L = $3,000 + $270
  L = $3,270
```

**Why higher leverage = tighter liquidation price:**

```
Leverage   Collateral   Liq Price (Long)   Distance from Entry
──────────────────────────────────────────────────────────────
  2x       $15,000      $1,530             -49%
  5x       $6,000       $2,430             -19%
 10x       $3,000       $2,730              -9%
 20x       $1,500       $2,880              -4%
 50x       $600         $2,970              -1%
100x       $300         $3,000               0%  ← collateral = maintenance margin

(Assuming 1% maintenance margin, $30,000 position, $3,000 entry)

Note: At 100x, collateral equals the maintenance margin — the position
is immediately liquidatable at the entry price. Any fee, spread, or
single-tick move triggers liquidation.
```

The table makes it visceral: at 50x, a 1% move liquidates you; at 100x, the position is liquidatable the instant it opens. On a volatile asset like ETH, a 1% move can happen between two blocks.

**Funding payments shift liquidation price:** The formulas above assume no funding. In practice, accumulated funding payments reduce (or increase) remaining margin, which shifts the effective liquidation price over time. This is why long-duration highly-leveraged positions are particularly dangerous — even if price stays flat, funding can slowly drain your margin.

---

## GMX Architecture

<a id="gmx-model"></a>
### 💡 The GMX Model: Liquidity Pool as Counterparty

**Why this matters:** GMX pioneered a radically different perpetual architecture. Instead of matching buyers and sellers (order book) or using a virtual AMM curve, GMX has traders trade directly against a liquidity pool. The pool is the counterparty to every trade. This model has been forked dozens of times and is the basis for many L2 perp protocols.

**How it works:**

```
Traditional Order Book:              GMX Pool Model:

  Buyer ←──match──→ Seller            Trader ←──trade──→ LP Pool
                                                          │
  Price: set by order book            Price: set by oracle│
  Slippage: depends on depth          Slippage: zero     │
  Counterparty: another trader        Counterparty: pool  │
                                                          │
                                      LPs deposit ETH + USDC
                                      Earn: fees, funding
                                      Risk: trader PnL
```

**Key properties:**
1. **Oracle-based execution** — trades execute at the Chainlink/oracle price, not at a market-clearing price. This means zero price impact for small trades (huge advantage for retail traders).
2. **LPs take the other side** — when a trader opens a long, the pool is effectively short. If traders profit, LPs lose. If traders lose, LPs profit.
3. **LPs earn fees** — in exchange for this risk, LPs earn all trading fees, borrow fees, and liquidation penalties. Historically, LP returns have been positive because most traders lose money over time.
4. **No counterparty needed** — a trader can open a $10M long even if no one wants to short. The pool absorbs the other side. This is a massive liquidity advantage.

**The LP's risk profile:**

```
Scenario 1: Traders lose (most common historically)
  Trader deposits $1,000 margin, opens 10x long → loses $1,000
  LP Pool receives: $1,000 (margin) + fees
  LP P&L: positive ✓

Scenario 2: Traders win (LP's nightmare)
  Trader deposits $1,000 margin, opens 10x long → profits $5,000
  LP Pool pays out: $5,000
  LP Pool received: $1,000 (margin) + fees
  LP P&L: −$4,000 + fees ✗

Key insight: LPs are essentially selling options to traders.
In favorable conditions: steady income from premiums (fees).
In adverse conditions: large losses when directional moves hit.
```

> **Connection to Module 1 (LSTs):** GMX V2 accepts wstETH and other LSTs as LP collateral and position collateral. The oracle pricing pipeline from P3M1 Exercise 1 is exactly what GMX uses to value LST collateral. As a GMX LP, you earn both trading fees AND staking yield on your LST collateral.

<a id="gmx-v2"></a>
### 💡 GMX V2: GM Pools and Position Tracking

GMX V2 (launched 2023) restructured liquidity into **isolated per-market pools** called GM pools. Each market (ETH/USD, BTC/USD, ARB/USD, etc.) has its own separate pool with its own LP tokens.

**GM Pool structure:**

```
ETH/USD GM Pool
┌────────────────────────────────────────────────┐
│                                                │
│  Long Collateral: ETH (or wstETH, wETH)       │
│  Short Collateral: USDC                        │
│                                                │
│  ┌──────────────────┐  ┌───────────────────┐   │
│  │   Long Side      │  │   Short Side      │   │
│  │                  │  │                   │   │
│  │  Backed by ETH   │  │  Backed by USDC   │   │
│  │  Used for long   │  │  Used for short   │   │
│  │  positions       │  │  positions        │   │
│  └──────────────────┘  └───────────────────┘   │
│                                                │
│  Open Interest Caps:                           │
│    Max long OI:  constrained by ETH in pool    │
│    Max short OI: constrained by USDC in pool   │
│                                                │
└────────────────────────────────────────────────┘
```

**Position data structure (simplified from GMX V2):**

```solidity
// What GMX stores for each position
struct Position {
    // Identification
    bytes32 key;           // hash(account, market, collateralToken, isLong)
    address account;       // the trader

    // Core fields
    uint256 sizeInUsd;     // position size in USD (30 decimals in GMX)
    uint256 sizeInTokens;  // position size in the index token (e.g., ETH)
    uint256 collateralAmount; // collateral deposited

    // Tracking
    uint256 borrowingFactor;    // snapshot of cumulative borrow rate at open
    uint256 fundingFeeAmountPerSize;  // snapshot of funding accumulator
    uint256 longTokenClaimableFundingAmountPerSize;
    uint256 shortTokenClaimableFundingAmountPerSize;

    // State
    bool isLong;
    uint256 increasedAtBlock;  // block when last increased (for min hold time)
    uint256 decreasedAtBlock;
}
```

**Why so many fields?** Each "snapshot" field stores the value of a global accumulator at the time the position was opened or last modified. When the position is closed, the protocol computes the difference between the current accumulator and the stored snapshot to determine how much borrow fee, funding, etc., the position owes. This is the Funding Rate Accumulator pattern from above applied multiple times.

<a id="keeper-execution"></a>
### 🔍 Deep Dive: Two-Step Keeper Execution

**The problem:** If a trader submits a market order with a price visible on-chain before execution, validators (or MEV bots) can frontrun it — they see the order, check the oracle price, and trade ahead if profitable. This is a critical problem for oracle-based perps.

**GMX's solution: Two-step execution.**

```
Step 1: User creates order (on-chain)
  ┌─────────────────────────────────────┐
  │ CreateOrder tx:                     │
  │   market: ETH/USD                   │
  │   isLong: true                      │
  │   sizeDelta: +$10,000               │
  │   collateral: 1 ETH                 │
  │   acceptablePrice: $3,050           │
  │   executionFee: 0.001 ETH           │
  │                                     │
  │ NOTE: No price at this point.       │
  │ Order just says "I want to open     │
  │ a long, up to price X"             │
  └───────────────┬─────────────────────┘
                  │
                  ▼ (1-2 blocks later)

Step 2: Keeper executes with signed oracle price
  ┌─────────────────────────────────────┐
  │ ExecuteOrder tx (from keeper):      │
  │   orderId: 0xabc...                 │
  │   oraclePrices: [signed Chainlink   │
  │                   price report]     │
  │                                     │
  │ The price is from AFTER the order   │
  │ was created. Frontrunners can't     │
  │ know it at order creation time.     │
  │                                     │
  │ If price > acceptablePrice → revert │
  │ Otherwise → execute at oracle price │
  └─────────────────────────────────────┘
```

**Why this prevents frontrunning:**
1. At order creation time, the execution price is unknown (it's the oracle price at execution time, 1-2 blocks later)
2. Frontrunners can't profit because they can't predict the future oracle price
3. The `acceptablePrice` protects the trader from executing at a price they wouldn't accept

**Keeper incentives:** Keepers earn a gas fee (paid by the trader at order creation via `executionFee`). Anyone can run a keeper — it's permissionless. Keepers monitor the order book, wait for fresh oracle prices, and execute orders.

> **Connection to P2M3 (Oracles):** GMX V2 uses a combination of Chainlink and custom off-chain signing for oracle prices. The signed price reports are submitted by keepers alongside the execution transaction. This is similar to Pyth's pull-based model — prices are fetched off-chain and submitted on-chain when needed.

<a id="fee-structure"></a>
### 🔍 Deep Dive: Fee Structure and Price Impact

GMX V2 has multiple fee layers that serve different purposes:

**1. Open/Close Position Fees (~0.05-0.1%)**
```
Standard execution fee applied to every position change.
$100,000 position × 0.05% = $50 fee per open/close
```

**2. Borrow Fees (hourly, utilization-based)**
```
Charged to all open positions, proportional to how much pool
capacity they consume. Higher utilization → higher borrow rate.

borrowFeePerHour = baseFee × utilizationFactor
```
This is analogous to the borrow rate in lending protocols (P2M4) — it incentivizes traders to close positions when the pool is heavily utilized.

**3. Funding Fees (between longs and shorts)**
```
Standard funding rate mechanism (see Funding Rate Mechanics above).
GMX V2 uses skew-based funding similar to Synthetix.

If long OI >> short OI: longs pay shorts
If short OI >> long OI: shorts pay longs
```

**4. Price Impact Fees (the most novel)**

This is GMX V2's key innovation for protecting LPs. Large trades relative to the pool size incur additional fees that simulate the price impact you'd experience on an order book.

```
Example: ETH/USD pool has $50M liquidity

$10,000 trade:  ~0% price impact (negligible vs pool)
$1,000,000 trade: ~0.2% price impact (2% of pool)
$5,000,000 trade: ~1% price impact (10% of pool)

Price impact = (sizeDelta / poolSize)^exponent × impactFactor
```

**Why price impact fees matter:** Without them, a trader could open a massive position at zero slippage (oracle price), then close it on a CEX at the same price — effectively extracting value from LPs. Price impact fees make this economically unprofitable for large sizes.

**Fee distribution:**

```
Total Fees Collected
        │
        ├── 63% → LP token holders (GM pool)
        │
        ├── 27% → GMX stakers (protocol revenue sharing)
        │
        └── 10% → Treasury / development fund
```

<a id="gmx-code-reading"></a>
### 📖 Code Reading Strategy: GMX V2

**Repository:** [gmx-io/gmx-synthetics](https://github.com/gmx-io/gmx-synthetics)

GMX V2's codebase is large (~100+ contracts). Here's a focused reading path:

**Start here (data structures):**
1. `contracts/position/Position.sol` — the `Position.Props` struct. Understand what fields define a position before reading any logic.
2. `contracts/market/Market.sol` — the `Market.Props` struct. Understand pool composition.

**Core flows:**
3. `contracts/order/OrderUtils.sol` — follow `createOrder` to see what happens when a trader submits an order
4. `contracts/order/OrderUtils.sol` → `executeOrder` — follow the keeper execution path
5. `contracts/position/IncreasePositionUtils.sol` — how a position is opened/increased
6. `contracts/position/DecreasePositionUtils.sol` — how a position is closed/decreased

**Fee calculation:**
7. `contracts/pricing/PositionPricingUtils.sol` — all fee calculations (open/close fees, price impact)
8. `contracts/market/MarketUtils.sol` — pool accounting, utilization, borrow rates

**Liquidation:**
9. `contracts/liquidation/LiquidationUtils.sol` — margin checks and liquidation logic
10. `contracts/adl/AdlUtils.sol` — auto-deleveraging when needed

**What to skip initially:**
- Callback contracts (complex but not core)
- Migration contracts
- Governance/role management
- Token transfer utils

> **Tip:** Read the tests first. GMX V2's test suite (in the `test/` directory) shows exactly how the contracts are used, with realistic scenarios. Tests are often the best documentation.

---

## Synthetix & Alternative Models

<a id="synthetix-debt-pool"></a>
### 💡 Synthetix: The Debt Pool Model

**Why this is architecturally interesting:** Synthetix takes a completely different approach from GMX. Instead of an LP pool that acts as counterparty, Synthetix uses a **shared debt pool** where all SNX stakers collectively take the other side of every trade. This has profound implications for risk distribution.

**How it works:**

1. SNX holders stake their tokens (must maintain ~400% collateralization ratio)
2. Staking lets them mint sUSD (a stablecoin)
3. sUSD can be traded for any "synth" — synthetic assets that track real prices (sETH, sBTC, etc.)
4. All synths are backed by the collective SNX staking pool

```
                    ┌────────────────────────────┐
                    │     Synthetix Debt Pool     │
                    │                            │
 SNX Staker A ─────┤  Total debt = sum of all    │
 (stakes 10k SNX)  │  outstanding synths         │
                    │                            │
 SNX Staker B ─────┤  Your share = your debt /   │
 (stakes 5k SNX)   │  total debt at entry        │
                    │                            │
 SNX Staker C ─────┤  If traders profit → total  │
 (stakes 20k SNX)  │  debt grows → you owe more  │
                    │                            │
                    │  If traders lose → total    │
                    │  debt shrinks → you owe less│
                    └────────────────────────────┘
```

**The key insight:** Every SNX staker's debt is proportional to the **total system debt**, not just the synths they personally minted. If another trader profits big, YOUR debt increases even if you did nothing. This is a form of socialized risk.

<a id="debt-pool-math"></a>
### 🔍 Deep Dive: Debt Pool Math with Worked Example

This is one of the more counterintuitive mechanisms in DeFi. Let's walk through a concrete example.

**Setup:**
```
Two stakers in the system:
  Alice: stakes SNX, mints 1,000 sUSD → buys 0.5 sETH (ETH = $2,000)
  Bob:   stakes SNX, mints 1,000 sUSD → holds sUSD

Total system debt: 2,000 sUSD
Alice's debt share: 50% (1,000 / 2,000)
Bob's debt share:   50% (1,000 / 2,000)
```

**ETH doubles to $4,000:**

```
Alice's portfolio:  0.5 sETH × $4,000 = $2,000 sUSD value
Bob's portfolio:    1,000 sUSD

Total system debt:  $2,000 + $1,000 = $3,000 sUSD
  (Alice's synths are worth $2,000, Bob's are worth $1,000)

Alice's debt: 50% × $3,000 = $1,500
  Alice has $2,000 in sETH, owes $1,500 → PROFIT of $500 ✓

Bob's debt:   50% × $3,000 = $1,500
  Bob has $1,000 in sUSD, owes $1,500 → LOSS of $500 ✗
```

**What just happened:** Alice made a directional bet (long ETH via sETH) and profited $500. But that profit came directly from the debt pool — Bob's debt increased by $500 even though he just held sUSD. Bob effectively took the short side of Alice's long trade without choosing to.

```
Before ETH doubles:             After ETH doubles:
┌─────────┬──────────┐         ┌─────────┬──────────┐
│         │ Debt     │         │         │ Debt     │
│ Alice   │ $1,000   │         │ Alice   │ $1,500   │
│ (sETH)  │ 50%      │         │ (sETH)  │ 50%      │
├─────────┼──────────┤         ├─────────┼──────────┤
│ Bob     │ $1,000   │         │ Bob     │ $1,500   │
│ (sUSD)  │ 50%      │         │ (sUSD)  │ 50%      │
├─────────┼──────────┤         ├─────────┼──────────┤
│ Total   │ $2,000   │         │ Total   │ $3,000   │
└─────────┴──────────┘         └─────────┴──────────┘

Alice's net: $2,000 - $1,500 = +$500
Bob's net:   $1,000 - $1,500 = -$500
Zero-sum: Alice's gain = Bob's loss ✓
```

**Why 400% collateralization?** Because stakers absorb all trader PnL. If a trader makes a massive profit, the debt pool grows proportionally. The high c-ratio ensures there's enough SNX backing to absorb large swings. During the 2021 bull run, some stakers saw their debt grow faster than their SNX appreciation — a painful lesson in debt pool mechanics.

**On-chain, this uses the accumulator pattern:**

```solidity
// Simplified from Synthetix
uint256 public totalDebt;           // global: sum of all synth values
uint256 public totalDebtShares;     // global: total debt shares outstanding

mapping(address => uint256) public debtShares;  // per-staker

// When staker mints sUSD:
function issue(uint256 amount) external {
    uint256 newShares = (totalDebtShares == 0)
        ? amount
        : amount * totalDebtShares / totalDebt;

    debtShares[msg.sender] += newShares;
    totalDebtShares += newShares;
    totalDebt += amount;
}

// Current debt for a staker:
function currentDebt(address staker) public view returns (uint256) {
    return totalDebt * debtShares[staker] / totalDebtShares;
}
```

This is the same share-based math as ERC-4626 vaults (P2M7), but applied to debt rather than assets. Your `debtShares` represent your proportional claim on the total system debt.

<a id="synthetix-perps-v2"></a>
### 💡 Synthetix Perps V2: Skew-Based Funding

Synthetix Perps V2 (deployed on Optimism) introduced a different funding rate model: **skew-based funding** rather than the traditional mark-vs-index approach.

**The key difference:**

```
Traditional funding (BitMEX-style):
  Rate = (Mark Price - Index Price) / Index Price

Synthetix skew-based funding:
  Rate = Skew / SkewScale

  Where:
    Skew = Long Open Interest - Short Open Interest
    SkewScale = protocol parameter (e.g., 1,000,000 ETH)
```

**Why skew-based?** In oracle-priced systems (like both GMX and Synthetix), the mark price effectively equals the index price — there's no independent perp market price. So the traditional mark-vs-index formula would always give zero. Instead, Synthetix uses the **imbalance between longs and shorts** (the skew) as a direct proxy for demand pressure.

**Example:**

```
Market: ETH perps
SkewScale: 1,000,000 ETH
Long OI: 60,000 ETH
Short OI: 40,000 ETH

Skew = 60,000 - 40,000 = 20,000 ETH (net long)
Funding Rate = 20,000 / 1,000,000 = 2% per funding period

Longs pay 2% to shorts → incentivizes new shorts / long closures
```

**Velocity-based dynamic fees:** Synthetix also charges dynamic fees based on how quickly the skew is changing. Rapid skew changes (e.g., a large trader opening a massive position) incur higher fees, discouraging sudden large trades that would destabilize the pool.

**Pyth oracle integration:** Synthetix Perps V2 was one of the first major protocols to use Pyth's pull-based oracle model, where prices are fetched off-chain and submitted on-chain at time of execution. This gives much higher price update frequency than traditional Chainlink push-based feeds (sub-second vs every heartbeat/deviation threshold).

<a id="dydx"></a>
### 💡 dYdX: Order Book Model (Awareness)

dYdX takes yet another approach: a full limit order book on a dedicated Cosmos app-chain (dYdX Chain).

**Architecture:**
- Purpose-built L1 blockchain (Cosmos SDK) optimized for order matching
- Off-chain order matching by validators, on-chain settlement
- Validators run the matching engine as part of block production
- No AMM, no pool counterparty — pure buyer-meets-seller

**Trade-offs vs pool models:**

| Advantage | Disadvantage |
|-----------|-------------|
| Capital efficient (no idle liquidity) | Requires market makers for liquidity |
| Familiar UX for CeFi traders | Less decentralized (validator-dependent) |
| Tight spreads in liquid markets | Spread widens in volatile/illiquid markets |
| No LP risk (makers choose their exposure) | Harder to bootstrap new markets |

**Why it's relevant:** dYdX V4 has become the highest-volume decentralized perp protocol. Understanding the order book model helps you appreciate the design trade-offs in pool-based models like GMX and Synthetix.

<a id="hyperliquid"></a>
### 💡 Hyperliquid (Awareness)

Hyperliquid is a purpose-built L1 for perpetuals with sub-second finality:

- Full order book (like dYdX) but with its own consensus mechanism
- Native spot + perps on the same chain
- HyperBFT consensus (~0.2s block times)
- Vertically integrated: chain, DEX, and bridge all built together
- Rapidly growing volume — sometimes exceeding dYdX

**Why it matters:** Hyperliquid demonstrates that app-specific chains for perps can achieve CeFi-level performance. The competitive landscape is shifting from "which smart contract design is best" to "which execution environment is best for perps."

<a id="architecture-comparison"></a>
### 💡 Architecture Comparison

| Feature | GMX V2 | Synthetix Perps V2 | dYdX V4 | Hyperliquid |
|---------|--------|-------------------|---------|-------------|
| **Price Discovery** | Oracle (Chainlink) | Oracle (Pyth) | Order Book | Order Book |
| **Counterparty** | LP Pool (GM) | Debt Pool (SNX stakers) | Other Traders | Other Traders |
| **Slippage** | Near-zero + price impact fee | Near-zero + dynamic fee | Market-based (spread) | Market-based (spread) |
| **LP/Maker Risk** | Trader PnL exposure | Socialized debt | Chosen by makers | Chosen by makers |
| **Chain** | Arbitrum (L2) | Optimism (L2) | Cosmos app-chain | Custom L1 |
| **Frontrun Protection** | Two-step keeper | Off-chain + Pyth | Validator ordering | Validator ordering |
| **Funding Model** | Skew-based | Skew-based + velocity | Mark vs index | Mark vs index |
| **Capital Efficiency** | Moderate (pool must be large) | Low (400% SNX c-ratio) | High (no idle capital) | High (no idle capital) |
| **Bootstrapping** | Easy (just add LP) | Hard (need SNX stakers) | Hard (need market makers) | Hard (need market makers) |
| **Max Leverage** | 50-100x (per market) | 25-50x | 20x | 50x |

**Which model wins?** There's no universal winner — each optimizes for different trade-offs:

- **GMX**: Best for retail (zero slippage for small trades, easy LP), worst for capital efficiency
- **Synthetix**: Best for asset diversity (any synth with an oracle), worst for capital efficiency (400% c-ratio)
- **dYdX/Hyperliquid**: Best for capital efficiency and institutional traders, worst for bootstrapping new markets

---

## Liquidation in Perpetuals

<a id="perp-vs-lending-liquidation"></a>
### 💡 Why Perp Liquidation Differs from Lending

You studied liquidation in lending protocols (P2M4). Perp liquidation shares the same concept (position becomes undercollateralized → someone closes it for a fee) but differs in critical ways:

| Aspect | Lending (Aave/Compound) | Perpetuals (GMX/Synthetix) |
|--------|------------------------|---------------------------|
| **Speed** | Slow — asset depreciates against a stable debt | Fast — leverage amplifies every move |
| **Leverage** | 1.2-5x implicit | 2-100x explicit |
| **Time to liquidation** | Hours to days (for typical LTVs) | Minutes to seconds at high leverage |
| **Oracle dependency** | Moderate (periodic updates OK) | Critical (stale price = bad liquidation) |
| **Liquidation unit** | Partial (repay part of debt) | Often full position (in GMX V2) |
| **Cascading risk** | Moderate | Severe (leverage amplifies cascades) |

**The core difference: leverage.** In lending, if your collateral drops 10%, you lose ~10% of margin (less if LTV is conservative). In a 10x leveraged perp, a 10% move wipes 100% of your margin. This means perp liquidation is a time-critical operation — positions can go from healthy to underwater within a single block.

```
Lending: 80% LTV, 83% LT, ETH drops 10%
  Before: $1,000 collateral, $800 debt → HF = 1.04 (at 83% LT)
  After:  $900 collateral, $800 debt → HF = 0.93 (liquidatable)
  Time from healthy to liquidatable: gradual (one oracle update)

Perps: 10x leverage, ETH drops 10%
  Before: $1,000 margin, $10,000 position → margin ratio = 10%
  After:  $0 margin, $10,000 position → margin ratio = 0% (UNDERWATER)
  Time from healthy to underwater: ONE price move
```

<a id="liquidation-engine"></a>
### 🔍 Deep Dive: Liquidation Engine Flow

**The lifecycle of a perp liquidation:**

```
                    Continuous Monitoring
                    ┌─────────────┐
                    │ Keeper Bot  │  Monitors all open positions
                    │ (off-chain) │  every block
                    └──────┬──────┘
                           │
                     Check each position:
                     remainingMargin < maintenanceMargin?
                           │
                    ┌──────┴──────┐
                    │     No      │ → Skip, check next position
                    └─────────────┘
                    ┌──────┴──────┐
                    │     Yes     │ → Submit liquidation tx
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │   On-Chain      │
                    │   Liquidation   │
                    │                 │
                    │ 1. Verify       │  Re-check margin on-chain
                    │    position is  │  (price may have changed)
                    │    liquidatable │
                    │                 │
                    │ 2. Close        │  Close at oracle price
                    │    position     │
                    │                 │
                    │ 3. Distribute   │  Margin goes to:
                    │    remaining    │  • Liquidation fee → keeper
                    │    margin       │  • Penalty → insurance fund
                    │                 │  • Remainder → trader (if any)
                    │                 │
                    │ 4. If margin    │  Position was underwater:
                    │    negative     │  • Loss absorbed by insurance fund
                    │    (bad debt)   │  • If fund empty → ADL
                    └─────────────────┘
```

**In Solidity, the margin check looks like:**

```solidity
function isLiquidatable(Position memory pos, uint256 currentPrice) public view returns (bool) {
    // Calculate unrealized PnL
    int256 pnl;
    if (pos.isLong) {
        pnl = int256(pos.size) * (int256(currentPrice) - int256(pos.entryPrice)) / int256(pos.entryPrice);
    } else {
        pnl = int256(pos.size) * (int256(pos.entryPrice) - int256(currentPrice)) / int256(pos.entryPrice);
    }

    // Calculate pending funding
    int256 funding = _pendingFunding(pos);

    // Remaining margin = collateral + PnL - funding owed
    int256 remainingMargin = int256(pos.collateral) + pnl - funding;

    // Maintenance margin requirement
    uint256 maintenanceMargin = pos.size * MAINTENANCE_MARGIN_BPS / BPS;

    return remainingMargin < int256(maintenanceMargin);
}
```

**Keeper incentives and competition:**

Liquidation is a competitive MEV opportunity. Multiple keeper bots race to liquidate unhealthy positions because the liquidation fee is pure profit. This has two effects:
1. **Positive:** Positions get liquidated quickly, keeping the protocol solvent
2. **Negative:** MEV competition can increase gas costs and cause ordering games (covered in P3M5 — MEV)

> **Connection to P2M4 (Lending):** The liquidation keeper pattern is identical to Aave/Compound liquidation bots. The code structure is nearly the same — check position health, call liquidate function, collect reward. The main difference is the speed requirement: lending liquidation bots can be lazy (check every few blocks), perp liquidation bots must be fast (check every block, or use event-driven monitoring).

<a id="insurance-fund"></a>
### 💡 Insurance Fund

**The problem:** When a position is liquidated at exactly the maintenance margin, the remaining margin covers the liquidation fee. But in fast markets, the price can blow past the liquidation price before a keeper executes the liquidation. The position becomes **underwater** — remaining margin is negative, and closing the position at the current price creates a loss that no one has paid for.

**The solution: Insurance fund.**

```
Normal liquidation:                    Bad debt liquidation:

Position: 10x long at $3,000          Position: 10x long at $3,000
Collateral: $3,000                     Collateral: $3,000
Maint margin: $300                     Maint margin: $300

Price drops to $2,730:                 Price drops to $2,680 (gap!):
  PnL = -$2,700                          PnL = -$3,200
  Remaining = $300 (= maint)             Remaining = -$200 (NEGATIVE)
  Liquidation fee: $100                   Bad debt: $200
  To insurance: $200                      Insurance fund pays $200
  To trader: $0
```

**Insurance fund sources:**
1. Liquidation penalties from normal liquidations
2. A portion of trading fees (protocol-dependent)
3. In GMX V2: from the pool itself (LPs absorb bad debt indirectly)

**Insurance fund sizing is critical:** Too small, and the protocol can't handle a flash crash. Too large, and capital is sitting idle. Most protocols aim for the insurance fund to cover a 2-3 standard deviation price move across all open positions.

> **Connection to P2M6 (Stablecoins):** The insurance fund concept parallels Liquity's stability pool — both are reserves that absorb losses from underwater positions. The stability pool absorbs bad CDP debt; the insurance fund absorbs bad perp position debt. Same pattern, different context.

<a id="adl"></a>
### 💡 Auto-Deleveraging (ADL)

**When the insurance fund is depleted**, the protocol must find another source of funds to cover bad debt. Auto-deleveraging (ADL) is the last resort.

**How ADL works:**
1. Insurance fund is empty (or insufficient for the bad debt)
2. Protocol identifies the most profitable positions on the **opposite side** of the liquidated position
3. Those profitable positions are forcefully partially closed to generate the funds needed
4. The closed portion is settled at the mark price

```
Example: Insurance fund depleted after a crash

Liquidated position: 50x long, -$50,000 bad debt (was long, price crashed)
Insurance fund: $0

Protocol runs ADL:
  Find most profitable SHORT positions:
    Short A: +$200,000 unrealized profit → close 25% → releases $50,000

  Short A is forced to realize $50,000 of their $200,000 profit.
  Their position is reduced from full size to 75%.
  They didn't choose this — it was forced by the protocol.
```

**Why this is controversial:**
- Profitable traders lose part of their position without consent
- Creates trust issues: "Can I rely on my winning position staying open?"
- Some traders avoid protocols with ADL risk
- But it's necessary — without ADL, the protocol becomes insolvent

**GMX V2 ADL mechanics:**
- ADL is triggered when the pool can't cover trader PnL
- Positions are ranked by profit-to-collateral ratio
- Highest P&L-ratio positions are deleveraged first
- Announced with a flag (`isAdlEnabled`) so traders can monitor

**Mitigation strategies (how protocols reduce ADL risk):**
1. Conservative open interest caps (limits total exposure)
2. Dynamic fees that increase with utilization
3. Adequate insurance fund capitalization
4. Position size limits (no single position can create catastrophic bad debt)

<a id="cascading-liquidation"></a>
### 💡 Cascading Liquidation

**The nightmare scenario:** A large liquidation creates price impact, which triggers more liquidations, which create more price impact, creating a liquidation cascade — a self-reinforcing spiral.

```
Phase 1: Initial crash
  ETH drops 5% ($3,000 → $2,850)
  50x leveraged positions hit liquidation
  $10M in liquidations triggered

Phase 2: Cascade begins
  ┌─ $10M of longs force-closed ───────────────────────┐
  │                                                     │
  │  On order book: selling pressure → price drops more │
  │  On oracle-based: oracle updates → new price lower  │
  │                                                     │
  │  Price drops another 3% ($2,850 → $2,765)          │
  │                                                     │
  │  20x leveraged positions now hit liquidation         │
  │  $25M more in liquidations triggered                │
  └─────────────────────────────────────────────────────┘

Phase 3: Cascade accelerates
  ┌─ $25M more longs force-closed ─────────────────────┐
  │                                                     │
  │  Price drops another 5% ($2,765 → $2,627)          │
  │                                                     │
  │  10x positions hit liquidation                      │
  │  $100M+ in liquidations                             │
  │                                                     │
  │  Insurance fund depleted → ADL triggered            │
  └─────────────────────────────────────────────────────┘

Phase 4: Aftermath
  Total price impact: -12.4% (vs initial -5%)
  The cascade more than doubled the crash severity.
```

**Real-world examples:**
- **March 12, 2020 ("Black Thursday"):** ETH dropped 43% in a day. BitMEX's liquidation engine couldn't keep up, leading to cascading liquidations that drove the price down further than fundamentals warranted. BitMEX eventually went down entirely, which ironically stopped the cascade.
- **May 19, 2021:** $8B in liquidations across crypto in 24 hours. Cascading liquidations across CeFi and DeFi venues amplified a ~30% ETH drop.

**Why oracle-based systems (GMX) have different cascade dynamics:**

In order book systems, liquidations create direct selling pressure on the venue, causing the price to drop further on that same venue. In oracle-based systems like GMX, liquidations don't directly impact the oracle price (which comes from external exchanges). However:
1. Large GMX liquidations can still cascade within GMX (depleting insurance fund → ADL)
2. If GMX liquidation bots hedge on other venues, they create selling pressure there, which eventually feeds back into the oracle
3. Cross-venue cascade: perp liquidation on Venue A → selling on Venue B → oracle price drops → more liquidations on Venue C

**Mitigation strategies:**
1. **Open interest caps** — limit total exposure per market
2. **Position size limits** — prevent single positions from creating outsized impact
3. **Dynamic fees** — higher fees when utilization/skew is high, discouraging crowded trades
4. **Gradual liquidation** — close positions in parts rather than all at once
5. **Circuit breakers** — pause trading during extreme volatility (controversial — centralization risk)

#### 🔗 DeFi Pattern Connection

Cascading liquidation is the perp equivalent of bank runs and is closely related to:
- **Lending cascading liquidation (P2M4):** Same mechanism, lower leverage, slower speed
- **Oracle manipulation attacks (P2M8):** If an attacker can manipulate the oracle, they can trigger artificial cascades
- **Flash crash exploitation (P3M5 MEV):** MEV bots can profit from cascade dynamics by positioning ahead of liquidation waves

---

<a id="pattern-connections"></a>
## 🔗 DeFi Pattern Connections

**Where perpetual concepts appear across DeFi:**

| Concept | Where else it appears | Connection |
|---------|----------------------|------------|
| Funding rate accumulator | Aave interest index, ERC-4626 share price, Compound borrowIndex | Same O(1) accumulator pattern — global counter + per-user snapshot |
| Pool-as-counterparty (GMX) | Uniswap LP risk, covered call vaults | LPs take the other side of trader activity |
| Debt pool (Synthetix) | MakerDAO system surplus/deficit, Ethena backing | Socialized risk across all participants |
| Two-step execution | Chainlink VRF (request → fulfill), Gelato relay | Off-chain execution to prevent frontrunning |
| Insurance fund | Liquity stability pool, Aave safety module | Protocol-level reserve for bad debt absorption |
| ADL | Partial liquidation in lending, socialized losses in bridges | Forced position reduction to maintain solvency |
| Open interest caps | Borrow caps in lending (Aave), supply caps | Limiting protocol exposure to any single asset |
| Keeper-based liquidation | Aave/Compound liquidation bots, Gelato automation | Off-chain monitoring, on-chain execution |

**The meta-pattern:** Perpetual protocols are essentially leveraged lending protocols with different terminology. Margin = collateral, position = borrow, funding = interest, liquidation = liquidation. The math is the same — what changes is the speed (leverage amplifies everything) and the counterparty structure (pool vs debt pool vs order book).

---

<a id="job-market"></a>
## 💼 Job Market Context

**What DeFi teams expect:**

1. **"How does a funding rate work and why is it necessary?"**
   - Good answer: Explains the mechanism (longs pay shorts when mark > index) and that it keeps the perp price tracking spot.
   - Great answer: Explains the accumulator pattern, why continuous funding is more gas-efficient than periodic, how skew-based funding differs from mark-vs-index, and connects to delta-neutral yield strategies (Ethena).

2. **"Compare GMX's LP pool model with a traditional order book."**
   - Good answer: Lists the basic differences (oracle vs order book, pool vs traders as counterparty).
   - Great answer: Discusses trade-offs in depth — capital efficiency (order book wins), bootstrapping ease (pool wins), LP risk profile (options-like payoff), frontrunning protection (two-step execution), and when each model is more appropriate.

3. **"What happens when the insurance fund is depleted?"**
   - Good answer: ADL kicks in and profitable positions are forcefully closed.
   - Great answer: Explains the full cascade — insurance fund depletion → ADL ranking by profit-to-collateral ratio → trust implications for traders → how protocols size insurance funds → mitigation strategies (OI caps, dynamic fees, position limits). Mentions that in Synthetix, the debt pool itself absorbs bad debt (no separate insurance fund), and how this is socialized across all stakers.

4. **"How would you design a liquidation engine that minimizes cascading risk?"**
   - Good answer: Open interest caps, position size limits, insurance fund.
   - Great answer: Multi-layer defense — (1) prevention via dynamic fees and OI caps, (2) gradual liquidation (partial rather than full position close), (3) price impact fees on liquidation execution, (4) insurance fund sizing based on VaR modeling, (5) ADL as absolute last resort with clear ordering. Mentions that oracle-based systems have different cascade dynamics than order book systems.

5. **"Explain the funding rate accumulator pattern and where else it appears in DeFi."**
   - Good answer: Global counter, per-position snapshot, O(1) settlement.
   - Great answer: Connects to Compound's borrowIndex, Aave's liquidityIndex, ERC-4626 share pricing, and Synthetix's debtRatio. Explains that it's the same mathematical technique (proportional claim on a growing/shrinking pool) applied in different contexts. Can sketch the Solidity implementation from memory.

**Interview red flags:**
- Not understanding that LPs in GMX take real risk (they're not just earning passive fees)
- Confusing mark price and index price, or not knowing which is used for liquidation
- Thinking "zero slippage" means "zero cost" (forgetting about funding, borrow fees, price impact fees)
- Not being able to explain why the funding rate accumulator is O(1)
- Describing ADL without understanding why it's controversial

**Pro tip:** Perp protocol development is one of the hottest DeFi hiring areas. If you can explain the funding rate accumulator, implement a basic perp exchange, and discuss the trade-offs between pool-based and order book models with nuance, you'll stand out from most candidates. Understanding MEV implications (P3M5) of perp designs is an additional differentiator.

---

<a id="exercises"></a>
## 🎯 Module 2 Exercises

**Workspace:** `workspace/src/part3/module2/`

### Exercise 1: Funding Rate Engine

**File:** `workspace/src/part3/module2/exercise1-funding-rate-engine/FundingRateEngine.sol`
**Test:** `workspace/test/part3/module2/exercise1-funding-rate-engine/FundingRateEngine.t.sol`

Build the core funding rate accumulator pattern:
- Global cumulative funding index (per-second continuous funding)
- Skew-based funding rate calculation (longs OI vs shorts OI)
- Per-position funding settlement using the accumulator
- Correct sign handling (longs pay when positive, shorts pay when negative)
- Time-weighted accumulation with `vm.warp` testing

**What you'll learn:** The O(1) accumulator pattern that appears everywhere in DeFi. After this exercise, you'll recognize it instantly in Aave, Compound, Synthetix, and every perp protocol.

### Exercise 2: SimplePerpExchange

**File:** `workspace/src/part3/module2/exercise2-simple-perp-exchange/SimplePerpExchange.sol`
**Test:** `workspace/test/part3/module2/exercise2-simple-perp-exchange/SimplePerpExchange.t.sol`

Build a simplified perpetual exchange combining all concepts:
- Position lifecycle: open long/short → accrue funding → close with PnL
- Oracle-based pricing (mock Chainlink, reuses P3M1 pattern)
- Leverage enforcement (max leverage check at open)
- Margin tracking (collateral + PnL + funding = remaining margin)
- Keeper-triggered liquidation with incentive fee
- LP pool as counterparty (deposit/withdraw liquidity)
- Insurance fund for bad debt absorption

**What you'll learn:** How all the pieces fit together — funding, margin, PnL, liquidation, and LP pool accounting in one contract. This is a simplified version of what you'll build at full scale in the Part 3 Capstone (Module 9).

**Run:** `forge test --match-contract FundingRateEngineTest -vvv` and `forge test --match-contract SimplePerpExchangeTest -vvv`

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [GMX V2 Synthetics](https://github.com/gmx-io/gmx-synthetics) — pool-based perp protocol (Arbitrum)
- [Synthetix V2 Perps](https://github.com/Synthetixio/synthetix/tree/develop/contracts) — debt pool model (Optimism)
- [Synthetix V3](https://github.com/Synthetixio/synthetix-v3) — modular redesign
- [dYdX V4](https://github.com/dydxprotocol/v4-chain) — order book on Cosmos app-chain

### Documentation
- [GMX V2 docs](https://docs.gmx.io/) — position mechanics, fee structure, risk parameters
- [Synthetix V2 docs](https://docs.synthetix.io/) — debt pool, synths, perps
- [dYdX V4 docs](https://docs.dydx.exchange/) — order book mechanics

### Further Reading
- [Paradigm: Everlasting Options](https://www.paradigm.xyz/2021/05/everlasting-options) — academic foundation for perpetual instruments
- [GMX V2 technical overview](https://gmx-io.notion.site/) — architecture deep dive
- [Ethena Labs](https://ethena.fi/docs) — delta-neutral funding rate yield (P3M6 connection)
- [Gauntlet Risk Reports](https://risk.gauntlet.xyz/) — quantitative risk analysis for perp protocols

---

**Navigation:** [← Module 1: Liquid Staking](1-liquid-staking.md) | [Part 3 Overview](README.md) | [Next: Module 3 — Yield Tokenization →](3-yield-tokenization.md)

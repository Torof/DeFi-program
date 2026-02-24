# Part 3 — Module 2: Perpetuals & Derivatives (~5 days)

> **Prerequisites:** Part 2 — Modules 2 (AMMs), 3 (Oracles), 4 (Lending & Borrowing)

## Overview

Perpetual futures are one of the largest DeFi verticals by volume, often exceeding spot DEX volume. This module covers the mechanics of perpetual contracts, how they maintain price tracking through funding rates, and the architecturally distinct approaches taken by GMX (oracle-based) and Synthetix (debt pool). You'll understand margin, leverage, liquidation in the perps context, and build a simplified perpetual exchange.

---

## Day 1: Perpetual Futures Fundamentals

### What is a Perpetual?
- Traditional futures: contract to buy/sell at future date at set price
- Perpetual futures: no expiry date — position stays open indefinitely
- Tracks an index price (spot price of underlying asset)
- Funding rate mechanism keeps perp price (mark) close to index price
- Invented by BitMEX (2016), now dominant DeFi derivative

### Mark Price vs Index Price
- **Index price** — spot price from oracles (Chainlink, Pyth, aggregated)
- **Mark price** — current trading price of the perpetual contract
- When mark > index: longs are paying shorts (too many longs)
- When mark < index: shorts are paying longs (too many shorts)
- Mark price used for liquidation calculations (not index)

### Funding Rate Mechanics
- Periodic payment between longs and shorts (typically every 8h or continuous)
- Formula: `Funding Rate = (Mark Price - Index Price) / Index Price`
- Positive funding: longs pay shorts
- Negative funding: shorts pay longs
- Self-correcting: high funding → expensive to hold position → traders close → mark approaches index
- Annualized funding rates can be 10-100%+ in volatile markets

### 🔍 Deep Dive: Funding Rate Math
- Per-period funding payment: `Position Size x Funding Rate`
- Continuous funding: accumulated per second via funding rate accumulator
- Impact on PnL: must be factored into position profitability
- Funding rate as yield source: "delta-neutral" strategies (Ethena connection, P2M6)

### Margin and Leverage
- **Initial margin** — collateral required to open position
- **Maintenance margin** — minimum collateral to keep position open
- **Leverage** — position size / collateral (e.g., 10x = $1000 position on $100 collateral)
- **Isolated margin** — each position has separate collateral
- **Cross margin** — all positions share a collateral pool
- **Liquidation price** — price at which position's margin falls below maintenance

### PnL Calculation
- Long PnL: `Position Size x (Exit Price - Entry Price) / Entry Price`
- Short PnL: `Position Size x (Entry Price - Exit Price) / Entry Price`
- Real PnL includes: trading PnL + funding payments - fees
- Unrealized vs realized PnL

### 🔍 Deep Dive: Liquidation Price Derivation
- For longs: `Liquidation Price = Entry Price x (1 - Initial Margin / Leverage + Maintenance Margin)`
- For shorts: mirror formula
- Step-by-step example with real numbers
- Why higher leverage = tighter liquidation price

---

## Day 2: GMX Architecture

### The GMX Model: Liquidity Pool as Counterparty
- No order book, no AMM curve
- Traders trade against a liquidity pool (GLP in V1, GM pools in V2)
- Oracle-based execution: trades execute at Chainlink price (zero slippage for small trades)
- LPs earn trading fees + funding + liquidation penalties
- LPs take the other side of every trade (if traders win, LPs lose)

### GMX V2 (GM Pools)
- Per-market isolated pools (ETH/USD, BTC/USD, etc.)
- Each pool has long collateral token + short collateral token
- Position tracking: size, collateral, entry price, funding index
- **Keeper network** — off-chain keepers execute orders after oracle update
  - Two-step: user creates order → keeper executes at oracle price
  - Prevents frontrunning (price not known at order time)

### Fee Structure
- Open/close position fees (~0.05-0.1%)
- Borrow fees (hourly, based on utilization)
- Funding fees (between longs/shorts)
- Price impact fees (for large trades relative to pool)
- Fees distributed: 63% to LPs, 27% to GMX stakers, 10% to treasury

### 📖 Read: GMX V2 Key Contracts
- `PositionStore` — position data structure and storage
- `IncreasePosition` / `DecreasePosition` — position lifecycle
- `MarketUtils` — pool accounting and fee calculations
- `OrderHandler` — keeper execution flow
- `LiquidationHandler` — liquidation mechanics

### 📖 Code Reading Strategy
1. Start with position data structure (what fields define a position)
2. Read `IncreasePosition` for opening a trade
3. Trace fee calculations in `MarketUtils`
4. Understand keeper flow: order creation → execution delay → oracle price
5. Study `LiquidationHandler` for margin checks

---

## Day 3: Synthetix & Alternative Models

### Synthetix: The Debt Pool Model
- All SNX stakers share a collective debt pool
- Stakers must maintain c-ratio (collateralization ratio, ~400%)
- Mint sUSD → trade for any synth (sETH, sBTC, etc.)
- **Key insight:** when a trader profits, the debt pool grows → all stakers owe more
- When a trader loses, the debt pool shrinks → all stakers owe less
- Zero slippage (oracle-priced) but debt pool exposure

### Synthetix Perps V2 (Optimism)
- On-chain perpetual futures
- Pyth oracle integration (pull-based, high frequency)
- Off-chain order execution with on-chain settlement
- Funding rate based on market skew (not mark/index)
- Dynamic fees based on velocity of skew change

### dYdX: Order Book Model (Awareness)
- Full limit order book on dedicated app-chain (Cosmos)
- Off-chain matching, on-chain settlement
- MEV-resistant by design (validators can't frontrun)
- Professional market maker integration
- Different trade-offs: more capital efficient, less decentralized

### Hyperliquid (Awareness)
- Purpose-built L1 for perps
- Sub-second block times for order book
- Native spot + perps on same chain
- Growing rapidly — relevant to understand the competitive landscape

### Architecture Comparison

| Feature | GMX | Synthetix | dYdX |
|---------|-----|-----------|------|
| Price Source | Oracle | Oracle | Order Book |
| Counterparty | LP Pool | Debt Pool | Other Traders |
| Slippage | Low (oracle) | Zero | Market-based |
| LP Risk | Trader PnL | Debt exposure | None (makers) |
| Chain | Arbitrum | Optimism | Cosmos app-chain |
| Decentralization | Moderate | Moderate | Lower |

---

## Day 4: Liquidation in Perpetuals

### Why Perp Liquidation Differs from Lending
- Lending: position slowly becomes undercollateralized as price moves
- Perps: leverage amplifies price movement → liquidation happens faster
- 10x long: 10% price drop = 100% of margin lost
- Speed is critical — positions can go underwater between blocks

### Liquidation Engine
- **Keepers/bots** continuously monitor positions
- Check: `remaining margin < maintenance margin requirement`
- Liquidation call: close position at current oracle price
- Remaining margin goes to: liquidation fee + insurance fund + protocol

### Insurance Fund
- Absorbs losses when liquidated position has negative margin
- Funded by: liquidation penalties, portion of trading fees
- When depleted → auto-deleveraging (ADL)

### Auto-Deleveraging (ADL)
- Last resort when insurance fund can't cover losses
- Most profitable opposing positions are forcefully reduced
- Controversial but necessary for protocol solvency
- GMX V2 ADL mechanics
- Traders can't fully trust that their profitable position will remain open

### Cascading Liquidation
- Large liquidation → position closed at market → price impact
- Price impact triggers more liquidations → cascade
- Especially dangerous with oracle-based execution (GMX)
- "Liquidation cascades" in March 2020, May 2021 crashes
- Mitigation: position size limits, open interest caps, dynamic fees

### 🔗 DeFi Pattern Connection
- Liquidation mechanics → Lending module (P2M4)
- Oracle dependency → Oracle module (P2M3)
- Insurance fund → Stability pool concept (P2M6 Liquity)
- Keeper networks → similar to Chainlink keepers, Gelato

---

## Day 5: Build a Simplified Perpetual Exchange

### What to Build: SimplePerpExchange.sol
- Position tracking (size, collateral, entry price, direction, funding index)
- Open long / open short with leverage
- Close position with PnL settlement
- Funding rate accumulator (per-second continuous funding)
- Liquidation engine (keeper-callable)
- LP pool as counterparty (simplified)

### Test Suite
- Open/close positions with correct PnL
- Funding rate accrual over time
- Liquidation at correct threshold
- Cascading liquidation scenario
- Maximum leverage limits
- Fuzz: random price movements, verify solvency invariant
- Invariant: LP pool + insurance fund >= sum of all unrealized PnL obligations

---

## 🎯 Module 2 Exercises

**Workspace:** `workspace/src/part3/module2/`

### Exercise 1: Funding Rate Accumulator
- Implement continuous funding rate calculation
- Track cumulative funding per unit of position size
- Calculate funding payments for positions opened at different times
- Test with time manipulation (vm.warp)

### Exercise 2: SimplePerpExchange
- Full perpetual exchange with positions, leverage, funding, liquidation
- LP pool provides counterparty liquidity
- Oracle-based pricing (mock Chainlink)
- Keeper-triggered liquidation
- Comprehensive test suite including cascading scenarios

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding funding rate mechanics and their role in price convergence
- Familiarity with at least one perp architecture (GMX or Synthetix)
- Ability to reason about liquidation cascades and insurance fund solvency
- Understanding the trade-offs between oracle-based and order book models

**Common interview topics:**
- "How does a funding rate work and why is it necessary?"
- "Compare GMX's LP pool model with a traditional order book"
- "What happens when the insurance fund is depleted?"
- "How would you design a liquidation engine that minimizes cascading risk?"

---

## 📚 Resources

### Production Code
- [GMX V2 Synthetics](https://github.com/gmx-io/gmx-synthetics)
- [Synthetix V2 Perps](https://github.com/Synthetixio/synthetix/tree/develop/contracts)
- [Synthetix V3](https://github.com/Synthetixio/synthetix-v3)

### Documentation
- [GMX docs](https://docs.gmx.io/)
- [Synthetix docs](https://docs.synthetix.io/)
- [dYdX docs](https://docs.dydx.exchange/)

### Further Reading
- [Perpetual Protocol mechanism explainer](https://docs.perp.com/)
- [GMX V2 technical overview](https://gmx-io.notion.site/)
- [Paradigm: Everlasting Options (academic foundation)](https://www.paradigm.xyz/2021/05/everlasting-options)

---

**Navigation:** [← Module 1: Liquid Staking](1-liquid-staking.md) | [Part 3 Overview](README.md) | [Next: Module 3 — Yield Tokenization →](3-yield-tokenization.md)

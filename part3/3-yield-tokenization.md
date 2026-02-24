# Part 3 — Module 3: Yield Tokenization (~3 days)

> **Prerequisites:** Part 2 — Modules 2 (AMMs), 7 (Vaults & Yield) + Part 3 Module 1 (Liquid Staking)

## Overview

Yield tokenization splits yield-bearing assets into separate principal and yield components, enabling fixed-rate DeFi and yield speculation. Pendle is the dominant protocol in this space, and its architecture introduces a novel AMM design purpose-built for time-decaying assets. This module covers the mechanics, math, and integration patterns of yield tokenization — one of the most innovative DeFi primitives to emerge in 2023-2024.

---

## Day 1: The Concept — Splitting Principal from Yield

### Why Yield Tokenization?
- All yield in DeFi is variable — rates change constantly
- No native way to lock in a fixed rate
- Traditional finance has fixed-rate bonds — DeFi has none (until Pendle)
- Yield tokenization creates the DeFi equivalent of zero-coupon bonds

### The Core Mechanism
- Start with a yield-bearing asset (wstETH, aUSDC, GLP, etc.)
- Split into two tokens:
  - **PT (Principal Token)** — claim on the underlying at maturity
  - **YT (Yield Token)** — claim on all yield generated until maturity
- Before maturity: PT trades at discount (like a zero-coupon bond)
- At maturity: PT redeemable 1:1 for underlying, YT stops accruing

### Fixed Rate from Buying PT
- PT trades at discount: e.g., 1 PT-wstETH costs 0.97 wstETH
- At maturity: redeem 1 PT for 1 wstETH
- Fixed yield: 0.03/0.97 ≈ 3.09% (annualized based on time to maturity)
- Rate is locked at purchase — doesn't change regardless of market

### Yield Speculation from Buying YT
- YT captures all future yield from underlying until maturity
- If you think yields will increase → buy YT (leveraged yield exposure)
- YT price reflects market's expectation of future yield
- Cheap leverage on yield direction

### 🔍 Deep Dive: The Math
- PT + YT = 1 underlying (by construction)
- PT price + YT price = underlying price (arbitrage enforced)
- Implied yield = the market-priced future yield based on PT discount
- As maturity approaches: PT → 1.0, YT → 0.0
- Time decay: YT loses value as remaining yield period shrinks

---

## Day 2: Pendle Architecture

### SY (Standardized Yield) — ERC-5115
- Universal wrapper for any yield-bearing token
- Wraps: stETH, wstETH, aUSDC, cDAI, GLP, sDAI, etc.
- Standard interface: `deposit()`, `redeem()`, `exchangeRate()`
- Abstracts away differences between yield sources
- Foundation for the entire Pendle system

### PT/YT Minting
- Lock SY in YieldContractFactory → receive PT + YT
- Both have same maturity date
- 1 SY → 1 PT + 1 YT (always)
- Redeem: return PT + YT → get back SY (before maturity)
- After maturity: PT alone redeemable for SY

### The Pendle AMM — Purpose-Built for Time-Decaying Assets
- **Not constant product!** Standard x*y=k doesn't work for assets approaching 1:1 at maturity
- Uses modified logit curve (inspired by Notional Finance)
- The curve adjusts over time: as maturity approaches, the curve flattens
- At maturity, any remaining PT trades at exactly 1:1 with SY
- **Implied rate** is the key output — not just price
- Rate discovery: market participants express views on future yields

### 🔍 Deep Dive: The AMM Curve
- Pool contains PT and SY (not PT and YT)
- The curve parameter changes with time-to-maturity
- At t=0 (just created): wider price range, more speculation
- At t=maturity: curve collapses to 1:1
- Scalar and anchor parameters control curve shape
- LP positions: provide liquidity for PT/SY trading

### Market Creation and Lifecycle
- Markets created with specific maturity dates (quarterly, monthly)
- Active trading until maturity
- At maturity: PT redeemable, YT stops accruing, market closes
- Rolling: users move to new maturity market

### 📖 Read: Pendle Key Contracts
- `SYBase.sol` — standardized yield base implementation
- `PendleYieldToken.sol` — YT with yield accrual tracking
- `PendlePrincipalToken.sol` — PT with maturity redemption
- `PendleMarketV3.sol` — the custom AMM
- `PendleRouter.sol` — user-facing entry point

### 📖 Code Reading Strategy
1. Start with SY — understand the yield abstraction layer
2. Read PT/YT minting — how splitting works
3. Study the AMM — focus on how time-to-maturity affects pricing
4. Trace a swap through the router
5. Study redemption at maturity

---

## Day 3: Strategies, Integration & Build

### Strategy 1: Fixed Income (Buy PT)
- Buy PT at discount → hold to maturity → redeem at 1:1
- Locked fixed rate regardless of market conditions
- Risk: underlying protocol failure, smart contract risk
- Use case: treasury management, risk-off positioning

### Strategy 2: Yield Speculation (Buy YT)
- Buy YT → receive all yield until maturity
- Leveraged exposure to yield direction
- If actual yield > implied yield at purchase → profit
- If actual yield < implied yield → loss (plus time decay)
- Use case: betting on yield increases, airdrop farming

### Strategy 3: LP in PT/SY Pool
- Provide liquidity in Pendle's AMM
- Earn: swap fees + PT discount + underlying yield on SY portion
- IL characteristics different from standard AMMs (time-decay helps LP)
- As maturity approaches, PT and SY converge → IL decreases

### Composability: PT as Collateral
- Morpho Blue accepts Pendle PT as collateral
- Pricing: PT has known value at maturity → predictable collateral value
- Discount = safety margin (PT < underlying until maturity)
- Liquidation: can sell PT on Pendle AMM

### LST + Pendle Composability
- wstETH → SY-wstETH → PT-wstETH + YT-wstETH
- Buy PT-wstETH: lock in staking yield
- Buy YT-wstETH: leveraged bet on staking APR changes
- Points/airdrop meta: YT captures future airdrops of underlying protocol

### Build Exercise: Simplified Yield Splitter
- Implement basic PT/YT splitting from an ERC-4626 vault
- Time-based maturity and redemption
- Simple pricing model (not full AMM)
- Test yield accrual and maturity settlement

---

## 🎯 Module 3 Exercises

**Workspace:** `workspace/src/part3/module3/`

### Exercise 1: Yield Splitter
- Split an ERC-4626 vault token into PT + YT
- Implement maturity date and redemption logic
- YT claims accumulated yield from underlying vault
- PT redeemable 1:1 at maturity
- Test: splitting, yield accrual, redemption, pre/post maturity

### Exercise 2: Fixed Rate Calculator
- Given PT price and time-to-maturity, calculate implied fixed rate
- Given desired fixed rate, calculate required PT price
- Annualization logic for different maturity periods
- Test with realistic scenarios (3-month, 6-month, 1-year maturities)

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding the PT/YT split concept and its financial analogy (zero-coupon bonds)
- Familiarity with Pendle's architecture (SY, PT, YT, custom AMM)
- Ability to reason about implied rates and time decay
- Understanding composability implications (PT as collateral)

**Common interview topics:**
- "Explain how Pendle creates fixed-rate products in DeFi"
- "Why can't you use a standard AMM for PT trading?"
- "What are the risks of buying YT?"
- "How would you price a PT token with 6 months to maturity?"

---

## 📚 Resources

### Production Code
- [Pendle V2 core](https://github.com/pendle-finance/pendle-core-v2-public)
- [Pendle SY implementations](https://github.com/pendle-finance/pendle-core-v2-public/tree/main/contracts/core/StandardizedYield)

### Documentation
- [Pendle docs](https://docs.pendle.finance/)
- [Pendle Academy](https://academy.pendle.finance/)
- [ERC-5115: SY Token Standard](https://eips.ethereum.org/EIPS/eip-5115)

### Further Reading
- [Pendle: How the AMM works](https://docs.pendle.finance/developers/contracts/PendleMarket)
- [Notional Finance (AMM inspiration)](https://docs.notional.finance/)
- [Dan Robinson: The yield protocol](https://research.paradigm.xyz/)

---

**Navigation:** [← Module 2: Perpetuals](2-perpetuals.md) | [Part 3 Overview](README.md) | [Next: Module 4 — DEX Aggregation & Intents →](4-dex-aggregation.md)

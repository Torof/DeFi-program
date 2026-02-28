# Part 3 — Module 3: Yield Tokenization (~3 days)

**Prerequisites:** Part 2 — Modules 2 (AMMs), 7 (Vaults & Yield) + Part 3 Module 1 (Liquid Staking)
**Pattern:** The problem → Core mechanism → Production architecture → AMM design → Strategies → Hands-on
**Builds on:** ERC-4626 share math (P2M7), AMM curve theory (P2M2), accumulator pattern (P3M2), LST exchange rates (P3M1)
**Used by:** Module 9 (Capstone — yield tokenization as collateral source for perpetual exchange)

---

## 📚 Table of Contents

**The Fixed-Rate Problem**
- [Why Yield Tokenization?](#why-yield-tokenization)
- [The Zero-Coupon Bond Analogy](#zero-coupon-bond)

**Core Mechanism: The PT/YT Split**
- [How Splitting Works](#how-splitting-works)
- [Deep Dive: Implied Rate Math](#implied-rate-math)
- [Deep Dive: YT Yield Accumulator](#yt-yield-accumulator)

**ERC-5115: Standardized Yield**
- [SY vs ERC-4626](#sy-vs-erc4626)
- [Exchange Rate Mechanics](#exchange-rate-mechanics)

**Pendle Architecture**
- [System Overview](#pendle-system-overview)
- [YieldContractFactory: Minting PT + YT](#yield-contract-factory)
- [PendleYieldToken: Yield Tracking](#pendle-yield-token)
- [PendlePrincipalToken: Maturity Redemption](#pendle-principal-token)
- [Code Reading Strategy](#code-reading-strategy)

**The Pendle AMM**
- [Why Constant Product Fails for PT](#why-xy-k-fails)
- [Rate-Space Trading: The Key Insight](#rate-space-trading)
- [Deep Dive: The AMM Curve](#amm-curve-deep-dive)
- [LP Considerations](#lp-considerations)

**Strategies & Composability**
- [Fixed Income: Buy PT](#strategy-buy-pt)
- [Yield Speculation: Buy YT](#strategy-buy-yt)
- [LP in Pendle Pool](#strategy-lp)
- [PT as Collateral](#pt-as-collateral)
- [The LST + Pendle Pipeline](#lst-pendle-pipeline)

**Wrap Up**
- [DeFi Pattern Connections](#pattern-connections)
- [Job Market Context](#job-market)
- [Module Exercises](#exercises)
- [Summary](#summary)
- [Resources](#resources)

---

## The Fixed-Rate Problem

<a id="why-yield-tokenization"></a>
### 💡 Why Yield Tokenization?

**The problem:** All yield in DeFi is variable. Staking APR fluctuates daily. Aave supply rates change every block. Vault yields swing with market conditions. There is no native way to lock in a fixed rate.

This matters for everyone:
- **Treasuries** need predictable income (DAOs, protocols with runway)
- **Risk-averse users** want staking yield without rate uncertainty
- **Speculators** want leveraged exposure to yield direction
- **Market makers** want to trade yield as a separate asset

Traditional finance solved this decades ago with zero-coupon bonds and interest rate swaps. DeFi had no equivalent — until yield tokenization.

**The solution:** Split any yield-bearing asset into two components:
- **PT (Principal Token)** — claim on the underlying asset at maturity
- **YT (Yield Token)** — claim on all yield generated until maturity

This separation creates a fixed-rate market: buying PT at a discount locks in a known return at maturity, regardless of what happens to variable rates.

```
Traditional Finance               DeFi Equivalent (Pendle)
─────────────────────              ─────────────────────────
Zero-coupon bond         ←→       PT (Principal Token)
Floating-rate note       ←→       YT (Yield Token)
Bond yield               ←→       Implied rate
Maturity date            ←→       Maturity date
Coupon stripping         ←→       Tokenization (splitting)
```

<a id="zero-coupon-bond"></a>
### 🔗 The Zero-Coupon Bond Analogy

A zero-coupon bond pays no interest during its life. You buy it at a discount ($970 for a $1000 face value) and receive $1000 at maturity. The difference IS your return, locked at purchase.

PT works identically:
- Buy 1 PT-wstETH for 0.97 wstETH today
- At maturity, redeem 1 PT for 1 wstETH
- Return: 0.03 / 0.97 = 3.09% for the period (fixed, locked at purchase)
- Variable rates can crash to 0% or spike to 20% — your return is fixed

YT is the complement — it captures whatever variable yield actually materializes:
- Buy 1 YT-wstETH for 0.03 wstETH today
- Until maturity, receive ALL staking yield on 1 wstETH
- If actual yield > 3.09% → profit (you paid 0.03 for more than 0.03 worth of yield)
- If actual yield < 3.09% → loss
- This is leveraged yield exposure: ~33x leverage for 0.03 cost

```
1 wstETH deposited
       │
       ├──→ 1 PT-wstETH (buy at 0.97, redeem at 1.00)
       │         │
       │         └──→ Fixed 3.09% return ← buyer locks this in
       │
       └──→ 1 YT-wstETH (buy at 0.03, receive variable yield)
                 │
                 └──→ Variable staking yield ← speculator bets on direction
                      (could be 2%, 5%, 10%...)

Invariant: PT price + YT price = 1 underlying (arbitrage-enforced)
```

> 💡 **Key insight:** Yield tokenization doesn't create yield — it separates existing yield into fixed and variable components, letting each participant take the side they prefer.

---

## Core Mechanism: The PT/YT Split

<a id="how-splitting-works"></a>
### 💡 How Splitting Works

The mechanism is elegant in its simplicity:

**Minting (splitting):**
1. User deposits 1 yield-bearing token (e.g., 1 wstETH via SY wrapper)
2. Contract mints 1 PT + 1 YT, both with the same maturity date
3. The yield-bearing token stays locked in the contract

**Before maturity:**
- PT trades at a discount (< 1 underlying) — the discount IS the implied fixed rate
- YT has positive value — it represents remaining yield entitlement
- Users can "unsplit": return 1 PT + 1 YT → get back 1 yield-bearing token

**At maturity:**
- PT is redeemable 1:1 for the underlying
- YT stops accruing yield and becomes worthless (value → 0)
- The "unsplit" option is no longer needed

**After maturity:**
- PT can still be redeemed for 1 underlying (no expiry on redemption)
- Any unclaimed YT yield can still be collected

```
Timeline for PT-wstETH (6-month maturity):

Time ──────────────────────────────────────────────→

T=0 (Mint)           T=3mo                 T=6mo (Maturity)
PT price: 0.970      PT price: 0.985       PT price: 1.000
YT price: 0.030      YT price: 0.010       YT price: 0.000
                                            │
                                            ├── PT redeemable for 1 wstETH
                                            └── YT has paid out all yield
                                                (worthless now)

Sum always = 1.000   Sum always = 1.000    Sum = 1.000
```

> 💡 **Time decay:** YT loses value as maturity approaches because there's less time remaining to earn yield. This is exactly like options time decay (theta). The yield that hasn't been earned yet decreases as the earning window shrinks.

<a id="implied-rate-math"></a>
### 🔍 Deep Dive: Implied Rate Math

The implied rate is the annualized fixed return you lock in by buying PT at a discount. Understanding this math is fundamental to yield tokenization.

**The basic relationship:**
- PT trades at a discount to the underlying
- At maturity, PT = 1 underlying
- The return = (1 - ptPrice) / ptPrice for the remaining period
- Annualize to get the implied rate

**Simple compounding formula (used in most DeFi implementations):**

```
                     (1 - ptPrice)     YEAR
impliedRate =  ─────────────────  ×  ──────────────────
                     ptPrice          timeToMaturity

Or equivalently:

                  1                          YEAR
impliedRate = ( ─────── - 1 )  ×  ──────────────────
                ptPrice              timeToMaturity
```

**Step-by-step example:**

```
Given:
  PT price     = 0.97 underlying (3% discount)
  Maturity     = 6 months (182.5 days)

Step 1: Period return
  periodReturn = (1 - 0.97) / 0.97
               = 0.03 / 0.97
               = 0.03093 (3.09% for 6 months)

Step 2: Annualize
  impliedRate  = 0.03093 × (365 / 182.5)
               = 0.03093 × 2.0
               = 0.06186 (6.19% annual)

Verification: if you invest 0.97 at 6.19% for 6 months:
  0.97 × (1 + 0.0619 × 182.5/365) = 0.97 × 1.03093 = 1.0 ✓
```

**The inverse — PT price from a target rate:**

```
                          YEAR
ptPrice =  ───────────────────────────────────────
            YEAR + (impliedRate × timeToMaturity)

Example: What PT price gives a 5% annual rate with 3 months to maturity?

ptPrice = 365 / (365 + 0.05 × 91.25)
        = 365 / 369.5625
        = 0.98766

Check: (1 - 0.98766) / 0.98766 × 365/91.25 = 0.01249 × 4.0 = 5.0% ✓
```

**In Solidity (18-decimal fixed-point):**

```solidity
uint256 constant WAD = 1e18;
uint256 constant SECONDS_PER_YEAR = 365 days; // 31_536_000

/// @notice Calculate implied annual rate from PT price and time to maturity.
/// @param ptPriceWad PT price in WAD (e.g., 0.97e18)
/// @param timeToMaturity Seconds until maturity
function getImpliedRate(uint256 ptPriceWad, uint256 timeToMaturity)
    public pure returns (uint256)
{
    // rate = (WAD - ptPrice) * YEAR / (ptPrice * timeToMaturity / WAD)
    // Rearranged to avoid overflow:
    // rate = (WAD - ptPrice) * YEAR * WAD / (ptPrice * timeToMaturity)
    return (WAD - ptPriceWad) * SECONDS_PER_YEAR * WAD
           / (ptPriceWad * timeToMaturity);
}
```

💻 **Quick Try:**

Deploy this in [Remix](https://remix.ethereum.org/) to build intuition for PT pricing:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PTCalculator {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;

    /// @notice PT price → implied annual rate
    function getRate(uint256 ptPrice, uint256 timeToMaturity) external pure returns (uint256) {
        return (WAD - ptPrice) * YEAR * WAD / (ptPrice * timeToMaturity);
    }

    /// @notice Target annual rate → PT fair price
    function getPrice(uint256 annualRate, uint256 timeToMaturity) external pure returns (uint256) {
        return YEAR * WAD / (YEAR + annualRate * timeToMaturity / WAD);
    }
}
```

Deploy and try:
- `getRate(0.97e18, 182.5 days)` → should return ~6.19% (`0.0619e18`)
- `getPrice(0.05e18, 91.25 days)` → should return ~0.9877e18 (PT at 5% with 3 months left)
- `getRate(0.9999e18, 1 days)` → see how even a tiny discount implies a big annualized rate
- Try `getPrice(0.05e18, 1 days)` → PT price ≈ 0.99986e18 (nearly 1.0 — convergence!)

This is the math that drives every Pendle market. Notice how the same rate produces wildly different prices depending on time to maturity.

**Multiple maturities — same underlying, different rates:**

```
wstETH Yield Tokenization Markets (hypothetical):

Maturity        PT Price    Implied Rate    Interpretation
─────────────   ────────    ────────────    ───────────────────
3 months        0.9876      5.02%           Market expects ~5% staking yield
6 months        0.9700      6.19%           Higher rate = yield might increase
1 year          0.9300      7.53%           Even higher = bullish on staking yield

A rising term structure (short < long) suggests the market expects
yields to increase over time. Sound familiar? It's a yield curve —
the same concept from bond markets, now in DeFi.
```

> 💡 **Continuous compounding note:** Pendle internally uses a continuous compounding model: `ptPrice = e^(-rate × timeToMaturity)`. This requires `ln()` and `exp()` functions in Solidity (Pendle has custom implementations). For exercise purposes, simple compounding is accurate enough for short maturities (< 1 year) and avoids complex math libraries.

<a id="yt-yield-accumulator"></a>
### 🔍 Deep Dive: YT Yield Accumulator — The Pattern Returns

If you completed Module 2's FundingRateEngine exercise, this will feel familiar. The YT yield tracking uses the **exact same accumulator pattern** — a global counter that grows over time, with per-user snapshots at entry.

**The pattern across DeFi:**

```
Protocol            Global Accumulator          Per-User Snapshot
────────────────    ──────────────────────      ──────────────────────
Compound            borrowIndex                 borrowIndex at borrow
Aave                liquidityIndex              userIndex at deposit
ERC-4626            share price (assets/shares) shares at deposit
Module 2 (Perps)    cumulativeFundingPerUnit    entryFundingIndex
Pendle (YT)         pyIndex (yield index)       userIndex at purchase
```

**How YT yield tracking works:**

The yield-bearing token's exchange rate naturally increases over time (that's what "yield-bearing" means). This exchange rate IS the accumulator:

```
Time        Exchange Rate       Yield Accrued (per unit)
────        ──────────────      ────────────────────────
T=0         1.000               —
T=1mo       1.004               0.4% (1 month of staking yield)
T=2mo       1.008               0.8%
T=3mo       1.013               1.3%
T=6mo       1.027               2.7%

The exchange rate only goes up. Each snapshot lets us compute
the yield earned between any two points in time.
```

**Per-user yield calculation:**

```
Alice buys YT when exchange rate = 1.004 (T=1mo)
  → entryRate = 1.004

At T=4mo, exchange rate = 1.017
  → yield per unit = (1.017 - 1.004) / 1.004 = 0.01295 = 1.29%
  → For 100 YT: yield = 100 × 0.01295 = 1.295 underlying

Bob buys YT when exchange rate = 1.013 (T=3mo)
  → entryRate = 1.013

At T=4mo, exchange rate = 1.017
  → yield per unit = (1.017 - 1.013) / 1.013 = 0.00395 = 0.39%
  → For 100 YT: yield = 100 × 0.00395 = 0.395 underlying

Each user's yield depends on WHEN they entered — captured by their
snapshot of the exchange rate. O(1) per calculation, no iteration.
```

**In Solidity:**

```solidity
// The vault exchange rate IS the yield accumulator
// No separate index needed — it's already there!

function getAccruedYield(address user) public view returns (uint256) {
    Position memory pos = positions[user];
    uint256 currentRate = vault.convertToAssets(1e18); // current exchange rate

    // yield = ytBalance × (currentRate - entryRate) / entryRate
    // This is: how much each unit has grown since user's entry
    uint256 yieldPerUnit = (currentRate - pos.entryRate) * WAD / pos.entryRate;
    return pos.ytBalance * yieldPerUnit / WAD;
}
```

> 💡 **The insight:** In Module 2's FundingRateEngine, you built the accumulator from scratch (computing rate × time, accumulating it). Here, the vault's exchange rate IS the accumulator — it's already maintained by the underlying protocol (Lido, Aave, etc.). YT yield tracking simply snapshots this existing accumulator. Same pattern, different source.

**What happens to the locked shares?**

When yield is claimed from YT, the contract needs to pay out actual tokens. The math works elegantly:

```
At tokenization:
  100 vault shares deposited (rate = 1.0)
  → 100 underlying worth of principal (PT claim)
  → 100 underlying worth of yield entitlement (YT claim)
  → Contract holds: 100 shares

Later (rate = 1.05):
  100 shares now worth 105 underlying
  PT claim: 100 underlying = 100/1.05 = 95.24 shares
  YT yield: 5 underlying = 5/1.05 = 4.76 shares
  Total: 95.24 + 4.76 = 100 shares ✓

The yield comes from the shares becoming MORE valuable.
Fewer shares are needed to cover the fixed principal,
and the "excess" shares fund the yield payout.
```

---

## ERC-5115: Standardized Yield

<a id="sy-vs-erc4626"></a>
### 💡 SY vs ERC-4626

Pendle introduced [ERC-5115](https://eips.ethereum.org/EIPS/eip-5115) (Standardized Yield) because ERC-4626 wasn't general enough for all yield sources.

**ERC-4626 limitations:**
- Requires a single underlying `asset()` for deposit/withdraw
- Assumes the vault IS the yield source
- Some yield-bearing tokens don't fit the vault model (e.g., stETH rebases, GLP has custom minting)

**ERC-5115 (SY) extends this:**
- Supports **multiple input tokens** (deposit with ETH, stETH, or wstETH → same SY)
- Supports **multiple output tokens** (redeem to ETH or wstETH)
- Works with any yield-bearing token regardless of its native interface
- Standard `exchangeRate()` function for yield tracking

```
ERC-4626 (Vault):                    ERC-5115 (SY):
─────────────────                    ─────────────────
One asset in/out                     Multiple tokens in/out
deposit(assets) → shares             deposit(tokenIn, amount) → syAmount
redeem(shares) → assets              redeem(tokenOut, syAmount) → amount
asset() → address                    yieldToken() → address
convertToAssets(shares)              exchangeRate() → uint256

Example: SY-wstETH accepts:
  ├── ETH    (auto-stakes via Lido)
  ├── stETH  (wraps to wstETH)
  └── wstETH (direct wrap)
  All produce the same SY-wstETH token.
```

**Why SY matters for developers:**
- SY is the universal adapter layer — write one integration, support any yield source
- All PT/YT markets are denominated in SY, not the raw yield token
- `exchangeRate()` is the single function that drives the entire yield tokenization math

<a id="exchange-rate-mechanics"></a>
### 🔍 Exchange Rate Mechanics

The SY exchange rate is the foundation of all yield calculations:

```solidity
// SY-wstETH exchange rate example
function exchangeRate() external view returns (uint256) {
    // 1 SY = how much underlying?
    // For wstETH: returns stETH per wstETH (increases over time)
    return IWstETH(wstETH).stEthPerToken(); // e.g., 1.156e18
}
```

The exchange rate ONLY increases (for non-rebasing tokens). This monotonic growth is what makes it a natural accumulator. Note the contrast with Module 2's `cumulativeFundingPerUnit`, which can move in both directions (positive during net-long skew, negative during net-short). The exchange rate is strictly monotonic — a simpler accumulator that never reverses.

```
SY-wstETH Exchange Rate Over Time:

Rate
1.20 │                                          ╱
1.18 │                                      ╱──╱
1.16 │                                 ╱──╱─
1.14 │                            ╱──╱─
1.12 │                       ╱──╱─
1.10 │                  ╱──╱─
1.08 │             ╱──╱─
1.06 │        ╱──╱─
1.04 │   ╱──╱─
1.02 │╱─╱─
1.00 │─
     └──────────────────────────────────────────→ Time
     T=0    3mo    6mo    9mo    12mo   15mo

Each point on this curve is a "snapshot" opportunity.
YT yield = the vertical distance between entry and exit.
```

---

## Pendle Architecture

<a id="pendle-system-overview"></a>
### 💡 System Overview

Pendle V2 (current version) has a clean layered architecture:

```
User Layer:         PendleRouter (single entry point)
                         │
                    ┌────┴────┐
                    │         │
Split Layer:   YieldContractFactory    PendleMarket (AMM)
                    │                       │
                ┌───┴───┐              ┌────┴────┐
                │       │              │         │
Token Layer:   PT      YT             PT        SY
                │       │              │         │
                └───┬───┘              └────┬────┘
                    │                       │
Yield Layer:       SY (ERC-5115 wrapper)    │
                    │                       │
                    └───────────────────────┘
                              │
Raw Asset:            Yield-bearing token
                    (wstETH, aUSDC, sDAI...)
```

**The flow:**
1. User deposits yield-bearing token → SY wrapper creates SY token
2. SY token → YieldContractFactory splits into PT + YT (same maturity)
3. PT trades against SY in the PendleMarket (AMM)
4. YT accrues yield from the underlying via the SY exchange rate
5. At maturity: PT redeemable for SY → unwrap to yield-bearing token

<a id="yield-contract-factory"></a>
### 🏗️ YieldContractFactory: Minting PT + YT

The factory creates PT/YT pairs for each (SY, maturity) combination:

```solidity
// Simplified from Pendle's YieldContractFactory
function createYieldContract(address SY, uint256 expiry)
    external returns (address PT, address YT)
{
    // Each (SY, expiry) pair gets exactly one PT and one YT
    // PT address is deterministic (CREATE2)
    PT = _deployPT(SY, expiry);
    YT = _deployYT(SY, expiry, PT);
}
```

**Maturity encoding:** Pendle uses quarterly maturities (March, June, September, December) for major markets. Each maturity creates a separate market with its own implied rate. As one market approaches maturity, liquidity migrates to the next ("rolling" — same as futures markets in TradFi).

<a id="pendle-yield-token"></a>
### 🏗️ PendleYieldToken: Yield Tracking

The YT contract maintains the yield accumulator that we discussed above:

```solidity
// Simplified from PendleYieldToken
contract PendleYieldToken {
    uint256 public pyIndexStored;     // Global: last recorded exchange rate
    mapping(address => uint256) public userIndex; // Per-user: rate at last claim

    function _updateAndDistributeYield(address user) internal {
        uint256 currentIndex = SY.exchangeRate();

        if (currentIndex > pyIndexStored) {
            // Yield has accrued since last global update
            pyIndexStored = currentIndex;
        }

        uint256 userIdx = userIndex[user];
        if (userIdx == 0) userIdx = pyIndexStored; // first interaction

        if (pyIndexStored > userIdx) {
            // User has unclaimed yield
            uint256 yieldPerUnit = (pyIndexStored - userIdx) * WAD / userIdx;
            uint256 yield = balanceOf(user) * yieldPerUnit / WAD;
            // Transfer yield to user...
            userIndex[user] = pyIndexStored;
        }
    }

    // CRITICAL: yield must be settled on every transfer
    function _beforeTokenTransfer(address from, address to, uint256) internal {
        if (from != address(0)) _updateAndDistributeYield(from);
        if (to != address(0)) _updateAndDistributeYield(to);
    }
}
```

> 💡 **Why settle on transfer?** If Alice transfers YT to Bob without settling, the yield Alice earned would incorrectly flow to Bob (his entry index would be lower than it should be). By settling before every transfer, each user's accumulated yield is correctly attributed. This is the same reason Compound settles interest before any borrow/repay operation.

<a id="pendle-principal-token"></a>
### 🏗️ PendlePrincipalToken: Maturity Redemption

PT is simpler — it's essentially a zero-coupon bond token:

```solidity
// Simplified from PendlePrincipalToken
contract PendlePrincipalToken {
    uint256 public expiry;
    address public SY;
    address public YT;

    function redeem(uint256 amount) external {
        require(block.timestamp >= expiry, "Not matured");
        _burn(msg.sender, amount);

        // 1 PT = 1 underlying at maturity
        // Convert to SY amount using current exchange rate
        uint256 syAmount = amount * WAD / SY.exchangeRate();
        SY.transfer(msg.sender, syAmount);
    }
}
```

**Post-maturity behavior:** PT can be redeemed at any time after maturity. There's no penalty for late redemption. However, the PT holder foregoes any yield earned between maturity and redemption — that yield effectively belongs to the protocol or is distributed to other participants.

<a id="code-reading-strategy"></a>
### 📖 Code Reading Strategy for Pendle

**Repository:** [pendle-core-v2-public](https://github.com/pendle-finance/pendle-core-v2-public)

**Reading order:**
1. **Start with SY** — `SYBase.sol` and one concrete implementation (e.g., `SYWstETH.sol`). Understand `exchangeRate()`, `deposit()`, `redeem()`. This is the yield abstraction layer.
2. **Read PT/YT minting** — `YieldContractFactory.sol`. See how `createYieldContract()` deploys PT + YT with deterministic addresses.
3. **Study YT yield tracking** — `PendleYieldToken.sol`. Focus on `pyIndexStored`, `userIndex`, and `_updateAndDistributeYield()`. This is the accumulator.
4. **Trace a swap** — `PendleMarketV7.sol`. Start with `swapExactPtForSy()`. Follow the AMM curve math.
5. **Read the Router** — `PendleRouter.sol`. See how user-facing functions compose the lower-level operations.

**Don't get stuck on:** The AMM curve math internals (`MarketMathCore.sol`). The formulas involve `ln()` and `exp()` approximations that are dense. Understand the CONCEPT (rate-space trading) first, then optionally deep-dive into the math.

**Key test files:** `test/core/Market/` — tests for AMM operations, especially around maturity edge cases.

---

## The Pendle AMM

<a id="why-xy-k-fails"></a>
### 💡 Why Constant Product Fails for PT

Standard AMMs (Uniswap's `x × y = k`) assume the two tokens have an independent, freely floating price relationship. PT breaks this assumption because PT has a **known future value**: at maturity, 1 PT = 1 underlying. Always.

**The problem with x × y = k:**

```
Standard AMM pool: PT / Underlying

At T=0 (6 months to maturity):
  Pool: 1000 PT + 970 underlying (PT at 3% discount)
  Works fine — normal trading, reasonable slippage

At T=5.5 months (2 weeks to maturity):
  PT should trade at ~0.998 (0.2% discount for 2 weeks)
  But x*y=k still allows wide price swings
  A moderate swap could move PT price to 0.95 — absurd for a near-maturity asset

At maturity:
  PT MUST trade at exactly 1.0
  But x*y=k has no concept of time or convergence
  The pool would still allow trades at 0.90 or 1.10
  Massive arbitrage opportunities, broken pricing
```

```
Price
1.10 │
     │
1.05 │                    x*y=k range at maturity
     │                    ┌─────────────┐
1.00 │ · · · · · · · · · ·│· · SHOULD · │· · · · · ← PT = 1.0 here
     │                    │ BE HERE!    │
0.95 │                    └─────────────┘
     │
0.90 │
     └──────────────────────────────────────→ Time
     T=0                               Maturity

Problem: x*y=k doesn't know about maturity.
It allows prices that make no economic sense.
```

> 💡 **Analogy:** Imagine a bond market where the exchange allows a 1-year Treasury to trade at 50 cents on the dollar with 1 day until maturity. No rational market would allow this. But a standard AMM has no mechanism to prevent it.

<a id="rate-space-trading"></a>
### 💡 Rate-Space Trading: The Key Insight

Pendle's AMM (inspired by [Notional Finance](https://docs.notional.finance/)) solves this by trading in **rate space** instead of **price space**.

**The insight:** Instead of asking "what price should PT trade at?", ask "what implied interest rate should the market express?" Then derive the price from the rate.

```
Price-space trading (standard AMM):
  "1 PT costs 0.97 underlying"
  → No concept of time decay
  → Wide price range even near maturity

Rate-space trading (Pendle AMM):
  "The market implies a 6.19% annual rate"
  → Rate naturally has bounded behavior
  → Near maturity, even large rate changes produce tiny price changes
  → At maturity, any finite rate maps to price ≈ 1.0
```

**Why rate-space works:**

```
Rate = 6.19%          Rate = 6.19%           Rate = 6.19%
Time = 6 months       Time = 1 month         Time = 1 day
────────────────      ────────────────       ────────────────
PT price = 0.970      PT price = 0.995       PT price = 0.99983

Same rate, but:
  - 6mo out → 3% price discount (meaningful)
  - 1mo out → 0.5% discount (small)
  - 1 day out → 0.002% discount (negligible)

As maturity approaches, rate-space naturally compresses
the price range toward 1.0. The AMM doesn't need special
logic for convergence — it falls out of the math.
```

<a id="amm-curve-deep-dive"></a>
### 🔍 Deep Dive: The AMM Curve

Pendle's AMM uses a modified logit curve with time-dependent parameters. The pool contains **PT and SY** (not PT and underlying directly).

**Conceptual formula (simplified):**

```
                ln(ptProportion / syProportion)
impliedRate = ──────────────────────────────────── × scalar
                     timeToMaturity

Where:
  ptProportion = ptReserve / totalLiquidity
  syProportion = syReserve / totalLiquidity
  scalar = amplification parameter (like Curve's A)
  timeToMaturity = seconds remaining (decreases over time)
```

**Key properties:**

1. **Time-to-maturity in the denominator:** As maturity approaches, the same reserve change produces a larger rate movement. But since price = f(rate, time), and time is shrinking, the net effect is that price movements get SMALLER. The curve "flattens" near maturity.

2. **Scalar (amplification):** Controls rate sensitivity. Higher scalar → more concentrated liquidity around the current rate → lower slippage for normal trades, but larger slippage for rate-moving trades. Similar to Curve Finance's A parameter.

3. **Anchor rate:** The initial implied rate at pool creation. The curve is centered around this rate. LPs implicitly express a view on rates by providing liquidity.

```
Pendle AMM Curve at Different Times to Maturity:

PT Price
  │
1.000 │·········································╱── T=1 day
  │                                        ╱     (very flat, price ≈ 1.0)
0.998 │······························╱───────╱
  │                           ╱─── T=1 month
0.990 │····················╱────────╱          (flatter, price ≈ 0.99)
  │               ╱────╱
0.980 │·········╱────────╱
  │      ╱──╱            T=3 months
0.970 │──╱──╱               (moderate curve)
  │ ╱╱
0.960 │╱    T=6 months
  │     (widest curve)
  └──────────────────────────────────────────→ Pool Imbalance
   More SY          Balanced          More PT

As maturity approaches:
  - Curve FLATTENS (less price sensitivity)
  - Price CONVERGES to 1.0
  - Any finite implied rate maps to PT ≈ 1.0
```

**Comparison with standard AMMs:**

```
Feature              Uniswap V2 (x*y=k)     Curve (StableSwap)     Pendle
─────────────────    ───────────────────     ──────────────────     ──────────────
Curve shape          Hyperbola               Flat near peg          Time-dependent
Time awareness       None                    None                   Built-in
Price convergence    No                      No                     Yes (at maturity)
Rate discovery       No                      No                     Yes
Best for             Independent tokens      Pegged assets          Time-decaying assets
```

<a id="lp-considerations"></a>
### 🏗️ LP Considerations

LPing in Pendle pools has unique properties compared to standard AMMs:

**Impermanent loss dynamics:**
- In standard AMMs, IL is permanent if prices diverge
- In Pendle pools, PT converges to 1.0 at maturity
- This means IL DECREASES over time as the pool naturally rebalances
- LPs in Pendle pools near maturity have almost zero IL

**Triple yield for Pendle LPs:**
1. **Swap fees** — from traders buying/selling PT
2. **PT discount** — the SY side of the pool earns yield from the underlying
3. **Underlying yield** — the PT side also implicitly earns (it converges to 1.0)

**When LP is most attractive:**
- High trading volume (fees)
- Moderate time to maturity (enough fee income, declining IL)
- Volatile rates (more trading, more fees)

> 💡 **LP convergence insight:** A Pendle LP position held to maturity essentially has zero IL because both sides of the pool converge to the same value (1 SY = 1 PT = 1 underlying). This is unique among AMM designs.

---

## Strategies & Composability

<a id="strategy-buy-pt"></a>
### 💡 Strategy 1: Fixed Income — Buy PT

**Mechanism:** Buy PT at a discount → hold to maturity → redeem at 1:1.

**Worked example:**

```
Scenario: Lock in a fixed staking yield on wstETH

Step 1: Buy 100 PT-wstETH at 0.97 price
  Cost: 97 wstETH

Step 2: Hold until maturity (6 months)

Step 3: Redeem 100 PT for 100 wstETH

Result:
  Paid: 97 wstETH
  Received: 100 wstETH
  Profit: 3 wstETH (3.09% over 6 months = 6.19% annualized)
  Rate locked at purchase — doesn't matter if staking yield drops to 2%
```

**Risk analysis:**
- **Smart contract risk:** Pendle or underlying protocol bug
- **Underlying failure:** If the yield source (e.g., Lido) has a slashing event, PT may not be worth 1.0
- **Opportunity cost:** If rates spike to 20%, you're locked at 6.19%
- **Liquidity risk:** Selling PT before maturity incurs AMM slippage
- **No impermanent loss:** This isn't an LP position — just a buy and hold

**Use cases:** DAO treasury management, yield hedging, risk-off positioning.

<a id="strategy-buy-yt"></a>
### 💡 Strategy 2: Yield Speculation — Buy YT

**Mechanism:** Buy YT → receive all yield on the underlying until maturity.

**Worked example:**

```
Scenario: Bet that wstETH staking yield increases

Step 1: Buy 100 YT-wstETH at 0.03 price
  Cost: 3 wstETH (for yield entitlement on 100 wstETH!)
  → This is ~33x leverage on yield

Step 2: Over 6 months, actual average staking yield = 4.5%

Step 3: Yield received = 100 wstETH × 4.5% × 0.5 year = 2.25 wstETH

Result:
  Cost: 3 wstETH
  Received: 2.25 wstETH
  Loss: 0.75 wstETH

Break-even analysis:
  Need actual yield to equal implied rate: 6.19% annual = 3.09% over 6 months
  Need 100 × 3.09% = 3.09 wstETH in yield to break even on 3 wstETH cost
  Any average yield above ~6.19% annual → profit
```

**The points/airdrop meta:** In 2024, YT became hugely popular for airdrop farming. If an underlying protocol distributes points or airdrops to holders, YT holders receive them (since YT represents yield entitlement). Buying 100 YT for 3 wstETH gives airdrop exposure on 100 wstETH — massive leverage on potential airdrops.

<a id="strategy-lp"></a>
### 💡 Strategy 3: LP in Pendle Pool

LPing in Pendle pools provides exposure to both sides with unique IL characteristics:

```
Pendle LP Yield Sources:

1. Swap fees         ← From traders (PT buyers/sellers)
2. SY yield          ← The SY portion of pool earns yield
3. PENDLE rewards    ← Gauge emissions (vePENDLE-boosted)
4. PT convergence    ← IL decreases over time (free yield!)

Total APY can be attractive: 5-15% on stable pools, higher on volatile ones
```

<a id="pt-as-collateral"></a>
### 💡 PT as Collateral

**The insight:** PT has a known minimum value at maturity (1 underlying). This makes it excellent collateral — lenders know exactly what it's worth at a specific date.

**Morpho Blue + Pendle PT:**
- Morpho accepts Pendle PT tokens as collateral for borrowing
- The PT discount provides a built-in safety margin
- Example: Borrow 0.95 USDC against 1 PT-aUSDC (LTV ~97%)
- At maturity, PT = 1.0 → comfortable collateral ratio

**Looping strategy:**
1. Deposit yield-bearing asset → get SY → split to PT + YT
2. Use PT as collateral on Morpho → borrow more underlying
3. Repeat → leveraged fixed-rate exposure

<a id="lst-pendle-pipeline"></a>
### 🔗 The LST + Pendle Pipeline

Combining Module 1 (LSTs) with yield tokenization creates a full-stack yield management system:

```
ETH → Lido → stETH → wrap → wstETH → Pendle SY → PT + YT
 │                                                   │    │
 │                                                   │    └── YT: speculate on
 │                                                   │        staking yield direction
 │                                                   │
 │                                                   └──── PT: lock in fixed
 │                                                         staking yield
 │
 └── Originally earning variable ~3-4% staking yield
     Now separated into fixed and variable components

DeFi composability at its finest:
  - Ethereum staking (L1)
  - Lido (liquid staking)
  - Pendle (yield tokenization)
  - Morpho (lending against PT)
  Each layer adds a new financial primitive.
```

---

## DeFi Pattern Connections

<a id="pattern-connections"></a>
### 🔗 Patterns Across the Curriculum

**The accumulator pattern (3rd appearance):**

| Module | Accumulator | What it tracks | Update trigger |
|--------|-------------|----------------|----------------|
| P2M7 | ERC-4626 share price | Vault yield per share | Deposit/withdraw |
| P3M2 | cumulativeFundingPerUnit | Funding payments per unit | Position open/close |
| **P3M3** | **Exchange rate (pyIndex)** | **Yield per unit of SY** | **YT claim/transfer** |

Each is the SAME mathematical pattern: a global counter that grows, per-user snapshots at entry, delta = amount owed. The only difference is what's being accumulated (vault yield, funding payments, staking yield).

**Time-decaying assets (new pattern):**
- PT value converges to 1.0 at maturity
- Options value decays (theta) as expiry approaches
- Bond price converges to par at maturity
- Any AMM for time-decaying assets needs a time-aware curve

**Fixed rate from variable rate (financial engineering pattern):**
- PT/YT splitting in Pendle
- Interest rate swaps in TradFi
- Notional Finance (fixed-rate lending)
- All achieve the same goal: converting floating exposure to fixed

---

## Job Market Context

<a id="job-market"></a>
### 💼 What DeFi Teams Expect

**1. "Explain how Pendle creates fixed-rate products in DeFi."**

Good answer: "Pendle splits yield-bearing tokens into PT (principal) and YT (yield). PT trades at a discount and can be redeemed at par at maturity, giving buyers a fixed rate."

Great answer: "Pendle wraps yield-bearing tokens into SY (ERC-5115), then splits them into PT and YT with a shared maturity. PT is a zero-coupon bond — buying at a discount locks in a fixed rate calculated as `(1/ptPrice - 1) * year/timeToMaturity`. YT captures variable yield using a global exchange rate accumulator with per-user snapshots, the same O(1) pattern as Compound's borrowIndex. The custom AMM trades in rate-space rather than price-space, which is essential because PT must converge to 1.0 at maturity — something constant-product AMMs can't handle."

**2. "Why can't you use Uniswap's x*y=k AMM for PT trading?"**

Good answer: "PT converges to 1.0 at maturity, and standard AMMs don't account for time."

Great answer: "x*y=k treats both assets as having independent, freely floating prices. PT has a deterministic future value — it equals 1 underlying at maturity. Near maturity, a standard AMM would still allow wide price swings, enabling trades at absurd discounts or premiums. Pendle's AMM operates in rate-space: the curve uses `ln(ptProportion/syProportion) / timeToMaturity * scalar`, which naturally flattens as maturity approaches. This is inspired by Notional Finance's logit curve, and the scalar parameter plays a role analogous to Curve's amplification factor A."

**3. "What are the risks of buying YT?"**

Good answer: "Time decay — YT loses value as maturity approaches. If actual yield is lower than implied, you lose money."

Great answer: "YT is leveraged long yield exposure with time decay. The break-even rate equals the implied rate at purchase — if average actual yield stays below that, YT is unprofitable. Key risks: (1) Time decay — shorter remaining period means less yield to capture, (2) Rate compression — if staking yields fall, YT can lose most of its value rapidly, (3) Smart contract risk on both Pendle and the underlying protocol, (4) Liquidity risk — YT markets are thinner than PT markets, so exiting a position can have high slippage. The leverage works both ways — a small cost buys yield exposure on a large notional, but the maximum loss is 100% of the YT purchase price."

**4. "How does Pendle's YT track yield?"**

Good answer: "It uses the SY exchange rate to calculate accrued yield per holder."

Great answer: "Pendle uses the same accumulator pattern as Compound/Aave. The global `pyIndexStored` tracks the latest SY exchange rate. Each user has a `userIndex` snapshotted at purchase or last claim. Accrued yield is `ytBalance * (pyIndexStored - userIndex) / userIndex` — an O(1) calculation. Critically, YT overrides `_beforeTokenTransfer` to settle yield before any transfer. Without this, transferring YT would incorrectly shift accumulated yield to the recipient. This settlement-on-transfer pattern appears in every token that tracks per-holder rewards."

**5. "How does PT pricing change as maturity approaches?"**

Good answer: "PT price converges to 1.0 as maturity approaches."

Great answer: "Using simple compounding, `ptPrice = year / (year + rate * timeToMaturity)`. As timeToMaturity → 0, ptPrice → 1.0 regardless of the implied rate. Even at a 100% implied rate, with 1 day to maturity, PT trades at 0.99726. This convergence is built into Pendle's AMM curve — the `timeToMaturity` in the denominator of the rate formula means the curve naturally flattens, reducing price sensitivity of swaps. This is why Pendle LPs experience decreasing IL over time, unlike standard AMMs where IL is path-dependent and potentially permanent."

**Interview Red Flags:**
- ❌ Confusing PT and YT roles (which one gives fixed rate?)
- ❌ Not knowing why a standard AMM doesn't work for PT
- ❌ Thinking yield tokenization creates yield (it only separates it)
- ❌ Not understanding the accumulator pattern for YT yield tracking
- ❌ Ignoring time decay when analyzing YT profitability

**Pro tip:** Yield tokenization is one of the most innovative DeFi primitives of 2023-2024, and Pendle's TVL growth reflects this. Understanding it deeply signals you follow cutting-edge DeFi beyond the basics. Bonus points for knowing how PT-as-collateral works in Morpho, and for connecting the accumulator pattern across Compound, Aave, and Pendle.

**Hot topics (2025-2026):**
- Pendle expansion to new yield sources (LRT protocols, RWA yields)
- PT as collateral proliferating across lending protocols
- Institutional adoption of fixed-rate DeFi products
- Competition from Spectra (formerly APWine) and potential new entrants
- ERC-5115 adoption beyond Pendle

---

<a id="exercises"></a>
## 🎯 Module 3 Exercises

**Workspace:** `workspace/src/part3/module3/`

### Exercise 1: YieldTokenizer

**Workspace:**
- Scaffold: `workspace/src/part3/module3/exercise1-yield-tokenizer/YieldTokenizer.sol`
- Tests: `workspace/test/part3/module3/exercise1-yield-tokenizer/YieldTokenizer.t.sol`

Build the core PT/YT splitting mechanism from an ERC-4626 vault:
- Accept vault shares → internally mint PT + YT balances
- Track yield using the vault's exchange rate as the accumulator
- YT holders claim accrued yield (paid out in vault shares)
- PT holders redeem at maturity (principal value in vault shares)
- Before maturity: "unsplit" by burning PT + YT balances

**5 TODOs:** `tokenize()`, `getAccruedYield()`, `claimYield()`, `redeemAtMaturity()`, `redeemBeforeMaturity()`

**🎯 Goal:** Implement the same accumulator pattern from Module 2's FundingRateEngine, but now driven by an external exchange rate instead of an internal calculation.

**Run:** `forge test --match-contract YieldTokenizerTest -vvv`

### Exercise 2: PTRateOracle

**Workspace:**
- Scaffold: `workspace/src/part3/module3/exercise2-pt-rate-oracle/PTRateOracle.sol`
- Tests: `workspace/test/part3/module3/exercise2-pt-rate-oracle/PTRateOracle.t.sol`

Build a rate oracle that computes and tracks implied rates from PT prices:
- Calculate implied annual rate from PT price and time-to-maturity
- Calculate PT fair value from a target annual rate
- Record rate observations with timestamps
- Compute Time-Weighted Average Rate (TWAR) — same accumulator pattern as Uniswap V2's TWAP oracle
- Calculate YT break-even rate for profitability analysis

**5 TODOs:** `getImpliedRate()`, `getPTPrice()`, `recordObservation()`, `getTimeWeightedRate()`, `getYTBreakEven()`

**🎯 Goal:** Master the implied rate math and connect rate-oracle tracking to the TWAP accumulator pattern from Part 2 Module 3 (Oracles).

**Run:** `forge test --match-contract PTRateOracleTest -vvv`

---

<a id="summary"></a>
## 📋 Summary

**✓ Covered:**
- The fixed-rate problem and zero-coupon bond analogy
- PT/YT splitting mechanics and invariant (PT + YT = 1 underlying)
- Implied rate math with worked examples (annualization, inverse formula)
- YT yield accumulator — same O(1) pattern as Compound, Aave, Module 2 funding rate
- ERC-5115 (Standardized Yield) vs ERC-4626
- Pendle architecture: SY → Factory → PT/YT → AMM → Router
- Why x*y=k fails for time-decaying assets
- Rate-space trading and the Pendle AMM curve
- Strategies: fixed income (PT), yield speculation (YT), LP, PT as collateral
- LST + Pendle pipeline (Module 1 integration)

**Key insight:** The accumulator pattern appears for the third time in this curriculum. Whether it's vault share pricing (P2M7), funding rates (P3M2), or yield tracking (P3M3), the math is identical: global growing counter + per-user snapshot + delta = amount owed.

**Next:** [Module 4 — DEX Aggregation & Intents](4-dex-aggregation.md) — how orders get routed across multiple venues for best execution.

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [Pendle V2 Core (GitHub)](https://github.com/pendle-finance/pendle-core-v2-public) — full protocol implementation
- [PendleYieldToken.sol](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/core/YieldContracts/PendleYieldToken.sol) — yield accumulator implementation
- [PendleMarketV7.sol](https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/core/Market/PendleMarketV7.sol) — AMM with rate-space trading

### Standards
- [ERC-5115: Standardized Yield (EIP)](https://eips.ethereum.org/EIPS/eip-5115) — the SY token standard
- [ERC-4626: Tokenized Vault (EIP)](https://eips.ethereum.org/EIPS/eip-4626) — comparison reference

### Documentation
- [Pendle Documentation](https://docs.pendle.finance/) — official protocol docs
- [Pendle Academy](https://academy.pendle.finance/) — educational resources from the team (note: Pendle Academy may have been deprecated or merged into main docs; if the link is dead, see [Pendle Docs](https://docs.pendle.finance/) instead)
- [Notional Finance Docs](https://docs.notional.finance/) — AMM curve inspiration

### Further Reading
- [Pendle Documentation](https://docs.pendle.finance/) — includes AMM curve details (navigate to Developers → Contracts)
- [Dan Robinson & Allan Niemerg: Yield Protocol](https://research.paradigm.xyz/Yield.pdf) — foundational research on yield tokenization

---

**Navigation:** [← Module 2: Perpetuals & Derivatives](2-perpetuals.md) | [Part 3 Overview](README.md) | [Next: Module 4 — DEX Aggregation & Intents →](4-dex-aggregation.md)

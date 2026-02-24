# Part 2 — Module 6: Stablecoins & CDPs

**Duration:** ~4 days (3–4 hours/day)
**Prerequisites:** Modules 1–5 (especially oracles and lending)
**Pattern:** Concept → Read MakerDAO/Sky core contracts → Build simplified CDP → Compare stablecoin designs
**Builds on:** Module 3 (oracle integration for collateral pricing), Module 4 (interest rate models, health factor math, liquidation mechanics)
**Used by:** Module 8 (threat modeling and invariant testing your CDP), Module 9 (integration capstone), Part 3 Module 9 (capstone: multi-collateral stablecoin)

---

## 📚 Table of Contents

**The CDP Model and MakerDAO/Sky Architecture**
- [How CDPs Work](#how-cdps-work)
- [MakerDAO Contract Architecture](#maker-architecture)
  - [Deep Dive: `rpow()` — Exponentiation by Squaring](#how-cdps-work)
- [The Full Flow: Opening a Vault](#opening-vault-flow)
- [Read: Vat.sol](#read-vat)
- [Exercises](#day1-exercises)

**Liquidations, PSM, and DAI Savings Rate**
- [Liquidation 2.0: Dutch Auctions](#liquidation-auctions)
  - [Deep Dive: Dutch Auction Liquidation — Numeric Walkthrough](#liquidation-auctions)
- [Peg Stability Module (PSM)](#psm)
- [Dai Savings Rate (DSR)](#dsr)
- [Read: Dog.sol and Clipper.sol](#read-dog-clipper)
- [Exercises](#day2-exercises)

**Build a Simplified CDP Engine**
- [SimpleCDP.sol](#simple-cdp)

**Stablecoin Landscape and Design Trade-offs**
- [Taxonomy of Stablecoins](#stablecoin-taxonomy)
- [Liquity: A Different CDP Design](#liquity)
  - [Deep Dive: Liquity Redemption — Numeric Walkthrough](#liquity)
- [The Algorithmic Stablecoin Failure Pattern](#algo-failure)
- [Ethena (USDe): The Delta-Neutral Model](#ethena)
- [crvUSD: Curve's Soft-Liquidation Model](#crvusd)
- [The Fundamental Trilemma](#stablecoin-trilemma)
- [Common Mistakes](#common-mistakes)
- [Exercises](#day4-exercises)

---

## 💡 Why Stablecoins Are Different from Lending

On the surface, a CDP (Collateralized Debt Position) looks like a lending protocol — deposit collateral, borrow an asset. But there's a fundamental difference: in a lending protocol, borrowers withdraw *existing* tokens from a pool that suppliers deposited. In a CDP system, the borrowed stablecoin is **minted into existence** when the user opens a position. There are no suppliers. The protocol *is* the issuer.

This changes everything about the design: there's no utilization rate (because there's no supply pool), no supplier interest rate, and the stability of the stablecoin depends entirely on the protocol's ability to maintain the peg through mechanism design — collateral backing, liquidation efficiency, and monetary policy via the stability fee and savings rate.

MakerDAO (now rebranded to Sky Protocol) pioneered CDPs and remains the largest decentralized stablecoin issuer, with over $7.8 billion in DAI + USDS liabilities. Understanding its architecture gives you the template for how on-chain monetary systems work.

---

## The CDP Model and MakerDAO/Sky Architecture

<a id="how-cdps-work"></a>
### 💡 How CDPs Work

The core lifecycle:

1. **Open a Vault.** User selects a collateral type (called an "ilk" — e.g., ETH-A, WBTC-B, USDC-A) and deposits collateral.
2. **Generate DAI/USDS.** User mints stablecoins against the collateral, up to the maximum allowed by the collateral ratio (typically 150%+ for volatile assets). The stablecoins are newly minted — they didn't exist before.
3. **Accrue stability fee.** Interest accrues on the minted DAI, paid in DAI. This is the protocol's revenue.
4. **Repay and close.** User returns the minted DAI plus accrued stability fee. The returned DAI is *burned* (destroyed). User withdraws their collateral.
5. **Liquidation.** If collateral value drops below the liquidation ratio, the Vault is liquidated via auction.

The critical insight: DAI's value comes from the guarantee that every DAI in circulation is backed by more than $1 of collateral, and that the system can liquidate under-collateralized positions to maintain this backing.

<a id="maker-architecture"></a>
### 📖 MakerDAO Contract Architecture

MakerDAO's codebase (called "dss" — Dai Stablecoin System) uses a unique naming convention inherited from formal verification traditions. The core contracts:

**Vat** — The core accounting engine. Stores all Vault state, DAI balances, and collateral balances. Every state-changing operation ultimately modifies the Vat. Think of it as the protocol's ledger.

```
Vat stores:
  Ilk (collateral type): Art (total debt), rate (stability fee accumulator), spot (price with safety margin), line (debt ceiling), dust (minimum debt)
  Urn (individual vault): ink (locked collateral), art (normalized debt)
  dai[address]: internal DAI balance
  sin[address]: system debt (bad debt from liquidations)
```

**Key Vat functions:**
- `frob(ilk, u, v, w, dink, dart)` — The fundamental Vault operation. Modifies collateral (`dink`) and debt (`dart`) simultaneously. This is how users deposit collateral and generate DAI.
- `grab(ilk, u, v, w, dink, dart)` — Seize collateral from a Vault (used in liquidation). Transfers collateral to the liquidation module and creates system debt (`sin`).
- `fold(ilk, u, rate)` — Update the stability fee accumulator for a collateral type. This is how interest accrues globally.
- `heal(rad)` — Cancel equal amounts of DAI and sin (system debt). Used after auctions recover DAI.

**Normalized debt:** The Vat stores `art` (normalized debt), not actual DAI owed. Actual debt = `art × rate`. The `rate` accumulator increases over time based on the stability fee. This is the same index pattern from Module 4 (lending), applied to stability fees instead of borrow rates.

#### 🔍 Deep Dive: MakerDAO Precision Scales (WAD / RAY / RAD)

MakerDAO uses three fixed-point precision scales throughout its codebase. Understanding these is essential for reading any dss code:

```
WAD = 10^18  (18 decimals) — used for token amounts
RAY = 10^27  (27 decimals) — used for rates and ratios
RAD = 10^45  (45 decimals) — used for internal DAI accounting (= WAD × RAY)

Why three scales?
┌──────────────────────────────────────────────────────────┐
│  ink (collateral)  = WAD   e.g., 10.5 ETH = 10.5e18     │
│  art (norm. debt)  = WAD   e.g., 5000 units = 5000e18   │
│  rate (fee accum.) = RAY   e.g., 1.05 = 1.05e27         │
│  spot (price/LR)   = RAY   e.g., $1333 = 1333e27        │
│                                                          │
│  Actual debt = art × rate = WAD × RAY = RAD (10^45)      │
│  Vault check = ink × spot  vs  art × rate                │
│                WAD × RAY      WAD × RAY                  │
│                = RAD           = RAD        ← same scale! │
└──────────────────────────────────────────────────────────┘
```

**Why RAY for rates?** 18 decimals isn't enough precision for per-second compounding. A 5% annual stability fee is ~1.0000000015 per second — you need 27 decimals to represent that accurately.

**Why RAD?** When you multiply a WAD amount by a RAY rate, you get a 45-decimal number. Rather than truncating, the Vat keeps the full precision for internal accounting. External DAI (the [ERC-20](https://eips.ethereum.org/EIPS/eip-20)) uses WAD.

#### 🔍 Deep Dive: Vault Safety Check — Step by Step

Let's trace a real example to understand how the Vat checks if a vault is safe:

```
Scenario: User deposits 10 ETH, mints 15,000 DAI
  ETH price:     $2,000
  Liquidation ratio: 150% (so LR = 1.5)

Step 1: Compute spot (price with safety margin baked in)
  spot = oracle_price / liquidation_ratio
  spot = $2,000 / 1.5 = $1,333.33
  In RAY: 1333.33e27

Step 2: Store vault state
  ink = 10e18  (10 ETH in WAD)
  art = 15000e18  (15,000 normalized debt in WAD)
  rate = 1.0e27  (fresh vault, no fees yet — 1.0 in RAY)

Step 3: Safety check — is ink × spot ≥ art × rate?
  Left side:  10e18 × 1333.33e27 = 13,333.3e45 (RAD)
  Right side: 15000e18 × 1.0e27  = 15,000e45  (RAD)
  13,333 < 15,000 → ❌ UNSAFE! Vault would be rejected.

  The user can only mint up to:
  max_art = ink × spot / rate = 10 × 1333.33 / 1.0 = 13,333 DAI

Step 4: After 1 year with 5% stability fee
  rate increases: 1.0e27 → 1.05e27
  Actual debt: art × rate = 15000 × 1.05 = 15,750 DAI
  (User now owes 750 DAI more in stability fees)

  Safety check with same ink and spot:
  ink × spot = 13,333 (unchanged)
  art × rate = 15000 × 1.05 = 15,750
  Even more unsafe → liquidation trigger!
```

> **🔗 Connection:** This is the same index-based accounting from Module 4 (Aave's liquidity index, Compound's borrow index). The pattern: store a normalized amount, multiply by a growing rate to get the actual amount. No per-user updates needed — only the global rate changes.

**Spot** — The Oracle Security Module (OSM) interface. Computes the collateral price with the safety margin (liquidation ratio) baked in: `spot = oracle_price / liquidation_ratio`. The Vat uses this directly: a Vault is safe if `ink × spot ≥ art × rate`.

**Jug** — The stability fee module. Calls `Vat.fold()` to update the rate accumulator for each collateral type. The stability fee (an annual percentage) is converted to a per-second rate and compounds continuously.

**Dai** — The ERC-20 token contract for external DAI. Internal DAI in the Vat (`dai[]`) is not the same as the ERC-20 token. The **DaiJoin** adapter converts between them.

**Join adapters** — Bridge between external ERC-20 tokens and the Vat's internal accounting:
- `GemJoin` — Locks collateral ERC-20 tokens and credits internal `gem` balance in the Vat
- `DaiJoin` — Converts internal `dai` balance to/from the external DAI ERC-20 token

**CDP Manager** — A convenience layer that lets a single address own multiple Vaults via proxy contracts (UrnHandlers). Without it, one address can only have one Urn per Ilk.

#### 🎓 Intermediate Example: Simplified Vault Accounting

Before diving into the full Vat flow (which uses terse formal-verification naming), let's see the same logic with readable names:

```solidity
// The core CDP check, readable version:
function isSafe(address user) public view returns (bool) {
    uint256 collateralValue = collateralAmount[user] * oraclePrice / PRECISION;
    uint256 debtValue = normalizedDebt[user] * stabilityFeeRate / PRECISION;
    uint256 minCollateral = debtValue * liquidationRatio / PRECISION;
    return collateralValue >= minCollateral;
}

// The Vat does exactly this, but in one line:
//   ink × spot ≥ art × rate
// where spot = oraclePrice / liquidationRatio (safety margin baked in)
```

This is the same check. The Vat just pre-computes `spot = price / LR` so the safety check is a single comparison. Once you see this, the Vat code becomes readable.

<a id="opening-vault-flow"></a>
### The Full Flow: Opening a Vault

1. User calls `GemJoin.join()` — transfers ETH (via WETH) to GemJoin, credits internal `gem` balance in Vat
2. User calls `CdpManager.frob()` (or `Vat.frob()` directly) — locks `gem` as `ink` (collateral) and generates `art` (normalized debt)
3. Vat verifies: `ink × spot ≥ art × rate` (Vault is safe) and total debt ≤ debt ceiling
4. Vat credits `dai` to the user's internal balance
5. User calls `DaiJoin.exit()` — converts internal `dai` to external DAI ERC-20 tokens

💻 **Quick Try:**

On a mainnet fork, read MakerDAO state directly:
```solidity
IVat vat = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
(uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust) = vat.ilks("ETH-A");
// Art = total normalized debt for ETH-A vaults
// rate = stability fee accumulator (starts at 1.0 RAY, grows over time)
// spot = ETH price / liquidation ratio (in RAY)
// Actual total debt = Art * rate (in RAD)
```

Observe that `rate` is > 1.0e27 — that difference from 1.0 represents all accumulated stability fees since ETH-A was created. Every vault's actual debt is `art × rate`.

<a id="read-vat"></a>
### 📖 Read: Vat.sol

**Source:** `dss/src/vat.sol` (github.com/sky-ecosystem/dss)

This is one of the most important contracts in DeFi. Focus on:
- The `frob()` function — understand each check and state modification
- How `spot` encodes the liquidation ratio into the price
- The authorization system (`wards` and `can` mappings)
- The `cage()` function for Emergency Shutdown

The naming convention is terse (derived from formal specification): `ilk` = collateral type, `urn` = vault, `ink` = collateral amount, `art` = normalized debt, `gem` = unlocked collateral, `dai` = stablecoin balance, `sin` = system debt, `tab` = total debt for auction.

#### 📖 How to Study the MakerDAO/dss Codebase

The dss codebase is one of DeFi's most important — and one of the hardest to read due to its terse naming. Here's how to approach it:

1. **Build a glossary first** — Before reading any code, memorize the core terms: `ilk` (collateral type), `urn` (vault), `ink` (locked collateral), `art` (normalized debt), `gem` (free collateral), `dai` (internal stablecoin), `sin` (bad debt), `rad`/`ray`/`wad` (precision scales: 45/27/18 decimals). Write these on a card and keep it visible while reading.

2. **Read `frob()` line by line** — This single function IS the CDP system. It modifies collateral (`dink`) and debt (`dart`) simultaneously. Trace each `require` statement: what's it checking? Map them to: vault safety check (`ink × spot ≥ art × rate`), debt ceiling check (`Art × rate ≤ line`), dust check, and authorization. Understanding `frob()` means understanding the entire protocol.

3. **Trace the authorization system** — `wards` mapping controls admin access. `can` mapping controls who can modify whose vaults. The `wish()` function checks both. This is unusual compared to OpenZeppelin's AccessControl — understand how `hope()` and `nope()` grant/revoke per-user permissions.

4. **Read the Join adapters** — `GemJoin.join()` and `DaiJoin.exit()` are the bridges between external ERC-20 tokens and the Vat's internal accounting. These are short (~30 lines each) and clarify how the internal `gem` and `dai` balances relate to actual token balances.

5. **Study `grab()` and `heal()`** — `grab()` is the forced version of `frob()` used during liquidation — it seizes collateral and creates `sin` (system debt). `heal()` cancels equal amounts of `dai` and `sin`. Together, they form the liquidation and recovery cycle: grab creates bad debt, auctions recover DAI, heal cancels the bad debt.

**Don't get stuck on:** The formal verification annotations in comments. The dss codebase was designed for formal verification (which is why the naming is so terse — it maps to mathematical specifications). You can ignore the verification proofs and focus on the logic.

<a id="day1-exercises"></a>
### 🛠️ Exercises: CDP Model and MakerDAO

**Exercise 1:** On a mainnet fork, trace a complete Vault lifecycle:
- Join WETH as collateral via GemJoin
- Open a Vault via CdpManager, lock collateral, generate DAI via frob
- Read the Vault state from the Vat (ink, art)
- Compute actual debt: `art × rate` (fetch rate from `Vat.ilks(ilk)`)
- Exit DAI via DaiJoin
- Verify you hold the expected DAI ERC-20 balance

**Exercise 2:** Read the Jug contract. Calculate the per-second rate for a 5% annual stability fee. Call `Jug.drip()` on a mainnet fork and verify the rate accumulator updates correctly. Compute how much more DAI a Vault owes after 1 year of accrued fees.

#### 🔍 Deep Dive: Stability Fee Per-Second Rate

A 5% annual fee needs to be converted to a per-second compound rate:

```
Annual rate: 1.05 (5%)
Seconds per year: 365.25 × 24 × 60 × 60 = 31,557,600

Per-second rate = 1.05 ^ (1 / 31,557,600)
               ≈ 1.000000001547125957...

In RAY (27 decimals): 1000000001547125957000000000

Verification: 1.000000001547125957 ^ 31,557,600 ≈ 1.05 ✓

This is stored in Jug as the `duty` parameter per ilk.
Each time drip() is called:
  rate_new = rate_old × (per_second_rate ^ seconds_elapsed)
```

> **🔗 Connection:** This is the same continuous compounding from Module 4 — Aave and Compound use the same per-second rate accumulator for borrow interest. The math is identical; only the context differs (stability fee vs borrow rate).

#### 🔍 Deep Dive: `rpow()` — Exponentiation by Squaring

The Jug needs to compute `per_second_rate ^ seconds_elapsed`. With `seconds_elapsed` potentially being millions (weeks between `drip()` calls), you can't loop. MakerDAO uses **exponentiation by squaring** — an O(log n) algorithm:

```
Goal: compute base^n (in RAY precision)

Standard approach: base × base × base × ... (n multiplications) → O(n) — too expensive

Exponentiation by squaring: O(log n) multiplications
  Key insight: x^10 = x^8 × x^2  (use binary representation of exponent)

Example: 1.000000001547^(604800)  [1 week in seconds]

  604800 in binary = 10010011101010000000

  Step through each bit (right to left):
  bit 0 (0): skip                    base = base²
  bit 1 (0): skip                    base = base²
  ...
  For each '1' bit: result *= current base
  For each bit: base = base × base (square)

  Total: ~20 multiplications instead of 604,800
```

```solidity
// Simplified rpow (MakerDAO's actual implementation in jug.sol):
function rpow(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
    assembly {
        z := base                          // result = 1.0 (in RAY)
        for {} n {} {
            if mod(n, 2) {                 // if lowest bit is 1
                z := div(mul(z, x), base)  // result *= x (RAY multiplication)
            }
            x := div(mul(x, x), base)      // x = x² (square the base)
            n := div(n, 2)                  // shift exponent right
        }
    }
}
// Jug.drip() calls: rpow(duty, elapsed_seconds, RAY)
// where duty = per-second rate (e.g., 1.000000001547... in RAY)
```

**Why assembly?** Two reasons: (1) overflow checks — the intermediate `mul(z, x)` can overflow uint256, and the assembly version handles this via checked division, (2) gas efficiency — this is called frequently and the savings matter.

**Where you'll see this:** Every protocol that compounds per-second rates uses this pattern or a variation. Aave's `MathUtils.calculateCompoundedInterest()` uses a 3-term Taylor approximation instead (see Module 4) — faster but less precise for large exponents.

---

### 📋 Summary: CDP Model and MakerDAO

**✓ Covered:**
- CDP model: mint stablecoins against collateral (not lending from a pool)
- MakerDAO architecture: Vat (accounting), Jug (fees), Join adapters, CDP Manager
- Precision scales: WAD (18), RAY (27), RAD (45) and why each exists
- Vault safety check: `ink × spot ≥ art × rate` with step-by-step example
- Normalized debt and rate accumulator pattern (same as Module 4 lending indexes)
- Code reading strategy for the terse dss codebase

**Next:** Liquidation 2.0 (Dutch auctions), PSM for peg stability, and DSR/SSR for DAI demand

---

## Liquidations, PSM, and DAI Savings Rate

💻 **Quick Try:**

Before studying the liquidation architecture, read live auction state on a mainnet fork:

```solidity
IDog dog = IDog(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
IClipper clipper = IClipper(0xc67963a226eddd77B91aD8c421630A1b0AdFF270); // ETH-A Clipper

// Check if there are any active auctions
uint256 count = clipper.count();
emit log_named_uint("Active ETH-A auctions", count);

// Read the circuit breaker state
(uint256 Art,,, uint256 line,) = IVat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B).ilks("ETH-A");
(, uint256 chop, uint256 hole, uint256 dirt) = dog.ilks("ETH-A");
emit log_named_uint("Liquidation penalty (chop, RAY)", chop); // e.g., 1.13e27 = 13% penalty
emit log_named_uint("Per-ilk auction cap (hole, RAD)", hole);
emit log_named_uint("DAI currently in auctions (dirt, RAD)", dirt);
```

Even if `count` is 0 (no active auctions), you'll see the circuit breaker parameters — `hole` caps how much DAI can be raised simultaneously, preventing the cascade that caused Black Thursday.

<a id="liquidation-auctions"></a>
### 💡 Liquidation 2.0: Dutch Auctions

MakerDAO's original liquidation system (Liquidation 1.2) used English auctions — participants bid DAI in increasing amounts, with capital locked for the duration. This was slow and capital-inefficient, and it catastrophically failed on "Black Thursday" (March 12, 2020) when network congestion prevented liquidation bots from bidding, allowing attackers to win auctions for $0 and causing $8.3 million in bad debt.

#### 🔍 Deep Dive: Black Thursday Timeline (March 12, 2020)

```
Timeline (UTC):
┌─────────────────────────────────────────────────────────────────────────┐
│ 06:00  ETH at ~$193. Markets stable. MakerDAO holds $700M+ in vaults. │
│                                                                         │
│ 08:00  COVID panic sell-off begins. ETH starts sliding.                │
│                                                                         │
│ 10:00  ETH drops below $170. First liquidations trigger.               │
│        ⚠ Ethereum gas prices spike 10-20x (>200 gwei)                 │
│                                                                         │
│ 12:00  ETH hits $130. Massive cascade of vault liquidations.           │
│        ⚠ Network congestion: liquidation bots can't get txs mined     │
│        ⚠ Keeper bids fail with "out of gas" or stuck in mempool       │
│                                                                         │
│ 13:00  KEY MOMENT: Auctions complete with ZERO bids.                   │
│        → Attackers win collateral for 0 DAI                            │
│        → Protocol takes 100% loss on those vaults                      │
│        → English auction requires active bidders — none could bid      │
│                                                                         │
│ 14:00  ETH bottoms near $88. Total of 1,200+ vaults liquidated.       │
│        $8.3 million in DAI left unbacked (bad debt).                   │
│                                                                         │
│ Post-  MakerDAO auctions MKR tokens to cover the deficit.             │
│ crisis Governance votes for Liquidation 2.0 redesign.                  │
│        English auctions → Dutch auctions (no bidders needed)           │
└─────────────────────────────────────────────────────────────────────────┘

Root causes:
  1. English auction REQUIRES competing bidders — no bidders = $0 wins
  2. Network congestion prevented keeper bots from submitting bids
  3. Capital lockup: bids locked DAI for auction duration → less liquidity
  4. No circuit breakers: all liquidations fired simultaneously
```

**Why this matters for protocol designers:** Any mechanism that relies on external participants acting in real-time (bidding, liquidating, updating) can fail when the network is congested — which is exactly when these mechanisms are needed most. This is the "coincidence of needs" problem in DeFi crisis design.

Liquidation 2.0 replaced English auctions with **Dutch auctions**:

**Dog** — The liquidation trigger contract (replaces the old "Cat"). When a Vault is unsafe:
1. Keeper calls `Dog.bark(ilk, urn, kpr)` 
2. Dog calls `Vat.grab()` to seize the Vault's collateral and debt
3. Dog calls `Clipper.kick()` to start a Dutch auction
4. Keeper receives a small incentive (`tip` + `chip` percentage of the tab)

**Clipper** — The Dutch auction contract (one per collateral type). Each auction:
1. Starts at a high price (oracle price × `buf` multiplier, e.g., 120% of oracle price)
2. Price decreases over time according to a price function (`Abacus`)
3. Any participant can call `Clipper.take()` at any time to buy collateral at the current price
4. Instant settlement — no capital lockup, no bidding rounds

**Abacus** — Price decrease functions. Two main types:
- `LinearDecrease` — price drops linearly over time
- `StairstepExponentialDecrease` — price drops in discrete steps (e.g., 1% every 90 seconds)

#### 🔍 Deep Dive: Dutch Auction Price Decrease

```
Price
  │
  │ ●  Starting price = oracle × buf (e.g., 120% of oracle)
  │  \
  │   \  LinearDecrease: straight line to zero
  │    \
  │     \
  │      \        StairstepExponentialDecrease:
  │  ─────●       drops 1% every 90 seconds
  │       │───●
  │            │───●
  │                 │───●
  │                      │───●  ← "cusp" floor (e.g., 40%)
  │ · · · · · · · · · · · · · · · · · ← tail (max duration)
  └───────────────────────────────────────── Time
  0     5min    10min    15min    20min

Liquidator perspective:
  - At t=0: price is ABOVE market → unprofitable, nobody buys
  - Price falls... falls... falls...
  - At some point: price = market price → breakeven
  - Price keeps falling → increasingly profitable
  - Rational liquidator buys when: auction_price × (1 - gas%) > market_price
  - First buyer wins → no gas wars like in English auctions
```

Why Dutch auctions fix Black Thursday:
- **No capital lockup** — buy instantly, no bidding rounds
- **Flash loan compatible** — borrow DAI → buy collateral → sell collateral → repay
- **Natural price discovery** — the falling price finds the market clearing level
- **MEV-compatible** — composable with other DeFi operations (→ Module 5 flash loans)

**Circuit breakers:**
- `tail` — maximum auction duration before reset required
- `cusp` — minimum price (% of starting price) before reset required
- `hole` / `Hole` — maximum total DAI being raised in auctions (per-ilk and global). Prevents runaway liquidation cascades.

The Dutch auction design fixes Black Thursday's problems: no capital lockup means participants can use flash loans, settlement is instant (composable with other DeFi operations), and the decreasing price naturally finds the market clearing level.

#### 🔍 Deep Dive: Dutch Auction Liquidation — Numeric Walkthrough

```
Setup:
  Vault: 10 ETH collateral, 15,000 DAI debt (normalized art = 15,000, rate = 1.0)
  ETH price drops from $2,000 → $1,800
  Liquidation ratio: 150% → spot = $1,800 / 1.5 = $1,200 (RAY)
  Safety check: ink × spot = 10 × $1,200 = $12,000 < art × rate = $15,000 → UNSAFE

Step 1: Keeper calls Dog.bark(ETH-A, vault_owner, keeper_address)
  → Vat.grab() seizes collateral: 10 ETH moved to Clipper, 15,000 DAI of sin created
  → tab (total to recover) = art × rate × chop = 15,000 × 1.0 × 1.13 = 16,950 DAI
    (chop = 1.13 RAY = 13% liquidation penalty)
  → Keeper receives: tip (flat, e.g., 300 DAI) + chip (% of tab, e.g., 0.1% = 16.95 DAI)

Step 2: Clipper.kick() starts Dutch auction
  → Starting price (top) = oracle_price × buf = $1,800 × 1.20 = $2,160 per ETH
    (buf = 1.20 = start 20% above oracle to ensure initial price is above market)
  → lot = 10 ETH (collateral for sale)
  → tab = 16,950 DAI (amount to recover)

Step 3: Price decreases over time (StairstepExponentialDecrease)
  → t=0:    price = $2,160  (above market — nobody buys)
  → t=90s:  price = $2,138  (1% drop per step)
  → t=180s: price = $2,117
  → t=270s: price = $2,096
  → ...
  → t=900s: price = $1,953  (still above market $1,800)
  → t=1800s: price = $1,767  (now BELOW market — profitable!)
    ($2,160 × 0.99^20 = $2,160 × 0.8179 = $1,767)

Step 4: Liquidator calls Clipper.take() at t=1800s (price = $1,767)
  → Liquidator offers: 16,950 DAI (the full tab)
  → Collateral received: 16,950 / $1,767 = 9.59 ETH
  → Remaining: 10 - 9.59 = 0.41 ETH returned to vault owner

  Liquidator P&L (with flash loan from Balancer):
    Received: 9.59 ETH
    Sell on DEX at $1,800: 9.59 × $1,800 = $17,262
    After 0.3% swap fee: $17,262 × 0.997 = $17,210
    Repay flash loan: 16,950 DAI
    Profit: $17,210 - $16,950 = $260
    Gas: ~$10-30
    Net: ~$230-250

  Vault owner outcome:
    Lost: 9.59 ETH ($17,262 at market price)
    Recovered: 0.41 ETH ($738)
    Penalty paid: 9.59 × $1,800 - 15,000 = $2,262 (~15.1% effective penalty)
    → The 13% chop + buying below market price = higher effective cost

  Protocol outcome:
    Recovered: 16,950 DAI (covers 15,000 debt + 1,950 penalty)
    The 1,950 DAI penalty goes to Vow (protocol surplus buffer)
    sin (bad debt) cleared via Vat.heal()
```

**Key insight:** The liquidator doesn't need to wait for the absolute best price — they just need `auction_price < market_price - swap_fees - gas`. The competition between liquidators (and MEV searchers) pushes the buy time earlier, reducing the vault owner's penalty. More competition = better outcomes for everyone except the liquidator margins.

<a id="psm"></a>
### 💡 Peg Stability Module (PSM)

The PSM allows 1:1 swaps between DAI and approved stablecoins (primarily USDC) with a small fee (typically 0%). It serves as the primary peg maintenance mechanism:

- If DAI > $1: Users swap USDC → DAI at 1:1, increasing DAI supply, pushing price down
- If DAI < $1: Users swap DAI → USDC at 1:1, decreasing DAI supply, pushing price up

The PSM is controversial because it makes DAI heavily dependent on USDC (a centralized stablecoin). At various points, over 50% of DAI's backing has been USDC through the PSM. This tension — decentralization vs peg stability — is one of the fundamental challenges in stablecoin design.

**Contract architecture:** The PSM is essentially a special Vault type that accepts USDC (or other stablecoins) as collateral at a 100% collateral ratio and auto-generates DAI. The `tin` (fee in) and `tout` (fee out) parameters control the swap fees in each direction.

<a id="dsr"></a>
### 💡 Dai Savings Rate (DSR)

The DSR lets DAI holders earn interest by locking DAI in the `Pot` contract. The interest comes from stability fees paid by Vault owners — it's a mechanism to increase DAI demand (and thus support the peg) by making holding DAI attractive.

**Pot contract:** Users call `Pot.join()` to lock DAI and `Pot.exit()` to withdraw. Accumulated interest is tracked via a rate accumulator (same pattern as stability fees). The DSR is set by governance as a monetary policy tool.

**Sky Savings Rate (SSR):** The Sky rebrand introduced a parallel savings rate for USDS using an [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault (sUSDS). This is significant because ERC-4626 is the standard vault interface — meaning sUSDS is natively composable with any protocol that supports ERC-4626.

### 💡 The Sky Rebrand: What Changed

In September 2024, MakerDAO rebranded to Sky Protocol. Key changes:
- DAI → USDS (1:1 convertible, both remain active)
- MKR → SKY (1:24,000 conversion ratio)
- SubDAOs → "Stars" (Spark Protocol is the first Star — a lending protocol built on top of Sky)
- USDS adds a freeze function for compliance purposes (controversial in the community)
- SSR uses ERC-4626 standard

The underlying protocol mechanics (Vat, Dog, Clipper, etc.) remain the same. For this module, we'll use the original MakerDAO naming since that's what the codebase uses.

<a id="read-dog-clipper"></a>
### 📖 Read: Dog.sol and Clipper.sol

**Source:** `dss/src/dog.sol` and `dss/src/clip.sol`

In `Dog.bark()`, trace:
- How the Vault is validated as unsafe
- The `grab` call that seizes collateral
- How the `tab` (debt + liquidation penalty) is calculated
- The circuit breaker checks (`Hole`/`hole`, `Dirt`/`dirt`)

In `Clipper.kick()`, trace:
- How the starting price is set (oracle price × buf)
- The auction state struct
- How `take()` works: price calculation via Abacus, partial fills, refunds

#### 📖 How to Study MakerDAO Liquidation 2.0

1. **Start with `Dog.bark()`** — This is the entry point. Trace: how does it verify the vault is unsafe? (Calls `Vat.urns()` and `Vat.ilks()`, checks `ink × spot < art × rate`.) How does it call `Vat.grab()` to seize collateral? How does it compute the `tab` (total debt including penalty)?

2. **Read `Clipper.kick()`** — After `bark()` seizes collateral, `kick()` starts the auction. Focus on: how `top` (starting price) is computed as `oracle_price × buf`, how the auction struct stores the state, and how the keeper incentive (`tip` + `chip`) is calculated and paid.

3. **Understand the Abacus price functions** — Read `LinearDecrease` first (simpler: price drops linearly over time). Then read `StairstepExponentialDecrease` (price drops in discrete steps). The key question: given a `tab` (debt to cover) and the current auction price, how much collateral does the `take()` caller receive?

4. **Trace a complete `take()` call** — This is where collateral is actually sold. Follow: price lookup via Abacus → compute collateral amount for the DAI offered → handle partial fills (buyer wants less than the full lot) → refund excess collateral to the vault owner → cancel `sin` via `Vat.heal()`.

5. **Study the circuit breakers** — `tail` (max auction duration), `cusp` (min price before reset), `Hole`/`hole` (max simultaneous DAI in auctions). These exist because of Black Thursday — without caps, a cascade of liquidations can overwhelm the system.

**Don't get stuck on:** The `redo()` function initially — it's for restarting stale auctions. Understand `bark()` → `kick()` → `take()` first, then come back to `redo()` and the edge cases.

<a id="day2-exercises"></a>
### 🛠️ Exercises: Liquidations and PSM

**Exercise 1:** On a mainnet fork, simulate a liquidation:
- Open a Vault with ETH collateral near the liquidation ratio
- Mock the oracle to drop the price below the liquidation threshold
- Call `Dog.bark()` to start the auction
- Call `Clipper.take()` to buy the collateral at the current auction price
- Verify: correct amount of DAI paid, correct collateral received, debt cleared

**Exercise 2:** Read the PSM contract. Execute a USDC → DAI swap through the PSM on a mainnet fork. Verify the 1:1 conversion and fee application.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Why did MakerDAO switch from English to Dutch auctions?"**
   - Good answer: English auctions were slow and required capital lockup
   - Great answer: Black Thursday proved English auctions fail under network congestion — bots couldn't bid, allowing $0 wins and $8.3M bad debt. Dutch auctions fix this: instant settlement, flash-loan compatible, no bidding rounds. The falling price naturally finds the market clearing level.

2. **"What's the trade-off of the PSM?"**
   - Good answer: It stabilizes the peg but makes DAI dependent on USDC
   - Great answer: The PSM creates a hard peg floor/ceiling but at the cost of centralization — at peak, >50% of DAI was backed by USDC through the PSM. This is the stablecoin trilemma in action: DAI chose stability over decentralization. The Sky rebrand introduced USDS with a freeze function, pushing further toward the centralized end.

**Interview Red Flags:**
- 🚩 Not knowing how CDPs differ from lending (minting vs redistributing)
- 🚩 Confusing normalized debt (`art`) with actual debt (`art × rate`)
- 🚩 Thinking liquidation auctions are the same as in traditional finance

**Pro tip:** If you can trace a `frob()` call through the Vat's safety checks and explain each parameter, you demonstrate deeper protocol knowledge than 95% of DeFi developers. MakerDAO's architecture shows up directly in interview questions at top DeFi teams.

---

### 📋 Summary: Liquidations, PSM, and DSR

**✓ Covered:**
- Liquidation 2.0: Dutch auctions (Dog + Clipper), why they replaced English auctions
- Auction price functions: LinearDecrease vs StairstepExponentialDecrease
- Circuit breakers: tail, cusp, Hole/hole — preventing liquidation cascades
- PSM: 1:1 peg stability, centralization trade-off, tin/tout fees
- DSR/SSR: demand-side lever for peg maintenance
- Sky rebrand: DAI→USDS, MKR→SKY, sUSDS as ERC-4626

**Next:** Building a simplified CDP engine from scratch

---

## Build a Simplified CDP Engine

<a id="simple-cdp"></a>
### 🛠️ SimpleCDP.sol

Build a minimal CDP system that captures the essential mechanisms:

**Core contracts:**

**SimpleVat.sol** — The accounting engine:
```solidity
struct Ilk {
    uint256 Art;    // total normalized debt
    uint256 rate;   // stability fee accumulator (RAY)
    uint256 spot;   // price with safety margin (RAY)
    uint256 line;   // debt ceiling (RAD)
    uint256 dust;   // minimum debt (RAD)
}

struct Urn {
    uint256 ink;    // locked collateral (WAD)
    uint256 art;    // normalized debt (WAD)
}

mapping(bytes32 => Ilk) public ilks;
mapping(bytes32 => mapping(address => Urn)) public urns;
mapping(address => uint256) public dai;   // internal stablecoin balance
uint256 public debt;  // total system debt
uint256 public Line;  // global debt ceiling
```

**Functions:**
- `frob(ilk, dink, dart)` — lock/unlock collateral and generate/repay stablecoins. Check: vault remains safe, debt ceiling not exceeded, minimum debt met.
- `fold(ilk, rate)` — update stability fee accumulator. Called by the Jug equivalent.
- `grab(ilk, u, v, w, dink, dart)` — seize collateral for liquidation.

**SimpleJug.sol** — Stability fee accumulator:
- Stores per-second stability fee rate per ilk
- `drip(ilk)` computes time elapsed since last update, compounds the rate, calls `Vat.fold()`

**SimpleStablecoin.sol** — ERC-20 token with mint/burn controlled by the join adapter.

**SimpleJoin.sol** — Collateral join (lock ERC-20, credit Vat gem) and stablecoin join (convert internal dai ↔ external ERC-20).

**SimpleDog.sol** — Liquidation trigger:
- Check if Vault is unsafe: `ink × spot < art × rate`
- Call `Vat.grab()` to seize collateral
- Start a Dutch auction (simplified: decreasing price over time)

**SimplePSM.sol** — Peg stability module:
- Accept USDC, mint stablecoin 1:1 (with configurable tin/tout fee)
- Accept stablecoin, return USDC 1:1

### Test Suite

- **Full lifecycle:** join collateral → frob (lock + generate) → transfer stablecoin → frob (repay + unlock) → exit collateral
- **Stability fee accrual:** open vault, warp 1 year, verify debt increased by stability fee %
- **Liquidation:** open vault, drop oracle price, trigger liquidation, buy collateral at auction, verify debt cleared
- **Debt ceiling:** attempt to generate stablecoins beyond the ceiling, verify revert
- **Dust check:** attempt to leave a vault with debt below the dust threshold, verify revert
- **PSM peg arbitrage:** when stablecoin trades above $1, show how PSM swap creates profit; when below $1, show the reverse
- **Multi-collateral:** support two collateral types with different stability fees and liquidation ratios

---

### 📋 Summary: SimpleCDP

**✓ Covered:**
- Building the core CDP contracts: SimpleVat, SimpleJug, SimpleDog, SimplePSM
- Implementing the vault safety check, stability fee accumulator, and liquidation trigger
- Testing: full lifecycle, fee accrual, liquidation, debt ceiling, dust check, multi-collateral

**Next:** Comparing stablecoin designs across the landscape — overcollateralized, algorithmic, delta-neutral

---

## Stablecoin Landscape and Design Trade-offs

<a id="stablecoin-taxonomy"></a>
### 💡 Taxonomy of Stablecoins

**1. Fiat-backed (USDC, USDT)** — Centralized issuer holds bank deposits or T-bills equal to the stablecoin supply. Simple, stable, but requires trust in the issuer and is subject to censorship (addresses can be blacklisted).

**2. Overcollateralized crypto-backed (DAI/USDS, LUSD)** — Protocol holds >100% crypto collateral. Decentralized and censorship-resistant (depending on collateral composition), but capital-inefficient (you need $150+ of ETH to mint $100 of stablecoins).

**3. Algorithmic (historical: UST/LUNA, FRAX, ESD, BAC)** — Attempt to maintain peg through algorithmic supply adjustment without full collateral backing. Most have failed catastrophically.

**4. Delta-neutral / yield-bearing (USDe by Ethena)** — Holds crypto collateral and hedges price exposure using perpetual futures short positions. The yield comes from positive funding rates. Novel design but carries exchange counterparty risk and funding rate reversal risk.

<a id="liquity"></a>
### 💡 Liquity: A Different CDP Design

Liquity (LUSD) takes a minimalist approach compared to MakerDAO:

**Key differences from MakerDAO:**
- **No governance.** Parameters are immutable once deployed. No governance token, no parameter changes.
- **One-time fee instead of ongoing stability fee.** Users pay a fee at borrowing time (0.5%–5%, adjusted algorithmically based on redemption activity). No interest accrues.
- **110% minimum collateral ratio.** Much more capital-efficient than MakerDAO's typical 150%+.
- **ETH-only collateral.** No multi-collateral complexity.
- **Redemption mechanism:** Any LUSD holder can redeem LUSD for $1 worth of ETH from the riskiest Vault (lowest collateral ratio). This creates a hard price floor.
- **Stability Pool:** LUSD holders can deposit into the Stability Pool, which automatically absorbs liquidated collateral at a discount. No auction needed — liquidation is instant.

**Liquity V2 (2024-25):** Introduces user-set interest rates (borrowers bid their own rate), multi-collateral support (LSTs like wstETH, rETH), and a modified redemption mechanism.

#### 🔍 Deep Dive: Liquity Redemption — Numeric Walkthrough

```
Scenario: LUSD trades at $0.97 on DEXes. An arbitrageur spots the opportunity.

System state — all active Troves, sorted by collateral ratio (ascending):
  Trove A: 2 ETH collateral, 2,800 LUSD debt → CR = (2 × $2,000) / 2,800 = 142.8%
  Trove B: 3 ETH collateral, 3,500 LUSD debt → CR = (3 × $2,000) / 3,500 = 171.4%
  Trove C: 5 ETH collateral, 4,000 LUSD debt → CR = (5 × $2,000) / 4,000 = 250.0%

Step 1: Arbitrageur buys 3,000 LUSD on DEX at $0.97
  Cost: 3,000 × $0.97 = $2,910

Step 2: Call redeemCollateral(3,000 LUSD)
  System starts with the RISKIEST Trove (lowest CR = Trove A)

  → Trove A: has 2,800 LUSD debt
    Redeem 2,800 LUSD → receive $2,800 worth of ETH = 2,800 / $2,000 = 1.4 ETH
    Trove A: CLOSED (0 debt, 0.6 ETH returned to Trove A owner)
    Remaining to redeem: 3,000 - 2,800 = 200 LUSD

  → Trove B: has 3,500 LUSD debt (next riskiest)
    Redeem 200 LUSD → receive $200 worth of ETH = 200 / $2,000 = 0.1 ETH
    Trove B: debt reduced to 3,300, collateral reduced to 2.9 ETH
    CR now = (2.9 × $2,000) / 3,300 = 175.8% (improved!)
    Remaining: 0 LUSD ✓

Step 3: Redemption fee (0.5% base, increases with volume)
  Fee = 0.5% × 3,000 = 15 LUSD (deducted in ETH: 0.0075 ETH)
  Total ETH received: 1.4 + 0.1 - 0.0075 = 1.4925 ETH

Step 4: Arbitrageur P&L
  Received: 1.4925 ETH × $2,000 = $2,985
  Cost: $2,910 (buying LUSD on DEX)
  Profit: $75 (2.58% return)

  This profit closes the peg gap:
  - 3,000 LUSD bought on DEX → buying pressure → LUSD price rises toward $1
  - 3,000 LUSD burned via redemption → supply decreases → further price support
```

**Why riskiest-first?** It improves system health — the lowest-CR troves pose the most risk. Redemption either closes them or pushes their CR higher. The base fee (0.5%, rising with redemption volume) prevents excessive redemptions that would disrupt healthy vaults.

**The peg guarantee:** Redemptions create a hard floor at ~$1.00 (minus the fee). If LUSD trades at $0.97, anyone can profit by redeeming. This arbitrage force pushes the price back up. The ceiling is softer — at ~$1.10 (the minimum CR), it becomes attractive to open new Troves and sell LUSD.

<a id="algo-failure"></a>
### ⚠️ The Algorithmic Stablecoin Failure Pattern

UST/LUNA (Terra, May 2022) is the canonical example. The mechanism:
- UST was pegged to $1 via an arbitrage loop with LUNA
- When UST > $1: burn $1 of LUNA to mint 1 UST (increase supply, push price down)
- When UST < $1: burn 1 UST to mint $1 of LUNA (decrease supply, push price up)

The death spiral: when confidence in UST dropped, holders rushed to redeem UST for LUNA. Massive LUNA minting cratered LUNA's price, which reduced the backing for UST, causing more redemptions, more LUNA minting, more price collapse. $40+ billion in value was destroyed in days.

**The lesson:** Without external collateral backing, algorithmic stablecoins rely on reflexive confidence. When confidence breaks, there's nothing to stop the spiral. Every algorithmic stablecoin that relies purely on its own governance/seigniorage token for backing has either failed or abandoned that model.

<a id="ethena"></a>
### 💡 Ethena (USDe): The Delta-Neutral Model

Ethena mints USDe against crypto collateral (primarily staked ETH) and simultaneously opens a short perpetual futures position of equal size. The net exposure is zero (delta-neutral), meaning the collateral value doesn't change with ETH price movements.

**How it works:**
1. User deposits stETH (or ETH, which gets staked)
2. Ethena opens an equal-sized short perpetual position on centralized exchanges
3. ETH price goes up → collateral gains, short loses → net zero
4. ETH price goes down → collateral loses, short gains → net zero
5. Revenue: staking yield (~3-4%) + funding rate income (shorts get paid when funding is positive)

**Revenue breakdown:**
- Staking yield: ~3-4% APR (consistent)
- Funding rate: historically ~8-15% APR average, but highly variable
- Combined: sUSDe has offered 15-30%+ APR at times

**Risk factors:**
- **Funding rate reversal:** In bear markets, funding rates go negative (shorts PAY longs). Ethena's insurance fund covers short periods, but prolonged negative funding would erode backing. During the 2022 bear market, funding was negative for months.
- **Exchange counterparty risk:** Positions are on centralized exchanges (Binance, Bybit, Deribit) via custodians (Copper, Ceffu). If an exchange fails or freezes, positions can't be managed.
- **Basis risk:** Spot price and futures price can diverge, creating temporary unbacking.
- **Custodian risk:** Assets held in "off-exchange settlement" custody, not directly on exchanges.
- **Insurance fund:** ~$50M+ reserve for negative funding periods. If depleted, USDe backing degrades.

> **🔗 Connection:** The funding rate mechanics here connect directly to Part 3 Module 2 (Perpetuals), where you'll study how funding rates work in detail. Ethena is essentially using a DeFi primitive (perpetual funding) as a stablecoin backing mechanism.

### 💡 GHO: Aave's Native Stablecoin

GHO is a decentralized stablecoin minted directly within Aave V3. It extends the lending protocol with stablecoin issuance — users who already have collateral in Aave can mint GHO against it without removing their collateral from the lending pool.

**Key design choices:**
- **No separate CDP system** — GHO uses Aave V3's existing collateral and liquidation infrastructure
- **Facilitators** — entities authorized to mint/burn GHO. Aave V3 Pool is the primary facilitator, but others can be added (e.g., a flash mint facilitator)
- **Interest rate is governance-set** — not algorithmic. MakerDAO's stability fee is also governance-set, but Aave's rate doesn't depend on utilization since there's no supply pool
- **stkAAVE discount** — AAVE stakers get a discount on GHO borrow rates (incentivizes AAVE staking)
- **Built on existing battle-tested infrastructure** — Aave's oracle, liquidation, and risk management systems

**Why it matters:** GHO shows how a lending protocol can evolve into a stablecoin issuer without building separate infrastructure. Since you studied Aave V3 in Module 4, GHO is a natural extension of that knowledge.

<a id="crvusd"></a>
### 💡 crvUSD: Curve's Soft-Liquidation Model (LLAMMA)

Curve's stablecoin crvUSD introduces a novel liquidation mechanism called LLAMMA (Lending-Liquidating AMM Algorithm) that replaces the traditional discrete liquidation threshold with continuous soft liquidation.

**How LLAMMA works:**
- Collateral is deposited into a special AMM (not a regular lending pool)
- As collateral price drops, the AMM automatically converts collateral to crvUSD (soft liquidation)
- As price recovers, the AMM converts back from crvUSD to collateral (de-liquidation)
- No sudden liquidation event — instead, a gradual, continuous transition
- Borrower keeps their position throughout (unless price drops too far)

**Why it's novel:**
- Traditional CDPs: price hits threshold → entire position liquidated → penalty applied → user loses collateral
- LLAMMA: price drops → collateral gradually converts → price recovers → collateral converts back
- Reduces liquidation losses for borrowers (no penalty on soft liquidation)
- Reduces bad debt risk for the protocol (continuous adjustment vs sudden cascade)

**Trade-offs:**
- During soft liquidation, the AMM-converted position earns less than holding pure collateral (similar to impermanent loss in an LP position)
- More complex than traditional liquidation — harder to reason about and audit
- LLAMMA pools need liquidity to function properly

> **🔗 Connection:** crvUSD's LLAMMA is essentially an AMM (Module 2) repurposed as a liquidation mechanism (Module 4). It shows how DeFi primitives can be combined in unexpected ways.

### 💡 FRAX: The Evolution from Algorithmic to Fully Backed

FRAX started as a "fractional-algorithmic" stablecoin — partially backed by collateral (USDC) and partially by its governance token (FXS). The collateral ratio would adjust algorithmically based on market conditions.

**The evolution:**
1. **V1 (2020):** Fractional-algorithmic — e.g., 85% USDC + 15% FXS backing
2. **V2 (2022):** Moved toward 100% collateral ratio after algorithmic stablecoins collapsed (Terra)
3. **V3 / frxETH (2023+):** Pivoted to liquid staking (frxETH, sfrxETH) and became fully collateralized

**The lesson:** The algorithmic component was abandoned because it created the same reflexive risk as Terra — when confidence drops, the algorithmic portion amplifies the problem. FRAX's evolution mirrors the industry's consensus: full collateral backing is necessary.

> **🔗 Connection:** frxETH and sfrxETH are liquid staking tokens covered in Part 3 Module 1. FRAX's pivot illustrates how stablecoin protocols evolve toward safety.

### Design Trade-off Matrix

| Property | DAI/USDS | LUSD | GHO | crvUSD | USDe | USDC |
|----------|----------|------|-----|--------|------|------|
| Decentralization | Medium | High | Medium | Medium | Low | Low |
| Capital efficiency | Low (150%+) | Medium (110%) | Low (Aave LTVs) | Medium (soft liq.) | ~1:1 | 1:1 |
| Peg stability | Strong (PSM) | Good (redemptions) | Moderate | Moderate | Good | Very strong |
| Yield | DSR/SSR | None | Discount for stkAAVE | None | High (15%+) | None |
| Liquidation | Dutch auction | Stability Pool | Aave standard | Soft (LLAMMA) | N/A | N/A |
| Failure mode | Bad debt, USDC dep. | Bad debt | Same as Aave | LLAMMA IL | Funding reversal | Regulatory |

<a id="stablecoin-trilemma"></a>
### 💡 The Fundamental Trilemma

Stablecoins face a trilemma between:
1. **Decentralization** — no central point of failure or censorship
2. **Capital efficiency** — not requiring significantly more collateral than the stablecoins minted
3. **Peg stability** — maintaining a reliable $1 value

No design achieves all three. DAI sacrifices efficiency for decentralization and stability. USDC sacrifices decentralization for efficiency and stability. Algorithmic designs attempt efficiency and decentralization but sacrifice stability (and typically fail).

Understanding this trilemma is essential for evaluating any stablecoin design you encounter or build.

#### 🔍 Deep Dive: Peg Mechanism Comparison

How does each stablecoin actually maintain its $1 peg? The mechanisms are fundamentally different:

```
                        When price > $1                    When price < $1
                        (too much demand)                  (too much supply)
┌──────────┬───────────────────────────────┬───────────────────────────────────┐
│ DAI/USDS │ PSM: swap USDC → DAI at 1:1  │ PSM: swap DAI → USDC at 1:1     │
│          │ ↑ supply → price falls        │ ↓ supply → price rises          │
│          │ Also: lower stability fee →   │ Also: raise stability fee →     │
│          │ more vaults open → more DAI   │ vaults close → less DAI         │
├──────────┼───────────────────────────────┼───────────────────────────────────┤
│ LUSD     │ Anyone can open vault at 110% │ Redemption: burn 1 LUSD →       │
│          │ cheap to mint → more supply   │ get $1 of ETH from riskiest     │
│          │ (soft ceiling at $1.10)       │ vault (hard floor at $1.00)     │
├──────────┼───────────────────────────────┼───────────────────────────────────┤
│ GHO      │ Governance lowers borrow rate │ Governance raises borrow rate   │
│          │ → more minting → more supply  │ → repayment → less supply      │
│          │ (slower response than PSM)    │ (slower response than PSM)      │
├──────────┼───────────────────────────────┼───────────────────────────────────┤
│ crvUSD   │ Minting via LLAMMA pools     │ PegKeeper contracts buy crvUSD  │
│          │ + PegKeepers sell crvUSD      │ from pools, reducing supply     │
│          │ into Curve pools              │ (automated, no governance)      │
├──────────┼───────────────────────────────┼───────────────────────────────────┤
│ USDe     │ Arbitrage: mint USDe at $1,  │ Arbitrage: buy USDe < $1,       │
│          │ sell at market for > $1       │ redeem for $1 of backing        │
│          │ (requires whitelisting)       │ (requires whitelisting)         │
├──────────┼───────────────────────────────┼───────────────────────────────────┤
│ USDC     │ Circle mints new USDC for $1 │ Circle redeems USDC for $1 bank │
│          │ bank deposit                 │ transfer                        │
│          │ (centralized, instant)       │ (centralized, 1-3 business days)│
└──────────┴───────────────────────────────┴───────────────────────────────────┘

Speed of peg restoration:
  USDC ≈ PSM (DAI) > Redemption (LUSD) > PegKeeper (crvUSD) > Arb (USDe) > Governance (GHO)
  ← faster                                                            slower →
```

**The pattern:** Faster peg restoration requires either centralization (USDC, PSM's USDC dependency) or capital lock-up (Liquity's 110% CR). Slower mechanisms preserve decentralization but risk prolonged depegs during stress.

<a id="day4-exercises"></a>
### 🛠️ Exercises: Stablecoin Design Trade-offs

**Exercise 1: Liquity analysis.** Read Liquity's `TroveManager.sol` and `StabilityPool.sol`. Compare the liquidation mechanism (Stability Pool absorption) to MakerDAO's Dutch auctions. Which is simpler? Which handles edge cases better? Write a comparison document.

**Exercise 2: Peg stability simulation.** Using your SimpleCDP from the Build exercise, simulate peg pressure scenarios:
- What happens when collateral prices crash 30%? Model the liquidation volume and its impact.
- What happens when demand for the stablecoin exceeds Vault creation? The price goes above $1. Show how the PSM resolves this.
- What happens if the PSM's USDC reserves are depleted? The stablecoin trades above $1 with no easy correction.

**Exercise 3: Stability fee as monetary policy.** Using your Jug implementation, model how changing the stability fee affects Vault behavior:
- High fee → users repay and close Vaults → stablecoin supply decreases → price pressure upward
- Low fee → users open Vaults → stablecoin supply increases → price pressure downward
- The DSR works in reverse: high DSR → more DAI locked → supply decreases → price up

Map out the feedback loops. This is how decentralized monetary policy works.

#### 💼 Job Market Context — Module-Level Interview Prep

**What DeFi teams expect you to know:**

1. **"Explain the stablecoin trilemma and where DAI sits"**
   - Good answer: DAI trades off capital efficiency for decentralization and stability
   - Great answer: DAI started decentralized (ETH-only collateral) but the PSM made it USDC-dependent for better stability. The Sky rebrand pushed further toward centralization with USDS's freeze function. Liquity V1 sits at the opposite extreme — fully decentralized and immutable, but less capital-efficient and narrower collateral. No design achieves all three.

2. **"How does crvUSD's LLAMMA differ from traditional liquidation?"**
   - Good answer: It gradually converts collateral instead of a sudden liquidation event
   - Great answer: LLAMMA is essentially an AMM where your collateral IS the liquidity. As price drops, the AMM sells your collateral for crvUSD automatically. If price recovers, it buys back. This eliminates the discrete liquidation penalty but introduces AMM-like impermanent loss during soft liquidation. It's a fundamentally different paradigm — continuous adjustment vs threshold-triggered liquidation.

3. **"What's the main risk with Ethena's USDe?"**
   - Good answer: Funding rates can go negative
   - Great answer: Three correlated risks: (1) prolonged negative funding drains the insurance fund and erodes backing, (2) centralized exchange counterparty risk — positions are on Binance/Bybit/Deribit via custodians, (3) during a black swan, all three risks compound simultaneously (funding reversal + exchange stress + basis blowout). The model works great in bull markets with positive funding but hasn't been tested through a severe extended downturn with the current AUM.

**Interview Red Flags:**
- 🚩 Thinking algorithmic stablecoins without external collateral can work (Terra killed this thesis)
- 🚩 Not knowing the difference between a CDP and a lending protocol
- 🚩 Inability to explain how stability fees act as monetary policy
- 🚩 Not recognizing that MakerDAO's terse naming convention exists (demonstrates you haven't read the code)

**Pro tip:** The stablecoin landscape is one of the most interview-relevant DeFi topics because it touches everything — oracles, liquidation, governance, monetary policy, risk management. Being able to compare MakerDAO vs Liquity vs Ethena design trade-offs demonstrates systems-level thinking that teams value highly.

---

### 📋 Summary: Stablecoin Landscape

**✓ Covered:**
- Stablecoin taxonomy: fiat-backed, overcollateralized, algorithmic, delta-neutral
- MakerDAO vs Liquity: governance vs immutability, Dutch auction vs Stability Pool
- GHO: stablecoin built on existing lending infrastructure (Aave V3)
- crvUSD: novel soft-liquidation via LLAMMA (AMM-based continuous adjustment)
- FRAX evolution: fractional-algorithmic → fully collateralized (lesson from Terra)
- Ethena USDe: delta-neutral hedging with funding rate revenue and its risks
- The fundamental trilemma: decentralization vs capital efficiency vs stability
- Terra collapse as the definitive failure case for uncollateralized algorithmic designs

**Next:** Module 7 — ERC-4626 tokenized vaults, yield aggregation, inflation attacks

---

<a id="common-mistakes"></a>
### ⚠️ Common Mistakes

**Mistake 1: Confusing normalized debt (`art`) with actual debt (`art × rate`)**

```solidity
// ❌ WRONG — reading art directly as the debt amount
(uint256 ink, uint256 art) = vat.urns(ilk, user);
uint256 debtOwed = art;  // This is NORMALIZED debt, not actual

// ✅ CORRECT — multiply by the rate accumulator
(uint256 ink, uint256 art) = vat.urns(ilk, user);
(, uint256 rate,,,) = vat.ilks(ilk);
uint256 debtOwed = art * rate / RAY;  // Actual debt in WAD
```

After years of accumulated stability fees, `rate` might be 1.15e27 (15% total fees). Reading `art` directly would understate the debt by 15%. This same mistake applies to Aave's `scaledBalance` vs actual balance.

**Mistake 2: Forgetting to call `drip()` before reading or modifying debt**

```solidity
// ❌ WRONG — rate is stale (hasn't been updated since last drip)
(, uint256 rate,,,) = vat.ilks(ilk);
uint256 debtOwed = art * rate / RAY;  // Could be hours/days stale

// ✅ CORRECT — drip first to update the rate accumulator
jug.drip(ilk);  // Updates rate to current timestamp
(, uint256 rate,,,) = vat.ilks(ilk);
uint256 debtOwed = art * rate / RAY;  // Accurate to this block
```

If nobody has called `drip()` for a week, the rate is a week stale. Any debt calculation, vault safety check, or liquidation trigger that reads the stale rate will be wrong. In practice, keepers and frontends call `drip()` before state-changing operations. Your contracts should too.

**Mistake 3: PSM decimal mismatch (USDC is 6 decimals, DAI is 18)**

```solidity
// ❌ WRONG — treating USDC and DAI amounts as the same scale
uint256 usdcAmount = 1000e18;  // 10^21 base units ÷ 10^6 decimals = 10^15 USDC ($1 quadrillion!)
psm.sellGem(address(this), usdcAmount);

// ✅ CORRECT — USDC uses 6 decimals
uint256 usdcAmount = 1000e6;   // 1000 USDC ($1,000)
psm.sellGem(address(this), usdcAmount);
// The PSM internally handles the 6→18 decimal conversion via GemJoin
```

The PSM's GemJoin adapter handles the decimal conversion (`gem_amount * 10^(18-6)`), but you must pass the USDC amount in USDC's native 6-decimal scale. Passing 18-decimal amounts will either overflow or swap vastly more than intended.

**Mistake 4: Not checking the `dust` minimum when partially repaying**

```solidity
// ❌ WRONG — partial repay leaves vault below dust threshold
// Vault has 10,000 DAI debt, dust = 5,000 DAI
vat.frob(ilk, address(this), address(this), address(this), 0, -int256(8000e18));
// Tries to reduce debt to 2,000 DAI → REVERTS (below dust of 5,000)

// ✅ CORRECT — either repay fully (dart = -art) or keep above dust
// Option A: Full repay
vat.frob(ilk, ..., 0, -int256(art));  // Close to 0 debt
// Option B: Stay above dust
vat.frob(ilk, ..., 0, -int256(5000e18));  // Leaves 5,000 DAI ≥ dust
```

The `dust` parameter prevents tiny vaults whose gas costs for liquidation would exceed the recovered value. When a vault has debt, it must be either 0 or ≥ `dust`. This catches developers who try to partially repay without checking.

---

## Key Takeaways

1. **CDPs mint money.** Unlike lending protocols that redistribute existing assets, CDP systems create new stablecoins backed by collateral. This is closer to how central banks work than how commercial banks work.

2. **The Vat is the source of truth.** Every DAI that exists can be traced back to a `frob()` call that created debt in the Vat. Understanding the Vat means understanding the entire system. The normalized debt pattern (`art × rate`) is the same index-based accounting from Module 4.

3. **Liquidation design is existential.** Black Thursday proved that auction mechanics can fail under stress. Three dominant approaches exist: Dutch auctions (MakerDAO Liquidation 2.0), Stability Pool absorption (Liquity), and continuous soft-liquidation via AMM (crvUSD LLAMMA). Each has different failure modes.

4. **Peg stability requires trade-offs.** The PSM makes DAI's peg extremely stable but introduces centralization risk. Liquity's redemption mechanism maintains the peg purely through crypto-native arbitrage but is less capital-efficient. Every design choice has consequences.

5. **Algorithmic stablecoins without external collateral fail.** Terra's $40B collapse is the definitive case study. FRAX abandoned its algorithmic component. Any design relying on its own token for backing should be treated with extreme skepticism.

6. **The landscape is diversifying.** GHO extends lending into issuance. crvUSD reinvents liquidation with AMMs. Ethena hedges with perps. Each approach shows how DeFi primitives from other modules (AMMs, oracles, lending, perps) can be recombined into stablecoin designs.

7. **Stablecoins are the ultimate integration test.** A stablecoin protocol touches every DeFi primitive: oracles (pricing), lending (collateral), liquidation (solvency), governance (monetary policy), AMMs (liquidity). This is why your Part 3 capstone IS a stablecoin.

8. **`rpow()` and rate accumulators are the mathematical backbone.** Per-second compounding via exponentiation by squaring (O(log n)) enables gas-efficient fee accumulation across the entire Vat. The same pattern appears in Aave (liquidity index), Compound (borrow index), and every protocol with time-based interest.

9. **Redemptions and PSMs are dual peg mechanisms.** Liquity uses crypto-native redemptions (burn LUSD → get ETH from riskiest vault) creating a hard floor at ~$1. MakerDAO uses the PSM (swap DAI ↔ USDC 1:1) creating a hard peg but introducing USDC dependency. Each makes a different trilemma trade-off.

---

## 📖 Production Study Order

Study these codebases in order — each builds on the previous one's patterns:

| # | Repository | Why Study This | Key Files |
|---|-----------|----------------|-----------|
| 1 | [MakerDAO dss (Vat)](https://github.com/sky-ecosystem/dss) | The foundational CDP engine — normalized debt, rate accumulator, `frob()` as the atomic vault operation | `src/vat.sol` |
| 2 | [MakerDAO Jug](https://github.com/sky-ecosystem/dss/blob/master/src/jug.sol) | Stability fee accumulator — per-second compounding via `drip()`, same index pattern as lending protocols | `src/jug.sol` |
| 3 | [MakerDAO Dog + Clipper](https://github.com/sky-ecosystem/dss/blob/master/src/clip.sol) | Liquidation 2.0 — Dutch auction mechanics, circuit breakers, keeper incentives (post-Black Thursday redesign) | `src/dog.sol`, `src/clip.sol`, `src/abaci.sol` |
| 4 | [MakerDAO PSM](https://github.com/sky-ecosystem/dss-psm) | Peg Stability Module — 1:1 stablecoin swaps, `tin`/`tout` fee mechanism, centralization trade-off | `src/psm.sol` |
| 5 | [Liquity V1](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/) | Alternative CDP: no governance, 110% CR, Stability Pool instant liquidation, redemption mechanism | `contracts/TroveManager.sol`, `contracts/StabilityPool.sol`, `contracts/BorrowerOperations.sol` |
| 6 | [crvUSD LLAMMA](https://github.com/curvefi/curve-stablecoin) | Novel soft-liquidation via AMM — continuous collateral conversion, PegKeeper for peg maintenance | `contracts/AMM.sol`, `contracts/Controller.sol` |

**Reading strategy:** Start with the Vat — memorize the glossary (ilk, urn, ink, art, gem, dai, sin) and read `frob()` line by line. Then Jug for the fee accumulator. Dog + Clipper show the Dutch auction (trace `bark()` → `kick()` → `take()`). PSM is short and shows the peg mechanism. Liquity shows a radically different CDP design (no governance). crvUSD shows the frontier: AMM-based soft liquidation.

---

## 🔗 Cross-Module Concept Links

### ← Backward References (Part 1 + Modules 1–5)

| Source | Concept | How It Connects |
|--------|---------|-----------------|
| Part 1 Section 1 | `mulDiv` / fixed-point math | WAD/RAY/RAD arithmetic throughout the Vat; `rmul`/`rpow` for stability fee compounding |
| Part 1 Section 1 | Custom errors | Production CDP contracts use custom errors for vault safety violations, ceiling breaches |
| Part 1 Section 2 | Transient storage | Modern CDP implementations can use TSTORE for reentrancy guards during liquidation callbacks |
| Part 1 Section 5 | Fork testing / `vm.mockCall` | Essential for testing against live MakerDAO state and simulating oracle price drops for liquidation |
| Part 1 Section 5 | Invariant testing | Property-based testing for CDP invariants: total debt ≤ total DAI, all vaults safe, rate monotonicity |
| Part 1 Section 6 | Proxy patterns | MakerDAO's authorization system (`wards`/`can`) and join adapter pattern for upgradeable periphery |
| Module 1 | SafeERC20 / token decimals | Join adapters bridge external ERC-20 tokens to Vat's internal accounting; decimal handling critical for multi-collateral |
| Module 1 | Fee-on-transfer awareness | Collateral join adapters must handle non-standard token behavior; PSM must handle USDC's blacklist |
| Module 2 | AMM / Curve StableSwap | PSM uses 1:1 swap; crvUSD's LLAMMA repurposes AMM as liquidation mechanism; Curve pools for peg monitoring |
| Module 3 | Oracle Security Module (OSM) | MakerDAO delays oracle prices by 1 hour via OSM — gives governance reaction time before liquidations |
| Module 3 | Chainlink / staleness checks | Collateral pricing for vault safety checks; oracle failure triggers emergency shutdown |
| Module 4 | Index-based accounting | Normalized debt (`art × rate`) is the same pattern as Aave's `scaledBalance × liquidityIndex` |
| Module 4 | Liquidation mechanics | Dutch auction (Dog/Clipper) parallels Aave's direct liquidation; Stability Pool parallels Compound's absorb |
| Module 5 | Flash loans / flash mint | Dutch auctions designed for flash loan compatibility; DssFlash mints unlimited DAI for flash borrowing |

### → Forward References (Modules 7–9 + Part 3)

| Target | Concept | How Stablecoin/CDP Knowledge Applies |
|--------|---------|--------------------------------------|
| Module 7 (Yield/Vaults) | sUSDS as ERC-4626 | Sky Savings Rate packaged as standard vault interface — stablecoin meets tokenized vault |
| Module 7 (Yield/Vaults) | DSR as yield source | DAI Savings Rate and sUSDS as yield-bearing stablecoin deposits for vault strategies |
| Module 8 (Security) | CDP invariant testing | Invariant testing SimpleCDP: total debt ≤ ceiling, all active vaults safe, rate accumulator monotonic |
| Module 8 (Security) | Peg stability threat model | Modeling peg attacks: PSM drain, oracle manipulation, governance parameter manipulation |
| Module 9 (Integration) | CDP + flash liquidation | Capstone combines CDP liquidation with flash loans and AMM swaps in a production flow |
| Part 3 Module 1 (Liquid Staking) | LSTs as collateral | wstETH, rETH as CDP collateral types — requires exchange rate oracle chaining |
| Part 3 Module 2 (Perpetuals) | Funding rate mechanics | Ethena's USDe uses perpetual funding rates as stablecoin backing — studied in depth |
| Part 3 Module 8 (Governance) | Monetary policy governance | Governor for stability fee, DSR, debt ceiling parameter updates; governance attack surface |
| Part 3 Module 9 (Capstone) | Multi-collateral stablecoin | Building a complete CDP-based stablecoin protocol from scratch — the curriculum's final integration |

---

## 📚 Resources

**MakerDAO/Sky:**
- [Technical docs](https://docs.makerdao.com)
- [Source code (dss)](https://github.com/sky-ecosystem/dss)
- [Vat detailed documentation](https://docs.makerdao.com/smart-contract-modules/core-module/vat-detailed-documentation)
- [Liquidation 2.0 (Dog & Clipper) documentation](https://docs.makerdao.com/smart-contract-modules/dog-and-clipper-detailed-documentation)
- [Developer guides](https://github.com/sky-ecosystem/developerguides)
- [Sky Protocol whitepaper](https://makerdao.com/whitepaper/DaiDec17WP.pdf)

**Liquity:**
- [Documentation](https://docs.liquity.org)
- [Source code](https://github.com/liquity/dev)
- [Liquity V2](https://www.liquity.org/bold)

**GHO:**
- [GHO documentation](https://aave.com/docs/ecosystem/gho)
- [GHO source code](https://github.com/aave/gho-core)

**crvUSD:**
- [crvUSD documentation](https://docs.curve.fi/crvUSD/overview/)
- [LLAMMA explanation](https://docs.curve.fi/crvUSD/amm/)
- [crvUSD source code](https://github.com/curvefi/curve-stablecoin)

**Ethena:**
- [Ethena documentation](https://docs.ethena.fi)
- [Ethena source code](https://github.com/ethena-labs)

**Stablecoin analysis:**
- [CDP classical design](https://onekey.so/blog/learn/cdp-the-classical-aesthetics-of-stablecoins/)
- Terra post-mortem: Search "Terra LUNA collapse analysis" for numerous detailed breakdowns

**Black Thursday:**
- MakerDAO Black Thursday post-mortem and Liquidation 2.0 rationale: MIP45 forum discussion
- [ChainSecurity Liquidation 2.0 audit](https://old.chainsecurity.com/wp-content/uploads/2021/04/ChainSecurity_MakerDAO_Liquidations2.0_Final.pdf)

---

**Navigation:** [← Module 5: Flash Loans](5-flash-loans.md) | [Module 7: Vaults & Yield →](7-vaults-yield.md)

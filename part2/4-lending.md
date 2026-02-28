# Part 2 — Module 4: Lending & Borrowing

**Duration:** ~7 days (3–4 hours/day)
**Prerequisites:** Modules 1–3 (tokens, AMMs, oracles)
**Pattern:** Math → Read Aave V3 → Read Compound V3 → Build simplified protocol → Liquidation deep dive
**Builds on:** Module 1 (SafeERC20), Module 3 (Chainlink consumer, staleness checks), Part 1 Module 5 (invariant testing, fork testing)
**Used by:** Module 5 (flash loan liquidation), Module 6 (stablecoin CDPs share index math), Module 7 (vault share pricing uses same index pattern), Module 8 (invariant testing your lending pool), Module 9 (integration capstone), Part 3 Module 8 (governance attacks on lending params), Part 3 Module 6 (cross-chain lending)

---

## 📚 Table of Contents

**The Lending Model from First Principles**
- [How DeFi Lending Works](#how-lending-works)
- [Key Parameters](#key-parameters)
- [Interest Rate Models: The Kinked Curve](#interest-rate-models)
- [Interest Accrual: Indexes and Scaling](#interest-accrual)
- [Deep Dive: RAY Arithmetic](#ray-arithmetic)
- [Deep Dive: Compound Interest Approximation](#compound-interest-approx)
- [Exercise: Build the Math](#build-lending-math)

**Aave V3 Architecture — Supply and Borrow**
- [Contract Architecture Overview](#aave-architecture)
- [aTokens: Interest-Bearing Receipts](#atokens)
- [Debt Tokens: Tracking What's Owed](#debt-tokens)
- [Read: Supply Flow](#read-supply-flow)
- [Read: Borrow Flow](#read-borrow-flow)
- [Exercise: Fork and Interact](#fork-interact)

**Aave V3 — Risk Modes and Advanced Features**
- [Efficiency Mode (E-Mode)](#e-mode)
- [Isolation Mode](#isolation-mode)
- [Supply and Borrow Caps](#supply-borrow-caps)
- [Read: Configuration Bitmap](#config-bitmap)
- [Deep Dive: Bitmap Encoding/Decoding](#bitmap-deep-dive)

**Compound V3 (Comet) — A Different Architecture**
- [The Single-Asset Model](#single-asset-model)
- [Comet Contract Architecture](#comet-architecture)
- [Principal and Index Accounting](#principal-index)
- [Read: Comet.sol Core Functions](#read-comet)

**Liquidation Mechanics**
- [Why Liquidation Exists](#why-liquidation)
- [The Liquidation Flow](#liquidation-flow)
- [Aave V3 Liquidation](#aave-liquidation)
- [Compound V3 Liquidation ("Absorb")](#compound-liquidation)
- [Liquidation Bot Economics](#liquidation-economics)

**Build a Simplified Lending Protocol**
- [SimpleLendingPool.sol](#simple-lending-pool)

**Synthesis and Advanced Patterns**
- [Architectural Comparison: Aave V3 vs Compound V3](#arch-comparison)
- [Bad Debt and Protocol Solvency](#bad-debt)
- [The Liquidation Cascade Problem](#liquidation-cascade)
- [Emerging Patterns (Morpho Blue, Euler V2)](#emerging-patterns)
- [Aave V3.1 / V3.2 / V3.3 Updates](#aave-updates)

---

## 💡 Why This Module Is the Longest After AMMs

**Why this matters:** Lending is where everything you've learned converges. Token mechanics (Module 1) govern how assets move in and out. Oracle integration (Module 3) determines collateral valuation and liquidation triggers. And the interest rate math shares DNA with the constant product formula from AMMs (Module 2) — both are mechanism design problems where smart contracts use mathematical curves to balance supply and demand without human intervention.

> **Real impact:** Lending protocols are the highest-TVL category in DeFi. [Aave holds $18B+ TVL](https://defillama.com/protocol/aave) (2024), [Compound $3B+](https://defillama.com/protocol/compound), [Spark (MakerDAO) $2.5B+](https://defillama.com/protocol/spark). Combined, lending protocols represent >$30B in user deposits.

> **Real impact — exploits:** Lending protocols have been the target of some of DeFi's largest hacks:
- [Euler Finance](https://rekt.news/euler-rekt/) ($197M, March 2023) — donation attack bypassing health checks
- [Radiant Capital](https://rekt.news/radiant-capital-rekt/) ($4.5M, January 2024) — flash loan rounding exploit on newly activated empty market
- [Rari Capital/Fuse](https://rekt.news/rari-capital-rekt/) ($80M, May 2022) — reentrancy in pool withdrawals
- [Cream Finance](https://rekt.news/cream-rekt-2/) ($130M, October 2021) — oracle manipulation
- [Hundred Finance](https://rekt.news/agave-hundred-rekt/) ($7M, March 2022) — [ERC-777](https://eips.ethereum.org/EIPS/eip-777) reentrancy
- [Venus Protocol](https://rekt.news/venus-blizz-rekt/) ($11M, May 2023) — stale oracle pricing

If you're building DeFi products, you'll either build a lending protocol, integrate with one, or compete with one. Understanding the internals is non-negotiable.

---

## The Lending Model from First Principles

<a id="how-lending-works"></a>
### 💡 How DeFi Lending Works

**Why this matters:** Traditional lending requires a bank to assess creditworthiness, set terms, and enforce repayment. DeFi lending replaces all of this with overcollateralization and algorithmic liquidation.

The core loop:

1. **Suppliers** deposit assets (e.g., USDC) into a pool. They earn interest from borrowers.
2. **Borrowers** deposit collateral (e.g., ETH), then borrow from the pool (e.g., USDC) up to a limit determined by their collateral's value and the protocol's risk parameters.
3. **Interest** accrues continuously. Borrowers pay it; suppliers receive it (minus a protocol cut called the reserve factor).
4. **If collateral value drops** (or debt grows) past a threshold, the position becomes eligible for **liquidation** — a third party repays part of the debt and receives the collateral at a discount.

**No credit checks. No loan officers. No repayment schedule.** Borrowers can hold positions indefinitely as long as they remain overcollateralized.

> **Used by:** [Aave V3](https://github.com/aave/aave-v3-core) (May 2022 deployment), [Compound V3 (Comet)](https://github.com/compound-finance/comet) (August 2022), [Spark](https://github.com/marsfoundation/sparklend) (fork of Aave V3, May 2023)

---

<a id="key-parameters"></a>
### 💡 Key Parameters

**Loan-to-Value (LTV):** The maximum ratio of borrowed value to collateral value at the time of borrowing. If ETH has an LTV of 80%, depositing $10,000 of ETH lets you borrow up to $8,000.

**Liquidation Threshold (LT):** The ratio at which a position becomes liquidatable. Always higher than LTV (e.g., 82.5% for ETH). The gap between LTV and LT is the borrower's safety buffer.

**Health Factor:** The single number that determines whether a position is safe:

```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value
```

HF > 1 = safe. HF < 1 = eligible for liquidation. HF = 1.5 means the collateral could lose 33% of its value before liquidation.

#### 🔍 Deep Dive: Health Factor Calculation Step-by-Step

**Scenario:** Alice deposits 5 ETH and 10,000 USDC as collateral, then borrows 8,000 DAI.

**Step 1: Get collateral values in USD (from oracle)**
```
ETH price  = $2,000      →  5 ETH × $2,000     = $10,000
USDC price = $1.00        →  10,000 USDC × $1   = $10,000
                                      Total collateral = $20,000
```

**Step 2: Apply each asset's Liquidation Threshold**
```
ETH  LT = 82.5%    →  $10,000 × 0.825 = $8,250
USDC LT = 85.0%    →  $10,000 × 0.850 = $8,500
                       Weighted collateral = $16,750
```

**Step 3: Get total debt value in USD**
```
DAI price = $1.00    →  8,000 DAI × $1  = $8,000
```

**Step 4: Compute Health Factor**
```
HF = Weighted Collateral / Total Debt
HF = $16,750 / $8,000
HF = 2.09
```

**What does 2.09 mean?** Alice's collateral (after risk-weighting) is 2.09× her debt. Her position can absorb a ~52% collateral value drop before liquidation.

**When does Alice get liquidated?** When HF drops below 1.0:
```
If ETH drops to $1,200 (-40%):
  ETH value  = 5 × $1,200 = $6,000  →  weighted = $6,000 × 0.825 = $4,950
  USDC value = $10,000               →  weighted = $10,000 × 0.850 = $8,500
  HF = ($4,950 + $8,500) / $8,000 = 1.68  ← still safe

If ETH drops to $400 (-80%):
  ETH value  = 5 × $400 = $2,000    →  weighted = $2,000 × 0.825 = $1,650
  USDC value = $10,000               →  weighted = $10,000 × 0.850 = $8,500
  HF = ($1,650 + $8,500) / $8,000 = 1.27  ← still safe (USDC cushion!)

If ETH drops to $0 (100% crash):
  HF = $8,500 / $8,000 = 1.06  ← still safe! USDC collateral alone covers the debt
```

**Key takeaway:** Multi-collateral positions are more resilient. The stablecoin collateral acts as a floor.

> **Example:** On [Aave V3 Ethereum mainnet](https://app.aave.com/), ETH has LTV = 80.5%, LT = 82.5%. If you deposit $10,000 ETH:
- Maximum initial borrow: $8,050 (80.5%)
- Liquidation triggered when debt/collateral exceeds 82.5%
- Safety buffer: 2% price movement room before liquidation risk

**Liquidation Bonus (Penalty):** The discount a liquidator receives on seized collateral (e.g., 5%). This incentivizes liquidators to monitor and act quickly, keeping the protocol solvent.

> **Why this matters:** Without sufficient liquidation bonus, liquidators have no incentive to act during high gas prices or volatile markets. Too high, and liquidations become excessively punitive for borrowers.

**Reserve Factor:** The percentage of interest that goes to the protocol treasury rather than suppliers (typically 10–25%). This builds a reserve fund for bad debt coverage.

> **Used by:** [Aave V3 reserves](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L199) range from 10-20% depending on asset, [Compound V3](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) uses protocol-specific reserve factors

**Close Factor:** How much of the debt a liquidator can repay in a single liquidation. Aave V3 uses 50% normally, but allows 100% when HF < 0.95 to clear dangerous positions faster.

> **Common pitfall:** Setting close factor too high (100% always) can lead to liquidation cascades where all collateral is dumped at once, crashing prices further. Gradual liquidation (50%) reduces market impact.

💻 **Quick Try:**

Before diving into the math, read live Aave V3 data on a mainnet fork. In your Foundry test:

```solidity
// Paste into a test file and run with --fork-url
interface IPool {
    struct ReserveData {
        uint256 configuration;
        uint128 liquidityIndex;      // RAY (27 decimals)
        uint128 currentLiquidityRate; // RAY — APY for suppliers
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate; // RAY — APY for borrowers
        uint128 currentStableBorrowRate;
        uint40  lastUpdateTimestamp;
        uint16  id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
    function getReserveData(address asset) external view returns (ReserveData memory);
}

function testReadAaveReserveData() public {
    IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IPool.ReserveData memory data = pool.getReserveData(usdc);

    // Convert RAY rates to human-readable APY
    uint256 supplyAPY = data.currentLiquidityRate / 1e23; // basis points
    uint256 borrowAPY = data.currentVariableBorrowRate / 1e23;

    emit log_named_uint("USDC Supply APY (bps)", supplyAPY);
    emit log_named_uint("USDC Borrow APY (bps)", borrowAPY);
    emit log_named_uint("Liquidity Index (RAY)", data.liquidityIndex);
    emit log_named_uint("Borrow Index (RAY)", data.variableBorrowIndex);
}
```

Run with `forge test --match-test testReadAaveReserveData --fork-url $ETH_RPC_URL -vv`. See the live rates and indexes — these are the numbers the kinked curve produces.

---

<a id="interest-rate-models"></a>
### 💡 Interest Rate Models: The Kinked Curve

**Why this matters:** The interest rate model is the mechanism that balances supply and demand for each asset pool. Every major lending protocol uses some variant of a piecewise linear "kinked" curve.

**Utilization rate:**
```
U = Total Borrowed / Total Supplied
```

When U is low, there's plenty of liquidity — rates should be low to encourage borrowing. When U is high, liquidity is scarce — rates should spike to attract suppliers and discourage borrowing. **If U hits 100%, suppliers can't withdraw. That's a crisis.**

> **Real impact:** During the March 2020 crash, [Aave's USDC borrow rate spiked past 50% APR](https://app.aave.com/reserve-overview/?underlyingAsset=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48&marketName=proto_mainnet_v3) when utilization hit 98%. This was working as designed — extreme rates forced borrowers to repay, restoring liquidity.

**The two-slope model:**

Below the optimal utilization (the "kink," typically 80–90%):
```
BorrowRate = BaseRate + (U / U_optimal) × Slope1
```

Above the optimal utilization:
```
BorrowRate = BaseRate + Slope1 + ((U - U_optimal) / (1 - U_optimal)) × Slope2
```

Slope2 is dramatically steeper than Slope1. This creates a sharp increase in rates past the kink, which acts as a self-correcting mechanism — expensive borrowing pushes utilization back down.

#### 🔍 Deep Dive: Visualizing the Kinked Curve

```
Borrow Rate
(APR)
  │
110%│                                          ╱  ← Slope2 (100%)
  │                                        ╱     Steep! Forces borrowers
  │                                      ╱       to repay, restoring
  │                                    ╱         utilization below kink
  │                                  ╱
  │                                ╱
  │                              ╱
  │                            ╱
  │                          ╱
  │                        ╱
  │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─╱─ ─ ─ ─ ─ ─ ─ ─ ─
  │                    ╱·│
 8%│                  ╱···│
  │                ╱·····│
  │              ╱·······│  ← Slope1 (8%)
  │            ╱·········│    Gentle: borrowing is cheap
  │          ╱···········│    when liquidity is ample
  │        ╱·············│
  │      ╱···············│
  │    ╱·················│
  │  ╱···················│
 2%│╱····················│  ← Base rate
  │──────────────────────┼──────────────────── Utilization
  0%                    80%                100%
                    "The Kink"
                (Optimal Utilization)

Note: Production values vary by asset. Stablecoins often use Slope2 = 60-80%,
volatile assets 200-300%+. The table below uses moderate values for clarity.
```

**Reading the curve with numbers (USDC-like parameters):**

| Utilization | Borrow Rate | What's happening |
|-------------|-------------|-----------------|
| 0% | 2% (base) | No borrows — minimum rate |
| 40% | 2% + 4% = 6% | Normal borrowing — gentle slope |
| 80% (kink) | 2% + 8% = 10% | At optimal — slope about to steepen |
| 85% | 10% + ~25% = 35% | Past kink — rates spiking rapidly |
| 90% | 10% + ~50% = 60% | Severe — borrowers forced to repay |
| 95% | 10% + ~75% = 85% | Emergency — liquidity nearly gone |
| 100% | 10% + 100% = 110% | Crisis — suppliers can't withdraw |

**Why this works as mechanism design:**
- Below the kink: rates are predictable and affordable → borrowers stay, utilization is healthy
- At the kink: rates start climbing → signal to borrowers that liquidity is tightening
- Past the kink: rates explode → *economic force* that pushes borrowers to repay
- The kink acts as a "thermostat" — the system self-corrects without governance intervention

> **Deep dive:** [Aave interest rate strategy contracts](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol), [Compound V3 rate model](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423), [RareSkills guide to interest rate models](https://rareskills.io/post/aave-interest-rate-model)

**Supply rate derivation:**
```
SupplyRate = BorrowRate × U × (1 - ReserveFactor)
```

Suppliers earn a fraction of what borrowers pay, reduced by utilization (not all capital is lent out) and the reserve factor (the protocol's cut).

**Numeric example (USDC-like parameters):**
```
Pool state: $100M supplied, $80M borrowed → U = 80%
Borrow rate at 80% utilization (from kinked curve) = 10% APR
Reserve factor = 15%

SupplyRate = 10% × 0.80 × (1 - 0.15)
           = 10% × 0.80 × 0.85
           = 6.8% APR

Where the interest goes:
  Borrowers pay:        $80M × 10% = $8M/year
  Suppliers receive:    $100M × 6.8% = $6.8M/year
  Protocol treasury:    $8M - $6.8M = $1.2M/year  (= reserve factor's cut)
```

**Why suppliers earn less than borrowers pay:** Two factors compound — not all supplied capital is borrowed (utilization < 100%), and the protocol takes a cut (reserve factor). This "spread" funds the protocol treasury and bad debt reserves.

> **Common pitfall:** Expecting supply rate to equal borrow rate. Suppliers always earn less due to utilization < 100% and reserve factor. If U = 80% and reserve factor = 15%, suppliers earn only `BorrowRate × 0.8 × 0.85 = 68%` of the gross borrow rate.

---

<a id="interest-accrual"></a>
### 💡 Interest Accrual: Indexes and Scaling

**Why this matters:** Interest doesn't accrue by updating every user's balance every second. That would be impossibly expensive. Instead, protocols use a **global index** that compounds over time:

```
currentIndex = previousIndex × (1 + ratePerSecond × timeElapsed)
```

A user's actual balance is:
```
actualBalance = storedPrincipal × currentIndex / indexAtDeposit
```

When a user deposits, the protocol stores their `principal` and the current index. When they withdraw, the protocol computes their balance using the latest index. **This means the protocol only needs to update one global variable, not millions of individual balances.**

> **Used by:** [Aave V3 supply index](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ReserveLogic.sol#L46), [Compound V3 supply/borrow indexes](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313), every modern lending protocol

#### 🔍 Deep Dive: Index Accrual — A Numeric Walkthrough

**Setup:** A pool with 5% APR borrow rate, two users deposit at different times.

**Step 0 — Pool creation:**
```
supplyIndex = 1.000000000000000000000000000  (1e27 in RAY)
Time: T₀
```

**Step 1 — Alice deposits 1,000 USDC at T₀:**
```
Alice's scaledBalance = 1,000 / supplyIndex = 1,000 / 1.0 = 1,000
Alice's balanceOf()   = 1,000 × 1.0 = 1,000 USDC  ✓
```

**Step 2 — 6 months pass (5% APR → ~2.5% for 6 months):**
```
ratePerSecond = 5% / 31,536,000 = 0.00000000158549 per second
timeElapsed   = 15,768,000 seconds (≈ 6 months)

supplyIndex = 1.0 × (1 + 0.00000000158549 × 15,768,000)
            = 1.0 × 1.025
            = 1.025000000000000000000000000

Alice's balanceOf() = 1,000 × 1.025 / 1.0 = 1,025 USDC  (+$25 interest)
```

**Step 3 — Bob deposits 2,000 USDC at T₀ + 6 months:**
```
Current supplyIndex = 1.025

Bob's scaledBalance = 2,000 / 1.025 = 1,951.22
Bob's balanceOf()   = 1,951.22 × 1.025 = 2,000 USDC  ✓ (no interest yet)
```

**Step 4 — Another 6 months pass (full year from T₀):**
```
supplyIndex = 1.025 × (1 + 0.00000000158549 × 15,768,000)
            = 1.025 × 1.025
            = 1.050625000000000000000000000

Alice's balanceOf() = 1,000.00 × 1.050625 / 1.0   = 1,050.63 USDC  (+$50.63 total — 1 year)
Bob's balanceOf()   = 1,951.22 × 1.050625 / 1.025  = 2,050.00 USDC  (+$50.00 — 6 months)
```

**Why this is elegant:**
- Only ONE storage write per pool interaction (update the global index)
- Alice and Bob's balances are computed on-the-fly from their `scaledBalance` and the current index
- No iteration over users, no batch updates, no cron jobs
- Works for millions of users with the same O(1) gas cost

**The pattern:** `actualBalance = scaledBalance × currentIndex / indexAtDeposit`

This is the same math behind [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault shares (Module 7) and staking reward distribution.

**Compound interest approximation:** [Aave V3 uses a binomial expansion](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol#L28) to approximate `(1 + r)^n` on-chain, which is cheaper than computing exponents. For small `r` (per-second rates are tiny), the approximation is extremely accurate.

> **Deep dive:** [Aave V3 MathUtils.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol) — compound interest calculation

<a id="ray-arithmetic"></a>
#### 🔍 Deep Dive: RAY Arithmetic — Why 27 Decimals?

**The problem:** Solidity has no floating point. Lending protocols need to represent per-second interest rates like `0.000000001585489599` (5% APR / 31,536,000 seconds). With 18-decimal WAD precision, this would be `1585489599` — losing 9 digits of precision. Over a year of compounding, those lost digits accumulate into significant errors.

**The solution:** RAY uses 27 decimals (`1e27 = 1 RAY`), giving 9 extra digits of precision compared to WAD:

```
WAD (18 decimals): 1.000000000000000000
RAY (27 decimals): 1.000000000000000000000000000

5% APR per-second rate:
  As WAD: 0.000000001585489599 → 1585489599 (10 significant digits)
  As RAY: 0.000000001585489599000000000 → 1585489599000000000 (19 significant digits)
```

**How `rayMul` and `rayDiv` work:**

```solidity
// From Aave V3 WadRayMath.sol
uint256 constant RAY = 1e27;
uint256 constant HALF_RAY = 0.5e27;

// rayMul: multiply two RAY values, round to nearest
function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a * b + HALF_RAY) / RAY;
}

// rayDiv: divide two RAY values, round to nearest
function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a * RAY + b / 2) / b;
}
```

**Step-by-step example — computing Alice's aToken balance:**

```
supplyIndex = 1.025 RAY = 1_025_000_000_000_000_000_000_000_000
Alice's scaledBalance = 1000e6 (1,000 USDC, 6 decimals)

// balanceOf() calls: scaledBalance.rayMul(currentIndex)
// rayMul(1000e6, 1.025e27)

a = 1_000_000_000                           // 1000 USDC in 6-decimal
b = 1_025_000_000_000_000_000_000_000_000   // 1.025 RAY

a * b = 1_025_000_000_000_000_000_000_000_000_000_000_000
+ HALF_RAY = ... + 500_000_000_000_000_000_000_000_000
/ RAY      = 1_025_000_000                  // 1,025 USDC ✓
```

**Rounding direction matters for protocol solvency:**

| Operation | Round Direction | Why |
|-----------|----------------|-----|
| Deposit → scaledBalance | Round **down** | Fewer shares = less claim on pool |
| Withdraw → actual amount | Round **down** | User gets slightly less |
| Borrow → scaledDebt | Round **up** | More debt recorded |
| Repay → remaining debt | Round **up** | Slightly more left to repay |

**The rule:** Always round *against the user, in favor of the protocol*. This prevents rounding-based drain attacks where millions of tiny operations each round in the user's favor, slowly bleeding the pool.

> **Used by:** [WadRayMath.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/WadRayMath.sol) — Aave's core math library. Compound V3 uses a simpler approach with `BASE_INDEX_SCALE = 1e15`.

<a id="compound-interest-approx"></a>
#### 🔍 Deep Dive: Compound Interest Approximation

**The problem:** True compound interest requires computing `(1 + r)^n` where `r` is the per-second rate and `n` is seconds elapsed. Exponentiation is expensive on-chain — and `n` can be millions (months of elapsed time).

**Aave's solution:** Use a [Taylor series expansion](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol#L28) truncated at 3 terms:

```
(1 + r)^n ≈ 1 + n·r + n·(n-1)·r²/2 + n·(n-1)·(n-2)·r³/6
              ↑        ↑                ↑
           linear   quadratic         cubic
           term     correction        correction
```

**Why this works:** Per-second rates are *tiny* (on the order of `1e-9` to `1e-8`). When `r` is small:
- `r²` is vanishingly small (~`1e-18`)
- `r³` is essentially zero (~`1e-27`)
- Three terms give accuracy to 27+ decimal places — well within RAY precision

**Numeric example — 10% APR over 30 days:**

```
r = 10% / 31,536,000 = 3.170979198e-9 per second
n = 30 × 86,400 = 2,592,000 seconds

3-term approx: 1 + n·r + n·(n-1)·r²/2 + n·(n-1)·(n-2)·r³/6

Term 1 (linear):    n × r                    = 0.008219178...
Term 2 (quadratic): n×(n-1) × r² / 2         = 0.000033778...
Term 3 (cubic):     n×(n-1)×(n-2) × r³ / 6   = 0.000000092...

3-term approximation: 1.008253048...
True compound value:  (1 + r)^n = 1.008253048...  ← essentially identical!
Simple interest:      1 + n×r   = 1.008219178...  ← 0.003% lower (missing quadratic+cubic)
```

The 3-term approximation matches the true compound value to ~10 decimal places. The 4th term (`n(n-1)(n-2)(n-3)·r⁴/24`) is on the order of `1e-10` — negligible at RAY precision. This is why Aave stops at 3 terms.

**Why not just use `n × r` (simple interest)?** Over long periods, the quadratic term matters:

```
10% APR over 1 year:
  Simple interest (1 term):    1.10000  (+10.0%)
  Aave approximation (3 terms): 1.10517  (+10.517%)
  True compound:               1.10517  (+10.517%)
  Error: <0.001% — the 3-term approximation matches!

  Simple interest error: 0.517% — real money at $18B TVL
```

**In code** ([MathUtils.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol#L28)):

```solidity
function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp, uint256 currentTimestamp)
    internal pure returns (uint256)
{
    uint256 exp = currentTimestamp - lastUpdateTimestamp;
    if (exp == 0) return RAY;

    uint256 expMinusOne = exp - 1;
    uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;

    uint256 basePowerTwo = rate.rayMul(rate);           // r²
    uint256 basePowerThree = basePowerTwo.rayMul(rate);  // r³

    uint256 secondTerm = exp * expMinusOne * basePowerTwo / 2;
    uint256 thirdTerm = exp * expMinusOne * expMinusTwo * basePowerThree / 6;

    return RAY + (rate * exp) + secondTerm + thirdTerm;
}
```

**Key insight:** This function runs on every `supply()`, `borrow()`, `repay()`, and `withdraw()` call. Using a 3-term approximation instead of iterative exponentiation saves thousands of gas per interaction — across millions of transactions, this is a significant optimization.

> **Compound V3's approach:** [Comet uses simple interest per-period](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313) (`index × (1 + rate × elapsed)`), which is slightly less accurate for long gaps but even cheaper. The difference is negligible because `accrueInternal()` is called frequently.

---

<a id="build-lending-math"></a>
### 🛠️ Exercise 1: Interest Rate Model

**Workspace:** [`workspace/src/part2/module4/exercise1-interest-rate/`](../workspace/src/part2/module4/exercise1-interest-rate/) — starter file: [`InterestRateModel.sol`](../workspace/src/part2/module4/exercise1-interest-rate/InterestRateModel.sol), tests: [`InterestRateModel.t.sol`](../workspace/test/part2/module4/exercise1-interest-rate/InterestRateModel.t.sol)

Implement a complete interest rate model contract that covers all the math from this section:

1. **RAY multiplication** (`rayMul`) — the bread-and-butter operation of all lending protocol math. A reference `rayDiv` implementation is provided for you to study.
2. **Utilization rate** (`getUtilization`) — the x-axis of the kinked curve
3. **Kinked borrow rate** (`getBorrowRate`) — the two-slope curve with the gentle slope below optimal and the steep slope above
4. **Supply rate** (`getSupplyRate`) — derived from borrow rate, utilization, and reserve factor
5. **Compound interest approximation** (`calculateCompoundInterest`) — the 3-term Taylor expansion used by Aave V3's MathUtils

All rates use RAY precision (27 decimals), matching Aave V3's internal math. The exercise scaffold has detailed hints and worked examples in the TODO comments.

> **Common pitfall:** Integer overflow when multiplying rates. Always ensure intermediate calculations don't overflow. Use smaller precision (e.g., per-second rates in RAY = 27 decimals) rather than storing APY directly.

**🎯 Goal:** Internalize RAY arithmetic and the kinked curve math before moving to the full lending pool. This is pure math — no tokens, no protocol state.

---

### 📋 Summary: The Lending Model

**Covered:**
- How DeFi lending works: overcollateralization → interest accrual → liquidation loop
- Key parameters: LTV, Liquidation Threshold, Health Factor, Liquidation Bonus, Reserve Factor, Close Factor
- Interest rate models: the two-slope kinked curve and why slope2 is steep (self-correcting mechanism)
- Supply rate derivation from borrow rate, utilization, and reserve factor (with numeric example)
- Index-based interest accrual: global index pattern that scales to millions of users
- RAY arithmetic: why 27 decimals, rayMul/rayDiv mechanics, rounding direction conventions
- Compound interest approximation: 3-term Taylor expansion, accuracy vs gas trade-off, Aave's MathUtils implementation

**Key insight:** The kinked curve is *mechanism design* — it uses price signals (rates) to automatically rebalance supply and demand without human intervention.

**Next:** Aave V3 architecture — how these concepts are implemented in production code.

#### 💼 Job Market Context

**What DeFi teams expect you to know about lending fundamentals:**

1. **"Explain how a lending protocol's interest rate model works."**
   - Good answer: Describes the kinked curve, utilization-based rates, slope1/slope2 distinction
   - Great answer: Explains *why* the kink exists (self-correcting mechanism), how supply rate derives from borrow rate × utilization × (1 - reserve factor), and mentions that Compound V3 uses independent curves vs Aave's derived approach

2. **"How does interest accrue without updating every user's balance?"**
   - Good answer: Global index pattern — store principal and index at deposit, compute live balance as `principal × currentIndex / depositIndex`
   - Great answer: Explains the gas motivation (O(1) vs O(n) updates), mentions the compound interest approximation in Aave's MathUtils.sol, and notes this same pattern appears in ERC-4626 vaults and staking contracts

3. **"What happens if a user's health factor drops below 1?"**
   - Good answer: Position becomes liquidatable, a third party repays part of the debt and receives collateral at a discount
   - Great answer: Explains close factor mechanics (50% vs 100% at HF < 0.95 in Aave V3), liquidation bonus calibration trade-offs, minimum position rules to prevent dust, and Compound V3's absorb/auction alternative

**Interview red flags:**
- Saying lending protocols "charge" interest (they don't — interest is algorithmic, not invoiced)
- Not understanding why collateral doesn't earn interest in Compound V3
- Confusing LTV (max borrow ratio) with Liquidation Threshold (liquidation trigger ratio)

**Pro tip:** The single most impressive thing you can do in a lending protocol interview is articulate the *trade-offs* between Aave and Compound architectures. This signals senior-level thinking.

---

## Aave V3 Architecture — Supply and Borrow

<a id="aave-architecture"></a>
### 💡 Contract Architecture Overview

**Why this matters:** [Aave V3](https://github.com/aave/aave-v3-core) (deployed May 2022) uses a proxy pattern with logic delegated to libraries. Understanding this architecture is essential for reading production lending code.

**The entry point is the Pool contract (behind a proxy), which delegates to specialized logic libraries:**

```
User → Pool (proxy)
         ├─ SupplyLogic
         ├─ BorrowLogic
         ├─ LiquidationLogic
         ├─ FlashLoanLogic
         ├─ BridgeLogic
         └─ EModeLogic
```

**Supporting contracts:**
- **[PoolAddressesProvider](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PoolAddressesProvider.sol):** Registry for all protocol contracts. Single source of truth for addresses.
- **[AaveOracle](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol):** Wraps Chainlink feeds. Each asset has a registered price source.
- **[PoolConfigurator](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/PoolConfigurator.sol):** Governance-controlled contract that sets risk parameters (LTV, LT, reserve factor, caps).
- **[PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol):** L2-specific — checks sequencer uptime before allowing liquidations.

> **Deep dive:** [Aave V3 technical paper](https://github.com/aave/aave-v3-core/blob/master/techpaper/Aave_V3_Technical_Paper.pdf), [MixBytes architecture analysis](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-aave-v3)

---

<a id="atokens"></a>
### 💡 aTokens: Interest-Bearing Receipts

**Why this matters:** When you supply USDC to Aave, you receive **aUSDC**. This is an [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token whose balance *automatically increases* over time as interest accrues. You don't need to claim anything — your `balanceOf()` result grows continuously.

**How it works internally:**

[aTokens](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol) store a "scaled balance" (principal divided by the current liquidity index). The `balanceOf()` function multiplies the scaled balance by the current index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedIncome(asset));
}
```

`getReserveNormalizedIncome()` returns the current supply index, which grows every second based on the supply rate. This design means:
- Transferring aTokens transfers the proportional claim on the pool (including future interest)
- aTokens are composable — they can be used in other DeFi protocols as yield-bearing collateral
- No explicit "harvest" or "claim" step for interest

> **Used by:** [Yearn V3 vaults](https://github.com/yearn/yearn-vaults-v3) accept aTokens as deposits, [Convex](https://www.convexfinance.com/) wraps aTokens for boosted rewards, many protocols use aTokens as collateral in other lending markets

> **Common pitfall:** Assuming aToken balance is static. If you cache `balanceOf()` at t0 and check again at t1, the balance will have increased. Always read the current value.

---

<a id="debt-tokens"></a>
### 💡 Debt Tokens: Tracking What's Owed

When you borrow, the protocol mints **[variableDebtTokens](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/VariableDebtToken.sol)** (or stable debt tokens, though stable rate borrowing is being deprecated) to your address. These are non-transferable ERC-20 tokens whose balance *increases* over time as interest accrues on your debt.

The mechanics mirror aTokens but use the borrow index instead of the supply index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedVariableDebt(asset));
}
```

Debt tokens being non-transferable is a deliberate security choice — you can't transfer your debt to someone else without their consent (credit delegation notwithstanding).

> **Common pitfall:** Trying to `transfer()` debt tokens. This reverts. Debt can only be transferred via credit delegation (`approveDelegation()`).

---

<a id="read-supply-flow"></a>
### 📖 Read: Supply Flow

**Source:** [aave-v3-core/contracts/protocol/libraries/logic/SupplyLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol)

Trace the supply path through Aave V3:

1. User calls [`Pool.supply(asset, amount, onBehalfOf, referralCode)`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L138)
2. Pool delegates to [`SupplyLogic.executeSupply()`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol#L47)
3. Logic validates the reserve is active and not paused
4. Updates the reserve's indexes (accrues interest up to this moment)
5. Transfers the underlying asset from user to the aToken contract
6. Mints aTokens to the `onBehalfOf` address (scaled by current index)
7. Updates the user's configuration bitmap (tracks which assets are supplied/borrowed)

---

<a id="read-borrow-flow"></a>
### 📖 Read: Borrow Flow

**Source:** [BorrowLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol)

1. User calls [`Pool.borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L190)
2. Pool delegates to [`BorrowLogic.executeBorrow()`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol#L52)
3. Logic validates: reserve active, borrowing enabled, amount ≤ borrow cap
4. **Validates the user's health factor will remain > 1 after the borrow**
5. Mints debt tokens to the borrower (or `onBehalfOf` for credit delegation)
6. Transfers the underlying asset from the aToken contract to the user
7. Updates the interest rate for the reserve (utilization changed)

**Key insight:** The health factor check happens *before* the tokens are transferred. If the borrow would make the position undercollateralized, it reverts.

> **Common pitfall:** Not accounting for accrued interest when calculating max borrow. Debt grows continuously, so the maximum borrowable amount decreases over time even if collateral price stays constant.

#### 📖 How to Study Aave V3 Architecture

The Aave V3 codebase is ~15,000+ lines across many libraries. Here's how to approach it without getting lost:

1. **Start with the Pool proxy entry points** — Open [Pool.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) and read just the function signatures. Each one (`supply`, `borrow`, `repay`, `withdraw`, `liquidationCall`) delegates to a Logic library. Map the routing: which function calls which library.

2. **Trace one complete flow end-to-end** — Pick `supply()`. Follow it into [SupplyLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol). Read every line of `executeSupply()`. Note: index update → transfer → mint aTokens → update user config bitmap. Draw this as a sequence diagram.

3. **Understand the data model** — Read [DataTypes.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/types/DataTypes.sol). The `ReserveData` struct is the central state. Map each field to what it controls (indexes for interest, configuration bitmap for risk params, address pointers for aToken/debtToken).

4. **Read the index math** — Open [ReserveLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ReserveLogic.sol) and trace `updateState()` → `_updateIndexes()`. This is the compound interest accumulation. Then read how `balanceOf()` in [AToken.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol) uses the index to compute the live balance.

5. **Then read ValidationLogic.sol** — This is where all the safety checks live: health factor validation, borrow cap checks, E-Mode constraints. Read `validateBorrow()` to understand every condition that must pass before a borrow succeeds.

**Don't get stuck on:** The configuration bitmap encoding initially. It's clever bit manipulation (Part 1 Module 1 territory) but you can treat `getters` as black boxes on first pass. Focus on the flow: entry point → logic library → state update → token operations.

---

### 💡 Credit Delegation

The `onBehalfOf` parameter enables [credit delegation](https://aave.com/docs/aave-v3/guides/credit-delegation): Alice can allow Bob to borrow using her collateral. Alice's health factor is affected, but Bob receives the borrowed assets. This is done through `approveDelegation()` on the debt token contract.

> **Used by:** [InstaDapp](https://instadapp.io/) uses credit delegation for automated strategies, institutional custody solutions use it for sub-account management

---

<a id="fork-interact"></a>
### 🛠️ Exercise 2: Simplified Lending Pool

**Workspace:** [`workspace/src/part2/module4/exercise2-lending-pool/`](../workspace/src/part2/module4/exercise2-lending-pool/) — starter file: [`LendingPool.sol`](../workspace/src/part2/module4/exercise2-lending-pool/LendingPool.sol), tests: [`LendingPool.t.sol`](../workspace/test/part2/module4/exercise2-lending-pool/LendingPool.t.sol)

Build a minimal but correct lending pool that puts the Aave V3 concepts into practice. The scaffold provides the state layout (Reserve struct, user positions, collateral configs) and RAY math helpers. You implement the core protocol logic:

1. **`supply(amount)`** — transfer tokens in, compute scaled deposit using the liquidity index
2. **`withdraw(amount)`** — convert scaled balance back, validate sufficient funds
3. **`depositCollateral(token, amount)`** — post collateral (no interest earned, like Compound V3)
4. **`borrow(amount)`** — record scaled debt, enforce health factor >= 1.0
5. **`repay(amount)`** — burn scaled debt, cap at actual debt to prevent overpayment
6. **`accrueInterest()`** — update both indexes using linear interest (simplified from Aave's compound)
7. **`getHealthFactor(user)`** — iterate collateral tokens, fetch oracle prices, compute weighted collateral vs debt

The exercise tests cover: happy path supply/withdraw/borrow/repay, interest accrual over time, health factor computation, over-borrow reverts, and multi-supplier independence.

**🎯 Goal:** Understand how index-based accounting works end-to-end in a lending pool, from accrual to health factor enforcement.

> **Bonus (no workspace):** Fork Ethereum mainnet and run a full supply → borrow → repay → withdraw cycle on Aave V3 directly, using `vm.prank()` and `deal()`. Compare the live behavior with your simplified implementation.

---

### 📋 Summary: Aave V3 Supply and Borrow

**Covered:**
- Aave V3 architecture: Pool proxy → logic libraries (Supply, Borrow, Liquidation, FlashLoan, Bridge, EMode)
- aTokens: interest-bearing ERC-20 receipts with auto-growing `balanceOf()` via liquidity index
- Debt tokens: non-transferable ERC-20s tracking borrow obligations via borrow index
- Supply flow: validate → update indexes → transfer underlying → mint aTokens → update config bitmap
- Borrow flow: validate → health factor check → mint debt tokens → transfer underlying → update rates
- Credit delegation: `onBehalfOf` pattern and `approveDelegation()`
- Code reading strategy for the 15,000+ line Aave V3 codebase

**Key insight:** aTokens' auto-rebasing balance enables composability — they can be used as yield-bearing collateral across DeFi without explicit claim steps.

**Next:** Aave V3's risk isolation features — E-Mode, Isolation Mode, and the configuration bitmap.

---

## Aave V3 — Risk Modes and Advanced Features

<a id="e-mode"></a>
### 💡 Efficiency Mode (E-Mode)

**Why this matters:** [E-Mode](https://aave.com/docs/aave-v3/markets/advanced) allows higher capital efficiency when collateral and borrowed assets are correlated. For example, borrowing USDC against DAI — both are USD stablecoins, so the risk of the collateral losing value relative to the debt is minimal.

When a user activates an E-Mode category (e.g., "USD stablecoins"), the protocol overrides the standard LTV and liquidation threshold with higher values specific to that category. A stablecoin category might allow 97% LTV vs the normal 75%.

E-Mode categories can also specify a custom oracle. For stablecoin-to-stablecoin, a fixed 1:1 oracle might be used instead of market price feeds, eliminating unnecessary liquidations from minor depeg events.

> **Real impact:** During the March 2023 USDC depeg (Silicon Valley Bank crisis), E-Mode users with DAI collateral borrowing USDC were not liquidated due to the correlated asset treatment, while non-E-Mode users faced liquidation risk from the price deviation.

> **Used by:** [Aave V3 E-Mode categories](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/EModeLogic.sol) — stablecoins, ETH derivatives (ETH/wstETH/rETH), BTC derivatives

---

<a id="isolation-mode"></a>
### 💡 Isolation Mode

**Why this matters:** New or volatile assets can be listed in [Isolation Mode](https://aave.com/docs/aave-v3/overview). When a user supplies an isolated asset as collateral:
- They cannot use any other assets as collateral simultaneously
- They can only borrow assets approved for isolation mode (typically stablecoins)
- There's a hard debt ceiling for the isolated asset across all users

This prevents a volatile long-tail asset from threatening the entire protocol. If SHIB were listed in isolation mode with a $1M debt ceiling, even a complete collapse of SHIB's price could only create $1M of potential bad debt.

> **Common pitfall:** Not understanding the trade-off. Isolation Mode severely limits composability — users can't mix isolated collateral with other assets. This is intentional for risk management.

---

### 💡 Siloed Borrowing

Assets with manipulatable oracles (e.g., tokens with thin liquidity that could be subject to the oracle attacks from Module 3) can be listed as "siloed." Users borrowing siloed assets can only borrow that single asset — no mixing with other borrows.

> **Deep dive:** [Aave V3 siloed borrowing](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ValidationLogic.sol#L203)

---

<a id="supply-borrow-caps"></a>
### 💡 Supply and Borrow Caps

[V3 introduces governance-set caps per asset](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ValidationLogic.sol#L82):
- **Supply cap:** Maximum total deposits. Prevents excessive concentration of a single collateral asset.
- **Borrow cap:** Maximum total borrows. Limits the protocol's exposure to any single borrowed asset.

These are simple but critical risk controls that didn't exist in V2.

> **Real impact:** After the [CRV liquidity crisis](https://cointelegraph.com/news/curve-liquidation-risk-poses-systemic-threat-to-defi-even-as-founder-scurries-to-repay-loans) (November 2023), Aave governance tightened CRV supply caps to limit exposure. This prevented further accumulation of risky CRV positions.

---

### 🛡️ Virtual Balance Layer

[Aave V3 tracks balances internally](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol#L73) rather than relying on actual `balanceOf()` calls to the token contract. This protects against donation attacks (someone sending tokens directly to the aToken contract to manipulate share ratios) and makes accounting predictable regardless of external token transfers like airdrops.

> **Real impact:** [Euler Finance hack](https://rekt.news/euler-rekt/) ($197M, March 2023) exploited donation attack vectors in ERC-4626-like vaults. Aave's virtual balance approach prevents this entire class of attacks.

---

<a id="config-bitmap"></a>
### 📖 Read: Configuration Bitmap

[Aave V3 packs all risk parameters](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol) for a reserve into a single `uint256` bitmap in `ReserveConfigurationMap`. This is extreme gas optimization:

```
Bit 0-15:   LTV
Bit 16-31:  Liquidation threshold
Bit 32-47:  Liquidation bonus
Bit 48-55:  Decimals
Bit 56:     Active flag
Bit 57:     Frozen flag
Bit 58:     Borrowing enabled
Bit 59:     Stable rate borrowing enabled (deprecated)
Bit 60:     Paused
Bit 61:     Borrowable in isolation
Bit 62:     Siloed borrowing
Bit 63:     Flashloaning enabled
...
```

> **Deep dive:** [ReserveConfiguration.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol) — read the getter/setter library functions to understand bitwise manipulation patterns used throughout production DeFi.

<a id="bitmap-deep-dive"></a>
#### 🔍 Deep Dive: Encoding and Decoding the Configuration Bitmap

**The problem:** Each reserve in Aave V3 has ~20 configuration parameters (LTV, liquidation threshold, bonus, decimals, flags, caps, e-mode category, etc.). Storing each in a separate `uint256` storage slot would cost 20 × 2,100 gas for a cold read. Packing them into a single `uint256` costs just one 2,100 gas SLOAD.

**The bitmap layout (first 64 bits):**

```
Bit position:  63      56 55    48 47     32 31     16 15      0
              ┌────────┬────────┬─────────┬─────────┬─────────┐
              │ flags  │decimals│  bonus  │   LT    │   LTV   │
              │ 8 bits │ 8 bits │ 16 bits │ 16 bits │ 16 bits │
              └────────┴────────┴─────────┴─────────┴─────────┘

Example for USDC on Aave V3 Ethereum:
  LTV = 77%              → stored as 7700   (bits 0-15)
  LT  = 80%              → stored as 8000   (bits 16-31)
  Bonus = 104.5% (4.5%)  → stored as 10450  (bits 32-47)
  Decimals = 6           → stored as 6      (bits 48-55)
```

**Reading LTV (bits 0-15) — mask the lower 16 bits:**

```solidity
uint256 constant LTV_MASK = 0xFFFF;  // = 65535 = 16 bits of 1s

function getLtv(uint256 config) internal pure returns (uint256) {
    return config & LTV_MASK;
}

// Example:
// config = ...0001_1110_0001_0100_0010_1000_1110_0010_0001_0001_0100  (binary)
//                                                      └─────────────┘
//                                                      LTV = 7700 (77%)
// config & 0xFFFF = 7700  ✓
```

**Reading Liquidation Threshold (bits 16-31) — shift right, then mask:**

```solidity
uint256 constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;

function getLiquidationThreshold(uint256 config) internal pure returns (uint256) {
    return (config >> 16) & 0xFFFF;
}

// Step by step:
// 1. config >> 16  →  shifts right 16 bits, LTV bits fall off
//    Now LT occupies bits 0-15
// 2. & 0xFFFF      →  masks to get just those 16 bits
// Result: 8000 (80%)
```

**Writing LTV — clear the old bits, then set new ones:**

```solidity
uint256 constant LTV_MASK = 0xFFFF;

function setLtv(uint256 config, uint256 ltv) internal pure returns (uint256) {
    // Step 1: Clear bits 0-15 (set them to 0)
    //   ~LTV_MASK = 0xFFFF...FFFF0000 (all 1s except bits 0-15)
    //   config & ~LTV_MASK zeroes out the LTV field
    // Step 2: OR in the new value
    return (config & ~LTV_MASK) | (ltv & LTV_MASK);
}

// Example — changing LTV from 7700 to 8050:
// Before: ...0001_1110_0001_0100  (7700 in bits 0-15)
// After:  ...0001_1111_0111_0010  (8050 in bits 0-15)
// All other bits unchanged ✓
```

**Reading a single-bit flag (e.g., "Active" at bit 56):**

```solidity
uint256 constant ACTIVE_MASK = 1 << 56;

function getActive(uint256 config) internal pure returns (bool) {
    return (config & ACTIVE_MASK) != 0;
}

function setActive(uint256 config, bool active) internal pure returns (uint256) {
    if (active) return config | ACTIVE_MASK;     // set bit 56 to 1
    else        return config & ~ACTIVE_MASK;    // set bit 56 to 0
}
```

**Why this matters for DeFi development:** This bitmap pattern appears everywhere — Uniswap V3/V4 tick bitmaps, Compound V3's `assetsIn` field, governance proposal states. Once you understand the mask-shift-or pattern, you can read any packed configuration in production code.

> **Connection:** Part 1 Module 1 covers bit manipulation fundamentals. This is the production application of those patterns.

---

### 🛠️ Exercise 3: Configuration Bitmap

**Workspace:** [`workspace/src/part2/module4/exercise3-config-bitmap/`](../workspace/src/part2/module4/exercise3-config-bitmap/) — starter file: [`ConfigBitmap.sol`](../workspace/src/part2/module4/exercise3-config-bitmap/ConfigBitmap.sol), tests: [`ConfigBitmap.t.sol`](../workspace/test/part2/module4/exercise3-config-bitmap/ConfigBitmap.t.sol)

Implement an Aave-style bitmap library that packs multiple risk parameters into a single `uint256`. The exercise provides reference implementations for `setLiquidationBonus`/`getLiquidationBonus` and `setDecimals`/`getDecimals` -- study the pattern, then apply it to:

1. **`setLtv`/`getLtv`** — bits 0-15 (simplest: no offset needed)
2. **`setLiquidationThreshold`/`getLiquidationThreshold`** — bits 16-31
3. **`setFlag`/`getFlag`** — generalized single-bit setter/getter for boolean flags (active, frozen, borrow enabled, etc.)

The tests include field independence checks (setting LTV must not corrupt the threshold) and a full roundtrip test with all fields set simultaneously -- matching real Aave V3 USDC and WETH configurations.

**🎯 Goal:** Master the mask-shift-or pattern used throughout production DeFi (Aave bitmaps, Uniswap tick bitmaps, Compound V3 `assetsIn`).

---

### 📋 Summary: Aave V3 Risk Modes

**Covered:**
- E-Mode: higher LTV/LT for correlated asset pairs (stablecoins, ETH derivatives)
- Isolation Mode: risk-containing new/volatile assets with debt ceilings and single-collateral restriction
- Siloed Borrowing: restricting assets with manipulatable oracles to single-borrow-asset positions
- Supply and Borrow Caps: governance-set limits preventing excessive concentration
- Virtual Balance Layer: internal balance tracking that prevents donation attacks
- Configuration bitmap: all risk parameters packed into a single `uint256` for gas efficiency

**Key insight:** Aave V3's risk features (E-Mode, Isolation, Siloed, Caps) are *defense in depth* — each addresses a different attack vector or risk scenario, and they compose together.

**Next:** Compound V3 (Comet) — a fundamentally different architectural approach to the same problem.

---

## Compound V3 (Comet) — A Different Architecture

💻 **Quick Try:**

Before reading Comet's architecture, see how differently it stores state compared to Aave. On a mainnet fork:

```solidity
interface IComet {
    function getUtilization() external view returns (uint256);
    function getSupplyRate(uint256 utilization) external view returns (uint64);
    function getBorrowRate(uint256 utilization) external view returns (uint64);
    function totalSupply() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function baseTrackingSupplySpeed() external view returns (uint256);
}

function testReadCometState() public {
    IComet comet = IComet(0xc3d688B66703497DAA19211EEdff47f25384cdc3); // USDC market

    uint256 util = comet.getUtilization();
    uint64 supplyRate = comet.getSupplyRate(util);
    uint64 borrowRate = comet.getBorrowRate(util);

    // Rates are per-second, scaled by 1e18. Convert to APR:
    emit log_named_uint("Utilization (1e18 = 100%)", util);
    emit log_named_uint("Supply APR (bps)", uint256(supplyRate) * 365 days / 1e14);
    emit log_named_uint("Borrow APR (bps)", uint256(borrowRate) * 365 days / 1e14);
    emit log_named_uint("Total Supply (USDC)", comet.totalSupply() / 1e6);
    emit log_named_uint("Total Borrow (USDC)", comet.totalBorrow() / 1e6);
}
```

Run with `forge test --match-test testReadCometState --fork-url $ETH_RPC_URL -vv`. Compare the rates and utilization with Aave's USDC market — you'll see they're in the same ballpark but computed independently.

---

### 💡 Why Study Both Aave and Compound

**Why this matters:** [Aave V3](https://github.com/aave/aave-v3-core) and [Compound V3](https://github.com/compound-finance/comet) represent two fundamentally different architectural approaches to the same problem. Understanding both gives you the design vocabulary to make informed choices when building your own protocol.

> **Deep dive:** [RareSkills Compound V3 Book](https://rareskills.io/compound-v3-book), [RareSkills architecture walkthrough](https://rareskills.io/post/compound-v3-contracts-tutorial)

---

<a id="single-asset-model"></a>
### 💡 The Single-Asset Model

**Why this matters:** [Compound V3's](https://github.com/compound-finance/comet) (deployed August 2022) key architectural decision: **each market only lends one asset** (the "base asset," typically USDC). This is a radical departure from V2 and from Aave, where every asset in the pool can be both collateral and borrowable.

**Implications:**
- **Simpler risk model:** There's no cross-asset risk contagion. If one collateral asset collapses, it can only affect the single base asset pool.
- **Collateral doesn't earn interest.** Your ETH or wBTC sitting as collateral in Compound V3 earns nothing. This is the trade-off for the simpler, safer architecture.
- **Separate markets for each base asset.** There's a [USDC market](https://app.compound.finance/) and an ETH market — completely independent contracts with separate parameters.

> **Common pitfall:** Expecting collateral to earn yield in Compound V3 like it does in Aave. It doesn't. Users must choose: deposit as base asset (earns interest), or deposit as collateral (enables borrowing, no interest).

---

<a id="comet-architecture"></a>
### 💡 Comet Contract Architecture

**Source:** [compound-finance/comet/contracts/Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol)

Everything lives in one contract (behind a proxy), called **Comet**:

```
User → Comet Proxy
         └─ Comet Implementation
              ├─ Supply/withdraw logic
              ├─ Borrow/repay logic
              ├─ Liquidation logic (absorb)
              ├─ Interest rate model
              └─ CometExt (fallback for auxiliary functions)
```

**Supporting contracts:**
- **[CometExt](https://github.com/compound-finance/comet/blob/main/contracts/CometExt.sol):** Handles overflow functions that don't fit in the main contract (24KB limit workaround via the fallback extension pattern)
- **[Configurator](https://github.com/compound-finance/comet/blob/main/contracts/Configurator.sol):** Sets parameters, deploys new Comet implementations when governance changes settings
- **[CometFactory](https://github.com/compound-finance/comet/blob/main/contracts/CometFactory.sol):** Deploys new Comet instances
- **[Rewards](https://github.com/compound-finance/comet/blob/main/contracts/CometRewards.sol):** Distributes COMP token incentives (separate from the lending logic)

---

### 💡 Immutable Variables: A Unique Design Choice

**Why this matters:** [Compound V3 stores all parameters](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L65-L109) (interest rate model coefficients, collateral factors, liquidation factors) as **immutable variables**, not storage. To change any parameter, governance must deploy an entirely new Comet implementation and update the proxy.

**Why?** Immutable variables are significantly cheaper to read than storage (3 gas vs 2100 gas for cold SLOAD). Since rate calculations happen on every interaction, this saves substantial gas across millions of transactions. The trade-off is governance friction — changing a parameter requires a full redeployment, not just a storage write.

> **Common pitfall:** Trying to update parameters via governance without redeploying. Compound V3 parameters are immutable — you must deploy a new implementation.

---

<a id="principal-index"></a>
### 💡 Principal and Index Accounting

[Compound V3 tracks balances](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313) using a principal/index system similar to Aave but with a twist: the principal is a **signed integer**. Positive means the user is a supplier; negative means they're a borrower. There's no separate debt token.

```solidity
struct UserBasic {
    int104 principal;       // signed: positive = supply, negative = borrow
    uint64 baseTrackingIndex;
    uint64 baseTrackingAccrued;
    uint16 assetsIn;        // bitmap of which collateral assets are deposited
}
```

The actual balance is computed:
```
If principal > 0: balance = principal × supplyIndex / indexScale
If principal < 0: balance = |principal| × borrowIndex / indexScale
```

---

### 💡 Separate Supply and Borrow Rate Curves

Unlike Aave (where supply rate is derived from borrow rate), [Compound V3 defines **independent** kinked curves](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423) for both supply and borrow rates. Both are functions of utilization with their own base rates, kink points, and slopes. This gives governance more flexibility but means the spread isn't automatically guaranteed.

> **Deep dive:** [Comet.sol getSupplyRate() / getBorrowRate()](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423)

---

<a id="read-comet"></a>
### 📖 Read: Comet.sol Core Functions

**Source:** [compound-finance/comet/contracts/Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol)

Key functions to read:
- [`supplyInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L683): How supply is processed, including the `repayAndSupplyAmount()` split (if user has debt, supply first repays debt, then adds to balance)
- [`withdrawInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L721): How withdrawal works, including automatic borrow creation if withdrawing more than supplied
- [`getSupplyRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L428) / [`getBorrowRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423): The kinked curve implementations
- [`accrueInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313): How indexes are updated using `block.timestamp` and per-second rates
- [`isLiquidatable()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L555): Health check using collateral factors and oracle prices

**Note:** Compound V3 is ~4,300 lines of Solidity (excluding comments). This is compact for a lending protocol and very readable.

#### 📖 How to Study Compound V3 (Comet)

Comet is dramatically simpler than Aave — one contract, ~4,300 lines. This makes it the better starting point if you're new to lending protocol code.

1. **Start with the state variables** — Open [Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) and read the immutable declarations (lines ~65-109). These ARE the protocol configuration — base token, interest rate params, collateral factors, oracle feeds. Notice: all immutable, not storage. Understanding why this matters (gas) and the trade-off (redeployment for changes) is key.

2. **Read `supplyInternal()` and `withdrawInternal()`** — These are the core flows. Notice the signed principal pattern: supplying when you have debt first repays debt. Withdrawing when you have no supply creates a borrow. This dual behavior is elegant but different from Aave's separate supply/borrow paths.

3. **Trace the index update in `accrueInternal()`** — This is simpler than Aave's version. One function, linear compound, per-second rates. Map how `baseSupplyIndex` and `baseBorrowIndex` grow over time.

4. **Read `isLiquidatable()`** — Follow the health check: for each collateral asset, fetch oracle price, multiply by collateral factor, sum up. Compare to borrow balance. This is the health factor equivalent, computed inline rather than as a separate ratio.

5. **Compare with Aave** — After reading both, you should be able to articulate: why did Compound choose a single-asset model? (Risk isolation.) Why immutables? (Gas.) Why signed principal? (Simplicity — no separate debt tokens.) These are the architectural trade-offs interviewers ask about.

**Don't get stuck on:** The `CometExt` fallback pattern. It's a workaround for the 24KB contract size limit — auxiliary functions are deployed separately and called via the fallback function. Understand that it exists, but focus on the core Comet logic.

---

### 🛠️ Exercise

**Exercise 1:** Read the Compound V3 [`getUtilization()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L413), [`getBorrowRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423), and [`getSupplyRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L428) functions. For each, trace the math and verify it matches the kinked curve formula from the Lending Model section.

**Exercise 2:** Compare Aave V3 and Compound V3 storage layout for user positions. Aave uses separate aToken and debtToken balances; Compound uses a single signed principal. Write a comparison document: what are the trade-offs of each approach for gas, composability, and complexity?

---

### 📋 Summary: Compound V3 (Comet)

**Covered:**
- Compound V3's single-asset model: one borrowable asset per market, simpler risk isolation
- Comet contract architecture: everything in one contract (vs Aave's library pattern)
- Immutable variables for parameters: 3 gas reads vs 2100 gas SLOAD, but requires full redeployment
- Signed principal pattern: positive = supplier, negative = borrower (no separate debt tokens)
- Independent supply and borrow rate curves (vs Aave's derived supply rate)
- Code reading strategy for the ~4,300 line Comet codebase

**Key insight:** Compound V3 trades composability (no yield on collateral) for simplicity and risk isolation. Neither architecture is strictly better — the choice depends on what you're building.

**Next:** The protocol's immune system — liquidation mechanics in both Aave and Compound.

---

## Liquidation Mechanics

💻 **Quick Try:**

Before diving into liquidation theory, find a real position close to liquidation on Aave V3. On a mainnet fork:

```solidity
interface IPool {
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,    // in USD (8 decimals, base currency units)
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,  // percentage (4 decimals: 8250 = 82.50%)
        uint256 ltv,
        uint256 healthFactor              // 18 decimals: 1e18 = HF of 1.0
    );
}

function testReadHealthFactor() public {
    IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // Pick any active Aave borrower from Etherscan or Dune
    // Or use your own address if you have an Aave position
    address borrower = 0x...; // replace with a real borrower

    (
        uint256 collateral, uint256 debt, uint256 available,
        uint256 lt, uint256 ltvVal, uint256 hf
    ) = pool.getUserAccountData(borrower);

    emit log_named_uint("Collateral (USD, 8 dec)", collateral);
    emit log_named_uint("Debt (USD, 8 dec)", debt);
    emit log_named_uint("Health Factor (18 dec)", hf);
    emit log_named_uint("Liquidation Threshold (bps)", lt);

    // Manually verify: HF = (collateral × LT / 10000) / debt
    uint256 manualHF = (collateral * lt / 10000) * 1e18 / debt;
    emit log_named_uint("Manual HF calc", manualHF);
    // These should match (within rounding)
}
```

Run with `forge test --match-test testReadHealthFactor --fork-url $ETH_RPC_URL -vv`. Seeing real health factors brings the abstraction to life — a number printed on screen is someone's real money at risk.

---

<a id="why-liquidation"></a>
### 💡 Why Liquidation Exists

**Why this matters:** Lending without credit checks requires overcollateralization. But crypto prices are volatile — collateral can lose value. Without liquidation, a $10,000 ETH collateral backing an $8,000 USDC loan could become worth $7,000, leaving the protocol with unrecoverable bad debt.

**Liquidation is the protocol's immune system.** It removes unhealthy positions before they can create bad debt, keeping the system solvent for all suppliers.

> **Real impact:** During the May 2021 crypto crash, [Aave processed $521M in liquidations](https://dune.com/queries/82373/162957) across 2,800+ positions in a single day. The system remained solvent — no bad debt accrued despite 40%+ price drops.

---

<a id="liquidation-flow"></a>
### 💡 The Liquidation Flow

**Step 1: Detection.** A position's health factor drops below 1 (meaning debt value exceeds collateral value × liquidation threshold). This happens when collateral price drops or debt value increases (from accrued interest or borrowed asset price increase).

**Step 2: A liquidator calls the liquidation function.** Liquidation is permissionless — anyone can do it. In practice, it's done by specialized bots that monitor all positions and submit transactions the moment a position becomes liquidatable.

**Step 3: Debt repayment.** The liquidator repays some or all of the borrower's debt (up to the close factor).

**Step 4: Collateral seizure.** The liquidator receives an equivalent value of the borrower's collateral, plus the liquidation bonus (discount). For example, repaying $5,000 of USDC debt might yield $5,250 worth of ETH (at 5% bonus).

**Step 5: Health factor restoration.** After liquidation, the borrower's health factor should be above 1 (smaller debt, proportionally less collateral).

---

<a id="aave-liquidation"></a>
### 📖 Aave V3 Liquidation

**Source:** [LiquidationLogic.sol → executeLiquidationCall()](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol#L48)

Key details:
- Caller specifies `collateralAsset`, `debtAsset`, `user`, and `debtToCover`
- Protocol validates HF < 1 using oracle prices
- **Close factor:** 50% normally. If HF < 0.95, the full 100% can be liquidated ([V3 improvement](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol#L163) over V2's fixed 50%)
- **Minimum position:** Partial liquidations must leave at least $1,000 of both collateral and debt remaining — otherwise the position must be fully cleared (prevents dust accumulation)
- Liquidator can choose to receive aTokens (collateral stays in the protocol) or the underlying asset
- Oracle prices are fetched fresh during the liquidation call

> **Common pitfall:** Forgetting to approve the liquidator contract to spend the debt asset. The liquidation call transfers debt tokens from the liquidator to the protocol — this requires prior approval.

**Aave V3 Liquidation Flow:**

```
                    ┌─────────────────────────────────────────┐
                    │     Liquidator calls liquidationCall()   │
                    │  (collateralAsset, debtAsset, user, amt) │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │  1. Validate: is user's HF < 1.0?       │
                    │     → Fetch oracle prices (AaveOracle)   │
                    │     → Compute HF using all collateral    │
                    │     → If HF ≥ 1.0, REVERT                │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │  2. Determine close factor               │
                    │     → HF < 0.95: can liquidate 100%      │
                    │     → HF ≥ 0.95: can liquidate max 50%   │
                    │     → Cap debtToCover at close factor     │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │  3. Calculate collateral to seize         │
                    │                                          │
                    │  collateral = debtToCover × debtPrice    │
                    │               × (1 + liquidationBonus)   │
                    │               / collateralPrice           │
                    │                                          │
                    │  e.g., $5,000 USDC × 1.05 / $2,000 ETH  │
                    │      = 2.625 ETH seized                  │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │  4. Execute transfers                     │
                    │     → Liquidator sends debtAsset to pool │
                    │     → Pool burns user's debt tokens       │
                    │     → Pool transfers collateral to        │
                    │       liquidator (aTokens or underlying)  │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │  5. Post-liquidation state               │
                    │     → User's debt decreased              │
                    │     → User's collateral decreased         │
                    │     → User's HF should now be > 1.0      │
                    │     → Liquidator profit = bonus portion   │
                    └─────────────────────────────────────────┘
```

---

<a id="compound-liquidation"></a>
### 📖 Compound V3 Liquidation ("Absorb")

**Why this matters:** Compound V3 takes a different approach: **the protocol itself absorbs underwater positions**, rather than individual liquidators repaying debt.

**The [`absorb()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L773) function:**
1. Anyone can call `absorb(absorber, [accounts])` for one or more underwater accounts
2. The protocol seizes the underwater account's collateral and stores it internally
3. The underwater account's debt is written off (socialized across suppliers via a "deficit" in the protocol)
4. The caller (absorber) receives no direct compensation from the absorb itself

**The [`buyCollateral()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L843) function:**
After absorption, the protocol holds seized collateral. Anyone can buy this collateral at a discount through `buyCollateral()`, paying in the base asset. The protocol uses the proceeds to cover the deficit. The discount follows a Dutch auction pattern — it starts small and increases over time until someone buys.

**This two-step process (absorb → buyCollateral) separates the urgency of removing bad positions from the market dynamics of selling collateral.** It prevents sandwich attacks on liquidations and gives the market time to find the right price.

> **Deep dive:** [Compound V3 absorb documentation](https://docs.compound.finance/collateral-and-borrowing/#absorb), [buyCollateral Dutch auction](https://docs.compound.finance/collateral-and-borrowing/#buying-absorbed-collateral)

---

<a id="liquidation-economics"></a>
### 💡 Liquidation Bot Economics

**Why this matters:** Running a liquidation bot is a competitive business:

**Revenue:** Liquidation bonus (typically 4–10% of seized collateral)

**Costs:**
- Gas for monitoring + execution
- Capital for repaying debt (or flash loan fees)
- Smart contract risk
- Oracle latency risk

**Competition:** Multiple bots compete for the same liquidation. In practice, the winner is often the one with the lowest latency to the mempool or the best MEV strategy (priority gas auctions, [Flashbots bundles](https://docs.flashbots.net/))

**Flash loan liquidations:** Liquidators can use flash loans to avoid needing capital — borrow the repayment asset, execute the liquidation, sell the seized collateral, repay the flash loan, keep the profit. All in one transaction.

> **Real impact:** During the May 2021 crash, liquidation bots earned an estimated $50M+ in bonuses across all protocols. The largest single liquidation on Aave was ~$30M collateral seized.

> **Deep dive:** [Flashbots docs](https://docs.flashbots.net/) — MEV infrastructure and searcher strategies, [Eigenphi liquidation tracking](https://eigenphi.io/)

---

### 🛠️ Exercise 4: Flash Loan Liquidation Bot

**Workspace:** [`workspace/src/part2/module4/exercise4-flash-liquidator/`](../workspace/src/part2/module4/exercise4-flash-liquidator/) — starter file: [`FlashLiquidator.sol`](../workspace/src/part2/module4/exercise4-flash-liquidator/FlashLiquidator.sol), tests: [`FlashLiquidator.t.sol`](../workspace/test/part2/module4/exercise4-flash-liquidator/FlashLiquidator.t.sol)

Build a zero-capital liquidation bot using ERC-3156 flash loans. The scaffold provides all the mock infrastructure (flash lender, lending pool, DEX) and the contract skeleton with interfaces. You wire together the composability flow:

1. **`liquidate(borrower, debtToken, debtAmount, collateralToken)`** — entry point that encodes parameters and requests a flash loan
2. **`onFlashLoan(...)`** — ERC-3156 callback that performs the liquidation with borrowed funds. Two critical security checks are required (caller validation and initiator validation).
3. **`_sellCollateral(...)`** — approve and swap seized collateral on the DEX
4. **`_verifyProfit(...)`** — ensure the liquidation was profitable after accounting for flash loan fees

The tests cover: profitable liquidation end-to-end, exact profit calculation (5% bonus minus 0.09% flash fee), close factor mechanics (50% vs 100%), unprofitable liquidation revert, callback security (wrong caller/initiator), and profit withdrawal.

**🎯 Goal:** Understand how MEV bots and liquidation bots compose flash loans, lending pools, and DEXes in a single atomic transaction.

---

### 📋 Summary: Liquidation Mechanics

**Covered:**
- Why liquidation exists: the immune system that prevents bad debt from price volatility
- The 5-step liquidation flow: detection → call → debt repayment → collateral seizure → HF restoration
- Aave V3 liquidation: direct liquidator model, close factor (50% normal, 100% when HF < 0.95), minimum position rules
- Compound V3 liquidation: two-step `absorb()` + `buyCollateral()` Dutch auction (separates urgency from market dynamics)
- Liquidation bot economics: revenue (bonus) vs costs (gas, capital, latency, competition)
- Flash loan liquidations: zero-capital liquidation using atomic borrow → liquidate → swap → repay

**Key insight:** Compound V3's absorb/auction split is architecturally elegant — it prevents sandwich attacks on liquidations and decouples "remove the risk" from "find the best price for collateral."

#### 💼 Job Market Context — Liquidation Mechanics

**What DeFi teams expect you to know about liquidation:**

1. **"Design a liquidation bot. What's your architecture?"**
   - Good answer: Monitor health factors, submit liquidation tx when HF < 1, use flash loans for capital efficiency
   - Great answer: Discusses mempool monitoring vs on-chain event listening, Flashbots bundles to avoid front-running, priority gas auction dynamics, the economics of when liquidation is profitable (bonus vs gas + flash loan fee + swap slippage), and multi-protocol monitoring (Aave + Compound + Euler simultaneously)

2. **"A user reports they were liquidated unfairly. How do you investigate?"**
   - Good answer: Check oracle prices at the liquidation block, verify HF was actually < 1
   - Great answer: Trace the full sequence — was the oracle price stale? Was the sequencer down (L2)? Was there a price manipulation in the same block? Did the liquidator front-run an oracle update? Check if the liquidation bonus was correctly applied and the close factor respected. This is a real scenario teams face in post-mortems.

3. **"Compare Aave's direct liquidation with Compound V3's absorb/auction model."**
   - Great answer: Aave's model is simpler — one atomic transaction, liquidator bears price risk. Compound's two-step model (absorb → buyCollateral) separates urgency from price discovery — absorption happens immediately (protocol takes bad debt), then Dutch auction finds optimal price for seized collateral. Trade-off: Compound's model socializes losses temporarily but gets better execution prices; Aave's model relies on liquidator speed and can suffer from sandwich attacks.

**Interview red flags:**
- Not knowing that liquidation is permissionless (anyone can call it)
- Thinking flash loan liquidations are "cheating" (they're essential for market health)
- Not understanding why close factor exists (prevent cascade selling)

**Pro tip:** If asked about liquidation in an interview, mention the **Euler V1 exploit** — the attacker used `donateToReserves()` to manipulate health factors, bypassing the standard liquidation check. This shows you understand how liquidation edge cases create attack surfaces.

**Next:** Build a simplified lending protocol (SimpleLendingPool) that integrates everything from the previous sections.

---

## Build a Simplified Lending Protocol

<a id="simple-lending-pool"></a>
### 🛠️ SimpleLendingPool.sol

Build a minimal but correct lending protocol that incorporates everything from this module:

**State:**
```solidity
struct Reserve {
    uint256 totalSupplied;
    uint256 totalBorrowed;
    uint256 supplyIndex;      // RAY (27 decimals)
    uint256 borrowIndex;      // RAY
    uint256 lastUpdateTimestamp;
    uint256 reserveFactor;    // WAD (18 decimals)
}

struct UserPosition {
    uint256 scaledSupply;     // supply principal / supplyIndex at deposit
    uint256 scaledDebt;       // borrow principal / borrowIndex at borrow
    mapping(address => uint256) collateral;  // collateral token => amount
}

mapping(address => Reserve) public reserves;           // asset => reserve data
mapping(address => mapping(address => UserPosition)) public positions;  // user => asset => position
```

**Core functions:**

1. `supply(asset, amount)` — Transfer tokens in, update supply index, store scaled balance
2. `withdraw(asset, amount)` — Check health factor remains > 1 after withdrawal, transfer tokens out
3. `depositCollateral(asset, amount)` — Transfer collateral tokens in (no interest earned)
4. `borrow(asset, amount)` — Check health factor after borrow, mint scaled debt, transfer tokens out
5. `repay(asset, amount)` — Burn scaled debt, transfer tokens in. Handle `type(uint256).max` for full repayment (see [Aave's pattern](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol#L116) for handling dust from continuous interest accrual)
6. `liquidate(user, collateralAsset, debtAsset, debtAmount)` — Validate HF < 1, repay debt, seize collateral with bonus

**Supporting functions:**

7. `accrueInterest(asset)` — Update supply and borrow indexes using kinked rate model
8. `getHealthFactor(user)` — Sum collateral values × LT, sum debt values, compute ratio. Use Chainlink mock for prices.
9. `getAccountLiquidity(user)` — Return available borrow capacity

**Interest rate model:** Implement the kinked curve from the Lending Model section as a separate contract referenced by the pool.

**Oracle integration:** Use the safe Chainlink consumer pattern from Module 3. Mock the oracle in tests.

---

### 🛠️ Test Suite

Write comprehensive Foundry tests:

- **Happy path:** supply → borrow → accrue interest → repay → withdraw (verify balances at each step)
- **Interest accuracy:** supply, warp 365 days, verify balance matches expected APY within tolerance
- **Health factor boundary:** borrow right at the limit, verify HF ≈ LT/LTV ratio
- **Liquidation trigger:** manipulate oracle price to push HF below 1, execute liquidation, verify correct collateral seizure and debt reduction
- **Liquidation bonus math:** verify liquidator receives exactly (debtRepaid × (1 + bonus) / collateralPrice) collateral
- **Over-borrow revert:** attempt to borrow more than health factor allows, verify revert
- **Withdrawal blocked:** attempt to withdraw collateral that would make HF < 1, verify revert
- **Multiple collateral types:** deposit ETH + WBTC as collateral, borrow USDC, verify combined collateral valuation
- **Interest rate jumps:** push utilization past the kink, verify rate jumps to the steep slope
- **Reserve factor accumulation:** verify protocol's share of interest accumulates correctly

> **Common pitfall:** Not accounting for rounding errors in index calculations. Use a tolerance (e.g., ±1 wei) when comparing expected vs actual balances after interest accrual.

---

### 📋 Summary: SimpleLendingPool

**Covered:**
- Building SimpleLendingPool.sol: state design (Reserve struct, UserPosition struct, index-based accounting)
- Core functions: supply, withdraw, depositCollateral, borrow, repay, liquidate
- Supporting functions: accrueInterest (kinked rate model), getHealthFactor (Chainlink integration), getAccountLiquidity
- Full test suite design: happy path, interest accuracy, HF boundaries, liquidation correctness, over-borrow reverts, multi-collateral

**Key insight:** Building a lending pool from scratch — even a simplified one — forces you to understand every interaction between interest math, oracle pricing, and health factor enforcement. The tests are where the real learning happens.

**Next:** Synthesis — architectural comparison, bad debt, liquidation cascades, and emerging patterns.

---

## Synthesis and Advanced Patterns

<a id="arch-comparison"></a>
### 📋 Architectural Comparison: Aave V3 vs Compound V3

| Dimension | Aave V3 | Compound V3 |
|-----------|---------|-------------|
| Borrowable assets | Multiple per pool | Single base asset per market |
| Collateral interest | Yes (aTokens accrue) | No |
| Debt representation | Non-transferable debt tokens | Signed principal in UserBasic |
| Parameter storage | Storage variables | Immutable variables (cheaper reads, costlier updates) |
| Interest rate model | Borrow rate from curve, supply derived | Independent supply and borrow curves |
| Liquidation model | Direct liquidator repays, receives collateral | Protocol absorbs, then Dutch auction for collateral |
| Risk isolation | E-Mode, Isolation Mode, Siloed Borrowing | Inherent via single-asset markets |
| Code size | ~15,000+ lines across libraries | ~4,300 lines in Comet |
| Upgrade path | Update logic libraries, keep proxy | Deploy new Comet, update proxy |

---

<a id="bad-debt"></a>
### 💡 Bad Debt and Protocol Solvency

**Why this matters:** What happens when collateral value drops so fast that liquidation can't happen in time? The position becomes underwater — debt exceeds collateral. This creates **bad debt** that the protocol must absorb.

**[Aave's approach](https://aave.com/docs/developers/safety-module):** The Safety Module (staked AAVE) serves as a backstop. If bad debt accumulates, governance can trigger a "shortfall event" that slashes staked AAVE to cover losses. This is insurance funded by AAVE stakers who earn protocol revenue in return.

**Compound's approach:** The [`absorb`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L773) function socializes the loss across all suppliers (the protocol's reserves decrease). The subsequent `buyCollateral()` Dutch auction recovers what it can.

> **Real impact:** During the [CRV liquidity crisis](https://cointelegraph.com/news/curve-liquidation-risk-poses-systemic-threat-to-defi-even-as-founder-scurries-to-repay-loans) (November 2023), several Aave markets accumulated bad debt from a large borrower whose CRV collateral couldn't be liquidated fast enough due to thin liquidity. This led to governance discussions about tightening risk parameters for illiquid assets — and informed the design of Isolation Mode and supply/borrow caps in V3.

---

<a id="liquidation-cascade"></a>
### ⚠️ The Liquidation Cascade Problem

**Why this matters:** When crypto prices drop sharply, many positions become liquidatable simultaneously. Liquidators selling seized collateral on DEXes pushes prices down further, triggering more liquidations. This positive feedback loop is a **liquidation cascade**.

**Defenses:**
- **Gradual liquidation (close factor < 100%):** Prevents dumping all collateral at once
- **Liquidation bonus calibration:** Too high = excessive selling pressure; too low = no incentive to liquidate
- **Oracle smoothing / [PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol):** Delays liquidations briefly after sequencer recovery on L2 to let prices stabilize
- **Supply/borrow caps:** Limit total exposure so cascades can't grow unbounded

> **Real impact:** The March 2020 "Black Thursday" crash saw [over $8M in bad debt on Maker](https://web.archive.org/web/2024/https://blog.makerdao.com/the-market-collapse-of-march-12-2020-how-it-impacted-makerdao/) due to liquidation cascades and network congestion preventing timely liquidations. This informed V2/V3 risk parameter designs.

---

<a id="emerging-patterns"></a>
### 💡 Emerging Patterns

<a id="morpho-blue"></a>
**[Morpho Blue](https://github.com/morpho-org/morpho-blue) — The Minimalist Lending Core:**

Morpho Blue (deployed January 2024) represents a radical departure from both Aave and Compound. The core contract is **~650 lines of Solidity** — smaller than most ERC-20 tokens with governance.

**Key architectural insight:** Instead of one big pool with many assets (Aave) or one contract per base asset (Compound), Morpho Blue creates **isolated markets defined by 5 immutable parameters:** loan token, collateral token, oracle, interest rate model (IRM), and LTV. Anyone can create a market — no governance vote needed.

```
Traditional (Aave/Compound):        Morpho Blue:
┌─────────────────────────┐         ┌─────────────┐  ┌─────────────┐
│  One Pool / One Market  │         │ Market A     │  │ Market B     │
│  ETH, USDC, DAI, WBTC  │         │ USDC/ETH     │  │ DAI/wstETH   │
│  all cross-collateral   │         │ 86% LTV      │  │ 94.5% LTV    │
│  shared risk params     │         │ Oracle X     │  │ Oracle Y     │
└─────────────────────────┘         └─────────────┘  └─────────────┘
                                    Each market is fully isolated
                                    Parameters immutable at creation
```

**Why ~650 lines?** Morpho Blue pushes complexity to the edges:
- No governance, no upgradeability, no admin functions — parameters are immutable
- No interest rate model built in — it's an external contract passed at market creation
- No oracle built in — it's an external contract passed at market creation
- No token wrappers (no aTokens) — balances are tracked as simple mappings
- The result: a minimal, auditable core that's extremely hard to exploit

**The MetaMorpho layer:** On top of Morpho Blue, [MetaMorpho vaults](https://github.com/morpho-org/metamorpho) (ERC-4626 vaults managed by curators) allocate capital across multiple Morpho Blue markets. This separates *lending logic* (Morpho Blue, immutable) from *risk management* (MetaMorpho, managed).

> **Real impact:** Morpho Blue crossed [$3B+ TVL](https://defillama.com/protocol/morpho-blue) within its first year. Its market creation is permissionless — over 1,000 unique markets created by Q4 2024.

> **📖 How to study:** Read [Morpho.sol](https://github.com/morpho-org/morpho-blue/blob/main/src/Morpho.sol) — it's short enough to read entirely in one sitting. Focus on `supply()`, `borrow()`, and `liquidate()`. Compare the simplicity with Aave's 15,000 lines.

**[Euler V2](https://docs.euler.finance):** Modular architecture where each vault has its own risk parameters. Vaults can connect to each other via a "connector" system, creating a graph of lending relationships rather than a single pool. Represents the same "modular lending" trend as Morpho Blue but with different trade-offs (more flexibility, more complexity).

**Variable liquidation incentives:** Some protocols adjust the liquidation bonus dynamically based on how far underwater a position is, how much collateral is being liquidated, and current market conditions. This optimizes between "enough incentive to liquidate quickly" and "not so much that borrowers are unfairly punished."

<a id="aave-updates"></a>
#### 💡 Aave V3.1 / V3.2 / V3.3 — Recent Updates (Awareness)

Aave continues evolving within the V3 framework. These updates are important to know about even if you study the V3 base code:

**Aave V3.1 (April 2024):**
- **Liquid eMode:** Each asset can belong to *multiple* E-Mode categories simultaneously (previously limited to one). A user can activate the category that best matches their position. This increases capital efficiency for LST/LRT positions.
- **Stateful interest rate model:** The [DefaultReserveInterestRateStrategyV2](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/DefaultReserveInterestRateStrategyV2.sol) can adjust the base rate based on recent utilization history, making the curve adaptive rather than static.

**Aave V3.2 (July 2024):**
- **Umbrella (Safety Module replacement):** Replaces the staked-AAVE backstop with a more flexible insurance system. Individual "aToken umbrellas" protect specific reserves, allowing targeted risk coverage rather than one-size-fits-all protection.
- **Virtual accounting enforced:** The virtual balance layer (internal balance tracking vs `balanceOf()`) is now the default, not optional. This hardens all reserves against donation attacks.

**Aave V3.3 (February 2025):**
- **Deficit handling mechanism:** Automated bad debt handling where governance can write off accumulated deficits across reserves, replacing manual proposals with a standardized process.
- **Deprecation of stable rate borrowing:** The stable rate mode is fully removed from new deployments, simplifying the codebase.

**GHO — Aave's Native Stablecoin:**
[GHO](https://github.com/aave/gho-core) is minted directly through Aave V3 borrowing (a "facilitator" pattern). Users borrow GHO instead of withdrawing existing assets from the pool. This means Aave acts as both a lending protocol *and* a stablecoin issuer — connecting Module 4 directly to Module 6 (Stablecoins).

> **Why this matters for interviews:** Knowing about V3.1+ updates signals that you follow the space actively. Mentioning Liquid eMode or Umbrella shows you're beyond textbook knowledge.

---

### 🛠️ Exercise

**Workspace:** [`workspace/test/part2/module4/exercise4b-liquidation-scenarios/`](../workspace/test/part2/module4/exercise4b-liquidation-scenarios/) — test-only exercise: [`LiquidationScenarios.t.sol`](../workspace/test/part2/module4/exercise4b-liquidation-scenarios/LiquidationScenarios.t.sol) (implements `BadDebtPool.handleBadDebt()` inline, then runs cascade and bad debt tests)

**Exercise 1: Liquidation cascade simulation.** Using your SimpleLendingPool from the Build exercise, set up 5 users with progressively tighter health factors. Drop the oracle price in steps. After each drop, execute available liquidations. Track how each liquidation changes the "market" (the oracle price reflects the collateral being sold). Does the cascade stabilize or spiral?

**Exercise 2: Bad debt scenario.** Configure your pool with a very volatile collateral. Use `vm.warp` and `vm.mockCall` to simulate a 50% price crash in a single block (too fast for liquidation). Show the resulting bad debt. Implement a `handleBadDebt()` function that socializes the loss across suppliers.

**Exercise 3: Read Morpho Blue's minimal core.** Read [Morpho.sol](https://github.com/morpho-org/morpho-blue/blob/main/src/Morpho.sol) (~650 lines). Focus on: how are markets created (the 5 immutable parameters)? How does `supply()` / `borrow()` / `liquidate()` work without aTokens or debt tokens? How does the architecture achieve risk isolation without Aave's E-Mode/Isolation Mode complexity? Compare the simplicity with Aave's 15,000 lines. No build — just analysis.

---

### 📋 Summary: Synthesis and Advanced Patterns

**Covered:**
- Architectural comparison: Aave V3 (multi-asset, composable, complex) vs Compound V3 (single-asset, isolated, simple)
- Bad debt mechanics: Aave's Safety Module (staked AAVE backstop) vs Compound's absorb/auction socialization
- Liquidation cascades: the positive feedback loop and defenses (close factor, bonus calibration, oracle smoothing, caps)
- Emerging protocols: Morpho Blue (~650-line minimal core, permissionless isolated markets), Euler V2 (modular vaults), variable liquidation incentives
- Aave V3.1/V3.2/V3.3 updates: Liquid eMode, Umbrella, virtual accounting enforcement, deficit handling, stable rate deprecation
- GHO stablecoin: Aave as both lending protocol and stablecoin issuer via facilitator pattern

**Key insight:** The Aave vs Compound architectural trade-off is a core interview topic. Being able to articulate *why* each design was chosen (not just *what* it does) separates senior DeFi engineers from juniors.

**Next:** Module 5 — Flash Loans (atomic uncollateralized borrowing, composing multi-step arbitrage and liquidation flows).

#### 💼 Job Market Context

**What DeFi teams expect you to know about lending architecture:**

1. **"Compare Aave V3 and Compound V3 architectures. When would you choose one over the other?"**
   - Good answer: Lists the differences (multi-asset vs single-asset, aTokens vs signed principal, libraries vs monolith)
   - Great answer: Frames it as a trade-off space — Aave optimizes for composability and capital efficiency (yield-bearing collateral, E-Mode), Compound optimizes for risk isolation and simplicity (no cross-asset contagion, smaller attack surface). Choice depends on whether you're building a general lending market (Aave) or a focused, risk-minimized product (Compound)

2. **"How would you prevent bad debt in a lending protocol?"**
   - Good answer: Overcollateralization, timely liquidations, conservative risk parameters
   - Great answer: Discusses defense in depth — E-Mode/Isolation/Siloed borrowing for risk segmentation, supply/borrow caps for exposure limits, virtual balance layer against donation attacks, PriceOracleSentinel for L2 sequencer recovery, Safety Module as backstop, and the fundamental tension between capital efficiency and safety margin

3. **"Walk me through a liquidation cascade. How would you design defenses?"**
   - Great answer: Explains the positive feedback loop (liquidation → collateral sold → price drops → more liquidations), then discusses close factor < 100%, bonus calibration, oracle smoothing, and references Black Thursday 2020 as the canonical example that shaped current designs

**Hot topics in 2025-2026:**
- Cross-chain lending (L2 ↔ L1 collateral, shared liquidity across chains)
- Modular lending (Euler V2 vault graph, Morpho Blue's minimal core + modules)
- Real-World Assets (RWA) as collateral in lending markets (Maker/Sky, Centrifuge)
- Point-of-sale lending with on-chain credit scoring (undercollateralized lending frontier)

---

## ⚠️ Common Mistakes

**Mistakes that have caused real exploits and audit findings in lending protocols:**

1. **Not accruing interest before state changes**
   ```solidity
   // WRONG — reads stale index
   function borrow(uint256 amount) external {
       uint256 debt = getDebt(msg.sender); // uses old borrowIndex
       require(isHealthy(msg.sender), "undercollateralized");
       // ...
   }

   // CORRECT — accrue first, then compute
   function borrow(uint256 amount) external {
       accrueInterest();  // updates indexes to current timestamp
       uint256 debt = getDebt(msg.sender); // uses fresh borrowIndex
       require(isHealthy(msg.sender), "undercollateralized");
       // ...
   }
   ```
   **Impact:** Stale indexes undercount debt → users borrow more than they should → protocol becomes undercollateralized.

2. **Using `balanceOf()` instead of internal accounting for pool balances**
   ```solidity
   // WRONG — vulnerable to donation attacks
   function totalDeposits() public view returns (uint256) {
       return token.balanceOf(address(this));
   }

   // CORRECT — track internally
   function totalDeposits() public view returns (uint256) {
       return _internalTotalDeposits;
   }
   ```
   **Impact:** Attacker sends tokens directly to the contract → inflates share ratio → drains funds. This is how [Euler was exploited for $197M](https://rekt.news/euler-rekt/).

3. **Rounding in the wrong direction**
   ```solidity
   // WRONG — rounds in user's favor for debt
   scaledDebt = debtAmount * RAY / borrowIndex;  // rounds down = less debt

   // CORRECT — round UP for debt, DOWN for deposits
   scaledDebt = (debtAmount * RAY + borrowIndex - 1) / borrowIndex;  // rounds up
   ```
   **Impact:** Each borrow creates slightly less debt than it should. Over millions of borrows, the shortfall accumulates. Aave V3 uses `rayDiv` (round down) for deposits and `rayDiv` with round-up for debt.

4. **Not checking oracle freshness before liquidation**
   ```solidity
   // WRONG — uses potentially stale price
   uint256 price = oracle.latestAnswer();

   // CORRECT — validate freshness
   (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
   require(block.timestamp - updatedAt < STALENESS_THRESHOLD, "stale price");
   require(answer > 0, "invalid price");
   ```
   **Impact:** Stale oracle → incorrect HF calculation → either wrongful liquidation (user loss) or missed liquidation (protocol loss). See Module 3 for complete oracle safety patterns.

5. **Liquidation that doesn't restore health**
   ```solidity
   // WRONG — doesn't check post-liquidation state
   function liquidate(address user, uint256 amount) external {
       _repayDebt(user, amount);
       _seizeCollateral(user, amount * bonus);
       // done — but what if HF is still < 1?
   }

   // CORRECT — verify the liquidation actually helped
   // Aave V3 enforces minimum position sizes and validates post-liquidation state
   ```
   **Impact:** Partial liquidation that leaves a dust position still underwater → no one can liquidate the remainder profitably → bad debt.

6. **Not handling `type(uint256).max` for full repayment**
   ```solidity
   // WRONG — user passes type(uint256).max to mean "repay all"
   // but interest accrues between tx submission and execution
   function repay(uint256 amount) external {
       token.transferFrom(msg.sender, address(this), amount);
       userDebt[msg.sender] -= amount;
       // If amount > actual debt → underflow revert
       // If amount < actual debt → dust remains
   }

   // CORRECT — handle the "repay everything" case explicitly
   function repay(uint256 amount) external {
       accrueInterest();
       uint256 currentDebt = getDebt(msg.sender);
       uint256 repayAmount = amount == type(uint256).max ? currentDebt : amount;
       require(repayAmount <= currentDebt, "repay exceeds debt");
       token.transferFrom(msg.sender, address(this), repayAmount);
       userDebt[msg.sender] -= repayAmount;
   }
   ```
   **Impact:** Without the `type(uint256).max` pattern, users can never fully repay their debt because interest accrues between the time they calculate the amount and when the transaction executes. This leaves tiny dust debts that accumulate across thousands of users. [Aave V3 handles this explicitly](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol#L116).

---

## 📖 Production Study Order

Study these codebases in order — each builds on the previous one's patterns:

| # | Repository | Why Study This | Key Files |
|---|-----------|----------------|-----------|
| 1 | [Compound V3 Comet](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) | Simplest production lending codebase (~4,300 lines) — single-asset model, signed principal, immutable params | `contracts/Comet.sol`, `contracts/CometExt.sol` |
| 2 | [Aave V3 Core](https://github.com/aave/aave-v3-core) | The dominant lending architecture — library pattern, aTokens, debt tokens, index accrual | `contracts/protocol/pool/Pool.sol`, `contracts/protocol/libraries/logic/SupplyLogic.sol`, `contracts/protocol/libraries/logic/BorrowLogic.sol` |
| 3 | [Aave V3 LiquidationLogic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol) | Production liquidation: close factor, collateral seizure, minimum position rules | `contracts/protocol/libraries/logic/LiquidationLogic.sol` |
| 4 | [Aave V3 Interest Rate Strategy](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol) | The kinked curve in production — parameter encoding, compound interest approximation in MathUtils | `contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol`, `contracts/protocol/libraries/math/MathUtils.sol` |
| 5 | [Morpho Blue](https://github.com/morpho-org/morpho-blue) | Minimal lending core (~650 lines) — permissionless isolated markets, no governance, no upgradeability | `src/Morpho.sol`, `src/libraries/` |
| 6 | [Liquity V1](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/) | CDP-style lending with zero governance — redemption mechanism, stability pool, recovery mode | `contracts/BorrowerOperations.sol`, `contracts/TroveManager.sol`, `contracts/StabilityPool.sol` |

**Reading strategy:** Start with Compound V3 (smallest codebase, single file). Then Aave V3 — trace one flow end-to-end (supply → index update → aToken mint). Study liquidation separately. Read the interest rate strategy to see the kinked curve in production. Morpho Blue shows the minimalist alternative. Liquity shows CDP-style lending with no governance dependency.

---

## 🔗 Cross-Module Concept Links

**The lending module is the curriculum's crossroads** — nearly every other module either feeds into it (oracles, tokens) or builds on it (flash loans, stablecoins, vaults).

### ← Backward References (Part 1 + Modules 1–3)

| Source | Concept | How It Connects |
|--------|---------|-----------------|
| Part 1 Module 1 | Bit manipulation / UDVTs | Aave's `ReserveConfigurationMap` packs all risk params into a single `uint256` bitmap — production example of Module 1 patterns |
| Part 1 Module 1 | `mulDiv` / fixed-point math | RAY (27-decimal) arithmetic for index calculations; `rayMul`/`rayDiv` used in every balance computation |
| Part 1 Module 1 | Custom errors | Aave V3 uses custom errors for revert reasons; Compound V3 uses custom errors throughout Comet |
| Part 1 Module 2 | Transient storage | Reentrancy guards in lending pools; V4-era lending integrations can use TSTORE for flash accounting |
| Part 1 Module 3 | Permit / Permit2 | Gasless approvals for supply/repay operations; Compound V3 supports EIP-2612 permit natively |
| Part 1 Module 5 | Fork testing / `vm.mockCall` | Essential for testing against live Aave/Compound state and simulating oracle price movements |
| Part 1 Module 5 | Invariant / fuzz testing | Property-based testing for lending invariants: total debt ≤ total supply, HF checks, index monotonicity |
| Part 1 Module 6 | Proxy patterns | Both Aave V3 (Pool proxy + logic libraries) and Compound V3 (Comet proxy + CometExt fallback) use proxy architecture |
| Module 1 | SafeERC20 / token decimals | Safe transfers for supply/withdraw/liquidate; decimal normalization when computing collateral values across different tokens |
| Module 2 | Constant product / mechanism design | AMMs use `x × y = k` to set prices; lending uses kinked curves to set rates — both replace human market-makers with math |
| Module 2 | DEX liquidity for liquidation | Liquidators sell seized collateral on AMMs; pool depth determines liquidation feasibility for illiquid assets |
| Module 3 | Chainlink consumer / staleness | Lending protocols are the #1 consumer of oracles — every M3 pattern (staleness, deviation, L2 sequencer) is load-bearing here |
| Module 3 | Dual oracle / fallback | Liquity's 5-state oracle machine directly protects lending liquidation triggers |

### → Forward References (Modules 5–9 + Part 3)

| Target | Concept | How Lending Knowledge Applies |
|--------|---------|-------------------------------|
| Module 5 (Flash Loans) | Flash loan liquidation | Flash loans enable zero-capital liquidation — borrow → liquidate → swap → repay atomically |
| Module 6 (Stablecoins) | CDP liquidation | CDPs are a specialized lending model where the "borrowed" asset is minted (DAI); same HF math, same liquidation triggers |
| Module 7 (Yield/Vaults) | Index-based accounting | ERC-4626 share pricing uses the same `scaledBalance × index` pattern; vaults use `totalAssets / totalShares` instead of accumulating index |
| Module 7 (Yield/Vaults) | aToken composability | aTokens as yield-bearing inputs to vault strategies; auto-compounding aToken deposits |
| Module 8 (Security) | Economic attack modeling | Reserve factor determines treasury growth; economic exploits target the gap between reserves and potential bad debt |
| Module 8 (Security) | Invariant testing targets | Lending pool invariants (solvency, HF consistency, index monotonicity) are prime targets for formal verification |
| Module 9 (Integration) | Full-stack lending integration | Capstone combines lending + AMMs + oracles + flash loans in a production-grade protocol |
| Part 3 Module 8 (Governance) | Governance attack surface | Credit delegation and risk parameter changes create governance attack vectors; lending param manipulation |
| Part 3 Module 6 (Cross-chain) | Cross-chain lending | L2 ↔ L1 collateral, shared liquidity across chains — extending lending architecture cross-chain |

---

## 📋 Key Takeaways

**1. Interest rates are mechanism design.** The kinked curve isn't arbitrary — it's a carefully calibrated incentive system that uses price signals (rates) to maintain liquidity equilibrium. When you build a protocol that needs to balance supply and demand, this pattern is reusable.

**2. Indexes are the universal scaling pattern.** Every lending protocol uses global indexes to amortize per-user interest computation. You'll see this pattern again in vaults (Module 7) and staking systems.

**3. Liquidation is the protocol's immune system.** Without it, the first price crash would create cascading insolvency. The entire lending model depends on liquidation being reliable, fast, and properly incentivized.

**4. Oracle integration is load-bearing.** Everything in lending — health factor, liquidation trigger, collateral valuation — depends on accurate, timely price data. The oracle patterns from Module 3 aren't theoretical here; they're the difference between a $20B protocol and a drained one.

**5. Architectural trade-offs are real.** Aave's multi-asset pools offer flexibility and composability (yield-bearing aTokens). Compound's single-asset markets offer simplicity and risk isolation. Neither is strictly better — your choice depends on what you're building.

**6. RAY precision and rounding direction are protocol-critical.** 27-decimal precision prevents compounding errors over time. Rounding against the user (down for deposits, up for debt) prevents drain attacks across millions of tiny operations.

**7. Modular lending is the emerging trend.** Morpho Blue (~650 lines), Euler V2 vault graphs, and Aave's own V3.1+ updates all point toward smaller, composable, permissionless market creation — away from monolithic pools governed by token votes.

**8. The `type(uint256).max` pattern solves the dust problem.** Because interest accrues between tx submission and execution, users can never calculate the exact repayment amount. The "max repay" pattern is a production necessity, not a convenience.

---

## 📚 Resources

**Aave V3:**
- [Protocol documentation](https://aave.com/docs)
- [Source code](https://github.com/aave/aave-v3-core) (deployed May 2022)
- [Risk parameters dashboard](https://app.aave.com)
- [Technical paper](https://github.com/aave/aave-v3-core/blob/master/techpaper/Aave_V3_Technical_Paper.pdf)
- [MixBytes architecture analysis](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-aave-v3)
- [Cyfrin Aave V3 course](https://updraft.cyfrin.io/courses/aave-v3)

**Compound V3:**
- [Documentation](https://docs.compound.finance)
- [Source code](https://github.com/compound-finance/comet) (deployed August 2022)
- [RareSkills Compound V3 Book](https://rareskills.io/compound-v3-book)
- [RareSkills architecture walkthrough](https://rareskills.io/post/compound-v3-contracts-tutorial)

**Interest rate models:**
- [RareSkills — Aave/Compound interest rate models](https://rareskills.io/post/aave-interest-rate-model)
- [Aave interest rate strategy contracts](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol) (on-chain)

**Advanced / Emerging:**
- [Morpho Blue](https://github.com/morpho-org/morpho-blue) — minimal lending core (~650 lines), permissionless market creation
- [MetaMorpho](https://github.com/morpho-org/metamorpho) — ERC-4626 vault layer on top of Morpho Blue
- [Euler V2](https://docs.euler.finance) — modular vault architecture with connector system
- [GHO stablecoin](https://github.com/aave/gho-core) — Aave's native stablecoin via facilitator pattern
- [Berkeley DeFi MOOC — Lending protocols](https://berkeley-defi.github.io)

**Exploits and postmortems:**
- [Euler Finance postmortem](https://rekt.news/euler-rekt/) — $197M donation attack
- [Radiant Capital postmortem](https://rekt.news/radiant-capital-rekt/) — $4.5M flash loan rounding exploit
- [Rari Capital/Fuse postmortem](https://rekt.news/rari-capital-rekt/) — $80M reentrancy
- [Cream Finance postmortem](https://rekt.news/cream-rekt-2/) — $130M oracle manipulation
- [Hundred Finance postmortem](https://rekt.news/agave-hundred-rekt/) — $7M [ERC-777](https://eips.ethereum.org/EIPS/eip-777) reentrancy
- [Venus Protocol postmortem](https://rekt.news/venus-blizz-rekt/) — $11M stale oracle
- [CRV liquidity crisis analysis](https://cointelegraph.com/news/curve-liquidation-risk-poses-systemic-threat-to-defi-even-as-founder-scurries-to-repay-loans) — bad debt accumulation
- [MakerDAO Black Thursday report](https://web.archive.org/web/2024/https://blog.makerdao.com/the-market-collapse-of-march-12-2020-how-it-impacted-makerdao/) — liquidation cascades

---

## 🎯 Practice Challenges

- **[Damn Vulnerable DeFi #2 "Naive Receiver"](https://www.damnvulnerabledefi.xyz/)** — A flash loan receiver that can be drained by anyone initiating loans on its behalf. Tests your understanding of flash loan receiver security (directly relevant to Module 5).
- **[Ethernaut #16 "Preservation"](https://ethernaut.openzeppelin.com/level/0x97E982a15FbB1C28F6B8ee971BEc15C78b3d263F)** — Delegatecall with storage collision. Relevant to understanding how proxy patterns (Part 1 Module 6) can go wrong in lending protocol upgrades.

---

**Navigation:** [← Module 3: Oracles](3-oracles.md) | [Module 5: Flash Loans →](5-flash-loans.md)

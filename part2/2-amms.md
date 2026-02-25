# Part 2 — Module 2: AMMs from First Principles

**Duration:** ~12 days (3–4 hours/day)
**Prerequisites:** Module 1 complete (token mechanics, SafeERC20)
**Pattern:** Math → Build minimal version → Read production code → Extend
**Builds on:** Module 1 (SafeERC20, balance-before-after), Part 1 Section 5 (Foundry, fork testing)
**Used by:** Module 3 (TWAP oracles), Module 4 (liquidation swaps), Module 5 (flash swaps/arbitrage), Module 9 (integration capstone)

---

## 📚 Table of Contents

**The Constant Product Formula**
- [The Math](#amm-math)
- [Build: Minimal Constant Product Pool](#build-cpp)

**Reading Uniswap V2**
- [Read: UniswapV2Pair.sol](#read-v2-pair)
- [Read: UniswapV2Factory.sol](#read-v2-factory)
- [Read: UniswapV2Router02.sol](#read-v2-router)
- [V2 Exercises](#v2-exercises)

**Concentrated Liquidity (V3)**
- [The Problem V3 Solves](#v3-problem)
- [Core V3 Concepts](#v3-concepts)
- [Read: Key V3 Contracts](#read-v3-contracts)
- [V3 Exercises](#v3-exercises)

**Build a Simplified CLAMM**

**V4 — Singleton Architecture and Flash Accounting**
- [Read: Key V4 Contracts](#read-v4-contracts)
- [V4 Exercises](#v4-exercises)

**V4 Hooks**
- [The 10 Hook Functions](#hook-functions)
- [Hook Capabilities](#hook-capabilities)
- [Read: Hook Examples](#read-hook-examples)
- [Hook Security Considerations](#hook-security)
- [Build: A Simple Hook](#build-hook)

**Beyond Uniswap and Advanced AMM Topics**
- [AMMs vs Order Books (CLOBs)](#amms-vs-clobs)
- [Curve StableSwap](#curve-stableswap)
- [Balancer Weighted Pools](#balancer-weighted)
- [Trader Joe Liquidity Book](#trader-joe-lb)
- [ve(3,3) DEXes (Velodrome / Aerodrome)](#ve33-dexes)
- [MEV & Sandwich Attacks](#mev-sandwich)
- [JIT (Just-In-Time) Liquidity](#jit-liquidity)
- [AMM Aggregators & Routing](#amm-aggregators-routing)
- [LP Management Strategies](#lp-management)

**Practice Challenges and Review**

---

## Why This Is the Longest Module

**Why this matters:** AMMs are the foundation of decentralized finance. Lending protocols need them for liquidations. Aggregators route through them. Yield strategies compose on top of them. Intent systems like [UniswapX](https://uniswap.org/whitepaper-uniswapx.pdf) exist to improve on them. If you're going to build your own protocols, you need to understand AMMs deeply — not just the interface, but the math, the design trade-offs, and the evolution from V2's elegant simplicity through V3's concentrated liquidity to V4's programmable hooks.

> **Real impact:** [Uniswap V3 processes $1.5+ trillion in annual volume](https://dune.com/hagaetc/uniswap-metrics) (2024). The entire DeFi ecosystem — $50B+ TVL across lending, derivatives, yield — depends on AMM liquidity for price discovery and liquidations.

This module is 12 days because you're building one from scratch, then studying three generations of production AMM code, plus exploring alternative AMM designs and the advanced topics (MEV, aggregators, LP management) that every protocol builder needs.

> **Deep dive:** [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf), [V3 Whitepaper](https://uniswap.org/whitepaper-v3.pdf), [V4 Whitepaper](https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper/whitepaper-v4.pdf)

---

## The Constant Product Formula

<a id="amm-math"></a>
### 💡 The Math

**Why this matters:** Every AMM begins with a single equation: **x · y = k**

Where `x` is the reserve of token A, `y` is the reserve of token B, and `k` is a constant that only changes when liquidity is added or removed. This equation defines a hyperbolic curve — every valid state of the pool sits on this curve.

**Why this formula works:**

The constant product creates a price that changes proportionally to how much of the reserves you consume. Small trades barely move the price. Large trades move it significantly. The pool can never be fully drained of either token (the curve approaches but never touches the axes).

**Price from reserves:**

The spot price of token A in terms of token B is simply `y / x`. This falls directly out of the curve — the slope of the tangent at any point gives the instantaneous exchange rate.

**Calculating swap output:**

When a trader sends `dx` of token A to the pool, they receive `dy` of token B. The invariant must hold:

```
(x + dx) · (y - dy) = k
```

Solving for `dy`:

```
dy = y · dx / (x + dx)
```

This is the *output amount* formula. Notice it's nonlinear — as `dx` increases, `dy` increases at a decreasing rate. This is **price impact** (also called slippage, though technically slippage refers to price movement between submission and execution).

**Fees:**

In practice, a fee is deducted from the input before computing the swap. With a 0.3% fee ([introduced by Uniswap V1](https://hackmd.io/@HaydenAdams/HJ9jLsfTz)):

```
dx_effective = dx · (1 - 0.003)
dy = y · dx_effective / (x + dx_effective)
```

The fee stays in the pool, increasing `k` over time. This is how LPs earn — the pool's reserves grow from accumulated fees.

> **Used by:** [Uniswap V2](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L159), [SushiSwap](https://github.com/sushiswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) (V2 fork), [PancakeSwap](https://github.com/pancakeswap/pancake-smart-contracts/blob/master/projects/exchange-protocol/contracts/PancakePair.sol) (V2 fork), and hundreds of other AMMs use this exact formula.

#### 🔍 Deep Dive: Visualizing the Constant Product Curve

**The curve `x · y = k` looks like this:**

```
  Token B
  (reserve1)
    │
 2000 ┤ ╲
    │   ╲
 1500 ┤    ╲
    │      ╲
 1000 ┤●───────╲────────── Pool starts here (1000, 1000), k = 1,000,000
    │         ╲
  750 ┤          ╲
    │            ╲
  500 ┤              ╲──── After buying 500 token A → pool has (500, 2000)
    │                 ╲       Trader got 1000 B for 500 A? NO! Let's calculate...
  250 ┤                    ╲
    │                       ╲
    └───┬───┬───┬───┬───┬───┬── Token A (reserve0)
      250 500 750 1000 1500 2000
```

**Let's trace a real swap on this curve:**

Pool starts: `x = 1000 ETH, y = 1000 USDC, k = 1,000,000`

Trader sells 100 ETH to the pool (no fee for simplicity):
```
New x = 1000 + 100 = 1100 ETH
New y = k / x = 1,000,000 / 1100 = 909.09 USDC
Output  = 1000 - 909.09 = 90.91 USDC
```

**Key insight:** The spot price was 1.0 USDC/ETH, but the trader got 90.91 USDC for 100 ETH — an effective price of 0.909 USDC/ETH. That's **~9% price impact** for consuming 10% of the reserves.

```
Price impact by trade size (starting from 1:1 pool):

Trade size     │ Output    │ Effective price │ Price impact
(% of reserve) │           │                 │
───────────────┼───────────┼─────────────────┼─────────────
1%   (10 ETH)  │ 9.90 USDC │ 0.990 USDC/ETH  │ ~1.0%
5%   (50 ETH)  │ 47.62     │ 0.952           │ ~4.8%
10% (100 ETH)  │ 90.91     │ 0.909           │ ~9.1%
25% (250 ETH)  │ 200.00    │ 0.800           │ ~20%
50% (500 ETH)  │ 333.33    │ 0.667           │ ~33%
```

**The takeaway:** Price impact is NOT linear. It accelerates as you consume more of the reserves. This is why large trades need to be split across multiple DEXes (see [AMM Aggregators](#amm-aggregators-routing) later in this module).

💻 **Quick Try:**

Verify the constant product formula with this Foundry test:

```solidity
// In Foundry console or a quick test
function test_ConstantProduct() public pure {
    uint256 x = 1000e18; // 1000 ETH
    uint256 y = 1000e18; // 1000 USDC
    uint256 k = x * y;

    // Trader sells 100 ETH
    uint256 dx = 100e18;
    uint256 dy = (y * dx) / (x + dx); // output formula

    // Verify: k should be maintained
    uint256 newK = (x + dx) * (y - dy);
    assert(newK >= k); // Equal without fees, > k with fees

    // Verify: output is ~90.91 USDC (with 18 decimals)
    assert(dy > 90e18 && dy < 91e18);
}
```

Deploy and verify the price impact matches the table above. Then add the 0.3% fee and see how it changes the output.

**Impermanent loss:**

**Why this matters:** When the price of token A rises relative to token B, arbitrageurs buy A from the pool (cheap) and sell it on external markets. This re-balances the pool but means LPs end up with less A and more B than if they had just held. The difference between "hold" and "LP" value is impermanent loss.

It's called "impermanent" because it reverses if the price returns to the original ratio — but in practice, for volatile pairs, it's very real.

The formula for impermanent loss given a price change ratio `r`:

```
IL = 2·√r / (1 + r) - 1
```

For a 2x price move: ~5.7% loss. For a 5x price move: ~25.5% loss. LPs need fee income to exceed IL to be profitable.

> **Real impact:** During the May 2021 crypto crash, many ETH/USDC LPs on Uniswap V2 experienced 20-30% impermanent loss as ETH dropped from $4,000 to $1,700. Fee income over the same period was only ~5-8%, resulting in net losses compared to simply holding.

#### 🔍 Deep Dive: Impermanent Loss Step-by-Step

**Setup:** You deposit 1 ETH + 1000 USDC into a pool (ETH price = $1000). Your share is 10% of the pool.

```
Pool:    10 ETH + 10,000 USDC       k = 100,000
Your LP: 10% of pool = 1 ETH + 1,000 USDC = $2,000 total
HODL:    1 ETH + 1,000 USDC = $2,000
```

**ETH price doubles to $2000.** Arbitrageurs buy cheap ETH from the pool until the pool price matches:

```
New pool reserves (k must stay 100,000):
  price = y/x = 2000 → y = 2000x
  x · 2000x = 100,000 → x = √50 ≈ 7.071 ETH
  y = 100,000 / 7.071 ≈ 14,142 USDC

Your 10% LP share:
  0.7071 ETH ($1,414.21) + 1,414.21 USDC = $2,828.43

If you had just held:
  1 ETH ($2,000) + 1,000 USDC = $3,000

Impermanent Loss = $2,828.43 / $3,000 - 1 = -5.72%
```

**Verify with the formula:**
```
r = 2 (price doubled)
IL = 2·√2 / (1 + 2) - 1 = 2.828 / 3 - 1 = -0.0572 = -5.72% ✓
```

**IL at various price changes:**
```
Price change │ IL      │ In dollar terms ($2000 initial)
─────────────┼─────────┼─────────────────────────────────
1.25x        │ -0.6%   │ LP: $2,236 vs HODL: $2,250 → $14 lost
1.5x         │ -2.0%   │ LP: $2,449 vs HODL: $2,500 → $51 lost
2x           │ -5.7%   │ LP: $2,828 vs HODL: $3,000 → $172 lost
3x           │ -13.4%  │ LP: $3,464 vs HODL: $4,000 → $536 lost
5x           │ -25.5%  │ LP: $4,472 vs HODL: $6,000 → $1,528 lost
0.5x (drop)  │ -5.7%   │ LP: $1,414 vs HODL: $1,500 → $86 lost
```

**Why LPs accept this:** Fee income. If the ETH/USDC pool earns 30% APR in fees, the LP is profitable as long as the price doesn't move more than ~5x in a year. For stablecoin pairs (minimal price movement), fee income almost always exceeds IL.

**The mental model:** By LP-ing, you're continuously selling the winning token and buying the losing one. You're essentially selling volatility — profitable when fees > IL, unprofitable when the price moves too far.

> **Deep dive:** [Pintail's IL calculator](https://dailydefi.org/tools/impermanent-loss-calculator/), [Bancor IL research](https://blog.bancor.network/beginners-guide-to-getting-rekt-by-impermanent-loss-7c9510cb2f22)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What is impermanent loss and when does it matter?"**
   - Good answer: "IL is the difference between LP value and holding value. It's caused by arbitrageurs rebalancing the pool after external price changes."
   - Great answer: "LPs are implicitly short volatility — they sell the appreciating token and buy the depreciating one as the pool rebalances. IL = `2√r/(1+r) - 1` where r is the price ratio change. For a 2x move, that's ~5.7%. But IL is just a snapshot — the more accurate framework is LVR (Loss-Versus-Rebalancing), which measures the continuous cost of CEX-DEX arbitrageurs trading against stale AMM prices. LVR scales with σ² (volatility squared), which is why volatile pairs are so much more expensive to LP. For stablecoin pairs, both IL and LVR are near zero, making fee income almost pure profit. The key question is always: do fees exceed LVR? For most volatile pairs on V3, the answer is barely — especially with JIT liquidity extracting 5-10% of fee revenue."

**Interview Red Flags:**
- 🚩 Saying "impermanent loss isn't real" — it is real, and LVR makes it even more concrete
- 🚩 Only knowing IL but not LVR — shows outdated understanding of LP economics
- 🚩 Not understanding that LPs are selling volatility (short gamma)

**Pro tip:** In interviews, mention LVR by name and cite the Milionis et al. paper — it shows you follow DeFi research, not just Twitter summaries.

#### 🔍 Deep Dive: Beyond IL — The LVR Framework

**Why this matters:** Impermanent loss is the classic way to measure LP costs, but it only captures the loss at the moment of withdrawal. The DeFi research community has moved to **LVR (Loss-Versus-Rebalancing)** as the more accurate framework — and it's increasingly expected knowledge in interviews at serious DeFi teams.

**The core insight:**

IL compares "LP position" vs "holding." But that's not the right comparison for a professional market maker. The right comparison is: "LP position" vs "a portfolio that continuously rebalances to the same token ratio at market prices."

```
IL perspective (snapshot):
  "I deposited at price X, now the price is Y, I lost Z% vs holding"
  → Only matters at withdrawal. Reversible if price returns.

LVR perspective (continuous):
  "Every time the price moves on Binance, an arbitrageur trades against
   my AMM position at a stale price. The difference between the stale
   AMM price and the true market price is value extracted from me."
  → Accumulates continuously. NEVER reverses. Scales with volatility.
```

**Why LVR is more useful than IL:**

1. **IL can be zero while LPs are losing money.** If the price moves to 2x and back to 1x, IL = 0. But LVR accumulated the entire time — arbers profited on the way up AND on the way down.
2. **LVR explains WHY passive LPing loses.** The cost is real-time extraction by informed traders (mostly CEX-DEX arbitrageurs), not just an abstract "the price moved."
3. **LVR informs protocol design.** Dynamic fee mechanisms (like V4 hooks that increase fees during volatility) are designed to offset LVR, not IL.

**The formula (for full-range CPMM):**
```
LVR / V ≈ σ² / 8   (annualized, as fraction of pool value)

Where:
  σ = asset volatility (annualized)
  V = pool value
```

LVR scales with the *square* of volatility — which is why volatile pairs are so much more expensive to LP. A 2x increase in volatility → 4x increase in LVR.

**The practical takeaway for protocol builders:**

Fees must exceed LVR, not just IL, for LPs to profit. When evaluating whether a pool can sustain liquidity, estimate LVR from historical volatility and compare against fee income. This is what Arrakis, Gamma, and other LP managers actually optimize for.

> **Deep dive:** [Milionis et al. "Automated Market Making and Loss-Versus-Rebalancing" (2022)](https://arxiv.org/abs/2208.06046), [a16z LVR explainer](https://a16zcrypto.com/posts/article/lvr-quantifying-the-cost-of-providing-liquidity-to-automated-market-makers/), [Tim Roughgarden's LVR lecture](https://www.youtube.com/watch?v=cB-4pjhJHl8)

#### 🔗 DeFi Pattern Connection

**Where the constant product formula matters beyond AMMs:**

1. **Lending liquidations (Module 4):** Liquidation bots swap collateral through AMMs — price impact from the constant product formula determines whether liquidation is profitable
2. **Oracle design (Module 3):** TWAP oracles built on AMM prices inherit the constant product curve's properties — large trades cause large price movements that accumulate in TWAP
3. **Stablecoin pegs (Module 6):** Curve's StableSwap modifies the constant product formula for near-1:1 assets — understanding `x·y=k` is prerequisite for understanding Curve's hybrid invariant

---

<a id="build-cpp"></a>
### 🛠️ Build: Minimal Constant Product Pool

**Workspace:** [`workspace/src/part2/module2/exercise1-constant-product/`](../workspace/src/part2/module2/exercise1-constant-product/) — starter file: [`ConstantProductPool.sol`](../workspace/src/part2/module2/exercise1-constant-product/ConstantProductPool.sol), tests: [`ConstantProductPool.t.sol`](../workspace/test/part2/module2/exercise1-constant-product/ConstantProductPool.t.sol)

**Build a `ConstantProductPool.sol`** with these features:

**Core state:**
- `reserve0`, `reserve1` — current token reserves
- `totalSupply` of LP tokens (use a simple internal accounting, or inherit [ERC-20](https://eips.ethereum.org/EIPS/eip-20) ([OZ implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol)))
- `token0`, `token1` — the two ERC-20 token addresses
- `FEE_NUMERATOR = 3`, `FEE_DENOMINATOR = 1000` — 0.3% fee

**Functions to implement:**

**1. `addLiquidity(uint256 amount0, uint256 amount1) → uint256 liquidity`**

First deposit: LP tokens minted = `√(amount0 · amount1)` (geometric mean). Burn a `MINIMUM_LIQUIDITY` (1000 wei) to the zero address to prevent the pool from ever being fully drained (this is a critical anti-manipulation measure — read the [Uniswap V2 whitepaper section 3.4](https://uniswap.org/whitepaper.pdf) on this).

> **Why this matters:** Without minimum liquidity lock, an attacker can donate tiny amounts to manipulate the LP token price to extreme values, then exploit protocols that use LP tokens as collateral. [Analysis by Haseeb Qureshi](https://medium.com/dragonfly-research/unbundling-uniswap-the-future-of-on-chain-trading-is-abstraction-1f5d7c5c37c4).

Subsequent deposits: LP tokens minted proportionally to the smaller ratio:
```
liquidity = min(amount0 · totalSupply / reserve0, amount1 · totalSupply / reserve1)
```

This incentivizes depositors to add liquidity at the current ratio. If they deviate, they get fewer LP tokens (the excess is effectively donated to existing LPs).

> **Common pitfall:** Not checking both ratios. If you only check one token's ratio, an attacker can donate the other token to manipulate the LP token price. Always use `min()` of both ratios.

**2. `removeLiquidity(uint256 liquidity) → (uint256 amount0, uint256 amount1)`**

Burns LP tokens, returns proportional share of both reserves:
```
amount0 = liquidity · reserve0 / totalSupply
amount1 = liquidity · reserve1 / totalSupply
```

**3. `swap(address tokenIn, uint256 amountIn) → uint256 amountOut`**

Apply fee, compute output using constant product formula, transfer tokens. Update reserves.

Critical: use the balance-before-after pattern from Module 1 if you want to support fee-on-transfer tokens. For this exercise, you can start without it and add it as an extension.

**4. `getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) → uint256`**

Pure function implementing the swap math. This is the formula from above with fees applied.

> **Used by:** [Uniswap V2 Router](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L43) uses this exact function to compute multi-hop paths.

**Security considerations to implement:**

- **Reentrancy guard** on swap and liquidity functions ([OpenZeppelin ReentrancyGuard](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol))
- **Minimum liquidity** lock on first deposit
- **Reserve synchronization** — update reserves from actual balances after every operation
- **Zero-amount checks** — revert on zero deposits or zero output swaps
- **K invariant check** — after every swap, verify that `k_new >= k_old` (fees should only increase k)

> **Real impact:** Early AMM forks that skipped reentrancy guards were drained via flash loan attacks. Example: [Warp Finance exploit](https://rekt.news/warp-finance-rekt/) ($8M, December 2020) — reentrancy during LP token deposit allowed attacker to manipulate oracle price.

**Test suite:**

Write comprehensive Foundry tests covering:

- Add initial liquidity, verify LP token minting and MINIMUM_LIQUIDITY lock
- Add subsequent liquidity at correct ratio, verify proportional minting
- Add liquidity at incorrect ratio, verify the depositor gets fewer LP tokens
- Swap token0 for token1, verify output matches formula
- Swap with fee, verify fee stays in pool (k increases)
- Remove liquidity, verify proportional share returned
- Large swap (high price impact), verify output is sublinear
- Multiple sequential swaps, verify price moves in expected direction
- Sandwich scenario: large swap moves price, second swap at worse rate, then reverse
- Edge case: attempt to drain pool, verify it reverts or returns near-zero

> **Common pitfall:** Testing only with equal reserve ratios. Real pools drift over time as prices change. Test with imbalanced reserves (e.g., 1000:5000 ratio) to catch ratio-dependent bugs.

**Extension exercises:**

- Add a `getSpotPrice()` view function
- Add a `getAmountIn()` function (given desired output, compute required input)
- Add events: `Swap`, `Mint`, `Burn` (match [Uniswap V2's event signatures](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L13-L15))
- Implement a simple TWAP (time-weighted average price) oracle: store cumulative price and timestamp on each swap, expose a function to compute average price over a period

### 📋 Summary: The Constant Product Formula

**✓ Covered:**
- Constant product formula (`x · y = k`) and swap output calculation
- Price impact — nonlinear, accelerates with trade size
- Fee mechanics — fees stay in pool, increasing `k`
- Impermanent loss — formula, step-by-step walkthrough, dollar impact at various price changes
- Built a minimal constant product pool from scratch

**Next:** Read production V2 code and map it to your implementation.

---

## Reading Uniswap V2

### Why V2 Matters

**Why this matters:** Even though V3 and V4 exist, [Uniswap V2's codebase](https://github.com/Uniswap/v2-core) is the Rosetta Stone of DeFi. It's clean, well-documented, and every concept maps directly to what you just built. Most AMM forks in DeFi ([SushiSwap](https://github.com/sushiswap/sushiswap), [PancakeSwap](https://github.com/pancakeswap), hundreds of others) are V2 forks.

> **Real impact:** SushiSwap forked Uniswap V2 in September 2020, currently holds $300M+ TVL. Understanding V2 deeply means you can audit and reason about a huge swath of deployed DeFi.

> **Deep dive:** [Uniswap V2 Core contracts](https://github.com/Uniswap/v2-core) (May 2020 deployment), [V2 technical overview](https://docs.uniswap.org/contracts/v2/overview)

---

<a id="read-v2-pair"></a>
### 📖 Read: UniswapV2Pair.sol

**Source:** [github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)

Read the entire contract. Map every function to your own implementation. Focus on:

**`mint()` — Adding liquidity** ([line 110](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L110))
- How it uses `_mintFee()` to collect protocol fees *before* computing LP tokens
- The `MINIMUM_LIQUIDITY` lock (exactly what you implemented)
- How it reads balances directly from `IERC20(token0).balanceOf(address(this))` rather than relying on `amount` parameters — this is the "pull" pattern that makes V2 composable

> **Why this matters:** The balance-reading pattern means you can send tokens first, then call `mint()`. This enables flash mints and complex atomic transactions. [UniswapX uses this pattern](https://blog.uniswap.org/uniswapx-protocol).

**`burn()` — Removing liquidity** ([line 134](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L134))
- The same balance-reading pattern
- How it sends tokens back using `_safeTransfer` (their own SafeERC20 equivalent)

**`swap()` — The swap function** ([line 159](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L159))

This is the most important function to understand deeply.

- The **"optimistic transfer" pattern**: tokens are sent to the recipient *first*, then the invariant is checked. This is what enables flash swaps — you can receive tokens, use them, and return them (or the equivalent) in the same transaction.
- The `require(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000**2)` check — this is the k-invariant with fees factored in
- The callback to [`IUniswapV2Callee`](https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol) — this is the flash swap mechanism

> **Real impact:** Flash swaps enabled the entire flash loan arbitrage ecosystem. [Furucombo](https://furucombo.app/) aggregates flash swaps from multiple DEXes, [DeFi Saver](https://defisaver.com/) uses them for debt refinancing. Without this pattern, these protocols wouldn't exist.

> **Common pitfall:** Forgetting to implement the callback when using flash swaps. The pool calls your contract's `uniswapV2Call()` function — if it doesn't exist or doesn't return tokens, the transaction reverts with "K".

**`_update()` — Reserve and oracle updates** ([line 73](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L73))
- Cumulative price accumulators: `price0CumulativeLast` and `price1CumulativeLast`
- How TWAP oracles work: the price is accumulated over time, and external contracts can compute the time-weighted average by reading the cumulative value at two different timestamps
- The use of `UQ112.112` fixed-point numbers for precision

> **Used by:** [MakerDAO's OSM oracle](https://github.com/makerdao/osm), [Reflexer RAI](https://github.com/reflexer-labs/geb), [Liquity LUSD](https://github.com/liquity/dev) all use Uniswap V2 TWAP for price feeds.

> **Deep dive:** [Uniswap V2 Oracle guide](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/building-an-oracle), [TWAP manipulation risks](https://cmichel.io/pricing-lp-tokens/).

**`_mintFee()` — Protocol fee logic** ([line 88](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L88))
- If fees are on, the protocol takes 1/6th of LP fee growth (0.05% of the 0.3% swap fee)
- The clever math: instead of tracking fees directly, it compares `√k` growth between fee checkpoints

---

<a id="read-v2-factory"></a>
### 📖 Read: UniswapV2Factory.sol

**Source:** [github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol)

Focus on:
- [`createPair()`](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol#L23) — how `CREATE2` is used for deterministic addresses
- Why deterministic addresses matter: the Router can compute pair addresses without on-chain lookups (saves gas)
- The `feeTo` address for protocol fee collection

> **Why this matters:** CREATE2 determinism means you can compute a pair address off-chain before it exists. [Uniswap V2 Router uses this](https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol#L18) to avoid `SLOAD` for address lookups. [V3 and V4 both adopted this pattern](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol).

---

<a id="read-v2-router"></a>
### 📖 Read: UniswapV2Router02.sol

**Source:** [github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol)

This is the user-facing contract. Note how it:
- Wraps ETH to WETH transparently ([`swapExactETHForTokens`](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L224))
- Computes optimal liquidity amounts for adding liquidity
- Handles multi-hop swaps by chaining pair-to-pair transfers
- Enforces slippage protection via `amountOutMin` parameters
- Has deadline parameters to prevent stale transactions from executing

> **Common pitfall:** Not setting `amountOutMin` properly. Setting it to 0 means accepting any price — frontrunners will sandwich your trade for maximum slippage. Always compute expected output and use a reasonable slippage tolerance (e.g., 0.5-1% for volatile pairs).

> **Real impact:** [MEV-Boost searchers extract $500M+ annually](https://explore.flashbots.net/) from sandwich attacks on poorly configured trades. [Flashbots Protect RPC](https://docs.flashbots.net/flashbots-protect/overview) helps mitigate this.

---

<a id="v2-exercises"></a>
### Exercises

**Workspace:** [`workspace/test/part2/module2/exercise1b-v2-extensions/`](../workspace/test/part2/module2/exercise1b-v2-extensions/) — test-only exercise: [`V2Extensions.t.sol`](../workspace/test/part2/module2/exercise1b-v2-extensions/V2Extensions.t.sol) (implements `FlashSwapConsumer` and `SimpleRouter` inline, then runs tests for flash swaps, multi-hop routing, and TWAP)

**Exercise 1: Flash swap.** Using your own pool or a V2 fork, implement a flash swap consumer contract. Borrow tokens, "use" them (e.g., check arbitrage conditions), then return them with fee. Write tests verifying the flash swap callback works and that failing to return tokens reverts.

```solidity
// Example flash swap consumer
contract FlashSwapConsumer is IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        // Verify caller is a legitimate pair
        require(sender == address(this));

        // Do something with borrowed tokens
        // ...

        // Return tokens + 0.3% fee
        uint amountToRepay = amount0 > 0 ? amount0 * 1003 / 1000 : amount1 * 1003 / 1000;
        IERC20(token).transfer(msg.sender, amountToRepay);
    }
}
```

**Exercise 2: Multi-hop routing.** Create two pools (A/B and B/C) and implement a simple router that executes an A→C swap through both pools. Compute the optimal path off-chain and verify the output matches.

**Exercise 3: TWAP oracle consumer.** Deploy a pool, execute swaps at known prices, advance time with `vm.warp()`, and read the TWAP. Verify the oracle returns the time-weighted average.

> **Common pitfall:** Not accounting for price accumulator overflow. V2 uses uint256 for cumulative prices which can overflow. You must compute the difference modulo 2^256. [Example implementation](https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol).

#### 📖 How to Study Uniswap V2:

1. **Read tests first** — See how `mint()`, `burn()`, `swap()` are called in practice
2. **Read `getAmountOut()`** in UniswapV2Library.sol — This is just `dy = y·dx/(x+dx)` with fees. Match it to the formula you implemented
3. **Read `swap()`** — Understand optimistic transfer + k-check pattern. Trace the flash swap callback
4. **Read `mint()` and `burn()`** — Match to your own addLiquidity/removeLiquidity
5. **Read `_update()`** — TWAP oracle mechanics with cumulative price accumulators

**Don't get stuck on:** `_mintFee()` on first pass — it uses a clever `√k` growth comparison that's elegant but not essential for initial understanding.

---

#### 🎓 Intermediate Example: From V2 to V3

Before diving into V3's concentrated liquidity, notice the key limitation of V2:

```
V2 Pool: 10 ETH + 20,000 USDC (ETH at $2,000)

Liquidity is spread from price 0 → ∞
At the current price of $2,000, only a tiny fraction is "active"

If all the liquidity were concentrated between $1,800-$2,200:
  → Same dollar amount provides ~20x more effective depth
  → Trades in that range get ~20x less slippage
  → LPs earn ~20x more fees per dollar

This is exactly what V3 does — but it adds complexity:
  → LPs must choose their range
  → Positions go out of range (stop earning)
  → Each position is unique → NFTs instead of fungible LP tokens
  → The swap loop must cross tick boundaries
```

V3 trades simplicity for capital efficiency. Keep this tradeoff in mind as you read the next section.

### 📋 Summary: Reading Uniswap V2

**✓ Covered:**
- Read V2 Pair, Factory, and Router contracts
- Understood `mint()` / `burn()` / `swap()` — balance-reading pattern, optimistic transfers, k-invariant check
- Flash swap mechanism via `IUniswapV2Callee` callback
- TWAP oracle accumulators in `_update()`
- Protocol fee logic in `_mintFee()`
- CREATE2 deterministic addresses in Factory
- Exercises: flash swap consumer, multi-hop routing, TWAP oracle consumer

**Next:** Concentrated liquidity — how V3 achieves 2000x capital efficiency.

---

## Concentrated Liquidity (Uniswap V3 Concepts)

<a id="v3-problem"></a>
### 💡 The Problem V3 Solves

**Why this matters:** In V2, liquidity is spread uniformly across the entire price range from 0 to infinity. For a stablecoin pair like DAI/USDC, the price almost always stays between 0.99 and 1.01 — meaning ~99.5% of LP capital is sitting idle at extreme price ranges that never get traded. This is massively capital-inefficient.

V3 lets LPs choose a specific price range for their liquidity. Capital between 0.99–1.01 instead of 0–∞ means the same dollar amount provides ~2000x more effective liquidity.

> **Real impact:** [Uniswap V3 launched May 2021](https://uniswap.org/blog/uniswap-v3), currently holds $4B+ TVL with significantly less capital than V2's peak. The [USDC/ETH 0.05% pool](https://info.uniswap.org/#/pools/0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640) on V3 provides equivalent liquidity to V2's pool with ~10x less capital.

> **Deep dive:** [Uniswap V3 Whitepaper](https://uniswap.org/whitepaper-v3.pdf), [V3 Math Primer](https://blog.uniswap.org/uniswap-v3-math-primer)

---

<a id="v3-concepts"></a>
### 💡 Core V3 Concepts

**Ticks:**

V3 divides the price space into discrete points called ticks. Each tick `i` corresponds to a price:

```
price(i) = 1.0001^i
```

This means each tick represents a 0.01% price increment (1 basis point). Ticks range from -887272 to 887272, covering prices from effectively 0 to infinity.

Not every tick can be used for position boundaries — **tick spacing** limits where positions can start and end. Tick spacing depends on the fee tier:
- 0.01% fee → tick spacing 1
- 0.05% fee → tick spacing 10
- 0.3% fee → tick spacing 60
- 1% fee → tick spacing 200

> **Why this matters:** Tick spacing controls gas costs (fewer initialized ticks = lower gas) and prevents position fragmentation. [V3 fee tier guide](https://docs.uniswap.org/concepts/protocol/fees).

**Positions:**

An LP position is defined by: `(lowerTick, upperTick, liquidity)`. The position is "active" (earning fees) only when the current price is within the tick range. When the price moves outside the range, the position becomes entirely denominated in one token and stops earning fees.

> **Real impact:** During volatile markets, many V3 LPs see their positions go out of range and stop earning fees entirely. [On average, 60% of V3 liquidity is out of range](https://twitter.com/thiccythot_/status/1591565566068330496) at any given time. Active management is required.

**sqrtPriceX96:**

V3 stores prices as `√P · 2^96` — the square root of the price in Q96 fixed-point format. Two reasons:
1. The key AMM math formulas involve `√P` directly, so storing it avoids repeated square root operations
2. Q96 fixed-point gives 96 bits of fractional precision without floating-point, which Solidity doesn't support

To convert `sqrtPriceX96` to a human-readable price:
```
price = (sqrtPriceX96 / 2^96)^2
```

> **Deep dive:** [TickMath.sol library](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol) handles all tick ↔ sqrtPriceX96 conversions, [SqrtPriceMath.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol) computes token amounts.

#### 🔍 Deep Dive: Ticks, Prices, and sqrtPriceX96 Visually

**How ticks map to prices:**

```
Tick:    ...  -20000    0     20000    40000    60000   ...
Price:   ... 0.1353   1.0    7.389    54.60    403.4   ...
                       ↑
                    tick 0 = price 1.0
```

Every tick is a 0.01% (1 basis point) step. The relationship is exponential:
- Tick 0 → price 1.0
- Tick 10000 → price 1.0001^10000 ≈ 2.718 (≈ e!)
- Tick -10000 → price 1.0001^(-10000) ≈ 0.368

**Why square root? A visual intuition:**

The V3 swap formulas need `√P` everywhere. Instead of computing `√(1.0001^i)` every time, V3 stores `√P` directly and scales it by 2^96 for fixed-point precision:

```
                        sqrtPriceX96
Price        √Price     = √Price × 2^96           (2^96 = 79,228,162,514,264,337,593,543,950,336)
───────────────────────────────────────────────────────────────────────────
$1.00        1.0         79,228,162,514,264,337,593,543,950,336
$2,000       44.72       3,543,191,142,285,914,205,922,034,944
$100,000     316.23      25,054,144,837,504,793,118,641,380,156
$0.001       0.0316      2,505,414,483,750,479,311,864,138,816

Note: These are for ETH/USDC where price = USDC per ETH
      token0 = ETH (lower address), token1 = USDC
```

**Reading sqrtPriceX96 in practice:**

```
Given: sqrtPriceX96 = 3,543,191,142,285,914,205,922  (from slot0)

Step 1: Divide by 2^96
  √P = 3,543,191,142,285,914,205,922 / 79,228,162,514,264,337,593
  √P ≈ 44.72

Step 2: Square to get price
  P = 44.72² ≈ 2,000

→ ETH is trading at ~$2,000 USDC
```

**Tick spacing visually — what LPs can actually use:**

```
0.3% fee pool (tick spacing = 60):

Tick:   ... -120   -60    0     60    120   180   240  ...
Price:  ... 0.988  0.994  1.0   1.006 1.012 1.018 1.024 ...
                   ↑                   ↑
               Position A: 0.994 — 1.012 (ticks -60 to 120)
                          ↑       ↑
                    Position B: 1.0 — 1.006 (ticks 0 to 60) ← narrower, more concentrated

Position B has same capital in a tighter range → earns MORE fees per dollar
but goes out of range faster during price movements.
```

💻 **Quick Try:**

Play with tick-to-price conversions in Foundry:

```solidity
function test_TicksAndPrices() public pure {
    // tick 0 = price 1.0 → sqrtPriceX96 = 2^96
    uint160 sqrtPriceAtTick0 = uint160(1 << 96); // = 79228162514264337593543950336

    // For ETH at $2000 USDC, compute sqrtPriceX96:
    // √2000 ≈ 44.72
    // sqrtPriceX96 ≈ 44.72 × 2^96
    // In practice, use TickMath.getSqrtRatioAtTick()

    // Verify: tick 23027 ≈ $10 (1.0001^23027 ≈ 10)
    // tick 46054 ≈ $100
    // tick 69081 ≈ $1000
    // Each doubling of price ≈ +6931 ticks
}
```

Try computing: if ETH is at tick 86,841 relative to USDC, what's the approximate price? (Answer: 1.0001^86841 ≈ $5,900 — note: each +23,027 ticks ≈ 10× price, so 4 × 23,027 = 92,108 would be ~$10,000)

**The swap loop:**

In V2, a swap is one formula evaluation. In V3, a swap may cross multiple tick boundaries, each changing the active liquidity. The swap loop:
1. Compute how much of the swap can be filled within the current tick range
2. If the swap isn't fully filled, cross the tick boundary — activate/deactivate liquidity from positions at that tick
3. Repeat until the swap is filled or the price limit is reached

Between any two initialized ticks, the math is identical to V2's constant product — just with `L` (liquidity) potentially different in each range.

> **Common pitfall:** Assuming V3 swaps are always more gas-efficient than V2. For swaps that cross many ticks (e.g., 10+ tick crossings), V3 can be more expensive. [Gas comparison analysis](https://crocswap.medium.com/gas-efficiency-in-amms-1c2cd3c3e593).

**Liquidity (`L`):**

In V3, `L` represents the *depth* of liquidity at the current price. It relates to token amounts via:

```
Δtoken0 = L · (1/√P_lower - 1/√P_upper)
Δtoken1 = L · (√P_upper - √P_lower)
```

These formulas are why `√P` is stored directly — they simplify beautifully.

#### 🔍 Deep Dive: V3 Liquidity Math Step-by-Step

**Setup:** An LP wants to provide liquidity for ETH/USDC between $1,800 and $2,200 (current price = $2,000). To keep the math readable, we'll use abstract price units (not token-decimals-adjusted). The key is understanding the **formulas and ratios**, not the raw numbers.

```
Given:
  P_current = 2000,  √P_current = 44.72
  P_lower   = 1800,  √P_lower   = 42.43
  P_upper   = 2200,  √P_upper   = 46.90
  L = 1,000,000 (abstract units — see note below)

Token amounts needed (price is WITHIN range):

  Δtoken0 (ETH)  = L · (1/√P_current - 1/√P_upper)
                  = 1,000,000 · (1/44.72 - 1/46.90)
                  = 1,000,000 · (0.02236 - 0.02132)
                  = 1,000,000 · 0.00104
                  = 1,040

  Δtoken1 (USDC) = L · (√P_current - √P_lower)
                  = 1,000,000 · (44.72 - 42.43)
                  = 1,000,000 · 2.29
                  = 2,290,000

  Ratio check: 2,290,000 / 1,040 ≈ $2,202 per ETH ✓ (close to current price, as expected)
```

> **On-chain units:** In production V3, `L` is a `uint128` representing √(token0_amount × token1_amount) in wei-scale units. A real position providing ~1 ETH + ~2,290 USDC in this range would have L ≈ 1.54 × 10^15. The formulas above use simplified numbers to show the math clearly — the ratios and relationships are identical.

**What happens when price moves OUT of range:**
```
If ETH rises to $2,500 (above upper bound):
  → Position is 100% USDC, 0% ETH (LP sold all ETH on the way up)
  → Stops earning fees

If ETH drops to $1,500 (below lower bound):
  → Position is 100% ETH, 0% USDC (LP bought ETH all the way down)
  → Stops earning fees
```

**The key insight:** A narrower range requires LESS capital for the same liquidity depth `L`. That's capital efficiency — but the position goes out of range faster.

**LP tokens → NFTs:**

In V2, all LPs in a pool share fungible LP tokens. In V3, every position is unique (different range, different liquidity), so positions are represented as NFTs ([ERC-721](https://eips.ethereum.org/EIPS/eip-721)). This has major implications for composability — you can't just hold an ERC-20 LP token and deposit it into a farm; you need the NFT.

> **Real impact:** This NFT design broke composability with yield aggregators. [Arrakis](https://www.arrakis.finance/), [Gamma](https://www.gamma.xyz/), and [Uniswap's own PCSM](https://blog.uniswap.org/position-nft) emerged to manage V3 positions and provide fungible vault tokens.

**Fee accounting:**

Fees in V3 are tracked per unit of liquidity within active ranges using `feeGrowthGlobal` and per-tick `feeGrowthOutside` values. The math for computing fees owed to a specific position involves subtracting the fee growth "below" and "above" the position's range from the global fee growth. This is elegant but complex — study it closely.

> **Deep dive:** [V3 fee math explanation](https://uniswapv3book.com/docs/milestone_3/fees-and-price-oracle/), [Position.sol library](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/Position.sol#L61-L76)

---

<a id="read-v3-contracts"></a>
### 📖 Read: Key V3 Contracts

**Core contracts (v3-core):**
- [`UniswapV3Pool.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol) — the pool itself (swap, mint, burn, collect)
- [`UniswapV3Factory.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Factory.sol) — pool deployment with fee tiers

**Focus areas in UniswapV3Pool:**

- **[`swap()`](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol#L596)** — the main swap loop. Trace the `while` loop step by step. Understand `computeSwapStep()`, tick crossing, and how `state.liquidity` changes at tick boundaries.
- **[`mint()`](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol#L426)** — how positions are created, how tick bitmaps track initialized ticks
- **`_updatePosition()`** — fee growth accounting per position
- **`slot0`** — the packed storage slot holding `sqrtPriceX96`, `tick`, `observationIndex`, and other frequently accessed data

> **Common pitfall:** Not understanding tick bitmap navigation. V3 uses a clever bit-packing scheme where each word in the bitmap represents 256 ticks. [TickBitmap.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickBitmap.sol) handles this — read it carefully.

**Libraries:**
- [`TickMath.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol) — conversions between ticks and sqrtPriceX96
- [`SqrtPriceMath.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol) — token amount calculations given liquidity and price ranges
- [`SwapMath.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SwapMath.sol) — compute swap steps within a single tick range
- [`TickBitmap.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickBitmap.sol) — efficient lookup of the next initialized tick

> **Used by:** These libraries are extensively reused. [PancakeSwap V3](https://github.com/pancakeswap/pancake-v3-contracts), [Trader Joe V2.1](https://github.com/traderjoe-xyz/joe-v2), and many others fork or adapt V3's math libraries.

---

<a id="v3-exercises"></a>
### Exercises

**Workspace:** [`workspace/src/part2/module2/exercise2-v3-position/`](../workspace/src/part2/module2/exercise2-v3-position/) — starter file: [`V3PositionCalculator.sol`](../workspace/src/part2/module2/exercise2-v3-position/V3PositionCalculator.sol), tests: [`V3PositionCalculator.t.sol`](../workspace/test/part2/module2/exercise2-v3-position/V3PositionCalculator.t.sol)

**Exercise 1: Tick math implementation.** Write Solidity functions that convert between ticks, prices, and sqrtPriceX96. Verify against [TickMath.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol) outputs using Foundry tests. This will cement the relationship between these representations.

**Exercise 2: Position value calculator.** Given a position's `(tickLower, tickUpper, liquidity)` and the current `sqrtPriceX96`, compute how many of each token the position currently holds. Handle the three cases: price below range, price within range, price above range.

```solidity
// Skeleton — implement the three cases
function getPositionAmounts(
    uint160 sqrtPriceX96,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity
) public pure returns (uint256 amount0, uint256 amount1) {
    uint160 sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

    if (sqrtPriceX96 <= sqrtLower) {
        // Price BELOW range: position is 100% token0
        // amount0 = L · (1/√P_lower - 1/√P_upper)
        // TODO: implement using SqrtPriceMath
    } else if (sqrtPriceX96 >= sqrtUpper) {
        // Price ABOVE range: position is 100% token1
        // amount1 = L · (√P_upper - √P_lower)
        // TODO: implement using SqrtPriceMath
    } else {
        // Price WITHIN range: position holds both tokens
        // amount0 = L · (1/√P_current - 1/√P_upper)
        // amount1 = L · (√P_current - √P_lower)
        // TODO: implement using SqrtPriceMath
    }
}
```

Write tests that verify all three cases and check that amounts change continuously as price moves through the range boundaries.

**Exercise 3: Simulate a swap across ticks.** On paper or in a test, set up a pool with three positions at different ranges. Execute a large swap that crosses two tick boundaries. Trace the liquidity changes and verify the total output matches what V3 would produce.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Explain how Uniswap V3's concentrated liquidity works and why it matters."**
   - Good answer: "LPs choose a price range. Within that range, their capital provides the same liquidity depth as a much larger V2 position. It's more capital-efficient but requires active management."
   - Great answer: "V3 divides the price space into ticks at 1 basis point intervals. Between any two initialized ticks, the pool behaves like a V2 pool with liquidity L. The swap loop crosses tick boundaries, adding/removing liquidity from positions. sqrtPriceX96 is stored as the square root to simplify the core math formulas. The tradeoff is that LPs now compete with JIT liquidity providers and need active management — which spawned Arrakis, Gamma, and eventually V4 hooks for native LP management."

**Interview Red Flags:**
- 🚩 Not knowing what sqrtPriceX96 is or why prices are stored as square roots
- 🚩 Thinking V3 is always better than V2 (not true for high-volatility, low-volume pairs)
- 🚩 Unaware that ~60% of V3 liquidity is out of range at any given time

**Pro tip:** Be ready to trace through V3's swap loop (`computeSwapStep` → tick crossing → liquidity update). Teams want engineers who can debug at the source code level, not just explain concepts.

#### 📖 How to Study Uniswap V3:

1. **Start with the [V3 Development Book](https://uniswapv3book.com/)** — Build a simplified V3 alongside reading production code
2. **Read `SqrtPriceMath.sol` FIRST** — Pure math functions. Focus on inputs/outputs, not the bit manipulation
3. **Read `SwapMath.computeSwapStep()`** — One step of the swap loop, the core unit of work
4. **Read the `swap()` while loop** in UniswapV3Pool.sol — Now you see how steps compose into a full swap
5. **Read `Tick.sol` and `TickBitmap.sol` LAST** — Gas optimizations, important but not for first pass

**Don't get stuck on:** `FullMath.sol` (it's mulDiv for precision — you know this from Part 1), `Oracle.sol` (save for Module 3).

### 📋 Summary: Concentrated Liquidity (V3)

**✓ Covered:**
- Ticks (`price = 1.0001^i`), tick spacing, and fee tiers
- Positions as `(tickLower, tickUpper, liquidity)` — active only when price is in range
- `sqrtPriceX96` — why store `√P × 2^96`, how to convert to human-readable price
- V3 liquidity math (`Δtoken0`, `Δtoken1`) with worked numerical example
- The swap loop — crossing tick boundaries, active liquidity changes
- LP tokens → NFTs (each position is unique)
- Fee accounting with `feeGrowthGlobal` and per-tick tracking
- Read V3 Pool, Factory, and key libraries (TickMath, SqrtPriceMath, SwapMath)
- Exercises: tick math, position value calculator, swap simulation

**Next:** Build your own simplified CLAMM to internalize the swap loop.

---

## Build a Simplified Concentrated Liquidity Pool

### What to Build

You won't replicate V3's full complexity (the tick bitmap alone is a masterwork of gas optimization). Instead, build a simplified CLAMM (Concentrated Liquidity AMM) that captures the core mechanics:

**Simplified design:**

- Use a small, fixed set of tick boundaries (e.g., ticks every 100 units) instead of V3's full bitmap
- Support 3–5 concurrent positions
- Implement the swap loop that crosses ticks
- Track fees per position

**Contract: `SimpleCLAMM.sol`**

**State:**
```solidity
struct Position {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
}

uint160 public sqrtPriceX96;
int24 public currentTick;
uint128 public liquidity;  // active liquidity at current tick
mapping(int24 => TickInfo) public ticks;
mapping(bytes32 => Position) public positions;
```

**Functions:**

**1. `addLiquidity(int24 tickLower, int24 tickUpper, uint128 amount)`**
   - Compute token0 and token1 amounts needed for the given liquidity at the current price
   - Update tick data (add/remove liquidity at boundaries)
   - If the position range includes the current tick, add to active `liquidity`

**2. `swap(bool zeroForOne, int256 amountSpecified)`**
   - Implement the swap loop:
     - Compute the next initialized tick in the swap direction
     - Compute how much of the swap fills within the current range (use `SqrtPriceMath` formulas)
     - If the swap crosses a tick, update active liquidity and continue
     - Accumulate fees in `feeGrowthGlobal`

**3. `removeLiquidity(int24 tickLower, int24 tickUpper, uint128 amount)`**
   - Reverse of addLiquidity
   - Compute and distribute accrued fees to the position

**The key insight to internalize:**

Between any two initialized ticks, the pool behaves exactly like a V2 pool with liquidity `L`. The CLAMM is essentially a linked list of V2 segments, each with potentially different depth. The swap loop walks through these segments.

> **Deep dive:** [Uniswap V3 Development Book](https://uniswapv3book.com/) — comprehensive guide to building a V3 clone from scratch.

---

### Tests

- Create a single full-range position (equivalent to V2 behavior), verify swap outputs match your Constant Product Pool
- Create two overlapping positions, verify liquidity adds at overlapping ticks
- Execute a swap that crosses a tick boundary, verify liquidity changes correctly
- Verify fee accrual: position earning fees only while in range
- Out-of-range position: add liquidity above current price, verify it earns zero fees, verify it's 100% token0
- Impermanent loss test: add position, execute swaps that move price significantly, remove position, compare to holding

> **Common pitfall:** Not testing tick crossings in both directions. A swap buying token0 (decreasing price) crosses ticks differently than a swap buying token1 (increasing price). Test both directions.

### 📋 Summary: Simplified CLAMM Build

**✓ Covered:**
- Built a simplified CLAMM with `addLiquidity`, `swap` (with tick-crossing loop), `removeLiquidity`
- Understood V3's core insight: between any two initialized ticks, the pool behaves like V2 with liquidity `L`
- Fee accrual per position (only while in range)
- Tested tick crossings, overlapping positions, out-of-range behavior, IL comparison

**Next:** V4's singleton architecture — one contract to rule all pools.

---

#### 🎓 Intermediate Example: From V3 to V4

Before diving into V4, notice V3's key architectural limitation:

```
V3 multi-hop swap: ETH → USDC → DAI (two pools)

                    Pool A (ETH/USDC)          Pool B (USDC/DAI)
                    ┌──────────────┐           ┌──────────────┐
 User sends ETH ──→│ swap()       │──USDC──→  │ swap()       │──DAI──→ User receives DAI
                    │ (separate    │ (real     │ (separate    │ (real
                    │  contract)   │  ERC-20   │  contract)   │  ERC-20
                    └──────────────┘  transfer)└──────────────┘  transfer)

Token transfers: 3 (ETH in, USDC between pools, DAI out)
Gas cost: ~300k+ (each transfer = approve + transferFrom + balance updates)
```

What if all pools lived in the same contract?

```
V4 multi-hop swap: ETH → USDC → DAI (same PoolManager)

                    ┌─────────────────────────────────────────┐
                    │              PoolManager                 │
 User sends ETH ──→│                                         │──DAI──→ User receives DAI
                    │  Pool A: ETH delta: +1                  │
                    │          USDC delta: -2000               │
                    │  Pool B: USDC delta: +2000  ← cancels!  │
                    │          DAI delta: -1999                │
                    │                                         │
                    │  Net: ETH +1, DAI -1999 (only these move)│
                    └─────────────────────────────────────────┘

Token transfers: 2 (ETH in, DAI out — USDC never moves!)
Gas cost: ~200k (20-30% cheaper, and scales better with more hops)
```

V4 trades the simplicity of independent pool contracts for a singleton that tracks IOUs. The USDC delta from Pool A cancels with Pool B — it's just accounting. Combined with transient storage (TSTORE at 100 gas vs SSTORE at 2,100+), this makes complex multi-pool interactions dramatically cheaper.

---

## Uniswap V4 — Singleton Architecture and Flash Accounting

### 💡 Architectural Revolution

**Why this matters:** V4 is a fundamentally different architecture from V2/V3. The two key innovations make it significantly more gas-efficient and composable.

> **Real impact:** [V4 launched November 2024](https://blog.uniswap.org/uniswap-v4), pool creation costs dropped from ~5M gas (V3) to ~500 gas (V4) — a 10,000x reduction. Multi-hop swaps save 20-30% gas compared to V3.

**1. Singleton Pattern (PoolManager)**

In V2 and V3, every token pair gets its own deployed contract (created by the Factory). This means multi-hop swaps (A→B→C) require actual token transfers between pool contracts — expensive in gas.

V4 consolidates all pools into a single contract called [`PoolManager`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol). Pools are just entries in a mapping, not separate contracts. Creating a new pool is a state update, not a contract deployment — approximately 99% cheaper in gas.

The key benefit: multi-hop swaps never move tokens between contracts. All accounting happens internally within the PoolManager. Only the final net token movements are settled at the end.

> **Used by:** [Balancer V2 pioneered this pattern](https://github.com/balancer/balancer-v2-monorepo/tree/master/pkg/vault) with its Vault architecture (July 2021). V4 adopted and extended it with transient storage.

**2. Flash Accounting ([EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) Transient Storage)**

V4 uses [transient storage](https://eips.ethereum.org/EIPS/eip-1153) (which you studied in Part 1 Section 2) to implement "flash accounting." During a transaction:

1. The caller "unlocks" the PoolManager
2. The caller can perform multiple operations (swaps, liquidity changes) across any pools
3. The PoolManager tracks net balance changes ("deltas") in transient storage
4. At the end, the caller must settle all deltas to zero — either by transferring tokens or using [ERC-6909](https://eips.ethereum.org/EIPS/eip-6909) claim tokens
5. If deltas aren't zero, the transaction reverts

This is essentially flash-loan-like behavior baked into the protocol's core. You can swap A→B in one pool and B→C in another without ever transferring B — the PoolManager tracks that your B delta nets to zero.

> **Why this matters:** Transient storage (TSTORE/TLOAD) costs ~100 gas vs ~2,100+ gas for SSTORE/SLOAD. Flash accounting enables complex multi-pool interactions at a fraction of V3's cost.

> **Deep dive:** [V4 unlock pattern](https://docs.uniswap.org/contracts/v4/concepts/managing-positions), [Flash accounting explainer](https://www.paradigm.xyz/2023/06/uniswap-v4-flash-accounting)

**3. Native ETH Support**

Because flash accounting handles all token movements internally, V4 can support native ETH directly — no WETH wrapping needed. ETH transfers (`msg.value`) are cheaper than ERC-20 transfers, saving gas on the most common trading pairs.

> **Real impact:** ETH swaps in V4 save ~15,000 gas compared to WETH swaps in V3 (no `approve()` or `transferFrom()` needed for ETH).

**4. ERC-6909 Claim Tokens**

Instead of withdrawing tokens from the PoolManager, users can receive [ERC-6909](https://eips.ethereum.org/EIPS/eip-6909) tokens representing claims on tokens held by the PoolManager. These claims can be burned in future interactions instead of doing full ERC-20 transfers. This is a lightweight multi-token standard (simpler than [ERC-1155](https://eips.ethereum.org/EIPS/eip-1155)) optimized for gas.

> **Deep dive:** [EIP-6909 specification](https://eips.ethereum.org/EIPS/eip-6909), [V4 Claims implementation](https://github.com/Uniswap/v4-core/blob/main/src/ERC6909Claims.sol)

---

<a id="read-v4-contracts"></a>
### 📖 Read: Key V4 Contracts

**Source:** [github.com/Uniswap/v4-core](https://github.com/Uniswap/v4-core)

Focus on:
- **[`PoolManager.sol`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol)** — the singleton. Study [`unlock()`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol#L103), [`swap()`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol#L229), [`modifyLiquidity()`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol#L182), and the delta accounting system
- **[`Pool.sol`](https://github.com/Uniswap/v4-core/blob/main/src/libraries/Pool.sol) (library)** — the actual pool math, used by PoolManager. Note how it's a library, not a contract — keeping the PoolManager modular
- **`PoolKey`** — the struct that identifies a pool: `(currency0, currency1, fee, tickSpacing, hooks)`
- **`BalanceDelta`** — a packed int256 representing net token changes

**Periphery ([v4-periphery](https://github.com/Uniswap/v4-periphery)):**
- **[`PositionManager.sol`](https://github.com/Uniswap/v4-periphery/blob/main/src/PositionManager.sol)** — the entry point for LPs, manages positions as ERC-721 NFTs
- **`V4Router.sol`** / **Universal Router** — the entry point for swaps

> **Common pitfall:** Trying to call `swap()` directly on PoolManager. You must go through the `unlock()` pattern — your contract implements `unlockCallback()` which then calls `swap()`. [Example router implementation](https://github.com/Uniswap/v4-periphery/blob/main/src/V4Router.sol).

---

<a id="v4-exercises"></a>
### Exercises

**Workspace:** [`workspace/src/part2/module2/exercise3-dynamic-fee/`](../workspace/src/part2/module2/exercise3-dynamic-fee/) — starter file: [`DynamicFeeHook.sol`](../workspace/src/part2/module2/exercise3-dynamic-fee/DynamicFeeHook.sol), tests: [`DynamicFeeHook.t.sol`](../workspace/test/part2/module2/exercise3-dynamic-fee/DynamicFeeHook.t.sol)

**Exercise 1: Study the unlock pattern.** Trace through a simple swap: how does the caller interact with PoolManager? What's the sequence of `unlock()` → callback → `swap()` → `settle()` / `take()`? Draw the flow.

**Exercise 2: Multi-hop with flash accounting.** On paper, trace a three-pool multi-hop swap (A→B→C→D). Show how deltas accumulate and net to zero for intermediate tokens. Compare the token transfer count to V2/V3 equivalents.

**Exercise 3: Deploy PoolManager locally.** Fork mainnet or deploy V4 contracts to anvil. Create a pool, add liquidity, execute a swap. Observe the delta settlement pattern in practice.

```bash
# Fork mainnet to test V4
forge test --fork-url $MAINNET_RPC --match-contract V4Test
```

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Walk me through Uniswap V4's flash accounting. How does it save gas?"**
   - Good answer: "V4 uses a singleton contract and transient storage. Instead of transferring tokens between pool contracts for multi-hop swaps, it tracks balance changes (deltas) and only settles the net at the end."
   - Great answer: "V4's PoolManager consolidates all pools into one contract. When a caller `unlock()`s the PoolManager, it can perform multiple operations — swaps across different pools, liquidity changes — and the PoolManager tracks net balance changes per token using TSTORE/TLOAD (100 gas vs 2,100+ for SSTORE). For a 3-hop swap A→B→C→D, only A and D move — B and C deltas cancel to zero internally. The caller settles by transferring tokens or using ERC-6909 claim tokens. This saves 20-30% gas and eliminates intermediate token transfers entirely."

**Interview Red Flags:**
- 🚩 Not understanding the unlock → callback → settle pattern
- 🚩 Confusing V4's flash accounting with flash loans (related concepts but different mechanisms)

**Pro tip:** Mention that Balancer V2 pioneered the singleton Vault pattern and V4 extended it with transient storage — shows you understand the design lineage.

#### 📖 How to Study Uniswap V4:

1. **Read `PoolManager.unlock()`** and `IUnlockCallback` — Understand the interaction pattern before anything else
2. **Read the delta accounting** — How deltas are tracked, settled, and validated
3. **Read a simple hook** (FullRange or SwapCounter) — See the full hook lifecycle before complex hooks
4. **Read `Pool.sol` (library)** — V3's math adapted for V4's singleton, familiar territory
5. **Read `PositionManager.sol`** in v4-periphery — How the user-facing contract interacts with PoolManager

### 📋 Summary: V4 Singleton & Flash Accounting

**✓ Covered:**
- Singleton pattern — all pools in one PoolManager contract
- Flash accounting — delta tracking with transient storage, settle-at-end pattern
- `unlock()` → callback → operations → `settle()`/`take()` flow
- Native ETH support and ERC-6909 claim tokens
- Read PoolManager, Pool.sol library, PoolKey, BalanceDelta
- Exercises: unlock pattern tracing, multi-hop delta analysis, local V4 deployment

**Next:** V4 hooks — the extension mechanism that makes AMMs programmable.

---

## Uniswap V4 Hooks

### 💡 The Hook System

**Why this matters:** Hooks are external smart contracts that the PoolManager calls at specific points during pool operations. They are V4's extension mechanism — the "app store" for AMMs.

A pool is linked to a hook contract at initialization and cannot change it afterward. The hook address itself encodes which callbacks are enabled — specific bits in the address determine which hook functions the PoolManager will call. This is a gas optimization: the PoolManager checks the address bits rather than making external calls to query capabilities.

> **Real impact:** Over 100+ production hooks deployed in V4's first 3 months. Examples: [Clanker hook](https://www.clanker.world/) (meme coin launching), [Brahma hook](https://www.brahma.fi/) (MEV protection), [Full Range hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/FullRange.sol) (V2-style behavior).

> **Deep dive:** [Hooks documentation](https://docs.uniswap.org/contracts/v4/concepts/hooks), [Awesome Uniswap Hooks list](https://github.com/fewwwww/awesome-uniswap-hooks)

---

<a id="hook-functions"></a>
### The 10 Hook Functions

Hooks can intercept at these points:

**Pool lifecycle:**
- `beforeInitialize` / `afterInitialize` — when a pool is created

**Swaps:**
- `beforeSwap` / `afterSwap` — before and after swap execution

**Liquidity modifications:**
- `beforeAddLiquidity` / `afterAddLiquidity`
- `beforeRemoveLiquidity` / `afterRemoveLiquidity`

**Donations:**
- `beforeDonate` / `afterDonate` — donations send fees directly to in-range LPs

---

<a id="hook-capabilities"></a>
### Hook Capabilities

**Dynamic fees:** A hook can implement `getFee()` to return a custom fee for each swap. This enables strategies like: higher fees during volatile periods, lower fees for certain users, MEV-aware fee adjustment.

**Custom accounting:** Hooks can modify the token amounts involved in swaps. The `beforeSwap` return value can specify delta modifications, allowing the hook to effectively intercept and re-route part of the trade.

**Access control:** Hooks can implement KYC/AML checks, restricting who can swap or provide liquidity.

**Oracle integration:** A hook can maintain a custom oracle, updated on every swap — similar to V3's built-in oracle but customizable.

> **Used by:** [EulerSwap hook](https://www.euler.finance/) implements volatility-adjusted fees, [GeomeanOracle hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/GeomeanOracle.sol) provides TWAP oracles with better properties than V2/V3.

---

<a id="read-hook-examples"></a>
### 📖 Read: Hook Examples

**Source:** [github.com/Uniswap/v4-periphery/tree/main/src/hooks](https://github.com/Uniswap/v4-periphery/tree/example-contracts/contracts/hooks/examples) (official examples)
**Source:** [github.com/fewwwww/awesome-uniswap-hooks](https://github.com/fewwwww/awesome-uniswap-hooks) (curated community list)

Study these hook patterns:
- **[Limit order hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/LimitOrder.sol)** — converts a liquidity position into a limit order that executes when the price crosses a specific tick
- **[TWAMM hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/TWAMM.sol)** — time-weighted average market maker (execute large orders over time)
- **[Dynamic fee hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/VolatilityOracle.sol)** — adjusts fees based on volatility or other on-chain signals
- **[Full-range hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/FullRange.sol)** — enforces V2-style full-range liquidity for specific use cases

---

<a id="hook-security"></a>
### ⚠️ Hook Security Considerations

**Why this matters:** Hooks introduce new attack surfaces that don't exist in V2/V3.

> **Real impact:** [Cork Protocol exploit](https://medium.com/coinmonks/cork-protocol-exploit-analysis-9b8c866ff776) (July 2024) — hook didn't verify `msg.sender` was the PoolManager, allowing direct calls to manipulate internal state. Loss: $400k.

**Critical security patterns:**

**1. Access control** — Hooks MUST verify that `msg.sender` is the legitimate PoolManager. Without this check, attackers can call hook functions directly and manipulate internal state.

```solidity
// ✅ GOOD: Verify caller is PoolManager
modifier onlyPoolManager() {
    require(msg.sender == address(poolManager), "Not PoolManager");
    _;
}

function beforeSwap(...) external onlyPoolManager returns (...) {
    // Safe: only PoolManager can call
}
```

**2. Gas griefing** — A malicious or buggy hook with unbounded loops can make a pool permanently unusable by consuming all gas in swap transactions.

> **Common pitfall:** Hooks that iterate over unbounded arrays. If a hook stores a list of all past swaps and loops over it in `beforeSwap`, an attacker can make thousands of tiny swaps to bloat the array until gas limits are hit.

**3. Reentrancy** — Hooks execute within the PoolManager's context. If a hook makes external calls, it could re-enter the PoolManager.

```solidity
// ❌ BAD: External call during hook execution
function afterSwap(...) external returns (...) {
    externalContract.doSomething(); // Could re-enter PoolManager
}

// ✅ GOOD: Use checks-effects-interactions pattern
function afterSwap(...) external returns (...) {
    // Update state first
    lastSwapTime = block.timestamp;

    // Then external calls (if absolutely necessary)
    // Better: avoid external calls entirely in hooks
}
```

**4. Trust model** — Users must trust the hook contract as much as they trust the pool itself. A malicious hook can front-run swaps, extract MEV, or drain liquidity.

**5. Immutability** — Once a pool is initialized with a hook, the hook cannot be changed. If the hook has a bug, the pool must be abandoned and a new one created.

> **Common pitfall:** Not considering upgradability. If your hook needs to be upgradable, you must use a proxy pattern from the start. After pool initialization, you can't change the hook address, but you can change the hook's implementation if it's behind a proxy.

---

<a id="build-hook"></a>
### 🛠️ Build: A Simple Hook

**Exercise 1: Dynamic fee hook.** Build a hook that adjusts the swap fee based on recent volatility. Track the last N swap prices, compute a simple volatility metric, and return a higher fee when volatility is elevated. This teaches you the full hook development cycle:

- Extend [`BaseHook`](https://github.com/Uniswap/v4-hooks-public/blob/main/src/base/BaseHook.sol) from v4-periphery
- Set the correct hook address bits (use the [`Hooks`](https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol) library to mine an address with the right flags)
- Implement `beforeSwap` to adjust fees
- Deploy and test with a real PoolManager

```solidity
// Example: Mining a hook address with correct flags
// Hook address must have specific bits set to indicate which callbacks are enabled
contract VolatilityHook is BaseHook {
    using Hooks for IHooks;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,        // We need beforeSwap to adjust fees
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function beforeSwap(...) external override returns (...) {
        // Calculate volatility and return dynamic fee
    }
}
```

**Exercise 2: Swap counter hook.** Build a minimal hook that simply counts the number of swaps on a pool. This is the "hello world" of hooks — it gets you through the setup and deployment mechanics without complex logic.

**Exercise 3: Read an existing production hook.** Pick one from the [awesome-uniswap-hooks list](https://github.com/fewwwww/awesome-uniswap-hooks) (Clanker, EulerSwap, or the [Full Range hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/FullRange.sol) from Uniswap themselves). Read the source, understand what lifecycle points it hooks into and why.

> **Deep dive:** [Hook development guide](https://docs.uniswap.org/contracts/v4/guides/create-a-hook), [Hook security best practices](https://www.trustlook.com/blog/uniswap-v4-hooks-security/)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How do V4 hooks work and what are the security considerations?"**
   - Good answer: "Hooks are external contracts called at specific points during pool operations. The hook address encodes which callbacks are enabled through specific address bits."
   - Great answer: "Hooks intercept 10 lifecycle points: before/after initialize, swap, add/remove liquidity, and donate. The hook address itself determines which callbacks are active — specific bits in the address are checked by the PoolManager (gas optimization: bit checks vs external calls). Critical security: hooks MUST verify `msg.sender == poolManager` (Cork Protocol lost $400k from missing this check), avoid unbounded loops (gas griefing), and handle reentrancy carefully. Once a pool is initialized with a hook, it's permanent — bugs mean abandoning the pool."

**Interview Red Flags:**
- 🚩 Not knowing that hooks are immutably linked to pools at initialization
- 🚩 Thinking hooks can modify the pool's core math (they intercept at lifecycle points, not replace the invariant)
- 🚩 Not mentioning access control (`msg.sender == poolManager`) as a critical security pattern

**Pro tip:** Mention a specific production hook you've studied (Clanker, Bunni, or GeomeanOracle) — it shows you've gone beyond docs into actual codebases.

#### 🔗 DeFi Pattern Connection

**Where V4 hooks are being used in production:**

1. **MEV protection:** [Sorella's Angstrom](https://www.sorella.xyz/) uses hooks to batch-settle swaps at uniform clearing prices, eliminating sandwich attacks
2. **Lending integration:** Hooks that auto-deposit idle LP assets into lending protocols between swaps — earning additional yield on liquidity
3. **Custom oracles:** [GeomeanOracle hook](https://github.com/Uniswap/v4-periphery/blob/example-contracts/contracts/hooks/examples/GeomeanOracle.sol) provides TWAP with better properties than V2/V3's built-in oracle
4. **LP management:** [Bunni](https://bunni.pro/) uses hooks for native concentrated liquidity management without external vaults

**The pattern:** V4 hooks are the composability layer for AMM innovation. Instead of forking an AMM (fragmenting liquidity), you plug into shared liquidity with custom logic.

### 📋 Summary: V4 Hooks

**✓ Covered:**
- V4 hook system — 10 lifecycle functions, address-encoded permissions
- Hook capabilities: dynamic fees, custom accounting, access control, oracle integration
- Read production hooks: limit order, TWAMM, dynamic fee, full-range
- Hook security: access control (`msg.sender == poolManager`), gas griefing, reentrancy, trust model, immutability
- Built: dynamic fee hook and swap counter hook
- Real exploits: Cork Protocol ($400k from missing access control)

**Next:** Alternative AMM designs and advanced ecosystem topics.

---

## Beyond Uniswap and Advanced AMM Topics

<a id="amms-vs-clobs"></a>
### AMMs vs Order Books (CLOBs)

**Why this matters:** Before exploring alternative AMM designs, it's worth asking the fundamental question: **why use an AMM at all?** Traditional finance uses order books (Central Limit Order Books — CLOBs), where makers post limit orders and takers fill them. Understanding the tradeoffs is essential for protocol design decisions and a common interview question.

| Dimension | AMM | Order Book (CLOB) |
|-----------|-----|-------------------|
| **Liquidity provision** | Passive (deposit and earn) | Active (post/cancel orders) |
| **Infrastructure** | Fully on-chain, permissionless | Needs off-chain matching engine |
| **Price discovery** | Derived from reserve ratios | Explicit from order flow |
| **LP risk** | Impermanent loss / LVR | No IL (makers choose their prices) |
| **Gas efficiency** | One `swap()` call | Multiple order operations |
| **Long-tail assets** | Anyone can create a pool | Low liquidity = wide spreads |
| **MEV exposure** | Sandwich attacks, JIT | Front-running, quote stuffing |
| **Capital efficiency** | V2: poor, V3/V4: good | High (makers deploy exactly where they want) |

**When AMMs win:**
- Long-tail / new tokens — permissionless pool creation bootstraps liquidity from zero
- Composability — other contracts can swap atomically (liquidations, flash loans, yield harvesting)
- Simplicity — no off-chain infrastructure needed
- Passive investors — people who want yield without active market making

**When CLOBs win:**
- High-volume majors (ETH/USDC) — professional market makers provide tighter spreads
- Derivatives markets — options/perps need order book precision
- Low-latency environments — L2s and app-chains with fast sequencers

**The convergence:**
The line is blurring. V4 hooks enable limit-order-like behavior in AMMs. UniswapX and CoW Protocol use solver-based architectures that combine AMM liquidity with off-chain quotes. dYdX moved to a CLOB on its own app-chain. The future likely involves hybrid systems where intent-based architectures route between AMMs and CLOBs for optimal execution.

> **Deep dive:** [Paradigm — "Order Book vs AMM" (2021)](https://www.paradigm.xyz/2021/04/understanding-automated-market-makers), [Hasu — "Why AMMs will keep winning"](https://uncommoncore.co/why-automated-market-makers-will-continue-to-dominate/), [dYdX CLOB design](https://dydx.exchange/blog/dydx-chain)

---

### Beyond Uniswap: Other AMM Designs (Awareness)

This module focuses on Uniswap because it's the Rosetta Stone of AMMs — V2's constant product, V3's concentrated liquidity, and V4's hooks represent the core design space. But other AMM architectures are important to know about. They'll be covered in depth in Part 3; this section gives you enough context to recognize them in the wild.

<a id="curve-stableswap"></a>
### Curve StableSwap

**Why this matters:** [Curve](https://curve.fi/) is the dominant AMM for assets that should trade near 1:1 (stablecoins, wrapped/staked ETH variants). Its invariant is a hybrid between constant-product (`x · y = k`) and constant-sum (`x + y = k`):

- Constant-sum gives zero slippage but can be fully drained of one token
- Constant-product can't be drained but gives increasing slippage
- Curve blends them via an "amplification parameter" `A` that controls how close to constant-sum the curve behaves near the equilibrium point

When prices are near 1:1, Curve pools offer far lower slippage than Uniswap. When prices deviate significantly, the curve reverts to constant-product behavior for safety.

> **Real impact:** [Curve's 3pool (USDC/USDT/DAI)](https://curve.fi/#/ethereum/pools/3pool/deposit) holds $1B+ TVL, enables stablecoin swaps with <0.01% slippage for trades up to $10M.

**Why this matters for DeFi builders:** If your protocol involves stablecoin swaps (liquidations paying in USDC to receive DAI, for example), Curve pools will likely offer better execution than Uniswap V2/V3 for those pairs. Understanding the StableSwap invariant also helps you reason about stablecoin depegging mechanics (Module 6).

> **Deep dive:** [StableSwap whitepaper](https://curve.fi/files/stableswap-paper.pdf), [Curve v2 (Tricrypto) whitepaper](https://curve.fi/files/crypto-pools-paper.pdf) — extends StableSwap to volatile assets with dynamic `A` parameter.

---

<a id="balancer-weighted"></a>
### Balancer Weighted Pools

**Why this matters:** [Balancer](https://balancer.fi/) generalizes the constant product formula to N tokens with arbitrary weights. The invariant:

```
∏(Bi^Wi) = k     (product of each balance raised to its weight)
```

A pool with 80% ETH / 20% USDC behaves like a self-rebalancing portfolio — the pool naturally maintains the target ratio as prices change. This enables:
- Index-fund-like pools (e.g., 33% ETH, 33% BTC, 33% stables)
- Liquidity bootstrapping pools (LBPs) where weights shift over time for token launches

> **Real impact:** [Balancer V2 Vault](https://github.com/balancer/balancer-v2-monorepo/tree/master/pkg/vault) pioneered the singleton architecture that Uniswap V4 adopted. Its consolidated liquidity also provides zero-fee flash loans — which you'll use in Module 5.

> **Deep dive:** [Balancer V2 Whitepaper](https://balancer.fi/whitepaper.pdf), [Balancer V3 announcement](https://medium.com/balancer-protocol/balancer-v3-5638b1c1e8ed) (builds on V2 Vault with hooks similar to Uniswap V4).

💻 **Quick Try: Spot the Difference**

Compare how different invariants handle a stablecoin swap. In a quick Foundry test or on paper:

```
Pool: 1,000,000 USDC + 1,000,000 DAI (both $1)
Swap: 10,000 USDC → DAI

Constant Product (Uniswap):
  dy = 1,000,000 · 10,000 / (1,000,000 + 10,000) = 9,900.99 DAI
  Slippage: ~1% ($99 lost)

Constant Sum (x + y = k, theoretical):
  dy = 10,000 DAI exactly
  Slippage: 0% (but pool can be fully drained!)

StableSwap (Curve, A=100):
  dy ≈ 9,999.4 DAI
  Slippage: ~0.006% ($0.60 lost)  ← 165x better than constant product
```

This is why Curve dominates stablecoin trading. The amplification parameter `A` controls how close to constant-sum the curve behaves near equilibrium.

---

<a id="trader-joe-lb"></a>
### Trader Joe Liquidity Book (Bins vs Ticks)

**Why this matters:** [Trader Joe V2](https://traderjoexyz.com/) (dominant on Avalanche, growing on Arbitrum) takes a different approach to concentrated liquidity: instead of V3's continuous ticks, it uses **discrete bins**. Each bin has a fixed price and holds only one token type.

```
V3 (ticks): Continuous curve, position spans a range, math uses √P
                ┌────────────────────────────┐
                │ ████████████████████████████│  ← liquidity is continuous
                └────────────────────────────┘
               $1,800                        $2,200

LB (bins):   Discrete buckets, each at a single price
                ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐
                │  ││  ││██││██││██││  ││  │  ← liquidity in discrete bins
                └──┘└──┘└──┘└──┘└──┘└──┘└──┘
              $1,800  $1,900  $2,000  $2,100  $2,200
```

**Key differences:**
- **Simpler math** — no square root operations, each bin is a constant-sum pool
- **Fungible LP tokens per bin** — unlike V3's unique NFT positions
- **Zero slippage within a bin** — trades within a single bin execute at the bin's exact price
- **Variable bin width** — bin step parameter controls price granularity (similar to tick spacing)

> **Deep dive:** [Trader Joe V2 Whitepaper](https://github.com/traderjoe-xyz/LB-Whitepaper/blob/main/Joe%20v2%20Liquidity%20Book%20Whitepaper.pdf), [Liquidity Book contracts](https://github.com/traderjoe-xyz/joe-v2)

---

<a id="ve33-dexes"></a>
### ve(3,3) DEXes (Velodrome / Aerodrome)

**Why this matters:** [Velodrome](https://velodrome.finance/) (Optimism) and [Aerodrome](https://aerodrome.finance/) (Base) are the highest-TVL DEXes on their respective L2s, using a model called **ve(3,3)** — vote-escrowed tokenomics combined with game theory (the "3,3" from OlympusDAO). This model fundamentally changes how DEX liquidity is bootstrapped and incentivized.

**How it works:**
1. **veToken locking** — Users lock the DEX token (VELO/AERO) for up to 4 years, receiving veNFTs with voting power
2. **Gauge voting** — veToken holders vote on which liquidity pools receive token emissions (incentives)
3. **Bribes** — Protocols bribe veToken holders to vote for their pool's emissions, creating a marketplace for liquidity
4. **Fee sharing** — veToken voters earn 100% of the trading fees from pools they voted for

**Why this matters for protocol builders:**

If you're launching a token and need DEX liquidity, ve(3,3) DEXes are a primary venue. Instead of paying for liquidity mining directly, you bribe veToken holders — often cheaper and more sustainable. Understanding this model is essential for token launch strategy and liquidity management.

> **Real impact:** Aerodrome on Base holds $1.5B+ TVL (2024), making it one of the largest DEXes on any L2. The ve(3,3) model creates a flywheel: more TVL → more fees → more bribes → more emissions → more TVL.

> **Deep dive:** [Andre Cronje's original ve(3,3) design](https://andrecronje.medium.com/ve-3-3-44466eaa088b), [Velodrome documentation](https://docs.velodrome.finance/), [Aerodrome documentation](https://aerodrome.finance/docs)

---

### Advanced AMM Topics

These topics sit at the intersection of AMM mechanics, market microstructure, and protocol design. Understanding them is essential for building protocols that interact with AMMs — and for interview success.

---

<a id="mev-sandwich"></a>
### ⚠️ MEV & Sandwich Attacks

**Why this matters:** Every AMM swap is a public transaction that sits in the mempool before execution. MEV (Maximal Extractable Value) searchers monitor the mempool and exploit the ordering of transactions for profit. If you're building any protocol that swaps through an AMM, MEV is your adversary.

> **Real impact:** [Flashbots data](https://explore.flashbots.net/) shows MEV extraction on Ethereum exceeds $600M+ cumulative since 2020. On average, ~$1-3M is extracted daily through sandwich attacks alone.

**Types of MEV in AMMs:**

**1. Frontrunning**

A searcher sees your pending swap (e.g., buy ETH for 10,000 USDC), submits the same trade with higher gas to execute *before* you. They profit from the price movement your trade causes.

```
Mempool:  [Your tx: buy ETH with 10,000 USDC, slippage 1%]

Searcher sequence:
1. Frontrun:  Buy ETH with 50,000 USDC   → price moves up
2. Your tx:   Executes at worse price     → you pay more
3. Backrun:   Searcher sells ETH          → pockets the difference
```

**2. Sandwich Attacks**

The most common AMM MEV. The searcher wraps your trade with a frontrun *and* a backrun in the same block:

```
Block ordering (manipulated by searcher):

┌─ Tx 1: Searcher buys ETH    (moves price UP)
│  Pool: 1000 ETH / 2,000,000 USDC → 950 ETH / 2,105,263 USDC
│
├─ Tx 2: YOUR swap buys ETH   (at WORSE price, moves price UP more)
│  Pool: 950 → 940 ETH        (you get fewer ETH than expected)
│
└─ Tx 3: Searcher sells ETH   (at the inflated price)
   Searcher profit: the difference minus gas costs
```

**How much do sandwiches cost users?**
```
Your trade size  │ Typical sandwich loss │ As % of trade
─────────────────┼───────────────────────┼──────────────
$1,000           │ $1-5                  │ 0.1-0.5%
$10,000          │ $20-100               │ 0.2-1.0%
$100,000         │ $500-5,000            │ 0.5-5.0%
$1,000,000+      │ $5,000-50,000+        │ 0.5-5.0%+
```

Losses scale super-linearly because larger trades have more price impact to exploit.

**3. Arbitrage (Non-harmful MEV)**

When prices differ between AMMs (e.g., ETH is $2000 on Uniswap, $2010 on Sushi), arbitrageurs buy on the cheap venue and sell on the expensive one. This is beneficial — it keeps prices aligned across markets. But it comes at the cost of LP impermanent loss.

**CEX-DEX arbitrage — the #1 source of LP losses:**

The most important form of arbitrage to understand is **CEX-DEX arb**: when ETH moves from $2,000 to $2,010 on Binance, arbitrageurs immediately buy ETH from the on-chain AMM at the stale $2,000 price and sell on Binance at $2,010. This happens within seconds of every price movement.

```
Binance: ETH price moves $2,000 → $2,010

┌─ Arber buys ETH on Uniswap at ~$2,000  (stale AMM price)
│  → Pool moves to ~$2,010
└─ Arber sells ETH on Binance at $2,010
   → Profit: ~$10 per ETH minus gas

Who pays? The LPs. They sold ETH at $2,000 when it was worth $2,010.
This is "toxic flow" — trades from informed participants who know
the AMM price is stale. It happens on EVERY price movement.
```

This is the mechanism *behind* impermanent loss and the real-time cost that LVR measures. CEX-DEX arb accounts for [~60-80% of Uniswap V3 volume on major pairs](https://arxiv.org/abs/2208.06046) — the majority of trades LPs serve are from arbitrageurs, not retail users. This is why passive LPing at tight ranges is often unprofitable despite high fee APRs: most of the volume generating those fees is toxic flow that extracts more value than the fees pay.

> **Deep dive:** [Milionis et al. "Automated Market Making and Arbitrage Profits" (2023)](https://arxiv.org/abs/2307.02074), [Thiccythot's toxic flow analysis](https://twitter.com/thiccythot_/status/1591565566068330496)

**4. Just-In-Time (JIT) Liquidity**

Covered in detail [below](#jit-liquidity). A specialized form of MEV where searchers add and remove concentrated liquidity around large trades.

**Protection Mechanisms:**

| Mechanism | How it works | Trade-off |
|-----------|-------------|-----------|
| **`amountOutMin` (slippage protection)** | Revert if output is below threshold | Tight = safe but may fail; loose = executes but loses value |
| **[Flashbots Protect](https://docs.flashbots.net/flashbots-protect/overview)** | Submit tx privately to block builders, skip public mempool | Depends on builder honesty; slightly slower inclusion |
| **[MEV Blocker](https://mevblocker.io/)** | OFA (Order Flow Auction) — searchers bid for your order flow, you get a rebate | New, less battle-tested |
| **Private mempools / OFAs** | Route through private channels ([CoW Protocol](https://cow.fi/), [1inch Fusion](https://1inch.io/fusion/)) | Requires trust in the operator; may have slower execution |
| **Batch auctions** | [CoW Protocol](https://cow.fi/) batches trades and solves off-chain for uniform clearing price | No frontrunning possible, but introduces latency |
| **V4 hooks** | Custom hooks can implement MEV protection (e.g., [Sorella's Angstrom](https://www.sorella.xyz/)) | Application-level; requires hook trust |

> **Common pitfall:** Relying solely on `amountOutMin` for MEV protection. A tight `amountOutMin` prevents sandwiches but can cause reverts during volatile periods. Best practice: use private submission channels (Flashbots Protect) AND reasonable slippage settings.

**For protocol builders:**

If your protocol executes AMM swaps (liquidations, rebalancing, yield harvesting), you MUST consider MEV:
- **Liquidation bots** will be sandwiched if they swap through public AMMs naively
- **Yield strategies** that harvest and swap reward tokens are prime sandwich targets
- **Rebalancing operations** on predictable schedules can be frontrun

Solutions: use private mempools, implement internal buffers, randomize execution timing, or use auction-based swap mechanisms.

> **Deep dive:** [Flashbots documentation](https://docs.flashbots.net/), [MEV-Boost architecture](https://ethereum.org/en/developers/docs/mev/), [Paradigm MEV research](https://www.paradigm.xyz/2021/02/mev-and-me), [CoW Protocol documentation](https://docs.cow.fi/)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you protect a protocol's liquidation swaps from sandwich attacks?"**
   - Good answer: "Use slippage protection with `amountOutMin` and submit through Flashbots Protect."
   - Great answer: "Layer multiple defenses: (1) Flashbots Protect or MEV Blocker for private submission, (2) Set `amountOutMin` based on a reliable oracle price (Chainlink, not the AMM's spot price — that's circular), (3) Route through an aggregator like 1inch Fusion or CoW Protocol for large liquidations, (4) If the protocol has predictable rebalancing schedules, randomize timing. For maximum protection, use intent-based systems where solvers compete to fill the swap."

**Interview Red Flags:**
- 🚩 Not mentioning MEV/sandwich attacks when discussing AMM integrations
- 🚩 Hardcoding a single DEX for protocol swaps instead of using aggregators
- 🚩 Setting `amountOutMin = 0` ("accepting any price") — invitation for sandwich attacks

**Pro tip:** In architecture discussions, proactively bring up MEV protection before being asked — it signals you think about adversarial conditions, not just happy paths.

---

<a id="jit-liquidity"></a>
### JIT (Just-In-Time) Liquidity

**Why this matters:** JIT liquidity is a V3-specific MEV strategy that fundamentally changes the economics of concentrated liquidity provision. Understanding it is critical for anyone building on top of V3/V4 pools.

**How it works:**

A JIT liquidity provider monitors the mempool for large pending swaps. When they spot one, they:

```
Block ordering:

┌─ Tx 1: JIT provider ADDS concentrated liquidity
│         in an extremely tight range around the current price
│         (e.g., just 1 tick wide)
│
├─ Tx 2: LARGE SWAP executes
│         The JIT liquidity captures most of the fees
│         because it dominates the liquidity at the active price
│
└─ Tx 3: JIT provider REMOVES liquidity + collects fees
         All in the same block — near-zero impermanent loss risk
```

**Why it works economically:**

```
Normal LP (wide range, holds for weeks):
  - Capital: $100,000 across ticks -1000 to +1000
  - Active capital at current tick: ~$500 (0.5%)
  - Earns fees proportional to $500
  - Exposed to IL over weeks

JIT LP (1-tick range, holds for 1 block):
  - Capital: $100,000 concentrated in 1 tick
  - Active capital at current tick: ~$100,000 (100%)
  - Earns fees proportional to $100,000
  - IL risk ≈ 0 (removed same block)
```

The JIT provider earns ~200x more fees per dollar of capital, but only for a single block. They extract most of the fee revenue from a large trade, leaving passive LPs with a smaller share.

**Impact on passive LPs:**

JIT liquidity dilutes passive LPs' fee income. When a large trade comes in, the JIT provider's concentrated liquidity captures 80-95% of the fees, even though they had zero capital in the pool moments before.

> **Real impact:** [Research by 0x Labs](https://0x.org/post/measuring-the-impact-of-jit-liquidity) found JIT liquidity providers captured up to 80% of fees on some large V3 trades. [Sorella's analysis](https://www.sorella.xyz/) showed JIT accounts for ~5-10% of total V3 fee revenue.

**V4's response to JIT:**

V4 hooks enable countermeasures:
- **`beforeAddLiquidity` hook**: Reject liquidity additions that look like JIT (e.g., same-block add+remove patterns)
- **Time-weighted fee sharing**: Hook distributes fees proportional to time liquidity was active, not just amount
- **Minimum liquidity duration**: Hook enforces that liquidity must stay active for N blocks before collecting fees

> **Common pitfall:** Assuming JIT liquidity is always harmful. It actually provides better execution for large traders (more liquidity at the active price). The debate is about fair fee distribution between active and passive LPs.

**For protocol builders:** If your protocol manages V3 LP positions (vault strategies, LP managers), understand that your passive positions compete with JIT providers. This affects yield projections and should inform whether you target high-volume pools (where JIT is most active) or long-tail pools (where JIT is less common).

> **Deep dive:** [Uniswap JIT analysis](https://uniswap.org/blog/jit-liquidity), [JIT liquidity dataset on Dune](https://dune.com/queries/1236539)

---

<a id="amm-aggregators-routing"></a>
### AMM Aggregators & Routing

**Why this matters:** No single AMM pool has the best price for every trade. A $100K ETH→USDC swap might get better execution by splitting: 60% through Uniswap V3 (0.05% pool), 30% through Curve, 10% through Balancer. Aggregators solve this routing problem.

**How aggregators work:**

```
User wants: Swap 100 ETH → USDC

Aggregator scans:
┌────────────────────────────────────────────────────────────┐
│ Uniswap V3 (0.05%): 100 ETH → 199,800 USDC               │
│ Uniswap V3 (0.30%): 100 ETH → 199,200 USDC               │
│ Uniswap V2:         100 ETH → 198,500 USDC               │
│ Curve:               100 ETH → 199,600 USDC               │
│ Sushi:               100 ETH → 198,800 USDC               │
└────────────────────────────────────────────────────────────┘

Optimal route (found by solver):
  60 ETH → Uni V3 0.05%  = 119,920 USDC
  30 ETH → Curve          =  59,910 USDC
  10 ETH → Uni V3 0.30%  =  19,960 USDC
  Total:                   199,790 USDC  ← BETTER than any single pool
```

**Major aggregators:**

| Aggregator | Approach | Key Innovation |
|-----------|----------|----------------|
| **[1inch](https://1inch.io/)** | Pathfinder algorithm, limit orders, Fusion mode (MEV-protected) | Largest market share; [Fusion](https://1inch.io/fusion/) uses Dutch auctions for MEV protection |
| **[CoW Protocol](https://cow.fi/)** | Batch auctions with coincidence of wants (CoWs) | Peer-to-peer matching eliminates AMM fees when possible; MEV-proof by design |
| **[Paraswap](https://www.paraswap.io/)** | Multi-path routing with gas optimization | Augustus Router V6 supports complex multi-hop, multi-DEX routes |
| **[0x / Matcha](https://matcha.xyz/)** | Professional market maker integration | Combines AMM liquidity with off-chain RFQ quotes from market makers |

**Coincidence of Wants (CoWs):**

CoW Protocol's key insight: if Alice wants to sell ETH for USDC, and Bob wants to sell USDC for ETH, they can trade directly — no AMM needed. No fees, no price impact, no MEV.

```
Without CoW:
  Alice → AMM (0.3% fee + price impact) → Bob's trade also hits AMM

With CoW:
  Alice ←→ Bob   (direct swap at market price, 0 fee, 0 slippage)
  Remainder → AMM (only the unmatched portion touches the AMM)
```

**Intent-based architectures:**

The latest evolution: users express *what* they want (swap X for Y), not *how* (which DEX, which route). Solvers compete to fill the intent with the best execution.

- **[UniswapX](https://uniswap.org/whitepaper-uniswapx.pdf)**: Dutch auction for swap intents; fillers compete to provide best price
- **[CoW Protocol](https://docs.cow.fi/)**: Batch-level solving with CoW matching
- **[Across+](https://across.to/)**: Cross-chain intent settlement

> **Common pitfall:** Building a protocol that hardcodes a single AMM for swaps. Always integrate through an aggregator or allow configurable swap routes. Liquidity shifts between AMMs constantly.

**For protocol builders:**

If your protocol needs to execute swaps (liquidations, rebalancing, treasury management):
1. **Never hardcode a single DEX** — use aggregator APIs or on-chain aggregator contracts
2. **Consider intent-based systems** for large or predictable swaps (less MEV, better execution)
3. **Test with realistic routing** — fork mainnet and compare single-pool vs aggregated execution

> **Deep dive:** [1inch API docs](https://docs.1inch.io/), [CoW Protocol docs](https://docs.cow.fi/), [UniswapX whitepaper](https://uniswap.org/whitepaper-uniswapx.pdf), [Intent-based architectures overview](https://www.paradigm.xyz/2023/06/intents)

---

<a id="lp-management"></a>
### LP Management Strategies

**Why this matters:** In V3/V4, passive LP-ing (deposit and forget) is often unprofitable due to impermanent loss and JIT liquidity diluting fees. Active management has become essential — and it's created an entire sub-industry of LP management protocols.

**The problem: passive V3 LP-ing is hard**

```
V2 LP lifecycle:        V3 LP lifecycle:
┌──────────────┐        ┌──────────────────────────────────┐
│ Deposit      │        │ Choose range                      │
│ Hold forever │        │ Monitor price vs range             │
│ Collect fees │        │ Price drifts out of range?         │
│ Withdraw     │        │  → Stop earning fees               │
└──────────────┘        │  → Decide: wait or rebalance?      │
                        │ Rebalance = close + reopen position │
                        │  → Pay gas + swap fees              │
                        │  → Realize IL                       │
                        │  → Compete with JIT liquidity       │
                        └──────────────────────────────────┘
```

**Strategy spectrum:**

| Strategy | Range Width | Rebalance Frequency | Best For |
|----------|-----------|---------------------|----------|
| **Wide range** (±50%) | Passive, rarely out of range | Never/rarely | Low-maintenance, lower yield |
| **Medium range** (±10%) | Monthly rebalance | Monthly | Balance of yield and effort |
| **Tight range** (±2%) | Daily rebalance | Daily | Max yield, high gas costs |
| **Single-sided** (above/below price) | Limit-order-like behavior | On trigger | Targeted entry/exit points |
| **Full range** (V2-equivalent) | Never out of range | Never | Simplicity, composability |

**LP management protocols:**

These protocols manage V3/V4 positions for you, abstracting away range selection and rebalancing:

| Protocol | Approach | Key Feature |
|----------|---------|-------------|
| **[Arrakis (PALM)](https://www.arrakis.finance/)** | Algorithmic rebalancing vaults | Market-making strategies; used by protocols for their own token liquidity |
| **[Gamma](https://www.gamma.xyz/)** | Active management vaults | Multiple strategies per pool; wide protocol integrations |
| **[Bunni](https://bunni.pro/)** | V4 hooks-based LP management | Native V4 integration; "Liquidity-as-a-Service" |
| **[Maverick](https://www.mav.xyz/)** | AMM with built-in LP modes | Directional LPing (bet on price direction while earning fees) |

**Evaluating pool profitability — how to decide whether to LP:**

Before deploying capital as an LP, you need to estimate whether fees will outpace losses. Here are the key metrics:

```
1. Fee APR = (24h Volume × Fee Tier × 365) / TVL

   Example: ETH/USDC 0.05% pool
   Volume: $200M/day, TVL: $300M
   Fee APR = ($200M × 0.0005 × 365) / $300M = 12.2%

2. Estimated LVR cost ≈ σ² / 8
   (annualized, as % of position value, for full-range V2-style CPMM)

   ETH annualized volatility: ~80%
   LVR ≈ 0.80² / 8 = 8%

3. Net LP return ≈ Fee APR - LVR cost - Gas costs
   ≈ 12.2% - 8% - gas → marginally positive before gas, but tight.
   Concentrated ranges boost fee capture but also amplify LVR exposure.

4. Volume/TVL ratio — the single most useful metric
   > 0.5: High fee generation, likely profitable
   0.1-0.5: Moderate, depends on volatility
   < 0.1: Low fees relative to capital, likely unprofitable
```

**Toxic flow share** — the percentage of volume coming from informed traders (arbitrageurs) vs retail:
- High toxic flow (>60%): LPs are mostly serving arbers at stale prices → likely unprofitable
- Low toxic flow (<40%): Pool serves mostly retail → fees more likely to exceed LVR
- Stablecoin pairs: Very low toxic flow → almost always profitable for LPs

> **Deep dive:** [CrocSwap LP profitability framework](https://crocswap.medium.com/is-concentrated-liquidity-worth-it-e9c0aa24c9e0), [Revert Finance analytics](https://revert.finance/) — real-time LP position profitability tracker

**The compounding problem:**

V3 fees don't auto-compound (they accumulate as uncollected tokens, not as additional liquidity). Manual compounding requires:
1. Collect fees
2. Swap to correct ratio
3. Add liquidity at current range
4. Pay gas for all three transactions

LP management protocols automate this, but take a performance fee (typically 10-20% of earned fees).

> **Common pitfall:** Ignoring gas costs when evaluating LP strategies. A tight-range strategy earning 50% APR but requiring daily $20 rebalances on mainnet needs $7,300/year in gas alone. On an $10,000 position, that's 73% of the gross yield eaten by gas. L2 deployment changes this calculus entirely.

**For protocol builders:**

If your protocol uses LP tokens as collateral or manages liquidity:
- **Vault tokens** from Arrakis/Gamma are ERC-20s that represent managed V3 positions — much more composable than raw V3 NFTs
- **Consider Maverick** for protocols needing directional liquidity (e.g., token launches, price pegs)
- **V4 hooks** enable native LP management without external protocols — Bunni's approach is worth studying

> **Deep dive:** [Arrakis documentation](https://docs.arrakis.fi/), [Gamma strategies overview](https://docs.gamma.xyz/), [Maverick AMM docs](https://docs.mav.xyz/), [Bunni V2 design](https://docs.bunni.pro/)

### 📋 Summary: Beyond Uniswap & Advanced AMM Topics

**✓ Covered:**
- AMMs vs Order Books — tradeoffs, when each wins, the convergence toward hybrid systems
- Curve StableSwap — hybrid invariant, amplification parameter, stablecoin dominance
- Balancer weighted pools — N-token pools, LBPs, Vault architecture (inspiration for V4)
- Trader Joe Liquidity Book — bins vs ticks, a different approach to concentrated liquidity
- ve(3,3) DEXes — Velodrome/Aerodrome, vote-escrowed tokenomics, bribe markets for liquidity
- MEV & sandwich attacks — types, CEX-DEX arbitrage (primary LP cost), cost tables, protection mechanisms
- JIT liquidity — economics, impact on passive LPs, V4 countermeasures
- AMM aggregators — 1inch, CoW Protocol, Paraswap, intent-based architectures (UniswapX)
- LP management — strategy spectrum, pool profitability analysis, Arrakis/Gamma/Bunni/Maverick

**Next:** Practice challenges to cement your understanding.

---

## Practice Challenges and Review

Test your AMM understanding with these exercises:

**AMM-specific challenges:**

- **Build a two-pool arbitrage bot.** Deploy two constant product pools with the same token pair but different prices. Write a contract that detects the price discrepancy and executes an atomic arbitrage (buy on the cheap pool, sell on the expensive pool). Calculate the optimal trade size that maximizes profit. This teaches you how arbitrage keeps AMM prices aligned — and why it causes impermanent loss for LPs.

- **Implement a sandwich attack detector.** Given a block's transaction list (simulate with sequential swaps in a test), identify which swaps were sandwiched. Compute the MEV extracted: compare each victim's actual output to what they would have received without the frontrun. This cements your understanding of price impact manipulation.

- **V3 position profitability calculator.** Given a historical price path (simulated with `vm.warp` + sequential swaps), compute a V3 position's total PnL: fees earned minus impermanent loss minus gas costs for rebalancing. Compare narrow vs wide range strategies on the same price path.

**Damn Vulnerable DeFi challenges:**

- **[DVDF #4 "Side Entrance"](https://www.damnvulnerabledefi.xyz/)** — A flash loan pool with a subtle accounting flaw in its deposit/withdraw logic. Directly tests your understanding of how pool accounting should work.
- **[DVDF #5 "The Rewarder"](https://www.damnvulnerabledefi.xyz/)** — Reward token distribution interacting with pool deposits. Explores timing attacks on reward mechanisms.
- **[DVDF #9 "Puppet V2"](https://www.damnvulnerabledefi.xyz/)** — Manipulate a Uniswap V2 oracle to drain a lending pool. Directly tests AMM price manipulation → oracle exploitation.

#### 💼 Module-Level Interview Prep

**Interview Red Flags:**
- 🚩 Not knowing the difference between V2 and V3 architecture
- 🚩 Saying "impermanent loss isn't real" — it is real and must be accounted for
- 🚩 Only knowing IL but not LVR — shows outdated understanding of LP economics
- 🚩 Not understanding that CEX-DEX arbitrage is the primary cost to LPs, not retail flow
- 🚩 Thinking V3 is always better than V2 (not true for high-volatility, low-volume pairs)
- 🚩 Not knowing what sqrtPriceX96 is or why prices are stored as square roots
- 🚩 Hardcoding a single DEX for protocol swaps instead of using aggregators
- 🚩 Not knowing the difference between AMMs and order books, or when each is appropriate

**Pro tip:** In interviews, demonstrate that you can read production AMM code, not just explain concepts. Be ready to trace through V3's swap loop or V4's unlock pattern. Teams building on Uniswap want engineers who can debug at the source code level. Mention specific functions you've studied — `computeSwapStep()`, `unlock()`, the k-invariant check.

#### 📖 Recommended Study Order

| Order | Codebase | Time | What You'll Learn |
|-------|----------|------|-------------------|
| 1 | [Uniswap V2 Core](https://github.com/Uniswap/v2-core) | 1-2 days | AMM fundamentals, flash swaps, TWAP |
| 2 | [Uniswap V2 Periphery](https://github.com/Uniswap/v2-periphery) | 0.5 day | Router pattern, multi-hop, slippage protection |
| 3 | [V3 Development Book](https://uniswapv3book.com/) | 2-3 days | Concentrated liquidity concepts + build |
| 4 | [V3 Core (libraries)](https://github.com/Uniswap/v3-core/tree/main/contracts/libraries) | 1-2 days | Production math, tick bitmaps, fee accounting |
| 5 | [V4 Core](https://github.com/Uniswap/v4-core) | 1-2 days | Singleton, flash accounting, hooks |
| 6 | [Curve StableSwap](https://github.com/curvefi/curve-contract) | 0.5 day | Alternative invariant, amplification parameter |

---

## Key Takeaways for Protocol Builders

After 12 days, you should have internalized:

**1. The constant product formula is everywhere.** Even V3's concentrated liquidity reduces to V2's formula within each tick range. If you understand `x · y = k`, you understand the core of every AMM.

**2. Price impact is nonlinear.** The constant product curve means that larger trades get progressively worse prices. This is *by design* — it's the AMM's defense against being drained. Any protocol you build that touches AMMs must account for price impact and slippage.

**3. LVR is the real cost of LPing, not just IL.** Impermanent loss is a snapshot at withdrawal. LVR (Loss-Versus-Rebalancing) measures the continuous cost of CEX-DEX arbitrageurs trading against stale AMM prices. It scales with σ² and never reverses. Fees must exceed LVR — not just IL — for LPs to profit.

**4. CEX-DEX arbitrage is the dominant force in AMM markets.** The majority of volume on major V3 pools is toxic flow from informed traders exploiting stale prices. This is the mechanism behind LVR and the reason passive LPing at tight ranges often loses money despite high fee APRs.

**5. V3 concentrated liquidity = more capital efficiency, more complexity.** Narrow ranges earn more fees but require active management and expose LPs to sharper IL. Wide ranges are passive but capital-inefficient. The design of your protocol should account for which type of LP you're targeting.

**6. V4 hooks are the future of AMM innovation.** Instead of forking an AMM to add custom logic (which fragments liquidity), you build a hook and plug into V4's shared liquidity. This is the primary way DeFi protocols will extend AMM functionality going forward.

**7. Flash accounting + transient storage is a design pattern, not just a V4 feature.** The idea of tracking deltas and settling at the end of a transaction can be applied to any protocol that handles multiple token movements. You'll see this pattern again in lending, bridges, and aggregators.

**8. MEV is not optional knowledge.** Every protocol that executes AMM swaps must account for sandwich attacks, frontrunning, and JIT liquidity. Use private mempools, aggregators, and intent-based systems to protect your users.

**9. Never hardcode a single liquidity source.** Use aggregators or configurable routing. Liquidity migrates between AMMs, and the best execution path changes block-to-block.

**10. AMMs and order books are converging.** Pure AMMs and pure CLOBs each have strengths. The trend is toward intent-based systems (UniswapX, CoW Protocol) and hybrid architectures (V4 hooks enabling limit orders) that combine both. Understand the tradeoffs to make informed protocol design decisions.

**11. LP management is now a professional activity.** V3/V4 concentrated liquidity requires active management. Understand the LP management ecosystem (Arrakis, Gamma, Bunni) and evaluate pool profitability using Volume/TVL ratio, LVR estimates, and toxic flow share before deploying capital.

---

## 🔗 Cross-Module Concept Links

### ← Backward References (Part 1 + Module 1)

| Source | Concept | How It Connects |
|--------|---------|-----------------|
| Part 1 Section 1 | [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) share math / `mulDiv` | LP token minting uses the same shares-proportional-to-deposit pattern; `Math.sqrt` in V2 parallels vault share math |
| Part 1 Section 1 | Unchecked arithmetic | V2/V3 use unchecked blocks for gas-optimized tick and fee math where overflow is intentional |
| Part 1 Section 2 | Transient storage | V4 flash accounting uses TSTORE/TLOAD for delta tracking — 20× cheaper than SSTORE |
| Part 1 Section 3 | Permit2 | Universal token approvals for V4 PositionManager; aggregator integrations use Permit2 for gasless approvals |
| Part 1 Section 5 | Fork testing | Essential for testing AMM integrations against real mainnet liquidity and verifying swap routing |
| Part 1 Section 5 | Invariant / fuzz testing | Property-based testing for AMM invariants: `x * y >= k`, tick math boundaries, fee accumulation monotonicity |
| Part 1 Section 6 | Immutable core + periphery | V2/V3/V4 all use immutable core contracts with upgradeable periphery routers — the canonical DeFi proxy pattern |
| Module 1 | SafeERC20 / balance-before-after | V2 implements its own `_safeTransfer`; `mint()`/`burn()` read balances directly — the foundation of composability |
| Module 1 | Fee-on-transfer tokens | V2's `_update()` syncs reserves from actual balances; V3/V4 don't natively support fee-on-transfer |
| Module 1 | WETH wrapping | All AMM routers wrap/unwrap ETH; V4 supports native ETH pairs directly |
| Module 1 | Token decimals handling | Price display and tick math must account for differing decimals between token0/token1 |

### → Forward References (Modules 3–9)

| Target | Concept | How AMM Knowledge Applies |
|--------|---------|---------------------------|
| Module 3 (Oracles) | TWAP oracles | Built on AMM price accumulators; oracle manipulation via concentrated liquidity price impact |
| Module 4 (Lending) | Liquidation swaps | Route through AMMs; LP tokens as collateral; CEX-DEX arb informs liquidation MEV |
| Module 5 (Flash Loans) | Flash swaps / flash accounting | V2 flash swaps and V4 flash accounting are specialized flash loan patterns |
| Module 6 (Stablecoins) | Curve StableSwap | AMM design optimized for peg maintenance; AMM-based depegging detection signals |
| Module 7 (Yield) | LP fee income | Yield source from trading fees; auto-compounding vaults; LVR framework for LP strategy evaluation |
| Module 8 (DeFi Security) | Protocol fee switches | V2 `feeTo`, V3 factory owner, V4 hook governance; ve(3,3) gauge voting and bribe markets |
| Module 9 (Integration) | Full-stack capstone | Combining AMM + lending + oracles + yield in a production-grade protocol |

---

## Resources

**Essential reading:**
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Uniswap V3 Whitepaper](https://uniswap.org/whitepaper-v3.pdf)
- [Uniswap V4 Whitepaper](https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper/whitepaper-v4.pdf)
- [Uniswap V3 Math Primer (Parts 1 & 2)](https://blog.uniswap.org/uniswap-v3-math-primer)
- [UniswapX Whitepaper](https://uniswap.org/whitepaper-uniswapx.pdf) — intent-based swap architecture

**Source code:**
- [Uniswap V2 Core](https://github.com/Uniswap/v2-core) (deployed May 2020)
- [Uniswap V2 Periphery](https://github.com/Uniswap/v2-periphery)
- [Uniswap V3 Core](https://github.com/Uniswap/v3-core) (deployed May 2021, archived)
- [Uniswap V4 Core](https://github.com/Uniswap/v4-core) (deployed November 2024)
- [Uniswap V4 Periphery](https://github.com/Uniswap/v4-periphery)
- [Awesome Uniswap Hooks](https://github.com/fewwwww/awesome-uniswap-hooks)
- [Curve StableSwap contracts](https://github.com/curvefi/curve-contract)
- [Balancer V2 Vault](https://github.com/balancer/balancer-v2-monorepo/tree/master/pkg/vault)

**Deep dives:**
- [Concentrated liquidity math](https://atiselsts.github.io/pdfs/uniswap-v3-liquidity-math.pdf)
- [V3 ticks deep dive](https://mixbytes.io/blog/uniswap-v3-ticks-dive-into-concentrated-liquidity)
- [V4 architecture and security](https://www.zealynx.io/blogs/uniswap-v4)
- [Uniswap V4 hooks documentation](https://docs.uniswap.org/contracts/v4/concepts/hooks)
- [Curve StableSwap whitepaper](https://curve.fi/files/stableswap-paper.pdf)
- [Curve v2 Tricrypto whitepaper](https://curve.fi/files/crypto-pools-paper.pdf)
- [Balancer V2 Whitepaper](https://balancer.fi/whitepaper.pdf)
- [Trader Joe V2 Liquidity Book Whitepaper](https://github.com/traderjoe-xyz/LB-Whitepaper/blob/main/Joe%20v2%20Liquidity%20Book%20Whitepaper.pdf)

**LVR & LP economics:**
- [Milionis et al. "Automated Market Making and Loss-Versus-Rebalancing" (2022)](https://arxiv.org/abs/2208.06046) — the foundational LVR paper
- [a16z LVR explainer](https://a16zcrypto.com/posts/article/lvr-quantifying-the-cost-of-providing-liquidity-to-automated-market-makers/) — accessible summary
- [Tim Roughgarden's LVR lecture](https://www.youtube.com/watch?v=cB-4pjhJHl8) — video walkthrough
- [CrocSwap LP profitability framework](https://crocswap.medium.com/is-concentrated-liquidity-worth-it-e9c0aa24c9e0)
- [Revert Finance](https://revert.finance/) — real-time LP position profitability tracker

**AMM design & market structure:**
- [Paradigm — "Order Book vs AMM"](https://www.paradigm.xyz/2021/04/understanding-automated-market-makers)
- [Hasu — "Why AMMs will keep winning"](https://uncommoncore.co/why-automated-market-makers-will-continue-to-dominate/)

**ve(3,3) & alternative DEX models:**
- [Andre Cronje's ve(3,3) design](https://andrecronje.medium.com/ve-3-3-44466eaa088b) — original design post
- [Velodrome documentation](https://docs.velodrome.finance/)
- [Aerodrome documentation](https://aerodrome.finance/docs)

**MEV & market microstructure:**
- [Flashbots documentation](https://docs.flashbots.net/) — MEV protection, Flashbots Protect, MEV-Boost
- [Flashbots MEV explorer](https://explore.flashbots.net/) — live MEV extraction data
- [Paradigm MEV research](https://www.paradigm.xyz/2021/02/mev-and-me) — foundational MEV paper
- [MEV Blocker](https://mevblocker.io/) — order flow auction MEV protection
- [CoW Protocol documentation](https://docs.cow.fi/) — batch auctions, CoWs, MEV-proof swaps
- [Intent-based architectures](https://www.paradigm.xyz/2023/06/intents) — Paradigm overview

**LP management & JIT liquidity:**
- [Arrakis documentation](https://docs.arrakis.fi/) — algorithmic LP management
- [Gamma strategies](https://docs.gamma.xyz/) — active LP management vaults
- [Bunni V2 design](https://docs.bunni.pro/) — V4 hooks-based LP management
- [Maverick AMM docs](https://docs.mav.xyz/) — directional liquidity and built-in LP modes
- [JIT liquidity analysis](https://uniswap.org/blog/jit-liquidity) — Uniswap's own research on JIT impact
- [0x JIT impact study](https://0x.org/post/measuring-the-impact-of-jit-liquidity) — quantitative JIT analysis

**Aggregators:**
- [1inch API documentation](https://docs.1inch.io/) — pathfinder routing, Fusion mode
- [Paraswap documentation](https://doc.paraswap.network/) — Augustus Router, multi-path routing

**Interactive learning:**
- [Uniswap V3 Development Book](https://uniswapv3book.com/)

**Security and exploits:**
- [Warp Finance postmortem](https://rekt.news/warp-finance-rekt/) — reentrancy in LP deposit ($8M)
- [Cork Protocol exploit analysis](https://medium.com/coinmonks/cork-protocol-exploit-analysis-9b8c866ff776) — hook access control ($400k)

**Analytics:**
- [Uniswap metrics dashboard](https://dune.com/hagaetc/uniswap-metrics) — live V2/V3/V4 volume and TVL
- [Curve pool analytics](https://curve.fi/#/ethereum/pools) — stablecoin pool slippage comparison
- [JIT liquidity Dune dashboard](https://dune.com/queries/1236539)

---

**Navigation:** [← Module 1: Token Mechanics](1-token-mechanics.md) | [Module 3: Oracles →](3-oracles.md)

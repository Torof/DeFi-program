# Part 2 — Module 2: AMMs from First Principles

**Duration:** ~10 days (3–4 hours/day)
**Prerequisites:** Module 1 complete (token mechanics, SafeERC20)
**Pattern:** Math → Build minimal version → Read production code → Extend
**Builds on:** Module 1 (SafeERC20, balance-before-after), Part 1 Section 5 (Foundry, fork testing)
**Used by:** Module 3 (TWAP oracles), Module 4 (liquidation swaps), Module 5 (flash swaps/arbitrage), Module 9 (integration capstone)

---

## Why This Is the Longest Module

AMMs are the foundation of decentralized finance. Lending protocols need them for liquidations. Aggregators route through them. Yield strategies compose on top of them. Intent systems like UniswapX exist to improve on them. If you're going to build your own protocols, you need to understand AMMs deeply — not just the interface, but the math, the design trade-offs, and the evolution from V2's elegant simplicity through V3's concentrated liquidity to V4's programmable hooks.

This module is 10 days because you're building one from scratch, then studying three generations of production AMM code.

---

## Days 1–2: The Constant Product Formula

### The Math

Every AMM begins with a single equation: **x · y = k**

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

In practice, a fee is deducted from the input before computing the swap. With a 0.3% fee:

```
dx_effective = dx · (1 - 0.003)
dy = y · dx_effective / (x + dx_effective)
```

The fee stays in the pool, increasing `k` over time. This is how LPs earn — the pool's reserves grow from accumulated fees.

**Impermanent loss:**

When the price of token A rises relative to token B, arbitrageurs buy A from the pool (cheap) and sell it on external markets. This re-balances the pool but means LPs end up with less A and more B than if they had just held. The difference between "hold" and "LP" value is impermanent loss. It's called "impermanent" because it reverses if the price returns to the original ratio — but in practice, for volatile pairs, it's very real.

The formula for impermanent loss given a price change ratio `r`:

```
IL = 2·√r / (1 + r) - 1
```

For a 2x price move: ~5.7% loss. For a 5x price move: ~25.5% loss. LPs need fee income to exceed IL to be profitable.

### Build: Minimal Constant Product Pool (Days 1–2)

Create a new Foundry project:

```
forge init simple-amm
cd simple-amm
forge install OpenZeppelin/openzeppelin-contracts
```

**Build a `ConstantProductPool.sol`** with these features:

**Core state:**
- `reserve0`, `reserve1` — current token reserves
- `totalSupply` of LP tokens (use a simple internal accounting, or inherit ERC-20)
- `token0`, `token1` — the two ERC-20 token addresses
- `FEE_NUMERATOR = 3`, `FEE_DENOMINATOR = 1000` — 0.3% fee

**Functions to implement:**

1. **`addLiquidity(uint256 amount0, uint256 amount1) → uint256 liquidity`**

   First deposit: LP tokens minted = `√(amount0 · amount1)` (geometric mean). Burn a `MINIMUM_LIQUIDITY` (1000 wei) to the zero address to prevent the pool from ever being fully drained (this is a critical anti-manipulation measure — read the Uniswap V2 whitepaper section on this).

   Subsequent deposits: LP tokens minted proportionally to the smaller ratio:
   ```
   liquidity = min(amount0 · totalSupply / reserve0, amount1 · totalSupply / reserve1)
   ```

   This incentivizes depositors to add liquidity at the current ratio. If they deviate, they get fewer LP tokens (the excess is effectively donated to existing LPs).

2. **`removeLiquidity(uint256 liquidity) → (uint256 amount0, uint256 amount1)`**

   Burns LP tokens, returns proportional share of both reserves:
   ```
   amount0 = liquidity · reserve0 / totalSupply
   amount1 = liquidity · reserve1 / totalSupply
   ```

3. **`swap(address tokenIn, uint256 amountIn) → uint256 amountOut`**

   Apply fee, compute output using constant product formula, transfer tokens. Update reserves.

   Critical: use the balance-before-after pattern from Module 1 if you want to support fee-on-transfer tokens. For this exercise, you can start without it and add it as an extension.

4. **`getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) → uint256`**

   Pure function implementing the swap math. This is the formula from above with fees applied.

**Security considerations to implement:**

- **Reentrancy guard** on swap and liquidity functions
- **Minimum liquidity** lock on first deposit
- **Reserve synchronization** — update reserves from actual balances after every operation
- **Zero-amount checks** — revert on zero deposits or zero output swaps
- **K invariant check** — after every swap, verify that `k_new >= k_old` (fees should only increase k)

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

**Extension exercises:**

- Add a `getSpotPrice()` view function
- Add a `getAmountIn()` function (given desired output, compute required input)
- Add events: `Swap`, `Mint`, `Burn` (match Uniswap V2's event signatures)
- Implement a simple TWAP (time-weighted average price) oracle: store cumulative price and timestamp on each swap, expose a function to compute average price over a period

---

## Days 3–4: Reading Uniswap V2

### Why V2 Matters

Even though V3 and V4 exist, Uniswap V2's codebase is the Rosetta Stone of DeFi. It's clean, well-documented, and every concept maps directly to what you just built. Most AMM forks in DeFi (SushiSwap, PancakeSwap, hundreds of others) are V2 forks. Understanding V2 deeply means you can audit and reason about a huge swath of deployed DeFi.

### Read: UniswapV2Pair.sol

**Source:** https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol

Read the entire contract. Map every function to your own implementation. Focus on:

**`mint()` — Adding liquidity**
- How it uses `_mintFee()` to collect protocol fees *before* computing LP tokens
- The `MINIMUM_LIQUIDITY` lock (exactly what you implemented)
- How it reads balances directly from `IERC20(token0).balanceOf(address(this))` rather than relying on `amount` parameters — this is the "pull" pattern that makes V2 composable

**`burn()` — Removing liquidity**
- The same balance-reading pattern
- How it sends tokens back using `_safeTransfer` (their own SafeERC20 equivalent)

**`swap()` — The swap function**
- The "optimistic transfer" pattern: tokens are sent to the recipient *first*, then the invariant is checked. This is what enables flash swaps — you can receive tokens, use them, and return them (or the equivalent) in the same transaction.
- The `require(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000**2)` check — this is the k-invariant with fees factored in
- The callback to `IUniswapV2Callee` — this is the flash swap mechanism

**`_update()` — Reserve and oracle updates**
- Cumulative price accumulators: `price0CumulativeLast` and `price1CumulativeLast`
- How TWAP oracles work: the price is accumulated over time, and external contracts can compute the time-weighted average by reading the cumulative value at two different timestamps
- The use of `UQ112.112` fixed-point numbers for precision

**`_mintFee()` — Protocol fee logic**
- If fees are on, the protocol takes 1/6th of LP fee growth (0.05% of the 0.3% swap fee)
- The clever math: instead of tracking fees directly, it compares `√k` growth between fee checkpoints

### Read: UniswapV2Factory.sol

**Source:** https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol

Focus on:
- `createPair()` — how `CREATE2` is used for deterministic addresses
- Why deterministic addresses matter: the Router can compute pair addresses without on-chain lookups
- The `feeTo` address for protocol fee collection

### Read: UniswapV2Router02.sol

**Source:** https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol

This is the user-facing contract. Note how it:
- Wraps ETH to WETH transparently
- Computes optimal liquidity amounts for adding liquidity
- Handles multi-hop swaps by chaining pair-to-pair transfers
- Enforces slippage protection via `amountOutMin` parameters
- Has deadline parameters to prevent stale transactions from executing

### Exercises

**Exercise 1: Flash swap.** Using your own pool or a V2 fork, implement a flash swap consumer contract. Borrow tokens, "use" them (e.g., check arbitrage conditions), then return them with fee. Write tests verifying the flash swap callback works and that failing to return tokens reverts.

**Exercise 2: Multi-hop routing.** Create two pools (A/B and B/C) and implement a simple router that executes an A→C swap through both pools. Compute the optimal path off-chain and verify the output matches.

**Exercise 3: TWAP oracle consumer.** Deploy a pool, execute swaps at known prices, advance time with `vm.warp()`, and read the TWAP. Verify the oracle returns the time-weighted average.

---

## Days 5–6: Concentrated Liquidity (Uniswap V3 Concepts)

### The Problem V3 Solves

In V2, liquidity is spread uniformly across the entire price range from 0 to infinity. For a stablecoin pair like DAI/USDC, the price almost always stays between 0.99 and 1.01 — meaning ~99.5% of LP capital is sitting idle at extreme price ranges that never get traded. This is massively capital-inefficient.

V3 lets LPs choose a specific price range for their liquidity. Capital between 0.99–1.01 instead of 0–∞ means the same dollar amount provides ~2000x more effective liquidity.

### Core V3 Concepts

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

**Positions:**

An LP position is defined by: `(lowerTick, upperTick, liquidity)`. The position is "active" (earning fees) only when the current price is within the tick range. When the price moves outside the range, the position becomes entirely denominated in one token and stops earning fees.

**sqrtPriceX96:**

V3 stores prices as `√P · 2^96` — the square root of the price in Q96 fixed-point format. Two reasons:
1. The key AMM math formulas involve `√P` directly, so storing it avoids repeated square root operations
2. Q96 fixed-point gives 96 bits of fractional precision without floating-point, which Solidity doesn't support

To convert `sqrtPriceX96` to a human-readable price:
```
price = (sqrtPriceX96 / 2^96)^2
```

**The swap loop:**

In V2, a swap is one formula evaluation. In V3, a swap may cross multiple tick boundaries, each changing the active liquidity. The swap loop:
1. Compute how much of the swap can be filled within the current tick range
2. If the swap isn't fully filled, cross the tick boundary — activate/deactivate liquidity from positions at that tick
3. Repeat until the swap is filled or the price limit is reached

Between any two initialized ticks, the math is identical to V2's constant product — just with `L` (liquidity) potentially different in each range.

**Liquidity (`L`):**

In V3, `L` represents the *depth* of liquidity at the current price. It relates to token amounts via:

```
Δtoken0 = L · (1/√P_lower - 1/√P_upper)
Δtoken1 = L · (√P_upper - √P_lower)
```

These formulas are why `√P` is stored directly — they simplify beautifully.

**LP tokens → NFTs:**

In V2, all LPs in a pool share fungible LP tokens. In V3, every position is unique (different range, different liquidity), so positions are represented as NFTs (ERC-721). This has major implications for composability — you can't just hold an ERC-20 LP token and deposit it into a farm; you need the NFT.

**Fee accounting:**

Fees in V3 are tracked per unit of liquidity within active ranges using `feeGrowthGlobal` and per-tick `feeGrowthOutside` values. The math for computing fees owed to a specific position involves subtracting the fee growth "below" and "above" the position's range from the global fee growth. This is elegant but complex — study it closely.

### Read: Key V3 Contracts

**Core contracts (v3-core):**
- `UniswapV3Pool.sol` — the pool itself (swap, mint, burn, collect)
- `UniswapV3Factory.sol` — pool deployment with fee tiers

**Focus areas in UniswapV3Pool:**

- **`swap()`** — the main swap loop. Trace the `while` loop step by step. Understand `computeSwapStep()`, tick crossing, and how `state.liquidity` changes at tick boundaries.
- **`mint()`** — how positions are created, how tick bitmaps track initialized ticks
- **`_updatePosition()`** — fee growth accounting per position
- **`slot0`** — the packed storage slot holding `sqrtPriceX96`, `tick`, `observationIndex`, and other frequently accessed data

**Libraries:**
- `TickMath.sol` — conversions between ticks and sqrtPriceX96
- `SqrtPriceMath.sol` — token amount calculations given liquidity and price ranges
- `SwapMath.sol` — compute swap steps within a single tick range
- `TickBitmap.sol` — efficient lookup of the next initialized tick

### Exercises

**Exercise 1: Tick math implementation.** Write Solidity functions that convert between ticks, prices, and sqrtPriceX96. Verify against TickMath.sol outputs using Foundry tests. This will cement the relationship between these representations.

**Exercise 2: Position value calculator.** Given a position's `(tickLower, tickUpper, liquidity)` and the current `sqrtPriceX96`, compute how many of each token the position currently holds. Handle the three cases: price below range, price within range, price above range.

**Exercise 3: Simulate a swap across ticks.** On paper or in a test, set up a pool with three positions at different ranges. Execute a large swap that crosses two tick boundaries. Trace the liquidity changes and verify the total output matches what V3 would produce.

---

## Days 7–8: Build a Simplified Concentrated Liquidity Pool

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

1. **`addLiquidity(int24 tickLower, int24 tickUpper, uint128 amount)`**
   - Compute token0 and token1 amounts needed for the given liquidity at the current price
   - Update tick data (add/remove liquidity at boundaries)
   - If the position range includes the current tick, add to active `liquidity`

2. **`swap(bool zeroForOne, int256 amountSpecified)`**
   - Implement the swap loop:
     - Compute the next initialized tick in the swap direction
     - Compute how much of the swap fills within the current range (use `SqrtPriceMath` formulas)
     - If the swap crosses a tick, update active liquidity and continue
     - Accumulate fees in `feeGrowthGlobal`

3. **`removeLiquidity(int24 tickLower, int24 tickUpper, uint128 amount)`**
   - Reverse of addLiquidity
   - Compute and distribute accrued fees to the position

**The key insight to internalize:**

Between any two initialized ticks, the pool behaves exactly like a V2 pool with liquidity `L`. The CLAMM is essentially a linked list of V2 segments, each with potentially different depth. The swap loop walks through these segments.

### Tests

- Create a single full-range position (equivalent to V2 behavior), verify swap outputs match your Day 1–2 pool
- Create two overlapping positions, verify liquidity adds at overlapping ticks
- Execute a swap that crosses a tick boundary, verify liquidity changes correctly
- Verify fee accrual: position earning fees only while in range
- Out-of-range position: add liquidity above current price, verify it earns zero fees, verify it's 100% token0
- Impermanent loss test: add position, execute swaps that move price significantly, remove position, compare to holding

---

## Day 9: Uniswap V4 — Singleton Architecture and Flash Accounting

### Architectural Revolution

V4 is a fundamentally different architecture from V2/V3. The two key innovations:

**1. Singleton Pattern (PoolManager)**

In V2 and V3, every token pair gets its own deployed contract (created by the Factory). This means multi-hop swaps (A→B→C) require actual token transfers between pool contracts — expensive in gas.

V4 consolidates all pools into a single contract called `PoolManager`. Pools are just entries in a mapping, not separate contracts. Creating a new pool is a state update, not a contract deployment — approximately 99% cheaper in gas.

The key benefit: multi-hop swaps never move tokens between contracts. All accounting happens internally within the PoolManager. Only the final net token movements are settled at the end.

**2. Flash Accounting (EIP-1153 Transient Storage)**

V4 uses transient storage (which you studied in Part 1) to implement "flash accounting." During a transaction:

1. The caller "unlocks" the PoolManager
2. The caller can perform multiple operations (swaps, liquidity changes) across any pools
3. The PoolManager tracks net balance changes ("deltas") in transient storage
4. At the end, the caller must settle all deltas to zero — either by transferring tokens or using ERC-6909 claim tokens
5. If deltas aren't zero, the transaction reverts

This is essentially flash-loan-like behavior baked into the protocol's core. You can swap A→B in one pool and B→C in another without ever transferring B — the PoolManager tracks that your B delta nets to zero.

**3. Native ETH Support**

Because flash accounting handles all token movements internally, V4 can support native ETH directly — no WETH wrapping needed. ETH transfers (`msg.value`) are cheaper than ERC-20 transfers, saving gas on the most common trading pairs.

**4. ERC-6909 Claim Tokens**

Instead of withdrawing tokens from the PoolManager, users can receive ERC-6909 tokens representing claims on tokens held by the PoolManager. These claims can be burned in future interactions instead of doing full ERC-20 transfers. This is a lightweight multi-token standard (simpler than ERC-1155) optimized for gas.

### Read: Key V4 Contracts

**Source:** https://github.com/Uniswap/v4-core

Focus on:
- **`PoolManager.sol`** — the singleton. Study `unlock()`, `swap()`, `modifyLiquidity()`, and the delta accounting system
- **`Pool.sol` (library)** — the actual pool math, used by PoolManager. Note how it's a library, not a contract — keeping the PoolManager modular
- **`PoolKey`** — the struct that identifies a pool: `(currency0, currency1, fee, tickSpacing, hooks)`
- **`BalanceDelta`** — a packed int256 representing net token changes

**Periphery (v4-periphery):**
- **`PositionManager.sol`** — the entry point for LPs, manages positions as ERC-721 NFTs
- **`V4Router.sol`** / **Universal Router** — the entry point for swaps

### Exercises

**Exercise 1: Study the unlock pattern.** Trace through a simple swap: how does the caller interact with PoolManager? What's the sequence of `unlock()` → callback → `swap()` → `settle()` / `take()`? Draw the flow.

**Exercise 2: Multi-hop with flash accounting.** On paper, trace a three-pool multi-hop swap (A→B→C→D). Show how deltas accumulate and net to zero for intermediate tokens. Compare the token transfer count to V2/V3 equivalents.

**Exercise 3: Deploy PoolManager locally.** Fork mainnet or deploy V4 contracts to anvil. Create a pool, add liquidity, execute a swap. Observe the delta settlement pattern in practice.

---

## Day 10: Uniswap V4 Hooks

### The Hook System

Hooks are external smart contracts that the PoolManager calls at specific points during pool operations. They are V4's extension mechanism — the "app store" for AMMs.

A pool is linked to a hook contract at initialization and cannot change it afterward. The hook address itself encodes which callbacks are enabled — specific bits in the address determine which hook functions the PoolManager will call. This is a gas optimization: the PoolManager checks the address bits rather than making external calls to query capabilities.

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

### Hook Capabilities

**Dynamic fees:** A hook can implement `getFee()` to return a custom fee for each swap. This enables strategies like: higher fees during volatile periods, lower fees for certain users, MEV-aware fee adjustment.

**Custom accounting:** Hooks can modify the token amounts involved in swaps. The `beforeSwap` return value can specify delta modifications, allowing the hook to effectively intercept and re-route part of the trade.

**Access control:** Hooks can implement KYC/AML checks, restricting who can swap or provide liquidity.

**Oracle integration:** A hook can maintain a custom oracle, updated on every swap — similar to V3's built-in oracle but customizable.

### Read: Hook Examples

**Source:** https://github.com/Uniswap/v4-periphery (hooks examples)
**Source:** https://github.com/fewwwww/awesome-uniswap-hooks (curated list)

Study these hook patterns:
- **Limit order hook** — converts a liquidity position into a limit order that executes when the price crosses a specific tick
- **TWAP hook** — maintains a custom time-weighted average price oracle
- **Dynamic fee hook** — adjusts fees based on volatility or other on-chain signals
- **Full-range hook** — enforces V2-style full-range liquidity for specific use cases

### Hook Security Considerations

Hooks introduce new attack surfaces:

- **Access control:** Hooks MUST verify that `msg.sender` is the legitimate PoolManager. Without this check, attackers can call hook functions directly and manipulate internal state. The Cork Protocol exploit demonstrated this exact vulnerability.
- **Gas griefing:** A malicious or buggy hook with unbounded loops can make a pool permanently unusable by consuming all gas in swap transactions.
- **Reentrancy:** Hooks execute within the PoolManager's context. If a hook makes external calls, it could re-enter the PoolManager.
- **Trust model:** Users must trust the hook contract as much as they trust the pool itself. A malicious hook can front-run swaps, extract MEV, or drain liquidity.
- **Immutability:** Once a pool is initialized with a hook, the hook cannot be changed. If the hook has a bug, the pool must be abandoned and a new one created.

### Build: A Simple Hook

**Exercise 1: Dynamic fee hook.** Build a hook that adjusts the swap fee based on recent volatility. Track the last N swap prices, compute a simple volatility metric, and return a higher fee when volatility is elevated. This teaches you the full hook development cycle:

- Extend `BaseHook` from v4-periphery
- Set the correct hook address bits (use the `Hooks` library to mine an address with the right flags)
- Implement `beforeSwap` to adjust fees
- Deploy and test with a real PoolManager

**Exercise 2: Swap counter hook.** Build a minimal hook that simply counts the number of swaps on a pool. This is the "hello world" of hooks — it gets you through the setup and deployment mechanics without complex logic.

**Exercise 3: Read an existing production hook.** Pick one from the awesome-uniswap-hooks list (Clanker, EulerSwap, or the Full Range hook from Uniswap themselves). Read the source, understand what lifecycle points it hooks into and why.

---

## Beyond Uniswap: Other AMM Designs (Awareness)

This module focuses on Uniswap because it's the Rosetta Stone of AMMs — V2's constant product, V3's concentrated liquidity, and V4's hooks represent the core design space. But two other AMM architectures are important to know about. They'll be covered in depth in Part 3; this section gives you enough context to recognize them in the wild.

### Curve StableSwap

Curve is the dominant AMM for assets that should trade near 1:1 (stablecoins, wrapped/staked ETH variants). Its invariant is a hybrid between constant-product (`x · y = k`) and constant-sum (`x + y = k`):

- Constant-sum gives zero slippage but can be fully drained of one token
- Constant-product can't be drained but gives increasing slippage
- Curve blends them via an "amplification parameter" `A` that controls how close to constant-sum the curve behaves near the equilibrium point

When prices are near 1:1, Curve pools offer far lower slippage than Uniswap. When prices deviate significantly, the curve reverts to constant-product behavior for safety.

**Why this matters for DeFi builders:** If your protocol involves stablecoin swaps (liquidations paying in USDC to receive DAI, for example), Curve pools will likely offer better execution than Uniswap V2/V3 for those pairs. Understanding the StableSwap invariant also helps you reason about stablecoin depegging mechanics (Module 6).

### Balancer Weighted Pools

Balancer generalizes the constant product formula to N tokens with arbitrary weights. The invariant:

```
∏(Bi^Wi) = k     (product of each balance raised to its weight)
```

A pool with 80% ETH / 20% USDC behaves like a self-rebalancing portfolio — the pool naturally maintains the target ratio as prices change. This enables:
- Index-fund-like pools (e.g., 33% ETH, 33% BTC, 33% stables)
- Liquidity bootstrapping pools (LBPs) where weights shift over time for token launches

**Why this matters:** Balancer's Vault architecture (all tokens in one contract) inspired Uniswap V4's singleton pattern. Balancer V2 also provides zero-fee flash loans from its consolidated liquidity — which you'll use in Module 5.

---

## Practice Challenges

Test your AMM understanding with these exercises:

- **Damn Vulnerable DeFi #5 "The Rewarder"** — Reward token distribution interacting with pool deposits. Explores timing attacks on reward mechanisms.
- **Damn Vulnerable DeFi #4 "Side Entrance"** — A flash loan pool with a subtle accounting flaw in its deposit/withdraw logic. Directly tests your understanding of how pool accounting should work.

---

## Key Takeaways for Protocol Builders

After 10 days, you should have internalized:

1. **The constant product formula is everywhere.** Even V3's concentrated liquidity reduces to V2's formula within each tick range. If you understand `x · y = k`, you understand the core of every AMM.

2. **Price impact is nonlinear.** The constant product curve means that larger trades get progressively worse prices. This is *by design* — it's the AMM's defense against being drained. Any protocol you build that touches AMMs must account for price impact and slippage.

3. **Impermanent loss is the fundamental LP trade-off.** LPs are essentially selling options to arbitrageurs. Fee income must exceed IL for LPs to profit. When building a protocol that involves LP positions, you must help users understand this trade-off.

4. **V3 concentrated liquidity = more capital efficiency, more complexity.** Narrow ranges earn more fees but require active management and expose LPs to sharper IL. Wide ranges are passive but capital-inefficient. The design of your protocol should account for which type of LP you're targeting.

5. **V4 hooks are the future of AMM innovation.** Instead of forking an AMM to add custom logic (which fragments liquidity), you build a hook and plug into V4's shared liquidity. This is the primary way DeFi protocols will extend AMM functionality going forward.

6. **Flash accounting + transient storage is a design pattern, not just a V4 feature.** The idea of tracking deltas and settling at the end of a transaction can be applied to any protocol that handles multiple token movements. You'll see this pattern again in lending, bridges, and aggregators.

---

## Resources

**Essential reading:**
- Uniswap V2 Whitepaper: https://uniswap.org/whitepaper.pdf
- Uniswap V3 Whitepaper: https://uniswap.org/whitepaper-v3.pdf
- Uniswap V4 Whitepaper: https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper-v4.pdf
- Uniswap V3 Math Primer (Parts 1 & 2): https://blog.uniswap.org/uniswap-v3-math-primer

**Source code:**
- Uniswap V2 Core: https://github.com/Uniswap/v2-core
- Uniswap V2 Periphery: https://github.com/Uniswap/v2-periphery
- Uniswap V3 Core: https://github.com/Uniswap/v3-core (archived, read-only)
- Uniswap V4 Core: https://github.com/Uniswap/v4-core
- Uniswap V4 Periphery: https://github.com/Uniswap/v4-periphery
- Awesome Uniswap Hooks: https://github.com/fewwwww/awesome-uniswap-hooks

**Deep dives:**
- Concentrated liquidity math: https://atiselsts.github.io/pdfs/uniswap-v3-liquidity-math.pdf
- V3 ticks deep dive: https://mixbytes.io/blog/uniswap-v3-ticks-dive-into-concentrated-liquidity
- V4 architecture and security: https://www.zealynx.io/blogs/uniswap-v4
- Uniswap V4 hooks documentation: https://docs.uniswap.org/concepts/protocol/hooks

**Interactive learning:**
- Uniswap V3 Development Book: https://uniswapv3book.com/

---

*Next module: Oracles — why DeFi needs price feeds, Chainlink architecture, TWAP oracles, and oracle manipulation attacks.*

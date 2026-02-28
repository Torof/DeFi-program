# Part 3 — Module 4: DEX Aggregation & Intents (~4 days)

**Prerequisites:** Part 2 — Modules 2 (AMMs), 5 (Flash Loans) | Part 1 — Module 3 (EIP-712)
**Pattern:** The routing problem → Aggregator on-chain patterns → Intent paradigm → Settlement architecture → Solvers → Batch auctions → Hands-on
**Builds on:** AMM curve theory (P2M2), flash loan patterns (P2M5), EIP-712 signing (P1M3)
**Used by:** Module 5 (MEV — intents as MEV protection), Module 9 (Capstone — solver/routing integration)

## 📚 Table of Contents

1. [The Routing Problem](#routing-problem)
2. [Split Order Math](#split-order-math)
3. [Aggregator On-Chain Patterns](#aggregator-patterns)
4. [The Intent Paradigm](#intent-paradigm)
5. [EIP-712 Order Structures](#eip712-orders)
6. [Dutch Auction Price Decay](#dutch-auction)
7. [Settlement Contract Architecture](#settlement-architecture)
8. [Solvers & the Filler Ecosystem](#solvers)
9. [CoW Protocol: Batch Auctions](#cow-protocol)
10. [Interview Prep](#interview-prep)
11. [Exercises](#exercises)
12. [Resources](#resources)

---

## Overview

In practice, no single DEX has the best price for every trade. DEX aggregators solve the routing problem — finding optimal execution across fragmented liquidity. More recently, intent-based trading is replacing explicit transaction construction: users sign *what* they want, and solvers compete to figure out *how* to fill it.

This module covers both models — from traditional split-routing to the intent/solver paradigm that's reshaping DeFi execution. The emphasis is on intents: that's where the ecosystem is heading and where the job opportunities are.

---

<a id="routing-problem"></a>
## The Routing Problem

### 💡 Why Aggregation Exists

**The problem:** No single DEX has the best price for every trade.

Liquidity is fragmented across Uniswap V2/V3/V4, Curve, Balancer, SushiSwap, and hundreds of other pools. A 100 ETH trade on a single pool takes massive slippage. Split across multiple pools, total slippage drops dramatically.

This is the same insight that drives order routing in traditional finance — NBBO (National Best Bid and Offer) ensures trades execute at the best available price across exchanges. DEX aggregators are DeFi's equivalent.

**Why this matters for you:**
- Every DeFi protocol needs to think about where swaps happen
- Liquidation bots, arbitrage bots, and MEV searchers all solve routing problems
- If you build anything that swaps tokens, you'll either use an aggregator or build routing logic

### The Three Execution Models

Before diving into math, understand the evolution:

```
Traditional Swap     →    Aggregated Swap      →    Intent-Based Swap
──────────────────────────────────────────────────────────────────────
User picks one pool  →  Router finds best path  →  User signs what they want
User submits tx      →  Router submits tx        →  Solver fills the order
User takes slippage  →  Less slippage via splits →  Solver absorbs MEV risk
100% on-chain        →  Off-chain routing,       →  Off-chain solver,
                        on-chain execution          on-chain settlement
```

This module covers all three, with emphasis on the intent model — that's where the ecosystem is heading.

---

<a id="split-order-math"></a>
## Split Order Math

### 💡 When Does Splitting Beat a Single Pool?

This connects directly to your AMM math from Part 2 Module 2. Recall the constant product formula:

```
amountOut = reserveOut × amountIn / (reserveIn + amountIn)
```

The key insight: **price impact is nonlinear**. Doubling the trade size MORE than doubles the slippage. This means splitting a large trade across two pools produces less total slippage than routing through one.

#### 🔍 Deep Dive: Optimal Split Calculation

**Setup:** Two constant-product pools for the same pair (e.g., ETH/USDC):
- Pool A: reserves (xA, yA), k_A = xA × yA
- Pool B: reserves (xB, yB), k_B = xB × yB
- Total trade: sell Δ of token X

**Single pool output:**

```
outSingle = yA × Δ / (xA + Δ)
```

**Split output (δA to pool A, δB = Δ - δA to pool B):**

```
outSplit = yA × δA / (xA + δA)  +  yB × δB / (xB + δB)
```

**Optimal split** — maximize total output. Taking the derivative and setting to zero:

The optimal split gives **equal marginal price** in both pools after the trade. For constant-product pools, the marginal price after trading δ is `dy/dx = y × x / (x + δ)²`. Setting equal across pools:

```
After trading, both pools should have the same marginal price:

  yA × xA / (xA + δA)²  =  yB × xB / (xB + δB)²

For equal-price pools (yA/xA = yB/xB), this simplifies to:

  δA / δB ≈ xA / xB

Split proportional to pool depth.
```

**Intuition:** Send more volume to the deeper pool. If pool A has 2x the reserves of pool B, send roughly 2x the amount through pool A.

#### Worked Example: 100 ETH → USDC

```
Pool A: 1000 ETH / 2,000,000 USDC  (spot price: $2,000/ETH)
Pool B:  500 ETH / 1,000,000 USDC  (spot price: $2,000/ETH)
Total trade: 100 ETH

──── Single pool (all to A) ────
  out = 2,000,000 × 100 / (1000 + 100) = 181,818 USDC
  Effective price: $1,818/ETH
  Slippage: 9.1%

──── Split (67 ETH to A, 33 ETH to B — proportional to reserves) ────
  outA = 2,000,000 × 67 / (1000 + 67) = 125,585 USDC
  outB = 1,000,000 × 33 / (500 + 33)  =  61,913 USDC
  Total: 187,498 USDC
  Effective price: $1,875/ETH
  Slippage: 6.25%

──── Savings ────
  187,498 - 181,818 = 5,680 USDC  (+3.1% better)
```

**But there's a cost:** Each additional pool interaction costs gas. On L1, that's ~100k gas ≈ $5-50 depending on gas prices. On L2, it's negligible.

**Break-even formula:**

```
Split is worth it when:  slippageSavings > gasCostOfExtraPoolCall

Our example:
  If gas cost = $10:    saves $5,670 net → absolutely split
  If gas cost = $6,000: loses  $320 net  → single pool wins
```

This is why L2s enable more aggressive routing — the gas overhead of extra hops is near-zero.

💻 **Quick Try:**

Deploy this in [Remix](https://remix.ethereum.org/) to feel split routing:

```solidity
contract SplitDemo {
    // Pool A: 1000 ETH / 2,000,000 USDC
    uint256 xA = 1000e18;  uint256 yA = 2_000_000e18;
    // Pool B:  500 ETH / 1,000,000 USDC
    uint256 xB =  500e18;  uint256 yB = 1_000_000e18;

    function singlePool(uint256 amtIn) external view returns (uint256) {
        return yA * amtIn / (xA + amtIn);
    }

    function splitPools(uint256 amtIn) external view returns (uint256) {
        // Split proportional to reserves: 2/3 to A, 1/3 to B
        uint256 toA = amtIn * 2 / 3;
        uint256 toB = amtIn - toA;
        return yA * toA / (xA + toA) + yB * toB / (xB + toB);
    }
}
```

Try `singlePool(100e18)` vs `splitPools(100e18)` — the split wins by ~5,680 USDC. Now try `1e18` (tiny trade) — almost no difference. Splitting only matters when trade size is large relative to pool depth.

### 🔗 DeFi Pattern Connection

**Where split routing appears:**
- **DEX aggregators** (1inch, Paraswap, 0x) — their entire value proposition
- **Liquidation bots** — finding the best path to sell seized collateral
- **Arbitrage bots** — routing through multiple pools to capture price discrepancies
- **Protocol integrations** — any protocol that swaps tokens internally (vaults, CDPs, etc.)

The math is the same as Part 2 Module 2's AMM analysis, applied to optimization *across* pools instead of within one.

---

<a id="aggregator-patterns"></a>
## Aggregator On-Chain Patterns

### 💡 The Multi-Call Executor Pattern

Every aggregator — 1inch, Paraswap, 0x, CowSwap — uses the same on-chain pattern. The off-chain router determines the optimal path; the on-chain executor just follows instructions:

```
┌─────────────────────────────────────────┐
│              User                        │
│  1. approve(router, amount)             │
│  2. router.swap(encodedRoute)           │
└──────────┬──────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│         Router Contract                  │
│  1. transferFrom(user, self, amountIn)  │
│  2. For each hop in route:              │
│     a. approve(pool, hopAmount)         │
│     b. pool.swap(params)               │
│  3. transfer(user, finalOutput)         │
│  4. Verify: output >= minOutput         │
└─────────────────────────────────────────┘
```

**Simplified router pattern:**

```solidity
contract SimpleRouter {
    struct SwapStep {
        address pool;
        address tokenOut;
    }

    function swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        SwapStep[] calldata steps
    ) external returns (uint256 amountOut) {
        // Pull tokens from user
        tokenIn.transferFrom(msg.sender, address(this), amountIn);

        // Execute each step
        uint256 currentAmount = amountIn;
        IERC20 currentToken = tokenIn;

        for (uint256 i = 0; i < steps.length; i++) {
            currentToken.approve(steps[i].pool, currentAmount);
            currentAmount = IPool(steps[i].pool).swap(
                address(currentToken),
                steps[i].tokenOut,
                currentAmount,
                0  // router checks min at the end, not per-hop
            );
            currentToken = IERC20(steps[i].tokenOut);
        }

        // Final check + transfer
        require(currentAmount >= minAmountOut, "Insufficient output");
        currentToken.transfer(msg.sender, currentAmount);

        return currentAmount;
    }
}
```

**Key design decisions in this pattern:**
- **Min output check at the end, not per-hop.** Intermediate steps might give "bad" prices that result in good final output via multi-hop routing
- **Pull pattern** (transferFrom) — the user initiates by calling the router
- **Approval management** — some routers use infinite approvals to trusted pools, others approve per-swap
- **Dust handling** — rounding can leave tiny amounts in the router; production routers sweep these back

### Gas Optimization: Packed Calldata

Production aggregators go far beyond the simple struct-based pattern:

```solidity
// 1inch uses packed uint256 arrays instead of struct arrays:
function unoswap(
    IERC20 srcToken,
    uint256 amount,
    uint256 minReturn,
    uint256[] calldata pools  // each uint256 packs: address + direction + flags
) external returns (uint256);
```

**Why?** Calldata costs 16 gas per non-zero byte, 4 gas per zero byte. Packing a pool address (20 bytes) + direction flag (1 bit) + fee tier (2 bytes) into a single `uint256` saves significant calldata gas. On L2s (where calldata is the dominant cost), this matters even more.

### 📖 How to Study: 1inch AggregationRouterV6

1. Start with `unoswap()` — single-pool swap, simplest path
2. Read `swap()` — the general multi-hop/multi-split executor
3. Study how `GenericRouter` uses `delegatecall` to protocol-specific handlers
4. Look at calldata encoding — how pools, amounts, and flags are packed

Don't try to understand the full router in one pass. The core pattern is the multi-call loop above; everything else is gas optimization and edge-case handling.

> 🔍 **Code:** [1inch Limit Order Protocol](https://github.com/1inch/limit-order-protocol) — V6 aggregation router source is not publicly available; the limit-order-protocol repo is the best open-source reference for 1inch's on-chain patterns

---

<a id="intent-paradigm"></a>
## The Intent Paradigm

### 💡 From Transactions to Intents

This is arguably the most important paradigm shift in DeFi since AMMs:

```
TRANSACTION MODEL (2020-2023):
──────────────────────────────
User: "Swap 1 ETH for USDC on Uniswap V3, 0.3% pool,
       min 1900 USDC, via the public mempool"
Problem: User specifies HOW → gets sandwiched → takes MEV loss

INTENT MODEL (2023+):
─────────────────────
User: "I want at least 1900 USDC for my 1 ETH.
       I don't care how you do it."
Solver: "I'll give you 1920 USDC — routing through V3 + Curve,
         or using my private inventory, or going through a CEX."
```

**Why this matters:**
- User gets better prices (solvers compete on execution quality)
- MEV goes to user (via solver competition) instead of to searchers
- Cross-chain execution becomes possible (solver handles complexity)
- User doesn't need to know which pools exist or how to route

**The key innovation:** Separate WHAT (user's intent) from HOW (execution strategy). The competitive market for solvers ensures good execution quality.

### The Intent Lifecycle

```
1. USER SIGNS ORDER (off-chain, gasless)
   ┌──────────────────────────────────┐
   │  I want to sell: 1 ETH           │
   │  I want at least: 1900 USDC      │
   │  Deadline: block 19000000        │
   │  Signature: 0xabc...             │
   └──────────────────────────────────┘
              │
              ▼
2. SOLVERS COMPETE (off-chain)
   ┌───────────┐  ┌───────────┐  ┌───────────┐
   │ Solver A   │  │ Solver B   │  │ Solver C   │
   │ Via V3:    │  │ Via CEX:   │  │ Inventory: │
   │ 1915 USDC  │  │ 1920 USDC  │  │ 1918 USDC  │
   └───────────┘  └───────────┘  └───────────┘
                        │ ← Best offer wins
                        ▼
3. SETTLEMENT (on-chain, solver pays gas)
   ┌──────────────────────────────────┐
   │  Settlement Contract              │
   │  1. Verify user's EIP-712 sig    │
   │  2. Check: 1920 >= 1900 ✓        │
   │  3. Transfer 1 ETH from user     │
   │  4. Transfer 1920 USDC to user   │
   │  5. Emit OrderFilled event       │
   └──────────────────────────────────┘
```

---

<a id="eip712-orders"></a>
## EIP-712 Order Structures

### 💡 How Intent Orders Are Signed

EIP-712 enables typed, structured data signing — the user sees exactly what they're signing in their wallet, not just a hex blob. This is the foundation of every intent protocol.

> Recall from Part 1 Module 3: EIP-712 defines domain separators and type hashes for structured signing.

**UniswapX order structure (simplified):**

```solidity
struct Order {
    address offerer;          // who is selling
    IERC20 inputToken;        // token being sold
    uint256 inputAmount;      // amount being sold
    IERC20 outputToken;       // token being bought
    uint256 outputAmount;     // minimum amount to receive
    uint256 deadline;         // order expiration
    address recipient;        // who receives the output (usually = offerer)
    uint256 nonce;            // replay protection
}
```

**EIP-712 signing flow — the four steps:**

```solidity
// 1. Define the type hash (compile-time constant)
bytes32 constant ORDER_TYPEHASH = keccak256(
    "Order(address offerer,address inputToken,uint256 inputAmount,"
    "address outputToken,uint256 outputAmount,uint256 deadline,"
    "address recipient,uint256 nonce)"
);

// 2. Hash the struct fields
function hashOrder(Order memory order) internal pure returns (bytes32) {
    return keccak256(abi.encode(
        ORDER_TYPEHASH,
        order.offerer,
        order.inputToken,
        order.inputAmount,
        order.outputToken,
        order.outputAmount,
        order.deadline,
        order.recipient,
        order.nonce
    ));
}

// 3. Create the EIP-712 digest (domain separator + struct hash)
function getDigest(Order memory order) public view returns (bytes32) {
    return keccak256(abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        hashOrder(order)
    ));
}

// 4. Recover signer and verify
function verifyOrder(Order memory order, bytes memory signature)
    public view returns (address)
{
    bytes32 digest = getDigest(order);
    return ECDSA.recover(digest, signature);
}
```

**Why EIP-712 and not just `keccak256(abi.encode(...))`?**
- User sees "Sell 1 ETH for at least 1900 USDC" in MetaMask — not `0x5a3b7c...`
- **Domain separator** prevents cross-protocol replay (can't reuse a UniswapX signature on CoW Protocol)
- **Nonce** prevents same-order replay (fill it twice)
- **Type hash** ensures the struct layout is part of the hash (prevents field reordering attacks)

💻 **Quick Try:**

In Foundry, you can sign EIP-712 messages in tests with `vm.sign`:

```solidity
// Setup: create a user with a known private key
uint256 userPK = 0xA11CE;
address user = vm.addr(userPK);

// Build the order
Order memory order = Order({
    offerer: user,
    inputToken: IERC20(weth),
    inputAmount: 1e18,
    outputToken: IERC20(usdc),
    outputAmount: 1900e6,
    deadline: block.timestamp + 1 hours,
    recipient: user,
    nonce: 0
});

// Sign it
bytes32 digest = settlement.getDigest(order);
(uint8 v, bytes32 r, bytes32 s) = vm.sign(userPK, digest);
bytes memory signature = abi.encodePacked(r, s, v);

// Verify
address recovered = settlement.verifyOrder(order, signature);
assertEq(recovered, user);
```

This is exactly how your Exercise 2 tests will work.

---

<a id="dutch-auction"></a>
## Dutch Auction Price Decay

### 💡 How Price Discovery Works in Intents

In traditional limit orders, the user sets a fixed price. In intent-based trading, a **Dutch auction** finds the market price through time decay. The output the solver must provide starts high and decreases over time:

```
Output solver must provide
        │
  1950  │ ●                          ← Start: bad for solver (almost no profit)
        │    ●
  1930  │       ●
        │          ●
  1910  │             ●              ← Someone fills here (profitable enough)
        │                ●
  1900  │───────────────────●────    ← End: user's minimum (max solver profit)
        │
        └─────────────────────── Time
        t=0    30s    60s    90s
```

### The Formula

```
decayedOutput = startOutput - (startOutput - endOutput) × elapsed / decayPeriod
```

Where:
- `startOutput` = initial (high) output — almost no profit for solver
- `endOutput` = final (low) output — user's limit price
- `decayPeriod` = total auction duration
- `elapsed` = time since auction started (clamped to decayPeriod)

#### 🔍 Deep Dive: Step-by-Step

```
Parameters:  startOutput = 1950, endOutput = 1900, decayPeriod = 90s

At t =  0s:  1950 - (1950 - 1900) × 0/90   = 1950 - 0.0    = 1950 USDC
At t = 30s:  1950 - (1950 - 1900) × 30/90  = 1950 - 16.67  = 1933 USDC
At t = 45s:  1950 - (1950 - 1900) × 45/90  = 1950 - 25.0   = 1925 USDC
At t = 60s:  1950 - (1950 - 1900) × 60/90  = 1950 - 33.33  = 1917 USDC
At t = 90s:  1950 - (1950 - 1900) × 90/90  = 1950 - 50.0   = 1900 USDC
After 90s:   Clamped to endOutput = 1900 USDC
```

**In Solidity (from UniswapX's DutchDecayLib):**

```solidity
function resolve(
    uint256 startAmount,
    uint256 endAmount,
    uint256 decayStartTime,
    uint256 decayEndTime
) internal view returns (uint256) {
    if (block.timestamp <= decayStartTime) {
        return startAmount;
    }
    if (block.timestamp >= decayEndTime) {
        return endAmount;
    }

    uint256 elapsed = block.timestamp - decayStartTime;
    uint256 duration = decayEndTime - decayStartTime;
    uint256 decay = (startAmount - endAmount) * elapsed / duration;

    return startAmount - decay;
}
```

💻 **Quick Try:**

Deploy this in [Remix](https://remix.ethereum.org/) to watch Dutch auction decay in action:

```solidity
contract DutchDemo {
    uint256 public startTime;
    uint256 public startOutput = 1950;  // best for user
    uint256 public endOutput   = 1900;  // user's limit
    uint256 public duration    = 90;    // seconds

    constructor() { startTime = block.timestamp; }

    function currentOutput() external view returns (uint256) {
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= duration) return endOutput;
        return startOutput - (startOutput - endOutput) * elapsed / duration;
    }

    function reset() external { startTime = block.timestamp; }
}
```

Deploy, call `currentOutput()` immediately (1950). Wait 30+ seconds, call again — watch it drop. Call `reset()` to restart. The solver's decision: fill now (less profit) or wait (risk someone else fills first).

**Why Dutch auctions are brilliant for intents:**

1. **Price discovery without an order book.** The auction finds the market clearing price automatically through time.
2. **Solver competition compressed into time.** The first solver to fill profitably wins. Earlier fill = less profit for solver = better for user.
3. **No wasted gas.** Unlike English auctions where everyone bids on-chain, Dutch auctions have a single on-chain transaction (the fill).
4. **MEV-resistant.** The auction *is* the price discovery mechanism — there's nothing to sandwich.

**The tradeoff:** Decay parameters matter. Too fast a decay → solver gets a cheap fill. Too slow → user waits too long. Production protocols tune these per-pair and per-market-condition.

### 🔗 DeFi Pattern Connection

**Dutch auctions appear everywhere in DeFi:**
- **UniswapX** — solver competition for order fills (this module)
- **MakerDAO** — collateral auctions in liquidation (Part 2 Module 6)
- **Part 2 Module 9 capstone** — your stablecoin's Dutch auction liquidator uses the same formula!
- **Gradual Dutch Auctions (GDAs)** — Paradigm's design for NFTs and token sales

The formula is identical across all of these. What changes is: who's buying, what's being sold, and how the decay parameters are tuned.

---

<a id="settlement-architecture"></a>
## Settlement Contract Architecture

### 💡 The UniswapX Reactor Pattern

The **Reactor** is UniswapX's on-chain settlement engine. It's where the trust guarantee lives — no matter what the solver does off-chain, the on-chain contract enforces that the user gets what they signed for.

**Simplified settlement flow:**

```solidity
contract IntentSettlement {
    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address => mapping(uint256 => bool)) public nonces;

    /// @notice Fill a signed order. Called by the solver.
    function fill(
        Order calldata order,
        bytes calldata signature,
        uint256 fillerOutputAmount
    ) external {
        // 1. Verify the order signature
        address signer = verifyOrder(order, signature);
        require(signer == order.offerer, "Invalid signature");

        // 2. Check order hasn't expired
        require(block.timestamp <= order.deadline, "Order expired");

        // 3. Check nonce not used (replay protection)
        require(!nonces[order.offerer][order.nonce], "Already filled");
        nonces[order.offerer][order.nonce] = true;

        // 4. Resolve Dutch auction decay
        uint256 minOutput = resolveDecay(order);

        // 5. Verify solver provides enough
        require(fillerOutputAmount >= minOutput, "Insufficient output");

        // 6. Execute the swap atomically
        order.inputToken.transferFrom(order.offerer, msg.sender, order.inputAmount);
        order.outputToken.transferFrom(msg.sender, order.recipient, fillerOutputAmount);
    }
}
```

**Critical security properties:**
- **Signature verification** — only the offerer can authorize selling their tokens
- **Nonce** — prevents the same order from being filled twice
- **Min output check** — user ALWAYS gets at least the decayed auction amount
- **Atomic execution** — both transfers succeed or both revert
- **No solver trust** — the contract enforces rules; it doesn't trust the solver

### UniswapX's Full Architecture

UniswapX adds several production features on top of the basic pattern:

```
┌────────────────────────────────────────────────────┐
│            ExclusiveDutchOrderReactor               │
│                                                     │
│  ┌──────────────┐   ┌──────────────────────────┐   │
│  │ Permit2       │   │ ResolvedOrder             │   │
│  │ (approvals)   │   │  - decay applied          │   │
│  │               │   │  - outputs resolved       │   │
│  └──────────────┘   └──────────────────────────┘   │
│                                                     │
│  fill()  ──→  validate   ──→  resolve  ──→  settle  │
│               signature       decay        execute  │
│                                                     │
│  Exclusive filler window (optional):                │
│  First N seconds: only designated filler can fill   │
│  After N seconds: open to all fillers               │
└────────────────────────────────────────────────────┘
```

**Three key patterns from UniswapX:**

**1. Permit2 integration** — Users approve the Permit2 contract once, then sign per-order permits. No separate `approve()` transaction per order — huge UX improvement.

**2. Exclusive filler window** — For the first N seconds, only one designated solver can fill. The solver gets guaranteed exclusivity in exchange for committing to better starting prices. After the window, any solver can fill.

**3. Callback pattern** — Solvers can receive a callback *before* providing output tokens, letting them source liquidity just-in-time:

```solidity
// The Reactor calls the filler's callback before checking output
IReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);
// THEN verifies that output tokens arrived at the recipient
```

This is powerful — the solver can flash-swap from Uniswap, arbitrage across pools, or bridge from another chain *inside the callback*. They don't need to pre-fund the fill.

### 📖 How to Study: UniswapX

1. Start with `ExclusiveDutchOrderReactor.sol` — the main entry point
2. Read `DutchDecayLib.sol` — the decay math (short, pure functions)
3. Study `ResolvedOrder` — how raw orders become executable orders
4. Look at `IReactorCallback` — the solver callback interface
5. Skip Permit2 internals initially — just know it handles gasless approvals

> 🔍 **Code:** [UniswapX](https://github.com/Uniswap/UniswapX) — start with `src/reactors/`

---

<a id="solvers"></a>
## Solvers & the Filler Ecosystem

### 💡 What Solvers Actually Do

A solver (or "filler") is a service that fills intent orders profitably. This is one of the hottest areas in DeFi right now — teams are actively hiring solver engineers.

**A solver's job, step by step:**

```
1. MONITOR — Watch for new signed orders (from UniswapX API, CoW API, etc.)

2. EVALUATE — Can I fill this profitably?
   - What's the current DEX price for this pair?
   - What's the Dutch auction output RIGHT NOW?
   - Is the gap (market price - required output) > my costs?

3. ROUTE — Find the cheapest way to source the output tokens
   - AMM swap (Uniswap, Curve, Balancer)
   - CEX hedge (Binance, Coinbase)
   - Private inventory (already holding the tokens)
   - Flash loan + arbitrage combo

4. FILL — Submit the fill transaction to the settlement contract
   - Provide enough output to satisfy the decayed auction price
   - Beat other solvers to the fill (speed matters)
```

**Solver economics (worked example):**

```
User's order: selling 1 ETH, wants at least 1920 USDC (current auction output)
Market price: 1 ETH = 1935 USDC on Uniswap V3

Solver fills:
  Receives: 1 ETH from user (via settlement contract)
  Provides: 1920 USDC to user (minimum required)
  Then sells 1 ETH on Uniswap: gets 1935 USDC

  Revenue: 1935 USDC
  Cost:    1920 USDC (paid to user) + ~$3 gas
  Profit:  ~$12
```

**The competitive dynamic:** If solver A fills at the minimum (1920), solver B might fill earlier (at 1928) when the Dutch auction output is higher — less profit per fill but winning more fills. Competition pushes fill prices toward market price, benefiting users.

### The Solver Callback Pattern

From a Solidity perspective, the most important pattern is the callback:

```solidity
// Simplified ResolvedOrder — the Reactor resolves raw orders into this struct
// before passing them to the solver callback. The decay math has already been
// applied, so `input.amount` and `outputs[i].amount` reflect current prices.
//
// struct ResolvedOrder {
//     OrderInfo info;           // deadline, reactor address, swapper
//     InputToken input;         // { token, amount } — what the user is selling
//     OutputToken[] outputs;    // [{ token, amount, recipient }] — what user wants
//     bytes sig;                // EIP-712 signature
//     bytes32 hash;             // Order hash
// }

contract MySolver is IReactorCallback {
    ISwapRouter public immutable uniswapRouter;

    function reactorCallback(
        ResolvedOrder[] memory orders,
        bytes memory callbackData
    ) external override {
        // Called by the Reactor BEFORE output is checked.
        // We just received the user's input tokens.
        // Source liquidity and send output tokens to the recipient.

        for (uint i = 0; i < orders.length; i++) {
            // Option A: Swap on Uniswap using the input tokens we received
            uniswapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn: address(orders[i].input.token),
                tokenOut: address(orders[i].outputs[0].token),
                fee: 3000,
                recipient: orders[i].outputs[0].recipient,
                amountIn: orders[i].input.amount,
                amountOutMinimum: orders[i].outputs[0].amount,
                sqrtPriceLimitX96: 0
            }));

            // Option B: Transfer from inventory
            // outputToken.transfer(recipient, amount);

            // Option C: More complex routing, flash loans, etc.
        }
        // The Reactor checks output arrived after this returns
    }
}
```

**What makes a competitive solver:**
1. **Low-latency market data** — Know DEX prices across all pools in real-time
2. **Gas optimization** — Cheaper fill transactions = more competitive
3. **Multiple liquidity sources** — CEX + DEX + private inventory
4. **Cross-chain capability** — For cross-chain intents (UniswapX v2)
5. **Risk management** — Handle inventory risk, failed fills, gas spikes

---

<a id="cow-protocol"></a>
## CoW Protocol: Batch Auctions

### 💡 A Different Approach to Intents

While UniswapX uses Dutch auctions for individual orders, CoW Protocol collects orders into **batches** and finds optimal execution for the entire batch at once.

**The batch auction flow:**

```
                        Total batch window: ~60 seconds

Phase 1: ORDER COLLECTION (~30 seconds)
┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
│ Buy  │  │ Sell │  │ Sell │  │ Buy  │
│ ETH  │  │ ETH  │  │ DAI  │  │ USDC │
└──────┘  └──────┘  └──────┘  └──────┘

Phase 2: SOLVER COMPETITION (~30 seconds)
  Solver A: routes all through Uniswap
  Solver B: uses CoW matching + Curve for remainder
  Solver C: direct P2P for two orders + Balancer for rest

  → Winner: whichever solution gives users the most total surplus

Phase 3: ON-CHAIN SETTLEMENT
  GPv2Settlement.settle(trades, interactions)  // single transaction
```

**Coincidence of Wants (CoW) — the killer feature:**

When User A sells ETH for USDC and User B sells USDC for ETH, they can trade directly:

```
Without CoW (two separate AMM trades):
  A sells 1 ETH on Uniswap → gets 1935 USDC (pays LP fee + slippage)
  B sells 2000 USDC on Uniswap → gets 1.03 ETH (pays LP fee + slippage)
  Total cost: ~$10 in fees and slippage

With CoW (direct P2P matching):
  A gives 1 ETH to B
  B gives 1940 USDC to A
  Clearing price: 1940 USDC/ETH (between both users' limit prices)
  No LP fees, no slippage, no MEV
  Both get better prices than AMM
  Only the remainder (B needs more USDC) routes through an AMM
```

**MEV protection:** All orders in a batch execute at uniform clearing prices in a single transaction. There's nothing to sandwich — the batch is the atomic unit.

### GPv2Settlement Contract

```solidity
// Simplified from CoW Protocol
contract GPv2Settlement {
    /// @notice Execute a batch of trades
    /// @param trades Array of user trades with signed orders
    /// @param interactions External calls (DEX swaps, approvals, etc.)
    function settle(
        Trade[] calldata trades,
        Interaction[][3] calldata interactions  // [pre, intra, post]
    ) external onlySolver {
        // Phase 1: Pre-interactions (setup: approvals, flash loans, etc.)
        executeInteractions(interactions[0]);

        // Phase 2: Execute user trades
        for (uint i = 0; i < trades.length; i++) {
            // Verify order signature
            // Transfer sellToken from user to settlement
            // Record buyToken owed to user
        }

        // Phase 3: Intra-interactions (source liquidity: DEX swaps)
        executeInteractions(interactions[1]);

        // Phase 4: Post-interactions (cleanup: return flash loans, sweep dust)
        executeInteractions(interactions[2]);

        // Final check: every user received their minimum buyAmount
    }
}
```

The **three interaction phases** allow solvers maximum flexibility:
- **Pre:** Set up token approvals, initiate flash loans
- **Intra:** Execute DEX swaps for liquidity the batch needs beyond CoW matches
- **Post:** Clean up, return flash loans, sweep dust

### UniswapX vs CoW Protocol

| Aspect | UniswapX | CoW Protocol |
|---|---------|-------------|
| **Model** | Individual Dutch auctions | Batch auctions |
| **Price discovery** | Time decay per order | Solver competition on full batch |
| **CoW matching** | No (one order at a time) | Yes (batch-level P2P matching) |
| **Fill speed** | Seconds (continuous) | ~60s (batch window) |
| **MEV protection** | Dutch auction + exclusive filler | Batch settlement + uniform pricing |
| **Cross-chain** | Yes (v2) | Limited |
| **Best for** | Speed-sensitive, large individual orders | MEV-sensitive, many concurrent orders |

Both are valid approaches with different tradeoffs. Understanding both gives you the complete picture.

> 🔍 **Code:** [CoW Protocol GPv2Settlement](https://github.com/cowprotocol/contracts) — start with `GPv2Settlement.sol`

### 📖 How to Study: CoW Protocol

1. Start with `GPv2Settlement.sol` — the `settle()` function is the entry point
2. Read `GPv2Trade.sol` — how individual trades are encoded and decoded
3. Study the three interaction phases (pre, intra, post) — understand the solver's flexibility
4. Look at `GPv2Signing.sol` — how order signatures are verified (supports multiple schemes)
5. Skip the off-chain solver infrastructure initially — focus on the on-chain settlement guarantees

---

<a id="interview-prep"></a>
## 💼 Interview Prep

### 1. "How does a DEX aggregator find the optimal route?"

**Good answer:** "Aggregators query multiple pools off-chain, run an optimization algorithm to find the best split and routing path, then encode the solution as calldata for an on-chain executor contract. The executor pulls tokens from the user, swaps through each pool in sequence, and verifies the final output meets the user's minimum."

**Great answer:** "The routing problem is a constrained optimization — maximize output given pools with different liquidity profiles. For constant-product pools, the optimal split is approximately proportional to pool depth, because price impact is nonlinear — doubling the trade size more than doubles slippage. In practice, aggregators use heuristics because the general multi-hop, multi-split problem is NP-hard. The on-chain part is just a multi-call executor with a min-output check at the end — all the intelligence is off-chain. On L2s, routing gets more aggressive because the gas overhead of extra hops is near-zero, so more splits become profitable."

### 2. "Explain how UniswapX's Dutch auction works and why it's MEV-resistant."

**Good answer:** "Users sign an order with a start and end output amount. The required output decays from start to end over time. Solvers fill when it becomes profitable — earlier fills give users better prices."

**Great answer:** "The Dutch auction creates continuous solver competition compressed into time. The output starts above market price — unprofitable for solvers — and decays toward the user's limit price. A solver fills when the auction price crosses below `marketPrice - gasCost`, which is the profitability threshold. This is MEV-resistant because the price discovery IS the auction — there's no pending swap transaction to sandwich. The solver absorbs the MEV risk by choosing when to fill. The exclusive filler window adds another layer: a designated solver gets priority in exchange for committing to better starting prices. And the callback pattern lets solvers source liquidity just-in-time during the fill — they can flash-swap from AMMs, meaning they don't need pre-funded inventory."

### 3. "What's the difference between intent-based and transaction-based execution?"

**Good answer:** "In transaction-based, the user specifies exact routing. In intent-based, the user signs what they want and solvers compete to fill it."

**Great answer:** "The key insight is separation of concerns. Transaction-based systems couple the WHAT (swap ETH for USDC) with the HOW (via Uniswap V3, 0.3% pool). Intent-based systems decouple them — the user specifies only the WHAT, and a competitive market of solvers handles the HOW. This is strictly better because solvers have access to more liquidity sources than any individual user — CEX inventory, cross-chain bridges, private pools — and competition drives execution toward optimal. The tradeoff is trust assumptions: you need a settlement contract that cryptographically guarantees the user gets their minimum output, and you need a healthy solver ecosystem for competitive pricing. UniswapX handles trust via on-chain atomic settlement with EIP-712 signatures; CoW Protocol handles it via batch settlement with surplus optimization."

### 4. "How does CoW Protocol's batch auction prevent MEV?"

**Good answer:** "All orders in a batch execute at the same clearing price in a single transaction, so there's nothing to sandwich."

**Great answer:** "Three layers of MEV protection: (1) Orders are signed off-chain and submitted to a private API, never the public mempool — invisible to searchers. (2) Batch execution means all trades happen at uniform clearing prices in one transaction — you can't insert a sandwich between individual trades. (3) Coincidence of Wants matching means some trades never touch AMMs at all — no pool interaction means zero MEV surface. The residual MEV from AMM interactions needed for unmatched volume is captured by solver competition — solvers internalize the MEV and return surplus to users in order to win the batch."

### 5. "If you were building a solver, what would your architecture look like?"

**Good answer:** "Monitor order APIs for new orders, evaluate profitability, route through DEXes, submit fill transactions."

**Great answer:** "Three components: (1) An off-chain monitoring service that streams new orders from UniswapX/CoW APIs alongside real-time DEX prices. (2) A pricing engine that evaluates profitability at the current Dutch auction price — factoring in DEX quotes, gas costs, and expected competition. (3) An on-chain fill contract implementing `IReactorCallback` that sources liquidity just-in-time. I'd start with single-DEX routing using the callback pattern — you receive the user's input tokens, swap them on Uniswap, and the output goes directly to the user. Then add multi-DEX splits, then CEX hedging for large orders. The callback is key: you don't need inventory, you just need to source the output tokens between when you receive the input and when the Reactor checks the output."

**Interview red flags:**
- ❌ Thinking aggregators only do single-pool routing
- ❌ Not knowing what a Dutch auction is
- ❌ Conflating MEV protection with privacy (related but distinct concepts)
- ❌ Thinking intents are "gasless" (the solver pays gas, not the user — but gas still exists)
- ❌ Not knowing about Permit2 and its role in the intent flow

**Pro tip:** The intent space is moving fast. Knowing UniswapX's callback pattern and CoW's batch settlement model signals you're current. Mentioning Permit2 integration, exclusive filler windows, and cross-chain intents shows real depth.

---

<a id="exercises"></a>
## 🎯 Module 4 Exercises

**Workspace:** `workspace/src/part3/module4/`

### Exercise 1: SplitRouter

Build a simple DEX router that splits trades across two constant-product pools.

**What you'll implement:**
- `getAmountOut()` — constant-product AMM output calculation (refresher from Part 2)
- `getOptimalSplit()` — find the best split ratio across two pools
- `splitSwap()` — execute a split trade, pulling tokens and swapping through both pools
- `singleSwap()` — execute a single-pool trade (for comparison)

**Concepts exercised:**
- AMM output formula applied to routing
- Split order optimization math
- Multi-call execution pattern (the core of every aggregator)
- Gas-aware decision making (when splitting beats single-pool)

**🎯 Goal:** Prove that splitting a large trade across two unequal pools gives more output than routing through either pool alone.

Run: `forge test --match-contract SplitRouterTest -vvv`

### Exercise 2: IntentSettlement

Build a simplified intent settlement system with EIP-712 orders and Dutch auction price decay.

**What you'll implement:**
- `hashOrder()` — EIP-712 struct hashing for the order type
- `getDigest()` — full EIP-712 digest with domain separator
- `resolveDecay()` — Dutch auction price calculation at current timestamp
- `fill()` — complete settlement: verify signature, check deadline, resolve decay, execute atomic swap

**Concepts exercised:**
- EIP-712 typed data hashing and domain separators
- Signature verification with ECDSA recovery
- Dutch auction formula (linear decay)
- Settlement contract security: replay protection, deadline enforcement, minimum output

**🎯 Goal:** Build the core of a UniswapX-style settlement contract. Sign orders off-chain in tests using `vm.sign`, fill them on-chain with Dutch auction price decay.

Run: `forge test --match-contract IntentSettlementTest -vvv`

---

## 📋 Summary

**✓ Covered:**
- The routing problem and split order optimization math
- The multi-call executor pattern shared by all aggregators
- The intent paradigm shift: from transactions to signed intents
- EIP-712 order structures and signature verification
- Dutch auction price decay: formula, mechanics, and why it works
- Settlement contract architecture (UniswapX Reactor pattern)
- What solvers do and how to think about building one
- CoW Protocol's batch auction model and Coincidence of Wants
- UniswapX vs CoW Protocol tradeoffs

**Next:** [Module 5 — MEV Deep Dive →](5-mev.md) — where we explore the searcher side. Intents protect users from MEV; Module 5 explains what they're being protected from and how the MEV supply chain works.

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [UniswapX](https://github.com/Uniswap/UniswapX) — ExclusiveDutchOrderReactor, DutchDecayLib, IReactorCallback
- [CoW Protocol (GPv2)](https://github.com/cowprotocol/contracts) — GPv2Settlement
- [1inch Limit Order Protocol](https://github.com/1inch/limit-order-protocol) — V6 aggregation router source is not public; this is the best open-source reference

### Documentation
- [UniswapX docs](https://docs.uniswap.org/contracts/uniswapx/overview)
- [CoW Protocol docs](https://docs.cow.fi/)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)

### Key Reading
- [Paradigm: An Analysis of Intent-Based Markets](https://www.paradigm.xyz/2023/06/intents)
- [Frontier Research: Order Flow Auctions and Centralisation](https://frontier.tech/the-orderflow-auction-design-space)
- [Flashbots: MEV, Intents, and the Suave Future](https://writings.flashbots.net/)

---

**Navigation:** [← Module 3: Yield Tokenization](3-yield-tokenization.md) | [Part 3 Overview](README.md) | [Next: Module 5 — MEV Deep Dive →](5-mev.md)

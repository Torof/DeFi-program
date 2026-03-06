# Part 3 — Module 5: MEV Deep Dive

> **Difficulty:** Advanced
>
> **Estimated reading time:** ~30 minutes | **Exercises:** ~2 hours

## 📚 Table of Contents

**Understanding MEV**
- [The Invisible Tax](#invisible-tax)
- [Sandwich Attacks: Anatomy & Math](#sandwich-attacks)
- [Build Exercise: Sandwich Attack Simulation](#exercise1-sandwich-simulation)
- [Arbitrage & Liquidation MEV](#good-mev)
- [The Post-Merge MEV Supply Chain](#supply-chain)

**Defense & Protocol Design**
- [MEV Protection Mechanisms](#protection)
- [MEV-Aware Protocol Design](#mev-aware-design)
- [Build Exercise: MEV-Aware Dynamic Fee Hook](#exercise2-mev-fee-hook)

---

<a id="invisible-tax"></a>
## 💡 The Invisible Tax

Maximal Extractable Value (MEV) is the invisible tax on every DeFi transaction. If you swap on a DEX, someone might sandwich you. If you submit a liquidation, someone might front-run it. If you create a new pool, someone will arbitrage it within the same block.

Understanding MEV is essential for both sides: as a **protocol designer** (minimizing user harm) and as a **DeFi developer** (writing MEV-aware code). The AMMs module (Part 2 Module 2) introduced sandwich attacks — this module covers the full picture: attack taxonomy, the post-Merge supply chain, protection mechanisms, and how to design protocols that resist extraction.

**Why this matters for you:**
- Every DeFi protocol you build will face MEV — designing around it is non-negotiable
- MEV knowledge is a top interview differentiator — teams want engineers who think about ordering attacks
- The solver/searcher space is one of the hottest hiring areas in DeFi right now
- Module 4's intent paradigm was designed specifically to combat MEV — this module explains what it's combating

### 💡 Concept: What is MEV?

Originally "Miner Extractable Value" (pre-Merge), now **Maximal Extractable Value** — the total value that can be extracted by anyone who controls transaction ordering within a block.

**The core insight:** Transaction ordering affects outcomes. If you can see a pending transaction and place yours before or after it, you can capture value. MEV exists because Ethereum's mempool is public — anyone can see pending transactions and reorder them for profit.

**Scale:** Billions of dollars extracted since DeFi Summer (2020). [Flashbots MEV-Explore](https://explore.flashbots.net/) tracks historical extraction.

### The MEV Spectrum

Not all MEV is harmful. Understanding the spectrum is critical for protocol design:

```
BENIGN ──────────────────────────────────────────── HARMFUL
  │                    │                    │            │
  Arbitrage        Liquidation         Backrunning   Sandwich
  │                    │                    │            │
  Keeps prices     Keeps protocols      Captures       Directly
  aligned across   solvent — socially   leftover       harms users
  DEXes            useful               value          (the "tax")
```

| Type | Mechanism | Impact | Who Profits |
|------|-----------|--------|-------------|
| **Arbitrage** | Buy low on DEX A, sell high on DEX B | Aligns prices across markets — benign | Searcher |
| **Liquidation** | Race to liquidate undercollateralized positions | Keeps lending protocols solvent — useful | Searcher (bonus) |
| **Backrunning** | Place tx after a large trade to capture leftover value | Mild — doesn't affect the target tx | Searcher |
| **JIT Liquidity** | Flash-add/remove concentrated liquidity around a swap | Takes LP fees from passive LPs | JIT LP |
| **Frontrunning** | Copy a profitable tx and submit with higher priority | Steals opportunities — harmful | Searcher |
| **Sandwich** | Frontrun + backrun a user's swap | Directly extracts from user — most harmful | Searcher |
| **Cross-domain** | Arbitrage between L1 ↔ L2 or L2 ↔ L2 | Growing with L2 adoption | Sequencer/Searcher |

---

<a id="sandwich-attacks"></a>
## 💡 Sandwich Attacks: Anatomy & Math

### 💡 Concept: How a Sandwich Attack Works

This is the most important MEV attack to understand — it directly costs users money on every unprotected swap.

**Setup:** User submits a swap to the public mempool. Attacker sees it, calculates profit, and submits a front-run + back-run that wraps the user's transaction:

```
Block N:
┌────────────────────────────────────────────────────┐
│  tx 1: Attacker buys ETH         (front-run)       │
│  tx 2: User buys ETH             (victim swap)     │
│  tx 3: Attacker sells ETH        (back-run)        │
└────────────────────────────────────────────────────┘
         ↑ Attacker controls ordering via higher gas / builder tip
```

#### 🔍 Deep Dive: Sandwich Profit Calculation

**Pool:** 100 ETH / 200,000 USDC (spot price: $2,000/ETH)
**User:** Buying ETH with 20,000 USDC (expects ~10 ETH)
**Attacker:** Front-runs with 10,000 USDC

**Without sandwich — user swaps alone:**

```
User output = 100 × 20,000 / (200,000 + 20,000)
            = 2,000,000 / 220,000
            = 9.091 ETH

Effective price: $2,200/ETH  (9.1% slippage on a large trade)
```

**With sandwich — three transactions in sequence:**

```
Step 1: FRONT-RUN — Attacker buys ETH with 10,000 USDC
────────────────────────────────────────────────────
  attacker_eth = 100 × 10,000 / (200,000 + 10,000)
               = 1,000,000 / 210,000
               = 4.762 ETH

  Pool after:  (95.238 ETH, 210,000 USDC)
               ↑ Less ETH available, price pushed UP

Step 2: USER SWAP — User buys ETH with 20,000 USDC
────────────────────────────────────────────────────
  user_eth = 95.238 × 20,000 / (210,000 + 20,000)
           = 1,904,760 / 230,000
           = 8.282 ETH         ← 0.809 ETH LESS than without sandwich

  Pool after:  (86.956 ETH, 230,000 USDC)

Step 3: BACK-RUN — Attacker sells 4.762 ETH for USDC
────────────────────────────────────────────────────
  attacker_usdc = 230,000 × 4.762 / (86.956 + 4.762)
                = 1,095,260 / 91.718
                = 11,940 USDC

  Attacker profit: 11,940 - 10,000 = 1,940 USDC
```

**Summary:**

```
┌──────────────────────────────────────────────────┐
│  User loss:       9.091 - 8.282 = 0.809 ETH     │
│                   ≈ $1,618 at $2,000/ETH         │
│                                                   │
│  Attacker profit: 11,940 - 10,000 = $1,940       │
│  Attacker gas:    ~$3-10                          │
│  Attacker net:    ~$1,930                         │
│                                                   │
│  The user paid an invisible $1,618 "sandwich tax" │
└──────────────────────────────────────────────────┘
```

**Key insight:** Attacker profit ($1,940) exceeds user loss ($1,618). This isn't a contradiction — the pool's nonlinear pricing creates value redistribution. The pool ends with different reserves in each scenario; LPs implicitly absorb part of the cost.

**What determines sandwich profitability?**

```
Profitable when: attacker_profit > gas_cost

Profit scales with:
  ✓ User's trade size (larger trade = more price impact to exploit)
  ✓ Pool's illiquidity (shallower pool = more price impact per unit)
  ✓ User's slippage tolerance (wider tolerance = more room to extract)

Profit is limited by:
  ✗ Gas costs (two extra transactions)
  ✗ User's slippage limit (if sandwich pushes beyond limit, user tx reverts)
  ✗ Competition (other sandwich bots bid up gas, compressing profit)
```

### Slippage as Defense

```
User's slippage = 0.5%:
  User expects ≥ 9.091 × 0.995 = 9.046 ETH
  Sandwich gives user 8.282 ETH → REVERTS (below minimum)
  Sandwich attack fails ✓

User's slippage = 10%:
  User expects ≥ 9.091 × 0.90 = 8.182 ETH
  Sandwich gives user 8.282 ETH → passes (above minimum)
  Sandwich attack succeeds ✗
```

Tight slippage makes sandwiches unprofitable. But too tight → your transaction reverts on normal volatility. This tension drives the move to intent-based execution (Module 4).

💻 **Quick Try:**

Deploy in [Remix](https://remix.ethereum.org/) to see the sandwich tax:

```solidity
contract SandwichDemo {
    uint256 public x = 100e18;     // 100 ETH
    uint256 public y = 200_000e18; // 200,000 USDC

    function cleanSwap(uint256 usdcIn) external view returns (uint256 ethOut) {
        return x * usdcIn / (y + usdcIn);
    }

    function sandwichedSwap(uint256 usdcIn, uint256 frontrunUsdc)
        external view returns (uint256 userEth, uint256 attackerProfit)
    {
        // Step 1: front-run
        uint256 atkEth = x * frontrunUsdc / (y + frontrunUsdc);
        uint256 x1 = x - atkEth;
        uint256 y1 = y + frontrunUsdc;
        // Step 2: user swap
        userEth = x1 * usdcIn / (y1 + usdcIn);
        uint256 x2 = x1 - userEth;
        uint256 y2 = y1 + usdcIn;
        // Step 3: back-run
        uint256 atkUsdc = y2 * atkEth / (x2 + atkEth);
        attackerProfit = atkUsdc > frontrunUsdc ? atkUsdc - frontrunUsdc : 0;
    }
}
```

Try: `cleanSwap(20000e18)` → 9.091 ETH. Then `sandwichedSwap(20000e18, 10000e18)` → 8.282 ETH + $1,940 profit. Now try a tiny trade: `sandwichedSwap(100e18, 10000e18)` — profit drops to nearly zero. Sandwiches only work on trades large enough to create exploitable price impact.

#### 🔗 DeFi Pattern Connection

**Where sandwich risk matters in DeFi:**

1. **AMM swaps** — the primary attack surface (Part 2 Module 2)
2. **Liquidation collateral sales** — liquidators' swap of seized collateral can be sandwiched
3. **Vault rebalances** — automated vault strategies that swap on-chain are sandwich targets
4. **Oracle updates** — TWAP oracles can be manipulated through related ordering attacks
5. **Module 4's intent paradigm** — designed specifically to eliminate the sandwich surface by moving execution off-chain

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Explain how a sandwich attack works and how to prevent it."**
   - Good answer: "An attacker front-runs and back-runs a user's swap. The front-run pushes the price up, the user swaps at a worse rate, and the attacker sells for profit. Prevention: tight slippage limits or private mempools."
   - Great answer: "A sandwich exploits the public mempool and AMM nonlinear price impact. The attacker calculates the optimal front-run amount — enough to shift the price but within the user's slippage tolerance — then submits front-run, victim, back-run as an atomic bundle to a builder. Prevention exists at multiple levels: user-level tight slippage, private RPCs like Flashbots Protect, application-level intent systems like UniswapX where there's no on-chain tx to sandwich, and protocol-level V4 hooks that surcharge same-block opposite-direction swaps."

**Interview Red Flags:**
- 🚩 Thinking MEV only means sandwich attacks — it's a broad spectrum including arb, liquidation, backrunning, and JIT liquidity
- 🚩 Not knowing that slippage tolerance is the primary defense variable — and that too-tight slippage causes reverts on normal volatility
- 🚩 Describing sandwich prevention without mentioning the intent paradigm (UniswapX, CoW Protocol) — that's the direction the industry is moving

**Pro tip:** When discussing sandwiches, show you understand the economics: attacker profit scales with user trade size and pool illiquidity, and is bounded by the user's slippage tolerance. Explaining *why* a sandwich is profitable (not just *how* it works) immediately signals deeper understanding.

---

<a id="exercise1-sandwich-simulation"></a>
## 🎯 Build Exercise: Sandwich Attack Simulation

**Workspace:** `workspace/src/part3/module5/`

Build a test-only exercise that simulates a sandwich attack on a simple constant-product pool, measures the extraction, and verifies that slippage protection defeats it.

**What you'll implement:**
- `SimplePool` — a minimal constant-product AMM with `swap()`
- `SandwichBot` — a contract that executes front-run → victim swap → back-run atomically
- Test scenarios measuring user loss and attacker profit
- Slippage defense: verify that tight slippage makes sandwich revert

**Concepts exercised:**
- Sandwich attack mechanics (the three-step pattern)
- AMM price impact math applied to adversarial scenarios
- Slippage as a defense mechanism
- Thinking adversarially about transaction ordering

**🎯 Goal:** Prove quantitatively that sandwiches work on large trades with loose slippage, and fail against tight slippage limits.

Run: `forge test --match-contract SandwichSimTest -vvv`

---

## 📋 Key Takeaways: MEV Attacks

After this section, you should be able to:

- Explain MEV as an invisible tax on DeFi transactions and classify the spectrum from benign (arbitrage, liquidation) to harmful (sandwich attacks)
- Trace a sandwich attack step by step: front-run to push price up → victim swaps at worse rate → back-run to capture the difference, and calculate the attacker's profit from price impact math
- Explain why AMMs are inherently vulnerable to ordering-based extraction (deterministic price impact + public mempool) and how slippage tolerance is the primary user defense

---

<a id="good-mev"></a>
## 💡 Arbitrage & Liquidation MEV

### 💡 Concept: The "Good" MEV

Not all MEV harms users. Arbitrage and liquidation MEV serve essential functions in DeFi.

**Arbitrage — keeping prices aligned:**

```solidity
// Simplified arbitrage logic (searcher contract)
contract SimpleArbitrage {
    function execute(
        IPool poolA,      // ETH is cheap here
        IPool poolB,      // ETH is expensive here
        IERC20 usdc,
        IERC20 weth,
        uint256 amountIn
    ) external {
        // Buy ETH cheap on pool A
        usdc.approve(address(poolA), amountIn);
        uint256 ethReceived = poolA.swap(address(usdc), address(weth), amountIn);

        // Sell ETH expensive on pool B
        weth.approve(address(poolB), ethReceived);
        uint256 usdcReceived = poolB.swap(address(weth), address(usdc), ethReceived);

        // Profit = output - input (minus gas + builder tip)
        require(usdcReceived > amountIn, "Not profitable");
    }
}
```

**With flash loans — capital-free arbitrage:**

```solidity
// The most common searcher pattern: flash-funded arb
// (Simplified interfaces — real DEX routers have different function signatures)
function onFlashLoan(
    address, address token, uint256 amount, uint256 fee, bytes calldata data
) external returns (bytes32) {
    // Received `amount` tokens (no upfront capital needed)
    (address poolA, address poolB, address tokenB) = abi.decode(data, (address, address, address));

    // Route through profitable path
    IERC20(token).approve(poolA, amount);
    uint256 intermediate = IPool(poolA).swap(token, tokenB, amount);

    IERC20(tokenB).approve(poolB, intermediate);
    uint256 output = IPool(poolB).swap(tokenB, token, intermediate);

    // output > amount + fee → profitable
    IERC20(token).approve(msg.sender, amount + fee);
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
    // Profit: output - amount - fee (kept in this contract)
}
```

**Why arbitrage is socially useful:** Without arb bots, the same token would trade at wildly different prices across DEXes. Arbitrage keeps prices consistent — a public good that happens to be profitable.

**Liquidation MEV — keeping protocols solvent:**

Lending protocols (Aave, Compound — Part 2 Module 4) rely on liquidation bots racing to close undercollateralized positions. The liquidation bonus (5-10%) is the MEV incentive. Without it, bad debt accumulates and protocols become insolvent.

```
User's position goes underwater:
  Collateral: 1 ETH ($2,000) | Debt: $1,800 USDC | Health Factor < 1

  Bot A sees liquidation opportunity → submits tx with 30 gwei priority
  Bot B sees same opportunity       → submits tx with 35 gwei priority
  Bot C sees same opportunity       → submits tx with 40 gwei priority
                                                  ↑ Wins — gas priority auction

  Winner: repays $900 debt, receives $945 of ETH (5% bonus)
  Profit: $45 - gas cost
```

The gas auction is "wasteful" (bots overpay for gas), but the underlying liquidation is essential. This is why some protocols use Dutch auctions for liquidations (Part 2 Module 9 capstone) — they replace gas priority auctions with time-based price discovery.

---

<a id="supply-chain"></a>
## 💡 The Post-Merge MEV Supply Chain

### 💡 Concept: Proposer-Builder Separation (PBS)

Before the Merge, miners both built and proposed blocks — they could extract MEV directly. Post-Merge, **Proposer-Builder Separation** splits these roles:

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│  Users    │     │  Searchers   │     │  Builders    │
│           │     │              │     │              │
│ Submit    │────→│ Find MEV     │────→│ Construct    │
│ to public │     │ opportunities│     │ full blocks  │
│ mempool   │     │              │     │ from txs +   │
│           │     │ Submit       │     │ bundles      │
│   OR      │     │ "bundles"    │     │              │
│           │     └──────────────┘     │ Bid to       │
│ Submit to │                          │ proposer     │
│ private   │                          └──────┬───────┘
│ mempool   │                                 │
│ (protect) │                          ┌──────▼───────┐
└──────────┘                          │  Relays      │
                                       │              │
                                       │ Blind escrow │
                                       │ (proposer    │
                                       │ can't peek)  │
                                       └──────┬───────┘
                                              │
                                       ┌──────▼───────┐
                                       │  Proposers   │
                                       │ (Validators) │
                                       │              │
                                       │ Pick highest │
                                       │ bid block    │
                                       └──────────────┘
```

**Each role in detail:**

**Searchers** — the MEV hunters:
- Bots that scan the mempool for profitable opportunities (arb, liquidation, sandwich)
- Write smart contracts that atomically capture value
- Submit **bundles** to builders — ordered transaction sets that execute atomically
- Revenue: MEV profit minus gas cost minus builder tip

**Builders** — the block architects:
- Receive user transactions from the mempool + searcher bundles
- Construct the most valuable block possible (optimize transaction ordering)
- Bid to proposer: "My block earns you X ETH"
- Top builders (2025): Titan, BeaverBuild, Flashbots (builder), rsync
- **Centralization concern:** top 3 builders construct the majority of blocks

**Relays** — the trusted middlemen:
- Sit between builders and proposers
- **Critical property:** proposer can't see block contents until they commit to it
- Prevents proposers from stealing MEV by peeking at the block and rebuilding it themselves
- Major relays: Flashbots, bloXroute, Ultra Sound, Aestus

**Proposers (Validators)** — the block selectors:
- Run MEV-Boost to connect to the relay network
- Simply pick the block with the highest bid — no MEV knowledge needed
- Revenue: execution layer base fee + builder's bid

### Economics of the Supply Chain

```
Example: $10,000 MEV opportunity in a block

  Searcher extracts:    $10,000 gross
  → Tips builder:       -$7,000 (70% — bidding war among searchers)
  → Gas costs:          -$500
  Searcher profit:      $2,500

  Builder receives:     $7,000 from searchers (+ regular user tx fees)
  → Bids to proposer:  -$6,000 (bidding war among builders)
  Builder profit:       $1,000

  Proposer receives:    $6,000 block bid
  (No work beyond running MEV-Boost)
```

**The key insight:** Competition at each level drives most MEV to the proposer (validator). Searcher margins are thin; builder margins are thinner. Most value flows "up" the supply chain through competitive bidding.

### Centralization Concerns

This is the most debated topic in Ethereum governance:

| Concern | Why It Matters | Proposed Solutions |
|---------|---------------|-------------------|
| Builder centralization | Few builders = potential censorship | Inclusion lists, decentralized builders |
| Relay trust | Relays can censor or front-run | Relay diversity, enshrined PBS (ePBS) |
| OFAC compliance | Builders/relays may exclude sanctioned txs | Inclusion lists (force-include txs) |
| Latency advantage | Builders closer to validators win more | Timing games research, committee-based PBS |

**Inclusion lists** (actively being designed): Proposers specify transactions that MUST be included in the next block, regardless of builder preferences. This prevents censorship while preserving the efficiency of builder markets.

#### 📖 How to Study: Flashbots Architecture

1. Start with [MEV-Boost docs](https://docs.flashbots.net/flashbots-mev-boost/introduction) — how validators connect to the relay network
2. Read the [Builder API spec](https://ethereum.github.io/builder-specs/) — how builders submit blocks
3. Study [Flashbots Protect](https://docs.flashbots.net/flashbots-protect/overview) — the user-facing privacy layer
4. Look at [MEV-Share](https://docs.flashbots.net/flashbots-mev-share/overview) — how users capture MEV rebates
5. Skip relay internals initially — focus on the flow: user → searcher → builder → relay → proposer

> 🔍 **Code:** [MEV-Boost](https://github.com/flashbots/mev-boost) | [Flashbots Builder](https://github.com/flashbots/builder)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What is Proposer-Builder Separation and why does it matter?"**
   - Good answer: "PBS separates block construction from block proposal. Builders create blocks, proposers select the highest bid. This prevents validators from directly extracting MEV."
   - Great answer: "PBS is Ethereum's architectural response to MEV centralization. Post-Merge, specialized builders construct optimized blocks from user transactions plus searcher bundles, and proposers simply select the highest bid via MEV-Boost. Relays sit in between as blind escrows so proposers can't steal MEV. Competition at each layer drives most value up to the proposer. The current tension is builder centralization — top 3 builders produce the majority of blocks, creating censorship risk. The community is addressing this through inclusion lists and longer-term enshrined PBS (ePBS)."

**Interview Red Flags:**
- 🚩 Not knowing about PBS or the post-Merge supply chain — this is foundational Ethereum infrastructure knowledge
- 🚩 Confusing MEV privacy (hiding txs) with MEV elimination — arb and liquidation MEV is permanent and socially useful
- 🚩 Not mentioning builder centralization or censorship risk as the current open problem in PBS

**Pro tip:** Mention the economic flow: searchers tip builders, builders bid to proposers, competition drives most value to validators. Showing you understand the incentive structure — not just the architecture diagram — signals that you think about mechanism design, not just code.

---

<a id="protection"></a>
## 💡 MEV Protection Mechanisms

### 💡 Concept: Defending Against the Invisible Tax

Protection operates at four levels: transaction privacy, order flow auctions, application design, and cryptographic schemes.

### Level 1: Transaction Privacy

**Flashbots Protect** — private transaction submission:

```
Standard flow (vulnerable):
  User → Public Mempool → Sandwich bots see it → Sandwiched

Flashbots Protect flow:
  User → Flashbots RPC → Directly to builder → No public visibility
  (Add https://rpc.flashbots.net to your wallet)
```

**Trade-off:** You trust Flashbots not to exploit your transaction. The transaction may take slightly longer to be included (fewer builders see it). Other private RPCs exist with different trust assumptions (bloXroute, MEV Blocker).

**MEV Blocker (CoW Protocol):**
- Similar private submission
- Additionally: searchers bid for the right to backrun your transaction
- You receive a rebate from the backrun profit
- Your tx is sandwich-protected AND you earn from the MEV it creates

### Level 2: Order Flow Auctions (OFA)

**MEV-Share (Flashbots)** — turning MEV from a tax into a rebate:

```
Without MEV-Share:
  User swap → Public mempool → Searcher sandwiches → User loses $50

With MEV-Share:
  User swap → MEV-Share (private) → Searcher sees partial tx info
  → Searcher bids $30 for backrun rights → Bundle: user tx + backrun
  → User receives rebate: $20 (configurable %)
  → User's net MEV cost: -$20 (they EARNED from their own MEV)
```

**How partial information sharing works:**
1. User sends tx to MEV-Share
2. MEV-Share reveals *hints* to searchers (e.g., "a swap on Uniswap V3 ETH/USDC pool" — not the exact amount or direction)
3. Searchers simulate potential backruns based on hints
4. Searchers bid for the right to backrun
5. Winning bundle: user tx → searcher backrun
6. User receives configured percentage of searcher's profit

### Level 3: Application-Level Protection

**Intent-based systems (Module 4 connection):**

This is the deepest connection in Part 3. Module 4's entire intent paradigm exists because of MEV:

```
Why intents protect against MEV:
─────────────────────────────────
Traditional swap:
  User publishes: "swap(1 ETH, USDC, Uniswap, 0.3% pool)"
  → Attacker sees EXACTLY what to sandwich

Intent-based:
  User signs: "I want ≥1900 USDC for 1 ETH"
  → No on-chain tx in mempool → nothing to sandwich
  → Solver fills from private inventory or routes through private channels
  → Settlement is atomic — by the time it's on-chain, it's already done
```

**Batch auctions (CoW Protocol model):**
- Collect orders over a time window
- Execute all at uniform clearing prices in a single transaction
- No individual transaction to sandwich — the batch IS the atomic unit
- Coincidence of Wants (CoW) matching means some trades never touch AMMs at all

### Level 4: Cryptographic Protection

**Commit-reveal schemes:**

```solidity
// Phase 1: User commits hash of their action (hidden)
mapping(address => bytes32) public commits;
mapping(address => uint256) public commitBlock;

function commit(bytes32 hash) external {
    commits[msg.sender] = hash;
    commitBlock[msg.sender] = block.number;
}

// Phase 2: User reveals after N blocks (can't be front-run)
function reveal(uint256 amount, bytes32 salt) external {
    require(block.number > commitBlock[msg.sender] + DELAY, "Too early");
    require(
        keccak256(abi.encodePacked(amount, salt)) == commits[msg.sender],
        "Invalid reveal"
    );
    delete commits[msg.sender];

    // Execute the action — safe from frontrunning
    _execute(msg.sender, amount);
}
```

**Use cases:** Governance votes, NFT mints, sealed-bid auctions — any action where seeing the intent enables extraction. **Trade-off:** Two transactions, delay between commit and reveal.

**Threshold encryption (Shutter Network):**
- Transactions encrypted before submission
- Decryption key revealed only after block ordering is committed
- Prevents ALL forms of frontrunning (can't frontrun what you can't read)
- Trade-off: requires a decryption committee (trust assumption), added latency

#### 🔗 DeFi Pattern Connection

**MEV protection across the curriculum:**

| Protection | Where It Appears | Module |
|---|---|---|
| Slippage limits | AMM swaps, vault withdrawals | Part 2 Modules 2, 7 |
| Intent-based execution | UniswapX, CoW Protocol | Part 3 Module 4 |
| Dutch auction liquidation | MakerDAO Dog, Part 2 capstone | Part 2 Modules 6, 9 |
| Oracle-based execution | GMX perpetuals | Part 3 Module 2 |
| Batch settlement | CoW Protocol | Part 3 Module 4 |
| Time-weighted prices | TWAP oracles | Part 2 Module 3 |
| Keeper delay | GMX two-step execution | Part 3 Module 2 |

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What's the difference between MEV-Share and Flashbots Protect?"**
   - Good answer: "Flashbots Protect hides your transaction from sandwich bots. MEV-Share goes further by letting searchers bid for backrun rights and giving users a rebate."
   - Great answer: "They're different layers of the same stack. Protect is simple privacy — your tx goes to a private mempool, preventing sandwiches. MEV-Share adds an economic layer: your tx is still private from sandwich bots, but hints are revealed to searchers — enough to evaluate backrun opportunities, not enough to sandwich. Searchers competitively bid for backrun rights, and the user receives a configurable rebate. Protect eliminates the tax; MEV-Share eliminates the tax AND turns leftover MEV into user revenue."

2. **"How does cross-domain MEV work with L2s?"**
   - Good answer: "Price differences between L1 and L2 create arbitrage. L2 sequencers control ordering, creating L2-specific MEV."
   - Great answer: "Prices on L2s lag mainnet by the sequencer's batch submission delay, creating predictable arb windows. The centralized L2 sequencer is the de facto block builder and can extract MEV directly. This drives shared sequencing proposals that coordinate ordering across L2s, reducing cross-domain MEV. As L2 volume grows, cross-domain MEV is becoming dominant — which is why protocols like UniswapX V2 are building cross-chain intent settlement."

**Interview Red Flags:**
- 🚩 Saying "just use a private mempool" without understanding the trust tradeoffs — you're trusting Flashbots/bloXroute not to exploit your tx
- 🚩 Not knowing the difference between privacy (hiding txs) and redistribution (MEV-Share rebates) — they solve different problems
- 🚩 Ignoring cross-domain MEV when discussing L2s — it's becoming the dominant extraction vector as volume moves off mainnet

**Pro tip:** When discussing MEV protection, frame it as a spectrum: privacy (Protect) prevents harm, order flow auctions (MEV-Share) turn harm into revenue, and intent systems (UniswapX) eliminate the attack surface entirely. Showing you understand the progression signals architectural thinking about MEV defense.

---

<a id="mev-aware-design"></a>
## 💡 MEV-Aware Protocol Design

### 💡 Concept: Building Protocols That Resist Extraction

Four design principles that every DeFi protocol should follow:

### Principle 1: Minimize Information Leakage

Less visible = less extractable. If attackers can't see what's coming, they can't front-run it.

- **Private execution paths** — route through private mempools or intent systems
- **Encrypted transactions** — commit-reveal or threshold encryption
- **Delayed revelation** — oracle-based execution (GMX: submit order → keeper fills at oracle price later)

### Principle 2: Reduce Ordering Dependence

If transaction order doesn't matter, MEV disappears.

- **Batch operations** — CoW Protocol's batch auctions execute at uniform prices regardless of order
- **Frequent batch auctions** — academic proposal: discrete time intervals instead of continuous matching
- **Time-weighted execution** — TWAP orders spread impact across blocks, reducing per-block extraction

### Principle 3: Internalize MEV

Instead of MEV leaking to external searchers → capture and redistribute it.

**Uniswap V4 hooks — dynamic MEV fees:**

```solidity
/// @notice A V4-style hook that charges higher fees on suspected MEV swaps
contract MEVFeeHook {
    struct BlockSwapInfo {
        bool hasSwapZeroForOne;   // swapped token0 → token1
        bool hasSwapOneForZero;   // swapped token1 → token0
    }

    // Track swap directions per pool per block
    mapping(bytes32 => mapping(uint256 => BlockSwapInfo)) public blockSwaps;

    /// @notice Called before each swap — returns dynamic fee
    function getDynamicFee(
        bytes32 poolId,
        bool zeroForOne
    ) external returns (uint24 fee) {
        BlockSwapInfo storage info = blockSwaps[poolId][block.number];

        // If opposite-direction swap already happened → likely sandwich
        bool isSuspicious = zeroForOne
            ? info.hasSwapOneForZero
            : info.hasSwapZeroForOne;

        // Record this swap's direction
        if (zeroForOne) info.hasSwapZeroForOne = true;
        else info.hasSwapOneForZero = true;

        // Normal swap: 0.3%  |  Suspicious: 1.0%
        return isSuspicious ? 10000 : 3000;
    }
}
```

**The intuition:** If the same pool sees a buy AND a sell in the same block, that's the signature of a sandwich. Charging the second swap a higher fee makes the sandwich unprofitable while leaving normal trades unaffected.

**Osmosis ProtoRev — protocol-owned backrunning:**

```
Standard model:
  External searcher captures arb → profit leaves the protocol

ProtoRev model:
  Protocol detects arb opportunities after each swap
  Protocol captures the backrun profit itself
  Revenue → community pool (protocol treasury)
  Result: MEV stays in the ecosystem instead of leaking
```

### Principle 4: MEV Taxes (Paradigm Research)

A powerful theoretical framework: make fees proportional to the priority fee the transaction pays.

```
Normal user swap:
  Priority fee: 1 gwei → Swap fee: 0.01% → Cheap execution

MEV bot sandwich:
  Priority fee: 50 gwei → Swap fee: 0.5% → Expensive execution
  (Most MEV captured by LPs via the higher fee)
```

**Why it works:** MEV extraction requires transaction ordering priority. Priority requires higher gas bids. If swap fees scale with gas bids, MEV extractors pay proportionally more — and that value goes to LPs instead of searchers. Ordinary users with low-priority transactions pay minimal fees.

> 🔍 **Read:** [Paradigm — Priority Is All You Need](https://www.paradigm.xyz/2024/02/priority-is-all-you-need) — the full MEV tax framework

💻 **Quick Try:**

Deploy in [Remix](https://remix.ethereum.org/) to experiment with commit-reveal protection:

```solidity
contract CommitRevealDemo {
    mapping(address => bytes32) public commits;

    function getHash(uint256 bid, bytes32 salt) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(bid, salt));
    }

    function commit(bytes32 hash) external {
        commits[msg.sender] = hash;
    }

    function reveal(uint256 bid, bytes32 salt)
        external view returns (bool valid)
    {
        return keccak256(abi.encodePacked(bid, salt)) == commits[msg.sender];
    }
}
```

Try: call `getHash(1000, 0xdead000000000000000000000000000000000000000000000000000000000000)` → copy the returned hash → `commit(hash)` → `reveal(1000, 0xdead...)` → returns `true`. The bid was hidden until reveal. This is how governance votes and sealed-bid auctions prevent frontrunning.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you design a protocol to minimize MEV extraction?"**
   - Good answer: "Use batch auctions, private execution, and tight slippage controls to reduce the MEV surface."
   - Great answer: "Four principles: (1) Minimize information leakage — route through intents or private channels. (2) Reduce ordering dependence — batch operations so tx order doesn't affect outcomes. (3) Internalize MEV — use V4 hooks or MEV taxes to capture extraction value for LPs. (4) Time-weight operations — spread large actions via TWAP execution to reduce per-block extractable value. The key mindset is: assume adversarial ordering and design so that ordering doesn't affect outcomes."

**Interview Red Flags:**
- 🚩 Not connecting MEV to protocol design decisions — every swap, liquidation, and vault rebalance has an MEV surface
- 🚩 Only knowing defensive patterns (slippage, privacy) without knowing internalization (dynamic fees, MEV taxes, protocol-owned backrunning)
- 🚩 Thinking MEV can be eliminated rather than redirected — the value always goes somewhere; good design chooses where

**Pro tip:** The strongest signal of MEV expertise is understanding that MEV can't be eliminated — only redirected. Protocol designers choose WHERE the value goes: to searchers (bad), to validators (neutral), or back to users/LPs (good). Showing you think about this tradeoff immediately separates you from candidates who only know the attack taxonomy.

---

<a id="exercise2-mev-fee-hook"></a>
## 🎯 Build Exercise: MEV-Aware Dynamic Fee Hook

**Workspace:** `workspace/src/part3/module5/`

Implement a simplified V4-style hook that detects potential sandwich patterns and applies a dynamic fee surcharge.

**What you'll implement:**
- `MEVFeeHook` — tracks swap directions per pool per block
- `beforeSwap()` — detects opposite-direction swaps in the same block and returns a dynamic fee (normal or surcharge)
- `isSandwichLikely()` — view function that checks whether both swap directions occurred in the current block
- Test scenarios: normal swaps (low fee) vs sandwich-pattern swaps (high fee)

**Concepts exercised:**
- MEV detection heuristics (opposite-direction swaps in same block)
- Dynamic fee mechanism design
- The MEV internalization principle (capturing MEV for LPs)
- Uniswap V4 hook design patterns

**🎯 Goal:** Build a fee mechanism where normal users pay 0.3% but sandwich bots effectively pay 1%+, making the attack unprofitable.

Run: `forge test --match-contract MEVFeeHookTest -vvv`

---

<a id="summary-mev-defense"></a>
## 📋 Key Takeaways: MEV Defense & Protocol Design

After this section, you should be able to:

- Map the post-Merge MEV supply chain: searchers → builders → relays → proposers (PBS), and explain how competitive bidding drives most extracted value up to validators
- Compare MEV protection mechanisms across 4 layers: transaction privacy (Flashbots Protect), order flow auctions (MEV-Share with rebates), batch auctions (CoW Protocol), and intent-based execution (Module 4)
- Design MEV-aware protocols: minimize information leakage, reduce ordering dependence, and internalize MEV (dynamic fee hooks that surcharge suspected sandwich transactions, priority-fee-proportional swap fees that redirect extraction to LPs)

---

## 🔗 Cross-Module Concept Links

- AMM price impact → **P2 M2** constant product formula, slippage calculations
- Sandwich attacks on swaps → **P2 M2** swap mechanics, minimum output enforcement
- Flash loan arbitrage → **P2 M5** flash loan patterns, atomic execution
- Oracle manipulation → **P2 M3** TWAP vs spot price, multi-block attacks
- Liquidation MEV → **P2 M4** liquidation mechanics, health factor thresholds
- PBS and block building → **P3 M7** L2 sequencer ordering, centralized block production
- Dynamic fees as MEV defense → **P2 M2** Uniswap V4 hooks, fee adjustment

---

## 📖 Production Study Order

1. **Flashbots MEV-Boost relay** — builder API, block submission flow
2. **Flashbots Protect RPC** — private transaction submission, frontrunning protection
3. **MEV-Share contracts** — programmable MEV redistribution, order flow auctions
4. **UniswapX** — MEV-aware execution via Dutch auctions, filler network
5. **CoW Protocol** — batch auctions as MEV defense, solver competition
6. **Notable MEV bot contracts on Etherscan** — study real searcher strategies and gas optimization

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [Flashbots MEV-Boost](https://github.com/flashbots/mev-boost) — validator sidecar for PBS
- [Flashbots Builder](https://github.com/flashbots/builder) — reference block builder implementation
- [MEV-Share Node](https://github.com/flashbots/mev-share-node) — order flow auction implementation
- [CoW Protocol Solver](https://github.com/cowprotocol/solver) — batch auction solver

### Documentation
- [Flashbots Docs](https://docs.flashbots.net/) — full architecture docs for MEV-Boost, Protect, and MEV-Share
- [Ethereum.org: MEV](https://ethereum.org/en/developers/docs/mev/) — official MEV explainer
- [Builder API Specification](https://ethereum.github.io/builder-specs/) — Ethereum builder API spec

### Key Reading
- [Paradigm: Priority Is All You Need (MEV Taxes)](https://www.paradigm.xyz/2024/02/priority-is-all-you-need) — the MEV tax framework
- [Flashbots: The Future of MEV](https://writings.flashbots.net/the-future-of-mev) — post-Merge supply chain analysis
- [Flashbots: MEV-Share Design](https://collective.flashbots.net/t/mev-share-programmably-private-orderflow-to-share-mev-with-users/1264) — OFA design and economics
- [Frontier Research: Order Flow Auctions](https://frontier.tech/the-orderflow-auction-design-space) — design space analysis
- [MEV-Explore Dashboard](https://explore.flashbots.net/) — historical MEV extraction data

#### 📖 How to Study: MEV Ecosystem

1. Start with [Ethereum.org MEV page](https://ethereum.org/en/developers/docs/mev/) — the 10,000-foot overview
2. Read [Flashbots Protect docs](https://docs.flashbots.net/flashbots-protect/overview) — understand user-facing protection
3. Study [MEV-Share design](https://collective.flashbots.net/t/mev-share-programmably-private-orderflow-to-share-mev-with-users/1264) — understand order flow auctions
4. Read Paradigm's [MEV Taxes paper](https://www.paradigm.xyz/2024/02/priority-is-all-you-need) — the theoretical framework
5. Explore [MEV-Explore](https://explore.flashbots.net/) — look at real extraction data
6. Don't try to build a searcher from docs alone — the competitive advantage is in execution speed and gas optimization, which is best learned by doing

---

**Navigation:** [← Module 4: DEX Aggregation](4-dex-aggregation.md) | [Part 3 Overview](README.md) | [Next: Module 6 — Cross-Chain & Bridges →](6-cross-chain.md)

# Part 3 — Module 7: L2-Specific DeFi

> **Prerequisites:** Part 2 — Modules 3 (Oracles), 4 (Lending) | Part 3 — Module 6 (Cross-Chain)

## 📚 Table of Contents

1. [L2 Architecture for DeFi Developers](#l2-architecture)
2. [The L2 Gas Model](#gas-model)
3. [Build Exercise: L2 Gas Estimator](#exercise-gas-estimator)
4. [Sequencer Uptime & Oracle Safety](#sequencer-uptime)
5. [Build Exercise: L2-Aware Oracle Consumer](#exercise-oracle-consumer)
6. [Transaction Ordering & MEV on L2](#l2-mev)
7. [L2-Native Protocol Design](#l2-native)
8. [Multi-Chain Deployment Patterns](#multi-chain)
9. [Summary](#summary-l2-defi)
10. [Job Market Context](#job-market-context)
11. [Resources](#resources)

---

## 💡 Why L2 DeFi Matters

Most DeFi activity has migrated to L2s — Arbitrum, Base, and Optimism collectively host more DeFi transactions than Ethereum mainnet. But L2s aren't just "cheap Ethereum" — they have distinct sequencer behavior, gas models, finality properties, and design constraints that affect every protocol deployed on them.

**Why this matters for you:**
- Most new DeFi jobs are building on L2s — you'll deploy to Arbitrum/Base/Optimism, not mainnet
- L2-specific bugs (sequencer downtime, stale oracles, different block times) have caused real losses
- Gas model differences change which optimizations matter and which are unnecessary
- Understanding L2 architecture separates senior from junior DeFi engineers
- Connection to Module 5 (MEV): L2 sequencer ordering creates an entirely different MEV landscape
- Connection to Module 6 (Bridges): canonical rollup bridges are L2's trust anchor to L1

---

<a id="l2-architecture"></a>
## 💡 L2 Architecture for DeFi Developers

### 💡 Concept: Rollup Types

You don't need to understand rollup internals deeply, but you need to know how the two types affect your DeFi code:

```
OPTIMISTIC ROLLUPS (Arbitrum, Optimism, Base)
────────────────────────────────────────────
  Assumption: transactions are valid unless challenged
  Fraud proof: anyone can challenge within 7 days
  L2 → L1 withdrawal: 7-day delay (waiting for challenge period)
  L1 finality: ~7 days

  DeFi impact:
  ✓ Mature, battle-tested (most DeFi TVL)
  ✓ Full EVM equivalence
  ✗ Slow L1 finality (affects cross-chain composability)
  ✗ 7-day withdrawal delay (capital efficiency hit)

ZK ROLLUPS (zkSync Era, Scroll, Linea, Starknet)
────────────────────────────────────────────────
  Proof: validity proof mathematically guarantees correctness
  L2 → L1 withdrawal: hours (once proof verified on L1)
  L1 finality: hours (vs 7 days for optimistic)

  DeFi impact:
  ✓ Faster finality (better for cross-chain)
  ✓ Mathematical security guarantee
  ✗ Varying EVM compatibility (zkEVM types 1-4)
  ✗ Some opcodes unsupported or behave differently
  ✗ Higher prover costs passed to users
```

### The Sequencer: L2's Single Point of Control

Every major L2 currently runs a **centralized sequencer** — a single entity that:
1. Receives transactions from users
2. Orders them into blocks
3. Posts the data to L1

```
User tx → Sequencer → L2 Block → Batch → L1 (Ethereum)
           │
           ├─ Soft confirmation: ~250ms (Arbitrum), ~2s (OP Stack)
           │  "Your tx is included" — but only the sequencer says so
           │
           └─ Hard finality: 7 days (optimistic) / hours (ZK)
              "L1 has verified this is correct"
```

**Why this matters for DeFi:**
- The sequencer decides transaction ordering → it could theoretically front-run
- If the sequencer goes down → no new blocks → oracle prices freeze → liquidation risk
- Sequencer censorship: can delay (but not permanently block) your transaction
- **Forced inclusion:** Users can bypass the sequencer by submitting directly to L1
  - Arbitrum: delayed inbox (~24 hours)
  - Optimism: L1 deposit contract
  - This guarantee means the sequencer can delay but not permanently censor

### Block Properties: What Changes on L2

```solidity
// ⚠️ These behave differently on L2!

block.timestamp  // L2 block timestamp — NOT the L1 timestamp
                 // Arbitrum: set by sequencer, ~250ms resolution
                 // OP Stack: set to L1 origin block time, 2s blocks

block.number     // L2 block number — NOT the L1 block number
                 // Arbitrum: ~4 blocks/second
                 // OP Stack: 1 block per 2 seconds

block.basefee    // L2 base fee — much lower than L1

// Accessing L1 info:
// Arbitrum: ArbSys(0x64).arbBlockNumber() for L2 block count
// OP Stack: L1Block(0x4200000000000000000000000000000000000015).number() for latest known L1 block
```

**DeFi impact:** Any protocol using `block.number` for time-based logic (lock periods, vesting, epochs) must account for L2's different block times. A "1000 block lockup" means ~12 minutes on L1 but ~4 minutes on Arbitrum.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What are the risks of relying on the sequencer for transaction ordering?"**
   - Good answer: "The sequencer is centralized — it could censor transactions or go down."
   - Great answer: "Three risk categories: (1) Liveness — if the sequencer goes down, no transactions process, oracle prices freeze, users can't manage positions. Realized in the Arbitrum June 2023 outage. (2) Censorship — the sequencer can delay specific transactions. Forced inclusion via L1 mitigates this, but the delay (~24 hours on Arbitrum) is long enough to cause damage in fast-moving markets. (3) MEV extraction — the sequencer sees all pending transactions and controls ordering, so it could theoretically front-run or sandwich users. Current sequencers don't due to reputation, but there's no cryptographic guarantee — this is why sequencer decentralization is a major research area."

---

<a id="gas-model"></a>
## 💡 The L2 Gas Model

### 💡 Concept: Two Components of L2 Cost

This is the most important L2 concept for DeFi developers. Every L2 transaction pays for two things:

```
Total L2 tx cost = L2 execution cost + L1 data posting cost
                   ─────────────────   ────────────────────
                   Running EVM ops     Submitting tx data
                   on the rollup       to Ethereum L1
                   (cheap)             (the main expense)
```

#### 🔍 Deep Dive: L1 Data Cost Calculation

**Pre-EIP-4844 (calldata posting):**

```
L1 data cost = tx_data_bytes × gas_per_byte × L1_gas_price

Where:
  gas_per_byte = 16 (non-zero byte) or 4 (zero byte)
  Average: ~12 gas per byte (mix of zero/non-zero)

Example: a simple swap (≈300 bytes of calldata)
  L1 data cost = 300 × 12 × 30 gwei = 108,000 gwei ≈ $0.20
  L2 execution = ~100,000 gas × 0.1 gwei = 10,000 gwei ≈ $0.00002
  ──────────────────────────────────────────────────────────
  Total ≈ $0.20  (L1 data = 99.99% of cost!)
```

**Post-EIP-4844 (blob posting) — the game changer:**

```
Before 4844: Arbitrum tx ≈ $0.10 - $1.00
After 4844:  Arbitrum tx ≈ $0.001 - $0.01  (10-100x cheaper)

Why: blob space has separate fee market, much cheaper than calldata
     Target: 3 blobs per block, max 6
     Price adjusts like EIP-1559 — rises when demand > target

DeFi protocol impact:
  ✓ Complex multi-hop routing viable (more hops don't cost much more)
  ✓ Batch operations less necessary (individual txs already cheap)
  ✓ Smaller protocols can afford L2 deployment
  ✗ Blob pricing can spike during high demand
  ✗ Calldata-heavy operations still relatively expensive
```

**What this means for protocol design:**

```
L1 optimization priorities:         L2 optimization priorities:
─────────────────────────          ─────────────────────────
1. Minimize storage writes          1. Minimize calldata size
2. Minimize calldata size           2. Minimize storage writes
3. Pack structs tightly             3. Execution gas matters less
4. Use events for cheap data        4. More operations are "free"

On L1: storage is king            On L2: calldata is king
```

### Practical: Estimating L1 Data Cost

**On Optimism/Base — the GasPriceOracle:**

**Note:** The interface below shows the **pre-Ecotone** model. Post-Ecotone (March 2024), the oracle uses `baseFeeScalar()` and `blobBaseFeeScalar()` instead of the now-deprecated `overhead()` and `scalar()` functions. The `getL1Fee()` function remains valid across both models.

```solidity
// Optimism's L1 data cost estimation (simplified from GasPriceOracle)
// Pre-Ecotone interface (overhead/scalar deprecated since March 2024):
interface IGasPriceOracle {
    /// @notice Returns the L1 data fee for a given transaction (still valid post-Ecotone)
    function getL1Fee(bytes memory _data) external view returns (uint256);

    /// @notice Current L1 base fee
    function l1BaseFee() external view returns (uint256);

    /// @notice [DEPRECATED post-Ecotone] Overhead for each L1 data submission
    function overhead() external view returns (uint256);

    /// @notice [DEPRECATED post-Ecotone] Scalar applied to L1 data cost
    function scalar() external view returns (uint256);

    // --- Post-Ecotone functions (March 2024+) ---

    /// @notice Scalar applied to the L1 base fee portion of the blob cost
    function baseFeeScalar() external view returns (uint32);

    /// @notice Scalar applied to the L1 blob base fee
    function blobBaseFeeScalar() external view returns (uint32);
}

// Gas model evolution:
// - Pre-Ecotone: overhead() + scalar() model for calldata-only posting
// - Post-Ecotone (March 2024): baseFeeScalar() + blobBaseFeeScalar() for blob-aware pricing
// - Post-Fjord (July 2024): FastLZ compression estimation for more accurate L1 data cost

// Usage in your protocol:
contract L2CostAware {
    IGasPriceOracle constant GAS_ORACLE =
        IGasPriceOracle(0x420000000000000000000000000000000000000F);

    /// @notice Estimate whether splitting a swap saves money on L2
    function shouldSplit(
        bytes memory singleSwapCalldata,
        bytes memory splitSwapCalldata,
        uint256 singleOutput,
        uint256 splitOutput
    ) external view returns (bool) {
        // Extra L1 data cost from larger calldata
        uint256 extraL1Cost = GAS_ORACLE.getL1Fee(splitSwapCalldata)
                            - GAS_ORACLE.getL1Fee(singleSwapCalldata);

        // Is the routing improvement worth the extra L1 data cost?
        uint256 outputGain = splitOutput - singleOutput;
        return outputGain > extraL1Cost;
    }
}
```

**Connection to Module 4 (DEX Aggregation):** On L1, aggregators limit split routes because each extra hop costs ~$5-50 gas. On L2, the L2 execution cost per hop is negligible — the only cost is the extra calldata bytes. This is why L2 aggregators use more aggressive routing with more splits and hops.

💻 **Quick Try:**

Deploy in [Remix](https://remix.ethereum.org/) to see how calldata size affects L2 cost:

```solidity
contract CalldataCostDemo {
    // Simulate L1 data cost: 16 gas per non-zero byte, 4 per zero byte
    function estimateL1Gas(bytes calldata data) external pure returns (uint256 gas) {
        for (uint256 i = 0; i < data.length; i++) {
            gas += data[i] == 0 ? 4 : 16;
        }
    }

    // Compare: compact vs verbose encoding
    function compactSwap(address pool, uint128 amount, bool dir) external pure
        returns (bytes memory) { return abi.encodePacked(pool, amount, dir); }

    function verboseSwap(address pool, uint256 amount, uint256 minOut, address to, uint256 deadline)
        external pure returns (bytes memory) { return abi.encode(pool, amount, minOut, to, deadline); }
}
```

Call `compactSwap(addr, 1000, true)` and `verboseSwap(addr, 1000, 900, addr, 9999)`. Then pass each result to `estimateL1Gas()`. The compact version uses far fewer bytes. On L2, this calldata compression is the #1 gas optimization — not storage packing.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How does the L2 gas model differ from L1, and how does that affect protocol design?"**
   - Good answer: "L2 transactions pay for L2 execution plus L1 data posting. L1 data is the main cost, so on L2 you optimize for calldata size rather than storage writes."
   - Great answer: "Every L2 transaction has two cost components: L2 execution gas (cheap) and L1 data posting cost (dominant). Pre-EIP-4844, L1 data was ~99% of total cost. Post-4844, blob space is 10-100x cheaper, but calldata remains the primary optimization target. This flips the L1 hierarchy: on L1 you minimize storage writes; on L2 you minimize calldata bytes. Practically, packed calldata encoding saves more than storage packing. It also means complex routing with more hops is viable — extra pool interactions cost negligible L2 execution gas. This is why L2 aggregators use more aggressive split routing than L1 aggregators."

---

<a id="exercise-gas-estimator"></a>
## 🎯 Build Exercise: L2 Gas Estimator

**Workspace:** `workspace/src/part3/module7/`

Build a utility that estimates and compares L1 data costs for different calldata encodings, demonstrating why calldata optimization matters on L2.

**What you'll implement:**
- `estimateL1DataGas()` — calculate L1 gas cost for arbitrary calldata
- `compareEncodings()` — compare packed vs standard ABI encoding for the same swap parameters
- `shouldSplitRoute()` — determine if splitting a swap saves money after accounting for extra calldata cost
- Gas comparison tests proving that calldata size is the dominant L2 cost factor

**Concepts exercised:**
- L1 data cost calculation (16 gas per non-zero byte, 4 per zero byte)
- Calldata optimization techniques (packed encoding)
- Break-even analysis: routing improvement vs extra calldata cost
- The L2 cost model that flips L1 optimization priorities

**🎯 Goal:** Prove quantitatively that calldata size is the dominant cost on L2, and understand when routing optimizations are worth the extra calldata.

Run: `forge test --match-contract L2GasEstimatorTest -vvv`

---

## 📋 Summary: L2 Architecture & Gas

**✓ Covered:**
- L2 types: optimistic rollups (fraud proofs, 7-day finality) vs ZK rollups (validity proofs, hours)
- The sequencer: centralized ordering, soft vs hard finality, forced inclusion via L1
- Two-component gas model: L2 execution (cheap) + L1 data posting (dominant cost)
- EIP-4844 blob transactions: 10-100x fee reduction for L2s
- L1 data cost calculation: 16 gas per non-zero byte, 4 per zero byte
- Optimization priority flip: minimize calldata on L2, not storage writes
- Block property differences: `block.timestamp` and `block.number` vary across L2s

**Next:** Sequencer uptime risks and oracle safety patterns — the most critical L2-specific vulnerability for lending protocols.

---

<a id="sequencer-uptime"></a>
## ⚠️ Sequencer Uptime & Oracle Safety

### 💡 Concept: The Sequencer Downtime Problem

This is the most critical L2-specific DeFi issue. Real money has been lost because of it.

**The scenario:**

```
1. Sequencer goes down (network issue, bug, upgrade)
   → No new L2 blocks
   → Oracle prices freeze at last known value

2. While sequencer is down, market moves (ETH drops 10%)
   → L2 oracle still shows old price
   → Users can't add collateral (no blocks = no transactions)

3. Sequencer comes back online
   → Oracle updates to current price
   → Positions that were healthy are now underwater
   → Liquidation bots race to liquidate
   → Users had no chance to manage their positions

   Result: mass liquidations with no user recourse
```

**Real incident:** Arbitrum sequencer was down for ~1 hour in June 2023. Any lending protocol without sequencer checks would have exposed users to unfair liquidation on restart.

### The Aave PriceOracleSentinel Pattern

Aave V3 solves this with a grace period after sequencer restart:

```solidity
/// @notice Simplified from Aave V3 PriceOracleSentinel
contract PriceOracleSentinel {
    ISequencerUptimeFeed public immutable sequencerUptimeFeed;
    uint256 public immutable gracePeriod; // e.g., 3600 seconds (1 hour)

    constructor(address _feed, uint256 _gracePeriod) {
        sequencerUptimeFeed = ISequencerUptimeFeed(_feed);
        gracePeriod = _gracePeriod;
    }

    /// @notice Can liquidations proceed?
    function isLiquidationAllowed() public view returns (bool) {
        return _isUpAndPastGracePeriod();
    }

    /// @notice Can new borrows proceed?
    function isBorrowAllowed() public view returns (bool) {
        return _isUpAndPastGracePeriod();
    }

    function _isUpAndPastGracePeriod() internal view returns (bool) {
        (
            /* roundId */,
            int256 answer,      // 0 = up, 1 = down
            uint256 startedAt,  // when current status began
            /* updatedAt */,
            /* answeredInRound */
        ) = sequencerUptimeFeed.latestRoundData();

        // Sequencer is down → block everything
        if (answer != 0) return false;

        // Sequencer is up — but has it been up long enough?
        uint256 timeSinceUp = block.timestamp - startedAt;
        return timeSinceUp >= gracePeriod;
    }
}
```

**The logic:**

```
Sequencer DOWN:
  → Block liquidations (unfair — users can't respond)
  → Block new borrows (would use stale prices)
  → Allow repayments and collateral additions (always safe)

Sequencer UP but within grace period:
  → Block liquidations (give users time to manage positions)
  → Block new borrows (oracle might still be catching up)
  → Allow repayments and collateral additions

Sequencer UP and past grace period:
  → Normal operation — all actions allowed
```

**Chainlink L2 Sequencer Uptime Feed:**

Chainlink provides dedicated feeds that report sequencer status:

```
Feed address (Arbitrum): 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
⚠️ Always verify at Chainlink's L2 Sequencer Feeds docs — addresses may change.

Returns:
  answer = 0  → sequencer is UP
  answer = 1  → sequencer is DOWN
  startedAt   → timestamp when current status began
```

**Every lending protocol on L2 MUST implement this pattern.** Deploying an L1 lending protocol to L2 without sequencer uptime checks is a known vulnerability.

#### 🔗 DeFi Pattern Connection

**Sequencer dependency appears across DeFi on L2:**

| Protocol Type | Without Sequencer Check | With Sequencer Check |
|---|---|---|
| **Lending** | Mass liquidation on restart | Grace period protects borrowers |
| **Perpetuals** | Unfair liquidation at stale prices | Position management paused |
| **Vaults** | Rebalance at stale prices | Strategy paused during downtime |
| **Oracles** | Return stale data | Revert or flag staleness |

**Connection to Part 2 Module 3 (Oracles):** The staleness checks you learned for oracle prices extend to sequencer status. Same pattern — check freshness before trusting the data.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What should a lending protocol do when the L2 sequencer goes down?"**
   - Good answer: "Check sequencer uptime using Chainlink's feed, and pause liquidations with a grace period after restart."
   - Great answer: "Aave V3's PriceOracleSentinel is the gold standard. It checks Chainlink's L2 Sequencer Uptime Feed, which reports whether the sequencer is up/down and when the current status started. During downtime: block liquidations and new borrows, but allow repayments and collateral additions (always safe). After restart: enforce a grace period (typically 1 hour) before allowing liquidations, giving users time to manage positions that became undercollateralized while they couldn't interact. Any lending protocol deploying to L2 without this pattern has a known vulnerability — the Arbitrum June 2023 outage proved this isn't theoretical."

---

<a id="exercise-oracle-consumer"></a>
## 🎯 Build Exercise: L2-Aware Oracle Consumer

**Workspace:** `workspace/src/part3/module7/`

Build an oracle consumer that integrates Chainlink's L2 Sequencer Uptime Feed with a grace period pattern, protecting a lending protocol from stale-price liquidations.

**What you'll implement:**
- `isSequencerUp()` — check the sequencer uptime feed
- `isGracePeriodPassed()` — check if enough time has elapsed since restart
- `getPrice()` — return price only when safe (sequencer up + grace period passed + price fresh)
- `isLiquidationAllowed()` — combine all safety checks
- `isBorrowAllowed()` — same checks for new borrows

**Concepts exercised:**
- Chainlink sequencer uptime feed integration
- Grace period pattern (Aave PriceOracleSentinel)
- Defense-in-depth: multiple safety conditions combined
- L2-specific risk handling that doesn't exist on L1

**🎯 Goal:** Build the oracle safety layer that every L2 lending protocol needs. Your implementation should handle: sequencer down, sequencer just restarted (within grace period), stale price, and normal operation.

Run: `forge test --match-contract L2OracleTest -vvv`

---

## 📋 Summary: Sequencer Risks & Oracle Safety

**✓ Covered:**
- Sequencer liveness: downtime freezes oracle prices and blocks user transactions
- Chainlink L2 Sequencer Uptime Feed: dedicated feed reporting sequencer status
- Aave PriceOracleSentinel: the gold-standard grace period pattern
- Grace period logic: block liquidations/borrows during downtime and after restart
- Defense-in-depth: sequencer check + grace period + price staleness combined
- Differential safety: repayments and collateral additions always allowed, even during downtime

**Next:** Transaction ordering and MEV on L2 — how centralized sequencers create a fundamentally different MEV landscape.

---

<a id="l2-mev"></a>
## 💡 Transaction Ordering & MEV on L2

### 💡 Concept: A Different MEV Landscape

Module 5 covered L1 MEV in depth. L2 MEV is fundamentally different because the sequencer controls ordering:

```
L1 MEV SUPPLY CHAIN (Module 5):
  Users → Mempool → Searchers → Builders → Relays → Proposers
  (Many parties, competitive, PBS separates roles)

L2 MEV (current state):
  Users → Sequencer
  (One party controls ordering — the sequencer IS the builder)
```

**This centralization has tradeoffs:**

### Arbitrum: First-Come-First-Served (FCFS)

```
Arbitrum's approach: transactions ordered by arrival time
  → No gas priority auctions
  → Sandwich attacks harder (can't outbid for ordering)
  → But: latency races instead of gas wars
     Searcher closest to sequencer gets fastest inclusion

  Timeboost (newer): auction-based express lane
  → 60-second rounds, winner gets priority ordering
  → Revenue goes to the DAO (MEV internalization)
  → Non-express transactions still FCFS
```

### Optimism/Base: Priority Fee Ordering

```
OP Stack approach: standard priority fee model (like L1)
  → Higher priority fee = earlier inclusion
  → Standard MEV dynamics apply (sandwich, frontrun possible)
  → But: sequencer can theoretically extract MEV itself
     (reputational risk prevents this in practice)

  Sequencer revenue: base fee + priority fees
  → No PBS — sequencer is the builder
```

### Shared Sequencing (Future)

```
Current: each L2 has its own sequencer → cross-L2 MEV possible
         (arbitrage between Arbitrum and Optimism prices)

Shared sequencing: multiple L2s share a sequencer
  → Atomic cross-L2 transactions possible
  → Reduces cross-domain MEV (Module 5 connection)
  → Proposals: Espresso, Astria
  → Not yet deployed in production
```

**Key insight for protocol designers:** On L2, your MEV exposure depends on which L2 you deploy to. Arbitrum's FCFS makes sandwich attacks harder; OP Stack's priority ordering means L1-style MEV dynamics apply. This affects your choice of L2, your slippage parameters, and whether you need intent-based protection (Module 4).

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How does MEV differ between Arbitrum and Optimism?"**
   - Good answer: "Arbitrum uses first-come-first-served ordering, making sandwich attacks harder. Optimism uses priority fee ordering like L1."
   - Great answer: "The fundamental difference is ordering policy. Arbitrum uses FCFS — transactions ordered by arrival time, not gas price. You can't outbid for position, which makes traditional sandwich attacks harder, but it creates latency races instead. Arbitrum's Timeboost adds an auction layer: 60-second rounds, winner gets an express lane, revenue goes to the DAO (MEV internalization). OP Stack chains use standard priority fee ordering, so L1-style MEV dynamics apply. This affects protocol design: on Arbitrum you might rely on FCFS for MEV protection; on Base you'd still want intent-based execution or tight slippage limits."

---

<a id="l2-native"></a>
## 💡 L2-Native Protocol Design

### 💡 Concept: What Cheap Gas Enables

L2's low gas costs don't just make existing patterns cheaper — they enable entirely new protocol designs that wouldn't be viable on L1.

### Aerodrome (Base): ve(3,3) DEX

```
L1 constraint: epoch-based operations are expensive
  → Weekly vote cycles cost $50+ per LP to claim + vote
  → Only whales participate in governance

Aerodrome's L2 design: frequent operations are cheap
  → Weekly epochs: vote → emit rewards → swap → distribute fees
  → LPs can claim rewards, re-lock, and vote every week (~$0.01 each)
  → More granular incentive alignment
  → Result: dominant DEX on Base by TVL and volume
```

**Why it only works on L2:** The ve(3,3) mechanism requires frequent user interactions (voting, claiming, locking). On L1 at $50/tx, only large holders participate. On L2 at $0.01/tx, even small LPs can actively participate — making the governance mechanism actually work as designed.

### GMX on Arbitrum: Keeper-Based Execution

```
GMX's two-step execution model:
  Step 1: User creates order (market/limit) → stored on-chain
  Step 2: Keeper executes order at oracle price → fills the order

On L1: Step 2 costs keepers $10-50 → only profitable for large orders
On L2: Step 2 costs keepers $0.01 → viable for any order size
```

**Connection to Module 2 (Perpetuals):** GMX's keeper delay also serves as MEV protection — the oracle price at execution time is unknown when the order is submitted, preventing front-running. This two-step pattern was covered in Module 2's GMX architecture section.

### On-Chain Order Books

```
L1: on-chain order books are impractical
  → Placing an order costs $10-50
  → Cancelling costs $10-50
  → Market makers can't efficiently update quotes

L2: on-chain order books become viable
  → Place/cancel for $0.01
  → Market makers can update frequently
  → Examples: dYdX (moved to Cosmos for even cheaper execution)
```

### Design Patterns for L2

```solidity
/// @notice Example: auto-compounding vault that's only viable on L2
contract L2AutoCompounder {
    uint256 public constant HARVEST_INTERVAL = 1 hours; // viable on L2!
    uint256 public lastHarvest;

    /// @notice Harvest and reinvest — called frequently on L2
    /// On L1: would cost $20+ per harvest, only profitable monthly
    /// On L2: costs $0.01 per harvest, profitable hourly
    function harvest() external {
        require(block.timestamp >= lastHarvest + HARVEST_INTERVAL, "Too early");
        lastHarvest = block.timestamp;

        uint256 rewards = _claimRewards();
        uint256 newShares = _swapAndDeposit(rewards);
        // Compound effect: hourly on L2 vs monthly on L1
        // Over a year: significantly better returns
    }
}
```

**The compounding difference:**

```
$100,000 vault earning 10% APR:

L1 (monthly compound, $20 harvest cost):
  Effective APY: 10.47%
  Year-end: $110,471
  Harvest costs: $240/year

L2 (hourly compound, $0.01 harvest cost):
  Effective APY: 10.52%
  Year-end: $110,517
  Harvest costs: $87.60/year

Difference per $100K: $46 more returns + $152 less in gas
For a $10M vault: $4,600 + $15,200 = ~$20K/year better
```

The numbers are modest per user, but for large vaults the compounding frequency difference adds up — and the gas savings are significant at scale.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you design differently for L2 vs L1?"**
   - Good answer: "Use cheaper gas to enable more frequent operations. Add sequencer uptime checks. Adjust time-based logic for different block times."
   - Great answer: "Three categories: (1) Enable new operations — hourly auto-compounding instead of monthly, more aggressive aggregation routing, on-chain order books, keeper-based two-step execution for any order size. (2) Handle L2-specific risks — sequencer uptime checks on all oracle-dependent operations with grace periods, account for different block times in lockup/epoch logic, consider the L2's MEV model when setting slippage defaults. (3) Optimize for the L2 cost model — minimize calldata over storage, packed encodings, shorter function signatures. The biggest mistake is deploying an L1 protocol to L2 unchanged — the sequencer risk alone makes that dangerous."

---

<a id="multi-chain"></a>
## 💡 Multi-Chain Deployment Patterns

### 💡 Concept: Same Protocol, Different Parameters

When deploying a protocol across chains, you need chain-specific configuration:

```solidity
/// @notice Example: chain-aware lending configuration
contract ChainConfig {
    struct ChainParams {
        uint256 gracePeriod;        // sequencer restart grace (L2 only)
        uint256 liquidationDelay;   // extra buffer for sequencer risk
        uint256 minBorrowAmount;    // higher on L1 (gas cost floor)
        bool requireSequencerCheck; // true on L2, false on L1
    }

    // Chain-specific parameters
    // Arbitrum: fast blocks, FCFS ordering, needs sequencer check
    // Ethereum: slow blocks, PBS ordering, no sequencer check
    // Base: fast blocks, priority ordering, needs sequencer check
}
```

**Key differences across chains:**

| Parameter | Ethereum L1 | Arbitrum | Base/Optimism |
|---|---|---|---|
| Sequencer check | No | Yes | Yes |
| Grace period | N/A | 1 hour | 1 hour |
| Block time | 12 seconds | ~250ms | 2 seconds |
| Min viable tx | ~$5 | ~$0.01 | ~$0.01 |
| MEV model | PBS | FCFS / Timeboost | Priority fees |
| Oracle config | Standard Chainlink | + Sequencer uptime feed | + Sequencer uptime feed |

### CREATE2 for Deterministic Addresses

```solidity
// Deploy to the same address on every chain using CREATE2
// This simplifies cross-chain message verification (Module 6 connection)

bytes32 salt = keccak256("MyProtocol_v1");
address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
    bytes1(0xff),
    factory,
    salt,
    keccak256(creationCode)
)))));
// Same factory + same salt + same bytecode = same address on every chain
```

**Why this matters:** If your protocol has the same address on Arbitrum and Base, cross-chain message verification is simpler — you just check `msg.sender == knownAddress` instead of maintaining per-chain address mappings.

### Cross-Chain Governance

```
Pattern: Vote on L1, execute on L2

1. Governance token lives on Ethereum (deepest liquidity)
2. Users vote on proposals via on-chain governance (Governor)
3. Passed proposal → Timelock → Cross-chain message to each L2
4. Each L2 has a Timelock receiver that executes the action

    Ethereum                  Arbitrum              Base
┌────────────────┐     ┌──────────────────┐  ┌──────────────────┐
│  Governor       │     │  L2 Timelock      │  │  L2 Timelock      │
│  ↓ proposal     │────→│  ↓ verify msg     │  │  ↓ verify msg     │
│  Timelock       │     │  ↓ execute action  │  │  ↓ execute action  │
│  ↓ send msg     │────→│  (update params)   │  │  (update params)   │
└────────────────┘     └──────────────────┘  └──────────────────┘
        │                    via LayerZero/CCIP (Module 6)
```

This connects directly to Module 6's cross-chain message handler pattern and Module 8's governance module.

---

<a id="summary-l2-defi"></a>
## 📋 Summary: L2-Specific DeFi

**✓ Covered:**
- L2 architecture: optimistic vs ZK rollups and their DeFi implications
- The sequencer: centralization, soft vs hard finality, forced inclusion
- L2 gas model: two components, L1 data dominance, EIP-4844 impact
- Sequencer uptime and oracle safety: the PriceOracleSentinel pattern with full Solidity
- L2 MEV: Arbitrum FCFS/Timeboost vs OP Stack priority fees vs shared sequencing
- L2-native protocol design: what cheap gas enables (auto-compounding, order books, keeper execution)
- Multi-chain deployment: chain-specific parameters, CREATE2, cross-chain governance
- Block property differences: timestamp, block number, L1 info access

**Next:** Job market context — interview questions and what DeFi teams expect around L2 DeFi knowledge.

---

<a id="job-market-context"></a>
## 💼 Job Market Context

**Interview red flags:**
- Not knowing that L2 gas has two components (L2 execution + L1 data)
- Deploying a lending protocol to L2 without sequencer uptime checks
- Using `block.number` for time calculations without adjusting for L2 block time
- Treating L2 as "just cheaper L1" without understanding the architectural differences
- Not knowing about EIP-4844's impact on L2 economics

**Pro tip:** Most DeFi teams are building on L2 now. Demonstrating awareness of sequencer uptime checks, L2 gas optimization, and chain-specific MEV dynamics shows you've actually shipped on L2, not just read about it. Mentioning Aave's PriceOracleSentinel by name signals deep familiarity.

---

## 🔗 Cross-Module Concept Links

- Gas optimization on L2 → **P1 M2** EVM gas costs, **P2 M2** AMM gas patterns
- Oracle on L2 → **P2 M3** Chainlink feeds, sequencer uptime feeds
- MEV on L2 → **P3 M5** MEV supply chain, sequencer ordering differences
- Bridge deposits → **P3 M6** canonical bridges, message passing
- Multi-chain tokens → **P3 M6** xERC20, OFT standards for cross-chain fungibility
- Deployment scripts → **P1 M7** CREATE2, multi-chain deployment strategies

---

## 📖 Production Study Order

1. **Optimism L2OutputOracle** — state root posting, challenge period
2. **Arbitrum Sequencer Inbox** — transaction ordering, delayed inbox
3. **Base/Optimism L1Block.sol** — L1 data cost estimation, gas oracle
4. **Aave V3 on Arbitrum** — sequencer uptime integration, PriceOracleSentinel
5. **Uniswap V3 on multiple L2s** — deployment comparison, chain-specific adaptations
6. **Velodrome/Aerodrome** — L2-native AMM design, ve(3,3) on OP Stack

---

<a id="resources"></a>
## 📚 Resources

### Production Code
- [Aave PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol) — the gold standard sequencer uptime pattern
- [Chainlink L2 Sequencer Feed](https://docs.chain.link/data-feeds/l2-sequencer-feeds) — integration guide and addresses
- [Aerodrome](https://github.com/aerodrome-finance/contracts) — L2-native ve(3,3) DEX
- [Arbitrum Nitro Contracts](https://github.com/OffchainLabs/nitro-contracts) — ArbSys, ArbGasInfo
- [Optimism GasPriceOracle](https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/L2/GasPriceOracle.sol) — L1 data cost estimation

### Documentation
- [Arbitrum developer docs](https://docs.arbitrum.io/build-decentralized-apps/precompiles/reference) — precompiles and system contracts
- [Optimism developer docs](https://docs.optimism.io/builders/app-developers/transactions/estimates) — gas estimation and L1 data costs
- [Base developer docs](https://docs.base.org/) — building on OP Stack

### Key Reading
- [Vitalik: Different types of layer 2s](https://vitalik.eth.limo/general/2023/10/31/l2types.html) — framework for understanding L2 tradeoffs
- [L2Beat — L2 risk analysis](https://l2beat.com/) — risk comparison dashboard for all L2s
- [EIP-4844 FAQ](https://www.eip4844.com/) — blob transaction impact on L2s
- [Arbitrum Timeboost](https://docs.arbitrum.io/how-arbitrum-works/timeboost) — auction-based express lane
- [Chainlink: Using L2 Sequencer Feeds](https://docs.chain.link/data-feeds/l2-sequencer-feeds) — integration tutorial

#### 📖 How to Study: L2 DeFi

1. Start with [Vitalik's L2 types post](https://vitalik.eth.limo/general/2023/10/31/l2types.html) — understand the landscape
2. Read [Aave PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol) — the most important L2-specific pattern
3. Study [Chainlink's L2 Sequencer Feed docs](https://docs.chain.link/data-feeds/l2-sequencer-feeds) — how to integrate
4. Browse [L2Beat](https://l2beat.com/) — compare risk profiles of different L2s
5. Deploy a simple contract to Arbitrum Sepolia testnet — feel the gas difference
6. Read Optimism's [gas estimation docs](https://docs.optimism.io/builders/app-developers/transactions/estimates) — understand the two-component cost model

---

**Navigation:** [← Module 6: Cross-Chain & Bridges](6-cross-chain.md) | [Part 3 Overview](README.md) | [Next: Module 8 — Governance & DAOs →](8-governance.md)

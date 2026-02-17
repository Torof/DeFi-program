# Part 2 — Module 3: Oracles

**Duration:** ~3 days (3–4 hours/day)
**Prerequisites:** Modules 1–2 complete (token mechanics, AMM math and architecture)
**Pattern:** Concept → Read production integrations → Build safe consumer → Attack and defend
**Builds on:** Module 2 (TWAP oracle from AMM price accumulators), Part 1 Section 5 (fork testing with real Chainlink feeds)
**Used by:** Module 4 (lending collateral valuation, liquidation triggers), Module 6 (CDP liquidation triggers), Module 9 (integration capstone)

---

## Why Oracles Matter for Protocol Builders

DeFi protocols that only swap tokens can derive prices from their own reserves. But the moment you build anything that references the value of an asset — lending (what's the collateral worth?), derivatives (what's the settlement price?), stablecoins (is this position undercollateralized?) — you need external price data.

The problem: blockchains are deterministic and isolated. They can't fetch data from the outside world. Oracles bridge this gap, but in doing so, they become the single most attacked surface in DeFi. Oracle manipulation accounted for $403 million in losses in 2022, $52 million across 37 incidents in 2024, and continues to be the second most damaging attack vector. If you're building a protocol that uses price data, oracle security is not optional — it's existential.

This module teaches you to consume oracle data safely and understand the attack surface deeply enough to defend against it.

---

## Day 1: Oracle Fundamentals and Chainlink Architecture

### The Oracle Problem

Smart contracts execute deterministically — given the same state and input, they always produce the same output. This is a feature (consensus depends on it), but it means contracts can't natively access off-chain data like asset prices, weather, sports scores, or API results.

An oracle is any mechanism that feeds external data into a smart contract. The critical question is always: **who or what can you trust to provide accurate data, and what happens if that trust is violated?**

### Types of Price Oracles

**1. Centralized oracles** — A single entity publishes price data on-chain. Simple, fast, but a single point of failure. If the entity goes down, gets hacked, or acts maliciously, every protocol depending on it breaks. Mango Markets used FTX as part of its price source — a centralized exchange that later collapsed.

**2. On-chain oracles (DEX-based)** — Derive price from AMM reserves. The spot price in a Uniswap pool is `reserve1 / reserve0`. Free to read, no external dependency, but trivially manipulable with a large trade or flash loan. Using raw spot price as an oracle is essentially asking to be exploited.

**3. TWAP oracles** — Time-weighted average price computed from on-chain data over a window (e.g., 30 minutes). Resistant to single-block manipulation because the attacker would need to sustain the manipulated price across many blocks. Trade-off: the price lags behind the real market, which can be exploited during high volatility.

**4. Decentralized oracle networks (Chainlink, Pyth, Redstone)** — Multiple independent nodes fetch prices from multiple data sources, aggregate them, and publish the result on-chain. The most robust option for most use cases, but introduces latency, update frequency considerations, and trust in the oracle network itself.

### Chainlink Architecture Deep Dive

Chainlink is the dominant oracle provider in DeFi, securing hundreds of billions in value. Understanding its architecture is essential.

**Three-layer design:**

**Layer 1: Data providers** — Premium data aggregators (e.g., CoinGecko, CoinMarketCap, Kaiko, Amberdata) aggregate raw price data from centralized and decentralized exchanges, filtering for outliers, wash trading, and stale data.

**Layer 2: Chainlink nodes** — Independent node operators fetch data from multiple providers. Each node produces its own price observation. Nodes are selected for reputation, reliability, and stake. The node set for a given feed (e.g., ETH/USD) typically includes 15–31 nodes.

**Layer 3: On-chain aggregation** — Nodes submit observations to an on-chain Aggregator contract. The contract computes the median of all observations and publishes it as the feed's answer. The median is key — it's resistant to outliers, meaning a minority of compromised nodes can't skew the result.

**Offchain Reporting (OCR):** Rather than each node submitting a separate on-chain transaction (expensive), Chainlink uses OCR: nodes agree on a value off-chain and submit a single aggregated report with all signatures. This dramatically reduces gas costs.

**Update triggers:**

Feeds don't update continuously. They update when either condition is met:
- **Deviation threshold:** The off-chain value deviates from the on-chain value by more than X% (typically 0.5% for major pairs, 1% for others)
- **Heartbeat:** A maximum time between updates regardless of price movement (typically 1 hour for major pairs, up to 24 hours for less active feeds)

This means the on-chain price can be up to [deviation threshold] stale at any moment. Your protocol must account for this.

**On-chain contract structure:**

```
Consumer (your protocol)
    ↓ calls latestRoundData()
Proxy (EACAggregatorProxy)
    ↓ delegates to
Aggregator (AccessControlledOffchainAggregator)
    ↓ receives reports from
Chainlink Node Network
```

The Proxy layer is critical — it allows Chainlink to upgrade the underlying Aggregator (change node set, update parameters) without breaking consumer contracts. Your protocol should always point to the Proxy address, never directly to an Aggregator.

### Read: AggregatorV3Interface

**Source:** `@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol`

The interface your protocol will use:

```solidity
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
```

**Critical fields in `latestRoundData()`:**
- `answer` — the price, as an `int256` (can be negative for some feeds). For ETH/USD with 8 decimals, a value of `300000000000` means $3,000.00.
- `updatedAt` — timestamp of the last update. Your protocol MUST check this for staleness.
- `roundId` — the round identifier. Used for historical data lookups.
- `decimals()` — the number of decimal places in `answer`. Do NOT hardcode this. Different feeds use different decimals (most price feeds use 8, but ETH-denominated feeds use 18).

### Build: Safe Chainlink Consumer

**Exercise 1: Build an `OracleConsumer.sol`** that reads Chainlink price feeds with proper safety checks:

```solidity
function getPrice(address feed) public view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
    (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) = priceFeed.latestRoundData();

    // CHECK 1: Answer is positive
    require(answer > 0, "Invalid price");

    // CHECK 2: Round is complete
    require(updatedAt > 0, "Round not complete");

    // CHECK 3: Data is not stale
    require(block.timestamp - updatedAt < MAX_STALENESS, "Stale price");

    return uint256(answer);
}
```

All three checks are mandatory. Protocols that skip any of them have been exploited. The staleness check is the most commonly omitted — and the most dangerous.

**Exercise 2: Multi-feed price derivation.** Build a function that computes ETH/EUR by combining ETH/USD and EUR/USD feeds. Handle decimal normalization (both feeds may have different `decimals()` values).

**Exercise 3: L2 sequencer check.** On L2 networks (Arbitrum, Optimism), the sequencer can go down. During downtime, Chainlink feeds appear fresh but may be using stale data. Chainlink provides L2 Sequencer Uptime Feeds. Build a consumer that checks sequencer status before reading price data:

```solidity
function isSequencerUp(address sequencerFeed) internal view returns (bool) {
    (, int256 answer, , uint256 startedAt, ) =
        AggregatorV3Interface(sequencerFeed).latestRoundData();

    // answer == 0 means sequencer is up, 1 means it's down
    bool isUp = answer == 0;

    // Even if up, enforce a grace period after recovery
    // to let feeds catch up to real prices
    uint256 timeSinceUp = block.timestamp - startedAt;
    require(timeSinceUp > GRACE_PERIOD, "Grace period not over");

    return isUp;
}
```

**Exercise 4: Foundry tests using mainnet fork.** Fork Ethereum mainnet with `forge test --fork-url <RPC>` and read real Chainlink feeds. Verify your consumer returns sane values for ETH/USD, BTC/USD. Use `vm.warp()` to simulate staleness conditions and verify your checks revert correctly.

---

## Day 2: TWAP Oracles and On-Chain Price Sources

### TWAP: Time-Weighted Average Price

You studied TWAP briefly in Module 2 (Uniswap V2's cumulative price accumulators). Now let's go deeper into when and how to use TWAP oracles.

**How TWAP works:**

A TWAP oracle doesn't store prices directly. Instead, it stores a *cumulative price* that increases over time:

```
priceCumulative(t) = Σ(price_i × duration_i)  for all periods up to time t
```

To get the average price between time `t1` and `t2`:

```
TWAP = (priceCumulative(t2) - priceCumulative(t1)) / (t2 - t1)
```

The key property: a flash loan attacker can manipulate the spot price for one block, but that only affects the cumulative sum for ~12 seconds (one block). Over a 30-minute TWAP window, one manipulated block contributes only ~0.7% of the average. The attacker would need to sustain the manipulation for the entire window — which means holding a massive position across many blocks, paying gas, and taking on enormous market risk.

**Uniswap V2 TWAP:**
- `price0CumulativeLast` / `price1CumulativeLast` in the pair contract
- Updated on every `swap()`, `mint()`, or `burn()`
- Uses UQ112.112 fixed-point for precision
- The cumulative values are designed to overflow safely (unsigned integer wrapping)
- External contracts must snapshot these values at two points in time and compute the difference

**Uniswap V3 TWAP:**
- More sophisticated: uses an `observations` array (ring buffer) storing `(timestamp, tickCumulative, liquidityCumulative)`
- Can return TWAP for any window up to the observation buffer length
- Built-in `observe()` function computes TWAP ticks directly
- The TWAP is in tick space (geometric mean), not arithmetic mean — more resistant to manipulation

**V4 TWAP:**
- V4 removed the built-in oracle. TWAP is now implemented via hooks (e.g., the Geomean Oracle hook).
- This gives more flexibility but means protocols need to find or build the appropriate hook.

### When to Use TWAP vs Chainlink

| Factor | Chainlink | TWAP |
|--------|-----------|------|
| Manipulation resistance | High (off-chain aggregation) | Medium (sustained multi-block attack needed) |
| Latency | Medium (heartbeat + deviation) | High (window size = lag) |
| Cost | Free to read, someone else pays for updates | Free to read, relies on pool activity |
| Coverage | Broad (hundreds of pairs) | Only pairs with sufficient on-chain liquidity |
| Centralization risk | Moderate (node operator trust) | Low (fully on-chain) |
| Best for | Lending, liquidations, anything high-stakes | Supplementary checks, fallback, low-cap tokens |

**The production pattern:** Most serious protocols use Chainlink as the primary oracle and TWAP as a secondary check or fallback. If Chainlink reports a price that deviates significantly from the TWAP, the protocol can pause or flag the discrepancy.

### Build: TWAP Oracle

**Exercise 1: Build a TWAP oracle contract** that:
- Stores periodic price observations (price, timestamp) from a Uniswap V2 pair
- Exposes a `consult()` function that returns the TWAP over a configurable window
- Handles the case where insufficient observations exist (revert with clear error)
- Uses proper fixed-point arithmetic to avoid precision loss

**Exercise 2: Compare TWAP to spot.** Deploy a pool, execute swaps that move the price dramatically, then compare the TWAP (over 10 blocks) to the current spot price. Verify the TWAP lags behind the spot — this lag is the trade-off for manipulation resistance.

**Exercise 3: Dual oracle pattern.** Build a `DualOracle.sol` that:
- Reads Chainlink as the primary source
- Reads TWAP as the secondary source
- Reverts if the two sources disagree by more than a configurable threshold (e.g., 5%)
- Falls back to TWAP if the Chainlink feed is stale
- Emits an event when switching sources

This dual-oracle pattern is used in production by protocols like Liquity.

---

## Day 3: Oracle Manipulation Attacks

### The Attack Surface

Oracle manipulation is a category of attacks where the attacker corrupts the price data that a protocol relies on, then exploits the protocol's reaction to the false price. The protocol code executes correctly — it just operates on poisoned inputs.

### Attack Pattern 1: Spot Price Manipulation via Flash Loan

This is the most common oracle attack. The target: any protocol that reads spot price from a DEX pool.

**The attack flow:**

1. Attacker takes a flash loan of Token A (millions of dollars worth)
2. Attacker swaps Token A → Token B in a DEX pool, massively moving the spot price
3. Attacker interacts with the victim protocol, which reads the manipulated spot price
   - If lending protocol: deposit Token B as collateral (now valued at inflated price), borrow other assets far exceeding collateral's true value
   - If vault: trigger favorable exchange rate calculation
4. Attacker swaps Token B back → Token A in the DEX, restoring the price
5. Attacker repays the flash loan
6. All within a single transaction — profit extracted, protocol drained

**Why it works:** The victim protocol uses `reserve1 / reserve0` (spot price) as its oracle. A flash loan can move this ratio arbitrarily within a single block, and the protocol reads it in the same block.

**Real example — Polter Finance (2024):** Polter Finance used a Chainlink-Uniswap adapter to price BOO tokens from SpookySwap liquidity pools. The attacker flash-loaned BOO tokens, drained the SpookySwap pools to manipulate the price, deposited minimal BOO as collateral (now valued at $1.37 trillion due to the manipulated price), and borrowed massively against it.

### Attack Pattern 2: TWAP Manipulation (Multi-Block)

TWAP oracles resist single-block attacks, but they're not immune. An attacker with sufficient capital (or who can bribe block producers) can sustain a manipulated price across the TWAP window.

**The economics:** To manipulate a 30-minute TWAP by 10%, the attacker needs to sustain a 10% price deviation for 150 blocks (at 12s/block). This means holding a massive position that continuously loses to arbitrageurs. The cost of the attack = arbitrageur profits + opportunity cost + gas. For high-liquidity pools, this cost is prohibitive. For low-liquidity pools, it can be economical.

**Multi-block MEV:** With validator-level access (e.g., block builder who controls consecutive blocks), TWAP manipulation becomes cheaper because the attacker can exclude arbitrageur transactions. This is an active area of research and concern.

### Attack Pattern 3: Stale Oracle Exploitation

If a Chainlink feed hasn't updated (due to network congestion, gas price spikes, or feed misconfiguration), the on-chain price may lag significantly behind the real market price. An attacker can exploit the stale price:

- If the real price of ETH has dropped 20% but the oracle still shows the old price, the attacker can deposit ETH as collateral at the stale (higher) valuation and borrow against it
- When the oracle finally updates, the position is undercollateralized, and the protocol absorbs the loss

This is why your staleness check from Day 1 is critical.

### Attack Pattern 4: Donation/Direct Balance Manipulation

Some protocols calculate prices based on internal token balances (e.g., vault share prices based on `totalAssets() / totalShares()`). An attacker can send tokens directly to the contract (bypassing `deposit()`), inflating the perceived value per share. This is related to the "inflation attack" on ERC-4626 vaults (covered in Module 7).

### Defense Patterns

**1. Never use DEX spot price as an oracle.** This is the single most important rule. If your protocol reads `reserve1 / reserve0` as a price, it will be exploited.

**2. Use Chainlink or equivalent decentralized oracle networks** for any high-stakes price dependency (collateral valuation, liquidation triggers, settlement).

**3. Implement staleness checks** on every oracle read. Choose your `MAX_STALENESS` based on the feed's heartbeat — if the heartbeat is 1 hour, a staleness threshold of 1 hour + buffer is reasonable.

**4. Validate the answer is sane.** Check that the price is positive, non-zero, and optionally within a reasonable range compared to historical data or a secondary source.

**5. Use dual/multi-oracle patterns.** Cross-reference Chainlink with TWAP. If they disagree significantly, pause operations or use the more conservative value.

**6. Circuit breakers.** If the price changes by more than X% in a single update, pause the protocol and require manual review. Aave implements price deviation checks that can trigger sentinel alerts.

**7. For TWAP: require sufficient observation window.** A 30-minute minimum is generally recommended. Shorter windows are cheaper to manipulate.

**8. For internal accounting: use virtual offsets.** The ERC-4626 inflation attack is defended by initializing vaults with a virtual offset (e.g., minting dead shares to the zero address), preventing the "first depositor" attack.

### Build: Oracle Manipulation Lab

**Exercise 1: Build the vulnerable protocol.** Create a simple lending contract that reads spot price from a Uniswap V2 pool. Deploy the pool, the lending contract, and demonstrate the attack:
- Fund the pool with initial liquidity
- Take a flash loan (or use `vm.deal` to simulate capital)
- Swap to manipulate the spot price
- Deposit collateral at the inflated valuation
- Borrow more than the collateral is actually worth
- Swap back to restore the price
- Show the protocol is now undercollateralized

**Exercise 2: Fix the vulnerability.** Replace the spot price oracle with your Chainlink consumer from Day 1. Re-run the attack — it should fail because Chainlink's price doesn't move in response to the attacker's DEX swap.

**Exercise 3: TWAP attack cost analysis.** Using your TWAP oracle from Day 2, calculate (on paper or in a test): how much capital would an attacker need to sustain a 10% price manipulation over a 30-minute window, given a pool with $10 million TVL? How much would they lose to arbitrageurs? This exercise builds intuition for TWAP security margins.

**Exercise 4: Stale price exploit.** Using a mainnet fork, mock a Chainlink feed going stale (use `vm.mockCall` to return old `updatedAt`). Show how a protocol without staleness checks can be exploited when the real market price has moved significantly.

---

## Key Takeaways for Protocol Builders

1. **The oracle is your protocol's weakest link.** A perfectly written smart contract using bad price data is just as exploitable as a buggy contract. Oracle choice and integration deserve as much attention as your core logic.

2. **Never derive prices from spot ratios in DEX pools.** This rule has no exceptions for protocols where incorrect prices lead to financial loss.

3. **Always validate oracle data.** At minimum: positive answer, complete round, fresh timestamp. Optionally: price within historical bounds, cross-reference with secondary source.

4. **Chainlink is the default for production protocols.** It's not perfect (heartbeat lag, centralization concerns), but it's the most battle-tested option. Supplement with TWAP or other sources for defense in depth.

5. **Design for oracle failure.** What happens if your oracle goes down entirely? Your protocol needs a graceful degradation path — pause operations, use a fallback source, or enter a safe mode.

6. **L2 sequencer awareness.** If deploying on Arbitrum, Optimism, or other L2s with a sequencer, always check the Sequencer Uptime Feed before trusting price data.

---

## Resources

**Chainlink documentation:**
- Data Feeds overview: https://docs.chain.link/data-feeds
- Using Data Feeds: https://docs.chain.link/data-feeds/using-data-feeds
- Feed addresses: https://docs.chain.link/data-feeds/price-feeds/addresses
- L2 Sequencer Uptime Feeds: https://docs.chain.link/data-feeds/l2-sequencer-feeds
- API Reference: https://docs.chain.link/data-feeds/api-reference

**Oracle security:**
- Cyfrin — Price Oracle Manipulation Attacks: https://www.cyfrin.io/blog/price-oracle-manipulation-attacks-with-examples
- Cyfrin — Solodit Checklist: Price Manipulation: https://www.cyfrin.io/blog/solodit-checklist-explained-7-price-manipulation-attacks
- Three Sigma — 2024 Most Exploited DeFi Vulnerabilities: https://threesigma.xyz/blog/exploit/2024-defi-exploits-top-vulnerabilities
- Chainalysis — Oracle Manipulation Attacks Rising: https://www.chainalysis.com/blog/oracle-manipulation-attacks-rising/
- CertiK — Oracle Wars: https://www.certik.com/resources/blog/oracle-wars-the-rise-of-price-manipulation-attacks

**TWAP oracles:**
- Uniswap V3 oracle documentation: https://docs.uniswap.org/concepts/protocol/oracle
- Uniswap V3 Math Primer Part 2 (oracle section): https://blog.uniswap.org/uniswap-v3-math-primer-2

**Hands-on:**
- Oracle manipulation walkthrough (Foundry): https://github.com/calvwang9/oracle-manipulation

---

## Practice Challenges

- **Damn Vulnerable DeFi #7 "Compromised"** — An oracle whose private keys are leaked, enabling price manipulation. Tests your understanding of oracle trust models and the consequences of compromised price feeds.

---

*Next module: Lending & Borrowing — supply/borrow model, collateral factors, interest rate curves, health factors, liquidation mechanics. This module will heavily use everything you've learned about oracles.*

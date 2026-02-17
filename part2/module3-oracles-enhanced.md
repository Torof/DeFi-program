# Part 2 — Module 3: Oracles

**Duration:** ~3 days (3–4 hours/day)
**Prerequisites:** Modules 1–2 complete (token mechanics, AMM math and architecture)
**Pattern:** Concept → Read production integrations → Build safe consumer → Attack and defend
**Builds on:** Module 2 (TWAP oracle from AMM price accumulators), Part 1 Section 5 (fork testing with real Chainlink feeds)
**Used by:** Module 4 (lending collateral valuation, liquidation triggers), Module 6 (CDP liquidation triggers), Module 9 (integration capstone)

---

## Why Oracles Matter for Protocol Builders

**Why this matters:** DeFi protocols that only swap tokens can derive prices from their own reserves. But the moment you build anything that references the value of an asset — lending (what's the collateral worth?), derivatives (what's the settlement price?), stablecoins (is this position undercollateralized?) — you need external price data.

**The problem:** Blockchains are deterministic and isolated. They can't fetch data from the outside world. Oracles bridge this gap, but in doing so, they become the single most attacked surface in DeFi.

> **Real impact:** Oracle manipulation accounted for [$403 million in losses in 2022](https://www.chainalysis.com/blog/oracle-manipulation-attacks-rising/), [$52 million across 37 incidents in 2024](https://threesigma.xyz/blog/exploit/2024-defi-exploits-top-vulnerabilities), and continues to be the second most damaging attack vector after private key compromises.

**Major oracle-related exploits:**
- [Mango Markets](https://rekt.news/mango-markets-rekt/) ($114M, October 2022) — centralized oracle manipulation
- [Polter Finance](https://rekt.news/polter-finance-rekt/) ($12M, July 2024) — Chainlink-Uniswap adapter exploit
- [Cream Finance](https://rekt.news/cream-rekt-2/) ($130M, October 2021) — oracle price manipulation via yUSD
- [Harvest Finance](https://rekt.news/harvest-finance-rekt/) ($24M, October 2020) — TWAP manipulation via flash loans
- [Inverse Finance](https://rekt.news/inverse-rekt/) ($15M, June 2022) — oracle manipulation via Curve pool

If you're building a protocol that uses price data, oracle security is not optional — it's existential.

This module teaches you to consume oracle data safely and understand the attack surface deeply enough to defend against it.

---

## Day 1: Oracle Fundamentals and Chainlink Architecture

### The Oracle Problem

**Why this matters:** Smart contracts execute deterministically — given the same state and input, they always produce the same output. This is a feature (consensus depends on it), but it means contracts can't natively access off-chain data like asset prices, weather, sports scores, or API results.

An oracle is any mechanism that feeds external data into a smart contract. The critical question is always: **who or what can you trust to provide accurate data, and what happens if that trust is violated?**

> **Deep dive:** [Vitalik Buterin on oracle problem](https://blog.ethereum.org/2014/03/28/schellingcoin-a-minimal-trust-universal-data-feed), [Chainlink whitepaper](https://chain.link/whitepaper) (original 2017 version outlines decentralized oracle vision)

---

### Types of Price Oracles

**1. Centralized oracles** — A single entity publishes price data on-chain. Simple, fast, but a single point of failure. If the entity goes down, gets hacked, or acts maliciously, every protocol depending on it breaks.

> **Real impact:** [Mango Markets](https://rekt.news/mango-markets-rekt/) ($114M, October 2022) used FTX/Serum as part of its price source — a centralized exchange that later collapsed. The attacker manipulated Mango's own oracle by trading against himself on low-liquidity markets, inflating collateral value.

**2. On-chain oracles (DEX-based)** — Derive price from AMM reserves. The spot price in a Uniswap pool is `reserve1 / reserve0`. Free to read, no external dependency, but trivially manipulable with a large trade or flash loan.

> **Why this matters:** Using raw spot price as an oracle is essentially asking to be exploited. This is the #1 oracle vulnerability.

> **Real impact:** [Harvest Finance](https://rekt.news/harvest-finance-rekt/) ($24M, October 2020) — attacker flash-loaned USDT and USDC, swapped massively in Curve pools to manipulate price, exploited Harvest's vault share price calculation, then unwound the trade. All in one transaction.

**3. TWAP oracles** — Time-weighted average price computed from on-chain data over a window (e.g., 30 minutes). Resistant to single-block manipulation because the attacker would need to sustain the manipulated price across many blocks.

**Trade-off:** The price lags behind the real market, which can be exploited during high volatility.

> **Used by:** [MakerDAO OSM](https://github.com/makerdao/osm) (Oracle Security Module) uses 1-hour delayed medianized TWAP, [Reflexer RAI](https://github.com/reflexer-labs/geb) uses Uniswap V2 TWAP, [Liquity LUSD](https://github.com/liquity/dev) uses Chainlink + Tellor fallback.

**4. Decentralized oracle networks (Chainlink, Pyth, Redstone)** — Multiple independent nodes fetch prices from multiple data sources, aggregate them, and publish the result on-chain.

**The most robust option for most use cases**, but introduces latency, update frequency considerations, and trust in the oracle network itself.

> **Real impact:** [Chainlink secures $15B+ in DeFi TVL](https://data.chain.link/) (2024), used by [Aave](https://github.com/aave/aave-v3-core), [Compound](https://github.com/compound-finance/open-oracle), [Synthetix](https://github.com/Synthetixio/synthetix), and most major protocols.

---

### Chainlink Architecture Deep Dive

**Why this matters:** [Chainlink](https://chain.link/) is the dominant oracle provider in DeFi, securing hundreds of billions in value. Understanding its architecture is essential.

**Three-layer design:**

**Layer 1: Data providers** — Premium data aggregators (e.g., [CoinGecko](https://www.coingecko.com/), [CoinMarketCap](https://coinmarketcap.com/), [Kaiko](https://www.kaiko.com/), [Amberdata](https://www.amberdata.io/)) aggregate raw price data from centralized and decentralized exchanges, filtering for outliers, wash trading, and stale data.

**Layer 2: Chainlink nodes** — Independent node operators fetch data from multiple providers. Each node produces its own price observation. Nodes are selected for reputation, reliability, and stake. The node set for a given feed (e.g., [ETH/USD](https://data.chain.link/ethereum/mainnet/crypto-usd/eth-usd)) typically includes 15–31 nodes.

**Layer 3: On-chain aggregation** — Nodes submit observations to an on-chain Aggregator contract. The contract computes the **median** of all observations and publishes it as the feed's answer.

> **Why this matters:** The median is key — it's resistant to outliers, meaning a minority of compromised nodes can't skew the result. [Byzantine fault tolerance](https://docs.chain.link/architecture-overview/architecture-decentralized-model#aggregation) requires <50% honest nodes.

**Offchain Reporting (OCR):** Rather than each node submitting a separate on-chain transaction (expensive), Chainlink uses [OCR](https://docs.chain.link/architecture-overview/off-chain-reporting): nodes agree on a value off-chain and submit a single aggregated report with all signatures. This dramatically reduces gas costs (~90% reduction vs pre-OCR).

> **Deep dive:** [OCR documentation](https://docs.chain.link/architecture-overview/off-chain-reporting), [OCR 2.0 announcement](https://blog.chain.link/off-chain-reporting-live-on-mainnet/) (April 2021)

**Update triggers:**

Feeds don't update continuously. They update when either condition is met:
- **Deviation threshold:** The off-chain value deviates from the on-chain value by more than X% (typically 0.5% for major pairs, 1% for others)
- **Heartbeat:** A maximum time between updates regardless of price movement (typically 1 hour for major pairs, up to 24 hours for less active feeds)

> **Common pitfall:** Assuming Chainlink prices are real-time. The on-chain price can be up to [deviation threshold] stale at any moment. Your protocol MUST account for this.

> **Example:** [ETH/USD feed](https://data.chain.link/ethereum/mainnet/crypto-usd/eth-usd) has 0.5% deviation threshold and 1-hour heartbeat. If ETH price is stable, the feed may not update for the full hour. If ETH drops 0.4%, the feed won't update until the heartbeat expires or deviation crosses 0.5%.

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

The [Proxy layer](https://docs.chain.link/architecture-overview/architecture-decentralized-model#proxy) is critical — it allows Chainlink to upgrade the underlying Aggregator (change node set, update parameters) without breaking consumer contracts. Your protocol should always point to the Proxy address, never directly to an Aggregator.

> **Common pitfall:** Hardcoding the Aggregator address instead of using the Proxy. When Chainlink upgrades the feed, your protocol breaks. Always use the proxy address from [Chainlink's feed registry](https://docs.chain.link/data-feeds/price-feeds/addresses).

---

### Read: AggregatorV3Interface

**Source:** [@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol](https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)

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

> **Common pitfall:** Hardcoding `decimals` to 8. Some feeds use 18 decimals (e.g., [ETH/BTC](https://data.chain.link/ethereum/mainnet/crypto-eth/btc-eth)). Always call `decimals()` dynamically.

> **Used by:** [Aave V3 AaveOracle](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol#L107), [Compound V3 price feeds](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L1095), [Synthetix ExchangeRates](https://github.com/Synthetixio/synthetix/blob/develop/contracts/ExchangeRates.sol)

---

### Build: Safe Chainlink Consumer

**Exercise 1: Build an `OracleConsumer.sol`** that reads Chainlink price feeds with proper safety checks:

```solidity
// ✅ GOOD: Comprehensive safety checks
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

    // Optional CHECK 4: answeredInRound >= roundId
    // Ensures the round is finalized and not from a previous round
    require(answeredInRound >= roundId, "Stale round");

    return uint256(answer);
}
```

**All three checks are mandatory.** Protocols that skip any of them have been exploited. The staleness check is the most commonly omitted — and the most dangerous.

> **Real impact:** [Venus Protocol on BSC](https://rekt.news/venus-blizz-rekt/) ($11M, May 2023) — oracle didn't update for hours due to BSC network issues, allowed borrowing against stale collateral prices.

> **Common pitfall:** Setting `MAX_STALENESS` too loosely. If the feed heartbeat is 1 hour, setting `MAX_STALENESS = 24 hours` defeats the purpose. Use `heartbeat + buffer` (e.g., 1 hour + 15 minutes = 4500 seconds).

**Exercise 2: Multi-feed price derivation.** Build a function that computes ETH/EUR by combining [ETH/USD](https://data.chain.link/ethereum/mainnet/crypto-usd/eth-usd) and [EUR/USD](https://data.chain.link/ethereum/mainnet/fiat-usd/eur-usd) feeds. Handle decimal normalization (both feeds may have different `decimals()` values).

```solidity
// Compute ETH/EUR from ETH/USD and EUR/USD
function getETHEURPrice(address ethUsdFeed, address eurUsdFeed) public view returns (uint256) {
    uint256 ethUsdPrice = getPrice(ethUsdFeed);
    uint256 ethUsdDecimals = AggregatorV3Interface(ethUsdFeed).decimals();

    uint256 eurUsdPrice = getPrice(eurUsdFeed);
    uint256 eurUsdDecimals = AggregatorV3Interface(eurUsdFeed).decimals();

    // ETH/EUR = (ETH/USD) / (EUR/USD)
    // Normalize decimals to avoid precision loss
    uint256 ethEurPrice = (ethUsdPrice * 10**eurUsdDecimals) / eurUsdPrice;

    return ethEurPrice; // Price in EUR with ethUsdDecimals decimals
}
```

> **Common pitfall:** Not accounting for different decimal bases when combining feeds. This can cause 10^10 errors in calculations.

**Exercise 3: L2 sequencer check.** On L2 networks (Arbitrum, Optimism, Base), the sequencer can go down. During downtime, Chainlink feeds appear fresh but may be using stale data. Chainlink provides [L2 Sequencer Uptime Feeds](https://docs.chain.link/data-feeds/l2-sequencer-feeds). Build a consumer that checks sequencer status before reading price data:

```solidity
// ✅ GOOD: Check L2 sequencer status before reading price
function isSequencerUp(address sequencerFeed) internal view returns (bool) {
    (, int256 answer, , uint256 startedAt, ) =
        AggregatorV3Interface(sequencerFeed).latestRoundData();

    // answer == 0 means sequencer is up, 1 means it's down
    bool isUp = answer == 0;
    require(isUp, "Sequencer down");

    // Even if up, enforce a grace period after recovery
    // to let feeds catch up to real prices
    uint256 timeSinceUp = block.timestamp - startedAt;
    require(timeSinceUp > GRACE_PERIOD, "Grace period not over");

    return true;
}
```

> **Why this matters:** When an L2 sequencer goes down, transactions stop processing. Chainlink feeds on L2 rely on the sequencer to post updates. If the sequencer is down for hours, the last posted price may be very stale even if `updatedAt` appears recent (relative to L2 time). [Arbitrum sequencer uptime feed](https://docs.chain.link/data-feeds/l2-sequencer-feeds#arbitrum).

> **Used by:** [Aave V3 on Arbitrum](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol) checks sequencer uptime, [GMX V2](https://github.com/gmx-io/gmx-synthetics) on Arbitrum and Avalanche

**Exercise 4: Foundry tests using mainnet fork.** Fork Ethereum mainnet with `forge test --fork-url <RPC>` and read real Chainlink feeds. Verify your consumer returns sane values for [ETH/USD](https://data.chain.link/ethereum/mainnet/crypto-usd/eth-usd), [BTC/USD](https://data.chain.link/ethereum/mainnet/crypto-usd/btc-usd). Use `vm.warp()` to simulate staleness conditions and verify your checks revert correctly.

```solidity
function testStalenessCheck() public {
    vm.createSelectFork(mainnetRpcUrl);
    address ethUsdFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD mainnet

    // Should work with fresh data
    uint256 price = oracle.getPrice(ethUsdFeed);
    assertGt(price, 0);

    // Fast forward past staleness threshold
    vm.warp(block.timestamp + MAX_STALENESS + 1);

    // Should revert due to staleness
    vm.expectRevert("Stale price");
    oracle.getPrice(ethUsdFeed);
}
```

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

**The key property:** A flash loan attacker can manipulate the spot price for one block, but that only affects the cumulative sum for ~12 seconds (one block). Over a 30-minute TWAP window, one manipulated block contributes only ~0.7% of the average. The attacker would need to sustain the manipulation for the entire window — which means holding a massive position across many blocks, paying gas, and taking on enormous market risk.

> **Deep dive:** [Uniswap V2 oracle guide](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/building-an-oracle), [TWAP security analysis](https://samczsun.com/so-you-want-to-use-a-price-oracle/)

---

**Uniswap V2 TWAP:**
- [`price0CumulativeLast` / `price1CumulativeLast`](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L79) in the pair contract
- Updated on every `swap()`, `mint()`, or `burn()`
- Uses [UQ112.112 fixed-point](https://github.com/Uniswap/v2-core/blob/master/contracts/libraries/UQ112x112.sol) for precision
- The cumulative values are designed to overflow safely (unsigned integer wrapping)
- External contracts must snapshot these values at two points in time and compute the difference

> **Used by:** [MakerDAO OSM](https://github.com/makerdao/osm) uses medianized V2 TWAP, [Reflexer RAI](https://github.com/reflexer-labs/geb-fsm) uses V2 TWAP with 1-hour delay

**Uniswap V3 TWAP:**
- More sophisticated: uses an [`observations` array](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/Oracle.sol) (ring buffer) storing `(timestamp, tickCumulative, liquidityCumulative)`
- Can return TWAP for any window up to the observation buffer length
- Built-in [`observe()` function](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol#L188) computes TWAP ticks directly
- The TWAP is in tick space (geometric mean), not arithmetic mean — more resistant to manipulation

> **Why this matters:** Geometric mean TWAP is harder to manipulate than arithmetic mean. An attacker who moves the price by 100x for 1 second and 0.01x for 1 second averages to 1x in geometric mean (√(100 × 0.01) = 1), but 50x in arithmetic mean ((100 + 0.01)/2 ≈ 50).

> **Deep dive:** [Uniswap V3 oracle documentation](https://docs.uniswap.org/concepts/protocol/oracle), [V3 Math Primer Part 2](https://blog.uniswap.org/uniswap-v3-math-primer-2)

**V4 TWAP:**
- V4 removed the built-in oracle. TWAP is now implemented via hooks (e.g., the [Geomean Oracle hook](https://github.com/Uniswap/v4-periphery/blob/main/src/hooks/examples/GeomeanOracle.sol)).
- This gives more flexibility but means protocols need to find or build the appropriate hook.

---

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

> **Used by:** [Liquity](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol) uses Chainlink primary + Tellor fallback, [Maker's OSM](https://github.com/makerdao/osm) uses delayed TWAP, [Euler](https://github.com/euler-xyz/euler-contracts/blob/master/contracts/modules/EulDistributor.sol) used Uniswap V3 TWAP (before Euler relaunch).

---

### Build: TWAP Oracle

**Exercise 1: Build a TWAP oracle contract** that:
- Stores periodic price observations (price, timestamp) from a Uniswap V2 pair
- Exposes a `consult()` function that returns the TWAP over a configurable window
- Handles the case where insufficient observations exist (revert with clear error)
- Uses proper fixed-point arithmetic to avoid precision loss

```solidity
// Example: Simple TWAP oracle for Uniswap V2
contract SimpleTWAP {
    IUniswapV2Pair public pair;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;

    function update() external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        require(timeElapsed >= PERIOD, "Period not elapsed");

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        require(timeElapsed >= MINIMUM_WINDOW, "Window too short");

        uint256 priceCumulative = (token == pair.token0()) ? price0Cumulative : price1Cumulative;
        uint256 priceCumulativeLast = (token == pair.token0()) ? price0CumulativeLast : price1CumulativeLast;

        // TWAP = ΔpriceCumulative / Δtime
        uint256 priceAverage = (priceCumulative - priceCumulativeLast) / timeElapsed;
        amountOut = (amountIn * priceAverage) >> 112; // UQ112.112 fixed-point division
    }
}
```

> **Common pitfall:** Not enforcing a minimum window size. If `timeElapsed` is very small (e.g., 1 block), the TWAP degenerates to near-spot price and becomes manipulable.

**Exercise 2: Compare TWAP to spot.** Deploy a pool, execute swaps that move the price dramatically, then compare the TWAP (over 10 blocks) to the current spot price. Verify the TWAP lags behind the spot — this lag is the trade-off for manipulation resistance.

**Exercise 3: Dual oracle pattern.** Build a `DualOracle.sol` that:
- Reads Chainlink as the primary source
- Reads TWAP as the secondary source
- Reverts if the two sources disagree by more than a configurable threshold (e.g., 5%)
- Falls back to TWAP if the Chainlink feed is stale
- Emits an event when switching sources

```solidity
// ✅ GOOD: Dual oracle with fallback
function getPrice() public view returns (uint256) {
    uint256 chainlinkPrice;
    bool chainlinkFresh = true;

    try this.getChainlinkPrice() returns (uint256 price) {
        chainlinkPrice = price;
    } catch {
        chainlinkFresh = false;
    }

    uint256 twapPrice = getTWAPPrice();

    if (chainlinkFresh) {
        // Verify Chainlink and TWAP agree
        uint256 deviation = chainlinkPrice > twapPrice
            ? (chainlinkPrice - twapPrice) * 100 / twapPrice
            : (twapPrice - chainlinkPrice) * 100 / chainlinkPrice;

        require(deviation <= MAX_DEVIATION, "Oracle mismatch");
        return chainlinkPrice; // Use Chainlink as primary
    } else {
        emit FallbackToTWAP();
        return twapPrice; // Fallback to TWAP
    }
}
```

This dual-oracle pattern is used in production by protocols like [Liquity](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol).

> **Deep dive:** [Liquity PriceFeed.sol](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol) — implements Chainlink primary, Tellor fallback, with deviation checks

---

## Day 3: Oracle Manipulation Attacks

### The Attack Surface

**Why this matters:** Oracle manipulation is a category of attacks where the attacker corrupts the price data that a protocol relies on, then exploits the protocol's reaction to the false price. The protocol code executes correctly — it just operates on poisoned inputs.

> **Real impact:** Oracle manipulation is responsible for more DeFi losses than any other attack vector except private key compromises. Understanding these attacks is not optional for protocol developers.

---

### Attack Pattern 1: Spot Price Manipulation via Flash Loan

**This is the most common oracle attack.** The target: any protocol that reads spot price from a DEX pool.

**The attack flow:**

1. Attacker takes a flash loan of Token A (millions of dollars worth)
2. Attacker swaps Token A → Token B in a DEX pool, massively moving the spot price
3. Attacker interacts with the victim protocol, which reads the manipulated spot price
   - If lending protocol: deposit Token B as collateral (now valued at inflated price), borrow other assets far exceeding collateral's true value
   - If vault: trigger favorable exchange rate calculation
4. Attacker swaps Token B back → Token A in the DEX, restoring the price
5. Attacker repays the flash loan
6. **All within a single transaction** — profit extracted, protocol drained

**Why it works:** The victim protocol uses `reserve1 / reserve0` (spot price) as its oracle. A flash loan can move this ratio arbitrarily within a single block, and the protocol reads it in the same block.

> **Real impact:** [Harvest Finance](https://rekt.news/harvest-finance-rekt/) ($24M, October 2020) — attacker flash-loaned USDT and USDC, swapped massively in Curve pools to manipulate price, exploited Harvest's vault share price calculation (which used Curve pool reserves), then unwound the trade. Loss: $24M.

> **Real impact:** [Cream Finance](https://rekt.news/cream-rekt-2/) ($130M, October 2021) — attacker flash-loaned yUSD, manipulated Curve pool price oracle that Cream used for collateral valuation, borrowed against inflated collateral. Loss: $130M.

> **Real impact:** [Inverse Finance](https://rekt.news/inverse-rekt/) ($15M, June 2022) — attacker manipulated Curve pool oracle (used by Inverse for collateral pricing), deposited INV at inflated value, borrowed stables. Loss: $15.6M.

**Example code (VULNERABLE):**

```solidity
// ❌ VULNERABLE: Using spot price as oracle
function getCollateralValue(address token, uint256 amount) public view returns (uint256) {
    IUniswapV2Pair pair = IUniswapV2Pair(getPair(token, WETH));
    (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

    // Spot price = reserve1 / reserve0
    uint256 price = (reserve1 * 1e18) / reserve0;
    return amount * price / 1e18;
}
```

**This code will be exploited.** Do not use spot price as an oracle.

---

### Attack Pattern 2: TWAP Manipulation (Multi-Block)

TWAP oracles resist single-block attacks, but they're not immune. An attacker with sufficient capital (or who can bribe block producers) can sustain a manipulated price across the TWAP window.

**The economics:** To manipulate a 30-minute TWAP by 10%, the attacker needs to sustain a 10% price deviation for 150 blocks (at 12s/block). This means holding a massive position that continuously loses to arbitrageurs. The cost of the attack = arbitrageur profits + opportunity cost + gas. For high-liquidity pools, this cost is prohibitive. For low-liquidity pools, it can be economical.

> **Real impact:** While single-transaction TWAP manipulation is rare, low-liquidity pools with short TWAP windows have been exploited. [Rari Capital Fuse](https://rekt.news/rari-capital-rekt/) ($80M, May 2022) — though primarily a reentrancy exploit, used oracle manipulation on low-liquidity pairs.

**Multi-block MEV:** With validator-level access (e.g., block builder who controls consecutive blocks), TWAP manipulation becomes cheaper because the attacker can exclude arbitrageur transactions. This is an active area of research and concern.

> **Deep dive:** [Flashbots MEV research](https://github.com/flashbots/mev-research), [Multi-block MEV](https://collective.flashbots.net/t/multi-block-mev/457)

---

### Attack Pattern 3: Stale Oracle Exploitation

If a Chainlink feed hasn't updated (due to network congestion, gas price spikes, or feed misconfiguration), the on-chain price may lag significantly behind the real market price. An attacker can exploit the stale price:

- If the real price of ETH has dropped 20% but the oracle still shows the old price, the attacker can deposit ETH as collateral at the stale (higher) valuation and borrow against it
- When the oracle finally updates, the position is undercollateralized, and the protocol absorbs the loss

**This is why your staleness check from Day 1 is critical.**

> **Real impact:** [Venus Protocol on BSC](https://rekt.news/venus-blizz-rekt/) ($11M, May 2023) — Binance Smart Chain network issues caused Chainlink oracles to stop updating for hours. Attacker borrowed against stale collateral prices. When prices updated, positions were deeply undercollateralized. Loss: $11M.

> **Real impact:** [Arbitrum sequencer downtime](https://status.arbitrum.io/) (December 2023) — 78-minute sequencer outage. Protocols without sequencer uptime checks could have been exploited (none were, but it demonstrated the risk).

---

### Attack Pattern 4: Donation/Direct Balance Manipulation

Some protocols calculate prices based on internal token balances (e.g., vault share prices based on `totalAssets() / totalShares()`). An attacker can send tokens directly to the contract (bypassing `deposit()`), inflating the perceived value per share. This is related to the "inflation attack" on ERC-4626 vaults (covered in Module 7).

> **Real impact:** [Euler Finance](https://rekt.news/euler-rekt/) ($197M, March 2023) — though primarily a donation attack exploiting incorrect health factor calculations, demonstrated how direct balance manipulation can bypass protocol accounting. Loss: $197M.

**Example (VULNERABLE):**

```solidity
// ❌ VULNERABLE: Using balance for price calculation
function getPricePerShare() public view returns (uint256) {
    uint256 totalAssets = token.balanceOf(address(this));
    uint256 totalShares = totalSupply;
    return totalAssets * 1e18 / totalShares;
}
```

Attacker can donate tokens directly, inflating `totalAssets` without minting shares.

---

### Defense Patterns

**1. Never use DEX spot price as an oracle.** This is the single most important rule. If your protocol reads `reserve1 / reserve0` as a price, it will be exploited.

```solidity
// ❌ NEVER DO THIS
uint256 price = (reserve1 * 1e18) / reserve0;

// ✅ DO THIS INSTEAD
uint256 price = getChainlinkPrice(priceFeed);
```

**2. Use Chainlink or equivalent decentralized oracle networks** for any high-stakes price dependency (collateral valuation, liquidation triggers, settlement).

**3. Implement staleness checks** on every oracle read. Choose your `MAX_STALENESS` based on the feed's heartbeat — if the heartbeat is 1 hour, a staleness threshold of 1 hour + buffer is reasonable.

```solidity
// ✅ GOOD: Staleness check
require(block.timestamp - updatedAt < MAX_STALENESS, "Stale price");
```

**4. Validate the answer is sane.** Check that the price is positive, non-zero, and optionally within a reasonable range compared to historical data or a secondary source.

```solidity
// ✅ GOOD: Sanity checks
require(answer > 0, "Invalid price");
require(answer < MAX_PRICE, "Price too high"); // Optional: circuit breaker
```

**5. Use dual/multi-oracle patterns.** Cross-reference Chainlink with TWAP. If they disagree significantly, pause operations or use the more conservative value.

> **Used by:** [Aave V3](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol) uses Chainlink with fallback sources, [Compound V3](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) uses primary + backup feeds

**6. Circuit breakers.** If the price changes by more than X% in a single update, pause the protocol and require manual review. [Aave implements price deviation checks](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol) that can trigger sentinel alerts.

**7. For TWAP: require sufficient observation window.** A 30-minute minimum is generally recommended. Shorter windows are cheaper to manipulate.

```solidity
// ✅ GOOD: Enforce minimum TWAP window
uint32 timeElapsed = blockTimestamp - blockTimestampLast;
require(timeElapsed >= MINIMUM_WINDOW, "Window too short"); // e.g., 1800 seconds = 30 min
```

**8. For internal accounting: use virtual offsets.** The ERC-4626 inflation attack is defended by initializing vaults with a virtual offset (e.g., minting dead shares to the zero address), preventing the "first depositor" attack.

> **Deep dive:** [ERC-4626 inflation attack analysis](https://mixbytes.io/blog/overview-of-the-inflation-attack), [OpenZeppelin ERC4626 security](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol#L30-L40)

---

### Build: Oracle Manipulation Lab

**Exercise 1: Build the vulnerable protocol.** Create a simple lending contract that reads spot price from a Uniswap V2 pool. Deploy the pool, the lending contract, and demonstrate the attack:
- Fund the pool with initial liquidity
- Take a flash loan (or use `vm.deal` to simulate capital)
- Swap to manipulate the spot price
- Deposit collateral at the inflated valuation
- Borrow more than the collateral is actually worth
- Swap back to restore the price
- Show the protocol is now undercollateralized

```solidity
// Vulnerable lending protocol (for educational purposes)
contract VulnerableLending {
    function getCollateralValue(address token, uint256 amount) public view returns (uint256) {
        // ❌ VULNERABLE: Using spot price
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token, WETH));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 spotPrice = (reserve1 * 1e18) / reserve0;
        return amount * spotPrice / 1e18;
    }
}

// Attacker contract
contract Attacker {
    function attack() external {
        // 1. Flash loan Token A
        // 2. Swap A → B (manipulate price up)
        // 3. Deposit B as collateral (now valued at inflated price)
        // 4. Borrow maximum based on inflated value
        // 5. Swap B → A (restore price)
        // 6. Repay flash loan
        // 7. Keep borrowed funds - profit!
    }
}
```

**Exercise 2: Fix the vulnerability.** Replace the spot price oracle with your Chainlink consumer from Day 1. Re-run the attack — it should fail because Chainlink's price doesn't move in response to the attacker's DEX swap.

```solidity
// ✅ FIXED: Using Chainlink
function getCollateralValue(address token, uint256 amount) public view returns (uint256) {
    address priceFeed = priceFeedRegistry[token];
    uint256 price = getChainlinkPrice(priceFeed);
    return amount * price / 1e18;
}
```

**Exercise 3: TWAP attack cost analysis.** Using your TWAP oracle from Day 2, calculate (on paper or in a test): how much capital would an attacker need to sustain a 10% price manipulation over a 30-minute window, given a pool with $10 million TVL? How much would they lose to arbitrageurs? This exercise builds intuition for TWAP security margins.

**Exercise 4: Stale price exploit.** Using a mainnet fork, mock a Chainlink feed going stale (use `vm.mockCall` to return old `updatedAt`). Show how a protocol without staleness checks can be exploited when the real market price has moved significantly.

```solidity
function testStaleOracleExploit() public {
    vm.createSelectFork(mainnetRpcUrl);

    // Mock Chainlink returning stale price
    uint256 stalePrice = 3000e8; // $3000
    uint256 staleTimestamp = block.timestamp - 3 hours; // Very stale

    vm.mockCall(
        ethUsdFeed,
        abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
        abi.encode(1, int256(stalePrice), 0, staleTimestamp, 1)
    );

    // Protocol without staleness check accepts this
    // Attacker can deposit collateral at stale $3000 when real price is $2400
    // Then borrow against inflated value
}
```

---

## Key Takeaways for Protocol Builders

**1. The oracle is your protocol's weakest link.** A perfectly written smart contract using bad price data is just as exploitable as a buggy contract. Oracle choice and integration deserve as much attention as your core logic.

**2. Never derive prices from spot ratios in DEX pools.** This rule has no exceptions for protocols where incorrect prices lead to financial loss.

```solidity
// ❌ NEVER DO THIS
uint256 price = reserve1 / reserve0;

// ✅ DO THIS
uint256 price = chainlinkFeed.latestRoundData().answer;
```

**3. Always validate oracle data.** At minimum: positive answer, complete round, fresh timestamp. Optionally: price within historical bounds, cross-reference with secondary source.

**4. Chainlink is the default for production protocols.** It's not perfect (heartbeat lag, centralization concerns), but it's the most battle-tested option. Supplement with TWAP or other sources for defense in depth.

**5. Design for oracle failure.** What happens if your oracle goes down entirely? Your protocol needs a graceful degradation path — pause operations, use a fallback source, or enter a safe mode.

**6. L2 sequencer awareness.** If deploying on Arbitrum, Optimism, Base, or other L2s with a sequencer, always check the [Sequencer Uptime Feed](https://docs.chain.link/data-feeds/l2-sequencer-feeds) before trusting price data.

---

## Resources

**Chainlink documentation:**
- [Data Feeds overview](https://docs.chain.link/data-feeds)
- [Using Data Feeds](https://docs.chain.link/data-feeds/using-data-feeds)
- [Feed addresses](https://docs.chain.link/data-feeds/price-feeds/addresses) — mainnet, testnet, all chains
- [L2 Sequencer Uptime Feeds](https://docs.chain.link/data-feeds/l2-sequencer-feeds) — Arbitrum, Optimism, Base
- [API Reference](https://docs.chain.link/data-feeds/api-reference)
- [OCR documentation](https://docs.chain.link/architecture-overview/off-chain-reporting)

**Oracle security:**
- [Cyfrin — Price Oracle Manipulation Attacks](https://www.cyfrin.io/blog/price-oracle-manipulation-attacks-with-examples)
- [Cyfrin — Solodit Checklist: Price Manipulation](https://www.cyfrin.io/blog/solodit-checklist-explained-7-price-manipulation-attacks)
- [Three Sigma — 2024 Most Exploited DeFi Vulnerabilities](https://threesigma.xyz/blog/exploit/2024-defi-exploits-top-vulnerabilities)
- [Chainalysis — Oracle Manipulation Attacks Rising](https://www.chainalysis.com/blog/oracle-manipulation-attacks-rising/)
- [CertiK — Oracle Wars](https://www.certik.com/resources/blog/oracle-wars-the-rise-of-price-manipulation-attacks)
- [samczsun — So you want to use a price oracle](https://samczsun.com/so-you-want-to-use-a-price-oracle/) — comprehensive guide

**TWAP oracles:**
- [Uniswap V3 oracle documentation](https://docs.uniswap.org/concepts/protocol/oracle)
- [Uniswap V3 Math Primer Part 2](https://blog.uniswap.org/uniswap-v3-math-primer-2) — oracle section
- [Uniswap V2 oracle guide](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/building-an-oracle)
- [TWAP manipulation cost analysis](https://cmichel.io/pricing-lp-tokens/)

**Production examples:**
- [Aave V3 AaveOracle.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol) — Chainlink primary, fallback logic
- [Compound V3 Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — price feed integration
- [Liquity PriceFeed.sol](https://github.com/liquity/dev/blob/main/packages/contracts/contracts/PriceFeed.sol) — Chainlink + Tellor dual oracle
- [MakerDAO OSM](https://github.com/makerdao/osm) — delayed medianized TWAP

**Hands-on:**
- [Oracle manipulation walkthrough (Foundry)](https://github.com/calvwang9/oracle-manipulation)

**Exploits and postmortems:**
- [Mango Markets postmortem](https://rekt.news/mango-markets-rekt/) — $114M oracle manipulation
- [Polter Finance postmortem](https://rekt.news/polter-finance-rekt/) — $12M Chainlink-Uniswap adapter exploit
- [Cream Finance postmortem](https://rekt.news/cream-rekt-2/) — $130M oracle manipulation
- [Harvest Finance postmortem](https://rekt.news/harvest-finance-rekt/) — $24M flash loan TWAP manipulation
- [Inverse Finance postmortem](https://rekt.news/inverse-rekt/) — $15M Curve oracle manipulation
- [Venus Protocol postmortem](https://rekt.news/venus-blizz-rekt/) — $11M stale oracle exploit
- [Euler Finance postmortem](https://rekt.news/euler-rekt/) — $197M donation attack

---

## Practice Challenges

- **[Damn Vulnerable DeFi #7 "Compromised"](https://www.damnvulnerabledefi.xyz/)** — An oracle whose private keys are leaked, enabling price manipulation. Tests your understanding of oracle trust models and the consequences of compromised price feeds.

---

*Next module: Lending & Borrowing — supply/borrow model, collateral factors, interest rate curves, health factors, liquidation mechanics. This module will heavily use everything you've learned about oracles.*

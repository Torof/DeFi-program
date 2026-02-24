# Part 3 — Module 1: Liquid Staking & Restaking (~4 days)

> **Prerequisites:** Part 2 — Modules 1 (Token Mechanics), 3 (Oracles), 7 (Vaults & Yield)

## Overview

Liquid staking is the largest DeFi sector by TVL (~$50B+). This module covers how liquid staking protocols work, why LSTs behave the way they do, and the emerging restaking paradigm building a new infrastructure layer on top of staked ETH. You'll read production code from Lido and Rocket Pool, understand EigenLayer's restaking model, and build integration patterns that handle LST-specific edge cases.

---

## Day 1: Liquid Staking Fundamentals

### Why Liquid Staking Exists
- ETH staking requires 32 ETH and running a validator
- Staked ETH is locked — can't be used as DeFi collateral, can't be traded
- Liquid staking: stake ETH → receive liquid receipt token → use in DeFi
- Receipt token accrues staking rewards (~3-4% APR)

### Two Models: Rebasing vs Non-Rebasing

**Rebasing (stETH):**
- Balance increases daily via oracle reports
- 1 stETH always represents ~1 staked ETH
- Balance changes break some DeFi integrations (P2M1 weird tokens callback)
- Needs special handling in vaults, AMMs, lending pools

**Non-Rebasing / Wrapped (wstETH, rETH):**
- Fixed token balance, increasing exchange rate over time
- wstETH/stETH ratio grows as rewards accrue
- Same mental model as ERC-4626 shares (P2M7)
- Better DeFi composability — preferred by most protocols

### The Exchange Rate
- stETH: 1:1 by definition (rebasing adjusts balance)
- wstETH: `wstETH amount = stETH amount / stEthPerToken` — rate increases over time
- rETH: `rETH value = ETH deposited + rewards` — exchange rate increases
- Direct connection to ERC-4626 share math (P2M7)

### Withdrawal Queue (Post-Shapella)
- Before Shapella: no withdrawals, stETH traded at discount
- After Shapella: withdrawal requests processed by protocol
- Queue duration depends on validator exit queue
- Impact on LST/ETH peg stability

💻 **Quick Try:**
- Fork mainnet, wrap/unwrap stETH ↔ wstETH
- Check exchange rate, observe how it's > 1.0
- Compare rETH exchange rate

---

## Day 2: Lido & Rocket Pool Architecture

### Lido Architecture
- **Lido (stETH contract)** — rebasing ERC-20
  - `submit()` — deposit ETH, receive stETH
  - Oracle reports update total pooled ETH (balance rebase)
  - `getSharesByPooledEth()` / `getPooledEthByShares()` — conversion math
  - Shares-based internal accounting (similar to Aave aTokens)
- **wstETH** — non-rebasing wrapper
  - `wrap()` / `unwrap()` — convert between stETH and wstETH
  - `stEthPerToken()` — the exchange rate
  - `getStETHByWstETH()` / `getWstETHByStETH()`
- **Oracle system** — beacon chain balance reporting
  - Oracle committee reports validator balances
  - Triggers rebase of stETH balances
  - Sanity checks on reported values (limits on APR spikes)
- **Node Operator Registry** — curated validator set
  - Permissioned operators (professional node runners)
  - Centralization concern → dual governance model
- **Withdrawal Queue** — post-Shapella exit mechanism
  - Request/claim two-step process
  - NFT-based withdrawal requests

### 📖 Read: Lido stETH and wstETH
- `_submit()` flow — ETH deposit to share minting
- Oracle reporting — how `_handleOracleReport()` triggers rebase
- `getPooledEthByShares()` — the core conversion function
- wstETH `wrap()`/`unwrap()` — straightforward wrapper pattern

### Rocket Pool: Decentralized Alternative
- **Minipool model** — anyone can run a validator with 8 ETH (+24 from pool) or 16 ETH (+16)
- **rETH** — non-rebasing receipt token
  - Exchange rate updated by Oracle DAO
  - `getExchangeRate()` returns ETH per rETH
- **RPL staking** — node operators must stake RPL as insurance
- **Oracle DAO** — trusted committee for beacon chain reporting
- **Trade-offs vs Lido:**
  - More decentralized operator set
  - Less liquid (smaller market cap)
  - Different trust model (Oracle DAO vs curated operators)
  - Higher minimum for operators but permissionless entry

### 📖 Code Reading Strategy
1. Start with wstETH `wrap()`/`unwrap()` — simplest entry point
2. Read stETH `submit()` for deposit flow
3. Trace oracle reporting for balance updates
4. Study withdrawal queue for exit flow
5. Compare with rETH `deposit()` and `getExchangeRate()`

---

## Day 3: EigenLayer & Restaking

### What is Restaking?
- Staked ETH secures Ethereum consensus
- Restaking = opt-in to secure additional services with the same stake
- "Recycling" economic security across multiple protocols
- Creates new yield sources but also new slashing risk

### EigenLayer Architecture
- **EigenPodManager** — native ETH restaking via EigenPods
  - Validator points withdrawal credentials to EigenPod
  - Pod verifies beacon chain proofs
- **StrategyManager** — LST restaking
  - Deposit wstETH, rETH, etc. into strategies
  - Strategies hold deposited tokens
- **DelegationManager** — delegate restaked assets to operators
  - Operators run AVS software
  - Stakers delegate without running infrastructure
- **AVS (Actively Validated Services)** — services secured by restaked ETH
  - EigenDA (data availability)
  - Oracles, bridges, rollup sequencers
  - Each AVS defines its own slashing conditions
- **Slashing** — risk of stake reduction for operator misbehavior
  - AVS-specific conditions
  - Slashing committee and dispute resolution

### Liquid Restaking Tokens (LRTs)
- Same pattern as LSTs but for restaked positions
- ezETH (Renzo), rsETH (KelpDAO), pufETH (Puffer), weETH (EtherFi)
- Deposit LST → restake via EigenLayer → receive LRT
- Added complexity: underlying LST + restaking + AVS selection
- LRT exchange rates reflect restaking rewards + AVS rewards

### The Risk Landscape
- **Smart contract risk** — EigenLayer contracts, AVS contracts, LRT contracts
- **Slashing risk** — operator misbehavior triggers stake reduction
- **Liquidity risk** — LRT de-peg from underlying value
- **Systemic risk** — correlated slashing events across AVSes
- **Risk stacking** — each layer adds risk: ETH → staking → restaking → AVS → LRT
- Comparison: simple ETH staking risk vs full LRT risk stack

---

## Day 4: LST Integration Patterns

### LSTs as Collateral in Lending
- Aave V3 wstETH market — how it's configured
- Oracle setup: wstETH/ETH exchange rate x ETH/USD price feed
- E-Mode for correlated assets (wstETH ↔ ETH pair, higher LTV)
- Liquidation considerations: converting wstETH → ETH during liquidation
- Morpho Blue LST markets

### LST/ETH Oracle Pricing
- **On-chain exchange rate** — protocol-reported, accurate but manipulable via donation
- **Market price** — DEX price, reflects actual liquidity/demand
- **De-peg scenarios** — stETH depeg June 2022 (traded at 0.93 ETH)
- **Dual oracle pattern** — min(exchange rate, market price) for safety
- **Staleness** — exchange rate updates with oracle reports (not every block)

### LSTs in AMMs
- Curve stETH/ETH pool — the most important pool for LST liquidity
- StableSwap invariant is ideal for correlated assets
- Concentrated liquidity around 1:1 peg
- Yield-bearing LP positions (staking rewards + trading fees)

### LSTs in Vaults
- ERC-4626 vaults wrapping LSTs
- Nested yield: staking rewards + vault strategy yield
- wstETH is itself like an ERC-4626 — vaults wrapping vaults

### 🔗 DeFi Pattern Connection
- LST/ETH pricing → Oracle module (P2M3)
- LSTs as collateral → Lending module (P2M4)
- wstETH wrapper → ERC-4626 pattern (P2M7)
- Rebasing tokens → Token mechanics (P2M1)
- LST de-peg → DeFi Security (P2M8)

---

## 🎯 Module 1 Exercises

**Workspace:** `workspace/src/part3/module1/`

### Exercise 1: LST Oracle Consumer
- Build an oracle that correctly prices wstETH in USD
- Combine wstETH/stETH exchange rate with ETH/USD Chainlink feed
- Handle decimal normalization (exchange rate vs price feed decimals)
- Add staleness checks for both data sources
- Test with mock oracle reports showing exchange rate growth

### Exercise 2: LST Collateral Lending Pool
- Extend simplified lending pool to accept wstETH as collateral
- Implement proper wstETH → ETH valuation using oracle from Exercise 1
- Handle liquidation with wstETH → ETH unwrapping
- Test de-peg scenario (market price < exchange rate)
- Test E-Mode style parameters for correlated LST/ETH positions

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding rebasing vs non-rebasing patterns and their DeFi integration implications
- Ability to correctly price LSTs (exchange rate x underlying price)
- Awareness of EigenLayer and restaking as the current major trend
- Understanding risk stacking in LRT positions

**Common interview topics:**
- "How would you integrate wstETH as collateral in a lending protocol?"
- "What are the risks of accepting LRTs as collateral?"
- "Explain the difference between stETH and wstETH and when you'd use each"

---

## 📚 Resources

### Production Code
- [Lido stETH](https://github.com/lidofinance/lido-dao)
- [Lido wstETH](https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol)
- [Rocket Pool rETH](https://github.com/rocket-pool/rocketpool)
- [EigenLayer core](https://github.com/Layr-Labs/eigenlayer-contracts)
- [EtherFi weETH](https://github.com/etherfi-protocol/smart-contracts)

### Documentation
- [Lido docs](https://docs.lido.fi/)
- [Rocket Pool docs](https://docs.rocketpool.net/)
- [EigenLayer docs](https://docs.eigenlayer.xyz/)

### Further Reading
- [Lido: stETH integration guide](https://docs.lido.fi/guides/steth-integration-guide)
- [stETH depeg analysis (June 2022)](https://research.lido.fi/)
- [EigenLayer whitepaper](https://docs.eigenlayer.xyz/eigenlayer/overview)

---

**Navigation:** [Part 3 Overview](README.md) | [Next: Module 2 — Perpetuals & Derivatives →](2-perpetuals.md)

# Part 3 — Modern DeFi Stack & Advanced Verticals (~6-7 weeks)

Advanced DeFi protocol patterns, emerging verticals, and infrastructure — culminating in a capstone project integrating advanced concepts into a portfolio-ready protocol.

## Prerequisites

- **Part 1**: Modern Solidity, EVM changes, Foundry testing, proxy patterns
- **Part 2**: Core DeFi primitives (tokens, AMMs, oracles, lending, flash loans, stablecoins, vaults, security)

## Modules

| # | Module | Duration | Key Protocols |
|---|--------|----------|---------------|
| 1 | [Liquid Staking & Restaking](1-liquid-staking.md) | ~4 days | Lido, Rocket Pool, EigenLayer |
| 2 | [Perpetuals & Derivatives](2-perpetuals.md) | ~5 days | GMX, Synthetix, dYdX |
| 3 | [Yield Tokenization](3-yield-tokenization.md) | ~3 days | Pendle |
| 4 | [DEX Aggregation & Intents](4-dex-aggregation.md) | ~4 days | 1inch, UniswapX, CoW Protocol |
| 5 | [MEV Deep Dive](5-mev.md) | ~4 days | Flashbots, MEV-Boost, MEV-Share |
| 6 | [Cross-Chain & Bridges](6-cross-chain.md) | ~4 days | LayerZero, CCIP, Wormhole |
| 7 | [L2-Specific DeFi](7-l2-defi.md) | ~3 days | Arbitrum, Base, Optimism |
| 8 | [Governance & DAOs](8-governance.md) | ~3 days | OZ Governor, Curve, Velodrome |
| 9 | [Capstone: Perpetual Exchange](9-capstone.md) | ~5-7 days | GMX, dYdX, Synthetix Perps |

**Total: ~35-43 days** (~6-7 weeks at 3-4 hours/day)

## Module Progression

```
Module 1 (Liquid Staking) ← P2: Tokens, Vaults, Oracles
   ↓
Module 2 (Perpetuals) ← P2: AMMs, Oracles, Lending
   ↓
Module 3 (Yield Tokenization) ← P2: Vaults, AMMs + M1 (LSTs)
   ↓
Module 4 (DEX Aggregation) ← P2: AMMs, Flash Loans
   ↓
Module 5 (MEV) ← P2: AMMs, Flash Loans + M4
   ↓
Module 6 (Cross-Chain) ← P2: Tokens, Security
   ↓
Module 7 (L2 DeFi) ← P2: Oracles, Lending + M6
   ↓
Module 8 (Governance) ← P2: Tokens, Stablecoins
   ↓
Module 9 (Capstone) ← Everything
```

## Thematic Structure

**Modules 1-3: DeFi Verticals**
New protocol categories that build directly on Part 2's primitives. Each introduces a distinct DeFi vertical with its own mechanics, math, and architecture patterns.

**Modules 4-5: Trading Infrastructure**
How trades actually get executed in the real world — aggregation, intent-based trading, and the adversarial MEV environment that surrounds every transaction.

**Modules 6-7: Multi-Chain Reality**
Where DeFi lives today. Bridge architectures, messaging protocols, and the L2-specific concerns that affect every protocol deployed on rollups.

**Module 8: Protocol Coordination**
How protocols govern themselves — on-chain governance, tokenomics, and the security considerations that come with decentralized decision-making.

**Module 9: Capstone — Perpetual Exchange**
Design and build a simplified perpetual futures exchange from scratch. Portfolio-ready project integrating concepts across all three parts — perps are the highest-volume DeFi vertical and touch the most Part 3 modules (LSTs, perpetual mechanics, MEV, L2, governance).

---

**Previous:** [Part 2 — DeFi Foundations](../part2/)

# Part 3 — Module 9: Capstone — Perpetual Exchange (~5-7 days)

> **Prerequisites:** All of Parts 1, 2, and 3 Modules 1-8
>
> **Builds on:** Part 1 (Foundry testing, proxy patterns, gas optimization) | Part 2 (oracles, lending/liquidation math, flash loans, vault accounting, security patterns) | Part 3 Modules 1-8

## Overview

**Capstone choice: Perpetual Exchange.** Design and build a simplified perpetual futures exchange from scratch. Portfolio-ready project integrating concepts across all three parts.

**Why a perp exchange:** Perps are the highest-volume DeFi vertical. Building one demonstrates understanding of trading mechanics, funding rates, margin/liquidation, oracle design, MEV-aware liquidation, and L2 optimization — all in a single project.

**Key Part 3 concepts to integrate:**
- **M1 (Liquid Staking):** LSTs as collateral (wstETH margin)
- **M2 (Perpetuals):** Core mechanics — funding rates, mark/index price, PnL, margin, liquidation
- **M3 (Yield Tokenization):** Yield-bearing collateral implications
- **M4 (DEX Aggregation):** Liquidation routing
- **M5 (MEV):** MEV-resistant liquidation design
- **M6 (Cross-Chain):** Multi-chain deployment considerations, bridge risk for cross-chain collateral
- **M7 (L2 DeFi):** L2-native design (low latency, sequencer awareness)
- **M8 (Governance):** Parameter governance (fees, margin requirements, market listings)

**Connection to Part 2 Capstone:** Your P2 stablecoin could serve as the settlement asset for this exchange.

**Full curriculum to be written after M1-M8 are complete.**

---

**Navigation:** [← Module 8: Governance & DAOs](8-governance.md) | [Part 3 Overview](README.md)

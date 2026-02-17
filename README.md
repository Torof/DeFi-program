# DeFi Protocol Engineering

A structured, hands-on curriculum for going from experienced Solidity developer to DeFi protocol designer — covering the math, architecture, and security of production DeFi from first principles.

## About

This repo documents a self-directed learning path built around one goal: **designing and building original DeFi protocols**. It's written from the perspective of an experienced EVM/Solidity developer returning to DeFi after a ~2-year absence, with strong smart contract fundamentals but limited protocol-level building experience.

The approach throughout is **read production code, then rebuild**. Every module studies real deployed protocols (Uniswap, Aave, Compound, MakerDAO, etc.), breaks down their architecture, then builds simplified versions from scratch using Foundry. The focus is always on *why* things are designed the way they are — not just *how* they work.

## Structure

The curriculum is split into three parts, progressing from foundational mechanics to advanced protocol design.

### Part 1 — Solidity, EVM & Modern Tooling (~2.5-3 weeks)

Catching up on Solidity 0.8.x language changes, EVM-level upgrades (Dencun, Pectra), modern token approval patterns, account abstraction, Foundry testing workflows, proxy patterns, and deployment operations.

| # | Section | Duration | Status |
|---|---------|----------|--------|
| 1 | Solidity 0.8.x Modern Features | ~2 days | ⬜ |
| 2 | EVM-Level Changes (EIP-1153, EIP-4844, EIP-7702) | ~2 days | ⬜ |
| 3 | Modern Token Approvals (EIP-2612, Permit2) | ~3 days | ⬜ |
| 4 | Account Abstraction (ERC-4337, EIP-7702, Paymasters) | ~3 days | ⬜ |
| 5 | Foundry Workflow & Testing (Fuzz, Invariant, Fork) | ~2-3 days | ⬜ |
| 6 | Proxy Patterns & Upgradeability | ~1.5-2 days | ⬜ |
| 7 | Deployment & Operations | ~0.5 day | ⬜ |

### Part 2 — DeFi Foundations (~5-6 weeks)

The core primitives of decentralized finance. Each module follows a consistent pattern: concept → math → read production code → build → test → extend.

| # | Module | Duration | Status |
|---|--------|----------|--------|
| 1 | Token Mechanics | ~1 day | ⬜ |
| 2 | AMMs from First Principles | ~10 days | ⬜ |
| 3 | Oracles | ~3 days | ⬜ |
| 4 | Lending & Borrowing | ~7 days | ⬜ |
| 5 | Flash Loans | ~3 days | ⬜ |
| 6 | Stablecoins & CDPs | ~4 days | ⬜ |
| 7 | Vaults & Yield | ~4 days | ⬜ |
| 8 | DeFi Security | ~4 days | ⬜ |
| 9 | Integration Capstone | ~2-3 days | ⬜ |

### Part 3 — Modern DeFi Stack (~3-4 weeks)

Advanced patterns and a capstone project designing a multi-collateral stablecoin protocol from scratch.

| # | Module | Duration | Status |
|---|--------|----------|--------|
| 9 | DEX Aggregation & Intents | ~3 days | ⬜ |
| 10 | MEV Deep Dive | ~4 days | ⬜ |
| 11 | Cross-Chain & Bridges | ~3 days | ⬜ |
| 12 | Governance & DAOs | ~3 days | ⬜ |
| 13 | Capstone: Multi-Collateral Stablecoin | ~5-7 days | ⬜ |

## Learning Approach

Each module typically includes:

- **Concept** — The underlying math and mechanism design, explained from first principles
- **Read** — Guided walkthroughs of production protocol code (Uniswap V2/V3/V4, Aave V3, Compound V3, MakerDAO, etc.)
- **Build** — Simplified but correct implementations in Foundry capturing the core mechanics
- **Test** — Comprehensive Foundry test suites including fuzz and invariant testing
- **Extend** — Exercises that push beyond the basics (attack simulations, gas optimization, mainnet fork testing)

Time estimates assume 3-4 hours per day with no hard deadline.

## Tech Stack

- **Foundry** — Forge for testing, Anvil for local/fork testing, Cast for on-chain interaction
- **Solidity 0.8.x** — Modern compiler features (custom errors, user-defined value types, transient storage)
- **OpenZeppelin Contracts** — Standard implementations (ERC-20, AccessControl, ReentrancyGuard, etc.)
- **Chainlink** — Price feed integration and oracle patterns
- **Mainnet fork testing** — Real protocol interaction via `forge test --fork-url`

## Key Protocols Studied

Uniswap (V2, V3, V4) · Aave V3 · Compound V3 · MakerDAO · Balancer · Chainlink · Permit2 · ERC-4626 · UniswapX · ERC-4337

## Project Structure

### Curriculum docs

Each part's learning material is organized into section/module folders for easy navigation and extensibility:

```
defi-auto-program/
├── README.md                         # This file
├── part1/                            # Curriculum docs for Part 1
│   ├── README.md                     # Overview, section table, checklist
│   ├── section1-solidity-modern/     # Solidity 0.8.x features
│   ├── section2-evm-changes/         # EIP-1153, EIP-4844, EIP-7702
│   ├── section3-token-approvals/     # EIP-2612 Permit, Permit2
│   ├── section4-account-abstraction/ # ERC-4337, paymasters
│   ├── section5-foundry/             # Fuzz, invariant, fork testing
│   ├── section6-proxy-patterns/      # UUPS, transparent, beacon
│   └── section7-deployment/          # Scripts, verification, multisig
└── part2/                            # Curriculum docs for Part 2
    ├── module1-token-mechanics.md
    ├── module2-amms.md
    ├── module3-oracles.md
    ├── module4-lending.md
    ├── module5-flash-loans.md
    ├── module6-stablecoins-cdps.md
    ├── module7-vaults-yield.md
    ├── module8-defi-security.md
    └── module9-integration-capstone.md
```

Each section folder contains the main content file plus space for additional exercises, links, and notes.

### Code workspace

Single unified Foundry project for all exercises. This structure allows sharing dependencies and referencing earlier code:

```
workspace/                        # Unified Foundry project
├── src/
│   ├── part1/                    # Solidity, EVM & Modern Tooling
│   │   ├── section1/             # UDVTs, transient storage exercises
│   │   ├── section2/             # EIP-1153, 4844, 7702 exercises
│   │   ├── section3/             # Permit, Permit2 vaults
│   │   ├── section4/             # Smart accounts, paymasters
│   │   ├── section5/             # Fuzz, invariant, fork tests
│   │   ├── section6/             # Proxy patterns, upgradeability
│   │   └── section7/             # Deployment scripts
│   ├── part2/                    # DeFi Foundations
│   │   ├── module1/              # Token vault, SafeERC20 exercises
│   │   ├── module2/              # AMM pools (constant product, CLAMM)
│   │   ├── module3/              # Oracle consumers, TWAP
│   │   ├── module4/              # Lending pool, interest rate models
│   │   ├── module5/              # Flash loan receivers, arbitrage bots
│   │   ├── module6/              # CDP engine, liquidation
│   │   ├── module7/              # ERC-4626 vaults, yield strategies
│   │   ├── module8/              # Security exercises, invariant tests
│   │   └── module9/              # Integration capstone
│   └── part3/                    # Modern DeFi Stack
└── test/
    ├── part1/
    ├── part2/
    └── part3/
```

## Review Cadence

Dedicate the last hour of every 5th or 6th learning day to review. This isn't a separate "review day" — it's a wind-down session woven into a normal learning day:

- Re-read production code you studied that week
- Revisit exercises that felt shaky
- Write brief notes on what clicked and what didn't
- Check if earlier module concepts connect to what you just learned

This keeps retention high without losing learning momentum.

## Practice Challenges

[Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) and [Ethernaut](https://ethernaut.openzeppelin.com/) challenges are integrated throughout the modules at relevant points. Each module's "Practice Challenges" section recommends specific challenges that test the concepts covered. These are optional but strongly recommended — they force you to think like an attacker, which makes you a better builder.

## Status

This is a living repo. Modules are expanded with exercises, tests, and code as they're worked through. The outline and priorities evolve based on what comes up during the builds.

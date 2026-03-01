# DeFi Protocol Engineering

[![Read the Book](https://img.shields.io/badge/Read_the_Book-torof.github.io-blue?style=for-the-badge)](https://torof.github.io/DeFi-program/)
[![Open in GitHub Codespaces](https://img.shields.io/badge/Open_in-Codespaces-black?style=for-the-badge&logo=github)](https://codespaces.new/Torof/DeFi-program?quickstart=1)

A structured, hands-on curriculum for going from experienced Solidity developer to DeFi protocol designer — covering the math, architecture, and security of production DeFi from first principles.

## About

This repo documents a self-directed learning path built around one goal: **designing and building original DeFi protocols**. It's written from the perspective of an experienced EVM/Solidity developer returning to DeFi after a ~2-year absence, with strong smart contract fundamentals but limited protocol-level building experience.

The approach throughout is **read production code, then rebuild**. Every module studies real deployed protocols (Uniswap, Aave, Compound, MakerDAO, etc.), breaks down their architecture, then builds simplified versions from scratch using Foundry. The focus is always on *why* things are designed the way they are — not just *how* they work.

## Structure

The curriculum is split into four parts, progressing from foundational mechanics to advanced protocol design and EVM mastery.

### Part 1 — Solidity, EVM & Modern Tooling (~2.5-3 weeks)

Catching up on Solidity 0.8.x language changes, EVM-level upgrades (Dencun, Pectra), modern token approval patterns, account abstraction, Foundry testing workflows, proxy patterns, and deployment operations.

| # | Module | Duration | Status |
|---|---------|----------|--------|
| 1 | Solidity 0.8.x Modern Features | ~2 days | ⬜ |
| 2 | EVM-Level Changes (EIP-1153, EIP-4844, EIP-7702) | ~2 days | ⬜ |
| 3 | Modern Token Approvals (EIP-2612, Permit2) | ~3 days | ⬜ |
| 4 | Account Abstraction (ERC-4337, EIP-7702, Paymasters) | ~3 days | ⬜ |
| 5 | Foundry Workflow & Testing (Fuzz, Invariant, Fork) | ~2-3 days | ⬜ |
| 6 | Proxy Patterns & Upgradeability | ~1.5-2 days | ⬜ |
| 7 | Deployment & Operations | ~0.5 day | ⬜ |

### Part 2 — DeFi Foundations (~6-7 weeks)

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
| 9 | Capstone: Decentralized Stablecoin | ~5-7 days | ⬜ |

### Part 3 — Modern DeFi Stack & Advanced Verticals (~6-7 weeks)

DeFi verticals (liquid staking, perpetuals, yield tokenization), trading infrastructure (aggregation, MEV), multi-chain reality (bridges, L2), governance, and a capstone project integrating advanced concepts into a portfolio-ready protocol.

| # | Module | Duration | Status |
|---|--------|----------|--------|
| 1 | Liquid Staking & Restaking | ~4 days | ⬜ |
| 2 | Perpetuals & Derivatives | ~5 days | ⬜ |
| 3 | Yield Tokenization | ~3 days | ⬜ |
| 4 | DEX Aggregation & Intents | ~4 days | ⬜ |
| 5 | MEV Deep Dive | ~4 days | ⬜ |
| 6 | Cross-Chain & Bridges | ~4 days | ⬜ |
| 7 | L2-Specific DeFi | ~3 days | ⬜ |
| 8 | Governance & DAOs | ~3 days | ⬜ |
| 9 | Capstone: Perpetual Exchange | ~5-7 days | ⬜ |

### Part 4 — EVM Mastery: Yul & Assembly (~6-7 weeks)

Go from reading assembly snippets to writing production-grade Yul. Understand the machine underneath every DeFi protocol — the single biggest differentiator for senior roles.

| # | Module | Duration | Status |
|---|--------|----------|--------|
| 1 | EVM Fundamentals | ~3 days | ⬜ |
| 2 | Memory & Calldata | ~3 days | ⬜ |
| 3 | Storage Deep Dive | ~3 days | ⬜ |
| 4 | Control Flow & Functions | ~3 days | ⬜ |
| 5 | External Calls | ~3 days | ⬜ |
| 6 | Gas Optimization Patterns | ~3 days | ⬜ |
| 7 | Reading Production Assembly | ~3 days | ⬜ |
| 8 | Pure Yul Contracts | ~4 days | ⬜ |
| 9 | Capstone: DeFi Primitive in Yul | ~5-7 days | ⬜ |

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

Uniswap (V2, V3, V4) · Aave V3 · Compound V3 · MakerDAO · Balancer · Chainlink · Permit2 · ERC-4626 · UniswapX · ERC-4337 · Lido · Rocket Pool · EigenLayer · GMX · Synthetix · Pendle · 1inch · CoW Protocol · Flashbots · LayerZero · Chainlink CCIP · Curve · Velodrome

## Project Structure

### Curriculum docs

Each part's learning material is organized as flat module files:

```
defi-auto-program/
├── README.md                         # This file
├── part1/                            # Curriculum docs for Part 1
│   ├── README.md                     # Overview, module table, checklist
│   ├── 1-solidity-modern.md          # Solidity 0.8.x features
│   ├── 2-evm-changes.md              # EIP-1153, EIP-4844, EIP-7702
│   ├── 3-token-approvals.md          # EIP-2612 Permit, Permit2
│   ├── 4-account-abstraction.md      # ERC-4337, paymasters
│   ├── 5-foundry.md                  # Fuzz, invariant, fork testing
│   ├── 6-proxy-patterns.md           # UUPS, transparent, beacon
│   └── 7-deployment.md               # Scripts, verification, multisig
├── part2/                            # Curriculum docs for Part 2
│   ├── README.md                     # Overview, module table, checklist
│   ├── 1-token-mechanics.md          # ERC-20 edge cases, SafeERC20
│   ├── 2-amms.md                     # Uniswap V2, V3, V4
│   ├── 3-oracles.md                  # Chainlink, TWAP, dual oracle
│   ├── 4-lending.md                  # Aave V3, Compound V3
│   ├── 5-flash-loans.md              # Aave V3, ERC-3156, Uniswap V4
│   ├── 6-stablecoins-cdps.md         # MakerDAO, Liquity, crvUSD
│   ├── 7-vaults-yield.md             # ERC-4626, yield aggregation
│   ├── 8-defi-security.md            # Reentrancy, oracle manipulation
│   └── 9-integration-capstone.md     # Decentralized stablecoin capstone
├── part3/                            # Curriculum docs for Part 3
│   ├── README.md                     # Overview, module table, checklist
│   ├── 1-liquid-staking.md           # Lido, Rocket Pool, EigenLayer
│   ├── 2-perpetuals.md               # GMX, Synthetix, dYdX
│   ├── 3-yield-tokenization.md       # Pendle
│   ├── 4-dex-aggregation.md          # 1inch, UniswapX, CoW Protocol
│   ├── 5-mev.md                      # Flashbots, MEV-Boost, MEV-Share
│   ├── 6-cross-chain.md              # LayerZero, CCIP, Wormhole
│   ├── 7-l2-defi.md                  # Arbitrum, Base, Optimism
│   ├── 8-governance.md               # OZ Governor, Curve, Velodrome
│   └── 9-capstone.md                 # Perpetual exchange capstone
└── part4/                            # Curriculum docs for Part 4
    ├── README.md                     # Overview, learning arc
    ├── 1-evm-fundamentals.md         # Stack machine, opcodes, gas model
    ├── 2-memory-calldata.md          # mload/mstore, free memory pointer
    ├── 3-storage.md                  # sload/sstore, slot computation
    ├── 4-control-flow.md             # if/switch/for, function dispatch
    ├── 5-external-calls.md           # call/staticcall/delegatecall
    ├── 6-gas-optimization.md         # Solady patterns, bitmap tricks
    ├── 7-production-assembly.md      # Reading Uniswap, OZ, Solady
    ├── 8-pure-yul.md                 # Object notation, full Yul contracts
    └── 9-capstone.md                 # DeFi primitive in Yul
```

Each module file contains the full content for that topic.

### Code workspace

Single unified Foundry project for all exercises. This structure allows sharing dependencies and referencing earlier code:

```
workspace/                        # Unified Foundry project
├── src/
│   ├── part1/                    # Solidity, EVM & Modern Tooling
│   │   ├── module1/              # UDVTs, transient storage exercises
│   │   ├── module2/              # EIP-1153, 4844, 7702 exercises
│   │   ├── module3/              # Permit, Permit2 vaults
│   │   ├── module4/              # Smart accounts, paymasters
│   │   ├── module5/              # Fuzz, invariant, fork tests
│   │   ├── module6/              # Proxy patterns, upgradeability
│   │   └── module7/              # Deployment scripts
│   ├── part2/                    # DeFi Foundations
│   │   ├── module1/              # Token vault, SafeERC20 exercises
│   │   ├── module2/              # AMM pools (constant product, CLAMM)
│   │   ├── module3/              # Oracle consumers, TWAP
│   │   ├── module4/              # Lending pool, interest rate models
│   │   ├── module5/              # Flash loan receivers, arbitrage bots
│   │   ├── module6/              # CDP engine, liquidation
│   │   ├── module7/              # ERC-4626 vaults, yield strategies
│   │   ├── module8/              # Security exercises, invariant tests
│   │   └── module9/              # Decentralized stablecoin capstone
│   ├── part3/                    # Modern DeFi Stack
│   │   ├── module1/              # LST oracle, LST lending pool
│   │   ├── module2/              # Funding rate engine, perp exchange
│   │   ├── module3/              # Yield tokenizer, PT rate oracle
│   │   ├── module4/              # Split router, intent settlement
│   │   ├── module5/              # Sandwich simulation, MEV fee hook
│   │   ├── module6/              # Cross-chain handler, rate-limited token
│   │   ├── module7/              # L2 oracle consumer, gas estimator
│   │   └── module8/              # Governor system, vote escrow
│   └── part4/                    # EVM Mastery: Yul & Assembly (TBD)
└── test/
    ├── part1/
    ├── part2/
    ├── part3/
    └── part4/
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

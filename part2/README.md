# Part 2 — DeFi Foundations (~5-6 weeks)

The core primitives of decentralized finance. Each module follows a consistent pattern: concept → math → read production code → build → test → extend.

## Prerequisites

- **Part 1**: Modern Solidity (0.8.x features, custom errors, UDVTs), EVM changes (transient storage, EIP-7702), token approval patterns (EIP-2612, Permit2), Foundry testing (fuzz, invariant, fork), proxy patterns (UUPS, beacon)

## Modules

| # | Module | Duration | Key Protocols |
|---|--------|----------|---------------|
| 1 | [Token Mechanics](1-token-mechanics.md) | ~1 day | ERC-20 edge cases, SafeERC20, fee-on-transfer |
| 2 | [AMMs from First Principles](2-amms.md) | ~10 days | Uniswap V2, V3, V4 |
| 3 | [Oracles](3-oracles.md) | ~3 days | Chainlink, TWAP, Liquity dual oracle |
| 4 | [Lending & Borrowing](4-lending.md) | ~7 days | Aave V3, Compound V3, Morpho Blue |
| 5 | [Flash Loans](5-flash-loans.md) | ~3 days | Aave V3, ERC-3156, Uniswap V4 |
| 6 | [Stablecoins & CDPs](6-stablecoins-cdps.md) | ~4 days | MakerDAO (Vat, Jug, Dog, PSM), Liquity, crvUSD |
| 7 | [Vaults & Yield](7-vaults-yield.md) | ~4 days | ERC-4626, Yearn, yield aggregation |
| 8 | [DeFi Security](8-defi-security.md) | ~4 days | Reentrancy, oracle manipulation, invariant testing |
| 9 | [Integration Capstone](9-integration-capstone.md) | ~2-3 days | All of the above |

**Total: ~38-45 days** (~5-6 weeks at 3-4 hours/day)

## Module Progression

```
Module 1 (Tokens) ← P1: SafeERC20, custom errors, decimals
   ↓
Module 2 (AMMs) ← M1 + P1: Math (mulDiv, UDVTs), transient storage
   ↓
Module 3 (Oracles) ← M2 (TWAP from AMM pools)
   ↓
Module 4 (Lending) ← M1 + M2 + M3 (collateral, liquidation swaps, price feeds)
   ↓
Module 5 (Flash Loans) ← M2 + M4 (arbitrage, collateral swaps)
   ↓
Module 6 (Stablecoins) ← M3 + M4 (oracle-priced vaults, stability fees)
   ↓
Module 7 (Vaults & Yield) ← M1 + M2 + M4 (ERC-4626, strategy allocation)
   ↓
Module 8 (Security) ← M2 + M3 + M4 + M7 (attack vectors across all primitives)
   ↓
Module 9 (Capstone) ← Everything
```

## Part 2 Checklist

Before moving to Part 3, verify you can:

- [ ] Handle fee-on-transfer and rebasing tokens safely
- [ ] Normalize across different decimal tokens
- [ ] Derive and implement the constant product formula (x*y=k)
- [ ] Explain concentrated liquidity and tick math
- [ ] Describe Uniswap V4's singleton/hook architecture
- [ ] Integrate Chainlink price feeds with staleness and sequencer checks
- [ ] Build a TWAP oracle from cumulative price accumulators
- [ ] Implement a kink-based interest rate model
- [ ] Build a lending pool with supply, borrow, repay, and health factor
- [ ] Pack/unpack reserve configuration using bitmaps
- [ ] Execute a flash loan and explain the callback pattern
- [ ] Build flash loan arbitrage and collateral swap contracts
- [ ] Explain normalized debt (`art * rate`) and the MakerDAO accounting model
- [ ] Implement `frob()`, `fold()`, and `grab()` in a Vat
- [ ] Describe how the PSM maintains peg stability
- [ ] Build an ERC-4626 vault from scratch (deposit/withdraw/mint/redeem)
- [ ] Defend against the ERC-4626 inflation attack
- [ ] Implement a multi-strategy yield allocator
- [ ] Identify and exploit read-only reentrancy
- [ ] Demonstrate oracle manipulation via flash loans
- [ ] Write invariant tests that find bugs in DeFi contracts

---

**Previous:** [Part 1 — Solidity, EVM & Modern Tooling](../part1/)
**Next:** [Part 3 — Modern DeFi Stack & Advanced Verticals](../part3/)

# Part 3 — Module 9: Capstone — Multi-Collateral Stablecoin Protocol (~5-7 days)

> **Prerequisites:** All of Parts 1, 2, and 3 Modules 1-8

## Overview

Design and build a multi-collateral stablecoin protocol from scratch. This is the culmination of the entire program — a portfolio-ready project that integrates concepts from across all three parts. The goal is not to replicate MakerDAO, but to design an original protocol that demonstrates deep understanding of DeFi mechanics, trade-offs, and security.

This project gives control of money back to the people — a stablecoin backed by real collateral, governed by its users, resistant to censorship.

---

## What You're Building

A multi-collateral stablecoin protocol where users deposit collateral (ETH, wstETH, rETH) to mint a dollar-pegged stablecoin. The protocol includes:

- **Core CDP engine** — collateral management, stablecoin minting/burning, health factor tracking
- **Oracle integration** — Chainlink price feeds with LST exchange rate handling
- **Liquidation engine** — MEV-aware liquidation with Dutch auction
- **Interest accrual** — stability fee accumulator
- **Governance** — parameter updates via Governor + Timelock
- **Comprehensive testing** — unit, fuzz, invariant, and fork tests

---

## Concepts Integrated

### From Part 1: Solidity & Tooling
- User-Defined Value Types for Assets, Shares, Debt (type safety)
- Custom errors with informative parameters
- Transient storage for reentrancy guards
- UUPS proxy for upgradeability
- Comprehensive Foundry testing (fuzz, invariant, fork)
- Deployment scripts with verification

### From Part 2: DeFi Foundations
- **Token mechanics (M1):** SafeERC20 for collateral handling, decimal normalization
- **AMMs (M2):** Liquidation collateral sold via DEX integration
- **Oracles (M3):** Chainlink feeds, staleness checks, multi-source pricing
- **Lending (M4):** Health factors, collateralization ratios, interest accrual indexes
- **Flash loans (M5):** Flash mint for the stablecoin (atomic mint + use + burn)
- **CDPs (M6):** Core CDP mechanics, stability fees, liquidation flow
- **Vaults (M7):** ERC-4626 vault shares as collateral, inflation attack awareness
- **Security (M8):** Invariant testing, attack simulation, security checklist

### From Part 3: Advanced Patterns
- **Liquid staking (M1):** wstETH and rETH as collateral types, exchange rate oracle pricing
- **Perpetuals (M2):** Funding/interest rate accumulator pattern
- **Yield tokenization (M3):** Understanding how yield-bearing collateral affects backing
- **DEX aggregation (M4):** Liquidation routing through aggregator for best execution
- **MEV (M5):** MEV-resistant liquidation design (Dutch auction, not fixed-price)
- **Cross-chain (M6):** Awareness of cross-chain deployment (future extension)
- **L2 (M7):** Sequencer-aware oracle checks for L2 deployment
- **Governance (M8):** Governor + Timelock for parameter updates

---

## Day 1: Architecture Design

### Define the Protocol
- Choose collateral types and risk parameters per collateral:
  - ETH: LTV, liquidation threshold, liquidation bonus, stability fee
  - wstETH: same parameters (potentially higher LTV due to yield)
  - rETH: same parameters
- Design the core data structures:
  - Vault (CDP) struct: collateral amount, debt amount, collateral type
  - Collateral config: oracle, LTV, liquidation threshold, stability fee rate
  - Global state: total debt, debt ceiling per collateral, system surplus/deficit

### Architecture Decisions
- **Monolithic vs modular:**
  - MakerDAO style: separate contracts (Vat, Jug, Dog, Clipper)
  - Or simplified: fewer contracts, clearer to understand
  - Recommendation: 3-4 core contracts (Engine, Oracle, Liquidator, Stablecoin)
- **Interest accrual:** per-second compound via index (like Aave/Compound)
- **Liquidation model:** Dutch auction (like MakerDAO Liquidations 2.0)
  - Price starts high, decays over time
  - Prevents flash loan manipulation of fixed-price liquidation
  - Keeper-triggered, permissionless
- **Flash mint:** allow atomic mint/burn of stablecoin (like DAI flash mint)
  - Useful for arbitrage, liquidation, composability
  - Must repay within same transaction

### Sketch the Contracts
```
StablecoinEngine.sol    — Core CDP logic (open, deposit, borrow, repay, close)
StablecoinOracle.sol    — Price feed aggregation with LST support
StablecoinLiquidator.sol — Dutch auction liquidation engine
Stablecoin.sol          — ERC-20 stablecoin token with flash mint
```

---

## Day 2-3: Core Implementation

### StablecoinEngine.sol
- `openVault(collateralType)` — create a new CDP
- `depositCollateral(vaultId, amount)` — add collateral
- `mintStablecoin(vaultId, amount)` — borrow against collateral
- `repayStablecoin(vaultId, amount)` — reduce debt
- `withdrawCollateral(vaultId, amount)` — remove collateral (if healthy)
- `closeVault(vaultId)` — repay all debt, withdraw all collateral
- Health factor calculation: `(collateral value x LT) / (debt x accrued rate)`
- Stability fee accrual: global rate accumulator per collateral type
- Debt ceiling enforcement per collateral type

### StablecoinOracle.sol
- Chainlink feed integration for ETH/USD
- LST pricing: `wstETH price = wstETH/stETH rate x stETH/ETH rate x ETH/USD`
- Staleness checks with configurable heartbeat per feed
- L2 sequencer uptime check (for L2 deployment)
- Fallback oracle support (optional)

### StablecoinLiquidator.sol
- `liquidate(vaultId)` — initiate Dutch auction for unhealthy vault
- Auction: starting price = collateral value x premium, decays over time
- `buyCollateral(auctionId, amount)` — bid on auction (partial fills allowed)
- Auction proceeds: repay debt → return surplus to vault owner
- Bad debt handling: if auction doesn't cover debt → socialize loss

### Stablecoin.sol
- Standard ERC-20 with mint/burn restricted to Engine
- Flash mint: `flashMint(amount, receiver, data)` → callback → must repay
- EIP-2612 Permit support

---

## Day 4: Liquidation & Risk

### Dutch Auction Implementation
- Starting price: collateral oracle price x (1 + premium) — e.g., 120% of value
- Price decay: linear or exponential over auction duration (e.g., 1 hour)
- Floor price: minimum acceptable price (e.g., debt value)
- Partial fills: bidders can buy portions of the collateral
- Reset: if auction expires without full fill, can be restarted

### MEV Considerations in Liquidation
- **Fixed-price liquidation (what NOT to do):**
  - All liquidators see same profit → gas war → MEV extraction
  - Frontrunning: bot copies liquidation tx with higher gas
- **Dutch auction (better):**
  - Price starts unfavorable for liquidator, decays to profitable
  - Each bidder chooses their own entry point
  - No single "optimal" moment → less MEV
  - Natural price discovery

### Bad Debt Handling
- Scenario: collateral value < debt value (100% LTV exceeded)
- Auction can't fully cover the debt
- Options:
  - Socialize across all stablecoin holders (DAI's approach via system surplus)
  - Insurance fund / stability pool (Liquity's approach)
  - Protocol treasury absorbs loss
- Choice affects protocol design significantly

### Stress Testing
- Cascading liquidation scenario (price drops 30% in 1 block)
- Multiple vaults liquidated simultaneously
- Gas cost analysis for liquidation calls
- Oracle staleness during volatility

---

## Day 5: Governance & Operations

### Governor Integration
- Deploy ERC20Votes governance token
- Deploy Governor + TimelockController
- Governable parameters:
  - Collateral LTV, liquidation threshold, liquidation bonus
  - Stability fee rates
  - Debt ceilings per collateral type
  - Oracle configurations
  - New collateral type onboarding
- Non-governable (immutable):
  - Core CDP math
  - Liquidation auction mechanism
  - Flash mint interface

### Emergency Mechanisms
- **Pause guardian:** multisig that can pause new borrows and liquidations
  - Cannot unpause alone — requires governance
  - Circuit breaker for active exploit
- **Emergency shutdown:** nuclear option
  - Settles all positions at current oracle prices
  - Users claim their collateral share
  - Stablecoin redeemable for pro-rata collateral
  - Requires governance vote or high threshold

### LST-Specific Collateral Handling
- wstETH → unwrap to stETH during liquidation? Or sell as wstETH?
- Exchange rate risk: wstETH rate is protocol-controlled
  - If Lido has a bug → exchange rate could be wrong
  - Dual oracle: exchange rate + market price
- rETH: similar considerations, different oracle infrastructure

---

## Day 6-7: Testing & Hardening

### Unit Tests
- Every function in every contract
- Access control verification
- Edge cases: zero amounts, maximum values, rounding

### Fuzz Tests
- Random collateral deposits and debt minting
- Random price movements → health factor calculations
- Random liquidation timing → auction price correctness
- Random governance parameter changes → system stability

### Invariant Tests
- **Solvency:** total collateral value (at oracle prices) >= total debt outstanding
- **Backing:** every minted stablecoin has corresponding debt in a vault
- **Accounting:** sum of all vault debts = total protocol debt
- **Health:** no vault with health factor < 1.0 exists without active liquidation
- **Conservation:** collateral in + stability fees = collateral out + protocol surplus
- Handler contract with bounded operations:
  - `openVault()`, `deposit()`, `mint()`, `repay()`, `withdraw()`, `close()`
  - `liquidate()`, `buyCollateral()`
  - `updatePrice()` (oracle manipulation)
  - `warp()` (time advancement for interest accrual)

### Fork Tests
- Fork mainnet/Arbitrum
- Use real Chainlink oracles
- Use real wstETH exchange rate
- Real gas costs for liquidation calls
- Verify oracle staleness checks with actual feed behavior

### Attack Simulation
- Oracle manipulation attempt
- Flash loan attack on liquidation
- Inflation attack on collateral vaults
- Governance flash loan attack prevention verification
- Re-entrance through collateral token callbacks

### Gas Optimization Pass
- Profile gas costs for core operations
- Compare with production protocols (MakerDAO, Liquity)
- Optimize hot paths: deposit, mint, liquidation check

---

## Deliverables

### Code
- `StablecoinEngine.sol` — core CDP logic
- `StablecoinOracle.sol` — oracle aggregation
- `StablecoinLiquidator.sol` — Dutch auction liquidation
- `Stablecoin.sol` — ERC-20 with flash mint
- Governance contracts (Governor, Timelock)
- Test suite (unit, fuzz, invariant, fork)
- Deployment script

### Documentation
- Architecture decision record: why you made each design choice
- Risk parameter rationale: how you chose LTV, LT, fees
- Security considerations: attack vectors considered and mitigations
- Trade-offs: what you'd do differently with more time

### Interview Readiness
This capstone should prepare you to:
1. Walk through a protocol architecture whiteboard-style
2. Explain every design decision and its trade-offs
3. Discuss security considerations proactively
4. Demonstrate testing best practices
5. Show understanding of governance and operational security
6. Compare your design to MakerDAO/Liquity and explain differences

---

## Stretch Goals (Optional)

If you finish early and want to go further:

1. **Peg Stability Module (PSM):** 1:1 swap between your stablecoin and USDC
2. **Savings Rate:** deposit stablecoin to earn stability fee revenue
3. **Multi-chain deployment:** deploy on L2 with sequencer-aware oracles
4. **Pendle integration:** accept PT-wstETH as collateral (fixed-rate backing)
5. **Cross-chain bridging:** design the token for cross-chain transfers (xERC20 pattern)

---

## 📚 Reference Protocols

### Primary References
- [MakerDAO (dss)](https://github.com/makerdao/dss) — the canonical CDP protocol
- [Liquity](https://github.com/liquity/dev) — governance-minimized alternative
- [Ethena (USDe)](https://github.com/ethena-labs) — delta-neutral stablecoin

### Architecture Inspiration
- MakerDAO: comprehensive but complex (formal verification heritage)
- Liquity: elegant simplicity (immutable, no governance)
- Your protocol: find the right balance for your design goals

---

**Navigation:** [← Module 8: Governance & DAOs](8-governance.md) | [Part 3 Overview](README.md)

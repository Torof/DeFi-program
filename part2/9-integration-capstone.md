# Part 2 — Module 9: Capstone — Decentralized Multi-Collateral Stablecoin

**Duration:** ~5-7 days (3–4 hours/day)
**Prerequisites:** Modules 1–8 complete
**Pattern:** Architecture design → Core engine → Collateral pricing → Liquidation → Flash mint → Testing → Portfolio
**Builds on:** Module 4 (health factors, interest accrual, liquidation), Module 5 (flash loans, ERC-3156), Module 6 (CDP mechanics, rate accumulator, Dutch auctions), Module 7 (ERC-4626 vault shares, inflation attack), Module 8 (invariant testing, security)
**Used by:** Part 3 Module 8 (governance — potential upgrade path), Part 3 Capstone

---

## 📚 Table of Contents

**Overview & Design Philosophy**
- [Why a Stablecoin Capstone](#why-capstone)
- [The Stablecoin Landscape](#stablecoin-landscape)
- [Design Principles: Immutable, Permissionless, Crypto-Native](#design-principles)
- [Cross-Module Prerequisite Map](#prerequisite-map)

**Architecture Design**
- [Contract Structure: The 4 Core Contracts](#contract-structure)
- [Core Data Structures](#data-structures)
- [Design Decisions You'll Make](#design-decisions)

**Core CDP Engine**
- [The StablecoinEngine Contract](#engine-contract)
- [Health Factor with Multi-Decimal Normalization](#health-factor)
- [Stability Fee Accrual via Rate Accumulator](#stability-fees)
- [The Vault Lifecycle](#vault-lifecycle)

**Vault Share Collateral Pricing (Deep Dive)**
- [The Pricing Challenge: Dynamic Exchange Rates](#pricing-challenge)
- [The Pricing Pipeline](#pricing-pipeline)
- [Manipulation Risk and Protection Strategies](#manipulation-risk)

**Dutch Auction Liquidation (Deep Dive)**
- [Designing Your Liquidation System](#liquidation-design)
- [Choosing a Decay Function](#decay-function)
- [Partial Fills and Bad Debt](#partial-fills)
- [Full Liquidation Flow Walkthrough](#liquidation-walkthrough)

**Flash Mint (Deep Dive)**
- [Flash Mint vs Flash Loan](#flash-mint-vs-loan)
- [ERC-3156 Adapted for Minting](#flash-mint-erc3156)
- [Security Considerations](#flash-mint-security)
- [Use Cases: Peg Stability and Beyond](#flash-mint-uses)

**Testing & Hardening**
- [The 5 Critical Invariants](#critical-invariants)
- [Fuzz and Fork Testing](#fuzz-fork)
- [Edge Cases to Explore](#edge-cases)

**Building & Wrap Up**
- [Suggested Build Order](#build-order)
- [⚠️ Common Mistakes](#common-mistakes)
- [Portfolio & Interview Positioning](#portfolio)
- [Production Study Order](#study-order)
- [How to Study MakerDAO's dss](#study-makerdao)
- [Cross-Module Concept Links](#cross-module-links)
- [Self-Assessment Checklist](#self-assessment)

---

## Overview & Design Philosophy

<a id="why-capstone"></a>
### 💡 Why a Stablecoin Capstone

You've spent 8 modules building DeFi primitives in isolation — an AMM here, a lending pool there, a vault somewhere else. A stablecoin protocol is where they all converge. It touches every primitive you've learned:

- **Token mechanics (M1)** — SafeERC20 for collateral handling, decimal normalization across token types
- **AMMs (M2)** — liquidation collateral sold via DEX, slippage determines liquidation economics
- **Oracles (M3)** — Chainlink price feeds drive health factor calculations
- **Lending math (M4)** — health factors, collateralization ratios, interest accrual indexes
- **Flash loans (M5)** — flash mint for the stablecoin itself (atomic mint + use + burn)
- **CDPs (M6)** — the core engine: normalized debt, rate accumulators, vault safety checks, liquidation
- **Vaults (M7)** — ERC-4626 vault shares as a collateral type, share pricing, inflation attack awareness
- **Security (M8)** — invariant testing across the whole system, oracle manipulation defense

Module 6's key takeaway said it: "Stablecoins are the ultimate integration test." This capstone is that test.

**This is not a guided exercise.** You built scaffolded exercises in M1-M8. This is different — you'll design the architecture, make trade-offs, and own every decision. The curriculum provides architectural guidance, design considerations, and deep dives on new concepts. The implementation is yours.

<a id="stablecoin-landscape"></a>
### 💡 The Stablecoin Landscape: Where Your Protocol Sits

Before designing, understand the field you're entering.

| Protocol | Collateral | Liquidation | Governance | Peg Mechanism |
|---|---|---|---|---|
| **DAI** (MakerDAO) | Multi (ETH, USDC, RWAs) | Dutch auction (Clipper) | MKR governance | PSM + DSR |
| **LUSD** (Liquity V1) | ETH only | Stability Pool | None (immutable) | Redemptions |
| **GHO** (Aave) | Aave aTokens | Aave liquidation | Aave governance | Facilitators |
| **crvUSD** (Curve) | wstETH, WBTC, etc. | LLAMMA (soft liq.) | veCRV governance | PegKeeper |
| **Your protocol** | ETH + ERC-4626 shares | Dutch auction | None (immutable) | Flash mint arbitrage |

Your protocol's design position: **immutable like Liquity, multi-collateral like MakerDAO, with vault shares as collateral like GHO uses aTokens, and flash mint for peg stability.** Each of these choices has a rationale you'll be able to articulate in an interview.

**The 2025-2026 landscape context:** The stablecoin space continues to evolve. Liquity V2 moved away from full immutability toward user-set interest rates. Ethena's USDe pioneered delta-neutral backing (crypto collateral + perpetual short hedge). RWA-backed stablecoins are growing but face regulatory pressure. Understanding the full spectrum — from fully decentralized (your protocol, Liquity V1) to fully centralized (USDC) — is what interviewers expect. Your protocol sits at the decentralized end, and you should be able to articulate why that position has both strengths (censorship resistance, no counterparty risk) and limitations (capital inefficiency, no adaptability).

**Historical lessons baked into your design:**
- **Black Thursday (March 2020):** MakerDAO's English auction liquidations (Liquidations 1.0 via `Flipper`) failed — network congestion during the crash spiked gas prices, preventing keepers from submitting competitive bids. Zero-bid auctions caused ~$8M in bad debt. This is why MakerDAO moved to Dutch auctions (Liquidations 2.0 via `Dog` + `Clipper`), and why your protocol uses Dutch auctions from day one.
- **LUNA/UST collapse (May 2022):** Algorithmic stablecoins without real collateral can enter a death spiral. Your protocol is fully collateral-backed — no algorithmic peg mechanism.
- **MakerDAO centralization creep:** DAI became 50%+ USDC-backed through the PSM, undermining decentralization. Your protocol accepts only crypto-native collateral — no fiat-backed assets.

> 📖 **Study these:** Before you start building, spend time reading [MakerDAO dss](https://github.com/makerdao/dss) (the canonical CDP protocol) and [Liquity](https://github.com/liquity/dev) (the immutable alternative). Your protocol borrows from both philosophies.

<a id="design-principles"></a>
### 💡 Design Principles: Immutable, Permissionless, Crypto-Native

Three principles define every design decision in your protocol.

**1. Immutable — No admin keys, no parameter changes**

Once deployed, the contracts govern themselves by their rules. No multisig can change LTV ratios, no governance vote can adjust stability fees, no emergency admin can pause the system.

Why: eliminates the entire governance attack surface. No flash loan governance attacks (Module 8). No delegate corruption. No regulatory capture via governance tokens.

Trade-off: can't fix bugs, can't adapt to market changes. If your parameters are wrong, you deploy a new version. Liquity V1 proved this model works — but Liquity V2 moved away from it because the rigidity became a limitation. For this capstone, immutability is the right choice: it's the harder design challenge (you must get parameters right the first time) and the more impressive portfolio piece.

**2. Permissionless — Anyone can participate in every role**

- Anyone can open a CDP and mint stablecoins
- Anyone can liquidate an underwater position
- Anyone can use flash mint
- No whitelists, no KYC gates, no privileged roles

**3. Crypto-native collateral only — No fiat-backed assets**

ETH and ERC-4626 vault shares. No USDC, no RWAs, no tokens that a centralized entity can freeze. This eliminates centralization risk — the controversy with DAI where 50%+ of its collateral was USDC-backed.

Trade-off: harder to maintain peg without fiat-backed collateral. This is why flash mint matters — it provides the arbitrage mechanism that keeps the peg without relying on a PSM backed by centralized stablecoins.

<a id="prerequisite-map"></a>
### 🔗 Cross-Module Prerequisite Map

Before you start, verify you're comfortable with these concepts from earlier modules. Each one directly maps to a component you'll build.

| Module | Concept | Where You'll Use It |
|---|---|---|
| **M1** | SafeERC20, decimal normalization | All token transfers; multi-decimal health factor |
| **M3** | Chainlink integration, staleness checks | PriceFeed.sol — ETH/USD with safety checks |
| **M4** | Health factor, liquidation threshold | StablecoinEngine.sol — vault safety check |
| **M4** | Interest rate math (compound index) | Stability fee accrual in the engine |
| **M5** | ERC-3156 flash loan interface | Stablecoin.sol — flash mint implementation |
| **M6** | Normalized debt (`art × rate`), frob | Engine's deposit/mint/repay flow |
| **M6** | Rate accumulator, `rpow()`, `drip()` | Stability fee compounding per collateral type |
| **M6** | Dutch auction (bark/take, SimpleDog) | DutchAuctionLiquidator.sol |
| **M6** | WAD/RAY/RAD precision scales | All arithmetic throughout the protocol |
| **M7** | ERC-4626, `convertToAssets()` | Vault share collateral pricing |
| **M7** | Inflation attack defense | Rate cap for vault share pricing |
| **M8** | Invariant testing methodology | 5-invariant test suite with handler |
| **M8** | Oracle manipulation awareness | PriceFeed defensive design |

If any of these feel fuzzy, revisit the module before starting. This capstone assumes you've internalized them.

### 📋 Summary: Overview & Design Philosophy

**✓ Covered:**
- Why a stablecoin is the ultimate Part 2 integration — touches every primitive from M1-M8
- Stablecoin landscape — where your protocol sits vs DAI, LUSD, GHO, crvUSD
- Three design principles — immutable, permissionless, crypto-native — with trade-offs
- Prerequisite map — 13 specific concepts from 7 modules that directly map to your protocol

**Key insight:** The stablecoin landscape is defined by trade-offs between decentralization, capital efficiency, and adaptability. Your protocol maximizes decentralization (no governance, no fiat collateral) at the cost of adaptability. That's a defensible design position — the same one Liquity V1 took.

**Next:** Designing the architecture — how many contracts, what data structures, and the key decisions you'll make before writing a line of code.

---

## Architecture Design

<a id="contract-structure"></a>
### 💡 Contract Structure: The 4 Core Contracts

Your protocol has four contracts with clear responsibilities and clean interfaces between them.

```
                         ┌─────────────────────┐
                         │  Stablecoin.sol      │
                         │  (ERC-20 + Flash)    │
                         └─────────┬───────────┘
                                   │ mint / burn
                         ┌─────────┴───────────┐
                         │ StablecoinEngine.sol │
                         │   (CDP Core Logic)   │
                         ├─────────────────────┤
                         │ • Vault storage      │
                         │ • Health factor      │
                         │ • Rate accumulator   │
                         │ • Deposit/Mint/etc   │
                         └──┬──────────────┬───┘
                            │              │
               ┌────────────┴──┐    ┌──────┴──────────────────┐
               │ PriceFeed.sol │    │ DutchAuctionLiquidator  │
               │ (Oracle Agg)  │    │ (MEV-resistant auctions)│
               └───────────────┘    └─────────────────────────┘
```

**StablecoinEngine.sol** — The core. Stores all vault state: collateral amounts, normalized debt per vault, rate accumulators and collateral configurations per collateral type. Handles the complete vault lifecycle: deposit collateral, mint stablecoin, repay debt, withdraw collateral, close vault. Calls PriceFeed for pricing, calls Stablecoin for mint/burn. Exposes view functions for health factor and liquidation eligibility that the Liquidator reads.

**PriceFeed.sol** — Oracle aggregation with two pricing paths. Path 1 (ETH): Chainlink ETH/USD with staleness check. Path 2 (vault shares): `convertToAssets()` to get underlying amount, then Chainlink price for the underlying, with rate cap protection against manipulation. Returns prices in a consistent decimal base.

**DutchAuctionLiquidator.sol** — Receives notification (or checks) that a vault is liquidatable. Starts an auction: collateral for sale at a declining price. Anyone can call `buyCollateral()` at the current price. Handles partial fills, refunds remaining collateral to vault owner when debt is covered, tracks bad debt when auctions don't fully recover.

**Stablecoin.sol** — ERC-20 with two additional capabilities: (1) only the Engine can mint/burn for CDP operations, and (2) anyone can flash mint via the ERC-3156 interface. Clean, minimal token contract.

> **🔗 Connection:** This 4-contract architecture mirrors MakerDAO's separation (Vat = Engine, Spotter = PriceFeed, Dog+Clipper = Liquidator, Dai = Stablecoin) but simplified. You studied MakerDAO's modular architecture in Module 6 — same philosophy, cleaner boundaries.

<a id="data-structures"></a>
### 💡 Core Data Structures

These are the key structs you'll design. Think carefully about what goes where — per-vault vs per-collateral-type vs global.

**Per-vault state:**

```solidity
struct Vault {
    uint256 collateralAmount;    // [WAD] collateral deposited
    uint256 normalizedDebt;      // [WAD] debt / rate at time of borrow
    // Actual debt = normalizedDebt × rateAccumulator
}
```

> **🔗 Connection:** This is exactly M6's `ink` (collateral) and `art` (normalized debt) from the Vat. The actual debt = `art × rate` pattern you implemented in SimpleVat's `frob()`.

**Per-collateral-type configuration:**

```solidity
struct CollateralConfig {
    address token;                // ERC-20 address (WETH or ERC-4626 vault)
    address priceFeed;            // Chainlink feed for this collateral's underlying
    bool isVaultToken;            // true = ERC-4626 (needs two-step pricing)
    uint256 liquidationThreshold; // [BPS] e.g., 8250 = 82.5%
    uint256 liquidationBonus;     // [BPS] e.g., 500 = 5%
    uint256 debtCeiling;          // [WAD] max stablecoin mintable against this type
    uint256 rateAccumulator;      // [RAY] starts at 1e27, grows per-second
    uint256 stabilityFeeRate;     // [RAY] per-second compound rate
    uint256 lastUpdateTime;       // timestamp of last drip
    uint256 totalNormalizedDebt;  // [WAD] sum of all vaults' normalizedDebt for this type
    uint8 tokenDecimals;          // cached decimals of the collateral token itself
    uint8 underlyingDecimals;     // for vault tokens: decimals of the underlying asset (ignored for non-vault)
}
```

Design considerations:
- **Why `normalizedDebt` instead of actual debt?** Same reason as MakerDAO's `art` — you update one global `rateAccumulator` instead of touching every vault's debt individually. You built this in M6's SimpleJug.
- **Why `isVaultToken` flag?** The pricing path differs: ETH uses one Chainlink lookup, vault shares need `convertToAssets()` + Chainlink for the underlying. One flag, two code paths.
- **Why `tokenDecimals` cached?** Gas. You'll call decimal normalization on every health factor check. Calling `ERC20(token).decimals()` every time costs ~2,600 gas per SLOAD. Caching saves this on the hot path.

<a id="design-decisions"></a>
### 💡 Design Decisions You'll Make

These are real architectural choices with trade-offs. Think through each one before coding. There's no single right answer — what matters is that you can explain *why* you chose what you chose.

**Decision 1: WAD/RAY precision or simpler scheme?**

- **WAD (10^18) + RAY (10^27):** Battle-tested. MakerDAO uses it. Maximum precision for per-second compounding — a rate of 2% annually is `1000000000627937192491029810` in RAY. You already worked with this in M6.
  - Pro: Proven, precise over long time periods.
  - Con: Verbose, easy to mix up WAD and RAY in the same expression.
- **All WAD (10^18):** Simpler, but loses precision for very small per-second rates.
  - Pro: One scale, fewer conversion bugs.
  - Con: Rate precision may drift over months/years.

**Decision 2: Liquidation trigger — push vs pull?**

- **Pull (recommended):** The Liquidator checks the Engine (`isLiquidatable(user)`) and initiates the auction. Keepers call the Liquidator directly.
  - Pro: Simple, clear separation of concerns. MakerDAO's Dog does this.
- **Push:** The Engine notifies the Liquidator when a vault becomes unhealthy.
  - Con: Who triggers the Engine to check? You still need keepers.

**Decision 3: Bad debt handling**

When a Dutch auction expires without fully covering the debt, someone must eat the loss.

- **Track as protocol debt:** Accumulate bad debt in a global variable. It exists as unbacked stablecoin in circulation. Stability fees can gradually offset it (if the protocol generates surplus).
  - Pro: Simple, transparent. MakerDAO's `sin` (system debt) works this way.
- **Socialize across holders:** Effectively devalue the stablecoin by adjusting backing ratio.
  - Pro: Automatically resolves. Con: Breaks the $1 peg expectation.
- **Stability pool (Liquity model):** Depositors absorb bad debt in exchange for liquidation collateral.
  - Pro: Elegant. Con: Significant additional complexity.

**Decision 4: Flash mint fee — zero or nonzero?**

- **Zero fee:** Maximizes arbitrage incentive for peg maintenance. If the stablecoin trades at $1.01, even a $1 profit opportunity will attract arbitrageurs. MakerDAO's DssFlash charges 0.
  - Pro: Strongest peg stability. Con: No revenue from flash mint.
- **Nonzero fee (e.g., 0.05%):** Revenue source, but reduces the arbitrage window. The stablecoin can trade at $1.00 ± fee before arbitrage kicks in.
  - Pro: Revenue. Con: Wider peg band.

**Decision 5: One vault per user per collateral type, or multiple vaults?**

- **One vault per (user, collateralType):** Simpler storage (`mapping(address => mapping(bytes32 => Vault))`). User can only have one position per collateral type.
  - Pro: Simple, gas efficient. Liquity does this.
- **Multiple vaults with IDs:** User can open many positions. More flexible but more complex.
  - Pro: Can manage risk separately. Con: More storage, more complexity.

**Decision 6: Collateral held in Engine or separate Join adapters?**

- **Engine holds collateral directly:** Simpler. `depositCollateral()` transfers tokens to the Engine contract.
  - Pro: Fewer contracts, fewer external calls.
- **Join adapters (MakerDAO model):** Separate contracts (`GemJoin`) handle token-specific logic. The Engine only tracks internal accounting.
  - Pro: Engine stays token-agnostic. Adding a new collateral type just means deploying a new Join.
  - Con: More contracts, more calls. Overkill for 2 collateral types.

> Think through these before writing code. Your answers shape the entire architecture. Write them down — they become your Architecture Decision Record for the portfolio.

### 💡 Deployment & Authorization

Your 4 contracts have mutual dependencies. Think about deployment order and how contracts authorize each other:

- **Stablecoin** needs to know the Engine address (only Engine can mint/burn for CDPs)
- **Engine** needs to know PriceFeed and Stablecoin addresses
- **Liquidator** needs permission to call Engine's `seizeCollateral()`
- **PriceFeed** is standalone (no dependencies on other protocol contracts)

Since the protocol is immutable (no setters), these addresses must be set at deployment. One pattern: deploy PriceFeed first (no dependencies), then Stablecoin with Engine address as constructor arg (requires knowing Engine address — use `CREATE2` for deterministic addresses, or deploy Stablecoin with a placeholder and use an immutable initializer pattern).

This is a real production concern — MakerDAO's deployment scripts handle complex interdependencies across 10+ contracts. Your 4-contract system is simpler, but the authorization wiring still needs to be correct.

### 💡 Storage Layout Considerations

For gas optimization on the hot path (health factor checks happen on every mint/withdraw), think about how `CollateralConfig` fields pack into storage slots:

- Fields read together on the hot path: `rateAccumulator` (RAY — uint256, full slot), `totalNormalizedDebt` (WAD — uint256, full slot), `liquidationThreshold` and `liquidationBonus` (BPS values — could fit as uint16 in a packed slot with `tokenDecimals`, `underlyingDecimals`, and `isVaultToken`)
- Fields read less often: `debtCeiling`, `stabilityFeeRate`, `lastUpdateTime`

Packing BPS values as `uint16` (max 65,535 — more than enough for basis points) saves SLOADs on the hot path. This is the same optimization pattern Aave V3 uses in its reserve configuration bitmap (M4).

### 📋 Summary: Architecture Design

**✓ Covered:**
- 4-contract structure with clear responsibilities and data flow
- Core data structures — Vault (per-position) and CollateralConfig (per-type)
- 6 design decisions with trade-offs the user must resolve before coding
- Deployment order and cross-contract authorization
- Storage layout optimization for gas-efficient health factor checks

**Key insight:** The architecture IS the project. Getting the contract boundaries, data structures, and design decisions right before writing code is the difference between a clean protocol and a tangled mess. This is how protocol teams work — architecture review before implementation.

**Next:** Deep dive into the core CDP engine — health factor math, stability fees, and the vault lifecycle.

> **🧭 Checkpoint — Before Moving On:**
> Can you sketch the 4-contract architecture from memory? Can you name the 6 design decisions and articulate a preference (with rationale) for each? If you can't, re-read this section — the architecture IS the project, and changing it mid-build is expensive.

---

## Core CDP Engine

<a id="engine-contract"></a>
### 💡 The StablecoinEngine Contract

This is where the core logic lives. The Engine manages all vaults, tracks all debt, and enforces all safety rules.

**External functions:**

```solidity
// Vault lifecycle
function depositCollateral(bytes32 collateralType, uint256 amount) external;
function withdrawCollateral(bytes32 collateralType, uint256 amount) external;
function mintStablecoin(bytes32 collateralType, uint256 amount) external;
function repayStablecoin(bytes32 collateralType, uint256 amount) external;

// Rate accumulator
function drip(bytes32 collateralType) external;

// View functions (used by Liquidator and externally)
function getHealthFactor(address user, bytes32 collateralType) external view returns (uint256);
function isLiquidatable(address user, bytes32 collateralType) external view returns (bool);
function getVaultInfo(address user, bytes32 collateralType) external view returns (uint256 collateral, uint256 debt);

// Liquidation support (called by Liquidator only)
function seizeCollateral(address user, bytes32 collateralType, uint256 collateralAmount, uint256 debtToCover) external;
```

> **🔗 Connection:** Compare this interface to M6's SimpleVat. `depositCollateral` + `mintStablecoin` together are `frob()` with positive `dink` and `dart`. `seizeCollateral` is `grab()`. Same patterns, cleaner API.

<a id="health-factor"></a>
### 🔍 Deep Dive: Health Factor with Multi-Decimal Normalization

Health factor is the core solvency check. You implemented it in M4 (LendingPool) and saw it in M6 (Vat's safety check: `ink × spot ≥ art × rate`). The new challenge here: your protocol has **two collateral types with different pricing paths and different decimals**, and the health factor must handle both correctly.

**The formula:**

```
Health Factor = (collateral_value_usd × liquidation_threshold) / actual_debt_usd
```

Where:
- `collateral_value_usd` depends on collateral type (ETH vs vault shares — different pricing)
- `actual_debt = normalizedDebt × rateAccumulator`
- `HF ≥ 1.0` → safe. `HF < 1.0` → liquidatable.

**Numeric walkthrough — ETH collateral:**

```
Given:
  collateral    = 10 ETH            (18 decimals → 10e18)
  normalizedDebt = 15,000            (18 decimals → 15_000e18)
  rateAccumulator = 1.02e27          (RAY — 2% accumulated fees)
  ETH/USD price = $3,000             (Chainlink 8 decimals → 3000e8)
  liq. threshold = 82.5%             (BPS → 8250)

Step 1: Actual debt
  actualDebt = normalizedDebt × rateAccumulator / 1e27
             = 15_000e18 × 1.02e27 / 1e27
             = 15_300e18  (WAD)

Step 2: Collateral value in USD (normalize to 8 decimals)
  collateralUSD = collateral × ethPrice / 10^tokenDecimals
                = 10e18 × 3000e8 / 1e18
                = 30_000e8

Step 3: Debt value in USD (stablecoin = $1, 18 decimals)
  debtUSD = actualDebt × 1e8 / 1e18
          = 15_300e18 × 1e8 / 1e18
          = 15_300e8

Step 4: Health factor (scale to 1e18)
  HF = collateralUSD × liqThreshold × 1e18 / (debtUSD × 10000)
     = 30_000e8 × 8250 × 1e18 / (15_300e8 × 10000)
     = 1.617e18  (1.617 — healthy)
```

**Numeric walkthrough — ERC-4626 vault share collateral:**

```
Given:
  shares          = 100 vault shares  (18 decimals → 100e18)
  vault exchange  = 1 share = 1.05 WETH (vault has earned 5% yield)
  normalizedDebt  = 200,000            (18 decimals → 200_000e18)
  rateAccumulator = 1.01e27            (RAY)
  ETH/USD price   = $3,000             (Chainlink 8 decimals → 3000e8)
  liq. threshold  = 75%                (BPS → 7500)

Step 1: Actual debt
  actualDebt = 200_000e18 × 1.01e27 / 1e27 = 202_000e18

Step 2: Convert shares to underlying
  underlyingAmount = vault.convertToAssets(100e18) = 105e18 WETH

Step 3: Price underlying in USD
  collateralUSD = underlyingAmount × ethPrice / 10^underlyingDecimals
                = 105e18 × 3000e8 / 1e18
                = 315_000e8

Step 4: Debt value in USD
  debtUSD = 202_000e18 × 1e8 / 1e18 = 202_000e8

Step 5: Health factor
  HF = 315_000e8 × 7500 × 1e18 / (202_000e8 × 10000)
     = 1.170e18  (1.17 — healthy, but tighter than the ETH vault)
```

**The pattern:** Always track decimal counts explicitly at every step. Write them in comments during development. The most common integration bug is comparing values with different decimal bases.

> **🔗 Connection:** You practiced this exact decimal normalization in M4's health factor exercise. The addition here is the vault share pricing path (Step 2 above), which adds the `convertToAssets()` layer.

<a id="stability-fees"></a>
### 💡 Stability Fee Accrual via Rate Accumulator

Your stability fee system is the same pattern you built in M6's SimpleJug. Each collateral type has its own `rateAccumulator` that grows per-second via compound interest.

**The pattern:**

```solidity
function drip(bytes32 collateralType) external {
    CollateralConfig storage config = configs[collateralType];
    uint256 timeDelta = block.timestamp - config.lastUpdateTime;
    if (timeDelta == 0) return;

    // Per-second compounding: rate^timeDelta
    uint256 rateMultiplier = rpow(config.stabilityFeeRate, timeDelta, RAY);
    uint256 oldRate = config.rateAccumulator;
    uint256 newRate = oldRate * rateMultiplier / RAY;
    config.rateAccumulator = newRate;
    config.lastUpdateTime = block.timestamp;

    // Mint fee revenue to maintain the backing invariant
    // This is what MakerDAO's fold() does — increase surplus by the fee amount
    uint256 feeRevenue = config.totalNormalizedDebt * (newRate - oldRate) / RAY;
    if (feeRevenue > 0) {
        stablecoin.mint(surplus, feeRevenue);
    }
}
```

> **🔗 Connection:** This IS `SimpleJug.drip()` with an important addition: minting fee revenue to a surplus address. In M6's SimpleJug, `drip()` called `vat.fold()` which internally increased the Vat's `dai` balance for `vow`. Your version achieves the same by minting ERC-20 stablecoin directly. Without this step, the Backing invariant (`totalSupply == totalDebt + badDebt`) breaks after the first fee accrual. You already built `rpow()` (exponentiation by squaring in assembly) in M6. Reuse or adapt that implementation.

**Numeric example — rate accumulator growth over time:**

For a 5% annual stability fee, the per-second rate in RAY is `1000000001547125957863212448` (~1.0 + 5%/year per second).

```
Day 0:   rateAccumulator = 1.000000000e27
Day 1:   rateAccumulator = 1.000133681e27  (vault with 10,000 normalizedDebt owes 10,001.34)
Day 7:   rateAccumulator = 1.000936140e27  (owes 10,009.36)
Day 30:  rateAccumulator = 1.004018202e27  (owes 10,040.18)
Day 365: rateAccumulator = 1.050000000e27  (owes 10,500.00 — exactly 5%)
```

Note: the daily values are slightly less than simple interest (5% / 365 = 0.01370%/day) because per-second compounding distributes interest differently than simple division. With compound interest, the rate per period is smaller but applied more frequently — the total converges to 5% at year-end, but intermediate values differ from `principal × annualRate × daysFraction`. The difference is negligible but verifiable — use this as a sanity check when testing your `drip()` implementation.

Two collateral types compound independently. If ETH-type was last dripped 30 days ago and vault-share-type was dripped 1 day ago, their rate accumulators will differ — each tracks its own accumulated fees.

> **Note on `rpow()` precision:** MakerDAO's `rpow()` uses floor rounding (rounds down). This means the rate accumulator slightly under-accrues over long periods. The effect is negligible in practice but worth knowing — it's a conservative design choice that slightly favors borrowers.

**When to call `drip()`** — this is critical:

```
depositCollateral  → drip NOT needed (no debt change)
withdrawCollateral → drip NEEDED    (health factor uses current debt)
mintStablecoin     → drip NEEDED    (debt changes, must be current)
repayStablecoin    → drip NEEDED    (same reason)
liquidation check  → drip NEEDED    (health factor must use current debt)
seizeCollateral    → drip NEEDED    (debt settlement must be accurate)
```

The rule: **drip before any operation that reads or modifies debt.**

<a id="vault-lifecycle"></a>
### 💡 The Vault Lifecycle

The complete lifecycle with what changes in storage at each step:

```
  depositCollateral            mintStablecoin
  ┌──────┐                     ┌──────┐
  │ User │ ──→ collateral ──→ │Engine│ ──→ stablecoin ──→ User
  │      │     to Engine       │      │     minted
  └──────┘                     └──────┘

  vault.collateralAmount += amount    vault.normalizedDebt += amount * RAY / rateAccumulator
  totalNormalizedDebt unchanged       totalNormalizedDebt += same
  tokens transferred IN               tokens minted to user
  NO health check needed              Health factor checked AFTER (must be ≥ 1.0)
```

```
  repayStablecoin              withdrawCollateral
  ┌──────┐                     ┌──────┐
  │ User │ ──→ stablecoin ──→ │Engine│ ──→ collateral ──→ User
  │      │     to burn         │      │     returned
  └──────┘                     └──────┘

  vault.normalizedDebt -= amount * RAY / rateAccumulator    vault.collateralAmount -= amount
  totalNormalizedDebt -= same                          totalNormalizedDebt unchanged
  tokens burned                                        tokens transferred OUT
  NO health check needed                               Health factor checked AFTER
```

```
  Liquidation path (when HF < 1.0):

  Liquidator detects HF < 1.0
       │
       ▼
  Start Dutch auction (DutchAuctionLiquidator)
       │
       ▼
  Bidder calls buyCollateral() at current price
       │
       ├──→ Engine.seizeCollateral(): reduce vault's collateral + debt
       ├──→ Stablecoin burned (debt repaid)
       └──→ Collateral transferred to bidder
```

### 📋 Summary: Core CDP Engine

**✓ Covered:**
- Engine contract interface — 10 external functions with clear responsibilities
- Health factor with multi-decimal normalization — full numeric walkthroughs for both ETH and vault share collateral
- Stability fee accrual — `drip()` pattern from M6, when to call it
- Vault lifecycle — state changes at each step, liquidation path

**Key insight:** The Engine is conceptually simple — it's M6's Vat with a cleaner interface. The complexity is in getting the decimal normalization right across two collateral types and ensuring `drip()` is called at every point where debt accuracy matters.

**Next:** The pricing challenge that makes vault share collateral interesting — and dangerous.

---

## Vault Share Collateral Pricing

<a id="pricing-challenge"></a>
### 🔍 Deep Dive: The Pricing Challenge

ETH is straightforward to price: one Chainlink lookup, done. ERC-4626 vault shares are fundamentally different — their value changes continuously as the vault earns yield.

**The problem:** A vault share's price depends on two things:
1. The vault's exchange rate (`convertToAssets()`) — how many underlying tokens each share represents
2. The underlying token's USD price (Chainlink)

Both can change independently. The exchange rate changes as the vault earns yield (or suffers losses). The underlying price changes with the market. And crucially, the exchange rate can be **manipulated** via donation (you studied this in M7's inflation attack).

**The two pricing paths side by side:**

```
ETH collateral (one step):
  ┌──────────┐    Chainlink     ┌───────────┐
  │ ETH amt  │ ──────────────→  │ USD value │
  │ (18 dec) │    ETH/USD       │ (8 dec)   │
  └──────────┘    (8 dec)       └───────────┘

ERC-4626 vault shares (two steps):
  ┌──────────┐  convertToAssets  ┌────────────┐   Chainlink    ┌───────────┐
  │ shares   │ ───────────────→  │ underlying │ ────────────→  │ USD value │
  │ (18 dec) │   exchange rate   │ (18 dec)   │   ETH/USD     │ (8 dec)   │
  └──────────┘                   └────────────┘   (8 dec)      └───────────┘
                  ▲ manipulable!
```

The extra step is where the complexity — and the security risk — lives.

<a id="pricing-pipeline"></a>
### 💡 The Pricing Pipeline

**Two-step pricing for vault shares:**

```
Step 1: shares → underlying amount
  vault.convertToAssets(sharesAmount) → underlyingAmount

Step 2: underlying amount → USD value
  underlyingAmount × chainlinkPrice / 10^underlyingDecimals → USD value
```

**Compared to ETH pricing (one step):**

```
collateralAmount × chainlinkPrice / 10^18 → USD value
```

The Solidity for the PriceFeed might look like:

```solidity
function getCollateralValueUSD(
    bytes32 collateralType,
    uint256 amount
) external view returns (uint256 valueUSD) {
    CollateralConfig memory config = engine.getConfig(collateralType);

    if (config.isVaultToken) {
        // Two-step: shares → underlying → USD
        // NOTE: convertToAssets returns underlying token decimals, NOT vault share decimals
        uint256 underlyingAmount = IERC4626(config.token).convertToAssets(amount);
        uint256 price = _getChainlinkPrice(config.priceFeed);
        valueUSD = underlyingAmount * price / (10 ** config.underlyingDecimals);
    } else {
        // One-step: amount → USD
        uint256 price = _getChainlinkPrice(config.priceFeed);
        valueUSD = amount * price / (10 ** config.tokenDecimals);
    }
}
```

<a id="manipulation-risk"></a>
### ⚠️ Manipulation Risk and Protection Strategies

**The attack:** An attacker donates tokens directly to the ERC-4626 vault, inflating `totalAssets()` without minting shares. This inflates `convertToAssets()` for all existing shares — including those used as collateral in your protocol.

```
Before donation:
  vault has 1000 WETH, 1000 shares → 1 share = 1.0 WETH

Attacker donates 500 WETH directly to vault:
  vault has 1500 WETH, 1000 shares → 1 share = 1.5 WETH (50% inflated!)

Attacker's 100 shares as collateral:
  Before: 100 × 1.0 × $3,000 = $300,000
  After:  100 × 1.5 × $3,000 = $450,000 (artificially inflated)

Attacker mints more stablecoin against the inflated collateral value.
Donation is reversed (attacker withdraws or gets liquidated elsewhere).
Protocol is left with under-collateralized debt.
```

> **🔗 Connection:** This is the inflation attack from M7, but in a lending/CDP context rather than a vault deposit context. Same root cause, different exploitation path.

**Three defense strategies:**

**Strategy 1: Rate cap (recommended)**

Store the last known exchange rate. Enforce a maximum rate of increase (as a fixed BPS cap) per update. If the current rate exceeds the cap, use the capped rate. Update `lastKnownRate` whenever the current rate is within bounds.

```
lastKnownRate = 1.0 WETH per share
MAX_RATE_BPS = 100  (1% max increase per update)

maxRate = lastKnownRate × (10000 + MAX_RATE_BPS) / 10000 = 1.01

If convertToAssets() returns 1.5 (donation attack):
  safeRate = min(1.5, 1.01) = 1.01  ← attack neutralized
  lastKnownRate NOT updated (rate was capped)

If convertToAssets() returns 1.005 (legitimate yield):
  safeRate = min(1.005, 1.01) = 1.005  ← legitimate yield passes through
  lastKnownRate updated to 1.005 (for next check)
```

- Pro: Simple, effective, low gas overhead. The code in Common Mistake 3 shows exactly this pattern.
- Con: Legitimate large yield events (vault receiving liquidation proceeds) get capped temporarily. The cap must be tuned: too tight and legitimate yield is suppressed, too loose and donation attacks get through.

**Strategy 2: Exchange rate TWAP**

Accumulate exchange rate samples over time. Use the time-weighted average instead of the spot rate.

- Pro: Smooths out manipulation naturally.
- Con: More storage (cumulative samples), stale during rapid legitimate changes, more complex implementation.

**Strategy 3: Require redemption before deposit**

Don't accept vault shares directly. Require users to redeem their vault shares for the underlying token, then deposit the underlying.

- Pro: Eliminates manipulation entirely — you never call `convertToAssets()`.
- Con: Worse UX, users lose vault yield after depositing.

**Recommendation for the capstone:** Strategy 1 (rate cap). It's the simplest to implement correctly, demonstrates awareness of the manipulation vector, and is the kind of defense an interviewer would want to discuss. Document the other strategies as considered alternatives in your Architecture Decision Record.

### 📋 Summary: Vault Share Collateral Pricing

**✓ Covered:**
- Two-step pricing pipeline — shares → underlying → USD
- Manipulation risk — donation attack inflating exchange rate
- Three defense strategies with trade-offs
- Rate cap recommendation with numeric example

**Key insight:** Accepting yield-bearing tokens as collateral is a real design challenge that production protocols face (Aave accepting stETH, Morpho accepting PT tokens). The pricing pipeline and manipulation defense you build here is directly applicable to real protocol work. This is the kind of depth that separates a "tutorial project" from a "protocol designer's project."

**Next:** Designing your Dutch auction liquidation system.

> **🧭 Checkpoint — Before Moving On:**
> Take a piece of paper and trace a health factor calculation for vault share collateral end-to-end: shares → `convertToAssets()` → underlying amount → Chainlink price → USD value → HF formula. Include the rate cap check. If you can do this with concrete numbers (pick any), the pricing pipeline is solid. If the decimal normalization steps feel unclear, revisit the numeric walkthroughs above.

---

## Dutch Auction Liquidation

<a id="liquidation-design"></a>
### 💡 Designing Your Liquidation System

You built a Dutch auction liquidator in M6's SimpleDog exercise — `bark()` to start an auction and `take()` for bidders to buy collateral at the declining price. Your capstone liquidation system follows the same pattern, adapted for your protocol's architecture.

**The key differences from SimpleDog:**
- Your Liquidator is a **separate contract** that calls the Engine's `seizeCollateral()`
- You handle **two collateral types** (ETH and vault shares) with different pricing
- You need **bad debt tracking** when auctions don't fully recover
- The auction interacts with your PriceFeed for the starting price

**The flow:**

```
1. Keeper calls Liquidator.liquidate(user, collateralType)
2. Liquidator calls Engine.isLiquidatable(user, collateralType) → must be true
3. Liquidator creates auction: {lot, tab, startPrice, startTime, user, collateralType}
4. Price declines over time according to decay function
5. Bidder calls Liquidator.buyCollateral(auctionId, maxAmount)
6. Liquidator calls Engine.seizeCollateral() to move collateral and reduce debt
7. Collateral transferred to bidder, stablecoin burned
8. If tab fully covered: remaining collateral refunded to vault owner
9. If auction expires without full coverage: remaining tab tracked as bad debt
```

<a id="decay-function"></a>
### 🔍 Deep Dive: Choosing a Decay Function

The decay function determines how the auction price decreases over time. This directly affects MEV resistance and liquidation efficiency.

**Option A: Linear decrease** (what you built in SimpleDog)

```
price(t) = startPrice × (duration - elapsed) / duration
```

```
Price
  |●  $3,600 (startPrice = oracle × 1.20)
  | \
  |  \
  |   \
  |    \
  |     \
  |      ● $0 at duration end
  └────────────────── Time
        duration
```

Pro: Simple, predictable. You already have a reference implementation.
Con: Linear decrease means the "sweet spot" for bidding is fairly narrow — price drops at the same rate throughout.

**Option B: Exponential step decrease** (MakerDAO's approach)

```
price(t) = startPrice × (1 - step)^(elapsed / stepDuration)
```

Example with step = 1% every 90 seconds:

```
Price
  |●  $3,600
  |●● $3,564 (after 90s)
  | ●● $3,528 (after 180s)
  |  ●●● $3,493 (after 270s)
  |    ●●●●
  |        ●●●●●●●
  |               ●●●●●●●●●●●●
  └──────────────────────────────── Time
```

Pro: Rapid initial decrease (finds fair price faster), slows down near the floor (less risk of bad debt). More capital efficient.
Con: Requires discrete step logic. MakerDAO's `StairstepExponentialDecrease` in `abaci.sol` is a good reference.

Numeric example: startPrice = $3,600, step = 1%, stepDuration = 90s:
```
t=0s:    $3,600.00
t=90s:   $3,600 × 0.99^1 = $3,564.00
t=180s:  $3,600 × 0.99^2 = $3,528.36
t=270s:  $3,600 × 0.99^3 = $3,493.08
t=900s:  $3,600 × 0.99^10 = $3,255.78  (10 steps, ~9.6% decrease)
t=1800s: $3,600 × 0.99^20 = $2,944.46  (20 steps, ~18.2% decrease)
```

**Option C: Continuous exponential**

```
price(t) = startPrice × e^(-k × elapsed)
```

Pro: Smoothest curve. Con: Requires `exp()` approximation on-chain, extra gas.

**Recommendation:** Option A (linear) for a clean implementation, Option B (exponential step) as a stretch goal. Both work — the key is understanding *why* the choice matters for MEV resistance and capital efficiency.

> 📖 **Study:** MakerDAO's [abaci.sol](https://github.com/makerdao/dss/blob/master/src/abaci.sol) implements all three decrease functions. Read `LinearDecrease`, `StairstepExponentialDecrease`, and `ExponentialDecrease` to see how a production protocol handles this choice.

<a id="partial-fills"></a>
### 💡 Partial Fills and Bad Debt

**Partial fills:** A bidder doesn't have to buy all the collateral. They specify a maximum amount, pay the current price, and the auction continues with the remaining lot. When the cumulative payments cover the full debt (`tab`), the auction ends and surplus collateral returns to the vault owner.

```
Auction: 10 ETH lot, 15,000 stablecoin tab

Bidder A at t=300s: buys 4 ETH at $3,200 → pays 12,800 stablecoin
  Remaining: 6 ETH lot, 2,200 tab

Bidder B at t=450s: wants 0.75 ETH at $2,934 → owe = $2,200.50
  But tab is only 2,200, so: owe capped to 2,200, slice = 2,200 / 2,934 = 0.7498 ETH
  Auction complete. 6 - 0.7498 = 5.2502 ETH returned to original vault owner.
```

> **🔗 Connection:** This is the same partial fill logic from M6's SimpleDog `take()` function. The `slice` and `owe` calculations carry directly.

**Bad debt:** When the auction expires (price reaches zero or floor) without fully covering the tab:

```
Auction: 10 ETH lot, 20,000 stablecoin tab
Total bids only covered 17,000 stablecoin.
Bad debt: 3,000 stablecoin exists in circulation with no backing.
```

Your protocol must track this: `totalBadDebt += uncoveredTab`. This bad debt represents stablecoin in circulation that isn't backed by collateral — a protocol-level liability. In MakerDAO, this is the `sin` (system debt) in the Vat. Stability fee revenue (`surplus`) can offset it over time: `surplus > sin → system is solvent despite past bad debt`.

<a id="liquidation-walkthrough"></a>
### 🔍 Deep Dive: Full Liquidation Flow Walkthrough

End-to-end with concrete numbers, including the rate accumulator update that's easy to forget.

```
Setup:
  Vault: 10 ETH collateral, normalizedDebt = 14,000e18
  rateAccumulator = 1.02e27 (2% accumulated fees)
  ETH/USD = $3,000 → drops to $1,700
  Liquidation threshold = 82.5% (8250 bps)
  Liquidation bonus = 5% (500 bps)
  Auction duration = 3600 seconds (1 hour)
  Start price buffer = 120% of oracle price

─── Step 1: Drip (update rate accumulator) ───
  Assume 1 day since last drip, stabilityFeeRate = 5% annual
  New rateAccumulator ≈ 1.020000137e27 (tiny increase — 1 day of 5% annual)
  For simplicity, keep 1.02e27

─── Step 2: Check health factor ───
  actualDebt = 14,000e18 × 1.02e27 / 1e27 = 14,280e18
  collateralUSD = 10e18 × 1700e8 / 1e18 = 17,000e8
  debtUSD = 14,280e18 × 1e8 / 1e18 = 14,280e8
  HF = 17,000e8 × 8250 × 1e18 / (14,280e8 × 10000) = 0.982e18

  HF < 1e18 → LIQUIDATABLE

─── Step 3: Start auction ───
  tab = actualDebt × (1 + liquidation bonus) = 14,280 × 1.05 = 14,994 stablecoin
  lot = 10 ETH
  startPrice = $1,700 × 1.20 = $2,040 per ETH

  Note: this "bonus as extra debt" approach means the bidder pays debt + bonus to the protocol.
  MakerDAO takes a different approach: the bidder buys collateral at a discount (bonus baked
  into the starting price). Both achieve the same economic result — the vault owner loses a
  penalty. Choose one and document why in your Architecture Decision Record.

─── Step 4: Bidder buys at t=600s (10 minutes) ───
  Linear price: $2,040 × (3600-600)/3600 = $1,700 per ETH
  Bidder wants all 10 ETH: cost = 10 × $1,700 = $17,000

  But tab is only 14,994. So:
  ETH needed to cover tab at $1,700: 14,994 / 1,700 = 8.82 ETH
  Bidder pays: 14,994 stablecoin (burned)
  Bidder receives: 8.82 ETH
  Refund to vault owner: 10 - 8.82 = 1.18 ETH

  Tab fully covered → auction complete
  Engine.seizeCollateral: vault's collateral = 0, vault's normalizedDebt = 0
  Bad debt: 0

  Backing invariant note: bidder burned 14,994 but vault debt was only 14,280.
  The 714 difference (liquidation bonus) is stablecoin burned beyond the debt —
  this reduces totalSupply more than debt decreased. To keep Invariant 2 balanced,
  the bonus portion must be routed to protocol surplus (or tracked as surplus revenue),
  NOT simply burned. Design this carefully — it mirrors the flash mint fee issue.
```

### 💡 Liquidation Economics: DEX Interaction

After a bidder receives collateral from the auction, they typically need to sell it on a DEX (AMM) to realize profit. This creates a connection to M2 that affects your protocol's design:

- **Bidder profitability depends on DEX liquidity depth.** If on-chain liquidity for your collateral type is thin, the slippage from selling seized collateral may exceed the auction discount. No one bids → bad debt accumulates.
- **Multiple simultaneous auctions** can flood the DEX with sell pressure, worsening slippage for all bidders. This is a cascading risk.
- **The auction starting price buffer (e.g., 120%) and decay speed must be calibrated** against realistic DEX slippage for your collateral types. ETH has deep liquidity; a niche ERC-4626 vault token may not.

This is why Aave governance evaluates on-chain liquidity depth before listing new collateral types — and why your choice of collateral (ETH + a vault wrapping a liquid asset like WETH) is a deliberate safety decision.

> **🔗 Connection:** The slippage and AMM economics from M2 directly determine whether your liquidation system actually works in practice. A liquidation mechanism is only as reliable as the DEX liquidity behind it.

### 📋 Summary: Dutch Auction Liquidation

**✓ Covered:**
- Liquidation system architecture — separate Liquidator contract calling Engine
- Three decay functions with trade-offs (linear, exponential step, continuous)
- Partial fills — bidders buy portions, surplus collateral returns to owner
- Bad debt — tracking unrecovered tab as protocol liability
- Full numeric walkthrough — drip → health check → auction → bid → settlement
- Liquidation economics — DEX liquidity depth determines bidder profitability and system health

**Key insight:** The Dutch auction is MEV-resistant because there's no single "optimal" moment to bid — every bidder chooses their own entry point based on their profit threshold. This is why MakerDAO moved from English auctions (Liquidations 1.0) to Dutch auctions (Liquidations 2.0) after Black Thursday — English auctions failed during network congestion because keepers couldn't bid. Your protocol inherits this lesson from day one.

**Next:** Flash mint — the mechanism that keeps your stablecoin pegged without a PSM.

---

## Flash Mint

<a id="flash-mint-vs-loan"></a>
### 🔍 Deep Dive: Flash Mint vs Flash Loan

Flash loans (M5) borrow existing tokens from a liquidity pool. Flash mint creates tokens from thin air. This is a fundamental difference:

| | Flash Loan | Flash Mint |
|---|---|---|
| **Source** | Pool liquidity (Aave, Balancer) | Minted by the protocol |
| **Limit** | Pool balance | `type(uint256).max` — unlimited |
| **Fee** | 0.05% (Aave), 0 (Balancer) | Protocol's choice (0 or small) |
| **Constraint** | Pool must have enough liquidity | None — protocol is the issuer |
| **Repayment** | Return tokens to pool | Tokens burned at end of tx |

> **🔗 Connection:** Module 5 briefly mentioned MakerDAO's DssFlash: "MakerDAO's `DssFlash` module lets anyone mint *unlimited* DAI via flash loan — not from a pool, but minted from thin air and burned at the end." Your Stablecoin.sol implements this exact pattern.

**Why flash mint matters for your protocol:**

Without governance and without a PSM (fiat-backed peg stability module), your protocol needs another peg mechanism. Flash mint provides it through **arbitrage**.

If your stablecoin trades above $1.00 on a DEX:
```
1. Flash mint 1,000,000 stablecoin (cost: 0)
2. Sell 1,000,000 stablecoin for $1,010,000 USDC on DEX
3. Buy 1,000,000 stablecoin for $1,000,000 on another venue
4. Repay flash mint
5. Profit: $10,000
```

This arbitrage pushes the price back toward $1.00. It requires zero capital and works atomically — anyone can do it, so the peg corrects quickly.

<a id="flash-mint-erc3156"></a>
### 💡 ERC-3156 Adapted for Minting

The ERC-3156 interface you learned in M5 maps directly to flash minting. The Stablecoin token itself implements `IERC3156FlashLender`:

```solidity
interface IERC3156FlashLender {
    function maxFlashLoan(address token) external view returns (uint256);
    function flashFee(address token, uint256 amount) external view returns (uint256);
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}
```

Key differences from a standard flash loan implementation:
- `maxFlashLoan()` returns `type(uint256).max` — infinite liquidity since you're minting, not lending from a pool
- `flashLoan()` calls `_mint()` instead of `transfer()`, and `_burn()` instead of `transferFrom()`
- The token lends *itself* — the Stablecoin contract is both the token and the flash lender

> 📖 **Study:** [MakerDAO's DssFlash](https://github.com/makerdao/dss-flash/blob/master/src/flash.sol) and [GHO's GhoFlashMinter](https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/flashMinter/GhoFlashMinter.sol) — two production implementations of flash mint.

<a id="flash-mint-security"></a>
### ⚠️ Security Considerations

**1. Callback reentrancy**

The `flashLoan()` function makes an external call to `receiver.onFlashLoan()`. During this callback, the flash-minted tokens exist in circulation — `totalSupply()` and `balanceOf(receiver)` are inflated.

Any external protocol that reads your stablecoin's `totalSupply()` or a specific `balanceOf()` during the callback sees manipulated values. This is read-only reentrancy (M8).

Defense: reentrancy guard on `flashLoan()`. Also, be aware that your own Engine should not make decisions based on stablecoin `totalSupply()` — use internal accounting (`totalNormalizedDebt × rateAccumulator`).

**2. Interaction with the Engine**

During a flash mint callback, the receiver holds minted stablecoin. They could use it to:
- Repay their own CDP debt (legitimate — this is actually useful for self-liquidation)
- Deposit it somewhere to manipulate a price or balance

The first use case is a *feature*, not a bug — flash mint for self-liquidation is a valid pattern. The key invariant: at the end of the transaction, the flash-minted stablecoin is burned. Whatever happened during the callback is permanent (debt repayment, collateral withdrawal), but the flash-minted tokens themselves are gone.

**3. Cross-contract reentrancy surface**

Beyond flash mint, consider the broader reentrancy surface across your 4 contracts. When `depositCollateral()` or `seizeCollateral()` calls `ERC20(token).transferFrom()`, the collateral token could trigger a callback (if it's ERC-777 or has transfer hooks). Your ERC-4626 vault token's underlying could have such hooks. The `Checks-Effects-Interactions` pattern (update state before external calls) and a reentrancy guard on state-changing functions in the Engine protect against this.

**4. Fee handling**

If fee is zero: `_burn(address(receiver), amount)`. Simpler, maximizes arbitrage incentive.

If you charge a fee: the receiver must hold `amount + fee` at the end of the callback. But you can't simply `_burn(amount + fee)` — that destroys the fee, breaking Invariant 2 (Backing). The fee stablecoin wasn't minted against any CDP debt, so burning it creates a gap between `totalSupply` and total debt. Instead: `_burn(amount)` to undo the flash mint, then `transferFrom(receiver, surplus, fee)` to route the fee to the protocol surplus address. This way the fee remains in circulation as protocol revenue, and the backing invariant holds.

<a id="flash-mint-uses"></a>
### 💡 Use Cases: Peg Stability and Beyond

1. **Peg arbitrage** — described above. The primary peg maintenance mechanism.
2. **Self-liquidation** — flash mint stablecoin → repay own debt → withdraw collateral → sell collateral for stablecoin → burn flash mint. Zero-capital exit from an underwater position.
3. **Liquidation funding** — flash mint stablecoin → buy collateral from Dutch auction → sell collateral on DEX → burn flash mint + keep profit. This is the flash liquidation pattern from M4/M5, but using flash *mint* instead of flash *loan*.
4. **Composability** — any protocol can integrate your stablecoin knowing that flash mint provides infinite temporary liquidity for atomic operations.

### 📋 Summary: Flash Mint

**✓ Covered:**
- Flash mint vs flash loan — minting from thin air vs borrowing from a pool
- Why flash mint is the peg mechanism for an immutable, no-PSM protocol
- ERC-3156 adapted for minting — same interface, different internals
- Security — callback reentrancy, Engine interaction, fee handling
- Use cases — peg arbitrage, self-liquidation, liquidation funding, composability

**Key insight:** Flash mint is what makes an immutable stablecoin viable without a PSM. MakerDAO relies on the PSM (backed by USDC) for peg stability. Liquity uses redemptions. Your protocol uses flash mint arbitrage. Each is a different solution to the same problem: "how does the stablecoin stay at $1?" Understanding the trade-offs between these mechanisms is exactly the kind of reasoning DeFi teams want to hear in an interview.

**Next:** Testing strategy — the 5 invariants that prove your protocol is sound.

---

## Testing & Hardening

<a id="critical-invariants"></a>
### 🔍 Deep Dive: The 5 Critical Invariants

Invariant testing (M8) is where you prove your protocol works under arbitrary sequences of operations. These 5 invariants are your protocol's correctness properties.

**Invariant 1: Solvency**

```
Across all collateral types:
  sum(collateralValueUSD for ALL vaults) ≥ sum(actualDebt for ALL vaults) - totalBadDebt
```

Why: the system must never be insolvent (excluding acknowledged bad debt). If this breaks, your stablecoin is under-collateralized. Note: this is a *global* invariant — bad debt is tracked globally, not per collateral type, so the comparison must also be global.

Caveat: this invariant can be temporarily violated between a price drop (making vaults underwater) and the completion of liquidation auctions. In invariant testing, the handler should include `liquidate` and `buyCollateral` operations so the fuzzer can process liquidations and restore solvency as part of the operation sequence.

Handler operations that test it: `depositCollateral`, `withdrawCollateral`, `mintStablecoin`, `repayStablecoin`, `moveOraclePrice`, `drip`, `liquidate`, `buyCollateral`.

**Invariant 2: Backing**

```
stablecoin.totalSupply() == sum(vault.normalizedDebt × rateAccumulator for all vaults) + totalBadDebt
```

Why: every stablecoin in circulation must have a corresponding source — either an active CDP's debt or acknowledged bad debt. If `totalSupply > sum(debts) + badDebt`, stablecoins were created without backing.

**Important design implication:** For this invariant to hold, `drip()` must mint new stablecoin to a surplus address when it increases `rateAccumulator`. Otherwise, debt grows (via compounding) but `totalSupply` stays the same — breaking the invariant after the very first fee accrual. This is what MakerDAO's `fold()` does: it increases the Vat's internal `dai` balance for `vow` (the surplus address) by the fee revenue amount. Your `drip()` must do the equivalent: `stablecoin.mint(surplus, debtIncrease)` where `debtIncrease = totalNormalizedDebt × (newRate - oldRate) / RAY`.

Note: during a flash mint callback, `totalSupply` is temporarily inflated. Your invariant check should not run mid-flash-mint (the handler shouldn't trigger a flash mint that's still in progress when checking invariants).

**Invariant 3: Accounting**

```
For every collateral type:
  collateralConfig.totalNormalizedDebt == sum(vault.normalizedDebt for all vaults of that type)
```

Why: the per-type total must match the sum of individual vaults. If this breaks, the debt ceiling enforcement is wrong.

**Invariant 4: Health**

```
For every vault where healthFactor(user, collateralType) < 1.0:
  an auction is active for that vault
```

Why: unhealthy vaults should not persist without a liquidation in progress. If this breaks, your protocol is failing to protect itself. In practice, this invariant may temporarily fail after a `moveOraclePrice` handler call makes vaults underwater before the fuzzer calls `liquidate`. To handle this: either check the invariant only after a `liquidate` call has been given a chance to run, or relax the invariant to allow a bounded number of unliquidated unhealthy vaults (the fuzzer should eventually process them).

**Invariant 5: Conservation**

```
For every collateral type:
  ERC20(token).balanceOf(engine) + ERC20(token).balanceOf(liquidator)
    == sum(vault.collateralAmount for that type) + collateralInActiveAuctions
```

Why: tokens must be accounted for across both contracts that hold collateral (the Engine for active vaults, the Liquidator for collateral being auctioned). No tokens created or destroyed outside of expected flows. If this breaks, collateral is leaking. Note: if your design keeps all collateral in the Engine (even during auctions), simplify to just `balanceOf(engine)`.

**Handler design:**

```solidity
contract SystemHandler is Test {
    // Bounded operations — each wraps protocol calls with realistic inputs
    function depositCollateral(uint256 seed, uint256 amount) external;
    function withdrawCollateral(uint256 seed, uint256 amount) external;
    function mintStablecoin(uint256 seed, uint256 amount) external;
    function repayStablecoin(uint256 seed, uint256 amount) external;
    function moveOraclePrice(uint256 seed, int256 deltaBps) external;  // bounded: ±20%
    function advanceTime(uint256 seconds_) external;                    // bounded: 1-86400
    function liquidate(uint256 seed) external;                          // picks a random vault
    function buyCollateral(uint256 seed, uint256 amount) external;
}
```

> **🔗 Connection:** This is the same handler + ghost variable + invariant assertion pattern from M8's VaultInvariantTest exercise. Same methodology, bigger system.

<a id="fuzz-fork"></a>
### 💡 Fuzz and Fork Testing

**Fuzz tests:** Beyond invariants, write targeted fuzz tests:
- Random deposit/mint sequences should never create a vault with HF < 1.0
- `repay(amount) → withdraw(max)` should always succeed if there's no other debt
- Random price movements followed by health checks should match manual calculation
- Flash mint with random amounts should always leave `totalSupply` unchanged after the tx

**Fork tests:** Deploy on a mainnet fork:
- Use real Chainlink ETH/USD feed — verify staleness checks work with actual feed behavior
- Use a real ERC-4626 vault (e.g., Yearn's yvWETH or a WETH vault) as collateral
- Measure gas for key operations: deposit, mint, liquidation check, auction bid. Rough targets: deposit/withdraw ~50-80K, mint/repay ~80-120K (includes drip), health factor view ~30-50K, auction bid ~100-150K
- Compare gas to production protocols (MakerDAO's `frob` is ~150-200K gas)

<a id="edge-cases"></a>
### ⚠️ Edge Cases to Explore

**Cascading liquidation:** Set up 3 vaults with tight health factors. Drop the price. Liquidate the first — does the Dutch auction's collateral sale affect the oracle price? (It shouldn't — Chainlink is off-chain. But if you added an on-chain oracle component, it could.)

**Stale oracle + liquidation:** What happens if a liquidator calls `liquidate()` but the Chainlink feed is stale (> heartbeat)? Your PriceFeed should revert, blocking the liquidation. This protects users from being liquidated on stale prices.

**Vault share exchange rate drop:** The underlying vault suffers a loss (hack, slashing event). Exchange rate drops suddenly. Many vault-share-backed CDPs become liquidatable simultaneously. Does your system handle a flood of auctions?

**Flash mint + self-liquidation race:** Can a user flash-mint stablecoin, repay their own debt to avoid liquidation, withdraw collateral, and repay the flash mint — all while a liquidation auction is already in progress? Think through the state transitions.

**Dust amounts:** What happens with 1 wei of collateral or 1 wei of debt? Rounding in the health factor calculation could allow dust vaults that are technically unhealthy but too small to profitably liquidate.

### 📋 Summary: Testing & Hardening

**✓ Covered:**
- 5 critical invariants — solvency, backing, accounting, health, conservation
- Handler design with 8 bounded operations
- Fuzz test targets — random sequences, edge conditions
- Fork test strategy — real Chainlink, real vaults, gas benchmarks
- Edge cases — cascading liquidations, stale oracles, exchange rate drops, dust

**Key insight:** The 5 invariants ARE your protocol's specification. If they hold under arbitrary operation sequences with random inputs and random price movements, your protocol is sound. Everything else — unit tests, edge cases, fork tests — is supporting evidence. The invariant suite is the proof.

> **🧭 Checkpoint — Before Starting to Build:**
> Can you list all 5 invariants from memory and explain what failure of each one would mean for the protocol? Can you describe at least 4 handler operations and how they interact with the invariants? If yes, you understand the system well enough to build it. If not, re-read the invariants — they are the specification you're implementing against.

---

<a id="build-order"></a>
## 🛠️ Suggested Build Order

This is guidance, not prescription. Adapt to your working style — but if you're not sure where to start, this sequence builds from simple to complex with testable milestones at each phase.

**Phase 1: The token (~half day)**

Build `Stablecoin.sol` first. It's the simplest contract — an ERC-20 with authorized mint/burn and flash mint. You can unit test it in isolation before any other contract exists. Getting ERC-3156 working early means you understand the flash mint callback pattern before wiring it into the system.

> **Checkpoint:** Deploy Stablecoin in a test, flash mint 1M tokens, verify `totalSupply` is unchanged after the tx.

**Phase 2: The oracle (~half day)**

Build `PriceFeed.sol` next. Two pricing paths: ETH via Chainlink, vault shares via `convertToAssets()` + Chainlink. Test with mock Chainlink feeds. Implement the rate cap for vault share pricing. This is standalone — no dependencies on other protocol contracts.

> **Checkpoint:** Mock Chainlink returns $3,000. Mock vault returns 1.05 rate. Verify PriceFeed returns correct USD values for both collateral types. Simulate a donation attack — verify rate cap catches it.

**Phase 3: The engine (~2-3 days)**

Build `StablecoinEngine.sol` — the core. This is the bulk of the work. Start with the simplest flow (deposit ETH + mint) and build outward: repay, withdraw, drip, health factor. Add vault share collateral support after ETH works end-to-end. Leave `seizeCollateral()` as a stub initially.

> **Checkpoint:** Full vault lifecycle with ETH: deposit → mint → warp time → drip → repay → withdraw. Health factor correct. Debt ceiling enforced. Then repeat with vault share collateral.

**Phase 4: The liquidator (~1-2 days)**

Build `DutchAuctionLiquidator.sol`. Wire it to the Engine's `seizeCollateral()`. Start with linear decay (you already built this pattern in M6's SimpleDog), then optionally upgrade to exponential step.

> **Checkpoint:** Create a vault, drop the oracle price, verify liquidation triggers, verify auction price decays, verify bidder receives collateral and stablecoin is burned. Test partial fills. Test bad debt path.

**Phase 5: Integration testing (~1-2 days)**

Wire everything together. Write the 5 invariant tests with the system handler. Run fuzz tests. Fork test with real Chainlink. Explore edge cases. Profile gas. Write your Architecture Decision Record.

> **Checkpoint:** All 5 invariants pass with depth ≥ 50, runs ≥ 256. Fork test works. Gas benchmarks logged.

---

<a id="common-mistakes"></a>
## ⚠️ Common Mistakes

**Mistake 1: Decimal mismatch in health factor**

```solidity
// WRONG: mixing decimal bases
uint256 collateralUSD = collateral * ethPrice;     // 18 + 8 = 26 decimals
uint256 debtUSD = debt * stablecoinPrice;           // 18 + 8 = 26 decimals... or is it?
uint256 hf = collateralUSD / debtUSD;               // If debt is already in stablecoin (18 dec), this is 26 vs 18
```

```solidity
// CORRECT: normalize to a common base at every step
uint256 collateralUSD = collateral * ethPrice / (10 ** tokenDecimals);  // → 8 decimals
uint256 debtUSD = actualDebt * 1e8 / 1e18;                              // → 8 decimals
// Note: full HF also multiplies by liqThreshold / 10000 — omitted here to focus on decimal normalization
uint256 hf = collateralUSD * 1e18 / debtUSD;                            // → 18 decimals
```

**Mistake 2: Not calling `drip()` before health factor check**

```solidity
// WRONG: rate accumulator is stale
function isLiquidatable(address user, bytes32 colType) external view returns (bool) {
    uint256 hf = _getHealthFactor(user, colType);  // uses stale rateAccumulator
    return hf < 1e18;
    // Debt appears lower than it actually is → healthy-looking vault is actually underwater
}
```

```solidity
// CORRECT: use current rate (either drip first or calculate inline)
function isLiquidatable(address user, bytes32 colType) external view returns (bool) {
    uint256 currentRate = _getCurrentRate(colType);  // calculates what rate WOULD be after drip
    uint256 hf = _getHealthFactorWithRate(user, colType, currentRate);
    return hf < 1e18;
}
```

**Mistake 3: Using `convertToAssets()` without rate cap**

```solidity
// WRONG: directly trusting vault exchange rate (manipulable via donation)
uint256 underlyingAmount = IERC4626(vault).convertToAssets(shares);
uint256 value = underlyingAmount * price / 1e18;
```

```solidity
// CORRECT: apply rate cap
uint256 currentRate = IERC4626(vault).convertToAssets(1e18);
uint256 maxRate = lastKnownRate * (10000 + MAX_RATE_BPS) / 10000;
uint256 safeRate = currentRate > maxRate ? maxRate : currentRate;
uint256 underlyingAmount = shares * safeRate / 1e18;
uint256 value = underlyingAmount * price / 1e18;
```

**Mistake 4: Auction price below debt → unhandled bad debt**

```solidity
// WRONG: assuming auction always covers tab
function buyCollateral(uint256 auctionId, uint256 maxAmount) external {
    // ... price calculation, transfer ...
    if (auction.lot == 0) {
        delete auctions[auctionId];  // auction done, but what if tab > 0 still?
    }
}
```

```solidity
// CORRECT: track bad debt when auction expires or lot is exhausted
if (auction.lot == 0 || _auctionExpired(auctionId)) {
    if (auction.tab > 0) {
        totalBadDebt += auction.tab;  // acknowledge the loss
    }
    delete auctions[auctionId];
}
```

**Mistake 5: Flash mint callback reentrancy**

```solidity
// WRONG: no reentrancy protection, burns fee instead of routing to surplus
function flashLoan(...) external returns (bool) {
    _mint(address(receiver), amount);
    receiver.onFlashLoan(msg.sender, token, amount, fee, data);  // external call!
    _burn(address(receiver), amount + fee);  // destroys fee — breaks Backing invariant
    return true;
}
// Two bugs: (1) during callback, totalSupply is inflated — any protocol reading it gets wrong value
// (2) burning amount+fee destroys the fee instead of routing it to surplus
```

```solidity
// CORRECT: reentrancy guard + awareness
function flashLoan(...) external nonReentrant returns (bool) {
    _mint(address(receiver), amount);
    require(
        receiver.onFlashLoan(msg.sender, token, amount, fee, data) == CALLBACK_SUCCESS,
        "callback failed"
    );
    _burn(address(receiver), amount);  // burn only the minted amount
    if (fee > 0) {
        // Route fee to surplus — don't burn it (see Security §4: Fee handling)
        stablecoin.transferFrom(address(receiver), surplus, fee);
    }
    return true;
}
```

**Mistake 6: Forgetting to burn stablecoin on repay**

```solidity
// WRONG: reducing debt but not burning the stablecoin
function repayStablecoin(bytes32 colType, uint256 amount) external {
    Vault storage vault = vaults[msg.sender][colType];
    vault.normalizedDebt -= amount * RAY / configs[colType].rateAccumulator;
    configs[colType].totalNormalizedDebt -= amount * RAY / configs[colType].rateAccumulator;
    // stablecoin is still in circulation, unbacked!
}
```

```solidity
// CORRECT: burn the stablecoin as debt is reduced
function repayStablecoin(bytes32 colType, uint256 amount) external {
    _drip(colType);
    Vault storage vault = vaults[msg.sender][colType];
    uint256 normalizedAmount = amount * RAY / configs[colType].rateAccumulator;
    vault.normalizedDebt -= normalizedAmount;
    configs[colType].totalNormalizedDebt -= normalizedAmount;
    stablecoin.burn(msg.sender, amount);  // CRITICAL: remove from circulation
}
```

**Mistake 7: Vault share redemption limits during liquidation**

```solidity
// WRONG: assuming vault shares can always be redeemed by the auction bidder
// ERC-4626 vaults can have withdrawal limits (maxWithdraw, maxRedeem)
// If the vault is at capacity or paused, the bidder receives shares they can't redeem
```

This isn't a code fix — it's a design awareness issue. Options:
- Accept vault shares as-is in the auction (bidder receives shares, their problem to redeem)
- Redeem to underlying during the auction (adds gas, may fail if vault is limited)
- Document the risk and let the market price it into auction bids

**Mistake 8: Stale rate accumulator on the wrong collateral type**

```solidity
// WRONG: dripping one type but operating on another
function mintStablecoin(bytes32 colType, uint256 amount) external {
    _drip(ETH_TYPE);  // oops — dripped ETH but minting against VAULT_SHARE_TYPE
    // ...
}
```

```solidity
// CORRECT: always drip the specific collateral type being operated on
function mintStablecoin(bytes32 colType, uint256 amount) external {
    _drip(colType);  // drip the correct type
    // ...
}
```

---

<a id="portfolio"></a>
## 💼 Portfolio & Interview Positioning

### What This Project Proves

- You can **design a multi-contract DeFi protocol** from scratch — not fill in TODOs, but make architectural decisions
- You understand **CDP mechanics deeply** — normalized debt, rate accumulators, health factors, liquidation
- You can handle **complex pricing challenges** — multi-decimal normalization, vault share pricing with manipulation defense
- You chose **Dutch auction over fixed-discount** and can explain why (MEV resistance, capital efficiency)
- You chose **immutable design** and can articulate the trade-offs vs governed protocols
- You can write **production-quality invariant tests** that prove system correctness

### Interview Questions This Prepares For

**1. "Walk me through building a CDP-based stablecoin from scratch."**
- Good: Describe the 4 contracts and their responsibilities.
- Great: Explain the design *decisions* — why immutable, why Dutch auction, why rate cap for vault share pricing. Show you understand the trade-off space, not just the implementation.

**2. "How would you handle ERC-4626 vault shares as collateral?"**
- Good: Two-step pricing — `convertToAssets()` then Chainlink for the underlying.
- Great: Identify the manipulation risk (donation attack), describe the rate cap defense, and explain why you chose it over TWAP or mandatory redemption.

**3. "What's the difference between a flash loan and a flash mint?"**
- Good: Flash loan borrows existing tokens, flash mint creates new ones.
- Great: Explain why flash mint provides infinite liquidity (no pool constraint), how it enables peg arbitrage without a PSM, and the security implications (totalSupply inflation during callback).

**4. "How do you prevent oracle manipulation in a CDP protocol?"**
- Good: Chainlink with staleness checks.
- Great: Distinguish ETH pricing (straightforward) from vault share pricing (manipulable exchange rate), explain the rate cap mechanism, and note that Chainlink itself is the residual trust assumption in an otherwise decentralized system.

**5. "What invariants would you test for a stablecoin protocol?"**
- Good: "Total supply should equal total debt."
- Great: List all 5 invariants, explain what each prevents, and describe the handler with 8 bounded operations that stress-tests them.

**6. "Why Dutch auction over other liquidation models?"**
- Good: "Less MEV, better price discovery."
- Great: Explain two failure modes — English auctions (MakerDAO Liq 1.0) failed on Black Thursday because network congestion prevented keeper bidding. Fixed-discount liquidation (Aave/Compound model) creates gas wars where all liquidators see the same profit → pure priority fee competition → MEV extraction. Dutch auctions solve both: they're non-interactive (no bidding rounds to miss) and provide natural price discovery — each bidder enters at their own threshold.

### Interview Red Flags

Things that signal "tutorial-level understanding" in a stablecoin interview:
- Suggesting fixed-discount liquidation without understanding the MEV problem it creates
- Not knowing the difference between algorithmic (UST) and collateral-backed (DAI) stablecoins
- Treating all collateral types as having the same pricing path (ignoring vault share exchange rate complexity)
- Saying "`totalSupply()` tells you the total stablecoin debt" — it doesn't during flash mint callbacks
- Not being able to explain why `drip()` must be called before health factor checks

**Pro tip:** In interviews, describe your protocol by its trade-off position first: "I chose immutability over adaptability, similar to Liquity V1, because..." This signals protocol design thinking, not just Solidity implementation skills. Teams want to hear you reason about the design space before diving into code details.

**Pro tip:** If asked about stablecoin peg mechanisms, compare at least three approaches (PSM, redemptions, flash mint arbitrage). Showing you understand the design space — not just one solution — is what separates senior candidates from mid-level ones.

### How to Present This

- Push to a public GitHub repo with a clear README
- Include an architecture diagram (the ASCII diagram from this doc, or a nicer one)
- Include a comparison table: your protocol vs MakerDAO vs Liquity (what's similar, what's different, why)
- Include gas benchmarks for core operations (deposit, mint, liquidation, auction bid)
- Show your invariant test results — this signals maturity beyond basic unit testing
- Write a brief Architecture Decision Record: the 6 design decisions and your rationale

---

<a id="study-order"></a>
## 📖 Production Study Order

Study these in order — each builds understanding for the next.

| # | Repository / Resource | Why Study This | Key Files |
|---|---|---|---|
| 1 | [MakerDAO Vat + Jug](https://github.com/makerdao/dss) | The foundational CDP engine — your Engine mirrors this | `vat.sol` (frob, grab), `jug.sol` (drip, rpow) |
| 2 | [MakerDAO Dog + Clipper](https://github.com/makerdao/dss) | Dutch auction liquidation — your Liquidator mirrors this | `dog.sol` (bark), `clip.sol` (kick, take), `abaci.sol` (decay functions) |
| 3 | [MakerDAO DssFlash](https://github.com/makerdao/dss-flash) | Flash mint reference — your Stablecoin's flash mint | `DssFlash.sol` (flashLoan, max, fee) |
| 4 | [Liquity V1](https://github.com/liquity/dev) | Immutable CDP alternative — different design philosophy | `BorrowerOperations.sol`, `TroveManager.sol`, `StabilityPool.sol` |
| 5 | [GHO Flash Minter](https://github.com/aave/gho-core) | Facilitator-based minting + flash mint implementation | `Gho.sol`, `GhoFlashMinter.sol` |
| 6 | [Reflexer RAI](https://github.com/reflexer-labs/geb) | Non-pegged stablecoin — the furthest point on the decentralization spectrum. Note: project is largely inactive/archived, but the codebase remains educational | `SAFEEngine.sol`, `OracleRelayer.sol` |

**Reading strategy:** Start with MakerDAO (1-3) since your protocol directly mirrors its patterns. Compare Liquity (4) for the immutable design philosophy — note how they handle peg without governance or PSM (redemptions). Study GHO (5) for flash mint implementation specifics. Read Reflexer RAI (6) if you want to understand the frontier of decentralized stablecoin design — no peg target, pure market-driven stability.

> **Note:** MakerDAO's `dss` repo is the "classic" Multi-Collateral DAI codebase. MakerDAO has since rebranded to Sky Protocol and launched Spark (lending arm), but the `dss` codebase remains the canonical reference for CDP mechanics. Focus on `dss` for this capstone.

<a id="study-makerdao"></a>
### 📖 How to Study MakerDAO's dss

MakerDAO's codebase uses terse, domain-specific naming that can be disorienting. This decoder table maps their names to your protocol's cleaner equivalents:

| MakerDAO (dss) | Your Protocol | What It Is |
|---|---|---|
| `vat` | StablecoinEngine | Core CDP accounting |
| `ink` | `vault.collateralAmount` | Collateral in a vault |
| `art` | `vault.normalizedDebt` | Normalized debt (actual = art × rate) |
| `rate` | `config.rateAccumulator` | Per-type rate accumulator |
| `spot` | PriceFeed value | Collateral price × liquidation ratio |
| `jug` | `drip()` logic | Stability fee accrual |
| `dog` | DutchAuctionLiquidator | Liquidation trigger |
| `clip` | Auction logic | Dutch auction execution |
| `bark` | `liquidate()` | Start a liquidation |
| `take` | `buyCollateral()` | Bid on an auction |
| `frob` | `deposit()` + `mint()` | Modify vault (collateral and/or debt) |
| `grab` | `seizeCollateral()` | Forceful vault seizure for liquidation |
| `sin` | `totalBadDebt` | Unbacked system debt |
| `dai` | Stablecoin | The stablecoin token |

**Reading order for MakerDAO dss:**

1. **Start with tests** — `vat.t.sol` shows how `frob` and `grab` are used in practice
2. **Map to your protocol** — mentally replace `ink`/`art`/`rate` with your names as you read
3. **Read `jug.sol` next** — it's short (~80 lines) and maps directly to your `drip()`
4. **Read `dog.sol` + `clip.sol`** — your Liquidator mirrors this pair
5. **Skip `spot.sol` initially** — it handles oracle integration differently than your PriceFeed
6. **Skip NatSpec docs initially** — `///` comments describe function behavior but add reading noise when you're tracing logic. Certora formal verification specs (separate `.spec` files) can also be ignored for now

**Don't get stuck on:** MakerDAO's `auth` modifier pattern, the `wards` mapping, or the `rely`/`deny` authorization system. These are MakerDAO-specific access control — your protocol uses simpler immutable authorization.

---

<a id="cross-module-links"></a>
## 🔗 Cross-Module Concept Links

### Backward References

| Source | Concept | How It Connects |
|---|---|---|
| **Part 1 M1** | `mulDiv` / safe math | Health factor calculation, rate accumulator multiplication |
| **Part 1 M1** | Custom errors | Typed errors across all 4 contracts for clear debugging |
| **Part 1 M2** | Transient storage | Reentrancy guard for flash mint callback |
| **Part 1 M5** | Fork testing | Mainnet fork for real Chainlink oracles and real ERC-4626 vaults |
| **Part 1 M5** | Invariant testing | 5-invariant test suite with handler and ghost variables |
| **M1** | SafeERC20 / decimals | Multi-collateral token handling, decimal normalization |
| **M3** | Chainlink + staleness | PriceFeed.sol — ETH/USD with heartbeat and deviation checks |
| **M4** | Health factor | Core solvency check in StablecoinEngine |
| **M4** | Interest rate math | Stability fee per-second compounding pattern |
| **M4** | Liquidation mechanics | Dutch auction builds on M4's liquidation concepts |
| **M5** | ERC-3156 interface | Flash mint in Stablecoin.sol — same interface, different internals |
| **M5** | Flash loan callback security | Flash mint callback reentrancy defense |
| **M6** | Normalized debt (`art × rate`) | Engine's debt tracking — same pattern as SimpleVat |
| **M6** | `rpow()` exponentiation | Rate accumulator compounding — same implementation as SimpleJug |
| **M6** | Dutch auction (Dog/Clipper) | DutchAuctionLiquidator.sol — adapted from SimpleDog |
| **M6** | WAD/RAY precision scales | All arithmetic throughout the protocol |
| **M7** | ERC-4626 `convertToAssets()` | Vault share collateral pricing pipeline |
| **M7** | Inflation attack | Rate cap defense for vault share exchange rate manipulation |
| **M8** | Invariant testing methodology | Handler + ghost variable + invariant assertion pattern |
| **M8** | Oracle manipulation defense | PriceFeed defensive design, rate cap for vault shares |

### Forward References

| Target | Concept | How It Connects |
|---|---|---|
| **Part 3 M1** | LST collateral types | Adding wstETH/rETH as collateral — your vault share pricing pipeline generalizes directly to LSTs (same `convertToAssets()`-style exchange rate, same manipulation concerns) |
| **Part 3 M5** | MEV-resistant design | Dutch auction as MEV defense studied in depth — your Liquidator is a concrete implementation of the principles covered theoretically |
| **Part 3 M8** | Governance upgrade | Adding Governor + Timelock for parameter updates to your stablecoin — transforming from immutable V1 to governed V2 |
| **Part 3 Capstone** | Protocol extension | Building on this foundation with Part 3 advanced concepts — your stablecoin becomes the base layer for more sophisticated protocol design |

---

<a id="self-assessment"></a>
## ✅ Self-Assessment Checklist

### Architecture
- [ ] 4-contract structure designed and implemented (Engine, PriceFeed, Liquidator, Stablecoin)
- [ ] Clear separation of concerns — Engine doesn't know about auction mechanics, Liquidator doesn't know about rate accumulators
- [ ] Design decisions documented with rationale

### Core Engine
- [ ] Vault lifecycle works end-to-end: deposit → mint → repay → withdraw
- [ ] Health factor correct for ETH collateral (single Chainlink lookup)
- [ ] Health factor correct for vault share collateral (two-step pricing)
- [ ] `drip()` called before every debt-reading operation
- [ ] Rate accumulator compounds correctly over time (test with multi-day time warps)
- [ ] Debt ceiling enforced per collateral type
- [ ] Decimal normalization correct across all token types

### Pricing
- [ ] PriceFeed handles ETH pricing via Chainlink with staleness check
- [ ] PriceFeed handles vault share pricing with `convertToAssets()` + underlying price
- [ ] Rate cap protects against vault share exchange rate manipulation
- [ ] Price returns consistent decimal base for both collateral types

### Liquidation
- [ ] Dutch auction starts at correct price (oracle × buffer)
- [ ] Price decreases over time according to decay function
- [ ] Partial fills work correctly (bidder buys portion, auction continues)
- [ ] Surplus collateral refunded to vault owner when tab is fully covered
- [ ] Bad debt tracked when auction doesn't fully recover

### Flash Mint
- [ ] ERC-3156 interface implemented on Stablecoin
- [ ] `maxFlashLoan()` returns `type(uint256).max`
- [ ] Mint → callback → burn works atomically
- [ ] Reentrancy guard on `flashLoan()`
- [ ] Fee handling correct (if nonzero fee chosen)

### Testing
- [ ] Unit tests for every function and error path
- [ ] Fuzz tests with random amounts, prices, and operation sequences
- [ ] All 5 critical invariants implemented and passing (depth ≥ 50, runs ≥ 256)
- [ ] Fork test with real Chainlink oracle and real ERC-4626 vault
- [ ] Gas benchmarks for core operations logged

### Stretch Goals
- [ ] Exponential step decay function (instead of linear)
- [ ] Protocol surplus buffer funded by stability fee revenue
- [ ] Multiple collateral types per vault (not just one type per vault per user)
- [ ] Dust threshold enforcement (minimum vault size)
- [ ] Architecture Decision Record written for portfolio

---

*This completes Part 2: DeFi Foundations. You've gone from individual primitives (tokens, AMMs, oracles, lending, flash loans, CDPs, vaults, security) to designing and building a complete protocol. The stablecoin you built integrates every concept from Modules 1-8 into a cohesive, decentralized system. Next: Part 3 — Modern DeFi Stack.*

---

**Navigation:** [← Module 8: DeFi Security](8-defi-security.md) | End of Part 2

# Part 2 — Module 6: Stablecoins & CDPs

**Duration:** ~4 days (3–4 hours/day)
**Prerequisites:** Modules 1–5 (especially oracles and lending)
**Pattern:** Concept → Read MakerDAO/Sky core contracts → Build simplified CDP → Compare stablecoin designs
**Builds on:** Module 3 (oracle integration for collateral pricing), Module 4 (interest rate models, health factor math, liquidation mechanics)
**Used by:** Module 8 (threat modeling and invariant testing your CDP), Module 9 (integration capstone)

---

## Why Stablecoins Are Different from Lending

On the surface, a CDP (Collateralized Debt Position) looks like a lending protocol — deposit collateral, borrow an asset. But there's a fundamental difference: in a lending protocol, borrowers withdraw *existing* tokens from a pool that suppliers deposited. In a CDP system, the borrowed stablecoin is **minted into existence** when the user opens a position. There are no suppliers. The protocol *is* the issuer.

This changes everything about the design: there's no utilization rate (because there's no supply pool), no supplier interest rate, and the stability of the stablecoin depends entirely on the protocol's ability to maintain the peg through mechanism design — collateral backing, liquidation efficiency, and monetary policy via the stability fee and savings rate.

MakerDAO (now rebranded to Sky Protocol) pioneered CDPs and remains the largest decentralized stablecoin issuer, with over $7.8 billion in DAI + USDS liabilities. Understanding its architecture gives you the template for how on-chain monetary systems work.

---

## Day 1: The CDP Model and MakerDAO/Sky Architecture

### How CDPs Work

The core lifecycle:

1. **Open a Vault.** User selects a collateral type (called an "ilk" — e.g., ETH-A, WBTC-B, USDC-A) and deposits collateral.
2. **Generate DAI/USDS.** User mints stablecoins against the collateral, up to the maximum allowed by the collateral ratio (typically 150%+ for volatile assets). The stablecoins are newly minted — they didn't exist before.
3. **Accrue stability fee.** Interest accrues on the minted DAI, paid in DAI. This is the protocol's revenue.
4. **Repay and close.** User returns the minted DAI plus accrued stability fee. The returned DAI is *burned* (destroyed). User withdraws their collateral.
5. **Liquidation.** If collateral value drops below the liquidation ratio, the Vault is liquidated via auction.

The critical insight: DAI's value comes from the guarantee that every DAI in circulation is backed by more than $1 of collateral, and that the system can liquidate under-collateralized positions to maintain this backing.

### MakerDAO Contract Architecture

MakerDAO's codebase (called "dss" — Dai Stablecoin System) uses a unique naming convention inherited from formal verification traditions. The core contracts:

**Vat** — The core accounting engine. Stores all Vault state, DAI balances, and collateral balances. Every state-changing operation ultimately modifies the Vat. Think of it as the protocol's ledger.

```
Vat stores:
  Ilk (collateral type): Art (total debt), rate (stability fee accumulator), spot (price with safety margin), line (debt ceiling), dust (minimum debt)
  Urn (individual vault): ink (locked collateral), art (normalized debt)
  dai[address]: internal DAI balance
  sin[address]: system debt (bad debt from liquidations)
```

**Key Vat functions:**
- `frob(ilk, u, v, w, dink, dart)` — The fundamental Vault operation. Modifies collateral (`dink`) and debt (`dart`) simultaneously. This is how users deposit collateral and generate DAI.
- `grab(ilk, u, v, w, dink, dart)` — Seize collateral from a Vault (used in liquidation). Transfers collateral to the liquidation module and creates system debt (`sin`).
- `fold(ilk, u, rate)` — Update the stability fee accumulator for a collateral type. This is how interest accrues globally.
- `heal(rad)` — Cancel equal amounts of DAI and sin (system debt). Used after auctions recover DAI.

**Normalized debt:** The Vat stores `art` (normalized debt), not actual DAI owed. Actual debt = `art × rate`. The `rate` accumulator increases over time based on the stability fee. This is the same index pattern from Module 4 (lending), applied to stability fees instead of borrow rates.

**Spot** — The Oracle Security Module (OSM) interface. Computes the collateral price with the safety margin (liquidation ratio) baked in: `spot = oracle_price / liquidation_ratio`. The Vat uses this directly: a Vault is safe if `ink × spot ≥ art × rate`.

**Jug** — The stability fee module. Calls `Vat.fold()` to update the rate accumulator for each collateral type. The stability fee (an annual percentage) is converted to a per-second rate and compounds continuously.

**Dai** — The ERC-20 token contract for external DAI. Internal DAI in the Vat (`dai[]`) is not the same as the ERC-20 token. The **DaiJoin** adapter converts between them.

**Join adapters** — Bridge between external ERC-20 tokens and the Vat's internal accounting:
- `GemJoin` — Locks collateral ERC-20 tokens and credits internal `gem` balance in the Vat
- `DaiJoin` — Converts internal `dai` balance to/from the external DAI ERC-20 token

**CDP Manager** — A convenience layer that lets a single address own multiple Vaults via proxy contracts (UrnHandlers). Without it, one address can only have one Urn per Ilk.

### The Full Flow: Opening a Vault

1. User calls `GemJoin.join()` — transfers ETH (via WETH) to GemJoin, credits internal `gem` balance in Vat
2. User calls `CdpManager.frob()` (or `Vat.frob()` directly) — locks `gem` as `ink` (collateral) and generates `art` (normalized debt)
3. Vat verifies: `ink × spot ≥ art × rate` (Vault is safe) and total debt ≤ debt ceiling
4. Vat credits `dai` to the user's internal balance
5. User calls `DaiJoin.exit()` — converts internal `dai` to external DAI ERC-20 tokens

### Read: Vat.sol

**Source:** `dss/src/vat.sol` (github.com/makerdao/dss)

This is one of the most important contracts in DeFi. Focus on:
- The `frob()` function — understand each check and state modification
- How `spot` encodes the liquidation ratio into the price
- The authorization system (`wards` and `can` mappings)
- The `cage()` function for Emergency Shutdown

The naming convention is terse (derived from formal specification): `ilk` = collateral type, `urn` = vault, `ink` = collateral amount, `art` = normalized debt, `gem` = unlocked collateral, `dai` = stablecoin balance, `sin` = system debt, `tab` = total debt for auction.

### Exercise

**Exercise 1:** On a mainnet fork, trace a complete Vault lifecycle:
- Join WETH as collateral via GemJoin
- Open a Vault via CdpManager, lock collateral, generate DAI via frob
- Read the Vault state from the Vat (ink, art)
- Compute actual debt: `art × rate` (fetch rate from `Vat.ilks(ilk)`)
- Exit DAI via DaiJoin
- Verify you hold the expected DAI ERC-20 balance

**Exercise 2:** Read the Jug contract. Calculate the per-second rate for a 5% annual stability fee. Call `Jug.drip()` on a mainnet fork and verify the rate accumulator updates correctly. Compute how much more DAI a Vault owes after 1 year of accrued fees.

---

## Day 2: Liquidations, PSM, and DAI Savings Rate

### Liquidation 2.0: Dutch Auctions

MakerDAO's original liquidation system (Liquidation 1.2) used English auctions — participants bid DAI in increasing amounts, with capital locked for the duration. This was slow and capital-inefficient, and it catastrophically failed on "Black Thursday" (March 12, 2020) when network congestion prevented liquidation bots from bidding, allowing attackers to win auctions for $0 and causing $8.3 million in bad debt.

Liquidation 2.0 replaced English auctions with **Dutch auctions**:

**Dog** — The liquidation trigger contract (replaces the old "Cat"). When a Vault is unsafe:
1. Keeper calls `Dog.bark(ilk, urn, kpr)` 
2. Dog calls `Vat.grab()` to seize the Vault's collateral and debt
3. Dog calls `Clipper.kick()` to start a Dutch auction
4. Keeper receives a small incentive (`tip` + `chip` percentage of the tab)

**Clipper** — The Dutch auction contract (one per collateral type). Each auction:
1. Starts at a high price (oracle price × `buf` multiplier, e.g., 120% of oracle price)
2. Price decreases over time according to a price function (`Abacus`)
3. Any participant can call `Clipper.take()` at any time to buy collateral at the current price
4. Instant settlement — no capital lockup, no bidding rounds

**Abacus** — Price decrease functions. Two main types:
- `LinearDecrease` — price drops linearly over time
- `StairstepExponentialDecrease` — price drops in discrete steps (e.g., 1% every 90 seconds)

**Circuit breakers:**
- `tail` — maximum auction duration before reset required
- `cusp` — minimum price (% of starting price) before reset required
- `hole` / `Hole` — maximum total DAI being raised in auctions (per-ilk and global). Prevents runaway liquidation cascades.

The Dutch auction design fixes Black Thursday's problems: no capital lockup means participants can use flash loans, settlement is instant (composable with other DeFi operations), and the decreasing price naturally finds the market clearing level.

### Peg Stability Module (PSM)

The PSM allows 1:1 swaps between DAI and approved stablecoins (primarily USDC) with a small fee (typically 0%). It serves as the primary peg maintenance mechanism:

- If DAI > $1: Users swap USDC → DAI at 1:1, increasing DAI supply, pushing price down
- If DAI < $1: Users swap DAI → USDC at 1:1, decreasing DAI supply, pushing price up

The PSM is controversial because it makes DAI heavily dependent on USDC (a centralized stablecoin). At various points, over 50% of DAI's backing has been USDC through the PSM. This tension — decentralization vs peg stability — is one of the fundamental challenges in stablecoin design.

**Contract architecture:** The PSM is essentially a special Vault type that accepts USDC (or other stablecoins) as collateral at a 100% collateral ratio and auto-generates DAI. The `tin` (fee in) and `tout` (fee out) parameters control the swap fees in each direction.

### Dai Savings Rate (DSR)

The DSR lets DAI holders earn interest by locking DAI in the `Pot` contract. The interest comes from stability fees paid by Vault owners — it's a mechanism to increase DAI demand (and thus support the peg) by making holding DAI attractive.

**Pot contract:** Users call `Pot.join()` to lock DAI and `Pot.exit()` to withdraw. Accumulated interest is tracked via a rate accumulator (same pattern as stability fees). The DSR is set by governance as a monetary policy tool.

**Sky Savings Rate (SSR):** The Sky rebrand introduced a parallel savings rate for USDS using an ERC-4626 vault (sUSDS). This is significant because ERC-4626 is the standard vault interface — meaning sUSDS is natively composable with any protocol that supports ERC-4626.

### The Sky Rebrand: What Changed

In September 2024, MakerDAO rebranded to Sky Protocol. Key changes:
- DAI → USDS (1:1 convertible, both remain active)
- MKR → SKY (1:24,000 conversion ratio)
- SubDAOs → "Stars" (Spark Protocol is the first Star — a lending protocol built on top of Sky)
- USDS adds a freeze function for compliance purposes (controversial in the community)
- SSR uses ERC-4626 standard

The underlying protocol mechanics (Vat, Dog, Clipper, etc.) remain the same. For this module, we'll use the original MakerDAO naming since that's what the codebase uses.

### Read: Dog.sol and Clipper.sol

**Source:** `dss/src/dog.sol` and `dss/src/clip.sol`

In `Dog.bark()`, trace:
- How the Vault is validated as unsafe
- The `grab` call that seizes collateral
- How the `tab` (debt + liquidation penalty) is calculated
- The circuit breaker checks (`Hole`/`hole`, `Dirt`/`dirt`)

In `Clipper.kick()`, trace:
- How the starting price is set (oracle price × buf)
- The auction state struct
- How `take()` works: price calculation via Abacus, partial fills, refunds

### Exercise

**Exercise 1:** On a mainnet fork, simulate a liquidation:
- Open a Vault with ETH collateral near the liquidation ratio
- Mock the oracle to drop the price below the liquidation threshold
- Call `Dog.bark()` to start the auction
- Call `Clipper.take()` to buy the collateral at the current auction price
- Verify: correct amount of DAI paid, correct collateral received, debt cleared

**Exercise 2:** Read the PSM contract. Execute a USDC → DAI swap through the PSM on a mainnet fork. Verify the 1:1 conversion and fee application.

---

## Day 3: Build a Simplified CDP Engine

### SimpleCDP.sol

Build a minimal CDP system that captures the essential mechanisms:

**Core contracts:**

**SimpleVat.sol** — The accounting engine:
```solidity
struct Ilk {
    uint256 Art;    // total normalized debt
    uint256 rate;   // stability fee accumulator (RAY)
    uint256 spot;   // price with safety margin (RAY)
    uint256 line;   // debt ceiling (RAD)
    uint256 dust;   // minimum debt (RAD)
}

struct Urn {
    uint256 ink;    // locked collateral (WAD)
    uint256 art;    // normalized debt (WAD)
}

mapping(bytes32 => Ilk) public ilks;
mapping(bytes32 => mapping(address => Urn)) public urns;
mapping(address => uint256) public dai;   // internal stablecoin balance
uint256 public debt;  // total system debt
uint256 public Line;  // global debt ceiling
```

**Functions:**
- `frob(ilk, dink, dart)` — lock/unlock collateral and generate/repay stablecoins. Check: vault remains safe, debt ceiling not exceeded, minimum debt met.
- `fold(ilk, rate)` — update stability fee accumulator. Called by the Jug equivalent.
- `grab(ilk, u, v, w, dink, dart)` — seize collateral for liquidation.

**SimpleJug.sol** — Stability fee accumulator:
- Stores per-second stability fee rate per ilk
- `drip(ilk)` computes time elapsed since last update, compounds the rate, calls `Vat.fold()`

**SimpleStablecoin.sol** — ERC-20 token with mint/burn controlled by the join adapter.

**SimpleJoin.sol** — Collateral join (lock ERC-20, credit Vat gem) and stablecoin join (convert internal dai ↔ external ERC-20).

**SimpleDog.sol** — Liquidation trigger:
- Check if Vault is unsafe: `ink × spot < art × rate`
- Call `Vat.grab()` to seize collateral
- Start a Dutch auction (simplified: decreasing price over time)

**SimplePSM.sol** — Peg stability module:
- Accept USDC, mint stablecoin 1:1 (with configurable tin/tout fee)
- Accept stablecoin, return USDC 1:1

### Test Suite

- **Full lifecycle:** join collateral → frob (lock + generate) → transfer stablecoin → frob (repay + unlock) → exit collateral
- **Stability fee accrual:** open vault, warp 1 year, verify debt increased by stability fee %
- **Liquidation:** open vault, drop oracle price, trigger liquidation, buy collateral at auction, verify debt cleared
- **Debt ceiling:** attempt to generate stablecoins beyond the ceiling, verify revert
- **Dust check:** attempt to leave a vault with debt below the dust threshold, verify revert
- **PSM peg arbitrage:** when stablecoin trades above $1, show how PSM swap creates profit; when below $1, show the reverse
- **Multi-collateral:** support two collateral types with different stability fees and liquidation ratios

---

## Day 4: Stablecoin Landscape and Design Trade-offs

### Taxonomy of Stablecoins

**1. Fiat-backed (USDC, USDT)** — Centralized issuer holds bank deposits or T-bills equal to the stablecoin supply. Simple, stable, but requires trust in the issuer and is subject to censorship (addresses can be blacklisted).

**2. Overcollateralized crypto-backed (DAI/USDS, LUSD)** — Protocol holds >100% crypto collateral. Decentralized and censorship-resistant (depending on collateral composition), but capital-inefficient (you need $150+ of ETH to mint $100 of stablecoins).

**3. Algorithmic (historical: UST/LUNA, FRAX, ESD, BAC)** — Attempt to maintain peg through algorithmic supply adjustment without full collateral backing. Most have failed catastrophically.

**4. Delta-neutral / yield-bearing (USDe by Ethena)** — Holds crypto collateral and hedges price exposure using perpetual futures short positions. The yield comes from positive funding rates. Novel design but carries exchange counterparty risk and funding rate reversal risk.

### Liquity: A Different CDP Design

Liquity (LUSD) takes a minimalist approach compared to MakerDAO:

**Key differences from MakerDAO:**
- **No governance.** Parameters are immutable once deployed. No governance token, no parameter changes.
- **One-time fee instead of ongoing stability fee.** Users pay a fee at borrowing time (0.5%–5%, adjusted algorithmically based on redemption activity). No interest accrues.
- **110% minimum collateral ratio.** Much more capital-efficient than MakerDAO's typical 150%+.
- **ETH-only collateral.** No multi-collateral complexity.
- **Redemption mechanism:** Any LUSD holder can redeem LUSD for $1 worth of ETH from the riskiest Vault (lowest collateral ratio). This creates a hard price floor.
- **Stability Pool:** LUSD holders can deposit into the Stability Pool, which automatically absorbs liquidated collateral at a discount. No auction needed — liquidation is instant.

**Liquity V2 (2024-25):** Introduces user-set interest rates (borrowers bid their own rate), multi-collateral support (LSTs like wstETH, rETH), and a modified redemption mechanism.

### The Algorithmic Stablecoin Failure Pattern

UST/LUNA (Terra, May 2022) is the canonical example. The mechanism:
- UST was pegged to $1 via an arbitrage loop with LUNA
- When UST > $1: burn $1 of LUNA to mint 1 UST (increase supply, push price down)
- When UST < $1: burn 1 UST to mint $1 of LUNA (decrease supply, push price up)

The death spiral: when confidence in UST dropped, holders rushed to redeem UST for LUNA. Massive LUNA minting cratered LUNA's price, which reduced the backing for UST, causing more redemptions, more LUNA minting, more price collapse. $40+ billion in value was destroyed in days.

**The lesson:** Without external collateral backing, algorithmic stablecoins rely on reflexive confidence. When confidence breaks, there's nothing to stop the spiral. Every algorithmic stablecoin that relies purely on its own governance/seigniorage token for backing has either failed or abandoned that model.

### Ethena (USDe): The Delta-Neutral Model

Ethena mints USDe against crypto collateral (primarily staked ETH) and simultaneously opens a short perpetual futures position of equal size. The net exposure is zero (delta-neutral), meaning the collateral value doesn't change with ETH price movements.

Revenue comes from: staking yield (stETH earns ~3-4%) + funding rate payments from shorts (positive funding = shorts get paid, historically ~8-15% on average).

Risks: funding rates can go negative (shorts pay longs) during bear markets, exchange counterparty risk (positions are on centralized exchanges via custodians), and potential basis risk between spot and futures.

This model doesn't require overcollateralization and generates high yields, but it introduces off-chain dependencies that pure CDP models avoid.

### Design Trade-off Matrix

| Property | DAI/USDS | LUSD | USDC | USDe |
|----------|----------|------|------|------|
| Decentralization | Medium (governance, PSM USDC dependency) | High (immutable, ETH-only) | Low (centralized issuer) | Low (centralized exchanges) |
| Capital efficiency | Low (150%+ collateral) | Medium (110% collateral) | 1:1 | ~1:1 (hedged) |
| Peg stability | Strong (PSM) | Good (redemptions) | Very strong (fiat reserves) | Good (arbitrage) |
| Yield | DSR/SSR (variable) | No native yield | No native yield | High (staking + funding) |
| Censorship resistance | Medium | High | Low (freeze function) | Low |
| Scalability | Limited by collateral demand | Limited by ETH demand | Unlimited (with reserves) | Limited by futures OI |
| Failure mode | Bad debt from collateral crash | Same, but simpler | Issuer insolvency / regulatory | Funding rate reversal, exchange failure |

### The Fundamental Trilemma

Stablecoins face a trilemma between:
1. **Decentralization** — no central point of failure or censorship
2. **Capital efficiency** — not requiring significantly more collateral than the stablecoins minted
3. **Peg stability** — maintaining a reliable $1 value

No design achieves all three. DAI sacrifices efficiency for decentralization and stability. USDC sacrifices decentralization for efficiency and stability. Algorithmic designs attempt efficiency and decentralization but sacrifice stability (and typically fail).

Understanding this trilemma is essential for evaluating any stablecoin design you encounter or build.

### Exercise

**Exercise 1: Liquity analysis.** Read Liquity's `TroveManager.sol` and `StabilityPool.sol`. Compare the liquidation mechanism (Stability Pool absorption) to MakerDAO's Dutch auctions. Which is simpler? Which handles edge cases better? Write a comparison document.

**Exercise 2: Peg stability simulation.** Using your SimpleCDP from Day 3, simulate peg pressure scenarios:
- What happens when collateral prices crash 30%? Model the liquidation volume and its impact.
- What happens when demand for the stablecoin exceeds Vault creation? The price goes above $1. Show how the PSM resolves this.
- What happens if the PSM's USDC reserves are depleted? The stablecoin trades above $1 with no easy correction.

**Exercise 3: Stability fee as monetary policy.** Using your Jug implementation, model how changing the stability fee affects Vault behavior:
- High fee → users repay and close Vaults → stablecoin supply decreases → price pressure upward
- Low fee → users open Vaults → stablecoin supply increases → price pressure downward
- The DSR works in reverse: high DSR → more DAI locked → supply decreases → price up

Map out the feedback loops. This is how decentralized monetary policy works.

---

## Key Takeaways

1. **CDPs mint money.** Unlike lending protocols that redistribute existing assets, CDP systems create new stablecoins backed by collateral. This is closer to how central banks work than how commercial banks work.

2. **The Vat is the source of truth.** Every DAI that exists can be traced back to a `frob()` call that created debt in the Vat. Understanding the Vat means understanding the entire system.

3. **Liquidation design is existential.** Black Thursday proved that auction mechanics can fail under stress. Dutch auctions (Liquidation 2.0) and Stability Pool absorption (Liquity) are the two dominant solutions.

4. **Peg stability requires trade-offs.** The PSM makes DAI's peg extremely stable but introduces centralization risk. Liquity's redemption mechanism maintains the peg purely through crypto-native arbitrage but is less capital-efficient. Every design choice has consequences.

5. **Algorithmic stablecoins without external collateral fail.** The Terra collapse is the definitive case study. Any stablecoin design you encounter that relies on its own token for backing should be treated with extreme skepticism.

---

## Resources

**MakerDAO/Sky:**
- Technical docs: https://docs.makerdao.com
- Source code (dss): https://github.com/makerdao/dss
- Vat documentation: https://docs.makerdao.com/smart-contract-modules/core-module/vat-detailed-documentation
- Liquidation 2.0 docs: https://docs.makerdao.com/smart-contract-modules/dog-and-clipper-detailed-documentation
- Developer guides: https://github.com/sky-ecosystem/developerguides
- Sky Protocol whitepaper: https://makerdao.com/whitepaper

**Liquity:**
- Documentation: https://docs.liquity.org
- Source code: https://github.com/liquity/dev
- Liquity V2: https://www.liquity.org/v2

**Stablecoin analysis:**
- CDP classical design: https://onekey.so/blog/learn/cdp-the-classical-aesthetics-of-stablecoins/
- Ethena documentation: https://docs.ethena.fi
- Terra post-mortem: Search "Terra LUNA collapse analysis" for numerous detailed breakdowns

**Black Thursday:**
- MakerDAO Black Thursday post-mortem and Liquidation 2.0 rationale: MIP45 forum discussion
- ChainSecurity Liquidation 2.0 audit: https://old.chainsecurity.com/wp-content/uploads/2021/04/ChainSecurity_MakerDAO_Liquidations2.0_Final.pdf

---

*Next module: Vaults & Yield (~4 days) — ERC-4626 tokenized vaults, yield aggregation (Yearn architecture), vault share math, inflation attacks, and composable yield strategies.*

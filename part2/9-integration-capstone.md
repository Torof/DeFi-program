# Part 2 — Module 9: Integration Capstone

**Duration:** ~2-3 days (3–4 hours/day)
**Prerequisites:** Modules 1–8 complete
**Pattern:** Integrate → Wire → Stress test → Retrospective
**Builds on:** Module 2 (AMM), Module 3 (oracles), Module 4 (lending), Module 5 (flash loans), Module 7 (ERC-4626 vaults)

---

## 📚 Table of Contents

**Wire the Protocols Together**
- [Set Up the Integrated Environment](#setup-environment)
- [Deploy the Full Stack](#deploy-stack)
- [Integration Issues You'll Encounter](#integration-issues)

**Build the Flash Liquidation Bot**
- [The FlashLiquidator Contract](#flash-liquidator)
- [The Full Flow](#full-flow)
- [Liquidation Profitability Math](#profitability-math)
- [Testing the Liquidation](#testing-liquidation)

**Stress Testing, Invariants, and Retrospective**
- [Invariant Testing the Combined System](#system-invariants)
- [Edge Case Exploration](#edge-cases)
- [Run Security Tooling](#run-security-tooling)
- [Retrospective](#retrospective)

---

## 💡 Why This Module Exists

You've spent 7+ modules building isolated protocols — an AMM here, a lending pool there, a flash loan receiver somewhere else. But real DeFi doesn't work in isolation. Uniswap pools feed Aave liquidations. Flash loans fund arbitrage across multiple DEXes. Vault tokens serve as collateral in lending markets. The integration points are where the hardest bugs live — interface mismatches, decimal normalization, gas overhead from multiple external calls, and composability risks that no individual module prepares you for.

This capstone forces you to wire your builds together into a single system and discover what breaks.

---

## 🏗️ The Project: Flash-Loan-Powered Liquidation System

You'll build a complete liquidation system that combines five of your previous builds:

1. **SimpleLendingPool** (Module 4) — the lending protocol with health factors, liquidation mechanics, and interest accrual
2. **OracleConsumer** (Module 3) — Chainlink price feed integration with staleness checks
3. **ConstantProductPool** (Module 2) — your AMM for swapping seized collateral to debt asset
4. **Flash loan receiver** (Module 5) — zero-capital liquidation via Aave/Balancer flash loans
5. **[ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault shares** (Module 7) — accepted as a collateral type in the lending pool

The end result: a system where anyone can liquidate underwater positions on your lending protocol with zero capital, using flash loans to fund the liquidation and your AMM to convert collateral.

---

## Wire the Protocols Together

<a id="setup-environment"></a>
### 🔧 Step 1: Set Up the Integrated Environment

Create a new directory in your Part 2 workspace for the capstone. You'll import contracts from previous modules and deploy them together.

```
part2-workspace/src/module9/
├── IntegratedLendingPool.sol    # Module 4 lending pool, adapted
├── FlashLiquidator.sol          # The flash loan liquidation bot
└── test/
    ├── IntegrationTest.t.sol    # Full integration test suite
    └── InvariantTest.t.sol      # System-wide invariants
```

<a id="deploy-stack"></a>
### 🔧 Step 2: Deploy the Full Stack

In your test setup, deploy and configure the entire system:

1. **Deploy your ConstantProductPool** (Module 2) with ETH/USDC liquidity. Seed it with realistic reserves (e.g., $5M TVL equivalent).

2. **Deploy your OracleConsumer** (Module 3). For local tests, use mock oracles. For fork tests, point to real Chainlink feeds.

3. **Deploy an ERC-4626 vault** (Module 7) that wraps one of your tokens. This vault's share token will be used as collateral in the lending pool.

4. **Deploy your SimpleLendingPool** (Module 4). Configure it with:
   - ETH as a collateral type (LTV 80%, liquidation threshold 82.5%, bonus 5%)
   - ERC-4626 vault shares as a collateral type (LTV 70%, liquidation threshold 75%, bonus 8%)
   - USDC as the borrowable asset
   - Your oracle consumer for price feeds

5. **Verify basic operations work:**
   - Supply USDC to the lending pool
   - Deposit ETH as collateral, borrow USDC, verify health factor
   - Deposit vault shares as collateral, borrow USDC, verify health factor
   - Swap on your AMM pool, verify correct output

<a id="integration-issues"></a>
### ⚠️ Step 3: Integration Issues You'll Encounter

This is where the learning happens. You will likely hit:

**Decimal normalization:** ETH has 18 decimals, USDC has 6, Chainlink ETH/USD has 8. Your lending pool's health factor calculation needs to normalize all of these correctly. Off-by-one in decimal scaling is one of the most common integration bugs.

**Oracle price vs AMM price:** Your Chainlink mock might return $3,000 for ETH, but your AMM pool's ratio implies a different price (based on reserves). The lending pool uses the oracle; the liquidator swaps on the AMM. If these diverge significantly, the liquidation might not be profitable even with the bonus.

**Vault share pricing:** When using ERC-4626 shares as collateral, you need to price them. The naive approach calls `vault.convertToAssets(shares)`, but as Module 7 taught you, this can be manipulated. For this exercise, use the vault's internal rate but be aware of the limitation.

**Gas overhead:** A flash loan liquidation touches 4+ contracts in a single transaction. Monitor gas usage and identify bottlenecks.

#### 🔍 Deep Dive: Decimal Normalization Step-by-Step

This is the #1 source of integration bugs. Let's work through the exact math.

**The components and their decimals:**

| Component | Value | Decimals | Raw Value |
|---|---|---|---|
| ETH collateral | 2.0 ETH | 18 | `2_000000000000000000` |
| USDC borrowed | 3,000 USDC | 6 | `3_000_000000` |
| Chainlink ETH/USD | $3,000.00 | 8 | `300000000000` |
| LTV | 80% | - | 8000 (basis points) |

**Health factor calculation:**

```
Health Factor = (collateral_value × liquidation_threshold) / debt_value
```

**Step-by-step with raw values:**

```
Step 1: Get collateral value in USD
  collateral_amount = 2e18          (18 decimals)
  oracle_price      = 3000e8        (8 decimals)

  collateral_usd = collateral_amount × oracle_price / 1e18
                 = 2e18 × 3000e8 / 1e18
                 = 6000e8           (8 decimals — USD with 8 decimal places)

Step 2: Get debt value in USD
  debt_amount    = 3000e6           (6 decimals, USDC)
  usdc_price     = 1e8              (8 decimals, Chainlink USDC/USD)

  debt_usd = debt_amount × usdc_price / 1e6
           = 3000e6 × 1e8 / 1e6
           = 3000e8                 (8 decimals — same base as collateral!)

Step 3: Apply liquidation threshold (82.5% = 8250 bps)
  adjusted_collateral = collateral_usd × liq_threshold / 10000
                      = 6000e8 × 8250 / 10000
                      = 4950e8

Step 4: Health factor (scale to 1e18 for precision)
  HF = adjusted_collateral × 1e18 / debt_usd
     = 4950e8 × 1e18 / 3000e8
     = 1.65e18                      (1.65 — healthy!)
```

**The common mistakes:**

```solidity
// WRONG: forgetting to normalize decimals
uint256 collateralUsd = collateralAmount * oraclePrice; // ← 18+8 = 26 decimals!
uint256 debtUsd = debtAmount * usdcPrice;               // ← 6+8 = 14 decimals!
uint256 hf = collateralUsd / debtUsd;                   // ← comparing 26 vs 14 decimals = garbage

// CORRECT: normalize to common base
uint256 collateralUsd = collateralAmount * oraclePrice / 1e18; // → 8 decimals
uint256 debtUsd = debtAmount * usdcPrice / 1e6;                // → 8 decimals
uint256 hf = collateralUsd * 1e18 / debtUsd;                   // → 18 decimals (HF)
```

**General rule:** When multiplying two fixed-point values, the result has `decimals_a + decimals_b` decimals. You must divide by one of the bases to normalize. Always explicitly track the decimal count at each step — write it in comments during development.

### 🛠️ Exercise

**Exercise 1:** Deploy the full stack and run a happy-path test: supply → deposit collateral → borrow → accrue interest → repay → withdraw. Verify all balances at each step.

**Exercise 2:** Deposit ERC-4626 vault shares as collateral, borrow against them. Simulate the vault earning yield (increasing share price). Verify the borrower's health factor improves as their collateral becomes worth more.

### 📋 Summary: Wire the Protocols Together

**✓ Covered:**
- Setting up the integrated environment — deploying 5 protocol components together
- Wiring dependencies — oracle → lending pool, vault → lending pool, AMM for swaps
- Integration pain points — decimal normalization, oracle vs AMM price divergence, vault share pricing, gas overhead
- Happy-path testing — full supply → borrow → repay → withdraw cycle
- ERC-4626 collateral — borrowing against vault shares, share price changes affecting health factor

**Key insight:** Deploying individual protocols is straightforward. Wiring them together is where the real complexity lives — decimal mismatches, interface assumptions, and pricing inconsistencies between components. Every integration point is a potential bug.

**Next:** Building the FlashLiquidator — the contract that ties everything together in a single atomic transaction.

---

## Build the Flash Liquidation Bot

<a id="flash-liquidator"></a>
### 🔧 The FlashLiquidator Contract

Build a contract that executes the entire liquidation flow in a single atomic transaction.

📖 **Study real liquidation infrastructure first:**
- [Aave V3 liquidation logic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol) — how Aave calculates seized collateral, bonus, and debt coverage
- [Compound III (Comet) absorb/buy](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — Compound V3's liquidation mechanism (different pattern: protocol absorbs, then sells)
- [Aave liquidation bot example](https://github.com/aave/liquidation-bot-template) — official template for Aave liquidation bots
- Real liquidation tx example: search [Etherscan](https://etherscan.io/) for `LiquidationCall` events on the [Aave V3 Pool](https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2) to see professional liquidation bots in action

```solidity
contract FlashLiquidator {
    IPool public lendingPool;
    ISwapRouter public amm;
    IFlashLoanProvider public flashProvider;

    function liquidate(
        address borrower,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover
    ) external {
        // 1. Flash-borrow the debt asset
        // 2. In the callback:
        //    a. Repay the borrower's debt on the lending pool
        //    b. Receive seized collateral (at discount from liquidation bonus)
        //    c. Swap collateral → debt asset on the AMM
        //    d. Repay the flash loan
        //    e. Send profit to caller
    }
}
```

<a id="full-flow"></a>
### 📋 The Full Flow

```
1. FlashLiquidator.liquidate(borrower, ETH, USDC, 5000e6)
2. → Flash-borrow 5000 USDC from Aave (fork) or Balancer (fork)
3. → Callback:
   a. Approve lending pool, call lendingPool.liquidate(borrower, ETH, USDC, 5000e6)
   b. Receive 5000 * 1.05 / ETH_price worth of ETH collateral
   c. Swap ETH → USDC on AMM pool
   d. Verify USDC received > 5000 + flash_fee
   e. Repay flash loan
   f. Transfer profit to msg.sender
4. Transaction succeeds, borrower's position is healthier, liquidator earned the spread
```

<a id="profitability-math"></a>
#### 🔍 Deep Dive: Liquidation Profitability Math

Is a liquidation profitable? It depends on four factors: the liquidation bonus, flash loan fee, AMM slippage, and gas cost. Let's work through a concrete example.

**Setup:**
- Borrower: 2 ETH collateral (worth $6,000 at $3,000/ETH), 5,000 USDC debt
- ETH price drops to $2,700 → collateral = $5,400, HF = 5,400 × 0.825 / 5,000 = 0.891 (liquidatable!)
- Liquidation bonus: 5%
- Flash loan: Balancer (0 fee) or Aave (0.05% fee)
- AMM pool: 500 ETH / 1,350,000 USDC (~$2.7M TVL)

**The math:**

```
Step 1: Flash-borrow 5,000 USDC
  Flash loan fee (Aave): 5000 × 0.0005 = 2.50 USDC
  Flash loan fee (Balancer): 0

Step 2: Repay 5,000 USDC of borrower's debt
  Collateral seized: 5000 / 2700 × 1.05 = 1.944 ETH
  (We get 5% MORE collateral than the debt is worth)

Step 3: Swap 1.944 ETH → USDC on AMM
  AMM reserves: 500 ETH / 1,350,000 USDC
  k = 500 × 1,350,000 = 675,000,000
  New ETH = 501.944 → New USDC = 675,000,000 / 501.944 = 1,344,772
  Output = 1,350,000 - 1,344,772 = 5,228 USDC
  (Slippage cost: 1.944 × $2,700 = $5,249 real value, got $5,228 → ~$21 slippage)

Step 4: Repay flash loan
  Owe: 5,000 + 2.50 = 5,002.50 USDC (Aave)
  Have: 5,228 USDC

┌────────────────────────────────────────────┐
│  Profit = 5,228 - 5,002.50 = 225.50 USDC  │
│  Minus gas: ~200,000 gas × 30 gwei         │
│           = 0.006 ETH ≈ $16                │
│  Net profit: ~$210                         │
│  ROI: infinite (started with $0 capital)   │
└────────────────────────────────────────────┘
```

**When does it become unprofitable?**

```
Break-even: liquidation_bonus_value > slippage + flash_fee + gas

If AMM had only 20 ETH / 54,000 USDC ($108K TVL):
  k = 1,080,000. New ETH = 21.944. New USDC = 1,080,000/21.944 = 49,224
  Swapping 1.944 ETH → output = 54,000 - 49,224 = 4,776 USDC
  Profit = 4,776 - 5,002.50 = -226.50 USDC ← LOSS!

The liquidation reverts because the flash loan can't be repaid.
```

**Key insight:** Liquidation profitability is directly tied to AMM liquidity depth. Protocols must ensure sufficient on-chain liquidity for their collateral types, or liquidations won't happen and bad debt accumulates. This is why Aave governance carefully evaluates liquidity before listing new collateral types.

<a id="testing-liquidation"></a>
### 🧪 Testing the Liquidation

**Test 1: Basic flash liquidation**
- Set up a borrower near max LTV
- Mock the oracle to drop collateral price below liquidation threshold
- Execute the flash liquidation
- Verify: borrower's debt decreased, collateral seized correctly, flash loan repaid, profit transferred

**Test 2: ERC-4626 collateral liquidation**
- Set up a borrower with vault shares as collateral
- Drop the underlying asset price (which reduces vault share value)
- Execute flash liquidation with vault shares as collateral
- Additional complexity: the liquidator receives vault shares, needs to redeem them for the underlying asset, then swap to the debt asset

**Test 3: Unprofitable liquidation**
- Set up a scenario where the liquidation bonus doesn't cover AMM slippage + flash loan fee
- Verify the liquidation reverts cleanly (the flash loan callback should fail, reverting everything)
- Calculate: at what AMM liquidity depth does the liquidation become profitable?

**Test 4: Mainnet fork test**
- Fork Ethereum mainnet
- Flash-borrow from Balancer (0 fee) or Aave
- Execute liquidation on your lending pool (deployed on the fork)
- Swap via the real Uniswap V2 router
- Verify the entire flow works with production contracts

### 🛠️ Exercise

Build and test the FlashLiquidator. For each test, log:
- Gas used
- Profit (or loss) in debt asset terms
- Health factor before and after
- Number of external calls in the transaction

### 📋 Summary: Build the Flash Liquidation Bot

**✓ Covered:**
- FlashLiquidator contract architecture — flash borrow → repay debt → seize collateral → swap → repay flash loan → take profit
- The complete atomic liquidation flow — 4+ contracts in one transaction
- Testing: basic liquidation, ERC-4626 collateral liquidation, unprofitable liquidation (should revert), mainnet fork test
- Profitability tracking — gas, profit/loss, health factor changes

**Key insight:** The flash liquidation bot is the ultimate integration test. It touches every protocol you've built in a single atomic transaction. If any component has an interface mismatch, a decimal error, or a reentrancy vulnerability, the liquidation will either fail or be exploitable. This is composability in action.

**Next:** Stress testing the entire system with invariant testing, edge cases, and security tooling.

---

## Stress Testing, Invariants, and Retrospective

<a id="system-invariants"></a>
### 🔍 Invariant Testing the Combined System

Write invariant tests that verify system-wide properties across random sequences of operations:

**Handler contract:** Wrap all system operations with bounded inputs:
- `supply(amount)` — supply USDC to the lending pool
- `depositCollateral(amount)` — deposit ETH as collateral
- `depositVaultShares(amount)` — deposit ERC-4626 shares as collateral
- `borrow(amount)` — borrow USDC against collateral
- `repay(amount)` — repay debt
- `withdraw(amount)` — withdraw supplied USDC
- `swapOnAMM(amount)` — swap on the AMM (changes available liquidity)
- `moveOraclePrice(delta)` — shift oracle price up/down (bounded to realistic range)
- `accrueInterest()` — advance time and accrue
- `liquidate(borrower)` — attempt liquidation if any position is underwater

**System invariants:**
- Lending pool solvency: total USDC in pool >= total owed to suppliers (accounting for borrows)
- No healthy position is liquidatable: for every borrower with HF >= 1, liquidation should revert
- Every unhealthy position CAN be liquidated: for every borrower with HF < 1, liquidation should succeed
- AMM invariant: k only increases (fees accumulate)
- Vault shares: totalAssets >= sum of all share claims
- Conservation: tokens in the system = tokens deposited - tokens withdrawn (no creation or destruction outside flash loans)

Run with `depth = 50, runs = 500`. If any invariant breaks, you have a real bug — trace it, fix it.

<a id="edge-cases"></a>
### ⚠️ Edge Case Exploration

Test these specific scenarios:

**Cascading liquidation:** Set up 3 borrowers with progressively tighter health factors. Drop the price. Liquidate the first — does the collateral sale on the AMM move the price enough to push the second into liquidation territory? Does it cascade?

**Stale oracle + liquidation:** What happens if a liquidator tries to liquidate a position but the oracle is stale? Your lending pool should block it (staleness check from Module 3). Verify this.

**Vault share price manipulation during liquidation:** What happens if someone donates tokens to the ERC-4626 vault right before a liquidation, inflating the vault share price? Does it affect the health factor calculation? If you used `convertToAssets()` for pricing, it will. Document the risk.

**Flash loan unavailability:** What if the flash loan provider doesn't have enough liquidity? The liquidation reverts. Show that non-flash-loan liquidations still work (caller provides their own capital).

<a id="run-security-tooling"></a>
### 🛠️ Run Security Tooling

Run Slither and/or Aderyn on the combined codebase:

```bash
slither src/module9/ --json slither-report.json
```

Triage the findings. How many are real issues? How many are false positives? For any real findings, fix them.

<a id="retrospective"></a>
### 📝 Retrospective

After completing the capstone, document (for yourself, not for grading):

1. **What was hardest about integration?** (Usually: decimal normalization, interface mismatches, or gas management)
2. **What broke that you didn't expect?** (The bugs you only find when wiring things together)
3. **What would you design differently?** (Now that you've seen how the pieces interact, what interfaces would you change?)
4. **What's missing from your builds?** (Events? Better error messages? Gas optimizations? Access control?)

This retrospective is the highest-value part of the capstone. The insights you write down here directly inform how you'll design protocols going forward.

### 📋 Summary: Stress Testing, Invariants, and Retrospective

**✓ Covered:**
- System-wide invariant testing — handler with 10 operations, 6 cross-protocol invariants
- Edge case exploration — cascading liquidations, stale oracles, vault share manipulation, flash loan unavailability
- Security tooling — Slither/Aderyn on the combined codebase, triage findings
- Retrospective — documenting integration lessons, design decisions, and future improvements

**Key insight:** The retrospective is where the capstone pays its highest dividend. The specific integration bugs you hit, the decimal errors you debugged, the interface mismatches you resolved — these are the stories you'll tell in interviews and the instincts that will guide your future protocol design. Write them down.

---

## 📋 Key Takeaways

1. **Integration is where the bugs live.** Individual modules work in isolation but break at the boundaries. Decimal normalization, interface assumptions, and gas overhead are the primary failure modes.

2. **Flash loans change the security model of every protocol they touch.** Your lending pool must be secure against a caller with unlimited temporary capital. Your AMM must handle large sudden trades. Your vault must resist donation attacks. The flash liquidation bot is the forcing function that tests all of this simultaneously.

3. **Invariant testing shines on integrated systems.** Single-protocol invariants catch single-protocol bugs. Cross-protocol invariants catch the composability bugs that cause real-world exploits.

4. **Profitability determines whether liquidation works.** A liquidation system is only as reliable as its economics. If the bonus doesn't cover slippage + fees, no one will liquidate, and the protocol accumulates bad debt. This is a protocol design problem, not just a bot problem.

---

## 💼 Job Market Context: This Capstone as a Portfolio Piece

This capstone project demonstrates exactly the skills DeFi teams hire for. Here's how to position it.

**What this project proves:**
- You can wire multiple DeFi protocols together (AMM + lending + oracle + flash loans + vaults)
- You understand cross-protocol interactions and their failure modes
- You can build MEV infrastructure (flash liquidation bots)
- You can write system-wide invariant tests
- You can run security tooling and triage findings

**Interview questions this prepares you for:**

1. **"Walk me through a system you've built that integrates multiple DeFi protocols."**
   - This capstone IS the answer. Describe the architecture: 5 protocols, how they interact, what integration challenges you hit (decimal normalization, oracle/AMM price divergence), and how you tested it (invariant tests with cross-protocol handlers)

2. **"How would you build a liquidation bot?"**
   - Describe the flash liquidation flow: flash borrow → repay debt → seize collateral → swap → repay → profit. Discuss profitability conditions (bonus vs slippage + fees), mainnet fork testing, and the gas optimization considerations

3. **"What's the hardest integration bug you've encountered?"**
   - Pull from your Stress Testing retrospective. Decimal normalization stories are gold — they show you've actually built integrated systems, not just individual contracts

4. **"How do you test cross-protocol interactions?"**
   - Describe the system-wide invariant test suite: handler with 10 operations, ghost variables tracking cross-protocol state, invariants like "lending pool solvency holds across arbitrary sequences of deposits, borrows, swaps, price changes, and liquidations"

**Portfolio presentation tips:**
- Push the capstone to a public GitHub repo with a clear README
- Include gas benchmarks and profitability analysis in the README
- Show the invariant test suite — this signals maturity beyond basic unit testing
- Include your retrospective (edited for presentation) — it shows reflective engineering thinking
- If you fork-tested against mainnet, mention it — fork testing is a strong signal

---

## 🔗 Cross-Module Concept Links

### Backward References (concepts from earlier modules used here)

| Source | Concept | How It Connects |
|---|---|---|
| **Part 1 Section 1** | `mulDiv` / safe math | Health factor calculation uses `mulDiv` with explicit decimal normalization |
| **Part 1 Section 1** | Custom errors | Integrated system needs clear typed errors across 5 contracts for debugging |
| **Part 1 Section 2** | Transient storage | Cross-contract reentrancy guard across lending pool + flash loan callback |
| **Part 1 Section 5** | Fork testing | Flash Liquidation Bot mainnet fork test — flash borrow from real Balancer/Aave |
| **Part 1 Section 5** | Invariant testing | Stress Testing section's system-wide invariant suite with 10-operation handler and ghost variables |
| **M1** | Token decimals / SafeERC20 | Decimal normalization (ETH 18 / USDC 6 / Chainlink 8) — the #1 integration bug source |
| **M2** | ConstantProductPool | AMM for swapping seized collateral → debt asset; slippage determines liquidation profitability |
| **M2** | MEV / sandwich | Liquidation transactions are MEV targets — Flashbots Protect for submission |
| **M3** | Chainlink oracle + staleness | Health factor depends on oracle price; stale oracle edge case tested in Stress Testing |
| **M3** | Oracle vs AMM price divergence | Lending pool uses oracle price, liquidator swaps at AMM price — divergence affects profitability |
| **M4** | Lending / liquidation mechanics | Core: health factor, collateral seizure, liquidation bonus, interest accrual |
| **M4** | Cascading liquidations | Collateral sale on AMM moves price → triggers more liquidations → systemic risk |
| **M5** | Flash loans (zero-capital) | Flash borrow funds the entire liquidation — infinite ROI on profitable liquidations |
| **M6** | CDP collateral ratio patterns | Vault solvency invariants parallel CDP collateral ratio invariants |
| **M7** | ERC-4626 vault shares as collateral | Share pricing via `convertToAssets()`, manipulation risk from donation attack |
| **M7** | Vault share redemption path | ERC-4626 liquidation: receive shares → redeem → swap underlying → repay (extra step + gas) |
| **M8** | Invariant testing methodology | Stress Testing section's handler/ghost/actor pattern directly from M8's Invariant Testing section |
| **M8** | Security tooling (Slither/Aderyn) | Stress Testing: run static analysis on combined codebase, triage cross-contract findings |
| **M8** | Threat model / self-audit | Stress Testing retrospective applies M8's structured review methodology |

### Forward References (where these concepts lead)

| Target | Concept | How It Connects |
|---|---|---|
| **Part 3 M1** | Upgradeable integrated systems | Proxy patterns for upgrading individual components without breaking integrations |
| **Part 3 M2** | Governance over parameters | Timelock-controlled updates to LTV, bonus, oracle feeds across the integrated system |
| **Part 3 M5** | Formal verification of invariants | Proving system-wide properties (solvency, HF correctness) with Certora |
| **Part 3 M7** | Gas optimization | Optimizing the 4+ contract flash liquidation path for production viability |
| **Part 3 M8** | Deployment scripts | Scripted deployment of the full integrated stack with verification |
| **Part 3 M9** | Production monitoring | Real-time health factor monitoring, liquidation opportunity detection, alerting |

---

## 📖 Production Study Order

Study these liquidation and integration references in order — each builds on the previous:

| # | Repository / Resource | Why Study This | Key Files |
|---|---|---|---|
| 1 | [Aave V3 LiquidationLogic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol) | The production standard for liquidation math — bonus calculation, collateral seizure, debt coverage | `LiquidationLogic.sol` (full liquidation flow), `GenericLogic.sol` (health factor) |
| 2 | [Compound III (Comet)](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) | Alternative liquidation design — protocol absorbs bad debt, then sells collateral separately | `Comet.sol` (`absorb()`, `buyCollateral()`), compare with Aave's direct seizure model |
| 3 | [Aave Liquidation Bot Template](https://github.com/aave/liquidation-bot-template) | Official template for building liquidation infrastructure — monitoring, simulation, execution | README (architecture), bot logic (position monitoring, profitability checks) |
| 4 | [Uniswap V2 Router](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol) | The swap router your liquidator calls — understand `getAmountsOut`, slippage params, deadline | `UniswapV2Router02.sol` (`swapExactTokensForTokens`), `UniswapV2Library.sol` (`getAmountOut`) |
| 5 | [Flashbots Protect](https://docs.flashbots.net/) | MEV-protected transaction submission — essential for production liquidation bots | Docs (Protect RPC, bundle submission), understand why public mempool = front-run risk |
| 6 | [Liquidations: DeFi on a Knife-edge](https://arxiv.org/abs/2009.13235) | Academic analysis of liquidation incentives, cascading risks, and protocol design trade-offs | Full paper — focus on §3 (mechanism design), §5 (cascading risk), §7 (recommendations) |

**Reading strategy:** Start with Aave LiquidationLogic (1) to understand production liquidation math — this is what your FlashLiquidator mirrors. Compare with Compound's absorb model (2) for an alternative design. Study the Aave bot template (3) for monitoring and simulation patterns. Read the Uniswap router (4) since your liquidator swaps through it. Understand Flashbots (5) for MEV-safe submission. Finally, read the academic paper (6) for the game-theoretic perspective on why liquidation design matters.

---

## ⚠️ Common Mistakes

**Mistake 1: Decimal mismatch in health factor calculation**

```solidity
// WRONG: ETH (18 decimals) × Chainlink price (8 decimals) = 26 decimals
//        USDC (6 decimals) × Chainlink price (8 decimals) = 14 decimals
//        Comparing 26-decimal and 14-decimal values = meaningless
uint256 hf = (collateral * ethPrice) / (debt * usdcPrice);
```

```solidity
// CORRECT: normalize both to the same decimal base
uint256 collateralUsd = collateral * ethPrice / 1e18;   // → 8 decimals
uint256 debtUsd = debt * usdcPrice / 1e6;               // → 8 decimals
uint256 hf = collateralUsd * 1e18 / debtUsd;            // → 18 decimals
```

**Mistake 2: Not checking liquidation profitability before executing**

```solidity
// WRONG: execute the liquidation and hope it's profitable
function executeFlashLoanCallback() internal {
    lendingPool.liquidate(borrower, ...);
    uint256 collateralReceived = collateral.balanceOf(address(this));
    amm.swap(collateralReceived, ...);
    // If swap output < flash loan repayment, the whole tx reverts
    // Wasted gas for the caller
}
```

```solidity
// CORRECT: simulate profitability first (or use a minimum profit check)
function executeFlashLoanCallback() internal {
    lendingPool.liquidate(borrower, ...);
    uint256 collateralReceived = collateral.balanceOf(address(this));
    uint256 expectedOutput = amm.getAmountOut(collateralReceived, ...);
    require(expectedOutput > flashLoanRepayment + minProfit, "Unprofitable");
    amm.swap(collateralReceived, ...);
}
```

**Mistake 3: Forgetting flash loan fees in profitability calculation**

```solidity
// WRONG: only checking if swap output > debt repaid
require(swapOutput > debtRepaid, "Not profitable");

// CORRECT: include flash loan fee AND gas estimate
uint256 flashFee = flashProvider.flashFee(debtAsset, debtAmount);
require(swapOutput > debtRepaid + flashFee + minProfit, "Not profitable");
```

**Mistake 4: Using `vault.convertToAssets()` for collateral pricing without protection**

```solidity
// WRONG: directly reading vault exchange rate (manipulable via donation)
uint256 collateralValue = vault.convertToAssets(shares) * underlyingPrice / 1e18;
```

```solidity
// CORRECT: use a time-weighted rate or apply a rate cap
uint256 currentRate = vault.convertToAssets(1e18);
uint256 maxRate = lastKnownRate * MAX_RATE_INCREASE / 10000; // e.g., max 1% increase per block
uint256 safeRate = currentRate > maxRate ? maxRate : currentRate;
uint256 collateralValue = shares * safeRate * underlyingPrice / 1e36;
```

**Mistake 5: Not handling the "vault shares → redeem → swap" path for ERC-4626 liquidations**

When liquidating vault share collateral, the liquidator receives vault shares, not the underlying. The extra step (redeem shares → get underlying → swap underlying to debt asset) is easy to forget and adds gas + slippage.

---

## 🛡️ MEV & Liquidation Bot Strategies

Real liquidation bots operate differently from exercise code. Understanding the production landscape helps you design better liquidation mechanisms.

**How professional liquidation bots work:**
1. **Monitoring:** Watch every new block for positions crossing liquidation thresholds. Maintain an in-memory index of all positions and their health factors. Update on every oracle price change
2. **Simulation:** Before submitting, simulate the liquidation locally (via `eth_call`) to verify profitability and estimate gas
3. **MEV protection:** Submit via [Flashbots Protect](https://docs.flashbots.net/) or private mempool to avoid being front-run by other liquidators
4. **Priority fees:** In competitive liquidations, bots bid priority fees (tips) to get their transaction included first. The profit ceiling is: liquidation bonus - slippage - flash fee - gas - priority fee
5. **Multi-position:** Sophisticated bots liquidate multiple positions in a single transaction (batching) to amortize gas costs

**Why this matters for protocol designers:**
- If your liquidation bonus is too low, no bot will liquidate → bad debt accumulates
- If your bonus is too high, it incentivizes oracle manipulation to *trigger* liquidations → MEV extraction
- The sweet spot: bonus > expected slippage + gas, but < cost of manipulation. Aave uses 5-10% depending on asset risk tier
- Consider Dutch auction liquidations (gradually increasing bonus) — they find the market-clearing price for liquidation services

**Further reading:**
- [Flashbots documentation](https://docs.flashbots.net/) — MEV protection and private transaction submission
- [MEV Explore](https://explore.flashbots.net/) — real-time MEV activity dashboard
- [Liquidations: DeFi on a Knife-edge](https://arxiv.org/abs/2009.13235) — academic paper on liquidation mechanics and incentives

---

## ✅ Self-Assessment Checklist

Use this rubric to evaluate the quality of your capstone before considering it complete.

**Functionality:**
- [ ] Full stack deploys and passes happy-path test (supply → borrow → repay → withdraw)
- [ ] ERC-4626 vault shares work as collateral type
- [ ] FlashLiquidator executes basic liquidation successfully
- [ ] FlashLiquidator handles ERC-4626 collateral (redeem → swap)
- [ ] Unprofitable liquidation reverts cleanly
- [ ] Mainnet fork test passes (flash loan from real Balancer/Aave)

**Integration quality:**
- [ ] Decimal normalization correct for all token pairs (ETH/USDC/Chainlink)
- [ ] Oracle price and AMM price divergence handled gracefully
- [ ] Gas usage logged and reasonable (<500K gas for basic liquidation)

**Testing:**
- [ ] System-wide invariant tests with handler (10+ operations)
- [ ] Ghost variables tracking cross-protocol state
- [ ] At least 6 invariants covering lending, AMM, and vault properties
- [ ] Edge cases tested: cascading liquidation, stale oracle, vault manipulation, flash loan unavailability
- [ ] Slither/Aderyn run on combined codebase, findings triaged

**Documentation:**
- [ ] Retrospective written (4 questions answered)
- [ ] Gas benchmarks recorded
- [ ] Profitability analysis for liquidation (bonus vs slippage + fees)

**Stretch goals (optional, for interview differentiation):**
- [ ] Dutch auction liquidation mechanism
- [ ] Multi-position batch liquidation
- [ ] Flashbots integration for MEV-protected submission
- [ ] Monitoring script that watches for liquidatable positions

---

*This completes Part 2: DeFi Foundations. You now have deep understanding of token mechanics, AMMs, oracles, lending, flash loans, stablecoins, vaults, security, and — critically — how they all compose together. Next: Part 3 — Modern DeFi Stack.*

---

**Navigation:** [← Module 8: DeFi Security](8-defi-security.md) | End of Part 2

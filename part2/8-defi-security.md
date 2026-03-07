# Part 2 — Module 8: DeFi Security

> **Difficulty:** Advanced
>
> **Estimated reading time:** ~45 minutes | **Exercises:** ~4-5 hours

---

## 📚 Table of Contents

**DeFi-Specific Attack Patterns**
- [Read-Only Reentrancy](#read-only-reentrancy)
- [Cross-Contract Reentrancy in DeFi Compositions](#cross-contract-reentrancy)
- [Frontrunning and MEV](#frontrunning-mev)
- [Precision Loss and Rounding Exploits](#precision-loss)
- [Access Control Vulnerabilities](#access-control-attacks)
- [Composability Risk](#composability-risk)

**Invariant Testing with Foundry**
- [Why Invariant Testing Is the Most Powerful DeFi Testing Tool](#why-invariant-testing)
- [Foundry Invariant Testing Setup](#invariant-setup)
- [Handler Contracts: The Key to Effective Invariant Testing](#handler-contracts)

**Reading Audit Reports**
- [Exercise: Self-Audit](#self-audit)

**Security Tooling & Audit Preparation**
- [Static Analysis Tools](#static-analysis)
- [The Security Checklist](#security-checklist)
- [Building Security-First](#security-first)

---

## 📋 Quick Reference: Fundamentals You Already Know

DeFi protocols lost over $3.1 billion in the first half of 2025 alone. Roughly 70% of major exploits in 2024 hit contracts that had been professionally audited. The OWASP Smart Contract Top 10 (2025 edition) ranks access control as the #1 vulnerability for the second year running, followed by reentrancy, logic errors, and oracle manipulation — all patterns you've encountered throughout Part 2.

This module focuses on the DeFi-specific attack patterns and defense methodologies that go beyond general Solidity security. You already know CEI, reentrancy guards, and access control. Here we cover: read-only reentrancy in multi-protocol contexts, the full oracle/flash-loan manipulation taxonomy, invariant testing as the primary DeFi bug-finding tool, how to read audit reports, and security tooling for protocol builders.

These patterns should be second nature. This box is a refresher, not a learning section.

**Checks-Effects-Interactions (CEI):** Validate → update state → make external calls. The base defense against reentrancy.

**Reentrancy guards:** `nonReentrant` modifier (OpenZeppelin or transient storage variant from Part 1). Apply to all state-changing external functions. For cross-contract reentrancy, consider a shared lock.

**Access control:** OpenZeppelin `AccessControl` (role-based) or `Ownable2Step` (two-step transfer). Timelock all admin operations. Use `initializer` modifier on upgradeable contracts. Multisig threshold should scale with TVL.

**Input validation:** Validate every parameter of every external/public function. Never pass user-supplied addresses to `call()` or `delegatecall()` without validation. Check for zero addresses, zero amounts.

If any of these feel unfamiliar, review Part 1 and the OpenZeppelin documentation before proceeding.

---

## 💡 DeFi-Specific Attack Patterns

<a id="read-only-reentrancy"></a>
### 💡 Concept: Read-Only Reentrancy

The most subtle reentrancy variant. No state modification needed — just reading at the wrong time.

**The pattern:** A contract's `view` function reads state that is inconsistent during another contract's external call. A lending protocol reading a pool's `getRate()` during a join/exit operation gets a manipulated price because the pool has transferred tokens but hasn't updated its accounting yet.

```solidity
// Balancer pool during join (simplified):
function joinPool() external {
    // 1. Transfer tokens from user to pool
    token.transferFrom(msg.sender, address(this), amount);
    // 2. External callback (e.g., for hooks or nested calls)
    // At this point, pool has more tokens but hasn't minted BPT yet
    // getRate() returns an inflated rate
    // 3. Mint BPT to user
    _mint(msg.sender, shares);
    // 4. Update internal accounting
}
```

If a lending protocol calls `pool.getRate()` during step 2, it gets an inflated price. The attacker deposits the overpriced BPT as collateral and borrows against it.

**Real-world impact:** Multiple protocols have been hit by read-only reentrancy through Balancer and Curve pool interactions. The [Sentiment protocol lost ~$1M in April 2023](https://rekt.news/sentiment-rekt/) to exactly this pattern. See also the [Balancer read-only reentrancy advisory](https://forum.balancer.fi/t/reentrancy-vulnerability-scope-expanded/4345).

<a id="read-only-reentrancy-walkthrough"></a>
#### 🔍 Deep Dive: Read-Only Reentrancy — Numeric Walkthrough

Let's trace exactly how the Sentiment/Balancer exploit works with concrete numbers.

**Setup:**
- Balancer pool: 1,000 WETH + 1,000,000 USDC (BPT total supply: 10,000)
- `getRate()` = totalPoolValue / BPT supply = ($2M + $1M) / 10,000 = **$300 per BPT**
- Lending protocol accepts BPT as collateral, reads `pool.getRate()` for valuation
- Attacker holds 100 BPT (worth $30,000 at fair rate)

```
Step 1: Attacker calls joinPool() to add 500 ETH ($1M) to the Balancer pool
────────────────────────────────────────────────────────────────────────────

  Inside joinPool():
    ① Pool receives 500 ETH from attacker via transferFrom
       Pool balances now: 1,500 ETH + 1,000,000 USDC
       BUT BPT not yet minted — still 10,000 BPT outstanding

    ② Pool makes an external callback (e.g., ETH receive hook, or nested call)

    ─── DURING THE CALLBACK (between ① and ③) ───────────────────────

       Pool state is INCONSISTENT:
         Real pool value: (1,500 × $2,000) + $1,000,000 = $4,000,000
         BPT supply: 10,000 (unchanged — new BPT not minted yet!)

         getRate() = $4,000,000 / 10,000 = $400 per BPT  ← inflated 33%!

       The attacker's callback:
         → Deposit 100 BPT into lending protocol as collateral
         → Lending protocol reads getRate() → sees $400/BPT
         → Collateral valued at: 100 × $400 = $40,000

         At 150% collateralization, attacker borrows: $40,000 / 1.5 = $26,667
         Fair value of 100 BPT: 100 × $300 = $30,000
         Fair borrowing capacity: $30,000 / 1.5 = $20,000

         Excess borrowed: $26,667 - $20,000 = $6,667 stolen

    ───────────────────────────────────────────────────────────────────

    ③ Pool mints new BPT to attacker — getRate() returns to normal
       BPT minted ≈ 10,000 × (√1.5 - 1) ≈ 2,247  (single-sided join penalty)
       New BPT supply ≈ 12,247 → getRate() ≈ $4M / 12,247 ≈ $327
       (Higher than $300 because single-sided join adds value unevenly)

Step 2: Attacker walks away with $6,667 excess borrow
──────────────────────────────────────────────────────
  The 100 BPT collateral is worth $30,000 at fair price
  but backs $26,667 in debt — protocol is under-collateralized.
  If BPT price dips even slightly, the position becomes bad debt.

  Scale this up 100×: 10,000 BPT + larger join → $666,700 stolen.
  That's how Sentiment lost ~$1M.
```

**Why `nonReentrant` on the lending protocol doesn't help:** The lending protocol's `deposit()` isn't being reentered — it's called for the first time during the callback. It's the *Balancer pool* that's in a reentrant state. The lending protocol is just an innocent bystander reading a corrupted view function.

**The fix:** Before reading `getRate()`, verify the pool isn't mid-transaction:

```solidity
// Call a state-modifying function on Balancer Vault that reverts if locked
// manageUserBalance with empty array is a no-op but checks the reentrancy lock
IVault(balancerVault).manageUserBalance(new IVault.UserBalanceOp[](0));
// If we reach here, the vault isn't in a reentrant state — safe to read
uint256 rate = pool.getRate();
```

**Defense:**
- Never trust external `view` functions during your own state transitions
- Check reentrancy locks on external protocols before reading their rates ([Balancer V2 Vault](https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/vault/contracts/Vault.sol) pools have a `getPoolTokens` that reverts if the vault is in a reentrancy state — use it)
- Use time-delayed or externally-sourced rates instead of live pool calculations

<a id="cross-contract-reentrancy"></a>
### 💡 Concept: Cross-Contract Reentrancy in DeFi Compositions

When your protocol interacts with multiple external protocols, reentrancy can occur across trust boundaries:

```
Your Protocol → Aave (supply) → aToken callback → Your Protocol (read stale state)
Your Protocol → Uniswap (swap) → token transfer → receiver fallback → Your Protocol
```

**Defense:** Apply `nonReentrant` globally (not per-function) when your protocol makes external calls that could trigger callbacks. For protocols that interact with many external contracts, a single transient storage lock covering all entry points is the cleanest approach.

<a id="price-manipulation"></a>
#### 📋 Price Manipulation Taxonomy

This consolidates oracle attacks from Module 3 with flash loan amplification from Module 5:

**Category 1: Spot price manipulation via flash loan**
- Borrow → swap on DEX → manipulate price → exploit protocol reading spot price → swap back → repay
- Cost: gas only (flash loan is free if profitable)
- Defense: never use DEX spot prices, use Chainlink or TWAP
- Real example: [Polter Finance (2024)](https://rekt.news/polter-finance-rekt/) — flash-loaned BOO tokens, drained SpookySwap pools, deposited minimal BOO valued at $1.37 trillion

**Category 2: TWAP manipulation**
- Sustain price manipulation across the TWAP window
- Cost: capital × time (expensive for deep-liquidity pools with long windows)
- Defense: minimum 30-minute window, use deep-liquidity pools, multi-oracle

**Category 3: Donation/balance manipulation**
- Transfer tokens directly to a contract to inflate `balanceOf`-based calculations
- Affects: vault share prices (Module 7 inflation attack), reward calculations, any logic using `balanceOf`
- Defense: internal accounting, virtual shares/assets

**Category 4: [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) exchange rate manipulation**
- Inflate vault token exchange rate, use overvalued vault tokens as collateral
- [Venus Protocol lost 86 WETH](https://rekt.news/venus-protocol-rekt2/) in February 2025 to exactly this attack
- [Resupply protocol exploited](https://rekt.news/resupply-rekt/) via the same vector in 2025
- Defense: time-weighted exchange rates, external oracles for vault tokens, rate caps, virtual shares

**Category 5: Governance manipulation via flash loan**
- Flash-borrow governance tokens, vote on malicious proposal, return tokens
- Defense: snapshot-based voting (power based on past block), timelocks, quorum requirements
- Most modern governance ([OpenZeppelin Governor](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/Governor.sol), [Compound Governor Bravo](https://github.com/compound-finance/compound-governance/blob/master/contracts/GovernorBravoDelegate.sol)) already uses snapshot voting

<a id="flash-loan-walkthrough"></a>
#### 🔍 Deep Dive: Flash Loan Attack P&L Walkthrough

**Scenario:** A lending protocol uses Uniswap V2 spot prices for collateral valuation. An attacker exploits this with a flash loan.

**Setup:**
- Uniswap V2 ETH/USDC pool: 1,000 ETH + 2,000,000 USDC (spot price = $2,000/ETH)
- Lending protocol: 500,000 USDC available to borrow, requires 150% collateralization
- Attacker starts with: 0 capital (uses flash loan)

**The key insight:** The attacker needs to *inflate* the ETH price on Uniswap, so they buy ETH with USDC. Flash-borrowing USDC and swapping it into the pool pushes the ETH/USDC ratio up.

```
Step 1: Flash borrow 1,500,000 USDC from Balancer (0 fee)
─────────────────────────────────────────────────────────
  ┌──────────────────────────────────────────────────┐
  │  Attacker: 1,500,000 USDC (borrowed)             │
  │  Cost so far: 0 (flash loan is free if repaid)   │
  └──────────────────────────────────────────────────┘

Step 2: Swap 1,500,000 USDC → ETH on Uniswap V2
─────────────────────────────────────────────────
  Pool before: 1,000 ETH / 2,000,000 USDC  (k = 2,000,000,000)
  New USDC in pool: 2,000,000 + 1,500,000 = 3,500,000
  New ETH in pool:  2,000,000,000 / 3,500,000 = 571 ETH  (k preserved)
  ETH received: 1,000 - 571 = 429 ETH
  New spot price: 3,500,000 / 571 = $6,130/ETH  ← inflated 3×!

  ┌──────────────────────────────────────────────────┐
  │  Attacker: 429 ETH                               │
  │  Uniswap spot: $6,130/ETH (was $2,000)           │
  │  Real market price: still ~$2,000/ETH             │
  └──────────────────────────────────────────────────┘

Step 3: Deposit 100 ETH as collateral into lending protocol
───────────────────────────────────────────────────────────
  Protocol reads Uniswap spot: 100 × $6,130 = $613,000 collateral value
  At 150% collateralization: can borrow up to $613,000 / 1.5 = $408,667
  Attacker borrows: 400,000 USDC

  ┌──────────────────────────────────────────────────┐
  │  Attacker: 329 ETH + 400,000 USDC                │
  │  Lending position: 100 ETH collateral / 400k debt│
  └──────────────────────────────────────────────────┘

Step 4: Swap 329 ETH → USDC on Uniswap (reverse the manipulation)
──────────────────────────────────────────────────────────────────
  Pool before: 571 ETH / 3,500,000 USDC
  New ETH in pool: 571 + 329 = 900
  New USDC in pool: 2,000,000,000 / 900 = 2,222,222
  USDC received: 3,500,000 - 2,222,222 = 1,277,778 USDC

  ┌──────────────────────────────────────────────────┐
  │  Attacker: 400,000 + 1,277,778 = 1,677,778 USDC │
  │  Uniswap spot recovering toward ~$2,222/ETH      │
  └──────────────────────────────────────────────────┘

Step 5: Repay flash loan: 1,500,000 USDC
────────────────────────────────────────

  ┌──────────────────────────────────────────────────┐
  │  ATTACKER P&L:                                    │
  │  USDC in hand: 1,677,778                         │
  │  Flash loan repay: -1,500,000                    │
  │  Net profit: +177,778 USDC                       │
  │                                                   │
  │  Plus: 100 ETH locked as collateral, 400k debt   │
  │  Attacker walks away — never repays the loan.    │
  │  After price normalizes: 100 ETH = $200,000      │
  │  but debt = $400,000 → protocol has $200k bad debt│
  │                                                   │
  │  Total value extracted: ~$178k (kept) + ~$200k   │
  │  (bad debt absorbed by protocol/depositors)       │
  │  Attacker cost: gas only                          │
  └──────────────────────────────────────────────────┘
```

**Why this works:** The lending protocol trusts Uniswap's instantaneous spot price as the truth. But spot price is just the ratio of reserves — trivially manipulable with enough capital. The attacker has unlimited capital via flash loans. The entire attack — borrow, swap, deposit, borrow, swap back, repay — executes atomically in a single transaction.

**Why Chainlink prevents this:** Chainlink prices come from off-chain aggregation of multiple exchanges. A swap on one Uniswap pool doesn't affect the Chainlink price. Even TWAP oracles resist this because the manipulation must be sustained across the averaging window (expensive for deep-liquidity pools).

<a id="frontrunning-mev"></a>
### 💡 Concept: Frontrunning and MEV

**Sandwich attacks:** Attacker sees your pending swap in the mempool. They front-run (buy before you, pushing price up), your swap executes at the worse price, they back-run (sell after you, profiting from the difference).

Defense: slippage protection (`amountOutMin` in Uniswap swaps), private transaction submission (Flashbots Protect, MEV Blocker), deadline parameters.

**Just-In-Time (JIT) liquidity:** Specific to concentrated liquidity AMMs. An attacker adds concentrated liquidity right before a large swap (capturing fees) and removes it right after. Not a vulnerability per se, but reduces fees going to passive LPs.

**Liquidation MEV:** When a position becomes liquidatable, MEV searchers race to execute the liquidation (and capture the bonus). For protocol builders: ensure your liquidation mechanism is MEV-aware and that the bonus isn't so large it incentivizes price manipulation to trigger liquidations.

<a id="precision-loss"></a>
### 💡 Concept: Precision Loss and Rounding Exploits

Integer division in Solidity always truncates (rounds toward zero). In DeFi, this creates two distinct classes of vulnerability:

**Class 1: Silent reward loss (truncation to zero)**

When a reward pool distributes rewards proportionally, the accumulator update divides reward by total staked:

```solidity
// VULNERABLE: unscaled accumulator
rewardPerTokenStored += rewardAmount / totalStaked;
// If totalStaked = 1000e18 and rewardAmount = 100 wei:
//   100 / 1000e18 = 0  ← TRUNCATED! Rewards lost forever.
```

This isn't a one-time bug — it compounds. Every small reward distribution that truncates is value permanently stuck in the contract. Over time, this can represent significant losses, especially for tokens with small decimal precision or high-value-per-unit tokens.

**The fix — scale before dividing:**

```solidity
// SAFE: scaled accumulator (Synthetix StakingRewards pattern)
uint256 constant PRECISION = 1e18;
rewardPerTokenStored += rewardAmount * PRECISION / totalStaked;
// Example: 10_000 * 1e18 / 5000e18 = 1e22 / 5e21 = 2  (preserved, not truncated!)

// When calculating earned:
earned = staked[account] * (rewardPerToken - paid) / PRECISION;
// Example: 5000e18 * 2 / 1e18 = 10_000  (full reward recovered)
```

This is the standard pattern used by [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol), Convex, and virtually every production reward distribution contract.

**Class 2: Rounding direction exploits**

In share-based systems (vaults, lending), rounding direction matters:
- **Deposits:** round shares DOWN (give user fewer shares → protects vault)
- **Withdrawals:** round assets DOWN (give user fewer tokens → protects vault)

If rounding favors the user in either direction, they can extract value through repeated small operations:

```
Deposit 1 wei → receive 1 share (should be 0.7, rounded UP to 1)
Withdraw 1 share → receive 1 token (should be 0.7, rounded UP to 1)
Repeat 1000 times → extract ~300 wei from vault
```

At scale (or with low-decimal tokens like USDC with 6 decimals), this becomes significant.

**The fix — always round against the user:**

```solidity
// ERC-4626 standard: deposit rounds shares DOWN, withdraw rounds assets DOWN
function convertToShares(uint256 assets) public view returns (uint256) {
    return assets * totalSupply() / totalAssets(); // rounds down (fewer shares)
}

function convertToAssets(uint256 shares) public view returns (uint256) {
    return shares * totalAssets() / totalSupply(); // rounds down (fewer assets)
}
```

For mulDiv with explicit rounding: use OpenZeppelin's `Math.mulDiv(a, b, c, Math.Rounding.Ceil)` when rounding should favor the protocol.

**Where precision loss appears in DeFi:**

| Protocol Type | Where Truncation Hits | Impact |
|---|---|---|
| Reward pools | `reward / totalStaked` accumulator | Rewards silently lost |
| Vaults (ERC-4626) | Share/asset conversions | Value extraction via repeated small ops |
| Lending (Aave, Compound) | Interest index updates | Interest can be rounded away for small positions |
| AMMs | Fee collection and distribution | LP fees lost to rounding |
| CDPs (MakerDAO) | `art * rate` debt calculation | Dust debt that can't be fully repaid |

**Real-world examples:**
- Multiple vault protocols have had audit findings for incorrect rounding direction in `deposit()`/`mint()`/`withdraw()`/`redeem()`
- Aave V3 uses `WadRayMath` (1e27 scale factor) specifically to minimize precision loss in interest calculations
- MakerDAO's Vat tracks debt as `art * rate` (both in RAY = 1e27) to preserve precision across stability fee accruals

<a id="access-control-attacks"></a>
### 💡 Concept: Access Control Vulnerabilities

Access control is the [#1 vulnerability in the OWASP Smart Contract Top 10](https://owasp.org/www-project-smart-contract-top-10/) (2024 and 2025). It's devastatingly simple and the most common cause of total fund loss in DeFi.

**Pattern 1: Missing initializer guard (upgradeable contracts)**

Upgradeable contracts use `initialize()` instead of `constructor()` (constructors don't run in proxy context). If `initialize()` can be called more than once, anyone can re-initialize and claim ownership:

```solidity
// VULNERABLE: no initialization guard
function initialize(address owner_) external {
    owner = owner_;  // Can be called repeatedly — attacker overwrites owner
}
```

```solidity
// SAFE: OpenZeppelin Initializable pattern
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

function initialize(address owner_) external initializer {
    owner = owner_;  // initializer modifier ensures this runs only once
}
```

**Critical subtlety:** Even with `initializer`, the implementation contract itself (not the proxy) can be initialized by anyone if you don't call `_disableInitializers()` in the constructor. This is a common pattern found in multiple audits — an attacker calls `initialize()` directly on the implementation contract (bypassing the proxy), becomes the owner of the implementation, and then uses `selfdestruct` or other privileged functions to compromise the system. The [Parity wallet freeze ($150M, 2017)](https://rekt.news/parity-rekt/) is the most famous example: an unprotected `initWallet()` on the library contract allowed an attacker to take ownership and self-destruct it, permanently freezing all dependent wallets.

```solidity
// PRODUCTION PATTERN: disable initializers on implementation
constructor() {
    _disableInitializers();  // Prevents anyone from initializing the implementation
}
```

**Pattern 2: Unprotected critical functions**

Functions that move funds, change parameters, or pause the protocol must have access control. The pattern is simple, but forgetting it on even one function is catastrophic:

```solidity
// VULNERABLE: anyone can drain the vault
function emergencyWithdraw() external {
    token.transfer(owner, token.balanceOf(address(this)));
}

// SAFE: owner-only access
function emergencyWithdraw() external {
    require(msg.sender == owner, "not owner");
    token.transfer(owner, token.balanceOf(address(this)));
}
```

For protocols with multiple roles (admin, guardian, strategist), use OpenZeppelin's `AccessControl` with named roles instead of simple `owner` checks.

**Pattern 3: Missing function visibility**

In older Solidity versions (< 0.8.0), functions without explicit visibility defaulted to `public`. Modern Solidity requires explicit visibility, but the lesson still applies: always review that internal helper functions aren't accidentally `external` or `public`.

**The OWASP Smart Contract Top 10 access control patterns:**
1. Unprotected `initialize()` — re-initialization overwrites owner
2. Missing `onlyOwner` / role checks on critical functions
3. `tx.origin` used for authentication (phishable via intermediate contract)
4. Incorrect role assignment in constructor/initializer
5. Missing two-step ownership transfer (single-step transfer to wrong address = permanent lockout)

**Defense checklist:**
- [ ] Every `initialize()` uses `initializer` modifier (OpenZeppelin Initializable)
- [ ] Implementation contracts call `_disableInitializers()` in constructor
- [ ] Every fund-moving function has appropriate access control
- [ ] Ownership transfer uses two-step pattern (`Ownable2Step`)
- [ ] Never use `tx.origin` for authentication
- [ ] All roles assigned correctly in initializer, verified in tests

<a id="composability-risk"></a>
### 💡 Concept: Composability Risk

DeFi's composability means your protocol interacts with others in ways you can't fully predict:
- Your vault accepts aTokens as collateral → aTokens interact with Aave → Aave interacts with Chainlink → Chainlink relies on external data providers
- A flash loan from Balancer funds an operation on your protocol that calls a Curve pool that triggers a reentrancy via a Vyper callback

**Defense:**
- Document every external dependency and its assumptions
- Consider what happens if any dependency fails, returns unexpected values, or is malicious
- Use interface types (not concrete contracts) and validate return values
- Implement circuit breakers that pause the protocol if unexpected conditions are detected

#### 💼 Job Market Context

**What DeFi teams expect you to know about attack patterns:**

1. **"Walk me through a read-only reentrancy attack."**
   - Good answer: Explains that a view function reads inconsistent state during an external call's callback
   - Great answer: Gives the Balancer BPT / Sentiment example — pool has received tokens but hasn't minted BPT yet, so `getRate()` is inflated. Mentions that the defense is checking the vault's reentrancy lock *before* reading the rate, and that this class of bug is extremely common in DeFi compositions

2. **"How would you prevent price manipulation in a lending protocol?"**
   - Good answer: Use Chainlink instead of spot prices, add staleness checks
   - Great answer: Describes the full taxonomy — spot manipulation (flash loan + swap), TWAP manipulation (capital × time), donation attacks (`balanceOf` inflation), ERC-4626 exchange rate attacks. Explains that defense is layered: primary oracle + TWAP fallback + rate caps + circuit breakers. Mentions that even "safe" oracles like Chainlink need staleness checks, L2 sequencer checks, and zero-price validation

3. **"What's the most underestimated attack vector in DeFi right now?"**
   - Strong answer: Composability risk / cross-protocol interactions. Any time your protocol reads state from another protocol, you inherit their entire attack surface. Read-only reentrancy is one example, but there's also governance manipulation, oracle dependency chains, and the risk of external protocol upgrades changing behavior. The defense is documenting every external dependency and its failure modes

**Interview red flags:**
- ❌ Only knowing about classic reentrancy (state-modifying) but not read-only reentrancy
- ❌ Saying "just use Chainlink" without mentioning staleness checks, L2 sequencer, or multi-oracle patterns
- ❌ Not knowing about flash-loan-amplified attacks (thinking flash loans are just for arbitrage)

**Pro tip:** In security-focused interviews, employers care less about memorizing every exploit and more about your *systematic thinking*. Show that you have a mental taxonomy of attack classes and can map any new vulnerability into it. That's what separates a protocol engineer from a developer.

## 🎯 Build Exercise: Security Exploits and Defenses

**Workspace:** [`workspace/src/part2/module8/exercise1-reentrancy/`](../workspace/src/part2/module8/exercise1-reentrancy/) — starter files: [`ReentrancyAttack.sol`](../workspace/src/part2/module8/exercise1-reentrancy/ReentrancyAttack.sol), [`DefendedLending.sol`](../workspace/src/part2/module8/exercise1-reentrancy/DefendedLending.sol), tests: [`ReadOnlyReentrancy.t.sol`](../workspace/test/part2/module8/exercise1-reentrancy/ReadOnlyReentrancy.t.sol)

**Exercise 1: Read-only reentrancy exploit.** Build a mock vault whose `getSharePrice()` returns an inflated value during a `deposit()` that makes an external callback. Build a lending protocol that reads this value. Show how an attacker can deposit during the callback to get overvalued collateral. Fix it by checking the vault's reentrancy state.

**Workspace:** [`workspace/src/part2/module8/exercise2-oracle/`](../workspace/src/part2/module8/exercise2-oracle/) — starter files: [`OracleAttack.sol`](../workspace/src/part2/module8/exercise2-oracle/OracleAttack.sol), [`SecureLending.sol`](../workspace/src/part2/module8/exercise2-oracle/SecureLending.sol), tests: [`OracleManipulation.t.sol`](../workspace/test/part2/module8/exercise2-oracle/OracleManipulation.t.sol)

**Exercise 2: Oracle manipulation exploit.** Build a vulnerable lending protocol that reads AMM spot prices. Execute a flash loan attack: flash-borrow tokens, swap on the AMM to manipulate the price, deposit collateral into the lending protocol (now overvalued), borrow against the inflated collateral, swap back to restore the price, and repay the flash loan keeping the profit. Then fix the lending protocol to use Chainlink and verify the attack fails.

**Workspace:** [`workspace/src/part2/module8/exercise3-invariant/`](../workspace/src/part2/module8/exercise3-invariant/) — starter files: [`BuggyVault.sol`](../workspace/src/part2/module8/exercise3-invariant/BuggyVault.sol), [`VaultHandler.sol`](../workspace/src/part2/module8/exercise3-invariant/VaultHandler.sol), tests: [`VaultInvariant.t.sol`](../workspace/test/part2/module8/exercise3-invariant/VaultInvariant.t.sol)

**Exercise 3: Invariant testing.** Write a handler contract and invariant tests for `BuggyVault` — a share-based vault with a subtle ordering bug in `withdraw()`. Implement the handler's `deposit()` and `withdraw()` with actor management and ghost variable tracking, then write solvency and fairness invariants that automatically find the bug through random call sequences. (See the Invariant Testing section below for full details.)

**Workspace:** [`workspace/src/part2/module8/exercise4-precision-loss/`](../workspace/src/part2/module8/exercise4-precision-loss/) — starter files: [`RoundingExploit.sol`](../workspace/src/part2/module8/exercise4-precision-loss/RoundingExploit.sol), [`DefendedRewardPool.sol`](../workspace/src/part2/module8/exercise4-precision-loss/DefendedRewardPool.sol), tests: [`PrecisionLoss.t.sol`](../workspace/test/part2/module8/exercise4-precision-loss/PrecisionLoss.t.sol)

**Exercise 4: Precision loss exploit.** A reward pool distributes tokens proportionally, but uses an unscaled accumulator (`reward / totalStaked`). When `totalStaked` is large, rewards truncate to zero. Exploit this by staking a tiny amount (1 wei) when you're the only staker to capture 100% of rewards. Then fix the pool using the Synthetix scaled-accumulator pattern (`reward * 1e18 / totalStaked`).

**Workspace:** [`workspace/src/part2/module8/exercise5-access-control/`](../workspace/src/part2/module8/exercise5-access-control/) — starter files: [`AccessControlAttack.sol`](../workspace/src/part2/module8/exercise5-access-control/AccessControlAttack.sol), [`DefendedVault.sol`](../workspace/src/part2/module8/exercise5-access-control/DefendedVault.sol), tests: [`AccessControl.t.sol`](../workspace/test/part2/module8/exercise5-access-control/AccessControl.t.sol)

**Exercise 5: Access control exploit.** A vault has two bugs: `initialize()` can be re-called to overwrite the owner, and `emergencyWithdraw()` has no access control. Exploit both to drain user funds in a single transaction. Then build a defended version with initialization guards and proper owner checks.

## 📋 Key Takeaways: DeFi-Specific Attack Patterns

After this section, you should be able to:

- Explain read-only reentrancy: how `view` functions can return inconsistent state during callbacks, and why this is the most common "new" DeFi exploit pattern
- Classify price manipulation attacks into the 5 categories (spot, TWAP, donation, governance, composability) and trace an attack chain that combines flash loan + manipulation + assumption violation
- Identify precision loss vulnerabilities: truncation-to-zero in reward accumulators, rounding direction exploits in share-based systems, and apply the correct rounding direction fix
- Spot access control gaps: missing initializer guards, unprotected critical functions, and explain the Wormhole-style implementation initialization attack

---

## 💡 Invariant Testing with Foundry

<a id="why-invariant-testing"></a>
### 💡 Concept: Why Invariant Testing Is the Most Powerful DeFi Testing Tool

Unit tests verify specific scenarios you think of. Fuzz tests verify single functions with random inputs. Invariant tests verify that properties hold across random *sequences* of function calls — finding edge cases no human would think to test.

For DeFi protocols, invariants encode the fundamental properties your protocol must maintain:

- "Total supply of shares equals sum of all balances" ([ERC-20](https://eips.ethereum.org/EIPS/eip-20))
- "Sum of all deposits minus withdrawals equals total assets" (Vault)
- "No user can withdraw more than they deposited plus their share of yield" (Vault)
- "A position with health factor > 1 cannot be liquidated" (Lending)
- "Total borrowed ≤ total supplied" (Lending)
- "Every vault has collateral ratio ≥ minimum OR is being liquidated" (CDP)

<a id="invariant-setup"></a>
### 🔧 Foundry Invariant Testing Setup

```solidity
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract VaultInvariantTest is StdInvariant, Test {
    Vault vault;
    VaultHandler handler;

    function setUp() public {
        vault = new Vault(address(token));
        handler = new VaultHandler(vault, token);

        // Tell Foundry to only call functions on the handler
        targetContract(address(handler));
    }

    // Invariant: total shares value = total assets
    function invariant_totalAssetsMatchesShares() public view {
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        if (totalShares == 0) {
            assertEq(totalAssets, 0);
        } else {
            uint256 totalRedeemable = vault.convertToAssets(totalShares);
            assertApproxEqAbs(totalRedeemable, totalAssets, 10); // Allow small rounding
        }
    }

    // Invariant: no individual can withdraw more than their share
    function invariant_noFreeTokens() public view {
        assertGe(
            token.balanceOf(address(vault)),
            vault.totalAssets()
        );
    }
}
```

<a id="handler-contracts"></a>
### 🔧 Handler Contracts: The Key to Effective Invariant Testing

The handler wraps your protocol's functions with bounded inputs and realistic constraints:

```solidity
contract VaultHandler is Test {
    Vault vault;
    IERC20 token;

    // Ghost variables: track cumulative state for invariant checks
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    // Track actors
    address[] public actors;
    address currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function deposit(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        amount = bound(amount, 1, token.balanceOf(currentActor));
        if (amount == 0) return;

        token.approve(address(vault), amount);
        vault.deposit(amount, currentActor);
        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        uint256 maxWithdraw = vault.maxWithdraw(currentActor);
        amount = bound(amount, 0, maxWithdraw);
        if (amount == 0) return;

        vault.withdraw(amount, currentActor, currentActor);
        ghost_totalWithdrawn += amount;
    }
}
```

**Ghost variables** track cumulative state that isn't stored on-chain — total deposited, total withdrawn, per-user totals. These enable invariants like "total deposited - total withdrawn ≈ totalAssets (accounting for yield)."

**Actor management** simulates multiple users interacting with the protocol. The `useActor` modifier selects a random user from a pool and pranks as them.

**Bounded inputs** ensure the fuzzer generates realistic values (not amounts greater than the user's balance, not zero addresses).

### ⚙️ Configuration

```toml
# foundry.toml
[invariant]
runs = 256          # Number of test sequences
depth = 50          # Number of calls per sequence
fail_on_revert = false  # Don't fail on expected reverts
```

Higher depth = longer call sequences = more likely to find complex multi-step bugs. For production, use `runs = 1000+` and `depth = 100+`.

<a id="invariant-quick-try"></a>
💻 **Quick Try: Invariant Testing Catches a Bug**

Here's a minimal vault with a subtle bug in `withdraw()`. The invariant test finds it — unit tests wouldn't:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal vault with a subtle bug — can you spot it?
contract BuggyVault is ERC20("Vault", "vTKN") {
    IERC20 public immutable asset;

    constructor(IERC20 _asset) { asset = _asset; }

    function deposit(uint256 amount) external returns (uint256 shares) {
        shares = totalSupply() == 0
            ? amount
            : amount * totalSupply() / asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 amount) {
        _burn(msg.sender, shares);
        // BUG: totalSupply() is now REDUCED — each share redeems more than it should
        amount = shares * asset.balanceOf(address(this)) / totalSupply();
        asset.transfer(msg.sender, amount);
    }
}
```

Now write a test that catches it:

```solidity
// BuggyVaultInvariant.t.sol
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

contract BuggyVaultHandler is Test {
    BuggyVault vault;
    MockERC20 token;
    address[] public actors;
    mapping(address => uint256) public ghost_deposited;  // per-actor deposits
    mapping(address => uint256) public ghost_withdrawn;  // per-actor withdrawals

    constructor(BuggyVault _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            token.mint(actor, 100_000e18);
            vm.prank(actor);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 amount, uint256 actorSeed) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        amount = bound(amount, 1e18, token.balanceOf(actor));
        if (amount == 0) return;
        vm.prank(actor);
        vault.deposit(amount);
        ghost_deposited[actor] += amount;
    }

    function withdraw(uint256 shares, uint256 actorSeed) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 bal = vault.balanceOf(actor);
        shares = bound(shares, 0, bal);
        if (shares == 0) return;
        uint256 balBefore = token.balanceOf(actor);
        vm.prank(actor);
        vault.withdraw(shares);
        uint256 balAfter = token.balanceOf(actor);
        ghost_withdrawn[actor] += (balAfter - balBefore);
    }

    function actorCount() external view returns (uint256) { return actors.length; }
}

contract BuggyVaultInvariantTest is StdInvariant, Test {
    BuggyVault vault;
    MockERC20 token;
    BuggyVaultHandler handler;

    function setUp() public {
        token = new MockERC20();
        vault = new BuggyVault(token);
        handler = new BuggyVaultHandler(vault, token);
        targetContract(address(handler));
    }

    /// @dev Fairness: no actor withdraws more than they deposited (no yield in this vault)
    function invariant_noActorProfits() public view {
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 withdrawn = handler.ghost_withdrawn(actor);
            uint256 deposited = handler.ghost_deposited(actor);
            assertLe(
                withdrawn,
                deposited + 1e18,  // allow 1 token rounding
                "Fairness violated: actor withdrew more than deposited"
            );
        }
    }
}
```

Run with `forge test --match-contract BuggyVaultInvariantTest`. The `invariant_noActorProfits` test will **fail**. Here's why — trace through a deposit/deposit/withdraw sequence:

```
Actor A deposits 100e18:  shares = 100e18 (first deposit)
Actor B deposits 100e18:  shares = 100e18 * 100e18 / 100e18 = 100e18
State: vault balance = 200e18, totalSupply = 200e18, A = 100e18, B = 100e18

Actor A withdraws 100 shares:
  _burn(A, 100e18)        → totalSupply = 100e18
  amount = 100e18 * 200e18 / 100e18 = 200e18  ← A drains EVERYTHING!
  transfer(A, 200e18)     → vault balance = 0

B has 100e18 shares backed by 0 tokens. A stole B's deposit.
```

The invariant catches it: A deposited 100e18 but withdrew 200e18. Since this is a no-yield vault, no actor should ever profit — `withdrawn > deposited` is a clear fairness violation.

**Why not a conservation invariant?** You might be tempted to check `vault_balance == total_deposits - total_withdrawals`. That's a tautology — if the handler tracks actual token flows, deposits minus withdrawals always equals the balance by construction. The burn-before-calculate bug is a *fairness* bug (it redistributes value between users) not a *conservation* bug (no tokens are created or destroyed). Fairness invariants that track per-actor flows are the right tool here.

**The fix:** Calculate the amount *before* burning shares:

```solidity
function withdraw(uint256 shares) external returns (uint256 amount) {
    amount = shares * asset.balanceOf(address(this)) / totalSupply();
    _burn(msg.sender, shares);  // burn AFTER calculating amount
    asset.transfer(msg.sender, amount);
}
```

This is exactly the kind of ordering bug that unit tests miss — you'd have to think of the exact multi-user interleaving. Invariant tests find it automatically by exploring random call sequences.

<a id="invariant-catalog"></a>
#### 📋 What Invariants to Test for Each DeFi Primitive

**For a vault/ERC-4626:**
- Total assets ≥ sum of all shares × share price (no phantom assets)
- After deposit: user shares increase, vault assets increase by same amount
- After withdrawal: user shares decrease, user receives expected assets
- Share price never decreases (if no strategy losses reported)
- Rounding never favors the user

**For a lending protocol:**
- Total borrowed ≤ total supplied
- No user can borrow without sufficient collateral
- Health factor of every position ≥ 1 OR position is flagged for liquidation
- Interest index only increases
- After liquidation: position health factor improves

**For an AMM:**
- k = x × y (constant product) holds after every swap (minus fees)
- LP token supply matches liquidity provided
- Sum of all LP claim values = total pool value

**For a CDP/stablecoin:**
- Every vault has collateral ratio ≥ minimum OR is being liquidated
- Total stablecoin supply = sum of all vault debt
- Stability fee index only increases

#### 🔍 Deep Dive: Writing Good Invariants — A Mental Model

Coming up with invariants can feel abstract. Here's a systematic approach:

**Step 1: Ask "What must ALWAYS be true?"**

Think about your protocol from the perspective of conservation laws:
- **Conservation of value:** tokens in = tokens out (no creation or destruction)
- **Conservation of accounting:** internal records match actual balances
- **Conservation of solvency:** the protocol can always meet its obligations

**Step 2: Ask "What must NEVER happen?"**

Flip it — think about what would be catastrophic:
- A user withdraws more than they deposited + earned
- Total borrowed exceeds total supplied
- A liquidation makes the protocol *less* solvent
- Share price goes to 0 (or infinity)

**Step 3: Map actions to state transitions**

For each function in your protocol, trace what changes:

```
deposit(amount):
  BEFORE: totalAssets = X,  userShares = S,  totalShares = T
  AFTER:  totalAssets = X+amount,  userShares = S+newShares,  totalShares = T+newShares
  INVARIANT: newShares ≤ amount * T / X  (rounding down protects vault)
```

**Step 4: Add ghost variables for cumulative tracking**

On-chain state only shows the *current* state. Ghost variables track the *history*:

```
ghost_totalDeposited += amount    // in handler's deposit()
ghost_totalWithdrawn += amount    // in handler's withdraw()

// Invariant: totalAssets ≈ ghost_totalDeposited - ghost_totalWithdrawn + yieldAccrued
```

**Step 5: Think adversarially**

What if one actor calls functions in an unexpected order? What if they:
- Deposit 0? Deposit type(uint256).max?
- Withdraw immediately after depositing?
- Deposit, transfer shares to another address, both withdraw?
- Call functions during a callback?

The handler's `bound()` function handles invalid inputs, but the *sequence* of valid calls is where real bugs hide.

**Common invariant testing pitfalls:**
- Writing invariants that are too loose (always pass, catch nothing)
- Not having enough actors (single-actor tests miss multi-user edge cases)
- Not tracking ghost variables (can't verify cumulative properties)
- Setting `depth` too low (complex bugs need 20+ step sequences)

## 🎯 Build Exercise: Invariant Testing

**Workspace:** [`workspace/src/part2/module8/exercise3-invariant/`](../workspace/src/part2/module8/exercise3-invariant/) — starter files: [`BuggyVault.sol`](../workspace/src/part2/module8/exercise3-invariant/BuggyVault.sol), [`VaultHandler.sol`](../workspace/src/part2/module8/exercise3-invariant/VaultHandler.sol), tests: [`VaultInvariant.t.sol`](../workspace/test/part2/module8/exercise3-invariant/VaultInvariant.t.sol)

Write a comprehensive invariant test suite for your SimpleLendingPool from Module 4:

1. **Handler contract** with: `supply()`, `borrow()`, `repay()`, `withdraw()`, `liquidate()`, `accrueInterest()` — all with bounded inputs and actor management

2. **Invariants:**
   - Total supplied assets ≥ total borrowed
   - Health factor of every borrower is either ≥ 1 or they have no borrow
   - Interest indices only increase
   - No user can borrow without sufficient collateral
   - Sum of all user supply balances ≈ total supply (accounting for interest)

3. **Ghost variables:** total deposited, total withdrawn, total borrowed, total repaid, total liquidated

4. Run with `depth = 50, runs = 500`. If any invariant breaks, you have a bug — fix it and re-run.

## 📋 Key Takeaways: Invariant Testing with Foundry

After this section, you should be able to:

- Set up Foundry invariant testing: `StdInvariant`, `targetContract`, handler contracts with bounded inputs, `useActor` modifier for multi-actor testing
- Design handler contracts that define a realistic action space: bounded amounts, valid actor selection, and ghost variables that track cumulative state for invariant assertions
- Write invariant assertions for each protocol type: vaults (`totalAssets ≥ totalShares` scaled), lending (`totalDebt ≤ totalSupply`), AMMs (`x * y ≥ k`), CDPs (`debt ≤ ceiling`)
- Explain why invariant testing finds bugs that unit tests miss: it explores *sequences* of actions across multiple actors, revealing multi-step exploits

---

## 💡 Reading Audit Reports

### 💡 Concept: Why This Skill Matters

Audit reports are the densest source of real-world vulnerability knowledge. A single report can contain 10-20 findings, each one a potential exploit pattern you might encounter in your own code. Learning to read them efficiently — understanding severity classifications, root cause analysis, and recommended fixes — is one of the highest-ROI activities for a protocol builder.

<a id="how-read-audit"></a>
#### 📖 How to Read an Audit Report

**Structure of a typical report:**
- **Executive summary** — Protocol description, scope, methodology
- **Findings** — Sorted by severity: Critical, High, Medium, Low, Informational
- **Each finding includes:** Description, impact, root cause, proof of concept, recommendation, protocol team response

**What to focus on:**
- Critical and High findings — these are the exploitable bugs
- The root cause analysis — not just "what" but "why" it happened
- The fix recommendation — how would you have solved it?
- Informational findings — these reveal common anti-patterns and code smell

#### 📖 How to Study Audit Reports Effectively

1. **Read the executive summary and scope first** — Understand what the protocol does and which contracts were audited. If the audit covers only core contracts but not periphery/integrations, that's a significant limitation. Note the Solidity version, framework, and any unusual architecture choices the auditors call out.

2. **Read Critical and High findings deeply** — For each one: read the description, then STOP. Before reading the impact/PoC, ask yourself: "How would I exploit this?" Try to construct the attack mentally. Then read the auditor's impact assessment and PoC. Compare your thinking to theirs — this builds attacker intuition.

3. **Classify each finding into your mental taxonomy** — Is it reentrancy? Oracle manipulation? Access control? Logic error? Rounding? Map each finding to the attack patterns from the DeFi-Specific Attack Patterns section. Over time, you'll see the same categories appear across every audit. This is the pattern recognition that makes you faster at finding bugs.

4. **Read the fix, then evaluate it** — Does the fix address the root cause or just the symptom? Would you have fixed it differently? Sometimes the auditor's recommendation is a patch, but a better fix involves rearchitecting. Forming your own opinion on fixes is where you develop design judgment.

5. **Track informational findings** — These aren't exploitable, but they reveal what auditors consider code smell: missing events, inconsistent naming, unused variables, gas inefficiencies. If you see the same informational finding across multiple audits (you will), it's a pattern to avoid in your own code.

**Don't get stuck on:** Reading every finding in a 50+ finding report. Focus on Critical/High first, skim Medium, read Informational titles only. A single Critical finding teaches more than ten Informational ones.

<a id="report-aave"></a>
#### 📖 Report 1: Aave V3 Core (OpenZeppelin, SigmaPrime)

**Source code:** [aave-v3-core](https://github.com/aave/aave-v3-core)
**Audits:** [OpenZeppelin](https://blog.openzeppelin.com/aave-v3-core-audit) | [SigmaPrime](https://github.com/aave/aave-v3-core/blob/master/audits/27-01-2022_SigmaPrime_AaveV3.pdf) — both publicly available.

**What to look for:**
- How auditors analyze the interest rate model for edge cases
- Findings related to oracle integration and staleness
- Access control findings on protocol governance
- Any findings related to the aToken/debtToken accounting system

**Exercise:** Read the findings list. For each High/Medium finding, determine:
1. Which vulnerability class does it belong to? (from the DeFi-Specific Attack Patterns taxonomy)
2. Would your SimpleLendingPool from Module 4 be vulnerable to the same issue?
3. If yes, how would you fix it?

<a id="report-smaller"></a>
#### 📖 Report 2: A Smaller Protocol With Critical Findings

**Recommended options** (publicly available):
- Any [Cyfrin audit with critical findings](https://www.cyfrin.io/blog) (search their blog for audit reports)
- [Trail of Bits public audits on GitHub](https://github.com/trailofbits/publications/tree/master/reviews)
- [Spearbit reports](https://cantina.xyz/) — many DeFi protocol audits available

Pick one report for a protocol similar to what you've built (lending, AMM, or vault). Read the critical findings.

**Exercise:** For the most critical finding:
1. Reproduce the proof of concept in Foundry (even if simplified)
2. Implement the fix
3. Write a test that passes before the fix and fails after (regression test)

<a id="report-immunefi"></a>
#### 📖 Report 3: Immunefi Bug Bounty Writeup

**Source:** [Immunefi Medium](https://medium.com/immunefi) (search for "bug bounty writeup") or [Immunefi Explore](https://immunefi.com/explore/)

Bug bounty writeups show attacker thinking — the process of discovering a vulnerability, not just the final finding. This is the perspective you need to develop.

**Exercise:** Read 2-3 writeups. For each:
1. What was the initial observation that led to the discovery?
2. How did the researcher escalate from "suspicious" to "exploitable"?
3. What defense would have prevented it?

<a id="self-audit"></a>
## 🎯 Build Exercise: Self-Audit

Take your SimpleLendingPool from Module 4 and apply a structured review:

1. **Threat model:** List all actors (supplier, borrower, liquidator, oracle, admin). For each, list what they should and shouldn't be able to do.

2. **Trust assumptions:** List every external dependency (oracle, token contracts, flash loan providers). For each, describe the failure scenario.

3. **Code review checklist:**
   - [ ] All external/public functions have appropriate access control
   - [ ] CEI pattern followed everywhere (or `nonReentrant` applied)
   - [ ] All oracle integrations include staleness checks, zero-price checks
   - [ ] No reliance on `balanceOf` for critical accounting
   - [ ] Slippage protection on all swaps
   - [ ] Return values of external calls are checked

## 📋 Key Takeaways: Reading Audit Reports

After this section, you should be able to:

- Read an audit report efficiently: structure, severity levels, what to focus on, and how to classify findings into your mental taxonomy of attack patterns
- Apply the "pause and exploit" technique: after reading a vulnerability description, construct the attack yourself before reading the PoC — this builds attacker intuition
- Conduct a self-audit using the structured methodology: threat model, trust assumption mapping, and systematic checklist

---

## 💡 Security Tooling & Audit Preparation

<a id="static-analysis"></a>
### Static Analysis Tools

**[Slither](https://github.com/crytic/slither)** — Trail of Bits' static analyzer. Detects reentrancy, uninitialized variables, incorrect visibility, unchecked return values, and many more patterns. Run in CI/CD on every commit.

```bash
pip install slither-analyzer
slither . --json slither-report.json
```

**[Aderyn](https://github.com/Cyfrin/aderyn)** — Cyfrin's Rust-based analyzer. Faster than Slither for large codebases, catches Solidity-specific patterns. Good complement to Slither (different detectors).

```bash
cargo install aderyn
aderyn .
```

Both tools produce false positives. The skill is triaging results: understanding which findings are real vulnerabilities vs. informational or stylistic.

💻 **Quick Try:**

Save this vulnerable contract as `Vulnerable.sol` and run Slither on it:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VulnerableVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient");
        // Bug: external call before state update (CEI violation)
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] -= amount;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
```

```bash
pip install slither-analyzer   # if not installed
slither Vulnerable.sol
```

Slither should flag the reentrancy in `withdraw()` — the external call before the state update. See how it identifies the exact vulnerability pattern? Now fix the contract (move `balances[msg.sender] -= amount` before the call) and re-run Slither to confirm the finding disappears. That's the feedback loop: write code → analyze → fix → verify.

<a id="formal-verification"></a>
#### 🔍 Formal Verification (Awareness)

**[Certora Prover](https://docs.certora.com)** — Used by Aave, Compound, and other major protocols. You write properties in CVL (Certora Verification Language), and the prover mathematically verifies they hold for all possible inputs and states — not just random samples like fuzzing, but *all* of them.

```
// Certora rule example
rule depositIncreasesBalance {
    env e;
    uint256 amount;
    uint256 balanceBefore = balanceOf(e.msg.sender);
    deposit(e, amount);
    uint256 balanceAfter = balanceOf(e.msg.sender);
    assert balanceAfter >= balanceBefore;
}
```

Formal verification is expensive ($200,000+ for complex protocols) but provides the highest confidence level. For production DeFi protocols managing significant TVL, it's increasingly expected. You don't need to master CVL now, but understand that it exists and what it provides.

<a id="security-checklist"></a>
### ✅ The Security Checklist

Before any deployment:

**Code-level:**
- [ ] All external/public functions have appropriate access control
- [ ] CEI pattern followed everywhere (or `nonReentrant` applied)
- [ ] No external calls to user-supplied addresses without validation
- [ ] All arithmetic uses checked math (Solidity ≥0.8.0) or explicit SafeMath
- [ ] Return values of external calls are checked
- [ ] No reliance on `balanceOf` for critical accounting (use internal tracking)
- [ ] All oracle integrations include staleness checks, zero-price checks, and L2 sequencer checks
- [ ] No spot price usage for valuations
- [ ] Slippage protection on all swaps
- [ ] ERC-4626 vaults: virtual shares or dead shares for inflation attack prevention
- [ ] Upgradeable contracts: initializer modifier, storage gap, correct proxy pattern

**Testing:**
- [ ] Unit tests covering all functions and edge cases
- [ ] Fuzz tests for all functions with numeric inputs
- [ ] Invariant tests encoding protocol-wide properties
- [ ] Fork tests against mainnet state
- [ ] Negative tests (things that should fail DO fail)

**Operational:**
- [ ] Timelock on all admin functions
- [ ] Emergency pause function
- [ ] Circuit breakers for anomalous conditions (large withdrawals, price deviations)
- [ ] Monitoring/alerting for key state changes
- [ ] Incident response plan documented
- [ ] Bug bounty program (Immunefi or similar)

<a id="audit-preparation"></a>
#### 📋 Audit Preparation

Auditors are a final validation, not a substitute for your own security work. Protocols that arrive at audit with comprehensive tests and clear documentation get significantly more value from the audit.

**What to prepare:**
- Complete documentation of protocol design and intended behavior
- Threat model: who are the actors? What can each actor do? What should each actor NOT be able to do?
- Test suite with coverage report
- Known issues list (things you've identified but haven't fixed, or accepted risks)
- Deployment plan (chain, proxy pattern, initialization sequence)

**After audit:**
- Fix all critical and high findings before deployment
- Re-audit significant code changes (even "minor" fixes can introduce new vulnerabilities)
- Don't deploy code that differs from what was audited

<a id="security-first"></a>
### 💡 Concept: Building Security-First

The security mindset isn't a checklist — it's a way of thinking about code:

**Assume hostile inputs.** Every parameter is crafted to exploit your contract. Every external call returns something unexpected. Every caller has unlimited capital via flash loans.

**Design for failure.** What happens when the oracle goes stale? When a strategy loses money? When gas prices spike 100x? When a collateral token is blacklisted? Your protocol should degrade gracefully, not catastrophically.

**Minimize trust.** Every trust assumption is an attack surface. Trust in oracles → oracle manipulation. Trust in admin keys → compromised keys. Trust in external contracts → composability attacks. Document every trust assumption and ask: what happens if this assumption fails?

**Simplify.** The most secure protocol is the simplest one that achieves the goal. Every line of code is a potential vulnerability. MakerDAO's Vat is ~300 lines. Uniswap V2 core is ~400 lines. Compound V3's Comet is ~4,300 lines. Complexity is the enemy of security.

#### 💼 Job Market Context

**What DeFi teams expect you to know about security tooling and process:**

1. **"What does your security workflow look like before deployment?"**
   - Good answer: Unit tests, fuzz tests, Slither, get an audit
   - Great answer: Describes a layered approach — unit tests → fuzz tests → invariant tests (with handlers and ghost variables) → static analysis (Slither + Aderyn, triage false positives) → self-audit with threat model → comprehensive documentation → external audit → fix cycle → re-audit changes → bug bounty program. Mentions that the test suite and documentation quality directly affect audit ROI

2. **"Invariant testing vs fuzz testing — what's the difference and when do you use each?"**
   - Good answer: Fuzz tests random inputs to one function; invariant tests random sequences of calls and check properties hold
   - Great answer: Fuzz tests verify per-function behavior (`testFuzz_depositReturnsCorrectShares`). Invariant tests verify protocol-wide properties across arbitrary call sequences — they find multi-step bugs like "deposit → accrue → withdraw → accrue → deposit creates phantom assets." The handler contract is key: it bounds inputs, manages actors, and tracks ghost state. For DeFi, invariant tests are essential because most real exploits involve multi-step interactions, not single-function edge cases

3. **"Have you ever found a real bug with invariant testing?"**
   - This is a strong signal question. Having a concrete story (even from practice protocols) demonstrates real experience. If you haven't yet: run invariant tests on your Module 4 and Module 6 exercises with high depth — you'll likely find rounding edge cases or state inconsistencies worth discussing

**Hot topics (2025-26):**
- AI-assisted auditing (LLM-powered code review as a complement to manual audit)
- Formal verification becoming more accessible (Certora, Halmos)
- Security-as-a-service platforms (continuous monitoring, not just one-time audits)
- MEV-aware protocol design as a first-class security concern
- Cross-chain bridge security (still the largest single-exploit category by dollar value)

**Security career paths beyond protocol developer:**

- **Protocol Security Engineer** — Build protocols with security as a core responsibility. Threat modeling, invariant test suites, security-aware architecture. Premium over general Solidity devs (~$180-300k+ for senior roles). Signal: invariant tests in your portfolio, security-first design decisions, audit participation.
- **Smart Contract Auditor** — Review other teams' code. Entry via audit competitions ([Code4rena](https://code4rena.com/), [Sherlock](https://www.sherlock.xyz/), [CodeHawks](https://codehawks.cyfrin.io/)) → audit firm → independent. Compensation: $200-500k+ annually for competitive auditors. Signal: competition track record, published findings.
- **Security Researcher / Bug Hunter** — Find vulnerabilities in deployed protocols for bounties ($10k-$10M+ for critical findings). Signal: [Immunefi](https://immunefi.com/) profile, published writeups, responsible disclosure track record.
- **Security Tooling Developer** — Build static analyzers, formal verification tools, monitoring systems. Companies: Trail of Bits (Slither), Certora (Prover), Cyfrin (Aderyn), Forta, OpenZeppelin. Signal: open-source contributions, research publications.

Every path requires the fundamentals covered in this module — attack pattern taxonomy, invariant testing, audit report reading, and tooling familiarity.

## 🎯 Build Exercise: Security Review

**Exercise 1: Full security review.** Run Slither and Aderyn on your SimpleLendingPool from Module 4 and your SimpleCDP from Module 6. Triage every finding: real vulnerability, informational, or false positive. Fix any real vulnerabilities found.

**Exercise 2: Threat model.** Write a threat model for your SimpleCDP from Module 6:
- Identify all actors (vault owner, liquidator, PSM arbitrageur, governance)
- For each actor, list what they should be able to do
- For each actor, list what they should NOT be able to do
- Identify the trust assumptions (oracle, governance, collateral token behavior)
- For each trust assumption, describe the failure scenario

**Exercise 3: Invariant test your CDP.** Apply the Invariant Testing methodology to your SimpleCDP:
- Handler with: openVault, addCollateral, generateStablecoin, repay, withdrawCollateral, liquidate, updateOraclePrice
- Invariants: every vault safe or liquidatable, total stablecoin ≤ total vault debt × rate, debt ceiling not exceeded
- Run with high depth and runs

## 📋 Key Takeaways: Security Tooling & Audit Preparation

After this section, you should be able to:

- Run Slither and Aderyn on a project, interpret their output, and triage false positives from real issues
- Explain when formal verification (Certora Prover, CVL rules) is worth the cost and write a simple CVL rule for a critical invariant
- Walk through the deployment security checklist: code-level requirements (CEI, access control, oracle safety), testing requirements (unit + fuzz + invariant + fork), operational requirements (monitoring, incident response, bug bounty)
- Prepare a codebase for audit: what to provide auditors (documentation, threat model, known issues, test suite) and what to do with the report afterward

---

## 📚 Resources

**Vulnerability references:**
- [OWASP Smart Contract Top 10 (2025)](https://owasp.org/www-project-smart-contract-top-10/)
- [Three Sigma — 2024 most exploited DeFi vulnerabilities](https://threesigma.xyz/blog/exploit/2024-defi-exploits-top-vulnerabilities)
- [SWC Registry (Smart Contract Weakness Classification)](https://swcregistry.io/)
- [Cyfrin — Reentrancy attack guide](https://www.cyfrin.io/blog/what-is-a-reentrancy-attack-solidity-smart-contracts)

**Audit reports:**
- [Trail of Bits public audits](https://github.com/trailofbits/publications/tree/master/reviews)
- [OpenZeppelin audits](https://blog.openzeppelin.com/security-audits)
- [Cyfrin audit reports](https://www.cyfrin.io/blog)
- [Spearbit](https://spearbit.com)
- [Immunefi bug bounty writeups](https://medium.com/immunefi)

**Testing:**
- [Foundry invariant testing docs](https://getfoundry.sh/forge/invariant-testing)
- [RareSkills — Invariant testing tutorial](https://rareskills.io/post/invariant-testing-solidity)
- [Cyfrin — Fuzz testing and invariants guide](https://www.cyfrin.io/blog/smart-contract-fuzzing-and-invariants-testing-foundry)

**Static analysis:**
- [Slither](https://github.com/crytic/slither)
- [Aderyn](https://github.com/Cyfrin/aderyn)

**Formal verification:**
- [Certora documentation](https://docs.certora.com)
- [Certora tutorials](https://github.com/Certora/tutorials)

**Practice:**
- [Damn Vulnerable DeFi (v4)](https://www.damnvulnerabledefi.xyz)
- [Ethernaut](https://ethernaut.openzeppelin.com)
- [Cyfrin Updraft security course (free)](https://updraft.cyfrin.io)

---

**Navigation:** [← Module 7: Vaults & Yield](7-vaults-yield.md) | [Module 9: Integration Capstone →](9-integration-capstone.md)

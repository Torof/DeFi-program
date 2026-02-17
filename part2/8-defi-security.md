# Part 2 — Module 8: DeFi Security

**Duration:** ~4 days (3–4 hours/day)
**Prerequisites:** All previous Part 2 modules
**Pattern:** DeFi-specific attack deep-dive → Exploit reproduction → Invariant testing → Audit report reading → Tooling
**Builds on:** Module 3 (oracle manipulation), Module 4 (lending/liquidation), Module 5 (flash loan amplification), Module 7 (vault inflation)
**Used by:** Module 9 (integration capstone stress testing)

---

## Why This Module Matters

DeFi protocols lost over $3.1 billion in the first half of 2025 alone. Roughly 70% of major exploits in 2024 hit contracts that had been professionally audited. The OWASP Smart Contract Top 10 (2025 edition) ranks access control as the #1 vulnerability for the second year running, followed by reentrancy, logic errors, and oracle manipulation — all patterns you've encountered throughout Part 2.

This module focuses on the DeFi-specific attack patterns and defense methodologies that go beyond general Solidity security. You already know CEI, reentrancy guards, and access control. Here we cover: read-only reentrancy in multi-protocol contexts, the full oracle/flash-loan manipulation taxonomy, invariant testing as the primary DeFi bug-finding tool, how to read audit reports, and security tooling for protocol builders.

---

## Quick Reference: Fundamentals You Already Know

These patterns should be second nature. This box is a refresher, not a learning section.

**Checks-Effects-Interactions (CEI):** Validate → update state → make external calls. The base defense against reentrancy.

**Reentrancy guards:** `nonReentrant` modifier (OpenZeppelin or transient storage variant from Part 1). Apply to all state-changing external functions. For cross-contract reentrancy, consider a shared lock.

**Access control:** OpenZeppelin `AccessControl` (role-based) or `Ownable2Step` (two-step transfer). Timelock all admin operations. Use `initializer` modifier on upgradeable contracts. Multisig threshold should scale with TVL.

**Input validation:** Validate every parameter of every external/public function. Never pass user-supplied addresses to `call()` or `delegatecall()` without validation. Check for zero addresses, zero amounts.

If any of these feel unfamiliar, review Part 1 and the OpenZeppelin documentation before proceeding.

---

## Day 1: DeFi-Specific Attack Patterns

### Read-Only Reentrancy

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

**Real-world impact:** Multiple protocols have been hit by read-only reentrancy through Balancer and Curve pool interactions. The Sentiment protocol lost ~$1M in April 2023 to exactly this pattern.

**Defense:**
- Never trust external `view` functions during your own state transitions
- Check reentrancy locks on external protocols before reading their rates (Balancer V2 pools have a `getPoolTokens` that reverts if the vault is in a reentrancy state — use it)
- Use time-delayed or externally-sourced rates instead of live pool calculations

### Cross-Contract Reentrancy in DeFi Compositions

When your protocol interacts with multiple external protocols, reentrancy can occur across trust boundaries:

```
Your Protocol → Aave (supply) → aToken callback → Your Protocol (read stale state)
Your Protocol → Uniswap (swap) → token transfer → receiver fallback → Your Protocol
```

**Defense:** Apply `nonReentrant` globally (not per-function) when your protocol makes external calls that could trigger callbacks. For protocols that interact with many external contracts, a single transient storage lock covering all entry points is the cleanest approach.

### Price Manipulation Taxonomy

This consolidates oracle attacks from Module 3 with flash loan amplification from Module 5:

**Category 1: Spot price manipulation via flash loan**
- Borrow → swap on DEX → manipulate price → exploit protocol reading spot price → swap back → repay
- Cost: gas only (flash loan is free if profitable)
- Defense: never use DEX spot prices, use Chainlink or TWAP
- Real example: Polter Finance (2024) — flash-loaned BOO tokens, drained SpookySwap pools, deposited minimal BOO valued at $1.37 trillion

**Category 2: TWAP manipulation**
- Sustain price manipulation across the TWAP window
- Cost: capital × time (expensive for deep-liquidity pools with long windows)
- Defense: minimum 30-minute window, use deep-liquidity pools, multi-oracle

**Category 3: Donation/balance manipulation**
- Transfer tokens directly to a contract to inflate `balanceOf`-based calculations
- Affects: vault share prices (Module 7 inflation attack), reward calculations, any logic using `balanceOf`
- Defense: internal accounting, virtual shares/assets

**Category 4: ERC-4626 exchange rate manipulation**
- Inflate vault token exchange rate, use overvalued vault tokens as collateral
- Venus Protocol lost 86 WETH in February 2025 to exactly this attack
- Resupply protocol exploited via the same vector in 2025
- Defense: time-weighted exchange rates, external oracles for vault tokens, rate caps, virtual shares

**Category 5: Governance manipulation via flash loan**
- Flash-borrow governance tokens, vote on malicious proposal, return tokens
- Defense: snapshot-based voting (power based on past block), timelocks, quorum requirements
- Most modern governance (OpenZeppelin Governor, Compound Governor Bravo) already uses snapshot voting

### Frontrunning and MEV

**Sandwich attacks:** Attacker sees your pending swap in the mempool. They front-run (buy before you, pushing price up), your swap executes at the worse price, they back-run (sell after you, profiting from the difference).

Defense: slippage protection (`amountOutMin` in Uniswap swaps), private transaction submission (Flashbots Protect, MEV Blocker), deadline parameters.

**Just-In-Time (JIT) liquidity:** Specific to concentrated liquidity AMMs. An attacker adds concentrated liquidity right before a large swap (capturing fees) and removes it right after. Not a vulnerability per se, but reduces fees going to passive LPs.

**Liquidation MEV:** When a position becomes liquidatable, MEV searchers race to execute the liquidation (and capture the bonus). For protocol builders: ensure your liquidation mechanism is MEV-aware and that the bonus isn't so large it incentivizes price manipulation to trigger liquidations.

### Composability Risk

DeFi's composability means your protocol interacts with others in ways you can't fully predict:
- Your vault accepts aTokens as collateral → aTokens interact with Aave → Aave interacts with Chainlink → Chainlink relies on external data providers
- A flash loan from Balancer funds an operation on your protocol that calls a Curve pool that triggers a reentrancy via a Vyper callback

**Defense:**
- Document every external dependency and its assumptions
- Consider what happens if any dependency fails, returns unexpected values, or is malicious
- Use interface types (not concrete contracts) and validate return values
- Implement circuit breakers that pause the protocol if unexpected conditions are detected

### Exercise

**Exercise 1: Read-only reentrancy exploit.** Build a mock vault whose `getSharePrice()` returns an inflated value during a `deposit()` that makes an external callback. Build a lending protocol that reads this value. Show how an attacker can deposit during the callback to get overvalued collateral. Fix it by checking the vault's reentrancy state.

**Exercise 2: Complete flash loan attack.** Build a vulnerable lending protocol that reads Uniswap V2 spot prices. Execute a full flash loan attack:
1. Flash-borrow from Balancer (0 fee)
2. Swap on Uniswap to manipulate the price
3. Deposit collateral into the lending protocol (now overvalued)
4. Borrow against the inflated collateral
5. Swap back to restore the price
6. Repay the flash loan, keep the profit

Then fix the lending protocol to use Chainlink and verify the attack fails.

**Exercise 3: Sandwich attack simulation.** On a Uniswap V2 fork:
- Set up a pool with known liquidity
- Execute a large swap without slippage protection
- Show how a sandwich captures value
- Add slippage protection and show the sandwich becomes unprofitable

### Practice Challenges

- **Damn Vulnerable DeFi #1 "Unstoppable"** — Flash loan griefing via donation
- **Damn Vulnerable DeFi #7 "Compromised"** — Oracle manipulation
- **Damn Vulnerable DeFi #10 "Free Rider"** — Flash swap exploitation
- **Ethernaut #21 "Shop"** — Read-only reentrancy concept

---

## Day 2: Invariant Testing with Foundry

### Why Invariant Testing Is the Most Powerful DeFi Testing Tool

Unit tests verify specific scenarios you think of. Fuzz tests verify single functions with random inputs. Invariant tests verify that properties hold across random *sequences* of function calls — finding edge cases no human would think to test.

For DeFi protocols, invariants encode the fundamental properties your protocol must maintain:

- "Total supply of shares equals sum of all balances" (ERC-20)
- "Sum of all deposits minus withdrawals equals total assets" (Vault)
- "No user can withdraw more than they deposited plus their share of yield" (Vault)
- "A position with health factor > 1 cannot be liquidated" (Lending)
- "Total borrowed ≤ total supplied" (Lending)
- "Every vault has collateral ratio ≥ minimum OR is being liquidated" (CDP)

### Foundry Invariant Testing Setup

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

### Handler Contracts: The Key to Effective Invariant Testing

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

### Configuration

```toml
# foundry.toml
[invariant]
runs = 256          # Number of test sequences
depth = 50          # Number of calls per sequence
fail_on_revert = false  # Don't fail on expected reverts
```

Higher depth = longer call sequences = more likely to find complex multi-step bugs. For production, use `runs = 1000+` and `depth = 100+`.

### What Invariants to Test for Each DeFi Primitive

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

### Exercise

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

### Practice Challenges

- **Damn Vulnerable DeFi #4 "Side Entrance"** — The invariant "totalAssets == sum of deposits - withdrawals" is violated by a flash loan that counts as both
- **Damn Vulnerable DeFi #3 "Truster"** — Approval via flash loan callback — write an invariant that catches the unexpected allowance
- **Ethernaut #20 "Denial"** — Gas griefing that breaks withdrawal invariants

---

## Day 3: Reading Audit Reports

### Why This Skill Matters

Audit reports are the densest source of real-world vulnerability knowledge. A single report can contain 10-20 findings, each one a potential exploit pattern you might encounter in your own code. Learning to read them efficiently — understanding severity classifications, root cause analysis, and recommended fixes — is one of the highest-ROI activities for a protocol builder.

### How to Read an Audit Report

**Structure of a typical report:**
- **Executive summary** — Protocol description, scope, methodology
- **Findings** — Sorted by severity: Critical, High, Medium, Low, Informational
- **Each finding includes:** Description, impact, root cause, proof of concept, recommendation, protocol team response

**What to focus on:**
- Critical and High findings — these are the exploitable bugs
- The root cause analysis — not just "what" but "why" it happened
- The fix recommendation — how would you have solved it?
- Informational findings — these reveal common anti-patterns and code smell

### Report 1: Aave V3 Core (OpenZeppelin, Trail of Bits)

**Source:** Search for "Aave V3 audit report OpenZeppelin" or "Aave V3 audit Trail of Bits" — both are publicly available.

**What to look for:**
- How auditors analyze the interest rate model for edge cases
- Findings related to oracle integration and staleness
- Access control findings on protocol governance
- Any findings related to the aToken/debtToken accounting system

**Exercise:** Read the findings list. For each High/Medium finding, determine:
1. Which vulnerability class does it belong to? (from the taxonomy in Day 1)
2. Would your SimpleLendingPool from Module 4 be vulnerable to the same issue?
3. If yes, how would you fix it?

### Report 2: A Smaller Protocol With Critical Findings

**Recommended options** (publicly available):
- Any Cyfrin audit with critical findings (search "Cyfrin audit reports" on their blog)
- Trail of Bits public audits on GitHub: https://github.com/trailofbits/publications/tree/master/reviews
- Spearbit reports: search for DeFi protocol audits

Pick one report for a protocol similar to what you've built (lending, AMM, or vault). Read the critical findings.

**Exercise:** For the most critical finding:
1. Reproduce the proof of concept in Foundry (even if simplified)
2. Implement the fix
3. Write a test that passes before the fix and fails after (regression test)

### Report 3: Immunefi Bug Bounty Writeup

**Source:** https://medium.com/immunefi (search for "bug bounty writeup") or https://immunefi.com/explore/

Bug bounty writeups show attacker thinking — the process of discovering a vulnerability, not just the final finding. This is the perspective you need to develop.

**Exercise:** Read 2-3 writeups. For each:
1. What was the initial observation that led to the discovery?
2. How did the researcher escalate from "suspicious" to "exploitable"?
3. What defense would have prevented it?

### Exercise: Self-Audit

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

---

## Day 4: Security Tooling & Audit Preparation

### Static Analysis Tools

**Slither** — Trail of Bits' static analyzer. Detects reentrancy, uninitialized variables, incorrect visibility, unchecked return values, and many more patterns. Run in CI/CD on every commit.

```bash
pip install slither-analyzer
slither . --json slither-report.json
```

**Aderyn** — Cyfrin's Rust-based analyzer. Faster than Slither for large codebases, catches Solidity-specific patterns. Good complement to Slither (different detectors).

```bash
cargo install aderyn
aderyn .
```

Both tools produce false positives. The skill is triaging results: understanding which findings are real vulnerabilities vs. informational or stylistic.

### Formal Verification (Awareness)

**Certora Prover** — Used by Aave, Compound, and other major protocols. You write properties in CVL (Certora Verification Language), and the prover mathematically verifies they hold for all possible inputs and states — not just random samples like fuzzing, but *all* of them.

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

### The Security Checklist

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

### Audit Preparation

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

### Building Security-First

The security mindset isn't a checklist — it's a way of thinking about code:

**Assume hostile inputs.** Every parameter is crafted to exploit your contract. Every external call returns something unexpected. Every caller has unlimited capital via flash loans.

**Design for failure.** What happens when the oracle goes stale? When a strategy loses money? When gas prices spike 100x? When a collateral token is blacklisted? Your protocol should degrade gracefully, not catastrophically.

**Minimize trust.** Every trust assumption is an attack surface. Trust in oracles → oracle manipulation. Trust in admin keys → compromised keys. Trust in external contracts → composability attacks. Document every trust assumption and ask: what happens if this assumption fails?

**Simplify.** The most secure protocol is the simplest one that achieves the goal. Every line of code is a potential vulnerability. MakerDAO's Vat is ~300 lines. Uniswap V2 core is ~400 lines. Compound V3's Comet is ~4,300 lines. Complexity is the enemy of security.

### Exercise

**Exercise 1: Full security review.** Run Slither and Aderyn on your SimpleLendingPool from Module 4 and your SimpleCDP from Module 6. Triage every finding: real vulnerability, informational, or false positive. Fix any real vulnerabilities found.

**Exercise 2: Threat model.** Write a threat model for your SimpleCDP from Module 6:
- Identify all actors (vault owner, liquidator, PSM arbitrageur, governance)
- For each actor, list what they should be able to do
- For each actor, list what they should NOT be able to do
- Identify the trust assumptions (oracle, governance, collateral token behavior)
- For each trust assumption, describe the failure scenario

**Exercise 3: Invariant test your CDP.** Apply the Day 2 invariant testing methodology to your SimpleCDP:
- Handler with: openVault, addCollateral, generateStablecoin, repay, withdrawCollateral, liquidate, updateOraclePrice
- Invariants: every vault safe or liquidatable, total stablecoin ≤ total vault debt × rate, debt ceiling not exceeded
- Run with high depth and runs

### Practice Challenges

Complete any remaining Damn Vulnerable DeFi and Ethernaut challenges not yet attempted:

**Damn Vulnerable DeFi (v4):**
- #2 "Naive Receiver" — Flash loan receiver exploitation
- #5 "The Rewarder" — Reward distribution timing attack
- #15 "ABI Smuggling" — Calldata manipulation

**Ethernaut:**
- #10 "Re-entrancy" — Classic reentrancy (quick verification)
- #16 "Preservation" — Delegatecall storage collision
- #24 "Puzzle Wallet" — Proxy + delegatecall exploit

---

## Key Takeaways

1. **DeFi-specific attacks go beyond basic Solidity security.** Read-only reentrancy, flash-loan-amplified price manipulation, and ERC-4626 exchange rate attacks are patterns that don't appear in generic smart contract security guides. You need to know them specifically.

2. **Invariant testing is the most powerful DeFi testing methodology.** Unit tests and fuzz tests are necessary but not sufficient. Invariant tests with handlers, ghost variables, and realistic actor management find bugs that no other methodology catches. Invest the time to write comprehensive invariant suites for every protocol you build.

3. **Reading audit reports is high-ROI learning.** Each report condenses weeks of expert review into findings you can learn from in hours. Make it a habit to read 1-2 reports per month, even after finishing this curriculum.

4. **Security is a spectrum, not a binary.** No protocol is "secure" — it's a matter of how high you set the bar. The minimum: CEI, access control, oracle safety, comprehensive tests including invariants, static analysis, audit. The ideal: add formal verification, bug bounty, continuous monitoring, and incident response planning.

5. **Simplify.** The best defense is a smaller attack surface. Every abstraction, every external call, every storage variable is a potential vulnerability. Build the simplest protocol that achieves the goal.

---

## Resources

**Vulnerability references:**
- OWASP Smart Contract Top 10 (2025): https://owasp.org/www-project-smart-contract-top-10/
- Three Sigma 2024 exploit analysis: https://threesigma.xyz/blog/exploit/2024-defi-exploits-top-vulnerabilities
- SWC Registry (Smart Contract Weakness Classification): https://swcregistry.io/
- Cyfrin reentrancy guide: https://www.cyfrin.io/blog/what-is-a-reentrancy-attack-solidity-smart-contracts

**Audit reports:**
- Trail of Bits public audits: https://github.com/trailofbits/publications/tree/master/reviews
- OpenZeppelin audits: https://blog.openzeppelin.com/security-audits
- Cyfrin audit reports: https://www.cyfrin.io/blog
- Spearbit: https://spearbit.com
- Immunefi bug bounty writeups: https://medium.com/immunefi

**Testing:**
- Foundry invariant testing docs: https://getfoundry.sh/forge/invariant-testing
- RareSkills invariant testing tutorial: https://rareskills.io/post/invariant-testing-solidity
- Cyfrin fuzz testing guide: https://www.cyfrin.io/blog/smart-contract-fuzzing-and-invariants-testing-foundry

**Static analysis:**
- Slither: https://github.com/crytic/slither
- Aderyn: https://github.com/Cyfrin/aderyn

**Formal verification:**
- Certora documentation: https://docs.certora.com
- Certora tutorials: https://github.com/Certora/tutorials

**Practice:**
- Damn Vulnerable DeFi (v4): https://www.damnvulnerabledefi.xyz
- Ethernaut: https://ethernaut.openzeppelin.com
- Cyfrin Updraft security course (free): https://updraft.cyfrin.io

---

*Next module: Module 9 — Integration Capstone. Wire your AMM, lending pool, oracle, flash loans, and vault together into a single system and stress-test it.*

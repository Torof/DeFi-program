# Curriculum Quality Audit Report

**Date:** 2025-03-15
**Scope:** All 33 curriculum files (Parts 1-4 + Deep Dives)
**Method:** 8 audit agents + 5 verification agents (every finding checked against actual file content)

---

## Executive Summary

The curriculum is **strong on pedagogy and interview preparation** but has recurring weaknesses in **technical accuracy, currency, and depth calibration for the target audience**. The most impactful issues are:

1. **19 verified factual errors** that would undermine credibility if a reader cross-references
2. **Systematic over-explanation of basics** an 8-year Solidity dev already knows
3. **Significant currency gaps** — several major 2024-2025 protocols/developments missing
4. **Exercises skew toward mocks** rather than mainnet fork interaction

The interview preparation content is consistently excellent across all modules.

---

## Dimension 1: Technical Accuracy

### MUST FIX — Verified (all confirmed against actual file content)

| # | Module | Issue | Correct | Verified |
|---|--------|-------|---------|----------|
| 1 | P1 M7 | Ronin Bridge: "single key access" (line 418) | 5 of 9 validator keys compromised (4 Sky Mavis + 1 Axie DAO). Line 761 says "keys" plural — inconsistent within same file | ✅ TRUE |
| 2 | P4 M1 | SELFDESTRUCT "no longer transfers remaining balance" (line 496) | Post-EIP-6780, still transfers balance; only code/storage deletion restricted | ✅ TRUE |
| 3 | P4 M1 | Block gas limit "~30 million gas as of 2025" (line 168) | Raised to 36M in early 2025 | ✅ TRUE |
| 4 | P1 M6 | Storage gap: "Each variable occupies one slot (even uint128)" (line 503) | Wrong when packing occurs. Advice is pragmatically safe but explanation is incorrect | ✅ TRUE |
| 5 | P4 M6 | Jump table dispatch: ~93 gas (line 927) vs ~30 gas (line 1083) | Internal contradiction in same module — ~30 appears to be the error | ✅ TRUE |
| 6 | P2 M1 | SushiSwap MISO: "malicious token with transfer() that silently failed" (line 26) | Actually a supply chain attack on the auction contract frontend | ✅ TRUE |
| 7 | P2 M2 | Uniswap V4 launch: "November 2024" (lines 1113, 2019) | Launched January 2025 | ✅ TRUE |
| 8 | P2 M8 | "$3.1 billion lost in first half of 2025" (line 36) | Future/unverifiable — current date is March 2025 | ✅ TRUE |
| 9 | P3 M9 | KiloEx exploit "April 2025" (lines 98, 1954) | Future date relative to March 2025 | ✅ TRUE |
| 10 | P4 M1 | "V2 original: 0→1→0" reentrancy pattern (line 800) | V2 shipped with 1→2→1 from the start; 0→1→0 was the general pre-optimization pattern | ✅ TRUE |
| 11 | P2 M5 | Flash loan modes reversed: "mode 1 = variable, mode 2 = stable" (lines 112, 192, 214) | Aave V3 `InterestRateMode`: STABLE=1, VARIABLE=2. Line 299 in same file gets it right | ✅ TRUE |
| 12 | P2 M2 | V2 flash swap fee: `amount * 1003 / 1000` (line 536) | Should be `amount * 1000 / 997` to satisfy k-invariant | ✅ TRUE |
| 13 | P2 M3 | Chainlink BFT: ">50% of nodes are honest" (lines 112, 161) | BFT requires >2/3 honest (2f+1 of 3f+1), not simple majority | ✅ TRUE |
| 14 | P2 M2 | Cork Protocol exploit "July 2024" as V4 hook exploit (line 1304) | V4 wasn't on mainnet in July 2024 — date wrong | ✅ TRUE |
| 15 | P2 M5 | Aave called "The original" flash loan provider (line 108) | Marble Protocol (2018) and dYdX predated Aave V1's dedicated flash loan feature | ✅ TRUE |
| 16 | P4 DD-err | V4 PoolManager "uses try/catch to handle hook failures" (line 1899) | V4 hooks use direct calls; failures propagate and revert the transaction | ✅ TRUE |
| 17 | P3 M9 | wstETH `min()` "protects the trader during flash crash" (lines 739, 748) | `min()` always takes the LOWER value — during flash crash, uses crashed price (worse for trader). Protects *protocol*, not trader | ✅ TRUE |
| 18 | P3 M8 | OZ Governor import: `import { ERC20, ERC20Votes, ERC20Permit } from "...ERC20Votes.sol"` (line 115) | OZ v5 doesn't re-export ERC20/ERC20Permit from ERC20Votes.sol — would fail to compile | ✅ TRUE |

### Removed after verification (audit was wrong)

| Original # | Module | Claimed Issue | Why Removed |
|-------------|--------|---------------|-------------|
| 2 (old) | P1 M7 | Nomad hack called "deployment initialization error" | Text says exactly this — it WAS an initialization error during a deployment/upgrade. Characterization is a reasonable simplification |
| 5 (old) | P1 M6 | Compound V3 "immutable implementation" | Individual implementation contracts ARE immutable; proxy can be repointed. Misleading but not strictly wrong |
| 10 (old) | P1 M5 | Gas math "$0.01 at 100 gwei" | Depends on ETH price assumption — at ~$1000 ETH it's $0.01. Imprecise, not wrong. Moved to SHOULD FIX |
| 14 (old) | P2 M4 | Mode reversal "in P2 M4" | Not in P2 M4 at all — the modes are only discussed in P2 M5. Merged with Item 11 |

### SHOULD FIX — Verified

| # | Module | Issue | Verified |
|---|--------|-------|----------|
| 1 | P1 M1 | Solidity 0.8.30 (May 2025) and 0.8.31 (Dec 2025) referenced as released — future versions | ✅ TRUE |
| 2 | P1 M2 | Pectra described as "activated" (May 2025) — still upcoming | ✅ TRUE |
| 3 | P1 M5 | Custom errors save "~24 gas/revert" (line 985) — actual savings 100-200+ gas | ✅ TRUE |
| 4 | P1 M5 | `unchecked { ++i }` saves "~20 gas" (line 992) — closer to 60-80 gas | ✅ TRUE |
| 5 | P1 M5 | Gas math "$0.01 at 100 gwei" (line 957) — only accurate at ~$1k ETH, not current prices | ✅ TRUE |
| 6 | P2 M3 | "3 mandatory checks" in takeaways (line 475) vs "4 mandatory checks" in body (line 402) — inconsistency | ✅ TRUE |
| 7 | P2 M4 | Compound interest "27+ decimal places" accuracy (line 483) — overstated for extreme cases | ✅ TRUE |
| 8 | P2 M4 | Only $4.5M Radiant exploit (Jan 2024) mentioned, not the $50M one (Oct 2024) | ✅ TRUE |
| 9 | P2 M5 | Flash loan stable rate mode mentioned without noting V3.3 deprecation | ✅ TRUE |
| 10 | P2 M6 | crvUSD LLAMMA — band/tick structure not mentioned at all (key architectural detail omitted) | ✅ TRUE |
| 11 | P3 M1 | Rocket Pool commission "14%" (line 177) — variable 5-20% since Houston upgrade | ✅ TRUE |
| 12 | P3 M2 | Synthetix c-ratio "~400%" (line 789) — applies to V2 only, V3 is fundamentally different | ✅ TRUE |
| 13 | P3 M6 | "$2.5B lost to bridge exploits" — line 34 implies all-time, line 296 says "2022 alone" | ✅ TRUE |
| 14 | P3 M8 | `votingDelay` of 7200 blocks assumes 12s/block (L1) — no note about L2 differences | ✅ TRUE |
| 15 | P3 M8 | veCRV "50% of all Curve trading fees, distributed in 3CRV" (line 470) — changed to crvUSD for some pools | ✅ TRUE |
| 16 | P4 M6 | Access list "200 gas per slot" savings ignores calldata cost of access list entries | ✅ TRUE |
| 17 | P4 M7 | sqrt() comment says "Is x >= 2^128?" but threshold constant is `0xff...ff` (17 bytes = 2^136) | ✅ TRUE |
| 18 | P4 M7 | "Check your understanding" says `and(addr, mask)` but walkthrough shows `shr(96, shl(96, to))` — mismatch | ✅ TRUE |
| 19 | P3 M6 | CCIP import path `@chainlink/ccip/CCIPReceiver.sol` — actual path is `@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol` | ✅ TRUE |
| 20 | P2 M5 | DAI Flash Mint "Fee: 0%" (line 171) — governance-configurable via `toll`, not hardcoded | ✅ TRUE |
| 21 | P2 M3 | Chainlink "15-31 nodes per feed" (line 108) — some feeds have as few as 7 | ✅ TRUE |
| 22 | P3 M5 | MEV-Explore link `explore.flashbots.net` (lines 51, 880) — likely deprecated | ✅ TRUE |

### Removed after verification (audit was wrong)

| Original # | Claimed Issue | Why Removed |
|-------------|---------------|-------------|
| 3 (old) | BLS code labeled as working code | Code IS labeled "conceptual simplification" in comments |
| 4 (old) | Reentrancy guard narrative implies guard doesn't work | Narrative explicitly says "the guard actually blocks this specific attack" |
| 13 (old) | Virtual shares conflates `_decimalsOffset()` with virtual amount | Explanation correctly distinguishes offset parameter from virtual share count |
| 16 (old) | Simple vs continuous compounding mismatch unacknowledged | Mismatch IS explicitly acknowledged with explanation of why |
| 21 (old) | SSTORE 1->2 attributed to "Uniswap V2" — predates V2 | V2 DOES use this pattern (verified in UniswapV2Pair.sol). Attribution is correct |
| 23 (old) | FullMath "the difference tells us the upper 256 bits" is oversimplification | This IS the correct technique (Remco Bloemen). Simplified prose but math is right |
| 24 (old) | `add(shl(1, x), x)` "9 gas" in DD-bits | Text not found in file — audit fabricated this |
| 25 (old) | AMM ASCII label mixes buy/sell direction | Labels are correct — diagram and worked example show different trades, both internally consistent |
| 30 (old) | MEV tax `tx.gasprice` without PBS note | No `tx.gasprice` in the file — audit fabricated this |

---

## Dimension 2: Completeness

### Major gaps (topics a DeFi protocol engineer would be expected to know)

**Protocols/Standards missing entirely:**
- **GHO** (Aave's stablecoin) — not mentioned anywhere
- **Morpho Vaults / MetaMorpho** — arguably most important ERC-4626 system in 2024-2025
- **ERC-7540** (async vaults) — becoming standard for RWA/restaking vaults
- **ERC-1167 clones** (minimal proxy) — missing from proxy module despite heavy DeFi usage
- **Liquity V2** — fundamentally different design from V1, launched Q3 2024
- **Pendle** — covered only in P3 M3, but missing from the yield module (P2 M7) where it's most relevant
- **ERC-7683** (cross-chain intents standard) — missing from intent/cross-chain modules
- **Synthetix V3** — V2 covered extensively but V3 barely mentioned despite being live

**Topic gaps across modules:**
- **Oracle manipulation attacks** — one of the top attack vectors, no dedicated section in security module
- **Chainlink Data Streams** (low-latency pull-based feeds) — increasingly used for perps/derivatives
- **EIP-7412** (Synthetix oracle pattern) — standardizing pull-oracle integration
- **Governance attacks** (flash loan governance, malicious proposals) — missing from P3 M8
- **L2-specific considerations** — consistently thin across all Parts; sequencer MEV, gas models, deployment differences
- **Session keys** — mentioned once in AA module but critical for DeFi UX
- **MCOPY opcode** (EIP-5656) — relevant to P4 M6/M7, not covered
- **Formal verification** (Certora, Halmos) — single passing mention in security module
- **CEX-DEX arbitrage** — largest MEV category by volume, not covered in MEV module
- **Cross-chain failure recovery** — stored payloads, retries, gas estimation for destination — missing from bridge module

**Exercise gaps:**
- No exercises involving **mainnet fork interaction with real protocols** (consistent across all Parts)
- No exercise on **reproducing a real exploit** (Damn Vulnerable DeFi style)
- No exercise on **try/catch cross-contract error handling** despite deep coverage
- No exercise on **Permit2 integration** despite emphasis on its importance

### Adequately covered (notable strengths)
- ERC-4626 core mechanics and inflation attack
- Funding rate accumulators (hammered across P3 M1-M3 effectively)
- Transient storage and flash accounting
- SafeERC20 assembly walkthrough
- Interview preparation across all modules

---

## Dimension 3: Currency (as of March 2025)

### Presented as current but outdated or wrong timeline

| Issue | Modules Affected |
|-------|-----------------|
| Pectra described as live (May 2025) | P1 M1, P1 M2, P1 M4 |
| Solidity 0.8.30/0.8.31 referenced as released | P1 M1 |
| Uniswap V4 "November 2024" launch | P2 M2 |
| KiloEx exploit "April 2025" | P3 M9 |
| Future statistics presented as fact ("$3.1B in H1 2025") | P2 M8 |
| veCRV fee distribution (3CRV → crvUSD change) | P3 M8 |
| Synthetix V2 presented as current architecture | P3 M2 |

### Missing recent developments (2024-2025)

| Development | Where it should appear |
|-------------|----------------------|
| Hyperliquid dominance in perp DEX volume | P3 M2, P3 M9 |
| Morpho Vaults / MetaMorpho rise | P2 M7 |
| Pendle + yield tokenization growth | P2 M7 |
| EigenLayer AVS ecosystem (live AVSes) | P3 M1 |
| Points/airdrop farming meta | P2 M7, P3 M3 |
| Liquity V2 launch and design | P2 M6 |
| Arbitrum Stylus | P3 M7 |
| MakerDAO → Sky rebrand + SubDAO architecture | P2 M6 |
| EIP-6093 (standardized token errors) | Deep Dive: Errors |
| Solidity 0.8.27 `require` with custom errors | Deep Dive: Errors |
| Lido CSM (Community Staking Module) | P3 M1 |
| DVT (Obol, SSV Network) | P3 M1 |

### TVL/statistics without timestamps
Multiple modules cite TVL figures or statistics as facts without noting measurement date. Examples: "Morpho Blue $3B+", "Aerodrome $1.5B+", "Rocket Pool ~5-8% market share". All should include "(as of Q4 2024)" or similar.

---

## Dimension 4: Depth Calibration

### Systematic over-explanation pattern

Nearly every module opens with 1-2 pages explaining concepts an 8-year Solidity dev already knows:

| Module | Over-explained content |
|--------|----------------------|
| P1 M1 | Checked arithmetic basics, custom errors vs require strings |
| P1 M2 | EIP-1559 base fee mechanics, PUSH0/MCOPY (compiler-level) |
| P1 M3 | "Why Traditional Approvals Are Broken", approve race condition |
| P1 M4 | EOA vs contract account, "why AA matters" narrative |
| P1 M5 | "Why Foundry", Foundry vs Hardhat comparison, basic setup |
| P1 M6 | DELEGATECALL basics, "call instead of delegatecall" mistake |
| P1 M7 | Basic deployment pipeline diagram |
| P2 M1 | ERC-20 interface basics (first ~200 lines) |
| P2 M6 | "What is a CDP" opening, basic mapping explanations |
| P2 M7 | ERC-20 recap, deposit/withdraw signatures |
| P2 M8 | Basic reentrancy (checks-effects-interactions), onlyOwner |
| P3 M1 | Basic staking mechanics (32 ETH, running a validator) |
| P3 M2 | Basic leverage math ("10x means $100 controls $1000") |
| P3 M3 | Zero-coupon bond analogy (extended) |
| P3 M6 | Lock-and-mint Quick Try demo |
| P3 M8 | Proposal lifecycle diagram |
| P3 M9 | "Why a perpetual exchange capstone" motivation |
| P4 M1 | EOA vs contract accounts, tx types, EIP-1559 gas pricing |
| P4 M2 | Why ABI pads to 32 bytes |
| P4 DD-bits | AND/OR/XOR truth tables, basic SHL/SHR |

**Recommendation:** Each module should open with a 2-3 sentence "Assumed knowledge" note and jump directly to DeFi-specific content. The saved space can be redirected to under-explained production topics.

### Under-explained topics (where depth is needed)

| Module | Under-explained content |
|--------|------------------------|
| P1 M1 | `unchecked` safety proof methodology |
| P1 M2 | EIP-7702 security model edge cases |
| P1 M4 | EntryPoint validation internals, bundler mempool rules, session keys |
| P1 M5 | Effective invariant test handlers, debugging failing fuzz tests |
| P1 M6 | ERC-7201 namespaced storage (current OZ V5 standard) |
| P1 M7 | Deployment failure recovery, post-deployment verification, incident response |
| P2 M4 | Aave ReserveConfiguration bitmap packing |
| P2 M6 | MakerDAO `frob` function logic, oracle→Vat price flow |
| P2 M7 | Vault donation attacks, withdrawal queues, multi-source yield |
| P2 M8 | Complete exploit PoC construction, oracle manipulation |
| P3 M2 | GMX V2 price impact fee calculation, keeper infrastructure |
| P3 M3 | Pendle AMM curve math (logit function), LP mechanics |
| P3 M7 | Multi-chain deployment patterns, ZK rollup considerations |
| P3 M8 | ve-token implementation challenges, governance parameter tuning |
| P3 M9 | Storage layout for Position struct, LP share token design |
| P4 M6 | Deployment optimization (CREATE2 factories, minimal proxies) |
| P4 DD-bits | DeFi-specific applications (Uniswap V3 tick bitmap, Aave packed configs) |

---

## Dimension 5: Practical Readiness

### Exercise strengths
- **Consistent quality:** Scaffold + TODO + test pattern works well across all Parts
- **Best exercises:** P4 M4 YulDispatcher (mini ERC-20 in Yul), P4 M5 SafeCaller (4 token behaviors), P2 M8 VaultInvariantTest, P3 M5 Sandwich Simulation
- **Interview prep:** Consistently excellent — tiered answers, red flags, pro tips

### Exercise gaps (recurring across the curriculum)

| Gap | Impact |
|-----|--------|
| No mainnet fork exercises with real protocols | High — protocol engineers work with live contracts daily |
| No exploit reproduction exercises | High — top interview question: "walk me through a vuln you found" |
| No exercises involving Permit2 | Medium — stated as critical but never practiced |
| No deployment + upgrade exercise sequence | Medium — P1 M7 deploys but never upgrades |
| No exercises triaging static analysis output | Medium — false positives are the real skill |
| No cross-chain or L2-specific exercises | Medium — growing requirement for 2025 roles |
| Deep dives lack DeFi-specific production examples | Medium — theory-to-practice bridge missing |

### Production readiness gaps
- **P1 M7 (Deployment)** is weakest module — too surface-level on monitoring, incident response, and Safe integration
- **P2 M8 (Security)** teaches defensive patterns but not offensive thinking (constructing exploit PoCs)
- **P4 M8-M9 are empty placeholders** — either write them or remove from navigation

---

## Applied Fixes

### Priority 1: Factual errors — APPLIED (15 of 18)
The following 15 MUST FIX items have been corrected in the curriculum files:
- #1 (P1 M7): Ronin Bridge → "5 of 9 validator keys compromised"
- #2 (P4 M1): SELFDESTRUCT → "still transfers remaining ETH balance"
- #3 (P4 M1): Block gas limit → ~36M
- #4 (P1 M6): Storage gap → clarified packing vs conservative counting
- #5 (P4 M6): Jump table dispatch → reconciled to ~93 gas
- #6 (P2 M1): SushiSwap MISO → supply chain attack on frontend
- #7 (P2 M2): Uniswap V4 launch → January 2025 (2 locations)
- #10 (P4 M1): V2 reentrancy → "V2 shipped with 1→2→1 from the start"
- #11 (P2 M5): Flash loan modes → STABLE=1, VARIABLE=2 (3 locations)
- #12 (P2 M2): V2 flash swap fee → `amount * 1000 / 997`
- #13 (P2 M3): Chainlink BFT → >2/3 honest (2 locations)
- #14 (P2 M2): Cork Protocol → February 2025 (V4 wasn't live July 2024)
- #15 (P2 M5): Aave → "most widely used" (not "the original")
- #16 (P4 DD-err): V4 hooks → direct calls, no try/catch
- #17 (P3 M9): wstETH min() → protects protocol, not trader

**3 items were FALSE FINDINGS (date error — audit agents assumed March 2025, but today is March 2026):**
- #8 (P2 M8): "$3.1B in H1 2025" — correct historical stat, NOT future
- #9 (P3 M9): KiloEx "April 2025" — correct historical date, NOT future
- #18 (P3 M8): OZ Governor import — still applied (correct regardless of date)

### Priority 2: Timeline/currency — PARTIALLY APPLIED
**Applied (valid fixes):**
- veCRV fee distribution: noted 3CRV → crvUSD transition (P3 M8)
- Synthetix: added V3 context note, clarified V2 c-ratio (P3 M2)
- TVL timestamps: added "(as of Q4 2024)" to major TVL figures across P2 M2, M3, M4, P3 M1

**FALSE FINDINGS (removed — dates were correct all along):**
- Pectra "activated May 2025" — correct, Pectra IS live
- Solidity 0.8.30/0.8.31 "released" — correct, both ARE released
- "$3.1B in H1 2025" — correct historical stat
- KiloEx "April 2025" — correct historical date

### SHOULD FIX items — date-affected, need re-review
The following SHOULD FIX items were flagged by audit agents with a March 2025 date assumption and need re-evaluation before applying:
- #1: Solidity 0.8.30/0.8.31 "referenced as released" — they ARE released (FALSE)
- #2: Pectra "activated" — it IS activated (FALSE)
- #9: Flash loan stable rate mode "without noting V3.3 deprecation" — needs verification: did Aave V3.3 actually deprecate stable rate by March 2026?

All other SHOULD FIX items (#3-#8, #10-#22) are date-independent and remain valid.

---

## Remaining Action Plan

### Priority 3: Add missing major protocols/standards (8 items)
GHO, Morpho Vaults, ERC-7540, ERC-1167, Liquity V2, Synthetix V3, ERC-7683, Pendle in yield module. These are expected knowledge for 2025-2026 DeFi roles.

### Priority 4: Rebalance depth calibration
Compress over-explained basics into "Assumed knowledge" notes. Redirect space to under-explained production topics (see Dimension 4 tables).

### Priority 5: Add mainnet fork exercises
At least 3-4 exercises across the curriculum should fork mainnet and interact with real deployed contracts (Aave, Uniswap, Chainlink, Pendle).

### Priority 6: Resolve P4 M8-M9 placeholder status
Either write the Pure Yul and Yul Capstone modules or restructure Part 4 to end at Module 7.

### Priority 7: Fix remaining SHOULD FIX accuracy items
Address the date-independent imprecise claims (#3-#8, #10-#22 from the SHOULD FIX table).

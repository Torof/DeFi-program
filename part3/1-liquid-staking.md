# Part 3 — Module 1: Liquid Staking & Restaking (~4 days)

**Prerequisites:** Part 2 — Modules 1 (Token Mechanics), 3 (Oracles), 7 (Vaults & Yield)
**Pattern:** Fundamentals → Protocol architecture → Restaking → Integration patterns → Hands-on
**Builds on:** ERC-4626 share math (P2M7), Chainlink oracle integration (P2M3), rebasing tokens (P2M1), decimal normalization (P2M4/M9)
**Used by:** Module 3 (Yield Tokenization — Pendle splits LST yield into PT/YT), Module 9 (Capstone — LSTs as perpetual exchange collateral)

---

## 📚 Table of Contents

**Liquid Staking Fundamentals**
- [Why Liquid Staking Exists](#why-liquid-staking)
- [Two Models: Rebasing vs Non-Rebasing](#rebasing-vs-non-rebasing)
- [Deep Dive: The Exchange Rate](#exchange-rate)
- [Withdrawal Queue (Post-Shapella)](#withdrawal-queue)

**Protocol Architecture**
- [Lido Architecture](#lido-architecture)
- [Deep Dive: Shares-Based Accounting in Lido](#shares-accounting)
- [wstETH: The Non-Rebasing Wrapper](#wsteth-wrapper)
- [Oracle Reporting & the Rebase Mechanism](#oracle-reporting)
- [Rocket Pool: Decentralized Alternative](#rocket-pool)
- [Code Reading Strategy](#code-reading)

**EigenLayer & Restaking**
- [What is Restaking?](#what-is-restaking)
- [EigenLayer Architecture](#eigenlayer-architecture)
- [Liquid Restaking Tokens (LRTs)](#lrts)
- [The Risk Landscape](#risk-landscape)

**LST Integration Patterns**
- [Deep Dive: LST Oracle Pricing Pipeline](#oracle-pricing)
- [De-Peg Scenarios and the Dual Oracle Pattern](#depeg-dual-oracle)
- [LSTs as Collateral in Lending](#lst-collateral)
- [LSTs in AMMs](#lst-amms)
- [LSTs in Vaults](#lst-vaults)

**Wrap Up**
- [DeFi Pattern Connections](#pattern-connections)
- [Job Market Context](#job-market)
- [Module Exercises](#exercises)
- [Resources](#resources)

---

## Liquid Staking Fundamentals

<a id="why-liquid-staking"></a>
### 💡 Why Liquid Staking Exists

**The problem:** Ethereum staking requires 32 ETH and running a validator. Staked ETH is locked — you can't use it as DeFi collateral, you can't trade it, you can't LP with it. For an asset class worth billions, that's a massive capital efficiency problem.

**The solution:** Liquid staking protocols pool user deposits, run validators on their behalf, and issue a **liquid receipt token** (LST) that represents the staked position. The LST accrues staking rewards (~3-4% APR) while remaining freely tradeable and composable with DeFi.

**Why this matters for DeFi developers:** LSTs are the largest DeFi sector by TVL (~$50B+). wstETH is the most popular collateral type on Aave. Every major lending protocol, AMM, and vault must handle LSTs correctly — and "correctly" means understanding exchange rates, rebasing mechanics, oracle pricing, and de-peg risk. If you're building DeFi, you're integrating with LSTs.

```
Without liquid staking:                 With liquid staking:

32 ETH → Validator                      10 ETH → Lido
   │                                       │
   │  Locked. Earning ~3.5%                │  Receive 10 stETH
   │  Can't use in DeFi.                   │  Earning ~3.5% (balance rebases daily)
   │                                       │
   ▼                                       ▼
No DeFi composability.               Use stETH in DeFi:
                                      • Collateral on Aave
                                      • LP on Curve
                                      • Deposit in Pendle (split yield)
                                      • Collateral in CDPs
                                      • Restake via EigenLayer
```

<a id="rebasing-vs-non-rebasing"></a>
### 💡 Two Models: Rebasing vs Non-Rebasing

LSTs represent staked ETH plus accumulated rewards. There are two fundamentally different approaches to reflecting those rewards.

**Rebasing (stETH — Lido):**

Your token balance increases daily. If you hold 10 stETH today, you'll hold 10.001 stETH tomorrow (assuming ~3.5% APR). The token always represents ~1 staked ETH — the balance adjusts to reflect accumulated rewards.

```
Day 0:   balanceOf(you) = 10.000000 stETH
Day 1:   balanceOf(you) = 10.000959 stETH  (daily rebase at ~3.5% APR)
Day 30:  balanceOf(you) = 10.028767 stETH
Day 365: balanceOf(you) = 10.350000 stETH  (~3.5% growth)
```

The rebase happens automatically when Lido's oracle reports new validator balances. You don't call any function — your `balanceOf()` return value simply changes.

**The DeFi integration problem:** Many contracts assume token balances don't change between transactions. A vault that stores `balanceOf(address(this))` on deposit will find a different balance later — breaking accounting. This is the "weird token" callback issue from P2M1.

> **🔗 Connection:** This is exactly why P2M1 covered rebasing tokens as a "weird token" category. Contracts that cache balances, emit transfer events, or calculate shares based on balance differences all break with stETH.

**Non-Rebasing / Wrapped (wstETH, rETH):**

Your token balance stays fixed. Instead, the **exchange rate** increases over time. 10 wstETH today might be worth 11.9 stETH, and 10 wstETH in a year will be worth ~12.3 stETH. Same number of tokens, more underlying value.

```
Day 0:   balanceOf(you) = 10 wstETH  →  worth 11.900 stETH  (at 1.190 rate)
Day 365: balanceOf(you) = 10 wstETH  →  worth 12.317 stETH  (at 1.232 rate)

Your balance didn't change. The exchange rate did.
```

**This is the ERC-4626 pattern.** wstETH behaves exactly like vault shares — fixed balance, increasing exchange rate. rETH works the same way. This is why DeFi protocols overwhelmingly prefer wstETH over stETH.

> **🔗 Connection:** This maps directly to P2M7's vault share math. `convertToAssets(shares)` in ERC-4626 is analogous to `getStETHByWstETH(wstETHAmount)` in Lido. Same mental model, same integration patterns.

**Comparison:**

| | Rebasing (stETH) | Non-Rebasing (wstETH, rETH) |
|---|---|---|
| Balance changes? | Yes — daily rebase | No — fixed |
| Exchange rate? | Always ~1:1 by definition | Increases over time |
| DeFi-friendly? | No — breaks many integrations | Yes — standard ERC-20 behavior |
| Mental model | Like a bank account (balance grows) | Like vault shares (share price grows) |
| Internal tracking | Shares (hidden from user) | Shares ARE the token |
| Used in DeFi as | Rarely directly — wrapped to wstETH first | Directly — wstETH and rETH composable everywhere |

**The pattern:** In practice, stETH exists for user-facing simplicity (people understand "my balance grows"), while wstETH exists for DeFi composability. This is why Aave, Compound, Maker, and every lending protocol lists wstETH, not stETH.

<a id="exchange-rate"></a>
### 🔍 Deep Dive: The Exchange Rate

The exchange rate is how non-rebasing LSTs reflect accumulated rewards. Understanding the math is critical for pricing, oracles, and integration.

**wstETH exchange rate:**

```
stEthPerToken = totalPooledEther / totalShares
```

Where `totalPooledEther` is all ETH controlled by Lido (staked + buffered) and `totalShares` is the total internal shares issued. When validators earn rewards, `totalPooledEther` increases while `totalShares` stays the same — so `stEthPerToken` increases.

**Numeric walkthrough:**

```
Given (approximate values, early 2026):
  totalPooledEther = 9,600,000 ETH
  totalShares      = 8,100,000 shares

  stEthPerToken = 9,600,000 / 8,100,000 = 1.1852

  So: 1 wstETH = 1.1852 stETH = 1.1852 ETH (at protocol rate)

After one year of ~3.5% staking rewards:
  totalPooledEther = 9,600,000 × 1.035 = 9,936,000 ETH
  totalShares      = 8,100,000 (unchanged — no new deposits for simplicity)

  stEthPerToken = 9,936,000 / 8,100,000 = 1.2267

  So: 1 wstETH = 1.2267 stETH (3.5% increase in exchange rate)
```

**Converting between wstETH and stETH:**

```
Wrapping:   wstETH amount = stETH amount / stEthPerToken
Unwrapping: stETH amount  = wstETH amount × stEthPerToken
```

```
Example: Wrap 100 stETH when stEthPerToken = 1.1852
  wstETH received = 100 / 1.1852 = 84.37 wstETH

Later: Unwrap 84.37 wstETH when stEthPerToken = 1.2267
  stETH received = 84.37 × 1.2267 = 103.50 stETH

  Gain: 3.50 stETH — the staking rewards accumulated while holding wstETH
```

**rETH exchange rate:**

Rocket Pool's rETH uses a similar pattern but with different internals. The exchange rate is updated by Rocket Pool's Oracle DAO rather than derived from beacon chain balances.

```
rETH exchange rate = total ETH backing rETH / total rETH supply

Approximate value (early 2026): ~1.12 ETH per rETH
  (Rocket Pool launched Nov 2021, ~4 years of ~3% net yield after commission)

Example: 10 rETH × 1.12 = 11.2 ETH equivalent
```

> **Note:** Rocket Pool takes a 14% commission on staking rewards (distributed to node operators as RPL). So if beacon chain yields 3.5%, rETH holders earn ~3.0% net. This commission is why rETH's exchange rate grows slightly slower than wstETH's.

💻 **Quick Try:**

Fork mainnet in Foundry and check current exchange rates:
```solidity
// In a Foundry test with mainnet fork
IWstETH wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
uint256 rate = wstETH.stEthPerToken();
console.log("wstETH exchange rate:", rate); // ~1.19e18

IRocketTokenRETH rETH = IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
uint256 rethRate = rETH.getExchangeRate();
console.log("rETH exchange rate:", rethRate); // ~1.12e18
```

Deploy, call these view functions, and observe both rates are > 1.0 — reflecting years of accumulated staking rewards.

<a id="withdrawal-queue"></a>
### 💡 Withdrawal Queue (Post-Shapella)

Before Ethereum's Shapella upgrade (April 2023), staked ETH could not be withdrawn. LSTs traded at a discount to ETH because there was no redemption mechanism — the only way to exit was selling on a DEX.

**After Shapella:** Lido and Rocket Pool implemented withdrawal queues. Users can request to redeem their LST for underlying ETH, but the process takes time:

```
Request flow:
  User calls requestWithdrawals(stETHAmount)
       │
       ▼
  Protocol queues withdrawal
  User receives NFT receipt (Lido uses ERC-721)
       │
       ▼
  Wait for validators to exit + ETH to become available
  (typically 1-5 days, can be longer during high demand)
       │
       ▼
  Withdrawal finalized
  User calls claimWithdrawal(requestId)
  ETH returned to user
```

**Impact on LST/ETH peg:**
- The withdrawal queue creates an arbitrage loop: if stETH trades below 1 ETH on a DEX, arbitrageurs buy cheap stETH → request withdrawal → receive 1 ETH → profit. This keeps the peg tight.
- During extreme demand (mass exits), the queue lengthens and the peg can weaken — arbitrageurs must lock capital longer, reducing their incentive.
- Post-Shapella, stETH has traded very close to 1:1 with ETH. The June 2022 de-peg (0.93 ETH) happened pre-Shapella when no withdrawal mechanism existed.

### 📋 Summary: Liquid Staking Fundamentals

**Covered:**
- Why liquid staking exists — capital efficiency for staked ETH
- Two models — rebasing (stETH, balance changes) vs non-rebasing (wstETH/rETH, exchange rate changes)
- Exchange rate math — `stEthPerToken` and `getExchangeRate()` with numeric walkthroughs
- Why DeFi prefers non-rebasing — same ERC-4626 mental model, no integration surprises
- Withdrawal queue — post-Shapella redemption mechanism and its peg stabilization role

**Key insight:** Non-rebasing LSTs are conceptually identical to ERC-4626 vault shares. If you understand `convertToAssets(shares)`, you understand `getStETHByWstETH(wstETHAmount)`. The pricing pipeline, the manipulation concerns, and the oracle integration patterns all carry over from P2M7 and P2M9.

**Next:** How Lido and Rocket Pool actually implement this — the contract architecture that makes liquid staking work.

---

## Protocol Architecture

<a id="lido-architecture"></a>
### 💡 Lido Architecture

Lido is the largest liquid staking protocol (~70% market share of ETH LSTs). Understanding its architecture is essential because most DeFi LST integrations target wstETH.

```
User                   Lido Protocol                         Beacon Chain
  │                         │                                     │
  │── submit(ETH) ─────→  Lido (stETH)                          │
  │                    │  • mint shares to user                   │
  │                    │  • buffer ETH                            │
  │                    │        │                                  │
  │                    │  StakingRouter                           │
  │                    │  • allocate to Node Operators ────────→  Validators
  │                    │                                          │
  │                    │  AccountingOracle                        │
  │                    │  ← CL balance report ─────────────────  │
  │                    │  • update totalPooledEther               │
  │                    │  • triggers rebase for all holders       │
  │                    │                                          │
  │── wrap(stETH) ──→ WstETH                                    │
  │                    │  • holds stETH shares internally         │
  │                    │  • user gets fixed-balance wstETH        │
  │                    │                                          │
  │── requestWithdrawals → WithdrawalQueueERC721                 │
  │                    │  • mint NFT receipt                      │
  │                    │  • finalized when ETH available ←──────  │
  │── claimWithdrawal ─→  • return ETH to user                  │
```

**Key contracts:**

| Contract | Role | Key functions |
|---|---|---|
| `Lido.sol` (stETH) | Main contract — ERC-20 rebasing token + deposit | `submit()`, `getSharesByPooledEth()`, `getPooledEthByShares()` |
| `WstETH.sol` | Non-rebasing wrapper | `wrap()`, `unwrap()`, `stEthPerToken()`, `getStETHByWstETH()` |
| `AccountingOracle.sol` | Reports beacon chain state | `submitReportData()` → triggers `handleOracleReport()` |
| `StakingRouter.sol` | Routes ETH to node operators | `deposit()`, module-based operator allocation |
| `WithdrawalQueueERC721.sol` | Withdrawal requests as NFTs | `requestWithdrawals()`, `claimWithdrawals()` |
| `NodeOperatorsRegistry.sol` | Curated operator set | Operator management (permissioned — centralization point) |

<a id="shares-accounting"></a>
### 🔍 Deep Dive: Shares-Based Accounting in Lido

Lido's stETH looks like a simple rebasing token from the outside, but internally it uses **shares-based accounting** — the same pattern as Aave's aTokens and ERC-4626 vaults.

**The core math:**

```solidity
// Internal: every stETH holder has a shares balance
mapping(address => uint256) private shares;
uint256 public totalShares;
uint256 public totalPooledEther; // updated by oracle

// External: balanceOf returns stETH (not shares)
function balanceOf(address account) public view returns (uint256) {
    return shares[account] * totalPooledEther / totalShares;
}

// Deposit: ETH → shares
function submit(address referral) external payable returns (uint256) {
    uint256 sharesToMint = msg.value * totalShares / totalPooledEther;
    shares[msg.sender] += sharesToMint;
    totalShares += sharesToMint;
    totalPooledEther += msg.value;
    return sharesToMint;
}
```

**How the rebase works:**

```
Before oracle report:
  totalPooledEther = 1,000,000 ETH
  totalShares      = 900,000
  Alice has         = 9,000 shares

  Alice's balance = 9,000 × 1,000,000 / 900,000 = 10,000 stETH

Oracle reports: validators earned 100 ETH in rewards.

After oracle report:
  totalPooledEther = 1,000,100 ETH  (increased by 100)
  totalShares      = 900,000         (unchanged)
  Alice has         = 9,000 shares   (unchanged)

  Alice's balance = 9,000 × 1,000,100 / 900,000 = 10,001.00 stETH

Alice's balance increased by 1 stETH without any transaction. That's the rebase.
```

**Why shares internally?** Because updating `totalPooledEther` once (O(1)) is far cheaper than iterating over every holder's balance (O(n)). The math resolves everything at read time. This is the same insight behind ERC-4626 and Aave's scaled balances — one global variable update serves all holders.

> **🔗 Connection:** This is the exact pattern from P2M7's vault share math. The only difference is naming: ERC-4626 calls it `totalAssets / totalSupply`, Lido calls it `totalPooledEther / totalShares`. Same math, same O(1) rebase mechanism.

<a id="wsteth-wrapper"></a>
### 💡 wstETH: The Non-Rebasing Wrapper

wstETH is a thin wrapper around stETH shares. When you "wrap" stETH, you're converting from the rebasing representation to the shares representation. When you "unwrap," you convert back.

```solidity
// Simplified from Lido's WstETH.sol
contract WstETH is ERC20 {
    IStETH public stETH;

    function wrap(uint256 stETHAmount) external returns (uint256) {
        // Convert stETH amount to shares
        uint256 wstETHAmount = stETH.getSharesByPooledEth(stETHAmount);
        // Transfer stETH in (as shares internally)
        stETH.transferFrom(msg.sender, address(this), stETHAmount);
        // Mint wstETH 1:1 with shares
        _mint(msg.sender, wstETHAmount);
        return wstETHAmount;
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256) {
        // Convert shares back to stETH amount
        uint256 stETHAmount = stETH.getPooledEthByShares(wstETHAmount);
        // Burn wstETH
        _burn(msg.sender, wstETHAmount);
        // Transfer stETH out
        stETH.transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }

    // The exchange rate — how much stETH one wstETH is worth
    function stEthPerToken() external view returns (uint256) {
        return stETH.getPooledEthByShares(1 ether); // 1 share → X stETH
    }

    // Conversion helpers
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256) {
        return stETH.getSharesByPooledEth(stETHAmount);
    }

    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256) {
        return stETH.getPooledEthByShares(wstETHAmount);
    }
}
```

**The key insight:** 1 wstETH = 1 Lido share. The "wrapping" is conceptual — wstETH simply exposes shares as a standard ERC-20 instead of hiding them behind the rebasing `balanceOf()`. This is why wstETH is DeFi-compatible: its balance never changes, only the rate returned by `stEthPerToken()` grows.

<a id="oracle-reporting"></a>
### 💡 Oracle Reporting & the Rebase Mechanism

The oracle is how Lido learns about validator performance on the beacon chain (consensus layer). This is a trust assumption worth understanding.

**The flow:**

```
Beacon Chain validators earn rewards
       │
       ▼
Oracle committee (5/9 quorum in V1; V2 uses HashConsensus)
reports new total CL balance
       │
       ▼
AccountingOracle.submitReportData()
       │
       ▼
Lido._handleOracleReport()
  • Updates totalPooledEther
  • Applies sanity checks:
    - APR can't exceed a configured max (~10%)
    - Balance can't drop more than configured limit (slashing protection)
  • Mints fee shares (10% of rewards → treasury + node operators)
  • All stETH holders' balanceOf() now returns updated values
```

**The trust model:** Lido relies on a permissioned oracle committee to report beacon chain balances accurately. This is a centralization point — if the oracle reports inflated balances, stETH becomes over-valued. The sanity checks (max APR cap, max balance drop) limit the damage from a compromised oracle, but the trust assumption exists.

**Sanity check example:**
```
Last reported: totalPooledEther = 9,600,000 ETH
New report claims: totalPooledEther = 10,500,000 ETH

APR implied: (10,500,000 - 9,600,000) / 9,600,000 = 9.375%
Max allowed APR: 10%

9.375% < 10% → passes sanity check

But if new report claimed 11,000,000 ETH:
APR implied: 14.6% → exceeds 10% cap → REJECTED

(Simplified — Lido's actual checks use per-report balance limits, not annualized rates.
 This annualized framing illustrates the concept.)
```

**Frequency:** Oracle reports happen roughly once per day. (Lido V1 used a fixed ~225-epoch cadence; V2 uses configurable reporting frames that can vary.) Between reports, the exchange rate is stale — it doesn't reflect the latest beacon chain rewards. This staleness is normally negligible but matters during rapid market changes.

> **🔗 Connection:** This oracle sanity check pattern is analogous to the rate cap you saw in P2M9's vault share pricing — both limit how fast an exchange rate can grow to prevent manipulation. Lido's cap is built into the protocol itself; your P2M9 stablecoin cap was external.

<a id="rocket-pool"></a>
### 💡 Rocket Pool: Decentralized Alternative

Rocket Pool takes a different approach to decentralization. Where Lido uses a curated set of professional operators, Rocket Pool is **permissionless** — anyone can run a validator.

**The minipool model:**

```
Traditional staking:     Validator needs 32 ETH from one source

Rocket Pool minipool:    Validator needs:
                           • 8 ETH from node operator (+ RPL stake as insurance)
                           • 24 ETH from rETH depositors (pooled)
                         Or:
                           • 16 ETH from node operator (+ RPL stake)
                           • 16 ETH from rETH depositors

  ┌──────────────────────────────────────────┐
  │            32 ETH Validator              │
  ├────────────┬─────────────────────────────┤
  │ 8 ETH      │        24 ETH              │
  │ (operator) │   (rETH depositors pool)   │
  │ + RPL bond │                             │
  └────────────┴─────────────────────────────┘
```

**rETH exchange rate:**

```solidity
// Simplified from RocketTokenRETH.sol
function getExchangeRate() public view returns (uint256) {
    uint256 totalEth = address(rocketDepositPool).balance
                     + totalStakedEthInMinipools
                     + rewardsAccumulated;
    uint256 rethSupply = totalSupply();
    if (rethSupply == 0) return 1 ether;
    return totalEth * 1 ether / rethSupply;
}
```

The rate is updated by Rocket Pool's Oracle DAO (a set of trusted nodes) rather than derived directly from the contract's beacon chain view. This introduces a similar trust assumption to Lido's oracle, but with a different governance structure.

**Trade-offs: Lido vs Rocket Pool**

| | Lido (stETH/wstETH) | Rocket Pool (rETH) |
|---|---|---|
| Market share | ~70% of LST market | ~5-8% |
| Operator model | Curated (permissioned) | Permissionless (8 ETH + RPL) |
| Oracle | Oracle committee (5/9) | Oracle DAO (trusted node set) |
| DeFi liquidity | Deep (Curve, Aave, Uniswap, etc.) | Thinner but growing |
| Commission | 10% of rewards | 14% of rewards |
| Exchange rate (approx. early 2026) | ~1.19 | ~1.12 |
| Governance | LDO token + dual governance | pDAO + oDAO |
| Centralization concern | Operator set concentration | Oracle DAO trust |

**Why this matters for integration:** When you build a protocol that accepts LST collateral, you'll likely support both wstETH and rETH. The oracle pricing pattern is the same (exchange rate × underlying price), but the liquidity profiles differ. wstETH can be liquidated against deep Curve/Uniswap pools; rETH has thinner secondary market liquidity, so you'd set a lower LTV for rETH collateral.

<a id="code-reading"></a>
### 📖 Code Reading Strategy

**Lido — reading order:**

| # | File | Why Read | Key Functions |
|---|---|---|---|
| 1 | `WstETH.sol` | Simplest entry point — clean wrapper | `wrap()`, `unwrap()`, `stEthPerToken()` |
| 2 | `Lido.sol` (stETH) | Core token — shares-based accounting | `submit()`, `_transferShares()`, `getPooledEthByShares()` |
| 3 | `AccountingOracle.sol` | How rebase is triggered | `submitReportData()`, sanity checks |
| 4 | `WithdrawalQueueERC721.sol` | Exit mechanism | `requestWithdrawals()`, `_finalize()` |

**Don't get stuck on:** Lido's governance contracts, the `Burner` contract (handles cover/slashing accounting), or the `StakingRouter` module system. These are protocol-governance concerns, not DeFi integration concerns.

**Rocket Pool — reading order:**

| # | File | Why Read | Key Functions |
|---|---|---|---|
| 1 | `RocketTokenRETH.sol` | The token — exchange rate | `getExchangeRate()`, `mint()`, `burn()` |
| 2 | `RocketDepositPool.sol` | Deposit entry point | `deposit()` → allocates to minipools |

**Don't get stuck on:** Rocket Pool's minipool lifecycle contracts (`RocketMinipoolManager`, `RocketMinipoolDelegate`). These are validator-operations concerns, not DeFi integration concerns.

> **Repos:** [Lido](https://github.com/lidofinance/lido-dao) | [Rocket Pool](https://github.com/rocket-pool/rocketpool)

### 📋 Summary: Protocol Architecture

**Covered:**
- Lido architecture — 6 key contracts with roles and data flow
- Shares-based accounting — internal shares + `totalPooledEther` enables O(1) rebase
- wstETH wrapper — exposes shares as standard ERC-20 (no rebase surprises)
- Oracle reporting — how beacon chain rewards become stETH balance changes, including sanity checks
- Rocket Pool — permissionless minipool model, rETH exchange rate, trade-offs vs Lido
- Code reading strategy with file-level specifics

**Key insight:** Both Lido and Rocket Pool use the same underlying math (shares × rate = value) but expose it differently. Lido shows it as a rebasing balance (stETH) with a wrapper option (wstETH). Rocket Pool only offers the non-rebasing form (rETH). For DeFi integration, both are "exchange rate × underlying price" — the same pipeline.

**Next:** Restaking — the layer built on top of liquid staking, and the new risk frontier.

> **🧭 Checkpoint — Before Moving On:**
> Can you explain the difference between stETH and wstETH in terms of how they represent staking rewards? Can you calculate a wstETH → stETH conversion given a `stEthPerToken` value? If you can, you understand the foundation that everything else in this module builds on.

---

## EigenLayer & Restaking

<a id="what-is-restaking"></a>
### 💡 What is Restaking?

Staked ETH secures Ethereum's consensus layer. Restaking extends this security to additional protocols by allowing stakers to **opt in** to securing additional services with the same stake.

**The concept:**
```
Traditional staking:
  32 ETH → Secures Ethereum → Earns ~3.5% APR

Restaking:
  32 ETH → Secures Ethereum → Earns ~3.5% APR
         → ALSO secures Oracle Network → Earns +0.5% APR
         → ALSO secures Bridge Protocol → Earns +0.3% APR
         → ALSO secures Data Availability → Earns +0.4% APR

  Same capital, multiple revenue streams.
  Trade-off: additional slashing risk for each service.
```

**Why it matters:** Before EigenLayer, every new protocol that needed economic security had to bootstrap its own staking system — recruit validators, create a token, incentivize staking. Restaking lets protocols "rent" Ethereum's existing security. This is a fundamental shift in how decentralized infrastructure is bootstrapped.

💻 **Quick Try (read-only, optional):**

If you have an Ethereum mainnet RPC (e.g., Alchemy/Infura), you can inspect EigenLayer's live state:

```solidity
// In Foundry's cast:
// cast call 0x858646372CC42E1A627fcE94aa7A7033e7CF075A "getTotalShares(address)(uint256)" 0x93c4b944D05dfe6df7645A86cd2206016c51564D --rpc-url $RPC
// (StrategyManager → stETH strategy shares)
```

This is a read-only peek at how much stETH is restaked in EigenLayer. No testnet deployment needed — just a mainnet RPC call.

<a id="eigenlayer-architecture"></a>
### 💡 EigenLayer Architecture

EigenLayer is the dominant restaking protocol. It has four core components:

```
                      ┌───────────────────────┐
                      │    AVS Contracts       │
                      │  (EigenDA, oracles,    │
                      │   bridges, sequencers) │
                      └───────────┬───────────┘
                                  │ registers + validates
                      ┌───────────┴───────────┐
                      │      Operators         │
                      │  (run AVS software,    │
                      │   sign attestations)   │
                      └───────────┬───────────┘
                                  │ delegation
                      ┌───────────┴───────────┐
                      │  DelegationManager     │
                      │  (stakers → operators) │
                      └─────┬───────────┬─────┘
                            │           │
               ┌────────────┴──┐  ┌─────┴────────────┐
               │StrategyManager│  │ EigenPodManager   │
               │  (LST deposit)│  │ (native ETH       │
               │  wstETH, rETH│  │  restaking via     │
               │  cbETH, etc. │  │  beacon proofs)    │
               └───────────────┘  └──────────────────┘
```

**StrategyManager** — Handles LST restaking. Users deposit LSTs (wstETH, rETH, etc.) into strategies. Each strategy holds one token type. The deposited tokens become the staker's restaked capital.

**EigenPodManager** — Handles native ETH restaking. Validators point their withdrawal credentials to an `EigenPod` contract. The pod verifies beacon chain proofs to confirm the validator's balance and status. No LST needed — raw staked ETH is restaked.

**DelegationManager** — The bridge between stakers and operators. Stakers delegate their restaked assets to operators who actually run AVS infrastructure. Stakers earn rewards but also bear slashing risk from the operator's behavior.

**AVS (Actively Validated Services)** — The protocols secured by restaked ETH. Each AVS defines its own:
- What operators must do (run specific software, provide attestations)
- What constitutes misbehavior (triggers slashing)
- How rewards are distributed

Major AVSes include EigenDA (data availability), various oracle networks, and bridge validation services.

**The delegation and slashing flow:**

```
Staker deposits 100 wstETH into StrategyManager
       │
       ▼
Staker delegates to Operator A via DelegationManager
       │
       ▼
Operator A opts into EigenDA AVS + Oracle AVS
       │
       ├── Operator runs EigenDA node → earns rewards → distributed to staker
       │
       └── Operator runs Oracle node → earns rewards → distributed to staker

If Operator A misbehaves on either AVS:
       │
       ▼
AVS triggers slashing → portion of staker's 100 wstETH is seized
```

**Key point for DeFi developers:** You don't need to understand EigenLayer's internals deeply to integrate with it. What matters is understanding that restaked assets have **additional slashing risk** beyond normal staking — and this risk affects how you should value LRTs (liquid restaking tokens) as collateral.

<a id="lrts"></a>
### 💡 Liquid Restaking Tokens (LRTs)

LRTs are to restaking what LSTs are to staking — liquid receipt tokens for restaked positions.

```
Staking:                        Restaking:
ETH → Lido → stETH (LST)       stETH → EigenLayer → deposit receipt
                                  │
                                  └── Not liquid! Locked in EigenLayer.

Liquid Restaking:
ETH → EtherFi → weETH (LRT)
  Internally: EtherFi stakes ETH → restakes via EigenLayer → issues weETH
  User gets: liquid token representing staked + restaked ETH
```

**Major LRTs (early 2026):**

| LRT | Protocol | Strategy | Notes |
|---|---|---|---|
| weETH | EtherFi | Native restaking | Largest LRT by TVL |
| ezETH | Renzo | Multi-AVS restaking | Diversified operator set |
| rsETH | KelpDAO | LST restaking | Accepts multiple LSTs |
| pufETH | Puffer | Native + anti-slashing | Uses Secure-Signer TEE technology |

**LRT exchange rates** reflect both staking rewards AND restaking rewards (minus fees). They're more complex than LST exchange rates because the yield sources are more diverse and the risk profile is different.

**Integration caution:** LRTs are newer and less battle-tested than LSTs. Their exchange rate mechanisms vary more across protocols, their oracle infrastructure is less mature, and their liquidity on DEXes is thinner. For DeFi integration (lending, collateral), LRTs warrant lower LTVs and more conservative oracle designs than wstETH or rETH.

<a id="risk-landscape"></a>
### ⚠️ The Risk Landscape

**Risk stacking visualization:**

```
┌──────────────────────────────────────────────────────┐
│  LRT (weETH, ezETH)                                 │ ← LRT contract risk
│  • Smart contract bugs in LRT protocol               │   + liquidity risk
│  • Exchange rate oracle accuracy                      │   + de-peg risk
├──────────────────────────────────────────────────────┤
│  Restaking (EigenLayer)                              │ ← AVS slashing risk
│  • Operator misbehavior → slashing                   │   + operator risk
│  • AVS-specific failure modes                        │   + smart contract risk
│  • Correlated slashing across AVSes                  │
├──────────────────────────────────────────────────────┤
│  LST (wstETH, rETH)                                 │ ← Protocol risk
│  • Lido/Rocket Pool smart contract bug               │   + oracle risk
│  • Oracle committee compromise                       │   + de-peg risk
│  • Validator slashing (minor — diversified)          │
├──────────────────────────────────────────────────────┤
│  ETH Staking (Beacon Chain)                          │ ← Validator risk
│  • Individual validator slashing                     │   (minor if diversified)
│  • Inactivity penalties                              │
├──────────────────────────────────────────────────────┤
│  ETH (Base Asset)                                    │ ← Market risk only
└──────────────────────────────────────────────────────┘

Each layer ADDS risk. You inherit ALL layers below you.
  ETH holder:     1 risk layer
  wstETH holder:  3 risk layers
  weETH holder:   5 risk layers
```

**Why this matters for DeFi integration:**

When you accept an asset as collateral, you must account for ALL risk layers. This directly affects:
- **LTV ratios:** ETH might get 85% LTV, wstETH 80%, rETH 75%, weETH 65%
- **Oracle design:** More risk layers → more defensive pricing needed
- **Liquidation parameters:** Thinner liquidity → higher liquidation bonus needed
- **Debt ceilings:** Higher risk → lower maximum exposure

This is not theoretical — Aave, Morpho, and every lending protocol that lists these assets goes through exactly this analysis.

**The systemic risk:** If many AVSes use the same operator set, and that operator set gets slashed on one AVS, the collateral damage cascades — all LRTs backed by those operators lose value simultaneously. This correlated slashing risk is the restaking-specific systemic concern.

### 📋 Summary: EigenLayer & Restaking

**Covered:**
- Restaking concept — recycling economic security, additional yield for additional risk
- EigenLayer's 4 core components — StrategyManager, EigenPodManager, DelegationManager, AVS
- The delegation and slashing flow — how stakers, operators, and AVSes interact
- LRTs — liquid receipt tokens for restaked positions (weETH, ezETH, rsETH, pufETH)
- Risk stacking — each layer adds risk, directly affecting DeFi integration parameters

**Key insight:** The risk stacking diagram is what DeFi integration comes down to. Every LTV ratio, oracle design choice, and liquidation parameter for LSTs and LRTs is ultimately a judgment about which risk layers you're willing to accept and at what discount. This is the analysis that protocol risk teams perform — and being able to articulate it is a strong interview signal.

**Next:** Putting it all together — how to actually integrate LSTs into DeFi protocols.

---

## LST Integration Patterns

<a id="oracle-pricing"></a>
### 🔍 Deep Dive: LST Oracle Pricing Pipeline

Pricing LSTs requires a **two-step pipeline** — convert to underlying ETH via exchange rate, then price ETH in USD via Chainlink. This is the same pattern you saw in P2M9's vault share pricing.

**The pipeline:**

```
wstETH pricing (two steps):
  ┌──────────┐  getStETHByWstETH  ┌────────────┐   Chainlink    ┌───────────┐
  │ wstETH   │ ────────────────→  │  ETH equiv │ ────────────→  │ USD value │
  │ (18 dec) │   exchange rate    │  (18 dec)  │   ETH/USD     │ (8 dec)   │
  └──────────┘                    └────────────┘   (8 dec)      └───────────┘

rETH pricing (two steps):
  ┌──────────┐  getExchangeRate   ┌────────────┐   Chainlink    ┌───────────┐
  │ rETH     │ ────────────────→  │  ETH equiv │ ────────────→  │ USD value │
  │ (18 dec) │   exchange rate    │  (18 dec)  │   ETH/USD     │ (8 dec)   │
  └──────────┘                    └────────────┘   (8 dec)      └───────────┘

Compare to ETH pricing (one step):
  ┌──────────┐                    Chainlink     ┌───────────┐
  │ ETH      │ ──────────────────────────────→  │ USD value │
  │ (18 dec) │                    ETH/USD       │ (8 dec)   │
  └──────────┘                    (8 dec)       └───────────┘
```

> **🔗 Connection:** This is the exact same two-step pattern from P2M9's vault share collateral pricing. `getStETHByWstETH()` is `convertToAssets()` by another name. The decimal normalization, the manipulation concerns, and the code structure all carry over.

**Numeric walkthrough — wstETH:**

```
Given:
  wstETH amount    = 10 wstETH              (18 decimals → 10e18)
  stEthPerToken    = 1.19e18                 (exchange rate, 18 decimals)
  ETH/USD price    = $3,200                  (Chainlink 8 decimals → 3200e8)

Step 1: wstETH → ETH equivalent
  ethEquiv = wstETHAmount × stEthPerToken / 1e18
           = 10e18 × 1.19e18 / 1e18
           = 11.9e18 ETH

Step 2: ETH → USD
  valueUSD = ethEquiv × ethPrice / 1e18
           = 11.9e18 × 3200e8 / 1e18
           = 38_080e8

  10 wstETH = $38,080.00 USD
```

**Numeric walkthrough — rETH:**

```
Given:
  rETH amount      = 10 rETH                (18 decimals → 10e18)
  rETH exchange    = 1.12e18                 (ETH per rETH, 18 decimals)
  ETH/USD price    = $3,200                  (Chainlink 8 decimals → 3200e8)

Step 1: rETH → ETH equivalent
  ethEquiv = rETHAmount × exchangeRate / 1e18
           = 10e18 × 1.12e18 / 1e18
           = 11.2e18 ETH

Step 2: ETH → USD
  valueUSD = ethEquiv × ethPrice / 1e18
           = 11.2e18 × 3200e8 / 1e18
           = 35_840e8

  10 rETH = $35,840.00 USD
```

**Solidity implementation:**

```solidity
function getLSTValueUSD(
    address lstToken,
    uint256 amount,
    bool isWstETH
) public view returns (uint256 valueUSD) {
    uint256 ethEquivalent;

    if (isWstETH) {
        // wstETH → ETH via Lido exchange rate
        ethEquivalent = IWstETH(lstToken).getStETHByWstETH(amount);
    } else {
        // rETH → ETH via Rocket Pool exchange rate
        uint256 rate = IRocketTokenRETH(lstToken).getExchangeRate();
        ethEquivalent = amount * rate / 1e18;
    }

    // ETH → USD via Chainlink
    (, int256 ethPrice,,uint256 updatedAt,) = ethUsdFeed.latestRoundData();
    require(ethPrice > 0, "Invalid price");
    require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, "Stale price");

    valueUSD = ethEquivalent * uint256(ethPrice) / 1e18;
    // Result in 8 decimals (Chainlink ETH/USD decimals)
}
```

<a id="depeg-dual-oracle"></a>
### ⚠️ De-Peg Scenarios and the Dual Oracle Pattern

**The problem:** The exchange rate from Lido/Rocket Pool always reflects the protocol's view of the backing — stETH is always worth ~1 ETH according to the protocol. But the **market price** can diverge. If stETH trades at 0.95 ETH on Curve, a lending protocol using only the exchange rate would overvalue wstETH collateral by ~5%.

**Historical precedent — June 2022 stETH de-peg:**

```
Context: 3AC and Celsius facing insolvency, forced to sell stETH for ETH.
Pre-Shapella: No withdrawal queue. Only exit is selling on DEX.

Timeline:
  May 2022:    stETH/ETH ≈ 1.00 (normal)
  June 10:     stETH/ETH ≈ 0.97 (selling pressure begins)
  June 13:     stETH/ETH ≈ 0.93 (peak de-peg, ~7% discount)
  July 2022:   stETH/ETH ≈ 0.97 (partial recovery)
  Post-Shapella: stETH/ETH ≈ 1.00 (withdrawal queue eliminates structural de-peg)

Lending protocols using exchange-rate-only oracle:
  Valued wstETH collateral at 1.00 ETH per stETH
  Actual liquidation value on market: 0.93 ETH per stETH
  Gap: 7% — enough to cause undercollateralization in tight positions
```

**The dual oracle pattern:**

Use the **minimum** of the protocol exchange rate and the market price. During normal times, both are ~1.0 and the minimum doesn't matter. During a de-peg, the market price is lower, and the minimum correctly reflects the actual liquidation value of the collateral.

```
Normal times:
  Exchange rate:  1 stETH = 1.00 ETH (protocol)
  Market price:   1 stETH = 1.00 ETH (Curve/Chainlink)
  min(1.00, 1.00) = 1.00 ETH  ← no difference

De-peg scenario:
  Exchange rate:  1 stETH = 1.00 ETH (protocol — unchanged)
  Market price:   1 stETH = 0.93 ETH (Curve/Chainlink)
  min(1.00, 0.93) = 0.93 ETH  ← safely uses market price
```

**Numeric impact on a lending position:**

```
Position: 100 wstETH collateral, stEthPerToken = 1.19
  = 119 stETH equivalent, borrowing 300,000 stablecoin
  ETH/USD = $3,200, liquidation threshold = 82.5%

Exchange-rate-only valuation:
  collateralUSD = 119 × 1.00 × $3,200 = $380,800
  HF = $380,800 × 0.825 / $300,000 = 1.047  ← looks healthy

Dual oracle during 7% de-peg:
  collateralUSD = 119 × 0.93 × $3,200 = $354,144
  HF = $354,144 × 0.825 / $300,000 = 0.974  ← LIQUIDATABLE

The $26,656 difference is the de-peg discount. Without the dual oracle,
this position appears healthy when it should be liquidated.
```

**Implementation sketch:**

```solidity
function getStETHToETHRate() public view returns (uint256) {
    // Protocol rate: always ~1.0 (stETH is 1:1 with staked ETH by design)
    uint256 protocolRate = 1e18;

    // Market rate: Chainlink stETH/ETH feed
    (, int256 marketRate,,uint256 updatedAt,) = stethEthFeed.latestRoundData();
    require(marketRate > 0, "Invalid stETH price");
    require(block.timestamp - updatedAt <= STETH_STALENESS, "Stale stETH price");

    // Use the lower of the two — conservative for collateral valuation
    uint256 safeRate = uint256(marketRate) < protocolRate
        ? uint256(marketRate)
        : protocolRate;

    return safeRate;
}
```

> **Note:** Chainlink provides a stETH/ETH feed on mainnet. For rETH, Chainlink provides an rETH/ETH feed. Both are used by production protocols (Aave, Morpho) for exactly this dual-oracle pattern.

<a id="lst-collateral"></a>
### 💡 LSTs as Collateral in Lending

**Aave V3 wstETH integration — how production does it:**

Aave V3 lists wstETH as a collateral asset with specific parameters tuned for its risk profile:

```
Aave V3 Ethereum — wstETH parameters (approximate):
  LTV:                    80%
  Liquidation Threshold:  83%
  Liquidation Bonus:      5%
  Supply Cap:             ~1.2M wstETH

E-Mode (ETH-correlated):
  LTV:                    93%    ← much higher!
  Liquidation Threshold:  95%
  Liquidation Bonus:      1%
```

**E-Mode (Efficiency Mode):** Aave V3's E-Mode allows higher LTV for assets that are highly correlated. wstETH and ETH are correlated — wstETH is backed 1:1 by staked ETH. So Aave creates an "ETH-correlated" E-Mode category where wstETH collateral can borrow ETH (or WETH) at up to 93% LTV instead of 80%.

**Why E-Mode works here:** The risk of wstETH dropping significantly relative to ETH is low (they're fundamentally the same asset minus protocol risk). The primary risk is the de-peg scenario, which the dual oracle handles. With the dual oracle and high correlation, 93% LTV is defensible — but only for borrowing ETH-denominated assets, not stablecoins (where ETH price risk applies fully).

**Liquidation with LSTs:**

When a wstETH-collateralized position is liquidated, the liquidator receives wstETH. They have options:
1. **Hold wstETH** — continue earning staking yield
2. **Sell on DEX** — swap wstETH → ETH on Curve/Uniswap
3. **Unwrap + sell** — unwrap wstETH → stETH → request withdrawal (slow but 1:1 rate)

In practice, liquidators sell on DEX for immediate ETH. This is why DEX liquidity depth for wstETH matters for liquidation parameter settings — the same concern as P2M9's liquidation economics section.

> **🔗 Connection:** This mirrors exactly the liquidation economics discussion from P2M9 — bidder profitability depends on DEX liquidity depth, which determines whether liquidation actually works at the parameters you've set.

<a id="lst-amms"></a>
### 💡 LSTs in AMMs

**The Curve stETH/ETH pool** is the most important pool for LST liquidity. It uses Curve's StableSwap invariant, which is optimized for assets that trade near 1:1.

**Why StableSwap and not constant product (Uniswap)?**

```
For assets near 1:1 peg:

Constant product (x × y = k):
  Slippage for 1,000 ETH swap in $500M pool: ~0.4%

StableSwap (Curve):
  Slippage for 1,000 ETH swap in $500M pool: ~0.01%

  ~40x less slippage for correlated assets — critical for liquidation efficiency
  (illustrative — exact values depend on pool parameters and amplification factor)
```

> **🔗 Connection:** This connects to P2M2's AMM module. The invariant choice (constant product vs StableSwap vs concentrated liquidity) directly determines slippage, which determines liquidation viability for LST collateral.

**Yield-bearing LP positions:** LPing in the stETH/ETH pool earns trading fees AND half the position earns staking yield (the stETH side). This "yield-bearing LP" concept connects to P2M7's yield stacking patterns.

<a id="lst-vaults"></a>
### 💡 LSTs in Vaults

wstETH is a natural fit for ERC-4626 vaults. Since wstETH already has an increasing exchange rate (staking yield), wrapping it in a vault adds another yield layer:

```
Nested yield stack:
  ETH staking:    ~3.5% APR (base layer — beacon chain rewards)
  Vault strategy:  +X% APR (additional yield from vault's strategy)

Example: A vault that deposits wstETH as collateral on Aave,
borrows ETH, and loops the leverage:
  Base yield:     3.5% (staking)
  Leveraged yield: 3.5% × leverage multiplier - borrow cost
```

**wstETH as quasi-ERC-4626:** wstETH itself behaves almost like an ERC-4626 vault. It has shares (wstETH tokens), assets (stETH), and an exchange rate (`stEthPerToken`). The main difference is that ERC-4626 defines `deposit()/withdraw()` with assets, while wstETH uses `wrap()/unwrap()`. Some protocols (like Morpho Blue) treat wstETH as an ERC-4626 by using adapter contracts.

> **🔗 Connection:** This directly links to P3M3 (Yield Tokenization) — Pendle's most popular markets are wstETH and eETH, where users split LST staking yield into principal and yield tokens. Understanding LSTs as yield-bearing assets is the prerequisite for understanding yield tokenization.

<a id="pattern-connections"></a>
### 🔗 DeFi Pattern Connections

| Source | Concept | How It Connects |
|---|---|---|
| **P2M1** | Rebasing tokens | stETH is the canonical rebasing token — the "weird token" integration challenge |
| **P2M3** | Chainlink integration | ETH/USD and stETH/ETH feeds for LST pricing pipeline |
| **P2M4** | Health factor, liquidation | LST collateral health factor uses dual oracle, liquidation via DEX |
| **P2M7** | ERC-4626 share math | wstETH exchange rate = vault share `convertToAssets()` |
| **P2M7** | Inflation attack | Exchange rate manipulation concern applies to LST pricing |
| **P2M8** | Oracle manipulation | De-peg scenario defense requires dual oracle pattern |
| **P2M9** | Two-step vault share pricing | LST pricing pipeline is the same pattern (exchange rate × underlying price) |
| **P2M9** | Rate cap | Lido's oracle sanity check serves the same role as P2M9's rate cap |
| **P3M3** | Yield tokenization | Pendle splits LST yield into PT/YT — LSTs are the primary input |
| **P3M9** | Capstone (perp exchange) | LSTs as margin collateral — pricing and liquidation mechanics carry over |

### 📋 Summary: LST Integration Patterns

**Covered:**
- Oracle pricing pipeline — two-step (exchange rate → Chainlink), with full numeric walkthroughs
- De-peg scenario — June 2022 stETH de-peg, numeric impact on lending positions
- Dual oracle pattern — min(protocol rate, market rate) for safe collateral valuation
- LSTs as collateral — Aave V3 parameters, E-Mode for correlated assets, liquidation considerations
- LSTs in AMMs — why StableSwap for correlated assets, yield-bearing LP
- LSTs in vaults — nested yield stacking, wstETH as quasi-ERC-4626

**Key insight:** LST integration is really about two things: (1) correctly converting to underlying value via the exchange rate, and (2) defensively handling the edge case where market price diverges from exchange rate (de-peg). The dual oracle pattern handles both. Everything else — LTV ratios, E-Mode, liquidation parameters — follows from understanding these two points.

---

<a id="job-market"></a>
## 💼 Job Market Context

### Interview Questions

**1. "How would you integrate wstETH as collateral in a lending protocol?"**

- Good: "Use the exchange rate to convert wstETH to ETH, then Chainlink for ETH/USD."
- Great: "Two-step pricing: `getStETHByWstETH()` for the exchange rate, then Chainlink ETH/USD. But I'd also use a Chainlink stETH/ETH market feed as a second oracle, taking the minimum — the dual oracle pattern. During a de-peg (like June 2022), the exchange rate says 1:1 but the market says 0.93. Without the dual oracle, positions appear healthier than they really are, and liquidations don't fire when they should."

**2. "What are the risks of accepting LRTs as collateral?"**

- Good: "Smart contract risk, slashing risk, liquidity risk."
- Great: "Risk stacking — an LRT like weETH carries five layers of risk: ETH market risk, validator slashing, LST protocol risk, EigenLayer smart contract and AVS slashing risk, and the LRT protocol's own risk. Each layer compounds. I'd set LTV significantly lower than for plain wstETH (maybe 65% vs 80%), require deeper liquidity on DEX for liquidation viability, set higher liquidation bonus to compensate bidders for the added complexity of selling an LRT, and impose tighter debt ceilings."

**3. "Explain the difference between stETH and wstETH and when you'd use each."**

- Good: "stETH rebases, wstETH doesn't."
- Great: "Both represent the same underlying staked ETH. stETH uses rebasing — your balance grows daily as oracle reports update `totalPooledEther`. Internally, stETH tracks shares, and `balanceOf()` returns `shares × totalPooledEther / totalShares`. wstETH is a wrapper that exposes those shares directly as a standard ERC-20 — your balance is fixed, and the exchange rate `stEthPerToken` grows instead. You'd use wstETH for any DeFi integration — lending, vaults, AMMs — because rebasing breaks contracts that cache balances. stETH exists for user-facing simplicity."

**4. "How does Lido's oracle work, and what are the trust assumptions?"**

- Good: "Oracle committee reports beacon chain balances, triggering rebase."
- Great: "A permissioned oracle committee (5/9 quorum) submits beacon chain balance reports to `AccountingOracle`. The report updates `totalPooledEther`, which changes every stETH holder's `balanceOf()` return value. Sanity checks cap the maximum APR and maximum balance drop to limit damage from a compromised oracle. The trust assumption is that the oracle committee honestly reports balances — if they inflate the report, stETH becomes temporarily overvalued. This is similar to how Chainlink oracles are a trust assumption for price feeds."

**5. "What happened during the June 2022 stETH de-peg and what did it teach us?"**

- Good: "stETH traded below 1 ETH. It was caused by selling pressure."
- Great: "3AC and Celsius faced insolvency and had to liquidate stETH positions. Pre-Shapella, there was no withdrawal queue — the only exit was selling on DEX. Massive sell pressure pushed stETH/ETH to 0.93. This wasn't a protocol failure — Lido's backing was fine. It was a liquidity/market failure. The lesson: exchange rate and market price can diverge, so lending protocols need dual oracle pricing. Post-Shapella (April 2023), the withdrawal queue creates an arbitrage floor that prevents deep de-pegs."

### Interview Red Flags

- Saying "stETH is always worth 1 ETH" without qualifying that this is the protocol rate, not the market rate
- Not knowing why DeFi protocols prefer wstETH over stETH
- Treating LSTs and LRTs as having the same risk profile
- Not being able to explain the oracle reporting mechanism (it's a trust assumption worth understanding)
- Saying "just use the exchange rate" for collateral pricing without mentioning de-peg risk

**Pro tip:** In interviews, when discussing LST integration, always mention the de-peg scenario unprompted. Saying "we'd use a dual oracle pattern because of the June 2022 de-peg risk" signals real-world awareness, not just textbook knowledge. Protocol teams remember June 2022 — it shaped how every subsequent LST integration was designed.

**Pro tip:** If asked about EigenLayer/restaking, focus on the risk analysis (risk stacking, correlated slashing, LTV implications) rather than trying to explain the full architecture. Teams care more about how you'd evaluate the risk of accepting restaked assets than about memorizing contract names.

---

<a id="exercises"></a>
## 🎯 Module Exercises

**Workspace:** `workspace/src/part3/module1/`

### Exercise 1: LST Oracle Consumer

Build a `WstETHOracle` contract that correctly prices wstETH in USD using a two-step pipeline.

**What you'll implement:**
- `getWstETHValueUSD(uint256 wstETHAmount)` — exchange rate × Chainlink ETH/USD, with staleness checks on both data sources
- `getWstETHValueUSDSafe(uint256 wstETHAmount)` — same pipeline but with dual oracle pattern: uses `min(protocolRate, marketRate)` for the stETH → ETH conversion
- Staleness checks on both Chainlink feeds (ETH/USD and stETH/ETH)
- Decimal normalization across the pipeline

**What's provided:**
- Mock wstETH contract with configurable exchange rate (`stEthPerToken`)
- Mock Chainlink aggregator for ETH/USD and stETH/ETH feeds
- Interfaces for `IWstETH` and Chainlink `AggregatorV3Interface`

**Tests verify:**
- Basic pricing matches manual calculation (known exchange rate × known price)
- Dual oracle uses market price during simulated de-peg (stETH/ETH < 1.0)
- Staleness check reverts on stale ETH/USD feed
- Staleness check reverts on stale stETH/ETH feed
- Exchange rate growth over time produces correct price increase
- Zero amount reverts with `ZeroAmount` error
- Decimal normalization is correct across the pipeline

**🎯 Goal:** Internalize the two-step LST pricing pipeline and the dual oracle safety pattern. This is the exact oracle design used by Aave, Morpho, and every lending protocol that accepts wstETH.

### Exercise 2: LST Collateral Lending Pool

Build a simplified lending pool that accepts wstETH as collateral, using the oracle from Exercise 1.

**What you'll implement:**
- `depositCollateral(uint256 wstETHAmount)` — deposit wstETH as collateral
- `borrow(uint256 stablecoinAmount)` — borrow stablecoin against wstETH collateral
- `repay(uint256 stablecoinAmount)` — repay borrowed stablecoin
- `withdrawCollateral(uint256 wstETHAmount)` — withdraw collateral (health check after)
- `liquidate(address user)` — liquidate unhealthy position, transfer wstETH to liquidator
- `getHealthFactor(address user)` — calculate HF using safe (dual oracle) valuation
- E-Mode toggle: when borrowing ETH-denominated assets, use higher LTV

**What's provided:**
- `WstETHOracle` from Exercise 1 (imported, already deployed)
- Mock stablecoin ERC-20 for borrowing
- Mock wstETH with configurable exchange rate
- Mock Chainlink feeds for both price sources

**Tests verify:**
- Full lifecycle: deposit → borrow → repay → withdraw
- Health factor increases as wstETH exchange rate grows (staking rewards)
- De-peg scenario: stETH/ETH drops to 0.93, previously healthy position becomes liquidatable
- Liquidation transfers wstETH to liquidator, burns repaid stablecoin
- E-Mode allows higher LTV when borrowing ETH-denominated asset
- Cannot withdraw below minimum health factor
- Cannot borrow above debt ceiling

**🎯 Goal:** Practice building a lending integration that correctly handles LST-specific concerns — two-step pricing, de-peg risk, and E-Mode for correlated assets. These are production patterns used by every major lending protocol.

---

<a id="resources"></a>
## 📚 Resources

### Production Code

| Repository | What to Study | Key Files |
|---|---|---|
| [Lido stETH](https://github.com/lidofinance/lido-dao) | Shares accounting, oracle, rebase | `Lido.sol`, `WstETH.sol`, `AccountingOracle.sol` |
| [Rocket Pool](https://github.com/rocket-pool/rocketpool) | rETH exchange rate, minipool model | `RocketTokenRETH.sol`, `RocketDepositPool.sol` |
| [EigenLayer](https://github.com/Layr-Labs/eigenlayer-contracts) | Restaking architecture | `StrategyManager.sol`, `DelegationManager.sol` |
| [EtherFi](https://github.com/etherfi-protocol/smart-contracts) | LRT implementation | `weETH.sol`, `LiquidityPool.sol` |

### Documentation

- [Lido docs](https://docs.lido.fi/) — comprehensive, well-maintained
- [Lido stETH integration guide](https://docs.lido.fi/guides/steth-integration-guide) — essential reading for any integration
- [Rocket Pool docs](https://docs.rocketpool.net/)
- [EigenLayer docs](https://docs.eigenlayer.xyz/)

### Further Reading

- [stETH depeg analysis (June 2022)](https://research.lido.fi/) — post-mortem and market analysis
- [EigenLayer whitepaper](https://docs.eigenlayer.xyz/eigenlayer/overview) — restaking design rationale
- [Aave V3 wstETH risk parameters](https://governance.aave.com/) — search for wstETH listing proposals to see risk team analysis

---

**Navigation:** [Part 3 Overview](README.md) | [Next: Module 2 — Perpetuals & Derivatives →](2-perpetuals.md)

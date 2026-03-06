# Part 2 — Module 5: Flash Loans

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~30 minutes | **Exercises:** ~2-3 hours

---

## 📚 Table of Contents

**Flash Loan Mechanics**
- [The Atomic Guarantee](#atomic-guarantee)
- [Flash Loan Providers](#flash-loan-providers)
- [Read: Aave FlashLoanLogic.sol](#read-aave-flash)
- [Read: Balancer FlashLoans](#read-balancer-flash)
- [Exercises](#day1-exercises)

**Composing Flash Loan Strategies**
- [Strategy 1: DEX Arbitrage](#dex-arbitrage)
- [Strategy 2: Flash Loan Liquidation](#flash-liquidation)
- [Strategy 3: Collateral Swap](#collateral-swap)
- [Strategy 4: Leverage/Deleverage](#leverage-deleverage)
- [Exercises](#day2-exercises)

**Security, Anti-Patterns, and the Bigger Picture**
- [Flash Loan Security for Protocol Builders](#flash-security)
- [Flash Loan Receiver Security](#receiver-security)
- [Flash Loans vs Flash Accounting](#flash-vs-accounting)
- [Governance Attacks via Flash Loans](#governance-attacks)
- [Common Mistakes](#common-mistakes)
- [Exercises](#day3-exercises)

---

## 💡 Flash Loan Mechanics

Flash loans are DeFi's most counterintuitive innovation: uncollateralized loans of unlimited size that must be repaid within a single transaction. If repayment fails, the entire transaction reverts — as if nothing happened.

This matters because it eliminates capital requirements for operations that are inherently profitable within a single atomic step. Before flash loans, liquidating an underwater Aave position required holding enough capital to repay the debt. After flash loans, anyone can liquidate any position. Before flash loans, arbitraging a price discrepancy between two DEXes required capital proportional to the opportunity. After flash loans, a developer with $0 and a smart contract can capture a $100,000 arbitrage.

Flash loans are also the primary tool used in oracle manipulation attacks (Module 3) and are integral to the liquidation flows you studied in Module 4. This module teaches you to use them offensively (arbitrage, liquidation, collateral swaps) and defend against them.

💻 **Quick Try:**

Before diving into providers and callbacks, feel the atomic guarantee on a mainnet fork:
```solidity
// In a Foundry test:
// 1. Flash-borrow 1M USDC from Balancer Vault (0x BA12222222228d8Ba445958a75a0704d566BF2C8)
// 2. In the callback, check your USDC balance — you're a temporary millionaire
// 3. Transfer amount back to the Vault
// 4. Watch it succeed. Now try returning 1 USDC less — watch the entire tx revert
// That revert IS the atomic guarantee. The million dollars never moved.
```

<a id="atomic-guarantee"></a>
### 💡 Concept: The Atomic Guarantee

A flash loan works because of Ethereum's transaction model: either every operation in a transaction succeeds, or the entire transaction reverts. The flash loan provider transfers tokens to your contract, calls your callback function, then checks that the tokens (plus a fee) have been returned. If the check fails, the whole transaction unwinds.

```
1. Your contract calls Provider.flashLoan(amount)
2. Provider transfers `amount` to your contract
3. Provider calls your contract's callback function
4. Your contract executes arbitrary logic (arbitrage, liquidation, etc.)
5. Your contract approves/transfers amount + fee back to Provider
6. Provider verifies repayment
7. If insufficient: entire transaction reverts (including step 2)
```

The key insight: from the blockchain's perspective, if repayment fails, the loan never happened. No tokens moved. No state changed. The borrower only pays gas for the failed transaction.

#### 🔍 Deep Dive: The Flash Loan Callback Flow

```
                     Single Ethereum Transaction
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  Your Contract              Flash Loan Provider             │
│  ────────────              ───────────────────              │
│       │                           │                         │
│  ①    │──── flashLoan(amount) ───→│                         │
│       │                           │                         │
│       │    ② Provider transfers   │                         │
│       │←──── amount tokens ───────│                         │
│       │                           │                         │
│       │    ③ Provider calls       │                         │
│       │←── your callback() ───────│                         │
│       │                           │                         │
│  ④    │  ┌─────────────────────┐  │                         │
│       │  │ YOUR LOGIC HERE:    │  │                         │
│       │  │ • Swap on DEX       │  │                         │
│       │  │ • Liquidate on Aave │  │                         │
│       │  │ • Collateral swap   │  │                         │
│       │  │ • Anything atomic   │  │                         │
│       │  └─────────────────────┘  │                         │
│       │                           │                         │
│  ⑤    │── approve(amount + fee) ─→│                         │
│       │                           │                         │
│       │    ⑥ Provider pulls       │                         │
│       │    amount + fee           │                         │
│       │    ✓ Repaid → tx succeeds │                         │
│       │    ✗ Short → ENTIRE TX    │                         │
│       │      REVERTS (steps 1-5   │                         │
│       │      never happened)      │                         │
│       │                           │                         │
└─────────────────────────────────────────────────────────────┘
```

**The critical property:** Steps ②-⑤ all happen within a single EVM call stack. The provider checks repayment at ⑥ — if it fails, the EVM unwinds everything. This is why flash loans are "risk-free" for the provider: they either get repaid or the loan never existed.

<a id="flash-loan-providers"></a>
### 💡 Concept: Flash Loan Providers

**Aave V3** — The original and most widely used.

Two functions:
- `flashLoanSimple(receiverAddress, asset, amount, params, referralCode)` — single asset, simpler interface, slightly cheaper gas
- `flashLoan(receiverAddress, assets[], amounts[], modes[], onBehalfOf, params, referralCode)` — multiple assets simultaneously, with the option to convert the flash loan into a regular borrow (by setting `modes[i] = 1` or `2` for variable/stable rate)

Callback: `executeOperation(asset, amount, premium, initiator, params)` must return `true`.

Fee: 0.05% (`_flashLoanPremiumTotal` = 5 bps). Waived for addresses granted the `FLASH_BORROWER` role by governance.

Premium split: A portion goes to the protocol treasury (`_flashLoanPremiumToProtocol` = 4 bps), the rest accrues to suppliers.

Liquidity: Limited to what's currently supplied and unborrowed in Aave pools. On Ethereum mainnet, this is billions of dollars across major assets.

**Balancer V2** — Zero-fee flash loans.

The Balancer Vault holds all tokens for all pools in a single contract. This consolidated liquidity is available as flash loans.

```solidity
function flashLoan(
    IFlashLoanRecipient recipient,
    IERC20[] memory tokens,
    uint256[] memory amounts,
    bytes memory userData
) external;
```

Callback: `receiveFlashLoan(tokens[], amounts[], feeAmounts[], userData)`.

Fee: **0%** (governance-set, currently zero). This makes Balancer the cheapest source for flash loans.

Security: Your callback must verify `msg.sender == vault`. Balancer's Vault holds over a billion dollars in liquidity.

**Uniswap V2 — Flash Swaps**

Uniswap V2 pairs support "optimistic transfers" — the pair sends you tokens *before* verifying the invariant. You can either:
1. Return the same tokens (a standard flash loan)
2. Return a different token (a flash swap — you receive token0 and pay back in token1)

The pair's `swap()` function sends tokens to the `to` address, then calls `uniswapV2Call(sender, amount0, amount1, data)` if `data.length > 0`. After the callback, the pair verifies the constant product invariant holds (accounting for the 0.3% fee).

Fee: Effectively ~0.3% (same as swap fee), since the invariant check includes fees.

**Uniswap V4 — Flash Accounting**

V4 doesn't have a dedicated "flash loan" function. Instead, flash loans are a natural consequence of the flash accounting system you studied in Module 2:

1. Unlock the PoolManager
2. Inside `unlockCallback`, perform any operations (swaps, liquidity changes)
3. All operations track internal deltas using transient storage
4. At the end, settle all deltas to zero

You can effectively "borrow" by creating a negative delta, using the tokens, then settling. This is more flexible than a dedicated flash loan function because it composes natively with swaps and liquidity operations — all within the same unlock context. No separate fee for the flash component; you pay whatever fees apply to the operations you perform.

**ERC-3156: The Flash Loan Standard**

[ERC-3156](https://eips.ethereum.org/EIPS/eip-3156) standardizes the flash loan interface so borrowers can write provider-agnostic code:
- `flashLoan(receiver, token, amount, data)` on the lender
- `onFlashLoan(initiator, token, amount, fee, data)` callback on the receiver
- `maxFlashLoan(token)` and `flashFee(token, amount)` for discovery

Not all providers implement ERC-3156 (Aave and Balancer have their own interfaces), but it's the standard for simpler flash loan providers. In practice, most production flash loan code targets Aave or Balancer directly because they have the deepest liquidity. ERC-3156 is most useful when building provider-agnostic tooling (e.g., a flash loan aggregator that routes to the cheapest available source) or when integrating with smaller lending protocols that implement the standard. [OpenZeppelin provides an ERC-3156 implementation](https://docs.openzeppelin.com/contracts/5.x/api/interfaces#IERC3156FlashLender) you can use as a reference.

**DAI Flash Mint** — MakerDAO's `DssFlash` module lets anyone mint *unlimited* DAI via flash loan — not from a pool, but minted from thin air and burned at the end. This is unique: the liquidity isn't constrained by pool deposits. DAI is minted in the Vat, used, and burned within the same tx. Fee: 0%. This is possible because DAI is protocol-issued (see Module 6 — CDPs mint stablecoins into existence).

> **🔗 Connection:** The flash mint concept connects to Module 6 — a CDP stablecoin can offer infinite flash liquidity because the protocol controls issuance. Your Part 2 Module 9 capstone stablecoin includes a flash mint feature, and Part 3 Module 9 (Perpetual Exchange capstone) builds on these composability patterns.

<a id="read-aave-flash"></a>
#### 📖 Read: Aave FlashLoanLogic.sol

**Source:** `aave-v3-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol`

Trace `executeFlashLoanSimple()`:

1. Validates the reserve is active and flash-loan-enabled
2. Computes premium: `amount × flashLoanPremiumTotal / 10000`
3. Transfers the requested amount to the receiver via `IAToken.transferUnderlyingTo()`
4. Calls `receiver.executeOperation(asset, amount, premium, initiator, params)`
5. Verifies the receiver returned `true`
6. Pulls `amount + premium` from the receiver (receiver must have approved the Pool)
7. Mints premium to the aToken (accrues to suppliers) and to treasury

**Key security observation:** The premium calculation happens before the callback. The receiver knows exactly how much it needs to repay. There's no reentrancy risk here because the Pool does the final pull after the callback returns.

Also read `executeFlashLoan()` (the multi-asset version). Note the `modes[]` parameter: mode 0 = repay, mode 1 = open variable debt, mode 2 = open stable debt. This enables a pattern where you flash-borrow an asset and convert it into a collateralized borrow in the same transaction — useful for collateral swaps and leverage.

<a id="read-balancer-flash"></a>
#### 📖 Read: Balancer FlashLoans

**Source:** Balancer V2 Vault `flashLoan()` implementation.

Simpler than Aave's because there are no interest rate modes. The Vault:
1. Transfers tokens to the recipient
2. Calls `receiveFlashLoan()`
3. After callback, checks that the Vault's balance of each token has increased by at least `feeAmount` (currently 0)

Balancer V3 introduces a transient unlock model similar to V4's flash accounting — the Vault must be "unlocked" and balances must be settled before the transaction ends.

#### 📖 How to Study Flash Loan Provider Code

1. **Start with the interface** — Read `IFlashLoanSimpleReceiver` (Aave) or `IFlashLoanRecipient` (Balancer). These tell you exactly what your callback must implement. Map the parameters: what data flows in, what the provider expects back.

2. **Trace the provider's flow in 3 steps** — Every flash loan provider follows the same pattern: (a) transfer tokens out, (b) call your callback, (c) verify repayment. In Aave's [FlashLoanLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/FlashLoanLogic.sol), find these three steps in `executeFlashLoanSimple()`. Note how the premium is computed before the callback — your contract knows exactly what to repay.

3. **Read the repayment verification** — This is where providers differ. Aave pulls tokens via `transferFrom` (you must approve). Balancer checks its own balance increased. Uniswap V2 verifies the constant product invariant. Understanding the verification mechanism tells you what your callback must do to succeed.

4. **Study the `modes[]` parameter** (Aave only) — In the multi-asset `flashLoan()`, mode 0 = repay, mode 1 = open variable debt, mode 2 = open stable debt. This enables "flash borrow and keep" patterns (collateral swap, leverage). This parameter doesn't exist in Balancer or Uniswap.

5. **Compare gas costs** — Deploy identical flash loans on an Aave fork vs Balancer fork. The gas difference comes from: Aave's premium calculation + aToken mint + index update vs Balancer's simpler balance check. This informs your provider choice in production.

**Don't get stuck on:** Aave's referral code system or Balancer's internal token accounting beyond the flash loan flow. Focus on the borrow → callback → repay cycle.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Explain the flash loan callback pattern"**
   - Good answer: Provider sends tokens, calls your callback, then verifies repayment
   - Great answer: It's a borrow-callback-verify pattern where atomicity guarantees zero risk for the provider. The key differences between providers: Aave uses `transferFrom` (you must approve), Balancer checks its own balance increased, Uniswap V2 verifies the constant product invariant. Aave's `modes[]` parameter lets you convert a flash loan into a collateralized borrow — that's how collateral swaps work.

2. **"How do you choose between flash loan providers?"**
   - Good answer: Compare fees — Balancer is free, Aave is 5 bps
   - Great answer: Fee is just one factor. Balancer V2 is cheapest (0%) but liquidity depends on pool composition. Aave has the deepest liquidity for major assets. Uniswap V2 is expensive (~0.3%) but available per-pair without pool dependencies. V4 flash accounting is the most flexible — no separate flash loan needed, it composes natively with swaps. For production, you'd check available liquidity across providers and route to the cheapest with sufficient depth.

**Interview Red Flags:**
- 🚩 Thinking flash loans create risk for the provider (they're zero-risk by construction)
- 🚩 Not knowing Balancer offers zero-fee flash loans
- 🚩 Confusing Uniswap V2 flash swaps with Aave-style flash loans (different repayment mechanics)

**Pro tip:** In interviews, emphasize that flash loans aren't just about arbitrage — they're a composability primitive. The collateral swap pattern (flash borrow → repay debt → withdraw → swap → redeposit → re-borrow → repay flash) is the most interview-relevant use case because it demonstrates deep understanding of lending mechanics.

<a id="day1-exercises"></a>
## 🎯 Build Exercise: Flash Loan Mechanics

**Workspace:** [`workspace/src/part2/module5/exercise1-flash-loan-receiver/`](../workspace/src/part2/module5/exercise1-flash-loan-receiver/) — starter file: [`FlashLoanReceiver.sol`](../workspace/src/part2/module5/exercise1-flash-loan-receiver/FlashLoanReceiver.sol), tests: [`FlashLoanReceiver.t.sol`](../workspace/test/part2/module5/exercise1-flash-loan-receiver/FlashLoanReceiver.t.sol)

**Exercise 1 — FlashLoanReceiver:** Build a minimal Aave V3-style flash loan receiver that borrows tokens, validates the callback (both `msg.sender` and `initiator`), approves repayment, and tracks premiums paid. Also implement a `rescueTokens` function to sweep any accidentally stuck tokens — reinforcing the "never store funds" principle.

- Implement `requestFlashLoan` (owner-only, initiates the flash loan)
- Implement `executeOperation` (callback security checks + approve repayment)
- Implement `rescueTokens` (owner-only safety net)
- Tests verify: correct premium accounting, cumulative tracking across multiple loans, callback validation, access control, and zero contract balance after every operation

**Stretch:** Build a Balancer flash loan receiver that borrows the same amount. Compare the callback pattern — Balancer checks balance increase (you transfer) vs Aave uses `transferFrom` (you approve). Verify the fee is 0.

---

## 📋 Key Takeaways: Flash Loan Mechanics

After this section, you should be able to:

- Explain the atomic guarantee (borrow → callback → repay, or entire tx reverts) and why this enables uncollateralized borrowing without trust
- Compare the 4 flash loan providers (Aave V3 0.05%, Balancer V2 0%, Uniswap V2 ~0.3%, Uniswap V4 flash accounting) and explain when you'd choose each based on fee and architecture
- Implement the correct callback interface for each provider (`executeOperation`, `receiveFlashLoan`, `uniswapV2Call`) and explain Aave's `modes[]` parameter for converting flash loans into debt positions

---

## 💡 Composing Flash Loan Strategies

💻 **Quick Try:**

Before building arbitrage contracts, see a price discrepancy with your own eyes. On a mainnet fork, query the same swap on two different DEXes:

```solidity
interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

function testSpotPriceDifference() public {
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IUniswapV2Router uniV2 = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router sushi = IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address[] memory path = new address[](2);
    path[0] = WETH;
    path[1] = USDC;

    uint256 amountIn = 10 ether; // 10 WETH

    uint256[] memory uniOut = uniV2.getAmountsOut(amountIn, path);
    uint256[] memory sushiOut = sushi.getAmountsOut(amountIn, path);

    emit log_named_uint("Uniswap V2: 10 WETH -> USDC", uniOut[1]);
    emit log_named_uint("Sushiswap:  10 WETH -> USDC", sushiOut[1]);

    // Any difference here is a potential arbitrage opportunity
    // In practice, MEV bots keep these within ~0.01% of each other
}
```

Run with `forge test --match-test testSpotPriceDifference --fork-url $ETH_RPC_URL -vv`. You'll likely see very similar prices — MEV bots keep them aligned. But during volatility, gaps appear briefly. That's where flash loan arbitrage lives.

---

<a id="dex-arbitrage"></a>
### 💡 Concept: Strategy 1: DEX Arbitrage

The classic flash loan use case: a price discrepancy between two DEXes.

**The flow:**
1. Flash-borrow Token A from Aave/Balancer
2. Swap Token A → Token B on DEX1 (where A is expensive / B is cheap)
3. Swap Token B → Token A on DEX2 (where B is expensive / A is cheap)
4. Repay flash loan + fee
5. Keep the profit (if any)

**Why this is harder than it sounds:**
- Price discrepancies are detected and captured by MEV bots within milliseconds
- Gas costs eat into thin margins
- Slippage on larger trades reduces profitability
- Frontrunning: your transaction sits in the mempool where MEV searchers can see it and extract the opportunity first (Flashbots private transactions mitigate this)

**Build: FlashLoanArbitrage**

The key architectural decision: your `executeArbitrage` function encodes the strategy parameters (which DEXs, which intermediate token, minimum profit) into bytes and passes them through the flash loan's `params` argument. The callback decodes them to execute the two-leg swap. This encode/decode pattern is how every real flash loan strategy passes information across the callback boundary.

Think about: how do you enforce that the arbitrage is actually profitable before committing? Where in the callback do you check `minProfit`? What happens to any remaining tokens after repayment?

**Workspace exercise:** The full scaffold with TODOs is in [`FlashLoanArbitrage.sol`](../workspace/src/part2/module5/exercise2-flash-loan-arbitrage/FlashLoanArbitrage.sol).

#### 🔍 Deep Dive: Arbitrage Profit Calculation

```
Scenario: WETH is $2,000 on DEX1 and $2,020 on DEX2 (1% discrepancy)
Flash borrow: 100 WETH from Balancer (0% fee)

Step 1: Sell 100 WETH on DEX2 (expensive side)
  → Receive: 100 × $2,020 = $202,000 USDC
  → After 0.3% swap fee: $202,000 × 0.997 = $201,394 USDC

Step 2: Buy WETH on DEX1 (cheap side) with enough to repay
  → Need: 100 WETH to repay flash loan
  → Cost: 100 × $2,000 = $200,000 USDC
  → After 0.3% swap fee: $200,000 / 0.997 = $200,601 USDC

Step 3: Repay flash loan
  → Return: 100 WETH to Balancer (0 fee)

Profit = $201,394 - $200,601 = $793 USDC
Gas cost ≈ ~$5-50 (depending on network)
Net profit ≈ ~$743-788

Reality check:
  - Slippage on 100 WETH ($200K) would be significant
  - MEV bots detect this in milliseconds
  - Real arb opportunities are usually < 0.1% and last < 1 block
  - Most profit goes to MEV searchers via Flashbots bundles
```

> **🔗 Connection:** MEV extraction from these opportunities is covered in depth in Part 3 Module 5 (MEV). Searchers, builders, and the PBS supply chain determine who actually captures this profit.

#### 💡 How MEV Searchers Actually Use Flash Loans

In practice, profitable flash loan arbitrage isn't done by humans submitting transactions to the mempool:

1. **Searchers** run bots that monitor pending transactions and DEX state for opportunities
2. They build a **bundle**: flash borrow → arb swaps → repay → profit, as a single transaction
3. They submit the bundle to **Flashbots Protect** or block builders directly (not the public mempool)
4. They bid most of the profit to the builder as a **tip** (often 90%+)
5. The builder includes the bundle in their block

The searcher keeps a thin margin. The builder captures most of the MEV. This is why the arbitrage profit from the example above ($793) would net the searcher maybe $50-100 after builder tips. The economics only work at scale with hundreds of opportunities per day.

<a id="flash-liquidation"></a>
### 💡 Concept: Strategy 2: Flash Loan Liquidation

You built a basic liquidation in Module 4. Now do it with zero capital:

**The flow:**
1. Identify an underwater position on Aave (HF < 1)
2. Flash-borrow the debt asset (e.g., USDC) from Balancer (0 fee) or Aave
3. Call `Pool.liquidationCall()` — repay the debt, receive collateral at discount
4. Swap the received collateral → debt asset on a DEX
5. Repay the flash loan
6. Keep the profit (liquidation bonus minus swap fees minus flash loan fee)

**Build: FlashLoanLiquidator.sol**

Implement a contract that:
- Takes flash loan from Balancer (zero fee)
- Executes Aave liquidation
- Swaps collateral to debt asset via Uniswap V3 (use exact input swap for simplicity)
- Repays Balancer
- Sends profit to caller

#### 🔍 Deep Dive: Flash Loan Liquidation Profit — Numeric Walkthrough

```
Setup:
  Borrower: 10 ETH collateral ($2,000/ETH = $20,000), 16,500 USDC debt
  ETH LT = 82.5% → HF = ($20,000 × 0.825) / $16,500 = 1.0 (exactly at threshold)
  ETH drops to $1,900 → HF = ($19,000 × 0.825) / $16,500 = 0.95 → liquidatable!
  Liquidation bonus = 5%, Close factor = 50% (HF ≥ 0.95)

Step 1: Flash borrow from Balancer (0% fee)
  Borrow: 8,250 USDC (50% of $16,500 debt)
  Cost: $0

Step 2: Call Aave liquidationCall()
  Repay: 8,250 USDC of borrower's debt
  Receive: $8,250 × 1.05 / $1,900 = 4.5592 ETH (includes 5% bonus)

Step 3: Swap ETH → USDC on Uniswap V3 (0.3% fee pool)
  Sell: 4.5592 ETH at $1,900
  Gross: 4.5592 × $1,900 = $8,662.48
  After 0.3% swap fee: $8,662.48 × 0.997 = $8,636.49 USDC

Step 4: Repay Balancer flash loan
  Repay: 8,250 USDC (0% fee)

Profit = $8,636.49 - $8,250 = $386.49 USDC
Gas cost ≈ ~$5-30
Net profit ≈ ~$356-381

Breakeven analysis:
  Minimum liquidation bonus for profitability:
  bonus > swap_fee / (1 - swap_fee) = 0.003 / 0.997 ≈ 0.3%
  With Aave's 5% bonus, this is profitable even with significant slippage.

Using Aave flash loan instead (0.05% fee):
  Flash loan cost = 8,250 × 0.0005 = $4.13
  Net profit = $386.49 - $4.13 = $382.36
  Savings from Balancer: only $4.13 — but at scale, this adds up.
```

Test on mainnet fork:
- Set up an Aave position near liquidation (supply ETH, borrow USDC at max LTV)
- Use `vm.mockCall` to drop ETH price below liquidation threshold
- Execute the flash loan liquidation
- Verify: profit = (collateral seized × collateral price × (1 + liquidation bonus)) - debt repaid - swap fees

<a id="collateral-swap"></a>
### 💡 Concept: Strategy 3: Collateral Swap

A user has ETH collateral backing a USDC loan on Aave, but wants to switch to WBTC collateral without closing the position.

**Without flash loans:** Repay entire USDC debt → withdraw ETH → swap ETH to WBTC → deposit WBTC → re-borrow USDC. Requires capital to repay the debt first.

**With flash loans:**
1. Flash-borrow USDC equal to the debt
2. Repay the entire USDC debt on Aave
3. Withdraw ETH collateral (now possible because debt is zero)
4. Swap ETH → WBTC on Uniswap
5. Deposit WBTC as new collateral on Aave
6. Re-borrow USDC from Aave (against new collateral)
7. Repay flash loan with the re-borrowed USDC + use existing USDC for the premium

This is Aave's "liquidity switch" pattern — one of the primary production uses of flash loans.

**Build: CollateralSwap.sol**

This is the most complex composition — and the most interview-relevant. It touches lending (repay, withdraw, deposit, borrow) and swapping, all within a single flash loan callback.

**The 6-step callback pattern:**

```
Flash borrow debt asset (e.g., USDC)
  │
  ├─ Step 1: Repay user's entire debt on lending pool
  │           (we have the tokens from the flash loan)
  │
  ├─ Step 2: Pull user's aTokens, then withdraw old collateral
  │           (withdraw burns aTokens from msg.sender)
  │
  ├─ Step 3: Swap old collateral → new collateral on DEX
  │
  ├─ Step 4: Deposit new collateral into lending pool for user
  │           (supply on behalf of user — they receive aTokens)
  │
  ├─ Step 5: Borrow debt asset on behalf of user (credit delegation)
  │           to cover the flash loan repayment
  │
  └─ Step 6: Approve flash pool to pull amount + premium
```

**Key prerequisite:** The user must set up two delegations before calling this contract:
1. `aToken.approve(collateralSwap, amount)` — so the contract can withdraw their collateral
2. `variableDebtToken.approveDelegation(collateralSwap, amount)` — so the contract can borrow on their behalf

This delegation pattern is critical for interview discussions — it shows you understand Aave's credit delegation system.

**Workspace exercise:** The full scaffold with TODOs is in [`CollateralSwap.sol`](../workspace/src/part2/module5/exercise3-collateral-swap/CollateralSwap.sol).

<a id="leverage-deleverage"></a>
### 💡 Concept: Strategy 4: Leverage/Deleverage in One Transaction

**Leveraging up:** A user wants 3x long ETH exposure.
1. Flash-borrow ETH
2. Deposit all ETH as collateral on Aave
3. Borrow USDC against the collateral
4. Swap USDC → ETH
5. Deposit additional ETH as collateral
6. Repeat steps 3-5 (or do it in calculated amounts)
7. Final borrow covers the flash loan repayment

In practice, you calculate the exact amounts needed for the desired leverage ratio and do it in one step rather than looping.

**Deleveraging:** Reverse the process — flash-borrow to repay debt, withdraw collateral, swap to repay the flash loan.

#### 🔍 Deep Dive: Leverage — Numeric Walkthrough

```
Goal: 3x long ETH exposure starting with 10 ETH ($2,000/ETH = $20,000)
Aave ETH: max LTV = 80% (borrow limit), LT = 82.5% (liquidation threshold)
Remember: you BORROW up to max LTV, but HF uses LT (see Module 4).

Without flash loans (manual looping):
  Round 1: Deposit 10 ETH → Borrow $16,000 USDC → Buy 8 ETH
  Round 2: Deposit 8 ETH → Borrow $12,800 USDC → Buy 6.4 ETH
  Round 3: Deposit 6.4 ETH → Borrow $10,240 USDC → Buy 5.12 ETH
  ... (converges after many rounds, each with gas + swap fees)

With flash loans (one transaction):
  Target: 30 ETH total exposure (3x of 10 ETH)
  Need to deposit: 30 ETH
  Need to borrow: 20 ETH worth of USDC = $40,000 USDC
  Borrow check: $40,000 / $60,000 = 66.7% < 80% max LTV ✓ (within borrow limit)
  Health factor: ($60,000 × 0.825) / $40,000 = 1.24 ✓ (healthy)

Step 1: Flash-borrow 20 ETH from Balancer (0% fee)
  Now holding: 10 (own) + 20 (borrowed) = 30 ETH

Step 2: Deposit all 30 ETH into Aave
  Collateral: 30 ETH ($60,000)

Step 3: Borrow $40,000 USDC from Aave against the collateral
  Debt: $40,000 USDC
  HF = ($60,000 × 0.825) / $40,000 = 1.24

Step 4: Swap $40,000 USDC → ~19.94 ETH on Uniswap V3 (0.3% fee)
  $40,000 / $2,000 = 20 ETH × 0.997 = 19.94 ETH

Step 5: Repay Balancer flash loan (20 ETH)
  Need: 20 ETH, Have: 19.94 ETH
  Shortfall: 0.06 ETH ($120) — the swap fee cost

  Fix: Borrow slightly more USDC in Step 3 to cover swap fees:
  Borrow $40,120 USDC → Swap → 20.00 ETH → Repay → Done.
  Updated HF = ($60,000 × 0.825) / $40,120 = 1.23 (still healthy)

Result:
  Position: 30 ETH collateral, $40,120 debt
  Effective leverage: ~3x
  Cost: One tx gas + $120 in swap fees
  If ETH +10%: Position gains $6,000 (30% on your 10 ETH)
  If ETH -10%: Position loses $6,000 (30% on your 10 ETH)
  Liquidation price: ~$1,621 ETH (-19% from $2,000)
    → HF=1.0 when 30 × price × 0.825 = $40,120 → price = $1,621
```

**Why flash loans matter here:** Without them, you'd need 5+ loop iterations (each with gas costs and swap slippage). With a flash loan, it's a single atomic operation — cheaper, cleaner, and no partial exposure during intermediate steps.

<a id="day2-exercises"></a>
## 🎯 Build Exercise: Flash Loan Strategies

**Workspace:** [`workspace/src/part2/module5/exercise2-flash-loan-arbitrage/`](../workspace/src/part2/module5/exercise2-flash-loan-arbitrage/) — starter file: [`FlashLoanArbitrage.sol`](../workspace/src/part2/module5/exercise2-flash-loan-arbitrage/FlashLoanArbitrage.sol), tests: [`FlashLoanArbitrage.t.sol`](../workspace/test/part2/module5/exercise2-flash-loan-arbitrage/FlashLoanArbitrage.t.sol) | Also: [`CollateralSwap.sol`](../workspace/src/part2/module5/exercise3-collateral-swap/CollateralSwap.sol), tests: [`CollateralSwap.t.sol`](../workspace/test/part2/module5/exercise3-collateral-swap/CollateralSwap.t.sol)

**Exercise 2 — FlashLoanArbitrage:** Build a flash loan arbitrage contract that captures price discrepancies between two DEXs. This exercises the full composition pattern: flash borrow, encode/decode strategy params through the callback bytes, execute two-leg swap, enforce minimum profit, and sweep profit to the caller.

- Implement `executeArbitrage` (encode params, request flash loan, sweep profit)
- Implement `executeOperation` (decode params, two DEX swaps, profitability check, approve repayment)
- Tests verify: profitable arb with 1% spread, `minProfit` enforcement, revert when spread is too small, callback security, fuzz testing across varying borrow amounts

**Exercise 3 — CollateralSwap:** Build the most complex flash loan composition: switch a user's lending position from one collateral to another in a single atomic transaction. This is Aave's "liquidity switch" pattern and the most interview-relevant use case.

- Implement `swapCollateral` (encode SwapParams, request flash loan)
- Implement `executeOperation` (6-step callback: repay debt, pull aTokens + withdraw, swap on DEX, deposit new collateral, borrow on behalf of user via credit delegation, approve repayment)
- Tests verify: complete position migration (old collateral to new), correct debt accounting (original + premium), prerequisite delegation checks, callback security

---

## 📋 Key Takeaways: Flash Loan Strategies

After this section, you should be able to:

- Trace all 4 flash loan strategies step by step: DEX arbitrage (borrow → swap DEX1 → swap DEX2 → repay), flash liquidation (borrow debt → liquidate → swap collateral → repay), collateral swap (borrow → repay debt → withdraw → swap → deposit → re-borrow → repay), and leverage (borrow → deposit → borrow → deposit → repay)
- Calculate profitability for a flash loan arbitrage: output from DEX2 minus flash loan amount minus fees minus gas, and explain why MEV searchers capture 90%+ of profit via builder tips
- Design a collateral swap that atomically moves a user's Aave position from one collateral type to another without ever being undercollateralized

---

## ⚠️ Security, Anti-Patterns, and the Bigger Picture

<a id="flash-security"></a>
#### ⚠️ Flash Loan Security for Protocol Builders

Flash loans don't create vulnerabilities — they *democratize access to capital* for exploiting existing vulnerabilities. But as a protocol builder, you need to design for a world where any attacker has access to unlimited capital within a single transaction.

**Rule 1: Never use spot prices as oracle.** (Module 3 — reinforced here.) Flash loans make spot price manipulation essentially free. The attacker borrows millions, moves the price, exploits your protocol, and returns the loan. Cost to attacker: just gas.

**Rule 2: Be careful with any state that can be manipulated and read in the same transaction.** This includes:
- DEX reserve ratios (spot prices)
- Contract token balances (donation attacks)
- Share prices in vaults based on `totalAssets() / totalShares()`
- Governance voting power based on current token holdings

**Rule 3: Time-based defenses.** If an action depends on a value that can be flash-manipulated, require that the value was established in a *previous* block. TWAPs work because they span multiple blocks. Governance timelocks work because proposals can't be executed immediately.

**Rule 4: Use reentrancy guards on functions that manipulate critical state.** Flash loans involve external calls (the callback). If your protocol interacts with flash-loaned funds, ensure reentrant calls can't exploit intermediate states.

#### 🔍 Deep Dive: The bZx Attacks (February 2020) — Flash Loans' Debut

The bZx attacks were the first major flash loan exploits, demonstrating what "unlimited capital in one tx" means for protocol security:

```
Attack 1 ($350K, Feb 14, 2020):
┌──────────────────────────────────────────────────────────┐
│ 1. Flash-borrow 10,000 ETH from dYdX                    │
│ 2. Deposit 5,500 ETH in Compound as collateral           │
│ 3. Borrow 112 WBTC from Compound                         │
│ 4. Send 1,300 ETH to bZx to open 5x short ETH/BTC      │
│    → bZx swaps on Uniswap, crashing ETH/BTC price       │
│ 5. Swap 112 WBTC → ETH on Uniswap at the crashed price  │
│    → Got MORE ETH than 112 WBTC was worth before         │
│ 6. Repay Compound, repay dYdX, keep profit               │
└──────────────────────────────────────────────────────────┘

What went wrong: bZx used Uniswap spot price as its oracle.
The attacker manipulated that price with borrowed capital.
Cost to attacker: gas only (~$8). Profit: $350,000.
```

**The lesson for protocol builders:** This attack didn't exploit a bug in flash loans — it exploited bZx's reliance on a spot price oracle (Rule 1 above). Flash loans just made it free to execute. Every oracle manipulation attack you'll see in Module 3 postmortems follows this pattern: flash borrow → manipulate price → exploit protocol → repay.

> **📖 Study tip — Tracing real exploits:** Use [Tenderly](https://dashboard.tenderly.co/tx/mainnet/) or [Phalcon by BlockSec](https://app.blocksec.com/explorer) to trace historical exploit transactions step-by-step. Paste the tx hash and you'll see every internal call, state change, and token transfer in order. For the bZx attack, trace [this tx](https://etherscan.io/tx/0xb5c8bd9430b6cc87a0e2fe110ece6bf527fa4f170a4bc8cd032f768fc5219838) — you'll see the flash borrow from dYdX, the Compound interactions, the Uniswap price manipulation, and the profitable unwind all in a single call tree. This is the fastest way to internalize how flash loan compositions work in production.

<a id="receiver-security"></a>
#### ⚠️ Flash Loan Receiver Security

When building flash loan receivers (your callback contracts), guard against:

**Griefing attack:** Never store funds in your flash loan receiver contract between transactions. An attacker could initiate a flash loan using your receiver as the target, and your stored funds would be used to repay the loan.

**Initiator validation:** In `executeOperation`, check that `initiator == address(this)` (or your expected caller). Without this, anyone can initiate a flash loan that calls your receiver, potentially manipulating your contract's state.

```solidity
function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
) external override returns (bool) {
    require(msg.sender == address(POOL), "Caller must be Pool");
    require(initiator == address(this), "Initiator must be this contract");
    // ... your logic
}
```

**Parameter validation:** The `params` bytes are arbitrary and user-controlled. If you decode them into addresses or amounts, validate everything. An attacker could craft params that route funds to their own address.

<a id="flash-vs-accounting"></a>
### 💡 Concept: Flash Loans vs Flash Accounting: The Evolution

Flash loans (Aave, Balancer V2) are a specific feature: borrow tokens, use them, return them.

Flash accounting (Uniswap V4, Balancer V3) is a generalized pattern: all operations within an unlock context track internal deltas, and only net balances are settled. Flash loans are a *subset* of what flash accounting enables.

The evolution:
- **2020:** Flash loans introduced by Aave — revolutionary but limited to borrow-use-repay
- **2021-23:** Uniswap V2/V3 flash swaps — flash loans built into DEX operations
- **2024-25:** V4 flash accounting + [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) transient storage — the pattern becomes the architecture. No separate "flash loan" feature needed; the entire interaction model is flash-native

As a protocol builder, flash accounting is the pattern to understand deeply. It's more gas-efficient, more composable, and more flexible than dedicated flash loan functions. You'll see this pattern adopted by more protocols going forward.

<a id="governance-attacks"></a>
#### ⚠️ Governance Attacks via Flash Loans

Some governance tokens allow voting based on current token holdings at the time of the vote. An attacker can:
1. Flash-borrow governance tokens
2. Vote on a malicious proposal (or create and immediately vote on one)
3. Return the tokens

**Defenses:**
- **Snapshot-based voting:** Voting power is determined by holdings at a specific past block, not the current block. Flash-borrowed tokens have zero voting power because they weren't held at the snapshot block.
- **Timelocks:** Even if a proposal passes, it can't execute for N days, giving the community time to respond.
- **Quorum requirements:** High quorum thresholds make it expensive to flash-borrow enough tokens to pass a proposal.

Most modern governance systems (OpenZeppelin Governor, Compound Governor Bravo) use snapshot voting, making this attack vector largely mitigated. But be aware of it when evaluating protocols with simpler governance.

#### 📋 Flash Loan Fee Comparison

| Provider | Fee | Multi-asset | Liquidity Source | Fee Waiver |
|----------|-----|-------------|-----------------|------------|
| Aave V3 | 0.05% (5 bps) | Yes (`flashLoan`) | Supply pools | FLASH_BORROWER role |
| Balancer V2 | 0% | Yes | All Vault pools | N/A (already free) |
| Uniswap V2 | ~0.3% | Per-pair | Pair reserves | No |
| Uniswap V4 | 0% (flash accounting) | Native | PoolManager | N/A |
| Compound V3 | N/A | N/A | N/A | No flash loan function |

**Practical choice:** For pure flash loans, Balancer V2 (zero fee) is optimal when it has sufficient liquidity in the asset you need. Aave V3 for maximum liquidity and multi-asset borrows. Uniswap V4 flash accounting for operations that combine swaps with temporary borrowing.

#### 🔍 Deep Dive: Provider Repayment Mechanisms Compared

```
How each provider verifies you repaid:

Aave V3:
  callback returns → Pool calls transferFrom(receiver, pool, amount+premium)
  You MUST approve the Pool before callback returns.
  Premium goes to: aToken holders (suppliers) + protocol treasury.

Balancer V2:
  callback returns → Vault checks: balanceOf(vault) ≥ pre_balance + feeAmount
  You MUST transfer tokens TO the Vault inside your callback.
  No approval needed — direct transfer.

Uniswap V2:
  callback returns → Pair verifies: k_new ≥ k_old (constant product with fee)
  You can repay in EITHER token (flash swap).
  The 0.3% fee is implicit in the invariant check.

Uniswap V4 / Balancer V3:
  unlockCallback returns → Manager checks: all deltas == 0
  You settle via PoolManager.settle() or Vault.settle().
  No separate "flash loan" — it's native to the delta system.

Key difference:
  Aave/Balancer V2: explicit "flash loan" as a feature
  V4/Balancer V3: flash borrowing is emergent from the accounting model
```

<a id="day3-exercises"></a>
## 🎯 Build Exercise: Flash Loan Security

**Workspace:** [`workspace/src/part2/module5/exercise4-vault-donation/`](../workspace/src/part2/module5/exercise4-vault-donation/) — starter file: [`VaultDonationAttack.sol`](../workspace/src/part2/module5/exercise4-vault-donation/VaultDonationAttack.sol), tests: [`VaultDonationAttack.t.sol`](../workspace/test/part2/module5/exercise4-vault-donation/VaultDonationAttack.t.sol)

**Exercise 4 — VaultDonationAttack:** Build a flash loan-powered vault donation attack that exploits the classic ERC-4626 share price inflation vulnerability. This puts you in the attacker's shoes to understand why `balanceOf`-based asset accounting is dangerous and why the virtual shares/assets offset defense exists.

- Implement `executeAttack` (encode params, request flash loan, sweep profit)
- Implement `executeOperation` (5-step attack: deposit 1 wei to become sole shareholder, donate remaining tokens to inflate share price, trigger victim's harvest that rounds to 0 shares, withdraw everything, approve repayment)
- Tests verify: attacker profits ~4,995 USDC from 5,000 USDC victim, victim gets 0 shares and 0 balance, vault is empty after withdrawal, attack contract holds nothing, flash pool gains premium

**Stretch: Governance attack simulation.** Deploy a simple governance contract with non-snapshot voting. Show how a flash loan can pass a malicious proposal. Then deploy an OpenZeppelin Governor with snapshot voting and verify the attack fails.

**Stretch: Multi-provider composition.** Build a contract that nests flash loans from different providers (e.g., Balancer + Aave). This tests your ability to manage nested callbacks and track which repayment is owed to which provider.

---

## 📋 Key Takeaways: Flash Loan Security

After this section, you should be able to:

- Apply the protocol builder defense framework: never rely on same-tx-manipulable values (spot prices, `balanceOf`, share ratios), use previous-block values (TWAPs, snapshots), and design assuming every user has unlimited temporary capital
- Implement the 3 critical receiver security checks: validate `msg.sender` is the lending pool, validate `initiator` is your own contract, and never store funds in the receiver between transactions
- Explain why flash accounting (V4, Balancer V3) is replacing traditional flash loans: delta tracking + end-of-transaction settlement is more gas efficient and composable
- Describe a governance flash loan attack (borrow governance tokens → vote → return) and the defenses: snapshot voting power at proposal creation block, timelocks

#### 💼 Job Market Context — Module-Level Interview Prep

**What DeFi teams expect you to know:**

1. **"How should your protocol defend against flash loan attacks?"**
   - Good answer: Use TWAP oracles instead of spot prices
   - Great answer: Flash loans don't create vulnerabilities — they eliminate capital barriers for exploiting existing ones. The defense framework: (1) never rely on values that can be manipulated within a single tx (spot prices, balanceOf, share ratios), (2) use values established in previous blocks (TWAPs, snapshots), (3) for governance, snapshot voting power at proposal creation block, (4) for vaults, use virtual shares/assets offset to prevent donation-based share inflation. Design assuming every user has infinite temporary capital.

2. **"Walk through a flash loan liquidation end to end"**
   - Good answer: Borrow the debt asset, repay the position, receive collateral, sell it, repay the loan
   - Great answer: Flash borrow USDC from Balancer (0 fee). Call `Pool.liquidationCall(collateral, debt, user, debtToCover, receiveAToken=false)` — this repays the user's debt and sends you the collateral at the liquidation bonus discount. Swap collateral → USDC via Uniswap V3 exact input. Repay Balancer. Profit = `collateral × price × (1 + bonus) - debtRepaid - swapFees`. The key insight: you choose Balancer over Aave to save 5 bps, and you set `receiveAToken=false` to get the underlying directly for the swap.

**Interview Red Flags:**
- 🚩 Thinking flash loans are only useful for arbitrage (most production uses are liquidation and collateral management)
- 🚩 Not knowing that flash accounting (V4/Balancer V3) is replacing dedicated flash loan functions
- 🚩 Building a protocol without considering flash-loan-amplified attack vectors in the threat model
- 🚩 Storing funds in a flash loan receiver contract (griefing vector)

**Pro tip:** If asked to design a liquidation system in an interview, mention that flash loan compatibility is a feature, not a bug. MakerDAO Liquidation 2.0 was explicitly designed to be flash-loan compatible — Dutch auctions with instant settlement let liquidators use flash loans, which means more competition, better prices, and less bad debt. A protocol that's "flash loan resistant" for liquidations is actually worse off.

---

<a id="common-mistakes"></a>
## ⚠️ Common Mistakes

**Mistake 1: Not validating `msg.sender` in the callback**

```solidity
// ❌ WRONG — anyone can call this function directly
function executeOperation(
    address asset, uint256 amount, uint256 premium,
    address initiator, bytes calldata params
) external returns (bool) {
    // attacker calls this directly, initiator = whatever they want
    _doSensitiveOperation(params);
    return true;
}

// ✅ CORRECT — validate both msg.sender AND initiator
function executeOperation(
    address asset, uint256 amount, uint256 premium,
    address initiator, bytes calldata params
) external returns (bool) {
    require(msg.sender == address(POOL), "Only Pool");
    require(initiator == address(this), "Only self-initiated");
    _doSensitiveOperation(params);
    return true;
}
```

Both checks are required: `msg.sender` confirms the lending pool is calling you (not an arbitrary contract), and `initiator` confirms *your* contract requested the flash loan (not someone else using your callback as a target).

**Mistake 2: Storing funds in the receiver contract**

```solidity
// ❌ WRONG — contract holds USDC between transactions
contract MyFlashReceiver is IFlashLoanSimpleReceiver {
    function deposit(uint256 amount) external {
        USDC.transferFrom(msg.sender, address(this), amount);
    }

    function executeOperation(...) external returns (bool) {
        // Uses stored USDC + flash loaned amount for strategy
    }
}
// Attacker initiates a flash loan targeting YOUR contract
// → Pool sends tokens to your contract
// → Your callback runs with attacker-controlled params
// → Even if callback fails, attacker can try different params
```

```solidity
// ✅ CORRECT — pull funds in the same tx, never hold between txs
function executeArbitrage(...) external {
    USDC.transferFrom(msg.sender, address(this), seedAmount);
    POOL.flashLoanSimple(address(this), USDC, amount, params, 0);
    USDC.transfer(msg.sender, USDC.balanceOf(address(this)));
    // Contract balance returns to 0 after every tx
}
```

**Mistake 3: Forgetting to approve repayment (Aave)**

```solidity
// ❌ WRONG — Aave will revert because it can't pull the repayment
function executeOperation(...) external returns (bool) {
    _doStrategy();
    return true;  // Returns true but Pool's transferFrom fails
}

// ✅ CORRECT — approve before returning
function executeOperation(
    address asset, uint256 amount, uint256 premium, ...
) external returns (bool) {
    _doStrategy();
    IERC20(asset).approve(address(POOL), amount + premium);
    return true;
}
```

Aave uses `transferFrom` to pull the repayment *after* your callback returns. Balancer uses balance checks instead (you `transfer` inside the callback). Mixing up these patterns is a common source of reverts.

**Mistake 4: Using flash loans for operations that don't need atomicity**

Flash loans add complexity (callback architecture, approval management, extra gas). If you already have the capital and don't need atomicity, a simple multi-step transaction or even multiple transactions may be simpler and cheaper. Flash loans shine when: (1) you don't have the capital, or (2) you need the entire operation to succeed or fail atomically (e.g., you don't want to repay debt and then fail on the swap, leaving you exposed).

---

## 🔗 Cross-Module Concept Links

### ← Backward References (Part 1 + Modules 1–4)

| Source | Concept | How It Connects |
|--------|---------|-----------------|
| Part 1 Module 1 | Custom errors | Flash loan receivers use custom errors for initiator validation, repayment failures |
| Part 1 Module 2 | Transient storage / [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) | V4 flash accounting uses TSTORE/TLOAD for delta tracking — flash loans become emergent from the accounting model |
| Part 1 Module 3 | Permit / Permit2 | Gasless approvals in flash loan callbacks — approve repayment without separate tx |
| Part 1 Module 5 | Fork testing / `vm.mockCall` | Essential for testing flash loan strategies against real Aave/Balancer/Uniswap liquidity on mainnet forks |
| Part 1 Module 6 | Proxy patterns | Aave Pool proxy delegates to FlashLoanLogic library; Balancer Vault is a single immutable entry point |
| Module 1 | SafeERC20 / token transfers | Safe token handling in callbacks — approve patterns differ between providers (Aave: approve, Balancer: transfer) |
| Module 2 | AMM swaps / price impact | DEX swaps are the core operation inside most flash loan strategies (arbitrage, liquidation collateral disposal) |
| Module 2 | Flash accounting (V4) | V4 doesn't have dedicated flash loans — flash borrowing is emergent from the delta tracking system |
| Module 3 | Oracle manipulation threat model | Flash loans make spot price manipulation free — the entire oracle attack surface assumes flash loan access |
| Module 3 | TWAP / Chainlink defense | Time-based oracles resist flash loan manipulation because they span multiple blocks |
| Module 4 | Liquidation mechanics / health factor | Flash loan liquidation: borrow debt asset → liquidate → swap collateral → repay — zero-capital liquidation |
| Module 4 | Collateral swap / leverage | Flash borrow → repay debt → withdraw → swap → redeposit → re-borrow → repay flash — Aave's "liquidity switch" |

### → Forward References (Modules 6–9 + Part 3)

| Target | Concept | How Flash Loan Knowledge Applies |
|--------|---------|----------------------------------|
| Module 6 (Stablecoins) | DAI flash mint | Unlimited flash minting from CDP-issued stablecoins — infinite liquidity because the protocol controls issuance |
| Module 6 (Stablecoins) | Liquidation 2.0 | MakerDAO Dutch auctions designed for flash loan compatibility — more competition, better prices, less bad debt |
| Module 7 (Yield/Vaults) | ERC-4626 inflation attack | Flash loans amplify donation attacks on vault share prices — virtual shares/assets offset is the defense |
| Module 8 (Security) | Attack simulation | Flash-loan-amplified attack scenarios as primary threat model for invariant testing |
| Module 9 (Stablecoin Capstone) | Flash mint | Capstone stablecoin protocol includes ERC-3156-adapted flash mint — CDP-issued tokens can offer infinite flash liquidity |
| Part 3 Module 5 (MEV) | Searcher strategies | Flash loan arbitrage profits captured by MEV searchers via Flashbots bundles; builder tips consume 90%+ of profit |
| Part 3 Module 8 (Governance) | Governance attacks | Flash loan voting attacks and snapshot-based voting defense; quorum requirements |
| Part 3 Module 9 (Capstone) | Perpetual Exchange | Capstone perp exchange integrates flash loan patterns for liquidation and MEV strategies learned throughout Part 3 |

---

## 📖 Production Study Order

Study these codebases in order — each builds on the previous one's patterns:

| # | Repository | Why Study This | Key Files |
|---|-----------|----------------|-----------|
| 1 | [Aave V3 FlashLoanLogic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/FlashLoanLogic.sol) | The most widely used flash loan provider — premium calculation, callback verification, `modes[]` parameter | `contracts/protocol/libraries/logic/FlashLoanLogic.sol`, `contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol` |
| 2 | [Balancer V2 Vault](https://github.com/balancer/balancer-v2-monorepo/tree/master/pkg/vault) | Zero-fee flash loans from consolidated vault liquidity — simpler callback, balance-based verification | `pkg/vault/contracts/Vault.sol` (search `flashLoan`), `pkg/interfaces/contracts/vault/IFlashLoanRecipient.sol` |
| 3 | [Uniswap V2 Pair](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) | Flash swaps — optimistic transfers with constant product verification; repay in either token | `contracts/UniswapV2Pair.sol` (search `swap`, `uniswapV2Call`) |
| 4 | [MakerDAO DssFlash](https://github.com/makerdao/dss-flash) | Flash mint pattern — unlimited DAI minted from thin air, burned at end of tx; zero-fee | `src/flash.sol` |
| 5 | [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) | Flash accounting — no dedicated flash loan, borrowing is emergent from delta tracking + transient storage | `src/PoolManager.sol` (search `unlock`, `settle`), `src/libraries/TransientStateLibrary.sol` |
| 6 | [ERC-3156 Reference](https://github.com/albertocuestacanada/ERC3156) | The flash loan standard interface — provider-agnostic borrower code | `contracts/interfaces/IERC3156FlashLender.sol`, `contracts/interfaces/IERC3156FlashBorrower.sol` |

**Reading strategy:** Start with Aave's FlashLoanLogic — trace `executeFlashLoanSimple()` to understand the canonical borrow → callback → verify pattern. Then Balancer for the simpler balance-check approach. Uniswap V2 shows flash swaps (repay in a different token). MakerDAO's DssFlash shows flash minting — a fundamentally different model. V4's PoolManager shows the future: flash borrowing as emergent behavior from delta accounting.

---

## 📚 Resources

**Aave flash loans:**
- [Developer guide](https://aave.com/docs/aave-v3/guides/flash-loans)
- [FlashLoanLogic.sol source](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/FlashLoanLogic.sol)
- [Cyfrin Aave V3 flash loan lesson](https://updraft.cyfrin.io/courses/aave-v3/contract-architecture/flash-loan)

**Balancer flash loans:**
- [V2 documentation](https://docs-v2.balancer.fi/reference/contracts/flash-loans.html)
- [V3 documentation](https://docs.balancer.fi/concepts/vault/flash-loans.html)

**Uniswap flash swaps/accounting:**
- [V2 flash swaps](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps)
- [V4 flash accounting](https://docs.uniswap.org/contracts/v4/concepts/flash-accounting)

**Flash loan attacks and security:**
- [Cyfrin — Flash loan attack patterns](https://www.cyfrin.io/blog/price-oracle-manipulation-attacks-with-examples)
- [RareSkills — Flash loan guide](https://rareskills.io/post/flash-loan)
- [samczsun — Taking undercollateralized loans for fun and for profit](https://samczsun.com/taking-undercollateralized-loans-for-fun-and-for-profit/) (classic)

---

**Navigation:** [← Module 4: Lending](4-lending.md) | [Module 6: Stablecoins & CDPs →](6-stablecoins-cdps.md)

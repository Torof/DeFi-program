# Part 2 — Module 5: Flash Loans

**Duration:** ~3 days (3–4 hours/day)
**Prerequisites:** Modules 1–4 (especially AMMs and lending)
**Pattern:** Concept → Read provider implementations → Build multi-step compositions → Security analysis
**Builds on:** Module 2 (AMM swaps for arbitrage), Module 4 (liquidation mechanics for flash loan liquidation)
**Used by:** Module 8 (flash-loan-amplified attack patterns), Module 9 (integration capstone flash liquidation bot)

---

## Why Flash Loans Are a Foundational Primitive

Flash loans are DeFi's most counterintuitive innovation: uncollateralized loans of unlimited size that must be repaid within a single transaction. If repayment fails, the entire transaction reverts — as if nothing happened.

This matters because it eliminates capital requirements for operations that are inherently profitable within a single atomic step. Before flash loans, liquidating an underwater Aave position required holding enough capital to repay the debt. After flash loans, anyone can liquidate any position. Before flash loans, arbitraging a price discrepancy between two DEXes required capital proportional to the opportunity. After flash loans, a developer with $0 and a smart contract can capture a $100,000 arbitrage.

Flash loans are also the primary tool used in oracle manipulation attacks (Module 3) and are integral to the liquidation flows you studied in Module 4. This module teaches you to use them offensively (arbitrage, liquidation, collateral swaps) and defend against them.

---

## Day 1: Flash Loan Mechanics

### The Atomic Guarantee

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

### Flash Loan Providers

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

### Read: Aave FlashLoanLogic.sol

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

### Read: Balancer FlashLoans

**Source:** Balancer V2 Vault `flashLoan()` implementation.

Simpler than Aave's because there are no interest rate modes. The Vault:
1. Transfers tokens to the recipient
2. Calls `receiveFlashLoan()`
3. After callback, checks that the Vault's balance of each token has increased by at least `feeAmount` (currently 0)

Balancer V3 introduces a transient unlock model similar to V4's flash accounting — the Vault must be "unlocked" and balances must be settled before the transaction ends.

### Exercise

**Exercise 1:** Build a minimal Aave V3 flash loan receiver. On a mainnet fork:
- Flash-borrow 1,000,000 USDC
- In the callback, simply approve and return the amount + premium
- Verify the transaction succeeds and your contract paid exactly the premium
- Log the premium amount to confirm the fee

**Exercise 2:** Build a Balancer flash loan receiver that borrows the same 1,000,000 USDC. Compare gas costs with the Aave version. Verify the fee is 0.

**Exercise 3:** Build a Uniswap V2 flash swap receiver. Flash-borrow WETH from a WETH/USDC pair. In the callback, verify you received the WETH, then send USDC (equivalent value + 0.3% fee) back to the pair. Verify the invariant is maintained.

---

## Day 2: Composing Flash Loan Strategies

### Strategy 1: DEX Arbitrage

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

**Build: SimpleArbitrage.sol**

```solidity
contract SimpleArbitrage is IFlashLoanSimpleReceiver {
    function executeArbitrage(
        address flashLoanProvider,
        address tokenA,
        uint256 amount,
        address dex1Router,
        address dex2Router,
        address tokenB,
        uint256 minProfit
    ) external { ... }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // Decode params: dex1Router, dex2Router, tokenB, minProfit
        // Swap asset → tokenB on dex1
        // Swap tokenB → asset on dex2
        // Verify: balance >= amount + premium + minProfit
        // Approve Pool for amount + premium
        return true;
    }
}
```

Test on a mainnet fork by deploying two Uniswap V2 pools with deliberately different prices. Execute the arbitrage and verify profit.

### Strategy 2: Flash Loan Liquidation

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

Test on mainnet fork:
- Set up an Aave position near liquidation (supply ETH, borrow USDC at max LTV)
- Use `vm.mockCall` to drop ETH price below liquidation threshold
- Execute the flash loan liquidation
- Verify: profit = (collateral seized × collateral price × (1 + liquidation bonus)) - debt repaid - swap fees

### Strategy 3: Collateral Swap

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

Implement and test. This is the most complex composition: it touches lending (repay, withdraw, deposit, borrow) and swapping, all within a single flash loan callback.

### Strategy 4: Leverage/Deleverage in One Transaction

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

### Exercise

**Exercise:** Build at least two of the four strategies above. For each, write tests that verify:
- The flash loan is fully repaid
- The strategy is profitable (or at least demonstrates the correct flow)
- The strategy reverts cleanly if conditions aren't met (e.g., arbitrage isn't profitable enough to cover fees)
- Edge cases: what happens if the DEX doesn't have enough liquidity for the swap?

---

## Day 3: Security, Anti-Patterns, and the Bigger Picture

### Flash Loan Security for Protocol Builders

Flash loans don't create vulnerabilities — they *democratize access to capital* for exploiting existing vulnerabilities. But as a protocol builder, you need to design for a world where any attacker has access to unlimited capital within a single transaction.

**Rule 1: Never use spot prices as oracle.** (Module 3 — reinforced here.) Flash loans make spot price manipulation essentially free. The attacker borrows millions, moves the price, exploits your protocol, and returns the loan. Cost to attacker: just gas.

**Rule 2: Be careful with any state that can be manipulated and read in the same transaction.** This includes:
- DEX reserve ratios (spot prices)
- Contract token balances (donation attacks)
- Share prices in vaults based on `totalAssets() / totalShares()`
- Governance voting power based on current token holdings

**Rule 3: Time-based defenses.** If an action depends on a value that can be flash-manipulated, require that the value was established in a *previous* block. TWAPs work because they span multiple blocks. Governance timelocks work because proposals can't be executed immediately.

**Rule 4: Use reentrancy guards on functions that manipulate critical state.** Flash loans involve external calls (the callback). If your protocol interacts with flash-loaned funds, ensure reentrant calls can't exploit intermediate states.

### Flash Loan Receiver Security

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

### Flash Loans vs Flash Accounting: The Evolution

Flash loans (Aave, Balancer V2) are a specific feature: borrow tokens, use them, return them.

Flash accounting (Uniswap V4, Balancer V3) is a generalized pattern: all operations within an unlock context track internal deltas, and only net balances are settled. Flash loans are a *subset* of what flash accounting enables.

The evolution:
- **2020:** Flash loans introduced by Aave — revolutionary but limited to borrow-use-repay
- **2021-23:** Uniswap V2/V3 flash swaps — flash loans built into DEX operations
- **2024-25:** V4 flash accounting + EIP-1153 transient storage — the pattern becomes the architecture. No separate "flash loan" feature needed; the entire interaction model is flash-native

As a protocol builder, flash accounting is the pattern to understand deeply. It's more gas-efficient, more composable, and more flexible than dedicated flash loan functions. You'll see this pattern adopted by more protocols going forward.

### Governance Attacks via Flash Loans

Some governance tokens allow voting based on current token holdings at the time of the vote. An attacker can:
1. Flash-borrow governance tokens
2. Vote on a malicious proposal (or create and immediately vote on one)
3. Return the tokens

**Defenses:**
- **Snapshot-based voting:** Voting power is determined by holdings at a specific past block, not the current block. Flash-borrowed tokens have zero voting power because they weren't held at the snapshot block.
- **Timelocks:** Even if a proposal passes, it can't execute for N days, giving the community time to respond.
- **Quorum requirements:** High quorum thresholds make it expensive to flash-borrow enough tokens to pass a proposal.

Most modern governance systems (OpenZeppelin Governor, Compound Governor Bravo) use snapshot voting, making this attack vector largely mitigated. But be aware of it when evaluating protocols with simpler governance.

### Flash Loan Fee Comparison

| Provider | Fee | Multi-asset | Liquidity Source | Fee Waiver |
|----------|-----|-------------|-----------------|------------|
| Aave V3 | 0.05% (5 bps) | Yes (`flashLoan`) | Supply pools | FLASH_BORROWER role |
| Balancer V2 | 0% | Yes | All Vault pools | N/A (already free) |
| Uniswap V2 | ~0.3% | Per-pair | Pair reserves | No |
| Uniswap V4 | 0% (flash accounting) | Native | PoolManager | N/A |
| Compound V3 | N/A | N/A | N/A | No flash loan function |

**Practical choice:** For pure flash loans, Balancer V2 (zero fee) is optimal when it has sufficient liquidity in the asset you need. Aave V3 for maximum liquidity and multi-asset borrows. Uniswap V4 flash accounting for operations that combine swaps with temporary borrowing.

### Exercise

**Exercise 1: Build the vulnerable protocol, then defend it.** Create a simple vault contract that calculates share price as `totalAssets() / totalShares()`. Show how an attacker can use a flash loan to donate assets, inflate the share price, and exploit a protocol that reads this vault's share price. Then fix it with virtual shares/assets offset (the standard ERC-4626 defense).

**Exercise 2: Governance attack simulation.** Deploy a simple governance contract with non-snapshot voting. Show how a flash loan can pass a malicious proposal. Then deploy an OpenZeppelin Governor with snapshot voting and verify the attack fails.

**Exercise 3: Multi-provider composition.** Build a contract that:
- Flash-borrows USDC from Balancer (0 fee)
- Flash-borrows WETH from Aave (uses the USDC from Balancer as part of a larger strategy)
- Executes a complex multi-step operation
- Repays both flash loans

This tests your ability to nest or chain flash loans from different providers. Note: nesting callbacks requires careful tracking of which repayment is owed to which provider.

---

## Key Takeaways

1. **Flash loans eliminate capital as a barrier.** This is both powerful (anyone can liquidate or arbitrage) and dangerous (anyone can attack with unlimited capital). Design your protocols assuming every user has infinite temporary capital.

2. **The callback pattern is universal.** Aave's `executeOperation`, Balancer's `receiveFlashLoan`, Uniswap's `uniswapV2Call` — they all follow the same structure: receive funds, do work, repay. The pattern is simple; the compositions are where complexity lives.

3. **Flash accounting is the future.** Uniswap V4 and Balancer V3 don't bolt flash loans on as a feature — they build the entire protocol around delta tracking and end-of-transaction settlement. This is more gas-efficient and more composable. Learn this pattern deeply.

4. **Zero-fee flash loans change the economics.** Balancer V2 (0%) and V4 flash accounting (0% for the flash component) mean flash loans have essentially no cost beyond gas. This lowers the profitability threshold for attacks and arbitrage.

5. **Receiver security is critical.** Validate `msg.sender`, validate `initiator`, never store funds in flash loan contracts, validate decoded params. A careless receiver is an invitation for griefing or fund theft.

---

## Resources

**Aave flash loans:**
- Developer guide: https://aave.com/docs/aave-v3/guides/flash-loans
- FlashLoanLogic.sol source: https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/FlashLoanLogic.sol
- Cyfrin Aave V3 flash loan lesson: https://updraft.cyfrin.io/courses/aave-v3/contract-architecture/flash-loan

**Balancer flash loans:**
- V2 documentation: https://docs-v2.balancer.fi/reference/contracts/flash-loans.html
- V3 documentation: https://docs.balancer.fi/concepts/vault/flash-loans.html

**Uniswap flash swaps/accounting:**
- V2 flash swaps: https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps
- V4 flash accounting: https://docs.uniswap.org/contracts/v4/concepts/flash-accounting

**Flash loan attacks and security:**
- Cyfrin — Flash loan attack patterns: https://www.cyfrin.io/blog/price-oracle-manipulation-attacks-with-examples
- RareSkills — Flash loan guide: https://rareskills.io/post/flash-loan
- samczsun — Taking undercollateralized loans for fun and for profit (classic): https://samczsun.com/taking-undercollateralized-loans-for-fun-and-for-profit/

---

## Practice Challenges

Flash loans are a key component in many CTF challenges. These are directly relevant:

- **Damn Vulnerable DeFi #1 "Unstoppable"** — A flash loan vault that can be griefed by a donation attack. Tests your understanding of `balanceOf` vs internal accounting.
- **Damn Vulnerable DeFi #3 "Truster"** — A flash loan provider that allows arbitrary external calls during the loan. Tests approval/callback security.
- **Damn Vulnerable DeFi #4 "Side Entrance"** — A flash loan pool with a flaw: depositing flash-loaned funds counts as a "real" deposit. Tests pool accounting invariants.
- **Damn Vulnerable DeFi #10 "Free Rider"** — Buying NFTs using a Uniswap flash swap where the payment check has a flaw. Tests flash swap mechanics.

---

*Next module: Stablecoins & CDPs (~4 days) — MakerDAO/DAI mechanics, collateralized debt positions, stability fees, liquidation auctions, algorithmic vs overcollateralized stablecoins, and the Peg Stability Module.*

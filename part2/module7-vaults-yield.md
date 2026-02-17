# Part 2 — Module 7: Vaults & Yield

**Duration:** ~4 days (3–4 hours/day)
**Prerequisites:** Modules 1–6 (especially token mechanics, lending, and stablecoins)
**Pattern:** Standard deep-dive → Read Yearn V3 → Build vault + strategy → Security analysis
**Builds on:** Module 1 (ERC-20 mechanics, SafeERC20), Module 4 (index-based accounting — the same shares × rate = assets pattern)
**Used by:** Module 8 (inflation attack invariant testing), Module 9 (vault shares as collateral in integration capstone)

---

## Why Vaults Matter

Every protocol in DeFi that holds user funds and distributes yield faces the same core problem: how do you track each user's share of a pool that changes in size as deposits, withdrawals, and yield accrual happen simultaneously?

The answer is vault share accounting — the same shares/assets math that underpins Aave's aTokens, Compound's cTokens, Uniswap LP tokens, Yearn vault tokens, and MakerDAO's DSR Pot. ERC-4626 standardized this pattern into a universal interface, and it's now the foundation of the modular DeFi stack.

Understanding ERC-4626 deeply — the math, the interface, the security pitfalls — gives you the building block for virtually any DeFi protocol. Yield aggregators like Yearn compose these vaults into multi-strategy systems, and the emerging "curator" model (Morpho, Euler V2) uses ERC-4626 vaults as the fundamental unit of risk management.

---

## Day 1: ERC-4626 — The Tokenized Vault Standard

### The Core Abstraction

An ERC-4626 vault is an ERC-20 token that represents proportional ownership of a pool of underlying assets. The two key quantities:

- **Assets:** The underlying ERC-20 token (e.g., USDC, WETH)
- **Shares:** The vault's ERC-20 token, representing a claim on a portion of the assets

The **exchange rate** = `totalAssets() / totalSupply()`. As yield accrues (totalAssets increases while totalSupply stays constant), each share becomes worth more assets. This is the "rebasing without rebasing" pattern — your share balance doesn't change, but each share's value increases.

### The Interface

ERC-4626 extends ERC-20 with these core functions:

**Informational:**
- `asset()` → the underlying token address
- `totalAssets()` → total underlying assets the vault holds/controls
- `convertToShares(assets)` → how many shares would `assets` amount produce
- `convertToAssets(shares)` → how many assets do `shares` redeem for

**Deposit flow (assets → shares):**
- `maxDeposit(receiver)` → max assets the receiver can deposit
- `previewDeposit(assets)` → exact shares that would be minted for `assets` (rounds down)
- `deposit(assets, receiver)` → deposits exactly `assets`, mints shares to `receiver`
- `maxMint(receiver)` → max shares the receiver can mint
- `previewMint(shares)` → exact assets needed to mint `shares` (rounds up)
- `mint(shares, receiver)` → mints exactly `shares`, pulls required assets

**Withdraw flow (shares → assets):**
- `maxWithdraw(owner)` → max assets `owner` can withdraw
- `previewWithdraw(assets)` → exact shares that would be burned for `assets` (rounds up)
- `withdraw(assets, receiver, owner)` → withdraws exactly `assets`, burns shares from `owner`
- `maxRedeem(owner)` → max shares `owner` can redeem
- `previewRedeem(shares)` → exact assets that would be returned for `shares` (rounds down)
- `redeem(shares, receiver, owner)` → redeems exactly `shares`, sends assets to `receiver`

**Critical rounding rules:** The standard mandates that conversions always round in favor of the vault (against the user). This means:
- Depositing/minting: user gets fewer shares (rounds down) or pays more assets (rounds up)
- Withdrawing/redeeming: user gets fewer assets (rounds down) or burns more shares (rounds up)

This ensures the vault can never be drained by rounding exploits.

### The Share Math

```
shares = assets × totalSupply / totalAssets    (for deposits — rounds down)
assets = shares × totalAssets / totalSupply     (for redemptions — rounds down)
```

When the vault is empty (totalSupply == 0), the first depositor typically gets shares at a 1:1 ratio with assets (implementation-dependent).

As yield accrues, `totalAssets` increases while `totalSupply` stays constant, so the assets-per-share ratio grows. Example:

```
Initial: 1000 USDC deposited → 1000 shares minted
         totalAssets = 1000, totalSupply = 1000, rate = 1.0

Yield:   Vault earns 100 USDC from strategy
         totalAssets = 1100, totalSupply = 1000, rate = 1.1

Redeem:  User redeems 500 shares → 500 × 1100/1000 = 550 USDC
```

### Read: OpenZeppelin ERC4626.sol

**Source:** `@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol`

Focus on:
- The `_decimalsOffset()` virtual function and its role in inflation attack mitigation
- How `_convertToShares` and `_convertToAssets` add virtual shares/assets: `shares = assets × (totalSupply + 10^offset) / (totalAssets + 1)`
- The rounding direction in each conversion
- How `deposit`, `mint`, `withdraw`, and `redeem` all route through `_deposit` and `_withdraw`

Also compare with Solmate's implementation (`solmate/src/tokens/ERC4626.sol`) which is more gas-efficient but less defensive.

### Exercise

**Exercise 1:** Implement a minimal ERC-4626 vault from scratch (don't use OpenZeppelin or Solmate). Use `Math.mulDiv` for safe division. Implement all required functions. Test:
- Deposit 1000 USDC, receive 1000 shares
- Simulate yield: manually transfer 100 USDC to the vault
- New deposit of 1000 USDC should receive ~909 shares (1000 × 1000/1100)
- First user redeems 1000 shares, receives ~1100 USDC
- Verify all preview functions return correct values
- Verify rounding always favors the vault

**Exercise 2:** Implement `deposit` and `mint` side by side. Show that `deposit(100)` and `mint(previewDeposit(100))` produce the same result. Show that `mint(100)` and `deposit(previewMint(100))` produce the same result (accounting for rounding).

---

## Day 2: The Inflation Attack and Defenses

### The Attack

The inflation attack (also called the donation attack or first-depositor attack) exploits empty or nearly-empty vaults:

**Step 1:** Attacker deposits 1 wei of assets, receives 1 share.
**Step 2:** Attacker donates a large amount (e.g., 10,000 USDC) directly to the vault contract via `transfer()` (not through `deposit()`).
**Step 3:** Now `totalAssets = 10,000,000,001` (including the 1 wei), `totalSupply = 1`. The exchange rate is extremely high.
**Step 4:** Victim deposits 20,000 USDC. Shares received = `20,000 × 1 / 10,000.000001 = 1` share (rounded down from ~2).
**Step 5:** Attacker and victim each hold 1 share. Attacker redeems for ~15,000 USDC. Attacker profit: ~5,000 USDC stolen from the victim.

The attack works because the large donation inflates the exchange rate, and the subsequent deposit rounds down to give the victim far fewer shares than their deposit warrants.

### Why It Still Matters

This isn't theoretical. The Resupply protocol was exploited via this vector in 2025, and the Venus Protocol lost approximately 86 WETH to a similar attack on ZKsync in February 2025. Any protocol using ERC-4626 vaults as collateral in a lending market is at risk if the vault's exchange rate can be manipulated.

### Defense 1: Virtual Shares and Assets (OpenZeppelin approach)

OpenZeppelin's ERC4626 (since v4.9) adds a configurable decimal offset that creates "virtual" shares and assets:

```solidity
function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
    return assets.mulDiv(
        totalSupply() + 10 ** _decimalsOffset(),  // virtual shares
        totalAssets() + 1,                          // virtual assets
        rounding
    );
}
```

With `_decimalsOffset() = 3`, there are always at least 1000 virtual shares and 1 virtual asset in the denominator. This means even an empty vault behaves as if it already has deposits, making donation attacks unprofitable because the attacker's donation is diluted across the virtual shares.

The trade-off: virtual shares capture a tiny fraction of all yield (the virtual shares "earn" yield that belongs to no one). This is negligible in practice.

### Defense 2: Dead Shares (Uniswap V2 approach)

On the first deposit, permanently lock a small amount of shares (e.g., mint shares to `address(0)` or `address(1)`). This ensures `totalSupply` is never trivially small.

```solidity
function _deposit(uint256 assets, address receiver) internal {
    if (totalSupply() == 0) {
        uint256 deadShares = 1000;
        _mint(address(1), deadShares);
        _mint(receiver, _convertToShares(assets) - deadShares);
    } else {
        _mint(receiver, _convertToShares(assets));
    }
}
```

This is simpler but slightly punishes the first depositor (they lose the value of the dead shares).

### Defense 3: Internal Accounting (Aave V3 approach)

Don't use `balanceOf(address(this))` for `totalAssets()`. Instead, track deposits and withdrawals internally. Direct token transfers (donations) don't affect the vault's accounting.

```solidity
uint256 private _totalManagedAssets;

function totalAssets() public view returns (uint256) {
    return _totalManagedAssets;  // NOT asset.balanceOf(address(this))
}

function _deposit(uint256 assets, address receiver) internal {
    _totalManagedAssets += assets;
    // ...
}
```

This is the most robust defense but requires careful bookkeeping — you must update `_totalManagedAssets` correctly for every flow (deposits, withdrawals, yield harvest, losses).

### When Vaults Are Used as Collateral

The inflation attack becomes especially dangerous when ERC-4626 tokens are used as collateral in lending protocols. If a lending protocol prices collateral using `vault.convertToAssets(shares)`, an attacker can:

1. Inflate the vault's exchange rate via donation
2. Deposit vault shares as collateral (now overvalued)
3. Borrow against the inflated collateral value
4. The exchange rate normalizes (or the attacker redeems), leaving the lending protocol with bad debt

Defense: lending protocols should use time-weighted or externally-sourced exchange rates for ERC-4626 collateral, not the vault's own `convertToAssets()` at a single point in time.

### Exercise

**Exercise 1:** Build the inflation attack. Deploy a naive vault (no virtual shares, `totalAssets = balanceOf`), execute the attack step by step, and show the victim's loss. Then add OpenZeppelin's virtual share offset and show the attack becomes unprofitable.

**Exercise 2:** Build a vault with internal accounting (`_totalManagedAssets`). Show that direct token transfers don't affect the exchange rate. Then show a scenario where a strategy reports yield and updates `_totalManagedAssets` correctly.

**Exercise 3:** Implement all three defenses (virtual shares, dead shares, internal accounting) and compare: gas cost of deposit/withdraw, precision loss on first deposit, effectiveness against varying donation sizes.

---

## Day 3: Yield Aggregation — Yearn V3 Architecture

### The Yield Aggregation Problem

A single yield source (e.g., supplying USDC on Aave) gives you one return. But there are dozens of yield sources for USDC: Aave, Compound, Morpho, Curve pools, Balancer pools, DSR, etc. Each has different risk, return, and capacity. A yield aggregator's job is to:

1. Accept deposits in a single asset
2. Allocate those deposits across multiple yield sources (strategies)
3. Rebalance as conditions change
4. Handle deposits/withdrawals seamlessly
5. Account for profits and losses correctly

### Yearn V3: The Allocator Vault Pattern

Yearn V3 redesigned their vault system around ERC-4626 composability:

**Allocator Vault** — An ERC-4626 vault that doesn't generate yield itself. Instead, it holds an ordered list of **strategies** and allocates its assets among them. Users deposit into the Allocator Vault and receive vault shares. The vault manages the allocation.

**Tokenized Strategy** — An ERC-4626 vault that generates yield from a single external source. Strategies are stand-alone — they can receive deposits directly from users or from Allocator Vaults. Each strategy inherits from `BaseStrategy` and overrides three functions:

```solidity
// Required overrides:
function _deployFunds(uint256 _amount) internal virtual;
    // Deploy assets into the yield source

function _freeFunds(uint256 _amount) internal virtual;
    // Withdraw assets from the yield source

function _harvestAndReport() internal virtual returns (uint256 _totalAssets);
    // Harvest rewards, report total assets under management
```

**The delegation pattern:** TokenizedStrategy is a pre-deployed implementation contract. Your strategy contract delegates all ERC-4626, accounting, and reporting logic to it via `delegateCall` in the fallback function. You only write the three yield-specific functions above.

### Allocator Vault Mechanics

**Adding strategies:** The vault manager calls `vault.add_strategy(strategy_address)`. Each strategy gets a `max_debt` parameter — the maximum the vault will allocate to that strategy.

**Debt allocation:** The `DEBT_MANAGER` role calls `vault.update_debt(strategy, target_debt)` to move funds. The vault tracks `currentDebt` per strategy. When allocating, the vault calls `strategy.deposit()`. When deallocating, it calls `strategy.withdraw()`.

**Reporting:** When `vault.process_report(strategy)` is called:
1. The vault calls `strategy.convertToAssets(strategy.balanceOf(vault))` to get current value
2. Compares to `currentDebt` to determine profit or loss
3. If profit: records gain, charges fees (via Accountant contract), mints fee shares
4. If loss: reduces strategy debt, reduces overall vault value

**Profit unlocking:** Profits aren't immediately available to withdrawers. They unlock linearly over a configurable `profitMaxUnlockTime` period. This prevents sandwich attacks where someone deposits right before a harvest and withdraws right after, capturing yield they didn't contribute to.

### The Curator Model

The broader trend in DeFi (2024-25) extends Yearn's pattern: protocols like Morpho and Euler V2 allow third-party "curators" to deploy ERC-4626 vaults that allocate to their underlying lending markets. Curators set risk parameters, choose which markets to allocate to, and earn management/performance fees. Users choose a curator based on risk appetite and track record.

This separates infrastructure (the lending protocol) from risk management (the curator's vault), creating a modular stack:
- **Layer 1:** Base lending protocol (Morpho Blue, Euler V2, Aave)
- **Layer 2:** Curator vaults (ERC-4626) that allocate across Layer 1 markets
- **Layer 3:** Meta-vaults that allocate across curator vaults

Each layer uses ERC-4626, so they compose naturally.

### Read: Yearn V3 Source

**VaultV3.sol:** `github.com/yearn/yearn-vaults-v3`
- Focus on `process_report()` — how profit/loss is calculated and fees charged
- The withdrawal queue — how the vault pulls funds from strategies when a user withdraws
- The `profitMaxUnlockTime` mechanism

**TokenizedStrategy:** `github.com/yearn/tokenized-strategy`
- The `BaseStrategy` abstract contract — the three functions you override
- How `report()` triggers `_harvestAndReport()` and handles accounting

### Exercise

**Exercise:** Build a simplified allocator vault:

**SimpleAllocator.sol** — An ERC-4626 vault that:
- Accepts USDC deposits
- Manages 2-3 strategies (each also ERC-4626)
- Has `allocate(strategy, amount)` and `deallocate(strategy, amount)` functions
- On withdrawal, pulls from strategies in queue order if idle balance is insufficient
- Reports profit/loss per strategy

**MockStrategy.sol** — A simple ERC-4626 strategy that:
- Accepts deposits
- Simulates yield by increasing `totalAssets()` over time (use block.timestamp)
- Returns funds on withdrawal

Test:
- Deposit 10,000 USDC into allocator
- Allocate 5,000 to Strategy A, 3,000 to Strategy B, keep 2,000 idle
- Warp time, strategies accrue yield
- Report: verify profit is correctly calculated
- Withdraw 8,000 USDC: verify funds are pulled from idle first, then strategies
- Verify shares reflect correct value throughout

---

## Day 4: Composable Yield Patterns and Security

### Pattern 1: Auto-Compounding

Many yield sources distribute rewards in a separate token (e.g., COMP tokens from Compound, CRV from Curve). Auto-compounding sells these reward tokens for the underlying asset and re-deposits:

```
1. Deposit USDC into Compound → earn COMP rewards
2. Harvest: claim COMP, swap COMP → USDC on Uniswap
3. Deposit the additional USDC back into Compound
4. totalAssets increases → share price increases
```

**Build consideration:** The harvest transaction pays gas and incurs swap slippage. Only economical when accumulated rewards exceed costs. Most vaults use keeper bots that call harvest based on profitability calculations.

### Pattern 2: Leveraged Yield (Recursive Borrowing)

Combine lending with borrowing to amplify yield:

```
1. Deposit 1000 USDC as collateral on Aave → earn supply APY
2. Borrow 800 USDC against collateral → pay borrow APY
3. Re-deposit the 800 USDC → earn supply APY on it too
4. Repeat until desired leverage is reached
```

Net yield = (Supply APY × leverage) - (Borrow APY × (leverage - 1))

Only profitable when supply APY + incentives > borrow APY, which is common when protocols distribute governance token rewards. The flash loan strategies from Module 5 make this achievable in a single transaction.

**Risk:** Liquidation if collateral value drops. The strategy must manage health factor carefully and deleverage automatically if it approaches the liquidation threshold.

### Pattern 3: LP + Staking

Provide liquidity to an AMM pool, then stake the LP tokens for additional rewards:

```
1. Deposit USDC → swap half to ETH → provide USDC/ETH liquidity on Uniswap
2. Stake LP tokens in a reward contract (or Convex/Aura for Curve/Balancer)
3. Earn: trading fees + liquidity mining rewards + boosted rewards
4. Harvest: claim all rewards, swap to USDC, re-provide liquidity
```

This is the model behind Yearn's Curve strategies (Curve LP → stake in Convex → earn CRV+CVX), which have historically been among the highest and most consistent yield sources.

### Pattern 4: Vault Composability

Because ERC-4626 vaults are ERC-20 tokens, they can be used as:
- **Collateral in lending protocols:** Deposit sUSDe (Ethena's staked USDe vault token) as collateral on Aave, borrow against your yield-bearing position
- **Liquidity in AMMs:** Create a trading pair with a vault token (e.g., wstETH/sDAI pool)
- **Strategy inputs for other vaults:** A Yearn allocator vault can add any ERC-4626 vault as a strategy, including another allocator vault (vault-of-vaults)

This composability is why ERC-4626 adoption has been so rapid — each new vault automatically works with every protocol that supports the standard.

### Security Considerations for Vault Builders

**1. totalAssets() must be manipulation-resistant.** If `totalAssets()` reads external state that can be manipulated within a transaction (DEX spot prices, raw token balances), your vault is vulnerable. Use internal accounting or time-delayed oracles.

**2. Withdrawal liquidity risk.** If all assets are deployed to strategies, a large withdrawal can fail. Maintain an "idle buffer" (percentage of assets not deployed) and implement a withdrawal queue that pulls from strategies in priority order.

**3. Strategy loss handling.** Strategies can lose money (smart contract hack, bad debt in lending, impermanent loss). The vault must handle losses gracefully — reduce share price proportionally, not revert on withdrawal. Yearn V3's `max_loss` parameter lets users specify acceptable loss on withdrawal.

**4. Sandwich attack on harvest.** An attacker sees a pending `harvest()` transaction that will increase `totalAssets`. They front-run with a deposit (buying shares cheap), let harvest execute (share price increases), then back-run with a withdrawal (redeeming at higher price). Defense: profit unlocking over time (Yearn's `profitMaxUnlockTime`), deposit/withdrawal fees, or private transaction submission.

**5. Fee-on-transfer and rebasing tokens.** ERC-4626 assumes standard ERC-20 behavior. Fee-on-transfer tokens deliver less than the requested amount on `transferFrom`. Rebasing tokens change balances outside of transfers. Both break naive vault accounting. Use balance-before-after checks (Module 1 pattern) and avoid rebasing tokens as underlying assets.

**6. ERC-4626 compliance edge cases.** The standard requires specific behaviors for max functions (must return `type(uint256).max` or actual limit), preview functions (must be exact or revert), and empty vault handling. Non-compliant implementations cause integration failures across the ecosystem. Test against the ERC-4626 property tests.

### Exercise

**Exercise 1: Auto-compounder.** Build an ERC-4626 vault that:
- Deposits USDC into a mock lending protocol
- Earns yield in a separate REWARD token
- Has a `harvest()` function that claims REWARD, swaps to USDC via a mock DEX, and re-deposits
- Verify: share price increases after harvest, profit unlocks over time

**Exercise 2: Sandwich defense.** Using your vault from Exercise 1:
- Show the sandwich attack: deposit → harvest → withdraw captures yield
- Implement linear profit unlocking over 6 hours
- Show the same sandwich attempt now captures minimal yield

**Exercise 3: Strategy loss.** Using the allocator vault from Day 3:
- Simulate a strategy losing 20% of its funds (mock a hack)
- Call report — verify the vault correctly records the loss
- Verify share price decreased proportionally
- Verify existing depositors can still withdraw (at reduced value)
- Verify new depositors enter at the correct (lower) share price

---

## Key Takeaways

1. **ERC-4626 is the TCP/IP of DeFi yield.** It's the universal interface that lets any vault plug into any protocol. Understanding it deeply — the math, the rounding rules, the security model — is foundational for building anything yield-related.

2. **Share math is the same pattern everywhere.** Aave aTokens, Compound cTokens, Uniswap LP tokens, Yearn vault tokens, MakerDAO DSR — they all use the same shares × rate = assets formula. Master it once, apply it everywhere.

3. **The inflation attack is real and ongoing.** It exploited protocols as recently as 2025. Virtual shares (OpenZeppelin) or internal accounting are non-negotiable defenses. Never use raw `balanceOf` for critical pricing.

4. **Profit unlocking prevents sandwich attacks.** Any vault that instantly reflects harvested yield in share price is vulnerable. Linear unlock over hours/days is the standard defense.

5. **The allocator pattern is the future of DeFi.** Yearn V3, Morpho curators, Euler V2 vaults — the industry is converging on modular ERC-4626 vaults with pluggable strategies. Building and understanding this pattern prepares you for the current state of DeFi architecture.

---

## Resources

**ERC-4626:**
- EIP specification: https://eips.ethereum.org/EIPS/eip-4626
- Ethereum.org overview: https://ethereum.org/developers/docs/standards/tokens/erc-4626
- OpenZeppelin implementation + security guide: https://docs.openzeppelin.com/contracts/5.x/erc4626
- OpenZeppelin source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol

**Inflation attack:**
- MixBytes overview: https://mixbytes.io/blog/overview-of-the-inflation-attack
- OpenZeppelin exchange rate risk analysis: https://www.openzeppelin.com/news/erc-4626-tokens-in-defi-exchange-rate-manipulation-risks
- SpeedrunEthereum vault security: https://speedrunethereum.com/guides/erc-4626-vaults

**Yearn V3:**
- V3 overview: https://docs.yearn.fi/developers/v3/overview
- VaultV3 spec: https://github.com/yearn/yearn-vaults-v3/blob/master/TECH_SPEC.md
- Tokenized Strategy: https://github.com/yearn/tokenized-strategy
- Strategy writing guide: https://docs.yearn.fi/developers/v3/strategy_writing_guide

**Modular DeFi / Curators:**
- Morpho documentation: https://docs.morpho.org
- Euler V2 documentation: https://docs.euler.finance

---

## Practice Challenges

These challenges test vault interaction patterns and are best attempted after completing the module:

- **Damn Vulnerable DeFi #15 — "ABI Smuggling":** A vault with an authorization mechanism that can be bypassed through careful ABI encoding. Tests your understanding of how vault deposit/withdraw flows interact with access control.

---

*Next module: DeFi Security (~4 days) — DeFi-specific attack patterns, invariant testing with Foundry, reading audit reports, and security tooling.*

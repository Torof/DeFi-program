# Part 2 — Module 4: Lending & Borrowing

**Duration:** ~7 days (3–4 hours/day)
**Prerequisites:** Modules 1–3 (tokens, AMMs, oracles)
**Pattern:** Math → Read Aave V3 → Read Compound V3 → Build simplified protocol → Liquidation deep dive
**Builds on:** Module 1 (SafeERC20), Module 3 (Chainlink consumer, staleness checks), Part 1 Section 5 (invariant testing, fork testing)
**Used by:** Module 5 (flash loan liquidation), Module 8 (invariant testing your lending pool), Module 9 (integration capstone)

---

## Why This Module Is the Longest After AMMs

**Why this matters:** Lending is where everything you've learned converges. Token mechanics (Module 1) govern how assets move in and out. Oracle integration (Module 3) determines collateral valuation and liquidation triggers. And the interest rate math shares DNA with the constant product formula from AMMs (Module 2) — both are mechanism design problems where smart contracts use mathematical curves to balance supply and demand without human intervention.

> **Real impact:** Lending protocols are the highest-TVL category in DeFi. [Aave holds $18B+ TVL](https://defillama.com/protocol/aave) (2024), [Compound $3B+](https://defillama.com/protocol/compound), [Spark (MakerDAO) $2.5B+](https://defillama.com/protocol/spark). Combined, lending protocols represent >$30B in user deposits.

> **Real impact — exploits:** Lending protocols have been the target of some of DeFi's largest hacks:
- [Euler Finance](https://rekt.news/euler-rekt/) ($197M, March 2023) — donation attack bypassing health checks
- [Radiant Capital](https://rekt.news/radiant-rekt/) ($58M, January 2024) — flash loan price manipulation
- [Rari Capital/Fuse](https://rekt.news/rari-capital-rekt/) ($80M, May 2022) — reentrancy in pool withdrawals
- [Cream Finance](https://rekt.news/cream-rekt-2/) ($130M, October 2021) — oracle manipulation
- [Hundred Finance](https://rekt.news/hundred-rekt/) ($7M, April 2022) — [ERC-777](https://eips.ethereum.org/EIPS/eip-777) reentrancy
- [Venus Protocol](https://rekt.news/venus-blizz-rekt/) ($11M, May 2023) — stale oracle pricing

If you're building DeFi products, you'll either build a lending protocol, integrate with one, or compete with one. Understanding the internals is non-negotiable.

---

## Day 1: The Lending Model from First Principles

### How DeFi Lending Works

**Why this matters:** Traditional lending requires a bank to assess creditworthiness, set terms, and enforce repayment. DeFi lending replaces all of this with overcollateralization and algorithmic liquidation.

The core loop:

1. **Suppliers** deposit assets (e.g., USDC) into a pool. They earn interest from borrowers.
2. **Borrowers** deposit collateral (e.g., ETH), then borrow from the pool (e.g., USDC) up to a limit determined by their collateral's value and the protocol's risk parameters.
3. **Interest** accrues continuously. Borrowers pay it; suppliers receive it (minus a protocol cut called the reserve factor).
4. **If collateral value drops** (or debt grows) past a threshold, the position becomes eligible for **liquidation** — a third party repays part of the debt and receives the collateral at a discount.

**No credit checks. No loan officers. No repayment schedule.** Borrowers can hold positions indefinitely as long as they remain overcollateralized.

> **Used by:** [Aave V3](https://github.com/aave/aave-v3-core) (May 2022 deployment), [Compound V3 (Comet)](https://github.com/compound-finance/comet) (August 2022), [Spark](https://github.com/marsfoundation/sparklend) (fork of Aave V3, May 2023)

---

### Key Parameters

**Loan-to-Value (LTV):** The maximum ratio of borrowed value to collateral value at the time of borrowing. If ETH has an LTV of 80%, depositing $10,000 of ETH lets you borrow up to $8,000.

**Liquidation Threshold (LT):** The ratio at which a position becomes liquidatable. Always higher than LTV (e.g., 82.5% for ETH). The gap between LTV and LT is the borrower's safety buffer.

**Health Factor:** The single number that determines whether a position is safe:

```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value
```

HF > 1 = safe. HF < 1 = eligible for liquidation. HF = 1.5 means the collateral could lose 33% of its value before liquidation.

> **Example:** On [Aave V3 Ethereum mainnet](https://app.aave.com/), ETH has LTV = 80.5%, LT = 82.5%. If you deposit $10,000 ETH:
- Maximum initial borrow: $8,050 (80.5%)
- Liquidation triggered when debt/collateral exceeds 82.5%
- Safety buffer: 2% price movement room before liquidation risk

**Liquidation Bonus (Penalty):** The discount a liquidator receives on seized collateral (e.g., 5%). This incentivizes liquidators to monitor and act quickly, keeping the protocol solvent.

> **Why this matters:** Without sufficient liquidation bonus, liquidators have no incentive to act during high gas prices or volatile markets. Too high, and liquidations become excessively punitive for borrowers.

**Reserve Factor:** The percentage of interest that goes to the protocol treasury rather than suppliers (typically 10–25%). This builds a reserve fund for bad debt coverage.

> **Used by:** [Aave V3 reserves](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L199) range from 10-20% depending on asset, [Compound V3](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) uses protocol-specific reserve factors

**Close Factor:** How much of the debt a liquidator can repay in a single liquidation. Aave V3 uses 50% normally, but allows 100% when HF < 0.95 to clear dangerous positions faster.

> **Common pitfall:** Setting close factor too high (100% always) can lead to liquidation cascades where all collateral is dumped at once, crashing prices further. Gradual liquidation (50%) reduces market impact.

---

### Interest Rate Models: The Kinked Curve

**Why this matters:** The interest rate model is the mechanism that balances supply and demand for each asset pool. Every major lending protocol uses some variant of a piecewise linear "kinked" curve.

**Utilization rate:**
```
U = Total Borrowed / Total Supplied
```

When U is low, there's plenty of liquidity — rates should be low to encourage borrowing. When U is high, liquidity is scarce — rates should spike to attract suppliers and discourage borrowing. **If U hits 100%, suppliers can't withdraw. That's a crisis.**

> **Real impact:** During the March 2020 crash, [Aave's USDC borrow rate spiked past 50% APR](https://app.aave.com/reserve-overview/?underlyingAsset=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48&marketName=proto_mainnet_v3) when utilization hit 98%. This was working as designed — extreme rates forced borrowers to repay, restoring liquidity.

**The two-slope model:**

Below the optimal utilization (the "kink," typically 80–90%):
```
BorrowRate = BaseRate + (U / U_optimal) × Slope1
```

Above the optimal utilization:
```
BorrowRate = BaseRate + Slope1 + ((U - U_optimal) / (1 - U_optimal)) × Slope2
```

Slope2 is dramatically steeper than Slope1. This creates a sharp increase in rates past the kink, which acts as a self-correcting mechanism — expensive borrowing pushes utilization back down.

> **Deep dive:** [Aave interest rate strategy contracts](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/DefaultReserveInterestRateStrategyV2.sol), [Compound V3 rate model](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423), [RareSkills guide to interest rate models](https://rareskills.io/post/aave-interest-rate-model)

**Supply rate derivation:**
```
SupplyRate = BorrowRate × U × (1 - ReserveFactor)
```

Suppliers earn a fraction of what borrowers pay, reduced by utilization (not all capital is lent out) and the reserve factor (the protocol's cut).

> **Common pitfall:** Expecting supply rate to equal borrow rate. Suppliers always earn less due to utilization < 100% and reserve factor. If U = 80% and reserve factor = 15%, suppliers earn only `BorrowRate × 0.8 × 0.85 = 68%` of the gross borrow rate.

---

### Interest Accrual: Indexes and Scaling

**Why this matters:** Interest doesn't accrue by updating every user's balance every second. That would be impossibly expensive. Instead, protocols use a **global index** that compounds over time:

```
currentIndex = previousIndex × (1 + ratePerSecond × timeElapsed)
```

A user's actual balance is:
```
actualBalance = storedPrincipal × currentIndex / indexAtDeposit
```

When a user deposits, the protocol stores their `principal` and the current index. When they withdraw, the protocol computes their balance using the latest index. **This means the protocol only needs to update one global variable, not millions of individual balances.**

> **Used by:** [Aave V3 supply index](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ReserveLogic.sol#L46), [Compound V3 supply/borrow indexes](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313), every modern lending protocol

**Compound interest approximation:** [Aave V3 uses a binomial expansion](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol#L28) to approximate `(1 + r)^n` on-chain, which is cheaper than computing exponents. For small `r` (per-second rates are tiny), the approximation is extremely accurate.

> **Deep dive:** [Aave V3 MathUtils.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/MathUtils.sol) — compound interest calculation

---

### Exercise: Build the Math

**Exercise 1:** Implement a `KinkedInterestRate.sol` contract with:
- `getUtilization(totalSupply, totalBorrow)` → returns U as a WAD (18 decimals)
- `getBorrowRate(utilization)` → returns per-second borrow rate using two-slope model
- `getSupplyRate(utilization, borrowRate, reserveFactor)` → returns per-second supply rate
- Configurable parameters: baseRate, slope1, slope2, optimalUtilization, reserveFactor

```solidity
// Example: Two-slope interest rate model
contract KinkedInterestRate {
    uint256 public immutable baseRatePerSecond;
    uint256 public immutable slope1;
    uint256 public immutable slope2;
    uint256 public immutable optimalUtilization; // e.g., 0.8e18 (80%)
    uint256 public immutable reserveFactor; // e.g., 0.15e18 (15%)

    function getUtilization(uint256 totalSupply, uint256 totalBorrow) public pure returns (uint256) {
        if (totalSupply == 0) return 0;
        return (totalBorrow * 1e18) / totalSupply;
    }

    function getBorrowRate(uint256 utilization) public view returns (uint256) {
        if (utilization <= optimalUtilization) {
            // Below kink: linear slope from base to base + slope1
            return baseRatePerSecond + (utilization * slope1) / optimalUtilization;
        } else {
            // Above kink: steep slope2
            uint256 excessUtilization = utilization - optimalUtilization;
            uint256 excessRange = 1e18 - optimalUtilization;
            return baseRatePerSecond + slope1 + (excessUtilization * slope2) / excessRange;
        }
    }

    function getSupplyRate(uint256 utilization, uint256 borrowRate) public view returns (uint256) {
        // SupplyRate = BorrowRate × U × (1 - ReserveFactor)
        return (borrowRate * utilization * (1e18 - reserveFactor)) / 1e36;
    }
}
```

> **Common pitfall:** Integer overflow when multiplying rates. Always ensure intermediate calculations don't overflow. Use smaller precision (e.g., per-second rates in RAY = 27 decimals) rather than storing APY directly.

**Exercise 2:** Implement an `InterestAccumulator.sol` that:
- Maintains a global `supplyIndex` and `borrowIndex`
- Exposes `accrueInterest()` which updates both indexes based on elapsed time and current rates
- Exposes `balanceOf(user)` which returns the user's scaled balance using the current index
- Test: deposit at t=0, warp forward 1 year, verify the balance matches expected APY

---

## Day 2: Aave V3 Architecture — Supply and Borrow

### Contract Architecture Overview

**Why this matters:** [Aave V3](https://github.com/aave/aave-v3-core) (deployed May 2022) uses a proxy pattern with logic delegated to libraries. Understanding this architecture is essential for reading production lending code.

**The entry point is the Pool contract (behind a proxy), which delegates to specialized logic libraries:**

```
User → Pool (proxy)
         ├─ SupplyLogic
         ├─ BorrowLogic
         ├─ LiquidationLogic
         ├─ FlashLoanLogic
         ├─ BridgeLogic
         └─ EModeLogic
```

**Supporting contracts:**
- **[PoolAddressesProvider](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PoolAddressesProvider.sol):** Registry for all protocol contracts. Single source of truth for addresses.
- **[AaveOracle](https://github.com/aave/aave-v3-core/blob/master/contracts/misc/AaveOracle.sol):** Wraps Chainlink feeds. Each asset has a registered price source.
- **[PoolConfigurator](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/PoolConfigurator.sol):** Governance-controlled contract that sets risk parameters (LTV, LT, reserve factor, caps).
- **[PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol):** L2-specific — checks sequencer uptime before allowing liquidations.

> **Deep dive:** [Aave V3 technical paper](https://github.com/aave/aave-v3-core/blob/master/techpaper/Aave_V3_Technical_Paper.pdf), [MixBytes architecture analysis](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-aave-v3)

---

### aTokens: Interest-Bearing Receipts

**Why this matters:** When you supply USDC to Aave, you receive **aUSDC**. This is an ERC-20 token whose balance *automatically increases* over time as interest accrues. You don't need to claim anything — your `balanceOf()` result grows continuously.

**How it works internally:**

[aTokens](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol) store a "scaled balance" (principal divided by the current liquidity index). The `balanceOf()` function multiplies the scaled balance by the current index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedIncome(asset));
}
```

`getReserveNormalizedIncome()` returns the current supply index, which grows every second based on the supply rate. This design means:
- Transferring aTokens transfers the proportional claim on the pool (including future interest)
- aTokens are composable — they can be used in other DeFi protocols as yield-bearing collateral
- No explicit "harvest" or "claim" step for interest

> **Used by:** [Yearn V3 vaults](https://github.com/yearn/yearn-vaults-v3) accept aTokens as deposits, [Convex](https://www.convexfinance.com/) wraps aTokens for boosted rewards, many protocols use aTokens as collateral in other lending markets

> **Common pitfall:** Assuming aToken balance is static. If you cache `balanceOf()` at t0 and check again at t1, the balance will have increased. Always read the current value.

---

### Debt Tokens: Tracking What's Owed

When you borrow, the protocol mints **[variableDebtTokens](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/VariableDebtToken.sol)** (or stable debt tokens, though stable rate borrowing is being deprecated) to your address. These are non-transferable ERC-20 tokens whose balance *increases* over time as interest accrues on your debt.

The mechanics mirror aTokens but use the borrow index instead of the supply index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedVariableDebt(asset));
}
```

Debt tokens being non-transferable is a deliberate security choice — you can't transfer your debt to someone else without their consent (credit delegation notwithstanding).

> **Common pitfall:** Trying to `transfer()` debt tokens. This reverts. Debt can only be transferred via credit delegation (`approveDelegation()`).

---

### Read: Supply Flow

**Source:** [aave-v3-core/contracts/protocol/libraries/logic/SupplyLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol)

Trace the supply path through Aave V3:

1. User calls [`Pool.supply(asset, amount, onBehalfOf, referralCode)`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L138)
2. Pool delegates to [`SupplyLogic.executeSupply()`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol#L47)
3. Logic validates the reserve is active and not paused
4. Updates the reserve's indexes (accrues interest up to this moment)
5. Transfers the underlying asset from user to the aToken contract
6. Mints aTokens to the `onBehalfOf` address (scaled by current index)
7. Updates the user's configuration bitmap (tracks which assets are supplied/borrowed)

---

### Read: Borrow Flow

**Source:** [BorrowLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol)

1. User calls [`Pool.borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L190)
2. Pool delegates to [`BorrowLogic.executeBorrow()`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol#L52)
3. Logic validates: reserve active, borrowing enabled, amount ≤ borrow cap
4. **Validates the user's health factor will remain > 1 after the borrow**
5. Mints debt tokens to the borrower (or `onBehalfOf` for credit delegation)
6. Transfers the underlying asset from the aToken contract to the user
7. Updates the interest rate for the reserve (utilization changed)

**Key insight:** The health factor check happens *before* the tokens are transferred. If the borrow would make the position undercollateralized, it reverts.

> **Common pitfall:** Not accounting for accrued interest when calculating max borrow. Debt grows continuously, so the maximum borrowable amount decreases over time even if collateral price stays constant.

#### 📖 How to Study Aave V3 Architecture

The Aave V3 codebase is ~15,000+ lines across many libraries. Here's how to approach it without getting lost:

1. **Start with the Pool proxy entry points** — Open [Pool.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) and read just the function signatures. Each one (`supply`, `borrow`, `repay`, `withdraw`, `liquidationCall`) delegates to a Logic library. Map the routing: which function calls which library.

2. **Trace one complete flow end-to-end** — Pick `supply()`. Follow it into [SupplyLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol). Read every line of `executeSupply()`. Note: index update → transfer → mint aTokens → update user config bitmap. Draw this as a sequence diagram.

3. **Understand the data model** — Read [DataTypes.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/types/DataTypes.sol). The `ReserveData` struct is the central state. Map each field to what it controls (indexes for interest, configuration bitmap for risk params, address pointers for aToken/debtToken).

4. **Read the index math** — Open [ReserveLogic.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ReserveLogic.sol) and trace `updateState()` → `_updateIndexes()`. This is the compound interest accumulation. Then read how `balanceOf()` in [AToken.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol) uses the index to compute the live balance.

5. **Then read ValidationLogic.sol** — This is where all the safety checks live: health factor validation, borrow cap checks, E-Mode constraints. Read `validateBorrow()` to understand every condition that must pass before a borrow succeeds.

**Don't get stuck on:** The configuration bitmap encoding initially. It's clever bit manipulation (Part 1 Section 1 territory) but you can treat `getters` as black boxes on first pass. Focus on the flow: entry point → logic library → state update → token operations.

---

### Credit Delegation

The `onBehalfOf` parameter enables [credit delegation](https://docs.aave.com/developers/guides/credit-delegation): Alice can allow Bob to borrow using her collateral. Alice's health factor is affected, but Bob receives the borrowed assets. This is done through `approveDelegation()` on the debt token contract.

> **Used by:** [InstaDapp](https://instadapp.io/) uses credit delegation for automated strategies, institutional custody solutions use it for sub-account management

---

### Exercise: Fork and Interact

**Exercise 1:** Fork Ethereum mainnet. Using Foundry's `vm.prank()`, simulate a full supply → borrow → repay → withdraw cycle on Aave V3. Verify aToken and debt token balances at each step.

```solidity
function testAaveSupplyBorrowCycle() public {
    vm.createSelectFork(mainnetRpcUrl);

    IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // Aave V3 Pool
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 aUSDC = IERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);

    address user = makeAddr("user");
    uint256 supplyAmount = 10_000e6; // 10k USDC

    // Setup: give user USDC
    deal(address(usdc), user, supplyAmount);

    vm.startPrank(user);
    usdc.approve(address(pool), supplyAmount);

    // Supply
    pool.supply(address(usdc), supplyAmount, user, 0);
    assertEq(aUSDC.balanceOf(user), supplyAmount); // aUSDC minted 1:1 initially

    // Warp forward, verify interest accrued
    vm.warp(block.timestamp + 365 days);
    assertGt(aUSDC.balanceOf(user), supplyAmount); // Balance increased

    vm.stopPrank();
}
```

**Exercise 2:** Inspect the [`ReserveData`](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/types/DataTypes.sol#L49) struct for USDC on the forked state. Extract: liquidityIndex, variableBorrowIndex, currentLiquidityRate, currentVariableBorrowRate, configuration (decode the bitmap to get LTV, liquidation threshold, etc.). This builds familiarity with how Aave stores state.

---

## Day 3: Aave V3 — Risk Modes and Advanced Features

### Efficiency Mode (E-Mode)

**Why this matters:** [E-Mode](https://docs.aave.com/developers/whats-new/efficiency-mode-emode) allows higher capital efficiency when collateral and borrowed assets are correlated. For example, borrowing USDC against DAI — both are USD stablecoins, so the risk of the collateral losing value relative to the debt is minimal.

When a user activates an E-Mode category (e.g., "USD stablecoins"), the protocol overrides the standard LTV and liquidation threshold with higher values specific to that category. A stablecoin category might allow 97% LTV vs the normal 75%.

E-Mode categories can also specify a custom oracle. For stablecoin-to-stablecoin, a fixed 1:1 oracle might be used instead of market price feeds, eliminating unnecessary liquidations from minor depeg events.

> **Real impact:** During the March 2023 USDC depeg (Silicon Valley Bank crisis), E-Mode users with DAI collateral borrowing USDC were not liquidated due to the correlated asset treatment, while non-E-Mode users faced liquidation risk from the price deviation.

> **Used by:** [Aave V3 E-Mode categories](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/EModeLogic.sol) — stablecoins, ETH derivatives (ETH/wstETH/rETH), BTC derivatives

---

### Isolation Mode

**Why this matters:** New or volatile assets can be listed in [Isolation Mode](https://docs.aave.com/developers/whats-new/isolation-mode). When a user supplies an isolated asset as collateral:
- They cannot use any other assets as collateral simultaneously
- They can only borrow assets approved for isolation mode (typically stablecoins)
- There's a hard debt ceiling for the isolated asset across all users

This prevents a volatile long-tail asset from threatening the entire protocol. If SHIB were listed in isolation mode with a $1M debt ceiling, even a complete collapse of SHIB's price could only create $1M of potential bad debt.

> **Common pitfall:** Not understanding the trade-off. Isolation Mode severely limits composability — users can't mix isolated collateral with other assets. This is intentional for risk management.

---

### Siloed Borrowing

Assets with manipulatable oracles (e.g., tokens with thin liquidity that could be subject to the oracle attacks from Module 3) can be listed as "siloed." Users borrowing siloed assets can only borrow that single asset — no mixing with other borrows.

> **Deep dive:** [Aave V3 siloed borrowing](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ValidationLogic.sol#L203)

---

### Supply and Borrow Caps

[V3 introduces governance-set caps per asset](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ValidationLogic.sol#L82):
- **Supply cap:** Maximum total deposits. Prevents excessive concentration of a single collateral asset.
- **Borrow cap:** Maximum total borrows. Limits the protocol's exposure to any single borrowed asset.

These are simple but critical risk controls that didn't exist in V2.

> **Real impact:** After the [CRV liquidity crisis](https://cointelegraph.com/news/curve-founder-s-300m-loans-teeter-on-liquidation) (November 2023), Aave governance tightened CRV supply caps to limit exposure. This prevented further accumulation of risky CRV positions.

---

### Virtual Balance Layer

[Aave V3 tracks balances internally](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol#L73) rather than relying on actual `balanceOf()` calls to the token contract. This protects against donation attacks (someone sending tokens directly to the aToken contract to manipulate share ratios) and makes accounting predictable regardless of external token transfers like airdrops.

> **Real impact:** [Euler Finance hack](https://rekt.news/euler-rekt/) ($197M, March 2023) exploited donation attack vectors in ERC-4626-like vaults. Aave's virtual balance approach prevents this entire class of attacks.

---

### Read: Configuration Bitmap

[Aave V3 packs all risk parameters](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol) for a reserve into a single `uint256` bitmap in `ReserveConfigurationMap`. This is extreme gas optimization:

```
Bit 0-15:   LTV
Bit 16-31:  Liquidation threshold
Bit 32-47:  Liquidation bonus
Bit 48-55:  Decimals
Bit 56:     Active flag
Bit 57:     Frozen flag
Bit 58:     Borrowing enabled
Bit 59:     Stable rate borrowing enabled (deprecated)
Bit 60:     Paused
Bit 61:     Borrowable in isolation
Bit 62:     Siloed borrowing
Bit 63:     Flashloaning enabled
...
```

> **Deep dive:** [ReserveConfiguration.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/configuration/ReserveConfiguration.sol) — read the getter/setter library functions to understand bitwise manipulation patterns used throughout production DeFi.

---

### Exercise

**Exercise 1:** On a mainnet fork, activate E-Mode for a user position (stablecoin category). Compare the borrowing power before and after. Verify the LTV and liquidation threshold change.

**Exercise 2:** Read the [PoolConfigurator.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/PoolConfigurator.sol) contract. Trace how `configureReserveAsCollateral()` encodes LTV, liquidation threshold, and liquidation bonus into the bitmap. Write a helper contract that decodes a raw bitmap into a human-readable struct.

---

## Day 4: Compound V3 (Comet) — A Different Architecture

### Why Study Both Aave and Compound

**Why this matters:** [Aave V3](https://github.com/aave/aave-v3-core) and [Compound V3](https://github.com/compound-finance/comet) represent two fundamentally different architectural approaches to the same problem. Understanding both gives you the design vocabulary to make informed choices when building your own protocol.

> **Deep dive:** [RareSkills Compound V3 Book](https://rareskills.io/compound-v3-book), [RareSkills architecture walkthrough](https://rareskills.io/post/compound-v3-contracts-tutorial)

---

### The Single-Asset Model

**Why this matters:** [Compound V3's](https://github.com/compound-finance/comet) (deployed August 2022) key architectural decision: **each market only lends one asset** (the "base asset," typically USDC). This is a radical departure from V2 and from Aave, where every asset in the pool can be both collateral and borrowable.

**Implications:**
- **Simpler risk model:** There's no cross-asset risk contagion. If one collateral asset collapses, it can only affect the single base asset pool.
- **Collateral doesn't earn interest.** Your ETH or wBTC sitting as collateral in Compound V3 earns nothing. This is the trade-off for the simpler, safer architecture.
- **Separate markets for each base asset.** There's a [USDC market](https://app.compound.finance/) and an ETH market — completely independent contracts with separate parameters.

> **Common pitfall:** Expecting collateral to earn yield in Compound V3 like it does in Aave. It doesn't. Users must choose: deposit as base asset (earns interest), or deposit as collateral (enables borrowing, no interest).

---

### Comet Contract Architecture

**Source:** [compound-finance/comet/contracts/Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol)

Everything lives in one contract (behind a proxy), called **Comet**:

```
User → Comet Proxy
         └─ Comet Implementation
              ├─ Supply/withdraw logic
              ├─ Borrow/repay logic
              ├─ Liquidation logic (absorb)
              ├─ Interest rate model
              └─ CometExt (fallback for auxiliary functions)
```

**Supporting contracts:**
- **[CometExt](https://github.com/compound-finance/comet/blob/main/contracts/CometExt.sol):** Handles overflow functions that don't fit in the main contract (24KB limit workaround via the fallback extension pattern)
- **[Configurator](https://github.com/compound-finance/comet/blob/main/contracts/Configurator.sol):** Sets parameters, deploys new Comet implementations when governance changes settings
- **[CometFactory](https://github.com/compound-finance/comet/blob/main/contracts/CometFactory.sol):** Deploys new Comet instances
- **[Rewards](https://github.com/compound-finance/comet/blob/main/contracts/CometRewards.sol):** Distributes COMP token incentives (separate from the lending logic)

---

### Immutable Variables: A Unique Design Choice

**Why this matters:** [Compound V3 stores all parameters](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L65-L109) (interest rate model coefficients, collateral factors, liquidation factors) as **immutable variables**, not storage. To change any parameter, governance must deploy an entirely new Comet implementation and update the proxy.

**Why?** Immutable variables are significantly cheaper to read than storage (3 gas vs 2100 gas for cold SLOAD). Since rate calculations happen on every interaction, this saves substantial gas across millions of transactions. The trade-off is governance friction — changing a parameter requires a full redeployment, not just a storage write.

> **Common pitfall:** Trying to update parameters via governance without redeploying. Compound V3 parameters are immutable — you must deploy a new implementation.

---

### Principal and Index Accounting

[Compound V3 tracks balances](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313) using a principal/index system similar to Aave but with a twist: the principal is a **signed integer**. Positive means the user is a supplier; negative means they're a borrower. There's no separate debt token.

```solidity
struct UserBasic {
    int104 principal;       // signed: positive = supply, negative = borrow
    uint64 baseTrackingIndex;
    uint64 baseTrackingAccrued;
    uint16 assetsIn;        // bitmap of which collateral assets are deposited
}
```

The actual balance is computed:
```
If principal > 0: balance = principal × supplyIndex / indexScale
If principal < 0: balance = |principal| × borrowIndex / indexScale
```

---

### Separate Supply and Borrow Rate Curves

Unlike Aave (where supply rate is derived from borrow rate), [Compound V3 defines **independent** kinked curves](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423) for both supply and borrow rates. Both are functions of utilization with their own base rates, kink points, and slopes. This gives governance more flexibility but means the spread isn't automatically guaranteed.

> **Deep dive:** [Comet.sol getSupplyRate() / getBorrowRate()](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423)

---

### Read: Comet.sol Core Functions

**Source:** [compound-finance/comet/contracts/Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol)

Key functions to read:
- [`supplyInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L683): How supply is processed, including the `repayAndSupplyAmount()` split (if user has debt, supply first repays debt, then adds to balance)
- [`withdrawInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L721): How withdrawal works, including automatic borrow creation if withdrawing more than supplied
- [`getSupplyRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L428) / [`getBorrowRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423): The kinked curve implementations
- [`accrueInternal()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L313): How indexes are updated using `block.timestamp` and per-second rates
- [`isLiquidatable()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L555): Health check using collateral factors and oracle prices

**Note:** Compound V3 is ~4,300 lines of Solidity (excluding comments). This is compact for a lending protocol and very readable.

#### 📖 How to Study Compound V3 (Comet)

Comet is dramatically simpler than Aave — one contract, ~4,300 lines. This makes it the better starting point if you're new to lending protocol code.

1. **Start with the state variables** — Open [Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) and read the immutable declarations (lines ~65-109). These ARE the protocol configuration — base token, interest rate params, collateral factors, oracle feeds. Notice: all immutable, not storage. Understanding why this matters (gas) and the trade-off (redeployment for changes) is key.

2. **Read `supplyInternal()` and `withdrawInternal()`** — These are the core flows. Notice the signed principal pattern: supplying when you have debt first repays debt. Withdrawing when you have no supply creates a borrow. This dual behavior is elegant but different from Aave's separate supply/borrow paths.

3. **Trace the index update in `accrueInternal()`** — This is simpler than Aave's version. One function, linear compound, per-second rates. Map how `baseSupplyIndex` and `baseBorrowIndex` grow over time.

4. **Read `isLiquidatable()`** — Follow the health check: for each collateral asset, fetch oracle price, multiply by collateral factor, sum up. Compare to borrow balance. This is the health factor equivalent, computed inline rather than as a separate ratio.

5. **Compare with Aave** — After reading both, you should be able to articulate: why did Compound choose a single-asset model? (Risk isolation.) Why immutables? (Gas.) Why signed principal? (Simplicity — no separate debt tokens.) These are the architectural trade-offs interviewers ask about.

**Don't get stuck on:** The `CometExt` fallback pattern. It's a workaround for the 24KB contract size limit — auxiliary functions are deployed separately and called via the fallback function. Understand that it exists, but focus on the core Comet logic.

---

### Exercise

**Exercise 1:** Read the Compound V3 [`getUtilization()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L413), [`getBorrowRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L423), and [`getSupplyRate()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L428) functions. For each, trace the math and verify it matches the kinked curve formula from Day 1.

**Exercise 2:** Compare Aave V3 and Compound V3 storage layout for user positions. Aave uses separate aToken and debtToken balances; Compound uses a single signed principal. Write a comparison document: what are the trade-offs of each approach for gas, composability, and complexity?

---

## Day 5: Liquidation Mechanics

### Why Liquidation Exists

**Why this matters:** Lending without credit checks requires overcollateralization. But crypto prices are volatile — collateral can lose value. Without liquidation, a $10,000 ETH collateral backing an $8,000 USDC loan could become worth $7,000, leaving the protocol with unrecoverable bad debt.

**Liquidation is the protocol's immune system.** It removes unhealthy positions before they can create bad debt, keeping the system solvent for all suppliers.

> **Real impact:** During the May 2021 crypto crash, [Aave processed $521M in liquidations](https://dune.com/queries/82373/162957) across 2,800+ positions in a single day. The system remained solvent — no bad debt accrued despite 40%+ price drops.

---

### The Liquidation Flow

**Step 1: Detection.** A position's health factor drops below 1 (meaning debt value exceeds collateral value × liquidation threshold). This happens when collateral price drops or debt value increases (from accrued interest or borrowed asset price increase).

**Step 2: A liquidator calls the liquidation function.** Liquidation is permissionless — anyone can do it. In practice, it's done by specialized bots that monitor all positions and submit transactions the moment a position becomes liquidatable.

**Step 3: Debt repayment.** The liquidator repays some or all of the borrower's debt (up to the close factor).

**Step 4: Collateral seizure.** The liquidator receives an equivalent value of the borrower's collateral, plus the liquidation bonus (discount). For example, repaying $5,000 of USDC debt might yield $5,250 worth of ETH (at 5% bonus).

**Step 5: Health factor restoration.** After liquidation, the borrower's health factor should be above 1 (smaller debt, proportionally less collateral).

---

### Aave V3 Liquidation

**Source:** [LiquidationLogic.sol → executeLiquidationCall()](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol#L48)

Key details:
- Caller specifies `collateralAsset`, `debtAsset`, `user`, and `debtToCover`
- Protocol validates HF < 1 using oracle prices
- **Close factor:** 50% normally. If HF < 0.95, the full 100% can be liquidated ([V3 improvement](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/LiquidationLogic.sol#L163) over V2's fixed 50%)
- **Minimum position:** Partial liquidations must leave at least $1,000 of both collateral and debt remaining — otherwise the position must be fully cleared (prevents dust accumulation)
- Liquidator can choose to receive aTokens (collateral stays in the protocol) or the underlying asset
- Oracle prices are fetched fresh during the liquidation call

> **Common pitfall:** Forgetting to approve the liquidator contract to spend the debt asset. The liquidation call transfers debt tokens from the liquidator to the protocol — this requires prior approval.

---

### Compound V3 Liquidation ("Absorb")

**Why this matters:** Compound V3 takes a different approach: **the protocol itself absorbs underwater positions**, rather than individual liquidators repaying debt.

**The [`absorb()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L773) function:**
1. Anyone can call `absorb(absorber, [accounts])` for one or more underwater accounts
2. The protocol seizes the underwater account's collateral and stores it internally
3. The underwater account's debt is written off (socialized across suppliers via a "deficit" in the protocol)
4. The caller (absorber) receives no direct compensation from the absorb itself

**The [`buyCollateral()`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L843) function:**
After absorption, the protocol holds seized collateral. Anyone can buy this collateral at a discount through `buyCollateral()`, paying in the base asset. The protocol uses the proceeds to cover the deficit. The discount follows a Dutch auction pattern — it starts small and increases over time until someone buys.

**This two-step process (absorb → buyCollateral) separates the urgency of removing bad positions from the market dynamics of selling collateral.** It prevents sandwich attacks on liquidations and gives the market time to find the right price.

> **Deep dive:** [Compound V3 absorb documentation](https://docs.compound.finance/collateral-and-borrowing/#absorb), [buyCollateral Dutch auction](https://docs.compound.finance/collateral-and-borrowing/#buying-absorbed-collateral)

---

### Liquidation Bot Economics

**Why this matters:** Running a liquidation bot is a competitive business:

**Revenue:** Liquidation bonus (typically 4–10% of seized collateral)

**Costs:**
- Gas for monitoring + execution
- Capital for repaying debt (or flash loan fees)
- Smart contract risk
- Oracle latency risk

**Competition:** Multiple bots compete for the same liquidation. In practice, the winner is often the one with the lowest latency to the mempool or the best MEV strategy (priority gas auctions, [Flashbots bundles](https://docs.flashbots.net/))

**Flash loan liquidations:** Liquidators can use flash loans to avoid needing capital — borrow the repayment asset, execute the liquidation, sell the seized collateral, repay the flash loan, keep the profit. All in one transaction.

> **Real impact:** During the May 2021 crash, liquidation bots earned an estimated $50M+ in bonuses across all protocols. The largest single liquidation on Aave was ~$30M collateral seized.

> **Deep dive:** [Flashbots MEV explore](https://explore.flashbots.net/) — real-time liquidation bot activity, [Eigenphi liquidation tracking](https://eigenphi.io/)

---

### Exercise

**Exercise 1: Build a liquidation scenario.** On an Aave V3 mainnet fork:
- Supply ETH as collateral (use `vm.deal` and `vm.prank`)
- Borrow USDC near the maximum LTV
- Use `vm.mockCall` to simulate a Chainlink price drop that pushes HF below 1
- Execute the liquidation call from a separate address
- Verify: debt decreased, collateral seized (including bonus), HF restored above 1

**Exercise 2: Flash loan liquidation.** Build a contract that:
- Takes a flash loan from Aave for the debt asset
- Uses it to liquidate an underwater position
- Sells the received collateral on Uniswap (or swap for the debt asset)
- Repays the flash loan
- Keeps the profit
- Test end-to-end on the mainnet fork

**Exercise 3: Compare liquidation economics.** Calculate the profit/loss for a liquidator who repays $10,000 of USDC debt against ETH collateral with a 5% bonus, given a flash loan fee of 0.09% and a Uniswap swap fee of 0.3%. What's the net profit? At what bonus percentage does liquidation become unprofitable?

---

## Day 6: Build a Simplified Lending Protocol

### SimpleLendingPool.sol

Build a minimal but correct lending protocol that incorporates everything from this module:

**State:**
```solidity
struct Reserve {
    uint256 totalSupplied;
    uint256 totalBorrowed;
    uint256 supplyIndex;      // RAY (27 decimals)
    uint256 borrowIndex;      // RAY
    uint256 lastUpdateTimestamp;
    uint256 reserveFactor;    // WAD (18 decimals)
}

struct UserPosition {
    uint256 scaledSupply;     // supply principal / supplyIndex at deposit
    uint256 scaledDebt;       // borrow principal / borrowIndex at borrow
    mapping(address => uint256) collateral;  // collateral token => amount
}

mapping(address => Reserve) public reserves;           // asset => reserve data
mapping(address => mapping(address => UserPosition)) public positions;  // user => asset => position
```

**Core functions:**

1. `supply(asset, amount)` — Transfer tokens in, update supply index, store scaled balance
2. `withdraw(asset, amount)` — Check health factor remains > 1 after withdrawal, transfer tokens out
3. `depositCollateral(asset, amount)` — Transfer collateral tokens in (no interest earned)
4. `borrow(asset, amount)` — Check health factor after borrow, mint scaled debt, transfer tokens out
5. `repay(asset, amount)` — Burn scaled debt, transfer tokens in. Handle `type(uint256).max` for full repayment (see [Aave's pattern](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/BorrowLogic.sol#L116) for handling dust from continuous interest accrual)
6. `liquidate(user, collateralAsset, debtAsset, debtAmount)` — Validate HF < 1, repay debt, seize collateral with bonus

**Supporting functions:**

7. `accrueInterest(asset)` — Update supply and borrow indexes using kinked rate model
8. `getHealthFactor(user)` — Sum collateral values × LT, sum debt values, compute ratio. Use Chainlink mock for prices.
9. `getAccountLiquidity(user)` — Return available borrow capacity

**Interest rate model:** Implement the kinked curve from Day 1 as a separate contract referenced by the pool.

**Oracle integration:** Use the safe Chainlink consumer pattern from Module 3. Mock the oracle in tests.

---

### Test Suite

Write comprehensive Foundry tests:

- **Happy path:** supply → borrow → accrue interest → repay → withdraw (verify balances at each step)
- **Interest accuracy:** supply, warp 365 days, verify balance matches expected APY within tolerance
- **Health factor boundary:** borrow right at the limit, verify HF ≈ LT/LTV ratio
- **Liquidation trigger:** manipulate oracle price to push HF below 1, execute liquidation, verify correct collateral seizure and debt reduction
- **Liquidation bonus math:** verify liquidator receives exactly (debtRepaid × (1 + bonus) / collateralPrice) collateral
- **Over-borrow revert:** attempt to borrow more than health factor allows, verify revert
- **Withdrawal blocked:** attempt to withdraw collateral that would make HF < 1, verify revert
- **Multiple collateral types:** deposit ETH + WBTC as collateral, borrow USDC, verify combined collateral valuation
- **Interest rate jumps:** push utilization past the kink, verify rate jumps to the steep slope
- **Reserve factor accumulation:** verify protocol's share of interest accumulates correctly

> **Common pitfall:** Not accounting for rounding errors in index calculations. Use a tolerance (e.g., ±1 wei) when comparing expected vs actual balances after interest accrual.

---

## Day 7: Synthesis and Advanced Patterns

### Architectural Comparison: Aave V3 vs Compound V3

| Dimension | Aave V3 | Compound V3 |
|-----------|---------|-------------|
| Borrowable assets | Multiple per pool | Single base asset per market |
| Collateral interest | Yes (aTokens accrue) | No |
| Debt representation | Non-transferable debt tokens | Signed principal in UserBasic |
| Parameter storage | Storage variables | Immutable variables (cheaper reads, costlier updates) |
| Interest rate model | Borrow rate from curve, supply derived | Independent supply and borrow curves |
| Liquidation model | Direct liquidator repays, receives collateral | Protocol absorbs, then Dutch auction for collateral |
| Risk isolation | E-Mode, Isolation Mode, Siloed Borrowing | Inherent via single-asset markets |
| Code size | ~15,000+ lines across libraries | ~4,300 lines in Comet |
| Upgrade path | Update logic libraries, keep proxy | Deploy new Comet, update proxy |

---

### Bad Debt and Protocol Solvency

**Why this matters:** What happens when collateral value drops so fast that liquidation can't happen in time? The position becomes underwater — debt exceeds collateral. This creates **bad debt** that the protocol must absorb.

**[Aave's approach](https://docs.aave.com/faq/aave-safety-module):** The Safety Module (staked AAVE) serves as a backstop. If bad debt accumulates, governance can trigger a "shortfall event" that slashes staked AAVE to cover losses. This is insurance funded by AAVE stakers who earn protocol revenue in return.

**Compound's approach:** The [`absorb`](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L773) function socializes the loss across all suppliers (the protocol's reserves decrease). The subsequent `buyCollateral()` Dutch auction recovers what it can.

> **Real impact:** During the [CRV liquidity crisis](https://cointelegraph.com/news/curve-founder-s-300m-loans-teeter-on-liquidation) (November 2023), several Aave markets accumulated bad debt from a large borrower whose CRV collateral couldn't be liquidated fast enough due to thin liquidity. This led to governance discussions about tightening risk parameters for illiquid assets — and informed the design of Isolation Mode and supply/borrow caps in V3.

---

### The Liquidation Cascade Problem

**Why this matters:** When crypto prices drop sharply, many positions become liquidatable simultaneously. Liquidators selling seized collateral on DEXes pushes prices down further, triggering more liquidations. This positive feedback loop is a **liquidation cascade**.

**Defenses:**
- **Gradual liquidation (close factor < 100%):** Prevents dumping all collateral at once
- **Liquidation bonus calibration:** Too high = excessive selling pressure; too low = no incentive to liquidate
- **Oracle smoothing / [PriceOracleSentinel](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/configuration/PriceOracleSentinel.sol):** Delays liquidations briefly after sequencer recovery on L2 to let prices stabilize
- **Supply/borrow caps:** Limit total exposure so cascades can't grow unbounded

> **Real impact:** The March 2020 "Black Thursday" crash saw [over $8M in bad debt on Maker](https://blog.makerdao.com/the-market-collapse-of-march-12-2020-how-it-impacted-makerdao/) due to liquidation cascades and network congestion preventing timely liquidations. This informed V2/V3 risk parameter designs.

---

### Emerging Patterns

**[Morpho](https://github.com/morpho-org/morpho-blue):** A lending protocol that optimizes rates by matching suppliers and borrowers peer-to-peer when possible, falling back to Aave/Compound pools for unmatched liquidity. Uses Aave/Compound as a "backstop pool."

**[Euler V2](https://docs.euler.finance):** Modular architecture where each vault has its own risk parameters. Vaults can connect to each other, creating a graph of lending relationships rather than a single pool.

**Variable liquidation incentives:** Some protocols adjust the liquidation bonus dynamically based on how far underwater a position is, how much collateral is being liquidated, and current market conditions.

---

### Exercise

**Exercise 1: Liquidation cascade simulation.** Using your SimpleLendingPool from Day 6, set up 5 users with progressively tighter health factors. Drop the oracle price in steps. After each drop, execute available liquidations. Track how each liquidation changes the "market" (the oracle price reflects the collateral being sold). Does the cascade stabilize or spiral?

**Exercise 2: Bad debt scenario.** Configure your pool with a very volatile collateral. Use `vm.warp` and `vm.mockCall` to simulate a 50% price crash in a single block (too fast for liquidation). Show the resulting bad debt. Implement a `handleBadDebt()` function that socializes the loss across suppliers.

**Exercise 3: Read Morpho's matching engine.** Skim the [Morpho Blue codebase](https://github.com/morpho-org/morpho-blue). Focus on how the matching works: when does a user get peer-to-peer rates vs pool rates? How does this differ from Aave/Compound's architecture? No build — just analysis.

---

## Key Takeaways

**1. Interest rates are mechanism design.** The kinked curve isn't arbitrary — it's a carefully calibrated incentive system that uses price signals (rates) to maintain liquidity equilibrium. When you build a protocol that needs to balance supply and demand, this pattern is reusable.

**2. Indexes are the universal scaling pattern.** Every lending protocol uses global indexes to amortize per-user interest computation. You'll see this pattern again in vaults (Module 7) and staking systems.

**3. Liquidation is the protocol's immune system.** Without it, the first price crash would create cascading insolvency. The entire lending model depends on liquidation being reliable, fast, and properly incentivized.

**4. Oracle integration is load-bearing.** Everything in lending — health factor, liquidation trigger, collateral valuation — depends on accurate, timely price data. The oracle patterns from Module 3 aren't theoretical here; they're the difference between a $20B protocol and a drained one.

**5. Architectural trade-offs are real.** Aave's multi-asset pools offer flexibility and composability (yield-bearing aTokens). Compound's single-asset markets offer simplicity and risk isolation. Neither is strictly better — your choice depends on what you're building.

---

## Resources

**Aave V3:**
- [Protocol documentation](https://docs.aave.com/developers/getting-started/readme)
- [Source code](https://github.com/aave/aave-v3-core) (deployed May 2022)
- [Risk parameters dashboard](https://app.aave.com)
- [Technical paper](https://github.com/aave/aave-v3-core/blob/master/techpaper/Aave_V3_Technical_Paper.pdf)
- [MixBytes architecture analysis](https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-aave-v3)
- [Cyfrin Aave V3 course](https://updraft.cyfrin.io/courses/aave-v3)

**Compound V3:**
- [Documentation](https://docs.compound.finance)
- [Source code](https://github.com/compound-finance/comet) (deployed August 2022)
- [RareSkills Compound V3 Book](https://rareskills.io/compound-v3-book)
- [RareSkills architecture walkthrough](https://rareskills.io/post/compound-v3-contracts-tutorial)

**Interest rate models:**
- [RareSkills — Aave/Compound interest rate models](https://rareskills.io/post/aave-interest-rate-model)
- [Aave interest rate strategy contracts](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/DefaultReserveInterestRateStrategyV2.sol) (on-chain)

**Advanced:**
- [Morpho Blue](https://github.com/morpho-org/morpho-blue) — peer-to-peer optimization layer
- [Euler V2](https://docs.euler.finance) — modular vault architecture
- [Berkeley DeFi MOOC — Lending protocols](https://berkeley-defi.github.io)

**Exploits and postmortems:**
- [Euler Finance postmortem](https://rekt.news/euler-rekt/) — $197M donation attack
- [Radiant Capital postmortem](https://rekt.news/radiant-rekt/) — $58M flash loan manipulation
- [Rari Capital/Fuse postmortem](https://rekt.news/rari-capital-rekt/) — $80M reentrancy
- [Cream Finance postmortem](https://rekt.news/cream-rekt-2/) — $130M oracle manipulation
- [Hundred Finance postmortem](https://rekt.news/hundred-rekt/) — $7M [ERC-777](https://eips.ethereum.org/EIPS/eip-777) reentrancy
- [Venus Protocol postmortem](https://rekt.news/venus-blizz-rekt/) — $11M stale oracle
- [CRV liquidity crisis analysis](https://cointelegraph.com/news/curve-founder-s-300m-loans-teeter-on-liquidation) — bad debt accumulation
- [MakerDAO Black Thursday report](https://blog.makerdao.com/the-market-collapse-of-march-12-2020-how-it-impacted-makerdao/) — liquidation cascades

---

## Practice Challenges

- **[Damn Vulnerable DeFi #2 "Naive Receiver"](https://www.damnvulnerabledefi.xyz/)** — A flash loan receiver that can be drained by anyone initiating loans on its behalf. Tests your understanding of flash loan receiver security (directly relevant to Module 5).
- **[Ethernaut #16 "Preservation"](https://ethernaut.openzeppelin.com/level/0x97E982a15FbB1C28F6B8ee971BEc15C78b3d263F)** — Delegatecall with storage collision. Relevant to understanding how proxy patterns (Part 1 Section 6) can go wrong in lending protocol upgrades.

---

*Next module: Flash Loans (~3 days) — atomic uncollateralized borrowing, Aave/Balancer flash loan mechanics, composing multi-step arbitrage and liquidation flows.*

# Part 2 — Module 4: Lending & Borrowing

**Duration:** ~7 days (3–4 hours/day)
**Prerequisites:** Modules 1–3 (tokens, AMMs, oracles)
**Pattern:** Math → Read Aave V3 → Read Compound V3 → Build simplified protocol → Liquidation deep dive
**Builds on:** Module 1 (SafeERC20), Module 3 (Chainlink consumer, staleness checks), Part 1 Section 5 (invariant testing, fork testing)
**Used by:** Module 5 (flash loan liquidation), Module 8 (invariant testing your lending pool), Module 9 (integration capstone)

---

## Why This Module Is the Longest After AMMs

Lending is where everything you've learned converges. Token mechanics (Module 1) govern how assets move in and out. Oracle integration (Module 3) determines collateral valuation and liquidation triggers. And the interest rate math shares DNA with the constant product formula from AMMs (Module 2) — both are mechanism design problems where smart contracts use mathematical curves to balance supply and demand without human intervention.

Lending protocols are also the highest-TVL category in DeFi. Aave alone holds over $18 billion. If you're building DeFi products, you'll either build a lending protocol, integrate with one, or compete with one. Understanding the internals is non-negotiable.

---

## Day 1: The Lending Model from First Principles

### How DeFi Lending Works

Traditional lending requires a bank to assess creditworthiness, set terms, and enforce repayment. DeFi lending replaces all of this with overcollateralization and algorithmic liquidation.

The core loop:

1. **Suppliers** deposit assets (e.g., USDC) into a pool. They earn interest from borrowers.
2. **Borrowers** deposit collateral (e.g., ETH), then borrow from the pool (e.g., USDC) up to a limit determined by their collateral's value and the protocol's risk parameters.
3. **Interest** accrues continuously. Borrowers pay it; suppliers receive it (minus a protocol cut called the reserve factor).
4. **If collateral value drops** (or debt grows) past a threshold, the position becomes eligible for **liquidation** — a third party repays part of the debt and receives the collateral at a discount.

No credit checks. No loan officers. No repayment schedule. Borrowers can hold positions indefinitely as long as they remain overcollateralized.

### Key Parameters

**Loan-to-Value (LTV):** The maximum ratio of borrowed value to collateral value at the time of borrowing. If ETH has an LTV of 80%, depositing $10,000 of ETH lets you borrow up to $8,000.

**Liquidation Threshold (LT):** The ratio at which a position becomes liquidatable. Always higher than LTV (e.g., 82.5% for ETH). The gap between LTV and LT is the borrower's safety buffer.

**Health Factor:** The single number that determines whether a position is safe:

```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value
```

HF > 1 = safe. HF < 1 = eligible for liquidation. HF = 1.5 means the collateral could lose 33% of its value before liquidation.

**Liquidation Bonus (Penalty):** The discount a liquidator receives on seized collateral (e.g., 5%). This incentivizes liquidators to monitor and act quickly, keeping the protocol solvent.

**Reserve Factor:** The percentage of interest that goes to the protocol treasury rather than suppliers (typically 10–25%). This builds a reserve fund for bad debt coverage.

**Close Factor:** How much of the debt a liquidator can repay in a single liquidation. Aave V3 uses 50% normally, but allows 100% when HF < 0.95 to clear dangerous positions faster.

### Interest Rate Models: The Kinked Curve

The interest rate model is the mechanism that balances supply and demand for each asset pool. Every major lending protocol uses some variant of a piecewise linear "kinked" curve.

**Utilization rate:**
```
U = Total Borrowed / Total Supplied
```

When U is low, there's plenty of liquidity — rates should be low to encourage borrowing. When U is high, liquidity is scarce — rates should spike to attract suppliers and discourage borrowing. If U hits 100%, suppliers can't withdraw. That's a crisis.

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

**Supply rate derivation:**
```
SupplyRate = BorrowRate × U × (1 - ReserveFactor)
```

Suppliers earn a fraction of what borrowers pay, reduced by utilization (not all capital is lent out) and the reserve factor (the protocol's cut).

**Why the kink matters:** Without it, rates would rise linearly and might not create urgency for borrowers to repay during liquidity crunches. The kink ensures that past a certain point, borrowing becomes extremely expensive very quickly. During the March 2020 crash, Aave's USDC borrow rate spiked past 50% APR when utilization hit 98%.

### Interest Accrual: Indexes and Scaling

Interest doesn't accrue by updating every user's balance every second. That would be impossibly expensive. Instead, protocols use a **global index** that compounds over time:

```
currentIndex = previousIndex × (1 + ratePerSecond × timeElapsed)
```

A user's actual balance is:
```
actualBalance = storedPrincipal × currentIndex / indexAtDeposit
```

When a user deposits, the protocol stores their `principal` and the current index. When they withdraw, the protocol computes their balance using the latest index. This means the protocol only needs to update one global variable, not millions of individual balances.

**Compound interest approximation:** Aave V3 uses a binomial expansion to approximate `(1 + r)^n` on-chain, which is cheaper than computing exponents. For small `r` (per-second rates are tiny), the approximation is extremely accurate.

### Exercise: Build the Math

**Exercise 1:** Implement a `KinkedInterestRate.sol` contract with:
- `getUtilization(totalSupply, totalBorrow)` → returns U as a WAD (18 decimals)
- `getBorrowRate(utilization)` → returns per-second borrow rate using two-slope model
- `getSupplyRate(utilization, borrowRate, reserveFactor)` → returns per-second supply rate
- Configurable parameters: baseRate, slope1, slope2, optimalUtilization, reserveFactor

**Exercise 2:** Implement an `InterestAccumulator.sol` that:
- Maintains a global `supplyIndex` and `borrowIndex`
- Exposes `accrueInterest()` which updates both indexes based on elapsed time and current rates
- Exposes `balanceOf(user)` which returns the user's scaled balance using the current index
- Test: deposit at t=0, warp forward 1 year, verify the balance matches expected APY

---

## Day 2: Aave V3 Architecture — Supply and Borrow

### Contract Architecture Overview

Aave V3 uses a proxy pattern with logic delegated to libraries. The entry point is the **Pool** contract (behind a proxy), which delegates to specialized logic libraries:

```
User → Pool (proxy)
         ├─ SupplyLogic
         ├─ BorrowLogic
         ├─ LiquidationLogic
         ├─ FlashLoanLogic
         ├─ BridgeLogic
         └─ EModeLogic
```

Supporting contracts:
- **PoolAddressesProvider:** Registry for all protocol contracts. Single source of truth for addresses.
- **AaveOracle:** Wraps Chainlink feeds. Each asset has a registered price source.
- **PoolConfigurator:** Governance-controlled contract that sets risk parameters (LTV, LT, reserve factor, caps).
- **PriceOracleSentinel:** L2-specific — checks sequencer uptime before allowing liquidations.

### aTokens: Interest-Bearing Receipts

When you supply USDC, you receive **aUSDC**. This is an ERC-20 token whose balance *automatically increases* over time as interest accrues. You don't need to claim anything — your `balanceOf()` result grows continuously.

**How it works internally:**

aTokens store a "scaled balance" (principal divided by the current liquidity index). The `balanceOf()` function multiplies the scaled balance by the current index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedIncome(asset));
}
```

`getReserveNormalizedIncome()` returns the current supply index, which grows every second based on the supply rate. This design means:
- Transferring aTokens transfers the proportional claim on the pool (including future interest)
- aTokens are composable — they can be used in other DeFi protocols as yield-bearing collateral
- No explicit "harvest" or "claim" step for interest

### Debt Tokens: Tracking What's Owed

When you borrow, the protocol mints **variableDebtTokens** (or stable debt tokens, though stable rate borrowing is being deprecated) to your address. These are non-transferable ERC-20 tokens whose balance *increases* over time as interest accrues on your debt.

The mechanics mirror aTokens but use the borrow index instead of the supply index:

```solidity
function balanceOf(address user) public view returns (uint256) {
    return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedVariableDebt(asset));
}
```

Debt tokens being non-transferable is a deliberate security choice — you can't transfer your debt to someone else without their consent (credit delegation notwithstanding).

### Read: Supply Flow

Trace the supply path through Aave V3:

1. User calls `Pool.supply(asset, amount, onBehalfOf, referralCode)`
2. Pool delegates to `SupplyLogic.executeSupply()`
3. Logic validates the reserve is active and not paused
4. Updates the reserve's indexes (accrues interest up to this moment)
5. Transfers the underlying asset from user to the aToken contract
6. Mints aTokens to the `onBehalfOf` address (scaled by current index)
7. Updates the user's configuration bitmap (tracks which assets are supplied/borrowed)

**Source:** `aave-v3-core/contracts/protocol/libraries/logic/SupplyLogic.sol`

### Read: Borrow Flow

1. User calls `Pool.borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)`
2. Pool delegates to `BorrowLogic.executeBorrow()`
3. Logic validates: reserve active, borrowing enabled, amount ≤ borrow cap
4. Validates the user's health factor will remain > 1 after the borrow
5. Mints debt tokens to the borrower (or `onBehalfOf` for credit delegation)
6. Transfers the underlying asset from the aToken contract to the user
7. Updates the interest rate for the reserve (utilization changed)

**Key insight:** The health factor check happens *before* the tokens are transferred. If the borrow would make the position undercollateralized, it reverts.

### Credit Delegation

The `onBehalfOf` parameter enables credit delegation: Alice can allow Bob to borrow using her collateral. Alice's health factor is affected, but Bob receives the borrowed assets. This is done through `approveDelegation()` on the debt token contract.

### Exercise: Fork and Interact

**Exercise 1:** Fork Ethereum mainnet. Using Foundry's `vm.prank()`, simulate a full supply → borrow → repay → withdraw cycle on Aave V3. Verify aToken and debt token balances at each step.

**Exercise 2:** Inspect the `ReserveData` struct for USDC on the forked state. Extract: liquidityIndex, variableBorrowIndex, currentLiquidityRate, currentVariableBorrowRate, configuration (decode the bitmap to get LTV, liquidation threshold, etc.). This builds familiarity with how Aave stores state.

---

## Day 3: Aave V3 — Risk Modes and Advanced Features

### Efficiency Mode (E-Mode)

E-Mode allows higher capital efficiency when collateral and borrowed assets are correlated. For example, borrowing USDC against DAI — both are USD stablecoins, so the risk of the collateral losing value relative to the debt is minimal.

When a user activates an E-Mode category (e.g., "USD stablecoins"), the protocol overrides the standard LTV and liquidation threshold with higher values specific to that category. A stablecoin category might allow 97% LTV vs the normal 75%.

E-Mode categories can also specify a custom oracle. For stablecoin-to-stablecoin, a fixed 1:1 oracle might be used instead of market price feeds, eliminating unnecessary liquidations from minor depeg events.

### Isolation Mode

New or volatile assets can be listed in Isolation Mode. When a user supplies an isolated asset as collateral:
- They cannot use any other assets as collateral simultaneously
- They can only borrow assets approved for isolation mode (typically stablecoins)
- There's a hard debt ceiling for the isolated asset across all users

This prevents a volatile long-tail asset from threatening the entire protocol. If SHIB were listed in isolation mode with a $1M debt ceiling, even a complete collapse of SHIB's price could only create $1M of potential bad debt.

### Siloed Borrowing

Assets with manipulatable oracles (e.g., tokens with thin liquidity that could be subject to the oracle attacks from Module 3) can be listed as "siloed." Users borrowing siloed assets can only borrow that single asset — no mixing with other borrows.

### Supply and Borrow Caps

V3 introduces governance-set caps per asset:
- **Supply cap:** Maximum total deposits. Prevents excessive concentration of a single collateral asset.
- **Borrow cap:** Maximum total borrows. Limits the protocol's exposure to any single borrowed asset.

These are simple but critical risk controls that didn't exist in V2.

### Virtual Balance Layer

Aave V3 tracks balances internally rather than relying on actual `balanceOf()` calls to the token contract. This protects against donation attacks (someone sending tokens directly to the aToken contract to manipulate share ratios) and makes accounting predictable regardless of external token transfers like airdrops.

### Read: Configuration Bitmap

Aave V3 packs all risk parameters for a reserve into a single `uint256` bitmap in `ReserveConfigurationMap`. This is extreme gas optimization:

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

**Source:** `ReserveConfiguration.sol` — read the getter/setter library functions to understand bitwise manipulation patterns used throughout production DeFi.

### Exercise

**Exercise 1:** On a mainnet fork, activate E-Mode for a user position (stablecoin category). Compare the borrowing power before and after. Verify the LTV and liquidation threshold change.

**Exercise 2:** Read the `PoolConfigurator.sol` contract. Trace how `configureReserveAsCollateral()` encodes LTV, liquidation threshold, and liquidation bonus into the bitmap. Write a helper contract that decodes a raw bitmap into a human-readable struct.

---

## Day 4: Compound V3 (Comet) — A Different Architecture

### Why Study Both Aave and Compound

Aave V3 and Compound V3 represent two fundamentally different architectural approaches to the same problem. Understanding both gives you the design vocabulary to make informed choices when building your own protocol.

### The Single-Asset Model

Compound V3's key architectural decision: **each market only lends one asset** (the "base asset," typically USDC). This is a radical departure from V2 and from Aave, where every asset in the pool can be both collateral and borrowable.

Implications:
- **Simpler risk model:** There's no cross-asset risk contagion. If one collateral asset collapses, it can only affect the single base asset pool.
- **Collateral doesn't earn interest.** Your ETH or wBTC sitting as collateral in Compound V3 earns nothing. This is the trade-off for the simpler, safer architecture.
- **Separate markets for each base asset.** There's a USDC market and an ETH market — completely independent contracts with separate parameters.

### Comet Contract Architecture

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

Supporting contracts:
- **CometExt:** Handles overflow functions that don't fit in the main contract (24KB limit workaround via the fallback extension pattern)
- **Configurator:** Sets parameters, deploys new Comet implementations when governance changes settings
- **CometFactory:** Deploys new Comet instances
- **Rewards:** Distributes COMP token incentives (separate from the lending logic)

### Immutable Variables: A Unique Design Choice

Compound V3 stores all parameters (interest rate model coefficients, collateral factors, liquidation factors) as **immutable variables**, not storage. To change any parameter, governance must deploy an entirely new Comet implementation and update the proxy.

Why? Immutable variables are significantly cheaper to read than storage (3 gas vs 2100 gas for cold SLOAD). Since rate calculations happen on every interaction, this saves substantial gas across millions of transactions. The trade-off is governance friction — changing a parameter requires a full redeployment, not just a storage write.

### Principal and Index Accounting

Compound V3 tracks balances using a principal/index system similar to Aave but with a twist: the principal is a **signed integer**. Positive means the user is a supplier; negative means they're a borrower. There's no separate debt token.

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
If principal < 0: balance = principal × borrowIndex / indexScale
```

### Separate Supply and Borrow Rate Curves

Unlike Aave (where supply rate is derived from borrow rate), Compound V3 defines **independent** kinked curves for both supply and borrow rates. Both are functions of utilization with their own base rates, kink points, and slopes. This gives governance more flexibility but means the spread isn't automatically guaranteed.

### Read: Comet.sol Core Functions

**Source:** `compound-finance/comet/contracts/Comet.sol`

Key functions to read:
- `supplyInternal()`: How supply is processed, including the `repayAndSupplyAmount()` split (if user has debt, supply first repays debt, then adds to balance)
- `withdrawInternal()`: How withdrawal works, including automatic borrow creation if withdrawing more than supplied
- `getSupplyRate()` / `getBorrowRate()`: The kinked curve implementations — note separate supply/borrow kink parameters
- `accrueInternal()`: How indexes are updated using `block.timestamp` and per-second rates
- `isLiquidatable()`: Health check using collateral factors and oracle prices

**Note:** Compound V3 is ~4,300 lines of Solidity (excluding comments). This is compact for a lending protocol and very readable.

### Exercise

**Exercise 1:** Read the Compound V3 `getUtilization()`, `getBorrowRate()`, and `getSupplyRate()` functions. For each, trace the math and verify it matches the kinked curve formula from Day 1.

**Exercise 2:** Compare Aave V3 and Compound V3 storage layout for user positions. Aave uses separate aToken and debtToken balances; Compound uses a single signed principal. Write a comparison document: what are the trade-offs of each approach for gas, composability, and complexity?

---

## Day 5: Liquidation Mechanics

### Why Liquidation Exists

Lending without credit checks requires overcollateralization. But crypto prices are volatile — collateral can lose value. Without liquidation, a $10,000 ETH collateral backing a $8,000 USDC loan could become worth $7,000, leaving the protocol with unrecoverable bad debt.

Liquidation is the protocol's immune system. It removes unhealthy positions before they can create bad debt, keeping the system solvent for all suppliers.

### The Liquidation Flow

**Step 1: Detection.** A position's health factor drops below 1 (meaning debt value exceeds collateral value × liquidation threshold). This happens when collateral price drops or debt value increases (from accrued interest or borrowed asset price increase).

**Step 2: A liquidator calls the liquidation function.** Liquidation is permissionless — anyone can do it. In practice, it's done by specialized bots that monitor all positions and submit transactions the moment a position becomes liquidatable.

**Step 3: Debt repayment.** The liquidator repays some or all of the borrower's debt (up to the close factor).

**Step 4: Collateral seizure.** The liquidator receives an equivalent value of the borrower's collateral, plus the liquidation bonus (discount). For example, repaying $5,000 of USDC debt might yield $5,250 worth of ETH (at 5% bonus).

**Step 5: Health factor restoration.** After liquidation, the borrower's health factor should be above 1 (smaller debt, proportionally less collateral).

### Aave V3 Liquidation

**Source:** `LiquidationLogic.sol` → `executeLiquidationCall()`

Key details:
- Caller specifies `collateralAsset`, `debtAsset`, `user`, and `debtToCover`
- Protocol validates HF < 1 using oracle prices
- **Close factor:** 50% normally. If HF < 0.95, the full 100% can be liquidated (V3 improvement over V2's fixed 50%)
- **Minimum position:** Partial liquidations must leave at least $1,000 of both collateral and debt remaining — otherwise the position must be fully cleared (prevents dust accumulation)
- Liquidator can choose to receive aTokens (collateral stays in the protocol) or the underlying asset
- Oracle prices are fetched fresh during the liquidation call

### Compound V3 Liquidation ("Absorb")

Compound V3 takes a different approach: **the protocol itself absorbs underwater positions**, rather than individual liquidators repaying debt.

**The `absorb()` function:**
1. Anyone can call `absorb(absorber, [accounts])` for one or more underwater accounts
2. The protocol seizes the underwater account's collateral and stores it internally
3. The underwater account's debt is written off (socialized across suppliers via a "deficit" in the protocol)
4. The caller (absorber) receives no direct compensation from the absorb itself

**The `buyCollateral()` function:**
After absorption, the protocol holds seized collateral. Anyone can buy this collateral at a discount through `buyCollateral()`, paying in the base asset. The protocol uses the proceeds to cover the deficit. The discount follows a Dutch auction pattern — it starts small and increases over time until someone buys.

This two-step process (absorb → buyCollateral) separates the urgency of removing bad positions from the market dynamics of selling collateral. It prevents sandwich attacks on liquidations and gives the market time to find the right price.

### Liquidation Bot Economics

Running a liquidation bot is a competitive business:
- **Revenue:** Liquidation bonus (typically 4–10% of seized collateral)
- **Costs:** Gas for monitoring + execution, capital for repaying debt, smart contract risk, oracle latency risk
- **Competition:** Multiple bots compete for the same liquidation. In practice, the winner is often the one with the lowest latency to the mempool or the best MEV strategy (priority gas auctions, Flashbots bundles)
- **Flash loan liquidations:** Liquidators can use flash loans to avoid needing capital — borrow the repayment asset, execute the liquidation, sell the seized collateral, repay the flash loan, keep the profit. All in one transaction.

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
5. `repay(asset, amount)` — Burn scaled debt, transfer tokens in. Handle `type(uint256).max` for full repayment (see Aave's pattern for handling dust from continuous interest accrual)
6. `liquidate(user, collateralAsset, debtAsset, debtAmount)` — Validate HF < 1, repay debt, seize collateral with bonus

**Supporting functions:**

7. `accrueInterest(asset)` — Update supply and borrow indexes using kinked rate model
8. `getHealthFactor(user)` — Sum collateral values × LT, sum debt values, compute ratio. Use Chainlink mock for prices.
9. `getAccountLiquidity(user)` — Return available borrow capacity

**Interest rate model:** Implement the kinked curve from Day 1 as a separate contract referenced by the pool.

**Oracle integration:** Use the safe Chainlink consumer pattern from Module 3. Mock the oracle in tests.

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

### Bad Debt and Protocol Solvency

What happens when collateral value drops so fast that liquidation can't happen in time? The position becomes underwater — debt exceeds collateral. This creates **bad debt** that the protocol must absorb.

**Aave's approach:** The Safety Module (staked AAVE) serves as a backstop. If bad debt accumulates, governance can trigger a "shortfall event" that slashes staked AAVE to cover losses. This is insurance funded by AAVE stakers who earn protocol revenue in return.

**Compound's approach:** The `absorb` function socializes the loss across all suppliers (the protocol's reserves decrease). The subsequent `buyCollateral()` Dutch auction recovers what it can.

**Real-world bad debt events:** During the CRV liquidity crisis in late 2023, several Aave markets accumulated bad debt from a large borrower whose CRV collateral couldn't be liquidated fast enough due to thin liquidity. This led to governance discussions about tightening risk parameters for illiquid assets — and informed the design of Isolation Mode and supply/borrow caps in V3.

### The Liquidation Cascade Problem

When crypto prices drop sharply, many positions become liquidatable simultaneously. Liquidators selling seized collateral on DEXes pushes prices down further, triggering more liquidations. This positive feedback loop is a **liquidation cascade**.

Defenses:
- **Gradual liquidation (close factor < 100%):** Prevents dumping all collateral at once
- **Liquidation bonus calibration:** Too high = excessive selling pressure; too low = no incentive to liquidate
- **Oracle smoothing / PriceOracleSentinel:** Delays liquidations briefly after sequencer recovery on L2 to let prices stabilize
- **Supply/borrow caps:** Limit total exposure so cascades can't grow unbounded

### Emerging Patterns

**Morpho:** A lending protocol that optimizes rates by matching suppliers and borrowers peer-to-peer when possible, falling back to Aave/Compound pools for unmatched liquidity. Uses Aave/Compound as a "backstop pool."

**Euler V2:** Modular architecture where each vault has its own risk parameters. Vaults can connect to each other, creating a graph of lending relationships rather than a single pool.

**Variable liquidation incentives:** Some protocols adjust the liquidation bonus dynamically based on how far underwater a position is, how much collateral is being liquidated, and current market conditions.

### Exercise

**Exercise 1: Liquidation cascade simulation.** Using your SimpleLendingPool from Day 6, set up 5 users with progressively tighter health factors. Drop the oracle price in steps. After each drop, execute available liquidations. Track how each liquidation changes the "market" (the oracle price reflects the collateral being sold). Does the cascade stabilize or spiral?

**Exercise 2: Bad debt scenario.** Configure your pool with a very volatile collateral. Use `vm.warp` and `vm.mockCall` to simulate a 50% price crash in a single block (too fast for liquidation). Show the resulting bad debt. Implement a `handleBadDebt()` function that socializes the loss across suppliers.

**Exercise 3: Read Morpho's matching engine.** Skim the Morpho Blue codebase (`morpho-org/morpho-blue`). Focus on how the matching works: when does a user get peer-to-peer rates vs pool rates? How does this differ from Aave/Compound's architecture? No build — just analysis.

---

## Key Takeaways

1. **Interest rates are mechanism design.** The kinked curve isn't arbitrary — it's a carefully calibrated incentive system that uses price signals (rates) to maintain liquidity equilibrium. When you build a protocol that needs to balance supply and demand, this pattern is reusable.

2. **Indexes are the universal scaling pattern.** Every lending protocol uses global indexes to amortize per-user interest computation. You'll see this pattern again in vaults (Module 7) and staking systems.

3. **Liquidation is the protocol's immune system.** Without it, the first price crash would create cascading insolvency. The entire lending model depends on liquidation being reliable, fast, and properly incentivized.

4. **Oracle integration is load-bearing.** Everything in lending — health factor, liquidation trigger, collateral valuation — depends on accurate, timely price data. The oracle patterns from Module 3 aren't theoretical here; they're the difference between a $20B protocol and a drained one.

5. **Architectural trade-offs are real.** Aave's multi-asset pools offer flexibility and composability (yield-bearing aTokens). Compound's single-asset markets offer simplicity and risk isolation. Neither is strictly better — your choice depends on what you're building.

---

## Resources

**Aave V3:**
- Protocol documentation: https://aave.com/docs/aave-v3/overview
- Source code: https://github.com/aave/aave-v3-core
- Risk parameters dashboard: https://app.aave.com
- MixBytes architecture analysis: https://mixbytes.io/blog/modern-defi-lending-protocols-how-its-made-aave-v3
- Cyfrin Aave V3 course: https://updraft.cyfrin.io/courses/aave-v3

**Compound V3:**
- Documentation: https://docs.compound.finance
- Source code: https://github.com/compound-finance/comet
- RareSkills Compound V3 Book: https://rareskills.io/compound-v3-book
- RareSkills architecture walkthrough: https://rareskills.io/post/compound-v3-contracts-tutorial

**Interest rate models:**
- RareSkills — Aave/Compound interest rate models: https://rareskills.io/post/aave-interest-rate-model
- Aave interest rate strategy contracts (on-chain): check Etherscan for DefaultReserveInterestRateStrategyV2

**Advanced:**
- Morpho Blue: https://github.com/morpho-org/morpho-blue
- Euler V2: https://docs.euler.finance
- Berkeley DeFi MOOC — Lending protocols paper: https://berkeley-defi.github.io

---

## Practice Challenges

- **Damn Vulnerable DeFi #2 "Naive Receiver"** — A flash loan receiver that can be drained by anyone initiating loans on its behalf. Tests your understanding of flash loan receiver security (directly relevant to Module 5).
- **Ethernaut #16 "Preservation"** — Delegatecall with storage collision. Relevant to understanding how proxy patterns (Part 1 Section 6) can go wrong in lending protocol upgrades.

---

*Next module: Flash Loans (~3 days) — atomic uncollateralized borrowing, Aave/Balancer flash loan mechanics, composing multi-step arbitrage and liquidation flows.*

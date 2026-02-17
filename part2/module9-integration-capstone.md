# Part 2 — Module 9: Integration Capstone

**Duration:** ~2-3 days (3–4 hours/day)
**Prerequisites:** Modules 1–8 complete
**Pattern:** Integrate → Wire → Stress test → Retrospective
**Builds on:** Module 2 (AMM), Module 3 (oracles), Module 4 (lending), Module 5 (flash loans), Module 7 (ERC-4626 vaults)

---

## Why This Module Exists

You've spent 7+ modules building isolated protocols — an AMM here, a lending pool there, a flash loan receiver somewhere else. But real DeFi doesn't work in isolation. Uniswap pools feed Aave liquidations. Flash loans fund arbitrage across multiple DEXes. Vault tokens serve as collateral in lending markets. The integration points are where the hardest bugs live — interface mismatches, decimal normalization, gas overhead from multiple external calls, and composability risks that no individual module prepares you for.

This capstone forces you to wire your builds together into a single system and discover what breaks.

---

## The Project: Flash-Loan-Powered Liquidation System

You'll build a complete liquidation system that combines five of your previous builds:

1. **SimpleLendingPool** (Module 4) — the lending protocol with health factors, liquidation mechanics, and interest accrual
2. **OracleConsumer** (Module 3) — Chainlink price feed integration with staleness checks
3. **ConstantProductPool** (Module 2) — your AMM for swapping seized collateral to debt asset
4. **Flash loan receiver** (Module 5) — zero-capital liquidation via Aave/Balancer flash loans
5. **ERC-4626 vault shares** (Module 7) — accepted as a collateral type in the lending pool

The end result: a system where anyone can liquidate underwater positions on your lending protocol with zero capital, using flash loans to fund the liquidation and your AMM to convert collateral.

---

## Day 1: Wire the Protocols Together

### Step 1: Set Up the Integrated Environment

Create a new directory in your Part 2 workspace for the capstone. You'll import contracts from previous modules and deploy them together.

```
part2-workspace/src/module9/
├── IntegratedLendingPool.sol    # Module 4 lending pool, adapted
├── FlashLiquidator.sol          # The flash loan liquidation bot
└── test/
    ├── IntegrationTest.t.sol    # Full integration test suite
    └── InvariantTest.t.sol      # System-wide invariants
```

### Step 2: Deploy the Full Stack

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

### Step 3: Integration Issues You'll Encounter

This is where the learning happens. You will likely hit:

**Decimal normalization:** ETH has 18 decimals, USDC has 6, Chainlink ETH/USD has 8. Your lending pool's health factor calculation needs to normalize all of these correctly. Off-by-one in decimal scaling is one of the most common integration bugs.

**Oracle price vs AMM price:** Your Chainlink mock might return $3,000 for ETH, but your AMM pool's ratio implies a different price (based on reserves). The lending pool uses the oracle; the liquidator swaps on the AMM. If these diverge significantly, the liquidation might not be profitable even with the bonus.

**Vault share pricing:** When using ERC-4626 shares as collateral, you need to price them. The naive approach calls `vault.convertToAssets(shares)`, but as Module 7 taught you, this can be manipulated. For this exercise, use the vault's internal rate but be aware of the limitation.

**Gas overhead:** A flash loan liquidation touches 4+ contracts in a single transaction. Monitor gas usage and identify bottlenecks.

### Exercise

**Exercise 1:** Deploy the full stack and run a happy-path test: supply → deposit collateral → borrow → accrue interest → repay → withdraw. Verify all balances at each step.

**Exercise 2:** Deposit ERC-4626 vault shares as collateral, borrow against them. Simulate the vault earning yield (increasing share price). Verify the borrower's health factor improves as their collateral becomes worth more.

---

## Day 2: Build the Flash Liquidation Bot

### The FlashLiquidator Contract

Build a contract that executes the entire liquidation flow in a single atomic transaction:

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

### The Full Flow

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

### Testing the Liquidation

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

### Exercise

Build and test the FlashLiquidator. For each test, log:
- Gas used
- Profit (or loss) in debt asset terms
- Health factor before and after
- Number of external calls in the transaction

---

## Day 3: Stress Testing, Invariants, and Retrospective

### Invariant Testing the Combined System

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

### Edge Case Exploration

Test these specific scenarios:

**Cascading liquidation:** Set up 3 borrowers with progressively tighter health factors. Drop the price. Liquidate the first — does the collateral sale on the AMM move the price enough to push the second into liquidation territory? Does it cascade?

**Stale oracle + liquidation:** What happens if a liquidator tries to liquidate a position but the oracle is stale? Your lending pool should block it (staleness check from Module 3). Verify this.

**Vault share price manipulation during liquidation:** What happens if someone donates tokens to the ERC-4626 vault right before a liquidation, inflating the vault share price? Does it affect the health factor calculation? If you used `convertToAssets()` for pricing, it will. Document the risk.

**Flash loan unavailability:** What if the flash loan provider doesn't have enough liquidity? The liquidation reverts. Show that non-flash-loan liquidations still work (caller provides their own capital).

### Run Security Tooling

Run Slither and/or Aderyn on the combined codebase:

```bash
slither src/module9/ --json slither-report.json
```

Triage the findings. How many are real issues? How many are false positives? For any real findings, fix them.

### Retrospective

After completing the capstone, document (for yourself, not for grading):

1. **What was hardest about integration?** (Usually: decimal normalization, interface mismatches, or gas management)
2. **What broke that you didn't expect?** (The bugs you only find when wiring things together)
3. **What would you design differently?** (Now that you've seen how the pieces interact, what interfaces would you change?)
4. **What's missing from your builds?** (Events? Better error messages? Gas optimizations? Access control?)

This retrospective is the highest-value part of the capstone. The insights you write down here directly inform how you'll design protocols going forward.

---

## Key Takeaways

1. **Integration is where the bugs live.** Individual modules work in isolation but break at the boundaries. Decimal normalization, interface assumptions, and gas overhead are the primary failure modes.

2. **Flash loans change the security model of every protocol they touch.** Your lending pool must be secure against a caller with unlimited temporary capital. Your AMM must handle large sudden trades. Your vault must resist donation attacks. The flash liquidation bot is the forcing function that tests all of this simultaneously.

3. **Invariant testing shines on integrated systems.** Single-protocol invariants catch single-protocol bugs. Cross-protocol invariants catch the composability bugs that cause real-world exploits.

4. **Profitability determines whether liquidation works.** A liquidation system is only as reliable as its economics. If the bonus doesn't cover slippage + fees, no one will liquidate, and the protocol accumulates bad debt. This is a protocol design problem, not just a bot problem.

---

*This completes Part 2: DeFi Foundations. You now have deep understanding of token mechanics, AMMs, oracles, lending, flash loans, stablecoins, vaults, security, and — critically — how they all compose together. Next: Part 3 — Modern DeFi Stack.*

# Part 2 — Module 7: Vaults & Yield

**Duration:** ~4 days (3–4 hours/day)
**Prerequisites:** Modules 1–6 (especially token mechanics, lending, and stablecoins)
**Pattern:** Standard deep-dive → Read Yearn V3 → Build vault + strategy → Security analysis
**Builds on:** Module 1 ([ERC-20](https://eips.ethereum.org/EIPS/eip-20) mechanics, SafeERC20), Module 4 (index-based accounting — the same shares × rate = assets pattern)
**Used by:** Module 8 (inflation attack invariant testing), Module 9 (vault shares as collateral in integration capstone)

---

## 📚 Table of Contents

**ERC-4626 — The Tokenized Vault Standard**
- [The Core Abstraction](#core-abstraction)
- [The Interface](#vault-interface)
- [The Share Math](#share-math)
- [Read: OpenZeppelin ERC4626.sol](#read-oz-erc4626)
- [Exercise](#day1-exercise)

**The Inflation Attack and Defenses**
- [The Attack](#inflation-attack)
- [Quick Try: Inflation Attack in Foundry](#inflation-quick-try)
- [Defense 1: Virtual Shares and Assets](#defense-virtual-shares)
- [Defense 2: Dead Shares](#defense-dead-shares)
- [Defense 3: Internal Accounting](#defense-internal-accounting)
- [When Vaults Are Used as Collateral](#vaults-as-collateral)

**Yield Aggregation — Yearn V3 Architecture**
- [The Yield Aggregation Problem](#yield-aggregation)
- [Yearn V3: The Allocator Vault Pattern](#yearn-allocator)
- [Allocator Vault Mechanics](#allocator-mechanics)
- [The Curator Model](#curator-model)
- [Read: Yearn V3 Source](#read-yearn-v3)
- [Job Market: Yield Aggregation](#yield-aggregation-jobs)

**Composable Yield Patterns and Security**
- [Yield Strategy Comparison](#yield-strategies)
- [Pattern 1: Auto-Compounding](#auto-compounding)
- [Pattern 2: Leveraged Yield](#leveraged-yield)
- [Deep Dive: Leveraged Yield Numeric Walkthrough](#leveraged-yield-walkthrough)
- [Pattern 3: LP + Staking](#lp-staking)
- [Security Considerations for Vault Builders](#vault-security)

---

## 💡 Why Vaults Matter

Every protocol in DeFi that holds user funds and distributes yield faces the same core problem: how do you track each user's share of a pool that changes in size as deposits, withdrawals, and yield accrual happen simultaneously?

The answer is vault share accounting — the same shares/assets math that underpins Aave's aTokens, Compound's cTokens, Uniswap LP tokens, Yearn vault tokens, and MakerDAO's DSR Pot. [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) standardized this pattern into a universal interface, and it's now the foundation of the modular DeFi stack.

Understanding ERC-4626 deeply — the math, the interface, the security pitfalls — gives you the building block for virtually any DeFi protocol. Yield aggregators like Yearn compose these vaults into multi-strategy systems, and the emerging "curator" model (Morpho, Euler V2) uses ERC-4626 vaults as the fundamental unit of risk management.

---

## ERC-4626 — The Tokenized Vault Standard

<a id="core-abstraction"></a>
### 💡 The Core Abstraction

An ERC-4626 vault is an ERC-20 token that represents proportional ownership of a pool of underlying assets. The two key quantities:

- **Assets:** The underlying ERC-20 token (e.g., USDC, WETH)
- **Shares:** The vault's ERC-20 token, representing a claim on a portion of the assets

The **exchange rate** = `totalAssets() / totalSupply()`. As yield accrues (totalAssets increases while totalSupply stays constant), each share becomes worth more assets. This is the "rebasing without rebasing" pattern — your share balance doesn't change, but each share's value increases.

💻 **Quick Try:**

Read a live ERC-4626 vault on a mainnet fork. This script reads Yearn's USDC vault to see the share math in action:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface IERC4626 {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract ReadVault is Script {
    function run() external view {
        // Yearn V3 USDC vault on mainnet
        IERC4626 vault = IERC4626(0xBe53A109B494E5c9f97b9Cd39Fe969BE68f2166c);

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        uint8 decimals = vault.decimals();

        console.log("=== Yearn V3 USDC Vault ===");
        console.log("Total Assets:", totalAssets);
        console.log("Total Supply:", totalSupply);
        console.log("Decimals:", decimals);

        // What's 1000 USDC worth in shares?
        uint256 sharesFor1000 = vault.convertToShares(1000 * 10**6);
        console.log("Shares for 1000 USDC:", sharesFor1000);

        // What's 1000 shares worth in assets?
        uint256 assetsFor1000 = vault.convertToAssets(1000 * 10**6);
        console.log("Assets for 1000 shares:", assetsFor1000);

        // Exchange rate: if shares < assets, the vault has earned yield
        if (totalSupply > 0) {
            console.log("Rate (assets/share):", totalAssets * 1e18 / totalSupply);
        }
    }
}
```

Run with: `forge script ReadVault --rpc-url https://eth.llamarpc.com`

Notice the exchange rate is > 1.0 — that's accumulated yield. Each share is worth more than 1 USDC because the vault's strategies have earned profit since launch.

<a id="vault-interface"></a>
### 📖 The Interface

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

<a id="share-math"></a>
### 💡 The Share Math

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

#### 🔍 Deep Dive: Share Math — Multi-Deposit Walkthrough

Let's trace a vault through multiple deposits, yield events, and withdrawals to build intuition for how shares track proportional ownership.

**Setup:** Empty USDC vault, no virtual shares (for clarity).

```
Step 1: Alice deposits 1,000 USDC
─────────────────────────────────────────────────
  shares_alice = 1000 × 0 / 0  → first deposit, 1:1 ratio
  shares_alice = 1,000

  State: totalAssets = 1,000  |  totalSupply = 1,000  |  rate = 1.000
  ┌──────────────────────────────────────────────┐
  │  Alice: 1,000 shares (100% of vault)         │
  │  Vault holds: 1,000 USDC                     │
  └──────────────────────────────────────────────┘

Step 2: Bob deposits 2,000 USDC
─────────────────────────────────────────────────
  shares_bob = 2000 × 1000 / 1000 = 2,000

  State: totalAssets = 3,000  |  totalSupply = 3,000  |  rate = 1.000
  ┌──────────────────────────────────────────────┐
  │  Alice: 1,000 shares (33.3%)                 │
  │  Bob:   2,000 shares (66.7%)                 │
  │  Vault holds: 3,000 USDC                     │
  └──────────────────────────────────────────────┘

Step 3: Vault earns 300 USDC yield (strategy profits)
─────────────────────────────────────────────────
  No shares minted — totalAssets increases, totalSupply unchanged

  State: totalAssets = 3,300  |  totalSupply = 3,000  |  rate = 1.100
  ┌──────────────────────────────────────────────┐
  │  Alice: 1,000 shares → 1,000 × 1.1 = 1,100 USDC  │
  │  Bob:   2,000 shares → 2,000 × 1.1 = 2,200 USDC  │
  │  Vault holds: 3,300 USDC                           │
  │  Yield distributed proportionally ✓                │
  └──────────────────────────────────────────────┘

Step 4: Carol deposits 1,100 USDC (after yield)
─────────────────────────────────────────────────
  shares_carol = 1100 × 3000 / 3300 = 1,000
  Carol gets 1,000 shares — same as Alice, but she deposited
  1,100 USDC (not 1,000). She's buying in at the higher rate.

  State: totalAssets = 4,400  |  totalSupply = 4,000  |  rate = 1.100
  ┌──────────────────────────────────────────────┐
  │  Alice: 1,000 shares (25%) → 1,100 USDC     │
  │  Bob:   2,000 shares (50%) → 2,200 USDC     │
  │  Carol: 1,000 shares (25%) → 1,100 USDC     │
  │  Vault holds: 4,400 USDC                     │
  └──────────────────────────────────────────────┘

Step 5: Alice withdraws everything
─────────────────────────────────────────────────
  assets_alice = 1000 × 4400 / 4000 = 1,100 USDC ✓
  Alice deposited 1,000, gets back 1,100 → earned 100 USDC (10%)

  State: totalAssets = 3,300  |  totalSupply = 3,000  |  rate = 1.100
  ┌──────────────────────────────────────────────┐
  │  Bob:   2,000 shares (66.7%) → 2,200 USDC   │
  │  Carol: 1,000 shares (33.3%) → 1,100 USDC   │
  │  Vault holds: 3,300 USDC                     │
  │  Rate unchanged after withdrawal ✓           │
  └──────────────────────────────────────────────┘
```

**Key observations:**
- Shares track **proportional ownership**, not absolute amounts
- Yield accrual increases the rate without minting shares — existing holders benefit automatically
- Late depositors (Carol) buy at the current rate — they don't capture past yield
- Withdrawals don't change the exchange rate for remaining holders
- This is **exactly** how aTokens, cTokens, and LP tokens work under the hood

**Rounding in practice:** The example above used numbers that divide evenly, but real values rarely do. If Carol deposited 1,099 USDC instead, she'd get `1099 × 3000 / 3300 = 999.09...` which rounds down to 999 shares — slightly fewer than the "fair" amount. This rounding loss is typically negligible (< 1 wei of the underlying), but it accumulates vault-favorably — the vault slowly builds a tiny surplus that protects against rounding-based exploits.

<a id="read-oz-erc4626"></a>
### 📖 Read: OpenZeppelin ERC4626.sol

**Source:** [`@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)

Focus on:
- The `_decimalsOffset()` virtual function and its role in inflation attack mitigation
- How `_convertToShares` and `_convertToAssets` add virtual shares/assets: `shares = assets × (totalSupply + 10^offset) / (totalAssets + 1)`
- The rounding direction in each conversion
- How `deposit`, `mint`, `withdraw`, and `redeem` all route through `_deposit` and `_withdraw`

Also compare with Solmate's implementation (`solmate/src/tokens/ERC4626.sol`) which is more gas-efficient but less defensive.

#### 📖 How to Study OpenZeppelin ERC4626.sol

1. **Read the conversion functions first** — `_convertToShares()` and `_convertToAssets()` are the mathematical core. Notice the `+ 10 ** _decimalsOffset()` and `+ 1` terms — these are the virtual shares/assets that defend against the inflation attack. Understand why rounding direction differs between deposit (rounds down = fewer shares for user) and withdraw (rounds up = more shares burned from user).

2. **Trace a `deposit()` call end-to-end** — Follow: `deposit()` → `previewDeposit()` → `_convertToShares()` → `_deposit()` → `SafeERC20.safeTransferFrom()` + `_mint()`. Map which function handles the math vs the token movement vs the event emission.

3. **Compare `deposit()` vs `mint()`** — Both result in shares being minted, but they specify different inputs. `deposit(assets)` says "I want to deposit exactly X assets, give me however many shares." `mint(shares)` says "I want exactly X shares, pull however many assets needed." The rounding direction flips between them. Draw a table showing the rounding for all four operations (deposit, mint, withdraw, redeem).

4. **Read `maxDeposit()`, `maxMint()`, `maxWithdraw()`, `maxRedeem()`** — These are often overlooked but critical for integration. A vault that returns `0` for `maxDeposit` signals it's paused or full. Protocols integrating your vault MUST check these before attempting operations.

5. **Compare with Solmate's ERC4626** — [Solmate's version](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC4626.sol) skips virtual shares (no `_decimalsOffset`). This is more gas-efficient but vulnerable to the inflation attack without additional protection. Understanding this trade-off is interview-relevant.

**Don't get stuck on:** The `_decimalsOffset()` virtual function mechanics. Just know: default is 0 (no virtual offset), override to 3 or 6 for inflation protection. The higher the offset, the more expensive the attack becomes, but the more precision you lose for tiny deposits.

<a id="day1-exercise"></a>
### 🛠️ Exercise

**Workspace:** [`workspace/src/part2/module7/exercise1-simple-vault/`](../workspace/src/part2/module7/exercise1-simple-vault/) — starter file: [`SimpleVault.sol`](../workspace/src/part2/module7/exercise1-simple-vault/SimpleVault.sol), tests: [`SimpleVault.t.sol`](../workspace/test/part2/module7/exercise1-simple-vault/SimpleVault.t.sol)

**Exercise 1:** Implement a minimal ERC-4626 vault from scratch (don't use OpenZeppelin or Solmate). Use `Math.mulDiv` for safe division. Implement all required functions. Test:
- Deposit 1000 USDC, receive 1000 shares
- Simulate yield: manually transfer 100 USDC to the vault
- New deposit of 1000 USDC should receive ~909 shares (1000 × 1000/1100)
- First user redeems 1000 shares, receives ~1100 USDC
- Verify all preview functions return correct values
- Verify rounding always favors the vault

**Exercise 2:** Implement `deposit` and `mint` side by side. Show that `deposit(100)` and `mint(previewDeposit(100))` produce the same result. Show that `mint(100)` and `deposit(previewMint(100))` produce the same result (accounting for rounding).

#### 💼 Job Market Context

**What DeFi teams expect you to know about ERC-4626:**

1. **"Explain the rounding rules in ERC-4626 and why they matter."**
   - Good answer: "Conversions round in favor of the vault — fewer shares on deposit, fewer assets on withdrawal — so the vault can't be drained."
   - Great answer: "The spec mandates `deposit` rounds shares down, `mint` rounds assets up, `withdraw` rounds shares up, `redeem` rounds assets down. This creates a tiny vault-favorable spread on every operation. It's the same principle as a bank's bid/ask spread — the vault always wins the rounding."

2. **"How does ERC-4626 differ from Compound cTokens or Aave aTokens?"**
   - Good answer: "ERC-4626 standardizes the interface. cTokens use an exchange rate, aTokens rebase — both do the same thing differently."
   - Great answer: "cTokens store `exchangeRate` and you multiply by your balance. aTokens rebase your balance directly using a `scaledBalance × liquidityIndex` pattern. ERC-4626 abstracts both approaches behind `convertToShares/convertToAssets` — any protocol can implement the interface however they want. The key win is composability: any ERC-4626 vault works as a strategy in Yearn, as collateral in Morpho, etc."

3. **"What's the first thing you check when auditing a new ERC-4626 vault?"**
   - Good answer: "I check for the inflation attack — whether the vault uses virtual shares."
   - Great answer: "I check three things: (1) how `totalAssets()` is computed — if it reads `balanceOf(address(this))` it's vulnerable to donation attacks; (2) whether there's inflation protection (virtual shares or dead shares); (3) whether `preview` functions match actual `deposit`/`withdraw` behavior, since broken preview functions break all integrators."

**Interview Red Flags:**
- ❌ Not knowing what ERC-4626 is (it's the foundation of modern DeFi infrastructure)
- ❌ Confusing shares and assets (which direction does the conversion go?)
- ❌ Not knowing about the inflation attack and its defenses

**Pro tip:** The ERC-4626 ecosystem is one of the fastest-growing in DeFi. Morpho, Euler V2, Yearn V3, Ethena (sUSDe), Lido (wstETH adapter), and hundreds of other protocols all use it. Being able to write, audit, and integrate ERC-4626 vaults is a high-demand skill.

### 📋 Summary: ERC-4626 — The Tokenized Vault Standard

**✓ Covered:**
- The shares/assets abstraction and why it's the universal pattern for yield-bearing tokens
- ERC-4626 interface — all 16 functions across deposit, mint, withdraw, redeem flows
- Rounding rules: always in favor of the vault (against the user)
- Share math with multi-deposit walkthrough (Alice → Bob → yield → Carol → withdrawal)
- OpenZeppelin vs Solmate implementation trade-offs

**Key insight:** ERC-4626 is the same math pattern you've seen in Aave aTokens, Compound cTokens, and Uniswap LP tokens — standardized into a universal interface. Master the share math once, apply it everywhere.

**Next:** The inflation attack — why empty vaults are dangerous and three defense strategies.

---

## The Inflation Attack and Defenses

<a id="inflation-attack"></a>
### ⚠️ The Attack

The inflation attack (also called the donation attack or first-depositor attack) exploits empty or nearly-empty vaults:

**Step 1:** Attacker deposits 1 wei of assets, receives 1 share.
**Step 2:** Attacker donates a large amount (e.g., 10,000 USDC) directly to the vault contract via `transfer()` (not through `deposit()`).
**Step 3:** Now `totalAssets = 10,000,000,001` (including the 1 wei), `totalSupply = 1`. The exchange rate is extremely high.
**Step 4:** Victim deposits 20,000 USDC. Shares received = `20,000 × 1 / 10,000.000001 = 1` share (rounded down from ~2).
**Step 5:** Attacker and victim each hold 1 share. Attacker redeems for ~15,000 USDC. Attacker profit: ~5,000 USDC stolen from the victim.

The attack works because the large donation inflates the exchange rate, and the subsequent deposit rounds down to give the victim far fewer shares than their deposit warrants.

<a id="inflation-quick-try"></a>
💻 **Quick Try:**

Run this Foundry test to see the inflation attack in action. It deploys a naive vault and executes all 4 steps:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1_000_000e6);
    }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @notice Naive vault — no virtual shares, totalAssets = balanceOf
contract NaiveVault is ERC20 {
    IERC20 public immutable asset;
    constructor(IERC20 _asset) ERC20("Vault", "vUSDC") { asset = _asset; }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));  // ← THE VULNERABILITY
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 supply = totalSupply();
        shares = supply == 0 ? assets : (assets * supply) / totalAssets();
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function redeem(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
        _burn(msg.sender, shares);
        asset.transfer(receiver, assets);
    }
}

contract InflationAttackTest is Test {
    MockUSDC usdc;
    NaiveVault vault;
    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");

    function setUp() public {
        usdc = new MockUSDC();
        vault = new NaiveVault(usdc);
        usdc.transfer(attacker, 30_000e6);
        usdc.transfer(victim, 20_000e6);
    }

    function test_inflationAttack() public {
        // Step 1: Attacker deposits 1 wei
        vm.startPrank(attacker);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1, attacker);

        // Step 2: Attacker donates 10,000 USDC directly
        usdc.transfer(address(vault), 10_000e6);
        vm.stopPrank();

        // Step 3: Victim deposits 20,000 USDC
        vm.startPrank(victim);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(20_000e6, victim);
        vm.stopPrank();

        // Check: victim got only 1 share (should have ~2,000)
        assertEq(vault.balanceOf(victim), 1, "Victim got robbed — only 1 share");

        // Step 4: Attacker redeems
        vm.prank(attacker);
        uint256 attackerReceived = vault.redeem(1, attacker);

        console.log("Attacker spent:    10,000 USDC");
        console.log("Attacker received:", attackerReceived / 1e6, "USDC");
        console.log("Victim deposited:  20,000 USDC");
        console.log("Victim can redeem:", vault.totalAssets(), "USDC (in vault)");
    }
}
```

Run with `forge test --match-test test_inflationAttack -vv`. Watch the attacker steal ~5,000 USDC from the victim in 4 steps.

#### 🔍 Deep Dive: Inflation Attack Step-by-Step

```
NAIVE VAULT (no virtual shares, totalAssets = balanceOf)
═══════════════════════════════════════════════════════════

Step 1: Attacker deposits 1 wei
─────────────────────────────────
  totalAssets = 1          totalSupply = 1
  shares_attacker = 1      rate = 1.0

  ┌─────────────────────────────────────┐
  │  Vault: 1 wei                       │
  │  Attacker: 1 share (100%)           │
  └─────────────────────────────────────┘

Step 2: Attacker DONATES 10,000 USDC via transfer()
─────────────────────────────────────────────────────
  balanceOf(vault) = 10,000,000,001 (10k USDC + 1 wei)
  totalAssets = 10,000,000,001     totalSupply = 1
  rate = 10,000,000,001 per share  ← INFLATED!

  ┌─────────────────────────────────────┐
  │  Vault: 10,000.000001 USDC         │
  │  Attacker: 1 share (100%)          │
  │  Attacker cost so far: ~10,000 USDC│
  └─────────────────────────────────────┘

Step 3: Victim deposits 20,000 USDC
─────────────────────────────────────
  shares = 20,000,000,000 × 1 / 10,000,000,001
         = 1.999...
         = 1  (rounded DOWN — vault-favorable)

  totalAssets = 30,000,000,001     totalSupply = 2

  ┌─────────────────────────────────────┐
  │  Vault: 30,000.000001 USDC         │
  │  Attacker: 1 share (50%)           │
  │  Victim:   1 share (50%)  ← WRONG! │
  │  Victim deposited 2× but gets 50%  │
  └─────────────────────────────────────┘

Step 4: Attacker redeems 1 share
─────────────────────────────────
  assets = 1 × 30,000,000,001 / 2 = 15,000 USDC

  ┌─────────────────────────────────────────────┐
  │  Attacker spent:   10,000 USDC (donation)   │
  │                  +     0 USDC (1 wei deposit)│
  │  Attacker received: 15,000 USDC             │
  │  Attacker PROFIT:    5,000 USDC             │
  │                                             │
  │  Victim deposited:  20,000 USDC             │
  │  Victim can redeem: 15,000 USDC             │
  │  Victim LOSS:        5,000 USDC             │
  └─────────────────────────────────────────────┘

WITH VIRTUAL SHARES (OpenZeppelin, offset = 3)
═══════════════════════════════════════════════

  Same attack, but conversion uses virtual shares/assets:
  shares = assets × (totalSupply + 1000) / (totalAssets + 1)

  After donation (Step 2):
    totalAssets = 10,000,000,001    totalSupply = 1

  Victim deposits 20,000 USDC (Step 3):
    shares = 20,000,000,000 × (1 + 1000) / (10,000,000,001 + 1)
           = 20,000,000,000 × 1001 / 10,000,000,002
           = 2,001          ← victim gets ~2000 shares!

  Attacker has 1 share, victim has 2,001 shares. totalSupply = 2,002.
  totalAssets = 30,000,000,001 (10k donation + 20k deposit + 1 wei)

  Attacker redeems 1 share (conversion also uses virtual shares/assets):
    assets = 1 × (30,000,000,001 + 1) / (2,002 + 1000)
           = 30,000,000,002 / 3,002
           = 9,993,338  ← ~$10 USDC
  Attacker LOSS: ~$9,990 USDC ← Attack is UNPROFITABLE
```

**Why virtual shares work:** The 1000 virtual shares in the denominator mean the attacker's donation is spread across 1001 shares (1 real + 1000 virtual), not just 1. The attacker can't monopolize the inflated rate.

### ⚠️ Why It Still Matters

This isn't theoretical. The Resupply protocol was exploited via this vector in 2025, and the Venus Protocol lost approximately 86 WETH to a similar attack on ZKsync in February 2025. Any protocol using ERC-4626 vaults as collateral in a lending market is at risk if the vault's exchange rate can be manipulated.

<a id="defense-virtual-shares"></a>
### 🛡️ Defense 1: Virtual Shares and Assets (OpenZeppelin approach)

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

<a id="defense-dead-shares"></a>
### 🛡️ Defense 2: Dead Shares (Uniswap V2 approach)

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

<a id="defense-internal-accounting"></a>
### 🛡️ Defense 3: Internal Accounting (Aave V3 approach)

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

<a id="vaults-as-collateral"></a>
### ⚠️ When Vaults Are Used as Collateral

The inflation attack becomes especially dangerous when ERC-4626 tokens are used as collateral in lending protocols. If a lending protocol prices collateral using `vault.convertToAssets(shares)`, an attacker can:

1. Inflate the vault's exchange rate via donation
2. Deposit vault shares as collateral (now overvalued)
3. Borrow against the inflated collateral value
4. The exchange rate normalizes (or the attacker redeems), leaving the lending protocol with bad debt

Defense: lending protocols should use time-weighted or externally-sourced exchange rates for ERC-4626 collateral, not the vault's own `convertToAssets()` at a single point in time.

### 🛠️ Exercise

**Workspace:** [`workspace/src/part2/module7/exercise2-inflation-attack/`](../workspace/src/part2/module7/exercise2-inflation-attack/) — starter files: [`NaiveVault.sol`](../workspace/src/part2/module7/exercise2-inflation-attack/NaiveVault.sol), [`DefendedVault.sol`](../workspace/src/part2/module7/exercise2-inflation-attack/DefendedVault.sol), tests: [`InflationAttack.t.sol`](../workspace/test/part2/module7/exercise2-inflation-attack/InflationAttack.t.sol)

**Exercise 1:** Build the inflation attack. Deploy a naive vault (no virtual shares, `totalAssets = balanceOf`), execute the attack step by step, and show the victim's loss. Then add OpenZeppelin's virtual share offset and show the attack becomes unprofitable.

**Exercise 2:** Build a vault with internal accounting (`_totalManagedAssets`). Show that direct token transfers don't affect the exchange rate. Then show a scenario where a strategy reports yield and updates `_totalManagedAssets` correctly.

**Exercise 3:** Implement all three defenses (virtual shares, dead shares, internal accounting) and compare: gas cost of deposit/withdraw, precision loss on first deposit, effectiveness against varying donation sizes.

### 📋 Summary: The Inflation Attack and Defenses

**✓ Covered:**
- The inflation (donation/first-depositor) attack — step-by-step mechanics
- Real exploits: Resupply (2025), Venus Protocol on ZKsync (2025)
- Defense 1: Virtual shares and assets (OpenZeppelin's `_decimalsOffset`)
- Defense 2: Dead shares (Uniswap V2 approach — lock minimum liquidity)
- Defense 3: Internal accounting (track `_totalManagedAssets` instead of `balanceOf`)
- Collateral pricing risk when ERC-4626 tokens are used in lending markets

**Key insight:** The inflation attack is the #1 ERC-4626 security concern. Virtual shares (OpenZeppelin) are the most common defense, but internal accounting is the most robust. Never use raw `balanceOf(address(this))` for critical pricing in any vault.

**Next:** Yield aggregation architecture — how Yearn V3 composes ERC-4626 vaults into multi-strategy systems.

---

## Yield Aggregation — Yearn V3 Architecture

<a id="yield-aggregation"></a>
### 💡 The Yield Aggregation Problem

A single yield source (e.g., supplying USDC on Aave) gives you one return. But there are dozens of yield sources for USDC: Aave, Compound, Morpho, Curve pools, Balancer pools, DSR, etc. Each has different risk, return, and capacity. A yield aggregator's job is to:

1. Accept deposits in a single asset
2. Allocate those deposits across multiple yield sources (strategies)
3. Rebalance as conditions change
4. Handle deposits/withdrawals seamlessly
5. Account for profits and losses correctly

<a id="yearn-allocator"></a>
### 💡 Yearn V3: The Allocator Vault Pattern

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

<a id="allocator-mechanics"></a>
### 🔧 Allocator Vault Mechanics

**Adding strategies:** The vault manager calls `vault.add_strategy(strategy_address)`. Each strategy gets a `max_debt` parameter — the maximum the vault will allocate to that strategy.

**Debt allocation:** The `DEBT_MANAGER` role calls `vault.update_debt(strategy, target_debt)` to move funds. The vault tracks `currentDebt` per strategy. When allocating, the vault calls `strategy.deposit()`. When deallocating, it calls `strategy.withdraw()`.

**Reporting:** When `vault.process_report(strategy)` is called:
1. The vault calls `strategy.convertToAssets(strategy.balanceOf(vault))` to get current value
2. Compares to `currentDebt` to determine profit or loss
3. If profit: records gain, charges fees (via Accountant contract), mints fee shares
4. If loss: reduces strategy debt, reduces overall vault value

**Profit unlocking:** Profits aren't immediately available to withdrawers. They unlock linearly over a configurable `profitMaxUnlockTime` period. This prevents sandwich attacks where someone deposits right before a harvest and withdraws right after, capturing yield they didn't contribute to.

#### 🔍 Deep Dive: Profit Unlocking — Numeric Walkthrough

Why does profit unlocking matter? Without it, an attacker can sandwich the `harvest()` call to steal yield. Let's trace both scenarios.

```
SCENARIO A: NO PROFIT UNLOCKING (vulnerable)
═════════════════════════════════════════════

Setup: Vault has 100,000 USDC, 100,000 shares, rate = 1.0
       Strategy earned 10,000 USDC profit (not yet reported)

Timeline:
  T=0  Attacker sees harvest() in mempool
       Attacker deposits 100,000 USDC → gets 100,000 shares
       State: totalAssets = 200,000 | totalSupply = 200,000

  T=1  harvest() executes, reports 10,000 profit
       State: totalAssets = 210,000 | totalSupply = 200,000
       Rate: 1.05 per share

  T=2  Attacker redeems 100,000 shares
       Receives: 100,000 × 210,000 / 200,000 = 105,000 USDC
       Attacker PROFIT: 5,000 USDC (in ONE block!)

  Legitimate depositors earned 5,000 USDC instead of 10,000.
  Attacker captured 50% of the yield by holding for 1 block.


SCENARIO B: WITH PROFIT UNLOCKING (profitMaxUnlockTime = 6 hours)
════════════════════════════════════════════════════════════════

Setup: Same — 100,000 USDC, 100,000 shares, 10,000 profit pending

Timeline:
  T=0  Attacker deposits 100,000 USDC → gets 100,000 shares
       State: totalAssets = 200,000 | totalSupply = 200,000

  T=1  harvest() executes, reports 10,000 profit
       But profit is LOCKED — it unlocks linearly over 6 hours.
       Immediately available: 0 USDC of profit
       State: totalAssets = 200,000 (profit not yet in totalAssets)
              totalSupply = 200,000
       Rate: still 1.0

  T=2  Attacker redeems immediately
       Receives: 100,000 × 200,000 / 200,000 = 100,000 USDC
       Attacker PROFIT: 0 USDC ← sandwich FAILED

  After 1 hour:  1,667 USDC unlocked (10,000 / 6)
  After 3 hours: 5,000 USDC unlocked
  After 6 hours: 10,000 USDC fully unlocked → rate = 1.10
  Only depositors who stayed the full 6 hours earn the yield.
```

**How the unlock works mechanically:** Yearn V3 tracks `fullProfitUnlockDate` and `profitUnlockingRate`. The vault's `totalAssets()` includes only the portion of profit that has unlocked so far: `unlockedProfit = profitUnlockingRate × (block.timestamp - lastReport)`. This smooths the share price increase over the unlock period.

**The trade-off:** Longer unlock times are more sandwich-resistant but delay yield recognition for legitimate depositors. Most vaults use 6-24 hours as a balance.

<a id="curator-model"></a>
### 💡 The Curator Model

The broader trend in DeFi (2024-25) extends Yearn's pattern: protocols like [Morpho](https://github.com/morpho-org/metamorpho) and [Euler V2](https://github.com/euler-xyz/euler-vault-kit) allow third-party "curators" to deploy ERC-4626 vaults that allocate to their underlying lending markets. Curators set risk parameters, choose which markets to allocate to, and earn management/performance fees. Users choose a curator based on risk appetite and track record.

This separates infrastructure (the lending protocol) from risk management (the curator's vault), creating a modular stack:
- **Layer 1:** Base lending protocol (Morpho Blue, Euler V2, Aave)
- **Layer 2:** Curator vaults (ERC-4626) that allocate across Layer 1 markets
- **Layer 3:** Meta-vaults that allocate across curator vaults

Each layer uses ERC-4626, so they compose naturally.

<a id="read-yearn-v3"></a>
### 📖 Read: Yearn V3 Source

**VaultV3.sol:** [`yearn/yearn-vaults-v3`](https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy)
- Focus on [`process_report()`](https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy) — how profit/loss is calculated and fees charged
- The withdrawal queue — how the vault pulls funds from strategies when a user withdraws
- The `profitMaxUnlockTime` mechanism

**TokenizedStrategy:** [`yearn/tokenized-strategy`](https://github.com/yearn/tokenized-strategy/blob/master/src/TokenizedStrategy.sol)
- The [`BaseStrategy`](https://github.com/yearn/tokenized-strategy/blob/master/src/BaseStrategy.sol) abstract contract — the three functions you override
- How `report()` triggers `_harvestAndReport()` and handles accounting

**Morpho MetaMorpho Vault:** [`morpho-org/metamorpho`](https://github.com/morpho-org/metamorpho/blob/main/src/MetaMorpho.sol) — A production curator vault built on Morpho Blue. Compare with Yearn V3: both are ERC-4626 allocator vaults, but MetaMorpho allocates across Morpho Blue lending markets while Yearn allocates across arbitrary strategies.

#### 📖 How to Study Yearn V3 Architecture

1. **Start with a strategy, not the vault** — Read a simple strategy implementation first (Yearn publishes example strategies). Find the three overrides: `_deployFunds()`, `_freeFunds()`, `_harvestAndReport()`. These are typically 10-30 lines each. Understanding what a strategy does grounds the rest of the architecture.

2. **Read the TokenizedStrategy delegation pattern** — Your strategy contract doesn't implement ERC-4626 directly. It delegates to a pre-deployed `TokenizedStrategy` implementation via `delegateCall` in the fallback function. This means all the accounting, reporting, and ERC-4626 compliance lives in one shared contract. Focus on: how does `report()` call your `_harvestAndReport()` and then update the strategy's total assets?

3. **Read VaultV3's `process_report()`** — This is the core allocator vault function. Trace: how it calls `strategy.convertToAssets()` to get current value, compares to `currentDebt` to compute profit/loss, charges fees via the Accountant, and handles profit unlocking. The `profitMaxUnlockTime` mechanism is the key anti-sandwich defense.

4. **Study the withdrawal queue** — When a user withdraws from the allocator vault and idle balance is insufficient, the vault pulls from strategies in queue order. Read how `_withdraw()` iterates through strategies, calls `strategy.withdraw()`, and handles partial fills. This is where withdrawal liquidity risk manifests.

5. **Map the role system** — Yearn V3 uses granular roles: `ROLE_MANAGER`, `DEBT_MANAGER`, `REPORTING_MANAGER`, etc. Understanding who can call what clarifies the trust model: vault managers control allocation, reporting managers trigger harvests, and the role manager controls access.

**Don't get stuck on:** The Vyper syntax in VaultV3 (Yearn V3 vaults are written in Vyper, not Solidity). The logic maps directly to Solidity concepts — `@external` = `external`, `@view` = `view`, `self.variable` = `this.variable`. Focus on the architecture, not the syntax.

<a id="yield-aggregation-jobs"></a>
#### 💼 Job Market Context

**What DeFi teams expect you to know about yield aggregation:**

1. **"How would you design a multi-strategy vault from scratch?"**
   - Good answer: "An ERC-4626 vault that holds a list of strategies, allocates debt to each, and pulls from them in order on withdrawal."
   - Great answer: "I'd follow the allocator pattern: the vault is an ERC-4626 shell with an ordered strategy queue. Each strategy is also ERC-4626 for composability. Key design decisions: (1) debt management — who sets target allocations and how often; (2) withdrawal queue priority — which strategies to pull from first (idle → lowest-yield → most-liquid); (3) profit accounting — harvest reports go through a `process_report()` that separates profit from fees and unlocks profit linearly to prevent sandwich attacks; (4) loss handling — reduce share price proportionally rather than reverting."

2. **"What's the difference between Yearn V3 and MetaMorpho?"**
   - Good answer: "Both are ERC-4626 allocator vaults, but Yearn allocates across arbitrary strategies while MetaMorpho allocates across Morpho Blue lending markets."
   - Great answer: "The key difference is the strategy universe: Yearn strategies can do anything (LP, leverage, restaking), so the vault manager has more flexibility but more risk surface. MetaMorpho is constrained to Morpho Blue markets — the curator picks which markets to allocate to and sets caps, but all the underlying lending logic is in Morpho Blue itself. This constraint makes MetaMorpho easier to reason about and audit. The trend is toward this modular stack: protocol layer (Morpho Blue) handles mechanics, curator layer (MetaMorpho) handles risk allocation."

3. **"How do you prevent a vault manager from rugging depositors?"**
   - Good answer: "Use a timelock on strategy changes and cap allocations per strategy."
   - Great answer: "Defense in depth: (1) granular role system — separate who can add strategies vs who can allocate debt vs who can trigger reports; (2) strategy allowlists with timelocked additions — depositors see new strategies before funds flow; (3) per-strategy max debt caps to limit blast radius; (4) depositor-side `max_loss` parameter on withdrawal — revert if the vault is trying to return less than expected; (5) the Yearn V3 approach of requiring strategy contracts to be pre-audited and whitelisted."

**Interview Red Flags:**
- ❌ Thinking vault managers have unrestricted access to user funds (they shouldn't — debt limits and roles constrain them)
- ❌ Not understanding profit unlocking (the #1 sandwich defense for yield vaults)
- ❌ Confusing Yearn V2 and V3 architecture (V3's ERC-4626-native design is fundamentally different)

**Pro tip:** The curator/vault-as-a-service model is the fastest-growing DeFi architectural pattern in 2025. Being able to articulate the trade-offs between Yearn V3 (flexible strategies, higher risk surface) vs MetaMorpho (constrained to lending, easier to audit) vs Euler V2 (modular with custom vault logic) signals you understand the current state of DeFi infrastructure.

### 🛠️ Exercise

**Workspace:** [`workspace/src/part2/module7/exercise3-simple-allocator/`](../workspace/src/part2/module7/exercise3-simple-allocator/) — starter files: [`SimpleAllocator.sol`](../workspace/src/part2/module7/exercise3-simple-allocator/SimpleAllocator.sol), [`MockStrategy.sol`](../workspace/src/part2/module7/exercise3-simple-allocator/MockStrategy.sol), tests: [`SimpleAllocator.t.sol`](../workspace/test/part2/module7/exercise3-simple-allocator/SimpleAllocator.t.sol)

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

### 📋 Summary: Yield Aggregation — Yearn V3 Architecture

**✓ Covered:**
- The yield aggregation problem — why allocating across multiple sources matters
- Yearn V3 Allocator Vault pattern — vault holds strategies, not yield sources directly
- TokenizedStrategy delegation pattern — your strategy delegates ERC-4626 logic to a shared implementation
- The three overrides: `_deployFunds()`, `_freeFunds()`, `_harvestAndReport()`
- Debt allocation mechanics: `max_debt`, `update_debt()`, `process_report()`
- Profit unlocking as anti-sandwich defense (`profitMaxUnlockTime`)
- The Curator model (Morpho, Euler V2) — modular risk management layers

**Key insight:** The allocator vault pattern separates yield generation (strategies) from risk management (the vault). ERC-4626 composability means each layer can plug into the next — this is how modern DeFi infrastructure is being built.

**Next:** Composable yield patterns (auto-compounding, leveraged yield, LP staking) and critical security considerations for vault builders.

---

## Composable Yield Patterns and Security

<a id="yield-strategies"></a>
### 📋 Yield Strategy Comparison

| Strategy | Typical APY | Risk Level | Complexity | Key Risk | Example |
|---|---|---|---|---|---|
| **Single lending** | 2-8% | Low | Low | Protocol hack, bad debt | Aave USDC supply |
| **Auto-compound** | 4-12% | Low-Med | Medium | Swap slippage, keeper costs | Yearn Aave strategy |
| **Leveraged yield** | 8-25% | Medium-High | High | Liquidation, rate inversion | Recursive borrowing on Aave |
| **LP + staking** | 10-40% | High | High | Impermanent loss, reward token dump | Curve/Convex USDC-USDT |
| **Vault-of-vaults** | 5-15% | Medium | Very High | Cascading losses, liquidity fragmentation | Yearn allocator across strategies |
| **Delta-neutral** | 5-20% | Medium | Very High | Funding rate reversal, basis risk | Ethena USDe (spot + short perp) |

*APY ranges are illustrative and vary significantly with market conditions. Higher APY = higher risk.*

<a id="auto-compounding"></a>
### 💡 Pattern 1: Auto-Compounding

Many yield sources distribute rewards in a separate token (e.g., COMP tokens from Compound, CRV from Curve). Auto-compounding sells these reward tokens for the underlying asset and re-deposits:

```
1. Deposit USDC into Compound → earn COMP rewards
2. Harvest: claim COMP, swap COMP → USDC on Uniswap
3. Deposit the additional USDC back into Compound
4. totalAssets increases → share price increases
```

**Build consideration:** The harvest transaction pays gas and incurs swap slippage. Only economical when accumulated rewards exceed costs. Most vaults use keeper bots that call harvest based on profitability calculations.

<a id="leveraged-yield"></a>
### 💡 Pattern 2: Leveraged Yield (Recursive Borrowing)

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

<a id="leveraged-yield-walkthrough"></a>
#### 🔍 Deep Dive: Leveraged Yield — Numeric Walkthrough

```
SETUP
═════
  Aave USDC market:
    Supply APY:  3.0%
    Borrow APY:  4.5%
    AAVE incentive (supply + borrow): +2.0% effective
    Max LTV: 80%

  Starting capital: 10,000 USDC

LOOP-BY-LOOP RECURSIVE BORROWING
═════════════════════════════════

  Loop 0: Deposit 10,000 USDC
          Collateral: 10,000  |  Debt: 0  |  Effective exposure: 10,000

  Loop 1: Borrow 80% → 8,000 USDC, re-deposit
          Collateral: 18,000  |  Debt: 8,000  |  Exposure: 18,000

  Loop 2: Borrow 80% of new 8,000 → 6,400 USDC, re-deposit
          Collateral: 24,400  |  Debt: 14,400  |  Exposure: 24,400

  Loop 3: Borrow 80% of 6,400 → 5,120 USDC, re-deposit
          Collateral: 29,520  |  Debt: 19,520  |  Exposure: 29,520

  ... converges to:
  Loop ∞: Collateral: 50,000  |  Debt: 40,000  |  Leverage: 5×
          (Geometric series: 10,000 / (1 - 0.8) = 50,000)

  In practice, 3 loops gets you ~3× leverage. Flash loans skip looping
  entirely — borrow the full target amount in one tx (see Module 5).

APY CALCULATION AT 3× LEVERAGE (3 loops ≈ 29,520 exposure)
═══════════════════════════════════════════════════════════

  Supply yield:    29,520 × 3.0%  = +$885.60
  Borrow cost:    19,520 × 4.5%  = -$878.40
  AAVE incentive: 29,520 × 2.0%  = +$590.40  (on total exposure)
  ─────────────────────────────────────────────
  Net profit:                       $597.60
  On 10,000 capital → 5.98% APY  (vs 5.0% unleveraged: 3% + 2%)

WHEN IT GOES WRONG — RATE INVERSION
════════════════════════════════════

  Market heats up. Borrow APY spikes to 8%, incentives drop to 0.5%:

  Supply yield:    29,520 × 3.0%  = +$885.60
  Borrow cost:    19,520 × 8.0%  = -$1,561.60
  AAVE incentive: 29,520 × 0.5%  = +$147.60
  ─────────────────────────────────────────────
  Net profit:                       -$528.40  ← LOSING MONEY

  The strategy must monitor rates and deleverage automatically when
  net yield turns negative. Good strategies check this on every harvest().

HEALTH FACTOR CHECK
═══════════════════

  At 3× leverage (3 loops):
    Collateral: 29,520 USDC  |  Debt: 19,520 USDC
    LT = 86% for stablecoins on Aave V3
    HF = (29,520 × 0.86) / 19,520 = 25,387 / 19,520 = 1.30 ✓

  Since both collateral and debt are USDC (same asset), price movement
  doesn't affect HF — the risk is purely rate inversion, not liquidation.
  For cross-asset leverage (e.g., deposit ETH, borrow USDC), price
  movement is the primary liquidation risk (see Module 5 walkthrough).
```

<a id="lp-staking"></a>
### 💡 Pattern 3: LP + Staking

Provide liquidity to an AMM pool, then stake the LP tokens for additional rewards:

```
1. Deposit USDC → swap half to ETH → provide USDC/ETH liquidity on Uniswap
2. Stake LP tokens in a reward contract (or Convex/Aura for Curve/Balancer)
3. Earn: trading fees + liquidity mining rewards + boosted rewards
4. Harvest: claim all rewards, swap to USDC, re-provide liquidity
```

This is the model behind Yearn's Curve strategies (Curve LP → stake in Convex → earn CRV+CVX), which have historically been among the highest and most consistent yield sources.

### 🔗 Pattern 4: Vault Composability

Because ERC-4626 vaults are ERC-20 tokens, they can be used as:
- **Collateral in lending protocols:** Deposit sUSDe (Ethena's staked USDe vault token) as collateral on Aave, borrow against your yield-bearing position
- **Liquidity in AMMs:** Create a trading pair with a vault token (e.g., wstETH/sDAI pool)
- **Strategy inputs for other vaults:** A Yearn allocator vault can add any ERC-4626 vault as a strategy, including another allocator vault (vault-of-vaults)

This composability is why ERC-4626 adoption has been so rapid — each new vault automatically works with every protocol that supports the standard.

<a id="vault-security"></a>
### ⚠️ Security Considerations for Vault Builders

**1. totalAssets() must be manipulation-resistant.** If `totalAssets()` reads external state that can be manipulated within a transaction (DEX spot prices, raw token balances), your vault is vulnerable. Use internal accounting or time-delayed oracles.

**2. Withdrawal liquidity risk.** If all assets are deployed to strategies, a large withdrawal can fail. Maintain an "idle buffer" (percentage of assets not deployed) and implement a withdrawal queue that pulls from strategies in priority order.

**3. Strategy loss handling.** Strategies can lose money (smart contract hack, bad debt in lending, impermanent loss). The vault must handle losses gracefully — reduce share price proportionally, not revert on withdrawal. Yearn V3's `max_loss` parameter lets users specify acceptable loss on withdrawal.

**4. Sandwich attack on harvest.** An attacker sees a pending `harvest()` transaction that will increase `totalAssets`. They front-run with a deposit (buying shares cheap), let harvest execute (share price increases), then back-run with a withdrawal (redeeming at higher price). Defense: profit unlocking over time (Yearn's `profitMaxUnlockTime`), deposit/withdrawal fees, or private transaction submission.

**5. Fee-on-transfer and rebasing tokens.** ERC-4626 assumes standard ERC-20 behavior. Fee-on-transfer tokens deliver less than the requested amount on `transferFrom`. Rebasing tokens change balances outside of transfers. Both break naive vault accounting. Use balance-before-after checks (Module 1 pattern) and avoid rebasing tokens as underlying assets.

**6. ERC-4626 compliance edge cases.** The standard requires specific behaviors for max functions (must return `type(uint256).max` or actual limit), preview functions (must be exact or revert), and empty vault handling. Non-compliant implementations cause integration failures across the ecosystem. Test against the ERC-4626 property tests.

#### 💼 Job Market Context

**What DeFi teams expect you to know about vault security:**

1. **"How would you prevent sandwich attacks on a yield vault?"**
   - Good answer: "Use profit unlocking — spread harvested yield over hours/days so an attacker can't capture it instantly."
   - Great answer: "Three layers: (1) linear profit unlocking via `profitMaxUnlockTime` (Yearn's approach) — profits accrue to share price gradually; (2) deposit/withdrawal fees that punish short-term deposits; (3) private transaction submission (Flashbots Protect) for harvest calls so MEV searchers can't see them in the mempool."

2. **"A protocol wants to use your ERC-4626 vault token as collateral. What do you warn them about?"**
   - Good answer: "Don't use `convertToAssets()` directly for pricing — it can be manipulated via donation."
   - Great answer: "Three risks: (1) the vault's exchange rate can be manipulated within a single transaction (donation attack) — use a TWAP or oracle for pricing; (2) the vault may have withdrawal liquidity constraints (strategy funds locked, withdrawal queue) — so liquidation may fail; (3) the vault's `totalAssets()` may include unrealized gains that could reverse (strategy loss, depeg). They should read `maxWithdraw()` to check actual liquidity."

3. **"What yield strategy patterns have you built or reviewed?"**
   - Good answer: "Auto-compounders that claim rewards and reinvest, leveraged staking."
   - Great answer: "I've worked with (1) auto-compounders with keeper economics (harvest only when reward value exceeds gas + slippage); (2) leveraged yield via recursive borrowing with automated health factor management; (3) LP strategies that handle impermanent loss reporting; (4) allocator vaults that rebalance across multiple strategies based on utilization and APY signals."

**Hot topics (2025-26):**
- ERC-4626 as collateral in lending markets (Morpho, Euler V2, Aave V3.1)
- Curator/vault-as-a-service models replacing monolithic vault managers
- Restaking vaults (EigenLayer, Symbiotic) — ERC-4626 wrappers around restaking positions
- Real-world asset (RWA) vaults — tokenized treasury yields via ERC-4626

### 🛠️ Exercise

**Workspace:** [`workspace/src/part2/module7/exercise4-auto-compounder/`](../workspace/src/part2/module7/exercise4-auto-compounder/) — starter files: [`AutoCompounder.sol`](../workspace/src/part2/module7/exercise4-auto-compounder/AutoCompounder.sol), [`MockSwap.sol`](../workspace/src/part2/module7/exercise4-auto-compounder/MockSwap.sol), tests: [`AutoCompounder.t.sol`](../workspace/test/part2/module7/exercise4-auto-compounder/AutoCompounder.t.sol)

**Exercise 1: Auto-compounder.** Build an ERC-4626 vault that:
- Deposits USDC into a mock lending protocol
- Earns yield in a separate REWARD token
- Has a `harvest()` function that claims REWARD, swaps to USDC via a mock DEX, and re-deposits
- Verify: share price increases after harvest, profit unlocks over time

**Exercise 2: Sandwich defense.** Using your vault from Exercise 1:
- Show the sandwich attack: deposit → harvest → withdraw captures yield
- Implement linear profit unlocking over 6 hours
- Show the same sandwich attempt now captures minimal yield

**Exercise 3: Strategy loss.** Using the allocator vault from the Yield Aggregation section:
- Simulate a strategy losing 20% of its funds (mock a hack)
- Call report — verify the vault correctly records the loss
- Verify share price decreased proportionally
- Verify existing depositors can still withdraw (at reduced value)
- Verify new depositors enter at the correct (lower) share price

### 📋 Summary: Composable Yield Patterns and Security

**✓ Covered:**
- Auto-compounding: claim rewards → swap → re-deposit, keeper economics
- Leveraged yield: recursive borrowing, health factor management, flash loan shortcuts
- LP + staking: AMM liquidity + reward farming (Curve/Convex pattern)
- Vault composability: ERC-4626 tokens as collateral, LP assets, or strategy inputs
- Six critical security considerations for vault builders
- Sandwich attack on harvest and profit unlocking defense

**Key insight:** ERC-4626 composability is a double-edged sword. It enables powerful yield strategies (vault-of-vaults, vault tokens as collateral), but every layer of composition adds attack surface. The security checklist (manipulation-resistant `totalAssets`, withdrawal liquidity, loss handling, sandwich defense, token edge cases, compliance) is non-negotiable for production vaults.

---

## ⚠️ Common Mistakes

**Mistake 1: Using `balanceOf(address(this))` for `totalAssets()`**

```solidity
// WRONG — vulnerable to donation attack
function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this));
}

// CORRECT — internal accounting
uint256 private _managedAssets;
function totalAssets() public view returns (uint256) {
    return _managedAssets;
}
```

**Mistake 2: Wrong rounding direction in conversions**

```solidity
// WRONG — rounds in favor of the USER (attacker can drain vault)
function convertToShares(uint256 assets) public view returns (uint256) {
    return assets * totalSupply() / totalAssets();  // rounds down = fewer shares (OK for deposit)
}
function previewWithdraw(uint256 assets) public view returns (uint256) {
    return assets * totalSupply() / totalAssets();  // rounds down = fewer shares burned (BAD!)
}

// CORRECT — withdraw must round UP (burn more shares = vault-favorable)
function previewWithdraw(uint256 assets) public view returns (uint256) {
    return Math.mulDiv(assets, totalSupply(), totalAssets(), Math.Rounding.Ceil);
}
```

**Mistake 3: Not handling the empty vault case**

```solidity
// WRONG — division by zero when totalSupply == 0
function convertToShares(uint256 assets) public view returns (uint256) {
    return assets * totalSupply() / totalAssets();  // 0/0 on first deposit!
}

// CORRECT — handle first deposit explicitly or use virtual shares
function convertToShares(uint256 assets) public view returns (uint256) {
    uint256 supply = totalSupply();
    return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets());
}
```

**Mistake 4: Instantly reflecting harvested yield in share price**

```solidity
// WRONG — enables sandwich attack on harvest
function harvest() external {
    uint256 profit = strategy.claim();
    _managedAssets += profit;  // share price jumps instantly
}

// CORRECT — unlock profit linearly over time
function harvest() external {
    uint256 profit = strategy.claim();
    _profitUnlockingRate = profit / UNLOCK_PERIOD;
    _lastHarvestTimestamp = block.timestamp;
    _fullProfitUnlockDate = block.timestamp + UNLOCK_PERIOD;
}

function totalAssets() public view returns (uint256) {
    uint256 unlocked = _profitUnlockingRate * (block.timestamp - _lastHarvestTimestamp);
    return _managedAssets + Math.min(unlocked, _totalLockedProfit);
}
```

**Mistake 5: Not checking `maxDeposit`/`maxWithdraw` before operations**

```solidity
// WRONG — assumes vault always accepts deposits
function depositIntoVault(IERC4626 vault, uint256 assets) external {
    vault.deposit(assets, msg.sender);  // reverts if vault is paused or full!
}

// CORRECT — check limits first
function depositIntoVault(IERC4626 vault, uint256 assets) external {
    uint256 maxAllowed = vault.maxDeposit(msg.sender);
    require(assets <= maxAllowed, "Exceeds vault deposit limit");
    vault.deposit(assets, msg.sender);
}
```

---

## 📋 Key Takeaways

1. **ERC-4626 is the TCP/IP of DeFi yield.** It's the universal interface that lets any vault plug into any protocol. Understanding it deeply — the math, the rounding rules, the security model — is foundational for building anything yield-related.

2. **Share math is the same pattern everywhere.** Aave aTokens, Compound cTokens, Uniswap LP tokens, Yearn vault tokens, MakerDAO DSR — they all use the same shares × rate = assets formula. Master it once, apply it everywhere.

3. **The inflation attack is real and ongoing.** It exploited protocols as recently as 2025. Virtual shares (OpenZeppelin) or internal accounting are non-negotiable defenses. Never use raw `balanceOf` for critical pricing.

4. **Profit unlocking prevents sandwich attacks.** Any vault that instantly reflects harvested yield in share price is vulnerable. Linear unlock over hours/days is the standard defense.

5. **The allocator pattern is the future of DeFi.** Yearn V3, Morpho curators, Euler V2 vaults — the industry is converging on modular ERC-4626 vaults with pluggable strategies. Building and understanding this pattern prepares you for the current state of DeFi architecture.

6. **Leveraged yield is profitable only when incentives exceed the borrow-supply spread.** Recursive borrowing amplifies both yield and cost. When incentives dry up or borrow rates spike, leveraged positions bleed money. Same-asset strategies (USDC/USDC) avoid liquidation risk but still face rate inversion.

7. **The curator model separates infrastructure from risk management.** Protocol layer handles mechanics (lending, swaps), curator layer handles allocation (which markets, what caps, what risk parameters). This modular stack — each layer using ERC-4626 — is how production DeFi is being built in 2025-26.

---

## 🔗 Cross-Module Concept Links

### Backward References (concepts from earlier modules used here)

| Source | Concept | How It Connects |
|---|---|---|
| **Part 1 Section 1** | `mulDiv` with rounding | Vault conversions use `Math.mulDiv` with explicit rounding direction — rounds down for deposits, up for withdrawals |
| **Part 1 Section 1** | Custom errors | Vault revert patterns (`DepositExceedsMax`, `InsufficientShares`) use typed errors from Section 1 |
| **Part 1 Section 2** | Transient storage | Reentrancy guard for vault deposit/withdraw uses transient storage pattern from Section 2 |
| **Part 1 Section 5** | Fork testing | ERC-4626 Quick Try reads a live Yearn vault on mainnet fork — fork testing from Section 5 enables this |
| **Part 1 Section 5** | Invariant testing | ERC-4626 property tests (a16z suite) use invariant/fuzz patterns from Section 5 |
| **Part 1 Section 6** | Proxy / delegateCall | Yearn V3 TokenizedStrategy uses `delegateCall` to shared implementation — proxy pattern from Section 6 |
| **M1** | SafeERC20 | All vault deposit/withdraw flows use SafeERC20 for underlying token transfers |
| **M1** | Fee-on-transfer tokens | Break naive vault accounting — balance-before-after check from M1 is required |
| **M2** | MINIMUM_LIQUIDITY / dead shares | Uniswap V2's dead shares defense is the same pattern as Defense 2 (burn shares to `address(1)`) |
| **M2** | AMM swaps / MEV | Auto-compound harvest routes through DEXs — slippage and sandwich risks from M2 apply directly |
| **M3** | Oracle pricing | Vault tokens used as lending collateral need oracle pricing — can't trust the vault's own `convertToAssets()` |
| **M4** | Index-based accounting | `shares × rate = assets` is the same pattern as Aave's `scaledBalance × liquidityIndex` |
| **M5** | Flash loans | Enable single-tx recursive leverage; also enable atomic sandwich attacks on harvest |
| **M6** | MakerDAO DSR / sDAI | DSR Pot is a vault pattern; sDAI is an ERC-4626 wrapper around it — same share math |

### Forward References (where these concepts lead)

| Target | Concept | How It Connects |
|---|---|---|
| **M8** | Invariant testing for vaults | Property-based tests verify vault rounding, share price monotonicity, withdrawal guarantees |
| **M8** | Composability attack surfaces | Multi-layer vault composition creates novel attack vectors covered in M8 threat models |
| **M9** | Vault shares as collateral | Integration capstone uses ERC-4626 vault tokens as building blocks |
| **M9** | Yield aggregator integration | Capstone combines vault patterns with flash loans and liquidation mechanics |
| **Part 3 M1** | Upgradeable vault architecture | Proxy patterns for vault upgrades and migration strategies |
| **Part 3 M5** | Formal verification | Proving vault invariants (share price monotonicity, rounding correctness) formally |
| **Part 3 M8** | Vault deployment | Production deployment patterns for vault infrastructure |
| **Part 3 M9** | Vault monitoring | Runtime monitoring of vault health, strategy performance, exchange rate anomalies |

---

## 📖 Production Study Order

Study these implementations in order — each builds on concepts from the previous:

| # | Repository | Why Study This | Key Files |
|---|---|---|---|
| 1 | [OpenZeppelin ERC4626](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol) | Foundation implementation with virtual shares defense — the reference all others compare against | `ERC4626.sol` (conversion math, rounding), `Math.sol` (mulDiv) |
| 2 | [Solmate ERC4626](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC4626.sol) | Minimal gas-efficient alternative — no virtual shares, shows the trade-off between safety and efficiency | `ERC4626.sol` (compare rounding, no `_decimalsOffset`) |
| 3 | [Yearn TokenizedStrategy](https://github.com/yearn/tokenized-strategy/blob/master/src/TokenizedStrategy.sol) | The delegation pattern — how a strategy delegates ERC-4626 logic to a shared implementation via `delegateCall` | `TokenizedStrategy.sol` (accounting, reporting), `BaseStrategy.sol` (the 3 overrides) |
| 4 | [Yearn VaultV3](https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy) | Allocator vault with profit unlocking, role system, and multi-strategy debt management | `VaultV3.vy` (`process_report`, `update_debt`, profit unlock), `TECH_SPEC.md` |
| 5 | [Morpho MetaMorpho](https://github.com/morpho-org/metamorpho/blob/main/src/MetaMorpho.sol) | Production curator vault — allocates across Morpho Blue lending markets, real-world fee/cap/queue mechanics | `MetaMorpho.sol` (allocation logic, fee handling, withdrawal queue) |
| 6 | [a16z ERC-4626 Property Tests](https://github.com/a16z/ERC4626-property-tests) | Comprehensive compliance test suite — run against any vault to verify rounding, preview accuracy, edge cases | `ERC4626.prop.sol` (all property tests), README (how to integrate) |

**Reading strategy:** Start with OZ ERC4626 (1) to understand the math foundation. Compare with Solmate (2) to see what "no virtual shares" means in practice. Then read a simple Yearn strategy (3) to understand the user-facing abstraction. VaultV3 (4) shows how strategies compose into an allocator. MetaMorpho (5) is the most production-complete curator vault. Finally, run the a16z tests (6) against your own implementations.

---

## 📚 Resources

**ERC-4626:**
- [EIP-4626 specification](https://eips.ethereum.org/EIPS/eip-4626)
- [Ethereum.org ERC-4626 overview](https://ethereum.org/developers/docs/standards/tokens/erc-4626)
- [OpenZeppelin ERC-4626 implementation + security guide](https://docs.openzeppelin.com/contracts/5.x/erc4626)
- [OpenZeppelin ERC4626.sol source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)

**Inflation attack:**
- [MixBytes — Overview of the inflation attack](https://mixbytes.io/blog/overview-of-the-inflation-attack)
- [OpenZeppelin — ERC-4626 exchange rate manipulation risks](https://www.openzeppelin.com/news/erc-4626-tokens-in-defi-exchange-rate-manipulation-risks)
- [SpeedrunEthereum — ERC-4626 vault security](https://speedrunethereum.com/guides/erc-4626-vaults)

**Yearn V3:**
- [V3 overview](https://docs.yearn.fi/developers/v3/overview)
- [VaultV3 technical spec](https://github.com/yearn/yearn-vaults-v3/blob/master/TECH_SPEC.md)
- [Tokenized Strategy source](https://github.com/yearn/tokenized-strategy)
- [Strategy writing guide](https://docs.yearn.fi/developers/v3/strategy_writing_guide)

**ERC-4626 Property Tests:**
- [a16z ERC-4626 property tests](https://github.com/a16z/ERC4626-property-tests) — Comprehensive property-based test suite for ERC-4626 compliance. Run these against any vault implementation to verify spec-correctness: rounding invariants, preview accuracy, max function behavior, and edge cases. If your vault passes these, it will integrate correctly with the broader ERC-4626 ecosystem.
- [OpenZeppelin ERC-4626 tests](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/test/token/ERC20/extensions) — OpenZeppelin's own test suite covers the virtual share mechanism and rounding behavior.

**Modular DeFi / Curators:**
- [Morpho documentation](https://docs.morpho.org)
- [Euler V2 documentation](https://docs.euler.finance)
- [MetaMorpho source](https://github.com/morpho-org/metamorpho) — Production ERC-4626 curator vault

---

## 🎯 Practice Challenges

These challenges test vault interaction patterns and are best attempted after completing the module:

- **Damn Vulnerable DeFi #15 — "ABI Smuggling":** A vault with an authorization mechanism that can be bypassed through careful ABI encoding. Tests your understanding of how vault deposit/withdraw flows interact with access control.

---

**Navigation:** [← Module 6: Stablecoins & CDPs](6-stablecoins-cdps.md) | [Module 8: DeFi Security →](8-defi-security.md)

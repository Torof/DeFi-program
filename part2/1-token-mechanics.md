# Part 2 — Module 1: Token Mechanics in Practice

> **Difficulty:** Beginner
>
> **Estimated reading time:** ~30 minutes | **Exercises:** ~2 hours

---

## 📚 Table of Contents

**ERC-20 Core Patterns & Weird Tokens**
- [The Approval Model](#approval-model)
- [Decimal Handling — The Silent Bug Factory](#decimal-handling)
- [Read: OpenZeppelin ERC20 and SafeERC20](#read-oz-erc20)
- [Read: The Weird ERC-20 Catalog](#read-weird-erc20)

**Advanced Token Behaviors & Protocol Design**
- [Advanced Token Behaviors That Break Protocols](#advanced-token-behaviors)
- [Read: WETH](#read-weth)
- [Token Listing Patterns](#token-listing-patterns)
- [Token Evaluation Checklist](#token-evaluation-checklist)
- [Build Exercises: Token Interaction Patterns](#build-token-test-suite)

---

## 💡 ERC-20 Core Patterns & Weird Tokens

**Why this matters:** Every DeFi protocol moves tokens. AMMs swap them, lending pools custody them, vaults compound them. Before you build any of that, you need to deeply understand how token interactions actually work at the contract level — not just the [ERC-20 interface](https://eips.ethereum.org/EIPS/eip-20), but the real-world edge cases that have caused millions in losses.

> **Real impact:** [Hundred Finance hack](https://rekt.news/hundred-rekt2/) ($7M, April 2023) — exploited lending pool that didn't account for [ERC-777](https://eips.ethereum.org/EIPS/eip-777) [reentrancy hooks](https://github.com/d-xo/weird-erc20#reentrant-calls). [SushiSwap MISO incident](https://www.coindesk.com/tech/2021/09/17/3m-in-ether-stolen-from-sushiswap-token-launchpad/) ($3M, September 2021) — malicious token with transfer() that silently failed but returned true, draining auction funds.

> **Note:** Permit ([EIP-2612](https://eips.ethereum.org/EIPS/eip-2612)) and [Permit2](https://github.com/Uniswap/permit2) patterns are covered in Part 1 Module 3. This module focuses on the ERC-20 edge cases and safe integration patterns that will affect every protocol you build in Part 2.

<a id="approval-model"></a>
### 💡 Concept: The Approval Model

**Why this matters:** The approve/transferFrom two-step isn't just a design pattern — it's the foundation that every DeFi interaction is built on. Understanding *why* it exists and how it shapes protocol architecture is essential before building anything.

**The core problem:** A smart contract can't "pull" tokens from a user without prior authorization. Unlike ETH (which can be sent with `msg.value`), ERC-20 tokens require the user to first call `approve(spender, amount)` on the token contract, granting the spender permission. The protocol then calls `transferFrom(user, protocol, amount)` to actually move the tokens.

This creates the foundational DeFi interaction pattern:

```
User → Token.approve(protocol, amount)    // tx 1: grant permission
User → Protocol.deposit(amount)           // tx 2: protocol calls transferFrom internally
```

Every DeFi protocol you'll ever build begins here. [Uniswap V2](https://github.com/Uniswap/v2-core), [Aave V3](https://github.com/aave/aave-v3-core), [Compound V3](https://github.com/compound-finance/comet) — all use this exact pattern.

> **Deep dive:** [EIP-20 specification](https://eips.ethereum.org/EIPS/eip-20) defines the standard, but see [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20) for what the standard *doesn't* cover.

#### 🔗 DeFi Pattern Connection

**Where the approve/transferFrom pattern shapes protocol architecture:**

1. **AMMs (Module 2):** Uniswap V2's "pull" pattern — users approve the Router, Router calls `transferFrom` to move tokens into Pair contracts. V4 replaces this with flash accounting
2. **Lending (Module 4):** Users approve the Pool contract to pull collateral. Aave V3 and Compound V3 both use this for deposits
3. **Vaults (Module 7):** [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vaults call `transferFrom` on deposit — the entire vault standard is built on this two-step pattern
4. **Alternative:** Permit (Part 1 Module 3) eliminates the separate approve transaction by using [EIP-712](https://eips.ethereum.org/EIPS/eip-712) signatures

---

<a id="decimal-handling"></a>
### 💡 Concept: Decimal Handling — The Silent Bug Factory

**Why this matters:** Tokens have different decimal places: USDC and USDT use 6, WBTC uses 8, DAI and WETH use 18. Incorrect decimal normalization is one of the most common sources of DeFi bugs. When your protocol compares 1 USDC (1e6) with 1 DAI (1e18), you're comparing numbers that differ by a factor of 10^12. Get this wrong and your protocol is either giving away money or locking up funds.

**The core problem:**

```solidity
// ❌ WRONG: Comparing raw amounts of different tokens
// 1 USDC = 1_000_000 (6 decimals)
// 1 DAI  = 1_000_000_000_000_000_000 (18 decimals)
// This makes 1 DAI look like 1 trillion USDC
uint256 totalValue = usdcAmount + daiAmount; // Meaningless!

// ✅ CORRECT: Normalize to a common base (e.g., 18 decimals)
uint256 normalizedUSDC = usdcAmount * 10**(18 - 6);  // Scale up to 18 decimals
uint256 normalizedDAI = daiAmount;                     // Already 18 decimals
uint256 totalValue = normalizedUSDC + normalizedDAI;   // Now comparable
```

**How production protocols handle this:**

**Aave V3** normalizes all asset amounts to 18 decimals internally using a `reserveDecimals` lookup:

```solidity
// From Aave V3's ReserveLogic — all internal math uses normalized amounts
// See: https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/ReserveLogic.sol
uint256 normalizedAmount = amount * 10**(18 - reserve.configuration.getDecimals());
```

**Chainlink price feeds** return prices with varying decimals — ETH/USD uses 8 decimals, but other feeds may differ. You must always call `decimals()` on the feed:

```solidity
// ❌ BAD: Hardcoding 8 decimals
uint256 price = uint256(answer) * 1e10; // Assumes 8 decimals — breaks on some feeds

// ✅ GOOD: Dynamic decimal handling
uint8 feedDecimals = priceFeed.decimals();
uint256 price = uint256(answer) * 10**(18 - feedDecimals);
```

> **Edge case — extreme decimals:** Most tokens use 6, 8, or 18, but outliers exist. [GUSD](https://etherscan.io/token/0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd) uses 2 decimals, and some tokens use >18 (e.g., 24). Normalizing with `10**(18 - decimals)` underflows when `decimals > 18`. Always guard: `require(decimals <= 18)` or handle both directions with `decimals > 18 ? amount / 10**(decimals - 18) : amount * 10**(18 - decimals)`.

> **Common pitfall:** Hardcoding Chainlink feed decimals to 8. While ETH/USD and BTC/USD use 8, the ETH/BTC feed uses 18. Always call `priceFeed.decimals()` and normalize dynamically. See [Chainlink feed registry](https://docs.chain.link/data-feeds/feed-registry).

**Compound V3 (Comet)** stores an explicit `baseTokenDecimals` and uses scaling factors throughout:

```solidity
// From Compound V3 — explicit scaling
// See: https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol
uint256 internal immutable baseScale; // = 10 ** baseToken.decimals()
```

> **Real impact:** Decimal bugs are among the most common critical findings in [Code4rena contests](https://code4rena.com/). A recurring pattern: protocol assumes 18 decimals for all tokens, then someone deposits USDC (6 decimals) or WBTC (8 decimals) and the math is off by factors of 10^10 or 10^12 — either giving away funds or locking them. [Midas Finance](https://rekt.news/midas-capital-rekt/) ($660K, January 2023) was exploited partly because a newly listed collateral token's decimal handling wasn't properly validated.

💻 **Quick Try:**

Test this in your Foundry console to feel the difference:

```solidity
// In a Foundry test
uint256 oneUSDC = 1e6;    // 1 USDC (6 decimals)
uint256 oneDAI  = 1e18;   // 1 DAI (18 decimals)
uint256 oneWBTC = 1e8;    // 1 WBTC (8 decimals)

// Normalize all to 18 decimals
uint256 normUSDC = oneUSDC * 1e12;  // 1e6 * 1e12 = 1e18 ✓
uint256 normWBTC = oneWBTC * 1e10;  // 1e8 * 1e10 = 1e18 ✓

assertEq(normUSDC, oneDAI);  // Both represent "1 token" at 18 decimals
```

> **Deep dive:** [OpenZeppelin Math.mulDiv](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol) — when scaling involves multiplication that could overflow, use `mulDiv` for safe precision handling. Covered in Part 1 Module 1.

---

<a id="read-oz-erc20"></a>
#### 📖 Read: OpenZeppelin ERC20 and SafeERC20

**Source:** [@openzeppelin/contracts v5.x](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20)

Read the [OpenZeppelin ERC20 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol) end-to-end. Pay attention to:

- The `_update()` function (v5.x replaced `_beforeTokenTransfer`/`_afterTokenTransfer` hooks with a single `_update` function — this is a design change you'll encounter when reading older protocol code vs newer code)
- How `approve()` and `transferFrom()` interact through the `_allowances` mapping
- The `_spendAllowance()` helper and its special case for `type(uint256).max` (infinite approval)

Then read [SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) carefully. This is not optional — it's mandatory for any protocol that accepts arbitrary tokens.

**The key insight:** The [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20) says `transfer()` and `transferFrom()` should return `bool`, but major tokens like [USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7) don't return anything at all. SafeERC20 handles this by using low-level calls and checking both the return data length and value.

**Key functions to understand:**
- `safeTransfer` / `safeTransferFrom` — handles non-compliant tokens that don't return bool
- `forceApprove` — replaces the deprecated `safeApprove`, handles USDT's "must approve to 0 first" behavior

> **Used by:** [Uniswap V3 NonfungiblePositionManager](https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol#L9), [Aave V3 Pool](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol#L11), [Compound V3 Comet](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — every major protocol uses SafeERC20.

#### 📖 How to Study SafeERC20:

1. **Read the interface first** — `IERC20.sol` defines what tokens *should* do
2. **Read `safeTransfer`** — See how it uses `functionCallWithValue` to handle missing return values
3. **Read `forceApprove`** — Understand the USDT "approve to zero first" workaround
4. **Compare with Solmate's `SafeTransferLib`** — [Solmate's version](https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol) skips `address.code.length` checks for gas savings (trade-off: no empty address detection)
5. **Don't get stuck on:** The assembly-level return data parsing — understand *what* it does (check return bool or accept empty return), not every opcode

---

<a id="read-weird-erc20"></a>
#### 📖 Read: The Weird ERC-20 Catalog

**Source:** [github.com/d-xo/weird-erc20](https://github.com/d-xo/weird-erc20)

**Why this matters:** This repository documents real tokens with behaviors that break naive assumptions. As a protocol builder, you must design for these. The critical categories:

**1. Missing return values**

[USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#code), [BNB](https://etherscan.io/token/0xB8c77482e45F1F44dE1745F52C74426C631bDD52), [OMG](https://etherscan.io/token/0xd26114cd6EE289AccF82350c8d8487fedB8A0C07) don't return `bool`. If your protocol does `require(token.transfer(...))`, it will fail on these tokens. SafeERC20 exists specifically for this.

> **Common pitfall:** Writing `require(token.transfer(to, amount))` without SafeERC20. This compiles fine with standard ERC-20 but silently reverts with USDT. Always use `token.safeTransfer(to, amount)`.

**2. Fee-on-transfer tokens**

[STA](https://etherscan.io/token/0xa7DE087329BFcda5639aF29130af3Da1C99dF6e4), [PAXG](https://etherscan.io/token/0x45804880De22913dAFE09f4980848ECE6EcbAf78), and others deduct a fee on every transfer. If a user sends 100 tokens, the protocol might only receive 97.

**The standard pattern to handle this:**

```solidity
uint256 balanceBefore = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - balanceBefore;
// Use `received`, not `amount`
```

This "balance-before-after" pattern adds ~2,000 gas but is essential when supporting arbitrary tokens. You'll see this in [Uniswap V2's `swap()` function](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L159-L160) and many lending protocols.

> **Real impact:** Early AMM forks that assumed `amount` == received balance got arbitraged to death when fee-on-transfer tokens were added to pools. The fee was extracted by the token contract but the AMM credited the full amount, leading to protocol insolvency.

💻 **Quick Try:**

Deploy this in Foundry to see the balance-before-after pattern catch a fee-on-transfer token:

```solidity
// In a Foundry test file
function test_FeeOnTransferCaughtByBalanceCheck() public {
    FeeOnTransferToken feeToken = new FeeOnTransferToken();
    feeToken.mint(alice, 1000e18);

    vm.startPrank(alice);
    feeToken.approve(address(vault), 1000e18);

    // Alice deposits 100 tokens, but 1% fee means vault receives 99
    uint256 vaultBalBefore = feeToken.balanceOf(address(vault));
    feeToken.transfer(address(vault), 100e18);
    uint256 received = feeToken.balanceOf(address(vault)) - vaultBalBefore;

    // Without balance-before-after: would credit 100e18 (WRONG)
    // With balance-before-after: correctly credits 99e18
    assertEq(received, 99e18);  // 100 - 1% fee = 99
    vm.stopPrank();
}
```

Run it and see the 1% difference. This is why `received != amount`.

**3. Rebasing tokens**

[stETH](https://etherscan.io/token/0xae7ab96520de3a18e5e111b5eaab095312d7fe84), [AMPL](https://etherscan.io/token/0xd46ba6d942050d489dbd938a2c909a5d5039a161), [OHM](https://etherscan.io/token/0x64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d5) change user balances automatically. A protocol that stores `balanceOf` at deposit time may find the actual balance has changed by withdrawal.

**Protocols either:**
- (a) Wrap rebasing tokens into non-rebasing versions ([wstETH](https://docs.lido.fi/contracts/wsteth/) for stETH)
- (b) Explicitly exclude them ([Uniswap V2 explicitly warns against rebasing tokens](https://docs.uniswap.org/contracts/v2/reference/smart-contracts/common-errors#rebasing-tokens))

> **Used by:** [Aave V3 treats stETH specially](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) by wrapping to wstETH, [Curve has dedicated pools for rebasing tokens](https://curve.fi/#/ethereum/pools/steth/deposit) with special accounting.

**4. Approval race condition**

If Alice has approved 100 tokens to a spender, and then calls `approve(200)`, the spender can front-run to spend the original 100, then spend the new 200, getting 300 total.

**Solutions:**
- USDT's brute-force: "approve to zero first" requirement
- Better: use `increaseAllowance`/`decreaseAllowance` (removed from OZ v5 core but still available in extensions)
- Best: use [Permit (EIP-2612)](https://eips.ethereum.org/EIPS/eip-2612) or [Permit2](https://github.com/Uniswap/permit2) (covered in Part 1 Module 3)

> **Common pitfall:** Calling `approve(newAmount)` directly without first checking if existing approval is non-zero. With USDT, this reverts. Use `forceApprove` which handles the zero-first pattern automatically.

**5. Tokens that revert on zero transfer**

[LEND](https://etherscan.io/token/0x80fB784B7eD66730e8b1DBd9820aFD29931aab03) and others revert when transferring 0 tokens. Your protocol logic needs to guard against this:

```solidity
if (amount > 0) {
    token.safeTransfer(to, amount);
}
```

> **Common pitfall:** Batch operations that might include zero amounts (e.g., claiming rewards when no rewards are due). Always guard against zero transfers when supporting arbitrary tokens.

**6. Tokens with multiple entry points**

Some proxied tokens have multiple addresses pointing to the same contract. Don't use `address(token)` as a unique identifier without care.

> **Used by:** [Aave V3 uses internal assetId mappings](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) rather than relying solely on token addresses.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"A user reports they deposited 100 tokens but only got credit for 97. What happened?"**
   - Good answer: "Fee-on-transfer token"
   - Great answer: "Almost certainly a fee-on-transfer token like STA or PAXG. The fix is the balance-before-after pattern — measure `balanceOf` before and after `transferFrom`, credit the delta not the input amount. If this is a new finding, we also need to audit all other deposit/transfer paths for the same bug. This is why testing with `FeeOnTransferToken` mocks is essential."

**Interview Red Flags:**
- 🚩 Not knowing what `SafeERC20` is or why `token.transfer()` needs wrapping
- 🚩 Never heard of fee-on-transfer tokens
- 🚩 Treating all ERC-20 tokens as identical in behavior

**Pro tip:** Mention the [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20) by name in interviews — it shows you've studied real-world token edge cases, not just the EIP-20 spec.

#### 🔗 DeFi Pattern Connection

**Where weird token behaviors break real protocols:**

1. **AMMs (Module 2):** Fee-on-transfer tokens cause accounting drift in constant product pools — Uniswap V2's `_update()` syncs from actual balances to handle this
2. **Lending (Module 4):** Rebasing tokens break collateral accounting — Aave V3 wraps stETH to wstETH before accepting as collateral
3. **Yield (Module 7):** Fee-on-transfer in ERC-4626 vault deposits requires balance-before-after to compute correct share amounts

---

<a id="intermediate-example-safe-deposit"></a>
#### 🎓 Intermediate Example: Building a Minimal Safe Deposit Function

Before diving into the advanced token behaviors below, let's bridge from basic SafeERC20 to a production-ready pattern. This combines everything from topics 1-6 above:

```solidity
/// @notice Handles deposits for ANY ERC-20, including weird ones
function deposit(IERC20 token, uint256 amount) external nonReentrant {
    // 1. Guard zero amounts (some tokens revert on zero transfer)
    require(amount > 0, "Zero deposit");

    // 2. Balance-before-after (handles fee-on-transfer tokens)
    uint256 balanceBefore = token.balanceOf(address(this));
    token.safeTransferFrom(msg.sender, address(this), amount);
    uint256 received = token.balanceOf(address(this)) - balanceBefore;

    // 3. Credit what we actually received, not what was requested
    balances[msg.sender] += received;

    emit Deposit(msg.sender, address(token), received);
}
```

**Why each line matters:**
- `nonReentrant` → guards against ERC-777 hooks (topic 7 below)
- `require(amount > 0)` → guards against tokens that revert on zero transfer (topic 5)
- `safeTransferFrom` → handles tokens with no return value like USDT (topic 1)
- `received` vs `amount` → handles fee-on-transfer tokens (topic 2)

This 8-line function handles 90% of weird token edge cases. The remaining 10% (rebasing, pausable, upgradeable) requires architectural decisions covered below.

---

## 📋 Key Takeaways: ERC-20 Core Patterns & Weird Tokens

After this section, you should be able to:
- Explain why SafeERC20 is mandatory for arbitrary tokens (USDT's missing return value), what `forceApprove` solves that `safeApprove` doesn't, and how Solmate's approach differs
- Given an unknown ERC-20, classify it into the 6 weird token categories (missing returns, fee-on-transfer, rebasing, approval race, zero-transfer revert, multiple entry points) and name the defensive pattern for each
- Implement the balance-before-after pattern for fee-on-transfer tokens and explain why trusting the `amount` parameter directly causes accounting drift
- Normalize token amounts across different decimal scales (USDC 6, WBTC 8, DAI 18) using dynamic `decimals()` lookups without precision loss

---

## 💡 Advanced Token Behaviors & Protocol Design

<a id="advanced-token-behaviors"></a>
### 💡 Concept: Advanced Token Behaviors That Break Protocols

Beyond the "weird ERC-20" edge cases above, several token categories introduce behaviors that fundamentally affect protocol architecture. You won't encounter these on every integration, but when you do, not knowing about them leads to exploits.

---

#### 7. 🔄 ERC-777 Hooks — Reentrancy Through Token Transfers

**Why this matters:** [ERC-777](https://eips.ethereum.org/EIPS/eip-777) is a token standard that adds `tokensToSend` and `tokensReceived` hooks — callback functions that execute during transfers. This means **every token transfer can trigger arbitrary code execution** on the sender or receiver, creating reentrancy vectors that don't exist with standard ERC-20.

**How it works:**

```
Normal ERC-20 transfer:
  Token.transfer(to, amount) → updates balances → done

ERC-777 transfer:
  Token.transfer(to, amount)
    → calls sender.tokensToSend()     ← arbitrary code runs HERE
    → updates balances
    → calls receiver.tokensReceived()  ← arbitrary code runs HERE
```

The receiver's `tokensReceived` hook fires *after* the balance update but *before* the calling contract's state is fully updated. This is the classic reentrancy window.

**Real exploits:**

> **Real impact:** [imBTC/Uniswap V1 exploit](https://zengo.com/imbtc-defi-hack-explained/) (~$300K, April 2020) — The attacker used imBTC (an ERC-777 token) on Uniswap V1, which had no reentrancy protection. The `tokensToSend` hook was called during `tokenToEthSwap`, allowing the attacker to re-enter the pool before reserves were updated, extracting more ETH than deserved.

> **Real impact:** [Hundred Finance exploit](https://rekt.news/hundred-rekt2/) ($7M, April 2023) — Similar pattern on a Compound V2 fork. The ERC-777 hook allowed reentrancy during the borrow flow.

**How to guard against it:**

```solidity
// Option 1: Reentrancy guard (from Part 1 Module 2 — use transient storage version!)
modifier nonReentrant() {
    assembly {
        if tload(0) { revert(0, 0) }
        tstore(0, 1)
    }
    _;
    assembly { tstore(0, 0) }
}

// Option 2: Checks-Effects-Interactions pattern (update state BEFORE external calls)
function withdraw(uint256 amount) external nonReentrant {
    require(balances[msg.sender] >= amount);
    balances[msg.sender] -= amount;      // Effect BEFORE interaction
    token.safeTransfer(msg.sender, amount); // Interaction LAST
}
```

> **Common pitfall:** Assuming reentrancy only happens through ETH transfers (`call{value: ...}`). ERC-777 hooks create reentrancy through *any token transfer* — including `transferFrom` calls within your protocol. This is why the Checks-Effects-Interactions pattern matters even for token-only protocols.

> **Used by:** [Uniswap V2 added a reentrancy lock](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L31-L36) specifically because of this risk. [Aave V3 uses reentrancy guards](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol) on all token-moving functions.

> **Deep dive:** [EIP-777 specification](https://eips.ethereum.org/EIPS/eip-777), [SWC-107: Reentrancy](https://swcregistry.io/docs/SWC-107/), [OpenZeppelin ERC777 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC777/ERC777.sol) (removed from OZ v5 — a signal that the standard is falling out of favor).

---

#### 8. 🔀 Upgradeable Tokens (Proxy Tokens)

**Why this matters:** Some of the most widely used tokens — [USDC](https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#code) ($30B+ market cap), [USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7) — are deployed behind proxies. The token issuer can upgrade the implementation contract, potentially changing behavior that your protocol depends on.

**What can change after an upgrade:**
- Transfer logic (adding fees, blocking addresses)
- Approval behavior
- New functions or modified interfaces
- Gas costs of operations
- Return value behavior

**Real-world example — USDC V2 → V2.1 upgrade:**
Circle upgraded USDC in August 2020 to add [gasless sends (EIP-3009)](https://eips.ethereum.org/EIPS/eip-3009) and [blacklisting improvements](https://www.circle.com/blog/announcing-usdc-v2-2). While this was benign, the capability to modify the token's behavior means your protocol must consider:

```solidity
// Your protocol assumption:
// "transfer() always moves exactly `amount` tokens"
// After an upgrade, this could become false if Circle adds a fee

// Defensive approach: balance-before-after even for "known" tokens
// when the token is upgradeable
uint256 balanceBefore = usdc.balanceOf(address(this));
usdc.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = usdc.balanceOf(address(this)) - balanceBefore;
```

> **Common pitfall:** Treating upgradeable tokens as static. If your protocol hardcodes assumptions about USDC's behavior (e.g., exact transfer amounts, no hooks, no fees), an upgrade could break your protocol without any code changes on your end. Defensive coding treats all proxy tokens as potentially changing.

**How protocols manage this risk:**
- **Monitoring:** Watch for [proxy upgrade events](https://eips.ethereum.org/EIPS/eip-1967) (`Upgraded(address indexed implementation)`) on critical tokens
- **Governance response:** Aave's [risk service providers](https://governance.aave.com/) monitor token changes and can pause markets
- **Conservative assumptions:** Use balance-before-after pattern even for "trusted" tokens

> **Used by:** [MakerDAO's collateral onboarding](https://github.com/makerdao/mips/blob/master/MIP6/mip6.md) evaluates whether tokens are upgradeable as a risk factor. [Aave's risk framework](https://docs.aave.com/risk/) considers proxy risk in asset ratings.

---

#### 9. 🔒 Pausable & Blacklistable Tokens

**Why this matters:** USDC and USDT have admin functions that can freeze your protocol's funds:

- **Pause:** The issuer can pause ALL transfers globally (USDC has `pause()`, USDT has `pause`)
- **Blacklist:** The issuer can block specific addresses from sending/receiving tokens (USDC has `blacklist(address)`, USDT has `addBlackList(address)`)

**The stuck funds scenario:**

```
1. User deposits 1000 USDC into your protocol
2. Your protocol holds USDC at address 0xProtocol
3. OFAC sanctions 0xProtocol (or a user who deposited)
4. Circle blacklists 0xProtocol
5. Your protocol can NEVER transfer USDC again — all user funds are stuck
```

This is not theoretical — [Tornado Cash sanctions](https://home.treasury.gov/news/press-releases/jy0916) (August 2022) led to Circle freezing ~$75K in USDC held in Tornado Cash contracts.

**How protocols handle this:**

```solidity
// Pattern 1: Allow withdrawal in alternative token
// If USDC is frozen, users can claim equivalent in another asset
function emergencyWithdraw(address user) external {
    uint256 amount = balances[user];
    balances[user] = 0;
    // Try USDC first
    try usdc.transfer(user, amount) {
        // Success
    } catch {
        // USDC frozen — pay in ETH or protocol token at oracle price
        uint256 ethEquivalent = getETHEquivalent(amount);
        payable(user).transfer(ethEquivalent);
    }
}

// Pattern 2: Support multiple stablecoins
// If one is frozen, liquidity can flow to others
// See: Curve 3pool (USDC + USDT + DAI) — diversification against single-issuer risk
```

> **Real impact:** When USDC depegged to $0.87 during the [SVB crisis](https://rekt.news/usdc-depeg/) (March 2023), protocols using USDC as sole collateral faced liquidation cascades. MakerDAO had already diversified to limit USDC exposure to ~40% of DAI backing. This is the operational reality of centralized stablecoin risk.

> **Common pitfall:** Assuming your protocol's address will never be blacklisted. Even if your protocol is legitimate, composability means a blacklisted address might interact with your contracts through a flash loan or arbitrage path, potentially contaminating your contract's history. [Chainalysis Reactor](https://www.chainalysis.com/reactor/) and [OFAC SDN list](https://sanctionssearch.ofac.treas.gov/) are the tools compliance teams use.

> **Used by:** [Aave V3 can freeze individual reserves](https://aave.com/docs/resources/risks) via governance if the underlying token is paused. [MakerDAO's PSM (Peg Stability Module)](https://github.com/makerdao/mips/blob/master/MIP29/mip29.md) has emergency shutdown capability for this scenario. [Liquity](https://docs.liquity.org/) chose to use only ETH as collateral — no freeze risk.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What happens if your protocol holds USDC and Circle blacklists your contract address?"**
   - Good answer: "USDC transfers would revert, funds would be stuck"
   - Great answer: "All USDC operations would revert. We need a mitigation strategy: either emergency withdrawal in an alternative asset (ETH, DAI), multi-stablecoin support so liquidity can migrate, or governance-triggered asset swap. MakerDAO's PSM handles this with emergency shutdown. We should also monitor the [OFAC SDN list](https://sanctionssearch.ofac.treas.gov/) and have an incident response plan."

**Interview Red Flags:**
- 🚩 Not knowing that USDC/USDT are upgradeable proxy tokens
- 🚩 Assuming your protocol's address will never be blacklisted
- 🚩 No awareness of the Tornado Cash sanctions precedent

**Pro tip:** In architecture discussions, proactively mention emergency withdrawal mechanisms and multi-stablecoin diversification — it shows you think about operational risk, not just code correctness.

---

#### 10. 📊 Token Supply Mechanics

**Why this matters:** Tokens don't just sit still — their total supply changes through minting and burning, and these supply mechanics directly affect protocol accounting.

**Inflationary tokens (reward emissions):**
Protocols like [Aave (stkAAVE)](https://aave.com/docs/developers/safety-module), [Compound (COMP)](https://compound.finance/governance/comp), and [Curve (CRV)](https://resources.curve.finance/crv-token/overview/) distribute reward tokens to users. When you build yield aggregators or reward distribution systems, you need to handle:
- Continuous emission schedules
- Reward accrual per block/second
- Claim accounting without iterating over all users (the "reward per token" pattern)

```solidity
// The standard reward-per-token pattern (from Synthetix StakingRewards)
// See: https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
rewardPerTokenStored += (rewardRate * (block.timestamp - lastUpdateTime) * 1e18) / totalSupply;
rewards[user] += balance[user] * (rewardPerTokenStored - userRewardPerTokenPaid[user]) / 1e18;
```

> **Used by:** This exact pattern (originally from [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol)) is used by virtually every DeFi protocol that distributes rewards — [Sushi MasterChef](https://github.com/sushiswap/masterchef/blob/master/contracts/MasterChef.sol), [Convex](https://github.com/convex-eth/platform/blob/main/contracts/contracts/BaseRewardPool.sol), [Yearn V3 gauges](https://docs.yearn.fi/).

#### 🔍 Deep Dive: Reward-Per-Token Math

**The problem it solves:** You have N stakers with different balances, and rewards flow in continuously. How do you track each staker's share without iterating over all stakers on every reward distribution? (Iterating would cost O(N) gas — unusable at scale.)

**The insight:** Instead of tracking each user's rewards directly, track a single global accumulator: "how much reward has been earned per 1 token staked, since the beginning of time?"

**Step-by-step example:**

```
Timeline: Alice stakes 100, then Bob stakes 200, then rewards arrive

State at T=0:
  totalSupply = 0, rewardPerToken = 0

T=100: Alice stakes 100 tokens
  totalSupply = 100
  Alice.userRewardPerTokenPaid = 0  (current rewardPerToken)

T=200: Bob stakes 200 tokens (100 seconds have passed, rewardRate = 1 token/sec)
  rewardPerToken += (1 * 100 * 1e18) / 100 = 1e18
  │                  │   │     │        └── totalSupply
  │                  │   │     └── scaling factor (for precision)
  │                  │   └── seconds elapsed (200 - 100)
  │                  └── rewardRate
  └── accumulator update

  totalSupply = 300 (100 + 200)
  Bob.userRewardPerTokenPaid = 1e18  (current rewardPerToken)

T=300: Alice claims rewards (another 100 seconds, now 300 totalSupply)
  rewardPerToken += (1 * 100 * 1e18) / 300 = 0.333e18
  rewardPerToken = 1e18 + 0.333e18 = 1.333e18

  Alice's reward = 100 * (1.333e18 - 0) / 1e18 = 133.3 tokens
  │                 │     │            │
  │                 │     │            └── Alice's userRewardPerTokenPaid (was 0)
  │                 │     └── current rewardPerToken
  │                 └── Alice's staked balance
  └── Her share: 100% of first 100 sec + 33% of next 100 sec = 100 + 33.3

  Bob's reward (if he claimed) = 200 * (1.333e18 - 1e18) / 1e18 = 66.6 tokens
  └── His share: 67% of last 100 sec = 66.6 ✓
```

**Why 1e18 scaling?** Solidity has no decimals. Without the `* 1e18` scaling, `rewardRate * elapsed / totalSupply` would round to 0 whenever `totalSupply > rewardRate * elapsed`. The 1e18 factor preserves precision, and is divided out when computing per-user rewards.

**The pattern generalized:** This same "accumulator + difference" pattern appears as:
- `feeGrowthGlobal` in Uniswap V3 (fee distribution to LPs)
- `liquidityIndex` in Aave V3 (interest distribution to depositors)
- `rewardPerToken` in every staking/farming contract

Once you recognize it, you'll see it everywhere in DeFi.

**Deflationary tokens (burn on transfer):**
Some tokens burn a percentage on every transfer (covered above as fee-on-transfer). The key additional insight: deflationary mechanics means total supply decreases over time, affecting any accounting that references `totalSupply()`.

**Elastic supply (rebase) tokens:**
[AMPL](https://www.ampleforth.org/technology/) adjusts ALL holder balances daily to target $1. [OHM](https://docs.olympusdao.finance/) rebases to distribute staking rewards. This breaks any protocol that stores `balanceOf` at a point in time:

```solidity
// ❌ BROKEN with rebasing tokens:
mapping(address => uint256) public deposits; // Stored balance at deposit time

function deposit(uint256 amount) external {
    token.safeTransferFrom(msg.sender, address(this), amount);
    deposits[msg.sender] += amount; // This amount may not match future balanceOf
}

// ✅ Works: Track shares, not amounts (like wstETH or ERC-4626)
// User deposits 100 stETH → protocol records their share of the pool
// On withdrawal, shares convert to current stETH amount (which rebased)
```

> **Deep dive:** [ERC-4626 Tokenized Vault Standard](https://eips.ethereum.org/EIPS/eip-4626) solves this elegantly with the shares/assets pattern. Covered in depth in Module 7 (Vaults & Yield).

#### 🔗 DeFi Pattern Connection

**The reward-per-token pattern is everywhere:**

1. **Yield farming (Module 7):** Synthetix StakingRewards is the template — Sushi MasterChef, Convex BaseRewardPool, Yearn gauges all use the same formula
2. **Lending (Module 4):** Aave V3's interest accrual uses a similar accumulator pattern (`liquidityIndex`) to distribute interest without iterating over users
3. **AMMs (Module 2):** Uniswap V3's fee accounting (`feeGrowthGlobal`) is the same concept — accumulate per-unit value, compute individual shares by difference

**The pattern:** Whenever you need to distribute something (rewards, fees, interest) to N users proportionally without iterating, use an accumulator that tracks "value per unit" and let each user compute their share lazily.

---

#### 11. ⚡ Flash-Mintable Tokens

**Why this matters:** Some tokens can be created from nothing and destroyed in the same transaction. [DAI has `flashMint()`](https://docs.makerdao.com/smart-contract-modules/flash-mint-module) allowing anyone to mint arbitrary amounts of DAI, use it, and burn it — all atomically.

**The security implications:**

```
1. Attacker flash-mints 1 billion DAI (costs only gas + 0.05% fee)
2. Uses the DAI to manipulate a protocol that checks DAI balances or DAI-based prices
3. Returns the DAI + fee in the same transaction
4. Profit from the manipulation exceeds the fee
```

**What this means for protocol design:**

```solidity
// ❌ DANGEROUS: Using token balance as a voting weight or price signal
uint256 votes = dai.balanceOf(msg.sender); // Can be flash-minted to billions

// ✅ SAFE: Use time-weighted or snapshot-based checks
uint256 votes = votingToken.getPastVotes(msg.sender, block.number - 1);
// Can't flash-mint in a previous block
```

> **Common pitfall:** Using `balanceOf` in the current block for governance votes or price calculations. Flash mints (and flash loans, covered in Module 5) can inflate balances to arbitrary amounts within a single transaction. Always use historical snapshots or time-weighted values.

> **Used by:** [MakerDAO flash mint module](https://docs.makerdao.com/smart-contract-modules/flash-mint-module) — 0.05% fee, no maximum. [Aave V3 flash loans](https://aave.com/docs/aave-v3/guides/flash-loans) enable similar behavior for any token they hold. [OpenZeppelin ERC20FlashMint](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20FlashMint.sol) provides a standard implementation.

> **Deep dive:** Flash loans and flash mints are covered extensively in Module 5. Here, the key takeaway is: **never trust current-block balances for security-critical decisions**.

💻 **Quick Try:**

See why `balanceOf` is dangerous for governance in Foundry:

```solidity
import {ERC20Votes, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract GovToken is ERC20Votes {
    constructor() ERC20("Gov", "GOV") EIP712("Gov", "1") {
        _mint(msg.sender, 1000e18);
    }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// In your test:
function test_SnapshotVsBalance() public {
    GovToken gov = new GovToken();
    gov.delegate(address(this));  // self-delegate to activate checkpoints

    // Snapshot: 1000 tokens at previous block
    vm.roll(block.number + 1);
    assertEq(gov.getPastVotes(address(this), block.number - 1), 1000e18);

    // Now simulate a "flash mint" — balance spikes but snapshot is safe
    gov.mint(address(this), 1_000_000e18);  // sudden 1M tokens
    assertEq(gov.balanceOf(address(this)), 1_001_000e18);  // balanceOf: inflated!
    assertEq(gov.getPastVotes(address(this), block.number - 1), 1000e18); // snapshot: unchanged ✓
}
```

The snapshot still reads 1,000 tokens even though `balanceOf` shows 1,001,000. This is why `getPastVotes` is safe and `balanceOf` is not.

---

<a id="read-weth"></a>
#### 📖 Read: WETH

**Source:** The canonical [WETH9 contract](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) (deployed December 2017)

**Why this matters:** WETH exists because ETH doesn't conform to ERC-20. Protocols that want to treat ETH uniformly with other tokens use WETH. The contract is trivially simple:

- `deposit()` (payable): accepts ETH, mints equivalent WETH (1:1)
- `withdraw(uint256 wad)`: burns WETH, sends ETH back

Understand that many protocols ([Uniswap](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L18), [Aave](https://github.com/aave/aave-v3-periphery/blob/master/contracts/misc/WrappedTokenGatewayV3.sol), etc.) have dual paths — one for ETH (wraps to WETH internally) and one for ERC-20 tokens.

**When you build your own protocols, you'll face the same design choice:**
- Support raw ETH: better UX (users don't need to wrap), but requires separate code paths and careful handling of `msg.value`
- Require WETH: simpler code (single ERC-20 path), but users must wrap ETH themselves

> **Used by:** [Uniswap V2 Router](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol) has `swapExactETHForTokens` (wraps ETH → WETH internally), [Aave WETHGateway](https://github.com/aave/aave-v3-periphery/blob/master/contracts/misc/WrappedTokenGatewayV3.sol) wraps/unwraps for users. [Uniswap V4 added native ETH support](https://github.com/Uniswap/v4-core) — its singleton architecture manages ETH balances directly via flash accounting, eliminating the WETH wrapping overhead.

> **Awareness:** [ERC-6909](https://eips.ethereum.org/EIPS/eip-6909) is a minimal multi-token standard (think lightweight [ERC-1155](https://eips.ethereum.org/EIPS/eip-1155)). Uniswap V4 uses it for LP position tokens instead of V3's [ERC-721](https://eips.ethereum.org/EIPS/eip-721) NFTs — simpler, cheaper, and fungible per-pool. You'll encounter it when reading V4 code.

> **Deep dive:** [WETH9 source code](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) — only 60 lines. Read it.

💻 **Quick Try:**

Test the WETH wrap/unwrap cycle in Foundry using a mainnet fork:

```solidity
// In a Foundry test (requires fork mode: forge test --fork-url $ETH_RPC_URL)
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address) external view returns (uint256);
}

function test_WETHWrapUnwrap() public {
    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Wrap: send 1 ETH, get 1 WETH
    uint256 ethBefore = address(this).balance;
    weth.deposit{value: 1 ether}();
    assertEq(weth.balanceOf(address(this)), 1 ether);

    // Unwrap: burn 1 WETH, get 1 ETH back
    weth.withdraw(1 ether);
    assertEq(weth.balanceOf(address(this)), 0);
    assertEq(address(this).balance, ethBefore); // ETH fully restored

    // Key insight: WETH is a 1:1 wrapper — no fees, no slippage, just ERC-20 compatibility
}
```

Feel the simplicity — WETH is just a deposit/withdraw box. Now imagine every protocol needing separate code paths for ETH vs ERC-20, and you understand why WETH exists.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How does Uniswap V4 handle native ETH differently from V2/V3?"**
   - Good answer: "V4 supports native ETH directly without requiring WETH wrapping"
   - Great answer: "V2/V3 used WETH as an intermediary — the Router wrapped ETH before interacting with pair/pool contracts. V4's singleton architecture manages ETH balances natively via flash accounting: ETH is tracked as internal deltas alongside ERC-20 tokens, settled at the end of the transaction. This eliminates the gas cost of wrapping/unwrapping and simplifies multi-hop swaps involving ETH. The `address(0)` or `CurrencyLibrary.NATIVE` represents ETH in V4's currency system."

**Interview Red Flags:**
- 🚩 Thinking V4 dropped native ETH support (it's the opposite — V4 added it)
- 🚩 Not knowing what WETH is or why it exists

**Pro tip:** If applying to a DEX role, knowing the V4 `CurrencyLibrary` and how `address(0)` represents native ETH shows you've read the actual codebase.

---

<a id="token-listing-patterns"></a>
### 💡 Concept: Token Listing Patterns — Permissionless vs Curated

**Why this matters:** One of the first architectural decisions in any DeFi protocol is: which tokens does it support? This decision shapes your entire security model, risk framework, and user experience.

**The three approaches:**

**1. Permissionless (anyone can add any token)**

[Uniswap V2](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol#L23) and [V3](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Factory.sol) allow anyone to create a pool for any ERC-20 pair. [Uniswap V4](https://github.com/Uniswap/v4-core) continues this.

- **Pros:** Maximum composability, no governance bottleneck, any token can be traded immediately
- **Cons:** Users interact with potentially malicious/weird tokens at their own risk. The protocol must handle ALL edge cases (fee-on-transfer, rebase, etc.) or explicitly document unsupported behaviors
- **Security model:** User responsibility. The protocol warns but doesn't prevent

**2. Curated allowlist (governance-approved tokens only)**

[Aave V3](https://aave.com/docs/aave-v3/markets/data) requires governance approval for each new asset, with risk parameters set per token (LTV, liquidation threshold, etc.). [Compound V3](https://github.com/compound-finance/comet) has hardcoded asset lists per market.

- **Pros:** Each token is risk-assessed before addition. Protocol can optimize for known token behaviors. Smaller attack surface
- **Cons:** Slow to add new assets (governance overhead). May miss opportunities. Centralization of listing decisions
- **Security model:** Protocol responsibility. Governance evaluates risk

**3. Hybrid (permissionless with risk tiers)**

[Euler V2](https://docs.euler.finance/) allows permissionless vault creation where vault creators set their own risk parameters. [Morpho Blue](https://docs.morpho.org/) allows anyone to create lending markets with any collateral/borrow pair, but each market has explicit risk parameters.

- **Pros:** Permissionless innovation with isolated risk. Bad tokens can't affect good markets
- **Cons:** More complex architecture. Users must evaluate individual market risk
- **Security model:** Market-level isolation. Risk is per-market, not protocol-wide

**Comparison table:**

| Protocol | Approach | Who decides | Token support | Risk isolation |
|----------|----------|-------------|---------------|----------------|
| Uniswap V2/V3/V4 | Permissionless | Anyone | Any ERC-20 | Per-pool |
| Aave V3 | Curated | Governance | ~30 assets | Shared (E-Mode/Isolation helps) |
| Compound V3 | Curated | Governance | ~5-10 per market | Per-market |
| Euler V2 | Hybrid | Vault creators | Any | Per-vault |
| Morpho Blue | Hybrid | Market creators | Any pair | Per-market |
| MakerDAO | Curated | Governance | ~20 collaterals | Per-vault type |

> **Common pitfall:** Building a permissionless protocol without handling weird token edge cases. If anyone can add tokens, someone WILL add a fee-on-transfer token, a rebasing token, or a malicious token. Either handle all cases or explicitly document/revert on unsupported behaviors.

> **Deep dive:** [Aave's asset listing governance process](https://governance.aave.com/), [Gauntlet risk assessment framework](https://www.gauntlet.xyz/) (used by Aave and Compound for parameter recommendations), [Euler V2 architecture](https://docs.euler.finance/).

---

<a id="token-evaluation-checklist"></a>
#### 📋 Token Evaluation Checklist

**Use this when integrating a new token into your protocol.** This synthesizes everything in this module into a practical assessment tool.

| # | Check | What to look for | Impact if missed |
|---|-------|-------------------|-----------------|
| 1 | **Return values** | Does `transfer`/`transferFrom` return `bool`? (USDT doesn't) | Silent failures → fund loss |
| 2 | **Fee-on-transfer** | Does the received amount differ from the sent amount? | Accounting drift → insolvency |
| 3 | **Rebasing** | Does `balanceOf` change without transfers? (stETH, AMPL, OHM) | Stale balance accounting → incorrect withdrawals |
| 4 | **Decimals** | How many? (6, 8, 18, or something else?) | Overflow/underflow, wrong exchange rates |
| 5 | **Upgradeable** | Is it behind a proxy? (USDC, USDT) | Behavior can change post-deployment |
| 6 | **Pausable** | Can the issuer pause all transfers? (USDC, USDT) | Stuck funds, broken liquidations |
| 7 | **Blacklistable** | Can specific addresses be blocked? (USDC, USDT) | Protocol address frozen → all funds stuck |
| 8 | **ERC-777 hooks** | Does it have transfer hooks? (imBTC) | Reentrancy via `tokensReceived` callback |
| 9 | **Zero transfer** | Does it revert on zero-amount transfer? (LEND) | Batch operations fail |
| 10 | **Multiple addresses** | Does it have proxy aliases or multiple entry points? | Address-based dedup fails |
| 11 | **Flash-mintable** | Can supply be inflated atomically? (DAI) | Balance-based governance/pricing exploitable |
| 12 | **Max supply / inflation** | What's the emission schedule? | Dilution affects collateral value over time |
| 13 | **Approve race condition** | Does it require approve-to-zero first? (USDT) | `approve()` reverts → UX breaks |

**Quick assessment flow:**

```
Is the token a well-known standard token? (DAI, WETH, etc.)
├── YES → Checks 4-7 still apply (USDC is "well-known" but upgradeable + pausable + blacklistable)
└── NO → Run ALL 13 checks

Is your protocol permissionless or curated?
├── Permissionless → Must handle checks 1-3, 8-9 defensively in code
└── Curated → Can skip some defensive patterns for pre-vetted tokens, but still use SafeERC20
```

> **Pro tip:** When listing a new token in a curated protocol, write a Foundry fork test that interacts with the real deployed token on mainnet. This catches behaviors that documentation misses.

### 📖 How to Study Token Integration in Production

1. **Start with the token interface** — Look for `using SafeERC20 for IERC20` or custom token interfaces
2. **Follow the money** — Trace every `safeTransfer`, `safeTransferFrom` call. Map who sends tokens where
3. **Check decimal handling** — Search for `decimals()`, `10**`, and scaling factors
4. **Look for guards** — Reentrancy protection, zero-amount checks, allowance management
5. **Read the tests** — Production test suites often include weird-token mocks that reveal what the team considered

**Recommended study order:**

| Order | Protocol | What to study | Key file |
|-------|----------|--------------|----------|
| 1 | [Solmate ERC20](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol) | Minimal ERC20 — understand the base | `ERC20.sol` (180 lines) |
| 2 | [Uniswap V2 Pair](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) | Balance-before-after in `swap()` and `mint()` | Lines 159-187 |
| 3 | [Aave V3 SupplyLogic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/SupplyLogic.sol) | SafeERC20, decimal normalization, aToken minting | Full file |
| 4 | [Compound V3 Comet](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) | Curated approach, scaling, immutable config | `supply()` and `withdraw()` |
| 5 | [OpenZeppelin SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) | How low-level calls handle missing return values | Full file (~60 lines) |

---

<a id="build-token-test-suite"></a>
## 🎯 Build Exercise: Token Interaction Patterns

**Workspace:** [`workspace/src/part2/module1/`](../workspace/src/part2/module1/) — starter files: [`DefensiveVault.sol`](../workspace/src/part2/module1/exercise1-defensive-vault/DefensiveVault.sol), [`DecimalNormalizer.sol`](../workspace/src/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.sol), tests: [`DefensiveVault.t.sol`](../workspace/test/part2/module1/exercise1-defensive-vault/DefensiveVault.t.sol), [`DecimalNormalizer.t.sol`](../workspace/test/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.t.sol)

**Exercise 1: Defensive Vault** ([`DefensiveVault.sol`](../workspace/src/part2/module1/exercise1-defensive-vault/DefensiveVault.sol)) — Build a vault that correctly handles deposits and withdrawals for ANY ERC-20 token, including fee-on-transfer tokens and tokens that don't return a bool. Requirements:
- Import and apply [SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) for all token interactions
- Implement `deposit()` using the balance-before-after pattern (credit actual received, not requested)
- Implement `withdraw()` with proper balance checks
- Track per-user balances and total tracked amount
- Emit events for deposits and withdrawals

Tests ([`DefensiveVault.t.sol`](../workspace/test/part2/module1/exercise1-defensive-vault/DefensiveVault.t.sol)) cover standard tokens, fee-on-transfer tokens (1% fee), USDT-style no-return-value tokens, edge cases, and fuzz invariants.

**Exercise 2: Decimal Normalizer** ([`DecimalNormalizer.sol`](../workspace/src/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.sol)) — Build a multi-token accounting contract that accepts deposits from tokens with different decimals (USDC=6, WBTC=8, DAI=18) and maintains a single normalized internal ledger in 18 decimals. Requirements:
- Register tokens and read their decimals dynamically
- Implement `_normalize()` and `_denormalize()` conversion helpers
- Implement `deposit()` and `withdraw()` with decimal scaling
- Track per-user, per-token normalized balances and a global total
- Understand precision loss when denormalizing (division truncation)

Tests ([`DecimalNormalizer.t.sol`](../workspace/test/part2/module1/exercise2-decimal-normalizer/DecimalNormalizer.t.sol)) cover registration, normalization math for 6/8/18 decimal tokens, cross-token totals, roundtrip precision, and fuzz invariants.

**Foundry tip:** The workspace already includes mock tokens in [`workspace/src/part2/module1/mocks/`](../workspace/src/part2/module1/mocks/) — `FeeOnTransferToken.sol` (1% fee), `NoReturnToken.sol` (USDT-style), and `MockERC20.sol` (configurable decimals). Here is the fee-on-transfer pattern for reference:

```solidity
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1%

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_BPS) / 10_000;
        _spendAllowance(from, msg.sender, amount);
        _burn(from, fee);             // burn fee from sender
        _transfer(from, to, amount - fee); // transfer remainder
        return true;
    }
}
```

> **Common pitfall:** Testing only with standard ERC-20 mocks. Your vault will pass all tests but fail in production when encountering USDT or fee-on-transfer tokens. Always test with weird token mocks.

## 📋 Key Takeaways: Advanced Token Behaviors & Protocol Design

After this section, you should be able to:

- Trace an ERC-777 reentrancy attack through `tokensReceived` and explain why reentrancy guards must protect ALL token transfers, not just ETH sends
- Walk through the reward-per-token accumulator pattern (Synthetix) step by step and identify where it reappears in Uniswap V3 (`feeGrowthGlobal`) and Aave V3 (`liquidityIndex`)
- Explain why `balanceOf` is unsafe for governance or pricing within the same block and what snapshot-based alternative (`getPastVotes`) prevents flash-mint manipulation
- Evaluate a new token for DeFi integration using the 13-point checklist and distinguish which risks need code-level defenses vs operational monitoring
- Compare permissionless (Uniswap), curated (Aave), and hybrid (Euler V2) token listing strategies and explain the security trade-offs of each

---

## 💼 Job Market Context

**The synthesis question — this is what ties the whole module together:**

1. **"How would you safely integrate an arbitrary ERC-20 token into a lending protocol?"**
   - Good answer: "Use SafeERC20, balance-before-after for deposits, normalize decimals, check for reentrancy"
   - Great answer: "First decide if we're permissionless or curated. If permissionless: SafeERC20, balance-before-after, reentrancy guard, decimal normalization via `token.decimals()`, guard against zero transfers. If curated: still use SafeERC20, but we can skip balance-before-after for tokens we've verified. Either way, test with fee-on-transfer, rebasing, and USDT mocks. I'd also check if the token is upgradeable or pausable — that affects our risk model. I'd run through the 13-point token evaluation checklist before listing."

2. **"Walk me through your token evaluation process for a new collateral asset."**
   - Good answer: "Check decimals, see if it's upgradeable, look for weird behaviors"
   - Great answer: "I have a 13-point checklist: return values, fee-on-transfer, rebasing, decimals, upgradeability, pausability, blacklistability, ERC-777 hooks, zero-transfer behavior, multiple entry points, flash-mintability, supply inflation, and approve race conditions. For a curated protocol, I'd write a Foundry fork test against the real deployed token to verify assumptions. For permissionless, I'd build defensive code that handles all 13 cases."

**Interview Red Flags — signals of outdated or shallow knowledge:**
- 🚩 Not knowing what SafeERC20 is or why it's needed
- 🚩 Never heard of fee-on-transfer tokens or the balance-before-after pattern
- 🚩 Treating all tokens as 18 decimals
- 🚩 Unaware that USDC/USDT are upgradeable, pausable, and blacklistable
- 🚩 Not knowing about ERC-777 reentrancy vectors
- 🚩 No systematic approach to token evaluation (ad-hoc vs checklist)

**Pro tip:** When interviewing, mention the [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20) by name and the 13-point evaluation checklist approach — it shows you think systematically about token integration, not just "use SafeERC20 and hope for the best."

---

## 🔗 Cross-Module Concept Links

### Building on Part 1

| Module | Concept | How It Connects |
|--------|---------|-----------------|
| [← Module 1: Modern Solidity](../part1/1-solidity-modern.md) | Custom errors | Token transfer failure revert data — `InsufficientBalance()` over string messages |
| [← Module 1: Modern Solidity](../part1/1-solidity-modern.md) | `unchecked` blocks | Gas-optimized balance math where underflow is impossible (post-require) |
| [← Module 1: Modern Solidity](../part1/1-solidity-modern.md) | UDVTs | Prevent mixing up token amounts with share amounts — `type Shares is uint256` |
| [← Module 2: EVM Changes](../part1/2-evm-changes.md) | Transient storage | Reentrancy guards for ERC-777 hook protection — `TSTORE`/`TLOAD` pattern |
| [← Module 3: Token Approvals](../part1/3-token-approvals.md) | Permit (EIP-2612) | Gasless approve built on the approval mechanics covered in this module |
| [← Module 3: Token Approvals](../part1/3-token-approvals.md) | Permit2 | Universal approval manager — extends the approve/transferFrom pattern |
| [← Module 5: Foundry](../part1/5-foundry.md) | Fork testing | Test against real mainnet tokens (USDC, USDT, WETH) — catch behaviors mocks miss |
| [← Module 5: Foundry](../part1/5-foundry.md) | Fuzz testing | Randomized token amounts and decimal values to catch edge cases |
| [← Module 6: Proxy Patterns](../part1/6-proxy-patterns.md) | Upgradeable proxies | USDC/USDT are proxy tokens — same storage layout and upgrade mechanics from Module 6 |

### Forward to Part 2

| Module | Token Pattern | Application |
|--------|--------------|-------------|
| [→ M2: AMMs](2-amms.md) | Balance-before-after | V2's `swap()` uses balance checks, not transfer amounts — handles fee-on-transfer |
| [→ M2: AMMs](2-amms.md) | WETH in routers | V2/V3 Router wraps ETH → WETH; V4 handles native ETH via flash accounting |
| [→ M3: Oracles](3-oracles.md) | Decimal normalization | Combining token amounts with price feeds requires dynamic `decimals()` handling |
| [→ M4: Lending](4-lending.md) | SafeERC20 everywhere | Aave V3 supply/borrow/repay all use SafeERC20, decimal normalization via reserveDecimals |
| [→ M4: Lending](4-lending.md) | Token listing as risk | Collateral token properties (decimals, pausability) directly affect lending risk |
| [→ M5: Flash Loans](5-flash-loans.md) | Flash-mintable tokens | DAI `flashMint()` and flash loan callbacks as reentrancy vectors |
| [→ M6: Stablecoins & CDPs](6-stablecoins-cdps.md) | Pausable/blacklistable | USDC/USDT freeze risk directly impacts stablecoin protocol design |
| [→ M7: Vaults & Yield](7-vaults-yield.md) | Reward-per-token | Synthetix StakingRewards pattern reappears in vault yield distribution and gauge systems |
| [→ M7: Vaults & Yield](7-vaults-yield.md) | Rebasing tokens | ERC-4626 shares/assets pattern solves rebasing token accounting |
| [→ M8: DeFi Security](8-defi-security.md) | Token attack vectors | ERC-777 reentrancy, flash mint oracle manipulation, fee-on-transfer accounting bugs |
| [→ M9: Integration](9-integration-capstone.md) | Full token integration | Capstone requires handling all token edge cases in a complete protocol |

---

## 📖 Production Study Order

Study these codebases in order — each builds on the previous one's patterns:

| # | Repository | Why Study This | Key Files |
|---|-----------|----------------|-----------|
| 1 | [OpenZeppelin ERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol) | The canonical implementation — understand the `_update()` hook, virtual functions, and how every other token inherits or deviates from this | `ERC20.sol` (`_update`, `_approve`, `_spendAllowance`), `extensions/` |
| 2 | [Solmate ERC20](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol) | Gas-optimized alternative — compare with OZ to understand which safety checks are worth the gas and which are ceremony. No virtual `_update()` hook | `src/tokens/ERC20.sol` (compare `transfer`, `approve` with OZ) |
| 3 | [Weird ERC-20 Tokens](https://github.com/d-xo/weird-erc20) | Catalog of every non-standard ERC-20 behavior — fee-on-transfer, missing return values, rebasing, pausable, blocklist. Every integrating protocol must handle these | `README.md` (the catalog itself), individual token implementations |
| 4 | [USDT TetherToken](https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code) | The most integrated non-standard token — missing return values on `transfer`/`approve`, non-zero-to-non-zero approval restriction. Why SafeERC20 exists | `TetherToken.sol` (compare `transfer` signature with ERC-20 spec) |
| 5 | [WETH9](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) | Canonical wrapped ETH — deposit/withdraw pattern, `fallback` for implicit wrapping. Every DeFi router integrates this | `WETH9.sol` (`deposit`, `withdraw`, `fallback`) |
| 6 | [Uniswap V2 Pair](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) | Balance-before-after pattern in production — `swap()` reads actual balances instead of trusting transfer amounts; `skim()` and `sync()` for balance recovery | `UniswapV2Pair.sol` (`swap`, `_update`, `skim`, `sync`) |
| 7 | [Aave V3 AToken](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol) | Rebasing token via scaled balances — `balanceOf()` returns `scaledBalance * liquidityIndex`, not stored balance. The index-based accounting pattern used across all lending protocols | `AToken.sol`, `ScaledBalanceTokenBase.sol` |

**Reading strategy:** Start with OZ ERC20 (1) — read `_update()` and understand the hook pattern all extensions build on. Compare with Solmate (2) to see what a minimal implementation looks like without hooks. Study the weird-erc20 catalog (3) to map the full landscape of non-standard behaviors. Then read USDT (4) to see the real-world token that forced the creation of SafeERC20. WETH9 (5) is short and shows the ETH wrapping pattern every router uses. Uniswap V2 Pair (6) shows how production protocols defend against fee-on-transfer tokens via balance-before-after. Aave's AToken (7) shows the rebasing/scaled-balance pattern you'll encounter in lending and yield protocols.

---

## 📚 Resources

**Reference implementations:**
- [OpenZeppelin ERC20 (v5.x)](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20)
- [OpenZeppelin SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol)
- [Weird ERC-20 catalog](https://github.com/d-xo/weird-erc20)
- [WETH9 source](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) (Etherscan verified)
- [Solmate ERC20](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol) — gas-optimized reference

**Specifications:**
- [EIP-20 (ERC-20)](https://eips.ethereum.org/EIPS/eip-20)
- [EIP-777](https://eips.ethereum.org/EIPS/eip-777) — hooks-enabled token standard
- [EIP-2612 (Permit)](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-4626 (Tokenized Vaults)](https://eips.ethereum.org/EIPS/eip-4626) — shares/assets standard (Module 7)

**Production examples:**
- [Uniswap V2 Pair.sol](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) — balance-before-after pattern in `swap()`
- [Aave V3 Pool.sol](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol) — SafeERC20 usage, wstETH wrapping, decimal normalization
- [Compound V3 Comet.sol](https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol) — curated allowlist approach, scaling factors
- [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol) — reward-per-token pattern
- [USDC proxy implementation](https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#code) — upgradeable, pausable, blacklistable

**Security reading:**
- [MixBytes — DeFi patterns: ERC20 token transfers](https://mixbytes.io/blog/defi-patterns-erc20-token-transfers-howto)
- [Integrating arbitrary ERC-20 tokens (cheat sheet)](https://andrej.hashnode.dev/integrating-arbitrary-erc-20-tokens)
- [Hundred Finance postmortem](https://rekt.news/hundred-rekt2/) — ERC-777 reentrancy ($7M)
- [SushiSwap MISO incident](https://www.coindesk.com/tech/2021/09/17/3m-in-ether-stolen-from-sushiswap-token-launchpad/) — malicious token ($3M)
- [imBTC/Uniswap V1 exploit](https://zengo.com/imbtc-defi-hack-explained/) — ERC-777 hook reentrancy (~$300K)
- [USDC depeg analysis (SVB crisis)](https://rekt.news/usdc-depeg/) — centralized stablecoin risk
- [Tornado Cash OFAC sanctions](https://home.treasury.gov/news/press-releases/jy0916) — address blacklisting in practice

**Hybrid/permissionless architectures:**
- [Euler V2 documentation](https://docs.euler.finance/) — permissionless vault creation with isolated risk
- [Morpho Blue documentation](https://docs.morpho.org/) — permissionless lending markets with per-market risk parameters

**Risk frameworks:**
- [Aave risk documentation](https://aave.com/docs/resources/risks)
- [Gauntlet risk platform](https://www.gauntlet.xyz/) — quantitative risk assessment
- [MakerDAO collateral onboarding (MIP6)](https://github.com/makerdao/mips/blob/master/MIP6/mip6.md)

---

**Navigation:** [← Part 1 Module 7: Deployment](../part1/7-deployment.md) | [Module 2: AMMs →](2-amms.md)

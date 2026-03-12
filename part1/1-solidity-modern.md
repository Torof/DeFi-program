# Part 1 — Module 1: Solidity 0.8.x — What Changed

> **Difficulty:** Beginner
>
> **Estimated reading time:** ~45 minutes | **Exercises:** ~2 hours

## 📚 Table of Contents

**Language-Level Changes That Matter for DeFi**
- [Checked Arithmetic (0.8.0)](#checked-arithmetic)
- [Custom Errors (0.8.4+)](#custom-errors)
- [User-Defined Value Types (0.8.8+)](#user-defined-value-types)
- [abi.encodeCall (0.8.11+)](#abi-encodecall)
- [Other Notable Changes](#other-notable-changes)
- [Build Exercise: ShareMath](#day1-exercise)

**Solidity 0.8.24+ — The Bleeding Edge**
- [Transient Storage Support (0.8.24+)](#transient-storage)
- [Pectra/Prague EVM Target (0.8.30+)](#pectra-prague-evm)
- [What's Coming — Solidity 0.9.0 Deprecations](#solidity-09-deprecations)
- [Build Exercise: TransientGuard](#day2-exercise)

---

## 💡 Language-Level Changes That Matter for DeFi

<a id="checked-arithmetic"></a>
### 💡 Concept: Checked Arithmetic (0.8.0)

**Why this matters:** You know the history — pre-0.8 overflow was silent, SafeMath was everywhere. Since 0.8.0, arithmetic reverts on overflow by default. The real question for DeFi work is: **when do you turn it off, and how do you prove it's safe?**

> Introduced in [Solidity 0.8.0](https://www.soliditylang.org/blog/2020/12/16/solidity-v0.8.0-release-announcement/) (December 2020)

> **Legacy context:** You'll still encounter SafeMath in Uniswap V2, Compound V2, and original MakerDAO. Recognize it, never use it in new code.

**The `unchecked {}` escape hatch:**

When you can mathematically prove an operation won't overflow, use `unchecked` to skip the safety check and save gas:

```solidity
// ✅ CORRECT: Loop counter that can't realistically overflow
for (uint256 i = 0; i < length;) {
    // ... loop body
    unchecked { ++i; }  // Saves ~20 gas per iteration
}

// ✅ CORRECT: AMM math where inputs are already validated
// Safety proof: reserveIn and amountInWithFee are bounded by token supply
// (max ~10^30 for 18-decimal tokens), so their product can't overflow uint256 (~10^77)
unchecked {
    uint256 denominator = reserveIn * 1000 + amountInWithFee;
}
```

**Safe vs dangerous — the key distinction:**

```solidity
// ✅ SAFE: Uniswap V2 swap — inputs are bounded by protocol invariants
// reserveIn comes from the pool's own storage (max ~10^30 for 18-decimal tokens)
// amountIn is validated against the reserve before reaching this point
// The product CANNOT overflow uint256 (~10^77)
unchecked {
    uint256 denominator = reserveIn * 1000 + amountInWithFee;
}

// ❌ DANGEROUS: User-facing deposit — inputs are arbitrary
// depositAmount comes directly from the user — could be type(uint256).max
// totalShares comes from storage — could also be very large
// No mathematical guarantee that the product fits in 256 bits
function deposit(uint256 depositAmount) external {
    unchecked {
        uint256 shares = depositAmount * totalShares / totalAssets;  // Can overflow!
    }
}
```

The difference: in the swap, the protocol controls and bounds both inputs. In the deposit, the user controls `depositAmount` — you cannot prove safety without validation. This is why vault math uses `mulDiv` (covered below) instead of raw multiplication.

**When to use `unchecked`:**

Only when you can mathematically prove the operation won't overflow. In DeFi, this usually means:
- Loop counters with bounded iteration counts
- Formulas where the mathematical structure guarantees safety
- Values already validated through require checks

> ⚡ **Common pitfall:** Don't use `unchecked` just because "it probably won't overflow." The gas savings (5-20 gas per operation) aren't worth the risk if your proof is wrong.

💻 **Quick Try:**

Before moving on, open [Remix](https://remix.ethereum.org/) and test this:
```solidity
// See the difference yourself
function testChecked() external pure returns (uint256) {
    return type(uint256).max + 1;  // Reverts!
}

function testUnchecked() external pure returns (uint256) {
    unchecked {
        return type(uint256).max + 1;  // Wraps to 0
    }
}
```
Deploy, call both. One reverts, one returns 0. Feel the difference.

🏗️ **Real usage:**

[Uniswap V4's `FullMath.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/libraries/FullMath.sol) (originally from V3) is a masterclass in `unchecked` usage. Every operation is proven safe through the structure of 512-bit intermediate calculations. Study the `mulDiv` function to see how production DeFi handles complex fixed-point math safely.

#### 🔍 Deep Dive: Understanding `mulDiv` — Safe Precision Math

**The problem:**
In DeFi, the formula `(a * b) / c` appears everywhere — vault shares, AMM pricing, interest rates. But in Solidity, the intermediate product `a * b` can overflow `uint256` before the division brings it back down. This is called **phantom overflow**: the final result fits in 256 bits, but the intermediate step doesn't.

**Concrete example with real numbers:**

```solidity
// A vault with massive TVL
uint256 depositAmount = 500_000e18;    // 500k tokens (18 decimals)
uint256 totalShares   = 1_000_000e18;  // 1M shares
uint256 totalAssets   = 2_000_000e18;  // 2M assets

// Expected: (500k * 1M) / 2M = 250k shares ✓ (fits in uint256)
// But the intermediate product:
// 500_000e18 * 1_000_000e18 = 5 * 10^41
// That's fine here. But scale up to real DeFi TVLs...

uint256 totalShares2 = 10**60;  // large share supply after years of compounding
uint256 totalAssets2 = 10**61;

// Now: 500_000e18 * 10^60 = 5 * 10^83 → EXCEEDS uint256.max (≈ 1.15 * 10^77)
// The multiplication reverts even though the final answer (5 * 10^22) is tiny
```

**The naive approach — broken at scale:**
```solidity
// ❌ Phantom overflow: a * b exceeds uint256 even though result fits
function shareBroken(uint256 assets, uint256 supply, uint256 total) pure returns (uint256) {
    return (assets * supply) / total;  // Reverts on large values
}
```

**The fix — `mulDiv`:**
```solidity
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// ✅ Safe at any scale — computes in 512-bit intermediate space
function shareFixed(uint256 assets, uint256 supply, uint256 total) pure returns (uint256) {
    return Math.mulDiv(assets, supply, total);  // Never overflows
}
```

That's it. Same formula, same result, safe at any scale. `mulDiv(a, b, c)` computes `(a * b) / c` using 512-bit intermediate math.

**How it works under the hood:**

```
Step 1: Multiply a * b into a 512-bit result (two uint256 slots)
        ┌─────────────┬─────────────┐
        │    high      │     low     │  ← a * b stored across 512 bits
        └─────────────┴─────────────┘

Step 2: Divide the full 512-bit value by c → result fits back in uint256
```

- `uint256` max ≈ 10^77 (that's 1 followed by 77 zeros — an astronomically large number)
- Two `uint256` slots hold up to 10^154 (10 to the power of 154) — more than enough for any real DeFi scenario
- The final result is exact (no precision loss from splitting the operation)

**Rounding direction matters:**

In vault math, rounding isn't neutral — it determines who eats the dust:

```solidity
// Deposits: round DOWN → depositor gets slightly fewer shares (vault keeps dust)
shares = Math.mulDiv(assets, totalSupply, totalAssets);  // default: round down

// Withdrawals: round UP → withdrawer gets slightly fewer assets (vault keeps dust)
assets = Math.mulDiv(shares, totalAssets, totalSupply, Math.Rounding.Ceil);
```

**The rule:** always round against the user, in favor of the vault. This prevents a roundtrip (deposit → withdraw) from being profitable, which would let attackers drain the vault 1 wei at a time.

**When you'll see this in DeFi:**
- [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) vault share calculations (`convertToShares`, `convertToAssets`)
- AMM price calculations with large reserves
- Fixed-point math libraries ([Ray/Wad math in Aave](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/WadRayMath.sol), [DSMath in MakerDAO](https://github.com/dapphub/ds-math/blob/master/src/math.sol))

**Available libraries:**

| Library | Style | When to use |
|---------|-------|-------------|
| [OpenZeppelin Math.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol) | Clean Solidity | Default choice — readable, audited, supports rounding modes |
| [Solady FixedPointMathLib](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol) | Assembly-optimized | Gas-critical paths (saves ~200 gas vs OZ) |
| [Uniswap FullMath](https://github.com/Uniswap/v4-core/blob/main/src/libraries/FullMath.sol) | Assembly, unchecked | Uniswap-specific — study for learning, use OZ/Solady in practice |

**The actual assembly — from Uniswap V4's FullMath.sol:**

Here's the core of the 512-bit multiplication (simplified from the full function):

```solidity
// From Uniswap V4 FullMath.sol — the 512-bit multiply step
assembly {
    // mul(a, b) — EVM multiply opcode, keeps only the LOW 256 bits.
    // If a * b > 2^256, the overflow is silently discarded (no revert in assembly).
    let prod0 := mul(a, b)

    // mulmod(a, b, not(0)) — a single EVM opcode that computes (a * b) mod (2^256 - 1)
    // without intermediate overflow. Gives a different "view" of the same product.
    let mm := mulmod(a, b, not(0))

    // The difference between mm and prod0, adjusted for borrow (the lt check),
    // gives us the HIGH 256 bits of the full product.
    // If prod1 == 0, no overflow occurred and simple a * b / c suffices.
    let prod1 := sub(sub(mm, prod0), lt(mm, prod0))
}
// Full 512-bit product = prod1 * 2^256 + prod0
// The rest of the function divides this 512-bit value by the denominator.
```

**Reading this code — every symbol explained:**
- `mul(a, b)` → the EVM MUL opcode (3 gas). In assembly, overflow wraps — no revert
- `mulmod(a, b, m)` → the EVM MULMOD opcode (8 gas). Computes `(a * b) % m` without intermediate overflow
- `not(0)` → bitwise NOT of zero, flips all bits: gives `0xFFFF...FFFF` = 2^256 - 1 (the largest uint256)
- `lt(mm, prod0)` → "less than" comparison, returns 1 if `mm < prod0`, 0 otherwise. Acts as a borrow flag for the subtraction
- `sub(a, b)` → subtraction. The nested `sub(sub(mm, prod0), lt(...))` subtracts with borrow to extract the high bits
- `:=` → Yul's assignment operator (like `=` in Solidity, but for assembly variables)

You don't need to prove WHY the extraction math works. The key insight: two views of the same product (mod 2^256 vs mod 2^256 - 1), combined, recover the full 512-bit value. Trust the library, understand the concept.

**How to read the code:**
1. Start with [OpenZeppelin's `mulDiv`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol) — clean, well-commented Solidity
2. The core insight: multiply first (in 512 bits), divide second (back to 256)
3. Then compare with [Uniswap's FullMath](https://github.com/Uniswap/v4-core/blob/main/src/libraries/FullMath.sol) to see the assembly optimizations above in full context
4. Don't get stuck on the bit manipulation — understand the *concept* first, internals later

> 🔍 **Deep dive:** [Consensys Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/) covers integer overflow/underflow security patterns. [Trail of Bits - Building Secure Contracts](https://github.com/crytic/building-secure-contracts) provides development guidelines including arithmetic safety.

#### 🔗 DeFi Pattern Connection

**Where checked arithmetic changed everything:**

1. **Vault Share Math ([ERC-4626](https://eips.ethereum.org/EIPS/eip-4626))**
   - Pre-0.8: Every vault needed SafeMath for `shares = (assets * totalSupply) / totalAssets`
   - Post-0.8: Built-in safety, cleaner code
   - You'll implement this in the ShareMath exercise below

2. **AMM Pricing** (Uniswap, Curve, Balancer)
   - Constant product formula: `x * y = k`
   - Reserve updates must never overflow
   - Modern AMMs use `unchecked` only where math proves safety (like in Uniswap's `FullMath`)

3. **Rebasing Tokens** ([Aave aTokens](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol), [Lido stETH](https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/StETH.sol))
   - Balance = `shares * rebaseIndex / 1e18`
   - Overflow protection is critical when rebaseIndex grows over years
   - Checked arithmetic prevents silent corruption

**The pattern:** If you're doing `(a * b) / c` with large numbers in DeFi, you need `mulDiv`. Every major protocol has its own version or uses a library.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Using unchecked without mathematical proof
unchecked {
    uint256 result = userInput - fee;  // If fee > userInput → wraps to ~2^256!
}

// ✅ CORRECT: Validate first, then use unchecked
require(userInput >= fee, InsufficientBalance());
unchecked {
    uint256 result = userInput - fee;  // Safe: validated above
}
```

```solidity
// ❌ WRONG: Importing SafeMath in 0.8+ code
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
using SafeMath for uint256;
uint256 total = a.add(b);  // Redundant! Already checked by default

// ✅ CORRECT: Just use native operators
uint256 total = a + b;  // Reverts on overflow automatically
```

```solidity
// ❌ WRONG: Wrapping entire function in unchecked to "save gas"
function processDeposit(uint256 amount) external {
    unchecked {
        totalDeposits += amount;             // Could overflow with enough deposits!
        userBalances[msg.sender] += amount;  // Same problem
    }
}

// ✅ CORRECT: Only unchecked for provably safe operations
function processDeposit(uint256 amount) external {
    totalDeposits += amount;  // Keep checked — can't prove safety
    userBalances[msg.sender] += amount;

    unchecked { ++depositCount; }  // Safe: would need 2^256 deposits to overflow
}
```

#### 💼 Job Market Context

**What DeFi teams expect you to know:**
1. "When would you use `unchecked` in a vault contract?"
   - Good answer: Loop counters, intermediate calculations where inputs are validated, formulas with mathematical guarantees

2. "Why can't we just divide first: `(a / c) * b` instead of `(a * b) / c`?"
   - Good answer: Lose precision. If `a < c`, you get 0, then 0 * b = 0 (wrong!)

3. "How do you handle multiplication overflow in share price calculations?"
   - Good answer: Use a `mulDiv` library ([OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol), [Solady](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol), or custom) for precise 512-bit intermediate math

**Interview Red Flags:**
- 🚩 Importing SafeMath in new Solidity 0.8+ code
- 🚩 Not knowing when to use `unchecked`
- 🚩 Can't explain why `unchecked` is safe in a specific case

**Pro tip:** In interviews, mention that you understand the tradeoff: checked arithmetic costs gas (~20-30 gas per operation) but prevents exploits. Show you think about both security AND efficiency.

---

<a id="custom-errors"></a>
### 💡 Concept: Custom Errors (0.8.4+)

**Why this matters:** Every revert in DeFi costs gas. Thousands of transactions revert daily (failed slippage checks, insufficient balances, etc.). String-based `require` messages waste ~24 gas per revert and bloat your contract bytecode. Custom errors fix both problems.

> Introduced in [Solidity 0.8.4](https://www.soliditylang.org/blog/2021/04/21/custom-errors/) (April 2021)

**The old way:**
```solidity
// ❌ OLD: Stores the string in bytecode, costs gas on every revert
require(amount > 0, "Amount must be positive");
require(balance >= amount, "Insufficient balance");
```

**The modern way:**
```solidity
// ✅ MODERN: ~24 gas cheaper per revert, no string storage
error InvalidAmount();
error InsufficientBalance(uint256 available, uint256 required);

if (amount == 0) revert InvalidAmount();
if (balance < amount) revert InsufficientBalance(balance, amount);
```

**`require` with custom errors (0.8.26+) — the recommended pattern:**

As of [Solidity 0.8.26](https://www.soliditylang.org/blog/2024/05/21/solidity-0.8.26-release-announcement/), you can use custom errors directly in `require`. This is now **the recommended way** to write input validation — it combines the readability of `require` with the gas efficiency and tooling benefits of custom errors:

```solidity
// ✅ RECOMMENDED (0.8.26+): Best of both worlds
error InvalidAmount();
error InsufficientBalance(uint256 available, uint256 required);

require(amount > 0, InvalidAmount());
require(balance >= amount, InsufficientBalance(balance, amount));
```

This replaces both the old `require("string")` pattern AND the verbose `if (...) revert` pattern for simple validations. Use `if (...) revert` when you need complex branching logic; use `require(condition, CustomError())` for straightforward precondition checks.

> ⚡ **Production note:** As of early 2026, not all codebases have adopted this yet — you'll see both `if/revert` and `require` with custom errors in modern protocols. Both are correct; `require` is more readable for simple checks.

**Beyond gas savings:**

Custom errors are better for off-chain tooling too — you can decode them by selector without needing string parsing or ABIs.

💻 **Quick Try:**

Test error selectors in Remix:
```solidity
error Unauthorized();
error InsufficientBalance(uint256 available, uint256 needed);

function testErrors() external pure {
    // Copy the selector from the revert - it's 0x82b42900
    revert Unauthorized();

    // With parameters: notice how the data includes encoded values
    revert InsufficientBalance(100, 200);
}
```
Call this, check the revert data in the console. See the 4-byte selector + ABI-encoded parameters.

🏗️ **Real usage:**

Two common patterns in production:
- **Centralized:** [Aave V3's `Errors.sol`](https://github.com/aave/aave-v3-core/blob/ea4867086d39f094303916e72e180f99d8149fd5/contracts/protocol/libraries/helpers/Errors.sol) defines 60+ revert reasons in one library using `string public constant` (the pre-custom-error pattern). The principle — single source of truth for all revert reasons — carries forward to custom errors.
- **Decentralized:** Uniswap V4 defines errors per-contract. More modular, less coupling.

Both work — choose based on your protocol size and organization.

> ⚡ **Common pitfall:** Changing an error signature (e.g., adding a parameter) changes its selector. Update your frontend/indexer decoding logic when you do this, or reverts will decode as "unknown error."

#### 🔗 DeFi Pattern Connection

**Why custom errors matter in DeFi composability:**

1. **Cross-Contract Error Propagation**
   ```solidity
   // Your aggregator calls Uniswap
   try IUniswapV3Pool(pool).swap(...) {
       // Success path
   } catch (bytes memory reason) {
       // Uniswap's custom error bubbles up in 'reason'
       // Decode the selector to handle specific errors:
       // - InsufficientLiquidity → try another pool
       // - InvalidTick → recalculate parameters
       // - Generic revert → fail the whole transaction
   }
   ```

2. **Error-Based Control Flow**
   - Flash loan callbacks check for specific errors
   - Aggregators route differently based on pool errors
   - Multisig wallets decode errors for transaction preview

3. **Frontend Error Handling**
   - Instead of showing "Transaction reverted"
   - Decode `InsufficientBalance(100, 200)` → "Need 200 tokens, you have 100"
   - Better UX = more users = more TVL

**Production example:**
Aave's frontend decodes 60+ custom errors to show specific messages like "Health factor too low" instead of cryptic hex data.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How do you handle errors when calling external protocols?"**
   - Good answer: Use try/catch, decode custom error selectors, implement fallback logic based on error type
   - Better answer: Show code example of catching Uniswap errors and routing to Curve as fallback

2. **"Why use custom errors over require strings in production?"**
   - Okay answer: Gas savings
   - Good answer: Gas savings + better off-chain tooling + smaller bytecode
   - Great answer: Plus explain the tradeoff (error handling complexity in try/catch)

3. **"How would you design error handling for a cross-protocol aggregator?"**
   - Show understanding of: error propagation, selector decoding, graceful degradation

**Interview Red Flags:**
- 🚩 Still using `require(condition, "String message")` everywhere in new code
- 🚩 Not knowing how to decode error selectors
- 🚩 Can't explain how errors bubble up in cross-contract calls

**Pro tip:** When building aggregators or routers, design your error types as a hierarchy — base errors for the protocol, specific errors per module. Teams that do this well (like 1inch, Paraswap) can provide users with actionable revert reasons instead of opaque failures.

> 🔍 **Deep dive:** [Cyfrin Updraft - Custom Errors](https://updraft.cyfrin.io/courses/solidity/fund-me/solidity-custom-errors) provides a tutorial with practical examples. [Solidity Docs - Error Handling](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions) covers how custom errors work with try/catch.

<a id="try-catch"></a>
#### 🔍 Deep Dive: try/catch for Cross-Contract Error Handling

Custom errors shine when combined with `try/catch` — the pattern you'll use constantly in DeFi aggregators, routers, and any protocol that calls external contracts.

**The problem:** External calls can fail, and you need to handle failures gracefully — not just let them propagate up and kill the entire transaction.

**Basic try/catch:**
```solidity
// Catch specific custom errors from external calls
try pool.swap(amountIn, minAmountOut) returns (uint256 amountOut) {
    // Success — use amountOut
} catch Error(string memory reason) {
    // Catches require(false, "reason") or revert("reason")
} catch Panic(uint256 code) {
    // Catches assert failures, division by zero, overflow (codes: 0x01, 0x11, 0x12, etc.)
} catch (bytes memory lowLevelData) {
    // Catches custom errors and anything else
    // Decode: bytes4 selector = bytes4(lowLevelData);
}
```

**DeFi pattern — aggregator with fallback routing:**
```solidity
function swapWithFallback(
    address primaryPool,
    address fallbackPool,
    uint256 amountIn,
    uint256 minOut
) external returns (uint256) {
    // Try primary pool first
    try IPool(primaryPool).swap(amountIn, minOut) returns (uint256 out) {
        return out;
    } catch (bytes memory reason) {
        bytes4 selector = bytes4(reason);

        if (selector == IPool.InsufficientLiquidity.selector) {
            // Known error — fall through to backup pool
        } else {
            // Unknown error — re-throw (don't swallow unexpected failures)
            assembly { revert(add(reason, 32), mload(reason)) }
        }
    }

    // Fallback to secondary pool
    return IPool(fallbackPool).swap(amountIn, minOut);
}
```

**Key rules:**
- `try` only works on **external** function calls and contract creation (`new`)
- The `returns` clause captures success values
- Always handle the catch-all `catch (bytes memory)` — custom errors land here
- Never silently swallow errors (`catch {}`) unless you genuinely intend to ignore failures

**Understanding what each catch branch receives:**

When an external call fails, what your catch block receives depends on HOW it failed:

| Failure type | `catch Error(string)` | `catch Panic(uint256)` | `catch (bytes memory)` |
|---|---|---|---|
| `revert("message")` / `require(false, "msg")` | ✅ Caught | — | ✅ Also caught (ABI-encoded) |
| `revert CustomError(params)` | — | — | ✅ Caught (4-byte selector + params) |
| `assert(false)` / overflow / div-by-zero | — | ✅ Caught (panic code) | ✅ Also caught |
| Out of gas in the sub-call | — | — | ✅ Caught, **but `reason` is empty** |
| `revert()` with no argument | — | — | ✅ Caught, **`reason` is empty** |

The critical edge case: **empty returndata**. When a call runs out of gas or uses bare `revert()`, catch receives zero-length bytes. If you try to read `bytes4(reason)` on empty data, you get a panic. Always check length first:

```solidity
catch (bytes memory reason) {
    if (reason.length >= 4) {
        bytes4 selector = bytes4(reason);

        if (selector == IPool.InsufficientLiquidity.selector) {
            // Decode the error parameters — skip the 4-byte selector
            (uint256 available, uint256 required) = abi.decode(
                // reason[4:] is a bytes slice — everything after the selector
                reason[4:],
                (uint256, uint256)
            );
            // Now you have the actual values from the error
            emit SwapFailedWithDetails(available, required);
        } else if (selector == IPool.Expired.selector) {
            // Handle differently
        } else {
            // Unknown error — re-throw it (explained below)
            assembly { revert(add(reason, 32), mload(reason)) }
        }
    } else {
        // Empty or very short reason — could be:
        //   - Out of gas in the sub-call
        //   - Bare revert() with no data
        //   - Very old contract without error messages
        // Don't try to decode — propagate or handle generically
        revert SwapFailed();
    }
}
```

**The re-throw pattern — explained line by line:**

You'll see this assembly line everywhere in production DeFi code. Here's what each piece does:

```solidity
assembly { revert(add(reason, 32), mload(reason)) }
```

- `reason` — a `bytes memory` variable. In memory, it's laid out as: [32 bytes: length][actual bytes data...]
- `mload(reason)` — reads the first 32 bytes at that memory address, which is the **length** of the bytes array
- `add(reason, 32)` — skips past the length prefix, pointing to where the **actual data** starts
- `revert(offset, size)` — the EVM REVERT opcode: stops execution and returns the specified memory range as returndata

In plain English: "take the raw error bytes exactly as received from the sub-call and re-throw them." This preserves the original error selector and parameters through each call layer, no matter how deep.

**Multi-hop error propagation:**

In DeFi, calls are often 3-4 levels deep: User → Router → Pool → Callback. Understanding how errors flow through this chain is critical:

```
User → Router.swap()
         │
         └→ try Pool.swap()
                   │
                   └→ Callback.uniswapV3SwapCallback()
                              │
                              └─ reverts: InsufficientBalance(100, 200)
                                  │
                   ┌───────────────┘
                   │ Pool doesn't catch — error propagates UP automatically
                   │ (Solidity's default: uncaught reverts bubble up)
         ┌─────────┘
         │ Router's catch receives: reason = 0xf4d678b8...0064...00c8
         │   (that's InsufficientBalance.selector + abi.encode(100, 200))
         │
         │ Router can now:
         │   1. Decode it → know exactly what went wrong
         │   2. Re-throw it → user sees the original error
         │   3. Try fallback pool → graceful degradation
         │   4. Wrap it → revert RouterSwapFailed(primaryPool, reason)
```

**Without the re-throw pattern**, each layer wraps or loses the original error. The caller sees "Swap failed" instead of "InsufficientBalance(100, 200)." For debugging, for frontends, and for MEV searchers — the original error data is invaluable.

**Where this appears in DeFi:**
- **Aggregators** (1inch, Paraswap): try Pool A, catch → decode error → try Pool B with adjusted parameters
- **Liquidation bots**: try to liquidate, catch → check if it's "healthy position" (skip) vs "insufficient gas" (retry)
- **Keepers** (Gelato, Chainlink Automation): try execution, catch → log specific error for monitoring dashboards
- **Flash loans**: decode callback errors — was it the user's callback that failed, or the repayment?
- **Routers** (Uniswap Universal Router): multi-hop swaps where each hop can fail independently

> Forward reference: You'll implement cross-contract error handling in Part 2 Module 5 (Flash Loans) where callback errors must be decoded and handled.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Mixing old and new error styles in the same contract
error InsufficientBalance(uint256 available, uint256 required);

function withdraw(uint256 amount) external {
    require(amount > 0, "Amount must be positive");  // Old style string
    if (balance < amount) revert InsufficientBalance(balance, amount);  // New style
}

// ✅ CORRECT: Consistent error style throughout
error ZeroAmount();
error InsufficientBalance(uint256 available, uint256 required);

function withdraw(uint256 amount) external {
    if (amount == 0) revert ZeroAmount();
    if (balance < amount) revert InsufficientBalance(balance, amount);
}
```

```solidity
// ❌ WRONG: Losing error context in cross-contract calls
try pool.swap(amount) {} catch {
    revert("Swap failed");  // Lost the original error — debugging nightmare
}

// ✅ CORRECT: Decode and handle specific errors
try pool.swap(amount) {} catch (bytes memory reason) {
    if (bytes4(reason) == IPool.InsufficientLiquidity.selector) {
        // Try alternate pool
    } else {
        // Re-throw original error with full context
        assembly { revert(add(reason, 32), mload(reason)) }
    }
}
```

```solidity
// ❌ WRONG: Errors without useful parameters
error TransferFailed();  // Which transfer? Which token? How much?

// ✅ CORRECT: Include debugging context in error parameters
error TransferFailed(address token, address to, uint256 amount);
```

---

<a id="user-defined-value-types"></a>
### 💡 Concept: User-Defined Value Types (0.8.8+)

**Why this matters:** Type safety catches bugs at compile time, not runtime. In DeFi, mixing up similar values (token addresses vs. pool addresses, amounts vs. shares, prices vs. quantities) causes expensive bugs. UDVTs prevent these with zero gas cost.

> Introduced in [Solidity 0.8.8](https://www.soliditylang.org/blog/2021/09/27/solidity-0.8.8-release-announcement/) (September 2021)

**The problem UDVTs solve:**

Without type safety, this compiles but is wrong:
```solidity
// ❌ WRONG: Compiles but has a logic bug
function execute(uint128 price, uint128 quantity) external {
    uint128 total = quantity + price;  // BUG: should be price * quantity
    // Compiler can't help you — both are uint128
}
```

**The solution — wrap primitives in types:**

```solidity
// ✅ CORRECT: Type safety catches the bug at compile time
type Price is uint128;
type Quantity is uint128;

function execute(Price price, Quantity qty) external {
    // Price + Quantity won't compile — type mismatch caught immediately ✨
    uint128 rawPrice = Price.unwrap(price);
    uint128 rawQty = Quantity.unwrap(qty);
    uint128 total = rawPrice * rawQty;  // Must unwrap to do math
}
```

UDVTs are erased at compile time. The EVM only sees the underlying primitive (`uint128`, `address`, etc.) — no extra opcodes, no wrapping cost. The type safety is purely a compiler check, making UDVTs a true zero-cost abstraction.

**Custom operators (0.8.19+):**

Since [Solidity 0.8.19](https://www.soliditylang.org/blog/2023/02/22/solidity-0.8.19-release-announcement/), you can define operators on UDVTs to avoid manual unwrap/wrap:

```solidity
type Fixed18 is uint256;

using { add as +, sub as - } for Fixed18 global;

function add(Fixed18 a, Fixed18 b) pure returns (Fixed18) {
    return Fixed18.wrap(Fixed18.unwrap(a) + Fixed18.unwrap(b));
}

function sub(Fixed18 a, Fixed18 b) pure returns (Fixed18) {
    return Fixed18.wrap(Fixed18.unwrap(a) - Fixed18.unwrap(b));
}

// Now you can use: result = a + b - c
```

**Why opt-in?** Not all types should support arithmetic. `type Timestamp is uint256` — what would `Timestamp + Timestamp` even mean? By requiring you to explicitly bind operators, Solidity lets you decide which operations are meaningful for each type. The friction is the feature.

Besides `+` and `-`, you can bind `*`, `/`, `%`, and all comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`) — each maps to a free function you define. The Quick Try below shows `==`:

💻 **Quick Try:**

Build a simple UDVT with an operator in Remix:
```solidity
type TokenId is uint256;

using { equals as == } for TokenId global;

function equals(TokenId a, TokenId b) pure returns (bool) {
    return TokenId.unwrap(a) == TokenId.unwrap(b);
}

function test() external pure returns (bool) {
    TokenId id1 = TokenId.wrap(42);
    TokenId id2 = TokenId.wrap(42);
    return id1 == id2;  // Uses your custom operator!
}
```

#### 🎓 Intermediate Example: Building a Practical UDVT

Before diving into Uniswap V4, let's build a realistic DeFi example - a vault with type-safe shares:

```solidity
// Type-safe vault shares
type Shares is uint256;
type Assets is uint256;

// Global operators
using { addShares as +, subShares as - } for Shares global;
using { addAssets as +, subAssets as - } for Assets global;

function addShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap(Shares.unwrap(a) + Shares.unwrap(b));
}

function subShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap(Shares.unwrap(a) - Shares.unwrap(b));
}

// Similar for Assets...

// Now your vault logic is type-safe:
function deposit(Assets assets) external returns (Shares) {
    Shares shares = convertToShares(assets);

    _totalAssets = _totalAssets + assets;  // Can't mix with shares!
    _totalShares = _totalShares + shares;  // Type enforced ✨

    return shares;
}
```

**Why this matters:** Try mixing `Shares` and `Assets` - it won't compile. This prevents the classic bug: `shares + assets` (meaningless operation).

🏗️ **Real usage — Uniswap V4:**

Understanding UDVTs is essential for reading V4 code. They use them extensively:
- [`PoolId.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/PoolId.sol) — `type PoolId is bytes32`, computed via `keccak256(abi.encode(poolKey))`
- [`Currency.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/Currency.sol) — `type Currency is address`, unifies native ETH and [ERC-20](https://eips.ethereum.org/EIPS/eip-20) handling with custom comparison operators
- [`BalanceDelta.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/BalanceDelta.sol) — `type BalanceDelta is int256`, packs two `int128` values using bit manipulation with custom `+`, `-`, `==`, `!=` operators

<a id="balance-delta"></a>
#### 🔍 Deep Dive: `BalanceDelta` — UDVTs on Packed Data

UDVTs aren't just wrappers around simple values. Uniswap V4's `BalanceDelta` wraps an `int256` that *packs two int128 values* — the balance change for each token in a pair. One storage slot instead of two saves 20,000 gas per swap.

```
┌─────────────────────────────┬─────────────────────────────┐
│      amount0 (128 bits)     │      amount1 (128 bits)     │
└─────────────────────────────┴─────────────────────────────┘
                    int256 (256 bits total)
```

The UDVT lesson here isn't the packing itself — it's that you can define **custom operators on packed data**:

```solidity
// Simplified from Uniswap V4's BalanceDelta.sol
function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    // Unpack both
    int256 aRaw = BalanceDelta.unwrap(a);
    int256 bRaw = BalanceDelta.unwrap(b);

    // Add each half separately, repack
    int128 sum0 = int128(aRaw >> 128) + int128(bRaw >> 128);
    int128 sum1 = int128(aRaw) + int128(bRaw);

    int256 packed = (int256(sum0) << 128) | int256(uint256(uint128(sum1)));
    return BalanceDelta.wrap(packed);
}

using { add as + } for BalanceDelta global;

// Callers just write: result = deltaA + deltaB
// The packing details are hidden behind the operator.
```

This is the real power of UDVTs with operators: **complex internal representation, clean external API**. The caller never thinks about bit shifts — they use `+` and the type system ensures they can't accidentally add a `BalanceDelta` to a plain `int256`.

#### 🔗 DeFi Pattern Connection

**Where UDVTs prevent real bugs:**

1. **"Wrong Token" Bug Class**
   ```solidity
   // Without UDVTs - this compiles but is wrong:
   function swap(address tokenA, address tokenB, uint256 amount) {
       // Oops - swapped tokenA and tokenB
       IERC20(tokenB).transferFrom(msg.sender, pool, amount);
       IERC20(tokenA).transfer(msg.sender, output);
   }

   // With UDVTs - won't compile:
   type TokenA is address;
   type TokenB is address;

   function swap(TokenA a, TokenB b, uint256 amount) {
       IERC20(TokenB.unwrap(a)).transfer...  // TYPE ERROR! ✨
   }
   ```

2. **AMM Pool Identification**
   - Uniswap V4 uses `type PoolId is bytes32`
   - Can't accidentally use a random bytes32 as a PoolId
   - Type system prevents: `pools[someRandomHash]` (compile error)

3. **Vault Shares vs Assets**
   - `type Shares is uint256` vs `type Assets is uint256`
   - Prevents: `shares + assets` (meaningless operation caught at compile time)
   - You'll implement this in the ShareMath exercise below

**The pattern:** Use UDVTs for domain-specific identifiers (PoolId, TokenId, OrderId) and values that shouldn't be mixed (Shares vs Assets, Price vs Quantity).

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Why does Uniswap V4 use PoolId instead of bytes32?"**
   - Good answer: Type safety - prevents using random hashes as pool identifiers
   - Great answer: Plus explain the zero-cost abstraction (no runtime overhead)

2. **"How would you design a type-safe vault?"**
   - Show understanding of: `type Shares is uint256`, custom operators, preventing shares/assets confusion

3. **"Explain bit-packing in BalanceDelta."**
   - This is a common interview question for Uniswap-related roles
   - Expected: Explain the memory layout, how packing/unpacking works, why it saves gas
   - Bonus: Mention the tradeoff (complexity vs gas savings)

**Interview Red Flags:**
- 🚩 Never heard of UDVTs
- 🚩 Can't explain when you'd use them
- 🚩 Don't know about Uniswap V4's usage (if applying to DEX roles)

**Pro tip:** Mentioning you've studied `BalanceDelta.sol` and understand bit-packing shows you can handle complex production code. It's a signal that you're beyond beginner tutorials.

> 🔍 **Deep dive:** [Uniswap V4 Design Blog](https://blog.uniswap.org/uniswap-v4) explains their architectural reasoning for using UDVTs. [Solidity Blog - User-Defined Operators](https://www.soliditylang.org/blog/2023/02/22/user-defined-operators/) provides an official deep dive on custom operators.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Unwrapping too early, losing type safety
function deposit(Assets assets) external {
    uint256 raw = Assets.unwrap(assets);  // Unwrapped immediately
    // ... 50 lines of math with raw uint256 ...
    // Type safety lost — could mix with shares again
}

// ✅ CORRECT: Keep wrapped as long as possible
function deposit(Assets assets) external {
    Shares shares = convertToShares(assets);  // Types maintained throughout
    _totalAssets = _totalAssets + assets;      // Can't accidentally mix with shares
    _totalShares = _totalShares + shares;      // Type-enforced ✨
}
```

```solidity
// ❌ WRONG: Wrapping arbitrary values — defeats the purpose
type PoolId is bytes32;

function getPool(bytes32 data) external view returns (Pool memory) {
    return pools[PoolId.wrap(data)];  // Wrapping unvalidated data — no safety!
}

// ✅ CORRECT: Only create PoolId from validated sources
function computePoolId(PoolKey memory key) internal pure returns (PoolId) {
    return PoolId.wrap(keccak256(abi.encode(key)));  // Only valid path
}
```

```solidity
// ❌ WRONG: Forgetting to define operators, leading to verbose code
type Shares is uint256;

// Without operators, every operation is painful:
Shares total = Shares.wrap(Shares.unwrap(a) + Shares.unwrap(b));

// ✅ CORRECT: Define operators with `using for ... global`
using { addShares as + } for Shares global;

function addShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap(Shares.unwrap(a) + Shares.unwrap(b));
}

// Now clean and readable:
Shares total = a + b;
```

---

<a id="abi-encodecall"></a>
### 💡 Concept: abi.encodeCall (0.8.11+)

**Why this matters:** When you call `token.transfer(to, amount)`, the compiler silently builds the calldata — a 4-byte function selector followed by the ABI-encoded arguments. But sometimes you can't make a direct call: you're going through a proxy (`delegatecall`), routing through a generic contract (`address.call(data)`), batching multiple operations, or encoding data for a cross-chain message. In those cases, you build the calldata yourself and pass it as raw `bytes`.

That's what `abi.encodeCall` does: it constructs that same bytes payload, but with **compile-time type checking** on the arguments — catching bugs that `abi.encodeWithSelector` silently lets through.

> Introduced in [Solidity 0.8.11](https://www.soliditylang.org/blog/2021/12/20/solidity-0.8.11-release-announcement/) (December 2021)

**The old way:**
```solidity
// ❌ OLD: No compile-time type checking — easy to swap arguments
bytes memory data = abi.encodeWithSelector(
    IERC20.transfer.selector,
    amount,      // BUG: swapped with recipient
    recipient
);
```

**The modern way:**
```solidity
// ✅ MODERN: Compiler verifies argument types match the function signature
bytes memory data = abi.encodeCall(
    IERC20.transfer,
    (recipient, amount)  // Compile error if these are swapped ✨
);
```

The compiler knows `IERC20.transfer` expects `(address, uint256)` and will reject mismatches at compile time.

**When to use this:**
- Encoding calls for `delegatecall`, `call`, `staticcall`
- Building multicall batches
- Encoding data for cross-chain messages
- Anywhere you previously used `abi.encodeWithSelector`

**What about the others?** `abi.encodeCall` doesn't replace everything. Use `abi.encodeWithSelector` when the target interface isn't known at compile time (e.g., generic proxy forwarding). Use `abi.encodeWithSignature` when you only have a string signature. Use `abi.encode` when you're not encoding a function call at all (e.g., hashing data with `keccak256`).

💻 **Quick Try:**

Test the type-safety difference in Remix or Foundry:
```solidity
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

function testEncoding() external pure returns (bytes memory safe, bytes memory unsafe) {
    address recipient = address(0xBEEF);
    uint256 amount = 100e18;

    // ✅ Type-safe: compiler verifies (address, uint256) match
    safe = abi.encodeCall(IERC20.transfer, (recipient, amount));

    // ❌ No type checking: swapping args compiles fine — silent bug!
    unsafe = abi.encodeWithSelector(IERC20.transfer.selector, amount, recipient);

    // Both produce 4-byte selector + args, but only encodeCall catches the swap
}
```
Try swapping `(recipient, amount)` to `(amount, recipient)` in the `encodeCall` line — the compiler rejects it immediately. The `encodeWithSelector` version silently produces wrong calldata.

#### 🔗 DeFi Pattern Connection

**Where `abi.encodeCall` matters in DeFi:**

1. **Multicall Routers** (1inch, Paraswap aggregators)
   ```solidity
   // Building a batch of swaps
   bytes[] memory calls = new bytes[](3);

   calls[0] = abi.encodeCall(
       IUniswap.swap,
       (tokenA, tokenB, amount, minOut)  // Type-checked!
   );

   calls[1] = abi.encodeCall(
       ICurve.exchange,
       (i, j, dx, min_dy)  // Compiler ensures correct types
   );

   // Execute batch
   multicall(calls);
   ```

2. **Flash Loan Callbacks**
   ```solidity
   // Encoding callback data for Aave flash loan
   bytes memory params = abi.encodeCall(
       this.executeArbitrage,
       (token, amount, profitTarget)
   );

   lendingPool.flashLoan(address(this), assets, amounts, modes, params);
   ```

3. **Cross-Chain Messages** (LayerZero, Axelar)
   ```solidity
   // Encoding a message to execute on destination chain
   bytes memory payload = abi.encodeCall(
       IDestination.mint,
       (recipient, amount, tokenId)  // Type safety prevents costly errors
   );

   bridge.send(destChainId, destAddress, payload);
   ```

**Why this matters:** In cross-chain/cross-protocol calls, debugging is expensive (can't just revert and retry). Type safety catches bugs before deployment.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Using abi.encodeWithSignature — typo-prone, no type checking
bytes memory data = abi.encodeWithSignature(
    "tranfer(address,uint256)",  // Typo! Missing 's' — silent failure
    recipient, amount
);

// ❌ ALSO WRONG: Using abi.encodeWithSelector — no argument type checking
bytes memory data = abi.encodeWithSelector(
    IERC20.transfer.selector,
    amount, recipient  // Swapped args — compiles fine, fails at runtime!
);

// ✅ CORRECT: abi.encodeCall catches both issues at compile time
bytes memory data = abi.encodeCall(
    IERC20.transfer,
    (recipient, amount)  // Compiler verifies types match signature
);
```

```solidity
// ❌ WRONG: Forgetting the tuple syntax for arguments
bytes memory data = abi.encodeCall(IERC20.transfer, recipient, amount);
// Compile error! Arguments must be wrapped in a tuple

// ✅ CORRECT: Arguments in parentheses as a tuple
bytes memory data = abi.encodeCall(IERC20.transfer, (recipient, amount));
```

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you build a multicall router?"**
   - Good answer: Batch multiple calls, use `abi.encodeCall` for type safety
   - Great answer: Plus mention gas optimization (batch vs individual), error handling, and security (reentrancy)

2. **"What's the difference between abi.encodeCall and abi.encodeWithSelector?"**
   - `abi.encodeCall`: Type-checked at compile time
   - `abi.encodeWithSelector`: No type checking, easy to make mistakes
   - Show you know when to use each (prefer encodeCall in new code)

**Interview Red Flags:**
- 🚩 Still using `abi.encodeWithSelector` or `abi.encodeWithSignature` in new code
- 🚩 Not aware of the type safety benefits

**Pro tip:** In multicall/batch architectures, `abi.encodeCall` shines because a single typo in a selector can drain funds. Show interviewers you default to the type-safe option and only drop to `encodeWithSelector` when dealing with dynamic interfaces (e.g., proxy patterns where the target ABI isn't known at compile time).

---

<a id="other-notable-changes"></a>
### 💡 Concept: Other Notable Changes

**Named parameters in mapping types (0.8.18+):**

Self-documenting code, especially useful for nested mappings:

```solidity
// ❌ BEFORE: Hard to understand
mapping(address => mapping(address => uint256)) public balances;

// ✅ AFTER: Self-explanatory
mapping(address user => mapping(address token => uint256 balance)) public balances;
```

> Introduced in [Solidity 0.8.18](https://www.soliditylang.org/blog/2023/02/01/solidity-0.8.18-release-announcement/)

**OpenZeppelin v5 — The `_update()` hook pattern:**

OpenZeppelin v5 (aligned with Solidity 0.8.20+) replaced the dual `_beforeTokenTransfer` / `_afterTokenTransfer` hooks with a single `_update()` function. When reading protocol code, check which OZ version they're using.

> Learn more: [Introducing OpenZeppelin Contracts 5.0](https://blog.openzeppelin.com/introducing-openzeppelin-contracts-5.0)

**`bytes.concat` and `string.concat` (0.8.4+ / 0.8.12+):**

Cleaner alternatives to `abi.encodePacked` for non-hashing concatenation:

```solidity
// ❌ BEFORE: abi.encodePacked for everything
bytes memory data = abi.encodePacked(prefix, payload);

// ✅ AFTER: Purpose-specific concatenation
bytes memory data = bytes.concat(prefix, payload);       // For bytes
string memory name = string.concat(first, " ", last);    // For strings
```

Use `bytes.concat` / `string.concat` for building data, `abi.encodePacked` only for hash inputs.

**`immutable` improvements (0.8.8+ / 0.8.21+):**

Immutable variables became more flexible over time:
- **0.8.8+**: Immutables can be read in the constructor
- **0.8.21+**: Immutables can be non-value types (bytes, strings) — previously only value types (uint256, address, etc.) were supported

```solidity
// Since 0.8.21: immutable string and bytes
string public immutable name;   // Stored in code, not storage — cheaper to read
bytes32 public immutable merkleRoot;

constructor(string memory _name, bytes32 _root) {
    name = _name;
    merkleRoot = _root;
}
```

**Free functions and `using for` at file level (0.8.0+):**

Functions can exist outside contracts, and `using LibraryX for TypeY global` makes library functions available everywhere:

```solidity
// Free function (not in a contract)
function toWad(uint256 value) pure returns (uint256) {
    return value * 1e18;
}

// Make it available globally
using { toWad } for uint256 global;

// Now usable anywhere in the file:
uint256 wad = 100.toWad();
```

This pattern dominates [Uniswap V4's codebase](https://github.com/Uniswap/v4-core) — nearly all their utilities are free functions with global `using for` declarations.

---

<a id="day1-exercise"></a>
## 🎯 Build Exercise: ShareMath

**Workspace:** [`workspace/src/part1/module1/exercise1-share-math/`](../workspace/src/part1/module1/exercise1-share-math/) — starter file: [`ShareMath.sol`](../workspace/src/part1/module1/exercise1-share-math/ShareMath.sol), tests: [`ShareMath.t.sol`](../workspace/test/part1/module1/exercise1-share-math/ShareMath.t.sol)

Build a **vault share calculator** — the exact math that underpins every ERC-4626 vault, lending pool, and LP token in DeFi:

1. **Define UDVTs** for `Assets` and `Shares` (both wrapping `uint256`) with custom `+` and `-` operators
   - Implement the operators as **free functions** with `using { add as +, sub as - } for Assets global`
   - This exercises the free function + `using for global` pattern

2. **Implement conversion functions:**
   - `toShares(Assets assets, Assets totalAssets, Shares totalSupply)`
   - `toAssets(Shares shares, Assets totalAssets, Shares totalSupply)`
   - Use `unchecked` where the math is provably safe
   - Use custom errors: `ZeroAssets()`, `ZeroShares()`, `ZeroTotalSupply()`

3. **Create a wrapper contract** `ShareCalculator` that wraps these functions
   - In your Foundry tests, call it via `abi.encodeCall` for at least one test case
   - Verify the type-safe encoding catches what `abi.encodeWithSelector` wouldn't

4. **Test the math:**
   - Deposit 1000 assets when totalAssets=5000, totalSupply=3000 → verify you get 600 shares
   - Test the roundtrip: convert assets→shares→assets
   - Verify the result is within 1 wei of the original (rounding always favors the vault)

**🎯 Goal:** Get hands-on with the syntax in a DeFi context. This exact shares/assets math shows up in every vault and lending protocol in Part 2 — you're building the intuition now.

## 📋 Key Takeaways: Language-Level Changes

After this section, you should be able to:
- Explain why `unchecked` is safe in a Uniswap V2 swap (bounded inputs) but dangerous in a user-facing deposit (arbitrary inputs), and why vault math uses `mulDiv` instead
- Explain why `mulDiv` uses a 512-bit intermediate for `a * b / c` and how this prevents phantom overflow (the product is too large for 256 bits, but the final result isn't)
- Explain how `try/catch` handles external call failures and how custom error selectors let callers identify *which* error occurred without parsing strings
- Read a UDVT definition like Uniswap V4's `Currency` and explain the type safety it provides over a raw `address`
- Look at an `abi.encodeCall` invocation and explain what compile-time check it provides that `abi.encodeWithSelector` doesn't

---

## 💡 Solidity 0.8.24+ — The Bleeding Edge

<a id="transient-storage"></a>
### 💡 Concept: Transient Storage Support (0.8.24+)

**Why this matters:** Reentrancy guards cost 5,000-20,000 gas to write to storage. Transient storage costs ~100 gas for the same protection. That's a 50-200x gas savings. Beyond guards, transient storage enables new patterns like [Uniswap V4's flash accounting system](https://blog.uniswap.org/uniswap-v4).

> Based on [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153), supported since [Solidity 0.8.24](https://www.soliditylang.org/blog/2024/01/26/transient-storage/)

**Assembly-first (0.8.24-0.8.27):**

Initially, transient storage required inline assembly:

```solidity
// ⚠️ OLD SYNTAX: Assembly required (0.8.24-0.8.27)
modifier nonreentrant() {
    assembly {
        if tload(0) { revert(0, 0) }
        tstore(0, 1)
    }
    _;
    assembly {
        tstore(0, 0)
    }
}
```

**The `transient` keyword (0.8.28+):**

Since [Solidity 0.8.28](https://www.soliditylang.org/blog/2024/10/09/solidity-0.8.28-release-announcement/), you can declare state variables with `transient`, and the compiler handles the opcodes:

```solidity
// ✅ MODERN SYNTAX: transient keyword (0.8.28+)
contract ReentrancyGuard {
    bool transient locked;

    modifier nonreentrant() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }
}
```

The `transient` keyword makes the variable live in transient storage — same slot-based addressing as regular storage, but discarded at the end of every transaction.

💻 **Quick Try:**

Test transient vs regular storage gas costs in Remix:
```solidity
contract GasTest {
    // Regular storage
    uint256 regularValue;

    // Transient storage
    uint256 transient transientValue;

    function testRegular() external {
        regularValue = 1;  // Check gas cost
    }

    function testTransient() external {
        transientValue = 1;  // Check gas cost
    }
}
```
Deploy and compare execution costs. You'll see ~20,000 vs ~100 gas difference.

**📊 Gas comparison:**

| Storage Type | First Write | Warm Write | Savings |
|--------------|-------------|------------|---------|
| Regular storage (cold) | ~20,000 gas | ~5,000 gas | Baseline |
| Transient storage | ~100 gas | ~100 gas | **50-200x cheaper** ✨ |

> ⚡ **Note:** Exact gas costs vary by compiler version, optimizer settings, and EVM upgrades. The relative difference (transient is dramatically cheaper) is what matters, not the precise numbers.

#### 🔍 Deep Dive: Transient Storage at EVM Level

**How it works:**

```
Regular Storage (SSTORE/SLOAD):
┌─────────────────────────────────┐
│  Persists across transactions  │
│  Written to blockchain state   │
│  Expensive (disk I/O)           │
│  Refunds available              │
└─────────────────────────────────┘

Transient Storage (TSTORE/TLOAD):
┌─────────────────────────────────┐
│  Lives only during transaction  │
│  In-memory (no disk writes)     │
│  Cheap (~100 gas)               │
│  Auto-cleared after transaction │
└─────────────────────────────────┘
```

**Key properties:**
1. **Transaction-scoped**: Set in call A, read in call B (same transaction) ✅
2. **Auto-reset**: Cleared when transaction ends (no manual cleanup needed)
3. **No refunds**: Unlike SSTORE, no refund mechanism needed (simpler gas accounting)
4. **Same slot addressing**: Uses storage slots like regular storage

**When to use assembly vs keyword:**

```solidity
// Use the keyword (0.8.28+) for simple cases:
bool transient locked;  // Clear, readable

// Use assembly for dynamic slot calculation:
assembly {
    let slot := keccak256(add(key, someOffset))
    tstore(slot, value)  // Dynamic slot access
}
```

🏗️ **Real usage:**

[OpenZeppelin's `ReentrancyGuardTransient.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol) — their production implementation using the `transient` keyword. Compare it to the classic storage-based [`ReentrancyGuard.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol) to see the difference.

#### 🔍 Deep Dive: Uniswap V4 Flash Accounting

**The traditional model** (V1, V2, V3):
```solidity
// Transfer tokens IN
token.transferFrom(user, pool, amountIn);

// Do swap logic
uint256 amountOut = calculateSwap(amountIn);

// Transfer tokens OUT
token.transfer(user, amountOut);
```
Every swap = 2 token transfers = expensive!

**V4's flash accounting** (using transient storage):
```solidity
// Record debt in transient storage
int256 transient delta0;  // How much pool owes/is owed for token0
int256 transient delta1;  // How much pool owes/is owed for token1

// During swap: just update deltas (cheap!)
delta0 -= int256(amountIn);   // Pool gains token0
delta1 += int256(amountOut);  // Pool owes token1

// At END of transaction: settle all debts at once
function settle() external {
    if (delta0 < 0) token0.transferFrom(msg.sender, pool, uint256(-delta0));
    if (delta1 > 0) token1.transfer(msg.sender, uint256(delta1));
}
```

**The breakthrough:**
- Multiple swaps in one transaction? Update deltas multiple times (cheap)
- Settle debts ONCE at the end (one transfer per token)
- Net result: Massive gas savings for multi-hop swaps

**Visualization:**
```
Old model (V3):
Swap A: Transfer IN → Swap → Transfer OUT
Swap B: Transfer IN → Swap → Transfer OUT
Swap C: Transfer IN → Swap → Transfer OUT
Total: 6 transfers

New model (V4):
Swap A: Update delta (100 gas)
Swap B: Update delta (100 gas)
Swap C: Update delta (100 gas)
Settle: Transfer IN + Transfer OUT (2 transfers total)
Savings: 4 transfers eliminated!
```

**Why transient storage is essential:**
- Deltas must persist across internal calls within the transaction
- But must be cleared before next transaction (no state pollution)
- Perfect fit for transient storage

#### 🔗 DeFi Pattern Connection

**Where transient storage changes DeFi:**

1. **Reentrancy Guards** (everywhere)
   - Before: 20,000 gas per protected function
   - After: 100 gas per protected function
   - Every protocol with external calls benefits

2. **Flash Loan State** (Aave, Balancer)
   - Track "in flash loan" state across callback
   - Verify repayment before transaction ends
   - No permanent storage pollution

3. **Multi-Protocol Routing** (aggregators like 1inch)
   - Track token balances across multiple DEX calls
   - Settle once at the end
   - Massive savings for complex routes

4. **Temporary Access Control**
   - Grant permission for duration of transaction
   - Auto-revoke when transaction ends
   - Useful for complex DeFi operations

**The pattern:** Whenever you need state that:
- Lives across multiple calls in ONE transaction
- Must be cleared before next transaction
- Is accessed frequently (gas-sensitive)

→ Use transient storage

#### 💼 Job Market Context

**This is production-critical** — Uniswap V4 uses this pattern, and every major DEX team is adopting it.

**What DeFi teams expect you to know:**

1. **"Explain Uniswap V4's flash accounting."**
   - This is THE interview question for DEX roles
   - Expected: Explain delta tracking, settlement, why transient storage
   - Bonus: Explain the gas savings quantitatively

2. **"When would you use transient storage?"**
   - Good answer: Reentrancy guards, temporary state within transaction
   - Great answer: Plus mention flash accounting pattern, multi-step operations, the tradeoff (only works within one transaction)

3. **"How would you migrate a reentrancy guard to transient storage?"**
   - Show understanding of: drop-in replacement, gas savings, when it's worth it

**Interview Red Flags:**
- 🚩 Never heard of transient storage (major red flag for modern DeFi roles)
- 🚩 Can't explain EIP-1153 basics
- 🚩 Don't know about Uniswap V4's usage

**Pro tip:** If interviewing for a DEX/AMM role, deeply study Uniswap V4's implementation. Mentioning you understand flash accounting puts you ahead of 90% of candidates.

> 🔍 **Deep dive:** [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) includes detailed security considerations. [Uniswap V4 Flash Accounting Docs](https://docs.uniswap.org/contracts/v4/concepts/flash-accounting) shows production usage. [Cyfrin - Uniswap V4 Swap Deep Dive](https://www.cyfrin.io/blog/uniswap-v4-swap-deep-dive-into-execution-and-accounting) provides a technical walkthrough of flash accounting with transient storage.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Assuming transient storage persists across transactions
contract TokenCache {
    address transient lastSender;

    function recordSender() external {
        lastSender = msg.sender;  // Gone after this transaction!
    }

    function getLastSender() external view returns (address) {
        return lastSender;  // Always address(0) in a new transaction
    }
}

// ✅ CORRECT: Use regular storage for cross-transaction state
contract TokenCache {
    address public lastSender;       // Regular storage — persists
    bool transient _processing;      // Transient — only for intra-tx flags
}
```

```solidity
// ❌ WRONG: Using transient storage for data that must survive upgrades
contract VaultV1 {
    uint256 transient totalDeposits;  // Lost after every transaction!
}

// ✅ CORRECT: Only transient for ephemeral intra-transaction state
contract VaultV1 {
    uint256 public totalDeposits;       // Persistent — survives across txs
    bool transient _reentrancyLocked;   // Ephemeral — only during tx
}
```

```solidity
// ❌ WRONG: Forgetting to reset transient state in multi-step transactions
modifier withCallback() {
    _callbackExpected = true;
    _;
    // Forgot to reset! If tx continues after this call, stale flag remains
}

// ✅ CORRECT: Explicitly reset even though tx-end auto-clears
modifier withCallback() {
    _callbackExpected = true;
    _;
    _callbackExpected = false;  // Clean up — don't rely only on auto-clear
}
```

---

<a id="pectra-prague-evm"></a>
### 💡 Concept: Pectra/Prague EVM Target (0.8.30+)

**What changed:** [Solidity 0.8.30](https://www.soliditylang.org/blog/2025/05/07/solidity-0.8.30-release-announcement/) changed the default EVM target from Cancun to Prague (the Pectra upgrade, May 2025). New opcodes are available and the compiler's code generation assumes the newer EVM.

**What Pectra brought:**
- **EIP-7702**: Set EOA code (delegate transactions) — enables account abstraction patterns without deploying a new wallet contract. Covered in depth in Module 4.
- **EIP-7685**: General purpose execution layer requests
- **EIP-2537**: BLS12-381 precompile — efficient BLS signature verification (important for consensus layer interactions)

**What this means for you:**
- ✅ Deploying to Ethereum mainnet: use default (Prague/Pectra)
- ⚠️ Deploying to L2s or chains that haven't upgraded: specify `--evm-version cancun` in your compiler settings
- ⚠️ Compiling with Prague target produces bytecode that may fail on pre-Pectra chains

Check your target chain's EVM version in your Foundry config (`foundry.toml`):
```toml
[profile.default]
evm_version = "cancun"  # For L2s that haven't adopted Pectra yet
```

---

<a id="solidity-09-deprecations"></a>
### 💡 Concept: What's Coming — Solidity 0.9.0 Deprecations

[Solidity 0.8.31](https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/) started emitting deprecation warnings for features being removed in 0.9.0:

| Feature | Status | What to Use Instead |
|---------|--------|---------------------|
| ABI coder v1 | ⚠️ Deprecated | ABI coder v2 (default since 0.8.0) |
| Virtual modifiers | ⚠️ Deprecated | Virtual functions |
| `transfer()` / `send()` | ⚠️ Deprecated | `.call{value: amount}("")` |
| Contract type comparisons | ⚠️ Deprecated | Address comparisons |

You should already be avoiding all of these in new code, but you'll encounter them when reading older DeFi protocols.

> ⚠️ **Critical:** `.transfer()` and `.send()` have a fixed 2300 gas stipend, which breaks with some smart contract wallets and modern opcodes. Always use `.call{value: amount}("")` instead.

---

<a id="day2-exercise"></a>
## 🎯 Build Exercise: TransientGuard

**Workspace:** [`workspace/src/part1/module1/exercise2-transient-guard/`](../workspace/src/part1/module1/exercise2-transient-guard/) — starter file: [`TransientGuard.sol`](../workspace/src/part1/module1/exercise2-transient-guard/TransientGuard.sol), tests: [`TransientGuard.t.sol`](../workspace/test/part1/module1/exercise2-transient-guard/TransientGuard.t.sol)

1. **Implement `TransientReentrancyGuard`** using the `transient` keyword (0.8.28+ syntax)
2. **Implement the same guard** using raw `tstore`/`tload` assembly (0.8.24+ syntax)
3. **Write a Foundry test** that demonstrates the reentrancy protection works:
   - Create an attacker contract that attempts reentrant calls
   - Verify the guard blocks the attack
4. **Compare gas costs** between:
   - Your transient guard
   - OpenZeppelin's storage-based `ReentrancyGuard`
   - A raw storage implementation

**🎯 Goal:** Understand both the high-level `transient` syntax and the underlying opcodes. The gas comparison gives you a concrete sense of why this matters.

## 📋 Key Takeaways: Bleeding Edge

After this section, you should be able to:
- Explain why transient storage is dramatically cheaper than regular storage and what makes it unsuitable for cross-transaction state
- Describe Uniswap V4's flash accounting pattern: how delta tracking with transient storage replaces per-swap token transfers
- Compare `tstore`/`tload` assembly syntax (0.8.24) with the `transient` keyword (0.8.28) and know when each is appropriate

---

## 📚 Resources

**Core Solidity Documentation:**
- [0.8.0 Breaking Changes](https://docs.soliditylang.org/en/latest/080-breaking-changes.html) — complete list of all changes from 0.7
- [Solidity Blog - Release Announcements](https://www.soliditylang.org/blog/category/releases/) — every version explained
- [Solidity Changelog](https://github.com/ethereum/solidity/blob/develop/Changelog.md) — detailed version history

**Checked Arithmetic & Unchecked:**
- [Solidity docs — Checked or Unchecked Arithmetic](https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic)
- [Uniswap V4 FullMath.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/libraries/FullMath.sol) — production `unchecked` usage for 512-bit math

**Custom Errors:**
- [Solidity docs — Errors](https://docs.soliditylang.org/en/latest/structure-of-a-contract.html#errors)
- [Solidity blog — "Custom Errors in Solidity"](https://www.soliditylang.org/blog/2021/04/21/custom-errors/) — introduction, gas savings, ABI encoding
- [Aave V3 Errors.sol](https://github.com/aave/aave-v3-core/blob/ea4867086d39f094303916e72e180f99d8149fd5/contracts/protocol/libraries/helpers/Errors.sol) — centralized error library pattern

**User-Defined Value Types:**
- [Solidity docs — UDVTs](https://docs.soliditylang.org/en/latest/types.html#user-defined-value-types)
- [Uniswap V4 PoolId.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/PoolId.sol) — `type PoolId is bytes32`
- [Uniswap V4 Currency.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/Currency.sol) — `type Currency is address` with custom operators
- [Uniswap V4 BalanceDelta.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/BalanceDelta.sol) — `type BalanceDelta is int256` with bit-packed int128 pair

**ABI Encoding:**
- [Solidity docs — ABI Encoding and Decoding Functions](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#abi-encoding-and-decoding-functions)

**Transient Storage:**
- [Solidity blog — "Transient Storage Opcodes in Solidity 0.8.24"](https://www.soliditylang.org/blog/2024/01/26/transient-storage/) — EIP-1153, use cases, risks
- [Solidity blog — 0.8.28 Release](https://www.soliditylang.org/blog/2024/10/09/solidity-0.8.28-release-announcement/) — full `transient` keyword support
- [EIP-1153: Transient Storage Opcodes](https://eips.ethereum.org/EIPS/eip-1153) — the EIP specification
- [OpenZeppelin ReentrancyGuardTransient.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol) — production implementation

**OpenZeppelin v5:**
- [Introducing OpenZeppelin Contracts 5.0](https://blog.openzeppelin.com/introducing-openzeppelin-contracts-5.0) — all breaking changes, migration from v4
- [OpenZeppelin Contracts 5.x docs](https://docs.openzeppelin.com/contracts/5.x)
- [Changelog with migration guide](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/CHANGELOG.md)

**Solidity 0.9.0 Deprecations:**
- [Solidity blog — 0.8.31 Release](https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/) — first deprecation warnings for 0.9.0

**Security & Analysis Tools:**
- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation) — automated security checks for modern Solidity features

---

**Navigation:** Start of Part 1 | [Module 2: EVM Changes →](2-evm-changes.md)

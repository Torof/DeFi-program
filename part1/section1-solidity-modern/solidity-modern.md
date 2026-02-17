# Section 1: Solidity 0.8.x — What Changed (~2 days)

## 📚 Table of Contents

**Day 1: Language-Level Changes**
- [Checked Arithmetic (0.8.0)](#checked-arithmetic)
- [Custom Errors (0.8.4+)](#custom-errors)
- [User-Defined Value Types (0.8.8+)](#user-defined-value-types)
- [abi.encodeCall (0.8.11+)](#abi-encodecall)
- [Other Notable Changes](#other-notable-changes)
- [Day 1 Build Exercise](#day1-exercise)

**Day 2: The Bleeding Edge**
- [Transient Storage (0.8.24+)](#transient-storage)
- [Pectra/Prague EVM (0.8.30+)](#pectra-prague-evm)
- [Solidity 0.9.0 Deprecations](#solidity-09-deprecations)
- [Day 2 Build Exercise](#day2-exercise)

---

## Day 1: Language-Level Changes That Matter for DeFi

<a id="checked-arithmetic"></a>
### 💡 Concept: Checked Arithmetic (0.8.0)

**Why this matters:** Before Solidity 0.8, integer overflow/underflow was silent and deadly. A simple `balances[user] -= amount` could wrap from 0 to `type(uint256).max`, draining contracts. Every pre-0.8 contract needed SafeMath just to avoid this. Now it's built into the language.

> Introduced in [Solidity 0.8.0](https://www.soliditylang.org/blog/2020/12/16/solidity-v0.8.0-release-announcement/) (December 2020)

**The change:** Arithmetic operations now revert on overflow/underflow by default. `uint256(0) - 1` reverts instead of wrapping to `type(uint256).max`.

**What this eliminated:** SafeMath — a library that was in literally every pre-0.8 contract. You'll still see it in older protocol code (Uniswap V2, Compound V2, original MakerDAO), so recognize it when you encounter it, but never use it in new code.

**The `unchecked {}` escape hatch:**

When you can mathematically prove an operation won't overflow, use `unchecked` to skip the safety check and save gas:

```solidity
// ✅ CORRECT: Loop counter that can't realistically overflow
for (uint256 i = 0; i < length;) {
    // ... loop body
    unchecked { ++i; }  // Saves ~20 gas per iteration
}

// ✅ CORRECT: AMM math where inputs are already validated
unchecked {
    uint256 denominator = reserveIn * 1000 + amountInWithFee;
}
```

**When to use `unchecked`:**

Only when you can mathematically prove the operation won't overflow. In DeFi, this usually means:
- Loop counters with bounded iteration counts
- Formulas where the mathematical structure guarantees safety
- Values already validated through require checks

> ⚡ **Common pitfall:** Don't use `unchecked` just because "it probably won't overflow." The gas savings (5-20 gas per operation) aren't worth the risk if your proof is wrong.

🏗️ **Real usage:**

[Uniswap V4's `FullMath.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/libraries/FullMath.sol) (originally from V3) is a masterclass in `unchecked` usage. Every operation is proven safe through the structure of 512-bit intermediate calculations. Study the `mulDiv` function to see how production DeFi handles complex fixed-point math safely.

> 🔍 **Deep dive:** [Consensys Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/) covers integer overflow/underflow security patterns. [Trail of Bits - Building Secure Contracts](https://github.com/crytic/building-secure-contracts) provides development guidelines including arithmetic safety.

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

**Even more modern (0.8.26+):**

As of [Solidity 0.8.26](https://www.soliditylang.org/blog/2024/05/21/solidity-0.8.26-release-announcement/), you can use custom errors directly in `require`:

```solidity
// ✅ NEWEST: Best of both worlds
require(amount > 0, InvalidAmount());
require(balance >= amount, InsufficientBalance(balance, amount));
```

**Beyond gas savings:**

Custom errors are better for off-chain tooling too — you can decode them by selector without needing string parsing or ABIs.

🏗️ **Real usage:**

Two common patterns in production:
- **Centralized:** [Aave V3's `Errors.sol`](https://github.com/aave/aave-v3-core/blob/ea4867086d39f094303916e72e180f99d8149fd5/contracts/protocol/libraries/helpers/Errors.sol) defines 60+ errors in one library. Easier to maintain, single source of truth.
- **Decentralized:** Uniswap V4 defines errors per-contract. More modular, less coupling.

Both work — choose based on your protocol size and organization.

> ⚡ **Common pitfall:** Changing an error signature (e.g., adding a parameter) changes its selector. Update your frontend/indexer decoding logic when you do this, or reverts will decode as "unknown error."

> 🔍 **Deep dive:** [Cyfrin Updraft - Custom Errors](https://updraft.cyfrin.io/courses/solidity/fund-me/solidity-custom-errors) provides a tutorial with practical examples. [Solidity Docs - Error Handling](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions) covers how custom errors work with try/catch.

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

🏗️ **Real usage — Uniswap V4:**

Understanding UDVTs is essential for reading V4 code. They use them extensively:
- [`PoolId.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/PoolId.sol) — `type PoolId is bytes32`, computed via `keccak256(abi.encode(poolKey))`
- [`Currency.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/Currency.sol) — `type Currency is address`, unifies native ETH and ERC-20 handling with custom comparison operators
- [`BalanceDelta.sol`](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/BalanceDelta.sol) — `type BalanceDelta is int256`, packs two `int128` values using bit manipulation with custom `+`, `-`, `==`, `!=` operators

> Spend time with `BalanceDelta.sol` — it shows advanced UDVT patterns including bit-packing and how to implement operators that work across the packed structure.

> 🔍 **Deep dive:** [Uniswap V4 Design Blog](https://blog.uniswap.org/uniswap-v4) explains their architectural reasoning for using UDVTs. [Solidity Blog - User-Defined Operators](https://www.soliditylang.org/blog/2023/02/22/user-defined-operators/) provides an official deep dive on custom operators.

---

<a id="abi-encodecall"></a>
### 💡 Concept: abi.encodeCall (0.8.11+)

**Why this matters:** Low-level calls are everywhere in DeFi — delegate calls in proxies, calls through routers, flash loan callbacks. Type-safe encoding prevents silent bugs where you pass the wrong argument types.

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
## 🎯 Day 1 Build Exercise

**Workspace:** [`workspace/src/part1/section1/`](../../workspace/src/part1/section1/) — starter files: [`ShareMath.sol`](../../workspace/src/part1/section1/ShareMath.sol), tests: [`ShareMath.t.sol`](../../workspace/test/part1/section1/ShareMath.t.sol)

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

---

## 📋 Day 1 Summary

**✓ Covered:**
- Checked arithmetic by default (0.8.0) — no more SafeMath needed
- Custom errors (0.8.4+) — gas savings and better tooling
- User-Defined Value Types (0.8.8+) — type safety for domain concepts
- `abi.encodeCall` (0.8.11+) — type-safe low-level calls
- Named mapping parameters (0.8.18+) — self-documenting code
- OpenZeppelin v5 patterns — `_update()` hook
- Free functions and global `using for` — Uniswap V4 style

**Next:** Day 2 — Transient storage, bleeding edge features, and what's coming in 0.9.0

---

## Day 2: Solidity 0.8.24+ — The Bleeding Edge

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

**📊 Gas comparison:**

| Storage Type | First Write | Warm Write | Savings |
|--------------|-------------|------------|---------|
| Regular storage (cold) | ~20,000 gas | ~5,000 gas | Baseline |
| Transient storage | ~100 gas | ~100 gas | **50-200x cheaper** ✨ |

🏗️ **Real usage:**

[OpenZeppelin's `ReentrancyGuardTransient.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol) — their production implementation using the `transient` keyword. Compare it to the classic storage-based [`ReentrancyGuard.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol) to see the difference.

> 🔍 **Deep dive:** [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) includes detailed security considerations. [Uniswap V4 Flash Accounting Docs](https://docs.uniswap.org/contracts/v4/concepts/flash-accounting) shows production usage. [Cyfrin - Uniswap V4 Swap Deep Dive](https://www.cyfrin.io/blog/uniswap-v4-swap-deep-dive-into-execution-and-accounting) provides a technical walkthrough of flash accounting with transient storage.

---

<a id="pectra-prague-evm"></a>
### 💡 Concept: Pectra/Prague EVM Target (0.8.30+)

**What changed:** [Solidity 0.8.30](https://www.soliditylang.org/blog/2025/05/07/solidity-0.8.30-release-announcement/) changed the default EVM target from Cancun to Prague (the Pectra upgrade, May 2025). New opcodes are available and the compiler's code generation assumes the newer EVM.

**What this means for you:**
- ✅ Deploying to Ethereum mainnet: use default (Prague/Pectra)
- ⚠️ Deploying to chains that haven't upgraded: specify `--evm-version cancun` in your compiler settings

Check your target chain's EVM version in your Foundry/Hardhat config.

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
## 🎯 Day 2 Build Exercise

**Workspace:** [`workspace/src/part1/section1/`](../../workspace/src/part1/section1/) — starter files: [`TransientGuard.sol`](../../workspace/src/part1/section1/TransientGuard.sol), tests: [`TransientGuard.t.sol`](../../workspace/test/part1/section1/TransientGuard.t.sol)

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

---

## 📋 Day 2 Summary

**✓ Covered:**
- Transient storage (0.8.24+) — 50-200x cheaper than regular storage
- `transient` keyword (0.8.28+) — high-level syntax for transient storage
- Pectra/Prague EVM target (0.8.30+) — new default compiler target
- Solidity 0.9.0 deprecations — what to avoid in new code

**Key takeaway:** Transient storage is the biggest gas optimization since EIP-2929. Understanding it is essential for reading modern DeFi code (especially Uniswap V4) and building gas-efficient protocols.

---

## 📚 Resources

### Core Solidity Documentation
- [0.8.0 Breaking Changes](https://docs.soliditylang.org/en/latest/080-breaking-changes.html) — complete list of all changes from 0.7
- [Solidity Blog - Release Announcements](https://www.soliditylang.org/blog/category/releases/) — every version explained
- [Solidity Changelog](https://github.com/ethereum/solidity/blob/develop/Changelog.md) — detailed version history

### Checked Arithmetic & Unchecked
- [Solidity docs — Checked or Unchecked Arithmetic](https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic)
- [Uniswap V4 FullMath.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/libraries/FullMath.sol) — production `unchecked` usage for 512-bit math

### Custom Errors
- [Solidity docs — Errors](https://docs.soliditylang.org/en/latest/structure-of-a-contract.html#errors)
- [Solidity blog — "Custom Errors in Solidity"](https://www.soliditylang.org/blog/2021/04/21/custom-errors/) — introduction, gas savings, ABI encoding
- [Aave V3 Errors.sol](https://github.com/aave/aave-v3-core/blob/ea4867086d39f094303916e72e180f99d8149fd5/contracts/protocol/libraries/helpers/Errors.sol) — centralized error library pattern

### User-Defined Value Types
- [Solidity docs — UDVTs](https://docs.soliditylang.org/en/latest/types.html#user-defined-value-types)
- [Uniswap V4 PoolId.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/PoolId.sol) — `type PoolId is bytes32`
- [Uniswap V4 Currency.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/Currency.sol) — `type Currency is address` with custom operators
- [Uniswap V4 BalanceDelta.sol](https://github.com/Uniswap/v4-core/blob/d153b048868a60c2403a3ef5b2301bb247884d46/src/types/BalanceDelta.sol) — `type BalanceDelta is int256` with bit-packed int128 pair

### ABI Encoding
- [Solidity docs — ABI Encoding and Decoding Functions](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#abi-encoding-and-decoding-functions)

### Transient Storage
- [Solidity blog — "Transient Storage Opcodes in Solidity 0.8.24"](https://www.soliditylang.org/blog/2024/01/26/transient-storage/) — EIP-1153, use cases, risks
- [Solidity blog — 0.8.28 Release](https://www.soliditylang.org/blog/2024/10/09/solidity-0.8.28-release-announcement/) — full `transient` keyword support
- [EIP-1153: Transient Storage Opcodes](https://eips.ethereum.org/EIPS/eip-1153) — the EIP specification
- [OpenZeppelin ReentrancyGuardTransient.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol) — production implementation

### OpenZeppelin v5
- [Introducing OpenZeppelin Contracts 5.0](https://blog.openzeppelin.com/introducing-openzeppelin-contracts-5.0) — all breaking changes, migration from v4
- [OpenZeppelin Contracts 5.x docs](https://docs.openzeppelin.com/contracts/5.x)
- [Changelog with migration guide](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/CHANGELOG.md)

### Solidity 0.9.0 Deprecations
- [Solidity blog — 0.8.31 Release](https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/) — first deprecation warnings for 0.9.0

### Security & Analysis Tools
- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation) — automated security checks for modern Solidity features

---

**Navigation:** [Next: Section 2 - EVM Changes →](../section2-evm-changes/evm-changes.md)

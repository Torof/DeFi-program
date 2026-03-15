# Part 4 — Module 5: External Calls

> **Difficulty:** Intermediate-Advanced
>
> **Estimated reading time:** ~55 minutes | **Exercises:** ~3-4 hours

---

## 📚 Table of Contents

**Building Calls by Hand**
- [Encoding Calldata for External Calls](#encoding-calldata)
- [The Call Lifecycle: Encode, Call, Check, Decode](#call-lifecycle)
- [Decoding Return Data](#decoding-returndata)
- [Build Exercise: CallEncoder](#exercise1)

**Error Handling & Safety Patterns**
- [Error Propagation: Bubbling Revert Data](#error-propagation)
- [The SafeERC20 Pattern](#safe-erc20)
- [The Returnbomb Attack](#returnbomb)
- [Gas Forwarding in Practice](#gas-forwarding)
- [Build Exercise: SafeCaller](#exercise2)

**Production Call Patterns**
- [DELEGATECALL in Depth](#delegatecall-depth)
- [Precompile Calls — ecrecover in Assembly](#precompile-calls)
- [The Multicall Pattern](#multicall)
- [Build Exercise: AssemblyRouter](#exercise3)

---

## 💡 Building Calls by Hand

Modules 1-4 gave you the pieces: memory layout and the free memory pointer (M2), calldata decoding and ABI encoding (M2), storage operations (M3), and selector dispatch — how to *receive* calls (M4). Now you combine them to *make* outbound calls. M4 taught the inbound side; M5 teaches the outbound side.

<a id="encoding-calldata"></a>
### 💡 Concept: Encoding Calldata for External Calls

**Why this matters:** Every `token.transfer(to, amount)` in Solidity compiles to memory encoding followed by a CALL opcode. When you write this in assembly, you control every byte — where the selector goes, where arguments go, and how much memory you use. This is the foundation for every external call pattern in this module.

**Encoding `transfer(address,uint256)` by hand:**

The function selector is `0xa9059cbb` — the first 4 bytes of `keccak256("transfer(address,uint256)")`. The two arguments are ABI-encoded as 32-byte words starting at offset 4.

```solidity
assembly {
    let ptr := mload(0x40) // allocate from FMP

    // Selector — shifted left to occupy the high 4 bytes of a 32-byte word
    mstore(ptr, shl(224, 0xa9059cbb))

    // Argument 1: address (left-padded to 32 bytes — the ABI standard)
    mstore(add(ptr, 0x04), to)

    // Argument 2: uint256 (full 32 bytes)
    mstore(add(ptr, 0x24), amount)

    // Total calldata: 4 (selector) + 32 (address) + 32 (uint256) = 68 bytes
}
```

**Memory layout after encoding:**

```
ptr:
┌──────────────┬────────────────────────────────┬────────────────────────────────┐
│ ptr + 0x00   │ ptr + 0x04                     │ ptr + 0x24                     │
│              │                                │                                │
│  a9059cbb    │  000000000000000000000000addr   │  0000000000000000amount        │
│  (selector)  │  (address, left-padded to 32)  │  (uint256, 32 bytes)           │
│              │                                │                                │
│◄── 4 bytes ─►│◄──────── 32 bytes ────────────►│◄──────── 32 bytes ────────────►│
└──────────────┴────────────────────────────────┴────────────────────────────────┘
Total: 68 bytes (0x44)
```

Notice the selector occupies only 4 bytes, but `mstore` writes 32 bytes. By shifting `0xa9059cbb` left by 224 bits (`shl(224, 0xa9059cbb)`), the selector lands in the first 4 bytes and the remaining 28 bytes are zeros. The next `mstore` at `ptr + 0x04` overwrites those 28 zero bytes with the address argument — this is intentional and correct. The ABI layout is: bytes 0-3 = selector, bytes 4-35 = arg1, bytes 36-67 = arg2.

**Two memory strategies — where to write the calldata:**

**Strategy 1: FMP-allocated (safe always)**

```solidity
assembly {
    let ptr := mload(0x40)           // read free memory pointer
    mstore(ptr, shl(224, 0xa9059cbb))
    mstore(add(ptr, 0x04), to)
    mstore(add(ptr, 0x24), amount)

    let success := call(gas(), token, 0, ptr, 0x44, 0, 0)
    // ... FMP is intact, Solidity code can run after this
}
```

Use this when Solidity code runs after the assembly block. The free memory pointer stays valid, and nothing is corrupted.

**Strategy 2: Scratch space (0x00 — gas-cheaper, restricted)**

```solidity
assembly {
    mstore(0x00, shl(224, 0xa9059cbb))
    mstore(0x04, to)
    mstore(0x24, amount)

    let success := call(gas(), token, 0, 0x00, 0x44, 0, 0)
    // ⚠️ Scratch space, FMP (0x40), and zero slot (0x60) are overwritten
    // Safe ONLY if no Solidity code reads these afterward
}
```

The [scratch space](2-memory-calldata.md#memory-layout) at 0x00-0x1f is free to use, and Solidity's reserved regions at 0x40 (FMP) and 0x60 (zero slot) can be overwritten if you don't need them. This saves the `mload(0x40)` read and avoids memory expansion if memory hasn't grown past 0x80 yet. Solady's SafeTransferLib uses this approach — every byte of gas counts in hot paths.

> **🔗 Connection:** Module 2 explained [memory layout](2-memory-calldata.md#memory-layout) and the [safety rules](2-memory-calldata.md#free-memory-pointer) for scratch space vs FMP. The proxy forwarding preview in M2 wrote to offset 0 for the same reason — the function returns or reverts immediately, so memory corruption doesn't matter.

💻 **Quick Try:**

Deploy a simple counter contract in Remix, then call it from assembly:

```solidity
contract Counter {
    uint256 public count;
    function increment() external { count++; }
    function getCount() external view returns (uint256) { return count; }
}

contract Caller {
    function callIncrement(address counter) external {
        assembly {
            // Encode increment() — selector only, no arguments
            mstore(0x00, shl(224, 0xd09de08a)) // increment() selector

            let success := call(gas(), counter, 0, 0x00, 0x04, 0, 0)
            if iszero(success) { revert(0, 0) }
        }
    }

    function readCount(address counter) external view returns (uint256 result) {
        assembly {
            // Encode getCount() — selector only
            mstore(0x00, shl(224, 0xa87d942c)) // getCount() selector

            let success := staticcall(gas(), counter, 0x00, 0x04, 0x00, 0x20)
            if iszero(success) { revert(0, 0) }

            result := mload(0x00) // return data was written to offset 0
        }
    }
}
```

Deploy both. Call `callIncrement`, then `readCount`. The count increases — you just made an external call entirely in assembly.

#### ⚠️ Common Mistakes

**Mistake 1: Forgetting to shift the selector**

```solidity
// WRONG — mstore writes 32 bytes, so 0xa9059cbb lands at bytes 28-31
mstore(0x00, 0xa9059cbb)
// Memory at 0x00: 00000000000000000000000000000000000000000000000000000000a9059cbb
// Selector should be at bytes 0-3, not 28-31

// CORRECT — shift left by 224 bits to position selector in bytes 0-3
mstore(0x00, shl(224, 0xa9059cbb))
// Memory at 0x00: a9059cbb00000000000000000000000000000000000000000000000000000000
```

Without the shift, the first 4 bytes of calldata are `0x00000000` — the target contract sees no valid selector and hits its fallback (or reverts).

**Mistake 2: Wrong calldata size**

```solidity
// WRONG — transfer takes 2 args (64 bytes) + selector (4 bytes) = 68, not 64
call(gas(), token, 0, ptr, 0x40, 0, 0)  // 0x40 = 64 bytes — missing 4 bytes

// CORRECT — 4 + 32 + 32 = 68 bytes = 0x44
call(gas(), token, 0, ptr, 0x44, 0, 0)
```

If you pass too few bytes, the target contract reads zeros for the missing argument bytes. If you pass too many, the extra bytes are ignored — but you waste gas on larger calldata.

---

<a id="call-lifecycle"></a>
### 💡 Concept: The Call Lifecycle: Encode, Call, Check, Decode

**Why this matters:** Every external call in assembly follows the same 4-step pattern. Once you internalize this template, you can read any production code's external call block — Solady, OpenZeppelin, Uniswap — because they all follow it.

**The 4-step template:**

```solidity
assembly {
    // ── Step 1: Encode calldata in memory ──
    let ptr := mload(0x40)
    mstore(ptr, shl(224, SELECTOR))
    mstore(add(ptr, 0x04), arg1)
    // ... more args at 0x24, 0x44, etc.
    let argsSize := 0x24  // 4 + 32 = 36 bytes for 1 arg

    // ── Step 2: Make the call ──
    let success := call(gas(), target, 0, ptr, argsSize, 0x00, 0x20)
    //                   │      │      │  │    │         │     │
    //                   │      │      │  │    │         │     └─ retSize: expect 32 bytes
    //                   │      │      │  │    │         └─ retOffset: write to 0x00
    //                   │      │      │  │    └─ argsSize
    //                   │      │      │  └─ argsOffset
    //                   │      │      └─ value (0 = no ETH)
    //                   │      └─ target address
    //                   └─ gas to forward

    // ── Step 3: Check success ──
    if iszero(success) {
        // Bubble revert data from the sub-call
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
    }

    // ── Step 4: Decode return data ──
    let result := mload(0x00)  // retOffset from step 2
}
```

This template handles the common case: encode arguments, call the target, revert if it fails, read the return value. Every variation in this module is a modification of these 4 steps.

**The retOffset/retSize optimization — two approaches:**

When you know the return size in advance (a `uint256` is always 32 bytes), you can have the EVM write it directly to memory during the CALL:

```
Approach A: Use retOffset/retSize in CALL (known return size)
──────────────────────────────────────────────────────────────
call(gas(), target, 0, ptr, argsSize, 0x00, 0x20)
                                       ▲     ▲
                                       │     └─ 32 bytes of return data
                                       └─ written to memory offset 0x00

Result: mload(0x00) gives you the return value immediately.
No RETURNDATACOPY needed.


Approach B: Use RETURNDATACOPY after (unknown return size)
──────────────────────────────────────────────────────────
call(gas(), target, 0, ptr, argsSize, 0, 0)   // retSize = 0
                                       ▲  ▲
                                       │  └─ don't write anything
                                       └─ ignored

// Check how much data came back
let rds := returndatasize()

// Copy it to memory
returndatacopy(0x00, 0, rds)

Result: memory at 0x00 has the full return data, whatever size it was.
```

Use Approach A when the return type is fixed (single uint256, bool, address). Use Approach B when the return type is dynamic (bytes, string, arrays) or when you don't know what the callee returns.

**STATICCALL for read-only calls:**

When calling view or pure functions, use `staticcall` instead of `call`. It has 6 arguments (no `value` parameter) and guarantees the callee cannot modify state. If the callee tries to write storage, emit events, or send ETH, the EVM reverts automatically.

```solidity
// Reading a balance — staticcall is correct here
let success := staticcall(gas(), token, ptr, 0x24, 0x00, 0x20)

// Writing a transfer — must use call, staticcall would revert
let success := call(gas(), token, 0, ptr, 0x44, 0x00, 0x20)
```

The gas cost is identical to CALL (minus the value-transfer logic). Use staticcall whenever the target function doesn't modify state — it's both an optimization and a safety guarantee.

> **🔗 Connection:** Module 1 covered the [stack signatures](1-evm-fundamentals.md#call-signatures) for CALL (7 args), STATICCALL (6 args), and DELEGATECALL (6 args). M1 also covered the return value semantics: the opcode pushes `1` (success) or `0` (failure) onto the stack. It does NOT revert the caller on failure — you must check explicitly.

#### 🔗 DeFi Pattern Connection

**Where the 4-step call lifecycle appears in DeFi:**

1. **Oracle price reads** — Every Chainlink integration uses `staticcall` to read `latestRoundData()`. The return data is 5 packed `uint256` values (160 bytes). Protocols decode specific offsets to extract `answer` and `updatedAt`.

2. **Token transfers** — Every DeFi protocol calls `transfer()` or `transferFrom()` on ERC-20 tokens. The call lifecycle is the skeleton; the [SafeERC20 pattern](#safe-erc20) (Section 2) adds safety for non-compliant tokens.

3. **Flash loan callbacks** — Aave/Uniswap lend tokens, then call a callback on the borrower's contract. The callback's return value is checked to confirm the borrower repaid. The call lifecycle is the same: encode → call → check.

4. **Router swap paths** — DEX aggregators (1inch, Paraswap) loop through a series of pool swaps. Each iteration is one call lifecycle: encode swap calldata → call pool → check success → decode output amount → use it as input for the next swap.

---

<a id="decoding-returndata"></a>
### 💡 Concept: Decoding Return Data

**Why this matters:** Making the call is half the job. Reading what came back is the other half. Production code must handle single values, tuples of values, and dynamically-sized data — each with a different decoding strategy.

**Single value — the simple case:**

When you set `retOffset` and `retSize` in the call itself, the return data is already in memory:

```solidity
// Call returns a single uint256
let success := staticcall(gas(), target, ptr, 0x24, 0x00, 0x20)
let result := mload(0x00)  // the uint256 return value
```

This works for `uint256`, `address`, `bool`, `bytes32` — any type that fits in exactly 32 bytes.

**Multiple values — fixed-size tuples:**

Chainlink's `latestRoundData()` returns 5 values: `(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)`. Each occupies 32 bytes in the return data (ABI encoding pads smaller types to 32).

```solidity
assembly {
    let ptr := mload(0x40)
    // Encode: latestRoundData() has no arguments, just the selector
    mstore(ptr, shl(224, 0xfeaf968c))  // latestRoundData() selector

    // 5 return values × 32 bytes = 160 bytes (0xa0)
    let success := staticcall(gas(), oracle, ptr, 0x04, 0x00, 0xa0)
    if iszero(success) { revert(0, 0) }

    // Decode specific values by offset:
    // let roundId   := mload(0x00)   // offset 0x00 — roundId
    let answer       := mload(0x20)   // offset 0x20 — the price
    // let startedAt := mload(0x40)   // offset 0x40
    let updatedAt    := mload(0x60)   // offset 0x60 — staleness check
    // let answeredIn := mload(0x80)  // offset 0x80
}
```

**Memory layout after a 5-value return:**

```
0x00: ┌──────────────┐
      │   roundId    │  (bytes 0-31)
0x20: ├──────────────┤
      │   answer     │  (bytes 32-63)   ← the price
0x40: ├──────────────┤
      │  startedAt   │  (bytes 64-95)
0x60: ├──────────────┤
      │  updatedAt   │  (bytes 96-127)  ← staleness check
0x80: ├──────────────┤
      │ answeredInRnd│  (bytes 128-159)
0xa0: └──────────────┘
```

You only `mload` the offsets you need. Skipping unused values costs nothing — the data is already in memory from the `staticcall`.

> **⚠️ Note:** Writing 160 bytes to offset 0x00 overwrites the scratch space (0x00-0x1f), the free memory pointer (0x40), and the zero slot (0x60). If Solidity code runs after this assembly block, those values are corrupted. Either restore them or allocate from the FMP instead.

**Dynamic return data — unknown size:**

When you don't know how much data the callee will return (or when it returns `bytes`, `string`, or arrays), use Approach B — set `retSize = 0` in the call and use `RETURNDATACOPY` afterward:

```solidity
assembly {
    let success := staticcall(gas(), target, ptr, argsSize, 0, 0)
    if iszero(success) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
    }

    let rds := returndatasize()
    let dest := mload(0x40)          // allocate from FMP
    mstore(0x40, add(dest, rds))     // advance FMP
    returndatacopy(dest, 0, rds)     // copy return data to allocated memory
    // Now memory[dest .. dest+rds-1] has the return data
}
```

`RETURNDATACOPY(destOffset, srcOffset, size)` copies `size` bytes from the return data buffer (starting at `srcOffset`) to memory (starting at `destOffset`). If `srcOffset + size > RETURNDATASIZE`, the EVM reverts — you cannot read beyond available return data. Always check `returndatasize()` before copying.

#### 🔍 Deep Dive: Decoding a `bytes` Return Value

When a function returns `bytes memory`, the return data is ABI-encoded with an indirection layer:

```
Offset in return data:
0x00: ┌───────────────────────────────────────┐
      │  0x0000...0020                        │  Offset pointer (points to 0x20)
0x20: ├───────────────────────────────────────┤
      │  0x0000...000a                        │  Length: 10 bytes
0x40: ├───────────────────────────────────────┤
      │  48656c6c6f576f726c6400000000000000...│  Data: "HelloWorld" + 22 zero-padding bytes
0x60: └───────────────────────────────────────┘
```

The layout:
1. **Offset pointer** (32 bytes at 0x00): says "the actual bytes data starts at offset 0x20 within this return data"
2. **Length** (32 bytes at 0x20): the byte length of the data (10 in this example)
3. **Data** (starting at 0x40): the raw bytes, right-padded to a 32-byte boundary

To decode in assembly:

```solidity
assembly {
    let success := staticcall(gas(), target, ptr, argsSize, 0, 0)
    if iszero(success) { revert(0, 0) }

    let rds := returndatasize()
    returndatacopy(0x00, 0, rds)

    // Read the offset pointer
    let offset := mload(0x00)         // = 0x20

    // Read the length at that offset
    let length := mload(offset)       // = 10

    // The actual bytes start at offset + 32
    let dataStart := add(offset, 0x20) // = 0x40

    // Now memory[dataStart .. dataStart+length-1] contains the raw bytes
}
```

This is the same ABI encoding pattern Module 2 covered for [dynamic calldata types](2-memory-calldata.md#dynamic-types) — but in reverse. There you decoded incoming calldata; here you decode outgoing return data. The offset/length/data structure is identical.

#### ⚠️ Common Mistakes

**Mistake: Assuming return data persists across calls**

```solidity
assembly {
    // First call
    let s1 := staticcall(gas(), oracle, ptr1, 0x04, 0x00, 0x20)
    let price := mload(0x00)

    // Second call — this OVERWRITES the return data buffer
    let s2 := staticcall(gas(), token, ptr2, 0x24, 0x00, 0x20)
    let balance := mload(0x00)

    // ⚠️ price is still valid (it was read before the second call)
    // But if you tried to use RETURNDATACOPY here to get the oracle's
    // return data, you'd get the token's return data instead.
}
```

Each external call replaces the previous return data buffer. `RETURNDATASIZE` and `RETURNDATACOPY` always refer to the *most recent* call's return data. If you need data from multiple calls, copy each call's return data to a separate memory region before making the next call.

<a id="exercise1"></a>
## 🎯 Build Exercise: CallEncoder

**Workspace:**
- Implementation: [`workspace/src/part4/module5/exercise1-call-encoder/CallEncoder.sol`](../workspace/src/part4/module5/exercise1-call-encoder/CallEncoder.sol)
- Tests: [`workspace/test/part4/module5/exercise1-call-encoder/CallEncoder.t.sol`](../workspace/test/part4/module5/exercise1-call-encoder/CallEncoder.t.sol)

Practice the 4-step call lifecycle from scratch: encode calldata in memory, make the call (CALL or STATICCALL), check success, decode return data. A `MockTarget` contract is provided with three functions to call — you write the assembly that talks to it.

**What's provided:**
- Function signatures with parameter names and return types
- Error selector for `CallFailed()` (0x3204506f)
- Selector values for all target functions in the TODO comments
- `MockTarget` with `deposit(address,uint256)`, `getBalance(address)`, and `getTriple(uint256)`

**3 TODOs:**

1. **`callWithValue(address target, address account, uint256 tag)`** — Encode calldata for `deposit(address,uint256)` into scratch space (selector + 2 args = 68 bytes), then CALL with `callvalue()` to forward ETH. Check success and bubble revert data on failure.
2. **`staticRead(address target, address account)`** — Encode calldata for `getBalance(address)` (selector + 1 arg = 36 bytes), STATICCALL with the return slot pointed at scratch space (retSize = 32), and decode the single `uint256` result. Revert with `CallFailed()` on failure.
3. **`multiRead(address target, uint256 x)`** — Encode calldata for `getTriple(uint256)`, STATICCALL with FMP-allocated output space (3 × 32 = 96 bytes — too large for scratch space), and decode three `uint256` return values from consecutive memory slots.

**🎯 Goal:** Internalize the encode → call → check → decode template so it becomes second nature. By the end, you should be able to construct an assembly call to any function given its selector and argument types.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module5/exercise1-call-encoder/*"
```

---

## 📋 Key Takeaways: Building Calls by Hand

After this section, you should be able to:

- Encode calldata in memory for any function call: selector (shifted left by 224 bits) at offset 0, arguments at offsets 0x04, 0x24, 0x44, etc.
- Choose between scratch space (0x00) and FMP-allocated memory for calldata encoding, understanding when each is safe
- Apply the 4-step call lifecycle (encode → call → check → decode) as a reusable template for every external call
- Decode single values, multi-value tuples, and dynamic `bytes` return data using the correct strategy (retSize in the call vs RETURNDATACOPY after)
- Explain why return data doesn't persist across calls and how to handle multiple sequential calls

<details>
<summary>Check your understanding</summary>

- **Calldata encoding for calls**: Write `shl(224, selector)` at the memory offset, then arguments at +0x04, +0x24, +0x44, etc. For scratch space encoding (offset 0x00), this is safe when the call immediately follows. For FMP-allocated memory, bump the free memory pointer after allocating.
- **Scratch space vs FMP**: Scratch space (0x00-0x3f) is cheaper (no FMP bookkeeping) and safe when the encoded calldata is consumed immediately by the next CALL opcode. Use FMP-allocated memory when you need the data to survive across multiple Solidity-level operations or when the calldata exceeds 64 bytes.
- **4-step call lifecycle**: (1) Encode calldata in memory, (2) execute CALL/STATICCALL/DELEGATECALL, (3) check the success flag, (4) decode return data. This template applies to every external call in assembly, regardless of the target.
- **Return data decoding**: For known-size returns, pass `retSize` in the CALL opcode and read directly from the output offset. For dynamic returns, set `retSize` to 0 and use RETURNDATACOPY after the call. RETURNDATASIZE gives the actual length.
- **Return data buffer lifetime**: The return data buffer is overwritten by every subsequent CALL, STATICCALL, DELEGATECALL, or CREATE. If you need data from a previous call, copy it to memory with RETURNDATACOPY before making the next call.

</details>

---

## 💡 Error Handling & Safety Patterns

Making calls that succeed is the easy part. Production code must handle failure gracefully — bubbling errors so callers see what went wrong, tolerating non-compliant tokens that break the ABI standard, defending against malicious return data, and budgeting gas so untrusted callees can't grief you. This section covers the patterns that separate production assembly from toy examples.

<a id="error-propagation"></a>
### 💡 Concept: Error Propagation: Bubbling Revert Data

**Why this matters:** When your contract calls another contract and it reverts, your contract does NOT automatically revert. Execution continues — the CALL opcode pushes `0` onto the stack and the revert data sits in the return data buffer, waiting for you to do something with it. If you ignore the failure, the caller has no idea anything went wrong. If you revert without forwarding the data, debuggers and UIs see a generic revert with no explanation.

**The standard bubble-up pattern:**

```solidity
assembly {
    let success := call(gas(), target, 0, argsPtr, argsSize, 0, 0)

    if iszero(success) {
        // Copy the callee's revert data to memory
        let rds := returndatasize()
        returndatacopy(0x00, 0, rds)

        // Revert with the same data — the original error propagates upward
        revert(0x00, rds)
    }
}
```

This forwards the exact revert data from the callee: a custom error like `InsufficientBalance()`, a `require` message encoded as `Error(string)`, or a `Panic(uint256)` from an assert. The caller, debugger, and frontend all see the original error as if it came from your contract.

This is what Solidity's low-level `.call()` expects you to do manually. And it's exactly what Solidity's `try/catch` compiles to under the hood — check the return value, branch on failure, optionally decode the error.

**Decoding the error selector — routing different errors:**

Sometimes you need to react differently to different errors. For example, a DEX aggregator might try multiple pools and only revert if *all* of them fail:

```solidity
assembly {
    let success := call(gas(), pool, 0, ptr, argsSize, 0, 0)

    if iszero(success) {
        let rds := returndatasize()

        // Need at least 4 bytes for an error selector
        if lt(rds, 4) {
            // No selector — raw revert, bubble it
            revert(0x00, 0)
        }

        // Copy first 4 bytes to read the selector
        returndatacopy(0x00, 0, 4)
        let errorSelector := shr(224, mload(0x00))

        // Route based on error type
        switch errorSelector
        case 0xfb8f41b2 {  // InsufficientLiquidity()
            // Try next pool instead of reverting
            // ... continue to next iteration
        }
        default {
            // Unknown error — bubble it
            returndatacopy(0x00, 0, rds)
            revert(0x00, rds)
        }
    }
}
```

The selector extraction — `shr(224, mload(0x00))` — is the same pattern Module 4 used for function dispatch, but in reverse: there you extracted selectors from incoming calldata, here you extract them from incoming revert data.

**The `revert(0, 0)` anti-pattern:**

```solidity
// BAD — empty revert gives no debugging info
if iszero(success) { revert(0, 0) }

// GOOD — bubble the callee's error data
if iszero(success) {
    returndatacopy(0, 0, returndatasize())
    revert(0, returndatasize())
}
```

Empty reverts make debugging impossible. Always bubble the revert data, or encode your own custom error (Module 4's error encoding patterns). The only exception is when the callee is untrusted and might return malicious data — in that case, use the bounded copy from the [returnbomb defense](#returnbomb) below.

#### 🔗 DeFi Pattern Connection

**Where error propagation matters in DeFi:**

1. **DEX aggregator routers** — 1inch and Paraswap route swaps through multiple DEXs. If one pool reverts with `InsufficientLiquidity`, the router catches it and tries the next pool. Only if all pools fail does the router bubble the last error to the user. This requires decoding error selectors in assembly to distinguish recoverable errors from fatal ones.

2. **Multicall contracts** — Uniswap's Multicall allows batched calls where individual calls can fail without reverting the entire batch. The contract catches each sub-call's revert data and returns it as part of the results array, letting the frontend decide how to handle partial failures.

3. **Proxy contracts** — Every proxy must bubble revert data from the implementation. If the implementation reverts with `Unauthorized()`, the proxy must forward that exact error — not swallow it or replace it with a generic revert.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What happens when a sub-call reverts in assembly?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "The success flag is 0 and you should check it."
   - Great answer: "The CALL opcode pushes 0 but execution continues in the caller. The revert data sits in the return data buffer — accessible via RETURNDATASIZE and RETURNDATACOPY. You must explicitly copy and re-revert with that data to propagate the error. If you forget the check entirely, the call silently fails and execution continues with stale or zero data. Solidity's `try/catch` compiles to exactly this pattern — check success, branch, optionally decode the error selector."

   </details>

**Interview Red Flags:**
- 🚩 Not knowing that sub-call failures don't automatically propagate in assembly
- 🚩 Using `revert(0, 0)` instead of bubbling the callee's error data
- 🚩 Confusing the Yul `revert` built-in (which stops execution) with Solidity's `revert` statement (which also encodes an error)

**Pro tip:** When discussing error handling in interviews, mention that the return data buffer is shared — each call overwrites the previous one. This shows you understand the EVM's execution frame model, not just the Solidity abstraction.

---

<a id="safe-erc20"></a>
### 💡 Concept: The SafeERC20 Pattern

**Why this matters:** This is the single most common assembly pattern in all of DeFi. Every protocol that handles ERC-20 tokens needs it. Part 2 Module 1 covered SafeERC20 at the Solidity level and said these libraries "use low-level calls to check return data length." Now you understand exactly what that means — you can read and write the assembly yourself.

**The problem:**

The ERC-20 standard says `transfer(address,uint256)` must return `bool`. But several major tokens — most notably USDT (Tether), the largest stablecoin by market cap — don't return anything. Their `transfer` function has no `return` statement.

When Solidity calls a function that should return `bool`, the ABI decoder expects exactly 32 bytes of return data. If it gets 0 bytes (USDT), the decoder reverts. So this innocent-looking code breaks with USDT:

```solidity
// Reverts when token is USDT — ABI decoder expects 32 bytes, gets 0
require(IERC20(token).transfer(to, amount));
```

This is why SafeERC20 exists. And its core is an assembly pattern.

**The solution — step by step:**

```solidity
function safeTransfer(address token, address to, uint256 amount) internal {
    assembly {
        // Step 1: Encode transfer(address,uint256) calldata
        mstore(0x00, shl(224, 0xa9059cbb))  // transfer selector
        mstore(0x04, to)                      // recipient
        mstore(0x24, amount)                  // amount

        // Step 2: Call the token
        let success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)

        // Step 3: Validate — success AND (no return data OR return data is true)
        if iszero(
            and(
                success,
                or(iszero(returndatasize()), eq(mload(0x00), 1))
            )
        ) {
            revert(0x00, 0x00)
        }
    }
}
```

The magic is in Step 3: `and(success, or(iszero(returndatasize()), eq(mload(0x00), 1)))`. This single expression handles every token behavior.

#### 🔍 Deep Dive: Breaking Down the Boolean Expression

The compound expression `and(success, or(iszero(returndatasize()), eq(mload(0x00), 1)))` evaluates in this order (inside out):

```
Inner checks:
  A = iszero(returndatasize())     "Did the token return nothing?"
  B = eq(mload(0x00), 1)           "Did the token return true?"

Combined:
  C = or(A, B)                     "Either no return data OR return data is true"
  D = and(success, C)              "Call succeeded AND return data is acceptable"

Final:
  iszero(D)                        "If D is false → revert"
```

**Truth table — every possible token behavior:**

```
Token behavior       │ success │ returndatasize │ mload(0x00) │ A │ B │ C │ D │ Revert?
─────────────────────┼─────────┼────────────────┼─────────────┼───┼───┼───┼───┼────────
Call reverts         │    0    │   (any)        │   (any)     │ — │ — │ — │ 0 │ YES ✓
Returns nothing      │    1    │      0         │ (stale/0)   │ 1 │ — │ 1 │ 1 │ NO  ✓
(USDT, BNB)          │         │                │             │   │   │   │   │
Returns true (1)     │    1    │     32         │      1      │ 0 │ 1 │ 1 │ 1 │ NO  ✓
(standard ERC-20)    │         │                │             │   │   │   │   │
Returns false (0)    │    1    │     32         │      0      │ 0 │ 0 │ 0 │ 0 │ YES ✓
(transfer failed)    │         │                │             │   │   │   │   │
```

Walk through each row:

- **Call reverts:** `success = 0`, so `and(0, anything) = 0` → revert. Correct — the transfer failed.
- **Returns nothing (USDT):** `success = 1`, `returndatasize() = 0`, so `iszero(0) = 1`, `or(1, anything) = 1`, `and(1, 1) = 1` → don't revert. Correct — USDT's transfer succeeded (it just didn't say so).
- **Returns true:** `success = 1`, `returndatasize() = 32`, `mload(0x00) = 1`, so `iszero(32) = 0`, `eq(1, 1) = 1`, `or(0, 1) = 1`, `and(1, 1) = 1` → don't revert. Correct — standard token confirmed success.
- **Returns false:** `success = 1`, `returndatasize() = 32`, `mload(0x00) = 0`, so `iszero(32) = 0`, `eq(0, 1) = 0`, `or(0, 0) = 0`, `and(1, 0) = 0` → revert. Correct — the token reported failure.

**Why `or` and not `||`:** Yul has no short-circuit boolean operators. `or(a, b)` is a bitwise OR that evaluates both operands. This is fine here — both `iszero(returndatasize())` and `eq(mload(0x00), 1)` are cheap (no state changes, no side effects). In Solidity, `||` short-circuits to save gas on the second operand, but in Yul you use `or` and accept both evaluations.

**A subtle detail — what does `mload(0x00)` return when there's no return data?**

When `returndatasize()` is 0, the CALL's `retSize = 0x20` parameter told the EVM to write 32 bytes of return data to memory at offset 0x00. But there were 0 bytes to write — so memory at 0x00 retains whatever was there before. In this code, that's the selector from Step 1: `shl(224, 0xa9059cbb)`, which is a large non-zero value. But it doesn't matter — the `iszero(returndatasize())` check catches this case *before* the `eq(mload(0x00), 1)` check is relevant. The `or` means: if `A` is true (no return data), the whole expression is true regardless of `B`.

**Solady vs OpenZeppelin — two assembly approaches:**

| Aspect | Solady SafeTransferLib | OpenZeppelin SafeERC20 (v5) |
|---|---|---|
| Memory | Scratch space (0x00) — no FMP allocation | FMP-allocated via `Address.functionCallWithValue` |
| Code size check | None — if `token` is an EOA (no code), `call` succeeds with 0 return data, which passes the `iszero(returndatasize())` check | Checks `address(token).code.length > 0` — reverts if token has no code |
| Gas | Cheaper — fewer operations, no memory expansion | Slightly more expensive |
| Safety trade-off | If you accidentally pass an EOA address, the "transfer" silently succeeds (no code = no revert, no return data = passes check). Solady documents this as a known behavior — the caller is responsible for passing a valid token address. | Catches the EOA case by checking code size first. Safer for careless callers, costs more gas. |

**Why the code size check matters — the EVM behavior underneath:**

When you CALL an address with no deployed code (an EOA, or a contract that hasn't been deployed yet), the EVM does *not* revert. The call succeeds with `returndatasize() = 0`. Walk through the SafeERC20 check: `success = 1`, `iszero(0) = 1`, `or(1, anything) = 1`, `and(1, 1) = 1` — the "transfer" silently passes. No tokens move (there's no code to execute), but your contract thinks it succeeded.

This is why OZ checks `extcodesize(token) > 0` before the call — it catches the case where `token` is an EOA or hasn't been deployed. Solady skips this check intentionally: the 2,600 gas for a cold `EXTCODESIZE` is expensive, and Solady expects the caller to validate token addresses before calling `safeTransfer`. Both choices are valid — know which trade-off your protocol makes.

Both are production-quality. Solady is the gas-optimized choice for protocols that validate token addresses elsewhere. OpenZeppelin is the safer default when the token address might be user-supplied.

💻 **Quick Try:**

Test the difference between standard and non-returning tokens. In Remix, deploy:

```solidity
// Standard token — returns true
contract StandardToken {
    mapping(address => uint256) public balanceOf;
    constructor() { balanceOf[msg.sender] = 1000e18; }
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// USDT-like — no return value
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    constructor() { balanceOf[msg.sender] = 1000e18; }
    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        // No return statement!
    }
}
```

Try calling `NoReturnToken.transfer()` through a normal Solidity interface (`IERC20(token).transfer(...)`) — it reverts. Then call it using the SafeERC20 assembly pattern — it succeeds.

<a id="how-to-study"></a>
#### 📖 How to Study Solady SafeTransferLib

1. **Start with `safeTransfer`** — it's the simplest function. Find the `and(success, or(...))` pattern.
2. **Note the scratch space usage** — calldata is encoded at 0x00. No `mload(0x40)`, no FMP allocation.
3. **Compare `safeTransfer` and `safeTransferFrom`** — the only differences are the selector (`0xa9059cbb` vs `0x23b872dd`) and an extra argument (the `from` address). The validation logic is identical.
4. **Read `forceApprove`** — this handles USDT's `approve` quirk: USDT requires you to set approval to 0 before setting a new non-zero approval. `forceApprove` tries the normal `approve` first; if it fails, it approves to 0, then approves to the desired amount. This is the SafeERC20 pattern chained with retry logic.
5. **Don't get stuck on:** the `BALANCE` opcode trick Solady uses for native ETH transfers — that's a separate gas optimization unrelated to the SafeERC20 pattern.

> **Source:** [Solady SafeTransferLib](https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Why can't you just use `require(token.transfer(to, amount))`?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "USDT doesn't return a bool, so the ABI decoder reverts."
   - Great answer: "Several major tokens — USDT, BNB, and others — omit the `bool` return from `transfer`. The Solidity ABI decoder expects exactly 32 bytes and reverts when it gets 0. SafeERC20 uses assembly to bypass the ABI decoder: make the low-level `call`, then check `and(success, or(iszero(returndatasize()), eq(mload(0x00), 1)))`. This accepts three cases: call reverted (fail), returned true (standard success), returned nothing (USDT success). Solady takes this further by writing calldata to scratch space for gas savings and skipping the `extcodesize` check that OpenZeppelin includes."

   </details>

This is arguably the number one assembly question in DeFi interviews. If you can explain the truth table from memory, you demonstrate both assembly fluency and practical DeFi awareness.

**Interview Red Flags:**
- 🚩 Not knowing that USDT doesn't return `bool`
- 🚩 Saying "just use SafeERC20" without being able to explain what it does under the hood
- 🚩 Not knowing the Solady vs OpenZeppelin trade-off (code size check)

**Pro tip:** If the interviewer asks about token integration edge cases, mention `forceApprove` for USDT's approval quirk (must approve to 0 first). It shows you've dealt with real token weirdness, not just textbook ERC-20.

---

<a id="returnbomb"></a>
### 💡 Concept: The Returnbomb Attack

**Why this matters:** The error bubbling pattern from the previous section — `returndatacopy(0, 0, returndatasize())` — has a hidden vulnerability. If the callee is untrusted, it can return an enormous amount of data, causing the caller to spend all its gas on memory expansion. This is the returnbomb attack.

**The attack:**

When you write `returndatacopy(0, 0, returndatasize())`, the EVM expands memory to fit the return data. Memory expansion cost is quadratic — it grows slowly at first, then explodes:

```
Return data size  │  Memory expansion gas  │  Context
──────────────────┼────────────────────────┼──────────────────────────
32 bytes          │  ~3 gas                │  Normal return value
1 KB              │  ~100 gas              │  A revert message
10 KB             │  ~3,000 gas            │  Unusually large
100 KB            │  ~60,000 gas           │  Getting expensive
1 MB              │  ~2,100,000 gas        │  Exceeds most gas limits
10 MB             │  ~200,000,000 gas      │  Impossible — block limit
```

A malicious contract can trivially return megabytes of data:

```solidity
// Malicious contract — returns 1MB of garbage data
contract ReturnBomb {
    fallback() external payable {
        assembly {
            // Expand memory to 1MB and return it all
            return(0, 0x100000)  // 1,048,576 bytes
        }
    }
}
```

If your contract calls this and then does `returndatacopy(0, 0, returndatasize())`, you're forced to allocate 1MB of memory, consuming ~2.1 million gas. Your transaction runs out of gas and reverts — even though the call itself "succeeded."

**Defense 1: Bound the RETURNDATACOPY**

Cap the amount of data you copy from the return buffer:

```solidity
assembly {
    let success := call(gas(), target, 0, ptr, argsSize, 0, 0)

    if iszero(success) {
        let rds := returndatasize()

        // Cap at 256 bytes — enough for any reasonable error message
        if gt(rds, 0x100) { rds := 0x100 }

        returndatacopy(0x00, 0, rds)
        revert(0x00, rds)
    }
}
```

256 bytes is enough for any custom error (4 bytes selector + parameters) or `Error(string)` with a reasonable message. Error data beyond 256 bytes is almost certainly adversarial.

**Defense 2: Use retOffset/retSize in the CALL itself**

```solidity
// The CALL writes at most 32 bytes to memory — regardless of actual return data size
let success := call(gas(), target, 0, ptr, argsSize, 0x00, 0x20)
```

Even if the callee returns 1MB, the EVM only writes the first 32 bytes to memory at offset 0x00. The full return data buffer still exists (RETURNDATASIZE reports the real size), but your memory hasn't expanded. You only expand memory if you explicitly call RETURNDATACOPY with a large size.

This is why the SafeERC20 pattern uses `retSize = 0x20` in the call: `call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)`. It caps the memory write to 32 bytes. If the token returns 1MB of data (unlikely for a token, but consider a malicious wrapper), memory stays bounded.

**Where returnbombs matter in DeFi:**

- **Flash loan callbacks** — The lending protocol calls a user-supplied callback address. A malicious borrower could deploy a contract that returns enormous data, causing the lender's `returndatacopy` to OOM.
- **Hook systems** — Uniswap V4 hooks call user-deployed contracts. Unbounded return data could grief the pool contract.
- **Liquidation bots** — If the liquidation flow calls any function on the borrower's contract (e.g., to check a callback), the borrower could deploy a returnbomb to prevent liquidation by making the liquidation transaction run out of gas.
- **Any protocol calling untrusted addresses** — The rule is simple: if you don't control the callee's code, bound your RETURNDATACOPY.

---

<a id="gas-forwarding"></a>
### 💡 Concept: Gas Forwarding in Practice

**Why this matters:** Module 1 introduced the 63/64 gas forwarding rule (EIP-150) — at each CALL, the EVM retains 1/64 of the remaining gas and forwards the rest. Here we apply that rule: how to decide how much gas to forward, when to use `gas()` vs a fixed limit, and why the wrong choice creates a gas griefing vulnerability.

**When to use `gas()` — forward all available gas:**

```solidity
// Trusted contract — forward everything
let success := call(gas(), trustedTarget, 0, ptr, size, 0, 0x20)
```

Use `gas()` when calling your own protocol's contracts or known, audited implementations. The callee needs as much gas as possible to execute its logic, and you trust it not to waste gas maliciously.

This is also correct for proxy forwarding — the proxy must forward maximum gas so the implementation contract can execute whatever the user intended.

**When to use a fixed gas limit — untrusted callbacks:**

```solidity
// Untrusted callback — cap the gas
let success := call(50000, untrustedCallback, 0, ptr, size, 0, 0)
```

Use a fixed limit when calling untrusted addresses: flash loan callbacks, user-deployed hooks, arbitrary contract interactions. The fixed limit prevents two attacks:

1. **Gas griefing:** The callee deliberately consumes all forwarded gas and reverts. Due to the 63/64 rule, the caller only has 1/64 of its original gas left — which may not be enough for cleanup operations (reverting state changes, logging events, refunding tokens).

2. **Gas theft:** The callee burns gas doing nothing useful, wasting the caller's gas budget.

**Computing the minimum gas budget for cleanup:**

If you need `X` gas after a sub-call returns, you need at least `64 × X` gas before making the call:

```
Before call:  total_gas
During call:  sub-call gets 63/64 of total_gas
After call:   caller has 1/64 of total_gas

Need 5,000 gas after the call?
  → Need at least 5,000 × 64 = 320,000 gas before the call

Need 50,000 gas after the call?
  → Need at least 50,000 × 64 = 3,200,000 gas before the call
```

In practice, this means: if your post-call logic includes SSTOREs (20,000 gas each), you need substantial gas reserves. A fixed gas limit for the callback avoids this — you control exactly how much gas the callee gets, and you keep the rest.

**The ETH transfer gas stipend:**

```solidity
// The classic "transfer" — 2300 gas stipend
let success := call(2300, recipient, amount, 0, 0, 0, 0)
```

The 2300 gas stipend was designed to be enough for the recipient to emit a LOG event but not enough for an SSTORE — preventing reentrancy by gas starvation. But this assumption has become fragile: gas repricing (EIP-2929 made cold SLOADs cost 2100 gas) and the increasing complexity of receiving contracts (multisigs, smart wallets) mean 2300 gas is sometimes insufficient even for legitimate recipients.

Modern practice: many protocols now forward all gas (`gas()`) and use reentrancy guards instead of gas starvation for protection:

```solidity
// Modern ETH transfer — forward all gas, protect with reentrancy guard
// (assumes nonReentrant modifier or TSTORE-based guard is in place)
let success := call(gas(), recipient, amount, 0, 0, 0, 0)
```

#### ⚠️ Common Mistakes

**Mistake: Using `gas()` for untrusted callbacks**

```solidity
// DANGEROUS — untrusted callback gets all remaining gas
let success := call(gas(), userCallback, 0, ptr, size, 0, 0)
// If userCallback burns all gas, you have ~1/64 left
// That might not be enough to revert state changes

// SAFER — cap the callback gas, keep reserves for cleanup
let success := call(100000, userCallback, 0, ptr, size, 0, 0)
// userCallback gets 100K gas max
// You keep everything else for post-call logic
```

The fix is simple: know your callee. Trusted → `gas()`. Untrusted → fixed limit.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you prevent gas griefing in a flash loan callback?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "Use a fixed gas limit for the callback."
   - Great answer: "Cap the callback gas to what the borrower's operation reasonably needs — say 500K gas. This keeps enough reserve for the lender's cleanup: verifying the loan was repaid, updating state, handling bad debt. Calculate the minimum reserve as `cleanup_gas_needed × 64` — that's how much you need before the call to guarantee enough after. Also check the `success` return value and revert the entire flash loan if the callback fails, ensuring atomicity."

   </details>

**Interview Red Flags:**
- 🚩 Not knowing what the 63/64 rule is
- 🚩 Thinking `gas()` is always safe because "the EVM handles it"
- 🚩 Not being able to explain why 2300 gas is no longer sufficient for ETH transfers to smart wallets

**Pro tip:** If asked about gas management in interviews, connect the 63/64 rule to real incidents — the KingOfTheEther attack exploited fixed 2300 gas stipends, and modern smart wallets with receive hooks need more gas than that. Showing you understand the historical evolution signals deep EVM knowledge.

<a id="exercise2"></a>
## 🎯 Build Exercise: SafeCaller

**Workspace:**
- Implementation: [`workspace/src/part4/module5/exercise2-safe-caller/SafeCaller.sol`](../workspace/src/part4/module5/exercise2-safe-caller/SafeCaller.sol)
- Tests: [`workspace/test/part4/module5/exercise2-safe-caller/SafeCaller.t.sol`](../workspace/test/part4/module5/exercise2-safe-caller/SafeCaller.t.sol)

Practice the SafeERC20 pattern, error bubbling, and returnbomb defense. The test suite includes a standard ERC-20 mock, a USDT-style non-returning mock, a false-returning mock, and a returnbomb mock — your implementations must handle all four.

**What's provided:**
- Function signatures with parameter names
- Error selectors for `TransferFailed()` (0x90b8ec18) and `TransferFromFailed()` (0x7939f424)
- Selector values for `transfer` and `transferFrom` in the TODO comments
- The truth table from the lesson reproduced in comments
- Mocks: `MockERC20`, `MockNoReturnToken`, `MockReturnBomb`, `MockTarget`

**4 TODOs:**

1. **`bubbleRevert(address target, bytes calldata data)`** — Call a target with arbitrary calldata. On failure, copy and re-revert with the callee's exact revert data. This is the standard error propagation pattern.
2. **`safeTransfer(address token, address to, uint256 amount)`** — The SafeERC20 `transfer` pattern. Must work with standard tokens (returns `true`) AND non-returning tokens (USDT). Uses the compound check: `and(ok, or(iszero(returndatasize()), eq(mload(0x00), 1)))`.
3. **`safeTransferFrom(address token, address from, address to, uint256 amount)`** — Same SafeERC20 pattern but for `transferFrom` with 3 args (100 bytes of calldata instead of 68).
4. **`boundedCall(address target, bytes calldata data)`** — Like `bubbleRevert`, but caps the RETURNDATACOPY at 256 bytes to defend against the returnbomb attack.

**🎯 Goal:** Write the SafeERC20 pattern from memory. If you can implement `safeTransfer` without looking at the lesson, you've internalized the most important assembly pattern in DeFi.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module5/exercise2-safe-caller/*"
```

---

## 📋 Key Takeaways: Error Handling & Safety Patterns

After this section, you should be able to:

- Implement the standard error bubble-up pattern (RETURNDATACOPY + revert) and explain why sub-call failures don't propagate automatically
- Write the SafeERC20 `safeTransfer` pattern from memory and walk through the truth table for all four token behaviors (reverts, returns nothing, returns true, returns false)
- Explain the Solady vs OpenZeppelin trade-off for SafeERC20 (code size check) and when each is appropriate
- Defend against the returnbomb attack by bounding RETURNDATACOPY or using retSize in the CALL itself
- Choose between `gas()` and a fixed gas limit for external calls based on whether the callee is trusted, and compute the minimum gas budget for post-call cleanup

<details>
<summary>Check your understanding</summary>

- **Error bubble-up pattern**: After a failed call (`success == 0`), use `returndatacopy(0, 0, returndatasize())` to copy the revert data to memory, then `revert(0, returndatasize())` to forward it. This preserves the original error selector and parameters so callers and debugging tools see the actual failure reason.
- **SafeERC20 / safeTransfer**: Handles four token behaviors: (1) reverts on failure (standard), (2) returns nothing (USDT-style -- treat as success), (3) returns true (standard success), (4) returns false (non-standard failure signal). The assembly pattern checks `or(iszero(returndatasize()), and(gt(returndatasize(), 31), eq(mload(ptr), 1)))`. Solady skips the code-size check for gas savings; OpenZeppelin includes it for safety.
- **Returnbomb defense**: A malicious callee can return megabytes of data, causing RETURNDATACOPY to consume all the caller's gas via memory expansion. Defend by passing a bounded `retSize` in the CALL opcode itself (limiting what gets written to memory) or by checking `returndatasize()` before copying.
- **Gas budgeting for calls**: Use `gas()` (forward all available gas) for trusted callees. For untrusted callees, pass a fixed gas limit to ensure you retain enough gas for post-call cleanup (error handling, state updates). The 63/64 rule means you always keep 1/64, but complex cleanup may need more -- calculate explicitly.

</details>

---

## 💡 Production Call Patterns

The first two sections taught you how to make calls and handle what comes back. This section covers three patterns you'll encounter in virtually every DeFi protocol: DELEGATECALL for proxies, precompile calls for cryptographic operations, and multicall for batching.

<a id="delegatecall-depth"></a>
### 💡 Concept: DELEGATECALL in Depth

**Why this matters:** Module 2 previewed the proxy forwarding pattern — `calldatacopy` + `delegatecall` + `returndatacopy`. Here we complete that preview: how DELEGATECALL's execution context actually works, why proxy storage layout matters, and how to read OpenZeppelin's Proxy.sol variants.

**CALL vs DELEGATECALL — who owns what:**

Understanding the difference between CALL and DELEGATECALL comes down to one question: *whose storage, whose `msg.sender`, whose `address(this)`?*

```
CALL to Contract B:
┌──────────────────────────────────┐
│ Caller (Contract A)              │
│                                  │
│  msg.sender = EOA                │
│  address(this) = A               │
│  storage: A's storage            │
│                                  │
│  call(gas, B, ...)  ─────────────┼──→  ┌─────────────────────────────┐
│                                  │     │ Callee (Contract B)         │
│                                  │     │                             │
│                                  │     │  msg.sender = A             │
│                                  │     │  address(this) = B          │
│                                  │     │  storage: B's storage       │
│                                  │     └─────────────────────────────┘
└──────────────────────────────────┘

DELEGATECALL to Contract B:
┌──────────────────────────────────┐
│ Caller (Contract A)              │
│                                  │
│  msg.sender = EOA                │
│  address(this) = A               │
│  storage: A's storage            │
│                                  │
│  delegatecall(gas, B, ...)  ─────┼──→  ┌─────────────────────────────┐
│                                  │     │ B's CODE runs, but:         │
│                                  │     │                             │
│                                  │     │  msg.sender = EOA  (kept!)  │
│                                  │     │  address(this) = A (kept!)  │
│                                  │     │  storage: A's storage       │
│                                  │     └─────────────────────────────┘
└──────────────────────────────────┘
```

With DELEGATECALL, Contract B's **code** executes but in **Contract A's context**. Every `sload` and `sstore` touches A's storage. Every `msg.sender` reference sees the original caller, not A. Every `address(this)` returns A's address, not B's.

This is exactly what proxies need: the proxy (A) holds storage and receives calls, while the implementation (B) provides the logic. Users interact with A's address forever, and the team can swap B for a new implementation without changing A's address or storage.

**The full proxy forwarding pattern — annotated:**

Module 2 showed the basic pattern. Here's the production-grade version with every line explained:

```solidity
assembly {
    // 1. Copy entire calldata to memory starting at offset 0
    //    calldatacopy(destOffset, srcOffset, size)
    //    This copies the function selector + all arguments
    calldatacopy(0, 0, calldatasize())

    // 2. DELEGATECALL to implementation
    //    delegatecall(gas, addr, argsOffset, argsSize, retOffset, retSize)
    //    - gas():          forward all remaining gas (trusted implementation)
    //    - impl:           the implementation contract address
    //    - 0:              args start at memory offset 0 (where we just copied)
    //    - calldatasize(): args length = entire calldata
    //    - 0, 0:           don't write return data yet — size unknown
    let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

    // 3. Copy return data to memory at offset 0
    //    The delegatecall is done — we now know the return data size
    //    returndatacopy(destOffset, srcOffset, size)
    returndatacopy(0, 0, returndatasize())

    // 4. Either return or revert with the forwarded data
    //    result = 1 (success) → return the data to the caller
    //    result = 0 (failure) → revert with the same revert data
    switch result
    case 0 { revert(0, returndatasize()) }
    default { return(0, returndatasize()) }
}
```

**Why offset 0 is safe here:**

This pattern writes to memory starting at offset 0, overwriting scratch space (0x00-0x1F), the free memory pointer (0x40), and the zero slot (0x60). Normally that would corrupt Solidity's memory management. But it's safe here because the function either `return`s or `revert`s immediately — no Solidity code runs after this block. The corrupted FMP and zero slot are never read.

If you needed to run Solidity code after the DELEGATECALL (which you almost never do in a proxy), you'd need to allocate memory properly using `mload(0x40)`.

**Storage slot alignment — the critical constraint:**

Because DELEGATECALL executes implementation code against proxy storage, both contracts must agree on storage layout. If the proxy has `owner` at slot 0 and the implementation expects `totalSupply` at slot 0, the implementation will read the owner address as a supply value — corrupted data, potential exploits.

This is why EIP-1967 defines specific, pseudo-random storage slots for proxy admin data:

```
Implementation slot: keccak256("eip1967.proxy.implementation") - 1
    = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

Admin slot: keccak256("eip1967.proxy.admin") - 1
    = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
```

These slots are so far into storage that no normal contract variable will ever collide with them. The `-1` is there so the slot can't be computed as a Solidity mapping key (Solidity computes mapping slots with `keccak256(abi.encode(key, slot))`, which can't produce `keccak256(...) - 1`).

#### 📖 How to Study OpenZeppelin's Proxy Contracts

1. **Start with `Proxy.sol`** — the base. It has one function: `_delegate(address implementation)`. That's the pattern above. Everything else is about *how the implementation address is determined*.

2. **Read `ERC1967Utils.sol`** — the storage slot helpers. `getImplementation()`, `upgradeToAndCall()`. These use the EIP-1967 slots.

3. **Compare the three proxy flavors:**
   - **TransparentUpgradeableProxy** — admin and users hit different code paths (admin calls see `upgradeTo`, user calls are forwarded). Uses `msg.sender == admin` check in fallback.
   - **UUPSUpgradeable** — upgrade logic lives in the *implementation*, not the proxy. The proxy is minimal (just the forwarding pattern). Cheaper to deploy, but the implementation must remember to include upgrade functions.
   - **BeaconProxy** — the implementation address isn't stored in the proxy. Instead, the proxy asks a "beacon" contract for the current implementation. One beacon upgrade updates all proxies that point to it.

4. **Read the tests** — `TransparentUpgradeableProxy.test.js` shows the admin/user split behavior clearly.

5. **Don't get stuck on:** the `_beforeFallback()` hook or the constructor initialization logic — these are safety rails, not the core pattern.

> **Source:** [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol)

#### 🔗 DeFi Pattern Connection

**Where DELEGATECALL proxies appear in DeFi:**

1. **Every upgradeable protocol** — Aave V3, Compound V3, Uniswap governance — all use proxy patterns so they can upgrade logic without migrating state or changing addresses.

2. **Diamond pattern (EIP-2535)** — A single proxy with multiple implementation contracts (called "facets"). The proxy's fallback dispatches by selector to different facets. Used by protocols that need modular upgradeability (e.g., LiFi, Louper).

3. **Minimal proxies (EIP-1167)** — Factory-deployed clones that DELEGATECALL to a shared implementation. Module 4 covered the bytecode pattern. Used by Uniswap V3 (pool clones) and many token launch platforms.

4. **UUPS is becoming standard** — It's cheaper to deploy (smaller proxy bytecode), and teams prefer keeping upgrade logic in the implementation where it can be removed entirely in a future version to make the protocol immutable.

#### ⚠️ Common Mistakes

**Mistake: DELEGATECALL to a contract with `selfdestruct`**

Pre-Dencun (before EIP-6780), `selfdestruct` in a DELEGATECALL destroyed the *caller* (the proxy), not the implementation. This was the attack vector in the Parity wallet hack — a `selfdestruct` was triggered via DELEGATECALL, destroying the library contract that all Parity multisigs depended on, permanently freezing ~$150M in ETH.

Post-Dencun (EIP-6780), `selfdestruct` only works in the same transaction as contract creation. But the lesson remains: audit every function in your implementation for operations that behave differently under DELEGATECALL context — `selfdestruct`, `address(this)`, and storage reads/writes all execute against the proxy.

**Mistake: Storage layout mismatch between proxy and implementation**

```solidity
// Proxy expects:      slot 0 = admin, slot 1 = implementation
// Implementation V1:  slot 0 = totalSupply, slot 1 = name
// Implementation V2:  slot 0 = totalSupply, slot 1 = name, slot 2 = symbol

// If V2 adds a NEW variable between existing ones:
// Implementation V2 BAD:  slot 0 = totalSupply, slot 1 = decimals, slot 2 = name
// This shifts `name` from slot 1 to slot 2 — data corruption!
```

Upgradeable contracts must only *append* new storage variables. Never reorder, remove, or insert between existing ones. OpenZeppelin's upgrade-safety tooling (hardhat-upgrades plugin) checks this automatically.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Explain how DELEGATECALL enables proxy upgrades."**
   <details>
   <summary>Answer</summary>

   - Good answer: "The proxy stores state and forwards calls to an implementation via DELEGATECALL. To upgrade, you point the proxy to a new implementation."
   - Great answer: "The proxy's fallback copies all calldata to memory, DELEGATECALLs the implementation, and forwards the return data back — or reverts with the same revert data. Because DELEGATECALL executes the implementation's code against the proxy's storage, `msg.sender` and `address(this)` remain the proxy's, so users don't notice the upgrade. The implementation address is stored at an EIP-1967 pseudo-random slot to avoid collisions. UUPS is becoming the preferred pattern because the proxy is cheaper to deploy and upgrade logic can be removed to make the protocol immutable."

   </details>

2. **"What are the risks of proxy patterns?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "Storage layout conflicts between versions can corrupt data."
   - Great answer: "Four main risks: (1) storage layout conflicts between versions causing silent data corruption, (2) uninitialized implementations — anyone can call `initialize()` on the implementation directly, so you must use `_disableInitializers()`, (3) function selector clashes in Transparent proxies between admin and user calls, and (4) pre-Dencun, `selfdestruct` in DELEGATECALL context would destroy the proxy, not the implementation."

   </details>

**Interview Red Flags:**
- 🚩 Not knowing the difference between CALL and DELEGATECALL context (who owns storage, what `msg.sender` is)
- 🚩 Forgetting that proxy and implementation must share the same storage layout
- 🚩 Not mentioning `_disableInitializers()` when discussing proxy security

**Pro tip:** When asked about proxies, mention the UUPS vs Transparent trade-off and why the industry is moving toward UUPS — smaller proxy bytecode, cheaper deployment, and the ability to make a protocol permanently immutable by removing the upgrade function. That signals you follow current best practices, not just textbook patterns.

---

<a id="precompile-calls"></a>
### 💡 Concept: Precompile Calls — ecrecover in Assembly

**Why this matters:** The EVM has precompiled contracts at addresses 0x01-0x0A that perform cryptographic operations more efficiently than EVM bytecode could. The most commonly used precompile in DeFi is `ecrecover` (address 0x01), which recovers a signer's address from a signature. Every `permit()` call, every EIP-712 signature, every meta-transaction — they all end up calling ecrecover.

In Solidity, you use `ecrecover(hash, v, r, s)`. In assembly, you make a STATICCALL to address 0x01 with the same four arguments laid out in memory.

**The ecrecover call pattern:**

```solidity
function recoverSigner(
    bytes32 hash,
    uint8 v,
    bytes32 r,
    bytes32 s
) internal view returns (address signer) {
    assembly {
        // 1. Write the 4 arguments to memory (128 bytes total)
        //    ecrecover expects: hash (32) | v (32) | r (32) | s (32)
        //    Note: v is a uint8 but must be zero-padded to 32 bytes
        let ptr := mload(0x40)          // Use FMP for memory safety
        mstore(ptr, hash)               // bytes 0-31:  message hash
        mstore(add(ptr, 0x20), v)       // bytes 32-63: v (left-padded to 32 bytes)
        mstore(add(ptr, 0x40), r)       // bytes 64-95: r
        mstore(add(ptr, 0x60), s)       // bytes 96-127: s

        // 2. STATICCALL to precompile at address 0x01
        //    staticcall(gas, addr, argsOffset, argsSize, retOffset, retSize)
        //    - gas():     forward all gas (precompile cost is fixed ~3000 gas)
        //    - 0x01:      ecrecover precompile address
        //    - ptr:       arguments start at our memory pointer
        //    - 0x80:      128 bytes of arguments (4 × 32)
        //    - ptr:       write result back to same location (safe — we're done with args)
        //    - 0x20:      expect 32 bytes back (one address, left-padded)
        let success := staticcall(gas(), 0x01, ptr, 0x80, ptr, 0x20)

        // 3. Validate the result
        //    ecrecover does NOT revert on invalid signatures — it returns address(0)
        //    A zero return means: invalid signature, malleable s-value, or wrong v
        signer := mul(mload(ptr), and(success, gt(mload(ptr), 0)))
        // If success=0 or recovered address=0 → signer = 0
        // Caller should check: require(signer != address(0))
    }
}
```

**Why `mul` instead of `if`?**

The expression `mul(mload(ptr), and(success, gt(mload(ptr), 0)))` is a branchless way to zero out the result if either the call failed or the recovered address is zero. It avoids a conditional branch:
- If `success = 1` AND `address ≠ 0`: `mul(address, 1)` = address
- If `success = 0` OR `address = 0`: `mul(address, 0)` = 0

This is a common Solady-style pattern for branchless conditionals in assembly. You'll see it often in optimized code.

**The zero-address pitfall:**

Unlike most precompiles, ecrecover does **not** revert on invalid input. It returns `address(0)`. If your code doesn't check for this, an attacker can forge signatures that "recover" to address(0) and then claim to be that address (which is impossible to control in practice — but contracts that check `signer != address(0)` are safe; contracts that don't are vulnerable).

```solidity
// WRONG — doesn't check for address(0)
address signer = ecrecover(hash, v, r, s);
require(signer == expectedSigner);  // If expectedSigner is somehow 0x0, this passes!

// RIGHT — explicit zero check
address signer = ecrecover(hash, v, r, s);
require(signer != address(0), "Invalid signature");
require(signer == expectedSigner);
```

**Memory safety note:**

The pattern above uses `mload(0x40)` to get a memory-safe pointer. If you're writing a function that runs *after* this assembly block (common for a `view` function), this is important — you need the FMP intact.

If you're in a context where nothing runs after (like the proxy forwarding pattern), you could use scratch space (offset 0x00) instead. But for ecrecover in a helper function, always use the FMP.

💻 **Quick Try:**

In Remix, deploy a contract that signs a message hash with a known private key and recovers the signer. Use the assembly `ecrecover` pattern above. Verify:
1. Valid signature → correct signer address
2. Corrupted `v` value → returns address(0)
3. `s` in the upper range (malleable) → may return a different address

You can use Foundry's `vm.sign(privateKey, hash)` cheatcode to generate test signatures.

#### 🔗 DeFi Pattern Connection

**Where ecrecover in assembly appears in DeFi:**

1. **ERC-2612 `permit()`** — Gasless token approvals. The token contract recovers the signer from the EIP-712 signature and sets the allowance. Uniswap V2's `permit()` uses ecrecover directly; most modern implementations use OpenZeppelin's `ECDSA.recover()` which wraps the assembly pattern.

2. **EIP-712 signed orders** — DEX protocols (0x, CoW Protocol, Uniswap X) use off-chain signed orders. The settlement contract recovers signers to verify order authorization.

3. **Meta-transactions / relayers** — GSN, Biconomy, Gelato — the relayer submits the transaction, but the contract recovers the original signer from the meta-transaction signature.

4. **Multisig wallets** — Gnosis Safe recovers each signer from an array of signatures, then checks that enough valid signers approved the transaction.

**Other precompiles you'll encounter:**

| Address | Name | Use case |
|---------|------|----------|
| 0x01 | ecrecover | Signature recovery (covered above) |
| 0x02 | SHA-256 | Hash computation (Bitcoin SPV proofs) |
| 0x04 | identity | Memory copy (`returndatacopy` alternative) |
| 0x05 | modexp | Modular exponentiation (RSA verification) |
| 0x06-0x08 | BN256 | Elliptic curve operations (ZK proof verification) |

Module 7 covers reading production code that uses these precompiles. For now, ecrecover is the one you need for DeFi interviews.

---

<a id="multicall"></a>
### 💡 Concept: The Multicall Pattern

**Why this matters:** Users interacting with DeFi protocols often need multiple operations atomically: approve + swap, remove liquidity + unwrap WETH, check price + execute trade. Without multicall, each operation is a separate transaction — more gas, more latency, and no atomicity guarantee.

The multicall pattern lets you batch arbitrary function calls into a single transaction. The insight: use DELEGATECALL to self. Each call in the batch executes against the same contract's storage, as if the user called each function individually.

**Why DELEGATECALL to self?**

```
Regular CALL to self:
  - msg.sender = address(this)   ← WRONG! Sender becomes the contract itself
  - Storage: same (it's the same contract)

DELEGATECALL to self:
  - msg.sender = original caller  ← Correct! Preserved from the outer call
  - Storage: same (it's the same contract)
  - address(this) = same
```

With CALL, the inner functions would see `msg.sender = address(this)` instead of the actual user. With DELEGATECALL, `msg.sender` is preserved — the inner functions see the real user, so access control works correctly.

**The Solidity version (for context):**

```solidity
// Simplified from Uniswap V3's Multicall.sol
function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
    results = new bytes[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
        (bool success, bytes memory result) = address(this).delegatecall(data[i]);
        if (!success) {
            // Bubble up the revert reason
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        results[i] = result;
    }
}
```

**The conceptual Yul version:**

In assembly, the pattern is a loop: decode each `bytes` element from the calldata array, DELEGATECALL to self, collect or discard the result.

```solidity
assembly {
    // Assume `data` is a bytes[] calldata parameter
    // The ABI encoding for bytes[] is:
    //   offset to array → length → [offset0, offset1, ...] → [bytes0, bytes1, ...]

    let count := calldataload(add(data.offset, 0))  // array length
    let baseOffset := add(data.offset, 0x20)          // start of offset entries

    for { let i := 0 } lt(i, count) { i := add(i, 1) } {
        // 1. Decode this element's calldata: offset → length → raw bytes
        let elemOffset := calldataload(add(baseOffset, mul(i, 0x20)))
        let elemPtr := add(data.offset, add(elemOffset, 0x20))
        let elemLen := calldataload(add(data.offset, elemOffset))

        // 2. Copy element's calldata to memory
        calldatacopy(0, elemPtr, elemLen)

        // 3. DELEGATECALL to self
        let ok := delegatecall(gas(), address(), 0, elemLen, 0, 0)

        // 4. If any call fails, bubble the revert data
        if iszero(ok) {
            returndatacopy(0, 0, returndatasize())
            revert(0, returndatasize())
        }

        // 5. Collect results (simplified — skip for fire-and-forget batches)
        //    For full bytes[] return encoding, see Exercise 3
    }
}
```

**When assembly multicall matters:**

For small batches (2-3 calls), the Solidity version is fine — the overhead is negligible. Assembly multicall becomes worth it for large batches or high-frequency paths. Uniswap V3's Multicall.sol is in Solidity because batch sizes are typically small (2-4 calls). But protocols processing large batch operations — token airdrops, mass liquidations, keeper bots executing dozens of operations — can benefit from the reduced overhead of assembly loop control and memory management.

Module 6 covers the specific gas savings and when assembly is overkill. For now, understand the pattern.

> **Source:** [Uniswap V3 Multicall.sol](https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol)

#### ⚠️ Common Mistakes

**Mistake: Using CALL instead of DELEGATECALL for multicall**

```solidity
// WRONG — inner calls see msg.sender = address(this)
(bool success,) = address(this).call(data[i]);
// Any function checking msg.sender (access control, balance lookups)
// will see the contract as the caller, not the user

// RIGHT — preserves msg.sender
(bool success,) = address(this).delegatecall(data[i]);
```

**Mistake: Forgetting that DELEGATECALL to self with `msg.value` can re-spend ETH**

If your multicall passes `msg.value` to each sub-call, the same ETH gets "spent" multiple times. This is because `msg.value` is set for the entire transaction — it doesn't decrease as sub-calls use it. Each DELEGATECALL sees the full original `msg.value`.

```solidity
// DANGEROUS — each call sees the full msg.value
// User sends 1 ETH, batches two calls that each try to use msg.value
// First call: msg.value = 1 ETH ✓
// Second call: msg.value = 1 ETH ← Still 1 ETH! Not 0!
```

This is the exact vulnerability that Uniswap V3 Multicall guards against — individual functions must track ETH spending themselves. If you're building a multicall pattern that handles ETH, you need explicit accounting.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How does Uniswap V3's multicall work?"**
   <details>
   <summary>Answer</summary>

   - Good answer: "It takes an array of encoded function calls and DELEGATECALLs to itself for each one, batching multiple operations atomically."
   - Great answer: "It loops through a `bytes[]` calldata array, DELEGATECALLs to `address(this)` for each element. DELEGATECALL preserves `msg.sender`, so inner functions see the real user, not the contract. If any call fails, it bubbles the revert. The key subtlety is `msg.value` — since each DELEGATECALL sees the original `msg.value`, functions that consume ETH need their own accounting to prevent double-spending. That's why Uniswap's `exactInputSingle` uses `refundETH()` as the last multicall element to sweep excess ETH back to the user."

   </details>

**Interview Red Flags:**
- 🚩 Not knowing why multicall uses DELEGATECALL instead of CALL (preserving `msg.sender`)
- 🚩 Missing the `msg.value` double-spending footgun in payable multicalls
- 🚩 Thinking multicall is just a convenience — not understanding it enables atomic batching (all-or-nothing)

**Pro tip:** If asked about multicall, mention that Uniswap V4 moved away from the V3 pattern toward hooks and flash accounting — showing you understand both the pattern and its evolution signals you stay current with protocol architecture.

---

<a id="exercise3"></a>
## 🎯 Build Exercise: AssemblyRouter

**Workspace:**
- Implementation: [`workspace/src/part4/module5/exercise3-assembly-router/AssemblyRouter.sol`](../workspace/src/part4/module5/exercise3-assembly-router/AssemblyRouter.sol)
- Tests: [`workspace/test/part4/module5/exercise3-assembly-router/AssemblyRouter.t.sol`](../workspace/test/part4/module5/exercise3-assembly-router/AssemblyRouter.t.sol)

Practice the three production patterns: proxy forwarding via DELEGATECALL, precompile calls (ecrecover), and the Uniswap-style multicall. A `MockPool` with a constant-product `swap()` function and a `MockImplementation` (in the test file) are provided.

**What's provided:**
- Function signatures with parameter names and return types
- Error selectors for `SwapFailed()`, `RecoverFailed()`, and `MultiCallFailed(uint256)`
- The `swap` selector (0xdf791e50) and step-by-step comments for each TODO
- Helper functions `echo(uint256)` and `getSender()` for multicall testing
- Solidity boilerplate for the multicall loop (array allocation, iteration) — you write the assembly inside

**4 TODOs:**

1. **`proxyForward(address impl, bytes calldata data)`** — Copy the inner calldata to memory, DELEGATECALL the implementation, then forward the return data (on success) or revert data (on failure). Uses assembly `return`/`revert` to bypass Solidity's ABI encoding — the caller sees the implementation's raw return bytes.
2. **`swapExactIn(address pool, address tokenIn, address tokenOut, uint256 amountIn)`** — Encode calldata for `swap(address,address,uint256)` (100 bytes), CALL the pool, decode the `uint256` return. Same encode → call → check → decode lifecycle from Exercise 1, but with 3 arguments and a state-changing CALL.
3. **`recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s)`** — Write the four ecrecover arguments to FMP-allocated memory (128 bytes), STATICCALL the precompile at address 0x01, check for address(0), and return the recovered signer.
4. **`multiCall(bytes[] calldata data)`** — The hardest TODO. For each element, copy it to memory, DELEGATECALL to `address(this)`, handle errors with `MultiCallFailed(i)`, and copy the return data into a Solidity-allocated `bytes[]`. The Solidity loop and array allocation are provided — you write the assembly body.

**🎯 Goal:** Combine everything from M5 into production patterns. After this exercise, you can read OpenZeppelin's `Proxy.sol`, Solady's `ecrecover`, and Uniswap's `Multicall.sol` and understand every line.

**Run:**
```bash
FOUNDRY_PROFILE=part4 forge test --match-path "test/part4/module5/exercise3-assembly-router/*"
```

---

## 📋 Key Takeaways: Production Call Patterns

After this section, you should be able to:

- Draw the CALL vs DELEGATECALL context diagram from memory — who owns storage, `msg.sender`, and `address(this)` in each case
- Write the full proxy forwarding pattern and explain why offset 0 is safe (immediate return/revert)
- Explain EIP-1967 storage slots and why they use `keccak256(...) - 1`
- Call the ecrecover precompile in assembly (write 128 bytes to memory, STATICCALL to 0x01, check for address(0))
- Explain the multicall pattern: DELEGATECALL to self preserves `msg.sender`, and `msg.value` persistence is a footgun that requires explicit ETH accounting

<details>
<summary>Check your understanding</summary>

- **CALL vs DELEGATECALL context**: CALL executes the target's code in the target's context -- `msg.sender` is the caller, `address(this)` is the target, and storage belongs to the target. DELEGATECALL executes the target's code in the caller's context -- `msg.sender` stays as the original sender, `address(this)` is the caller, and storage writes go to the caller's slots.
- **Proxy forwarding pattern**: Copy all calldata to memory at offset 0, DELEGATECALL to the implementation, copy return data to offset 0, then RETURN or REVERT based on the success flag. Starting at offset 0 is safe because the function terminates immediately -- no subsequent memory operations will be affected.
- **EIP-1967 slots**: Standardized storage slots for proxy metadata (implementation, admin, beacon) computed as `keccak256(identifier) - 1`. The `-1` prevents preimage collision with keccak256-derived mapping/array slots. Tools like Etherscan read these slots to identify proxy contracts and their implementations.
- **ecrecover precompile**: Write hash (0x00), v (0x20), r (0x40), s (0x60) to memory -- 128 bytes total. STATICCALL to address 0x01 with 3000 gas. Returns the recovered address (or 0x00 for invalid signatures). Always check for address(0) to reject malformed signatures.
- **Multicall with DELEGATECALL to self**: Each sub-call in the batch uses DELEGATECALL to `address(this)`, preserving `msg.sender` so access control works correctly. However, `msg.value` is the same for every sub-call in the batch -- a user sending 1 ETH could have it counted multiple times. Production multicall must track ETH spending explicitly.

</details>

---

## 📚 Resources

**Essential References:**
- [EVM Opcodes Reference](https://www.evm.codes/) — interactive opcode docs with gas costs for CALL, STATICCALL, DELEGATECALL, RETURNDATACOPY
- [Solady SafeTransferLib](https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol) — gas-optimized SafeERC20 with scratch space encoding
- [OpenZeppelin SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) — production SafeERC20 with code size check

**Proxy Patterns:**
- [OpenZeppelin Proxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol) — the base `_delegate()` pattern
- [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) — standard proxy storage slots
- [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167) — minimal proxy (clone) standard
- [EIP-2535](https://eips.ethereum.org/EIPS/eip-2535) — Diamond standard (multi-facet proxy)

**Multicall & Batching:**
- [Uniswap V3 Multicall.sol](https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol) — the reference multicall implementation

**EIPs:**
- [EIP-150](https://eips.ethereum.org/EIPS/eip-150) — 63/64 gas forwarding rule
- [EIP-214](https://eips.ethereum.org/EIPS/eip-214) — STATICCALL opcode
- [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780) — SELFDESTRUCT restriction (Dencun)

**Security:**
- [Returnbomb attack explained](https://github.com/nomad-xyz/ExcessivelySafeCall) — ExcessivelySafeCall library with bounded return data copy
- [Parity wallet hack postmortem](https://blog.openzeppelin.com/on-the-parity-wallet-multisig-hack-405a8c12e8f7) — DELEGATECALL + selfdestruct case study

---

**Navigation:** [← Module 4: Control Flow & Functions](4-control-flow.md) | [Module 6: Gas Optimization Patterns →](6-gas-optimization.md)

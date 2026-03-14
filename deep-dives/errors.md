# Deep Dives — Errors: The Complete Picture

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~90 minutes | **Exercises:** ~2 hours

---

## 📚 Table of Contents

**EVM Failure Modes**
- [The Three Ways Execution Fails](#three-failure-modes)
- [REVERT Opcode Mechanics](#revert-mechanics)

**Error Encoding**
- [The Anatomy of Error Data](#error-anatomy)
- [Three Error Formats](#three-formats)
- [Panic Codes Reference](#panic-codes)

**Solidity Error Primitives**
- [require, revert, assert — What Each Compiles To](#require-revert-assert)
- [Custom Error Declarations](#custom-errors)

**Error Propagation**
- [How Errors Travel Up the Call Stack](#error-bubbling)
- [Low-Level Calls — Manual Error Handling](#low-level-errors)
- [Propagation Through Proxies](#proxy-errors)
- [Constructor Reverts](#constructor-reverts)

**Try/Catch**
- [The Four Catch Clauses](#four-clauses)
- [What Try/Catch Cannot Catch](#try-catch-limits)

**Decoding & Detection**
- [Decoding Raw Revert Data](#decoding-revert)
- [Foundry Error Testing](#foundry-errors)

**DeFi Error Patterns**
- [Multicall Error Strategies](#multicall-errors)
- [Error Handling in Flash Loans](#flash-loan-errors)
- [Router & Aggregator Error Bubbling](#router-errors)
- [Liquidation Bot Patterns](#liquidation-errors)
- [Build Exercise: ErrorHandler](#exercise1)

---

## 💡 EVM Failure Modes

Every failed transaction you've ever seen on Etherscan ended in one of three ways. They look similar from the outside — "transaction reverted" — but at the EVM level, they behave completely differently in terms of gas consumption, returndata, and what information reaches the caller.

<a id="three-failure-modes"></a>
### 💡 Concept: The Three Ways Execution Fails

**Why this matters:** When your DeFi transaction fails, the failure mode determines whether you lose all your gas, whether you get an error message, and whether your caller can react to the failure. Understanding these three modes is the foundation for everything else in this deep dive.

**The three failure modes:**

| | REVERT | INVALID | Out-of-gas |
|---|---|---|---|
| **Opcode** | `REVERT` (0xFD) | `INVALID` (0xFE) | N/A (execution halts) |
| **Gas behavior** | Refunds remaining gas | Consumes ALL remaining gas | Consumes ALL remaining gas |
| **Returndata** | Yes — caller receives error data | None — returndata is empty | None — returndata is empty |
| **When it happens** | `require()`, `revert`, custom errors | Handwritten assembly, very old contracts | Insufficient gas, infinite loops, deep recursion |
| **State changes** | Reverted in current frame | Reverted in current frame | Reverted in current frame |

The critical distinction: REVERT is the only failure mode that gives the caller useful information. The other two are black holes — gas gone, no explanation.

**REVERT — the controlled failure:**

```
Caller sends 100,000 gas
  └─► Sub-call uses 30,000 gas, then hits REVERT
        ├─ Returndata: error message bytes (forwarded to caller)
        ├─ State: all changes in this frame rolled back
        └─ Gas: 70,000 remaining gas returned to caller
```

This is what Solidity's `require()`, `revert`, and custom errors compile to. The caller gets its unused gas back and can read the error data to decide what to do.

**INVALID — the hard crash:**

```
Caller sends 100,000 gas
  └─► Sub-call uses 30,000 gas, then hits INVALID (0xFE)
        ├─ Returndata: empty (nothing to read)
        ├─ State: all changes in this frame rolled back
        └─ Gas: ALL 100,000 consumed — nothing returned
```

Pre-0.8.0 Solidity compiled `assert()` to the INVALID opcode. Since 0.8.0, `assert` uses REVERT with a Panic code instead — so INVALID is now only encountered in handwritten assembly or contracts compiled with very old Solidity versions. You'll still see it in deployed contracts like early Uniswap V2 or original MakerDAO.

**Out-of-gas — the silent death:**

```
Caller sends 100,000 gas
  └─► Sub-call keeps executing... runs out of gas
        ├─ Returndata: empty (nothing to read)
        ├─ State: all changes in this frame rolled back
        └─ Gas: ALL consumed — the definition of "out of gas"
```

No opcode triggers this — execution simply halts when the gas counter hits zero. From the caller's perspective, it looks identical to INVALID: `success = false`, no returndata. This makes out-of-gas failures difficult to distinguish from INVALID crashes programmatically.

💻 **Quick Try:**

See all three failure modes in Remix:

```solidity
contract FailureModes {
    // Mode 1: REVERT — controlled, returns data, refunds gas
    function failRevert() external pure {
        revert("something went wrong");
    }

    // Mode 2: INVALID — consumes all gas, no returndata
    function failInvalid() external pure {
        assembly {
            invalid()
        }
    }

    // Mode 3: Out-of-gas — consumes all gas, no returndata
    function failOutOfGas() external pure {
        uint256 i;
        while (true) {
            i++;
        }
    }
}
```

Call each with a gas limit of 100,000. Compare the gas consumed: `failRevert` will consume much less than the other two. Check the return data in the Remix console — only `failRevert` returns error bytes.

#### 🔍 Deep Dive: Gas Behavior on Each Failure Mode

Why does gas behavior matter in DeFi? Because it affects the cost of failed transactions — and in protocols like liquidation bots or aggregators, failures are expected and frequent.

**REVERT gas accounting in detail:**

```
Transaction gas limit: 200,000

  CALL to sub-contract (forwards 150,000 gas)
  │
  │  Sub-contract executes:
  │    SLOAD         →  2,100 gas used
  │    MSTORE        →      3 gas used
  │    comparison    →      3 gas used
  │    REVERT        →      0 gas used (REVERT itself is free)
  │                    ─────────────────
  │    Total used:     2,106 gas
  │    Returned:     147,894 gas (150,000 - 2,106)
  │
  ◄── Caller gets 147,894 gas back
      Caller continues execution with remaining gas
```

Key detail: the REVERT opcode itself costs 0 gas. You only pay for the work done before the revert, plus the memory expansion cost of the returndata. This is why custom errors (small returndata) are cheaper than string errors (larger returndata) — less memory expansion.

**INVALID / out-of-gas — the 63/64 rule saves the caller:**

Even though INVALID and out-of-gas consume all gas in the sub-call, the caller doesn't necessarily lose everything. [EIP-150](https://eips.ethereum.org/EIPS/eip-150) introduced the 63/64 rule: when making a sub-call, at most 63/64 of the remaining gas is forwarded. The caller always retains at least 1/64.

```
Caller has 128,000 gas remaining
  │
  │  CALL forwards at most 63/64 = 126,000 gas
  │  Caller retains at least 1/64 = 2,000 gas
  │
  └─► Sub-call hits INVALID — all 126,000 consumed

  Caller still has ~2,000 gas to check success and react
```

This is why a sub-call hitting INVALID doesn't always kill the entire transaction — the caller retains enough gas to check the return value and potentially continue. But 1/64 isn't much — if the caller needs to do significant work after the failure (like emitting events or updating storage), it may still run out.

#### ⚠️ Common Mistakes

**Mistake 1: Assuming all failures return error data**

```solidity
// WRONG — this only works if the sub-call used REVERT
(bool success, bytes memory data) = target.call(payload);
if (!success) {
    // data might be EMPTY if the sub-call hit INVALID or ran out of gas
    // Trying to decode it will fail
    (string memory reason) = abi.decode(data, (string)); // Reverts on empty data!
}

// CORRECT — check data length first
(bool success, bytes memory data) = target.call(payload);
if (!success) {
    if (data.length > 0) {
        // Sub-call used REVERT — decode the error
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    } else {
        // INVALID or out-of-gas — no data to decode
        revert("sub-call failed without data");
    }
}
```

**Mistake 2: Confusing INVALID with out-of-gas**

Both produce `success = false` with empty returndata. You cannot distinguish them from within the EVM. If your code needs to know which happened, you have to check off-chain (via tracing) or infer from the gas remaining after the call.

---

<a id="revert-mechanics"></a>
### 💡 Concept: REVERT Opcode Mechanics

**Why this matters:** Every Solidity error — `require`, `revert`, custom errors, panics — compiles down to the same opcode: REVERT. Understanding exactly what this opcode does gives you the mental model for everything that follows: encoding, propagation, try/catch, and decoding.

**What REVERT does at the opcode level:**

The REVERT opcode takes two values from the stack:

```
REVERT(offset, size)
  │        │
  │        └─ How many bytes of returndata to send back
  └─ Where in memory the returndata starts
```

It does three things, in order:
1. **Copies `size` bytes from memory starting at `offset`** into the returndata buffer
2. **Rolls back all state changes** made in the current execution frame (storage writes, balance transfers, logs)
3. **Returns remaining gas** to the caller

That's it. The returndata bytes are whatever the contract put in memory before calling REVERT. Solidity puts ABI-encoded error data there — but at the EVM level, it's just arbitrary bytes.

**REVERT vs RETURN — the same mechanics, different outcome:**

```
RETURN(offset, size)  →  success = true,  state changes KEPT,   returndata sent
REVERT(offset, size)  →  success = false, state changes ROLLED BACK, returndata sent
```

Both opcodes send returndata. Both refund remaining gas. The only difference is whether the frame's state changes persist. This symmetry is important — it means the returndata mechanism works identically for errors and successful returns.

**What "current execution frame" means:**

REVERT only rolls back the current frame — the sub-call that executed it. The calling frame is unaffected and can continue:

```
Transaction
├── Frame 0 (your contract)
│   ├── SSTORE (slot 1 = 100)     ← persists (not in the reverted frame)
│   │
│   ├── CALL to Contract B ──────► Frame 1 (Contract B)
│   │                               ├── SSTORE (slot 5 = 999)  ← rolled back
│   │                               ├── SSTORE (slot 6 = 888)  ← rolled back
│   │                               └── REVERT(0x00, 0x24)     ← error data sent back
│   │
│   ◄── success = false, returndata = error bytes
│   │
│   ├── SSTORE (slot 2 = 200)     ← persists (Frame 0 continues)
│   └── RETURN
```

Frame 0's storage writes at slot 1 and slot 2 both persist. Frame 1's writes are gone. This is why `try/catch` works — the calling contract can catch a sub-call's revert without losing its own state.

💻 **Quick Try:**

Verify that state persists in the calling frame after a sub-call reverts:

```solidity
contract Inner {
    function failAfterWork() external pure {
        revert("I failed");
    }
}

contract Outer {
    uint256 public beforeCall;
    uint256 public afterCall;

    function test(address inner) external {
        beforeCall = 1;  // This persists

        (bool success, ) = inner.call(
            abi.encodeWithSignature("failAfterWork()")
        );
        // success is false, but we're still running

        afterCall = 2;  // This also persists
    }
}
```

Deploy both, call `Outer.test()`, then read `beforeCall` and `afterCall` — both are set despite the inner call failing.

#### 🔍 Deep Dive: The Returndata Buffer

The returndata buffer is a per-frame memory region that holds the output of the most recent external call. Understanding it is key to understanding error propagation.

**How the buffer works:**

```
Frame 0 makes CALL to Frame 1
  │
  Frame 1 executes REVERT(offset, size)
  │   └─ copies memory[offset..offset+size] into Frame 0's returndata buffer
  │
  ◄── Frame 0 can now access this data:
      │
      ├── RETURNDATASIZE   → returns the length of the buffer
      ├── RETURNDATACOPY    → copies buffer bytes into Frame 0's memory
      └── Solidity's abi.decode uses these under the hood
```

**Critical behavior — the buffer is overwritten by every external call:**

```solidity
(bool s1, bytes memory data1) = contractA.call(payload1);
// returndata buffer = data from contractA

(bool s2, bytes memory data2) = contractB.call(payload2);
// returndata buffer = data from contractB
// contractA's data is GONE from the buffer

// BUT: data1 still exists — Solidity copied it to memory
// This is why Solidity returns `bytes memory` — it copies out of
// the volatile buffer into persistent memory immediately
```

If you're working in assembly and don't copy the returndata before making another call, it's gone. Solidity handles this automatically, but in assembly you must use `RETURNDATACOPY` before making any subsequent external call.

**Returndata and memory expansion costs:**

The returndata itself doesn't cost gas to receive — the caller doesn't pay for the sub-call's memory. But when the caller uses `RETURNDATACOPY` to copy returndata into its own memory, it pays for memory expansion in its own frame. This is why returning huge error strings is wasteful — the caller pays to copy those bytes into memory.

```
Custom error:  revert InsufficientBalance(required, actual)
               → 4 bytes selector + 64 bytes params = 68 bytes

String error:  revert("Insufficient balance: required X but got Y")
               → 4 bytes selector + 32 bytes offset + 32 bytes length +
                 N bytes string = 100+ bytes

The caller copies all of these bytes into memory. Fewer bytes = less memory expansion = less gas.
```

---

## 📋 Key Takeaways: EVM Failure Modes

After this section, you should be able to:

- Identify which of the three failure modes (REVERT, INVALID, out-of-gas) occurred given a failed call's gas consumption and returndata, and explain why two of them are indistinguishable from the caller's perspective
- Explain why REVERT costs 0 gas itself and why custom errors produce cheaper reverts than string errors (less memory expansion for the returndata)
- Trace a REVERT through nested call frames and explain which state changes persist and which are rolled back
- Describe how the returndata buffer works, why it's overwritten by every subsequent external call, and what happens if you don't copy it in assembly before making another call
- Explain how the 63/64 rule (EIP-150) protects the caller from losing all gas when a sub-call hits INVALID or runs out of gas

<details>
<summary>Check your understanding</summary>

- **Three failure modes**: REVERT returns unused gas and sends returndata (cheapest, most informative). INVALID consumes all forwarded gas and returns nothing. Out-of-gas also consumes all forwarded gas and returns nothing. INVALID and out-of-gas are indistinguishable to the caller — both show success=0 with empty returndata.
- **REVERT cost and custom errors**: REVERT itself costs 0 gas; the cost comes from the memory expansion needed to write the returndata. Custom errors produce smaller returndata than string errors (4-byte selector + params vs 4-byte selector + offset + length + padded string), requiring less memory expansion.
- **Returndata buffer**: Overwritten by every external call (including calls that return no data). In assembly, you must `returndatacopy` the bytes you need before making another call, or the data is lost. The buffer persists only until the next `call`/`staticcall`/`delegatecall`.
- **63/64 rule (EIP-150)**: The caller retains 1/64th of available gas when making a sub-call. If the sub-call hits INVALID or runs out of gas, the caller still has its reserved 1/64th to detect the failure (success=0) and handle it — preventing complete gas exhaustion from propagating up the entire call chain.

</details>

---

## 💡 Error Encoding

You now know that REVERT sends bytes back to the caller. But what's actually in those bytes? Solidity doesn't send raw strings — it ABI-encodes error data using the exact same scheme as function calls. Understanding this encoding is what lets you decode errors from any contract, even ones you don't have the source for.

<a id="error-anatomy"></a>
### 💡 Concept: The Anatomy of Error Data

**Why this matters:** When you see raw revert data on Etherscan or in a Foundry trace, it's just hex bytes. Knowing the structure lets you decode any error from any contract — custom errors, string messages, panics — without needing the ABI. It's the same skill you use to decode function calldata, because the encoding is identical.

**The structure:**

Error data follows the exact same ABI encoding as function calldata: a 4-byte selector followed by ABI-encoded parameters.

```
Revert data layout:
┌──────────────┬──────────────────────────────────────────┐
│  Bytes 0-3   │  Bytes 4+                                │
│              │                                          │
│  Selector    │  ABI-encoded parameters                  │
│  (4 bytes)   │  (variable length)                       │
└──────────────┴──────────────────────────────────────────┘
```

The selector is `keccak256("ErrorName(paramTypes)")` truncated to 4 bytes — exactly like a function selector.

**Example — a custom error:**

```solidity
error InsufficientBalance(uint256 required, uint256 actual);

revert InsufficientBalance(1000, 500);
```

Produces this revert data:

```
Selector:  keccak256("InsufficientBalance(uint256,uint256)")[0:4]
           = 0xcf479181

Full revert data (68 bytes):
cf479181                                                          ← selector
00000000000000000000000000000000000000000000000000000000000003e8    ← 1000
00000000000000000000000000000000000000000000000000000000000001f4    ← 500
```

This is byte-for-byte identical in structure to calling a function `InsufficientBalance(uint256,uint256)` with arguments `(1000, 500)`. The ABI encoder doesn't know — or care — whether it's encoding a function call or an error.

**Example — a string error:**

```solidity
revert("insufficient balance");
```

Produces:

```
Selector:  keccak256("Error(string)")[0:4]
           = 0x08c379a0

Full revert data:
08c379a0                                                          ← selector
0000000000000000000000000000000000000000000000000000000000000020    ← offset to string data (32)
0000000000000000000000000000000000000000000000000000000000000014    ← string length (20 bytes)
696e73756666696369656e742062616c616e636500000000000000000000000000  ← "insufficient balance" + padding
```

Notice the extra indirection: strings are dynamic types in ABI encoding, so there's an offset pointer, then the length, then the data. This is why string errors use more gas — more bytes to encode and more memory expansion.

💻 **Quick Try:**

See the raw encoding yourself in Remix:

```solidity
contract ErrorEncoding {
    error InsufficientBalance(uint256 required, uint256 actual);

    function getCustomErrorData() external pure returns (bytes memory) {
        // Encode error data without actually reverting
        return abi.encodeWithSelector(
            InsufficientBalance.selector,
            1000,
            500
        );
    }

    function getStringErrorData() external pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", "insufficient balance");
    }

    // Compare the byte lengths
    function compareSizes() external pure returns (uint256 custom, uint256 str) {
        custom = abi.encodeWithSelector(InsufficientBalance.selector, 1000, 500).length;
        str = abi.encodeWithSignature("Error(string)", "insufficient balance").length;
    }
}
```

Call `compareSizes()` — the custom error is 68 bytes, the string error is 100+ bytes. Call the other two functions to see the raw hex and match it against the layouts above.

#### 🔍 Deep Dive: Error Selectors vs Function Selectors

Error selectors and function selectors are computed identically: `keccak256(signature)` truncated to 4 bytes. This means they share the same 4-byte selector space — and collisions are theoretically possible.

```solidity
// Function selector
bytes4 funcSelector = bytes4(keccak256("transfer(address,uint256)"));
// = 0xa9059cbb

// Error selector
bytes4 errSelector = bytes4(keccak256("InsufficientBalance(uint256,uint256)"));
// = 0xcf479181

// Same computation, same 4-byte space
```

**Why this matters for decoding:**

When you receive raw revert data and extract the first 4 bytes, you're looking up the selector against a known list of error signatures. Tools like [openchain.xyz/signatures](https://openchain.xyz/signatures) and [4byte.directory](https://www.4byte.directory/) maintain databases of known selectors — for both functions and errors.

**Selector collisions:** With 2^32 (~4.3 billion) possible selectors, collisions exist. The Solidity compiler checks for collisions within each category in a single contract — no two *functions* can share a selector, and no two *errors* can share a selector. But a function and an error *can* have the same selector (they're dispatched differently). Cross-contract collisions are also possible. In practice this is rarely a problem — you typically know which contract reverted and can match against its specific error definitions.

---

<a id="three-formats"></a>
### 💡 Concept: Three Error Formats

**Why this matters:** Not all revert data looks the same. Solidity produces three distinct formats depending on how the error was triggered. When you're decoding errors — whether in a try/catch, from a low-level call, or in off-chain tooling — you need to recognize which format you're dealing with before you can decode the parameters.

**Format 1: String errors — `Error(string)`**

Selector: `0x08c379a0`

```solidity
// Produced by:
require(condition, "message");
revert("message");
```

```
08c379a0                                                          ← always this selector
[ABI-encoded string]                                              ← offset + length + data
```

This was the only user-defined error format before Solidity 0.8.4 (Panic existed since 0.8.0 but is compiler-generated). It's verbose and gas-expensive because strings are dynamic types. Still used widely — OpenZeppelin's access control messages, many require statements in production code.

**Format 2: Custom errors — `ErrorName(params...)`**

Selector: first 4 bytes of `keccak256("ErrorName(paramTypes)")`

```solidity
// Produced by:
error InsufficientBalance(uint256 required, uint256 actual);
revert InsufficientBalance(1000, 500);
```

```
cf479181                                                          ← error-specific selector
[ABI-encoded params]                                              ← packed 32-byte words
```

Introduced in Solidity 0.8.4. Gas-efficient because parameters are statically typed (no offset/length overhead for simple types). This is the modern standard — Uniswap V4, Aave V3, and most new protocols use custom errors exclusively.

**Format 3: Panic codes — `Panic(uint256)`**

Selector: `0x4e487b71`

```solidity
// Produced automatically by the compiler:
assert(false);                    // Panic(0x01)
uint256 x = 1 / 0;               // Panic(0x12)
uint256 y = type(uint256).max + 1; // Panic(0x11) — if checked arithmetic
```

```
4e487b71                                                          ← always this selector
0000000000000000000000000000000000000000000000000000000000000011    ← panic code
```

Always exactly 36 bytes: 4-byte selector + 32-byte uint256 code. Panic codes are compiler-generated — you never write `revert Panic(0x11)` yourself. They indicate bugs in the code (failed assertions, arithmetic overflow, out-of-bounds access), not expected error conditions.

**Recognizing the format from raw bytes:**

```
First 4 bytes of revert data:
  0x08c379a0  →  String error   →  decode as Error(string)
  0x4e487b71  →  Panic code     →  decode as Panic(uint256)
  anything else →  Custom error  →  need the error ABI to decode params
  empty (0 bytes) →  No data    →  INVALID, out-of-gas, or bare revert()
```

This four-way check is the foundation of every error decoder — whether you're building one in Solidity, in a bot, or it's what Foundry does internally when it shows you readable error messages.

💻 **Quick Try:**

Trigger all three formats and compare the raw revert data:

```solidity
contract ThreeFormats {
    error CustomError(uint256 code);

    function stringError() external pure {
        revert("bad input");
    }

    function customError() external pure {
        revert CustomError(42);
    }

    function panicError() external pure {
        assert(false);
    }

    function bareRevert() external pure {
        revert();  // No data at all
    }
}
```

Call each in Remix and look at the revert data in the console. `stringError` starts with `08c379a0`, `customError` with the custom selector, `panicError` with `4e487b71`, and `bareRevert` has empty returndata.

#### ⚠️ Common Mistakes

**Mistake 1: Assuming all revert data is a string**

```solidity
// WRONG — only works for Error(string) format
try target.someFunction() {
    // ...
} catch Error(string memory reason) {
    // This ONLY catches string errors (0x08c379a0)
    // Custom errors and panics fall through to the next catch clause
}

// You need multiple catch clauses or catch (bytes memory) to handle all formats
```

**Mistake 2: Forgetting bare revert()**

`revert()` with no arguments produces zero bytes of returndata — not even a selector. Your decoder must handle the empty case:

```solidity
if (data.length == 0) {
    // bare revert(), INVALID, or out-of-gas — no information available
} else if (data.length >= 4) {
    bytes4 selector;
    assembly { selector := mload(add(data, 0x20)) } // bytes memory needs assembly

    if (selector == 0x08c379a0) {
        // string error
    } else if (selector == 0x4e487b71) {
        // panic
    } else {
        // custom error — need ABI to decode further
    }
}
```

**Mistake 3: Assuming data.length >= 4**

Revert data can technically be any length — including 1, 2, or 3 bytes from handwritten assembly. Always check `data.length >= 4` before extracting a selector.

---

<a id="panic-codes"></a>
### 💡 Concept: Panic Codes Reference

**Why this matters:** When you see `Panic(0x11)` in a Foundry trace or a failed transaction, you need to know instantly what triggered it. Panic codes are the compiler's way of telling you which internal safety check failed. Unlike custom errors that you define, panics are built into the compiler — and the list is exhaustive.

**Complete panic code table:**

| Code | Hex | Trigger | Common DeFi scenario |
|------|-----|---------|---------------------|
| 0x00 | `0x00` | Generic compiler-inserted panic | Rare — compiler internal |
| 0x01 | `0x01` | `assert(false)` | Failed invariant check |
| 0x11 | `0x11` | Arithmetic overflow/underflow | Token math without unchecked, price calculation overflow |
| 0x12 | `0x12` | Division or modulo by zero | Division by totalSupply when pool is empty |
| 0x21 | `0x21` | Conversion to enum with invalid value | Casting invalid uint to enum (e.g., order types) |
| 0x22 | `0x22` | Access to incorrectly encoded storage byte array | Rare — corrupted storage |
| 0x31 | `0x31` | `.pop()` on an empty array | Removing from an empty queue/stack |
| 0x32 | `0x32` | Array, `bytesN`, or slice index out of bounds | Accessing `pools[i]` with invalid index |
| 0x41 | `0x41` | Too much memory allocated or array too large | Creating a huge dynamic array |
| 0x51 | `0x51` | Calling a zero-initialized internal function variable | Rare — uninitialized function pointer |

**The ones you'll actually see in DeFi:**

- **0x11 (overflow)** — the most common. Happens when checked arithmetic catches an overflow. In DeFi: price calculations, reward accumulator math, or token amount computations that exceed uint256. When you see this, the question is whether the inputs were valid (code bug) or the inputs were invalid (missing validation).

- **0x12 (division by zero)** — second most common. In DeFi: dividing by `totalSupply` or `totalAssets` when a pool is empty, dividing by a reserve amount that's been fully drained. This is why production code checks `if (totalSupply == 0)` before any division.

- **0x32 (out of bounds)** — array access with an invalid index. In DeFi: iterating over a dynamic list of positions, pools, or tokens with a stale length.

- **0x01 (assertion failure)** — `assert()` is used for invariant checks that should never fail. If you see this in production, it means a fundamental invariant was violated — it's a serious bug, not an expected error condition.

**Panic vs custom error — when to use which:**

```solidity
// Use CUSTOM ERRORS for expected failure conditions:
error InsufficientBalance(uint256 required, uint256 actual);
if (balance < amount) revert InsufficientBalance(amount, balance);

// Use ASSERT for invariants that should NEVER be false:
assert(totalShares == 0 || totalAssets > 0);  // If shares exist, assets must exist
```

If your code triggers a panic in production, it's a bug. If it triggers a custom error, it's working as designed — rejecting invalid inputs or states.

#### 🔗 DeFi Pattern Connection

**Where panic codes surface in DeFi:**

1. **Vault math (0x11, 0x12)**
   The classic empty vault problem: when `totalSupply == 0`, any division by it panics with 0x12. This is why ERC-4626 vaults use virtual shares/assets or check for the zero case explicitly. The inflation attack exploits the boundary between 0 and 1 shares — and a panic at that boundary would halt deposits entirely.

2. **AMM reserve calculations (0x11)**
   The constant product formula `x * y = k` involves multiplying two reserve values. If reserves grow large enough (e.g., rebasing tokens), the multiplication can overflow. Uniswap V2 uses `UQ112x112` fixed-point to bound this. Uniswap V3 uses `mulDiv` for 512-bit intermediates. Without these, you'd see Panic(0x11) on large swaps.

3. **Reward accumulators (0x11)**
   Staking contracts accumulate `rewardPerToken` by adding `(reward * 1e18) / totalStaked` each period. If `reward * 1e18` overflows, you get 0x11. This is why production accumulators use careful scaling and sometimes 256-bit-safe math.

**The pattern:** Panic codes in DeFi almost always mean missing boundary checks — empty pools, zero supplies, or overflow-prone calculations. Production code prevents them by validating before the arithmetic, not by catching them after.

---

## 📋 Key Takeaways: Error Encoding

After this section, you should be able to:

- Look at raw revert data hex and identify which of the four cases it is (string error, custom error, panic, or empty) by checking the first 4 bytes against the known selectors `0x08c379a0` and `0x4e487b71`
- Explain why error encoding uses the same ABI scheme as function calldata — same selector computation, same parameter encoding — and why this means the same decoding tools work for both
- Decode a custom error's parameters by extracting the selector and ABI-decoding the remaining bytes, given the error's signature
- Map any panic code to its trigger and identify the most common ones in DeFi contexts (0x11 overflow, 0x12 division by zero, 0x32 out of bounds)
- Explain why custom errors are cheaper than string errors in terms of returndata size and memory expansion cost

<details>
<summary>Check your understanding</summary>

- **Identifying error format from raw hex**: Check bytes 0-3: `0x08c379a0` = `Error(string)`, `0x4e487b71` = `Panic(uint256)`, empty = bare revert/INVALID/OOG, anything else = custom error. This works because error encoding uses the same selector scheme as function calls.
- **Error encoding = function call encoding**: Both use `keccak256(signature)[0:4]` for the selector followed by ABI-encoded parameters. This means `cast 4byte`, `abi.decode`, and the same decoding libraries work for both calldata and revert data.
- **Decoding custom error parameters**: Extract the 4-byte selector, match it against known error signatures, then `abi.decode(data[4:], (paramTypes))` to recover the parameters. Without the error signature, you can still identify the selector via a 4byte directory lookup.
- **Common panic codes**: 0x11 = arithmetic overflow/underflow (most common in DeFi math), 0x12 = division by zero, 0x32 = array out-of-bounds access. These are emitted by `assert` failures and checked arithmetic in Solidity 0.8+.
- **Custom errors are cheaper**: A parameterless custom error produces just 4 bytes of returndata. `require(false, "Insufficient balance")` produces 4 + 32 + 32 + 32 + padded-string bytes. Less returndata means less memory expansion cost at the REVERT instruction.

</details>

---

## 💡 Solidity Error Primitives

You know the encoding. You know the three formats. Now let's look at the Solidity constructs that produce them — `require`, `revert`, `assert`, and custom error declarations. Each compiles to different bytecode, and what the compiler emits has changed across versions.

<a id="require-revert-assert"></a>
### 💡 Concept: require, revert, assert — What Each Compiles To

**Why this matters:** These three keywords look similar at the Solidity level, but they compile to fundamentally different bytecode. Knowing what each produces — and how that changed across compiler versions — tells you exactly what error format a contract will emit, which matters when you're decoding errors from contracts compiled with different Solidity versions.

**The current behavior (Solidity 0.8.x):**

| Construct | Bytecode | Error format | When to use |
|-----------|----------|-------------|-------------|
| `require(cond, "msg")` | `REVERT` | `Error(string)` — selector `0x08c379a0` | Input validation, access control |
| `require(cond, CustomError())` | `REVERT` | Custom error — error-specific selector | Input validation (0.8.26+) |
| `revert("msg")` | `REVERT` | `Error(string)` — selector `0x08c379a0` | Explicit failure with message |
| `revert CustomError()` | `REVERT` | Custom error — error-specific selector | Explicit failure (modern) |
| `require(cond)` | `REVERT` | Empty returndata (0 bytes) | Cheap validation (no message) |
| `revert()` | `REVERT` | Empty returndata (0 bytes) | Bare revert |
| `assert(cond)` | `REVERT` | `Panic(uint256)` — selector `0x4e487b71` | Invariant checks |

**What changed from pre-0.8.0 to 0.8.x:**

This is critical when reading old contracts that are still deployed on mainnet.

```
Pre-0.8.0 (Solidity 0.7.x and earlier):
─────────────────────────────────────────
require(cond, "msg")  →  REVERT with Error(string)     ← same as today
require(cond)         →  REVERT with empty data         ← same as today
assert(cond)          →  INVALID opcode (0xFE)          ← DIFFERENT!
                         ▲
                         │ Consumes ALL gas, no returndata
                         │ This is why old assert() was so dangerous

Since 0.8.0:
─────────────────────────────────────────
assert(cond)          →  REVERT with Panic(0x01)        ← controlled failure
                         ▲
                         │ Refunds gas, returns panic code
                         │ Much safer — caller can detect and react
```

**Why the assert change matters:** Pre-0.8.0, `assert(false)` in a sub-call would consume all forwarded gas and return nothing. The caller couldn't distinguish it from out-of-gas. Since 0.8.0, `assert` is just a REVERT with a specific error format — the caller gets gas back and can read the panic code. If you're reading a pre-0.8.0 contract and see `assert`, know that it's far more punishing than the modern version.

**Solidity 0.8.26 — require with custom errors:**

```solidity
// Before 0.8.26: had to use if/revert for custom errors
error Unauthorized(address caller);
if (msg.sender != owner) revert Unauthorized(msg.sender);

// Since 0.8.26: require accepts custom errors directly
require(msg.sender == owner, Unauthorized(msg.sender));
```

This is syntactic sugar — the bytecode is identical. But it makes custom errors as convenient as string messages, removing the last reason to prefer `require(cond, "string")`.

💻 **Quick Try:**

Compare the gas cost of each error style:

```solidity
contract ErrorGas {
    error Unauthorized();

    function withString() external pure {
        require(false, "unauthorized access attempt");
    }

    function withCustom() external pure {
        revert Unauthorized();
    }

    function withBareRequire() external pure {
        require(false);
    }

    function withAssert() external pure {
        assert(false);
    }
}
```

Call each in Remix and compare gas used. `withCustom` and `withBareRequire` are cheapest, `withString` is most expensive (string encoding overhead), and `withAssert` includes the Panic encoding.

#### 🔍 Deep Dive: Bytecode Comparison Across Versions

Let's trace what the compiler actually emits for a simple `require(x > 0, "zero")`:

**Solidity 0.8.x bytecode (simplified):**

```
PUSH1 0x00       // load x
CALLDATALOAD
PUSH1 0x00
GT               // x > 0 ?
PUSH1 [jump_ok]
JUMPI            // if true, jump past revert

// False path — emit Error(string):
PUSH32 0x08c379a0...   // Error(string) selector
MSTORE                  // write to memory
// ... encode "zero" as ABI string ...
REVERT                  // revert with the encoded data

[jump_ok]:
JUMPDEST         // continue execution
```

**The same require, pre-0.5.0:**

Before Solidity 0.4.22, `require` didn't even support reason strings. `require(cond)` and `assert(cond)` both produced bare reverts or INVALID opcodes with no error data at all. This is why many legacy contracts on mainnet revert with no explanation.

**What `revert CustomError(args)` emits:**

```
// revert InsufficientBalance(1000, 500)

PUSH4 0xcf479181     // error selector
MSTORE
PUSH2 0x03e8         // 1000
MSTORE
PUSH2 0x01f4         // 500
MSTORE
PUSH1 0x44           // 68 bytes of data
PUSH1 0x00           // starting at offset 0
REVERT
```

No string encoding, no offset pointers, no length fields. Just selector + packed 32-byte words. This is why custom errors save gas — the encoding is simpler and shorter.

#### ⚠️ Common Mistakes

**Mistake 1: Using assert for input validation**

```solidity
// WRONG — assert is for invariants, not validation
function withdraw(uint256 amount) external {
    assert(amount <= balances[msg.sender]); // Panic(0x01) if false
}

// CORRECT — use require or custom error for expected failures
error InsufficientBalance(uint256 available, uint256 requested);
function withdraw(uint256 amount) external {
    if (amount > balances[msg.sender]) {
        revert InsufficientBalance(balances[msg.sender], amount);
    }
}
```

`assert` signals "this should be impossible" — if it fires, it's a bug. Input validation is expected to fail sometimes — use `require` or custom errors so the caller gets a meaningful error.

**Mistake 2: Mixing string requires and custom errors inconsistently**

```solidity
// INCONSISTENT — harder to decode, confusing for integrators
function deposit(uint256 amount) external {
    require(amount > 0, "zero amount");              // Error(string)
    if (paused) revert Paused();                      // Custom error
    require(amount <= maxDeposit, "exceeds max");     // Error(string)
}

// CONSISTENT — all custom errors
error ZeroAmount();
error Paused();
error ExceedsMax(uint256 max, uint256 actual);
function deposit(uint256 amount) external {
    if (amount == 0) revert ZeroAmount();
    if (paused) revert Paused();
    if (amount > maxDeposit) revert ExceedsMax(maxDeposit, amount);
}
```

Pick one style per contract. Modern protocols use custom errors exclusively — they're cheaper, carry structured data, and are easier to decode programmatically.

---

<a id="custom-errors"></a>
### 💡 Concept: Custom Error Declarations

**Why this matters:** Custom errors (introduced in Solidity 0.8.4) are the modern standard for error handling in DeFi. They're cheaper than strings, carry structured parameters, and are the foundation for how production protocols communicate failures. Understanding their mechanics — declaration, inheritance, selectors, and gas implications — is essential for reading and writing production code.

**Declaration and scope:**

```solidity
// File-level — usable by any contract in the file
error Unauthorized(address caller);
error InsufficientBalance(uint256 required, uint256 actual);

contract Vault {
    // Contract-level — scoped to this contract (and inheritors)
    error DepositTooLarge(uint256 max, uint256 actual);

    function deposit(uint256 amount) external {
        if (msg.sender == address(0)) revert Unauthorized(msg.sender);
        if (amount > maxDeposit) revert DepositTooLarge(maxDeposit, amount);
    }
}
```

File-level errors are preferred when multiple contracts need the same error. Contract-level errors are useful when the error is specific to that contract's domain.

**Inheritance and interfaces:**

```solidity
interface IVault {
    error Unauthorized();
    error Paused();
}

contract BaseVault is IVault {
    // Can use errors from IVault without redeclaring
    function checkAccess() internal view {
        if (msg.sender != owner) revert Unauthorized();
    }
}

contract ChildVault is BaseVault {
    // Inherited errors are available here too
    function deposit() external {
        if (isPaused) revert Paused();
        checkAccess();
    }
}
```

Errors declared in interfaces serve as the contract's error API — integrators know exactly which errors to expect. This is why Uniswap V4's interfaces declare all errors up front.

**Custom errors with no parameters:**

```solidity
error Unauthorized();
error Paused();
error ZeroAddress();
```

These produce only 4 bytes of revert data (just the selector). Maximum gas efficiency — use them when the error name alone is descriptive enough.

**Gas comparison — real numbers:**

```
revert("unauthorized")           →  ~200 gas more (string encoding + larger returndata)
revert Unauthorized()            →  baseline (4 bytes, no encoding overhead)
revert Unauthorized(msg.sender)  →  ~20 gas more than no-param (one 32-byte word)
```

The savings come from two places: less bytecode in the deployed contract (no string literals stored) and less memory expansion at revert time (fewer bytes in returndata). For contracts that revert frequently (like routers checking many conditions), this adds up.

**Named parameters for readability:**

```solidity
// Without names — what do these numbers mean?
error SlippageExceeded(uint256, uint256);
// revert SlippageExceeded(950, 1000);  — which is expected, which is actual?

// With names — self-documenting
error SlippageExceeded(uint256 minExpected, uint256 actualReceived);
// revert SlippageExceeded(950, 1000);  — clear: expected 950, got 1000
```

Parameter names don't affect the selector or encoding — they're purely for readability in source code and tooling (Etherscan, Foundry traces). Always name your parameters.

💻 **Quick Try:**

Verify that error selectors work like function selectors:

```solidity
contract ErrorSelectors {
    error Transfer(address to, uint256 amount);

    function errorSelector() external pure returns (bytes4) {
        return Transfer.selector;
    }

    function manualSelector() external pure returns (bytes4) {
        return bytes4(keccak256("Transfer(address,uint256)"));
    }

    function areEqual() external pure returns (bool) {
        return Transfer.selector == bytes4(keccak256("Transfer(address,uint256)"));
    }
}
```

Call `areEqual()` — returns `true`. The `.selector` property on errors works identically to function selectors.

#### 🔗 DeFi Pattern Connection

**Where custom errors shape DeFi protocol design:**

1. **Uniswap V4 — error-driven interfaces**
   Uniswap V4's `IPoolManager` declares all errors in the interface. Integrators (hooks, routers) can match against these selectors to handle specific failure modes programmatically. When a swap fails, the router knows whether it was `PoolNotInitialized`, `InvalidTick`, or `InsufficientLiquidity` — each requires a different response.

2. **Aave V3 — error code libraries**
   Aave V3 uses a hybrid approach: custom errors with numeric codes defined in a `Errors` library. This lets them categorize errors by domain (validation errors, liquidity errors, oracle errors) while keeping the gas benefits of custom errors.

3. **OpenZeppelin 5.x — the migration from strings**
   OpenZeppelin 5.x migrated from string errors to custom errors across the entire library. `require(owner == msg.sender, "Ownable: caller is not the owner")` became `revert OwnableUnauthorizedAccount(msg.sender)`. This is the direction the entire ecosystem is moving.

**The pattern:** Modern DeFi protocols declare all errors in their interfaces, use descriptive parameter names, and never use string errors in new code. The error declarations serve as documentation — reading a protocol's errors tells you every way it can fail.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Why did you choose custom errors over require strings?"**
   - Good answer: Gas savings from smaller returndata and no string encoding
   - Great answer: Gas savings plus structured parameters that integrators can decode programmatically, plus they serve as the contract's failure API when declared in interfaces

2. **"How would you design the error hierarchy for a lending protocol?"**
   - Good answer: Group errors by domain — authorization, validation, liquidity, oracle
   - Great answer: Declare all errors in interfaces so integrators can match selectors, use descriptive parameters that carry enough context to diagnose without a trace, prefer parameterless errors for simple conditions and parameterized errors when the caller needs the values to react

**Interview Red Flags:**
- 🚩 Still using `require(cond, "string")` in new code
- 🚩 Declaring errors with unnamed parameters
- 🚩 Not knowing that custom errors produce different revert data than string errors

**Pro tip:** When reviewing a protocol's security, read its error declarations first. They tell you every failure mode the developers anticipated — and the ones they missed are where the bugs live.

---

## 📋 Key Takeaways: Solidity Error Primitives

After this section, you should be able to:

- Trace what bytecode `require`, `revert`, and `assert` each compile to, and explain how `assert` changed from INVALID (pre-0.8.0) to REVERT with Panic (0.8.0+)
- Explain why `require(cond, CustomError())` (0.8.26+) produces identical bytecode to `if (!cond) revert CustomError()` and why it removes the last reason to prefer string errors
- Design a custom error hierarchy for a DeFi protocol: file-level vs contract-level scope, interface declarations for integrators, parameterized vs parameterless based on caller needs
- Quantify the gas difference between string errors and custom errors and explain where the savings come from (bytecode size, memory expansion, returndata length)
- Read a pre-0.8.0 contract and identify where `assert` usage means INVALID opcode behavior (all gas consumed, no returndata)

<details>
<summary>Check your understanding</summary>

- **require, revert, assert bytecode**: `require` and `revert` both compile to REVERT (returns remaining gas, sends error data). Pre-0.8.0, `assert` compiled to INVALID (consumed all gas, no returndata); post-0.8.0, it compiles to REVERT with `Panic(uint256)` — same gas behavior as require, but with a panic code.
- **require with custom errors (0.8.26+)**: `require(cond, CustomError())` produces identical bytecode to `if (!cond) revert CustomError()`. This eliminates the last advantage of the if-revert pattern over require, making custom errors work cleanly with both syntax forms.
- **Custom error hierarchy design**: Declare errors in interfaces (for integrator access) or at file level (for shared use). Use parameters when callers need diagnostic data (e.g., `InsufficientBalance(uint256 available, uint256 required)`), omit them when the selector alone is sufficient to identify the failure.
- **Gas difference quantified**: A `revert InsufficientBalance()` with no parameters costs ~24 gas less than `require(false, "Insufficient balance")` due to smaller bytecode (no string literal stored) and smaller returndata (4 bytes vs ~100+ bytes). The savings compound across a contract with many revert sites.
- **Pre-0.8.0 assert behavior**: In contracts compiled before Solidity 0.8.0, every `assert` statement uses the INVALID opcode. If triggered, it consumes all forwarded gas and returns no data — making it impossible for the caller to know what went wrong. Identify these by checking the compiler version in the metadata.

</details>

---

## 💡 Error Propagation

You know how errors are created and encoded. Now the critical question: what happens to those error bytes as they travel through nested calls? In DeFi, transactions routinely chain 3-5+ contracts deep — a user calls a router, which calls a pool, which calls a token, which calls a hook. When something fails deep in that stack, how does the error reach the surface?

<a id="error-bubbling"></a>
### 💡 Concept: How Errors Travel Up the Call Stack

**Why this matters:** In a typical DeFi transaction — say, a swap through a router — the error might originate 3 or 4 calls deep. If propagation breaks at any level, the user sees a generic "execution reverted" instead of "InsufficientLiquidity" or "SlippageExceeded". Understanding how errors bubble up tells you where information gets lost and how to preserve it.

**Automatic bubbling in Solidity high-level calls:**

When you call another contract using Solidity's high-level syntax (e.g., `token.transfer(to, amount)`), a revert in the callee automatically reverts the caller with the same error data. No manual handling needed.

```solidity
contract Router {
    function swap(address pool, uint256 amount) external {
        // If Pool.execute reverts, Router.swap also reverts
        // with the SAME revert data — automatically
        IPool(pool).execute(amount);

        // This line never executes if execute() reverted
    }
}

contract Pool {
    function execute(uint256 amount) external {
        // If this reverts, the error data propagates up to Router
        require(reserves >= amount, "insufficient liquidity");
    }
}
```

```
User → Router.swap()
         └─► Pool.execute()
               └─► REVERT("insufficient liquidity")
                   │
                   │ Error data: 0x08c379a0...
                   │
              ◄────┘ Router sees success=false
              │
              │ Router ALSO reverts (automatic)
              │ with the SAME error data
              │
         ◄────┘ User sees: "insufficient liquidity"
```

This automatic bubbling is the default behavior for high-level calls. The compiler generates code that checks the return value and, if the sub-call failed, copies the returndata and reverts with it.

**What the compiler generates (simplified):**

```solidity
// IPool(pool).execute(amount) compiles roughly to:

// 1. Encode calldata
// 2. Make the call
(bool success, bytes memory returndata) = pool.call(
    abi.encodeWithSelector(IPool.execute.selector, amount)
);

// 3. If failed, bubble the error
if (!success) {
    assembly {
        revert(add(returndata, 0x20), mload(returndata))
    }
}

// 4. Decode return values (if any)
```

This is why high-level calls "just work" for error propagation — the compiler handles the bubble-up logic for you.

**Multi-level propagation:**

Errors propagate through as many levels as needed. Each frame copies the returndata and reverts:

```
User tx
 └─► Router.swap()
      └─► Pool.swap()
           └─► PriceOracle.getPrice()
                └─► REVERT StalePrice(lastUpdate, now)
                    │
                    │ returndata: 0x[StalePrice selector + params]
                    │
               ◄────┘ Pool receives returndata, auto-reverts with same data
          ◄────┘ Router receives returndata, auto-reverts with same data
     ◄────┘ User sees: StalePrice(lastUpdate, now)
```

The error data passes through untouched — Pool and Router don't modify it. The user (or their frontend) receives the original error from PriceOracle, 3 levels deep.

💻 **Quick Try:**

Verify multi-level error propagation:

```solidity
contract Level3 {
    error DeepError(uint256 depth);

    function fail() external pure {
        revert DeepError(3);
    }
}

contract Level2 {
    function callLevel3(address level3) external view {
        // High-level call — error auto-bubbles
        Level3(level3).fail();
    }
}

contract Level1 {
    function callLevel2(address level2, address level3) external view {
        Level2(level2).callLevel3(level3);
    }
}
```

Deploy all three, call `Level1.callLevel2()`. You'll see `DeepError(3)` in the revert — the original error from Level3 surfaces through two intermediate contracts.

#### 🔍 Deep Dive: Returndata at Each Call Frame

Each call frame has its own returndata buffer. When a sub-call reverts, the revert data lands in the caller's returndata buffer. Here's what happens at each level:

```
Frame 0 (Router)                    Frame 1 (Pool)                   Frame 2 (Oracle)
┌──────────────────┐                ┌──────────────────┐             ┌──────────────────┐
│                  │                │                  │             │                  │
│ returndata: empty│  ─── CALL ──► │ returndata: empty│ ─── CALL ─►│ returndata: N/A  │
│                  │                │                  │             │                  │
│                  │                │                  │             │ REVERT(data)     │
│                  │                │                  │ ◄───────── │                  │
│                  │                │ returndata: data │             └──────────────────┘
│                  │                │                  │
│                  │                │ // Auto-bubble:  │
│                  │                │ REVERT(data)     │
│                  │ ◄──────────── │                  │
│ returndata: data │                └──────────────────┘
│                  │
│ // Auto-bubble:  │
│ REVERT(data)     │
└──────────────────┘
```

At each level, the returndata buffer is populated by the sub-call's revert, then the current frame reverts with those same bytes. The data passes through unchanged.

**When returndata gets lost:**

The returndata buffer is overwritten by every external call. If a frame makes another call after catching an error, the original error data is gone from the buffer:

```solidity
function riskyPattern(address a, address b) external {
    (bool s1, bytes memory err) = a.call(payload1);
    // returndata buffer = error from a

    (bool s2, ) = b.call(payload2);
    // returndata buffer = result from b (error from a is GONE from buffer)
    // BUT: err variable still holds a's error (Solidity copied it to memory)

    if (!s1) {
        // Can still use err here — it was copied to memory
        assembly {
            revert(add(err, 0x20), mload(err))
        }
    }
}
```

This is why Solidity copies returndata into a `bytes memory` variable immediately — the buffer itself is volatile.

---

<a id="low-level-errors"></a>
### 💡 Concept: Low-Level Calls — Manual Error Handling

**Why this matters:** Low-level calls (`call`, `staticcall`, `delegatecall`) don't automatically revert on failure — they return `(bool success, bytes memory data)` and let you decide what to do. This is both powerful and dangerous: powerful because you can handle errors selectively, dangerous because forgetting to check `success` means the error is silently swallowed.

**The basic pattern:**

```solidity
(bool success, bytes memory data) = target.call(
    abi.encodeWithSelector(IToken.transfer.selector, to, amount)
);

if (!success) {
    // Option 1: Bubble the error (same as high-level call behavior)
    assembly {
        revert(add(data, 0x20), mload(data))
    }

    // Option 2: Wrap with context
    // revert TransferFailed(token, to, amount);

    // Option 3: Handle gracefully (rare — usually only in multicall patterns)
    // return false;
}
```

**Why assembly for error bubbling?**

```solidity
// You might wonder: why not just revert(string(data))?
// Because data isn't a string — it's ABI-encoded error data.
// You need to forward the raw bytes:

assembly {
    // data is a bytes memory variable
    // add(data, 0x20) skips the length prefix to get to the actual bytes
    // mload(data) reads the length
    revert(add(data, 0x20), mload(data))
}
```

This is the standard error bubbling pattern — you'll see it in OpenZeppelin's `Address.sol`, Solady, and virtually every production codebase that uses low-level calls.

💻 **Quick Try:**

Compare high-level and low-level error handling:

```solidity
contract Target {
    error NotAllowed(address caller);

    function restricted() external view {
        revert NotAllowed(msg.sender);
    }
}

contract Caller {
    // High-level — auto-bubbles
    function highLevel(address target) external view {
        Target(target).restricted(); // Automatically reverts with NotAllowed
    }

    // Low-level — manual handling required
    function lowLevel(address target) external view returns (bool, bytes memory) {
        (bool success, bytes memory data) = target.staticcall(
            abi.encodeWithSelector(Target.restricted.selector)
        );
        // success = false, data = encoded NotAllowed error
        return (success, data); // Return it instead of reverting
    }
}
```

Call `highLevel` — it reverts with `NotAllowed`. Call `lowLevel` — it succeeds and returns the error data as a return value. Same underlying error, different handling.

#### ⚠️ Common Mistakes: Silent Success on Empty Addresses

**The trap:** A low-level `call` to an address with no code (EOA or undeployed contract) succeeds silently with empty returndata. This is EVM behavior, not a Solidity bug.

```solidity
address emptyAddress = address(0xdead); // No code deployed here

// This SUCCEEDS — success = true, data = empty
(bool success, bytes memory data) = emptyAddress.call(
    abi.encodeWithSelector(IToken.transfer.selector, to, amount)
);
// success is TRUE even though no transfer happened!
```

**Why this happens:** The EVM's CALL opcode checks if the target has code. If it doesn't, the call succeeds immediately with no execution — there's nothing to run, so nothing fails. The returndata is empty (0 bytes), which is indistinguishable from a function that returns nothing.

**The protection:**

```solidity
// Check code size before calling
if (target.code.length == 0) revert NoCode(target);

// Or use OpenZeppelin's Address library / Solady's SafeTransferLib
// which includes this check
```

This is exactly why `SafeTransferLib` and `SafeERC20` exist — they check for code existence before calling token functions. Without this check, a `transfer` call to an empty address "succeeds" silently — the caller's state updates proceed as if the transfer worked, but no token contract logic actually ran. The tokens aren't moved anywhere; the caller is simply deceived into thinking the operation completed.

**Where this bites in DeFi:**

- Calling a token that was self-destructed (pre-Dencun)
- Calling a contract on the wrong chain (address exists on mainnet but not on L2)
- Calling a proxy whose implementation was deleted
- User provides wrong contract address

#### 🔗 DeFi Pattern Connection

**Where low-level error handling is essential in DeFi:**

1. **Token transfers — the SafeERC20/SafeTransferLib pattern**
   Some tokens (notably USDT) don't return a bool from `transfer()`. A high-level call expects a return value and reverts when it's missing. Low-level calls sidestep this by not requiring a specific return format. This is why SafeERC20 uses low-level calls with manual success checking.

2. **DEX aggregators — partial failure tolerance**
   Aggregators like 1inch route through multiple pools. If one pool fails, the aggregator catches the error and tries an alternative route rather than reverting the entire transaction. This requires low-level calls to prevent automatic bubbling.

3. **Keeper/bot operations — error collection**
   Liquidation bots attempt multiple liquidations in a single transaction. Each attempt uses a low-level call so that one failed liquidation doesn't abort the others. The bot collects error data for logging.

**The pattern:** Use high-level calls when you want automatic bubbling (most cases). Use low-level calls when you need to handle failure without reverting — multicall, aggregators, or when interfacing with non-standard contracts.

---

<a id="proxy-errors"></a>
### 💡 Concept: Propagation Through Proxies

**Why this matters:** Most DeFi protocols are deployed behind proxies (UUPS, Transparent, Diamond). When a function in the implementation contract reverts, the error must travel through the proxy's `delegatecall` back to the caller. Understanding how this works — and where it can break — is essential for debugging proxy-based protocols.

**How delegatecall propagates errors:**

```
User → Proxy.fallback()
         │
         │ DELEGATECALL to Implementation
         │ (executes in Proxy's storage context)
         │
         └─► Implementation.deposit()
               └─► REVERT InsufficientBalance(100, 50)
                   │
                   │ returndata: 0x[InsufficientBalance encoded]
                   │
              ◄────┘ DELEGATECALL returns success=false + returndata
         │
         │ Proxy's fallback forwards returndata:
         │ assembly {
         │     returndatacopy(0, 0, returndatasize())
         │     revert(0, returndatasize())  // if delegatecall failed
         │     // OR: return(0, returndatasize())  // if delegatecall succeeded
         │ }
         │
    ◄────┘ User sees: InsufficientBalance(100, 50)
```

The proxy's fallback function is the key piece. It uses `delegatecall`, then forwards the returndata regardless of whether it was a success or failure. This is why you see the same assembly pattern in every proxy implementation:

```solidity
// From OpenZeppelin's Proxy.sol — the universal forwarding pattern
fallback() external payable {
    address impl = _implementation();
    assembly {
        calldatacopy(0, 0, calldatasize())
        let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }   // forward revert data
        default { return(0, returndatasize()) }   // forward return data
    }
}
```

**Errors are transparent through proxies:** The user doesn't know or care that a proxy is involved — they see the implementation's errors directly. This works because `delegatecall` preserves the returndata exactly as the implementation produced it.

**When proxy error propagation breaks:**

1. **Missing fallback forwarding:** If the proxy's fallback doesn't forward returndata (e.g., it uses `revert()` instead of `revert(0, returndatasize())`), the original error is lost.

2. **Proxy-level reverts:** If the proxy itself reverts before reaching the `delegatecall` (e.g., access control on admin functions), the error comes from the proxy, not the implementation. This can be confusing during debugging.

3. **Implementation re-initialization:** If someone calls `initialize()` on a proxy that's already initialized, the error comes from the implementation — but the user called the proxy address. Knowing that errors propagate transparently through `delegatecall` helps you trace the source.

#### 📖 How to Study: Proxy Error Flows

1. **Start with OpenZeppelin's Proxy.sol** — read the fallback function. It's ~10 lines and shows the universal forwarding pattern
2. **Compare UUPS vs Transparent** — notice how the error forwarding is identical in both. The proxy type affects upgrades, not error handling
3. **Test with Foundry** — deploy a proxy + implementation, trigger a revert, and verify you see the implementation's error
4. **Read the Diamond standard (EIP-2535)** — it uses the same pattern per facet, with an extra selector lookup step before the `delegatecall`

---

<a id="constructor-reverts"></a>
### 💡 Concept: Constructor Reverts

**Why this matters:** When a contract deployment fails — whether via `CREATE` or `CREATE2` — the behavior is different from regular call reverts. Understanding this is important for factory patterns, deterministic deployment, and debugging failed deployments.

**CREATE/CREATE2 failure behavior:**

```
Regular CALL failure:
  └─► success = false, returndata = error bytes, address = N/A

CREATE failure:
  └─► success = false (returned address = 0), returndata = error bytes

CREATE2 failure:
  └─► success = false (returned address = 0), returndata = error bytes
```

Since Solidity 0.4.22, constructor reverts return error data just like regular reverts. The caller receives `address(0)` as the deployed address and can read the returndata for the error.

**Constructor revert in practice:**

```solidity
contract Token {
    constructor(string memory name) {
        require(bytes(name).length > 0, "empty name");
    }
}

contract Factory {
    function deploy(string memory name) external returns (address) {
        // If constructor reverts, this entire call reverts
        // with the constructor's error data
        Token token = new Token(name);
        return address(token);
    }

    function safeDeploy(string memory name) external returns (address) {
        // Low-level CREATE to handle failure without reverting
        bytes memory bytecode = abi.encodePacked(
            type(Token).creationCode,
            abi.encode(name)
        );

        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        if (addr == address(0)) {
            revert("deployment failed");
        }

        return addr;
    }
}
```

**CREATE2 and deterministic addresses:**

With CREATE2, a failed deployment is particularly important to handle: the salt is NOT consumed — since the constructor reverted, the address was never occupied, and a future deployment with the same salt and bytecode will succeed at the same predicted address. But if the failure isn't detected, the caller might think the contract exists at the predicted address when it doesn't.

```solidity
// Predicted address exists — but is there actually code there?
address predicted = computeCreate2Address(salt, bytecodeHash);

// After a failed CREATE2, predicted has no code
// Always verify: predicted.code.length > 0
```

---

## 📋 Key Takeaways: Error Propagation

After this section, you should be able to:

- Explain how Solidity's high-level calls automatically bubble errors by checking the return value and reverting with the same returndata, and identify the compiler-generated code that does this
- Write the standard error bubbling pattern for low-level calls using assembly (`revert(add(data, 0x20), mload(data))`) and explain why raw bytes must be forwarded rather than decoded
- Explain why a low-level call to an address with no code succeeds silently and describe the protection patterns (code length check, SafeERC20) that prevent this
- Trace error propagation through a proxy's `delegatecall` fallback and explain why errors are transparent to the caller — they see the implementation's errors directly
- Describe how constructor reverts differ from regular call reverts (address(0) return, CREATE2 salt implications) and handle them in factory patterns

<details>
<summary>Check your understanding</summary>

- **Automatic error bubbling**: Solidity high-level calls (e.g., `token.transfer(to, amount)`) check the return value and, on failure, automatically revert with the callee's returndata. The compiler generates `if iszero(call(...)) { returndatacopy(...); revert(...) }` — forwarding the exact error bytes.
- **Assembly error bubbling pattern**: For low-level calls, use `revert(add(data, 0x20), mload(data))` to forward raw revert bytes. This skips decoding entirely — you pass the bytes through as-is, preserving the original error for the caller above you.
- **No-code address trap**: A low-level call to an address with no deployed code succeeds silently (returns success=1, empty returndata). Protection requires checking `extcodesize > 0` before the call, or using SafeERC20 which includes this check.
- **Proxy delegatecall transparency**: A proxy's fallback does `delegatecall` to the implementation, then forwards return/revert data. Errors from the implementation appear as if they came from the proxy — the caller sees the implementation's error selectors directly.
- **Constructor revert behavior**: A reverted constructor returns address(0) from CREATE/CREATE2. With CREATE2, the salt is NOT consumed on failure — the address was never occupied, so a future deployment with the same salt and init code will succeed at the same predicted address. But if the failure goes undetected, the caller may assume a contract exists at the predicted address when it doesn't. Factory patterns must check `address != 0` after deployment.

</details>

---

## 💡 Try/Catch

Solidity's `try/catch` is the language-level mechanism for intercepting errors from external calls without reverting your own frame. It looks straightforward — but the details of which clause catches what, and what it fundamentally cannot catch, trip up even experienced developers.

<a id="four-clauses"></a>
### 💡 Concept: The Four Catch Clauses

**Why this matters:** `try/catch` has four distinct catch clause forms, each matching a different error format. Using the wrong clause means your error falls through to an unexpected handler — or isn't caught at all. Knowing which clause catches which format is the direct application of the error encoding knowledge from earlier sections.

**The four forms:**

```solidity
try target.someFunction() returns (uint256 result) {
    // Success path — use result
} catch Error(string memory reason) {
    // Catches: require(cond, "message") and revert("message")
    // Format:  Error(string) — selector 0x08c379a0
} catch Panic(uint256 code) {
    // Catches: assert failures, overflow, division by zero
    // Format:  Panic(uint256) — selector 0x4e487b71
} catch (bytes memory lowLevelData) {
    // Catches: custom errors, or any revert data that didn't match above
    // Format:  raw bytes — you decode manually
} catch {
    // Catches: anything not caught above, including empty revert data
    // No access to the error data
}
```

**The matching order matters:**

Solidity tries each clause top to bottom. The first matching clause handles the error:

```
Revert data arrives
  │
  ├─ Selector == 0x08c379a0?  →  catch Error(string memory reason)
  │
  ├─ Selector == 0x4e487b71?  →  catch Panic(uint256 code)
  │
  ├─ Has bytes data?          →  catch (bytes memory lowLevelData)
  │
  └─ Bare catch?              →  catch { }
```

**You don't need all four.** Use only the clauses you need:

```solidity
// Pattern 1: Catch everything with raw bytes (most flexible)
try target.doSomething() {
    // success
} catch (bytes memory data) {
    // Handle ALL error types — decode manually if needed
}

// Pattern 2: Separate string errors from everything else
try target.doSomething() {
    // success
} catch Error(string memory reason) {
    // String errors only
} catch (bytes memory data) {
    // Custom errors, panics, and anything else
}

// Pattern 3: Just know it failed (no error data needed)
try target.doSomething() {
    // success
} catch {
    // Failed — don't care why
}
```

**The `returns` clause:**

The `try` statement can capture return values on success:

```solidity
// Without returns — just check success/failure
try oracle.getPrice(token) {
    // Succeeded, but we didn't capture the price
} catch { }

// With returns — capture the return value
try oracle.getPrice(token) returns (uint256 price) {
    // price is available here
    latestPrice = price;
} catch {
    // Use stale price or revert
}
```

The `returns` types must match the called function's return signature exactly.

💻 **Quick Try:**

Test all four catch clauses:

```solidity
contract Thrower {
    error CustomError(uint256 code);

    function throwString() external pure { revert("bad"); }
    function throwCustom() external pure { revert CustomError(42); }
    function throwPanic() external pure { assert(false); }
    function throwBare() external pure { revert(); }
}

contract Catcher {
    event Caught(string which, bytes data);

    function catchString(address thrower) external {
        try Thrower(thrower).throwString() {
        } catch Error(string memory reason) {
            emit Caught("Error(string)", bytes(reason));
        } catch Panic(uint256 code) {
            emit Caught("Panic", abi.encode(code));
        } catch (bytes memory data) {
            emit Caught("bytes", data);
        } catch {
            emit Caught("bare", "");
        }
    }

    function catchCustom(address thrower) external {
        try Thrower(thrower).throwCustom() {
        } catch Error(string memory reason) {
            emit Caught("Error(string)", bytes(reason));
        } catch Panic(uint256 code) {
            emit Caught("Panic", abi.encode(code));
        } catch (bytes memory data) {
            emit Caught("bytes", data);
        } catch {
            emit Caught("bare", "");
        }
    }

    function catchPanic(address thrower) external {
        try Thrower(thrower).throwPanic() {
        } catch Error(string memory reason) {
            emit Caught("Error(string)", bytes(reason));
        } catch Panic(uint256 code) {
            emit Caught("Panic", abi.encode(code));
        } catch (bytes memory data) {
            emit Caught("bytes", data);
        } catch {
            emit Caught("bare", "");
        }
    }

    function catchBare(address thrower) external {
        try Thrower(thrower).throwBare() {
        } catch Error(string memory reason) {
            emit Caught("Error(string)", bytes(reason));
        } catch Panic(uint256 code) {
            emit Caught("Panic", abi.encode(code));
        } catch (bytes memory data) {
            emit Caught("bytes", data);
        } catch {
            emit Caught("bare", "");
        }
    }
}
```

Call each function and check which event fires. `catchString` → `Error(string)`, `catchPanic` → `Panic`, `catchCustom` → `bytes` (custom errors don't have a dedicated clause), `catchBare` → `bytes` with empty data (or `bare` if no `bytes` clause).

#### 🔍 Deep Dive: Which Clause Triggers When

Let's be precise about what each clause matches:

```
Error data                          Matched clause
──────────────────────────────────  ───────────────────────────
0x08c379a0 + valid string encoding  catch Error(string memory)
0x08c379a0 + invalid encoding       catch (bytes memory)  ← NOT Error!
0x4e487b71 + valid uint256          catch Panic(uint256)
0x4e487b71 + invalid encoding       catch (bytes memory)  ← NOT Panic!
Any other selector + data           catch (bytes memory)
Empty (0 bytes)                     catch (bytes memory) with empty bytes
                                    OR catch { } if no bytes clause
```

**Key subtlety:** `catch Error(string memory)` doesn't just check the selector — it also verifies that the remaining bytes are valid ABI-encoded string data. If the selector matches but the encoding is malformed, it falls through to `catch (bytes memory)`. Same for `catch Panic(uint256)`.

This means `catch (bytes memory)` is the true catch-all for any revert data. The bare `catch` only catches what falls through everything else — which in practice is only when you don't have a `catch (bytes memory)` clause.

**What happens with no matching clause:**

If the revert data doesn't match any of your catch clauses and there's no catch-all, the error **propagates up** as if there were no try/catch at all. Your function reverts with the original error data.

```solidity
// DANGEROUS — custom errors propagate uncaught!
try target.doSomething() {
} catch Error(string memory reason) {
    // Only catches string errors
}
// If target reverts with a custom error → your function reverts too
// The try/catch provided no protection for custom errors
```

Always include `catch (bytes memory)` or bare `catch` if you want to catch all possible errors.

#### ⚠️ Common Mistakes

**Mistake 1: Assuming catch Error catches custom errors**

```solidity
// WRONG — custom errors are NOT caught by catch Error
try target.withdraw(amount) {
} catch Error(string memory reason) {
    // This catches: require(cond, "msg"), revert("msg")
    // This does NOT catch: revert InsufficientBalance(100, 50)
    emit WithdrawFailed(reason);
}
// Custom error from withdraw() propagates as if try/catch wasn't there!

// CORRECT — use catch (bytes memory) to catch everything
try target.withdraw(amount) {
} catch Error(string memory reason) {
    emit WithdrawFailed(reason);
} catch (bytes memory data) {
    // Custom errors land here
    emit WithdrawFailedRaw(data);
}
```

**Mistake 2: Using try/catch on internal calls**

```solidity
// WRONG — try/catch only works on EXTERNAL calls
function process() internal {
    try this.internalHelper() { } catch { }
    //   ^^^^ This won't compile — internalHelper is internal
}

// ALSO WRONG — calling yourself externally just to use try/catch
function process() external {
    try this.riskyOperation() { } catch { }
    //  ^^^^ This "works" but creates an unnecessary external call
    //  with its own gas cost and msg.sender change
}
```

`try/catch` requires an external call — it's built on top of the CALL opcode's success/failure mechanism. For internal error handling, use regular `if` checks or low-level call patterns.

**Mistake 3: Modifying state before the try block**

```solidity
// DANGEROUS — state changes before try persist even if the try fails
function deposit(uint256 amount) external {
    balances[msg.sender] += amount;  // This persists!

    try token.transferFrom(msg.sender, address(this), amount) {
        // Transfer succeeded
    } catch {
        // Transfer failed — but balance was already updated!
        // Now user has credit without depositing tokens
    }
}

// CORRECT — modify state after confirming success
function deposit(uint256 amount) external {
    try token.transferFrom(msg.sender, address(this), amount) {
        balances[msg.sender] += amount;  // Only on success
    } catch {
        revert DepositFailed();
    }
}
```

Remember: `try/catch` catches the sub-call's revert, but your own frame's state changes persist. This is the same frame-level rollback behavior from the EVM Failure Modes section — only the called frame's changes are rolled back.

---

<a id="try-catch-limits"></a>
### 💡 Concept: What Try/Catch Cannot Catch

**Why this matters:** `try/catch` has fundamental limitations that stem from how the EVM works. Knowing these boundaries prevents you from building on false assumptions — thinking you've handled all error cases when you haven't.

**Limitation 1: Cannot catch out-of-gas in the current frame**

```solidity
try target.doSomething{gas: 100000}() {
    // success
} catch {
    // Catches: reverts inside doSomething
    // Does NOT catch: running out of gas AFTER the try/catch returns
}

// If the outer function itself runs out of gas, there's no try/catch
// that can save it — the entire transaction reverts
```

The 63/64 rule means the outer frame retains ~1.5% of gas, which is usually enough to enter the catch block. But if the catch block itself needs significant gas (storage writes, events), it might fail too.

**Limitation 2: Cannot catch errors in the same contract without external call**

```solidity
contract MyContract {
    function risky() public pure {
        revert("boom");
    }

    function safe() external {
        // WRONG — can't try/catch an internal call
        // try risky() { } catch { }  // Won't compile

        // WORKS but wasteful — external call to self
        try this.risky() {
        } catch {
            // Caught, but paid for external call overhead
            // Also: msg.sender changed to address(this)
        }
    }
}
```

**Limitation 3: Creation failures consume all CREATE gas**

```solidity
// Using try/catch with new:
try new Token(name) returns (Token token) {
    // Deployment succeeded
} catch (bytes memory data) {
    // Constructor reverted — you get the error data
    // But the CREATE gas is consumed
}
```

This works since Solidity 0.6.0, but note that you pay for the creation attempt even on failure.

**Limitation 4: The gas bomb problem**

A malicious contract can return huge amounts of data in its revert:

```solidity
contract Malicious {
    function attack() external pure {
        assembly {
            // Return 1MB of revert data
            revert(0, 1048576)
        }
    }
}

contract Victim {
    function callMalicious(address target) external {
        try Malicious(target).attack() {
        } catch (bytes memory data) {
            // data is 1MB — copying it into memory costs a LOT of gas
            // The memory expansion cost can drain all remaining gas
        }
    }
}
```

This is the "returnbomb" attack. When your catch clause accepts `bytes memory data`, Solidity copies all returndata into memory. If the returndata is maliciously large, the memory expansion cost can consume all your gas. The defense is to limit returndata size using assembly-level `returndatacopy` or use libraries like Solady that cap the copy size.

#### 🔗 DeFi Pattern Connection

**Where try/catch limitations matter in DeFi:**

1. **Oracle fallbacks**
   Lending protocols use try/catch to query oracles: if the primary oracle (Chainlink) reverts or returns stale data, fall back to a secondary oracle (TWAP). The catch clause must handle both string errors (old oracles) and custom errors (new oracles), and must guard against the returnbomb from a compromised oracle.

2. **Hook systems (Uniswap V4)**
   When the PoolManager calls a hook contract, it uses try/catch to handle hook failures. If a hook reverts, the PoolManager can decide whether to abort the swap or continue without the hook. The limitation is that if the hook consumes all gas (malicious hook), the catch block may not execute.

3. **Token approval race conditions**
   Some protocols try/catch the first `approve(0)` call before setting a new approval. If the token doesn't require zero-first (most don't), the catch block handles the revert gracefully.

**The pattern:** try/catch in DeFi is primarily used for graceful degradation — oracle fallbacks, optional features, and non-critical operations that shouldn't abort the main transaction.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you implement oracle fallback logic?"**
   - Good answer: Use try/catch around the primary oracle call, fall back to secondary on failure
   - Great answer: Use try/catch with `catch (bytes memory)` to handle all error formats, cap returndata size to prevent returnbomb attacks, validate the fallback oracle's response freshness, and consider the gas budget — ensure the catch path has enough gas for the fallback call

2. **"What are the limitations of try/catch in Solidity?"**
   - Good answer: Only works on external calls, can't catch out-of-gas in current frame
   - Great answer: Only works on external calls, can't catch out-of-gas in current frame, `catch Error` doesn't catch custom errors, state changes before the try persist in the catch path, and the returnbomb vulnerability when catching arbitrary bytes from untrusted contracts

**Interview Red Flags:**
- 🚩 Using try/catch with only `catch Error(string)` and thinking all errors are handled
- 🚩 Not knowing that state changes before `try` persist in the `catch` block
- 🚩 Not considering the returnbomb attack when catching errors from untrusted contracts

**Pro tip:** When you see try/catch in a protocol's code, immediately ask: "What error formats can the callee produce, and does this catch clause handle all of them?" This one question catches a surprising number of bugs in audits.

---

## 📋 Key Takeaways: Try/Catch

After this section, you should be able to:

- List the four catch clause forms (Error, Panic, bytes, bare), explain which error format each matches, and describe the matching order — including the subtlety that malformed encoding falls through to the bytes clause
- Identify the "custom errors aren't caught by catch Error" trap and write try/catch blocks that handle all error formats using `catch (bytes memory)`
- Explain why state changes before the try block persist in the catch path and design deposit/withdrawal patterns that avoid the resulting consistency bugs
- Describe the returnbomb attack, explain why it's possible through try/catch, and name the defense (capping returndata copy size)
- Design an oracle fallback pattern using try/catch that handles all error formats, guards against returnbomb, and ensures enough gas for the fallback path

<details>
<summary>Check your understanding</summary>

- **Four catch clauses and matching order**: `catch Error(string)` matches `Error(string)` selector. `catch Panic(uint256)` matches `Panic(uint256)` selector. `catch (bytes memory)` catches everything else including custom errors and malformed data. Bare `catch` catches everything but gives no access to the error data. Malformed encoding (e.g., truncated string) falls through to the bytes clause.
- **Custom errors and try/catch**: Custom errors are NOT caught by `catch Error(string)` — they fall through to `catch (bytes memory)` or bare `catch`. This is a common trap: if you only have `catch Error` and `catch Panic` clauses, custom errors from the callee will cause an unhandled revert.
- **State persistence in catch path**: State changes made BEFORE the `try` statement persist even if the catch path executes. This can cause consistency bugs: if you update a balance before the try and the call fails, the balance is still modified. Design patterns must account for this — update state after confirmed success.
- **Returnbomb attack**: A malicious callee returns megabytes of data, forcing the caller to pay for memory expansion when `catch (bytes memory)` copies all returndata into memory. Defense: cap `returndatasize()` before copying, or use assembly-level `returndatacopy` with a bounded size.
- **Oracle fallback pattern**: Use `try oracle.latestRoundData() returns (...)` with a `catch (bytes memory)` clause that falls back to a secondary oracle. Cap returndata size to prevent returnbomb, and use `gasleft()` checks to ensure enough gas remains for the fallback path.

</details>

---

## 💡 Decoding & Detection

You've learned how errors are encoded, how they propagate, and how to catch them. Now the practical skill: taking raw revert bytes and turning them into something useful. This is what you do when debugging failed transactions, building error-handling middleware, or writing comprehensive Foundry tests.

<a id="decoding-revert"></a>
### 💡 Concept: Decoding Raw Revert Data

**Why this matters:** When you catch error data from a low-level call or a `catch (bytes memory)` clause, you have raw bytes. To react meaningfully — log the error, retry with different parameters, or surface it to users — you need to decode those bytes back into structured data.

**The universal decoding algorithm:**

```solidity
function decodeError(bytes calldata data) external pure returns (string memory) {
    // Case 1: No data
    if (data.length == 0) {
        return "empty revert (bare revert, INVALID, or out-of-gas)";
    }

    // Case 2: Too short for a selector
    if (data.length < 4) {
        return "malformed revert data (< 4 bytes)";
    }

    // Extract selector (calldata slicing works cleanly here)
    bytes4 selector = bytes4(data[:4]);

    // Case 3: String error
    if (selector == 0x08c379a0) {
        // Skip selector, decode — abi.decode handles the offset pointer automatically
        string memory reason = abi.decode(data[4:], (string));
        return reason;
    }

    // Case 4: Panic code
    if (selector == 0x4e487b71) {
        uint256 code = abi.decode(data[4:], (uint256));
        if (code == 0x01) return "Panic: assert failed";
        if (code == 0x11) return "Panic: overflow";
        if (code == 0x12) return "Panic: division by zero";
        if (code == 0x32) return "Panic: index out of bounds";
        return "Panic: unknown code";
    }

    // Case 5: Custom error — need ABI to decode further
    return "custom error (use selector for ABI lookup)";
}
```

Note: this function uses `calldata` because calldata slicing (`data[4:]`) is clean and gas-efficient. If you're working with `bytes memory` from a low-level call, you need assembly to extract the selector and slice:

```solidity
bytes4 selector;
assembly { selector := mload(add(data, 0x20)) }
```

**In practice, a simpler approach for bubbling:**

Most of the time you don't need to decode — you just need to forward the raw bytes:

```solidity
(bool success, bytes memory data) = target.call(payload);
if (!success) {
    // Don't decode — just bubble
    assembly {
        revert(add(data, 0x20), mload(data))
    }
}
```

Decoding is for when you need to make decisions based on the error type, or when you need to log/display the error.

**Decoding known custom errors:**

When you know the error signature, decoding is straightforward:

```solidity
error InsufficientBalance(uint256 required, uint256 actual);

(bool success, bytes memory data) = target.call(payload);
if (!success && data.length >= 4) {
    bytes4 selector;
    assembly { selector := mload(add(data, 0x20)) }

    if (selector == InsufficientBalance.selector) {
        // Slice off the selector and decode
        (uint256 required, uint256 actual) = abi.decode(
            _sliceAfterSelector(data), (uint256, uint256)
        );
        // Now you can use required and actual
        emit BalanceShortfall(required, actual);
    }
}
```

**Slicing the selector off:**

There's no built-in way to slice `bytes memory` in Solidity. The common pattern:

```solidity
// Assembly approach (gas-efficient)
// WARNING: mutates memory in place — original `data` is corrupted after this call
function _sliceAfterSelector(bytes memory data) internal pure returns (bytes memory result) {
    assembly {
        result := add(data, 0x04)          // shift pointer past selector
        mstore(result, sub(mload(data), 4)) // adjust length (overwrites selector bytes)
    }
}

// Or use abi.decode with the offset trick:
// abi.decode expects data WITHOUT the selector, so you need to slice
```

💻 **Quick Try:**

Build a minimal error decoder in Remix:

```solidity
contract Decoder {
    function decodeRevert(bytes calldata data) external pure returns (string memory) {
        if (data.length == 0) return "empty";
        if (data.length < 4) return "too short";

        bytes4 sel = bytes4(data[:4]);

        if (sel == 0x08c379a0) {
            // String error — decode the reason
            string memory reason = abi.decode(data[4:], (string));
            return string.concat("Error: ", reason);
        }

        if (sel == 0x4e487b71) {
            uint256 code = abi.decode(data[4:], (uint256));
            if (code == 0x01) return "Panic: assert failed";
            if (code == 0x11) return "Panic: overflow";
            if (code == 0x12) return "Panic: division by zero";
            return "Panic: unknown code";
        }

        return "custom error";
    }
}
```

Feed it the raw bytes from earlier Quick Tries and verify it correctly identifies each error type. Note how `data[4:]` (calldata slicing) works cleanly here — this is one advantage of `calldata` over `memory` for byte slicing.

#### 🔍 Deep Dive: Building a Universal Error Decoder

A production-grade error decoder handles edge cases that the simple version above doesn't:

**1. Decoding nested errors (error wrapping):**

Some protocols wrap errors with additional context:

```solidity
error SwapFailed(address pool, bytes innerError);

// When caught:
// data = SwapFailed.selector + abi.encode(pool, innerError)
// innerError itself might be another encoded error
```

To decode nested errors, you decode the outer error first, then recursively decode the `innerError` bytes. This is how Foundry shows nested error traces.

**2. Using `abi.decode` with calldata slicing:**

Solidity 0.8.x supports calldata slicing (`data[4:]`), which is cleaner and cheaper than memory slicing:

```solidity
function handleError(bytes calldata data) external pure {
    if (bytes4(data[:4]) == InsufficientBalance.selector) {
        (uint256 required, uint256 actual) = abi.decode(
            data[4:],  // calldata slice — no copy needed
            (uint256, uint256)
        );
    }
}
```

But this only works with `calldata` parameters — not `bytes memory` from a low-level call's return. For memory bytes, you need the assembly slice or a helper library.

**3. Selector lookup services:**

When you have an unknown selector, tools can help:
- `cast 4byte <selector>` (Foundry) — reverse-looks up a selector from the 4byte.directory database
- `cast 4byte-decode <calldata>` (Foundry) — decodes entire calldata or error data given the raw hex
- Etherscan's "Decode" button on transaction reverts
- Tenderly's transaction trace view shows decoded errors automatically

---

<a id="foundry-errors"></a>
### 💡 Concept: Foundry Error Testing

**Why this matters:** Foundry's testing framework has specific cheatcodes and patterns for testing error conditions. Knowing these patterns lets you write comprehensive tests that verify not just that a function reverts, but that it reverts with the exact right error.

**`vm.expectRevert` — the core cheatcode:**

```solidity
// Expect any revert (don't care about the error)
vm.expectRevert();
target.functionThatReverts();

// Expect a specific string error
vm.expectRevert("insufficient balance");
target.withdraw(tooMuch);

// Expect a specific custom error
vm.expectRevert(abi.encodeWithSelector(
    InsufficientBalance.selector, 1000, 500
));
target.withdraw(1000);

// Shorthand for custom errors (Foundry convenience)
vm.expectRevert(InsufficientBalance.selector);
target.withdraw(1000);  // Only checks selector, not params
```

**Testing specific panic codes:**

```solidity
// Expect arithmetic overflow
vm.expectRevert(abi.encodeWithSelector(bytes4(0x4e487b71), uint256(0x11)));
target.overflowingFunction();

// Or use the stdError library (forge-std)
import {stdError} from "forge-std/StdError.sol";

vm.expectRevert(stdError.arithmeticError);  // Panic(0x11)
target.overflowingFunction();

vm.expectRevert(stdError.divisionError);    // Panic(0x12)
target.divideByZero();

vm.expectRevert(stdError.indexOOBError);    // Panic(0x32)
target.accessOutOfBounds();

vm.expectRevert(stdError.assertionError);   // Panic(0x01)
target.failedAssert();
```

**Testing that a function does NOT revert:**

There's no `vm.expectNoRevert()` — just call the function normally. If it reverts, the test fails automatically.

**Testing revert data from low-level calls:**

```solidity
function test_lowLevelCallError() public {
    (bool success, bytes memory data) = address(target).call(
        abi.encodeWithSelector(target.restricted.selector)
    );

    assertFalse(success);
    bytes4 selector;
    assembly { selector := mload(add(data, 0x20)) }
    assertEq(selector, Unauthorized.selector);

    // Decode and verify params
    (address caller) = abi.decode(
        _sliceAfterSelector(data), (address)
    );
    assertEq(caller, address(this));
}
```

**Testing error messages in fuzz tests:**

```solidity
function testFuzz_withdrawRevertsOnInsufficientBalance(uint256 amount) public {
    uint256 balance = target.balanceOf(address(this));
    vm.assume(amount > balance);

    vm.expectRevert(abi.encodeWithSelector(
        InsufficientBalance.selector, amount, balance
    ));
    target.withdraw(amount);
}
```

The `vm.assume` filters out fuzz inputs where `amount <= balance` (which wouldn't revert). The remaining inputs all trigger the expected error with the exact parameters.

💻 **Quick Try:**

Write a Foundry test file and run it:

```solidity
// test/ErrorTest.t.sol
import "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

contract Target {
    error Unauthorized(address caller);

    function restricted() external view {
        revert Unauthorized(msg.sender);
    }

    function overflow() external pure returns (uint256) {
        return type(uint256).max + 1;
    }
}

contract ErrorTest is Test {
    Target target;

    function setUp() public {
        target = new Target();
    }

    function test_customError() public {
        vm.expectRevert(abi.encodeWithSelector(
            Target.Unauthorized.selector, address(this)
        ));
        target.restricted();
    }

    function test_overflow() public {
        vm.expectRevert(stdError.arithmeticError);
        target.overflow();
    }
}
```

Run with `forge test -vv` and verify both tests pass. The `-vv` flag shows the expected and actual revert data on failure — invaluable for debugging.

---

## 📋 Key Takeaways: Decoding & Detection

After this section, you should be able to:

- Implement the four-way error decoding algorithm (empty → too short → string/panic by selector → custom error) and handle each case appropriately
- Decode custom error parameters from raw bytes using calldata slicing (`data[4:]`) or assembly-based memory slicing, given the error's known signature
- Write Foundry tests using `vm.expectRevert` with exact custom error encoding, selector-only matching, and `stdError` constants for panic codes
- Explain the difference between bubbling raw error bytes (assembly revert) and decoding them (abi.decode), and choose the right approach based on whether you need to inspect the error or just forward it
- Use Foundry's `-vv` verbosity flag and `cast 4byte` to debug unknown error selectors in failed transactions

<details>
<summary>Check your understanding</summary>

- **Four-way decoding algorithm**: Check length == 0 (empty revert), length < 4 (too short for selector), then match selector against `0x08c379a0` (string error) and `0x4e487b71` (panic). Anything else is a custom error — decode parameters using the known signature or look up the selector via `cast 4byte`.
- **Decoding custom error parameters**: Use `abi.decode(data[4:], (type1, type2))` in Solidity or `data[4:]` calldata slicing. In assembly, skip the first 4 bytes with `add(data, 0x24)` (0x20 length prefix + 0x04 selector) and read parameters from there.
- **Foundry test patterns for errors**: `vm.expectRevert(abi.encodeWithSelector(CustomError.selector, param1))` for exact matching, `vm.expectRevert(CustomError.selector)` for selector-only matching, and `vm.expectRevert(stdError.arithmeticError)` for panic codes. These must be called immediately before the reverting call.
- **Bubbling vs decoding**: Bubbling (`revert(add(data, 0x20), mload(data))`) forwards raw bytes without inspecting them — use when you just want to propagate the error. Decoding (`abi.decode`) extracts structured data — use when you need to inspect, log, or react differently based on the error type.
- **Debugging with Foundry**: `-vv` shows revert reasons in test output, `-vvvv` shows full call traces with revert data. `cast 4byte <selector>` looks up the function/error signature from the 4byte directory, letting you identify unknown errors from on-chain transactions.

</details>

---

## 💡 DeFi Error Patterns

Every concept so far — failure modes, encoding, propagation, try/catch, decoding — comes together in production DeFi code. The patterns below show how real protocols handle errors at scale: across batched calls, within flash loans, through aggregator chains, and in time-critical liquidation bots. These are the patterns you'll read in audits, implement in protocol code, and discuss in interviews.

<a id="multicall-errors"></a>
### 💡 Concept: Multicall Error Strategies

**Why this matters:** Multicall contracts batch multiple calls into a single transaction. The core design decision is what happens when one call in the batch fails — do you revert the entire batch, or do you skip the failure and continue? Production protocols offer both options, and the choice has real consequences for users and integrators.

**The problem:**

You have 10 token approvals batched into one transaction. Approval #7 fails because the token contract is paused. Should approvals 1–6 and 8–10 still go through, or should the entire transaction revert?

There's no universally correct answer — it depends on whether the calls are independent or interdependent.

**Strategy 1: Revert-all (strict)**

```solidity
contract StrictMulticall {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            // delegatecall to self — preserves msg.sender context
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                // Bubble the original error from the failed call
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
    }
}
```

One failure → entire batch reverts. The failed call's error data propagates unmodified to the caller.

**When to use:** When calls are interdependent. Example: Uniswap V3's multicall batches `mint` + `refund` — if minting fails, the refund is meaningless.

**Strategy 2: Try-each (lenient)**

```solidity
contract TryEachMulticall {
    struct Result {
        bool success;
        bytes returnData;
    }

    function tryMulticall(bytes[] calldata data) external returns (Result[] memory results) {
        results = new Result[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (results[i].success, results[i].returnData) = address(this).delegatecall(data[i]);
            // No revert — record and continue
        }
    }
}
```

Failed calls are recorded, successful calls persist. The caller gets an array of results and must check each `.success` field.

**When to use:** When calls are independent. Example: a portfolio rebalancer executing multiple swaps — one failed swap shouldn't block the others.

**Strategy 3: Hybrid (Uniswap V3 pattern)**

Uniswap V3's actual Multicall contract offers both options in a single deployment:

```solidity
// From Uniswap V3 Periphery — Multicall.sol
function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
    results = new bytes[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
        (bool success, bytes memory result) = address(this).delegatecall(data[i]);

        if (!success) {
            if (result.length < 68) revert();

            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

        results[i] = result;
    }
}
```

Notice the error handling: if the revert data is shorter than 68 bytes (4-byte selector + 32-byte offset + 32-byte length = minimum for an `Error(string)`), it does a bare revert. Otherwise, it strips the selector, decodes the string, and re-reverts with `revert(string)`. This rewraps the error as `Error(string)`.

**The trade-off:** Uniswap's approach normalises all errors into `Error(string)` format, losing custom error parameters. This was acceptable in V3 because the periphery contracts mostly used string requires. In V4 (with hooks that can define arbitrary custom errors), this pattern wouldn't preserve error data.

**Multicall with deadline (Uniswap V3 Periphery extension):**

```solidity
function multicall(uint256 deadline, bytes[] calldata data)
    external
    payable
    override
    returns (bytes[] memory)
{
    require(block.timestamp <= deadline, "Transaction too old");
    return multicall(data);
}
```

The deadline check happens *before* the loop, so a stale transaction fails fast without wasting gas on individual calls.

#### 📖 How to Study Multicall Contracts

1. **Start with the interface** — look at what return type the function uses. `bytes[]` means revert-all; a struct array with `success` fields means try-each.
2. **Find the error handling** — look inside the loop for `if (!success)`. Assembly revert = bubbling. Decode + re-revert = rewrapping. No check = lenient.
3. **Check for delegatecall vs call** — `delegatecall` preserves `msg.sender` and storage context (used when multicalling your own contract). `call` is for multicalling external contracts.
4. **Look for pre-loop checks** — deadlines, paused state, or access control that runs once before the batch.

#### 🔗 DeFi Pattern Connection

**Where multicall error strategies matter in DeFi:**

1. **Uniswap V3/V4 Periphery**
   All user-facing operations (mint, swap, collect) go through multicall. Understanding the error behaviour lets you batch operations safely and debug failed batches.

2. **Gnosis Safe (Safe) multi-send**
   Safe's `multiSend` uses a different pattern: it encodes operation type (call/delegatecall) per transaction. Failed sub-transactions revert the entire multi-send by default, but optional transactions can be flagged.

3. **Yield aggregators**
   Protocols like Yearn batch harvest calls across multiple strategies. A failing strategy shouldn't block others from harvesting, so they use the try-each pattern with error logging.

**The pattern:** If calls are interdependent → revert-all. If calls are independent → try-each with result tracking. Most protocols offer revert-all as default and try-each as an option.

---

<a id="flash-loan-errors"></a>
### 💡 Concept: Error Handling in Flash Loans

**Why this matters:** Flash loans are the highest-stakes error handling scenario in DeFi. The entire operation — borrow, use, repay — must succeed atomically within a single transaction. Any error in the user's callback or in the repayment check must revert the entire transaction, including the initial transfer. The error handling is what makes flash loans "safe" — without it, tokens would leave the pool without guarantee of return.

**The flash loan execution flow:**

```
Pool.flashLoan(amount, callbackData)
│
├── 1. Transfer tokens to borrower
├── 2. Call borrower.onFlashLoan(amount, fee, data)
│   │
│   ├── Borrower executes arbitrary logic
│   ├── (swap, arbitrage, liquidation, etc.)
│   └── Returns success indicator
│
├── 3. Verify repayment (balance check or transferFrom)
│   └── If balance < borrowed + fee → REVERT
│
└── Everything reverts atomically if any step fails
```

**Aave V3's flash loan error handling:**

```solidity
// Simplified from Aave V3 — FlashLoanLogic.sol
function executeFlashLoan(...) external {
    // 1. Transfer tokens to receiver
    IAToken(reserveData.aTokenAddress).transferUnderlyingTo(receiverAddress, amount);

    // 2. Call receiver's callback
    require(
        IFlashLoanReceiver(receiverAddress).executeOperation(
            assets, amounts, premiums, msg.sender, params
        ),
        Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN
    );

    // 3. Verify repayment via transferFrom
    // If receiver didn't approve enough, this reverts
    IERC20(asset).safeTransferFrom(receiverAddress, aTokenAddress, amountPlusFlashLoanFee);
}
```

Three layers of error protection:

1. **Callback return value** — the receiver must return `true`. If the callback reverts, that revert propagates. If it returns `false`, Aave's `require` catches it. This prevents contracts that don't properly implement the interface from silently swallowing the callback.

2. **transferFrom for repayment** — instead of checking balances (which can be manipulated), Aave pulls the repayment. If the receiver didn't `approve` enough tokens, `safeTransferFrom` reverts.

3. **Atomic transaction** — since everything runs in one transaction, failure at step 2 or 3 undoes step 1 (the initial transfer).

**Uniswap V2 flash swap error handling:**

```solidity
// Simplified from Uniswap V2 — UniswapV2Pair.sol
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external {
    // 1. Optimistically transfer tokens
    if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
    if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

    // 2. If data is non-empty, it's a flash swap — call the callback
    if (data.length > 0) {
        IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
    }

    // 3. Invariant check — k must not decrease
    uint balance0 = IERC20(token0).balanceOf(address(this));
    uint balance1 = IERC20(token1).balanceOf(address(this));
    require(
        balance0 * balance1 >= reserve0 * reserve1,
        "UniswapV2: K"
    );
}
```

Uniswap V2 uses a different strategy: optimistic transfer + invariant check. It sends the tokens first, calls the borrower, then verifies the constant product formula holds. If the borrower didn't repay enough, `K` decreases and the require fails, reverting everything.

**Key difference from Aave:** Uniswap doesn't check a return value from the callback — it only checks the invariant. This means a callback that reverts still propagates correctly (atomic revert), but a callback that *succeeds without repaying* also gets caught by the invariant check.

**Common error in flash loan receivers:**

```solidity
// WRONG — forgetting to return true
function executeOperation(...) external returns (bool) {
    // ... do arbitrage ...
    // forgot: return true;
    // Solidity returns false (default for bool) → Aave's require fails
}

// WRONG — not handling the fee
function executeOperation(...) external returns (bool) {
    uint256 amountOwed = amounts[0] + premiums[0]; // amount + fee
    // Only approve 'amounts[0]', not 'amountOwed'
    IERC20(assets[0]).approve(msg.sender, amounts[0]); // Missing fee!
    return true;
    // Aave's transferFrom will revert — not enough approved
}
```

#### 🔗 DeFi Pattern Connection

**Where flash loan error handling matters in DeFi:**

1. **Arbitrage bots**
   Your bot takes a flash loan, executes a multi-hop swap, and repays. If any hop fails (slippage, liquidity change), the entire flash loan reverts — you lose gas but not principal. The atomicity guarantee is what makes flash loan arbitrage risk-free (except for gas).

2. **Liquidation**
   Flash-loan-funded liquidations borrow the repayment asset, liquidate the position, receive collateral, swap collateral back, and repay. Error at any step → full revert. The error propagation chain is: swap fails → callback reverts → flash loan reverts → liquidation never happened.

3. **Flash mint (ERC-3156)**
   Stablecoins like DAI can be flash-minted: mint tokens, use them, burn them in the same transaction. The error handling must ensure minted tokens are burned even if the callback's custom logic fails — otherwise you've created tokens from nothing.

**The pattern:** Flash loans rely on atomic revert guarantees. The pool doesn't need to trust the borrower because any failure in the callback or repayment reverts the initial transfer. This is error propagation as a security mechanism.

---

<a id="router-errors"></a>
### 💡 Concept: Router & Aggregator Error Bubbling

**Why this matters:** Routers and aggregators sit between users and protocols, forwarding calls and translating errors. When a swap fails three layers deep (user → aggregator → DEX router → pool), the error must bubble up intact so the user (or their frontend) can understand what went wrong. How routers handle this bubbling determines whether users see "execution reverted" or "InsufficientLiquidity(0x1234...)".

**The layered call problem:**

```
User's wallet
  └── Aggregator.swap()              ← catches and re-throws
       └── Router.exactInputSingle()  ← bubbles or wraps
            └── Pool.swap()            ← original error source
                 └── REVERT InsufficientLiquidity()
```

At each layer, the error can be:
- **Bubbled** — forwarded as-is (preserves original error)
- **Wrapped** — caught and re-reverted with additional context
- **Swallowed** — caught and replaced with a generic error (information lost)

**Uniswap V3 Router error bubbling:**

```solidity
// Simplified from Uniswap V3 — SwapRouter.sol
function exactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    override
    returns (uint256 amountOut)
{
    amountOut = exactInputInternal(
        params.amountIn,
        params.recipient,
        params.sqrtPriceLimitX96,
        SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
    );
    require(amountOut >= params.amountOutMinimum, "Too little received");
}
```

The router adds its own check (`amountOutMinimum`) on top of the pool's internal checks. If the pool reverts, that error propagates through `exactInputInternal` automatically (Solidity bubbles reverts from internal calls). If the pool succeeds but the output is too low, the router's own `require` fires.

**The aggregator pattern — wrapping errors with context:**

```solidity
contract Aggregator {
    error SwapFailed(address dex, bytes reason);
    error AllRoutesFailed();

    function swap(Route[] calldata routes) external returns (uint256 bestOutput) {
        bytes memory lastError;

        for (uint256 i = 0; i < routes.length; i++) {
            (bool success, bytes memory result) = routes[i].dex.call(
                abi.encodeCall(IRouter.swap, (routes[i].params))
            );

            if (success) {
                uint256 output = abi.decode(result, (uint256));
                if (output > bestOutput) bestOutput = output;
            } else {
                lastError = result;
                // Don't revert — try next route
            }
        }

        if (bestOutput == 0) {
            // All routes failed — bubble the last error with context
            if (lastError.length > 0) {
                revert SwapFailed(routes[routes.length - 1].dex, lastError);
            }
            revert AllRoutesFailed();
        }
    }
}
```

This is a simplified illustration of the try-multiple-routes pattern used by aggregators like 1inch and Paraswap. In production, aggregators typically simulate routes off-chain (via `eth_call`) to find the best output, then execute only the winning route on-chain. The pattern here shows the error handling strategy — try routes, record failures, only revert if all fail. The `SwapFailed` error wraps the original error bytes as a parameter, preserving the downstream error while adding the failing DEX address.

**Decoding nested errors:**

When an aggregator wraps errors, the revert data contains an error-within-an-error:

```
SwapFailed(address,bytes) selector: 0x........
├── address dex: 0x1234...
└── bytes reason:
    └── InsufficientLiquidity() selector: 0x........
```

To fully decode this, you need to:
1. Decode the outer `SwapFailed` to get `dex` and `reason`
2. Check `reason.length` — if ≥ 4, extract the inner selector
3. Decode the inner error using the pool's ABI

This is why having structured custom errors matters — `Error(string)` at the inner level loses the structured data that the outer decoder might need.

#### 📖 How to Study Router Contracts

1. **Trace a single swap end-to-end** — pick `exactInputSingle` and follow every call from router → pool → callback → token transfer. Note where errors can originate at each step.
2. **Find the slippage check** — routers always have a "minimum output" check. Find it and note whether it uses `require` or a custom error.
3. **Look for try/catch vs low-level calls** — routers that call multiple pools often use low-level `call` so they can try alternative routes on failure. Direct pool interactions usually use high-level calls that auto-revert.
4. **Check callback error handling** — swap callbacks (like `uniswapV3SwapCallback`) run inside the pool's context. Errors in the callback propagate back to the pool, which propagates to the router. The chain must be unbroken.

---

<a id="liquidation-errors"></a>
### 💡 Concept: Liquidation Bot Patterns

**Why this matters:** Liquidation bots operate in the most error-hostile environment in DeFi. They compete with other bots (MEV), execute against state that changes every block, and must handle errors gracefully because every failed transaction costs gas. The error handling patterns used by liquidation bots are the most battle-tested in the ecosystem.

**The liquidation error landscape:**

```
Liquidation attempt
│
├── Price stale → Oracle revert
├── Position already liquidated → Protocol revert
├── Insufficient collateral seized → Slippage on swap
├── Front-run by another bot → State changed between simulation and execution
├── Gas price spike → Transaction pending too long, state changes
└── Flash loan pool drained → Can't borrow repayment asset
```

Every one of these produces a different error, and a production bot must distinguish between them to decide whether to retry, skip, or adjust parameters.

**Probe-first pattern:**

You can't `staticcall` a state-modifying function like `liquidationCall` — `staticcall` reverts on any state modification (SSTORE, LOG, token transfers), so it would always fail regardless of the position's health. Instead, production bots use view functions to probe whether a position is liquidatable before executing:

```solidity
contract LiquidationBot {
    error NotLiquidatable(address account, uint256 healthFactor);
    error LiquidationUnprofitable(address account, int256 expectedProfit);

    function liquidate(
        address account,
        bytes calldata swapData
    ) external returns (uint256 profit) {
        // Step 1: Probe with a view function — no state modification
        // Aave exposes getUserAccountData() which returns health factor
        (,,,,, uint256 healthFactor) = lendingPool.getUserAccountData(account);

        if (healthFactor >= 1e18) {
            revert NotLiquidatable(account, healthFactor);
        }

        // Step 2: Estimate profit from oracle prices + liquidation bonus
        int256 expectedProfit = _estimateProfit(account, swapData);

        if (expectedProfit <= 0) {
            revert LiquidationUnprofitable(account, expectedProfit);
        }

        // Step 3: Execute for real
        profit = _executeLiquidation(account, swapData);
    }
}
```

The view-function probe catches healthy positions and stale data before spending gas on the actual liquidation. This is the primary gas-saving strategy for liquidation bots.

**Alternative: simulate-and-revert pattern**

For protocols without convenient view functions, bots use the simulate-and-revert pattern off-chain. They call `eth_call` at the RPC level, which simulates the full transaction (including state modifications) without committing. This is done in the bot's off-chain code, not on-chain.

**Error classification for retry logic:**

```solidity
function _classifyError(bytes memory errorData) internal pure returns (ErrorType) {
    if (errorData.length < 4) return ErrorType.UNKNOWN;

    bytes4 selector;
    assembly {
        selector := mload(add(errorData, 0x20))
    }

    // Errors that mean "don't retry this account"
    if (selector == ILendingPool.HealthFactorAboveThreshold.selector) {
        return ErrorType.NOT_LIQUIDATABLE;      // Position is healthy
    }
    if (selector == ILendingPool.PositionAlreadyLiquidated.selector) {
        return ErrorType.ALREADY_LIQUIDATED;     // Someone beat us
    }

    // Errors that mean "retry with different parameters"
    if (selector == IRouter.InsufficientOutput.selector) {
        return ErrorType.SLIPPAGE;               // Adjust swap route
    }

    // Errors that mean "retry next block"
    if (selector == IOracle.StalePrice.selector) {
        return ErrorType.STALE_ORACLE;           // Wait for price update
    }

    return ErrorType.UNKNOWN;
}
```

This error classification pattern appears in every serious liquidation bot. The selector-based routing turns raw error bytes into actionable decisions: skip, adjust, or retry.

**Gas-aware error handling:**

```solidity
function batchLiquidate(address[] calldata accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
        // Low-level call — don't let one failure stop the batch
        (bool success, bytes memory result) = address(this).call(
            abi.encodeCall(this.liquidate, (accounts[i], ""))
        );

        if (!success) {
            ErrorType errType = _classifyError(result);

            if (errType == ErrorType.STALE_ORACLE) {
                break; // Oracle is stale — no point trying more accounts
            }
            // For other errors, continue to next account
            continue;
        }
    }
}
```

The batch function uses `call` instead of direct calls so that one failed liquidation doesn't revert the entire batch. But it's smart about it — a stale oracle affects all accounts, so it breaks the loop early instead of wasting gas on calls that will all fail.

**Why bots use call to self:**

```solidity
// This looks strange:
(bool success, bytes memory result) = address(this).call(
    abi.encodeCall(this.liquidate, (account, data))
);
```

Calling `address(this).call(...)` instead of `this.liquidate(...)` creates a new call frame. If `liquidate` reverts, only the inner call frame reverts — state changes in the outer function (like loop counters or profit tracking) persist. This is essential for batch operations where partial success is acceptable.

#### ⚠️ Common Mistakes

**Mistake 1: Not probing before executing**

```solidity
// WRONG — wastes gas on doomed liquidations
function liquidate(address account) external {
    // Directly calls the lending pool — pays full gas if position is healthy
    lendingPool.liquidationCall(collateral, debt, account, type(uint256).max, false);
}

// CORRECT — probe with a view function first
function liquidate(address account) external {
    (,,,,, uint256 healthFactor) = lendingPool.getUserAccountData(account);
    if (healthFactor >= 1e18) return; // Position is healthy, no gas wasted
    lendingPool.liquidationCall(collateral, debt, account, type(uint256).max, false);
}
```

**Mistake 2: Reverting the entire batch on one failure**

```solidity
// WRONG — one failed liquidation kills the whole batch
function batchLiquidate(address[] calldata accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
        this.liquidate(accounts[i]); // Reverts propagate!
    }
}
```

Use low-level `call` for batch operations, as shown above.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you design the error handling for a DEX aggregator?"**
   - Good answer: Use low-level calls to try multiple routes, catch failures, fall back to alternative routes
   - Great answer: Use low-level calls with error classification — distinguish slippage errors (retry with different parameters) from liquidity errors (skip this pool) from oracle errors (abort entirely). Wrap the original error bytes in a context-providing custom error so the caller can decode both the failing DEX and the root cause. Simulate off-chain first to avoid wasting gas on-chain.

2. **"A user reports 'execution reverted' with no message on your protocol. How do you debug it?"**
   - Good answer: Check the transaction on Etherscan, use Tenderly to get a trace
   - Great answer: Empty revert data means either a bare `revert()`, INVALID opcode (pre-0.8.0 assert or handwritten assembly), or out-of-gas. Check the gas used — if it consumed nearly all forwarded gas, it's likely INVALID or OOG. Use `cast run <txHash>` or Tenderly to get the full call trace. If it's a proxy, the error might originate in the implementation but surface through the proxy's fallback. Check if the target address has code — a call to an empty address succeeds silently, which can cause downstream reverts with confusing data.

3. **"How do flash loans stay safe without trusting the borrower?"**
   - Good answer: The transaction is atomic — if repayment fails, everything reverts
   - Great answer: The pool relies on the EVM's frame-level revert guarantee. The initial transfer, callback, and repayment check all run in the same top-level transaction. Any revert — whether from the callback, the repayment `transferFrom`, or a return-value check — rolls back the initial transfer. The pool doesn't trust the borrower's code at all; it trusts the EVM's atomicity. This is error propagation used as a security mechanism.

**Interview Red Flags:**
- 🚩 Using `staticcall` to "simulate" state-modifying functions (it always fails)
- 🚩 Not knowing that `catch Error(string)` doesn't catch custom errors
- 🚩 Reverting the entire batch when one operation in a multicall fails (unless calls are interdependent)
- 🚩 Not handling the empty-returndata case when decoding errors from low-level calls

**Pro tip:** When reviewing a protocol's error handling in an audit, trace one happy path and one revert path end-to-end through every call layer. Check: does the error data survive each hop? Is there a layer that swallows it? Is there a layer that adds context? The most common audit finding is error data getting lost at an intermediate layer.

---

## 🎯 Build Exercise: ErrorHandler

<a id="exercise1"></a>

**Workspace:** `workspace/src/deep-dives/errors/exercise1-error-handler/ErrorHandler.sol`
**Tests:** `workspace/test/deep-dives/errors/exercise1-error-handler/ErrorHandler.t.sol`

Build a contract that demonstrates production-level error handling patterns. You'll implement low-level call wrappers, strict and lenient multicall strategies, error classification by selector, and string error decoding — the core patterns from this deep dive.

**5 TODOs:**

1. `tryCall(address target, bytes calldata data)` — Execute a low-level call, return success status and raw result bytes. On failure, return the raw revert data without modification.

2. `multicallStrict(Call[] calldata calls)` — Execute an array of calls. If any call fails, bubble the original error using assembly (revert with the raw error bytes). Return all results on success.

3. `multicallLenient(Call[] calldata calls)` — Execute an array of calls. Never revert. Return an array of `Result` structs with `success` and `returnData` fields for each call.

4. `classifyError(bytes memory errorData)` — Given raw revert data, classify the error: return `ErrorType.EMPTY` if no data, `ErrorType.STRING_ERROR` if the selector matches `Error(string)`, `ErrorType.PANIC` if it matches `Panic(uint256)`, `ErrorType.CUSTOM` for any other 4+ byte selector, and `ErrorType.UNKNOWN` for data shorter than 4 bytes but non-empty.

5. `decodeStringError(bytes memory errorData)` — Given revert data with the `Error(string)` selector, strip the first 4 bytes and ABI-decode the remaining bytes into a string. Revert with `NotAStringError()` if the selector doesn't match.

**🎯 Goal:** Practice the three core error handling patterns (bubble, record, classify) that appear in every production DeFi protocol. After completing this exercise, you'll be able to read router and aggregator error handling code fluently.

---

## 📋 Key Takeaways: DeFi Error Patterns

After this section, you should be able to:

- Choose between revert-all and try-each multicall strategies based on whether batched calls are interdependent or independent, and implement both using low-level calls with assembly error bubbling
- Explain how flash loans use atomic revert guarantees as a security mechanism — the pool trusts the EVM's revert behaviour, not the borrower's code
- Trace error propagation through a multi-layer call chain (user → aggregator → router → pool) and identify where errors are bubbled, wrapped, or swallowed at each layer
- Implement error classification by selector to drive retry logic in bots: distinguish between "skip this account", "adjust parameters", and "retry next block"
- Use view-function probes (on-chain) and `eth_call` simulation (off-chain) to check whether an operation will succeed before spending gas on the real execution, and explain why this pattern is essential for liquidation bots
- Design batch operations that use `address(this).call(...)` to isolate failures, with smart early-exit conditions (like stale oracles) to avoid wasting gas

<details>
<summary>Check your understanding</summary>

- **Multicall error strategies**: Revert-all (strict) reverts the entire batch if any call fails — use when calls are interdependent (e.g., approve + swap). Try-each (lenient) catches individual failures and continues — use when calls are independent (e.g., batch claims). Both use low-level calls with assembly error bubbling for the revert-all case.
- **Flash loan atomic revert guarantee**: The pool transfers tokens to the borrower, calls the borrower's callback, then checks repayment. If repayment fails, the entire transaction reverts — including the initial transfer. The pool trusts the EVM's atomicity, not the borrower's code. This is why flash loans are safe without collateral.
- **Multi-layer error propagation**: In a chain like user -> aggregator -> router -> pool, errors bubble up through each layer. At each boundary, errors may be bubbled raw (assembly revert), wrapped in a higher-level error (adding context), or swallowed (try/catch with fallback logic). Understanding where information is lost helps debug failed transactions.
- **Error classification for bot retry logic**: Parse the revert selector to classify errors: "skip" (InsufficientBalance — this account is done), "adjust" (SlippageExceeded — retry with different params), or "retry" (StaleOracle — try next block). This prevents bots from wasting gas retrying unrecoverable failures.
- **Pre-flight simulation**: Use `eth_call` (off-chain) or view-function probes (on-chain) to check if an operation will succeed before submitting the real transaction. Essential for liquidation bots where failed transactions waste gas in competitive MEV environments.
- **Batch isolation with address(this).call**: Wrapping each operation in `address(this).call(abi.encodeCall(...))` creates a sub-call that can revert independently without reverting the parent. Add early-exit conditions (e.g., check oracle freshness once before the loop) to avoid wasting gas on operations that will all fail for the same reason.

</details>

---

## 📚 Resources

**Solidity Error Handling:**
- [Solidity Docs — Error Handling](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions) — official reference for require, revert, assert, and error propagation
- [Solidity Docs — Errors and the Revert Statement](https://docs.soliditylang.org/en/latest/abi-spec.html#errors) — ABI specification for error encoding
- [Solidity Blog — Custom Errors in 0.8.4](https://blog.soliditylang.org/2021/04/21/custom-errors/) — original announcement with gas comparison data

**EVM Internals:**
- [EVM Codes — REVERT](https://www.evm.codes/#fd) — opcode reference with gas behaviour
- [EVM Codes — INVALID](https://www.evm.codes/#fe) — opcode reference
- [EIP-140: REVERT Instruction](https://eips.ethereum.org/EIPS/eip-140) — the EIP that introduced REVERT in Byzantium
- [EIP-150: Gas Cost Changes](https://eips.ethereum.org/EIPS/eip-150) — introduced the 63/64 gas forwarding rule

**Production Code to Study:**
- [Uniswap V3 Multicall](https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol) — the standard multicall with error rewrapping
- [Uniswap V3 SwapRouter](https://github.com/Uniswap/v3-periphery/blob/main/contracts/SwapRouter.sol) — router error handling and slippage checks
- [Aave V3 FlashLoanLogic](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/FlashLoanLogic.sol) — flash loan error handling with callback verification
- [OpenZeppelin Address.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol) — utility functions for low-level call error bubbling

**Foundry Testing:**
- [Foundry Book — vm.expectRevert](https://book.getfoundry.sh/cheatcodes/expect-revert) — cheatcode reference for error testing
- [Foundry Book — stdError](https://book.getfoundry.sh/reference/forge-std/std-errors) — standard panic error constants

**Advanced Topics:**
- [Returnbomb Attack](https://github.com/nomad-xyz/ExcessivelySafeCall) — the `excessivelySafeCall` library and the returndata bomb vector
- [EIP-150 and the 63/64 Rule](https://eips.ethereum.org/EIPS/eip-150) — why try/catch can't reliably catch out-of-gas errors

---

**Navigation:** [← Deep Dives Index](README.md)

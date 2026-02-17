# Section 2: EVM-Level Changes (~2 days)

## 📚 Table of Contents

**Day 3: Dencun Upgrade**
- [Transient Storage Deep Dive (EIP-1153)](#transient-storage-deep-dive)
- [Proto-Danksharding (EIP-4844)](#proto-danksharding)
- [PUSH0 & MCOPY](#push0-mcopy)
- [SELFDESTRUCT Changes](#selfdestruct-changes)
- [Day 3 Build Exercise](#day3-exercise)

**Day 4: Pectra Upgrade**
- [EIP-7702 — EOA Code Delegation](#eip-7702)
- [Other Pectra EIPs](#other-pectra-eips)
- [Day 4 Build Exercise](#day4-exercise)

---

## Day 3: Dencun Upgrade — EIP-1153 & EIP-4844

<a id="transient-storage-deep-dive"></a>
### 💡 Concept: Transient Storage Deep Dive (EIP-1153)

**Why this matters:** You've used `transient` in Solidity. Now understand what the EVM actually does. Uniswap V4's entire architecture—the flash accounting that lets you batch swaps, add liquidity, and pay only net balances—depends on transient storage behaving exactly right across `CALL` boundaries.

> 🔗 **Connection to Section 1:** Remember the [TransientGuard exercise from Day 2](1-solidity-modern.md#day2-exercise)? You used the `transient` keyword and raw `tstore`/`tload` assembly. Now we're diving into **how EIP-1153 actually works at the EVM level**—the opcodes, gas costs, and why it's revolutionary for DeFi.

> Introduced in [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153), activated with the [Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) (March 2024)

**The model:**

Transient storage is a key-value store (32-byte keys → 32-byte values) that:
- Is scoped per contract, per transaction (same scope as regular storage, but transaction lifetime)
- Gets wiped clean when the transaction ends—values are never written to disk
- Persists across external calls within the same transaction (unlike memory, which is per-call-frame)
- Costs ~100 gas for both `TSTORE` and `TLOAD` (vs ~100 for warm `SLOAD`, but ~2,100-20,000 for `SSTORE`)
- Reverts correctly—if a call reverts, transient storage changes in that call frame are also reverted

**📊 The critical distinction:** Transient storage sits between memory (per-call-frame, byte-addressed) and storage (permanent, slot-addressed). It's slot-addressed like storage but temporary like memory. The key difference from memory is that it **survives across `CALL`, `DELEGATECALL`, and `STATICCALL` boundaries** within the same transaction.

#### 🔍 Deep Dive: Transient Storage Memory Layout

**Visual comparison of the three storage types:**

```
┌─────────────────────────────────────────────────────────────┐
│                         MEMORY                              │
│  - Byte-addressed (0x00, 0x01, 0x02, ...)                  │
│  - Per call frame (isolated to each function call)         │
│  - Wiped when call returns                                 │
│  - ~3 gas per word access                                  │
└─────────────────────────────────────────────────────────────┘
              ↓ External call (CALL/DELEGATECALL) ↓
┌─────────────────────────────────────────────────────────────┐
│                    New memory context                       │
│  - Previous memory is inaccessible                          │
└─────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│                   TRANSIENT STORAGE                         │
│  - Slot-addressed (slot 0, slot 1, slot 2, ...)           │
│  - Per contract, per transaction                           │
│  - Persists across all calls in same transaction          │
│  - Wiped when transaction ends                            │
│  - ~100 gas per TLOAD/TSTORE                               │
└─────────────────────────────────────────────────────────────┘
              ↓ External call (CALL/DELEGATECALL) ↓
┌─────────────────────────────────────────────────────────────┐
│                   TRANSIENT STORAGE                         │
│  - SAME transient storage accessible! ✨                   │
│  - This is the key difference from memory                  │
└─────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│                      STORAGE                                │
│  - Slot-addressed (slot 0, slot 1, slot 2, ...)           │
│  - Per contract, permanent on-chain                        │
│  - Persists across transactions                            │
│  - First access: ~2,100 gas (cold)                         │
│  - Subsequent: ~100 gas (warm)                             │
│  - Writing zero→nonzero: ~20,000 gas                       │
│  - Writing nonzero→nonzero: ~5,000 gas                     │
└─────────────────────────────────────────────────────────────┘
```

**Step-by-step example: Transient storage across calls**

```solidity
contract Parent {
    function execute() external {
        // Transaction starts - transient storage is empty
        assembly { tstore(0, 100) }  // Write 100 to slot 0

        Child child = new Child();
        child.readTransient();  // Child CANNOT see Parent's transient storage
                                // (different contract = different transient storage)

        this.callback();  // External call to self - CAN see transient storage
    }

    function callback() external view returns (uint256) {
        uint256 value;
        assembly { value := tload(0) }  // Reads 100 ✨
        return value;
    }
}
```

**Gas cost breakdown - actual numbers:**

| Operation | Cold Access | Warm Access | Notes |
|-----------|-------------|-------------|-------|
| `SLOAD` (storage read) | 2,100 gas | 100 gas | First access in tx is "cold" |
| `SSTORE` (zero→nonzero) | 20,000 gas | — | Adds new data to state |
| `SSTORE` (nonzero→nonzero) | 5,000 gas | — | Modifies existing data |
| `SSTORE` (nonzero→zero) | 5,000 gas | — | Removes data (gets refund) |
| **`TLOAD`** | **100 gas** | **100 gas** | Always same cost ✨ |
| **`TSTORE`** | **100 gas** | **100 gas** | Always same cost ✨ |
| `MLOAD`/`MSTORE` (memory) | ~3 gas | ~3 gas | Cheapest but doesn't persist |

**Real cost comparison for reentrancy guard:**

```solidity
// Classic storage guard (OpenZeppelin ReentrancyGuard pattern)
contract StorageGuard {
    uint256 private _locked = 1;  // 20,000 gas deployment cost

    modifier nonReentrant() {
        require(_locked == 1);     // SLOAD: 2,100 gas (cold first time)
        _locked = 2;               // SSTORE: 5,000 gas (nonzero→nonzero)
        _;
        _locked = 1;               // SSTORE: 5,000 gas (nonzero→nonzero)
    }
    // Total: ~12,100 gas first call, ~10,100 gas subsequent calls
}

// Transient storage guard
contract TransientGuard {
    bool transient _locked;        // 0 gas deployment cost ✨

    modifier nonReentrant() {
        require(!_locked);         // TLOAD: 100 gas
        _locked = true;            // TSTORE: 100 gas
        _;
        _locked = false;           // TSTORE: 100 gas
    }
    // Total: ~300 gas (40x cheaper!) ✨
}
```

**Why this matters for DeFi:**

In a Uniswap V4 swap that touches 5 pools in a single transaction:
- **With storage locks**: 5 × 12,100 = **60,500 gas** just for reentrancy protection
- **With transient locks**: 5 × 300 = **1,500 gas** for the same protection
- **Savings**: **59,000 gas per multi-pool swap** (enough to do 590+ more TLOAD operations!)

**DeFi use cases beyond reentrancy locks:**

1. **Flash accounting ([Uniswap V4](https://github.com/Uniswap/v4-core))**: Track balance deltas across multiple operations in a single transaction, settling the net difference at the end. The PoolManager uses transient storage to accumulate what each caller owes or is owed, then enforces that everything balances to zero before the transaction completes.

2. **Temporary approvals**: ERC-20 approvals that last only for the current transaction—approve, use, and automatically revoke, all without touching persistent storage.

3. **Callback validation**: A contract can set a transient flag before making an external call that expects a callback, then verify in the callback that it was legitimately triggered by the calling contract.

💻 **Quick Try:**

Test transient storage in Remix (requires Solidity 0.8.24+, set EVM version to `cancun`):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TransientDemo {
    uint256 transient counter;  // Lives only during transaction

    function demonstrateTransient() external view returns (uint256, uint256) {
        // Read current value (will be 0 on first call in tx)
        uint256 before = counter;

        // In a real non-view function, you could: counter++;
        // But it would reset to 0 in the next transaction

        return (before, 0);  // Always returns (0, 0) in separate txs
    }

    function demonstratePersistence() external returns (uint256, uint256) {
        uint256 before = counter;
        counter++;  // Increment
        uint256 after = counter;

        // Call yourself - transient storage persists across calls!
        this.checkPersistence();

        return (before, after);  // Returns (0, 1) first time, (0, 1) every time
    }

    function checkPersistence() external view returns (uint256) {
        return counter;  // Can read the value set by caller! ✨
    }
}
```

Try calling `demonstratePersistence()` twice. Notice that `counter` is always 0 at the start of each transaction.

#### 🎓 Intermediate Example: Building a Simple Flash Accounting System

Before diving into Uniswap V4's complex implementation, let's build a minimal flash accounting example:

```solidity
// A simple "borrow and settle" pattern using transient storage
contract SimpleFlashAccount {
    mapping(address => uint256) public balances;

    // Track debt in transient storage
    int256 transient debt;
    bool transient locked;

    modifier withLock() {
        require(!locked, "Locked");
        locked = true;
        debt = 0;  // Reset debt tracker
        _;
        require(debt == 0, "Must settle all debt");  // Enforce settlement
        locked = false;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function flashBorrow(uint256 amount) external withLock {
        // "Borrow" tokens (just accounting, not actual transfer)
        debt -= int256(amount);  // Owe the contract

        // In real usage, caller would do swaps, arbitrage, etc.
        // For demo, just settle the debt immediately
        flashRepay(amount);

        // withLock modifier ensures debt == 0 before finishing
    }

    function flashRepay(uint256 amount) public {
        debt += int256(amount);  // Pay back the debt
    }
}
```

**How this connects to Uniswap V4:**

Uniswap V4's PoolManager does exactly this, but for hundreds of pools:
- `lock()` opens a flash accounting session
- Swaps, adds liquidity, removes liquidity all update transient deltas
- `settle()` enforces that you've paid what you owe (or received what you're owed)
- All within ~300 gas for the lock/unlock mechanism ✨

> ⚠️ **Common pitfall—new reentrancy vectors:** Because `TSTORE` costs only ~100 gas, it can execute within the 2,300 gas stipend that `transfer()` and `send()` forward. A contract receiving ETH via `transfer()` can now execute `TSTORE` (something impossible with `SSTORE`). This creates new reentrancy attack surfaces in contracts that assumed 2,300 gas was "safe." This is one reason `transfer()` and `send()` are deprecated in Solidity 0.8.31+.

> 🔍 **Deep dive:** [ChainSecurity - TSTORE Low Gas Reentrancy](https://www.chainsecurity.com/blog/tstore-low-gas-reentrancy) demonstrates the attack with code examples. Their [GitHub repo](https://github.com/ChainSecurity/TSTORE-Low-Gas-Reentrancy) provides exploit POCs.

🏗️ **Real usage:**

Read [Uniswap V4's PoolManager.sol](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol)—the entire protocol is built on transient storage tracking deltas. You'll see this pattern in Part 3.

**📖 Code Reading Strategy for Uniswap V4 PoolManager:**

When you open PoolManager.sol, follow this path to understand the flash accounting:

1. **Start at the top**: Find the transient storage declarations
   ```solidity
   // Look for:
   NonzeroDeltaCount transient _nonzeroDeltaCount;
   mapping(Currency currency => int256) transient _currencyDelta;
   ```

2. **Understand the lock mechanism**: Search for `function lock()`
   - Notice how it sets `_nonzeroDeltaCount` to track how many currencies have deltas
   - The callback pattern: `ILockCallback(msg.sender).lockAcquired(...)`
   - This is how users execute complex operations within the lock

3. **Follow a swap flow**: Search for `function swap()`
   - See how it calls `_accountPoolBalanceDelta()` to update transient deltas
   - Notice: No actual token transfers happen yet!

4. **Understand settlement**: Search for `function settle()`
   - This is where actual token transfers occur
   - It reduces the debt tracked in `_currencyDelta`
   - If debt > 0 after all operations, transaction reverts

5. **The key insight**:
   - A user can swap Pool A → Pool B → Pool C in one transaction
   - Each swap updates transient deltas (cheap!)
   - Only the NET difference is transferred at the end (one transfer, not three!)

**Why this is revolutionary:**
- **Before V4**: Swap A→B = transfer. Swap B→C = transfer. Two transfers, two SSTORE operations.
- **After V4**: Swap A→B→C = three TSTORE operations, ONE transfer at the end. ~50,000 gas saved per multi-hop swap.

> 🔍 **Deep dive:** [Dedaub - Transient Storage Impact Study](https://dedaub.com/blog/transient-storage-in-the-wild-an-impact-study-on-eip-1153/) analyzes real-world usage patterns. [Hacken - Uniswap V4 Transient Storage Security](https://hacken.io/discover/uniswap-v4-transient-storage-security/) covers security considerations in production flash accounting.

#### 💼 Job Market Context: Transient Storage

**Interview question you WILL be asked:**

> "What's the difference between transient storage and memory?"

**What to say (30-second answer):**

"Memory is byte-addressed and isolated per call frame—when you make an external call, the callee can't access your memory. Transient storage is slot-addressed like regular storage, but it persists across external calls within the same transaction and gets wiped when the transaction ends. This makes it perfect for flash accounting patterns like Uniswap V4, where you want to track deltas across multiple pools and settle the net at the end. Gas-wise, both TLOAD and TSTORE cost ~100 gas regardless of warm/cold state, versus storage which ranges from 2,100 to 20,000 gas depending on the operation."

**Follow-up question:**

> "When would you use transient storage instead of memory or regular storage?"

**What to say:**

"Use transient storage when you need to share state across external calls within a single transaction. Classic examples: reentrancy guards (~40x cheaper than storage guards), flash accounting in AMMs, temporary approvals, or callback validation. Don't use it if the data needs to persist across transactions—that's what regular storage is for. And don't use it if you only need data within a single function scope—memory is cheaper at ~3 gas per access."

**Red flags in interviews:**

- 🚩 "Transient storage is like memory but cheaper" — No! It's more expensive than memory (~100 vs ~3 gas)
- 🚩 "You can use transient storage to avoid storage costs" — Only if data doesn't need to persist across transactions
- 🚩 "TSTORE is always cheaper than SSTORE" — True, but irrelevant if you need persistence

**What production DeFi engineers know:**

1. **Reentrancy guards**: If your protocol will be deployed post-Cancun (March 2024), use transient guards
2. **Flash accounting**: Essential for any multi-step operation (swaps, liquidity management, flash loans)
3. **The 2,300 gas pitfall**: TSTORE works within `transfer()`/`send()` stipend—creates new reentrancy vectors
4. **Testing**: Foundry's `vm.transient*` cheats for testing transient storage behavior

---

<a id="proto-danksharding"></a>
### 💡 Concept: Proto-Danksharding (EIP-4844)

**Why this matters:** If you're building on L2 (Arbitrum, Optimism, Base, Polygon zkEVM), your users' transaction costs dropped 90-95% after Dencun. Understanding blob transactions explains why.

> Introduced in [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844), activated with the [Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) (March 2024)

**What changed:**

EIP-4844 introduced "blob transactions"—a new transaction type (Type 3) that carries large data blobs (~128 KB each) at significantly lower cost than calldata. The blobs are available temporarily (roughly 18 days) and then pruned from the consensus layer.

**📊 The impact on L2 DeFi:**

Before Dencun, L2s posted transaction data to L1 as expensive calldata (~16 gas/byte). After Dencun, they post to cheap blob space (~1 gas/byte or less, depending on demand).

#### 🔍 Deep Dive: Blob Fee Market Math

**The blob fee formula:**

Blobs use an **independent fee market** from regular gas. The blob base fee adjusts based on how many blobs are used per block:

```
blob_base_fee(block_n+1) = blob_base_fee(block_n) × e^((excess_blobs) / BLOB_BASE_FEE_UPDATE_FRACTION)

Where:
- Target: 3 blobs per block
- Maximum: 6 blobs per block
- excess_blobs = total_blobs_in_block - target_blobs
- BLOB_BASE_FEE_UPDATE_FRACTION = 3,338,477 (~1/e when excess = target)
```

**Step-by-step calculation:**

1. **Block has 3 blobs (target)**: `excess_blobs = 0` → fee stays the same
2. **Block has 6 blobs (max)**: `excess_blobs = 3` → fee increases by ~e^(3/3,338,477) ≈ 1.0000009
3. **Block has 0 blobs**: `excess_blobs = -3` → fee decreases

**Why this matters:**

Unlike EIP-1559 (which targets 50% full blocks), blob pricing targets near-zero excess. This keeps blob fees **very low** most of the time.

**Real cost comparison with actual protocols:**

| Protocol | Operation | Before Dencun (Calldata) | After Dencun (Blobs) | Your Cost |
|----------|-----------|-------------------------|---------------------|-----------|
| **Aave on Base** | Supply USDC | ~$0.50 | ~$0.01 | **98% cheaper** ✨ |
| **Uniswap on Arbitrum** | Swap ETH→USDC | ~$1.20 | ~$0.03 | **97.5% cheaper** ✨ |
| **GMX on Arbitrum** | Open position | ~$2.00 | ~$0.05 | **97.5% cheaper** ✨ |
| **Velodrome on Optimism** | Add liquidity | ~$0.80 | ~$0.02 | **97.5% cheaper** ✨ |

*(Costs as of post-Dencun 2024, at ~$3,000 ETH and normal L1 activity)*

**Concrete math example:**

L2 posts a batch of 1,000 transactions:
- Average transaction data: 200 bytes
- Total data: 200,000 bytes

**Before Dencun (calldata):**
```
Cost = 200,000 bytes × 16 gas/byte = 3,200,000 gas
At 20 gwei L1 gas price and $3,000 ETH:
= 3,200,000 × 20 × 10^-9 × $3,000
= $192 per batch
= $0.192 per transaction
```

**After Dencun (blobs):**
```
Blob size: 128 KB = 131,072 bytes
Blobs needed: 200,000 / 131,072 ≈ 2 blobs
Blob fee: ~1 wei per blob (when not congested)
Cost = 2 blobs × 131,072 bytes × 1 gas/byte = 262,144 gas
At 20 gwei L1 gas price and $3,000 ETH:
= 262,144 × 20 × 10^-9 × $3,000
= $15.73 per batch
= $0.016 per transaction
```

**Savings: 92% reduction ($192 → $15.73)**

💻 **Quick Try:**

EIP-4844 is **infrastructure-level** (L2 sequencers use it to post data to L1), not application-level. You won't write blob transaction code in your DeFi contracts. But you can:

1. **Explore blob transactions on Etherscan**: [Etherscan Dencun Upgrade](https://etherscan.io/txs?block=19426587) (first Dencun block, March 13, 2024)
   - Look for Type 3 transactions (blob txs)
   - See the blob base fee in action

2. **Check L2Beat's blob explorer**: [L2Beat Blobs](https://l2beat.com/blobs)
   - Real-time blob usage by L2s
   - Blob fee market dynamics
   - Cost savings visualization

3. **Read blob data**: Use `eth_getBlob` RPC if your node supports it (within 18-day window)

**For application developers**: Your L2 DeFi contract doesn't interact with blobs directly. The impact is on **user economics**: design for higher volume, smaller transactions.

**From a protocol developer's perspective:**

- L2 DeFi became dramatically cheaper, accelerating adoption
- `block.blobbasefee` and `blobhash()` are now available in Solidity (though you'll rarely use them directly in application contracts)
- Understanding the blob fee market matters if you're building infrastructure-level tooling (sequencers, data availability layers)

> 🔍 **Deep dive:** The blob fee market uses a separate fee mechanism from regular gas. Read [EIP-4844 blob fee market dynamics](https://ethereum.org/en/roadmap/dencun/#eip-4844) to understand how blob pricing adjusts based on demand.

#### 💼 Job Market Context: EIP-4844 & L2 DeFi

**Interview question you WILL be asked:**

> "Why did L2 transaction costs drop 90%+ after the Dencun upgrade?"

**What to say (30-second answer):**

"Before Dencun, L2 rollups posted transaction data to L1 as calldata, which costs ~16 gas per byte. EIP-4844 introduced blob transactions—a new transaction type that carries up to ~128 KB of data per blob at ~1 gas/byte or less. Blobs use a separate fee market from regular gas, targeting 3 blobs per block with a max of 6. Since L2s were the primary users and adoption was gradual, blob fees stayed near-zero, dropping L2 costs by 90-97%. The blobs are available for ~18 days then pruned, which is fine since L2 nodes already have the data."

**Follow-up question:**

> "Does EIP-4844 affect how you build DeFi protocols on L2?"

**What to say:**

"Not directly for application contracts. EIP-4844 is an L1 infrastructure change—the L2 sequencer uses blobs to post data to L1, but your DeFi contract on the L2 doesn't interact with blobs. The impact is **user acquisition**: cheaper transactions mean more users can afford to use your protocol. For example, a $0.02 Aave supply on Base is viable for small amounts, whereas $0.50 wasn't. Your protocol should be designed for higher volume, smaller transactions post-Dencun."

**Red flags in interviews:**

- 🚩 "EIP-4844 is full Danksharding" — No! It's **proto**-Danksharding. Full danksharding will shard blob data across validators.
- 🚩 "Blobs are stored on-chain forever" — No! Blobs are pruned after ~18 days. L2 nodes keep the data.
- 🚩 "My DeFi contract needs to handle blobs" — No! Blobs are for L2→L1 data posting, not application contracts.

**What production DeFi engineers know:**

1. **L2 selection matters**: Post-Dencun, **Base, Optimism, Arbitrum** became equally cheap. Choose based on liquidity, ecosystem, not cost.
2. **Blob fee spikes**: During congestion, blob fees can spike (like March 2024 inscriptions). Your L2 costs are tied to blob fee volatility.
3. **The 18-day window**: If you're building infra (block explorers, analytics), you need to archive blob data within 18 days.
4. **Future scaling**: EIP-4844 is step 1. Full danksharding will increase from 6 max blobs per block to potentially 64+, further reducing costs.

---

<a id="push0-mcopy"></a>
### 💡 Concept: PUSH0 (EIP-3855) and MCOPY (EIP-5656)

**Behind-the-scenes optimizations** that make your compiled contracts smaller and cheaper:

**PUSH0 ([EIP-3855](https://eips.ethereum.org/EIPS/eip-3855))**: A new opcode that pushes the value 0 onto the stack. Previously, pushing zero required `PUSH1 0x00` (2 bytes). `PUSH0` is a single byte. This saves gas and reduces bytecode size. The Solidity compiler uses it automatically when targeting Shanghai or later.

**MCOPY ([EIP-5656](https://eips.ethereum.org/EIPS/eip-5656))**: Efficient memory-to-memory copy. Previously, copying memory required loading and storing word by word, or using identity precompile tricks. `MCOPY` does it in a single opcode. The compiler can use this for struct copying, array slicing, and similar operations.

#### 🔍 Deep Dive: Bytecode Before & After

**PUSH0 example - initializing variables:**

```solidity
function example() external pure returns (uint256) {
    uint256 x = 0;
    return x;
}
```

**Before PUSH0 (EVM < Shanghai):**
```
PUSH1 0x00    // 0x60 0x00 (2 bytes, 3 gas)
PUSH1 0x00    // 0x60 0x00 (2 bytes, 3 gas)
RETURN        // 0xf3 (1 byte)
```

**After PUSH0 (EVM >= Shanghai):**
```
PUSH0         // 0x5f (1 byte, 2 gas)
PUSH0         // 0x5f (1 byte, 2 gas)
RETURN        // 0xf3 (1 byte)
```

**Savings:**
- **Bytecode size**: 2 bytes smaller (4 bytes → 2 bytes for two pushes)
- **Gas cost**: 2 gas cheaper (6 gas → 4 gas for two pushes)
- **Deployment cost**: 2 bytes × 200 gas/byte = **400 gas saved on deployment**

**Real impact on a typical contract:**

A contract that initializes 20 variables to zero:
- **Before**: 20 × 2 bytes = 40 bytes, 20 × 3 gas = 60 gas
- **After**: 20 × 1 byte = 20 bytes, 20 × 2 gas = 40 gas
- **Deployment savings**: 20 bytes × 200 gas/byte = **4,000 gas**
- **Runtime savings**: 20 gas per function call

**MCOPY example - copying structs:**

```solidity
struct Position {
    uint256 amount;
    uint256 timestamp;
    address owner;
}

function copyPosition(Position memory pos) internal pure returns (Position memory) {
    return pos;  // Copies the struct in memory
}
```

**Before MCOPY (EVM < Cancun):**
```assembly
// Load and store word by word (3 words for the struct)
MLOAD offset        // Load word 1
MSTORE dest        // Store word 1
MLOAD offset+32    // Load word 2
MSTORE dest+32     // Store word 2
MLOAD offset+64    // Load word 3
MSTORE dest+64     // Store word 3

// Total: 6 operations × ~3-6 gas = ~18-36 gas
```

**After MCOPY (EVM >= Cancun):**
```assembly
MCOPY dest offset 96    // Copy 96 bytes (3 words) in one operation

// Total: ~3 gas per word + base cost = ~9-12 gas
```

**Savings:**
- **Gas cost**: ~50% cheaper for typical struct copies
- **Bytecode size**: Smaller (1 opcode vs 6 opcodes)

**Real impact in DeFi:**

Uniswap V4 pools copy position structs frequently during swaps:
- **Before**: ~30 gas per position copy
- **After**: ~12 gas per position copy
- **On a 5-hop swap** (5 position copies): **90 gas saved**

**What you need to know:** You won't write code that explicitly uses these opcodes, but they make your compiled contracts smaller and cheaper. Make sure your compiler's EVM target is set to `cancun` or later in your Foundry config:

```toml
# foundry.toml
[profile.default]
evm_version = "cancun"  # Enables PUSH0, MCOPY, and transient storage
```

#### 💼 Job Market Context: PUSH0 & MCOPY

**Interview question:**

> "What are some gas optimizations from recent EVM upgrades?"

**What to say (30-second answer):**

"PUSH0 from Shanghai (EIP-3855) saves 1 byte and 1 gas every time you push zero to the stack—common in variable initialization and padding. MCOPY from Cancun (EIP-5656) makes memory copies ~50% cheaper by replacing word-by-word MLOAD/MSTORE loops with a single operation. These are automatic optimizations when you set your compiler's EVM target to `cancun` or later in foundry.toml. For a typical DeFi contract, PUSH0 saves ~5-10 KB of bytecode and hundreds of gas across all zero-pushes, while MCOPY optimizes struct copying in AMM swaps and lending protocols. The compiler handles these—you don't write them explicitly."

**Follow-up question:**

> "Should I manually optimize my code to use PUSH0 and MCOPY?"

**What to say:**

"No, the Solidity compiler handles these automatically when targeting the right EVM version. Trying to manually optimize at the opcode level is an anti-pattern—it makes code harder to read and maintain for minimal gain. Focus on high-level optimizations like reducing storage operations, using memory efficiently, and batching transactions. Set `evm_version = \"cancun\"` in your config and let the compiler do its job. The only time you'd write assembly with these opcodes is if you're building compiler tooling or doing very specialized low-level work."

**Red flags in interviews:**

- 🚩 "I manually use PUSH0 in my code" — The compiler does this automatically
- 🚩 "MCOPY makes all operations faster" — Only memory-to-memory copies, not storage or other operations
- 🚩 "Setting EVM version to `cancun` might break my code" — It's backwards compatible; it just enables optimizations

**What production DeFi engineers know:**

1. **Always set `evm_version = "cancun"`** in foundry.toml for post-Dencun deployments
2. **Bytecode size matters**: PUSH0 helps stay under the 24KB contract size limit
3. **Pre-Shanghai deployments**: If deploying to a chain that hasn't upgraded, use `paris` or earlier
4. **Gas profiling**: Use `forge snapshot` to measure actual gas savings, not assumptions
5. **The 80/20 rule**: These opcodes give ~5-10% savings. Storage optimization gives 50%+ savings. Focus on the latter.

---

<a id="selfdestruct-changes"></a>
### 💡 Concept: SELFDESTRUCT Changes (EIP-6780)

**Why this matters:** Some older upgrade patterns are now permanently broken. If you encounter legacy code that relies on `SELFDESTRUCT` for upgradability, it won't work post-Dencun.

> Changed in [EIP-6780](https://eips.ethereum.org/EIPS/eip-6780), activated with Dencun (March 2024)

**What changed:**

Post-Dencun, `SELFDESTRUCT` only deletes the contract if called **in the same transaction that created it**. In all other cases, it sends the contract's ETH to the target address but the contract code and storage remain.

This effectively neuters `SELFDESTRUCT` as a code deletion mechanism.

**DeFi implications:**

| Pattern | Status | Explanation |
|---------|--------|-------------|
| Metamorphic contracts | ❌ **Dead** | Deploy → `SELFDESTRUCT` → redeploy at same address with different code no longer works |
| Old proxy patterns | ❌ **Broken** | Some relied on `SELFDESTRUCT` + `CREATE2` for upgradability |
| Contract immutability | ✅ **Good** | Contracts can no longer be unexpectedly removed, making blockchain state more predictable |

#### 🔍 Historical Context: Why SELFDESTRUCT Was Neutered

**The metamorphic contract exploit pattern:**

Before EIP-6780, attackers could:

1. **Deploy a benign contract** at address A using CREATE2 (deterministic address)
   ```solidity
   // Looks safe!
   contract Benign {
       function withdraw(address token) external {
           IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
       }
   }
   ```

2. **Get the contract whitelisted** by a DAO or protocol

3. **SELFDESTRUCT the contract**, removing all code from address A

4. **Redeploy DIFFERENT code** at the same address A using CREATE2
   ```solidity
   // Same address, malicious code!
   contract Malicious {
       function withdraw(address token) external {
           IERC20(token).transfer(ATTACKER, IERC20(token).balanceOf(address(this)));
       }
   }
   ```

5. **Exploit**: The DAO/protocol thinks address A is still the benign contract, but it's now malicious!

**Real attack: Tornado Cash governance (2023)**

An attacker used metamorphic contracts to:
- Deploy a proposal contract with benign code
- Get it approved by governance vote
- SELFDESTRUCT + redeploy with malicious code
- Drain governance funds

**Post-EIP-6780: This attack is impossible**

`SELFDESTRUCT` now only deletes code if called in the **same transaction** as deployment. The redeploy attack requires two transactions (deploy → selfdestruct → redeploy), so the code persists.

> ⚡ **Common pitfall:** If you're reading older DeFi code (pre-2024) and see `SELFDESTRUCT` used for upgrade patterns, be aware that pattern is now obsolete. Modern upgradeable contracts use UUPS or Transparent Proxy patterns (covered in Section 6).

> 🔍 **Deep dive:** [Dedaub - Removal of SELFDESTRUCT](https://dedaub.com/blog/eip-4758-eip-6780-removal-of-selfdestruct/) explains security benefits. [Vibranium Audits - EIP-6780 Objectives](https://www.vibraniumaudits.com/post/taking-self-destructing-contracts-to-the-next-level-the-objectives-of-eip-6780) covers how metamorphic contracts were exploited in governance attacks.

#### 💼 Job Market Context: SELFDESTRUCT Changes

**Interview question:**

> "I noticed your ERC-20 contract has a `kill()` function using SELFDESTRUCT. Is that still safe?"

**What to say (This is a red flag test!):**

"Actually, SELFDESTRUCT behavior changed with EIP-6780 in the Dencun upgrade (March 2024). It no longer deletes contract code unless called in the same transaction as deployment. The `kill()` function will send ETH to the target address but the contract code and storage will remain. If the goal is to disable the contract, we should use a `paused` state variable instead. Using SELFDESTRUCT post-Dencun suggests the codebase hasn't been updated for recent EVM changes, which is a red flag."

**Red flags in interviews/audits:**

- 🚩 Any contract using `SELFDESTRUCT` for upgradability (broken post-Dencun)
- 🚩 Contracts that rely on `SELFDESTRUCT` freeing up storage (no longer true)
- 🚩 Documentation mentioning CREATE2 + SELFDESTRUCT for redeployment (metamorphic pattern dead)

**What production DeFi engineers know:**

1. **Pause, don't destroy**: Use OpenZeppelin's `Pausable` pattern instead of SELFDESTRUCT
2. **Upgradability**: Use UUPS or Transparent Proxy (Section 6), not metamorphic contracts
3. **The one exception**: Factory contracts that deploy+test+destroy in a single transaction (rare)
4. **Historical code**: Pre-2024 contracts may have SELFDESTRUCT—understand it won't work as originally intended

---

<a id="day3-exercise"></a>
## 🎯 Day 3 Build Exercise

**Workspace:** [`workspace/src/part1/section2/`](../workspace/src/part1/section2/) — starter file: [`FlashAccounting.sol`](../workspace/src/part1/section2/FlashAccounting.sol), tests: [`FlashAccounting.t.sol`](../workspace/test/part1/section2/FlashAccounting.t.sol)

Build a "flash accounting" pattern using transient storage:

1. Create a `FlashAccounting` contract that uses transient storage to track balance deltas
2. Implement `lock()` / `unlock()` / `settle()` functions:
   - `lock()` opens a session (sets a transient flag)
   - During a locked session, operations accumulate deltas in transient storage
   - `settle()` verifies all deltas net to zero (or the caller has paid the difference)
   - `unlock()` clears the session
3. Write a test that executes multiple token swaps within a single locked session, settling only the net difference
4. Test reentrancy: verify that if an operation reverts during the locked session, the transient storage deltas are correctly reverted

**🎯 Goal:** This pattern is the foundation of Uniswap V4's architecture. Building it now means you'll instantly recognize it when reading V4 source code in Part 3.

---

## ⚠️ Common Mistakes: Day 3 Recap

**Transient Storage:**
1. ❌ **Using transient storage for cross-transaction state** → It resets every transaction! Use regular storage.
2. ❌ **Assuming TSTORE is cheaper than memory** → Memory is ~3 gas, TSTORE is ~100 gas. Use TSTORE when you need cross-call persistence.
3. ❌ **Forgetting the 2,300 gas reentrancy vector** → `transfer()` and `send()` now allow TSTORE, creating new attack surfaces.
4. ❌ **Not testing transient storage reverts** → If a call reverts, transient changes revert too. Test this behavior.

**EIP-4844:**
1. ❌ **Saying "full danksharding is live"** → It's **proto**-danksharding. Full danksharding comes later.
2. ❌ **Thinking your DeFi contract needs blob logic** → Blobs are L1 infrastructure. Your L2 contract doesn't interact with them.
3. ❌ **Assuming blob fees are always cheap** → During congestion (inscriptions, etc.), blob fees can spike.

**PUSH0 & MCOPY:**
1. ❌ **Not setting `evm_version = "cancun"` in foundry.toml** → You'll miss out on these optimizations.
2. ❌ **Manually optimizing for PUSH0** → The compiler does this automatically. Focus on logic, not opcode-level tricks.

**SELFDESTRUCT:**
1. ❌ **Using SELFDESTRUCT for upgradability** → Broken post-Dencun. Use proxy patterns (Section 6).
2. ❌ **Relying on SELFDESTRUCT for contract removal** → Code persists unless called in same transaction as deployment.
3. ❌ **Trusting pre-2024 code with SELFDESTRUCT** → Understand it won't work as originally intended.

---

## 📋 Day 3 Summary

**✓ Covered:**
- Transient storage mechanics (EIP-1153) — how it differs from memory and storage, gas costs, flash accounting
- Flash accounting pattern — Uniswap V4's core innovation with code reading strategy
- Proto-Danksharding (EIP-4844) — why L2s became 90-97% cheaper, blob fee market math
- PUSH0 & MCOPY — bytecode comparisons and gas savings
- SELFDESTRUCT changes (EIP-6780) — metamorphic contracts are dead, historical context

**Next:** Day 4 — EIP-7702 (EOA code delegation) and the Pectra upgrade

---

## Day 4: Pectra Upgrade — EIP-7702 and Beyond

<a id="eip-7702"></a>
### 💡 Concept: EIP-7702 — EOA Code Delegation

**Why this matters:** EIP-7702 bridges the gap between the 200+ million existing EOAs and modern account abstraction. Users don't need to migrate to smart accounts—their EOAs can temporarily become smart accounts. This is the biggest UX shift in Ethereum since EIP-1559.

> Introduced in [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702), activated with the [Pectra upgrade](https://ethereum.org/en/roadmap/pectra/) (May 2025)

**What it does:**

EIP-7702 allows Externally Owned Accounts (EOAs) to temporarily delegate to smart contract code. A new transaction type (Type 4) includes an `authorization_list`—a list of `(chain_id, contract_address, nonce, signature)` tuples. When processed, the EOA's code is temporarily set to a delegation designator pointing to the specified contract. For the duration of the transaction, calls to the EOA execute the delegated contract's code.

**Key properties:**

- The EOA retains its private key—the owner can always revoke the delegation
- The delegation persists across transactions (until explicitly changed or revoked)
- Multiple EOAs can delegate to the same contract implementation
- The EOA's storage is used (like `DELEGATECALL` semantics), not the implementation's

**Why DeFi engineers care:**

EIP-7702 means EOAs can:
- ✅ **Batch transactions**: Execute multiple operations in a single transaction
- ✅ **Use paymasters**: Have someone else pay gas fees (covered in Section 4)
- ✅ **Implement custom validation**: Use multisig, passkeys, session keys, etc.
- ✅ **All without creating a new smart account**

**Example flow:**

1. Alice (EOA) signs an authorization to delegate to a BatchExecutor contract
2. Alice submits a Type 4 transaction with the authorization
3. For that transaction, Alice's EOA acts like a smart account with batching capabilities
4. Alice can batch: approve USDC → swap on Uniswap → stake in Aave, all atomically ✨

#### 🔍 Deep Dive: Delegation Designator Format

**How the EVM knows an EOA has delegated:**

When a Type 4 transaction is processed, the EVM sets the EOA's code to a special **delegation designator**:

```
Delegation Designator Format (23 bytes):
┌────────┬──────────────────────────────────────────┐
│  0xef  │  0x0100  │  address (20 bytes)           │
│ magic  │ version  │  delegated contract address   │
└────────┴──────────┴──────────────────────────────┘

Example:
0xef0100 1234567890123456789012345678901234567890
│       │
│       └─ Points to BatchExecutor contract
└─ Identifies this as a delegation
```

**Step-by-step: What happens during a call**

```solidity
// Scenario: Alice's EOA (0xAA...AA) delegates to BatchExecutor (0xBB...BB)

// 1. Alice signs authorization:
authorization = {
    chain_id: 1,
    address: 0xBB...BB,  // BatchExecutor
    nonce: 0,
    signature: sign(hash(chain_id, address, nonce), alice_private_key)
}

// 2. Alice submits Type 4 transaction with authorization_list = [authorization]

// 3. EVM processes transaction:
//    - Verifies signature against Alice's EOA
//    - Sets code at 0xAA...AA to: 0xef0100BB...BB
//    - Now when anyone calls 0xAA...AA, it DELEGATECALLs to 0xBB...BB

// 4. Someone calls alice.execute([call1, call2]):
//    → EVM sees code = 0xef0100BB...BB
//    → EVM does: DELEGATECALL to 0xBB...BB with calldata = execute([call1, call2])
//    → BatchExecutor.execute() runs in context of Alice's EOA
//    → msg.sender = Alice's EOA, storage = Alice's storage
```

**Key insight: DELEGATECALL semantics**

```
┌─────────────────────────────────────────────────┐
│         Alice's EOA (0xAA...AA)                 │
│  Code: 0xef0100BB...BB (delegation designator)  │
│  Storage: Alice's storage (ETH, tokens, etc.)   │
│                                                 │
│  When called, it DELEGATECALLs to:             │
│         ↓                                       │
│  ┌─────────────────────────────────┐           │
│  │  BatchExecutor (0xBB...BB)      │           │
│  │  - Code executes in Alice's     │           │
│  │    storage context               │           │
│  │  - msg.sender = original caller │           │
│  │  - address(this) = 0xAA...AA    │           │
│  └─────────────────────────────────┘           │
└─────────────────────────────────────────────────┘
```

💻 **Quick Try:**

Simulate EIP-7702 delegation using DELEGATECALL (since Foundry's Type 4 support is evolving):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract BatchExecutor {
    struct Call {
        address target;
        bytes data;
    }

    function execute(Call[] calldata calls) external returns (bytes[] memory) {
        bytes[] memory results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call(calls[i].data);
            require(success, "Call failed");
            results[i] = result;
        }
        return results;
    }
}

// Simulate an EOA delegating to BatchExecutor
contract SimulatedEOA {
    // Pretend this EOA has delegated to BatchExecutor via EIP-7702

    function simulateDelegation(address batchExecutor, bytes calldata data)
        external
        returns (bytes memory)
    {
        // This is what the EVM does when it sees the delegation designator
        (bool success, bytes memory result) = batchExecutor.delegatecall(data);
        require(success, "Delegation failed");
        return result;
    }
}
```

Try batching: approve ERC20 + swap on Uniswap, all in one call!

#### 🎓 Intermediate Example: Batch Executor with Security

Before jumping to production account abstraction, here's a practical batch executor:

```solidity
contract SecureBatchExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    // Only the EOA that delegated can execute (in delegated context)
    modifier onlyDelegator() {
        // In EIP-7702, address(this) = the EOA that delegated
        // msg.sender = external caller
        // We want to ensure only the EOA owner can trigger execution
        require(msg.sender == address(this), "Only delegator");
        _;
    }

    function execute(Call[] calldata calls)
        external
        payable
        onlyDelegator
        returns (bytes[] memory)
    {
        bytes[] memory results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call{
                value: calls[i].value
            }(calls[i].data);

            require(success, "Call failed");
            results[i] = result;
        }

        return results;
    }
}
```

**Security consideration:**

```solidity
// ❌ INSECURE: Anyone can call this and execute as the EOA!
function badExecute(Call[] calldata calls) external {
    for (uint256 i = 0; i < calls.length; i++) {
        calls[i].target.call(calls[i].data);
    }
}

// ✅ SECURE: Only the EOA owner (via msg.sender == address(this))
function goodExecute(Call[] calldata calls) external {
    require(msg.sender == address(this), "Only delegator");
    // ...
}
```

> 🔍 **Deep dive:** EIP-7702 is closely related to ERC-4337 (Section 4). The difference: ERC-4337 requires deploying a new smart account, while EIP-7702 upgrades existing EOAs. Read [Vitalik's post on EIP-7702](https://notes.ethereum.org/@vbuterin/account_abstraction_roadmap) for the full account abstraction roadmap.

**Security considerations:**

- **`msg.sender` vs `tx.origin`**: When an EIP-7702-delegated EOA calls your contract, `msg.sender` is the EOA address (as expected). But `tx.origin` is also the EOA. Be careful with `tx.origin` checks—they can't distinguish between direct EOA calls and delegated calls.
- **Delegation revocation**: A user can always sign a new authorization pointing to a different contract (or to zero address to revoke delegation). Your DeFi protocol shouldn't assume delegation is permanent.

> ⚡ **Common pitfall:** Some contracts use `tx.origin` checks for authentication (e.g., "only allow if `tx.origin == owner`"). These patterns break with EIP-7702 because delegated calls have the same `tx.origin` as direct calls. Avoid `tx.origin`-based authentication.

> 🔍 **Deep dive:** [QuickNode - EIP-7702 Implementation Guide](https://www.quicknode.com/guides/ethereum-development/smart-contracts/eip-7702-smart-accounts) provides hands-on Foundry examples. [Biconomy - Comprehensive EIP-7702 Guide](https://blog.biconomy.io/a-comprehensive-eip-7702-guide-for-apps/) covers app integration. [Gelato - Account Abstraction from ERC-4337 to EIP-7702](https://gelato.cloud/blog/gelato-s-guide-to-account-abstraction-from-erc-4337-to-eip-7702) explains how EIP-7702 compares to ERC-4337.

#### 💼 Job Market Context: EIP-7702

**Interview question you WILL be asked:**

> "How does EIP-7702 differ from ERC-4337 for account abstraction?"

**What to say (30-second answer):**

"ERC-4337 requires deploying a new smart account contract—the user creates a dedicated account abstraction wallet separate from their EOA. EIP-7702 lets existing EOAs temporarily delegate to smart contract code without deploying anything new. The EOA's code is set to a delegation designator (0xef0100 + address), and calls to the EOA DELEGATECALL to the implementation. Key difference: EIP-7702 is reversible and works with existing wallets, while ERC-4337 requires user migration to a new address. Both enable batching, paymasters, and custom validation, but EIP-7702 reduces onboarding friction."

**Follow-up question:**

> "Your DeFi protocol has a function that checks `tx.origin == owner` for admin access. What happens with EIP-7702?"

**What to say (This is a red flag test!):**

"That's a security vulnerability. With EIP-7702, when an EOA delegates to a batch executor, `tx.origin` is still the EOA address even though the code executing is from the delegated contract. An attacker could trick the owner into batching malicious calls alongside legitimate ones, bypassing the `tx.origin` check. The fix is to use `msg.sender` instead of `tx.origin`, or implement a proper access control pattern like OpenZeppelin's `Ownable`. Using `tx.origin` for auth is already an antipattern, and EIP-7702 makes it actively exploitable."

**Red flags in interviews/audits:**

- 🚩 **`tx.origin` for authentication** (broken by EIP-7702 delegation)
- 🚩 **Assuming code at an address is immutable** (delegation can change behavior)
- 🚩 **No validation of delegation designator** (if your protocol interacts with EOAs, expect some might be delegated)

**What production DeFi engineers know:**

1. **Never use `tx.origin`**: Always use `msg.sender` for authentication
2. **Delegation is persistent**: Once set, the delegation stays until explicitly changed
3. **Users can revoke**: Sign a new authorization pointing to address(0)
4. **Testing**: Foundry support for Type 4 txs is evolving—simulate with DELEGATECALL for now
5. **UX opportunity**: EIP-7702 enables "try before you migrate" for AA—users can test batching with their existing EOA before committing to a full ERC-4337 smart account

**Common interview scenario:**

> "A user with an EIP-7702-delegated EOA calls your lending protocol's `borrow()` function. What security considerations apply?"

**What to say:**

"From the lending protocol's perspective, the call looks normal: `msg.sender` is the EOA, the protocol can check balances, approvals work as expected. But we need to be aware that the user might be batching multiple operations—for example, borrow + swap + repay in one transaction. Our reentrancy guards must work correctly, and we shouldn't assume the call is 'simple'. Also, if we emit events with `msg.sender`, they'll correctly show the EOA address, not the delegated contract. The key is that EIP-7702 is transparent to most protocols—the EOA still owns the assets, still approves tokens, still is the `msg.sender`."

---

<a id="other-pectra-eips"></a>
### 💡 Concept: Other Pectra EIPs

**EIP-7623 — Increased calldata cost** ([EIP-7623](https://eips.ethereum.org/EIPS/eip-7623)):

Transactions that predominantly post data (rather than executing computation) pay higher calldata fees. This affects:
- L2 data posting (though most L2s now use blobs from EIP-4844)
- Any protocol that uses heavy calldata (e.g., posting Merkle proofs, batch data)

**EIP-2537 — BLS12-381 precompile** ([EIP-2537](https://eips.ethereum.org/EIPS/eip-2537)):

Native BLS signature verification becomes available as a precompile. Useful for:
- Threshold signatures
- Validator-adjacent logic (e.g., liquid staking protocols)
- Any system that needs efficient pairing-based cryptography (privacy protocols, zkSNARKs)

#### 🎓 Concrete Example: Liquid Staking Validator Verification

**The problem:**

Lido/Rocket Pool needs to verify that validators are correctly attesting to Beacon Chain blocks. Validators sign attestations using BLS12-381 signatures. Before EIP-2537, verifying these on-chain was prohibitively expensive (~1M+ gas).

**With BLS12-381 precompile:**

```solidity
contract ValidatorRegistry {
    // BLS12-381 precompile addresses (hypothetical - check final EIP)
    address constant BLS_VERIFY = address(0x0A);

    struct ValidatorAttestation {
        bytes48 publicKey;      // BLS public key (G1 point)
        bytes32 messageHash;    // Hash of attested data
        bytes96 signature;      // BLS signature (G2 point)
    }

    function verifyAttestation(ValidatorAttestation calldata attestation)
        public
        view
        returns (bool)
    {
        // Prepare input for BLS verify precompile
        bytes memory input = abi.encodePacked(
            attestation.publicKey,
            attestation.messageHash,
            attestation.signature
        );

        // Call BLS12-381 pairing precompile
        (bool success, bytes memory output) = BLS_VERIFY.staticcall(input);

        require(success, "BLS verification failed");
        return abi.decode(output, (bool));

        // Gas cost: ~5,000-10,000 gas vs ~1M+ without precompile ✨
    }

    function verifyMultipleAttestations(ValidatorAttestation[] calldata attestations)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < attestations.length; i++) {
            if (!verifyAttestation(attestations[i])) {
                return false;
            }
        }
        return true;
    }
}
```

**Real use case: Lido's Distributed Validator Technology (DVT)**

```solidity
// Simplified DVT oracle contract
contract LidoDVTOracle {
    struct ConsensusReport {
        uint256 beaconChainEpoch;
        uint256 totalValidators;
        uint256 totalBalance;
        ValidatorAttestation[] signatures;  // From multiple operators
    }

    function submitConsensusReport(ConsensusReport calldata report)
        external
    {
        // Verify all operator signatures (threshold: 5 of 7 must sign)
        uint256 validSigs = 0;
        for (uint256 i = 0; i < report.signatures.length; i++) {
            if (verifyAttestation(report.signatures[i])) {
                validSigs++;
            }
        }

        require(validSigs >= 5, "Insufficient consensus");

        // Update Lido's accounting based on verified report
        _updateValidatorBalances(report.totalBalance);

        // Gas cost: ~50,000 gas vs ~7M+ without precompile
        // Makes on-chain oracle consensus practical ✨
    }
}
```

**Why this matters for DeFi:**

Before BLS precompile:
- Liquid staking protocols relied on **off-chain signature verification**
- Trusted oracle committees (centralization risk)
- Users couldn't verify validator attestations on-chain

After BLS precompile:
- **On-chain verification** of validator signatures
- Decentralized oracle consensus (multiple operators sign, verify on-chain)
- Users can independently verify staking rewards are accurate

**Gas comparison:**

| Operation | Without Precompile | With BLS Precompile | Savings |
|-----------|-------------------|---------------------|---------|
| Single BLS signature verification | ~1,000,000 gas | ~8,000 gas | **99.2%** ✨ |
| 5-of-7 threshold verification | ~7,000,000 gas | ~40,000 gas | **99.4%** ✨ |
| Batch verify 100 attestations | Would revert (OOG) | ~800,000 gas | **Enables new use cases** ✨ |

#### 💼 Job Market Context: BLS12-381 Precompile

**Interview question:**

> "What's the BLS12-381 precompile and why does it matter for DeFi?"

**What to say (30-second answer):**

"BLS12-381 is an elliptic curve used for signature aggregation and pairing-based cryptography. EIP-2537 adds it as a precompile, reducing BLS signature verification from ~1 million gas to ~8,000 gas—a 99%+ reduction. This enables on-chain validator consensus for liquid staking protocols like Lido. Before the precompile, protocols had to verify signatures off-chain using trusted oracles, which is a centralization risk. Now they can verify multiple validator attestations on-chain, enabling truly decentralized oracle consensus. The gas savings also unlock threshold signatures and privacy-preserving protocols that weren't viable before."

**Follow-up question:**

> "Is BLS12-381 the same curve used for zkSNARKs?"

**What to say (This is a knowledge test!):**

"No, that's a common misconception. Most zkSNARKs in production use BN254 (also called alt-bn128), which Ethereum already has precompiles for (EIP-196, EIP-197). BLS12-381 is optimized for signature aggregation—it lets you combine multiple signatures into one, which is why Ethereum 2.0 validators use it. Some newer zkSNARK systems do use BLS12-381, but the primary use case in Ethereum is validator signatures and threshold cryptography, not zero-knowledge proofs."

**Red flags in interviews:**

- 🚩 "BLS12-381 is for zkSNARKs" — No! It's primarily for signature aggregation
- 🚩 "All pairing-based crypto is the same" — Different curves have different security/performance tradeoffs
- 🚩 "The precompile makes all cryptography cheap" — Only BLS12-381 operations. ECDSA (standard Ethereum signatures) uses secp256k1

**What production DeFi engineers know:**

1. **Liquid staking oracles**: Lido, Rocket Pool, and others can now do on-chain validator consensus
2. **Threshold signatures**: N-of-M multisigs without multiple on-chain transactions
3. **Signature aggregation**: Combine signatures from multiple validators/oracles into one verification
4. **The 99% rule**: BLS operations went from ~1M gas (unusable) to ~8K gas (practical)
5. **Cross-chain messaging**: Bridges can aggregate validator signatures for cheaper verification

---

<a id="day4-exercise"></a>
## 🎯 Day 4 Build Exercise

**Workspace:** [`workspace/src/part1/section2/`](../workspace/src/part1/section2/) — starter file: [`EIP7702Delegate.sol`](../workspace/src/part1/section2/EIP7702Delegate.sol), tests: [`EIP7702Delegate.t.sol`](../workspace/test/part1/section2/EIP7702Delegate.t.sol)

1. **Research EIP-7702 delegation designator format**—understand how the EVM determines whether an address has delegated code
2. **Write a simple delegation target contract**:
   ```solidity
   contract BatchExecutor {
       function execute(Call[] calldata calls) external {
           // Execute multiple calls
       }
   }
   ```
3. **Write tests that simulate EIP-7702 behavior** using `DELEGATECALL` (since Foundry's Type 4 transaction support is still evolving):
   - Simulate an EOA delegating to your BatchExecutor
   - Test batched operations: approve + swap + stake
   - Verify `msg.sender` behavior
4. **Security exercise**: Write a test that shows how `tx.origin` checks can be bypassed with EIP-7702 delegation

**🎯 Goal:** Understand the mechanics well enough to reason about how EIP-7702 interacts with DeFi protocols. When a user interacts with your lending protocol through an EIP-7702-delegated EOA, what are the security implications?

---

## ⚠️ Common Mistakes: Day 4 Recap

**EIP-7702:**
1. ❌ **Using `tx.origin` for authentication** → Broken by EIP-7702 delegation. Always use `msg.sender`.
2. ❌ **Assuming EOA code is immutable** → Post-7702, EOAs can have delegated code. Check for delegation designator if needed.
3. ❌ **Confusing EIP-7702 with ERC-4337** → 7702 = EOA delegation. 4337 = new smart account. Different approaches to AA.
4. ❌ **Not validating delegation in batch executors** → Add `require(msg.sender == address(this))` to prevent unauthorized execution.
5. ❌ **Assuming delegation is one-time** → Delegation persists across transactions until explicitly revoked.

**BLS12-381:**
1. ❌ **Saying "BLS is for zkSNARKs"** → BLS12-381 is for signature aggregation. zkSNARKs often use BN254 (alt-bn128).
2. ❌ **Not understanding the gas savings** → 99%+ reduction (1M gas → 8K gas). Enables on-chain validator consensus for liquid staking.

---

## 📋 Day 4 Summary

**✓ Covered:**
- EIP-7702 — EOA code delegation, delegation designator format, DELEGATECALL semantics
- Type 4 transactions — authorization lists and how the EVM processes them
- Security implications — `tx.origin` antipattern, delegation revocation, batch executor security
- Other Pectra EIPs — increased calldata costs, BLS12-381 precompile with liquid staking example

**Key takeaway:** EIP-7702 brings account abstraction to existing EOAs without migration. Combined with ERC-4337 (Section 4), this creates a comprehensive AA ecosystem. The `tx.origin` antipattern becomes actively exploitable with EIP-7702—always use `msg.sender` for authentication.

---

## 📚 Resources

### EIP-1153 — Transient Storage
- [EIP-1153 specification](https://eips.ethereum.org/EIPS/eip-1153) — full technical spec
- [Uniswap V4 PoolManager.sol](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) — production flash accounting using transient storage
- [go-ethereum PR #26003](https://github.com/ethereum/go-ethereum/pull/26003) — implementation discussion

### EIP-4844 — Proto-Danksharding
- [EIP-4844 specification](https://eips.ethereum.org/EIPS/eip-4844) — blob transactions and data availability
- [Ethereum.org — Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) — overview of all Dencun EIPs
- [L2Beat — Blob Explorer](https://l2beat.com/blobs) — see real-time blob usage and costs

### SELFDESTRUCT Changes
- [EIP-6780 specification](https://eips.ethereum.org/EIPS/eip-6780) — SELFDESTRUCT behavior change
- [Why SELFDESTRUCT was changed](https://ethereum-magicians.org/t/eip-6780-deactivate-selfdestruct-except-where-it-occurs-in-the-same-transaction-in-which-a-contract-was-created/13539) — Ethereum Magicians discussion

### EIP-7702 — EOA Code Delegation
- [EIP-7702 specification](https://eips.ethereum.org/EIPS/eip-7702) — full technical spec
- [Vitalik's account abstraction roadmap](https://notes.ethereum.org/@vbuterin/account_abstraction_roadmap) — context on how EIP-7702 fits into AA
- [Ethereum.org — Pectra upgrade](https://ethereum.org/en/roadmap/pectra/) — overview of all Pectra EIPs

### Other Pectra EIPs
- [EIP-3855 (PUSH0)](https://eips.ethereum.org/EIPS/eip-3855) — single-byte zero push
- [EIP-5656 (MCOPY)](https://eips.ethereum.org/EIPS/eip-5656) — memory copy opcode
- [EIP-7623 (Calldata cost)](https://eips.ethereum.org/EIPS/eip-7623) — increased calldata pricing
- [EIP-2537 (BLS precompile)](https://eips.ethereum.org/EIPS/eip-2537) — BLS12-381 pairing operations

---

**Navigation:** [← Previous: Section 1 - Solidity Modern](1-solidity-modern.md) | [Next: Section 3 - Token Approvals →](3-token-approvals.md)

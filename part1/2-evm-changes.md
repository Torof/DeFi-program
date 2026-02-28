# Module 2: EVM-Level Changes (~3 days)

## 📚 Table of Contents

**Foundational EVM Concepts**
- [EIP-2929: Cold/Warm Access Model](#eip-2929)
- [EIP-1559: Base Fee Market](#eip-1559)
- [EIP-3529: Gas Refund Changes & Death of Gas Tokens](#eip-3529)
- [Contract Size Limits (EIP-170)](#eip-170)
- [CREATE vs CREATE2 vs CREATE3](#create2)
- [Precompile Landscape](#precompiles)

**Dencun Upgrade (March 2024)**
- [Transient Storage Deep Dive (EIP-1153)](#transient-storage-deep-dive)
- [Proto-Danksharding (EIP-4844)](#proto-danksharding)
  - [Blob Fee Market Math](#blob-fee-math)
- [PUSH0 & MCOPY](#push0-mcopy)
- [SELFDESTRUCT Changes](#selfdestruct-changes)
- [Build Exercise: FlashAccounting](#day3-exercise)

**Pectra Upgrade (May 2025)**
- [EIP-7702 — EOA Code Delegation](#eip-7702)
  - [Delegation Designator Format](#delegation-designator)
- [EIP-7623 — Increased Calldata Cost](#eip-7623)
- [EIP-2537 — BLS12-381 Precompile](#eip-2537)
- [Build Exercise: EIP7702Delegate](#day4-exercise)

**Looking Ahead**
- [EOF (EVM Object Format)](#eof)

---

## Foundational EVM Concepts

These pre-Dencun EVM changes underpin everything else in this module. The gas table above references "cold" and "warm" costs — this section explains where those numbers come from, along with other foundational concepts every DeFi developer must know.

<a id="eip-2929"></a>
### 💡 Concept: EIP-2929 — Cold/Warm Access Model

**Why this matters:** Every time your DeFi contract reads or writes storage, calls another contract, or checks a balance, the gas cost depends on whether the address/slot has already been "accessed" in the current transaction. This is the single most important concept for gas optimization.

> Introduced in [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929), activated with the Berlin upgrade (April 2021)

**The model:**

Before EIP-2929, `SLOAD` cost a flat 800 gas regardless of access pattern. After EIP-2929, the EVM maintains an **access set** — a list of addresses and storage slots that have been touched during the transaction. The first access to any address or slot is "cold" (expensive), subsequent accesses are "warm" (cheap).

```
Access Set (maintained per-transaction by the EVM):
┌────────────────────────────────────────────────────┐
│  Addresses:                                         │
│    0xUniswapRouter  ← accessed (warm)               │
│    0xWETH           ← accessed (warm)               │
│    0xDAI            ← NOT accessed yet (cold)       │
│                                                     │
│  Storage Slots:                                     │
│    (0xWETH, slot 5)   ← accessed (warm)             │
│    (0xWETH, slot 12)  ← NOT accessed yet (cold)     │
└────────────────────────────────────────────────────┘
```

**Gas costs with cold/warm model:**

| Operation | Cold (first access) | Warm (subsequent) | Before EIP-2929 |
|-----------|-------------------|-------------------|-----------------|
| `SLOAD` | 2,100 gas | 100 gas | 800 gas (flat) |
| `CALL` / `STATICCALL` | 2,600 gas | 100 gas | 700 gas (flat) |
| `BALANCE` / `EXTCODESIZE` | 2,600 gas | 100 gas | 700 gas (flat) |
| `EXTCODECOPY` | 2,600 gas | 100 gas | 700 gas (flat) |

**Step-by-step: How cold/warm affects a Uniswap swap**

```solidity
function swap(address tokenIn, uint256 amountIn) external {
    // 1. SLOAD balances[msg.sender]
    //    First access to this slot → COLD → 2,100 gas
    uint256 balance = balances[msg.sender];

    // 2. SLOAD balances[msg.sender] again (in require)
    //    Same slot, already accessed → WARM → 100 gas ✨
    require(balance >= amountIn);

    // 3. SLOAD reserves[tokenIn]
    //    Different slot, first access → COLD → 2,100 gas
    uint256 reserve = reserves[tokenIn];

    // 4. CALL to tokenIn.transferFrom()
    //    First call to tokenIn address → COLD → 2,600 gas
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

    // 5. CALL to tokenIn.transfer()
    //    Same address, already accessed → WARM → 100 gas ✨
    IERC20(tokenIn).transfer(recipient, amountOut);
}
```

**Optimization: Access Lists (EIP-2930)**

[EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) introduced **access lists** — a way to pre-declare which addresses and storage slots your transaction will touch. Pre-declared items start "warm," avoiding the cold surcharge at the cost of a smaller upfront fee (1,900 gas per address, 100 gas per slot in the access list).

```
When to use access lists:
- Transaction touches many storage slots in external contracts
- You know exactly which slots will be accessed
- The cold→warm savings exceed the access list declaration cost

When NOT to use:
- Simple transfers (overhead exceeds savings)
- You don't know which slots will be accessed (dynamic routing)
```

**Real DeFi impact:**

In a multi-hop Uniswap V3 swap touching 3 pools:
- **Without access list**: 3 cold CALL + ~9 cold SLOAD = 3×2,600 + 9×2,100 = **26,700 gas** in cold penalties
- **With access list**: 3×1,900 + 9×100 = 6,600 gas upfront, all accesses warm = ~1,200 gas during execution = **7,800 gas total**
- **Savings**: ~19,000 gas (~71% reduction in access costs)

#### 🔗 DeFi Pattern Connection

**Where cold/warm access matters most:**

1. **DEX aggregators** (1inch, Paraswap) — Route through multiple pools. Each pool is a new address (cold). Aggregators use access lists to pre-warm pools on the route.
2. **Liquidation bots** — Read health factors (cold SLOAD), call liquidate (cold CALL), swap collateral (cold CALL). Access lists are critical for staying competitive on gas.
3. **Storage-heavy protocols** (Aave V3) — Multiple storage reads per operation. Aave packs related data in fewer slots to minimize cold reads.

#### 💼 Job Market Context

**Interview question:**

> "How do cold and warm storage accesses affect gas costs?"

**What to say:**

"Since EIP-2929 (Berlin upgrade), the EVM maintains an access set per transaction. The first read of any storage slot costs 2,100 gas (cold), subsequent reads cost 100 gas (warm). Same pattern for external calls — first call to an address costs 2,600 gas. This means the order you access storage matters: reading the same slot twice costs 2,200 gas total, not 4,200. You can also use EIP-2930 access lists to pre-warm slots, which is valuable for multi-pool DEX swaps and liquidation bots."

**Interview Red Flags:**
- 🚩 "SLOAD always costs 200 gas" — Outdated (pre-Berlin pricing)
- 🚩 Not knowing about access lists — Critical optimization tool
- 🚩 "Gas costs are the same for every storage read" — Cold/warm distinction is fundamental

---

<a id="eip-1559"></a>
### 💡 Concept: EIP-1559 — Base Fee Market

**Why this matters:** EIP-1559 fundamentally changed how Ethereum prices gas. Understanding it matters for MEV strategy, gas estimation, transaction ordering, and L2 fee models.

> Introduced in [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559), activated with the London upgrade (August 2021)

**The model:**

Before EIP-1559, gas pricing was a first-price auction: users bid gas prices, miners picked the highest bids. This led to overpaying, gas price volatility, and poor UX.

EIP-1559 split the gas price into two components:

```
Total gas price = base fee + priority fee (tip)

┌─────────────────────────────────────────────────┐
│ BASE FEE (burned)                                │
│ - Set by the protocol, not the user              │
│ - Adjusts based on block fullness                │
│ - If block > 50% full → base fee increases       │
│ - If block < 50% full → base fee decreases       │
│ - Max change: ±12.5% per block                   │
│ - Burned (removed from supply) — not paid        │
│   to validators                                  │
├─────────────────────────────────────────────────┤
│ PRIORITY FEE / TIP (paid to validator)           │
│ - Set by the user                                │
│ - Incentivizes validators to include your tx     │
│ - During congestion, higher tip = faster          │
│   inclusion                                      │
│ - During calm periods, 1-2 gwei is sufficient    │
└─────────────────────────────────────────────────┘
```

**Why DeFi developers care:**

1. **Gas estimation**: `block.basefee` is available in Solidity — protocols can read the current base fee for gas-aware logic
2. **MEV**: Searchers set high priority fees to get their bundles included. Understanding base fee vs. tip is essential for MEV strategies
3. **L2 fee models**: L2s adapt EIP-1559 for their own fee markets (Arbitrum ArbGas, Optimism L1 data fee + L2 execution fee)
4. **Protocol design**: Some protocols adjust fees based on gas conditions (e.g., oracle update frequency)

**DeFi-relevant Solidity globals:**

```solidity
block.basefee    // Current block's base fee (EIP-1559)
block.blobbasefee // Current block's blob base fee (EIP-4844)
tx.gasprice      // Actual gas price of the transaction (base + tip)
```

#### 💼 Job Market Context

**Interview question:**

> "How does EIP-1559 affect MEV strategies?"

**What to say:**

"EIP-1559 separated the gas price into base fee (burned, set by protocol) and priority fee (paid to validators, set by user). For MEV, the base fee is a floor cost you can't avoid — it determines whether an arbitrage is profitable. The priority fee is how you bid for inclusion. Flashbots bypasses the public mempool entirely, but understanding base fee dynamics helps you predict profitability windows and set appropriate tips."

---

<a id="eip-3529"></a>
### 💡 Concept: EIP-3529 — Gas Refund Changes

**Why this matters:** EIP-3529 killed the gas token pattern and changed how SSTORE refunds work. If you've ever seen CHI or GST2 tokens mentioned in old DeFi code, this is why they're dead.

> Introduced in [EIP-3529](https://eips.ethereum.org/EIPS/eip-3529), activated with the London upgrade (August 2021)

**What changed:**

Before EIP-3529:
- Clearing a storage slot (nonzero → zero) refunded 15,000 gas
- `SELFDESTRUCT` refunded 24,000 gas
- Refunds could offset up to 50% of total transaction gas

After EIP-3529:
- Clearing a storage slot refunds only 4,800 gas
- `SELFDESTRUCT` refund removed entirely
- Refunds capped at 20% of total transaction gas (down from 50%)

**The gas token exploit (now dead):**

```solidity
// Before EIP-3529: Gas tokens exploited the refund mechanism
contract GasToken {
    // During low gas prices: write to many storage slots (cheap)
    function mint(uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            assembly { sstore(add(i, 0x100), 1) }  // Write nonzero
        }
    }

    // During high gas prices: clear those slots (get refunds!)
    function burn(uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            assembly { sstore(add(i, 0x100), 0) }  // Clear → refund
        }
        // Each clear refunded 15,000 gas — effectively "stored" cheap gas
        // for use during expensive periods. Arbitrage on gas prices!
    }
}
// CHI (1inch) and GST2 (Gas Station Network) used this pattern.
// EIP-3529 reduced refunds to 4,800 gas, making gas tokens unprofitable.
```

**Impact on DeFi:**
- Any protocol that relied on SELFDESTRUCT gas refunds for economic models is broken
- Storage cleanup patterns still get some refund (4,800 gas), but it's not a significant optimization target anymore
- The 20% refund cap means you can't use gas refunds to subsidize large transactions

#### 💼 Job Market Context

**Interview question:** "What were gas tokens and why don't they work anymore?"

**What to say:** "Gas tokens like CHI and GST2 exploited the SSTORE gas refund mechanism. You'd write to storage slots during low gas prices, then clear them during high gas prices to get refunds of 15,000 gas per slot. EIP-3529 in the London upgrade reduced the refund to 4,800 gas and capped total refunds at 20% of transaction gas, making the pattern unprofitable. It also removed the SELFDESTRUCT refund entirely."

---

<a id="eip-170"></a>
### 💡 Concept: Contract Size Limits (EIP-170)

**Why this matters:** If you're building a full-featured DeFi protocol, you will hit the 24 KiB contract size limit. Knowing the strategies to work around it is essential practical knowledge.

> Introduced in [EIP-170](https://eips.ethereum.org/EIPS/eip-170), activated with the Spurious Dragon upgrade (November 2016)

**The limit:** Deployed contract bytecode cannot exceed **24,576 bytes** (24 KiB). Attempting to deploy a larger contract reverts with an out-of-gas error.

**Why DeFi protocols hit this:**

Complex protocols (Aave, Uniswap, Compound) have many functions, modifiers, and internal logic. With Solidity's inline expansion of internal functions, a contract can easily exceed 24 KiB.

**Strategies to stay under the limit:**

| Strategy | Description | Tradeoff |
|----------|-------------|----------|
| **Optimizer** | `optimizer = true`, `runs = 200` in foundry.toml | Reduces bytecode but increases compile time |
| **`via_ir`** | `via_ir = true` in foundry.toml — uses the Yul IR optimizer | More aggressive optimization, slower compilation |
| **Libraries** | Extract logic into `library` contracts with `using for` | Adds DELEGATECALL overhead per call |
| **Split contracts** | Divide into core + periphery contracts | Adds deployment and integration complexity |
| **Diamond pattern** | [EIP-2535](https://eips.ethereum.org/EIPS/eip-2535) — modular facets behind a single proxy | Complex but powerful for large protocols |
| **Custom errors** | Replace `require(cond, "long string")` with custom errors | Saves ~200 bytes per error message |
| **Remove unused code** | Dead code still compiles into bytecode | Free — always do this first |

**Real DeFi examples:**

- **Aave V3**: Split into `Pool.sol` (core) + `PoolConfigurator.sol` + `L2Pool.sol` — each under 24 KiB
- **Uniswap V3**: `NonfungiblePositionManager.sol` required careful optimization to stay under the limit
- **Compound V3**: Uses the "Comet" architecture with a single streamlined contract

```toml
# foundry.toml — common settings for large DeFi contracts
[profile.default]
optimizer = true
optimizer_runs = 200     # Lower = smaller bytecode, higher = cheaper runtime
via_ir = true           # Yul IR optimizer — often saves 10-20% bytecode
evm_version = "cancun"  # PUSH0 saves ~1 byte per zero-push
```

#### 💼 Job Market Context

**Interview question:** "Your contract is 26 KiB and won't deploy. What do you do?"

**What to say:** "First, enable the optimizer with `via_ir = true` and lower `optimizer_runs` — this often saves 10-20% bytecode. Second, replace string revert messages with custom errors. Third, check for dead code. If it's still too large, extract read-only view functions into a separate 'Lens' contract, or split business logic into a core + periphery pattern. For very large protocols, the Diamond pattern (EIP-2535) provides modular facets behind a single proxy address. I'd also check if any internal functions should be external libraries instead."

---

<a id="create2"></a>
### 💡 Concept: CREATE vs CREATE2 vs CREATE3

**Why this matters:** Deterministic contract deployment is critical DeFi infrastructure. Uniswap uses it for pool deployment, Safe for wallet creation, and understanding it is essential for the [SELFDESTRUCT](#selfdestruct-changes) metamorphic attack explanation later in this module.

**The three deployment methods:**

```
┌───────────────────────────────────────────────────────────┐
│ CREATE (opcode 0xF0)                                      │
│ address = keccak256(sender, nonce)                        │
│                                                           │
│ - Address depends on deployer's nonce (tx count)          │
│ - Non-deterministic: deploying the same code from         │
│   different nonces gives different addresses              │
│ - Standard deployment method                              │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│ CREATE2 (opcode 0xF5, EIP-1014, Constantinople 2019)     │
│ address = keccak256(0xff, sender, salt, keccak256(code))  │
│                                                           │
│ - Address is DETERMINISTIC — depends on:                  │
│   1. The deployer address (sender)                        │
│   2. A user-chosen salt (bytes32)                         │
│   3. The init code hash                                   │
│ - Same inputs → same address, regardless of nonce         │
│ - Enables counterfactual addresses (know the address      │
│   before deployment)                                      │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│ CREATE3 (not an opcode — a pattern)                       │
│ address = keccak256(0xff, deployer, salt, PROXY_HASH)     │
│                                                           │
│ - Deploys a minimal proxy via CREATE2, then the proxy     │
│   deploys the actual contract via CREATE                  │
│ - Address depends ONLY on deployer + salt (not init code) │
│ - Same address across chains even if constructor args     │
│   differ (chain-specific config)                          │
│ - Used by: Axelar, LayerZero for cross-chain deployments  │
└───────────────────────────────────────────────────────────┘
```

**CREATE2 in DeFi — the key pattern:**

```solidity
// How Uniswap V2 deploys pair contracts deterministically
function createPair(address tokenA, address tokenB) external returns (address pair) {
    bytes32 salt = keccak256(abi.encodePacked(token0, token1));

    // CREATE2: address is deterministic based on tokens
    pair = address(new UniswapV2Pair{salt: salt}());

    // Anyone can compute the pair address WITHOUT calling the factory:
    // address pair = address(uint160(uint256(keccak256(abi.encodePacked(
    //     hex"ff",
    //     factory,
    //     keccak256(abi.encodePacked(token0, token1)),
    //     INIT_CODE_HASH
    // )))));
}
```

**Why counterfactual addresses matter:**

```solidity
// Routers can compute pair addresses off-chain without storage reads
function getAmountsOut(uint256 amountIn, address[] calldata path)
    external view returns (uint256[] memory)
{
    for (uint256 i = 0; i < path.length - 1; i++) {
        // No SLOAD needed! Compute pair address from tokens:
        address pair = computePairAddress(path[i], path[i + 1]);
        // This saves ~2,100 gas (cold SLOAD) per hop
        (uint256 reserveIn, uint256 reserveOut) = getReserves(pair);
        amounts[i + 1] = getAmountOut(amountIn, reserveIn, reserveOut);
    }
}
```

**Safe (Gnosis Safe) wallet deployment:**

CREATE2 enables **counterfactual wallets** — you can send funds to a Safe address before the Safe is even deployed. The address is computed from the owners + threshold + salt. When the user is ready, they deploy the Safe at the pre-computed address and the funds are already there.

**The metamorphic contract risk (now dead):**

CREATE2 address depends on init code hash. If you can SELFDESTRUCT a contract and redeploy different code at the same address, you get a metamorphic contract. **EIP-6780 killed this** — see [SELFDESTRUCT Changes](#selfdestruct-changes) below.

> 🔍 **Deep dive:** Module 7 (Deployment) covers CREATE2 deployment scripts and cross-chain deployment patterns in detail. This section provides the conceptual foundation.

#### 💼 Job Market Context

**Interview question:** "What's CREATE2 and why does Uniswap use it?"

**What to say:** "CREATE2 gives deterministic contract addresses based on the deployer, a salt, and the init code hash — unlike CREATE where the address depends on the nonce. Uniswap uses it so any contract can compute a pair's address off-chain by hashing the two token addresses, without needing a storage read. This saves ~2,100 gas per pool lookup in multi-hop swaps. Safe uses it for counterfactual wallets — you know the wallet address before deployment so you can send funds to it first. The newer CREATE3 pattern makes addresses independent of init code, which is useful for cross-chain deployments where constructor args differ per chain."

---

<a id="precompiles"></a>
### 💡 Concept: Precompile Landscape

**Why this matters:** Precompiles are native EVM functions at fixed addresses, much cheaper than equivalent Solidity. You've used `ecrecover` (address `0x01`) every time you verify an ERC-2612 permit signature.

**The precompile addresses:**

| Address | Name | Gas | DeFi Usage |
|---------|------|-----|------------|
| `0x01` | **ecrecover** | 3,000 | ERC-2612 permit, EIP-712 signatures, meta-transactions |
| `0x02` | SHA-256 | 60 + 12/word | Bitcoin SPV proofs (rare in DeFi) |
| `0x03` | RIPEMD-160 | 600 + 120/word | Bitcoin address derivation (rare) |
| `0x04` | Identity (memcpy) | 15 + 3/word | Compiler optimization (transparent) |
| `0x05` | **modexp** | Variable | RSA verification, large-number math |
| `0x06` | **ecAdd** (BN254) | 150 | zkSNARK verification (Tornado Cash, zkSync) |
| `0x07` | **ecMul** (BN254) | 6,000 | zkSNARK verification |
| `0x08` | **ecPairing** (BN254) | 34,000 + per-pair | zkSNARK verification |
| `0x09` | **blake2f** | Variable | Zcash interop (rare) |
| `0x0a` | **point evaluation** | 50,000 | EIP-4844 blob verification |
| `0x0b`-`0x13` | **BLS12-381** | Variable | Validator signatures ([see above](#eip-2537)) |

**The ones that matter for DeFi:**

1. **ecrecover (`0x01`)** — Used in every `permit()` call, every EIP-712 typed data signature, every meta-transaction. You've been using this indirectly through `ECDSA.recover()` from OpenZeppelin.

2. **BN254 pairing (`0x06`-`0x08`)** — The foundation of zkSNARK verification on Ethereum. Tornado Cash, zkSync's proof verification, and privacy protocols all depend on these. Note: this is a different curve from BLS12-381.

3. **BLS12-381 (`0x0b`-`0x13`)** — New in Pectra. Enables on-chain validator signature verification. See the [BLS section above](#eip-2537).

**Key distinction:** BN254 (alt-bn128) is for zkSNARKs. BLS12-381 is for signature aggregation. Different curves, different use cases. Confusing them is a common interview mistake.

---

## Dencun Upgrade — EIP-1153 & EIP-4844

<a id="transient-storage-deep-dive"></a>
### 💡 Concept: Transient Storage Deep Dive (EIP-1153)

**Why this matters:** You've used `transient` in Solidity. Now understand what the EVM actually does. Uniswap V4's entire architecture—the flash accounting that lets you batch swaps, add liquidity, and pay only net balances—depends on transient storage behaving exactly right across `CALL` boundaries.

> 🔗 **Connection to Module 1:** Remember the [TransientGuard exercise](1-solidity-modern.md#day2-exercise)? You used the `transient` keyword and raw `tstore`/`tload` assembly. Now we're diving into **how EIP-1153 actually works at the EVM level**—the opcodes, gas costs, and why it's revolutionary for DeFi.

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
│                       CALLDATA                              │
│  - Byte-addressed, read-only input to a call               │
│  - Per call frame (each call has its own calldata)         │
│  - ~3 gas per 32 bytes (CALLDATALOAD)                      │
│  - Cheaper than memory for read-only access                │
│  - In DeFi: function args, encoded swap paths, proofs      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                       RETURNDATA                            │
│  - Byte-addressed, output from the last external call      │
│  - Overwritten on each new CALL/STATICCALL/DELEGATECALL    │
│  - ~3 gas per 32 bytes (RETURNDATACOPY)                    │
│  - In DeFi: decoded return values, revert reasons          │
└─────────────────────────────────────────────────────────────┘

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
│  - First access: ~2,100 gas (cold) — see EIP-2929 below   │
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

    // Note: `view` is valid here — tload is a read-only opcode (like sload).
    // The compiler treats transient storage reads the same as storage reads
    // for function mutability purposes.
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
| `SLOAD` (storage read) | 2,100 gas | 100 gas | First access in tx is "cold" ([EIP-2929](#eip-2929)) |
| `SSTORE` (zero→nonzero) | 20,000 gas | 20,000 gas | Adds new data to state (cold/warm affects slot access, not write cost) |
| `SSTORE` (nonzero→nonzero) | 5,000 gas | 5,000 gas | Modifies existing data (+2,100 cold surcharge on first access) |
| `SSTORE` (nonzero→zero) | 5,000 gas | 5,000 gas | Removes data (gets partial refund — [EIP-3529](#eip-3529)) |
| **`TLOAD`** | **100 gas** | **100 gas** | Always same cost ✨ |
| **`TSTORE`** | **100 gas** | **100 gas** | Always same cost ✨ |
| `MLOAD`/`MSTORE` (memory) | ~3 gas | ~3 gas | Cheapest but doesn't persist |

> **Note:** SSTORE costs shown are the base write cost. If the storage slot hasn't been accessed yet in the transaction (cold), EIP-2929 adds a 2,100 gas cold access surcharge on top. Once the slot is warm, subsequent SSTOREs to the same slot pay only the base cost. See [EIP-2929 section](#eip-2929) for the full cold/warm model.

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

2. **Temporary approvals**: [ERC-20](https://eips.ethereum.org/EIPS/eip-20) approvals that last only for the current transaction—approve, use, and automatically revoke, all without touching persistent storage.

3. **Callback validation**: A contract can set a transient flag before making an external call that expects a callback, then verify in the callback that it was legitimately triggered by the calling contract.

💻 **Quick Try:**

Test transient storage in Remix (requires Solidity 0.8.24+, set EVM version to `cancun`):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TransientDemo {
    uint256 transient counter;  // Lives only during transaction

    // Note: `view` is valid — reading transient storage (tload) is treated
    // like reading regular storage (sload) for mutability purposes.
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
- `unlock()` opens a flash accounting session (calls back via `unlockCallback`)
- Swaps, adds liquidity, removes liquidity all update transient deltas
- `settle()` enforces that you've paid what you owe (or received what you're owed)
- All within ~300 gas for the unlock mechanism ✨

> ⚠️ **Common pitfall—new reentrancy vectors:** Because `TSTORE` costs only ~100 gas, it can execute within the 2,300 gas stipend that `transfer()` and `send()` forward. A contract receiving ETH via `transfer()` can now execute `TSTORE` (something impossible with `SSTORE`). This creates new reentrancy attack surfaces in contracts that assumed 2,300 gas was "safe." This is one reason `transfer()` and `send()` are deprecated — [Solidity 0.8.31](https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/) emits compiler warnings, and they'll be removed entirely in 0.9.0.

> 🔍 **Deep dive:** [ChainSecurity - TSTORE Low Gas Reentrancy](https://www.chainsecurity.com/blog/tstore-low-gas-reentrancy) demonstrates the attack with code examples. Their [GitHub repo](https://github.com/ChainSecurity/TSTORE-Low-Gas-Reentrancy) provides exploit POCs.

**The attack in code:**

```solidity
// VULNERABLE: This vault uses a transient-storage-based reentrancy guard,
// but sends ETH via transfer() BEFORE updating state.
contract VulnerableVault {
    uint256 transient _locked;

    modifier nonReentrant() {
        require(_locked == 0, "locked");
        _locked = 1;
        _;
        _locked = 0;
    }

    mapping(address => uint256) public balances;

    function withdraw() external nonReentrant {
        uint256 bal = balances[msg.sender];
        // Sends ETH via transfer() — 2,300 gas stipend
        payable(msg.sender).transfer(bal);
        balances[msg.sender] = 0;  // State update AFTER transfer
    }
}

// ATTACKER: Pre-Cancun, transfer()'s 2,300 gas stipend was too little
// for SSTORE (~5,000+ gas), so reentrancy via transfer() was "impossible."
// Post-Cancun, TSTORE costs only ~100 gas — well within the 2,300 budget.
contract Attacker {
    VulnerableVault vault;
    uint256 transient _attackCount;  // TSTORE fits in 2,300 gas!

    receive() external payable {
        // This executes within transfer()'s 2,300 gas stipend.
        // Pre-Cancun: SSTORE here would exceed gas limit → safe.
        // Post-Cancun: TSTORE costs ~100 gas → attack is possible.
        if (_attackCount < 3) {
            _attackCount += 1;      // ~100 gas (TSTORE)
            vault.withdraw();       // Re-enters! Guard uses transient storage
                                    // but the SAME transient slot is already 1
                                    // Wait — the guard checks _locked == 0...
        }
    }
}
// KEY INSIGHT: The guard actually blocks this specific attack because _locked
// is still 1 during re-entry. The REAL danger is contracts that DON'T use
// a reentrancy guard but relied on transfer()'s gas limit as implicit protection.
// Post-Cancun, transfer()/send() are NO LONGER safe assumptions for reentrancy
// prevention. Always use explicit guards + checks-effects-interactions.
```

> **Bottom line:** The transient reentrancy guard itself is fine — it's contracts that relied on `transfer()`'s gas limit *instead of* a guard that are now vulnerable. Any contract that assumed "2,300 gas isn't enough to do anything dangerous" is broken post-Cancun.

🏗️ **Real usage:**

Read [Uniswap V4's PoolManager.sol](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol)—the entire protocol is built on transient storage tracking deltas. You'll see this pattern in Part 3.

**📖 Code Reading Strategy for Uniswap V4 PoolManager:**

When you open PoolManager.sol, follow this path to understand the flash accounting:

1. **Start at the top**: Find the transient storage declarations
   ```solidity
   // Look for transient state in PoolManager and related contracts:
   // Currency deltas tracked per-caller in transient storage
   // NonzeroDeltaCount tracks how many currencies have outstanding deltas
   ```

2. **Understand the unlock mechanism**: Search for `function unlock()`
   - Notice how it uses a callback pattern: `IUnlockCallback(msg.sender).unlockCallback(...)`
   - The caller executes all operations inside the callback
   - `_nonzeroDeltaCount` tracks how many currencies still have unsettled deltas

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

**Interview Red Flags:**

- 🚩 "Transient storage is like memory but cheaper" — No! It's more expensive than memory (~100 vs ~3 gas)
- 🚩 "You can use transient storage to avoid storage costs" — Only if data doesn't need to persist across transactions
- 🚩 "TSTORE is always cheaper than SSTORE" — True, but irrelevant if you need persistence

**What production DeFi engineers know:**

1. **Reentrancy guards**: If your protocol will be deployed post-Cancun (March 2024), use transient guards
2. **Flash accounting**: Essential for any multi-step operation (swaps, liquidity management, flash loans)
3. **The 2,300 gas pitfall**: TSTORE works within `transfer()`/`send()` stipend—creates new reentrancy vectors
4. **Testing**: Foundry's `vm.transient*` cheats for testing transient storage behavior

**Pro tip:** Flash accounting is THE architectural pattern to understand for DEX/AMM roles. If you can whiteboard how Uniswap V4's PoolManager tracks deltas in transient storage and enforces settlement, you'll demonstrate systems-level thinking that separates senior candidates from mid-level ones.

---

<a id="proto-danksharding"></a>
### 💡 Concept: Proto-Danksharding (EIP-4844)

**Why this matters:** If you're building on L2 (Arbitrum, Optimism, Base, Polygon zkEVM), your users' transaction costs dropped 90-95% after Dencun. Understanding blob transactions explains why.

> Introduced in [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844), activated with the [Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) (March 2024)

**What changed:**

EIP-4844 introduced "blob transactions"—a new transaction type (Type 3) that carries large data blobs (128 KiB / 131,072 bytes each) at significantly lower cost than calldata. The blobs are available temporarily (roughly 18 days) and then pruned from the consensus layer.

**📊 The impact on L2 DeFi:**

Before Dencun, L2s posted transaction data to L1 as expensive calldata (~16 gas/byte). After Dencun, they post to cheap blob space (~1 gas/byte or less, depending on demand).

<a id="blob-fee-math"></a>
#### 🔍 Deep Dive: Blob Fee Market Math

**The blob fee formula:**

Blobs use an **independent fee market** from regular gas. The blob base fee adjusts based on cumulative excess blob gas:

```
blob_base_fee = MIN_BLOB_BASE_FEE × e^(excess_blob_gas / BLOB_BASE_FEE_UPDATE_FRACTION)

Where:
- Each blob = 131,072 blob gas
- Target: 3 blobs per block = 393,216 blob gas
- Maximum: 6 blobs per block = 786,432 blob gas
- excess_blob_gas accumulates across blocks:
    excess(block_n) = max(0, excess(block_n-1) + blob_gas_used - 393,216)
- BLOB_BASE_FEE_UPDATE_FRACTION = 3,338,477
- MIN_BLOB_BASE_FEE = 1 wei
```

**Step-by-step calculation:**

1. **Block has 3 blobs (target)**: excess_blob_gas unchanged → fee stays the same
2. **Block has 6 blobs (max)**: excess_blob_gas increases by 393,216 → fee multiplies by e^(393,216/3,338,477) ≈ **1.125** (~12.5% increase per max block)
3. **Block has 0 blobs**: excess_blob_gas decreases by up to 393,216 → fee drops
4. **After ~8.5 consecutive max blocks**: excess accumulates enough for fee to roughly triple (e^1 ≈ 2.718)

**Why this matters:**

The fee adjusts gradually — it takes many consecutive full blocks to drive fees up significantly. In practice, blob demand rarely sustains max capacity for long, so blob fees stay **very low** most of the time.

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

Two separate costs (blobs have their OWN fee market):

1. Blob fee (priced in blob gas, NOT regular gas):
   Blob gas = 2 blobs × 131,072 = 262,144 blob gas
   At minimum blob price (~1 wei per blob gas):
   = 262,144 wei ≈ $0.0000008 (essentially free)

2. L1 transaction overhead (regular gas for the Type 3 tx):
   ~50,000 gas for tx base + versioned hash calldata
   At 20 gwei and $3,000 ETH:
   = 50,000 × 20 × 10^-9 × $3,000 = $3.00

Total ≈ $3.00 per batch = $0.003 per transaction
```

**Savings: ~98% reduction ($192 → ~$3)**

The blob data itself is nearly free — the remaining cost is just the L1 transaction overhead. During blob fee spikes (high demand), the blob portion increases, but typical post-Dencun costs match the real-world figures in the table above.

💻 **Quick Try:**

EIP-4844 is **infrastructure-level** (L2 sequencers use it to post data to L1), not application-level. You won't write blob transaction code in your DeFi contracts. But you CAN read the blob base fee on-chain:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Read blob base fee — available in contracts targeting Cancun+
contract BlobFeeReader {
    /// @dev block.blobbasefee returns the current blob base fee (EIP-7516)
    function currentBlobBaseFee() external view returns (uint256) {
        return block.blobbasefee;
    }

    /// @dev Compare blob fee to regular gas price
    function feeComparison() external view returns (
        uint256 blobBaseFee,
        uint256 regularGasPrice,
        uint256 ratio
    ) {
        blobBaseFee = block.blobbasefee;
        regularGasPrice = tx.gasprice;
        ratio = regularGasPrice > 0 ? blobBaseFee / regularGasPrice : 0;
    }
}
```

Deploy in Remix (set EVM to `cancun`) and call `currentBlobBaseFee()`. In a local environment it returns 1 (minimum). On mainnet, it fluctuates based on blob demand.

**Explore further:**
1. **[Etherscan Dencun Upgrade](https://etherscan.io/txs?block=19426587)** — first Dencun block, March 13, 2024. Look for Type 3 blob transactions.
2. **[L2Beat Blobs](https://l2beat.com/blobs)** — real-time blob usage by L2s, fee market dynamics.
3. **Read blob data**: Use `eth_getBlob` RPC if your node supports it (within 18-day window).

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

**Interview Red Flags:**

- 🚩 "EIP-4844 is full Danksharding" — No! It's **proto**-Danksharding. Full danksharding will shard blob data across validators.
- 🚩 "Blobs are stored on-chain forever" — No! Blobs are pruned after ~18 days. L2 nodes keep the data.
- 🚩 "My DeFi contract needs to handle blobs" — No! Blobs are for L2→L1 data posting, not application contracts.

**What production DeFi engineers know:**

1. **L2 selection matters**: Post-Dencun, **Base, Optimism, Arbitrum** became equally cheap. Choose based on liquidity, ecosystem, not cost.
2. **Blob fee spikes**: During congestion, blob fees can spike (like March 2024 inscriptions). Your L2 costs are tied to blob fee volatility.
3. **The 18-day window**: If you're building infra (block explorers, analytics), you need to archive blob data within 18 days.
4. **Future scaling**: EIP-4844 is step 1. Full danksharding will increase from 6 max blobs per block to potentially 64+, further reducing costs.

**Pro tip:** When interviewing for L2-focused teams, frame EIP-4844 as a protocol design lever: "Post-Dencun, I'd design for higher frequency, smaller transactions because the L1 data cost bottleneck is largely gone." This shows you think about infrastructure economics, not just smart contract logic.

---

<a id="push0-mcopy"></a>
### 💡 Concept: PUSH0 (EIP-3855, Shanghai) and MCOPY (EIP-5656, Cancun)

**Behind-the-scenes optimizations** that make your compiled contracts smaller and cheaper:

> Note: PUSH0 was activated in the **Shanghai upgrade** (April 2023), predating Dencun. MCOPY was activated in Dencun (March 2024). Both are covered here because they affect post-Dencun compiler output.

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

**Interview Red Flags:**

- 🚩 "I manually use PUSH0 in my code" — The compiler does this automatically
- 🚩 "MCOPY makes all operations faster" — Only memory-to-memory copies, not storage or other operations
- 🚩 "Setting EVM version to `cancun` might break my Solidity code" — Source code is backwards compatible. However, if deploying to a chain that hasn't activated Cancun, the bytecode will fail (new opcodes aren't available). Always match your EVM target to the deployment chain.

**What production DeFi engineers know:**

1. **Always set `evm_version = "cancun"`** in foundry.toml for post-Dencun deployments
2. **Bytecode size matters**: PUSH0 helps stay under the 24KB contract size limit
3. **Pre-Shanghai deployments**: If deploying to a chain that hasn't upgraded, use `paris` or earlier
4. **Gas profiling**: Use `forge snapshot` to measure actual gas savings, not assumptions
5. **The 80/20 rule**: These opcodes give ~5-10% savings. Storage optimization gives 50%+ savings. Focus on the latter.

**Pro tip:** If asked about gas optimization in interviews, mention PUSH0/MCOPY as "free wins from the compiler" then pivot to the high-impact stuff: reducing SSTORE operations, batching with transient storage, minimizing cold storage reads. Teams want engineers who know where the real gas costs are.

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

**Real attack: [Tornado Cash governance (2023)](https://www.halborn.com/blog/post/explained-the-tornado-cash-hack-may-2023)**

An attacker used metamorphic contracts to:
- Deploy a proposal contract with benign code
- Get it approved by governance vote
- SELFDESTRUCT + redeploy with malicious code
- Drain governance funds

**Post-EIP-6780: This attack is impossible**

`SELFDESTRUCT` now only deletes code if called in the **same transaction** as deployment. The redeploy attack requires two transactions (deploy → selfdestruct → redeploy), so the code persists.

> ⚡ **Common pitfall:** If you're reading older DeFi code (pre-2024) and see `SELFDESTRUCT` used for upgrade patterns, be aware that pattern is now obsolete. Modern upgradeable contracts use UUPS or Transparent Proxy patterns (covered in Module 6).

> 🔍 **Deep dive:** [Dedaub - Removal of SELFDESTRUCT](https://dedaub.com/blog/eip-4758-eip-6780-removal-of-selfdestruct/) explains security benefits. [Vibranium Audits - EIP-6780 Objectives](https://www.vibraniumaudits.com/post/taking-self-destructing-contracts-to-the-next-level-the-objectives-of-eip-6780) covers how metamorphic contracts were exploited in governance attacks.

#### 💼 Job Market Context: SELFDESTRUCT Changes

**Interview question:**

> "I noticed your ERC-20 contract has a `kill()` function using SELFDESTRUCT. Is that still safe?"

**What to say (This is a red flag test!):**

"Actually, SELFDESTRUCT behavior changed with EIP-6780 in the Dencun upgrade (March 2024). It no longer deletes contract code unless called in the same transaction as deployment. The `kill()` function will send ETH to the target address but the contract code and storage will remain. If the goal is to disable the contract, we should use a `paused` state variable instead. Using SELFDESTRUCT post-Dencun suggests the codebase hasn't been updated for recent EVM changes, which is a red flag."

**Interview Red Flags:**

- 🚩 Any contract using `SELFDESTRUCT` for upgradability (broken post-Dencun)
- 🚩 Contracts that rely on `SELFDESTRUCT` freeing up storage (no longer true)
- 🚩 Documentation mentioning CREATE2 + SELFDESTRUCT for redeployment (metamorphic pattern dead)

**What production DeFi engineers know:**

1. **Pause, don't destroy**: Use OpenZeppelin's `Pausable` pattern instead of SELFDESTRUCT
2. **Upgradability**: Use UUPS or Transparent Proxy (Module 6), not metamorphic contracts
3. **The one exception**: Factory contracts that deploy+test+destroy in a single transaction (rare)
4. **Historical code**: Pre-2024 contracts may have SELFDESTRUCT—understand it won't work as originally intended

**Pro tip:** Knowing the Tornado Cash metamorphic governance exploit in detail is a strong auditor signal. If you can explain the deploy → whitelist → selfdestruct → redeploy attack chain and why EIP-6780 killed it, you demonstrate both historical awareness and security mindset.

---

<a id="day3-exercise"></a>
## 🎯 Build Exercise: FlashAccounting

**Workspace:** [`workspace/src/part1/module2/exercise1-flash-accounting/`](../workspace/src/part1/module2/exercise1-flash-accounting/) — starter file: [`FlashAccounting.sol`](../workspace/src/part1/module2/exercise1-flash-accounting/FlashAccounting.sol), tests: [`FlashAccounting.t.sol`](../workspace/test/part1/module2/exercise1-flash-accounting/FlashAccounting.t.sol)

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

## ⚠️ Common Mistakes: Dencun Recap

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
1. ❌ **Using SELFDESTRUCT for upgradability** → Broken post-Dencun. Use proxy patterns (Module 6).
2. ❌ **Relying on SELFDESTRUCT for contract removal** → Code persists unless called in same transaction as deployment.
3. ❌ **Trusting pre-2024 code with SELFDESTRUCT** → Understand it won't work as originally intended.

---

## 📋 Summary: Foundational Concepts & Dencun Upgrade

**✓ Covered (Foundational):**
- EIP-2929 cold/warm access model — why first storage read costs 2,100 gas vs 100 gas, access lists
- EIP-1559 base fee market — base fee + priority fee, MEV implications
- EIP-3529 gas refund reduction — death of gas tokens (CHI, GST2)
- Contract size limits (EIP-170) — the 24 KiB limit and strategies to work around it
- CREATE vs CREATE2 vs CREATE3 — deterministic deployment, counterfactual addresses
- Precompile landscape — ecrecover, BN254 (zkSNARKs), BLS12-381 (signatures)

**✓ Covered (Dencun):**
- Transient storage mechanics (EIP-1153) — how it differs from memory and storage, gas costs, flash accounting
- Flash accounting pattern — Uniswap V4's core innovation with code reading strategy
- Proto-Danksharding (EIP-4844) — why L2s became 90-97% cheaper, blob fee market math
- PUSH0 & MCOPY — bytecode comparisons and gas savings
- SELFDESTRUCT changes (EIP-6780) — metamorphic contracts are dead, historical context

**Next:** EIP-7702 (EOA code delegation) and the Pectra upgrade

---

## Pectra Upgrade — EIP-7702 and Beyond

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
- ✅ **Use paymasters**: Have someone else pay gas fees (covered in Module 4)
- ✅ **Implement custom validation**: Use multisig, passkeys, session keys, etc.
- ✅ **All without creating a new smart account**

**Example flow:**

1. Alice (EOA) signs an authorization to delegate to a BatchExecutor contract
2. Alice submits a Type 4 transaction with the authorization
3. For that transaction, Alice's EOA acts like a smart account with batching capabilities
4. Alice can batch: approve USDC → swap on Uniswap → stake in Aave, all atomically ✨

<a id="delegation-designator"></a>
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

> 🔍 **Deep dive:** EIP-7702 is closely related to ERC-4337 (Module 4). The difference: ERC-4337 requires deploying a new smart account, while EIP-7702 upgrades existing EOAs. Read [Vitalik's post on EIP-7702](https://notes.ethereum.org/@vbuterin/account_abstraction_roadmap) for the full account abstraction roadmap.

**Security considerations:**

- **`msg.sender` vs `tx.origin`**: When an EIP-7702-delegated EOA calls your contract, `msg.sender` is the EOA address (as expected). But `tx.origin` is also the EOA. Be careful with `tx.origin` checks—they can't distinguish between direct EOA calls and delegated calls.
- **Delegation revocation**: A user can always sign a new authorization pointing to a different contract (or to zero address to revoke delegation). Your DeFi protocol shouldn't assume delegation is permanent.

> ⚡ **Common pitfall:** Some contracts use `tx.origin` checks for authentication (e.g., "only allow if `tx.origin == owner`"). These patterns break with EIP-7702 because delegated calls have the same `tx.origin` as direct calls. Avoid `tx.origin`-based authentication.

> 🔍 **Deep dive:** [QuickNode - EIP-7702 Implementation Guide](https://www.quicknode.com/guides/ethereum-development/smart-contracts/eip-7702-smart-accounts) provides hands-on Foundry examples. [Biconomy - Comprehensive EIP-7702 Guide](https://blog.biconomy.io/a-comprehensive-eip-7702-guide-for-apps/) covers app integration. [Gelato - Account Abstraction from ERC-4337 to EIP-7702](https://gelato.cloud/blog/gelato-s-guide-to-account-abstraction-from-erc-4337-to-eip-7702) explains how EIP-7702 compares to ERC-4337.

**📖 Code Reading Strategy for EIP-7702 Delegation Targets:**

Real delegation targets are what EOAs point to via EIP-7702. Study them to understand production security patterns:

1. **Start with the interface** — Look for `execute(Call[])` or `executeBatch()`. Every delegation target exposes a batch execution entry point.
2. **Find the auth check** — Search for `msg.sender == address(this)`. This is the critical guard: in delegated context, `address(this)` is the EOA, so only the EOA owner can trigger execution.
3. **Check for module support** — Modern targets (Rhinestone, Biconomy) support pluggable validators and executors. Look for `isValidSignature()` and module registry patterns.
4. **Look at fallback handling** — What happens if someone calls an unknown function on the delegated EOA? Good targets have a secure `fallback()` that either reverts or routes to modules.
5. **Test files first** — As always, start with the test suite. Search for `test_batch`, `test_unauthorized`, `test_delegatecall` to see what security properties are verified.

**Recommended study order:**
- [Alchemy LightAccount](https://github.com/alchemyplatform/light-account/blob/main/src/LightAccount.sol) — cleanest minimal implementation
- [Rhinestone ModuleKit](https://github.com/rhinestonewtf/modulekit) — modular architecture with validators/executors
- [Biconomy Nexus](https://github.com/bcnmy/nexus) — production AA account with EIP-7702 support

**Don't get stuck on:** Module installation/uninstallation flows or ERC-4337 `validateUserOp()` specifics — those are Module 4 topics. Focus on the batch execution path and auth model.

#### 💼 Job Market Context: EIP-7702

**Interview question you WILL be asked:**

> "How does EIP-7702 differ from ERC-4337 for account abstraction?"

**What to say (30-second answer):**

"ERC-4337 requires deploying a new smart account contract—the user creates a dedicated account abstraction wallet separate from their EOA. EIP-7702 lets existing EOAs temporarily delegate to smart contract code without deploying anything new. The EOA's code is set to a delegation designator (0xef0100 + address), and calls to the EOA DELEGATECALL to the implementation. Key difference: EIP-7702 is reversible and works with existing wallets, while ERC-4337 requires user migration to a new address. Both enable batching, paymasters, and custom validation, but EIP-7702 reduces onboarding friction."

**Follow-up question:**

> "Your DeFi protocol has a function that checks `tx.origin == owner` for admin access. What happens with EIP-7702?"

**What to say (This is a red flag test!):**

"That's a security vulnerability. With EIP-7702, when an EOA delegates to a batch executor, `tx.origin` is still the EOA address even though the code executing is from the delegated contract. An attacker could trick the owner into batching malicious calls alongside legitimate ones, bypassing the `tx.origin` check. The fix is to use `msg.sender` instead of `tx.origin`, or implement a proper access control pattern like OpenZeppelin's `Ownable`. Using `tx.origin` for auth is already an antipattern, and EIP-7702 makes it actively exploitable."

**Interview Red Flags:**

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

**Pro tip:** EIP-7702 and ERC-4337 are converging — wallets like Ambire and Rhinestone already support both paths. If you can articulate how a protocol should handle both delegated EOAs (7702) and smart accounts (4337) transparently, you show the kind of forward-thinking AA expertise teams are actively hiring for.

---

<a id="other-pectra-eips"></a>
### 💡 Concept: Other Pectra EIPs

<a id="eip-7623"></a>
**EIP-7623 — Increased calldata cost** ([EIP-7623](https://eips.ethereum.org/EIPS/eip-7623)):

Transactions that predominantly post data (rather than executing computation) pay higher calldata fees. This affects:
- L2 data posting (though most L2s now use blobs from EIP-4844)
- Any protocol that uses heavy calldata (e.g., posting Merkle proofs, batch data)

<a id="eip-2537"></a>
**EIP-2537 — BLS12-381 precompile** ([EIP-2537](https://eips.ethereum.org/EIPS/eip-2537)):

Native BLS signature verification becomes available as a precompile. EIP-2537 defines **9 separate precompile operations** at addresses `0x0b` through `0x13`:

| Address | Operation | Gas Cost |
|---------|-----------|----------|
| `0x0b` | G1ADD | ~500 |
| `0x0c` | G1MUL | ~12,000 |
| `0x0d` | G1MSM (multi-scalar multiplication) | Variable |
| `0x0e` | G2ADD | ~800 |
| `0x0f` | G2MUL | ~45,000 |
| `0x10` | G2MSM | Variable |
| `0x11` | PAIRING | ~43,000 + per-pair |
| `0x12` | MAP_FP_TO_G1 | ~5,500 |
| `0x13` | MAP_FP2_TO_G2 | ~75,000 |

Useful for:
- Threshold signatures
- Validator-adjacent logic (e.g., liquid staking protocols)
- Any system that needs efficient pairing-based cryptography (privacy protocols, zkSNARKs)

#### 🎓 Concrete Example: Liquid Staking Validator Verification

**The problem:**

Lido/Rocket Pool needs to verify that validators are correctly attesting to Beacon Chain blocks. Validators sign attestations using BLS12-381 signatures. Before EIP-2537, verifying these on-chain was prohibitively expensive (~1M+ gas).

**With BLS12-381 precompile:**

```solidity
contract ValidatorRegistry {
    // BLS12-381 precompile addresses (EIP-2537, activated in Pectra)
    // Note: Signature verification requires the PAIRING precompile.
    // This is a conceptual simplification — real BLS verification
    // involves multiple precompile calls (G1MUL + PAIRING).
    address constant BLS_PAIRING = address(0x11);

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
        (bool success, bytes memory output) = BLS_PAIRING.staticcall(input);

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

**Interview Red Flags:**

- 🚩 "BLS12-381 is for zkSNARKs" — No! It's primarily for signature aggregation
- 🚩 "All pairing-based crypto is the same" — Different curves have different security/performance tradeoffs
- 🚩 "The precompile makes all cryptography cheap" — Only BLS12-381 operations. ECDSA (standard Ethereum signatures) uses secp256k1

**What production DeFi engineers know:**

1. **Liquid staking oracles**: Lido, Rocket Pool, and others can now do on-chain validator consensus
2. **Threshold signatures**: N-of-M multisigs without multiple on-chain transactions
3. **Signature aggregation**: Combine signatures from multiple validators/oracles into one verification
4. **The 99% rule**: BLS operations went from ~1M gas (unusable) to ~8K gas (practical)
5. **Cross-chain messaging**: Bridges can aggregate validator signatures for cheaper verification

**Pro tip:** Liquid staking is the largest DeFi sector by TVL. If you're targeting Lido, Rocket Pool, or EigenLayer roles, being able to explain how BLS signature verification enables decentralized oracle consensus shows you understand the trust assumptions that underpin the entire staking ecosystem.

---

<a id="day4-exercise"></a>
## 🎯 Build Exercise: EIP7702Delegate

**Workspace:** [`workspace/src/part1/module2/exercise2-eip7702-delegate/`](../workspace/src/part1/module2/exercise2-eip7702-delegate/) — starter file: [`EIP7702Delegate.sol`](../workspace/src/part1/module2/exercise2-eip7702-delegate/EIP7702Delegate.sol), tests: [`EIP7702Delegate.t.sol`](../workspace/test/part1/module2/exercise2-eip7702-delegate/EIP7702Delegate.t.sol)

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

## ⚠️ Common Mistakes: Pectra Recap

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

## 📋 Summary: Pectra Upgrade

**✓ Covered:**
- EIP-7702 — EOA code delegation, delegation designator format, DELEGATECALL semantics
- Type 4 transactions — authorization lists and how the EVM processes them
- Security implications — `tx.origin` antipattern, delegation revocation, batch executor security
- Other Pectra EIPs — increased calldata costs, BLS12-381 precompile with liquid staking example

**Key takeaway:** EIP-7702 brings account abstraction to existing EOAs without migration. Combined with ERC-4337 (Module 4), this creates a comprehensive AA ecosystem. The `tx.origin` antipattern becomes actively exploitable with EIP-7702—always use `msg.sender` for authentication.

---

## Looking Ahead

<a id="eof"></a>
### 💡 Concept: EOF — EVM Object Format

**Why this matters (awareness level):** EOF is the next major structural change to the EVM, targeted for the Osaka/Fusaka upgrade. While not yet live, DeFi developers at top teams should know what it is and why it matters.

**What EOF changes:**

EOF introduces a new **container format** for EVM bytecode that separates code from data, replaces dynamic jumps with static control flow, and adds new sections for metadata.

```
Current bytecode: Raw bytes, code and data mixed
┌──────────────────────────────────────────┐
│ opcodes + data + constructor args (flat) │
└──────────────────────────────────────────┘

EOF container: Structured sections
┌──────────┬──────────┬──────────┬────────┐
│  Header  │  Types   │   Code   │  Data  │
│ (magic + │ (function│ (validated│(static │
│ version) │  sigs)   │  opcodes)│  data) │
└──────────┴──────────┴──────────┴────────┘
```

**Key changes:**
- **Static jumps only** — `JUMP` and `JUMPI` replaced by `RJUMP`, `RJUMPI`, `RJUMPV` (relative jumps). No more `JUMPDEST` scanning.
- **Code/data separation** — Bytecode analysis becomes simpler and safer. No more ambiguity about whether bytes are code or data.
- **Stack validation** — The EVM validates stack heights at deploy time, catching errors that currently only surface at runtime.
- **New calling convention** — `CALLF`/`RETF` for internal function calls, reducing stack manipulation overhead.

**Why DeFi developers should care:**
- **Compiler changes**: Solidity will eventually target EOF containers, potentially changing gas profiles
- **Bytecode analysis**: Tools that analyze deployed bytecode (decompilers, security scanners) will need updates
- **Backwards compatible**: Legacy (non-EOF) contracts continue to work. EOF is opt-in via the new container format

**What you DON'T need to do right now:** Nothing. EOF is not yet live. When it ships, the Solidity compiler will handle the transition. Keep an eye on Solidity release notes for EOF compilation support.

> 🔍 **Deep dive:** [EIP-3540 (EOF v1)](https://eips.ethereum.org/EIPS/eip-3540), [ipsilon/eof](https://github.com/ipsilon/eof) — the EOF specification and reference implementation.

---

## 🔗 Cross-Module Concept Links

**Backward references (← concepts from earlier modules):**

| Module 2 Concept | Builds on | Where |
|---|---|---|
| Transient storage (EIP-1153) | `transient` keyword, `tstore`/`tload` assembly | [§1 — Transient Storage](1-solidity-modern.md#transient-storage) |
| Flash accounting gas savings | `unchecked` blocks, `mulDiv` precision | [§1 — Checked Arithmetic](1-solidity-modern.md#checked-arithmetic) |
| Delegation designator format | Custom types (UDVTs), type safety | [§1 — User-Defined Value Types](1-solidity-modern.md#user-defined-value-types) |

**Forward references (→ concepts you'll use later):**

| Module 2 Concept | Used in | Where |
|---|---|---|
| Transient storage | Temporary approvals, flash loans | [§3 — Token Approvals](3-token-approvals.md) |
| EIP-7702 delegation | Account abstraction architecture, paymasters | [§4 — Account Abstraction](4-account-abstraction.md) |
| SELFDESTRUCT neutered | Why proxy patterns are the only upgrade path | [§6 — Proxy Patterns](6-proxy-patterns.md) |
| Gas profiling (PUSH0/MCOPY) | Forge snapshot, gas optimization workflows | [§5 — Foundry](5-foundry.md) |
| CREATE2 deterministic deployment | Deployment scripts, cross-chain deployments | [§7 — Deployment](7-deployment.md) |
| Cold/warm access (EIP-2929) | Gas optimization in vault operations, DEX routing | [Part 2 — AMMs](../part2/2-amms.md) |
| Contract size limits (EIP-170) | Diamond pattern, proxy splitting | [§6 — Proxy Patterns](6-proxy-patterns.md) |

**Part 2 connections:**

| Module 2 Concept | Part 2 Module | How it connects |
|---|---|---|
| Transient storage + flash accounting | [M2 — AMMs](../part2/2-amms.md) | Uniswap V4's entire architecture is built on transient storage deltas |
| EIP-4844 blob economics | [M2](../part2/2-amms.md)–[M9](../part2/9-integration-capstone.md) | All L2 DeFi is 90-97% cheaper post-Dencun — affects protocol design assumptions |
| Transient storage | [M5 — Flash Loans](../part2/5-flash-loans.md) | Flash loan settlement patterns use the same lock → operate → settle flow |
| BLS12-381 precompile | [M7 — Vaults & Yield](../part2/7-vaults-yield.md) | On-chain validator consensus for liquid staking protocols (Lido, Rocket Pool) |
| EIP-7702 + tx.origin | [M8 — DeFi Security](../part2/8-defi-security.md) | New attack surfaces from delegated EOAs, `tx.origin` exploits |
| SELFDESTRUCT changes | [M8 — DeFi Security](../part2/8-defi-security.md) | Metamorphic contract attacks are dead — historical context for audit work |

---

## 📖 Production Study Order

Read these files in order to build progressive understanding of Module 2's concepts in production code:

| # | File | Why | Lines |
|---|------|-----|-------|
| 1 | [OZ ReentrancyGuardTransient.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol) | Simplest transient storage usage — compare to classic ReentrancyGuard | ~30 |
| 2 | [V4 Transient state declarations](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) | See `NonzeroDeltaCount transient` and `mapping(...) transient` — how V4 declares transient state | Top ~50 |
| 3 | [V4 `swap()` → `_accountPoolBalanceDelta()`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) | Follow how swaps update transient deltas without moving tokens | ~100 |
| 4 | [V4 `settle()` and `take()`](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol) | Where actual token transfers happen — the settlement phase | ~60 |
| 5 | [Lido AccountingOracle.sol](https://github.com/lidofinance/lido-dao/blob/master/contracts/0.8.9/oracle/AccountingOracle.sol) | Validator reporting — context for BLS precompile use cases | ~200 |
| 6 | [Rhinestone ModuleKit](https://github.com/rhinestonewtf/modulekit) | EIP-7702 compatible account modules — delegation target patterns | ~150 |
| 7 | [Alchemy LightAccount.sol](https://github.com/alchemyplatform/light-account/blob/main/src/LightAccount.sol) | Production ERC-4337 account that works with EIP-7702 delegation | ~200 |

**Reading strategy:** Files 1–4 cover transient storage from simple → complex. File 5 gives BLS context. Files 6–7 show real EIP-7702 delegation targets — study how they validate `msg.sender` and handle batch execution.

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

### Other EIPs
- [EIP-3855 (PUSH0)](https://eips.ethereum.org/EIPS/eip-3855) — single-byte zero push (Shanghai)
- [EIP-5656 (MCOPY)](https://eips.ethereum.org/EIPS/eip-5656) — memory copy opcode (Cancun)
- [EIP-7623 (Calldata cost)](https://eips.ethereum.org/EIPS/eip-7623) — increased calldata pricing (Pectra)
- [EIP-2537 (BLS precompile)](https://eips.ethereum.org/EIPS/eip-2537) — BLS12-381 pairing operations (Pectra)
- [EIP-2929 (Cold/Warm access)](https://eips.ethereum.org/EIPS/eip-2929) — access list gas pricing (Berlin)
- [EIP-1559 (Base fee)](https://eips.ethereum.org/EIPS/eip-1559) — fee market reform (London)
- [EIP-3529 (Gas refund reduction)](https://eips.ethereum.org/EIPS/eip-3529) — reduced SSTORE/SELFDESTRUCT refunds (London)

### Foundational EVM EIPs
- [EIP-170 (Contract size limit)](https://eips.ethereum.org/EIPS/eip-170) — 24 KiB bytecode limit
- [EIP-1014 (CREATE2)](https://eips.ethereum.org/EIPS/eip-1014) — deterministic contract deployment
- [EIP-2930 (Access lists)](https://eips.ethereum.org/EIPS/eip-2930) — optional access list transaction type

### Future EVM
- [EIP-3540 (EOF v1)](https://eips.ethereum.org/EIPS/eip-3540) — EVM Object Format specification
- [ipsilon/eof](https://github.com/ipsilon/eof) — EOF reference implementation

### Tooling & Pectra Support
- [Foundry EIP-7702 support](https://book.getfoundry.sh/) — evolving Type 4 transaction support
- [ethers.js v6 Type 4 transactions](https://docs.ethers.org/v6/) — account abstraction integration

---

**Navigation:** [← Module 1: Solidity Modern](1-solidity-modern.md) | [Module 3: Token Approvals →](3-token-approvals.md)

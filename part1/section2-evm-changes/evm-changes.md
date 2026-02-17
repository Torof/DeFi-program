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

> Introduced in [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153), activated with the [Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) (March 2024)

**The model:**

Transient storage is a key-value store (32-byte keys → 32-byte values) that:
- Is scoped per contract, per transaction (same scope as regular storage, but transaction lifetime)
- Gets wiped clean when the transaction ends—values are never written to disk
- Persists across external calls within the same transaction (unlike memory, which is per-call-frame)
- Costs ~100 gas for both `TSTORE` and `TLOAD` (vs ~100 for warm `SLOAD`, but ~2,100-20,000 for `SSTORE`)
- Reverts correctly—if a call reverts, transient storage changes in that call frame are also reverted

**📊 The critical distinction:** Transient storage sits between memory (per-call-frame, byte-addressed) and storage (permanent, slot-addressed). It's slot-addressed like storage but temporary like memory. The key difference from memory is that it **survives across `CALL`, `DELEGATECALL`, and `STATICCALL` boundaries** within the same transaction.

**DeFi use cases beyond reentrancy locks:**

1. **Flash accounting ([Uniswap V4](https://github.com/Uniswap/v4-core))**: Track balance deltas across multiple operations in a single transaction, settling the net difference at the end. The PoolManager uses transient storage to accumulate what each caller owes or is owed, then enforces that everything balances to zero before the transaction completes.

2. **Temporary approvals**: ERC-20 approvals that last only for the current transaction—approve, use, and automatically revoke, all without touching persistent storage.

3. **Callback validation**: A contract can set a transient flag before making an external call that expects a callback, then verify in the callback that it was legitimately triggered by the calling contract.

> ⚠️ **Common pitfall—new reentrancy vectors:** Because `TSTORE` costs only ~100 gas, it can execute within the 2,300 gas stipend that `transfer()` and `send()` forward. A contract receiving ETH via `transfer()` can now execute `TSTORE` (something impossible with `SSTORE`). This creates new reentrancy attack surfaces in contracts that assumed 2,300 gas was "safe." This is one reason `transfer()` and `send()` are deprecated in Solidity 0.8.31+.

> 🔍 **Deep dive:** [ChainSecurity - TSTORE Low Gas Reentrancy](https://www.chainsecurity.com/blog/tstore-low-gas-reentrancy) demonstrates the attack with code examples. Their [GitHub repo](https://github.com/ChainSecurity/TSTORE-Low-Gas-Reentrancy) provides exploit POCs.

🏗️ **Real usage:**

Read [Uniswap V4's PoolManager.sol](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol)—search for how `lock()` and `settle()` work. The entire protocol is built on transient storage tracking deltas. You'll see this pattern in Part 3.

> 🔍 **Deep dive:** [Dedaub - Transient Storage Impact Study](https://dedaub.com/blog/transient-storage-in-the-wild-an-impact-study-on-eip-1153/) analyzes real-world usage patterns. [Hacken - Uniswap V4 Transient Storage Security](https://hacken.io/discover/uniswap-v4-transient-storage-security/) covers security considerations in production flash accounting.

---

<a id="proto-danksharding"></a>
### 💡 Concept: Proto-Danksharding (EIP-4844)

**Why this matters:** If you're building on L2 (Arbitrum, Optimism, Base, Polygon zkEVM), your users' transaction costs dropped 90-95% after Dencun. Understanding blob transactions explains why.

> Introduced in [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844), activated with the [Dencun upgrade](https://ethereum.org/en/roadmap/dencun/) (March 2024)

**What changed:**

EIP-4844 introduced "blob transactions"—a new transaction type (Type 3) that carries large data blobs (~128 KB each) at significantly lower cost than calldata. The blobs are available temporarily (roughly 18 days) and then pruned from the consensus layer.

**📊 The impact on L2 DeFi:**

Before Dencun, L2s posted transaction data to L1 as expensive calldata (~16 gas/byte). After Dencun, they post to cheap blob space (~1 gas/byte or less, depending on demand). For example:

| L2 Network | Before Dencun | After Dencun | Savings |
|------------|---------------|--------------|---------|
| Arbitrum | ~$1-2 per tx | ~$0.01-0.10 | **90-95%** ✨ |
| Optimism/Base | ~$1-2 per tx | ~$0.01-0.10 | **90-95%** ✨ |
| zkSync/Polygon zkEVM | Similar | Similar | **90-95%** ✨ |

**From a protocol developer's perspective:**

- L2 DeFi became dramatically cheaper, accelerating adoption
- `block.blobbasefee` and `blobhash()` are now available in Solidity (though you'll rarely use them directly in application contracts)
- Understanding the blob fee market matters if you're building infrastructure-level tooling (sequencers, data availability layers)

> 🔍 **Deep dive:** The blob fee market uses a separate fee mechanism from regular gas. Read [EIP-4844 blob fee market dynamics](https://ethereum.org/en/roadmap/dencun/#eip-4844) to understand how blob pricing adjusts based on demand.

---

<a id="push0-mcopy"></a>
### 💡 Concept: PUSH0 (EIP-3855) and MCOPY (EIP-5656)

**Behind-the-scenes optimizations** that make your compiled contracts smaller and cheaper:

**PUSH0 ([EIP-3855](https://eips.ethereum.org/EIPS/eip-3855))**: A new opcode that pushes the value 0 onto the stack. Previously, pushing zero required `PUSH1 0x00` (2 bytes). `PUSH0` is a single byte. This saves gas and reduces bytecode size. The Solidity compiler uses it automatically when targeting Shanghai or later.

**MCOPY ([EIP-5656](https://eips.ethereum.org/EIPS/eip-5656))**: Efficient memory-to-memory copy. Previously, copying memory required loading and storing word by word, or using identity precompile tricks. `MCOPY` does it in a single opcode. The compiler can use this for struct copying, array slicing, and similar operations.

**What you need to know:** You won't write code that explicitly uses these opcodes, but they make your compiled contracts smaller and cheaper. Make sure your compiler's EVM target is set to `cancun` or later in your Foundry config.

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

> ⚡ **Common pitfall:** If you're reading older DeFi code (pre-2024) and see `SELFDESTRUCT` used for upgrade patterns, be aware that pattern is now obsolete. Modern upgradeable contracts use UUPS or Transparent Proxy patterns (covered in Section 6).

> 🔍 **Deep dive:** [Dedaub - Removal of SELFDESTRUCT](https://dedaub.com/blog/eip-4758-eip-6780-removal-of-selfdestruct/) explains security benefits. [Vibranium Audits - EIP-6780 Objectives](https://www.vibraniumaudits.com/post/taking-self-destructing-contracts-to-the-next-level-the-objectives-of-eip-6780) covers how metamorphic contracts were exploited in governance attacks.

---

<a id="day3-exercise"></a>
## 🎯 Day 3 Build Exercise

**Workspace:** [`workspace/src/part1/section2/`](../../workspace/src/part1/section2/) — starter file: [`FlashAccounting.sol`](../../workspace/src/part1/section2/FlashAccounting.sol), tests: [`FlashAccounting.t.sol`](../../workspace/test/part1/section2/FlashAccounting.t.sol)

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

## 📋 Day 3 Summary

**✓ Covered:**
- Transient storage mechanics (EIP-1153) — how it differs from memory and storage
- Flash accounting pattern — Uniswap V4's core innovation
- Proto-Danksharding (EIP-4844) — why L2s became 90-95% cheaper
- PUSH0 & MCOPY — behind-the-scenes compiler optimizations
- SELFDESTRUCT changes (EIP-6780) — metamorphic contracts are dead

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

> 🔍 **Deep dive:** EIP-7702 is closely related to ERC-4337 (Section 4). The difference: ERC-4337 requires deploying a new smart account, while EIP-7702 upgrades existing EOAs. Read [Vitalik's post on EIP-7702](https://notes.ethereum.org/@vbuterin/account_abstraction_roadmap) for the full account abstraction roadmap.

**Security considerations:**

- **`msg.sender` vs `tx.origin`**: When an EIP-7702-delegated EOA calls your contract, `msg.sender` is the EOA address (as expected). But `tx.origin` is also the EOA. Be careful with `tx.origin` checks—they can't distinguish between direct EOA calls and delegated calls.
- **Delegation revocation**: A user can always sign a new authorization pointing to a different contract (or to zero address to revoke delegation). Your DeFi protocol shouldn't assume delegation is permanent.

> ⚡ **Common pitfall:** Some contracts use `tx.origin` checks for authentication (e.g., "only allow if `tx.origin == owner`"). These patterns break with EIP-7702 because delegated calls have the same `tx.origin` as direct calls. Avoid `tx.origin`-based authentication.

> 🔍 **Deep dive:** [QuickNode - EIP-7702 Implementation Guide](https://www.quicknode.com/guides/ethereum-development/smart-contracts/eip-7702-smart-accounts) provides hands-on Foundry examples. [Biconomy - Comprehensive EIP-7702 Guide](https://blog.biconomy.io/a-comprehensive-eip-7702-guide-for-apps/) covers app integration. [Gelato - Account Abstraction from ERC-4337 to EIP-7702](https://gelato.cloud/blog/gelato-s-guide-to-account-abstraction-from-erc-4337-to-eip-7702) explains how EIP-7702 compares to ERC-4337.

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

**Concrete example:** Lido or Rocket Pool could use BLS signatures to verify validator consensus messages on-chain without prohibitive gas costs.

---

<a id="day4-exercise"></a>
## 🎯 Day 4 Build Exercise

**Workspace:** [`workspace/src/part1/section2/`](../../workspace/src/part1/section2/) — starter file: [`EIP7702Delegate.sol`](../../workspace/src/part1/section2/EIP7702Delegate.sol), tests: [`EIP7702Delegate.t.sol`](../../workspace/test/part1/section2/EIP7702Delegate.t.sol)

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

## 📋 Day 4 Summary

**✓ Covered:**
- EIP-7702 — EOA code delegation for account abstraction
- Type 4 transactions — authorization lists and delegation designators
- Security implications — `tx.origin` checks and delegation revocation
- Other Pectra EIPs — increased calldata costs, BLS precompile

**Key takeaway:** EIP-7702 brings account abstraction to existing EOAs without migration. Combined with ERC-4337 (Section 4), this creates a comprehensive AA ecosystem.

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

**Navigation:** [← Previous: Section 1 - Solidity Modern](../section1-solidity-modern/solidity-modern.md) | [Next: Section 3 - Token Approvals →](../section3-token-approvals/token-approvals.md)

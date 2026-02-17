# Section 3: Modern Token Approval Patterns (~3 days)

## 📚 Table of Contents

**Day 5: The Approval Problem**
- [Why Traditional Approvals Are Broken](#traditional-approvals-broken)
- [EIP-2612 — Permit](#eip-2612-permit)
- [OpenZeppelin ERC20Permit](#openzeppelin-erc20permit)
- [Day 5 Build Exercise](#day5-exercise)

**Day 6: Permit2**
- [How Permit2 Works](#how-permit2-works)
- [SignatureTransfer vs AllowanceTransfer](#signature-vs-allowance-transfer)
- [Permit2 Design Details](#permit2-design-details)
- [Reading Permit2 Source Code](#permit2-source-code)
- [Day 6-7 Build Exercise](#day6-exercise)

**Day 7: Security**
- [Permit Attack Vectors](#permit-attack-vectors)
- [Safe Permit Patterns](#safe-permit-patterns)
- [Day 7 Build Exercise](#day7-exercise)

---

## Day 5: The Approval Problem and EIP-2612

<a id="traditional-approvals-broken"></a>
### 💡 Concept: Why Traditional Approvals Are Broken

**Why this matters:** Every DeFi user has experienced the friction: "Approve USDC" → wait → "Swap USDC" → wait. This two-step dance isn't just annoying—it costs billions in wasted gas annually and creates a massive attack surface. Users who approved a protocol in 2021 still have active unlimited approvals today, forgotten but exploitable.

**The problems with ERC-20 `approve → transferFrom`:**

| Problem | Impact | Example |
|---------|--------|---------|
| **Two transactions** per interaction | 2x gas costs, poor UX | Approve tx + Action tx = ~42k extra gas |
| **Infinite approvals** as default | All tokens at risk if protocol hacked | 💰 **Euler Finance** (March 2023): $197M drained |
| **No expiration** | Forgotten approvals persist forever | Approvals from 2020 still active today |
| **No batch revocation** | 1 tx per token per spender to revoke | Users have 50+ active approvals on average |

**🚨 Real-world impact:**

When protocols get hacked (Euler Finance March 2023, KyberSwap November 2023), attackers drain not just deposited funds but all tokens users have approved. The approval system turns every protocol into a potential honeypot.

> ⚡ **Check your own approvals:** Visit [Revoke.cash](https://revoke.cash/) and see how many active unlimited approvals you have. Most users are shocked.

---

<a id="eip-2612-permit"></a>
### 💡 Concept: EIP-2612 — Permit

**Why this matters:** Single-transaction UX is table stakes in 2024. Protocols that still require two transactions lose users to competitors. EIP-2612 unlocks the "approve + action in one click" experience users expect.

> Introduced in [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612), formalized [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed data signing

**What it does:**

EIP-2612 introduced `permit()`—a function that allows approvals via EIP-712 signed messages instead of on-chain transactions:

```solidity
function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v, bytes32 r, bytes32 s
) external;
```

The user signs a message off-chain (free, no gas), and anyone can submit the signature on-chain to set the approval. This enables single-transaction flows: the dApp collects the permit signature, then calls a function that first executes the permit and then performs the operation—all in one transaction.

**How it works under the hood:**

1. Token contract stores a `nonces` mapping and exposes a `DOMAIN_SEPARATOR` (EIP-712)
2. User signs an EIP-712 typed data message containing: owner, spender, value, nonce, deadline
3. Anyone can call `permit()` with the signature
4. Contract verifies the signature via `ecrecover`, checks the nonce and deadline, and sets the allowance
5. Nonce increments to prevent replay ✨

**📊 The critical limitation:**

The token contract itself must implement EIP-2612. Tokens deployed before the standard (USDT, WETH on Ethereum mainnet, most early ERC-20s) don't support it. This is the gap that Permit2 fills.

| Token | Ethereum Mainnet | Polygon | Arbitrum | Optimism |
|-------|------------------|---------|----------|----------|
| USDC | ❌ No permit | ✅ Has permit | ✅ Has permit | ✅ Has permit |
| USDT | ❌ No permit | ❌ No permit | ❌ No permit | ❌ No permit |
| WETH | ❌ No permit | ✅ Has permit | ✅ Has permit | ✅ Has permit |
| DAI | ✅ Has permit* | ✅ Has permit | ✅ Has permit | ✅ Has permit |

*DAI's permit predates EIP-2612 but inspired it

> ⚡ **Common pitfall:** Not all "USDC" is the same. USDC on Ethereum mainnet predates EIP-2612 and doesn't support `permit()`. But USDC on Polygon, Arbitrum, and Optimism does. Always check `supportsInterface` or try calling `DOMAIN_SEPARATOR()` before assuming permit support.

🏗️ **Real usage:**

Most modern tokens implement EIP-2612:
- DAI was the first (DAI's `permit` predates EIP-2612 but inspired it)
- [Uniswap V2 LP tokens](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2ERC20.sol)
- All [OpenZeppelin ERC20Permit](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) tokens

---

<a id="openzeppelin-erc20permit"></a>
### 📖 Read: OpenZeppelin's ERC20Permit Implementation

**Source:** [`@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol)

Study how it extends ERC20 with:
- `EIP712` base contract for domain separator computation
- `Nonces` contract for replay protection
- The `permit()` function that calls `_approve` after signature verification

Pay attention to the EIP-712 domain separator construction—you'll need to understand this for Permit2.

> 🔍 **Deep dive:** Read [EIP-712](https://eips.ethereum.org/EIPS/eip-712) to understand how typed data signing prevents phishing (compared to raw `personal_sign`). The domain separator binds signatures to specific contracts on specific chains. [QuickNode - EIP-2612 Permit Guide](https://www.quicknode.com/guides/ethereum-development/transactions/how-to-use-erc20-permit-approval) provides a hands-on tutorial. [Cyfrin Updraft - EIP-712](https://updraft.cyfrin.io/courses/security/bridges/eip-712) covers typed structured data hashing with security examples.

---

<a id="day5-exercise"></a>
## 🎯 Day 5 Build Exercise

**Workspace:** [`workspace/src/part1/section3/`](../../workspace/src/part1/section3/) — starter file: [`PermitVault.sol`](../../workspace/src/part1/section3/PermitVault.sol), tests: [`PermitVault.t.sol`](../../workspace/test/part1/section3/PermitVault.t.sol)

1. Create an ERC-20 token with EIP-2612 permit support (extend OpenZeppelin's `ERC20Permit`)
2. Write a `Vault` contract that accepts deposits via permit—a single function that calls `permit()` then `transferFrom()` in one transaction
3. Write Foundry tests using `vm.sign()` to generate valid permit signatures:

```solidity
function testDepositWithPermit() public {
    // vm.createWallet or use vm.addr + vm.sign
    (address user, uint256 privateKey) = makeAddrAndKey("user");

    // Build the permit digest
    bytes32 digest = keccak256(abi.encodePacked(
        "\x19\x01",
        token.DOMAIN_SEPARATOR(),
        keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            user,
            address(vault),
            amount,
            token.nonces(user),
            deadline
        ))
    ));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    vault.depositWithPermit(amount, deadline, v, r, s);
}
```

4. **Test edge cases:**
   - Expired deadline (should revert)
   - Wrong nonce (should revert)
   - Signature replay (second call with same signature should revert)

**🎯 Goal:** Understand the full signature flow from construction to verification. This is the foundation for Permit2.

---

## 📋 Day 5 Summary

**✓ Covered:**
- Traditional approval problems — 2 transactions, infinite approvals, no expiration
- EIP-2612 permit — off-chain signatures for approvals
- EIP-712 typed data — domain separators prevent replay attacks
- Token compatibility — not all tokens support permit

**Next:** Day 6 — Permit2, the universal approval infrastructure used by Uniswap V4, UniswapX, and modern DeFi

---

## Day 6: Permit2 — Universal Approval Infrastructure

<a id="how-permit2-works"></a>
### 💡 Concept: How Permit2 Works

**Why this matters:** Permit2 is now the standard for token approvals in modern DeFi. Uniswap V4, UniswapX, Cowswap, 1inch, and most protocols launched after 2023 use it. Understanding Permit2 is non-negotiable for reading production code.

> Deployed by [Uniswap Labs](https://github.com/Uniswap/permit2), canonical deployment at [`0x000000000022D473030F116dDEE9F6B43aC78BA3`](https://etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3) (same address on all EVM chains)

**The key insight:**

Instead of requiring every token to implement `permit()`, Permit2 sits as a middleman. Users approve Permit2 **once per token** (standard ERC-20 approve), and then Permit2 manages all subsequent approvals via signatures.

```
Traditional:  User → approve(Protocol A) → approve(Protocol B) → approve(Protocol C)
Permit2:      User → approve(Permit2) [once per token, forever]
              Then:   sign(permit for Protocol A) → sign(permit for Protocol B) → ...
```

**Why this is genius:**

1. ✅ Works with **any ERC-20** (no permit support required)
2. ✅ **One on-chain approval** per token, ever
3. ✅ All subsequent protocol interactions use **free off-chain signatures**
4. ✅ Built-in **expiration and revocation**

---

<a id="signature-vs-allowance-transfer"></a>
### 💡 Concept: SignatureTransfer vs AllowanceTransfer

Permit2 has two modes of operation, implemented as two logical components within a single contract:

**📊 SignatureTransfer — One-time, stateless permits**

The user signs a message authorizing a specific transfer. The signature is consumed in the transaction and can never be replayed (nonce-based). No approval state is stored.

**Best for:** Infrequent interactions, maximum security (e.g., one-time swap, NFT purchase)

```solidity
interface ISignatureTransfer {
    struct PermitTransferFrom {
        TokenPermissions permitted;  // token address + max amount
        uint256 nonce;               // unique per-signature, bitmap-based
        uint256 deadline;            // expiration timestamp
    }

    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct SignatureTransferDetails {
        address to;                  // recipient
        uint256 requestedAmount;     // actual amount (≤ permitted amount)
    }

    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}
```

**📊 AllowanceTransfer — Persistent, time-bounded allowances**

More like traditional approvals but with expiration and better batch management. The user signs a permit to set an allowance, then the spender can transfer within that allowance until it expires.

**Best for:** Frequent interactions (e.g., a DEX router you use regularly)

```solidity
interface IAllowanceTransfer {
    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    struct PermitDetails {
        address token;
        uint160 amount;     // Note: uint160, not uint256
        uint48 expiration;  // When the allowance expires
        uint48 nonce;       // Sequential nonce
    }

    function permit(
        address owner,
        PermitSingle memory permitSingle,
        bytes calldata signature
    ) external;

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external;
}
```

---

<a id="permit2-design-details"></a>
### 💡 Concept: Permit2 Design Details

**Key design decisions to understand:**

**1. Bitmap nonces (SignatureTransfer):**

Instead of sequential nonces, SignatureTransfer uses a bitmap—each nonce is a single bit in a 256-bit word. This means nonces can be consumed in **any order**, enabling parallel signature collection. The nonce space is `(wordIndex, bitIndex)`—effectively unlimited unique nonces.

Why this matters: UniswapX collects multiple signatures from users for different orders in parallel. Bitmap nonces mean order1 can settle before order2 even if it was signed later. ✨

> 🔍 **Deep dive:** [Uniswap - SignatureTransfer Reference](https://docs.uniswap.org/contracts/permit2/reference/signature-transfer) explains how the bitmap stores 256 bits per word, with the first 248 bits of the nonce selecting the word and the last 8 bits selecting the bit position.

**2. uint160 amounts (AllowanceTransfer):**

Allowances are stored as `uint160`, not `uint256`. This allows packing the amount, expiration (`uint48`), and nonce (`uint48`) into a single storage slot for gas efficiency.

```solidity
// ✅ Packed storage: 160 + 48 + 48 = 256 bits (one slot)
struct PackedAllowance {
    uint160 amount;
    uint48 expiration;
    uint48 nonce;
}
```

**3. Witness data (permitWitnessTransferFrom):**

SignatureTransfer supports an extended mode where the user signs not just the transfer details but also arbitrary "witness" data—extra context that the receiving contract cares about.

**Example:** [UniswapX](https://github.com/Uniswap/UniswapX) uses this to include the swap order details in the permit signature, ensuring the user approved both the token transfer and the specific swap parameters atomically.

```solidity
// User signs: transfer 1000 USDC + witness: slippage=1%, path=USDC→WETH
function permitWitnessTransferFrom(
    PermitTransferFrom memory permit,
    SignatureTransferDetails calldata transferDetails,
    address owner,
    bytes32 witness,       // Hash of extra data
    string calldata witnessTypeString,  // EIP-712 type definition
    bytes calldata signature
) external;
```

> 🔍 **Deep dive:** The witness pattern is central to intent-based systems. Read [UniswapX's ResolvedOrder](https://github.com/Uniswap/UniswapX/blob/main/src/base/ResolvedOrder.sol) to see how witness data encodes an entire swap order in the permit signature. [Cyfrin - Full Guide to Implementing Permit2](https://www.cyfrin.io/blog/how-to-implement-permit2) provides step-by-step integration patterns.

---

<a id="permit2-source-code"></a>
### 📖 Read: Permit2 Source Code

**Source:** [github.com/Uniswap/permit2](https://github.com/Uniswap/permit2)

Read these contracts in order:

1. [`src/interfaces/ISignatureTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol) — the interface tells you the mental model
2. [`src/SignatureTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol) — focus on `permitTransferFrom` and the nonce bitmap logic in `_useUnorderedNonce`
3. [`src/interfaces/IAllowanceTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/interfaces/IAllowanceTransfer.sol) — compare the interface to SignatureTransfer
4. [`src/AllowanceTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/AllowanceTransfer.sol) — focus on `permit`, `transferFrom`, and how allowance state is packed
5. [`src/libraries/SignatureVerification.sol`](https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol) — handles EOA signatures, EIP-2098 compact signatures, and EIP-1271 contract signatures

🏗️ **Read: Permit2 Integration in the Wild**

**Source:** [Uniswap Universal Router](https://github.com/Uniswap/universal-router) uses Permit2 for all token ingress.

Look at how `V3SwapRouter` calls `permit2.permitTransferFrom` to pull tokens from users who have signed permits. Compare this to the old V2/V3 routers that required `approve` first.

> **Real-world data:** After Uniswap deployed Universal Router with Permit2 in November 2022, ~80% of swaps now use permit-based approvals instead of on-chain approves. [Dune Analytics dashboard](https://dune.com/queries/1635283)

---

<a id="day6-exercise"></a>
## 🎯 Day 6-7 Build Exercise

**Workspace:** [`workspace/src/part1/section3/`](../../workspace/src/part1/section3/) — starter file: [`Permit2Vault.sol`](../../workspace/src/part1/section3/Permit2Vault.sol), tests: [`Permit2Vault.t.sol`](../../workspace/test/part1/section3/Permit2Vault.t.sol)

Build a Vault contract that integrates with Permit2 for both transfer modes:

1. **Setup:** Fork mainnet in Foundry to interact with the deployed Permit2 contract at `0x000000000022D473030F116dDEE9F6B43aC78BA3`

2. **SignatureTransfer deposit:** Implement `depositWithSignaturePermit()`—the user signs a one-time permit, the vault calls `permitTransferFrom` on Permit2 to pull tokens

3. **AllowanceTransfer deposit:** Implement `depositWithAllowancePermit()`—the user first signs an allowance permit (setting a time-bounded approval on Permit2), then the vault calls `transferFrom` on Permit2

4. **Witness data:** Extend the SignatureTransfer version to include a `depositId` as witness data—the user signs both the transfer and the specific deposit they're authorizing

5. **Test both paths** with Foundry's `vm.sign()` to generate valid EIP-712 signatures

```solidity
// Hint: Permit2 is already deployed on mainnet
// Fork test setup:
function setUp() public {
    vm.createSelectFork("mainnet");
    permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // ...
}
```

6. **Gas comparison:**
   - Measure gas for: traditional approve → deposit (2 txs)
   - vs: deposit with SignatureTransfer (1 tx, signature off-chain)
   - You should see ~21,000 gas saved (one transaction eliminated)

**🎯 Goal:** Hands-on with the Permit2 contract so you recognize its patterns when you see them in Uniswap V4, UniswapX, and other modern DeFi protocols. The witness data extension is particularly important—it's central to intent-based systems you'll study in Part 3.

---

## 📋 Day 6 Summary

**✓ Covered:**
- Permit2 architecture — SignatureTransfer vs AllowanceTransfer
- Bitmap nonces — parallel signature collection
- Packed storage — uint160 amounts for gas efficiency
- Witness data — binding extra context to permit signatures
- Real usage — 80% of Uniswap swaps use Permit2

**Next:** Day 7 — Security considerations and attack vectors

---

## Day 7: Security Considerations and Edge Cases

<a id="permit-attack-vectors"></a>
### 💡 Concept: Permit/Permit2 Attack Vectors

**Why this matters:** Signature-based approvals introduce new attack surfaces. The bad guys know these patterns—you need to know them better.

**🚨 1. Signature replay:**

If a signature isn't properly scoped (chain ID, contract address, nonce), it can be replayed on other chains or after contract upgrades.

**Protection:**
- ✅ EIP-712 domain separators prevent cross-contract/cross-chain replay
- ✅ Nonces prevent same-contract replay
- ✅ Deadlines limit time window

> ⚡ **Common pitfall:** Forgetting to include `block.chainid` in your domain separator. Your signatures will be valid on all forks (Ethereum mainnet, Goerli, Sepolia with same contract address).

**🚨 2. Permit front-running:**

A signed permit is public once submitted in a transaction. An attacker can extract the signature from the mempool and use it in their own transaction.

**Example attack:**
1. Alice signs permit: approve 1000 USDC to VaultA
2. Alice submits tx: `vaultA.depositWithPermit(...)`
3. Attacker sees tx in mempool, extracts signature
4. Attacker submits (with higher gas): `permit(...)` → now Attacker can call `transferFrom`

**Protection:**
- ✅ Permit2's `permitTransferFrom` requires a specific `to` address—only the designated recipient can receive the tokens
- ⚠️ AllowanceTransfer's `permit()` can still be front-run to set the allowance early, but this just wastes the user's gas (not a fund loss)

**🚨 3. Permit phishing:**

An attacker tricks a user into signing a permit message that approves tokens to the attacker's contract. The signed message looks harmless to the user but authorizes a transfer.

**💰 Real attacks:**
- February 2023: "Approve Blur marketplace" phishing stole $230k
- March 2024: "Permit for airdrop claim" phishing campaign
- **2024 total:** $314M lost to permit phishing attacks

**Protection:**
- ✅ Wallet UIs must clearly display what a user is signing
- ✅ As a protocol: never ask users to sign permits for contracts they don't recognize
- ✅ User education: "If you didn't initiate the action, don't sign"

> ⚡ **Common pitfall:** Your dApp's UI shows "Sign to deposit" but the permit is actually approving tokens to an intermediary contract. Users can't verify the `spender` address. Be transparent about what the signature authorizes.

> 🔍 **Deep dive:** [Gate.io - Permit2 Phishing Analysis](https://www.gate.com/learn/articles/is-your-wallet-safe-how-hackers-exploit-permit-uniswap-permit2-and-signatures-for-phishing/4197) documents real attacks with $314M lost in 2024. [Eocene - Permit2 Risk Analysis](https://eocene.medium.com/permit2-introduction-and-risk-analysis-f9444b896fc5) covers security implications. [SlowMist - Examining Permit Signatures](https://slowmist.medium.com/examining-permit-signatures-is-phishing-of-tokens-possible-via-off-chain-signatures-bfb5723a5e9) analyzes off-chain signature attack vectors.

**🚨 4. Griefing with permit revocation:**

An attacker can call Permit2's `invalidateNonces` on behalf of any user to revoke a specific allowance-transfer nonce. This is a denial-of-service vector—the attacker can't steal funds but can prevent valid permits from being used.

**Protection:**
- ✅ Frontend should detect invalidated nonces and request a new signature
- ✅ For critical operations, verify nonce validity on-chain before execution

---

<a id="safe-permit-patterns"></a>
### 📖 Read: OpenZeppelin's SafeERC20 Permit Handling

**Source:** [`SafeERC20.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol)

Look at `forceApprove` and how they handle tokens with non-standard approval behavior (some tokens revert on approve if allowance is non-zero).

Also examine how they recommend handling permit failures (try/catch, because a front-run permit execution will cause your permit call to revert).

**Pattern:**
```solidity
// ✅ SAFE: Handle permit failures gracefully
try IERC20Permit(token).permit(...) {
    // Permit succeeded
} catch {
    // Permit failed (already used, front-run, or token doesn't support it)
    // Check if allowance is sufficient anyway
    require(IERC20(token).allowance(owner, spender) >= value, "Insufficient allowance");
}
```

---

<a id="day7-exercise"></a>
## 🎯 Day 7 Build Exercise

**Workspace:** [`workspace/src/part1/section3/`](../../workspace/src/part1/section3/) — starter file: [`SafePermit.sol`](../../workspace/src/part1/section3/SafePermit.sol), tests: [`SafePermit.t.sol`](../../workspace/test/part1/section3/SafePermit.t.sol)

1. **Write a test demonstrating permit front-running:**
   - User signs and submits permit
   - Attacker intercepts signature from mempool
   - Attacker uses signature first
   - User's transaction fails or succeeds with reduced impact

2. **Implement a safe permit wrapper** that uses try/catch:
   ```solidity
   function safePermit(IERC20Permit token, ...) internal {
       try token.permit(...) {
           // Success
       } catch {
           // Check allowance is sufficient anyway
           require(token.allowance(owner, spender) >= value, "Permit failed and allowance insufficient");
       }
   }
   ```

3. **Test with a non-EIP-2612 token** (e.g., mainnet USDT):
   - Verify your vault still works with the standard approve flow as a fallback
   - Test graceful degradation: if permit is unavailable, require pre-approval

4. **Phishing simulation:**
   - Create a malicious contract that requests permits
   - Show how a user signing a "deposit" permit could actually be approving a malicious spender
   - Demonstrate what wallet UIs should display to prevent this

**🎯 Goal:** Understand the real security landscape of signature-based approvals so you build defensive patterns from the start.

---

## 📋 Day 7 Summary

**✓ Covered:**
- Signature replay protection — domain separators, nonces, deadlines
- Front-running attacks — how to prevent with Permit2's design
- Phishing attacks — $314M lost in 2024, wallet UI responsibility
- Safe permit patterns — try/catch and graceful degradation

**Key takeaway:** Permit and Permit2 enable amazing UX but require defensive coding. Always use try/catch, validate signatures carefully, and never trust user-submitted permit data without verification.

---

## 📚 Resources

### EIP-2612 — Permit
- [EIP-2612 specification](https://eips.ethereum.org/EIPS/eip-2612) — permit function standard
- [EIP-712 specification](https://eips.ethereum.org/EIPS/eip-712) — typed structured data hashing and signing
- [OpenZeppelin ERC20Permit](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) — production implementation
- [DAI permit implementation](https://github.com/makerdao/dss/blob/master/src/dai.sol) — the original (predates EIP-2612)

### Permit2
- [Permit2 repository](https://github.com/Uniswap/permit2) — source code and docs
- [Permit2 deployment addresses](https://github.com/Uniswap/permit2#deployments) — same address on all chains
- [Uniswap Universal Router](https://github.com/Uniswap/universal-router) — Permit2 integration example
- [Permit2 integration guide](https://docs.uniswap.org/contracts/permit2/overview) — official docs
- [Dune: Permit2 adoption metrics](https://dune.com/queries/1635283) — usage stats

### Security
- [OpenZeppelin SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) — safe permit handling patterns
- [Revoke.cash](https://revoke.cash/) — check your active approvals
- [EIP-1271 specification](https://eips.ethereum.org/EIPS/eip-1271) — signature validation for smart accounts (covered in Section 4)

### Advanced Topics
- [UniswapX ResolvedOrder](https://github.com/Uniswap/UniswapX/blob/main/src/base/ResolvedOrder.sol) — witness data in production
- [EIP-2098 compact signatures](https://eips.ethereum.org/EIPS/eip-2098) — 64-byte vs 65-byte signatures

---

**Navigation:** [← Previous: Section 2 - EVM Changes](../section2-evm-changes/evm-changes.md) | [Next: Section 4 - Account Abstraction →](../section4-account-abstraction/account-abstraction.md)

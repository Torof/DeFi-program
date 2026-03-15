# Part 1 — Module 3: Modern Token Approval Patterns

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~40 minutes | **Exercises:** ~4-5 hours

## 📚 Table of Contents

**The Approval Problem and EIP-2612**
- [Why Traditional Approvals Are Broken](#traditional-approvals-broken)
- [EIP-2612 — Permit](#eip-2612-permit)
- [Build Exercise: PermitVault](#day5-exercise)

**Permit2 — Universal Approval Infrastructure**
- [How Permit2 Works](#how-permit2-works)
- [SignatureTransfer vs AllowanceTransfer](#signature-vs-allowance-transfer)
- [Permit2 Design Details](#permit2-design-details)
- [Build Exercise: Permit2Vault](#day6-exercise)

**Security Considerations and Edge Cases**
- [Permit/Permit2 Attack Vectors](#permit-attack-vectors)
- [Build Exercise: SafePermit](#day7-exercise)

---

## 💡 The Approval Problem and EIP-2612

<a id="traditional-approvals-broken"></a>
### 💡 Concept: Why Traditional Approvals Are Broken

**Why this matters:** Every DeFi user has experienced the friction: "Approve USDC" → wait → "Swap USDC" → wait. This two-step dance isn't just annoying—it costs billions in wasted gas annually and creates a massive attack surface. Users who approved a protocol in 2021 still have active unlimited approvals today, forgotten but exploitable.

**The problems with ERC-20 `approve → transferFrom`:**

| Problem | Impact | Example |
|---------|--------|---------|
| **Two transactions** per interaction | 2x gas costs, poor UX | Approve tx alone costs ~46k gas (21k base + ~25k execution) |
| **Infinite approvals** as default | All tokens at risk if protocol hacked | 💰 **[Euler Finance](https://www.certik.com/resources/blog/euler-finance-hack-explained)** (March 2023): $197M drained |
| **No expiration** | Forgotten approvals persist forever | Approvals from 2020 still active today |
| **No batch revocation** | 1 tx per token per spender to revoke | Users have 50+ active approvals on average |

**🚨 Real-world impact:**

When protocols get hacked ([Euler Finance March 2023](https://www.certik.com/resources/blog/euler-finance-hack-explained), [KyberSwap November 2023](https://blog.kyberswap.com/post-mortem-kyberswap-elastic-exploit/)), attackers drain not just deposited funds but all tokens users have approved. The approval system turns every protocol into a potential honeypot.

> ⚡ **Check your own approvals:** Visit [Revoke.cash](https://revoke.cash/) and see how many active unlimited approvals you have. Most users are shocked.

#### 🔗 DeFi Pattern Connection

**Where the approval problem hits hardest:**

1. **DEX Routers** (Uniswap, 1inch, Paraswap)
   - Users approve the router contract with unlimited amounts
   - Router gets upgraded → old router still has active approvals
   - Attack surface grows with every protocol upgrade

2. **Lending Protocols** (Aave, Compound)
   - Users approve the lending pool to pull collateral
   - Pool gets exploited → all approved tokens at risk, not just deposited ones
   - Euler Finance ($197M hack) exploited exactly this pattern

3. **Yield Aggregators** (Yearn, Beefy)
   - Users approve the vault → vault approves the strategy → strategy approves the underlying protocol
   - Chain of approvals: one weak link compromises everything
   - This is why approval hygiene became a security requirement

**The evolution:**
```
2017-2020: approve(MAX_UINT256) everywhere → "set it and forget it"
2021-2022: approve(exact amount) gaining traction → better but still 2 txs
2023+:     Permit2 → single approval, signature-based, expiring
```

#### 💼 Job Market Context

**Interview question you WILL be asked:**
> "What's wrong with the traditional ERC-20 approval model?"

<details>
<summary>Answer</summary>

"Three fundamental problems: two transactions per interaction wastes gas and creates UX friction; infinite approvals create a persistent attack surface where a protocol hack drains all approved tokens, not just deposited ones; and no built-in expiration means forgotten approvals from years ago remain exploitable. Permit2 solves all three by centralizing approval management with signature-based, time-bounded permits."

</details>

**Follow-up question:**
> "How would you handle approvals in a protocol you're building today?"

<details>
<summary>Answer</summary>

"I'd integrate Permit2 as the primary token ingress path with a fallback to standard approve for edge cases. For protocols that still need direct approvals, I'd enforce exact amounts instead of unlimited, and emit events that frontends can use to help users track and revoke."

</details>

**Interview Red Flags:**
- 🚩 "Just use `approve(type(uint256).max)`" — shows no security awareness
- 🚩 Not knowing about Permit2
- 🚩 Can't explain the Euler Finance attack vector

**Pro tip:** Check [Revoke.cash](https://revoke.cash/) for your own wallet before interviews. Being able to say "I had 47 active unlimited approvals and revoked them all last week" shows you practice what you preach — security-conscious teams love that.

#### 🔍 Deep Dive: The Approve Race Condition

Before EIP-2612, there was already a well-known vulnerability with `approve()`:

```solidity
// Scenario: Alice approved Bob for 100 tokens, now wants to change to 50
// Step 1: Alice calls approve(Bob, 50)
// Step 2: Bob sees the pending tx and front-runs with transferFrom(Alice, Bob, 100)
// Step 3: Alice's approve(50) executes → Bob now has 50 allowance
// Step 4: Bob calls transferFrom(Alice, Bob, 50)
// Result: Bob stole 150 tokens instead of the intended 100→50 change
```

**Production pattern:** Always approve to 0 first, then approve the new amount:
```solidity
token.approve(spender, 0);      // Reset to zero
token.approve(spender, newAmount); // Set new value
```

OpenZeppelin's `forceApprove` handles this automatically. EIP-2612 avoids this entirely because each permit signature is nonce-bound — you can't "change" a permit, you just sign a new one with the next nonce.

---

<a id="eip-2612-permit"></a>
### 💡 Concept: EIP-2612 — Permit

**Why this matters:** Single-transaction UX is table stakes in 2025-2026. Protocols that still require two transactions lose users to competitors. EIP-2612 unlocks the "approve + action in one click" experience users expect.

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
| USDC | ✅ Has permit (V2.2+) | ✅ Has permit | ✅ Has permit | ✅ Has permit |
| USDT | ❌ No permit | ❌ No permit | ❌ No permit | ❌ No permit |
| WETH | ❌ No permit | ✅ Has permit | ✅ Has permit | ✅ Has permit |
| DAI | ✅ Has permit* | ✅ Has permit | ✅ Has permit | ✅ Has permit |

*DAI's permit predates EIP-2612 but inspired it. USDC mainnet gained permit support via the FiatToken V2.2 proxy upgrade (domain: `{name: "USDC", version: "2"}`).

> ⚡ **Common pitfall:** Not all tokens support permit — USDT doesn't on any chain, and WETH on Ethereum mainnet (the original WETH9 contract from 2017) doesn't either. Try calling `DOMAIN_SEPARATOR()` via staticcall before assuming permit support — if it reverts, the token doesn't implement EIP-2612. Note: `supportsInterface` does NOT work for EIP-2612 detection because the standard doesn't define an interface ID. Even tokens that DO support permit may use different domain versions (e.g., USDC uses `version: "2"`).

💻 **Quick Try:**

Check if a token supports EIP-2612 on [Etherscan](https://etherscan.io/). Search for any token (e.g., [UNI](https://etherscan.io/token/0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984#readContract)):
1. Go to "Read Contract"
2. Look for `DOMAIN_SEPARATOR()` — if it exists, the token supports EIP-712 signing
3. Look for `nonces(address)` — if it exists alongside DOMAIN_SEPARATOR, it supports EIP-2612
4. Try calling `DOMAIN_SEPARATOR()` and decode the result — you'll see the chain ID, contract address, name, and version baked in

Now try the same with [USDT](https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#readContract) — no `DOMAIN_SEPARATOR`, no `nonces`. This is why Permit2 exists.

#### 🔍 Deep Dive: EIP-712 Domain Separator Structure

**Why this matters:** The domain separator is the security anchor for all permit signatures. It prevents cross-chain and cross-contract replay attacks. Understanding its structure is essential for debugging signature failures.

**Visual structure:**

```
DOMAIN_SEPARATOR = keccak256(abi.encode(
    ┌──────────────────────────────────────────────────────────┐
    │  keccak256("EIP712Domain(string name,string version,    │
    │            uint256 chainId,address verifyingContract)")  │
    │                                                          │
    │  keccak256(bytes("USD Coin"))     ← token name          │
    │  keccak256(bytes("2"))            ← version string      │
    │  1                                ← chainId (mainnet)   │
    │  0xA0b8...eB48                    ← contract address    │
    └──────────────────────────────────────────────────────────┘
))
```

**The full permit digest (what the user actually signs):**

```
digest = keccak256(abi.encodePacked(
    "\x19\x01",           ← EIP-191 prefix (prevents raw tx collision)
    DOMAIN_SEPARATOR,     ← binds to THIS contract on THIS chain
    keccak256(abi.encode(
        ┌────────────────────────────────────────────┐
        │  PERMIT_TYPEHASH                           │
        │  owner:    0xAlice...                      │
        │  spender:  0xVault...                      │
        │  value:    1000000 (1 USDC)                │
        │  nonce:    0 (first permit)                │
        │  deadline: 1700000000 (expiration)         │
        └────────────────────────────────────────────┘
    ))
))
```

**Why each field matters:**
- **`\x19\x01`**: Prevents the signed data from being a valid Ethereum transaction (security critical)
- **chainId**: Same contract on Ethereum vs Arbitrum produces different digests → no cross-chain replay
- **verifyingContract**: Signature for USDC can't be replayed on DAI
- **nonce**: Increments after each use → no same-contract replay
- **deadline**: Limits time window → forgotten signatures expire

**Common debugging scenario:**
```
"Invalid signature" error? Check:
1. Is DOMAIN_SEPARATOR computed with the correct chainId? (fork vs mainnet)
2. Is the nonce correct? (check token.nonces(owner))
3. Is the typehash correct? (exact string match required)
4. Did you use \x19\x01 prefix? (not \x19\x00)
```

🏗️ **Real usage:**

Most modern tokens implement EIP-2612:
- DAI was the first (DAI's `permit` predates EIP-2612 but inspired it)
- [Uniswap V2 LP tokens](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2ERC20.sol)
- All [OpenZeppelin ERC20Permit](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) tokens

---

<a id="openzeppelin-erc20permit"></a>
#### 📖 Read: OpenZeppelin's ERC20Permit Implementation

**Source:** [`@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol)

**📖 How to Study ERC20Permit:**

1. **Start with `EIP712.sol`** — the domain separator base contract
   - Find where `_domainSeparatorV4()` is computed
   - Trace how `chainId` and `address(this)` get baked in
   - This is the security anchor — understand it before `permit()`

2. **Read `Nonces.sol`** — replay protection
   - Simple: a `mapping(address => uint256)` that increments
   - Note: sequential nonces (0, 1, 2...) — contrast with Permit2's bitmap nonces later

3. **Read `ERC20Permit.permit()`** — the core function
   - Follow the flow: build struct hash → build digest → `ecrecover` → `_approve`
   - Map each line to the EIP-712 visual diagram above
   - Notice: the function is ~10 lines. The complexity is in the standard, not the code

4. **Compare with DAI's permit** — the non-standard variant
   - DAI uses `allowed` (bool) instead of `value` (uint256)
   - Different function signature = different selector
   - This is why production code needs to handle both

**Don't get stuck on:** The `_useNonce` internal function — it's just `return nonces[owner]++`. Focus on understanding the full digest construction flow.

> 🔍 **Deep dive:** Read [EIP-712](https://eips.ethereum.org/EIPS/eip-712) to understand how typed data signing prevents phishing (compared to raw `personal_sign`). The domain separator binds signatures to specific contracts on specific chains. [QuickNode - EIP-2612 Permit Guide](https://www.quicknode.com/guides/ethereum-development/transactions/how-to-use-erc20-permit-approval) provides a hands-on tutorial. [Cyfrin Updraft - EIP-712](https://updraft.cyfrin.io/courses/security/bridges/eip-712) covers typed structured data hashing with security examples.

#### 🔗 DeFi Pattern Connection

**Where EIP-2612 permit appears in production:**

1. **Aave V3 Deposits**
   ```solidity
   // Single-tx deposit: permit + supply in one call
   function supplyWithPermit(
       address asset, uint256 amount, address onBehalfOf,
       uint16 referralCode, uint256 deadline,
       uint8 v, bytes32 r, bytes32 s
   ) external;
   ```
   Aave's Pool contract calls `IERC20Permit(asset).permit(...)` then `safeTransferFrom` — same pattern you'll build in the PermitVault exercise.

2. **Uniswap V2 LP Token Removal**
   - Uniswap V2 LP tokens implement EIP-2612
   - Users can sign a permit to approve the router, then remove liquidity in one transaction
   - This was one of the earliest production uses of permit

3. **OpenZeppelin's `ERC20Wrapper`**
   - Wrapped tokens (like WETH alternatives) use permit for gasless wrapping
   - `depositFor` with permit = wrap + deposit atomically

**The limitation that led to Permit2:** All these only work if the token itself implements EIP-2612. For tokens like USDT, WETH (mainnet), and thousands of pre-2021 tokens — you're back to two transactions. This gap is exactly what Permit2 fills (next topic).

> **Connection to Module 1:** The EIP-712 typed data signing uses `abi.encode` for struct hashing — the same encoding you studied with `abi.encodeCall`. Custom errors (Module 1) are also critical here: permit failures need clear error messages for debugging.

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Assuming all tokens support permit
function deposit(address token, uint256 amount, ...) external {
    IERC20Permit(token).permit(...);  // Reverts for USDT, mainnet WETH, etc.
    IERC20(token).transferFrom(msg.sender, address(this), amount);
}

// ✅ CORRECT: Check permit support or use try/catch with fallback
function deposit(address token, uint256 amount, ...) external {
    try IERC20Permit(token).permit(...) {} catch {}
    // Falls back to pre-existing allowance if permit isn't supported
    IERC20(token).transferFrom(msg.sender, address(this), amount);
}
```

```solidity
// ❌ WRONG: Hardcoding DOMAIN_SEPARATOR — breaks on chain forks
bytes32 constant DOMAIN_SEP = 0xabc...;  // Computed at deployment on chain 1

// ✅ CORRECT: Recompute if chainId changes (OpenZeppelin pattern)
function DOMAIN_SEPARATOR() public view returns (bytes32) {
    if (block.chainid == _CACHED_CHAIN_ID) return _CACHED_DOMAIN_SEPARATOR;
    return _buildDomainSeparator();  // Recompute for different chain
}
```

```solidity
// ❌ WRONG: Not checking the nonce before building the digest
bytes32 digest = buildPermitDigest(owner, spender, value, 0, deadline);
//                                                        ^ hardcoded nonce 0!

// ✅ CORRECT: Always read the current nonce from the token
uint256 nonce = token.nonces(owner);
bytes32 digest = buildPermitDigest(owner, spender, value, nonce, deadline);
```

#### 💼 Job Market Context

**Interview question you WILL be asked:**
> "Explain how EIP-2612 permit works."

<details>
<summary>Answer</summary>

"EIP-2612 adds a `permit` function to ERC-20 tokens that accepts an EIP-712 signed message instead of an on-chain `approve` transaction. The user signs a typed data message containing the spender, amount, nonce, and deadline off-chain — which is free — and anyone can submit that signature on-chain to set the allowance. This enables single-transaction flows where the protocol calls permit and transferFrom in the same tx."

</details>

**Follow-up question:**
> "What's the relationship between EIP-712 and EIP-2612?"

<details>
<summary>Answer</summary>

"EIP-712 is the general standard for typed structured data signing — it defines domain separators and type hashes that prevent cross-chain and cross-contract replay. EIP-2612 is a specific application of EIP-712 for token approvals. The domain separator includes chainId and the token contract address, so a USDC permit on Ethereum can't be replayed on Arbitrum."

</details>

**Interview Red Flags:**
- 🚩 Confusing EIP-2612 with Permit2 — they're different systems
- 🚩 Not knowing that many tokens don't support permit (USDT, mainnet WETH)
- 🚩 Can't explain the role of the domain separator

**Pro tip:** Knowing the DAI permit story shows depth — DAI had `permit()` before EIP-2612 existed and actually inspired the standard, but uses a slightly different signature format (`allowed` boolean instead of `value` uint256). This is a common gotcha in production code.

---

<a id="day5-exercise"></a>
## 🎯 Build Exercise: PermitVault

**Workspace:** [`workspace/src/part1/module3/exercise1-permit-vault/`](../workspace/src/part1/module3/exercise1-permit-vault/) — starter file: [`PermitVault.sol`](../workspace/src/part1/module3/exercise1-permit-vault/PermitVault.sol), tests: [`PermitVault.t.sol`](../workspace/test/part1/module3/exercise1-permit-vault/PermitVault.t.sol)

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

## 📋 Key Takeaways: The Approval Problem

After this section, you should be able to:
- Explain how unlimited approvals create blast radius risk — if a protocol contract or frontend is compromised, attackers can drain entire wallet balances via `transferFrom`
- Describe the classic approve race condition and why production code approves to 0 before setting a new amount
- Construct an EIP-712 permit digest from its components: domain separator, struct hash, and nonce
- Identify which tokens support EIP-2612 `permit()` and what fallback strategy to use for tokens that don't

<details>
<summary>Check your understanding</summary>

- **Unlimited approval risk**: When users grant unlimited approvals to a protocol contract, a compromise of that contract (or its frontend) lets the attacker call `transferFrom` to drain entire wallet balances — far beyond what the user deposited. The BadgerDAO frontend compromise ($120M, December 2021) demonstrated this directly: malicious scripts injected into the frontend called `increaseAllowance`, then drained wallets via `transferFrom`. Scoped approvals (approve only what's needed per operation) limit blast radius.
- **Approve race condition**: If Alice has approved Bob for 100 and calls `approve(Bob, 50)`, Bob can front-run: spend the original 100, then spend the new 50 — getting 150 total. Fix: `approve(Bob, 0)` first, then `approve(Bob, 50)` in a second tx (or use `increaseAllowance`/`decreaseAllowance`).
- **EIP-712 permit digest**: `digest = keccak256(0x1901 ‖ domainSeparator ‖ structHash)`. The domain separator binds to chain + contract address (prevents cross-chain/cross-contract replay). The struct hash encodes the permit params (owner, spender, value, nonce, deadline). The nonce prevents replay of the same signature.
- **Permit support fallback**: Not all ERC-20s implement EIP-2612. Check by calling `permit()` in a try/catch — if it reverts, fall back to standard `approve` + `transferFrom`. Permit2 solves this universally since the user only needs one standard approval to the Permit2 contract.

</details>

---

## 💡 Permit2 — Universal Approval Infrastructure

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

💻 **Quick Try:**

Check Permit2's deployment on [Etherscan](https://etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#readContract):
1. Go to "Read Contract" → call `DOMAIN_SEPARATOR()` — compare it to your token's domain separator. Different contracts, different domains
2. Check the "Write Contract" tab — find `permitTransferFrom` and `permit` (the two modes)
3. Try `nonceBitmap(address,uint256)` with your address and word index `0` — you'll see `0` (no nonces used). After using a Permit2-integrated dApp, check again

Now go to [Revoke.cash](https://revoke.cash/) and search your wallet address. Look for "Permit2" in the approvals list — if you've used Uniswap recently, you'll see a max approval to Permit2 for each token you've traded.

#### 🎓 Intermediate Example: Permit2 vs EIP-2612 Side by Side

Before diving into Permit2's internals, see how the two approaches differ from a protocol developer's perspective:

```solidity
// ── Approach 1: EIP-2612 (only works if token supports permit) ──
function depositWithPermit(
    IERC20Permit token, uint256 amount,
    uint256 deadline, uint8 v, bytes32 r, bytes32 s
) external {
    // Step 1: Execute the permit on the TOKEN contract
    token.permit(msg.sender, address(this), amount, deadline, v, r, s);
    // Step 2: Transfer tokens (now approved)
    IERC20(address(token)).transferFrom(msg.sender, address(this), amount);
}

// ── Approach 2: Permit2 (works with ANY ERC-20) ──
function depositWithPermit2(
    ISignatureTransfer.PermitTransferFrom calldata permit,
    ISignatureTransfer.SignatureTransferDetails calldata details,
    bytes calldata signature
) external {
    // Single call: Permit2 verifies signature AND transfers tokens
    PERMIT2.permitTransferFrom(permit, details, msg.sender, signature);
    // That's it — Permit2 handled everything
}
```

**Key differences:**
| | EIP-2612 | Permit2 |
|---|---|---|
| **Token requirement** | Must implement `permit()` | Any ERC-20 |
| **On-chain calls** | permit() + transferFrom() | One call to Permit2 |
| **Signature target** | Token contract | Permit2 contract |
| **Nonce system** | Sequential (0, 1, 2, ...) | Bitmap (any order) |
| **Adoption** | Tokens that opted in | Universal (any ERC-20) |

#### 🔗 DeFi Pattern Connection

**Where Permit2 is now standard:**

1. **Uniswap V4** — all token transfers go through Permit2
   - The PoolManager doesn't call `transferFrom` on tokens directly
   - Permit2 is the single token ingress/egress point
   - Combined with flash accounting (Module 2), this means: sign once, swap through multiple pools, settle once

2. **UniswapX** — intent-based trading built on witness data
   - Users sign a Permit2 permit that includes swap order details as witness
   - Fillers (market makers) can execute the order and receive tokens atomically
   - This is the foundation of the "intent" paradigm you'll study in Part 3

3. **Cowswap** — batch auctions with Permit2
   - Users sign permits for their sell orders
   - Solvers batch-settle multiple orders in one transaction
   - Permit2's bitmap nonces enable parallel order collection

4. **1inch Fusion** — similar intent-based architecture
   - Permit2 enables gasless limit orders
   - Users sign, resolvers execute

**The pattern:** If you're building a DeFi protocol in 2025-2026, Permit2 integration is expected. Protocols that still require direct approve are considered legacy.

> **Connection to Module 2:** Permit2 + transient storage = Uniswap V4's entire token flow. Users sign Permit2 permits, the PoolManager tracks deltas in transient storage (flash accounting), and settlement happens once at the end.

#### 💼 Job Market Context

**Interview question you WILL be asked:**
> "How does Permit2 work and why is it better than EIP-2612?"

<details>
<summary>Answer</summary>

"Permit2 is a universal approval infrastructure deployed by Uniswap. Users do one standard ERC-20 approve to the Permit2 contract per token, then all subsequent protocol interactions use EIP-712 signed messages. It has two modes: SignatureTransfer for one-time stateless permits with bitmap nonces that enable parallel signatures, and AllowanceTransfer for persistent time-bounded allowances packed into single storage slots. The key advantage over EIP-2612 is universality — it works with any ERC-20, not just tokens that implement permit."

</details>

**Follow-up question:**
> "What's the risk of everyone approving a single contract like Permit2? Isn't that a single point of failure?"

<details>
<summary>Answer</summary>

"Valid concern. Permit2 is a singleton — if it had a critical bug, every protocol and user relying on it would be affected. The tradeoff is that one heavily-audited, immutable contract is easier to secure than thousands of individual protocol approvals. Permit2 is non-upgradeable (no proxy), has been audited multiple times, and has held billions in effective approvals since 2022 without incident. The risk is concentrated but well-managed, versus the traditional model where risk is scattered across many less-audited contracts."

</details>

**Interview Red Flags:**
- 🚩 "Permit2 is just Uniswap's version of permit" — shows superficial understanding
- 🚩 Not knowing the difference between SignatureTransfer and AllowanceTransfer
- 🚩 Can't explain why Permit2 uses bitmap nonces instead of sequential

**Pro tip:** Mention that Permit2 is deployed at the same address on every EVM chain (`0x000000000022D473030F116dDEE9F6B43aC78BA3`) using CREATE2. This detail shows you understand deployment patterns and cross-chain consistency — topics covered in Module 7.

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

#### 🔍 Deep Dive: Bitmap Nonces — How They Work

**The problem with sequential nonces:**
```
EIP-2612 nonces: 0 → 1 → 2 → 3 → ...

User signs order A (nonce 0) and order B (nonce 1) in parallel.
Order B CANNOT execute — it needs nonce 1, but current nonce is 0.
Order A MUST go first. If order A fails or gets stuck → order B is also blocked.
Sequential nonces force serial execution — no parallelism possible.
```

**Bitmap nonces solve this — any nonce can be used in any order:**

```
Nonce value: uint256 → split into two parts

┌──────────────────────────────────┬──────────────┐
│    Word index (bits 8-255)       │  Bit position │
│    Which 256-bit word to use     │  (bits 0-7)   │
│    248 bits → 2^248 words        │  0-255        │
└──────────────────────────────────┴──────────────┘

Example: nonce = 0x0000...0103
  Word index = 0x0000...01 = 1 (second word)
  Bit position = 0x03 = 3 (fourth bit)
```

**Visual — consuming nonces in any order:**

```
Nonce bitmap storage (per user, per spender):

Word 0: [0][0][0][0][0][0][0][0] ... [0][0][0][0]  ← 256 bits
Word 1: [0][0][0][0][0][0][0][0] ... [0][0][0][0]  ← 256 bits
Word 2: [0][0][0][0][0][0][0][0] ... [0][0][0][0]  ← 256 bits
...

Step 1: User signs order A with nonce 259 (word=1, bit=3)
Word 1: [0][0][0][1][0][0][0][0] ... [0][0][0][0]  ← bit 3 flipped!

Step 2: User signs order B with nonce 2 (word=0, bit=2)
Word 0: [0][0][1][0][0][0][0][0] ... [0][0][0][0]  ← bit 2 flipped!

Step 3: Order B settles FIRST (nonce 2) → ✅ works!
Step 4: Order A settles SECOND (nonce 259) → ✅ also works!

Sequential nonces would have failed at step 3.
```

**The Solidity implementation:**

```solidity
// Simplified from Permit2's _useUnorderedNonce
function _useUnorderedNonce(address from, uint256 nonce) internal {
    // Split nonce into word index and bit position
    uint256 wordIndex = nonce >> 8;    // First 248 bits
    uint256 bitIndex = nonce & 0xff;   // Last 8 bits (0-255)
    uint256 bit = 1 << bitIndex;       // Create bitmask

    // Load the bitmap word
    uint256 word = nonceBitmap[from][wordIndex];

    // Check if already used
    if (word & bit != 0) revert InvalidNonce();  // Bit already set!

    // Mark as used (flip the bit)
    nonceBitmap[from][wordIndex] = word | bit;
}
```

**Why this is clever:**
- Each 256-bit word stores 256 individual nonces → gas efficient (one SLOAD for 256 nonces)
- 2^248 possible words → effectively unlimited nonce space
- Any order of consumption → enables parallel signature collection
- One storage read + one storage write per nonce check

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

#### 🔍 Deep Dive: Packed AllowanceTransfer Storage

**The problem:** Storing allowance state naively costs 3 storage slots (amount, expiration, nonce) = 60,000+ gas for a cold write. By packing into one slot: 20,000 gas. That's 3x savings per permit.

**Memory layout (one storage slot = 256 bits):**

```
┌────────────────────────────────────┬──────────────┬──────────────┐
│          amount (160 bits)         │  expiration  │    nonce     │
│                                    │  (48 bits)   │  (48 bits)   │
│  Max: 2^160 - 1                    │  Max: 2^48-1 │  Max: 2^48-1 │
│  ≈ 1.46 × 10^48 tokens            │  ≈ year 8.9M │  ≈ 281T nonces│
├────────────────────────────────────┼──────────────┼──────────────┤
│  bits 96-255                       │  bits 48-95  │  bits 0-47   │
└────────────────────────────────────┴──────────────┴──────────────┘
                         256 bits total (1 slot)
```

**Why uint160 is enough:**
- ERC-20 `totalSupply` is uint256, but no real token has more than ~10^28 tokens
- uint160 max ≈ 1.46 × 10^48 — billions of times larger than any token supply
- The tradeoff is negligible: slightly smaller theoretical max for 3x gas savings

**Why uint48 expiration is enough:**
- uint48 max = 281,474,976,710,655
- As a Unix timestamp: that's approximately year 8,921,556
- Safe for ~7 million years of expiration timestamps

**Why uint48 nonces are enough:**
- AllowanceTransfer uses sequential nonces (unlike SignatureTransfer's bitmaps)
- uint48 max ≈ 281 trillion
- At 1 permit per second: lasts 8.9 million years
- In practice, a user might use a few thousand nonces in their lifetime

**Comparison to Module 1's BalanceDelta:**
| | BalanceDelta | PackedAllowance |
|---|---|---|
| **Total size** | 256 bits | 256 bits |
| **Packing** | 2 × int128 | uint160 + uint48 + uint48 |
| **Purpose** | Two token amounts | Amount + time + counter |
| **Access pattern** | Bit shifting | Struct packing (Solidity handles it) |

> **Connection to Module 1:** This is the same slot-packing optimization you studied with `BalanceDelta` in Module 1, but here Solidity's struct packing handles the bit manipulation automatically — no manual shifting needed.

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

#### ⚠️ Common Mistakes

```solidity
// ❌ WRONG: Using SignatureTransfer for frequent interactions
// User must sign a new permit for EVERY deposit — bad UX for daily users
function deposit(PermitTransferFrom calldata permit, ...) external {
    PERMIT2.permitTransferFrom(permit, details, msg.sender, signature);
}

// ✅ BETTER: Use AllowanceTransfer for protocols users interact with regularly
// User sets a time-bounded allowance once, then deposits freely
function deposit(uint256 amount) external {
    PERMIT2.transferFrom(msg.sender, address(this), uint160(amount), token);
}
```

```solidity
// ❌ WRONG: Forgetting that AllowanceTransfer uses uint160, not uint256
function deposit(uint256 amount) external {
    // This will silently truncate amounts > type(uint160).max!
    PERMIT2.transferFrom(msg.sender, address(this), uint160(amount), token);
}

// ✅ CORRECT: Validate the amount fits in uint160
function deposit(uint256 amount) external {
    require(amount <= type(uint160).max, "Amount exceeds uint160");
    PERMIT2.transferFrom(msg.sender, address(this), uint160(amount), token);
}
```

```solidity
// ❌ WRONG: Not approving Permit2 first — the one-time ERC-20 approve step
// Users need to: approve(PERMIT2, MAX) once per token BEFORE using permits
// Your dApp must check and prompt this approval

// ✅ CORRECT: Check Permit2 allowance in your frontend
// if (token.allowance(user, PERMIT2) == 0) → prompt approve tx
// Then use Permit2 signatures for all subsequent interactions
```

#### 💼 Job Market Context: Permit2 Internals

**Interview question:**
> "SignatureTransfer vs AllowanceTransfer — when would you use each?"

<details>
<summary>Answer</summary>

"SignatureTransfer for maximum security — each signature is consumed immediately with a unique nonce, no persistent state. Best for one-off operations like swaps or NFT purchases. AllowanceTransfer for convenience — set a time-bounded allowance once, then the protocol can pull tokens repeatedly until it expires. Best for protocols users interact with frequently, like a DEX router they use daily."

</details>

**Follow-up question:**
> "Why does Permit2 use bitmap nonces instead of sequential?"

<details>
<summary>Answer</summary>

"Sequential nonces force serial execution — if you sign order A (nonce 0) and order B (nonce 1), order B can't settle before order A. Bitmap nonces use a bit-per-nonce model where any nonce can be consumed in any order. This is essential for intent-based systems like UniswapX, where users sign multiple orders that may be filled by different solvers at different times. Each nonce is a single bit in a 256-bit word, so one storage slot covers 256 unique nonces."

</details>

**Interview Red Flags:**
- 🚩 Can't explain when to choose SignatureTransfer over AllowanceTransfer
- 🚩 Doesn't understand why bitmap nonces enable parallel execution
- 🚩 Thinks AllowanceTransfer's uint160 amount is a limitation (it's a deliberate packing optimization)

**Pro tip:** If you're interviewing at a protocol that integrates Permit2, know which mode they use. Uniswap's periphery contracts (Universal Router, PositionManager) primarily use SignatureTransfer (one-time, stateless). If the protocol has recurring interactions (like a lending pool), they likely use AllowanceTransfer. Showing you checked their codebase before the interview is a strong signal.

---

<a id="permit2-source-code"></a>
#### 📖 Read: Permit2 Source Code

**Source:** [github.com/Uniswap/permit2](https://github.com/Uniswap/permit2)

Read these contracts in order:

1. [`src/interfaces/ISignatureTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol) — the interface tells you the mental model
2. [`src/SignatureTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/SignatureTransfer.sol) — focus on `permitTransferFrom` and the nonce bitmap logic in `_useUnorderedNonce`
3. [`src/interfaces/IAllowanceTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/interfaces/IAllowanceTransfer.sol) — compare the interface to SignatureTransfer
4. [`src/AllowanceTransfer.sol`](https://github.com/Uniswap/permit2/blob/main/src/AllowanceTransfer.sol) — focus on `permit`, `transferFrom`, and how allowance state is packed
5. [`src/libraries/SignatureVerification.sol`](https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol) — handles EOA signatures, EIP-2098 compact signatures, and EIP-1271 contract signatures

> **EIP-2098 compact signatures:** Standard ECDSA signatures are 65 bytes (`r` [32] + `s` [32] + `v` [1]). [EIP-2098](https://eips.ethereum.org/EIPS/eip-2098) encodes them in 64 bytes by packing `v` into the highest bit of `s` (since `v` is always 27 or 28, only 1 bit is needed). Permit2's `SignatureVerification` accepts both formats — if the signature is 64 bytes, it extracts `v` from `s`. This saves ~1 byte of calldata per signature (~16 gas), which adds up in batch operations.

🏗️ **Read: Permit2 Integration in the Wild**

**Source:** [Uniswap Universal Router](https://github.com/Uniswap/universal-router) uses Permit2 for all token ingress.

Look at how `V3SwapRouter` calls `permit2.permitTransferFrom` to pull tokens from users who have signed permits. Compare this to the old V2/V3 routers that required `approve` first.

> **Real-world data:** After Uniswap deployed Universal Router with Permit2 in November 2022, ~80% of swaps now use permit-based approvals instead of on-chain approves. [Dune Analytics dashboard](https://dune.com/queries/1635283)

#### 📖 How to Study Permit2 Source Code

**Start here — the 5-step approach:**

1. **Start with interfaces** — `ISignatureTransfer.sol` and `IAllowanceTransfer.sol`
   - These tell you the mental model before implementation details
   - Map the struct names to concepts: `PermitTransferFrom` = one-time, `PermitSingle` = persistent

2. **Read `SignatureTransfer.permitTransferFrom`** — follow one complete flow
   - Entry point → signature verification → nonce consumption → token transfer
   - Focus on: what gets checked, in what order, and what reverts look like

3. **Understand `_useUnorderedNonce`** — the bitmap nonce system
   - This is the cleverest part — draw the bitmap on paper
   - Trace through with a concrete nonce value (e.g., nonce = 515 → word 2, bit 3)

4. **Read `AllowanceTransfer.permit` and `transferFrom`** — compare with SignatureTransfer
   - Notice: permit sets state, transferFrom reads state (two-step)
   - Contrast with SignatureTransfer where everything happens in one call

5. **Study `SignatureVerification.sol`** — the signature validation library
   - Handles three signature types: standard (65 bytes), compact EIP-2098 (64 bytes), and EIP-1271 (smart contract)
   - This connects directly to Module 4's account abstraction — smart wallets use EIP-1271

**Don't get stuck on:** The assembly optimizations in the verification library. Understand the concept first (verify signature → check nonce → transfer tokens), then revisit the low-level details.

**What to look for:**
- How errors are defined and when each one reverts
- The `witness` parameter in `permitWitnessTransferFrom` — this is how UniswapX binds order data to signatures
- How batch operations (`permitTransferFrom` for arrays) reuse the single-transfer logic — Permit2 supports `PermitBatchTransferFrom` and `PermitBatch` for multi-token transfers in a single signature, which is how protocols like 1inch and Cowswap handle complex multi-asset swaps

---

<a id="day6-exercise"></a>
## 🎯 Build Exercise: Permit2Vault

**Workspace:** [`workspace/src/part1/module3/exercise2-permit2-vault/`](../workspace/src/part1/module3/exercise2-permit2-vault/) — starter file: [`Permit2Vault.sol`](../workspace/src/part1/module3/exercise2-permit2-vault/Permit2Vault.sol), tests: [`Permit2Vault.t.sol`](../workspace/test/part1/module3/exercise2-permit2-vault/Permit2Vault.t.sol)

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

**⚠️ Running these tests — mainnet fork required:**

This exercise forks Ethereum mainnet to interact with the real, deployed Permit2 contract. You need an RPC endpoint:

```bash
# 1. Get a free RPC URL from one of these providers:
#    - Alchemy:  https://www.alchemy.com/  (free tier: 300M compute units/month)
#    - Infura:   https://www.infura.io/    (free tier: 100k requests/day)
#    - Ankr:     https://www.ankr.com/     (free public endpoint, slower)

# 2. Set it as an environment variable:
export MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"

# 3. Run the tests:
forge test --match-contract Permit2VaultTest --fork-url $MAINNET_RPC_URL -vvv

# Tip: Add the export to your .bashrc / .zshrc so you don't have to set it every session.
# You'll need this for many exercises later (Part 2 onwards) that fork mainnet.
```

The tests pin a specific block number (`19_000_000`) so results are deterministic — the first run downloads and caches that block's state, subsequent runs are fast.

6. **Gas savings:**
   - Traditional approve → deposit requires two on-chain transactions: approve (~46k gas) + deposit
   - Permit2 SignatureTransfer: one transaction (signature is off-chain and free) → saves the entire approve tx
   - The tests include a gas measurement to demonstrate this advantage

**🎯 Goal:** Hands-on with the Permit2 contract so you recognize its patterns when you see them in Uniswap V4, UniswapX, and other modern DeFi protocols. The witness data extension is particularly important—it's central to intent-based systems you'll study in Part 3.

## 📋 Key Takeaways: Permit2

After this section, you should be able to:
- Explain the difference between SignatureTransfer (one-time) and AllowanceTransfer (recurring) and when to choose each
- Describe how bitmap nonces enable parallel signature collection without requiring sequential ordering
- Explain what witness data is and why intent-based protocols like UniswapX need it to bind extra context to permits

<details>
<summary>Check your understanding</summary>

- **SignatureTransfer vs AllowanceTransfer**: SignatureTransfer is one-time — each signature is consumed on use (like a cheque). AllowanceTransfer is recurring — sets an on-chain allowance with an expiration that can be spent multiple times. Use SignatureTransfer for swaps/one-off actions; AllowanceTransfer for subscriptions/protocols needing repeated pulls.
- **Bitmap nonces**: Traditional sequential nonces (0, 1, 2…) force signatures to be used in order. Permit2's bitmap nonces assign each signature a `(wordIndex, bitIndex)` pair in a 256-bit bitmap. Any signature can be consumed in any order — critical for protocols collecting signatures from multiple users in parallel.
- **Witness data**: Extra application-specific data bound into the permit signature. UniswapX uses it to include order details (tokens, amounts, routes) so the filler can't repurpose the permit for a different trade. The witness hash is included in the EIP-712 struct, making it tamper-proof.

</details>

---

## 💡 Security Considerations and Edge Cases

<a id="permit-attack-vectors"></a>
### 💡 Concept: Permit/Permit2 Attack Vectors

**Why this matters:** Signature-based approvals introduce new attack surfaces. The bad guys know these patterns—you need to know them better.

**🚨 1. Signature replay:**

If a signature isn't properly scoped (chain ID, contract address, nonce), it can be replayed on other chains or after contract upgrades.

**Protection:**
- ✅ EIP-712 domain separators prevent cross-contract/cross-chain replay
- ✅ Nonces prevent same-contract replay
- ✅ Deadlines limit time window

> ⚡ **Common pitfall:** Forgetting to include `block.chainid` in your domain separator. Your signatures will be valid on all forks (Ethereum mainnet, Sepolia, Holesky with same contract address).

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
- **Scale:** $300M+ lost to permit phishing attacks (2024 alone)

**Protection — what wallet UIs must display:**

A phishing permit looks identical to a legitimate one unless the wallet shows the right fields. Wallets must display:

| Field | Why it matters |
|-------|---------------|
| **Spender address** | Who receives approval — is it the protocol you expect? |
| **Token contract + symbol** | Which token is being approved — not just "ERC-20 Token" |
| **Amount** | Exact amount, never just "unlimited" without warning |
| **Deadline** | When the permit expires — an already-expired deadline is suspicious |
| **Chain ID** | Which network — prevents cross-chain replay confusion |

MetaMask and Coinbase Wallet now render EIP-712 typed data with labeled fields. But many wallets still show raw hex — users can't distinguish a legitimate Uniswap permit from a phishing one.

**As a protocol developer:**
- ✅ Never ask users to sign permits for contracts they don't recognize
- ✅ Use descriptive EIP-712 type names (e.g., `PermitTransferFrom` not `Permit`)
- ✅ User education: "If you didn't initiate the action, don't sign"

> ⚡ **Common pitfall:** Your dApp's UI shows "Sign to deposit" but the permit is actually approving tokens to an intermediary contract. Users can't verify the `spender` address. Be transparent about what the signature authorizes.

> 🔍 **Deep dive:** [Gate.io - Permit2 Phishing Analysis](https://www.gate.com/learn/articles/is-your-wallet-safe-how-hackers-exploit-permit-uniswap-permit2-and-signatures-for-phishing/4197) documents real attacks with $314M lost in 2024. [Eocene - Permit2 Risk Analysis](https://eocene.medium.com/permit2-introduction-and-risk-analysis-f9444b896fc5) covers security implications. [SlowMist - Examining Permit Signatures](https://slowmist.medium.com/examining-permit-signatures-is-phishing-of-tokens-possible-via-off-chain-signatures-bfb5723a5e9) analyzes off-chain signature attack vectors.

**🚨 4. Nonce invalidation (self-service revocation):**

Users can call Permit2's `invalidateUnorderedNonces(uint256 wordPos, uint256 mask)` to proactively invalidate specific bitmap nonces — effectively revoking any pending SignatureTransfer permits that use those nonces. Note: only the nonce **owner** can call this function (it operates on `msg.sender`'s nonces), so this is not a griefing vector — it's a safety feature.

**When this matters:**
- ✅ User signed a permit but wants to cancel it before it's used
- ✅ User suspects their signature was leaked or phished
- ✅ Frontend should offer a "cancel pending permit" button that calls `invalidateUnorderedNonces`

#### 🔗 DeFi Pattern Connection

**Where permit security matters across protocols:**

1. **Approval-Based Attack Surface**
   - Traditional approvals: each protocol is an independent attack vector
   - Permit2: centralizes approval management → single point of audit, but also single point of failure
   - If Permit2 had a bug, ALL protocols using it would be affected (hasn't happened — it's been extensively audited)

2. **Cross-Protocol Phishing Campaigns**
   - Attackers target users of popular protocols (Uniswap, Aave, OpenSea)
   - Fake "claim airdrop" sites request permit signatures
   - The signature looks legitimate (EIP-712 typed data) but authorizes tokens to the attacker
   - This is why wallet signature display is a security-critical UX problem

3. **MEV and Permit Front-Running**
   - Flashbots bundles can include permit transactions
   - Searchers can extract permit signatures from the public mempool
   - Production protocols must handle the case where someone else executes the permit first
   - This is why the try/catch pattern (below) is mandatory, not optional

4. **Smart Contract Wallet Compatibility**
   - EOAs sign with `ecrecover` (v, r, s)
   - Smart wallets (ERC-4337, Module 4) sign with EIP-1271 (`isValidSignature`)
   - Permit2's `SignatureVerification` handles both → future-proof
   - Your protocol must not assume signatures always come from EOAs

**The pattern:** Signature-based systems shift the attack surface from on-chain (contract exploits) to off-chain (social engineering, phishing). Build defensively — always use try/catch for permits, validate all parameters, and never trust that a permit signature is "safe" just because it's valid.

#### ⚠️ Common Mistakes

**Mistakes that get caught in audits:**

1. **Not wrapping permit in try/catch**
   ```solidity
   // ❌ WRONG: Reverts if permit was already used (front-run)
   token.permit(owner, spender, value, deadline, v, r, s);
   token.transferFrom(owner, address(this), value);

   // ✅ CORRECT: Handle permit failure gracefully
   try token.permit(owner, spender, value, deadline, v, r, s) {} catch {}
   // If permit failed, maybe someone already executed it — check allowance
   token.transferFrom(owner, address(this), value);  // Will fail if allowance insufficient
   ```

2. **Forgetting to validate deadline on your side**
   ```solidity
   // ❌ WRONG: Relying only on the token's deadline check
   function deposit(uint256 deadline, ...) external {
       token.permit(..., deadline, ...);  // Token checks, but late revert wastes gas
   }

   // ✅ CORRECT: Check deadline early to save gas on failure
   function deposit(uint256 deadline, ...) external {
       require(block.timestamp <= deadline, "Permit expired");
       token.permit(..., deadline, ...);
   }
   ```

3. **Not handling DAI's non-standard permit**
   ```solidity
   // DAI uses: permit(holder, spender, nonce, expiry, allowed, v, r, s)
   // EIP-2612 uses: permit(owner, spender, value, deadline, v, r, s)
   // They have different function signatures and parameter types!
   // Production code needs to detect and handle both
   ```

4. **Using `msg.sender` as the permit owner without verification**
   ```solidity
   // ❌ WRONG: Anyone can submit someone else's permit
   function deposit(uint256 amount, ...) external {
       token.permit(msg.sender, ...);  // What if the signature is for a different owner?
   }

   // ✅ CORRECT: The permit's owner field must match
   // Or better: let Permit2 handle this — it verifies owner internally
   ```

#### 💼 Job Market Context

**Interview question you WILL be asked:**
> "What are the security risks of signature-based approvals?"

<details>
<summary>Answer</summary>

"Three main risks: phishing, front-running, and implementation bugs. Phishing is the biggest — $314M was lost in 2024 to fake permit signature requests. Front-running is a protocol-level concern — if a permit signature is submitted publicly, someone can execute it before the intended transaction, so protocols must use try/catch and check allowances as fallback. Implementation risks include forgetting domain separator validation, mismatched nonces, and not supporting both EIP-2612 and Permit2 paths."

</details>

**Follow-up question:**
> "How do you handle permit failures in production?"

<details>
<summary>Answer</summary>

"Always wrap permit calls in try/catch. If the permit fails — whether from front-running, expiry, or the token not supporting it — check if the allowance is already sufficient and proceed with transferFrom. This pattern is used by OpenZeppelin's SafeERC20 and is considered mandatory in production DeFi code."

</details>

**Follow-up question:**
> "How would you protect users from permit phishing?"

<details>
<summary>Answer</summary>

"On the protocol side: use Permit2's SignatureTransfer with a specific `to` address so tokens can only go to the intended recipient, not an attacker. Include witness data to bind the permit to a specific action. On the wallet side: clearly display what the user is signing — the spender address, amount, and expiration — in human-readable format. But ultimately, phishing is a UX problem more than a smart contract problem."

</details>

**Interview Red Flags:**
- 🚩 Not knowing about the try/catch pattern for permits
- 🚩 "Permit is safe because it uses cryptographic signatures" — ignores phishing
- 🚩 Can't explain the difference between front-running a permit vs stealing funds

**Pro tip:** Mention real-world permit phishing losses (hundreds of millions drained via malicious `permit` signatures). It shows you track production security incidents, not just theoretical attack vectors. DeFi security teams value practical awareness over academic knowledge.

---

<a id="safe-permit-patterns"></a>
#### 📖 Read: OpenZeppelin's SafeERC20 Permit Handling

**Source:** [`SafeERC20.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol)

**📖 How to Study SafeERC20.sol:**

1. **Start with `safeTransfer` / `safeTransferFrom`** — the simpler functions
   - See how they wrap low-level `.call()` and check both success AND return data
   - This handles tokens that don't return `bool` (like USDT on mainnet)

2. **Read `forceApprove`** — the non-obvious function
   - Some tokens (USDT) revert if you `approve` when allowance is already non-zero
   - `forceApprove` handles this: tries `approve(0)` first, then `approve(amount)`
   - This is a real production gotcha you'll encounter

3. **Study the permit try/catch pattern** — the security-critical function
   - Look for how they handle permit failure as a non-fatal event
   - The key insight: if permit fails (front-run, already used), check if allowance is already sufficient
   - This is the defensive pattern every DeFi protocol should use

4. **Trace one complete flow** — deposit with permit
   - User signs permit → protocol calls `safePermit()` → if fails, fallback to existing allowance → `safeTransferFrom()`
   - Draw this as a flowchart with the success and failure paths

**Don't get stuck on:** The assembly in `_callOptionalReturn` — it's handling tokens with non-standard return values. Understand the concept (some tokens don't return bool) and move on.

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
## 🎯 Build Exercise: SafePermit

**Workspace:** [`workspace/src/part1/module3/exercise3-safe-permit/`](../workspace/src/part1/module3/exercise3-safe-permit/) — starter file: [`SafePermit.sol`](../workspace/src/part1/module3/exercise3-safe-permit/SafePermit.sol), tests: [`SafePermit.t.sol`](../workspace/test/part1/module3/exercise3-safe-permit/SafePermit.t.sol)

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

## 📋 Key Takeaways: Security Considerations and Edge Cases

After this section, you should be able to:
- Walk through a permit front-running attack step by step and explain why Permit2's `permitTransferFrom` is immune to it
- Implement a safe permit wrapper using try/catch that gracefully handles both EIP-2612 tokens and non-permit tokens
- Explain why permit phishing is a $300M+ annual problem and what information wallet UIs must display to prevent it

<details>
<summary>Check your understanding</summary>

- **Permit front-running**: Attacker sees a `permit()` tx in the mempool and front-runs it with their own `permit()` call using the same signature. The victim's tx then reverts (nonce already used). With Permit2's `permitTransferFrom`, the permit and transfer are atomic — there's no window to front-run because the signature is consumed and tokens move in a single call.
- **Safe permit wrapper**: Wrap `permit()` in try/catch. If it succeeds, proceed. If it reverts, check if allowance is already sufficient (someone may have front-run the permit but the allowance is set). If allowance is insufficient, fall back to requiring a standard `approve` tx. This handles EIP-2612 tokens, non-permit tokens, and front-running gracefully.
- **Permit phishing ($300M+/yr)**: Attackers trick users into signing permit messages that approve the attacker's address as spender. The signed message looks harmless in most wallet UIs. Wallets must display: the spender address, the token, the amount, and the deadline. Users must verify the spender is a known contract — not an arbitrary EOA.

</details>

---

## 📚 Resources

**EIP-2612 — Permit:**
- [EIP-2612 specification](https://eips.ethereum.org/EIPS/eip-2612) — permit function standard
- [EIP-712 specification](https://eips.ethereum.org/EIPS/eip-712) — typed structured data hashing and signing
- [OpenZeppelin ERC20Permit](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) — production implementation
- [DAI permit implementation](https://github.com/makerdao/dss/blob/master/src/dai.sol) — the original (predates EIP-2612)

**Permit2:**
- [Permit2 repository](https://github.com/Uniswap/permit2) — source code and docs
- [Permit2 deployment addresses](https://github.com/Uniswap/permit2#deployments) — same address on all chains
- [Uniswap Universal Router](https://github.com/Uniswap/universal-router) — Permit2 integration example
- [Permit2 integration guide](https://docs.uniswap.org/contracts/permit2/overview) — official docs
- [Dune: Permit2 adoption metrics](https://dune.com/queries/1635283) — usage stats

**Security:**
- [OpenZeppelin SafeERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol) — safe permit handling patterns
- [Revoke.cash](https://revoke.cash/) — check your active approvals
- [EIP-1271 specification](https://eips.ethereum.org/EIPS/eip-1271) — signature validation for smart accounts (covered in Module 4)

**Advanced Topics:**
- [UniswapX ResolvedOrder](https://github.com/Uniswap/UniswapX/blob/main/src/base/ResolvedOrder.sol) — witness data in production
- [EIP-2098 compact signatures](https://eips.ethereum.org/EIPS/eip-2098) — 64-byte vs 65-byte signatures

---

**Navigation:** [← Module 2: EVM Changes](2-evm-changes.md) | [Module 4: Account Abstraction →](4-account-abstraction.md)

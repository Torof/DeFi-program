# Section 4: Account Abstraction (~3 days)

## 📚 Table of Contents

**Day 8: ERC-4337 Architecture**
- [The Problem Account Abstraction Solves](#problem-aa-solves)
- [ERC-4337 Components](#erc-4337-components)
- [The Flow](#the-flow)
- [Reading SimpleAccount and BaseAccount](#read-simpleaccount)
- [Day 8 Build Exercise](#day8-exercise)

**Day 9: EIP-7702 and DeFi Implications**
- [EIP-7702 — How It Differs from ERC-4337](#eip-7702-vs-erc-4337)
- [DeFi Protocol Implications](#defi-implications)
- [EIP-1271 — Contract Signature Verification](#eip-1271)
- [Day 9 Build Exercise](#day9-exercise)

**Day 10: Paymasters and Gas Abstraction**
- [Paymaster Design Patterns](#paymaster-patterns)
- [Paymaster Flow in Detail](#paymaster-flow)
- [Reading Paymaster Implementations](#read-paymasters)
- [Day 10 Build Exercise](#day10-exercise)

---

## Day 8: ERC-4337 Architecture

<a id="problem-aa-solves"></a>
### 💡 Concept: The Problem Account Abstraction Solves

**Why this matters:** As of 2025, over 40 million smart accounts are deployed on EVM chains. Major wallets (Coinbase Smart Wallet, Safe, Argent, Ambire) have migrated to ERC-4337. If your DeFi protocol doesn't support account abstraction, you're cutting off a massive and growing user base.

**📊 The fundamental limitations of EOAs:**

Ethereum's account model has two types: EOAs (controlled by private keys) and smart contracts. EOAs are the only accounts that can initiate transactions. This creates severe UX limitations:

| Limitation | Impact | Real-World Cost |
|------------|--------|----------------|
| **Must hold ETH for gas** | Users with USDC but no ETH can't transact | Massive onboarding friction |
| **Lost key = lost funds** | No recovery mechanism | $140B+ in lost crypto |
| **Single signature only** | No multisig, no social recovery | Enterprise users forced to use external multisig |
| **No batch operations** | Separate tx for approve + swap | 2x gas costs, poor UX |

> First proposed in [EIP-4337](https://eips.ethereum.org/EIPS/eip-4337) (March 2021), deployed to mainnet (March 2023)

**✨ The promise of account abstraction:**

Make smart contracts the primary account type, with programmable validation logic. ERC-4337 achieves this **without any changes to the Ethereum protocol itself**—everything is implemented at a higher layer.

> 🔍 **Deep dive:** [Cyfrin Updraft - Account Abstraction Course](https://updraft.cyfrin.io/courses/advanced-foundry/account-abstraction/introduction) provides hands-on Foundry tutorials. [QuickNode - ERC-4337 Guide](https://www.quicknode.com/guides/ethereum-development/wallets/account-abstraction-and-erc-4337) covers fundamentals and implementation patterns.

---

<a id="erc-4337-components"></a>
### 💡 Concept: The ERC-4337 Components

**The actors in the system:**

**1. UserOperation**

A pseudo-transaction object that describes what the user wants to do. It includes all the fields of a regular transaction (sender, calldata, gas limits) plus additional fields for smart account deployment, paymaster integration, and signature data.

Think of it as a "transaction intent" rather than an actual transaction.

```solidity
struct PackedUserOperation {
    address sender;              // The smart account
    uint256 nonce;
    bytes initCode;              // For deploying account if it doesn't exist
    bytes callData;              // The actual operation to execute
    bytes32 accountGasLimits;    // Packed: verificationGas | callGas
    uint256 preVerificationGas;  // Gas to compensate bundler
    bytes32 gasFees;             // Packed: maxPriorityFee | maxFeePerGas
    bytes paymasterAndData;      // Paymaster address + data (if sponsored)
    bytes signature;             // Smart account's signature
}
```

**2. Bundler**

An off-chain service that collects UserOperations from an alternative mempool, validates them, and bundles multiple UserOperations into a single real Ethereum transaction.

Bundlers compete with each other—it's a decentralized market. They call `handleOps()` on the EntryPoint contract and get reimbursed for gas.

**Who runs bundlers:** Flashbots, Alchemy, Pimlico, Biconomy, and any party willing to operate one. [Public bundler endpoints](https://www.alchemy.com/account-abstraction/bundler-endpoints).

**3. EntryPoint**

A singleton contract (one per network, shared by all smart accounts) that orchestrates the entire flow. It receives bundled UserOperations, validates each one by calling the smart account's validation function, executes the operations, and handles gas payment.

**Deployed addresses:**
- EntryPoint v0.7: [`0x0000000071727De22E5E9d8BAf0edAc6f37da032`](https://etherscan.io/address/0x0000000071727De22E5E9d8BAf0edAc6f37da032)
- (v0.6 at `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` - deprecated)

**4. Smart Account (Sender)**

The user's smart contract wallet. Must implement `validateUserOp()` which the EntryPoint calls during validation. This is where custom logic lives—multisig, passkey verification, social recovery, spending limits.

**🏗️ Popular implementations:**
- [Safe](https://github.com/safe-global/safe-smart-account) — most widely deployed, enterprise-grade multisig
- [Kernel (ZeroDev)](https://github.com/zerodev-app/kernel) — modular plugins, session keys
- [Biconomy](https://github.com/bcnmy/scw-contracts) — optimized for gas
- [SimpleAccount](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccount.sol) — reference implementation

**5. Paymaster**

An optional contract that sponsors gas on behalf of users. When a UserOperation includes paymaster data, the EntryPoint calls the paymaster to verify it agrees to pay, then charges the paymaster instead of the user.

This enables **gasless interactions**—a dApp can pay its users' gas costs, or accept ERC-20 tokens as gas payment. ✨

**6. Aggregator**

An optional component for signature aggregation—multiple UserOperations can share a single aggregate signature (e.g., BLS signatures), reducing on-chain verification cost.

---

<a id="the-flow"></a>
### 💡 Concept: The Flow

```
1. User creates UserOperation (off-chain)
2. User sends UserOp to Bundler (off-chain, via RPC)
3. Bundler validates UserOp locally (simulation)
4. Bundler batches multiple UserOps into one tx
5. Bundler calls EntryPoint.handleOps(userOps[])
6. For each UserOp:
   a. EntryPoint calls SmartAccount.validateUserOp() → validation
   b. If paymaster: EntryPoint calls Paymaster.validatePaymasterUserOp() → funding check
   c. EntryPoint calls SmartAccount with the operation callData → execution
   d. If paymaster: EntryPoint calls Paymaster.postOp() → post-execution accounting
7. EntryPoint reimburses Bundler for gas spent
```

**The critical insight:** Validation and execution are separated. Validation runs first for ALL UserOps in the bundle, then execution runs. This prevents one UserOp's execution from invalidating another UserOp's validation (which would waste the bundler's gas).

> 🔍 **Deep dive:** Read the [ERC-4337 spec](https://eips.ethereum.org/EIPS/eip-4337#implementation) section on the validation/execution split and the "forbidden opcodes" during validation (no storage reads, no external calls that could change state).

---

<a id="read-simpleaccount"></a>
### 📖 Read: SimpleAccount and BaseAccount

**Source:** [eth-infinitism/account-abstraction](https://github.com/eth-infinitism/account-abstraction)

Read these contracts in order:

1. [`contracts/interfaces/IAccount.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/interfaces/IAccount.sol) — the minimal interface a smart account must implement
2. [`contracts/core/BaseAccount.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/core/BaseAccount.sol) — helper base contract with validation logic
3. [`contracts/samples/SimpleAccount.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccount.sol) — a basic implementation with single-owner validation
4. [`contracts/core/EntryPoint.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/core/EntryPoint.sol) — focus on `handleOps`, `_validatePrepayment`, and `_executeUserOp` (it's complex, but understanding the flow is essential)
5. [`contracts/core/BasePaymaster.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/core/BasePaymaster.sol) — the interface for gas sponsorship

> ⚡ **Common pitfall:** The validation function returns a packed `validationData` uint256 that encodes three values: `sigFailed` (1 bit), `validUntil` (48 bits), `validAfter` (48 bits). Returning 0 means "signature valid, no time bounds." Returning 1 means "signature invalid." Get the packing wrong and your account won't work.

---

<a id="day8-exercise"></a>
## 🎯 Day 8 Build Exercise

**Workspace:** [`workspace/src/part1/section4/`](../../workspace/src/part1/section4/) — starter file: [`SimpleSmartAccount.sol`](../../workspace/src/part1/section4/SimpleSmartAccount.sol), tests: [`SimpleSmartAccount.t.sol`](../../workspace/test/part1/section4/SimpleSmartAccount.t.sol)

1. Create a minimal smart account that implements `IAccount` (just `validateUserOp`)
2. The account should validate that the UserOperation was signed by a single owner (ECDSA signature via `ecrecover`)
3. Implement basic `execute(address dest, uint256 value, bytes calldata func)` for the execution phase
4. Deploy against a local EntryPoint (the `account-abstraction` repo includes deployment scripts)

**Validation signature format:**
```solidity
function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
    external override returns (uint256 validationData)
{
    bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
    address recovered = ECDSA.recover(hash, userOp.signature);

    if (recovered != owner) return 1;  // ❌ Signature failed

    // Pay EntryPoint the required funds
    if (missingAccountFunds > 0) {
        (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
        require(success);
    }

    return 0;  // ✅ Signature valid, no time bounds
}
```

**🎯 Goal:** Understand the smart account contract interface from the builder's perspective. You're not building a wallet product—you're understanding how these accounts interact with DeFi protocols you'll design.

---

## 📋 Day 8 Summary

**✓ Covered:**
- EOA limitations — gas requirements, single key, no batch operations
- ERC-4337 architecture — UserOperation, Bundler, EntryPoint, Smart Account, Paymaster
- Validation/execution split — why it matters for security
- SimpleAccount implementation — ECDSA validation and execution

**Next:** Day 9 — EIP-7702 and how smart accounts change DeFi protocol design

---

## Day 9: EIP-7702 and DeFi Implications

<a id="eip-7702-vs-erc-4337"></a>
### 💡 Concept: EIP-7702 — How It Differs from ERC-4337

**Why this matters:** EIP-7702 (Pectra upgrade, May 2025) unlocks account abstraction for the ~200 million existing EOAs without requiring migration. Your DeFi protocol will interact with both "native" smart accounts (ERC-4337) and "upgraded" EOAs (EIP-7702).

> Introduced in [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702), activated with Pectra (May 2025)

**📊 The two paths to account abstraction:**

| Aspect | ERC-4337 | EIP-7702 |
|--------|----------|----------|
| **Account type** | Full smart account with new address | EOA keeps its address |
| **Migration** | Requires moving assets | No migration needed |
| **Flexibility** | Maximum (custom validation, storage) | Limited (temporary delegation) |
| **Adoption** | ~40M+ deployed as of 2025 | Native to protocol (all EOAs) |
| **Use case** | New users, enterprises | Existing users, wallets |

**Combined approach:**

An EOA can use EIP-7702 to delegate to an ERC-4337-compatible smart account implementation, gaining access to the full bundler/paymaster ecosystem without changing addresses. ✨

**🏗️ Real adoption:**
- [Coinbase Smart Wallet](https://www.coinbase.com/wallet/smart-wallet) uses this approach
- [Trust Wallet](https://trustwallet.com/) planning migration
- Metamask exploring integration

---

<a id="defi-implications"></a>
### 💡 Concept: DeFi Protocol Implications

**Why this matters:** As a DeFi protocol designer, account abstraction changes your core assumptions. Code that worked for 5 years breaks with smart accounts.

**1. `msg.sender` is now a contract**

When interacting with your protocol, `msg.sender` might be a smart account, not an EOA. If your protocol assumes `msg.sender == tx.origin` (to check for EOA), this breaks.

**Example of broken code:**
```solidity
// ❌ DON'T DO THIS
function deposit() external {
    require(msg.sender == tx.origin, "Only EOAs");  // BREAKS with smart accounts
    // ...
}
```

Some older protocols used this as a "reentrancy guard"—it's no longer reliable.

> ⚡ **Common pitfall:** Protocols that whitelist "known EOAs" or blacklist contracts. With EIP-7702, the same address can be an EOA one block and a contract the next.

**2. `tx.origin` is unreliable**

With bundlers submitting transactions, `tx.origin` is the bundler's address, not the user's. **Never use `tx.origin` for authentication.**

**Example of broken code:**
```solidity
// ❌ DON'T DO THIS
function withdraw() external {
    require(tx.origin == owner, "Not owner");  // tx.origin is the bundler!
    // ...
}
```

**3. Gas patterns change**

Paymasters mean users don't need ETH for gas. If your protocol requires users to hold ETH (e.g., for refund mechanisms), consider that smart account users might not have any.

**4. Batch transactions are common**

Smart accounts naturally batch operations. A single `handleOps` call might:
- Deposit collateral
- Borrow USDC
- Swap USDC for ETH
- All atomically ✨

Your protocol should handle this gracefully (no unexpected reentrancy, proper event emissions).

**5. Signatures are non-standard**

Smart accounts can use any signature scheme:
- Passkeys (WebAuthn)
- Multisig (m-of-n threshold)
- MPC (distributed key generation)
- Session keys (temporary authorization)

If your protocol requires EIP-712 signatures from users (e.g., for permit or off-chain orders), you need to support **EIP-1271** (contract signature verification) in addition to `ecrecover`.

---

<a id="eip-1271"></a>
### 💡 Concept: EIP-1271 — Contract Signature Verification

**Why this matters:** Every protocol that uses signatures (Permit2, OpenSea, Uniswap limit orders, governance proposals) must support EIP-1271 for smart account compatibility.

> Defined in [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271) (April 2019)

**The interface:**

```solidity
interface IERC1271 {
    // Standard method name
    function isValidSignature(
        bytes32 hash,      // The hash of the data that was signed
        bytes memory signature
    ) external view returns (bytes4 magicValue);
}
```

**How it works:**

1. Instead of calling `ecrecover(hash, signature)`, you check if `msg.sender` is a contract
2. If it's a contract, call `IERC1271(msg.sender).isValidSignature(hash, signature)`
3. If the return value is `0x1626ba7e` (the function selector itself), the signature is valid ✅
4. If it's anything else, the signature is invalid ❌

**Standard pattern:**
```solidity
// ✅ CORRECT: Supports both EOA and smart account signatures
function verifySignature(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
    // Check if signer is a contract
    if (signer.code.length > 0) {
        // EIP-1271 contract signature verification
        try IERC1271(signer).isValidSignature(hash, signature) returns (bytes4 magicValue) {
            return magicValue == 0x1626ba7e;
        } catch {
            return false;
        }
    } else {
        // EOA signature verification
        address recovered = ECDSA.recover(hash, signature);
        return recovered == signer;
    }
}
```

> 🔍 **Deep dive:** Permit2's [SignatureVerification.sol](https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol) is the production reference for handling both EOA and EIP-1271 signatures. [Ethereum.org - EIP-1271 Tutorial](https://ethereum.org/developers/tutorials/eip-1271-smart-contract-signatures/) provides step-by-step implementation. [Alchemy - Smart Contract Wallet Compatibility](https://www.alchemy.com/docs/how-to-make-your-dapp-compatible-with-smart-contract-wallets) covers dApp integration patterns.

---

<a id="day9-exercise"></a>
## 🎯 Day 9 Build Exercise

**Workspace:** [`workspace/src/part1/section4/`](../../workspace/src/part1/section4/) — starter file: [`SmartAccountEIP1271.sol`](../../workspace/src/part1/section4/SmartAccountEIP1271.sol), tests: [`SmartAccountEIP1271.t.sol`](../../workspace/test/part1/section4/SmartAccountEIP1271.t.sol)

1. **Extend your Day 8 smart account** to support EIP-1271:
   - Implement `isValidSignature(bytes32 hash, bytes signature)` that verifies the owner's ECDSA signature
   - Return `0x1626ba7e` if valid ✅, `0xffffffff` if invalid ❌

2. **Modify the Permit2 Vault** you built in Section 3 to support both EOA signatures (ecrecover) and contract signatures (EIP-1271):
   ```solidity
   function verifyPermitSignature(
       address owner,
       bytes32 permitHash,
       bytes memory signature
   ) internal view returns (bool) {
       if (owner.code.length > 0) {
           return IERC1271(owner).isValidSignature(permitHash, signature) == 0x1626ba7e;
       } else {
           address recovered = ECDSA.recover(permitHash, signature);
           return recovered == owner;
       }
   }
   ```

3. **Write tests** that perform a Permit2 deposit from your smart account:
   - Smart account signs a Permit2 message (as the owner)
   - Vault verifies the signature through EIP-1271
   - Permit2 transfers the tokens
   - Vault processes the deposit

**🎯 Goal:** See the full loop—smart account signs a Permit2 message, vault verifies it through EIP-1271, Permit2 transfers the tokens. This is how modern DeFi actually works with account-abstracted users.

---

## 📋 Day 9 Summary

**✓ Covered:**
- EIP-7702 vs ERC-4337 — temporary delegation vs full smart accounts
- DeFi protocol implications — `msg.sender`, `tx.origin`, batch transactions
- EIP-1271 — contract signature verification for smart account compatibility
- Real-world patterns — Permit2 integration with smart accounts

**Next:** Day 10 — Paymasters and how to sponsor gas for users

---

## Day 10: Paymasters and Gas Abstraction

<a id="paymaster-patterns"></a>
### 💡 Concept: Paymaster Design Patterns

**Why this matters:** Paymasters are where DeFi and account abstraction intersect most directly. Protocols can subsidize onboarding (Coinbase pays gas for new users), accept stablecoins for gas (pay in USDC instead of ETH), or implement novel gas markets.

**📊 Three common patterns:**

**1. Verifying Paymaster**

Requires an off-chain signature from a trusted signer authorizing the sponsorship. The dApp's backend signs each UserOperation it wants to sponsor.

**Use case:** "Free gas" onboarding flows. New users interact with your DeFi protocol without needing ETH first. ✨

**Implementation:**
```solidity
contract VerifyingPaymaster is BasePaymaster {
    address public verifyingSigner;

    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        // Extract signature from paymasterAndData
        bytes memory signature = userOp.paymasterAndData[20:];  // Skip paymaster address

        // Verify backend signed this UserOp
        bytes32 hash = keccak256(abi.encodePacked(userOpHash, block.chainid, address(this)));
        address recovered = ECDSA.recover(hash, signature);

        if (recovered != verifyingSigner) return ("", 1);  // ❌ Signature failed

        return ("", 0);  // ✅ Will sponsor this UserOp
    }
}
```

**2. ERC-20 Paymaster**

Accepts ERC-20 tokens as gas payment. The user pays in USDC or the protocol's native token, and the paymaster converts to ETH to reimburse the bundler.

**Use case:** Users hold stablecoins but no ETH. Protocol accepts USDC for gas.

Requires a **price oracle** (Chainlink or similar) to determine the exchange rate.

**Implementation sketch:**
```solidity
contract ERC20Paymaster is BasePaymaster {
    IERC20 public token;
    IChainlinkOracle public oracle;

    function validatePaymasterUserOp(...)
        external override returns (bytes memory context, uint256 validationData)
    {
        uint256 tokenPrice = oracle.getPrice();  // Token/ETH price
        uint256 tokenCost = (maxCost * 1e18) / tokenPrice;

        // Check user has enough tokens
        require(token.balanceOf(userOp.sender) >= tokenCost, "Insufficient token balance");

        // Return context with tokenCost for postOp
        return (abi.encode(userOp.sender, tokenCost), 0);
    }

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override {
        (address user, uint256 estimatedTokenCost) = abi.decode(context, (address, uint256));

        // Calculate actual token cost based on actual gas used
        uint256 tokenPrice = oracle.getPrice();
        uint256 actualTokenCost = (actualGasCost * 1e18) / tokenPrice;

        // Transfer tokens from user to paymaster
        token.transferFrom(user, address(this), actualTokenCost);
    }
}
```

> ⚡ **Common pitfall:** Oracle price updates can lag, leading to over/underpayment. Add a buffer (e.g., charge 105% of oracle price) and refund excess in `postOp`.

> 🔍 **Deep dive:** [OSEC - ERC-4337 Paymasters: Better UX, Hidden Risks](https://osec.io/blog/2025-12-02-paymasters-evm/) analyzes security vulnerabilities including post-execution charging risks. [Encrypthos - Security Risks of EIP-4337](https://encrypthos.com/guide/the-security-risks-of-eip-4337-you-need-to-know/) covers common attack vectors. [OpenZeppelin - Account Abstraction Impact on Security](https://blog.openzeppelin.com/account-abstractions-impact-on-security-and-user-experience/) provides security best practices.

**3. Deposit Paymaster**

Users pre-deposit ETH or tokens into the paymaster contract. Gas is deducted from the deposit.

**Use case:** Subscription-like models. Users deposit once, protocol deducts gas over time.

---

<a id="paymaster-flow"></a>
### 💡 Concept: Paymaster Flow in Detail

```
validatePaymasterUserOp(userOp, userOpHash, maxCost)
    → Paymaster checks if it will sponsor this UserOp
    → Returns context (arbitrary bytes) and validationData
    → EntryPoint locks paymaster's deposit for maxCost

// ... UserOp executes ...

postOp(mode, context, actualGasCost, actualUserOpFeePerGas)
    → Paymaster performs post-execution accounting
    → mode indicates: success, execution revert, or postOp revert
    → Can charge user in ERC-20, update internal accounting, etc.
```

**⚠️ Critical detail:** The `postOp` is called **even if the UserOp execution reverts** (in `PostOpMode.opReverted`), giving the paymaster a chance to still charge the user for the gas consumed.

---

<a id="read-paymasters"></a>
### 📖 Read: Paymaster Implementations

**Source:** [eth-infinitism/account-abstraction](https://github.com/eth-infinitism/account-abstraction)

- [`contracts/samples/VerifyingPaymaster.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/VerifyingPaymaster.sol) — reference verifying paymaster
- [`contracts/samples/TokenPaymaster.sol`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/TokenPaymaster.sol) — ERC-20 gas payment

**🏗️ Production paymasters:**
- [Pimlico's verifying paymaster](https://docs.pimlico.io/how-to/paymaster/verifying-paymaster)
- [Alchemy's gas manager](https://docs.alchemy.com/docs/gas-manager-services)

---

<a id="day10-exercise"></a>
## 🎯 Day 10 Build Exercise

**Workspace:** [`workspace/src/part1/section4/`](../../workspace/src/part1/section4/) — starter file: [`Paymasters.sol`](../../workspace/src/part1/section4/Paymasters.sol), tests: [`Paymasters.t.sol`](../../workspace/test/part1/section4/Paymasters.t.sol)

1. **Implement a simple verifying paymaster** that sponsors UserOperations if they carry a valid signature from a trusted signer:
   - Add a `verifyingSigner` address
   - In `validatePaymasterUserOp`, verify the signature in `userOp.paymasterAndData`
   - Return 0 for valid ✅, 1 for invalid ❌

2. **Implement an ERC-20 paymaster** that accepts a mock stablecoin as gas payment:
   - In `validatePaymasterUserOp`:
     - Verify the user has sufficient token balance
     - Return context with user address and estimated token cost
   - In `postOp`:
     - Calculate actual token cost based on `actualGasCost`
     - Transfer tokens from user to paymaster
   - Use a simple fixed exchange rate for now (1 USDC = 0.0005 ETH as mock rate)
   - In Part 2, you'll integrate Chainlink for real pricing

3. **Write tests** demonstrating the full flow:
   - User submits UserOp with no ETH
   - Paymaster sponsors gas
   - User pays in tokens
   - Verify user's token balance decreased by correct amount

4. **Test edge cases:**
   - User has insufficient tokens (paymaster should reject in validation)
   - UserOp execution reverts (paymaster should still charge in postOp)
   - Different gas prices (verify postOp correctly adjusts token cost)

**🎯 Goal:** Understand paymaster economics and how DeFi protocols can use them to remove gas friction for users.

---

## 📋 Day 10 Summary

**✓ Covered:**
- Paymaster patterns — verifying, ERC-20, deposit models
- Paymaster flow — validation, context passing, postOp accounting
- Real implementations — Pimlico, Alchemy gas managers
- Edge cases — reverted UserOps, oracle pricing, insufficient balances

**Key takeaway:** Paymasters enable gasless DeFi interactions, making protocols accessible to users without ETH. Understanding paymaster economics is essential for modern protocol design.

---

## 📚 Resources

### ERC-4337
- [EIP-4337 specification](https://eips.ethereum.org/EIPS/eip-4337) — full technical spec
- [eth-infinitism/account-abstraction](https://github.com/eth-infinitism/account-abstraction) — reference implementation
- [ERC-4337 docs](https://docs.alchemy.com/docs/account-abstraction-overview) — Alchemy's guide
- [Bundler endpoints](https://www.alchemy.com/account-abstraction/bundler-endpoints) — public bundler services

### Smart Account Implementations
- [Safe Smart Account](https://github.com/safe-global/safe-smart-account) — most widely deployed
- [Kernel by ZeroDev](https://github.com/zerodev-app/kernel) — modular plugins
- [Biconomy Smart Accounts](https://github.com/bcnmy/scw-contracts) — gas-optimized
- [SimpleAccount](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccount.sol) — reference

### EIP-7702
- [EIP-7702 specification](https://eips.ethereum.org/EIPS/eip-7702) — EOA code delegation
- [Vitalik's account abstraction roadmap](https://notes.ethereum.org/@vbuterin/account_abstraction_roadmap) — how EIP-7702 fits

### EIP-1271
- [EIP-1271 specification](https://eips.ethereum.org/EIPS/eip-1271) — contract signature verification
- [Permit2 SignatureVerification.sol](https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol) — production implementation
- [OpenZeppelin SignatureChecker](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/SignatureChecker.sol) — helper library

### Paymasters
- [Pimlico paymaster docs](https://docs.pimlico.io/how-to/paymaster/verifying-paymaster)
- [Alchemy Gas Manager](https://docs.alchemy.com/docs/gas-manager-services)
- [eth-infinitism VerifyingPaymaster](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/VerifyingPaymaster.sol)
- [eth-infinitism TokenPaymaster](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/TokenPaymaster.sol)

### Deployment Data
- [4337 Stats](https://www.bundlebear.com/overview/all) — account abstraction adoption metrics
- [Dune: Smart Account Growth](https://dune.com/johnrising/account-abstraction) — deployment trends

---

**Navigation:** [← Previous: Section 3 - Token Approvals](../section3-token-approvals/token-approvals.md) | [Next: Section 5 - Foundry →](../section5-foundry/foundry.md)

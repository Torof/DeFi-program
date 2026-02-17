# Section 6: Proxy Patterns & Upgradeability (~1.5-2 days)

## 📚 Table of Contents

**Day 14: Proxy Fundamentals**
- [Why Proxies Matter for DeFi](#why-proxies-matter)
- [How Proxies Work](#how-proxies-work)
- [Transparent Proxy Pattern](#transparent-proxy)
- [UUPS Pattern (ERC-1822)](#uups-pattern)
- [Beacon Proxy](#beacon-proxy)
- [Diamond Pattern (EIP-2535) — Awareness](#diamond-pattern)

**Day 15: Storage Layout and Initializers**
- [Storage Layout Compatibility](#storage-layout)
- [Initializers vs Constructors](#initializers)
- [Day 14-15 Build Exercises](#day14-15-exercise)

---

<a id="why-proxies-matter"></a>
## 💡 Why Proxies Matter for DeFi

**Why this matters:** Every major DeFi protocol uses proxy patterns—[Aave V3](https://github.com/aave/aave-v3-core), Compound V3, Uniswap's periphery contracts, MakerDAO's governance modules. The [Compound COMP token distribution bug](https://www.comp.xyz/t/bug-disclosure/2451) ($80M+ at risk) would have been fixable with a proxy pattern. Understanding proxies is non-negotiable for reading production code and deploying your own protocols.

In Part 2, you'll encounter: Aave V3 (transparent proxy + libraries), Compound V3 (custom proxy), MakerDAO (complex delegation patterns).

> 🔍 **Deep dive:** Read [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) to understand how proxy storage slots are chosen (specific slots to avoid collisions).

---

## Day 14: Proxy Fundamentals

<a id="how-proxies-work"></a>
### 💡 Concept: How Proxies Work

**The core mechanic:**

A proxy contract delegates all calls to a separate implementation contract using `DELEGATECALL`. The proxy holds the storage; the implementation holds the logic. Upgrading means pointing the proxy to a new implementation—storage persists, logic changes.

```
User → Proxy (storage lives here)
         ↓ DELEGATECALL
       Implementation V1 (logic only, no storage)

After upgrade:
User → Proxy (same storage, same address)
         ↓ DELEGATECALL
       Implementation V2 (new logic, reads same storage)
```

**⚠️ The critical constraint:** **Storage layout must be compatible across versions.** If V1 stores `uint256 totalSupply` at slot 0 and V2 stores `address owner` at slot 0, the upgrade corrupts all data. This is the #1 source of proxy-related exploits.

---

<a id="transparent-proxy"></a>
### 💡 Concept: Transparent Proxy Pattern

> OpenZeppelin's pattern, defined in [TransparentUpgradeableProxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/transparent/TransparentUpgradeableProxy.sol)

**How it works:**

Separates admin calls from user calls:
- If `msg.sender == admin`: the proxy handles the call directly (upgrade functions)
- If `msg.sender != admin`: the proxy delegates to the implementation

This prevents:
1. The admin from accidentally calling implementation functions
2. Function selector clashes between proxy admin functions and implementation functions

**📊 Trade-offs:**

| Aspect | Pro/Con | Details |
|--------|---------|---------|
| **Mental model** | ✅ Pro | Simple to understand |
| **Admin safety** | ✅ Pro | Admin can't accidentally interact with implementation |
| **Gas cost** | ❌ Con | Every call checks `msg.sender == admin` (~100 gas overhead) |
| **Admin limitation** | ❌ Con | Admin address can **never** interact with implementation |
| **Deployment** | ❌ Con | Extra contract (ProxyAdmin) |

**Evolution:** OpenZeppelin V5 moved the admin logic to a separate `ProxyAdmin` contract to reduce gas for regular users.

> ⚡ **Common pitfall:** Trying to call implementation functions as admin. You'll get `0x` (empty) return data because the proxy intercepts it. Use a different address to interact with the implementation.

---

<a id="uups-pattern"></a>
### 💡 Concept: UUPS Pattern (ERC-1822)

**Why this matters:** UUPS is now the **recommended** pattern for new deployments. Cheaper gas, more flexible upgrade logic. Used by: Uniswap V4 periphery, modern protocols.

> Defined in [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822), standardized as [EIP-1822](https://eips.ethereum.org/EIPS/eip-1822)

**How it works:**

Universal Upgradeable Proxy Standard puts the upgrade logic **in the implementation**, not the proxy:

```solidity
// Implementation contract
contract VaultV1 is UUPSUpgradeable, OwnableUpgradeable {
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ... vault logic
}
```

The proxy is minimal (just `DELEGATECALL` forwarding). The implementation includes `upgradeTo()` inherited from `UUPSUpgradeable`.

**📊 Trade-offs vs Transparent:**

| Feature | UUPS ✅ | Transparent |
|---------|---------|-------------|
| **Gas cost** | Cheaper (no admin check) | Higher (~100 gas/call) |
| **Flexibility** | Custom upgrade logic per version | Fixed upgrade logic |
| **Deployment** | Simpler (no ProxyAdmin) | Requires ProxyAdmin |
| **Risk** | Can brick if upgrade logic is missing | Safer for upgrades |

**⚠️ UUPS Risks:**
- If you deploy an implementation **without the upgrade function** (or with a bug in it), the proxy becomes non-upgradeable forever
- Must remember to include UUPS logic in every implementation version

> ⚡ **Common pitfall:** Forgetting to call `_disableInitializers()` in the implementation constructor. This allows someone to initialize the implementation contract directly (not through the proxy), potentially causing issues.

**🏗️ Real usage:**

[OpenZeppelin UUPS implementation](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol) — production reference.

> 🔍 **Deep dive:** [OpenZeppelin - UUPS Proxy Guide](https://docs.openzeppelin.com/contracts-stylus/uups-proxy) provides official documentation. [Cyfrin Updraft - UUPS Proxies Tutorial](https://updraft.cyfrin.io/courses/advanced-foundry/upgradeable-smart-contracts/introduction-to-uups-proxies) offers hands-on Foundry examples. [OpenZeppelin - Proxy Upgrade Pattern](https://docs.openzeppelin.com/upgrades-plugins/proxies) covers best practices and common pitfalls.

---

<a id="beacon-proxy"></a>
### 💡 Concept: Beacon Proxy

**Why this matters:** When you have 100+ proxy instances (like Aave's aTokens), upgrading them individually is expensive and error-prone. Beacon proxies let you upgrade ALL instances in a single transaction. ✨

> Defined in [BeaconProxy.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/beacon/BeaconProxy.sol)

**How it works:**

Multiple proxy instances share a single upgrade beacon that points to the implementation. Upgrading the beacon upgrades ALL proxies simultaneously.

```
Proxy A ─→ Beacon ─→ Implementation V1
Proxy B ─→ Beacon ─→ Implementation V1
Proxy C ─→ Beacon ─→ Implementation V1

After beacon update:
Proxy A ─→ Beacon ─→ Implementation V2
Proxy B ─→ Beacon ─→ Implementation V2
Proxy C ─→ Beacon ─→ Implementation V2
```

**🏗️ DeFi use case:**

[Aave's aToken contracts](https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/tokenization/AToken.sol). Every aToken (aUSDC, aWETH, aDAI, etc.) is a beacon proxy pointing to the same implementation. Upgrading the implementation upgrades all aTokens in a single transaction.

**📊 Trade-offs:**

| Aspect | Pro/Con |
|--------|---------|
| **Batch upgrades** | ✅ Pro — Upgrade many instances in one tx |
| **Gas efficiency** | ✅ Pro — Single upgrade vs many |
| **Flexibility** | ❌ Con — All instances must use same implementation |

---

<a id="diamond-pattern"></a>
### 💡 Concept: Diamond Pattern (EIP-2535) — Awareness

**What it is:**

The Diamond pattern allows a single proxy to delegate to **multiple** implementation contracts (called "facets"). Each function selector routes to its specific facet.

**🏗️ Used by:**
- LI.FI protocol (cross-chain aggregator)
- Some larger protocols with complex modular architectures

**📊 Trade-off:**

| Aspect | Pro/Con | Details |
|--------|---------|---------|
| **Modularity** | ✅ Pro | Split 100+ functions across domains |
| **Complexity** | ❌ Con | Significantly more complex |
| **Security risk** | ⚠️ Warning | [LI.FI exploit (March 2024, $10M)](https://rekt.news/lifi-rekt/) caused by facet validation bug |

**Recommendation:** For most DeFi protocols, UUPS or Transparent Proxy is sufficient. Diamond is worth knowing about but rarely needed. Complexity is a security risk.

---

## Day 15: Storage Layout and Initializers

<a id="storage-layout"></a>
### 💡 Concept: Storage Layout Compatibility

**Why this matters:** The #1 risk with proxy upgrades is **storage collisions**. [Audius governance takeover exploit](https://blog.openzeppelin.com/audius-governance-takeover-post-mortem) ($6M+ at risk) was caused by storage layout mismatch. This is silent, catastrophic, and happens at deployment—not caught by tests unless you specifically check.

**How Solidity assigns storage:**

Solidity assigns storage slots sequentially. If V2 adds a variable **before** existing ones, every subsequent slot shifts, corrupting data.

```solidity
// V1
contract VaultV1 {
    uint256 public totalSupply;              // slot 0
    mapping(address => uint256) balances;    // slot 1
}

// ❌ V2 — WRONG: inserts before existing variables
contract VaultV2 {
    address public owner;                    // slot 0 ← COLLISION with totalSupply!
    uint256 public totalSupply;              // slot 1 ← COLLISION with balances!
    mapping(address => uint256) balances;    // slot 2
}

// ✅ V2 — CORRECT: append new variables after existing ones
contract VaultV2 {
    uint256 public totalSupply;              // slot 0 (same)
    mapping(address => uint256) balances;    // slot 1 (same)
    address public owner;                    // slot 2 (new, appended)
}
```

**Storage gaps:**

To allow future inheritance changes, reserve empty slots:

```solidity
contract VaultV1 is Initializable {
    uint256 public totalSupply;
    mapping(address => uint256) balances;
    uint256[47] private __gap;  // ✅ Reserve 47 slots for future use (total 50 slots)
}

contract VaultV2 is Initializable {
    uint256 public totalSupply;
    mapping(address => uint256) balances;
    address public owner;                   // ✅ Added 1 new variable
    uint256[46] private __gap;  // ✅ Reduced gap by 1 (total still 50 slots)
}
```

**`forge inspect` for storage layout:**

```bash
# View storage layout of a contract
forge inspect src/VaultV1.sol:VaultV1 storage-layout

# Compare two versions (catch collisions before upgrade)
forge inspect src/VaultV1.sol:VaultV1 storage-layout > v1-layout.txt
forge inspect src/VaultV2.sol:VaultV2 storage-layout > v2-layout.txt
diff v1-layout.txt v2-layout.txt
```

> ⚡ **Common pitfall:** Changing the inheritance order. If V1 inherits `A, B` and V2 inherits `B, A`, the storage layout changes even if no variables were added. Always maintain inheritance order.

> 🔍 **Deep dive:** [Foundry Storage Check Tool](https://github.com/Rubilmax/foundry-storage-check) automates collision detection in CI/CD. [RareSkills - OpenZeppelin Foundry Upgrades](https://rareskills.io/post/openzeppelin-foundry-upgrades) covers the OZ Foundry upgrades plugin. [Runtime Verification - Foundry Upgradeable Contracts](https://runtimeverification.com/blog/using-foundry-to-explore-upgradeable-contracts-part-1) provides practical verification patterns.

---

<a id="initializers"></a>
### 💡 Concept: Initializers vs Constructors

**The problem:**

Constructors don't work with proxies—the constructor runs on the **implementation** contract, not the proxy. The proxy's storage is never initialized. ❌

**The solution:**

Replace constructors with `initialize()` functions that can only be called once:

```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VaultV1 is Initializable, OwnableUpgradeable {
    uint256 public totalSupply;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();  // ✅ Prevent implementation from being initialized
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }
}
```

**⚠️ The uninitialized proxy attack:**

If `initialize()` can be called by anyone (or called again), an attacker can take ownership. Real exploits:
- [Wormhole bridge initialization attack](https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a) ($10M+ at risk, caught before exploit)

**Protection mechanisms:**

1. ✅ `initializer` modifier: prevents re-initialization
2. ✅ `reinitializer(n)` modifier: allows controlled version-bumped re-initialization for upgrades that need to set new state
3. ✅ `_disableInitializers()` in constructor: prevents someone from initializing the implementation contract directly

> ⚡ **Common pitfall:** Deploying a proxy and forgetting to call `initialize()` in the same transaction. An attacker can front-run and call it first. Use a factory pattern or atomic deploy+initialize.

---

<a id="day14-15-exercise"></a>
## 🎯 Day 14-15 Build Exercises

**Workspace:** [`workspace/src/part1/section6/`](../../workspace/src/part1/section6/) — starter files: [`UUPSVault.sol`](../../workspace/src/part1/section6/UUPSVault.sol), [`UninitializedProxy.sol`](../../workspace/src/part1/section6/UninitializedProxy.sol), [`StorageCollision.sol`](../../workspace/src/part1/section6/StorageCollision.sol), [`BeaconProxy.sol`](../../workspace/src/part1/section6/BeaconProxy.sol), tests: [`UUPSVault.t.sol`](../../workspace/test/part1/section6/UUPSVault.t.sol), [`UninitializedProxy.t.sol`](../../workspace/test/part1/section6/UninitializedProxy.t.sol), [`StorageCollision.t.sol`](../../workspace/test/part1/section6/StorageCollision.t.sol), [`BeaconProxy.t.sol`](../../workspace/test/part1/section6/BeaconProxy.t.sol)

**Exercise 1: UUPS upgradeable vault**

1. Deploy a UUPS-upgradeable ERC-20 vault:
   - V1: basic deposit/withdraw
   - Include storage gap: `uint256[50] private __gap;`

2. Upgrade to V2:
   - Add withdrawal fee: `uint256 public withdrawalFeeBps;`
   - Reduce gap: `uint256[49] private __gap;`
   - Add `initializeV2(uint256 _fee)` with `reinitializer(2)`

3. Verify:
   - ✅ Storage persists across upgrade (deposits intact)
   - ✅ V2 logic is active (fee is charged)
   - ✅ Old deposits can still withdraw (with fee)

4. Use `forge inspect` to verify storage layout compatibility

**Exercise 2: Uninitialized proxy attack**

1. Deploy a transparent proxy with an implementation that has `initialize(address owner)`
2. Show the attack: anyone can call `initialize()` and become owner ❌
3. Fix with `initializer` modifier ✅
4. Show that calling `initialize()` again reverts
5. Add `_disableInitializers()` to implementation constructor

**Exercise 3: Storage collision demonstration**

1. Deploy V1 with `uint256 totalSupply` at slot 0, deposit 1000 tokens
2. Deploy V2 that inserts `address owner` before `totalSupply` ❌
3. Upgrade the proxy to V2
4. Read `owner`—it will contain the corrupted `totalSupply` value (1000 as an address)
5. Fix with correct append-only layout ✅
6. Verify with `forge inspect storage-layout`

**Exercise 4: Beacon proxy pattern**

1. Deploy a beacon and 3 proxy instances (simulating 3 aToken-like contracts)
2. Each proxy has different underlying tokens (USDC, DAI, WETH)
3. Upgrade the beacon's implementation (e.g., add a fee)
4. Verify all 3 proxies now use the new logic ✨
5. Show that upgrading once updated all instances

**🎯 Goal:** Understand proxy mechanics deeply enough to read Aave V3's proxy architecture and deploy your own upgradeable contracts safely.

---

## 📋 Day 14-15 Summary

**✓ Covered:**
- Proxy patterns — Transparent, UUPS, Beacon, Diamond
- Storage layout — append-only upgrades, storage gaps, collision detection
- Initializers — replacing constructors, preventing re-initialization
- Security — uninitialized proxies, storage collisions, real exploits

**Key takeaway:** Proxies enable upgradeability but introduce complexity. Storage layout compatibility is critical—test it with `forge inspect` before deploying upgrades.

---

## 📚 Resources

### Proxy Standards
- [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967) — standard proxy storage slots
- [EIP-1822 (UUPS)](https://eips.ethereum.org/EIPS/eip-1822) — universal upgradeable proxy standard
- [EIP-1967 (Transparent)](https://eips.ethereum.org/EIPS/eip-1967) — admin storage slot
- [EIP-2535 (Diamond)](https://eips.ethereum.org/EIPS/eip-2535) — multi-facet proxy

### OpenZeppelin Implementations
- [TransparentUpgradeableProxy](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/transparent/TransparentUpgradeableProxy.sol)
- [UUPSUpgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol)
- [BeaconProxy](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/beacon/BeaconProxy.sol)
- [Initializable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/Initializable.sol)

### Production Examples
- [Aave V3 Proxy Architecture](https://github.com/aave/aave-v3-core/tree/master/contracts/protocol/libraries) — beacon proxies, initialization patterns
- [Compound V3 Configurator](https://github.com/compound-finance/comet) — custom proxy with immutable implementation

### Security Resources
- [OpenZeppelin Proxy Upgrade Guide](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies) — best practices
- [Audius governance takeover postmortem](https://blog.openzeppelin.com/audius-governance-takeover-post-mortem) — storage collision exploit
- [Wormhole uninitialized proxy](https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a) — initialization attack

### Tools
- [Foundry storage layout](https://book.getfoundry.sh/reference/forge/forge-inspect) — `forge inspect storage-layout`
- [OpenZeppelin Upgrades Plugin](https://docs.openzeppelin.com/upgrades-plugins/1.x/) — automated layout checking

---

**Navigation:** [← Previous: Section 5 - Foundry](../section5-foundry/foundry.md) | [Next: Section 7 - Deployment →](../section7-deployment/deployment.md)

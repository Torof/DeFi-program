# Part 3 — Module 6: Cross-Chain & Bridges

> **Difficulty:** Intermediate
>
> **Estimated reading time:** ~30 minutes | **Exercises:** ~2-3 hours

## 📚 Table of Contents

**Bridge Architectures**
- [The Four Models](#the-four-models)

**How Bridges Work: On-Chain Mechanics**
- [The Lock-and-Mint Contract Pattern](#lock-and-mint-pattern)

**Bridge Security: Anatomy of Exploits**
- [Why Bridges Are the Highest-Risk DeFi Category](#bridge-highest-risk)

**Messaging Protocols: LayerZero & CCIP**
- [Beyond Token Bridges: Arbitrary Messaging](#arbitrary-messaging)
- [Build Exercise: Cross-Chain Message Handler](#exercise1-cross-chain-handler)

**Cross-Chain Token Standards**
- [The xERC20 Problem](#xerc20-problem)
- [Build Exercise: Rate-Limited Bridge Token](#exercise2-rate-limited-token)

**Cross-Chain DeFi Patterns**
- [Building on Multiple Chains](#building-multiple-chains)

---

<a id="bridge-architectures"></a>
## 💡 Bridge Architectures

Cross-chain bridges are both essential infrastructure and the most attacked category in DeFi — over $2.5B lost to bridge exploits. This module covers bridge architectures, the on-chain mechanics, security models, messaging protocols, and how to build cross-chain-aware applications.

**Why this matters for you:**
- Multi-chain DeFi is the norm — every protocol must think about cross-chain asset movement
- Bridge security evaluation is a critical skill for protocol integrations
- Messaging protocols (LayerZero, CCIP) are the foundation of cross-chain application development
- Bridge exploits are the #1 category of DeFi losses — understanding them is essential for security
- Cross-chain intents (Module 4 connection) are reshaping how bridging works

<a id="the-four-models"></a>
### 💡 Concept: The Four Models

DeFi liquidity is fragmented across Ethereum, Arbitrum, Base, Optimism, Polygon, and dozens of other chains. Bridges solve this — but each architecture makes different trust tradeoffs.

### Architecture 1: Lock-and-Mint

The oldest and simplest model. Lock on source chain, mint a wrapped representation on destination.

```
Source Chain (Ethereum)          Destination Chain (Arbitrum)
┌──────────────────────┐        ┌──────────────────────┐
│  User sends 10 ETH   │        │                      │
│  to Bridge Contract   │───────→│  Bridge mints 10     │
│                       │  verify │  wETH to user        │
│  10 ETH locked in    │        │                      │
│  bridge vault         │        │  wETH is an IOU for  │
│                       │        │  the locked ETH      │
└──────────────────────┘        └──────────────────────┘

To return:
  User burns 10 wETH on Arbitrum → Bridge unlocks 10 ETH on Ethereum
```

**Trust model:** Everything depends on who verifies the lock event — a custodian (WBTC), a multisig (early bridges), or a validator set (Wormhole guardians).

**The critical risk:** Wrapped tokens are only as good as the bridge. If the bridge is compromised and 10,000 wETH are minted without corresponding ETH locked, all wETH holders share the loss. This is why bridge exploits are catastrophic.

### Architecture 2: Burn-and-Mint

Token issuer controls minting on all chains. Burn on source, mint canonical tokens on destination.

```
Source Chain                     Destination Chain
┌──────────────────────┐        ┌──────────────────────┐
│  User burns 1000     │        │                      │
│  USDC                │───────→│  Circle mints 1000   │
│                       │  attest │  USDC (canonical)    │
│  USDC supply: -1000  │        │  USDC supply: +1000  │
└──────────────────────┘        └──────────────────────┘
```

**Examples:** USDC CCTP (Circle Cross-Chain Transfer Protocol), native token bridges.

**Advantage:** No wrapped tokens — canonical asset on every chain. **Limitation:** Only works for tokens whose issuer cooperates. You can't burn-and-mint someone else's token.

### Architecture 3: Liquidity Networks

No locking, no minting — real assets on each chain, moved via liquidity providers.

```
Source Chain                     Destination Chain
┌──────────────────────┐        ┌──────────────────────┐
│  User deposits 1 ETH │        │  LP releases 1 ETH   │
│  to bridge pool       │───────→│  to user (native!)    │
│                       │  verify │                      │
│  LP is repaid from   │        │  LP fronted the      │
│  user's deposit + fee│        │  destination ETH     │
└──────────────────────┘        └──────────────────────┘
```

**Examples:** Across Protocol, Stargate (LayerZero), Hop Protocol.

**Key advantage:** Fast and native assets — no wrapped tokens. **Limitation:** Needs LP capital staked on each chain; limited by available liquidity.

**Connection to Module 4:** Across Protocol uses an intent-based model — the LP is essentially a "solver" who fills the user's cross-chain intent and gets repaid later. Same paradigm as UniswapX, applied to bridging.

### Architecture 4: Canonical Rollup Bridges

The most trust-minimized option — inherits L1 security guarantees.

**Optimistic rollups (Arbitrum, Optimism, Base):**
- Deposits (L1 → L2): fast (~10 minutes)
- Withdrawals (L2 → L1): 7-day challenge period
- Security: full L1 security — anyone can challenge a fraudulent withdrawal

**ZK rollups (zkSync, Scroll, Linea):**
- Withdrawals: faster (hours, once validity proof is verified)
- Security: mathematical guarantee — the proof IS the verification

**Fast exits:** Third-party LPs front the withdrawal. User pays a fee; LP takes the 7-day delay risk. Across and Hop provide this service — a liquidity network layered on top of canonical security.

### Comparison Matrix

| Architecture | Speed | Trust Model | Wrapped? | Capital Efficiency | Risk |
|---|---|---|---|---|---|
| Lock-and-Mint | Moderate | Bridge validators | Yes | Low (locked capital) | Bridge compromise = all wrapped tokens worthless |
| Burn-and-Mint | Moderate | Token issuer | No (canonical) | High | Issuer centralization |
| Liquidity Network | Fast | Contracts + relayers | No (native) | Moderate (LP capital) | LP liquidity constraints |
| Canonical (Optimistic) | Slow (7 days) | L1 security | No | High | 7-day delay |
| Canonical (ZK) | Moderate | Math (ZK proofs) | No | High | Prover liveness |

💻 **Quick Try:**

Deploy in [Remix](https://remix.ethereum.org/) to feel the lock-and-mint pattern:

```solidity
contract MiniLockBridge {
    mapping(address => uint256) public locked;
    mapping(address => uint256) public minted; // simulates destination chain

    // Source chain: lock tokens
    function lock() external payable {
        locked[msg.sender] += msg.value;
        // In reality: emit event, relayer picks up, mints on destination
        minted[msg.sender] += msg.value; // simulate instant mint
    }

    // Destination chain: burn wrapped tokens to unlock
    function burn(uint256 amount) external {
        require(minted[msg.sender] >= amount, "Nothing to burn");
        minted[msg.sender] -= amount;
        locked[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    // THE VULNERABILITY: what if someone calls mint() without lock()?
    // That's exactly what bridge exploits do.
    function exploitMint(uint256 amount) external {
        minted[msg.sender] += amount; // minted without locking!
    }
}
```

Deploy with some ETH, call `lock{value: 1 ether}()`, check `minted` = 1 ETH. Then call `exploitMint(100 ether)` — you just "bridged" 100 ETH that don't exist. Call `burn(1 ether)` to get your real ETH back. This is the core of every bridge exploit: minting without corresponding locks.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"Compare lock-and-mint vs liquidity network bridges."**
   - Good answer: "Lock-and-mint locks tokens on source and mints wrapped tokens on destination. Liquidity networks use LPs to provide native tokens. Lock-and-mint creates wrapped token risk; liquidity networks give native assets but need LP capital."
   - Great answer: "The fundamental difference is the trust model and asset quality. Lock-and-mint creates a derivative whose value depends entirely on the bridge's security — if compromised, all wrapped tokens become worthless, cascading through every protocol that accepts them as collateral. Liquidity networks like Across use real assets on each chain, fronted by LPs who get repaid from the source deposit. The tradeoff is capital efficiency: lock-and-mint just needs a vault, while liquidity networks need LP capital on every chain. The industry is moving toward liquidity networks and intent-based bridging because wrapped token risk is too high for DeFi composability."

**Interview Red Flags:**
- 🚩 Treating wrapped tokens as equivalent to native tokens ("wETH is just ETH") — wrapped tokens carry bridge counterparty risk
- 🚩 Not knowing the difference between canonical rollup bridges and third-party bridges — the trust models are fundamentally different
- 🚩 Not considering how bridge architecture affects DeFi composability — if a bridge fails, every protocol using its wrapped tokens is affected

**Pro tip:** When discussing bridges, always frame them in terms of trust assumptions and failure modes. Saying "I'd evaluate the bridge's validator set, the wrapped token's dependencies in downstream protocols, and whether xERC20 rate limits are in place" signals production-level thinking about integration risk.

---

<a id="on-chain-mechanics"></a>
## 💡 How Bridges Work: On-Chain Mechanics

<a id="lock-and-mint-pattern"></a>
### 💡 Concept: The Lock-and-Mint Contract Pattern

```solidity
/// @notice Simplified bridge vault (source chain side)
contract BridgeVault {
    event TokensLocked(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint32 destinationChainId,
        bytes32 recipient  // destination chain address
    );

    /// @notice Lock tokens to bridge to destination chain
    function lock(
        IERC20 token,
        uint256 amount,
        uint32 destinationChainId,
        bytes32 recipient
    ) external {
        token.transferFrom(msg.sender, address(this), amount);

        // Emit event — the bridge's off-chain relayer/validator watches for this
        emit TokensLocked(msg.sender, address(token), amount, destinationChainId, recipient);
    }

    /// @notice Unlock tokens when user bridges back (called by bridge validator)
    function unlock(
        IERC20 token,
        address recipient,
        uint256 amount,
        bytes calldata proof  // proof that tokens were burned on destination
    ) external onlyValidator {
        _verifyProof(proof);  // THIS is where exploits happen
        token.transfer(recipient, amount);
    }
}
```

```solidity
/// @notice Simplified bridge token (destination chain side)
contract BridgedToken is ERC20 {
    address public bridge;

    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge");
        _;
    }

    /// @notice Mint wrapped tokens (called by bridge after verifying lock)
    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    /// @notice Burn wrapped tokens to unlock on source chain
    function burn(address from, uint256 amount) external onlyBridge {
        _burn(from, amount);
    }
}
```

**The security surface:** Everything hangs on `_verifyProof()` in the unlock function and the `onlyBridge` modifier in the mint function. Every bridge exploit targets one of these two verification steps.

### The Message Verification Problem

Cross-chain bridges must answer a fundamental question: **How do you prove that something happened on another chain?**

```
Approaches (from most trusted to least):

1. MULTISIG ATTESTATION
   "5 of 9 validators sign that they saw the lock event"
   Trust: the validators | Risk: key compromise (Ronin, Harmony)

2. ORACLE NETWORK
   "Chainlink nodes attest to the cross-chain event"
   Trust: oracle reputation + stake | Risk: oracle manipulation

3. OPTIMISTIC VERIFICATION
   "Assume the message is valid; challenge within N hours if not"
   Trust: at least one honest watcher | Risk: challenge period = slow

4. ZK PROOF
   "Mathematical proof that the state transition happened"
   Trust: math (trustless!) | Risk: prover bugs, circuit complexity

5. CANONICAL ROLLUP
   "The L1 itself verifies the L2 state root"
   Trust: L1 consensus | Risk: none beyond L1 security
```

The industry is moving from (1) toward (4) and (5). Every new bridge architecture tries to minimize the trust assumptions.

---

<a id="bridge-security"></a>
## 💡 Bridge Security: Anatomy of Exploits

<a id="bridge-highest-risk"></a>
### 💡 Concept: Why Bridges Are the Highest-Risk DeFi Category

Bridges hold massive TVL as locked collateral, and cross-chain verification is fundamentally hard. A single bug in verification = unlimited minting of wrapped tokens. Over $2.5B lost to bridge exploits in 2022 alone.

#### 🔍 Deep Dive: The Nomad Bridge Exploit ($190M, August 2022)

This is the most instructive bridge exploit — a tiny initialization bug that made every message valid.

**Nomad's design:** Optimistic verification. Messages are submitted with a Merkle root, and there's a challenge period before they're processed. The `confirmAt` mapping stores when each root becomes processable:

```solidity
// Nomad's Replica contract (simplified)
contract Replica {
    // Maps message root → timestamp when it becomes processable
    mapping(bytes32 => uint256) public confirmAt;

    function process(bytes memory message) external {
        bytes32 root = // ... derive root from message
        // Check: is this root confirmed AND past the challenge period?
        require(confirmAt[root] != 0, "Root not confirmed");
        require(block.timestamp >= confirmAt[root], "Still in challenge period");

        // Process the message (unlock tokens, etc.)
        _processMessage(message);
    }
}
```

**The bug:** During initialization on a new chain, the `confirmAt` mapping was initialized with a trusted root of `0x00`:

```solidity
// During initialization:
confirmAt[0x0000...0000] = 1;  // Set zero root as confirmed at timestamp 1
```

**Why this is catastrophic:** In Solidity, `mapping(bytes32 => uint256)` returns `0` for any key that hasn't been explicitly set. The `process()` function derives a root from the message — but if you submit a message that has never been seen before, its root in the `messages` mapping is `0x00`. And `confirmAt[0x00]` = 1 (a non-zero value from the initialization bug). So the check `confirmAt[root] != 0` passes for ANY message:

```
Attacker submits fake message:
  messages[fakeMessageHash] → not set → returns 0x00
  confirmAt[0x00] → returns 1 (from the bug!)
  1 != 0 → passes ✓
  block.timestamp >= 1 → passes ✓
  → Fake message processed → tokens unlocked without locking

Result: anyone can drain the bridge
```

**The exploit was crowd-looted** — once one attacker found it, hundreds of people copied the transaction calldata and submitted their own drain transactions. $190M lost in hours.

**The lesson:** One line of initialization code — `confirmAt[0x00] = 1` — destroyed $190M. Bridge verification must be rock-solid. Default values in Solidity (0 for mappings) interact with security checks in non-obvious ways. This is why bridge audits are the highest-stakes auditing category.

### Other Major Exploits

**Ronin Bridge ($625M, March 2022):**
- 5-of-9 validator multisig for Axie Infinity's bridge
- Attacker compromised 5 keys (4 Sky Mavis nodes + 1 Axie DAO validator that had been given temporary signing permission and never revoked)
- Drained the bridge across two transactions over 6 days — nobody noticed
- **Lesson:** Multisig key diversity is critical. Monitoring for large withdrawals is essential. Temporary permissions must be revoked.

**Wormhole ($325M, February 2022):**
- Signature verification bypass on the Solana side
- Attacker exploited a deprecated `verify_signatures` instruction that didn't properly verify the secp256k1 program address
- Minted 120,000 wETH on Solana without depositing ETH on Ethereum
- **Lesson:** Cross-VM verification (EVM ↔ Solana) is especially complex. Bridge verification must be audited per-chain, not just on the EVM side.

**Harmony Horizon ($100M, June 2022):**
- 2-of-5 multisig controlling the bridge
- Attacker compromised just 2 keys
- **Lesson:** 2-of-5 is an absurdly low threshold for a bridge holding $100M. Multisig threshold should scale with TVL.

### Security Evaluation Framework

When evaluating a bridge for protocol integration:

```
1. TRUST MODEL
   Who verifies messages? How many parties? What's the threshold?
   Rule of thumb: n-of-m where m ≥ 9 and n ≥ 2/3 of m

2. ECONOMIC SECURITY
   What's at stake for validators? Is stake > potential exploit profit?
   Bridge TVL should be < total validator stake × slashing penalty

3. MONITORING & RATE LIMITING
   Does the bridge have real-time anomaly detection?
   Are there maximum transfer amounts per time window?
   Can the bridge be paused? By whom? How fast?

4. AUDIT & TRACK RECORD
   How many audits? By whom? Scope?
   Has it survived adversarial conditions?
   Bug bounty program?

5. WRAPPED TOKEN RISK
   If this bridge is compromised, what tokens become worthless?
   How much of my protocol's TVL depends on this bridge's tokens?
```

#### 🔗 DeFi Pattern Connection

**Bridge security connects across the curriculum:**
- **Part 2 Module 8 (DeFi Security):** Bridge exploits are the #1 loss category, bigger than all oracle and reentrancy exploits combined
- **Part 3 Module 5 (MEV):** Cross-domain MEV exploits the timing gaps between chains — related to bridge finality
- **Part 2 Module 9 (Capstone):** Your stablecoin must consider what happens if a collateral token's bridge is compromised
- **Part 3 Module 1 (LSTs):** wstETH bridged to L2s introduces bridge dependency — if the bridge fails, all bridged wstETH loses its peg

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What went wrong in the Nomad bridge hack?"**
   - Good answer: "A bug in the initialization set the zero root as valid, so any message could pass verification. The bridge was drained of $190M."
   - Great answer: "Nomad used optimistic verification — `confirmAt` tracked which Merkle roots were processable. During initialization, `confirmAt[0x00]` was set to 1. In Solidity, unset mapping keys return zero, so any fake message's root defaulted to `0x00`, and `confirmAt[0x00]` returned 1 — passing the 'is this root confirmed?' check. The exploit was so simple it was crowd-looted: anyone could copy the attacker's calldata. The lesson: Solidity's default values interact with security checks in non-obvious ways — bridge verification must be rock-solid."

**Interview Red Flags:**
- 🚩 Not knowing about the major bridge exploits (Ronin, Wormhole, Nomad) — these are the most expensive bugs in DeFi history
- 🚩 Not considering bridge failure modes when evaluating DeFi integrations — "what happens to our TVL if this bridge is compromised?"
- 🚩 Thinking a multisig is sufficient bridge security without asking about threshold, key diversity, and monitoring

**Pro tip:** When discussing bridge security, reference the evaluation framework: trust model, economic security (is validator stake > bridge TVL?), rate limiting, and monitoring. Teams want engineers who evaluate bridges as integration dependencies, not just as black-box infrastructure.

---

## 📋 Key Takeaways: Bridge Fundamentals & Security

After this section, you should be able to:

- Compare the 4 bridge architectures (lock-and-mint, burn-and-mint, liquidity networks, canonical rollup bridges) and rank them by trust assumptions from weakest (multisig) to strongest (L1 consensus)
- Analyze the 3 major bridge exploits (Nomad $190M zero-root bug, Ronin $625M key compromise, Wormhole $325M verification bypass) and identify the root cause pattern in each
- Evaluate a bridge integration using the security framework: trust model, economic security, rate limiting, audit history, and wrapped token risk

---

<a id="messaging-protocols"></a>
## 💡 Messaging Protocols: LayerZero & CCIP

<a id="arbitrary-messaging"></a>
### 💡 Concept: Beyond Token Bridges: Arbitrary Messaging

Token bridges move assets. Messaging protocols move arbitrary data — function calls, state updates, governance votes. This enables cross-chain DeFi: deposit collateral on Arbitrum, borrow on Optimism. Vote on Ethereum, execute on Base.

### LayerZero V2: The OApp Pattern

LayerZero is the most widely adopted cross-chain messaging protocol. Its core abstraction is the **OApp (Omnichain Application)**:

```solidity
// Simplified LayerZero OApp pattern
import { OApp } from "@layerzero-v2/oapp/OApp.sol";

contract CrossChainCounter is OApp {
    uint256 public count;

    constructor(address _endpoint, address _owner)
        OApp(_endpoint, _owner) {}

    /// @notice Send a cross-chain increment message
    function sendIncrement(
        uint32 _dstEid,      // destination endpoint ID (chain)
        bytes calldata _options  // gas settings for destination execution
    ) external payable {
        bytes memory payload = abi.encode(count + 1);

        // Send message through LayerZero endpoint
        _lzSend(
            _dstEid,
            payload,
            _options,
            MessagingFee(msg.value, 0),  // pay for cross-chain gas
            payable(msg.sender)
        );
    }

    /// @notice Receive a cross-chain message (called by LayerZero endpoint)
    function _lzReceive(
        Origin calldata _origin,   // source chain + sender
        bytes32 _guid,             // unique message ID
        bytes calldata _message,   // the payload
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Decode and execute
        uint256 newCount = abi.decode(_message, (uint256));
        count = newCount;
    }
}
```

**Key patterns:**
- `_lzSend()` — send a message to another chain (user pays gas upfront)
- `_lzReceive()` — handle an incoming message (called by LayerZero's executor)
- **Source verification is built in** — the OApp base contract verifies that messages come from a trusted peer (configured per chain)

**OFT (Omnichain Fungible Token)** — LayerZero's cross-chain token standard:
- Extends the OApp pattern for token transfers
- Burn on source → mint on destination (burn-and-mint model)
- Single canonical token across all supported chains
- No wrapped tokens — every chain has the "real" token

### Chainlink CCIP: Defense-in-Depth

CCIP takes a different approach — multiple independent verification layers:

```solidity
// Simplified CCIP receiver pattern
import { CCIPReceiver } from "@chainlink/ccip/CCIPReceiver.sol";

contract CrossChainReceiver is CCIPReceiver {
    // Only accept messages from known senders on known chains
    mapping(uint64 => mapping(address => bool)) public allowedSenders;

    constructor(address _router) CCIPReceiver(_router) {}

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // 1. Verify source chain and sender
        require(
            allowedSenders[message.sourceChainSelector][
                abi.decode(message.sender, (address))
            ],
            "Unknown sender"
        );

        // 2. Decode and execute payload
        (address recipient, uint256 amount) = abi.decode(
            message.data, (address, uint256)
        );

        // 3. Execute the cross-chain action
        _processTransfer(recipient, amount);
    }
}
```

**CCIP's defense-in-depth model:**

```
Layer 1: Chainlink DON (Decentralized Oracle Network)
  → Observes source chain events, commits to destination

Layer 2: Risk Management Network (ARM)
  → INDEPENDENT set of nodes that verify message integrity
  → Can PAUSE the entire system if anomaly detected
  → Separate codebase, separate operators

Layer 3: Rate Limiting
  → Maximum transfer amount per token per time window
  → Prevents catastrophic drain even if verification is compromised

Layer 4: Manual Pause
  → Chainlink can emergency-pause the protocol
```

**The design philosophy difference:**
- **LayerZero:** Configurable security — each application chooses its own DVN (Decentralized Verifier Network) configuration. More flexible, more app-level responsibility.
- **CCIP:** Opinionated security — multiple hardcoded verification layers. Less flexible, but the security model is standardized and not app-configurable.

### Other Messaging Protocols

**Hyperlane:**
- Permissionless deployment — anyone can deploy to any chain
- ISMs (Interchain Security Modules) — configurable security per application
- Modular: choose multisig, economic, or optimistic verification

**Wormhole:**
- 19-guardian network, 13/19 multisig threshold
- VAA (Verifiable Action Approval) — signed message from guardians
- Widest chain support: EVM, Solana, Cosmos, Sui, Aptos
- NTT (Native Token Transfers) — canonical token bridging

#### 📖 How to Study: Cross-Chain Development

1. Start with [LayerZero OApp docs](https://docs.layerzero.network/v2/developers/evm/oapp/overview) — the simplest cross-chain app interface
2. Build a cross-chain counter or ping-pong using the OApp template
3. Read the [OFT standard](https://docs.layerzero.network/v2/developers/evm/oft/quickstart) — how tokens work across chains
4. Study [CCIP getting started](https://docs.chain.link/ccip/getting-started) — compare the developer experience with LayerZero
5. Read `CCIPReceiver.sol` — understand the receive-side verification pattern
6. Skip the internal endpoint/DVN implementation initially — focus on the application interface

> 🔍 **Code:** [LayerZero V2](https://github.com/LayerZero-Labs/LayerZero-v2) | [Chainlink CCIP](https://github.com/smartcontractkit/ccip)

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"What security checks would you implement when receiving a cross-chain message?"**
   - Good answer: "Verify the source chain and sender address, check for replay, validate the payload."
   - Great answer: "Three mandatory checks: (1) Source verification — maintain a mapping of trusted contract addresses per source chain, only process messages from known peers. (2) Replay protection — track processed message IDs using the messaging protocol's GUID or an application nonce. (3) Payload validation — decode the message type, validate all fields against expected ranges, handle unknown types by reverting. Beyond the three, add rate limiting on the receiver side as defense-in-depth, and emit events for every processed message for off-chain monitoring."

2. **"Explain the tradeoff between LayerZero and CCIP for cross-chain messaging."**
   - Good answer: "LayerZero lets applications configure their own security. CCIP has a fixed, multi-layer security model."
   - Great answer: "The core tradeoff is flexibility vs opinionated security. LayerZero V2 lets each app choose its DVN configuration — powerful but puts security responsibility on the developer. CCIP hardcodes multi-layer verification: DON commits, an independent Risk Management Network re-verifies, plus per-token rate limits. You can't misconfigure it, but you also can't customize it. For high-value protocols, CCIP's defense-in-depth is compelling; for wide chain coverage or custom verification, LayerZero's flexibility wins. Large protocols often integrate both."

**Interview Red Flags:**
- 🚩 Thinking cross-chain messaging is simple ("just send a message") — the verification, replay protection, and failure handling are where the complexity lives
- 🚩 Not knowing that LayerZero and CCIP have fundamentally different security philosophies — app-configured vs protocol-enforced
- 🚩 Skipping receiver-side validation because "the messaging protocol handles it" — defense-in-depth means validating at every layer

**Pro tip:** When discussing cross-chain architecture, mention that you'd implement the three mandatory receiver checks (source verification, replay protection, payload validation) regardless of which messaging protocol you use. This shows you don't blindly trust infrastructure and think about defense-in-depth at the application layer.

---

<a id="exercise1-cross-chain-handler"></a>
## 🎯 Build Exercise: Cross-Chain Message Handler

**Workspace:** `workspace/src/part3/module6/`

Build a contract that receives and validates cross-chain messages, with full source verification, replay protection, and message dispatch.

**What you'll implement:**
- `setTrustedSource()` — configure known senders per source chain
- `handleMessage()` — validate source, check replay, decode and dispatch
- `_handleTransfer()` — process a cross-chain token transfer message
- `_handleGovernance()` — process a cross-chain governance action

**Concepts exercised:**
- Source chain + sender verification pattern
- Nonce/message ID replay protection
- ABI encoding/decoding for cross-chain payloads
- Message type dispatching
- The receive-side security model that every cross-chain app needs

**🎯 Goal:** Build the receive-side security foundation that every cross-chain application needs. If you understand this pattern, you can integrate any messaging protocol.

Run: `forge test --match-contract CrossChainHandlerTest -vvv`

---

<a id="token-standards"></a>
## 💡 Cross-Chain Token Standards

<a id="xerc20-problem"></a>
### 💡 Concept: The xERC20 Problem

If your protocol deploys a token across multiple chains, you face a dilemma: which bridge(s) can mint it?

- **Single bridge:** If that bridge is exploited, all cross-chain tokens are worthless
- **Multiple bridges:** How do you prevent one compromised bridge from minting unlimited tokens?

**xERC20 (ERC-7281)** solves this with **per-bridge rate limits**:

```solidity
/// @notice Simplified xERC20 rate-limited minting
contract CrossChainToken is ERC20 {
    struct BridgeConfig {
        uint256 maxLimit;          // maximum mint capacity (bucket size)
        uint256 ratePerSecond;     // how fast the limit refills
        uint256 currentLimit;      // current available mint capacity
        uint256 lastUpdated;       // last time limit was refreshed
    }

    mapping(address => BridgeConfig) public bridges;
    address public owner;

    /// @notice Token owner configures each bridge's rate limit
    function setLimits(
        address bridge,
        uint256 mintingLimit  // max tokens per day
    ) external onlyOwner {
        bridges[bridge] = BridgeConfig({
            maxLimit: mintingLimit,
            ratePerSecond: mintingLimit / 1 days,
            currentLimit: mintingLimit,
            lastUpdated: block.timestamp
        });
    }

    /// @notice Mint tokens — called by an authorized bridge
    function mint(address to, uint256 amount) external {
        BridgeConfig storage config = bridges[msg.sender];
        _refreshLimit(config);

        require(config.currentLimit >= amount, "Rate limit exceeded");
        config.currentLimit -= amount;

        _mint(to, amount);
    }

    /// @notice Refill the rate limit based on elapsed time
    function _refreshLimit(BridgeConfig storage config) internal {
        uint256 elapsed = block.timestamp - config.lastUpdated;
        uint256 refill = elapsed * config.ratePerSecond;
        config.currentLimit = _min(config.maxLimit, config.currentLimit + refill);
        config.lastUpdated = block.timestamp;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
```

#### 🔍 Deep Dive: Rate Limiting Math (Token Bucket)

The rate limiter uses the **token bucket algorithm** — the same pattern used in API rate limiting:

```
Parameters:
  maxLimit (bucket capacity): 1,000,000 USDC
  ratePerSecond (refill rate): 11.57 USDC  (≈ 1M per day)

Timeline:
────────────────────────────────────────────────────────────
t=0:    limit = 1,000,000         (full bucket)

        Bridge A mints 800,000
t=0+:   limit = 200,000           (800k consumed)

t=1h:   limit = 200,000 + 11.57 × 3,600
              = 200,000 + 41,652
              = 241,652           (partially refilled)

        Bridge A tries to mint 300,000
        241,652 < 300,000 → REVERTS ✗

t=24h:  limit = min(1,000,000, 241,652 + 11.57 × 82,800)
              = min(1,000,000, 1,199,348)
              = 1,000,000         (fully refilled, capped at max)
────────────────────────────────────────────────────────────
```

**Why this matters for security:**

```
Scenario: Bridge A is compromised

WITHOUT rate limiting (traditional bridge):
  Attacker mints UNLIMITED tokens → entire TVL drained instantly

WITH xERC20 rate limiting:
  Bridge A's limit: 1,000,000 USDC/day
  Attacker mints 1,000,000 → hits rate limit → can't mint more
  Total damage: $1M (not $100M)
  Protocol has time to detect, pause, and respond

  Meanwhile, Bridge B and Bridge C are unaffected —
  users on those bridges can still operate normally
```

**The key insight:** xERC20 turns a catastrophic risk (total bridge compromise = total loss) into a bounded risk (compromised bridge damage ≤ rate limit). This is defense-in-depth applied to bridge design.

> 🔍 **Standard:** [ERC-7281: Sovereign Bridged Tokens](https://eips.ethereum.org/EIPS/eip-7281) — the full specification

#### 🔗 DeFi Pattern Connection

**Rate limiting appears across DeFi:**
- **xERC20** — per-bridge mint limits (this module)
- **Chainlink CCIP** — per-token transfer limits per time window
- **Aave V3** — supply/borrow caps per asset (Part 2 Module 4)
- **MakerDAO** — debt ceiling per collateral type (Part 2 Module 6)

The pattern is always the same: cap the blast radius of a single failure. The math is always: capacity, refill rate, current bucket level.

#### 💼 Job Market Context

**What DeFi teams expect you to know:**

1. **"How would you design a cross-chain token resilient to bridge failure?"**
   - Good answer: "Use xERC20 with rate-limited minting per bridge, so a single compromise can't create unlimited tokens."
   - Great answer: "Implement xERC20 (ERC-7281) with per-bridge rate limits using a token bucket algorithm. Each authorized bridge gets an independent minting cap that refills over time. If Bridge A is compromised, the attacker can only mint up to Bridge A's daily limit — not unlimited tokens — while Bridges B and C continue normally. Calibrate limits so no single bridge's cap exceeds what the protocol can absorb as bad debt. Add monitoring for total supply anomalies across chains. This turns a catastrophic risk into a bounded, manageable one."

**Interview Red Flags:**
- 🚩 Not understanding rate limiting as a security mechanism — it's defense-in-depth, not just a nice-to-have
- 🚩 Designing a cross-chain token with a single bridge dependency — one compromise and all cross-chain tokens are worthless
- 🚩 Not knowing ERC-7281 (xERC20) when discussing cross-chain token design — it's the standard for sovereign bridged tokens

**Pro tip:** Mention the token bucket algorithm by name and explain the calibration tradeoff: limits too high and a compromise is still catastrophic, limits too low and legitimate bridging is throttled. Showing you think about operational parameters — not just the code — signals real-world deployment experience.

---

<a id="exercise2-rate-limited-token"></a>
## 🎯 Build Exercise: Rate-Limited Bridge Token

**Workspace:** `workspace/src/part3/module6/`

Implement a token with per-bridge rate-limited minting — the xERC20 pattern.

**What you'll implement:**
- `setLimits()` — token owner configures minting/burning limits per bridge
- `mint()` — bridge mints tokens, subject to rate limit
- `burn()` — bridge burns tokens, subject to rate limit
- `mintingCurrentLimitOf()` — view current available mint capacity for a bridge
- `_refreshLimit()` — token bucket refill calculation

**Concepts exercised:**
- Token bucket rate limiting algorithm
- Per-bridge access control and independent limits
- Time-based refill math
- Defense-in-depth: bounding blast radius of a bridge compromise
- The ERC-7281 standard pattern

**🎯 Goal:** Build a cross-chain token where no single bridge compromise can drain more than a bounded amount per day.

Run: `forge test --match-contract RateLimitedTokenTest -vvv`

---

## 📋 Key Takeaways: Cross-Chain Integration

After this section, you should be able to:

- Implement a cross-chain message receiver using LayerZero V2's OApp pattern (`_lzSend()` / `_lzReceive()`) with mandatory source verification and replay protection
- Compare LayerZero (configurable security via DVNs) with Chainlink CCIP (defense-in-depth: DON + independent Risk Management Network + rate limiting) for cross-chain messaging
- Explain xERC20 (ERC-7281) rate-limited minting: how per-bridge minting caps using the token bucket algorithm (capacity, refill rate) bound the blast radius of any single bridge compromise

---

<a id="cross-chain-patterns"></a>
## 💡 Cross-Chain DeFi Patterns

<a id="building-multiple-chains"></a>
### 💡 Concept: Building on Multiple Chains

### Pattern 1: Cross-Chain Swaps

User wants Token A on Chain 1 → Token B on Chain 2. Three approaches:

```
Approach 1: Bridge then Swap
  Chain 1: bridge Token A to Chain 2
  Chain 2: swap Token A → Token B on local DEX
  Pros: simple | Cons: 2 transactions, user needs gas on Chain 2

Approach 2: Swap then Bridge
  Chain 1: swap Token A → Token B on local DEX
  Chain 1: bridge Token B to Chain 2
  Pros: single chain for swap | Cons: Token B might have less liquidity on Chain 1

Approach 3: Intent-based (Across model)
  User signs: "I have Token A on Chain 1, I want Token B on Chain 2"
  Solver: swaps + bridges in one step, fronts destination tokens
  User receives Token B on Chain 2 immediately
  Pros: best UX, fast | Cons: depends on solver liquidity
```

**Approach 3 is the Module 4 intent paradigm applied to bridging.** Across Protocol's relayers are solvers that specialize in cross-chain fills.

### Pattern 2: Cross-Chain Message Handler

The most common pattern when building cross-chain applications:

```solidity
/// @notice Base pattern for receiving and validating cross-chain messages
contract CrossChainHandler {
    // Trusted sources: chainId → contract address
    mapping(uint32 => address) public trustedSources;

    // Replay protection: messageId → processed
    mapping(bytes32 => bool) public processedMessages;

    enum MessageType { TRANSFER, GOVERNANCE, SYNC_STATE }

    function handleMessage(
        uint32 sourceChain,
        address sourceSender,
        bytes32 messageId,
        bytes calldata payload
    ) external onlyMessagingProtocol {
        // 1. Source verification
        require(
            trustedSources[sourceChain] == sourceSender,
            "Unknown source"
        );

        // 2. Replay protection
        require(!processedMessages[messageId], "Already processed");
        processedMessages[messageId] = true;

        // 3. Decode and dispatch
        MessageType msgType = abi.decode(payload[:32], (MessageType));

        if (msgType == MessageType.TRANSFER) {
            _handleTransfer(payload[32:]);
        } else if (msgType == MessageType.GOVERNANCE) {
            _handleGovernance(payload[32:]);
        } else if (msgType == MessageType.SYNC_STATE) {
            _handleStateSync(payload[32:]);
        }
    }
}
```

**Three security checks that every cross-chain receiver must implement:**
1. **Source verification** — only accept messages from known contracts on known chains
2. **Replay protection** — never process the same message twice (nonce or message ID)
3. **Payload validation** — decode carefully, validate all fields, handle unexpected types

### Pattern 3: Cross-Chain Governance

Governance votes on mainnet, execution on L2s:

```
1. Users vote on Ethereum mainnet (where governance token has deepest liquidity)
2. Proposal passes → governance contract sends cross-chain message
3. Timelock on each destination chain receives the message
4. After timelock delay → execute the governance action on the destination

Trust model: Same as the messaging protocol used.
Each destination chain's timelock independently verifies the message.
```

This pattern is used by Uniswap (governance on mainnet, execution across chains) and many multi-chain DAOs.

---

<a id="summary-cross-chain"></a>
## 📋 Key Takeaways: Cross-Chain & Bridges

After this section, you should be able to:

- Design cross-chain DeFi patterns: cross-chain swaps (intent-based with solver networks), cross-chain governance (message passing for proposal execution on remote chains), and cross-chain state syncing
- Choose between OFT (LayerZero-native, single canonical deployment) and xERC20 (bridge-agnostic, per-bridge rate limits) for a new cross-chain token and justify the trade-off

---

---

<a id="resources"></a>
## 📚 Resources

**Production Code:**
- [LayerZero V2](https://github.com/LayerZero-Labs/LayerZero-v2) — OApp, OFT, endpoint contracts
- [Chainlink CCIP](https://github.com/smartcontractkit/ccip) — router, receiver, token pool
- [Wormhole](https://github.com/wormhole-foundation/wormhole) — guardian network, VAA verification
- [Across Protocol](https://github.com/across-protocol/contracts) — intent-based cross-chain bridge
- [Hyperlane](https://github.com/hyperlane-xyz/hyperlane-monorepo) — permissionless messaging

**Documentation:**
- [LayerZero V2 docs](https://docs.layerzero.network/) — OApp and OFT developer guides
- [Chainlink CCIP docs](https://docs.chain.link/ccip) — getting started and architecture
- [Wormhole docs](https://docs.wormhole.com/) — protocol overview and integration guides
- [ERC-7281: Sovereign Bridged Tokens](https://eips.ethereum.org/EIPS/eip-7281) — xERC20 specification

**Key Reading:**
- [Vitalik: Why the future will be multi-chain but not cross-chain](https://old.reddit.com/r/ethereum/comments/rwojtk/ama_we_are_the_efs_research_team_pt_7_07_january/hrngyk8/) — foundational post on bridge security limits
- [L2Beat Bridge Risk Framework](https://l2beat.com/bridges/summary) — bridge risk comparison dashboard
- [Rekt.news: Bridge hacks](https://rekt.news/) — detailed exploit post-mortems
- [Nomad Bridge Post-Mortem](https://medium.com/nomad-xyz-blog/nomad-bridge-hack-root-cause-analysis-875ad2e5aacd) — official root cause analysis

---

**Navigation:** [← Module 5: MEV Deep Dive](5-mev.md) | [Next: Module 7 — L2-Specific DeFi →](7-l2-defi.md)

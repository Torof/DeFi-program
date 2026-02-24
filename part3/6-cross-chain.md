# Part 3 — Module 6: Cross-Chain & Bridges (~4 days)

> **Prerequisites:** Part 2 — Modules 1 (Token Mechanics), 8 (DeFi Security)

## Overview

Cross-chain bridges are both essential infrastructure and the most attacked category in DeFi — over $2.5B lost to bridge exploits. This module covers bridge architectures, messaging protocols, the security models behind each approach, and how to build cross-chain-aware applications. Understanding bridges is critical for any DeFi developer working on multi-chain protocols.

---

## Day 1: Bridge Architectures

### Why Bridges Exist
- DeFi liquidity is fragmented across chains (Ethereum, Arbitrum, Base, Optimism, Polygon, etc.)
- Users need to move assets between chains
- Protocols want to deploy on multiple chains
- No native cross-chain communication in blockchain architecture

### Architecture 1: Lock-and-Mint
- **How it works:**
  1. User locks tokens in bridge contract on source chain
  2. Bridge verifies the lock
  3. Bridge mints wrapped tokens on destination chain
  4. To return: burn wrapped tokens → unlock originals
- **Examples:** WBTC (centralized custodian), most early bridges
- **Trust:** depends on who verifies the lock (custodian, multisig, validators)
- **Risk:** wrapped tokens are only as good as the bridge — if bridge is compromised, wrapped tokens are worthless
- **Capital efficiency:** locked tokens are idle (can't be used on source chain)

### Architecture 2: Burn-and-Mint
- **How it works:**
  1. Burn tokens on source chain
  2. Mint canonical tokens on destination chain
  3. Requires token issuer cooperation
- **Examples:** USDC CCTP (Circle), native token bridges
- **Trust:** token issuer controls mint authority
- **Advantage:** no wrapped tokens — canonical asset on every chain
- **Limitation:** only works for tokens whose issuer supports it

### Architecture 3: Liquidity Networks
- **How it works:**
  1. User deposits on source chain
  2. Liquidity provider releases native tokens on destination chain
  3. LP is repaid from user's deposit (+ fee)
  4. No synthetic/wrapped tokens — real assets on each chain
- **Examples:** Across Protocol, Stargate (LayerZero), Hop Protocol
- **Trust:** smart contract verification + relayer network
- **Advantage:** fast, native assets, no wrapped risk
- **Limitation:** needs LP capital on each chain, limited by available liquidity

### Architecture 4: Canonical Rollup Bridges
- **Optimistic rollups:** 7-day challenge period for withdrawals
  - Deposits: fast (L1 → L2)
  - Withdrawals: slow (L2 → L1, 7-day delay)
  - Security: full L1 security guarantee
- **ZK rollups:** validity proof verification
  - Withdrawals: faster (hours, once proof is verified)
  - Security: mathematical guarantee
- **Fast exits:** third-party liquidity providers front the withdrawal
  - User pays fee to LP, LP takes the delay risk
  - Across, Hop provide this service

### Comparison Matrix

| Architecture | Speed | Trust | Wrapped? | Capital Efficiency |
|-------------|-------|-------|----------|--------------------|
| Lock-and-Mint | Moderate | Bridge validators | Yes | Low |
| Burn-and-Mint | Moderate | Token issuer | No | High |
| Liquidity Network | Fast | Smart contracts + relayers | No | Moderate |
| Canonical (Optimistic) | Slow (7 days) | L1 security | No | High |
| Canonical (ZK) | Moderate | Math (ZK proofs) | No | High |

---

## Day 2: Messaging Protocols

### Beyond Token Bridges: Arbitrary Messaging
- Token bridges move assets
- Messaging protocols move arbitrary data (function calls, state updates)
- Enables: cross-chain governance, cross-chain lending, synchronized state

### LayerZero
- **Architecture:** Ultra-light node + decentralized verifier network (DVN)
- **Endpoint contracts** on each chain — entry/exit points for messages
- **OApp framework** — build cross-chain apps using standard interface
  - `_lzSend()` — send message to another chain
  - `_lzReceive()` — handle incoming message
- **OFT (Omnichain Fungible Token)** — token standard for native multi-chain tokens
  - Burn on source → mint on destination
  - No wrapped tokens
  - Single canonical token across all chains
- **Security model:**
  - DVN (Decentralized Verifier Network) validates messages
  - Application can configure required DVNs
  - Configurable security per application

### Chainlink CCIP (Cross-Chain Interoperability Protocol)
- **Architecture:** Chainlink oracle network + Risk Management Network
- **Token transfer + arbitrary messaging** in single protocol
- **Risk Management Network** — independent monitoring layer
  - Separate set of nodes that verify message integrity
  - Can pause the system if anomaly detected
- **Rate limiting** — maximum transfer amounts per time window
- **Programmable token transfers** — send tokens + execute function on destination
- **Trust model:** Chainlink's decentralized oracle network + independent risk layer

### Hyperlane
- **Permissionless deployment** — anyone can deploy to new chains
- **Interchain Security Modules (ISMs)** — configurable security per application
  - Multisig ISM, economic ISM, optimistic ISM
  - Application chooses its own security model
- **Mailbox contracts** — send/receive messages
- **Warp Routes** — token transfer using Hyperlane messaging

### Wormhole
- **Guardian network** — 19 guardians, 13/19 multisig threshold
- **VAA (Verifiable Action Approval)** — signed message from guardians
- **Wide chain support** — Ethereum, Solana, Cosmos, Sui, Aptos, etc.
- **NTT (Native Token Transfers)** — canonical token bridging
- **Trust model:** guardian set reputation and stake

### 📖 Code Reading Strategy
1. Start with LayerZero OApp — simplest cross-chain app interface
2. Read OFT — how tokens work across chains
3. Study CCIP — compare the security model with LayerZero
4. Understand message verification: how each protocol proves a message is authentic

---

## Day 3: Bridge Security

### Why Bridges Are the Highest-Risk DeFi Category
- Bridges hold massive TVL as locked collateral
- Cross-chain verification is fundamentally hard
- Bug in verification = unlimited minting of wrapped tokens
- Single point of failure: bridge compromise → all wrapped tokens worthless

### Major Bridge Exploits

**Ronin Bridge ($625M, March 2022)**
- Axie Infinity's bridge to Ethereum
- 5-of-9 validator multisig
- Attacker compromised 5 validator keys (4 Sky Mavis + 1 Axie DAO)
- Drained bridge over multiple transactions
- **Lesson:** multisig key management, validator diversity, monitoring

**Wormhole ($325M, February 2022)**
- Signature verification bypass on Solana side
- Attacker minted 120,000 wETH on Solana without depositing on Ethereum
- Bug in Solana's `verify_signatures` instruction
- **Lesson:** cross-VM verification is complex, bridge-specific auditing needed

**Nomad ($190M, August 2022)**
- Initialization bug: trusted root set to 0x00
- Any message was considered valid (trivially provable)
- "Crowd-looted" — anyone could copy the exploit transaction
- **Lesson:** initialization is critical, one small bug = total compromise

**Harmony Horizon ($100M, June 2022)**
- 2-of-5 multisig controlling the bridge
- Attacker compromised 2 keys
- **Lesson:** low multisig threshold, insufficient decentralization

### Attack Pattern Categories
1. **Validator/guardian compromise** — gain control of verification keys (Ronin, Harmony)
2. **Smart contract bugs** — verification logic errors (Wormhole, Nomad)
3. **Replay attacks** — same message processed multiple times
4. **Message spoofing** — crafting fake cross-chain messages
5. **Race conditions** — timing between chains exploited

### Security Evaluation Framework
- **Trust model:** Who verifies messages? How many parties? What's the threshold?
- **Economic security:** What's at stake for validators? Slashing conditions?
- **Monitoring:** Real-time anomaly detection? Rate limiting?
- **Incident response:** Can the bridge be paused? By whom? How fast?
- **Audit history:** How thoroughly has the bridge been audited?
- **Track record:** Has it survived adversarial conditions?

---

## Day 4: Cross-Chain DeFi Patterns & Build

### Cross-Chain Token Standards
- OFT (LayerZero): burn/mint across chains, single canonical token
- NTT (Wormhole): native token transfers
- xERC20 (ERC-7281): standardized cross-chain token interface
  - Rate-limited minting per bridge
  - Multiple bridges can mint the same token
  - Token issuer controls mint limits per bridge
  - Prevents single bridge compromise from unlimited minting

### Cross-Chain Swaps
- User wants to swap Token A on Chain 1 for Token B on Chain 2
- Bridge + DEX composition: bridge A to Chain 2 → swap A for B on Chain 2
- Or: swap A for B on Chain 1 → bridge B to Chain 2
- Intent-based: user signs intent, solver handles bridging + swapping
- Across Protocol: solver fronts destination tokens, gets repaid from source

### Cross-Chain Lending (Awareness)
- Deposit collateral on Chain A, borrow on Chain B
- Requires: cross-chain message for collateral verification
- Requires: cross-chain liquidation coordination
- Complex: state synchronization, latency, finality differences
- Compound III (Comet) — studying cross-chain proposals

### Message Verification in Solidity
- Receiving and validating cross-chain messages
- Source chain verification: is this message from the expected contract?
- Nonce/sequence tracking: prevent replay
- Payload decoding: ABI decode the cross-chain message

### Build: Cross-Chain Message Receiver
- Implement a contract that receives and validates cross-chain messages
- Mock the messaging layer (simulate LayerZero or CCIP callback)
- Verify source chain and sender
- Decode and execute payload
- Replay protection via nonce tracking
- Test: valid messages, invalid source, replay attempts

---

## 🎯 Module 6 Exercises

**Workspace:** `workspace/src/part3/module6/`

### Exercise 1: Cross-Chain Message Handler
- Build a contract that receives cross-chain messages
- Implement source verification (only accept from known contracts on known chains)
- Nonce-based replay protection
- Decode and dispatch different message types
- Test with mock messaging layer

### Exercise 2: Rate-Limited Bridge Token (xERC20 Pattern)
- Implement a token with rate-limited cross-chain minting
- Multiple bridges can call `mint()` — each with its own rate limit
- Rate limits refresh over time (bucket pattern)
- Test: normal minting, rate limit enforcement, multi-bridge scenario

---

## 💼 Job Market Context

**What DeFi teams expect:**
- Understanding the trade-offs between bridge architectures
- Awareness of major bridge exploits and their root causes
- Ability to evaluate bridge security for protocol integrations
- Familiarity with at least one messaging protocol (LayerZero or CCIP)

**Common interview topics:**
- "Compare lock-and-mint vs liquidity network bridges"
- "What went wrong in the Nomad bridge hack?"
- "How would you design a cross-chain token that's resilient to bridge failure?"
- "What security checks would you implement when receiving a cross-chain message?"

---

## 📚 Resources

### Production Code
- [LayerZero V2](https://github.com/LayerZero-Labs/LayerZero-v2)
- [Chainlink CCIP](https://github.com/smartcontractkit/ccip)
- [Wormhole](https://github.com/wormhole-foundation/wormhole)
- [Across Protocol](https://github.com/across-protocol/contracts)
- [Hyperlane](https://github.com/hyperlane-xyz/hyperlane-monorepo)

### Documentation
- [LayerZero docs](https://docs.layerzero.network/)
- [Chainlink CCIP docs](https://docs.chain.link/ccip)
- [Wormhole docs](https://docs.wormhole.com/)

### Further Reading
- [Vitalik: Cross-chain bridge security](https://old.reddit.com/r/ethereum/comments/rwojtk/ama_we_are_the_efs_research_team_pt_7_07_january/hrngyk8/)
- [L2Beat: Bridge risk framework](https://l2beat.com/)
- [Rekt.news: Bridge hacks collection](https://rekt.news/)
- [ERC-7281: xERC20 standard](https://eips.ethereum.org/EIPS/eip-7281)

---

**Navigation:** [← Module 5: MEV Deep Dive](5-mev.md) | [Part 3 Overview](README.md) | [Next: Module 7 — L2-Specific DeFi →](7-l2-defi.md)

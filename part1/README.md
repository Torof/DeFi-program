# Part 1 — Solidity, EVM & Modern Tooling

**Duration:** ~16 days (3-4 hours/day)
**Prerequisites:** Prior Solidity experience (0.6.x-0.7.x era), familiarity with EVM basics
**Pattern:** Concept → Read production code → Build → Extend

---

## Why Part 1 Exists

You know Solidity. You've written contracts, deployed them, tested them. But the language, the EVM, and the tooling have all evolved significantly since mid-2022. Solidity 0.8.x introduced features that change how production DeFi code is written. The EVM gained new opcodes that protocols like Uniswap V4 depend on. Token approval patterns shifted from raw `approve` toward signature-based flows. Account abstraction went from theory to 40+ million deployed smart accounts. And Foundry replaced Hardhat as the default for serious protocol work.

This part gets you current. Everything here feeds directly into Part 2 — you'll encounter every one of these concepts when reading Uniswap, Aave, and MakerDAO source code.

---

## Sections

| # | Section | Duration | File |
|---|---------|----------|------|
| 1 | [Solidity 0.8.x Modern Features](section1-solidity-modern/solidity-modern.md) | ~2 days | `section1-solidity-modern/` |
| 2 | [EVM-Level Changes (EIP-1153, EIP-4844, EIP-7702)](section2-evm-changes/evm-changes.md) | ~2 days | `section2-evm-changes/` |
| 3 | [Modern Token Approvals (EIP-2612, Permit2)](section3-token-approvals/token-approvals.md) | ~3 days | `section3-token-approvals/` |
| 4 | [Account Abstraction (ERC-4337, EIP-7702, Paymasters)](section4-account-abstraction/account-abstraction.md) | ~3 days | `section4-account-abstraction/` |
| 5 | [Foundry Workflow & Testing (Fuzz, Invariant, Fork)](section5-foundry/foundry.md) | ~2-3 days | `section5-foundry/` |
| 6 | [Proxy Patterns & Upgradeability](section6-proxy-patterns/proxy-patterns.md) | ~1.5-2 days | `section6-proxy-patterns/` |
| 7 | [Deployment & Operations](section7-deployment/deployment.md) | ~0.5 day | `section7-deployment/` |

Each section folder can contain additional files: exercises, links, notes, etc.

---

## Part 1 Checklist

Before moving to Part 2, verify you can:

- [ ] Explain when and why to use `unchecked` blocks
- [ ] Define and use user-defined value types with custom operators
- [ ] Use custom errors in both `revert` and `require` syntax
- [ ] Explain what transient storage is and implement a reentrancy guard using it
- [ ] Describe EIP-4844's impact on L2 DeFi costs
- [ ] Explain why SELFDESTRUCT-based upgrade patterns are dead
- [ ] Describe EIP-7702 and how it relates to ERC-4337
- [ ] Build a contract that accepts EIP-2612 permit signatures
- [ ] Integrate with Permit2 using both SignatureTransfer and AllowanceTransfer
- [ ] Implement EIP-1271 signature verification for smart account compatibility
- [ ] Explain the ERC-4337 flow: UserOp → Bundler → EntryPoint → Smart Account
- [ ] Build a basic paymaster
- [ ] Write fuzz tests with `bound()` for input constraints
- [ ] Write invariant tests with handler contracts
- [ ] Run fork tests against mainnet with specific block pinning
- [ ] Use `forge snapshot` for gas comparison
- [ ] Deploy contracts with Foundry scripts
- [ ] Explain the difference between Transparent Proxy, UUPS, and Beacon patterns
- [ ] Deploy a UUPS-upgradeable contract and perform an upgrade
- [ ] Identify storage layout collisions using `forge inspect`
- [ ] Explain why `initializer` and `_disableInitializers()` are critical for proxy security
- [ ] Write a deployment script that deploys, initializes, and verifies a contract

Once you're confident on all of these, you're ready for Part 2 — and you'll find that every single concept here shows up in the production DeFi code you'll be reading.

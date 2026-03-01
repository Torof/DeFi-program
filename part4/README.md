# Part 4 — EVM Mastery: Yul & Assembly

> **Prerequisites:** Parts 1-3 completed
>
> **Goal:** Go from reading assembly snippets to writing production-grade Yul — understand the machine underneath every DeFi protocol.

## Why This Part Exists

Throughout Parts 1-3, you've encountered assembly in production code: `mulDiv` internals, proxy `delegatecall` forwarding, Solady's gas optimizations, Uniswap's FullMath. You could read it, roughly. Now you'll learn to write it.

Assembly fluency is the single biggest differentiator for senior DeFi roles. Most candidates can write Solidity. Very few understand the machine underneath.

## Module Overview

| Module | Topic | What You'll Learn |
|--------|-------|-------------------|
| 1 | EVM Fundamentals | Stack machine, opcodes, gas model, execution context |
| 2 | Memory & Calldata | mload/mstore, free memory pointer, calldataload, ABI encoding by hand |
| 3 | Storage Deep Dive | sload/sstore, slot computation, mapping/array layout, storage packing |
| 4 | Control Flow & Functions | if/switch/for in Yul, internal functions, function selector dispatch |
| 5 | External Calls | call/staticcall/delegatecall in assembly, returndata handling, error propagation |
| 6 | Gas Optimization Patterns | Why Solady is faster, bitmap tricks, when assembly is worth it vs overkill |
| 7 | Reading Production Assembly | Analyzing Uniswap, OpenZeppelin, Solady — from an audit perspective |
| 8 | Pure Yul Contracts | Object notation, constructor vs runtime, deploying full contracts in Yul |
| 9 | Capstone | Reimplement a core DeFi primitive in Yul |

## Learning Arc

```
Understand the machine (M1-M3)
    → Write assembly (M4-M5)
        → Optimize (M6)
            → Read real code (M7)
                → Build from scratch (M8-M9)
```

## By the End of Part 4

You will be able to:
- Read any inline assembly block in production DeFi code
- Write gas-optimized assembly for performance-critical paths
- Understand why specific opcodes are chosen and their gas implications
- Build and deploy pure Yul contracts
- Analyze assembly from an auditor's perspective
- Present assembly work confidently in interviews

---

**Navigation:** [Previous: Part 3](../part3/README.md)

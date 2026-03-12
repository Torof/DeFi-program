# Deep Dive: ABI Encoding

> **Status:** Planned — outline only.

## Summary

A standalone deep dive into how Solidity encodes and decodes data at the ABI level. Covers the full encoding family, calldata layout, and how to read raw bytes.

## Planned Sections

1. **What is ABI encoding?** — The contract-to-contract communication protocol. How function calls become raw bytes and how return data becomes values again.

2. **Calldata layout** — The 4-byte selector, head/tail encoding, static vs dynamic types, padding rules. Visual byte-by-byte breakdowns.

3. **The `abi.encode*` family** — When and why to use each:
   - `abi.encode` — general-purpose encoding (hashing, storage, cross-chain payloads)
   - `abi.encodePacked` — tightly packed, no padding (hashing, but beware collision risks)
   - `abi.encodeWithSelector` — function call encoding without type safety
   - `abi.encodeWithSignature` — same, from a string signature
   - `abi.encodeCall` — type-safe function call encoding

4. **Decoding** — `abi.decode`, how to decode return data, how to decode revert data (connects to the Errors deep dive).

5. **Selector computation** — `bytes4(keccak256("transfer(address,uint256)"))`, function selector clashes, and why they matter for proxies.

6. **Common patterns and pitfalls** — `encodePacked` collision bugs, dynamic type encoding surprises, nested tuple encoding.

## Exercise (planned)

An ABI encoding toolkit exercise: encode/decode function calls manually, verify against `abi.encodeCall` output, decode raw revert data, and detect selector clashes.

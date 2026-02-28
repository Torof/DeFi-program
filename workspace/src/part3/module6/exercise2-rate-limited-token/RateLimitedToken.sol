// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ============================================================================
// EXERCISE 2: Rate-Limited Bridge Token (xERC20 Pattern)
//
// Implement a cross-chain token where each authorized bridge has an independent
// minting/burning rate limit. If a bridge is compromised, the attacker can only
// mint up to that bridge's daily limit — not unlimited tokens.
//
// This is the ERC-7281 (xERC20) pattern used by tokens like Across, Stargate,
// and others to bound bridge risk.
//
// Concepts exercised:
//   - Token bucket rate limiting algorithm
//   - Per-bridge access control and independent limits
//   - Time-based refill math (capacity regeneration)
//   - Defense-in-depth: bounding blast radius of a bridge compromise
//   - The ERC-7281 standard pattern
//
// Key references:
//   - Module 6 lesson: "Token Standards for Cross-Chain" → xERC20 subsection
//   - Token bucket math: current = min(maxLimit, lastLimit + elapsed * ratePerSecond)
//   - ERC-7281 spec: https://eips.ethereum.org/EIPS/eip-7281
//
// Run: forge test --match-contract RateLimitedTokenTest -vvv
// ============================================================================

error NotOwner();
error NotAuthorizedBridge();
error MintLimitExceeded(uint256 requested, uint256 available);
error BurnLimitExceeded(uint256 requested, uint256 available);

/// @notice ERC20 token with per-bridge rate-limited minting and burning.
/// @dev Pre-built: ERC20 base, state, struct, events.
///      Student implements: setLimits, mint, burn, mintingCurrentLimitOf, burningCurrentLimitOf, _refreshLimit.
contract RateLimitedToken is ERC20 {
    // --- Types ---
    struct BridgeLimit {
        uint256 maxLimit;         // Maximum capacity (bucket size)
        uint256 currentLimit;     // Current available capacity
        uint256 lastRefreshTime;  // Last time the limit was refreshed
        uint256 ratePerSecond;    // Refill rate (tokens per second)
    }

    // --- State ---
    address public immutable owner;

    /// @dev bridge address => minting limit config
    mapping(address => BridgeLimit) public mintingLimits;

    /// @dev bridge address => burning limit config
    mapping(address => BridgeLimit) public burningLimits;

    // --- Events ---
    event BridgeLimitsSet(address indexed bridge, uint256 mintLimit, uint256 burnLimit);
    event BridgeMint(address indexed bridge, address indexed to, uint256 amount);
    event BridgeBurn(address indexed bridge, address indexed from, uint256 amount);

    // --- Modifier (pre-built) ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
    }

    // =============================================================
    //  TODO 1: Implement setLimits
    // =============================================================
    /// @notice Owner configures minting and burning limits for a bridge.
    /// @dev Sets BOTH the minting and burning limits for a bridge.
    ///      The rate per second is derived from the max limit:
    ///        ratePerSecond = maxLimit / 1 days  (refills to full in 24h)
    ///
    ///      When setting limits:
    ///        - Set maxLimit to the provided limit value
    ///        - Set currentLimit to the provided limit value (starts full)
    ///        - Set lastRefreshTime to block.timestamp
    ///        - Set ratePerSecond = maxLimit / 1 days
    ///
    ///      Numeric example (from lesson):
    ///        mintLimit = 1,000,000e18 (1M tokens/day)
    ///        ratePerSecond = 1,000,000e18 / 86,400 = 11.574e18 tokens/sec
    ///
    ///      Emit BridgeLimitsSet event.
    ///
    /// @param bridge The bridge address to configure
    /// @param mintLimit Maximum minting capacity per day
    /// @param burnLimit Maximum burning capacity per day
    function setLimits(address bridge, uint256 mintLimit, uint256 burnLimit) external onlyOwner {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement mint
    // =============================================================
    /// @notice Bridge mints tokens, subject to rate limit.
    /// @dev Steps:
    ///        1. Refresh the minting limit (call _refreshLimit)
    ///        2. Check that the bridge has enough capacity:
    ///           - If currentLimit == 0 AND maxLimit == 0 → revert NotAuthorizedBridge()
    ///           - If amount > currentLimit → revert MintLimitExceeded(amount, currentLimit)
    ///        3. Deduct amount from currentLimit
    ///        4. Mint tokens to the recipient via _mint(to, amount)
    ///        5. Emit BridgeMint event
    ///
    ///      Hint: Call _refreshLimit BEFORE checking the limit — this ensures
    ///      the token bucket has been refilled based on elapsed time.
    ///
    /// @param to Recipient of minted tokens
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement burn
    // =============================================================
    /// @notice Bridge burns tokens, subject to rate limit.
    /// @dev Same pattern as mint but for burning.
    ///
    ///      Steps:
    ///        1. Refresh the burning limit (call _refreshLimit)
    ///        2. Check authorization and capacity (same as mint):
    ///           - If currentLimit == 0 AND maxLimit == 0 → revert NotAuthorizedBridge()
    ///           - If amount > currentLimit → revert BurnLimitExceeded(amount, currentLimit)
    ///        3. Deduct amount from currentLimit
    ///        4. Burn tokens from the sender via _burn(from, amount)
    ///        5. Emit BridgeBurn event
    ///
    /// @param from Address whose tokens will be burned
    /// @param amount Number of tokens to burn
    function burn(address from, uint256 amount) external {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement mintingCurrentLimitOf
    // =============================================================
    /// @notice View the current available minting capacity for a bridge.
    /// @dev Must calculate the refilled amount WITHOUT modifying state.
    ///
    ///      This is the token bucket formula:
    ///        elapsed = block.timestamp - lastRefreshTime
    ///        refilled = currentLimit + (elapsed * ratePerSecond)
    ///        current = min(maxLimit, refilled)
    ///
    ///      This is a VIEW function — do NOT modify storage.
    ///
    /// @param bridge The bridge to check
    /// @return The current available minting capacity
    function mintingCurrentLimitOf(address bridge) external view returns (uint256) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 5: Implement burningCurrentLimitOf
    // =============================================================
    /// @notice View the current available burning capacity for a bridge.
    /// @dev Same formula as mintingCurrentLimitOf but for burning limits.
    ///
    /// @param bridge The bridge to check
    /// @return The current available burning capacity
    function burningCurrentLimitOf(address bridge) external view returns (uint256) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 6: Implement _refreshLimit
    // =============================================================
    /// @notice Refill the token bucket based on elapsed time.
    /// @dev The token bucket algorithm:
    ///
    ///      ┌──────────────────────────────────────────────┐
    ///      │  Token Bucket:                               │
    ///      │                                              │
    ///      │  ████████░░░░░░  (partially full)            │
    ///      │  ← currentLimit →                           │
    ///      │  ←──────── maxLimit ────────→                │
    ///      │                                              │
    ///      │  Every second: bucket fills by ratePerSecond │
    ///      │  Every mint/burn: bucket drains by amount    │
    ///      │  Bucket never exceeds maxLimit               │
    ///      └──────────────────────────────────────────────┘
    ///
    ///      Steps:
    ///        1. Calculate elapsed time since last refresh
    ///        2. Calculate refill: elapsed * ratePerSecond
    ///        3. Add refill to currentLimit
    ///        4. Cap at maxLimit (never exceed bucket size)
    ///        5. Update lastRefreshTime to block.timestamp
    ///
    ///      Hint: Use a simple min() to cap: if (limit.currentLimit > limit.maxLimit)
    ///      then limit.currentLimit = limit.maxLimit
    ///
    /// @param limit The BridgeLimit struct to refresh (storage reference)
    function _refreshLimit(BridgeLimit storage limit) internal {
        // YOUR CODE HERE
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
// EXERCISE: Intent Settlement — EIP-712 Orders & Dutch Auction Decay
//
// Build a simplified intent settlement contract inspired by UniswapX.
// Users sign orders off-chain; solvers fill them on-chain.
//
// This exercises four key concepts:
//
// 1. EIP-712 Structured Signing — typed data hashing for gasless orders
//      typehash → struct hash → domain separator → digest → ECDSA verify
//
// 2. Dutch Auction Decay — price discovery through time decay
//      output = startAmount - (startAmount - endAmount) * elapsed / duration
//
// 3. Settlement Security — replay protection, deadline, min output
//
// 4. Atomic Execution — both sides of the trade succeed or both revert
//
// This combines:
//   - EIP-712 from Part 1 Module 3
//   - Dutch auction pattern from Part 2 Module 6 / 9
//   - The intent paradigm from this module's curriculum
//
// Run: forge test --match-contract IntentSettlementTest -vvv
// ============================================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// --- Custom Errors ---
error InvalidSignature();
error OrderExpired();
error OrderAlreadyFilled();
error InsufficientOutput();

/// @notice Simplified intent settlement with EIP-712 orders and Dutch auction decay.
/// @dev Pre-built: constructor, state, Order struct, constants, DOMAIN_SEPARATOR.
///      Student implements: hashOrder, getDigest, resolveDecay, fill.
contract IntentSettlement {
    // --- Types ---

    struct Order {
        address offerer;        // who is selling
        address inputToken;     // token being sold
        uint256 inputAmount;    // amount being sold
        address outputToken;    // token being bought
        uint256 startAmount;    // Dutch auction start (high output, bad for solver)
        uint256 endAmount;      // Dutch auction end (low output = user's min, good for solver)
        uint256 decayStartTime; // when the Dutch auction begins
        uint256 decayEndTime;   // when the Dutch auction ends (output = endAmount)
        address recipient;      // who receives the output (usually = offerer)
        uint256 nonce;          // replay protection
    }

    // --- Constants ---

    /// @dev EIP-712 typehash for the Order struct.
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address offerer,address inputToken,uint256 inputAmount,"
        "address outputToken,uint256 startAmount,uint256 endAmount,"
        "uint256 decayStartTime,uint256 decayEndTime,address recipient,uint256 nonce)"
    );

    // --- State ---

    /// @dev EIP-712 domain separator (set in constructor, immutable).
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @dev Tracks which nonces have been used per offerer (replay protection).
    mapping(address => mapping(uint256 => bool)) public nonces;

    // --- Constructor ---

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IntentSettlement"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    // =============================================================
    //  TODO 1: Implement hashOrder
    // =============================================================
    /// @notice Hash an Order struct according to EIP-712 rules.
    /// @dev EIP-712 struct hashing:
    ///      hash = keccak256(abi.encode(TYPEHASH, field1, field2, ...))
    ///
    ///      Steps:
    ///        1. Return keccak256(abi.encode(
    ///             ORDER_TYPEHASH,
    ///             order.offerer,
    ///             order.inputToken,
    ///             order.inputAmount,
    ///             order.outputToken,
    ///             order.startAmount,
    ///             order.endAmount,
    ///             order.decayStartTime,
    ///             order.decayEndTime,
    ///             order.recipient,
    ///             order.nonce
    ///           ))
    ///
    ///      Note: All fixed-size types are encoded directly.
    ///            Dynamic types (bytes, string, arrays) would need
    ///            their own keccak256 — but we don't have any here.
    ///
    /// @param order The order to hash
    /// @return structHash The EIP-712 struct hash
    function hashOrder(Order memory order) public pure returns (bytes32 structHash) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement getDigest
    // =============================================================
    /// @notice Create the full EIP-712 digest for signing/verification.
    /// @dev The digest is what gets signed by the user's wallet.
    ///      It combines the domain separator and the struct hash:
    ///
    ///        digest = keccak256("\x19\x01" || domainSeparator || structHash)
    ///
    ///      The "\x19\x01" prefix is specified by EIP-712 to prevent
    ///      collision with other signing schemes (EIP-191, etc.).
    ///
    ///      Steps:
    ///        1. Compute the struct hash via hashOrder(order)
    ///        2. Return keccak256(abi.encodePacked(
    ///             "\x19\x01",
    ///             DOMAIN_SEPARATOR,
    ///             structHash
    ///           ))
    ///
    /// @param order The order to create a digest for
    /// @return digest The EIP-712 digest ready for ECDSA signing
    function getDigest(Order memory order) public view returns (bytes32 digest) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement resolveDecay
    // =============================================================
    /// @notice Calculate the current Dutch auction output at this moment.
    /// @dev Linear interpolation between startAmount and endAmount:
    ///
    ///        Before decayStartTime: return startAmount
    ///        After decayEndTime:    return endAmount
    ///        During decay:
    ///          elapsed  = block.timestamp - decayStartTime
    ///          duration = decayEndTime - decayStartTime
    ///          decay    = (startAmount - endAmount) * elapsed / duration
    ///          output   = startAmount - decay
    ///
    ///      Steps:
    ///        1. If block.timestamp <= order.decayStartTime, return order.startAmount
    ///        2. If block.timestamp >= order.decayEndTime, return order.endAmount
    ///        3. Compute elapsed = block.timestamp - order.decayStartTime
    ///        4. Compute duration = order.decayEndTime - order.decayStartTime
    ///        5. Compute decay = (order.startAmount - order.endAmount) * elapsed / duration
    ///        6. Return order.startAmount - decay
    ///
    ///      Example (from curriculum):
    ///        startAmount = 1950, endAmount = 1900, duration = 90s
    ///        At t=30s: 1950 - 50 * 30/90 = 1933
    ///        At t=45s: 1950 - 50 * 45/90 = 1925
    ///
    /// @param order The order containing decay parameters
    /// @return output The required output amount at the current timestamp
    function resolveDecay(Order memory order) public view returns (uint256 output) {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement fill
    // =============================================================
    /// @notice Fill a signed order. Called by the solver (filler).
    /// @dev This is the settlement function — the trust guarantee.
    ///      No matter what the solver does off-chain, this enforces:
    ///        - The order was signed by the offerer
    ///        - The order hasn't expired or been filled before
    ///        - The solver provides at least the Dutch auction output
    ///        - Both transfers happen atomically
    ///
    ///      Steps:
    ///        1. Compute the digest via getDigest(order)
    ///        2. Recover the signer via ECDSA.recover(digest, signature)
    ///        3. Revert with InvalidSignature if recovered signer != order.offerer
    ///        4. Revert with OrderExpired if block.timestamp > order.decayEndTime
    ///        5. Revert with OrderAlreadyFilled if nonces[offerer][nonce] is true
    ///        6. Mark the nonce as used: nonces[offerer][nonce] = true
    ///        7. Compute the required output via resolveDecay(order)
    ///        8. Revert with InsufficientOutput if fillerAmount < required output
    ///        9. Execute the atomic swap:
    ///           a. Transfer inputAmount of inputToken from offerer to msg.sender (solver)
    ///           b. Transfer fillerAmount of outputToken from msg.sender to recipient
    ///
    ///      Note: Both the offerer and the solver must have approved this contract
    ///            for their respective tokens before this call.
    ///
    /// @param order The signed order to fill
    /// @param signature The offerer's EIP-712 signature (65 bytes: r, s, v)
    /// @param fillerAmount The amount of output token the solver is providing
    function fill(Order calldata order, bytes calldata signature, uint256 fillerAmount) external {
        // YOUR CODE HERE
    }
}

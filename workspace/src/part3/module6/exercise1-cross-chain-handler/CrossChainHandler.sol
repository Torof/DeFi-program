// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
// EXERCISE 1: Cross-Chain Message Handler
//
// Build a contract that receives and validates cross-chain messages with the
// three mandatory security checks: source verification, replay protection,
// and payload dispatch. This is the receive-side pattern that every
// cross-chain application needs — regardless of which messaging protocol
// (LayerZero, CCIP, Hyperlane) you use underneath.
//
// Concepts exercised:
//   - Source chain + sender verification pattern
//   - Nonce/message ID replay protection
//   - ABI encoding/decoding for cross-chain payloads
//   - Message type dispatching
//   - The receive-side security model
//
// Key references:
//   - Module 6 lesson: "Cross-Chain DeFi Patterns" → Pattern 2
//   - Module 6 lesson: "Three security checks every receiver must implement"
//   - LayerZero OApp pattern (_lzReceive) and CCIP ccipReceive()
//
// Run: forge test --match-contract CrossChainHandlerTest -vvv
// ============================================================================

error NotOwner();
error NotMessagingProtocol();
error UntrustedSource(uint32 sourceChain, address sender);
error MessageAlreadyProcessed(bytes32 messageId);
error UnknownMessageType(uint8 msgType);

/// @notice Cross-chain message receiver with source verification and replay protection.
/// @dev Pre-built: constructor, state, enums, events, modifier.
///      Student implements: setTrustedSource, handleMessage, _handleTransfer, _handleGovernance.
contract CrossChainHandler {
    // --- Types ---
    enum MessageType { TRANSFER, GOVERNANCE }

    struct TransferMessage {
        address to;
        uint256 amount;
    }

    struct GovernanceMessage {
        bytes32 actionId;
        bytes data;
    }

    // --- State ---
    address public immutable owner;
    address public immutable messagingProtocol;

    /// @dev chainId => trusted sender address (the contract on the source chain)
    mapping(uint32 => address) public trustedSources;

    /// @dev messageId => whether it has been processed (replay protection)
    mapping(bytes32 => bool) public processedMessages;

    /// @dev Counters for testing/verification
    uint256 public totalTransfers;
    uint256 public totalGovernanceActions;

    /// @dev Last received messages for testing
    TransferMessage public lastTransfer;
    GovernanceMessage public lastGovernance;

    // --- Events ---
    event TrustedSourceSet(uint32 indexed chainId, address source);
    event TransferReceived(uint32 indexed sourceChain, address to, uint256 amount, bytes32 messageId);
    event GovernanceReceived(uint32 indexed sourceChain, bytes32 actionId, bytes32 messageId);

    // --- Modifiers (pre-built) ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyMessagingProtocol() {
        if (msg.sender != messagingProtocol) revert NotMessagingProtocol();
        _;
    }

    constructor(address _messagingProtocol) {
        owner = msg.sender;
        messagingProtocol = _messagingProtocol;
    }

    // =============================================================
    //  TODO 1: Implement setTrustedSource
    // =============================================================
    /// @notice Owner configures a trusted sender for a given source chain.
    /// @dev Only the owner can call this. This establishes the "peer" contract
    ///      on each chain that we trust to send messages.
    ///
    ///      From the lesson:
    ///        trustedSources[chainId] = sourceAddress
    ///        This is how LayerZero peers and CCIP allowlisted senders work.
    ///
    ///      Steps:
    ///        1. Restrict to owner (modifier already applied)
    ///        2. Store the trusted source for the given chain
    ///        3. Emit TrustedSourceSet event
    ///
    /// @param chainId The source chain identifier
    /// @param source The trusted contract address on that chain
    function setTrustedSource(uint32 chainId, address source) external onlyOwner {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 2: Implement handleMessage
    // =============================================================
    /// @notice Receive and validate a cross-chain message.
    /// @dev This implements the three mandatory security checks from the lesson:
    ///
    ///      1. SOURCE VERIFICATION:
    ///         trustedSources[sourceChain] must equal sourceSender.
    ///         If not → revert UntrustedSource(sourceChain, sourceSender)
    ///
    ///      2. REPLAY PROTECTION:
    ///         processedMessages[messageId] must be false.
    ///         If true → revert MessageAlreadyProcessed(messageId)
    ///         Then mark it true.
    ///
    ///      3. DECODE AND DISPATCH:
    ///         The first byte of payload is the MessageType (uint8).
    ///         Remaining bytes are the message data.
    ///         - MessageType.TRANSFER (0) → _handleTransfer(data)
    ///         - MessageType.GOVERNANCE (1) → _handleGovernance(data)
    ///         - Anything else → revert UnknownMessageType(msgType)
    ///
    ///      Hint: Solidity supports calldata slicing:
    ///         uint8 msgType = uint8(payload[0]);
    ///         bytes calldata data = payload[1:];
    ///
    ///      The test encodes payloads as: abi.encodePacked(uint8(type), abi.encode(struct))
    ///
    /// @param sourceChain The chain the message originated from
    /// @param sourceSender The contract that sent the message on the source chain
    /// @param messageId Unique identifier for this message (for replay protection)
    /// @param payload The encoded message (type byte + message data)
    function handleMessage(
        uint32 sourceChain,
        address sourceSender,
        bytes32 messageId,
        bytes calldata payload
    ) external onlyMessagingProtocol {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 3: Implement _handleTransfer
    // =============================================================
    /// @notice Process a cross-chain transfer message.
    /// @dev Decodes the transfer data and updates state.
    ///
    ///      Steps:
    ///        1. Decode the data as (address to, uint256 amount) using abi.decode
    ///        2. Store in lastTransfer for verification
    ///        3. Increment totalTransfers
    ///        4. Emit TransferReceived event
    ///
    ///      In a real protocol, this would mint tokens or release from escrow.
    ///      For the exercise, we just track the decoded data.
    ///
    /// @param sourceChain The source chain (for event)
    /// @param messageId The message ID (for event)
    /// @param data ABI-encoded (address to, uint256 amount)
    function _handleTransfer(uint32 sourceChain, bytes32 messageId, bytes memory data) internal {
        // YOUR CODE HERE
    }

    // =============================================================
    //  TODO 4: Implement _handleGovernance
    // =============================================================
    /// @notice Process a cross-chain governance message.
    /// @dev Decodes the governance data and updates state.
    ///
    ///      Steps:
    ///        1. Decode the data as (bytes32 actionId, bytes data) using abi.decode
    ///        2. Store in lastGovernance for verification
    ///        3. Increment totalGovernanceActions
    ///        4. Emit GovernanceReceived event
    ///
    ///      In a real protocol, this would queue the action in a timelock.
    ///      For the exercise, we just track the decoded data.
    ///
    /// @param sourceChain The source chain (for event)
    /// @param messageId The message ID (for event)
    /// @param data ABI-encoded (bytes32 actionId, bytes actionData)
    function _handleGovernance(uint32 sourceChain, bytes32 messageId, bytes memory data) internal {
        // YOUR CODE HERE
    }
}

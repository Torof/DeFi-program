// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// EXERCISE: EIP-7702 Delegation Target
//
// Build a contract that can serve as an EIP-7702 delegation target for EOAs.
// When an EOA delegates to this contract, it gains smart contract capabilities
// like batching, custom validation, and gas abstraction.
//
// Since Foundry doesn't fully support Type 4 transactions yet, we'll test the
// delegation logic using DELEGATECALL to simulate how the EVM would execute it.
//
// Run: forge test --match-contract EIP7702DelegateTest -vvv
// ============================================================================

// --- Custom Errors ---
error InvalidSignature();
error CallFailed(uint256 index, bytes returnData);
error Unauthorized();

// =============================================================
//  TODO 1: Implement SimpleAccount (EIP-7702 delegation target)
// =============================================================
/// @notice A simple smart account implementation that can be used as an EIP-7702 delegation target.
/// @dev When an EOA delegates to this contract, calls to the EOA execute this code via DELEGATECALL semantics.
contract SimpleAccount {
    /// @dev Storage slot for the owner. Since this runs via delegation, this storage
    ///      lives in the EOA's storage space, not the implementation contract.
    ///      Using a specific slot to avoid collisions.
    bytes32 private constant OWNER_SLOT = keccak256("SimpleAccount.owner");

    /// @notice Initializes the account with an owner.
    /// @dev This should be called once when first delegating to this contract.
    ///      In EIP-7702, the EOA's owner would call this in their first delegated transaction.
    function initialize(address _owner) external {
        // TODO: Implement
        // 1. Check that owner is not already set (prevent re-initialization)
        // 2. Store the owner in OWNER_SLOT using assembly sstore
        // Hint: assembly { sstore(OWNER_SLOT, _owner) }
        revert("Not implemented");
    }

    /// @notice Gets the current owner.
    function owner() public view returns (address _owner) {
        // TODO: Implement
        // Load the owner from OWNER_SLOT using assembly sload
        revert("Not implemented");
    }

    /// @notice Executes a single call.
    /// @dev Can only be called by the owner (in real EIP-7702, the EOA owner would sign the delegation).
    /// @param target The contract to call
    /// @param value The ETH value to send
    /// @param data The calldata
    /// @return returnData The return data from the call
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory returnData) {
        // TODO: Implement
        // 1. Check that msg.sender == owner() (revert Unauthorized() if not)
        // 2. Execute the call: (bool success, bytes memory returnData) = target.call{value: value}(data)
        // 3. If call failed, revert with CallFailed(0, returnData)
        // 4. Return the returnData
        revert("Not implemented");
    }

    /// @notice Executes multiple calls in a single transaction (batching).
    /// @dev This is the key feature that makes delegation useful — EOAs can't batch natively.
    /// @param calls Array of calls to execute
    /// @return results Array of return data from each call
    function executeBatch(Call[] calldata calls) external payable returns (bytes[] memory results) {
        // TODO: Implement
        // 1. Check that msg.sender == owner()
        // 2. Create results array with length = calls.length
        // 3. Loop through calls and execute each one:
        //    (bool success, bytes memory returnData) = calls[i].target.call{value: calls[i].value}(calls[i].data)
        // 4. If any call fails, revert with CallFailed(i, returnData)
        // 5. Store returnData in results[i]
        // 6. Return results
        revert("Not implemented");
    }

    /// @notice Allows the account to receive ETH.
    receive() external payable {}
}

/// @dev Call struct for batch execution.
struct Call {
    address target;
    uint256 value;
    bytes data;
}

// =============================================================
//  TODO 2: Implement EIP1271Account (with signature validation)
// =============================================================
/// @notice Extended account with EIP-1271 signature validation.
/// @dev Demonstrates how delegated EOAs can implement custom validation logic.
contract EIP1271Account {
    bytes32 private constant OWNER_SLOT = keccak256("EIP1271Account.owner");

    // EIP-1271 magic value
    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    function initialize(address _owner) external {
        // TODO: Same as SimpleAccount
        revert("Not implemented");
    }

    function owner() public view returns (address _owner) {
        // TODO: Same as SimpleAccount
        revert("Not implemented");
    }

    /// @notice EIP-1271 signature validation.
    /// @dev This allows contracts to verify signatures "on behalf of" the EOA.
    ///      When the EOA delegates to this contract, it can now sign arbitrary messages.
    /// @param hash The hash to validate
    /// @param signature The signature (65 bytes: r, s, v)
    /// @return magicValue EIP1271_MAGIC_VALUE if valid, 0xffffffff otherwise
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        // TODO: Implement
        // 1. Recover the signer from the signature using ecrecover
        //    Extract r, s, v from signature (bytes 0-31, 32-63, 64)
        // 2. If recovered signer == owner(), return EIP1271_MAGIC_VALUE
        // 3. Otherwise return 0xffffffff
        // Hint: address signer = ecrecover(hash, v, r, s);
        revert("Not implemented");
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory)
    {
        // TODO: Same as SimpleAccount
        revert("Not implemented");
    }

    receive() external payable {}
}

// =============================================================
//  PROVIDED — Helper contracts for testing
// =============================================================

/// @notice Mock ERC20 for testing batch operations.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Mock target contract for testing execute calls.
contract MockTarget {
    uint256 public value;
    address public sender;
    uint256 public msgValue;

    function setValue(uint256 _value) external payable {
        value = _value;
        sender = msg.sender;
        msgValue = msg.value;
    }

    function revertWithMessage() external pure {
        revert("Intentional revert");
    }
}

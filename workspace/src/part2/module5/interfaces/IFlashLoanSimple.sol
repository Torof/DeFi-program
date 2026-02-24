// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal interface for an Aave V3-style flash loan pool.
/// @dev Mirrors the relevant subset of Aave V3's IPool for flash loan operations.
///      See: https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPool.sol
interface IFlashLoanPool {
    /// @notice Execute a flash loan for a single asset.
    /// @param receiverAddress The contract that will receive the tokens and the callback.
    /// @param asset The address of the token to flash-borrow.
    /// @param amount The amount to flash-borrow.
    /// @param params Arbitrary bytes forwarded to the receiver's executeOperation callback.
    /// @param referralCode Aave referral code (pass 0 in most cases).
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /// @notice The flash loan premium rate in basis points.
    /// @return The premium rate (e.g., 5 = 0.05%).
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

/// @notice Interface that flash loan receivers must implement.
/// @dev Mirrors Aave V3's IFlashLoanSimpleReceiver.
///      See: https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol
interface IFlashLoanSimpleReceiver {
    /// @notice Called by the Pool after transferring the flash-loaned tokens.
    /// @dev At this point, your contract holds `amount` tokens. You must ensure
    ///      that `amount + premium` is approved for the Pool to pull when this returns.
    /// @param asset The address of the flash-borrowed token.
    /// @param amount The amount that was flash-borrowed.
    /// @param premium The fee owed on top of the borrowed amount.
    /// @param initiator The address that initiated the flash loan (called flashLoanSimple).
    /// @param params Arbitrary bytes forwarded from the flash loan request.
    /// @return True if the callback executed successfully.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================================
//  Simplified wstETH interface for LST integration exercises.
//
//  In production, you interact with the deployed WstETH contract:
//    Mainnet: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
//
//  wstETH is Lido's non-rebasing wrapper around stETH. Internally,
//  1 wstETH = 1 Lido share. The exchange rate stEthPerToken() grows
//  as beacon chain validators earn rewards.
//
//  This is the ERC-4626 pattern by another name:
//    stEthPerToken()        ≈  convertToAssets(1e18)
//    getStETHByWstETH(amt)  ≈  convertToAssets(amt)
//    getWstETHByStETH(amt)  ≈  convertToShares(amt)
//
//  See: https://docs.lido.fi/contracts/wsteth
//  See: https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
// ============================================================================

interface IWstETH {
    /// @notice Returns the current exchange rate: how many stETH one wstETH is worth.
    /// @dev Derived from: totalPooledEther / totalShares (the Lido global state).
    ///      This value only increases (barring slashing events) as validators earn rewards.
    ///      Returns 18-decimal fixed-point (e.g., 1.19e18 means 1 wstETH = 1.19 stETH).
    function stEthPerToken() external view returns (uint256);

    /// @notice Converts a wstETH amount to stETH equivalent.
    /// @dev wstETHAmount × stEthPerToken / 1e18
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);

    /// @notice Converts a stETH amount to wstETH equivalent.
    /// @dev stETHAmount × 1e18 / stEthPerToken
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256);
}

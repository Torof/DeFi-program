// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWstETH} from "../interfaces/IWstETH.sol";

/// @notice Mock wstETH with a configurable exchange rate for testing.
/// @dev The exchange rate can be updated to simulate:
///      - Normal operation (rate slowly increasing as validators earn rewards)
///      - Time progression (rate jumps to simulate months/years of staking)
///      - Edge cases (rate = 1e18 for fresh deployment, very high rates)
contract MockWstETH is ERC20, IWstETH {
    uint256 private _stEthPerToken;

    constructor(uint256 initialRate) ERC20("Wrapped liquid staked Ether 2.0", "wstETH") {
        _stEthPerToken = initialRate;
    }

    // --- IWstETH implementation ---

    function stEthPerToken() external view override returns (uint256) {
        return _stEthPerToken;
    }

    function getStETHByWstETH(uint256 wstETHAmount) external view override returns (uint256) {
        return wstETHAmount * _stEthPerToken / 1e18;
    }

    function getWstETHByStETH(uint256 stETHAmount) external view override returns (uint256) {
        return stETHAmount * 1e18 / _stEthPerToken;
    }

    // --- Test helpers ---

    /// @notice Set the exchange rate (simulates time passing / rewards accruing).
    function setExchangeRate(uint256 newRate) external {
        _stEthPerToken = newRate;
    }

    /// @notice Mint wstETH to an address (for test setup).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IBalancerVault
/// @notice Minimal subset of the Balancer V2 Vault interface we depend on.
/// @dev    Balancer V2 flash loans are 0-fee at the protocol level on Sepolia
///         (the `getFlashLoanFeePercentage()` parameter sits behind the
///         ProtocolFeesCollector). The adapter quotes the fee live so it
///         keeps working if Balancer turns the fee on.
interface IBalancerVault {
    /// @notice Multi-asset flash loan.
    /// @dev    Vault will call back `receiveFlashLoan` on `recipient` and
    ///         then verify the balance returned is `amount + fee` per asset.
    function flashLoan(address recipient, IERC20[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

/// @title IBalancerProtocolFeesCollector
/// @notice Subset used to quote the flash-loan fee percentage.
interface IBalancerProtocolFeesCollector {
    /// @return The flash-loan fee in 1e18-scaled fraction (e.g. 1e15 = 0.1%).
    function getFlashLoanFeePercentage() external view returns (uint256);
}

/// @title IBalancerV2FlashReceiver
/// @notice Callback the Vault invokes on the recipient of a flash loan.
interface IBalancerV2FlashReceiver {
    /// @dev    On return the Vault expects `amounts[i] + feeAmounts[i]` of
    ///         each token to be back in the Vault (sent by this contract).
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external;
}

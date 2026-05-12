// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFlashLoanProvider
/// @notice Provider-agnostic single-asset flash-loan entrypoint.
/// @dev    Locked Day-1 interface that Persons B, C, D consume via ABI only.
///         Each adapter (Aave V3, Balancer V2) implements this exactly so the
///         caller is provider-agnostic.
///         The caller MUST also implement {IFlashLoanCallback} — the adapter
///         delivers the borrowed funds and a fee quote back to `msg.sender`
///         through that callback inside the same transaction.
interface IFlashLoanProvider {
    /// @notice Borrow `amount` of `asset` for the duration of one tx.
    /// @param  asset  ERC-20 to borrow.
    /// @param  amount Amount to borrow (in the asset's decimals).
    /// @param  data   Opaque payload forwarded to the borrower's callback.
    function flashLoan(address asset, uint256 amount, bytes calldata data) external;
}

/// @title IFlashLoanProviderMulti
/// @notice Extension for providers (Balancer V2) that support multi-asset
///         flash loans in a single call. Single-asset providers (Aave V3
///         `flashLoanSimple`) intentionally do not implement this.
interface IFlashLoanProviderMulti {
    /// @notice Borrow multiple assets atomically.
    /// @param  assets  List of ERC-20s, length must match `amounts`.
    /// @param  amounts Per-asset amounts.
    /// @param  data    Opaque payload forwarded to the borrower's callback.
    function flashLoanMulti(address[] calldata assets, uint256[] calldata amounts, bytes calldata data) external;
}

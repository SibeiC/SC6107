// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFlashLoanCallback
/// @notice Provider-agnostic callback the adapters invoke on the borrower.
/// @dev    Implemented by {FlashLoanReceiverBase}. Business contracts
///         (e.g. ArbitrageExecutor) only override {_executeOperation} /
///         {_executeOperationMulti}.
interface IFlashLoanCallback {
    /// @notice Called by an adapter after it has transferred `amount` of
    ///         `asset` to this contract. The implementer MUST leave at least
    ///         `amount + fee` of `asset` on the adapter (via transfer or
    ///         approval, depending on the adapter) before returning.
    /// @param  asset     Borrowed token.
    /// @param  amount    Borrowed amount.
    /// @param  fee       Fee owed on top of `amount` for this loan.
    /// @param  initiator Account that originally called `flashLoan` on the adapter.
    /// @param  data      Opaque payload forwarded from the original call.
    /// @return success   Must return keccak256("IFlashLoanCallback.onFlashLoan")
    ///                   so the adapter can verify the borrower acknowledged the call.
    function onFlashLoan(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata data)
        external
        returns (bytes32 success);

    /// @notice Multi-asset variant for Balancer V2-style loans.
    /// @return success   Must return keccak256("IFlashLoanCallback.onFlashLoanMulti").
    function onFlashLoanMulti(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        address initiator,
        bytes calldata data
    ) external returns (bytes32 success);
}

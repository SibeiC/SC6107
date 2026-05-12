// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IFlashLoanCallback } from "../interfaces/IFlashLoanCallback.sol";
import { IFlashLoanProvider, IFlashLoanProviderMulti } from "../interfaces/IFlashLoanProvider.sol";

/// @title FlashLoanReceiverBase
/// @notice Provider-agnostic abstract base for any contract that wants to
///         borrow via the Aave V3 / Balancer V2 adapters.
/// @dev    Subclasses override {_executeOperation} (single-asset) and / or
///         {_executeOperationMulti} (multi-asset, Balancer-only).
///
///         Repayment convention: subclasses MUST leave at least
///         `amount + fee` of each borrowed asset in this contract before the
///         callback returns. The base contract then transfers exactly that
///         amount to the adapter (the `msg.sender` of the callback). Anything
///         left over is profit and stays in the contract.
///
///         Trust model: an `owner` adds adapter addresses to a whitelist.
///         The callback rejects calls from any other address.
abstract contract FlashLoanReceiverBase is IFlashLoanCallback, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev EIP-3156-style magic return values; non-zero so a 0-return wrapper
    ///      contract can't pretend to be us.
    bytes32 internal constant CALLBACK_OK = keccak256("IFlashLoanCallback.onFlashLoan");
    bytes32 internal constant CALLBACK_MULTI_OK = keccak256("IFlashLoanCallback.onFlashLoanMulti");

    /// @notice Adapter addresses authorised to call our callback.
    mapping(address adapter => bool trusted) public trustedAdapter;

    event AdapterSet(address indexed adapter, bool trusted);

    error UntrustedAdapter(address caller);
    error WrongInitiator(address initiator);
    error LengthMismatch();
    error IncompleteRepayment(address asset, uint256 owed, uint256 available);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Whitelist (or revoke) an adapter that may invoke our callbacks.
    function setAdapter(address adapter, bool trusted) external onlyOwner {
        trustedAdapter[adapter] = trusted;
        emit AdapterSet(adapter, trusted);
    }

    // ---------------------------------------------------------------------
    // Outbound helpers
    // ---------------------------------------------------------------------

    /// @notice Helper that opens a single-asset flash loan through `provider`.
    /// @dev    `provider` must already be in {trustedAdapter}, otherwise the
    ///         callback will revert with {UntrustedAdapter}.
    function _flashLoan(address provider, address asset, uint256 amount, bytes memory data) internal {
        IFlashLoanProvider(provider).flashLoan(asset, amount, data);
    }

    /// @notice Helper that opens a multi-asset flash loan through `provider`.
    function _flashLoanMulti(
        address provider,
        address[] memory assets,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        IFlashLoanProviderMulti(provider).flashLoanMulti(assets, amounts, data);
    }

    // ---------------------------------------------------------------------
    // Inbound callbacks
    // ---------------------------------------------------------------------

    /// @inheritdoc IFlashLoanCallback
    function onFlashLoan(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata data)
        external
        virtual
        override
        nonReentrant
        returns (bytes32)
    {
        if (!trustedAdapter[msg.sender]) revert UntrustedAdapter(msg.sender);
        if (initiator != address(this)) revert WrongInitiator(initiator);

        _executeOperation(asset, amount, fee, data);

        uint256 owed = amount + fee;
        uint256 bal = IERC20(asset).balanceOf(address(this));
        if (bal < owed) revert IncompleteRepayment(asset, owed, bal);
        IERC20(asset).safeTransfer(msg.sender, owed);

        return CALLBACK_OK;
    }

    /// @inheritdoc IFlashLoanCallback
    function onFlashLoanMulti(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        address initiator,
        bytes calldata data
    ) external virtual override nonReentrant returns (bytes32) {
        if (!trustedAdapter[msg.sender]) revert UntrustedAdapter(msg.sender);
        if (initiator != address(this)) revert WrongInitiator(initiator);
        if (assets.length != amounts.length || assets.length != fees.length) revert LengthMismatch();

        _executeOperationMulti(assets, amounts, fees, data);

        uint256 len = assets.length;
        for (uint256 i; i < len;) {
            uint256 owed = amounts[i] + fees[i];
            uint256 bal = IERC20(assets[i]).balanceOf(address(this));
            if (bal < owed) revert IncompleteRepayment(assets[i], owed, bal);
            IERC20(assets[i]).safeTransfer(msg.sender, owed);
            unchecked { ++i; }
        }

        return CALLBACK_MULTI_OK;
    }

    // ---------------------------------------------------------------------
    // Hooks for subclasses
    // ---------------------------------------------------------------------

    /// @notice Subclass business logic for single-asset loans.
    /// @dev    Must leave `amount + fee` of `asset` on this contract before return.
    function _executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata data) internal virtual;

    /// @notice Subclass business logic for multi-asset loans (Balancer).
    /// @dev    Default does nothing; the post-call balance check in
    ///         {onFlashLoanMulti} will then revert with {IncompleteRepayment}
    ///         because no funds were moved. Subclasses override to opt in.
    function _executeOperationMulti(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        bytes calldata data
    ) internal virtual {
        // assets, amounts, fees, data are unused in the default no-op.
        assets; amounts; fees; data;
    }
}

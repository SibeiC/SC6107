// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IFlashLoanProvider, IFlashLoanProviderMulti } from "../interfaces/IFlashLoanProvider.sol";
import { IFlashLoanCallback } from "../interfaces/IFlashLoanCallback.sol";
import { IBalancerVault, IBalancerV2FlashReceiver } from "../interfaces/IBalancerVault.sol";

/// @title BalancerV2FlashAdapter
/// @notice Wraps the Balancer V2 Vault `flashLoan` (single- and multi-asset)
///         behind {IFlashLoanProvider} / {IFlashLoanProviderMulti}.
/// @dev    Flow (single-asset uses the same machinery, just with length-1 arrays):
///         1. Borrower calls {flashLoan} or {flashLoanMulti}.
///         2. Adapter encodes `(borrower, data)` into `userData` and calls
///            `vault.flashLoan(this, tokens, amounts, userData)`.
///         3. Vault transfers tokens to this adapter and calls
///            {receiveFlashLoan}, which forwards to `borrower.onFlashLoan(Multi)`.
///         4. The borrower returns `amount + fee` of each token to the adapter.
///         5. Adapter transfers `amount + fee` of each token back to the Vault.
///         Balancer's Vault verifies the balance post-call; reverts otherwise.
contract BalancerV2FlashAdapter is
    IFlashLoanProvider,
    IFlashLoanProviderMulti,
    IBalancerV2FlashReceiver,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    IBalancerVault public immutable VAULT;

    bytes32 private constant CALLBACK_OK = keccak256("IFlashLoanCallback.onFlashLoan");
    bytes32 private constant CALLBACK_MULTI_OK = keccak256("IFlashLoanCallback.onFlashLoanMulti");

    event FlashLoanExecuted(address indexed borrower, address indexed asset, uint256 amount, uint256 fee);
    event FlashLoanMultiExecuted(address indexed borrower, uint256 length);

    error NotVault(address caller);
    error LengthMismatch();
    error BadCallbackReturn(bytes32 ret);

    constructor(address vault) {
        require(vault != address(0), "BalancerV2FlashAdapter: vault=0");
        VAULT = IBalancerVault(vault);
    }

    // ---------------------------------------------------------------------
    // Outbound entrypoints (IFlashLoanProvider / IFlashLoanProviderMulti)
    // ---------------------------------------------------------------------

    /// @inheritdoc IFlashLoanProvider
    function flashLoan(address asset, uint256 amount, bytes calldata data) external override nonReentrant {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(asset);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes memory userData = abi.encode(msg.sender, data, /*multi=*/ false);
        VAULT.flashLoan(address(this), tokens, amounts, userData);
    }

    /// @inheritdoc IFlashLoanProviderMulti
    function flashLoanMulti(address[] calldata assets, uint256[] calldata amounts, bytes calldata data)
        external
        override
        nonReentrant
    {
        uint256 len = assets.length;
        if (len != amounts.length) revert LengthMismatch();

        IERC20[] memory tokens = new IERC20[](len);
        uint256[] memory amts = new uint256[](len);
        for (uint256 i; i < len;) {
            tokens[i] = IERC20(assets[i]);
            amts[i] = amounts[i];
            unchecked { ++i; }
        }
        bytes memory userData = abi.encode(msg.sender, data, /*multi=*/ true);
        VAULT.flashLoan(address(this), tokens, amts, userData);
    }

    // ---------------------------------------------------------------------
    // Inbound callback (IBalancerV2FlashReceiver)
    // ---------------------------------------------------------------------

    /// @inheritdoc IBalancerV2FlashReceiver
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external override {
        if (msg.sender != address(VAULT)) revert NotVault(msg.sender);

        (address borrower, bytes memory data, bool multi) = abi.decode(userData, (address, bytes, bool));

        uint256 len = tokens.length;

        // Forward the borrowed funds to the borrower.
        for (uint256 i; i < len;) {
            tokens[i].safeTransfer(borrower, amounts[i]);
            unchecked { ++i; }
        }

        if (multi) {
            address[] memory assetAddrs = new address[](len);
            for (uint256 i; i < len;) {
                assetAddrs[i] = address(tokens[i]);
                unchecked { ++i; }
            }
            bytes32 ret = IFlashLoanCallback(borrower).onFlashLoanMulti(assetAddrs, amounts, feeAmounts, borrower, data);
            if (ret != CALLBACK_MULTI_OK) revert BadCallbackReturn(ret);
            emit FlashLoanMultiExecuted(borrower, len);
        } else {
            // Single-asset path: arrays are length 1 by construction.
            bytes32 ret = IFlashLoanCallback(borrower).onFlashLoan(
                address(tokens[0]), amounts[0], feeAmounts[0], borrower, data
            );
            if (ret != CALLBACK_OK) revert BadCallbackReturn(ret);
            emit FlashLoanExecuted(borrower, address(tokens[0]), amounts[0], feeAmounts[0]);
        }

        // Repay the Vault. Borrower has already sent `amount+fee` to us.
        for (uint256 i; i < len;) {
            tokens[i].safeTransfer(address(VAULT), amounts[i] + feeAmounts[i]);
            unchecked { ++i; }
        }
    }
}

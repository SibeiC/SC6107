// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FlashLoanReceiverBase } from "../../src/base/FlashLoanReceiverBase.sol";

/// @notice Receiver that exercises {FlashLoanReceiverBase} repayment & checks
///         end-to-end. Only `_executeOperation` / `_executeOperationMulti`
///         are overridden, so the base contract's transfer-back and balance
///         verification run unmodified.
contract BaseReceiver is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    enum Mode {
        Normal, // leave amount+fee on the contract before returning
        Shortfall, // burn the fee so the base hits IncompleteRepayment
        ImplementMulti // signal that _executeOperationMulti should also run
    }

    Mode public mode;
    address public sinkToken; // when Shortfall, we send fee to here
    address public sink;

    constructor(address initialOwner) FlashLoanReceiverBase(initialOwner) { }

    function setMode(Mode m, address token, address to) external {
        mode = m;
        sinkToken = token;
        sink = to;
    }

    function startLoan(address provider, address asset, uint256 amount, bytes memory data) external {
        _flashLoan(provider, asset, amount, data);
    }

    function startLoanMulti(
        address provider,
        address[] memory assets,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        _flashLoanMulti(provider, assets, amounts, data);
    }

    function _executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata) internal override {
        if (mode == Mode.Shortfall) {
            // Burn the fee out of our balance so the base check fails.
            IERC20(asset).safeTransfer(sink, fee);
        }
        // Otherwise: do nothing — the borrower already has `amount` of asset
        // in its balance from the adapter, plus we expect the caller of
        // startLoan to have pre-funded the contract with at least `fee`.
        // Suppress unused-var warning.
        amount;
    }

    function _executeOperationMulti(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        bytes calldata
    ) internal override {
        if (mode == Mode.Shortfall) {
            IERC20(assets[0]).safeTransfer(sink, fees[0]);
        }
        // suppress unused-var warning
        assets; amounts; fees;
    }
}

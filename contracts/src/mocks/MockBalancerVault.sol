// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBalancerVault, IBalancerV2FlashReceiver } from "../interfaces/IBalancerVault.sol";

/// @title MockBalancerVault
/// @notice Minimal stand-in for Balancer V2's Vault flash-loan path.
///         Configurable fee (0 by default to match mainnet). Verifies the
///         receiver returned exactly `amount + fee` per asset via balance
///         comparison, same as the real Vault.
contract MockBalancerVault is IBalancerVault {
    using SafeERC20 for IERC20;

    /// @notice Flash-loan fee in 1e18-scaled fraction. Real Vault is 0.
    uint256 public feeBps18; // e.g. 1e15 = 0.1%

    error RepaymentFailed(address token, uint256 owed, uint256 received);

    event FlashLoan(address indexed recipient, uint256 length);

    constructor(uint256 feeBps18_) {
        feeBps18 = feeBps18_;
    }

    function setFee(uint256 newFee18) external {
        feeBps18 = newFee18;
    }

    function flashLoan(address recipient, IERC20[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external
        override
    {
        require(tokens.length == amounts.length, "MockBalancerVault: length mismatch");
        uint256 len = tokens.length;

        uint256[] memory balancesBefore = new uint256[](len);
        uint256[] memory feeAmounts = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            balancesBefore[i] = tokens[i].balanceOf(address(this));
            feeAmounts[i] = (amounts[i] * feeBps18) / 1e18;
            tokens[i].safeTransfer(recipient, amounts[i]);
        }

        IBalancerV2FlashReceiver(recipient).receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        // Verify the recipient returned principal + fee.
        for (uint256 i; i < len; ++i) {
            uint256 balAfter = tokens[i].balanceOf(address(this));
            uint256 owed = balancesBefore[i] + feeAmounts[i];
            if (balAfter < owed) revert RepaymentFailed(address(tokens[i]), owed, balAfter);
        }

        emit FlashLoan(recipient, len);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAaveV3Pool, IAaveV3FlashReceiver } from "../interfaces/IAaveV3Pool.sol";

/// @title MockAaveV3Pool
/// @notice Bare-bones Aave V3 Pool stand-in. Funds itself from any mint
///         the test sends in; on `flashLoanSimple` it transfers principal
///         to the receiver, calls `executeOperation`, then pulls
///         `amount + premium` back via `transferFrom`.
contract MockAaveV3Pool is IAaveV3Pool {
    using SafeERC20 for IERC20;

    uint128 public premiumBps; // basis points, e.g. 5 = 0.05%

    error CallbackFailed();
    error RepaymentFailed();

    event FlashLoanSimple(address indexed receiver, address indexed asset, uint256 amount, uint256 premium);

    constructor(uint128 premiumBps_) {
        premiumBps = premiumBps_;
    }

    function setPremium(uint128 newBps) external {
        premiumBps = newBps;
    }

    function FLASHLOAN_PREMIUM_TOTAL() external view override returns (uint128) {
        return premiumBps;
    }

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 /* referralCode */
    ) external override {
        uint256 premium = (amount * uint256(premiumBps) + 1e4 - 1) / 1e4;
        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IERC20(asset).safeTransfer(receiverAddress, amount);

        bool ok = IAaveV3FlashReceiver(receiverAddress).executeOperation(
            asset, amount, premium, /*initiator=*/ receiverAddress, params
        );
        if (!ok) revert CallbackFailed();

        // Pull back principal + premium.
        IERC20(asset).safeTransferFrom(receiverAddress, address(this), amount + premium);

        uint256 balAfter = IERC20(asset).balanceOf(address(this));
        if (balAfter < balBefore + premium) revert RepaymentFailed();

        emit FlashLoanSimple(receiverAddress, asset, amount, premium);
    }
}

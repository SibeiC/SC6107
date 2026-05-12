// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FlashLoanReceiverBase } from "../../src/base/FlashLoanReceiverBase.sol";

/// @notice Configurable receiver used to drive the adapters in tests.
/// @dev    Behaviours selected via mode flags so a single contract can
///         exercise the happy path, fee-shortfall, bad-return, and nested
///         re-entry branches.
contract TestReceiver is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    enum Mode {
        Repay, // pay back amount+fee (happy path)
        Shortfall, // pay back less than amount+fee
        BadReturn, // override the magic return value
        Reenter // re-enter the same adapter inside the callback
    }

    Mode public mode;
    address public reentryProvider;
    address public reentryAsset;
    uint256 public reentryAmount;
    bytes32 public spoofedReturn;

    event SingleSeen(address asset, uint256 amount, uint256 fee, bytes data);
    event MultiSeen(uint256 len, bytes data);

    constructor(address initialOwner) FlashLoanReceiverBase(initialOwner) { }

    // ---------------------------------------------------------------------
    // Test controls
    // ---------------------------------------------------------------------

    function setMode(Mode m) external {
        mode = m;
    }

    function setReentry(address provider, address asset, uint256 amount) external {
        reentryProvider = provider;
        reentryAsset = asset;
        reentryAmount = amount;
    }

    function setSpoofedReturn(bytes32 r) external {
        spoofedReturn = r;
    }

    /// @notice Helper for tests to open a flash loan from this receiver.
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

    function approveSpend(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    // ---------------------------------------------------------------------
    // Override of the magic return so we can simulate bad-return paths
    // ---------------------------------------------------------------------

    function onFlashLoan(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        // We do NOT chain to the base implementation because we want to
        // simulate misbehaviour. We still respect the trust check.
        if (!trustedAdapter[msg.sender]) revert UntrustedAdapter(msg.sender);
        if (initiator != address(this)) revert WrongInitiator(initiator);

        emit SingleSeen(asset, amount, fee, data);

        if (mode == Mode.Reenter) {
            // Try to start a nested loan on the same adapter; should revert
            // because the adapter is guarded by ReentrancyGuard.
            _flashLoan(reentryProvider, reentryAsset, reentryAmount, "");
        }

        if (mode == Mode.Shortfall) {
            // Pay back only `amount` (skip the fee).
            IERC20(asset).safeTransfer(msg.sender, amount);
        } else if (mode == Mode.BadReturn) {
            // Pay back fully but return a wrong magic value.
            IERC20(asset).safeTransfer(msg.sender, amount + fee);
            return spoofedReturn;
        } else {
            IERC20(asset).safeTransfer(msg.sender, amount + fee);
        }

        return keccak256("IFlashLoanCallback.onFlashLoan");
    }

    function onFlashLoanMulti(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        address initiator,
        bytes calldata data
    ) external override returns (bytes32) {
        if (!trustedAdapter[msg.sender]) revert UntrustedAdapter(msg.sender);
        if (initiator != address(this)) revert WrongInitiator(initiator);

        emit MultiSeen(assets.length, data);

        if (mode == Mode.BadReturn) {
            for (uint256 i; i < assets.length; ++i) {
                IERC20(assets[i]).safeTransfer(msg.sender, amounts[i] + fees[i]);
            }
            return spoofedReturn;
        }

        for (uint256 i; i < assets.length; ++i) {
            uint256 owed = mode == Mode.Shortfall ? amounts[i] : amounts[i] + fees[i];
            IERC20(assets[i]).safeTransfer(msg.sender, owed);
        }
        return keccak256("IFlashLoanCallback.onFlashLoanMulti");
    }

    function _executeOperation(address, uint256, uint256, bytes calldata) internal pure override {
        // Unused: we override the entire `onFlashLoan` above.
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRouter, Route } from "../../src/interfaces/IRouter.sol";

interface IExecutorForReenter {
    function requestArb(
        address provider,
        address asset,
        uint256 amount,
        Route calldata route,
        uint256 minProfit
    ) external;
    function withdraw(address asset, address to, uint256 amount) external;
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @notice Configurable {IRouter} stand-in for unit / invariant tests.
///         Pulls the borrowed asset from the caller, then mints (or
///         transfers, depending on configuration) the configured
///         `amountOut` of the round-trip asset back to the caller — so a
///         single dial controls profit, break-even, and loss outcomes
///         without having to deploy real pools.
contract MockRouter is IRouter {
    using SafeERC20 for IERC20;

    enum Mode {
        Normal,
        RevertMode,
        ReenterRequestArb,
        ReenterWithdraw
    }

    Mode public mode;
    uint256 public amountOut;
    address public reentryAsset;
    uint256 public reentryAmount;
    Route internal _reentryRoute;
    address public reentryProvider;

    function setReturn(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    function setMode(Mode m) external {
        mode = m;
    }

    function setReentry(address provider, address asset, uint256 amount, Route calldata route) external {
        reentryProvider = provider;
        reentryAsset = asset;
        reentryAmount = amount;
        // Copy storage-incompatible calldata route into storage.
        delete _reentryRoute;
        for (uint256 i; i < route.hops.length; ++i) {
            _reentryRoute.hops.push(route.hops[i]);
        }
        _reentryRoute.amountIn = route.amountIn;
        _reentryRoute.minAmountOut = route.minAmountOut;
    }

    /// @dev Returns the route untouched + the configured `amountOut`. Off-chain
    ///      paths don't exercise this in the unit suite but it must exist for
    ///      the interface.
    function bestRoute(address, address, uint256)
        external
        view
        override
        returns (Route memory r, uint256 expectedOut)
    {
        r;
        expectedOut = amountOut;
    }

    function execute(Route calldata r) external override returns (uint256) {
        if (mode == Mode.RevertMode) revert("MockRouter: revert mode");

        // Pull input.
        IERC20(r.hops[0].tokenIn).safeTransferFrom(msg.sender, address(this), r.amountIn);

        if (mode == Mode.ReenterRequestArb) {
            // Try to start a fresh arb from inside the swap — should be
            // blocked by the executor's inherited reentrancy guard.
            IExecutorForReenter(msg.sender).requestArb(
                reentryProvider, reentryAsset, reentryAmount, _reentryRoute, 0
            );
        } else if (mode == Mode.ReenterWithdraw) {
            // Try to pull profit while the callback is still executing —
            // should hit the withdraw nonReentrant.
            IExecutorForReenter(msg.sender).withdraw(reentryAsset, address(this), 1);
        }

        // Mint output to caller. The output token is whatever the last hop
        // declares as `tokenOut`; we expect it to be a {MockERC20} for tests.
        address outToken = r.hops[r.hops.length - 1].tokenOut;
        IMintable(outToken).mint(msg.sender, amountOut);

        return amountOut;
    }
}

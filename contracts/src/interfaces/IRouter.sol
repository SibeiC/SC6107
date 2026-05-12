// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Single leg of a multi-hop trade through a specific DEX adapter.
/// @dev    Three full-width addresses — no packing possible without
///         changing the cross-module struct shape, which §4 locks.
struct Hop {
    address adapter;
    address tokenIn;
    address tokenOut;
}

/// @notice Ordered set of hops plus the input amount and a slippage floor.
/// @dev    Declared at file scope (alongside {Hop}) so consumers
///         (`ArbitrageExecutor`, tests) can import the types without
///         having to import the {IRouter} symbol.
struct Route {
    Hop[] hops;
    uint256 amountIn;
    uint256 minAmountOut;
}

/// @title IRouter
/// @notice Locked Day-1 interface for the DEX routing engine. Person B
///         implements; Person C / Person D consume via ABI only.
/// @dev    Lifted verbatim from Project1_TaskDivision.md §4 — see the
///         note on {IDexAdapter} for why this surface is frozen.
interface IRouter {
    /// @notice Returns the most-profitable route between `tokenIn` and
    ///         `tokenOut` for `amountIn` plus its expected output.
    /// @dev    View-only; intended for off-chain pre-flight by Person D's
    ///         profit simulator.
    function bestRoute(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (Route memory, uint256 expectedOut);

    /// @notice Execute the supplied route end-to-end.
    /// @return amountOut Realised output of the final hop.
    /// @dev    Must pull `r.amountIn` of the first hop's `tokenIn` from
    ///         `msg.sender`. The final output of the last hop is delivered
    ///         to `msg.sender` (the caller — typically `ArbitrageExecutor`).
    function execute(Route calldata r) external returns (uint256 amountOut);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDexAdapter
/// @notice Locked Day-1 interface every DEX adapter (Uniswap V3 wrapper,
///         V2 fork wrappers) implements so the {Router} can treat them
///         uniformly.
/// @dev    Lifted verbatim from Project1_TaskDivision.md §4 — DO NOT
///         change the shape without coordinating across Persons A/B/C/D/E,
///         because every module ABI-couples through this surface.
interface IDexAdapter {
    /// @notice Pure-view quote: how much `tokenOut` you would receive for
    ///         `amountIn` of `tokenIn` on this venue right now.
    /// @dev    Should not have side effects. Off-chain consumers
    ///         (Person D's price-watcher) call this via `eth_call`.
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);

    /// @notice Execute a swap of `amountIn` `tokenIn` for at least
    ///         `minOut` of `tokenOut`, delivering the output to `to`.
    /// @return amountOut The realised `tokenOut` amount.
    /// @dev    Must pull `amountIn` from `msg.sender` (the Router) via
    ///         `transferFrom` and revert if the realised output is below
    ///         `minOut`.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        returns (uint256 amountOut);
}

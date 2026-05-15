// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDexAdapter
 * @notice A unified interface for interacting with different DEX protocols.
 * @dev Wraps V2 and V3 AMMs so the router doesn't need to know the specifics of each protocol.
 */
interface IDexAdapter {
    /**
     * @notice Checks how much of `tokenOut` we can get for a given amount of `tokenIn`.
     * @param tokenIn The token to sell.
     * @param tokenOut The token to buy.
     * @param amountIn The amount of tokenIn to sell.
     * @return The amount of tokenOut expected.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256);

    /**
     * @notice Executes a swap on the underlying DEX.
     * @param tokenIn The token to sell.
     * @param tokenOut The token to buy.
     * @param amountIn The exact amount of tokenIn to sell.
     * @param minOut The minimum amount of tokenOut we are willing to accept (slippage protection).
     * @param to The address that should receive the tokenOut.
     * @return The actual amount of tokenOut received.
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to) external returns (uint256);
}

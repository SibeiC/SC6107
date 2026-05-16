// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Defines a single swap hop through a specific DEX adapter.
 */
struct Hop {
    address adapter;
    address tokenIn;
    address tokenOut;
}

/**
 * @notice Defines a full route, which can be one or multiple hops.
 */
struct Route {
    Hop[] hops;
    uint256 amountIn;
    uint256 minAmountOut;
}

/**
 * @title IRouter
 * @notice Finds the most profitable swap routes and executes them.
 */
interface IRouter {
    /**
     * @notice Simulates routes to find the most profitable path.
     * @param tokenIn The token to start with.
     * @param tokenOut The target token to end up with.
     * @param amountIn The starting input amount.
     * @return route The optimal route struct packed with necessary data.
     * @return expectedOut The expected amount of tokenOut from the best route.
     */
    function bestRoute(address tokenIn, address tokenOut, uint256 amountIn) external returns (Route memory route, uint256 expectedOut);

    /**
     * @notice Executes a pre-calculated route.
     * @param r The route data to execute.
     * @return amountOut The total amount of the final output token received.
     */
    function execute(Route calldata r) external returns (uint256 amountOut);
}

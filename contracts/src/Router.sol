// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IRouter, Route, Hop } from "./interfaces/IRouter.sol";
import { IDexAdapter } from "./interfaces/IDexAdapter.sol";

/**
 * @title Router
 * @notice Central routing engine that queries DEX adapters to find the best arbitrage path.
 */
contract Router is IRouter {
    address[] public adapters;

    /**
     * @notice Registers DEX adapters (like our V2 and V3 adapters) for routing.
     * @param _adapters Array of IDexAdapter addresses.
     */
    constructor(address[] memory _adapters) {
        adapters = _adapters;
    }

    /**
     * @notice Quotes single-hop routes across all registered adapters to find the best return.
     * @dev Currently implements single-hop only for Day 7. Multi-hop coming next.
     */
    function bestRoute(address tokenIn, address tokenOut, uint256 amountIn) external override returns (Route memory route, uint256 expectedOut) {
        uint256 bestOut = 0;
        address bestAdapter = address(0);

        // Iterate through all registered DEX adapters to find the highest quote
        for (uint256 i = 0; i < adapters.length; i++) {
            try IDexAdapter(adapters[i]).getAmountOut(tokenIn, tokenOut, amountIn) returns (uint256 amount) {
                if (amount > bestOut) {
                    bestOut = amount;
                    bestAdapter = adapters[i];
                }
            } catch {
                // Ignore reverting adapters (e.g. no liquidity pool present)
            }
        }

        require(bestAdapter != address(0), "No valid route found");

        // Construct the single-hop route
        Hop[] memory hops = new Hop[](1);
        hops[0] = Hop({
            adapter: bestAdapter,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });

        route = Route({
            hops: hops,
            amountIn: amountIn,
            minAmountOut: bestOut // For quoting purposes, we assume 0 slippage. Execution applies real slippage.
        });

        return (route, bestOut);
    }

    /**
     * @notice Executes the best route calculated. 
     */
    function execute(Route calldata r) external override returns (uint256 amountOut) {
        require(r.hops.length == 1, "Only single hop supported right now");
        
        Hop memory hop = r.hops[0];
        // The router expects the tokens to be sent to it before execute is called
        amountOut = IDexAdapter(hop.adapter).swap(
            hop.tokenIn, 
            hop.tokenOut, 
            r.amountIn, 
            r.minAmountOut, 
            msg.sender
        );
    }
}

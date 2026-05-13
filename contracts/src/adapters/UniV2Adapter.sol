// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IDexAdapter } from "../interfaces/IDexAdapter.sol";
import { IUniswapV2Router } from "../interfaces/IUniswapV2Router.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniV2Adapter
 * @notice Adapter for Uniswap V2 (and V2 forks) covering quote fetching and basic swaps.
 */
contract UniV2Adapter is IDexAdapter {
    IUniswapV2Router public immutable router;

    constructor(address _router) {
        require(_router != address(0), "Invalid router address");
        router = IUniswapV2Router(_router);
    }

    /**
     * @notice Fetch the expected output amount for a predefined swap amount.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view override returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    /**
     * @notice Execute a token swap using the underlying V2 router.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address to
    ) external override returns (uint256) {
        // Approve the router to spend our tokens
        IERC20(tokenIn).approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Perform the swap (no strict deadline used for atomic atomic ops like flash arbitrage)
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            to,
            block.timestamp
        );

        return amounts[1];
    }
}
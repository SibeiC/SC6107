// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IDexAdapter } from "../interfaces/IDexAdapter.sol";
import { IUniswapV3Quoter, IUniswapV3Router } from "../interfaces/IUniswapV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UniV3Adapter
 * @notice Adapter for Uniswap V3 fetching quotes and executing single-hop swaps.
 */
contract UniV3Adapter is IDexAdapter {
    IUniswapV3Router public immutable router;
    IUniswapV3Quoter public immutable quoter;
    
    // We default to the 0.3% fee tier for standard testnet pools
    uint24 public constant DEFAULT_FEE_TIER = 3000;

    constructor(address _router, address _quoter) {
        require(_router != address(0), "Invalid router addr");
        require(_quoter != address(0), "Invalid quoter addr");
        
        router = IUniswapV3Router(_router);
        quoter = IUniswapV3Quoter(_quoter);
    }

    /**
     * @notice Fetch the expected output out of V3 using the Quoter.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external override returns (uint256) {
        // The V3 Quoter is slightly weird—it's not always a pure `view` due to how it simulates swaps.
        // But for our router logic, we just accept the slight gas cost to simulate here.
        return quoter.quoteExactInputSingle(
            tokenIn,
            tokenOut,
            DEFAULT_FEE_TIER,
            amountIn,
            0 // no price limit
        );
    }

    /**
     * @notice Execute a single-hop V3 swap.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address to
    ) external override returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(router), amountIn);

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: DEFAULT_FEE_TIER,
            recipient: to,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = router.exactInputSingle(params);
        return amountOut;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router } from "../../src/interfaces/IUniswapV2Router.sol";

/**
 * @title MockV2Router
 * @notice A fake Uniswap V2 router specifically for local unit tests. Hardcodes a 1:2 exchange rate.
 */
contract MockV2Router is IUniswapV2Router {
    uint256 public constant RATE = 2;

    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure override returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn * RATE;
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external override returns (uint256[] memory amounts) {
        uint256 expectedOut = amountIn * RATE;
        require(expectedOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Take incoming tokens from the caller (the adapter)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        // Dispense the outgoing tokens (requires this contract to be pre-funded)
        IERC20(path[1]).transfer(to, expectedOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = expectedOut;
    }
}
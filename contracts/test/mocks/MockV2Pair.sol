// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";

/**
 * @title MockV2Pair
 * @notice A simulated Uniswap V2 Pair for testing localized reserves and swap math.
 */
contract MockV2Pair is MockERC20 {
    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    address public token0;
    address public token1;

    constructor(address _token0, address _token1) MockERC20("Mock V2 Pair", "UNI-V2", 18) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function sync() external {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
    }
}

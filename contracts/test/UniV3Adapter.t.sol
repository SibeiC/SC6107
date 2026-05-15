// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { UniV3Adapter } from "../src/adapters/UniV3Adapter.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { IUniswapV3Quoter, IUniswapV3Router } from "../src/interfaces/IUniswapV3.sol";

// Minimal mockup of V3 just to verify our adapter packs identical parameters
contract MockV3Router is IUniswapV3Router, IUniswapV3Quoter {
    uint256 public constant RATE = 2; // static 1:2 swap output

    function quoteExactInputSingle(
        address /*tokenIn*/,
        address /*tokenOut*/,
        uint24 /*fee*/,
        uint256 amountIn,
        uint160 /*sqrtPriceLimitX96*/
    ) external pure override returns (uint256 amountOut) {
        return amountIn * RATE;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256 amountOut) {
        amountOut = params.amountIn * RATE;
        require(amountOut >= params.amountOutMinimum, "INSUFFICIENT_OUTPUT_AMOUNT");
        // We skip actual ERC20 transfer calls for time sake; we just want to ensure adapter logic maps input correctly without reverting
    }
}

contract UniV3AdapterTest is Test {
    UniV3Adapter public adapter;
    MockV3Router public mockModule;
    address public tokenA = address(0x111);
    address public tokenB = address(0x222);

    address public user = address(0x1337);

    function setUp() public {
        mockModule = new MockV3Router();
        // Point both Router and Quoter to our shared mock module
        adapter = new UniV3Adapter(address(mockModule), address(mockModule));
    }

    function test_GetAmountOutV3() public {
        uint256 amountIn = 100 * 10**18;
        uint256 expectedOut = adapter.getAmountOut(tokenA, tokenB, amountIn);
        
        assertEq(expectedOut, 200 * 10**18, "Quote did not match V3 mock rate");
    }

    function test_SwapV3Mock() public {
        // Here we just test parameter packaging into exactInputSingle
        vm.mockCall(
            tokenA, 
            abi.encodeWithSelector(0x095ea7b3, address(mockModule), 100 * 10**18), // approve selector
            abi.encode(true)
        );

        uint256 amountIn = 100 * 10**18;
        uint256 minOut = 190 * 10**18;

        uint256 actualOut = adapter.swap(tokenA, tokenB, amountIn, minOut, user);
        assertEq(actualOut, 200 * 10**18, "Swap output mismatched in V3 struct packing");
    }
}
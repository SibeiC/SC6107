// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { UniV2Adapter } from "../src/adapters/UniV2Adapter.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockV2Router } from "./mocks/MockV2Router.sol";

contract UniV2AdapterTest is Test {
    UniV2Adapter public adapter;
    MockV2Router public mockRouter;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public user = address(0x1337);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);
        
        mockRouter = new MockV2Router();
        adapter = new UniV2Adapter(address(mockRouter));

        // Fund the mock router with output tokens to simulate pool liquidity
        tokenB.mint(address(mockRouter), 1_000_000 * 10**18);

        // Fund the test user
        tokenA.mint(user, 10_000 * 10**18);
    }

    function test_GetAmountOut() public view {
        uint256 amountIn = 100 * 10**18;
        uint256 expectedOut = adapter.getAmountOut(address(tokenA), address(tokenB), amountIn);
        
        // MockRouter is strictly set to give 2 tokenB for every 1 tokenA
        assertEq(expectedOut, 200 * 10**18, "Quote did not match mock rate");
    }

    function test_Swap() public {
        uint256 amountIn = 100 * 10**18;
        uint256 minOut = 190 * 10**18;

        vm.startPrank(user);

        // Pre-fund the adapter. In the real system, the flash loan callback would send 
        // the tokens here or to the router before execution.
        tokenA.transfer(address(adapter), amountIn);

        // Execute the swap
        uint256 actualOut = adapter.swap(address(tokenA), address(tokenB), amountIn, minOut, user);
        vm.stopPrank();

        assertEq(actualOut, 200 * 10**18, "Swap output mismatched");
        assertEq(tokenB.balanceOf(user), 200 * 10**18, "User did not receive tokens");
    }
}
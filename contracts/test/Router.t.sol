// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Router } from "../src/Router.sol";
import { Route, Hop } from "../src/interfaces/IRouter.sol";
import { UniV2Adapter } from "../src/adapters/UniV2Adapter.sol";
import { MockV2Router } from "./mocks/MockV2Router.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract RouterSingleHopTest is Test {
    Router public router;
    MockV2Router public mockV2;
    UniV2Adapter public v2Adapter;

    address public tokenA = address(0x111);
    address public tokenB = address(0x222);

    address public user = address(0x1337);

    function setUp() public {
        mockV2 = new MockV2Router();
        v2Adapter = new UniV2Adapter(address(mockV2));

        address[] memory dexes = new address[](1);
        dexes[0] = address(v2Adapter);

        router = new Router(dexes);
    }

    function test_BestRouteSingleHop() public {
        uint256 amountIn = 100 * 10**18;
        
        (Route memory route, uint256 expectedOut) = router.bestRoute(tokenA, tokenB, amountIn);
        
        // Ensure Quoting picks up the 1:2 swap output configured by the local MockV2Router
        assertEq(expectedOut, 200 * 10**18, "Router failed to quote correct amount");

        // Validate struct mapping
        assertEq(route.hops.length, 1, "Should be single hop");
        assertEq(route.hops[0].adapter, address(v2Adapter), "Adapter incorrectly assigned");
        assertEq(route.amountIn, amountIn, "Struct missing input amount");
    }
}

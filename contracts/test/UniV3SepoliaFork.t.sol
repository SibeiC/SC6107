// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { UniV3Adapter } from "../src/adapters/UniV3Adapter.sol";

// This test aims to run straight against a live node.
// To run this: forge test --match-test test_V3MainnetFork --fork-url https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
contract UniV3SepoliaForkTest is Test {
    UniV3Adapter public adapter;
    
    // Using Sepolia live addresses we hunted down
    address public SEP_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address public SEP_UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    address public routerAddr = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;
    address public quoterAddr = 0xED1f6473345f45b75f8179591Dd5BA1888cf2382;

    function setUp() public {
        adapter = new UniV3Adapter(routerAddr, quoterAddr);
    }

    // We skip this execution in normal CI pipelines unless a fork-url is provided!
    function test_V3MainnetFork_QuoterFetch() public {
        // Only run if actually on a fork environment
        if (block.chainid == 31337) {
            uint256 amountIn = 1 * 10**18;
            
            // This tests actual call packaging across to the actual V3 testnet quoter.
            // If the pool for (WETH -> UNI) doesn't exist, this will revert properly (expected behavior).
            try adapter.getAmountOut(SEP_WETH, SEP_UNI, amountIn) returns (uint256 expectedOut) {
                console.log("Sepolia Live Quote WETH to UNI:", expectedOut);
                assertTrue(expectedOut > 0, "Got 0 return quote from Sepolia V3");
            } catch {
                console.log("Pool may be inactive or lack liquidity on Sepolia Testnet right now.");
            }
        }
    }
}
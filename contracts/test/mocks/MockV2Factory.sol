// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MockV2Pair } from "./MockV2Pair.sol";

/**
 * @title MockV2Factory
 * @notice A fake V2 Factory strictly for unit testing. It only creates and tracks pairs.
 */
contract MockV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");

        // Deploy the new mock pair
        MockV2Pair newPair = new MockV2Pair(token0, token1);
        pair = address(newPair);

        // Track it
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // mirror
        allPairs.push(pair);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
}

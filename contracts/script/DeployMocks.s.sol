// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract DeployMocks is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mUSDC (6 decimals)
        MockERC20 mUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        console.log("mUSDC deployed to:", address(mUSDC));

        // Deploy mWETH (18 decimals)
        MockERC20 mWETH = new MockERC20("Mock WETH", "mWETH", 18);
        console.log("mWETH deployed to:", address(mWETH));

        // Deploy mDAI (18 decimals)
        MockERC20 mDAI = new MockERC20("Mock DAI", "mDAI", 18);
        console.log("mDAI deployed to:", address(mDAI));

        // Mint initial supply to deployer for testing
        address deployer = vm.addr(deployerPrivateKey);
        mUSDC.mint(deployer, 1_000_000 * 10**6); // 1M mUSDC
        mWETH.mint(deployer, 1_000 * 10**18);    // 1k mWETH
        mDAI.mint(deployer, 1_000_000 * 10**18); // 1M mDAI

        vm.stopBroadcast();
    }
}

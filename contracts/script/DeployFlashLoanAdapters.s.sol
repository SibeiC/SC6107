// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { AaveV3FlashAdapter } from "../src/adapters/AaveV3FlashAdapter.sol";
import { BalancerV2FlashAdapter } from "../src/adapters/BalancerV2FlashAdapter.sol";

/// @title DeployFlashLoanAdapters
/// @notice Deploys both flash-loan adapters and patches their addresses into
///         the shared `addresses.sepolia.json` so Persons B/C/D/E pick them
///         up automatically.
///
/// @dev    Usage:
///         ```bash
///         export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/<KEY>
///         export PRIVATE_KEY=0x...
///         forge script script/DeployFlashLoanAdapters.s.sol \
///             --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
///         ```
///
///         Sepolia defaults (overridable via env):
///         - AAVE_V3_POOL    = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
///         - BALANCER_VAULT  = 0xBA12222222228d8Ba445958a75a0704d566BF2C8
///
///         The script only touches the `aaveAdapter` and `balancerAdapter`
///         keys; everything else in the JSON is preserved untouched so it is
///         safe to run alongside Persons B/C's deploy scripts.
contract DeployFlashLoanAdapters is Script {
    // Aave V3 Pool on Sepolia. See https://aave.com/docs/resources/addresses.
    address internal constant DEFAULT_AAVE_V3_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    // Balancer V2 Vault — deployed at the same address on every supported network.
    address internal constant DEFAULT_BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /// @dev Relative path from `contracts/` to the shared addresses file.
    string internal constant ADDRESSES_PATH = "../addresses.sepolia.json";

    function run() external returns (AaveV3FlashAdapter aave, BalancerV2FlashAdapter bal) {
        address aavePool = vm.envOr("AAVE_V3_POOL", DEFAULT_AAVE_V3_POOL_SEPOLIA);
        address balVault = vm.envOr("BALANCER_VAULT", DEFAULT_BALANCER_VAULT);
        uint256 pk = vm.envUint("PRIVATE_KEY");

        console.log("Deploying with:");
        console.log("  aave pool   :", aavePool);
        console.log("  balancer vault:", balVault);

        vm.startBroadcast(pk);
        aave = new AaveV3FlashAdapter(aavePool);
        bal = new BalancerV2FlashAdapter(balVault);
        vm.stopBroadcast();

        console.log("AaveV3FlashAdapter     :", address(aave));
        console.log("BalancerV2FlashAdapter :", address(bal));

        _writeAddresses(address(aave), address(bal));
    }

    /// @dev Patches the two keys this module owns. The JSON file must already
    ///      exist with the canonical schema from the task-division spec; the
    ///      repository ships with a placeholder file at the repo root.
    function _writeAddresses(address aaveAdapter, address balancerAdapter) internal {
        vm.writeJson(vm.toString(aaveAdapter), ADDRESSES_PATH, ".aaveAdapter");
        vm.writeJson(vm.toString(balancerAdapter), ADDRESSES_PATH, ".balancerAdapter");
        console.log("Patched addresses.sepolia.json:");
        console.log("  .aaveAdapter      ->", aaveAdapter);
        console.log("  .balancerAdapter  ->", balancerAdapter);
    }
}

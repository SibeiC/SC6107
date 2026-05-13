// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { ArbitrageExecutor } from "../src/executor/ArbitrageExecutor.sol";
import { CommitRevealExecutor } from "../src/executor/CommitRevealExecutor.sol";
import { IRouter } from "../src/interfaces/IRouter.sol";

/// @title DeployArbitrageExecutor
/// @notice Deploys both executors (direct + commit-reveal) and patches
///         their addresses into the shared `addresses.sepolia.json`.
///         Mirrors {DeployFlashLoanAdapters} so contributors only have
///         to learn the convention once.
///
/// @dev    Reads adapter addresses from `addresses.sepolia.json`
///         (allowing env override). The router address may legitimately
///         be `address(0)` at first deploy — Person B's router can ship
///         later and the owner wires it in via `executor.setRouter(...)`.
///
///         Touched keys: `.executor` (= CommitRevealExecutor, canonical
///         per §4) and `.directExecutor` (= ArbitrageExecutor, additive
///         sibling for the rare case the demo wants a no-MEV path).
///         No other JSON keys are written.
contract DeployArbitrageExecutor is Script {
    using stdJson for string;

    string internal constant ADDRESSES_PATH = "../addresses.sepolia.json";
    uint64 internal constant DEFAULT_MIN_REVEAL_DELAY = 1;     // 1-block timelock fallback
    uint64 internal constant DEFAULT_MAX_REVEAL_WINDOW = 256;  // ~50 min on Sepolia

    function run() external returns (ArbitrageExecutor direct, CommitRevealExecutor mev) {
        // --- read addresses from the shared JSON, allow env override
        string memory json = vm.readFile(ADDRESSES_PATH);
        address aaveAdapter = vm.envOr("AAVE_ADAPTER", json.readAddress(".aaveAdapter"));
        address balancerAdapter = vm.envOr("BALANCER_ADAPTER", json.readAddress(".balancerAdapter"));
        address router = vm.envOr("ROUTER", address(0));

        // --- inputs sanity
        require(aaveAdapter != address(0), "DeployArb: aaveAdapter unset (run flash-loan deploy first)");
        require(balancerAdapter != address(0), "DeployArb: balancerAdapter unset (run flash-loan deploy first)");
        if (router == address(0)) {
            console.log("WARNING: router == address(0). Owner must call setRouter() after Person B deploys.");
        }

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(pk);

        console.log("Deploying with:");
        console.log("  owner            :", owner);
        console.log("  aaveAdapter      :", aaveAdapter);
        console.log("  balancerAdapter  :", balancerAdapter);
        console.log("  router           :", router);

        vm.startBroadcast(pk);
        direct = new ArbitrageExecutor(owner, IRouter(router));
        mev = new CommitRevealExecutor(
            owner, IRouter(router), DEFAULT_MIN_REVEAL_DELAY, DEFAULT_MAX_REVEAL_WINDOW
        );

        // Whitelist both flash-loan providers on both executors.
        direct.setAdapter(aaveAdapter, true);
        direct.setAdapter(balancerAdapter, true);
        mev.setAdapter(aaveAdapter, true);
        mev.setAdapter(balancerAdapter, true);
        vm.stopBroadcast();

        console.log("ArbitrageExecutor (direct)   :", address(direct));
        console.log("CommitRevealExecutor (mev)   :", address(mev));

        _writeAddresses(address(mev), address(direct));
    }

    /// @dev Patches the two keys this module owns. Canonical `.executor`
    ///      gets the MEV-protected variant; `.directExecutor` is an
    ///      additive sibling for the rare unprotected path. All other
    ///      keys (router, dex, tokens) are left untouched so the script
    ///      is safe to run alongside Person B's deploy.
    function _writeAddresses(address commitReveal, address direct_) internal {
        vm.writeJson(vm.toString(commitReveal), ADDRESSES_PATH, ".executor");
        vm.writeJson(vm.toString(direct_), ADDRESSES_PATH, ".directExecutor");
        console.log("Patched addresses.sepolia.json:");
        console.log("  .executor        ->", commitReveal);
        console.log("  .directExecutor  ->", direct_);
    }
}

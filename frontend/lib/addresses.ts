import type { AddressBook, DeploymentItem } from "./types";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export function isDeployed(address: string) {
  return Boolean(address) && address !== ZERO_ADDRESS;
}

export function shortAddress(address: string) {
  if (!isDeployed(address)) return "Not deployed";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function getDeploymentItems(addresses: AddressBook): DeploymentItem[] {
  return [
    { label: "Aave V3 adapter", owner: "A", address: addresses.aaveAdapter, status: isDeployed(addresses.aaveAdapter) ? "deployed" : "pending" },
    { label: "Balancer V2 adapter", owner: "A", address: addresses.balancerAdapter, status: isDeployed(addresses.balancerAdapter) ? "deployed" : "pending" },
    { label: "Commit-reveal executor", owner: "C", address: addresses.executor, status: isDeployed(addresses.executor) ? "deployed" : "pending" },
    { label: "Direct executor", owner: "C", address: addresses.directExecutor ?? ZERO_ADDRESS, status: isDeployed(addresses.directExecutor ?? ZERO_ADDRESS) ? "deployed" : "pending" },
    { label: "Router", owner: "B", address: addresses.router, status: isDeployed(addresses.router) ? "deployed" : "pending" },
    { label: "Uniswap V3 venue", owner: "B", address: addresses.dex.uniV3, status: isDeployed(addresses.dex.uniV3) ? "deployed" : "pending" },
    { label: "DEX-A venue", owner: "B", address: addresses.dex.dexA, status: isDeployed(addresses.dex.dexA) ? "deployed" : "pending" },
    { label: "DEX-B venue", owner: "B", address: addresses.dex.dexB, status: isDeployed(addresses.dex.dexB) ? "deployed" : "pending" }
  ];
}

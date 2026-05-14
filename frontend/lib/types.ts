export type HexAddress = `0x${string}`;

export type DeploymentStatus = "deployed" | "pending";

export type ExecutionMode = "commit" | "direct";

export type AddressBook = {
  aaveAdapter: HexAddress;
  balancerAdapter: HexAddress;
  router: HexAddress;
  executor: HexAddress;
  directExecutor?: HexAddress;
  dex: {
    uniV3: HexAddress;
    dexA: HexAddress;
    dexB: HexAddress;
  };
  tokens: {
    mUSDC: HexAddress;
    mWETH: HexAddress;
    mDAI: HexAddress;
  };
};

export type DeploymentItem = {
  label: string;
  address: HexAddress;
  owner: "A" | "B" | "C" | "D" | "E";
  status: DeploymentStatus;
};

export type Hop = {
  adapter: HexAddress;
  tokenIn: HexAddress;
  tokenOut: HexAddress;
};

export type Route = {
  hops: Hop[];
  amountIn: string;
  minAmountOut: string;
};

export type Opportunity = {
  id: string;
  pair: string;
  provider: "Aave V3" | "Balancer V2";
  path: string;
  expectedProfit: string;
  gasEstimate: string;
  netProfit: string;
  confidence: "High" | "Medium" | "Low";
  status: "Simulated" | "Ready" | "Blocked";
  route: Route;
};

export type TxUpdate = {
  hash: string;
  status: "pending" | "confirmed" | "failed";
  label: string;
  ts: string;
};

export type PricePoint = {
  time: string;
  dexA: number;
  dexB: number;
  uniV3: number;
};

export type LiquidationOpportunity = {
  user: HexAddress;
  healthFactor: string;
  debtAsset: string;
  collateralAsset: string;
  status: "watching" | "profitable" | "blocked";
};

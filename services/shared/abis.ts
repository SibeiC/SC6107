// Minimal ABIs — only the functions Person D actually calls.

export const ROUTER_ABI = [
  {
    name: 'bestRoute',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'tokenIn',  type: 'address' },
      { name: 'tokenOut', type: 'address' },
      { name: 'amountIn', type: 'uint256' },
    ],
    outputs: [
      {
        name: 'route',
        type: 'tuple',
        components: [
          {
            name: 'hops',
            type: 'tuple[]',
            components: [
              { name: 'adapter',  type: 'address' },
              { name: 'tokenIn',  type: 'address' },
              { name: 'tokenOut', type: 'address' },
            ],
          },
          { name: 'amountIn',      type: 'uint256' },
          { name: 'minAmountOut',  type: 'uint256' },
        ],
      },
      { name: 'expectedOut', type: 'uint256' },
    ],
  },
] as const;

export const AAVE_POOL_ABI = [
  {
    name: 'getUserAccountData',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [
      { name: 'totalCollateralBase',         type: 'uint256' },
      { name: 'totalDebtBase',               type: 'uint256' },
      { name: 'availableBorrowsBase',        type: 'uint256' },
      { name: 'currentLiquidationThreshold', type: 'uint256' },
      { name: 'ltv',                         type: 'uint256' },
      { name: 'healthFactor',                type: 'uint256' },
    ],
  },
  {
    name: 'liquidationCall',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'collateralAsset', type: 'address' },
      { name: 'debtAsset',       type: 'address' },
      { name: 'user',            type: 'address' },
      { name: 'debtToCover',     type: 'uint256' },
      { name: 'receiveAToken',   type: 'bool'    },
    ],
    outputs: [],
  },
] as const;

// UniV2 pair events (dexA, dexB)
export const UNIV2_PAIR_ABI = [
  {
    name: 'Swap',
    type: 'event',
    inputs: [
      { name: 'sender',     type: 'address', indexed: true  },
      { name: 'amount0In',  type: 'uint256', indexed: false },
      { name: 'amount1In',  type: 'uint256', indexed: false },
      { name: 'amount0Out', type: 'uint256', indexed: false },
      { name: 'amount1Out', type: 'uint256', indexed: false },
      { name: 'to',         type: 'address', indexed: true  },
    ],
  },
  {
    name: 'getReserves',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'reserve0',           type: 'uint112' },
      { name: 'reserve1',           type: 'uint112' },
      { name: 'blockTimestampLast', type: 'uint32'  },
    ],
  },
] as const;

// UniV3 pool events
export const UNIV3_POOL_ABI = [
  {
    name: 'Swap',
    type: 'event',
    inputs: [
      { name: 'sender',       type: 'address', indexed: true  },
      { name: 'recipient',    type: 'address', indexed: true  },
      { name: 'amount0',      type: 'int256',  indexed: false },
      { name: 'amount1',      type: 'int256',  indexed: false },
      { name: 'sqrtPriceX96', type: 'uint160', indexed: false },
      { name: 'liquidity',    type: 'uint128', indexed: false },
      { name: 'tick',         type: 'int24',   indexed: false },
    ],
  },
] as const;

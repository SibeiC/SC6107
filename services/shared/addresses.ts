import { createRequire } from 'module';

const require = createRequire(import.meta.url);

type TokenAddresses = { mUSDC: `0x${string}`; mWETH: `0x${string}`; mDAI: `0x${string}` };
type DexAddresses  = { uniV3: `0x${string}`; dexA: `0x${string}`; dexB: `0x${string}` };

type Addresses = {
  aaveAdapter:     `0x${string}`;
  balancerAdapter: `0x${string}`;
  router:          `0x${string}`;
  executor:        `0x${string}`;
  dex:             DexAddresses;
  tokens:          TokenAddresses;
};

function loadAddresses(): Addresses {
  const raw = require('../../addresses.sepolia.json') as Addresses;
  return raw;
}

export const addresses = loadAddresses();

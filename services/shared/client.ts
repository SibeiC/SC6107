import 'dotenv/config';
import { createPublicClient, createWalletClient, http, type PublicClient, type WalletClient } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

function requireEnv(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing required env var: ${key}`);
  return val;
}

export function makePublicClient(): PublicClient {
  return createPublicClient({
    chain: sepolia,
    transport: http(requireEnv('SEPOLIA_RPC_URL')),
  });
}

export function makeWalletClient(): WalletClient {
  const account = privateKeyToAccount(requireEnv('PRIVATE_KEY') as `0x${string}`);
  return createWalletClient({
    account,
    chain: sepolia,
    transport: http(requireEnv('SEPOLIA_RPC_URL')),
  });
}

// Singletons — import these instead of constructing per-service.
export const publicClient  = makePublicClient();
export const walletClient  = makeWalletClient();

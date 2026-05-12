#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Deploys the Aave V3 and Balancer V2 flash-loan adapters to Sepolia and patches
# `addresses.sepolia.json`. Wraps `forge script` so the contributor never has to
# remember the long invocation.
#
# Usage:
#   cp SC6107/.env.example SC6107/.env   # fill in PRIVATE_KEY + RPC
#   ./SC6107/scripts/deploy-flash-loan.sh           # broadcast
#   ./SC6107/scripts/deploy-flash-loan.sh --dry     # simulate only
# -----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONTRACTS="$ROOT/contracts"

if [[ -f "$ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$ROOT/.env"; set +a
fi

: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL must be set (see .env.example)}"
: "${PRIVATE_KEY:?PRIVATE_KEY must be set (see .env.example)}"

BROADCAST="--broadcast"
if [[ "${1:-}" == "--dry" ]]; then
  BROADCAST=""
fi

cd "$CONTRACTS"
forge script script/DeployFlashLoanAdapters.s.sol \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  $BROADCAST \
  -vvv

echo
echo "Done. addresses.sepolia.json:"
cat "$ROOT/addresses.sepolia.json"

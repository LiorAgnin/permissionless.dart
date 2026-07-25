#!/usr/bin/env bash
#
# Regenerates packages/permissionless/test/fixtures/entry_point_v09_vectors.json
# from the pinned EntryPoint v0.9 Solidity contracts.
#
# Requires Foundry (https://getfoundry.sh) and a checkout of eth-infinitism's
# account-abstraction at the v0.9 release. By default the sibling
# `account-abstraction/` directory in the workspace is used; override with:
#
#   AA_DIR=/path/to/account-abstraction ./generate.sh
#
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${AA_DIR:-}" ]]; then
  # Walk up looking for a sibling account-abstraction checkout.
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/account-abstraction/contracts/core/UserOperationLib.sol" ]]; then
      AA_DIR="$dir/account-abstraction"
      break
    fi
    dir="$(dirname "$dir")"
  done
fi

if [[ -z "${AA_DIR:-}" || ! -f "$AA_DIR/contracts/core/UserOperationLib.sol" ]]; then
  echo "error: could not locate an account-abstraction checkout." >&2
  echo "       set AA_DIR=/path/to/account-abstraction and re-run." >&2
  exit 1
fi

echo "Using EntryPoint contracts from: $AA_DIR"
ln -sfn "$AA_DIR" aa

forge script src/GenVectors.sol:GenVectors

echo "Wrote ../../packages/permissionless/test/fixtures/entry_point_v09_vectors.json"

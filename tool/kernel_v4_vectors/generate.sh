#!/usr/bin/env bash
#
# Regenerates packages/permissionless/test/fixtures/kernel_v4_vectors.json
# from the pinned Kernel v4.0 Solidity contracts.
#
# Requires Foundry (https://getfoundry.sh) and a checkout of zerodevapp/kernel
# at the v4.0 tag with its soldeer dependencies vendored. By default the
# workspace-root `kernel-v4.0/` directory is used; override with:
#
#   KERNEL_DIR=/path/to/kernel-v4.0 ./generate.sh
#
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${KERNEL_DIR:-}" ]]; then
  # Walk up looking for the pinned kernel-v4.0 checkout.
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/kernel-v4.0/src/KernelFactory.sol" ]]; then
      KERNEL_DIR="$dir/kernel-v4.0"
      break
    fi
    dir="$(dirname "$dir")"
  done
fi

if [[ -z "${KERNEL_DIR:-}" || ! -f "$KERNEL_DIR/src/KernelFactory.sol" ]]; then
  echo "error: could not locate a kernel-v4.0 checkout." >&2
  echo "       set KERNEL_DIR=/path/to/kernel-v4.0 and re-run." >&2
  exit 1
fi

echo "Using Kernel v4.0 contracts from: $KERNEL_DIR"
ln -sfn "$KERNEL_DIR" kernel

forge script src/GenKernelV4Vectors.sol:GenKernelV4Vectors

echo "Wrote ../../packages/permissionless/test/fixtures/kernel_v4_vectors.json"

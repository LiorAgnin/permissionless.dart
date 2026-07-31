# Kernel v4.0 reference vectors

Generates `packages/permissionless/test/fixtures/kernel_v4_vectors.json` — the
contract-derived fixture behind the Dart Kernel v4 tests — from the pinned
`zerodevapp/kernel` v4.0 contracts.

`dart test` only reads the committed fixture; nothing here runs in CI or on
developer machines unless the vectors need regenerating.

## What the vectors prove

- **Address cases** — for combinations of signer, `Install[]` packages, and
  deployment nonce: the factory salt, the Solady ERC-1967 clone initcode with
  the signer as immutable args, and the CREATE2 address — both against a
  locally deployed `KernelFactory` (via `getECDSAAddress` / `getAddress`) and
  against the canonical release addresses from `releases/v0.4.0.json`. Also the
  exact `deployECDSA` and `Staker.deployWithFactory` calldata bytes.
- **Root userOp acceptance** — a `KernelImmutableECDSA` account deployed by the
  real factory accepts a raw 65-byte `r‖s‖v` signature over the EntryPoint v0.9
  userOpHash (`validateUserOp` returns 0), rejects a wrong signer (returns 1),
  and fails cleanly (no revert) on the library's stub signature.
- **Execute round-trips** — ERC-7579 single and batch `execute` calldata that
  the deployed account actually executed, for byte-matching the Dart encoders.

## Regenerating

Requires [Foundry](https://getfoundry.sh) and a checkout of zerodevapp/kernel
at the `v4.0` tag with its soldeer dependencies vendored (the workspace-root
`kernel-v4.0/` directory).

```bash
./generate.sh                                # auto-detects ../{...}/kernel-v4.0
KERNEL_DIR=/path/to/kernel-v4.0 ./generate.sh
```

The script symlinks `kernel` → the checkout (gitignored), compiles with the
release toolchain (solc 0.8.33, prague, optimizer 200 runs), and runs
`src/GenKernelV4Vectors.sol`, which asserts every acceptance case on-EVM before
writing the fixture.

## Pinned truth

- Kernel contracts: `zerodevapp/kernel` tag `v4.0` (commit `f2a84a33`).
- EntryPoint v0.9: the `eth-infinitism-account-abstraction-0.9.0` soldeer
  dependency vendored in that checkout; canonical address
  `0x433709009B8330FDa32311DF1C2AFA402eD8D009`.
- Canonical Kernel release addresses: `releases/v0.4.0.json` (CREATE2
  predictions; the release repo records no confirmed on-chain deployments).

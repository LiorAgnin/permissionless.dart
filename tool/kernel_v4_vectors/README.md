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
  exact `deployECDSA`, UUPS `deploy`, and `Staker.deployWithFactory` calldata
  bytes.
- **Root userOp acceptance** — a `KernelImmutableECDSA` account deployed by the
  real factory accepts a raw 65-byte `r‖s‖v` signature over the EntryPoint v0.9
  userOpHash (`validateUserOp` returns 0), rejects a wrong signer (returns 1),
  and fails cleanly (no revert) on the library's stub signature.
- **UUPS root userOp acceptance** — the same three assertions for a
  `KernelUUPS` account deployed via `factory.deploy` with a root ECDSA
  validator as packages[0] (a minimal restatement of the pinned repo's own
  test mock), plus `deploy` landing exactly on `factory.getAddress`.
- **Execute round-trips** — ERC-7579 single and batch `execute` calldata that
  the deployed account actually executed, for byte-matching the Dart encoders.
- **Nonce key packing** — `[1B vMode | 1B vType | 20B vId | 2B nonceKey]`
  keys (and full nonces with a sequence) for root, validator, and permission
  validation types, non-zero parallel nonce keys, and the replayable mode bit
  `0x40` — restating the pinned repo's own `KernelTestBase.encodeNonce`.
- **Validator-routed userOp** — an account with an installed validator module
  (vType `0x01`) accepts the validator owner's raw 65-byte signature, rejects
  the root fallback signer, and fails cleanly on the stub — proving the nonce
  key, not the signature, does the routing.
- **Permission-routed userOp** — an account with a policy + ECDSA-signer
  permission (vType `0x02`, non-zero nonceKey) accepts
  `abi.encode(bytes[])` signatures (policy chunks in install order, signer
  last), rejects a wrong signer or wrong policy chunk, and fails cleanly on
  the stub list.
- **Replayable userOp** — with nonce mode `0x40`, the real Kernel accepts a
  signature over the chain-agnostic (sans-chainId EIP-712) digest and rejects
  one over the standard hash. The fixture hash is cross-checked between a
  restated oracle and the pinned `Lib4337` against etched EntryPoint v0.9
  bytecode.

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

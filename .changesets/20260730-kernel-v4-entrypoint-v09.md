---
title: "Kernel v4.0 + EntryPoint v0.9"
date: "2026-07-30"
packages:
  permissionless: "minor"
---

Adds **EntryPoint v0.9** as a first-class version and **Kernel v4.0** accounts
(UUPS, ImmutableECDSA, Kernel7702) grounded in the Kernel v4.0 contracts and
viem EntryPoint v0.9 packing/hash — not permissionless.js (which has no Kernel
v4 surface yet).

### EntryPoint v0.9
- `EntryPointVersion.v09` and canonical address
  `0x433709009B8330FDa32311DF1C2AFA402eD8D009`
- Shared `getUserOperationHash` / `getUserOperationTypedData` for v0.6–v0.9
- Optional paymaster signature packing
  (`signature ‖ uint16(length) ‖ 0x22e325a297439656`) per contract truth
  (ADR 0001)

### Kernel v4.0
- `createKernelImmutableECDSA`, `createKernelUUPS`, `createKernel7702`
- Offline counterfactual addresses, factory/Staker deploy paths, ERC-7579
  execute encoding
- Nonce-encoded validation (root / validator / permission; standard, enable,
  replayable modes)
- Enable-mode UserOperations and module install/uninstall / setRoot actions
- Permissions (policies + signer under a PermissionId) for session keys
- ERC-1271 / ERC-7739 nested EIP-712 message and typed-data signing
- Kernel7702 EIP-7702 delegation path on EntryPoint v0.9

### Docs and release gates
- ADR 0001 (paymaster-signature framing) and ADR 0002 (parity baseline pins)
- Glossary terms and README account matrix updates
- Integration address cross-checks and funded e2e suite that skip cleanly when
  no public Kernel v4 stack is available (local anvil + release recipe is the
  intended path today)

Correctness is pinned via Foundry-generated vectors in
`tool/kernel_v4_vectors/` and `tool/entry_point_v09_vectors/`.

# ADR 0002 — Kernel v4.0 parity baseline and pins

- **Status:** accepted
- **Date:** 2026-07-30
- **Scope:** Kernel v4.0 account surface, EntryPoint v0.9 shared hashing,
  release address constants

This ADR records why Kernel v4 does not follow permissionless.js, which
oracles define correctness, which contract addresses are pinned, and why
userOpHash is shared. Paymaster-signature framing for EntryPoint v0.9 is
decided in [ADR 0001](./0001-entrypoint-v09-paymaster-signature-framing.md).

## Context

Kernel v4.0 is a new modular account generation (ERC-7579 modules, nonce-encoded
validation mode/type/id, enable-mode installs, permissions, three variants:
UUPS, ImmutableECDSA, Kernel7702). It targets EntryPoint v0.9 exclusively.

permissionless.dart’s historical rule is “match permissionless.js.” That rule
does not apply here: **permissionless.js does not ship Kernel v4.** Treating
the TypeScript package as the baseline would invent a port of something that
does not exist, or freeze the Dart library on older Kernel lines forever.

Correctness therefore needs a different ground truth: the Kernel v4.0 contracts
and the EntryPoint v0.9 packing/hash behavior already established in the
ecosystem (eth-infinitism contracts + current viem).

## Decision

### Parity baseline

| Surface | Baseline | Not the baseline |
| --- | --- | --- |
| Kernel v4.0 account behavior (addresses, factory/salt, nonce layout, signatures, modules, enable mode, permissions, Kernel7702) | Kernel v4.0 contracts, release **v0.4.0** | permissionless.js |
| EntryPoint v0.9 packing, `paymasterAndData`, userOpHash | eth-infinitism EntryPoint v0.9 + **viem 2.44.4** (and later) | Vendored workspace `viem/` if stale; permissionless.js |
| Kernel v0.2.x / v0.3.x | permissionless.js (unchanged) | — |

When a future permissionless.js Kernel v4 lands, a follow-up may add
cross-SDK vectors. That is optional polish, not a blocker for this feature.

### Shared userOpHash

Introduce (and prefer) a shared `getUserOperationHash` /
`getUserOperationTypedData` that branches on EntryPoint version for
v0.6–v0.9. Kernel v4 is the first consumer of the v0.9 path; other accounts
migrate off private hash copies so packing/hash bugs are fixed once.

- EntryPoint v0.9 uses EIP-712 domain name `ERC4337`, version `1`, with primary
  type `PackedUserOperation` (same family as v0.8).
- Paymaster-signature framing in the packed blob follows **ADR 0001** (contract
  truth: wire suffix `sig ‖ uint16(len) ‖ magic`; hash uses `prefix ‖ magic`).
- Safe’s SafeOp digest remains a separate account-specific path; it is not
  replaced by the shared utility.

### Release address pins

**EntryPoint v0.9** (canonical eth-infinitism, same address on all chains):

- `0x433709009B8330FDa32311DF1C2AFA402eD8D009`

**Kernel release v0.4.0** CREATE2 predictions (deterministic deployer
`0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt 0; recorded in release
metadata `releases/v0.4.0.json`). No confirmed public multi-chain deployment
table is assumed; addresses are permissionless and stable where the recipe
has been run. Per-account overrides exist for private or forked deployments.

| Contract | Address |
| --- | --- |
| KernelUUPS | `0xC842fE2aC44046AE3cEf033A16c67a9BC287cbD2` |
| KernelImmutableECDSA | `0x6F0999265B6E1dFbe875F104548b875a99A65d37` |
| KernelFactory | `0xA299A4eFee7BBFb2Ea5668b30218C45fff78356c` |
| Staker | `0x58E2fD56990250b0eE784d15905C9856209226aE` |
| Kernel7702 | `0x36312BA78010247390C6677a59807Fe7878e9B59` |

No library default is pinned for an external ECDSA or WebAuthn **validator
module** address: Kernel v4 release artifacts do not yet publish production
validator deployments for every path. Callers that need an external root
validator supply the module address explicitly. ImmutableECDSA does not
require one (immutable fallback signer in the clone).

## Consequences

- Contributors looking for “the JS Kernel v4 port” will not find one; they
  should read the contracts and this ADR instead of permissionless.js.
- Golden vectors for EntryPoint v0.9 and Kernel v4 are generated from pinned
  contracts (and viem where it agrees) and committed so offline tests do not
  require Foundry.
- Changing a pin is a deliberate release decision: update constants, regenerate
  fixtures, and revise this ADR (or supersede it).
- Existing Kernel v0.2/v0.3 and EntryPoint v0.6–v0.8 behavior remains
  permissionless.js–aligned and non-breaking when v0.9/v4 are added.

## References

- [ADR 0001](./0001-entrypoint-v09-paymaster-signature-framing.md) — EntryPoint
  v0.9 paymaster signature framing
- Kernel v4.0 release metadata (`releases/v0.4.0.json` in the workspace Kernel
  v4.0 tree)
- eth-infinitism `account-abstraction` EntryPoint v0.9
- viem account-abstraction EntryPoint v0.9 (`getUserOperationHash`,
  `toPackedUserOperation`)

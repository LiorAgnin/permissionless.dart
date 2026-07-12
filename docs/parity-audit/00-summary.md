# Parity Audit Summary — permissionless.dart v0.3.0 vs permissionless.js v0.3.5

**Date:** 2026-07-11
**Method:** 15 parallel deep-comparison passes (one per module area; every account type audited separately), each producing a cited report in this directory. High-stakes findings were adversarially re-verified: selectors re-derived with `cast sig`, signature paths cross-executed against viem with identical keys, address tables diffed by hand. Baseline: `dart test -P quick` green (683 tests) before any change.

## Bottom line

The port is **structurally complete** — all 9 account types (incl. EIP-7702 variants), all smart-account and ERC-7579 actions, the Pimlico/Etherspot extensions, and the experimental ERC-20 paymaster exist, and the core byte-level machinery (UserOperation packing, userOpHash for v0.6/v0.7/v0.8, CREATE2/initcode derivation, EntryPoint addresses, MultiSend, ERC-20 state overrides) **mirrors the reference faithfully**. The `signUserOperation` happy path is byte-identical for Safe (v1.4.1), Kernel v0.3.x, Light, Trust, Etherspot, Biconomy, and Simple v0.7.

However, the audit found **7 confirmed runtime-breaking divergences (P0)** and **one systemic bug (P1)** that breaks ERC-1271 `signMessage`/`signTypedData` across nearly every account. Four of the nine account types have no unit tests, and the ERC-7579 tests assert the wrong selector values — which is exactly how the P0 bugs survived a green suite.

## Parity matrix

| Unit | mirrors | diverges | missing | dart-only | Report |
|---|---|---|---|---|---|
| Safe account | 12 | 9 | 9 | 1 | [01-account-safe.md](01-account-safe.md) |
| Kernel account | 15 | 5 | 6 | 3 | [01-account-kernel.md](01-account-kernel.md) |
| Nexus account | 14 | 1 | 3 | 1 | [01-account-nexus.md](01-account-nexus.md) |
| Light account | 7 | 1 | 4 | 1 | [01-account-light.md](01-account-light.md) |
| Simple account | 15 | 5 | 3 | 1 | [01-account-simple.md](01-account-simple.md) |
| Thirdweb account | 9 | 4 | 3 | 0 | [01-account-thirdweb.md](01-account-thirdweb.md) |
| Trust (Barz) account | 10 | 3 | 2 | 0 | [01-account-trust.md](01-account-trust.md) |
| Etherspot account | 11 | 2 | 3 | 0 | [01-account-etherspot.md](01-account-etherspot.md) |
| Biconomy (legacy) account | 18 | 1 | 5 | 1 | [01-account-biconomy.md](01-account-biconomy.md) |
| UserOp types/packing/hashing | 15 | 4 | 3 | 1 | [02-userop-encoding.md](02-userop-encoding.md) |
| Actions (smartAccount + 7579) | 8 | 10 | 0 | 1 | [03-actions.md](03-actions.md) |
| Pimlico/Etherspot clients | 5 | 3 | 0 | 2 | [04a-clients-pimlico-etherspot.md](04a-clients-pimlico-etherspot.md) |
| Core client pipeline | 7 | 6 | 2 | 1 | [04b-clients-core.md](04b-clients-core.md) |
| Utils | 9 | 4 | 2 | 5 | [05-utils.md](05-utils.md) |
| Experimental/errors/types | 12 | 5 | 2 | 2 | [06-experimental-errors-types.md](06-experimental-errors-types.md) |

## P0 — Runtime-breaking, independently verified

1. **Four wrong ERC-7579 selectors** (`lib/src/utils/erc7579.dart:81-93`): `uninstallModule` `0xa4d6f1d2`→should be `0xa71763a8`, `isModuleInstalled` `0x6d61fe70`→`0x112d3a7d` (that value is actually `onInstall(bytes)`), `supportsModule` `0x12d79da3`→`0xf2dc691d`, `accountId` `0x7b60424a`→`0x9cfd7cff`. Uninstall calldata reverts; queries silently return `false`/`''`. Tests lock in the wrong values (`test/utils/erc7579_test.dart:327-343`). *Verified with `cast sig`; found independently by two audit passes.* → Ticket 001
2. **Kernel v0.2.4 execute/executeBatch use SimpleAccount selectors** (`accounts/kernel/constants.dart:132,135`): `0xb61d27f6`/`0x47e1da2a` instead of Kernel v2's `0x51945447`/`0x34fcd5be`; parameter bodies don't match either. Every v0.2.4 call reverts. *Verified with `cast sig`.* → Ticket 002
3. **Nexus `signUserOperation` prepends the K1 validator address** (85 bytes, `accounts/nexus/nexus_account.dart:264-275`); JS returns the bare 65-byte signature (`toNexusSmartAccount.ts:346-348`). Nexus selects the validator via the nonce key and forwards the signature untouched → AA24 on-chain. *Verified by reading both sides.* → Ticket 003
4. **Thirdweb salt encoding**: JS UTF-8-encodes the salt string (`toThirdwebSmartAccount.ts:144,159`); Dart hex-decodes it (`thirdweb_account.dart:173-174`) → different factoryData and **different counterfactual addresses** for any non-default salt. → Ticket 004
5. **Three broken Pimlico client actions** (`clients/pimlico/pimlico_client.dart`): `validateSponsorshipPolicies` sends `pimlico_validateSponsorshipPolicies` instead of `pm_validateSponsorshipPolicies` (:286-309); `estimateErc20PaymasterCost` calls a nonexistent RPC method instead of computing locally (:239-255); `sendCompressedUserOperation` sends 4 params in the wrong shape vs the API's 3 (:?). → Ticket 005
6. **Safe v1.5.0 `MULTI_SEND_CALL_ONLY` address wrong** (`accounts/safe/constants.dart:196`): `0x0c28E9886f79618371c5Af86aA7e5Cf62dddd8dC` vs reference `0xA83c336B20401Af773B6219BA5027174338D1836`. *Verified by diffing both tables; all other v1.5.0 addresses match.* → Ticket 006
7. **Simple account v0.6 `executeBatch` emits the v0.7 selector** `0x47e1da2a` (3 arrays) instead of v0.6's `0x18dfb3c7` (`address[],bytes[]`); v0.8 non-7702 batching and signing also follow v0.7 shapes instead of the v0.8 forms. → Ticket 007

## P1 — Systemic

8. **ERC-1271 `signMessage`/`signTypedData` broken across accounts** — one root cause, many sites: Dart computes the account's EIP-712 wrapper digest and then signs it via `signPersonalMessage`, adding a second EIP-191 prefix (Light :392, Thirdweb :334-349, Trust :353-355, Etherspot :423-446, Biconomy :354-358 double-prefix variant), Kernel skips the wrap + validator prefix entirely (:655-690), and Safe omits the whole SafeMessage wrapper + eth_sign V adjustment (:865-911). Cross-executed byte-for-byte against viem for Trust and Etherspot: outputs differ; on-chain `isValidSignature` fails. The 7702 Kernel class does it correctly and Nexus's ERC-7739 path mirrors — proof the right pattern exists in-repo. → Ticket 008
9. **EP v0.6 signing configured-but-unimplemented** in Light, Thirdweb, Simple (accounts accept `v06` config, derive v0.6 addresses, then throw or mis-pack at signing); Safe has the v0.6 address table but signs SafeOp v0.7-only. → Ticket 009
10. **Missing library-wide vs JS**: `decodeCalls`, `sign({hash})`, configurable `nonceKey`, EntryPoint address override. → Ticket 014
11. **No unit tests** for Biconomy, Nexus, Thirdweb, Trust — precisely where P0/P1 bugs hid. → Ticket 012

## P2 — Behavioral divergences (see unit reports)

- `revertOnError` execution-mode bit inverted (`utils/erc7579.dart:202`) → Ticket 010
- `writeContract`'s hand-rolled ABI encoder mis-encodes dynamic `bytes`, lacks strings/arrays/tuples (`actions/smart_account/smart_account_actions.dart:122-338`) → Ticket 011
- Client pipeline semantics: no partial-override merge, always re-estimates gas, `waitForUserOperationReceipt` returns null on timeout (viem throws), paymaster RPC param arity, revert-decoding `getSenderAddress`, no fee-estimation middleware hook → Ticket 013
- Kernel: default version 0.3.1 vs JS 0.3.0-beta (different counterfactual addresses), missing versions/`useMetaFactory`/migration path, ECDSA signUserOperation signs raw hash where JS EIP-191-wraps → Ticket 015
- Safe: default threshold 1 vs owners.length (different multi-owner addresses), batches via MultiSend-delegatecall vs MultiSendCallOnly, divergent stub signatures, hardcoded proxy creation code, missing setup params/7579-v1.5.0 guard → Ticket 016
- passkeyServer actions/client not ported (the `permissionless_passkeys` package is client-side only) → Ticket 017
- Misc edges: sendTransaction returns userOpHash on timeout instead of throwing; EIP-5792 status edge handling; shallow AA## error mapping; EIP-712 edge cases (custom domain type, `codeUnits` vs UTF-8); ERC-20 paymaster extra round-trip + API shape → Ticket 018
- Stale root `CLAUDE.md` (wrong directory names/layout for this workspace) → Ticket 019

## Notes on "mirrors" confidence

Several agents validated mirrors claims by *execution*, not inspection: Trust and Etherspot cross-executed every byte-producing path against viem with identical inputs; Safe verified CREATE2 math against JS-0.3.5-generated test vectors; Biconomy diffed proxy creation code byte-identical and re-derived all selectors. UserOp packing/hashing was verified against viem's `getUserOperationHash` for all three EP versions.

## Gap tickets

Agent-ready tickets live in `.scratch/parity-audit/issues/` (this repo), numbered 001–019 with priorities and blocking edges. Work P0s first; ticket 012 (tests) is blocked by the fixes it must not lock out.

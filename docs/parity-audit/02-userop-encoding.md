# Parity Audit 02 — UserOperation Core Types, Packing, Hashing & Serialization

**Reference:** permissionless.js v0.3.5 (`permissionless.js/packages/permissionless`) + viem account-abstraction utils (`viem/src/account-abstraction`)
**Port:** permissionless.dart v0.3.0 (`permissionless.dart/packages/permissionless`)

## Scope

UserOperation v0.6 / v0.7 field sets, the `PackedUserOperation` layout (`accountGasLimits`, `gasFees`,
`initCode`, `paymasterAndData`), `userOpHash` computation per EntryPoint version, JSON-RPC hex serialization
rules (deepHexlify / formatUserOperationRequest parity), and EntryPoint address constants.

Note on structure: permissionless.js/viem expose **one** shared `getUserOperationHash` (viem
`account-abstraction/utils/userOperation/getUserOperationHash.ts`) that branches on EP version. The Dart port
has **no shared hash function** — every account re-implements `_computeUserOpHash` / `_packUserOp` inline.
Byte layouts below were verified against the actual Dart packing code in each account plus the shared
`packed_user_operation.dart`, not against names.

## Verdict Table

| # | Aspect | Verdict | JS/viem | Dart |
|---|--------|---------|---------|------|
| 1 | `getPackedUserOperation` top-level (v0.7) | **mirrors** | `utils/getPackedUserOperation.ts:108` | `utils/packed_user_operation.dart:99` |
| 2 | `initCode` = factory ‖ factoryData | **mirrors** | `getPackedUserOperation.ts:7` | `packed_user_operation.dart:123` |
| 3 | `accountGasLimits` = verificationGasLimit(16) ‖ callGasLimit(16) | **mirrors** | `getPackedUserOperation.ts:29` | `packed_user_operation.dart:142` |
| 4 | `gasFees` = maxPriorityFee(16) ‖ maxFee(16) | **mirrors** | `getPackedUserOperation.ts:47` | `packed_user_operation.dart:155` |
| 5 | `paymasterAndData` = paymaster(20) ‖ pmVerGas(16) ‖ pmPostOpGas(16) ‖ pmData | **mirrors** | `getPackedUserOperation.ts:63` | `packed_user_operation.dart:171` |
| 6 | Unpack helpers (initCode/gasLimits/gasFees/paymaster) | **mirrors** | `getPackedUserOperation.ts:16,40,56,91` | `packed_user_operation.dart:220,262,301,348` |
| 7 | v0.6 field set (initCode, paymasterAndData, split gas) | **mirrors** | viem `types/userOperation.ts:210` | `types/user_operation.dart:111` |
| 8 | v0.7 field set (factory/factoryData, split paymaster fields) | **mirrors** | viem `types/userOperation.ts:99` | `types/user_operation.dart:247` |
| 9 | v0.6 userOpHash (10-field abi.encode + keccak, then EP+chainId) | **mirrors** | `getUserOperationHash.ts:54` | `biconomy_account.dart:382`, `kernel_account.dart:616`, `trust_account.dart:359` |
| 10 | v0.7 userOpHash (8-field packed abi.encode + keccak, then EP+chainId) | **mirrors** | `getUserOperationHash.ts:90` | `simple_account.dart:355`, `kernel_account.dart:692`, others |
| 11 | v0.8 userOpHash (EIP-712 typed data, `ERC4337` domain) | **mirrors** | `getUserOperationHash.ts:44` + `getUserOperationTypedData.ts` | `eip7702_simple_account.dart:431` |
| 12 | EntryPoint v0.6 / v0.7 addresses | **mirrors** | viem `constants/address.ts:1,3` | `constants/entry_point.dart:14,21` |
| 13 | EntryPoint v0.8 address | **mirrors** (case only) | viem `constants/address.ts:5` | `constants/entry_point.dart:27` |
| 14 | JSON-RPC quantity encoding (minimal hex) | **mirrors** | viem `numberToHex` / `deepHexlify.ts:17` | `hex.dart:82` (`fromBigInt`) |
| 15 | v0.7 optional paymaster/factory fields omitted when null | **mirrors** | `formatUserOperationRequest.ts:20` | `user_operation.dart:380` |
| 16 | EntryPoint v0.9 support | **missing** | viem `constants/address.ts:7`, `getUserOperationHash.ts:44` | absent |
| 17 | `0x7702` factory sentinel in `getInitCode` | **missing** | viem `getInitCode.ts:10` | `packed_user_operation.dart:123` / per-account packers |
| 18 | `paymasterSignature` append in packed `paymasterAndData` (v0.9) | **missing** | viem `toPackedUserOperation.ts:50` | absent |
| 19 | Shared `getUserOperationHash` util | **diverges** | single `getUserOperationHash.ts` | duplicated per-account, no shared util |
| 20 | Pad/quantity overflow guard (size exceeded) | **diverges** | viem `pad` throws `SizeExceedsPaddingSizeError` | `hex.dart:41` silently returns oversize |
| 21 | Address casing in RPC output | **diverges** (cosmetic) | viem emits EIP-55 checksummed | Dart emits lowercase (`address.dart:15`) |
| 22 | `AbiEncoder.encodeUint128` naming vs behavior | **dart-only** (mislabel, correct output) | n/a | `encoding.dart:21` |

**Counts:** mirrors 15, diverges 4, missing 3, dart-only 1.

---

## Finding 16 — EntryPoint v0.9 not supported (missing)

viem defines `entryPoint09Address` (`viem/src/account-abstraction/constants/address.ts:7`) and
`getUserOperationHash` routes both `'0.8'` and `'0.9'` through the EIP-712 typed-data path
(`getUserOperationHash.ts:44`). The Dart `EntryPointVersion` enum stops at `v08`
(`types/user_operation.dart:14-32`) and `EntryPointAddresses` has no v0.9 entry
(`constants/entry_point.dart:8-37`).

Impact: **low for this reference version.** permissionless.js v0.3.5 itself uses no `"0.9"` string in its
non-test source (grep over `packages/permissionless` returns nothing); v0.9 exists only in the underlying
viem. So this is a viem-level capability the Dart port has not pulled forward, not a v0.3.5 feature gap.

## Finding 17 — `0x7702` factory sentinel not handled in initCode packing (missing)

viem's `getInitCode` treats a factory value of `0x7702` (or the padded
`0x7702000000000000000000000000000000000000`) specially: it substitutes the EIP-7702 authorization's
delegation address, or emits the sentinel unchanged when no authorization is present
(`viem/src/account-abstraction/utils/userOperation/getInitCode.ts:10-21`).

The Dart packers — both the shared `getInitCode` (`packed_user_operation.dart:123-131`) and every
per-account `_packUserOp` (e.g. `kernel_account.dart:709`, `simple_account.dart:373`) — implement only the
plain branch:

```dart
if (userOperation.factory == null) return '0x';
return Hex.concat([userOperation.factory!.hex, userOperation.factoryData ?? '0x']);
```

Impact: **low.** The Dart EIP-7702 accounts (`eip7702_simple_account.dart`, `eip7702_kernel_account.dart`)
never set `factory` to the sentinel — they return a `null` factory (`eip7702_simple_account.dart:230-233`)
and sign via EntryPoint v0.8 EIP-712 typed data, which does not route through the sentinel logic. So no
current Dart code path needs it. It only diverges if a caller manually constructs a UserOperation with
`factory = 0x7702`, which the port never does.

## Finding 18 — `paymasterSignature` not appended to packed `paymasterAndData` (missing)

viem's `toPackedUserOperation` appends an optional `paymasterSignature` after `paymasterData` inside
`paymasterAndData` (`viem/src/account-abstraction/utils/userOperation/toPackedUserOperation.ts:50`). Neither
the Dart `UserOperationV07` type (`types/user_operation.dart:247`) nor `getPaymasterAndData`
(`packed_user_operation.dart:171`) has a `paymasterSignature` field/branch.

Impact: **low.** `paymasterSignature` is a v0.9-only concern; permissionless.js v0.3.5's own
`getPackedUserOperation.ts` (the direct reference for this scope) does not emit it either — it is present
only in viem's newer packer. Ties to Finding 16.

## Finding 19 — Hash computation duplicated per account instead of a shared util (diverges)

viem centralizes all hashing in one `getUserOperationHash` that branches on EP version
(`getUserOperationHash.ts:24`). The Dart port has no equivalent shared function; each account carries its own
copy: `_computeUserOpHash` / `_packUserOp` in `simple_account.dart:355`, `nexus_account.dart:353`,
`light_account.dart:396`, `thirdweb_account.dart:379`, `kernel_account.dart:692`,
`eip7702_kernel_account.dart:362`, `etherspot_account.dart:448`, and the v0.6 variants
`_computeUserOpHashV06` in `biconomy_account.dart:382`, `kernel_account.dart:616`, `trust_account.dart:359`.

Behavior verified identical across all copies (byte-for-byte same packing: `keccak256` of
`abi.encode(sender, nonce, keccak(initCode), keccak(callData), accountGasLimits, preVerificationGas, gasFees,
keccak(paymasterAndData))` then `keccak256(abi.encode(innerHash, entryPoint, chainId))`). This is a
**structural / maintainability** divergence, not a behavioral one — but the duplication is a drift risk: a
future fix must be applied in ~11 places. Recommend extracting a shared `getUserOperationHash(userOp,
entryPoint, chainId, version)` mirroring viem.

## Finding 20 — No pad/quantity overflow guard (diverges)

viem's `pad` throws `SizeExceedsPaddingSizeError` when a value is wider than the requested size (used for the
16-byte gas fields). Dart's `Hex.padLeft` (`hex.dart:41-49`) and `Hex.fromBigInt(..., byteLength:)`
(`hex.dart:82-89`) instead return the value **unchanged** when it already exceeds the target width — no throw,
no truncation. A `verificationGasLimit`/`callGasLimit`/fee that overflows uint128 would silently produce a
mis-sized `accountGasLimits`/`gasFees` blob (and a wrong hash) rather than failing fast.

Impact: **low in practice** (gas values never approach 2^128) but it is a correctness guard viem has and the
port lacks.

## Finding 21 — RPC address casing differs (diverges, cosmetic)

viem formatters emit EIP-55 checksummed addresses in RPC payloads. Dart `toJson` uses `sender.hex` /
`factory!.hex` / `paymaster!.hex`, and the `hex` getter returns the **lowercase** form (`with0x`,
`types/address.dart:15`). Bundlers accept both, and hashing is case-insensitive (addresses are keccak-hashed
as bytes), so this is cosmetic. A checksummed getter (`checksummed`, `address.dart:18`) exists but is not used
in serialization.

## Finding 22 — `encodeUint128` mislabeled but behaviorally correct (dart-only)

`AbiEncoder.encodeUint128` (`encoding.dart:21`) is documented "16 bytes, left-padded to 32 bytes" and
`encodeUint48` similarly, but both call `Hex.fromBigInt(value, byteLength: 32)`, producing a full 32-byte
ABI word. That is the **correct** ABI encoding for any `uintN` (all integers pad to 32 bytes), so output is
right; only the doc/name is misleading. Not used in the packed-userop 16-byte fields (those use
`padLeft(..., 16)` / `byteLength: 16` directly), so no impact on packing.

---

## Confirmed mirrors (evidence)

- **Packing byte layout** (Findings 2–5): field widths and concatenation order match viem exactly —
  `initCode` = factory(20)‖factoryData; `accountGasLimits` = verificationGasLimit(16)‖callGasLimit(16);
  `gasFees` = maxPriorityFeePerGas(16)‖maxFeePerGas(16); `paymasterAndData` =
  paymaster(20)‖pmVerGas(16)‖pmPostOpGas(16)‖pmData. `'0x'` returned when factory/paymaster absent, matching
  viem's ternaries. Defaults for missing paymaster gas fields are `BigInt.zero` on both sides
  (`packed_user_operation.dart:179,184` vs `getPackedUserOperation.ts:71,80`).
- **v0.6 hash** (Finding 9): 10-field `abi.encode` with `keccak(initCode)`, `keccak(callData)`,
  `keccak(paymasterAndData)` and the un-packed gas fields as separate uint256s, exactly per
  `getUserOperationHash.ts:62-87`. Verified in `biconomy_account.dart:396`, `kernel_account.dart:630`,
  `trust_account.dart` packers.
- **v0.7 hash** (Finding 10): 8-field packed `abi.encode` with `accountGasLimits`/`gasFees` as `bytes32`
  and `keccak` of initCode/callData/paymasterAndData, per `getUserOperationHash.ts:90-113`. Verified across
  `simple/nexus/light/thirdweb/kernel/etherspot`. Final wrapper
  `keccak256(abi.encode(hash, entryPoint, chainId))` matches `getUserOperationHash.ts:119`.
- **v0.8 typed-data hash** (Finding 11): Dart's `_getUserOperationTypedData`
  (`eip7702_simple_account.dart:431-512`) reproduces viem's `getUserOperationTypedData` field-for-field —
  domain `{ name: 'ERC4337', version: '1', chainId, verifyingContract: entryPoint }`, primaryType
  `PackedUserOperation`, and the same 8 typed fields (`initCode`/`callData`/`paymasterAndData` as `bytes`,
  `accountGasLimits`/`gasFees` as `bytes32`). Matches `getUserOperationTypedData.ts:18-48`.
- **EntryPoint addresses** (Findings 12–13): v0.6 `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` and v0.7
  `0x0000000071727De22E5E9d8BAf0edAc6f37da032` are byte-identical to viem. v0.8
  `0x4337084d9e255ff0702461cf8895ce9e3b5ff108` matches viem's `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`
  up to EIP-55 casing only (both parse to the same address).
- **Quantity serialization** (Finding 14): `Hex.fromBigInt` with no `byteLength` emits minimal hex
  (`value.toRadixString(16)`), e.g. `0x186a0`, `0x0` for zero — matching viem `numberToHex` minimal
  quantities and `deepHexlify`'s bigint branch. Dart has no `deepHexlify` helper but achieves equivalent
  output field-by-field in each `toJson` and in the pimlico/bundler client serializers
  (`pimlico_client.dart:342`).
- **Optional-field omission** (Finding 15): `UserOperationV07.toJson` omits `factory`, `factoryData`,
  `paymaster`, `paymasterVerificationGasLimit`, `paymasterPostOpGasLimit`, `paymasterData` when null
  (`user_operation.dart:393-412`), matching `formatUserOperationRequest`'s `typeof !== 'undefined'` guards.

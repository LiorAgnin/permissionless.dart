# Parity Audit 03 — Smart-Account Actions & ERC-7579 Actions

**Scope**: `actions/smartAccount/` (sendTransaction, sendCalls, getCallsStatus, signMessage, signTypedData, writeContract) and `actions/erc7579/` (installModule(s), uninstallModule(s), isModuleInstalled, supportsModule, supportsExecutionMode, accountId), permissionless.js v0.3.5 vs permissionless.dart v0.3.0.

**JS root**: `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless`
**Dart root**: `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless`

Key Dart files:
- `lib/src/actions/smart_account/smart_account_actions.dart`
- `lib/src/actions/erc7579/erc7579_actions.dart`
- `lib/src/actions/erc7579/module_queries.dart`
- `lib/src/utils/erc7579.dart` (encoding backend, equivalent to JS `utils/encodeInstallModule.ts` / `utils/encodeUninstallModule.ts` and the inline ABIs in the JS actions)

**Headline finding**: 4 of the 7 hard-coded ERC-7579 function selectors in the Dart port are **wrong** (`uninstallModule`, `isModuleInstalled`, `supportsModule`, `accountId`). Every Dart action built on them produces calldata that no ERC-7579 account will recognize. The unit tests assert the same wrong constants, so they pass while the on-chain behavior is broken.

---

## Verdict table

| # | Aspect | Verdict | Notes |
|---|--------|---------|-------|
| 1 | sendTransaction → userop conversion (value/data defaults, single-call wrapping) | mirrors | `value ?? 0`, `data = '0x'` on both sides |
| 2 | sendTransaction receipt wait / return value on timeout | **diverges** | JS throws on timeout; Dart silently returns the userop hash as if it were a tx hash |
| 3 | sendTransaction userop-params passthrough form (batch `calls`) | **diverges** (minor) | JS accepts `SendUserOperationParameters`; Dart only single `to/value/data` |
| 4 | sendCalls (EIP-5792 submit, no wait) | mirrors | Both return the userop hash as the call-bundle id, no receipt wait |
| 5 | getCallsStatus (EIP-5792 status + receipt mapping) | mirrors | pending=100 / success=200 / failure=500, `version '1.0'`, `atomic: true`, spec-shaped receipt |
| 6 | signMessage delegation | **diverges** (minor) | Delegation to account mirrors; Dart accepts `String` only, JS also accepts raw bytes/hex. No ERC-6492 wrapping in either (JS does none at the action layer) |
| 7 | signTypedData delegation | mirrors | Dart auto-adds `EIP712Domain` type like JS; JS additionally runs `validateTypedData` pre-flight (Dart relies on hashing to fail) — cosmetic, not encoded output |
| 8 | writeContract ABI encoding path | **diverges** (major) | Dart uses a hand-rolled signature-string encoder: dynamic `bytes` args are mis-encoded (no offset head), `string`/arrays/tuples/`int` unsupported, no `dataSuffix` |
| 9 | Module type id mapping (validator=1, executor=2, fallback=3, hook=4) | mirrors | |
| 10 | installModule / installModules calldata + batching | mirrors | Selector `0x9517e29f` correct; one call per module to the account address, value 0 |
| 11 | install/uninstall parameter surface (paymaster override, authorization, appended `calls`) | **diverges** (minor) | JS supports per-op paymaster/paymasterContext/authorization/extra calls; Dart has none of these |
| 12 | uninstallModule / uninstallModules calldata | **diverges (CRITICAL)** | Wrong selector `0xa4d6f1d2` (actual: `0xa71763a8`) |
| 13 | isModuleInstalled read call | **diverges (CRITICAL)** | Wrong selector `0x6d61fe70` (that is `onInstall(bytes)`; actual: `0x112d3a7d`); also errors swallowed → `false`, no counterfactual fallback |
| 14 | supportsModule read call | **diverges (CRITICAL)** | Wrong selector `0x12d79da3` (actual: `0xf2dc691d`) |
| 15 | accountId read call | **diverges (CRITICAL)** | Wrong selector `0x7b60424a` (actual: `0x9cfd7cff`); errors swallowed → `''` |
| 16 | supportsExecutionMode mode encoding (callType/execType/selector/payload packing) | **diverges** | Layout and selector `0xd03c7914` mirror; but the `revertOnError` → execType byte is **inverted** relative to JS when set explicitly (defaults happen to coincide) |
| 17 | Counterfactual (undeployed account) fallback for all four query actions | **diverges** | JS retries via `call` with `factory`/`factoryData`; Dart has no equivalent |
| 18 | Fallback-module selector special-casing in install initData | mirrors | Neither side special-cases module type 3; init/context bytes passed through verbatim |
| 19 | installModuleAndWait / uninstallModuleAndWait / getInstalledModulesOfType / standalone `module_queries.dart` functions | dart-only | Convenience additions, no JS counterpart |

**Counts**: mirrors 8 · diverges 10 (4 critical) · missing 0 · dart-only 1 group (4 helpers).

---

## Critical: 4 wrong hard-coded ERC-7579 selectors (rows 12–15)

JS never hard-codes selectors — every action/util builds calldata from an inline ABI via viem's `encodeFunctionData`:

- `utils/encodeUninstallModule.ts:58` (`name: "uninstallModule"`, encoded at `utils/encodeUninstallModule.ts:80-85`)
- `actions/erc7579/isModuleInstalled.ts:60-77` (ABI) and `:87-95` (readContract args, `context ?? additionalContext` at `:92`)
- `actions/erc7579/supportsModule.ts:59-77` (ABI), invoked at `:79-87`
- `actions/erc7579/accountId.ts:37-50` (ABI), invoked at `:52-58`

Dart hard-codes the selectors in `Erc7579Selectors` and four of them do not match `keccak256(signature)[0:4]`:

| Function | Dart constant (`lib/src/utils/erc7579.dart`) | Actual selector | Status |
|---|---|---|---|
| `installModule(uint256,address,bytes)` | `0x9517e29f` (`erc7579.dart:77`) | `0x9517e29f` | correct |
| `uninstallModule(uint256,address,bytes)` | `0xa4d6f1d2` (`erc7579.dart:81`) | `0xa71763a8` | **WRONG** |
| `isModuleInstalled(uint256,address,bytes)` | `0x6d61fe70` (`erc7579.dart:85`) | `0x112d3a7d` | **WRONG** |
| `supportsModule(uint256)` | `0x12d79da3` (`erc7579.dart:89`) | `0xf2dc691d` | **WRONG** |
| `accountId()` | `0x7b60424a` (`erc7579.dart:93`) | `0x9cfd7cff` | **WRONG** |
| `supportsExecutionMode(bytes32)` | `0xd03c7914` (`erc7579.dart:97`) | `0xd03c7914` | correct |
| `execute(bytes32,bytes)` | `0xe9ae5c53` (`erc7579.dart:73`) | `0xe9ae5c53` | correct |

Selectors verified with `cast sig` / `cast keccak` (e.g. `keccak256("uninstallModule(uint256,address,bytes)") = 0xa71763a8...`).

Notably, `0x6d61fe70` is the selector of **`onInstall(bytes)`** — the Dart codebase even uses that same constant correctly under that name at `lib/src/accounts/etherspot/constants.dart:46` — so `isModuleInstalled` was evidently copy-pasted from the wrong signature.

Consequences (all calldata built in `lib/src/utils/erc7579.dart` and consumed by `lib/src/actions/erc7579/erc7579_actions.dart` and `lib/src/actions/erc7579/module_queries.dart`):

- `uninstallModule` / `uninstallModules` (`erc7579_actions.dart:142-164`, `:189-216` → `encode7579UninstallModule`, `erc7579.dart:432-448`): the userop executes a call to the account with an unknown selector — at best reverts, at worst hits a fallback handler. **Module uninstallation cannot work.**
- `isModuleInstalled` (`erc7579_actions.dart:370-390`; `module_queries.dart:26-41` → `encode7579IsModuleInstalled`, `erc7579.dart:470-486`): eth_call reverts or returns garbage; combined with the catch-all (`erc7579_actions.dart:387-389`) the method **always returns `false`**.
- `supportsModule` (`erc7579_actions.dart:341-355`; `module_queries.dart:64-72` → `erc7579.dart:501-504`): same failure mode, always `false`.
- `getAccountId` (`erc7579_actions.dart:402-415`; `module_queries.dart:88-95` → `erc7579.dart:541`): always returns `''` (catch at `erc7579_actions.dart:412-414`).
- The Dart-only `getInstalledModulesOfType` (`module_queries.dart:116-138`) is built on the broken `isModuleInstalled`, so it always returns an empty list.

The unit tests lock in the wrong values instead of catching them: `test/utils/erc7579_test.dart:327-343` asserts `0xa4d6f1d2`, `0x6d61fe70`, `0x12d79da3`, `0x7b60424a` with comments claiming they are the keccak prefixes.

Everything else about the calldata layout mirrors JS: `uint256 moduleTypeId` + `address module` + dynamic `bytes` at offset `0x60` (`erc7579.dart:398-448, 470-486` vs the viem-encoded ABIs above), and the module type ids match (`Erc7579ModuleType` 1/2/3/4 at `erc7579.dart:15-38` vs `parseModuleTypeId` at `actions/erc7579/supportsModule.ts:25-36`).

---

## supportsExecutionMode: execType bit inverted vs JS (row 16)

JS (`actions/erc7579/supportsExecutionMode.ts:46-61`) packs `bytes1 callType | bytes1 execType | bytes4 unused | bytes4 selector | bytes22 payload` and sets:

```ts
toHex(toBytes(revertOnError ? "0x01" : "0x00", { size: 1 }))   // :56
```

i.e. `revertOnError: true` → execType `0x01`.

Dart (`lib/src/utils/erc7579.dart:195-225`, `ExecutionMode.encode`):

```dart
mode[1] = revertOnError ? 0x00 : 0x01;   // erc7579.dart:202
```

i.e. `revertOnError: true` → execType `0x00` — the opposite bit for the same flag value.

Per ERC-7579 the Dart semantics are the correct ones (`0x00` = default/revert, `0x01` = try), and the JS mapping is arguably a reference bug; but as a parity matter the two SDKs disagree whenever the caller sets `revertOnError` explicitly. They coincide only by accident on defaults: JS `revertOnError` is optional (`supportsExecutionMode.ts:24-29`, undefined → falsy → `0x00`) and Dart defaults `revertOnError = true` → `0x00` (`erc7579.dart:161`).

Everything else mirrors: callType byte 0x00/0x01/0xff (`getCallType`, `supportsExecutionMode.ts:35-44` vs `Erc7579CallKind`, `erc7579.dart:103-131`), selector right-padded into bytes 6–9, context into bytes 10–31 (`supportsExecutionMode.ts:57-60` vs `erc7579.dart:206-222`), selector `0xd03c7914`, and a plain `bytes32` argument (`erc7579.dart:523-526`).

Error handling diverges as described in the next section: Dart returns `false` on any call failure (`erc7579_actions.dart:320-323`).

---

## Query actions: no counterfactual fallback, errors swallowed (rows 13–15, 17)

All four JS read actions (`accountId`, `isModuleInstalled`, `supportsModule`, `supportsExecutionMode`) share a pattern: try `readContract` against the deployed account; on `ContractFunctionExecutionError`, retry as an `eth_call` with `factory`/`factoryData` so the query works for **undeployed (counterfactual) accounts**, and rethrow anything else:

- `actions/erc7579/accountId.ts:62-91` (fallback at `:63-64`)
- `actions/erc7579/isModuleInstalled.ts:97-131`
- `actions/erc7579/supportsModule.ts:88-118` (fallback at `:89-90`)
- `actions/erc7579/supportsExecutionMode.ts:126-156` (fallback at `:127-128`)

Dart performs a single `publicClient.call` and converts **any** exception into a benign answer:

- `supportsExecutionMode` → `false` (`erc7579_actions.dart:316-323`)
- `supportsModule` → `false` (`erc7579_actions.dart:348-354`)
- `isModuleInstalled` → `false` (`erc7579_actions.dart:383-389`)
- `getAccountId` → `''` (`erc7579_actions.dart:408-414`)

(The standalone versions in `module_queries.dart:26-95` don't catch, but also have no counterfactual fallback.)

Behavioral differences: (a) queries against not-yet-deployed accounts return `false`/`''` in Dart but real answers in JS; (b) transport/RPC failures are indistinguishable from "not supported" in Dart, whereas JS propagates them. Also minor: JS `isModuleInstalled` accepts `context ?? additionalContext` (`isModuleInstalled.ts:92`); Dart exposes only `additionalContext` (`erc7579_actions.dart:374`) — same wire bytes, narrower input surface.

---

## writeContract: hand-rolled encoder, dynamic `bytes` mis-encoded (row 8)

JS delegates encoding entirely to viem's `encodeFunctionData` with a full ABI and supports `dataSuffix` concatenation (`actions/smartAccount/writeContract.ts:50-53`, `:61`), then routes through `sendTransaction`.

Dart (`smart_account_actions.dart:122-143`) parses a signature string and encodes each argument independently (`_encodeFunction`, `:268-300`; `_encodeArg`, `:303-338`), then flat-concatenates: `AbiEncoder.encodeFunctionCall` is `selector + concat(params)` (`lib/src/utils/encoding.dart:54-58`).

Divergences:

1. **Dynamic `bytes` produces invalid ABI encoding.** `_encodeArg('bytes', v)` returns `AbiEncoder.encodeBytes(v)` (`smart_account_actions.dart:333-335`), which is the *tail* (length word + padded data, `encoding.dart:33-42`). `_encodeFunction` inlines that tail into the head positions with no offset pointer, so any signature containing a `bytes` parameter (e.g. `execute(address,uint256,bytes)`) yields calldata the contract cannot decode. The codebase has a correct helper for this (`AbiEncoder.encodeWithDynamics`, `encoding.dart:64+`) but `writeContract` does not use it. JS handles all of this via viem.
2. **Type coverage.** Only `address`, `uint*`, `bool`, `bytes32`, `bytes` are supported; `string`, arrays, tuples, `int*`, fixed-size arrays throw `ArgumentError` (`smart_account_actions.dart:337`). JS supports the full ABI.
3. **No `dataSuffix`** equivalent (JS: `writeContract.ts:61`).
4. `uint*` widths are all encoded as full 32-byte words (`smart_account_actions.dart:313-323`) — this is actually correct ABI behavior, noted only because the doc comment implies width-awareness.

---

## sendTransaction: timeout fallback returns the wrong kind of hash (rows 2–3)

Both sides convert a `{to, value, data}` triple to a single-call userop with identical defaults — JS `value || BigInt(0)`, `data || "0x"` (`actions/smartAccount/sendTransaction.ts:107-108`), Dart `value` defaulting to 0 via `Call` (`lib/src/types/user_operation.dart:450-454`) and `data = '0x'` (`smart_account_actions.dart:78, 85`) — then wait for the receipt and return `receipt.transactionHash` (`sendTransaction.ts:124-132` vs `smart_account_actions.dart:91-94`).

Divergences:

1. **Timeout semantics.** JS `waitForUserOperationReceipt` throws (`WaitForUserOperationReceiptTimeoutError`) if the op is not included, so a returned hash is always a transaction hash. Dart's `waitForReceipt` returns `null` on timeout (`lib/src/clients/bundler/bundler_client.dart:208-224`) and `sendTransaction` then falls back to returning the **UserOperation hash** (`smart_account_actions.dart:94`: `receipt?.receipt?.transactionHash ?? hash`). The caller receives a value that looks like a tx hash but will never resolve via `eth_getTransactionReceipt`.
2. **No userop-params form.** JS `sendTransaction` also accepts full `SendUserOperationParameters` (multiple `calls`, paymaster override, etc.) when no `to` field is present (`sendTransaction.ts:78, 117-121`); Dart supports only the single-call named-parameter form (`smart_account_actions.dart:75-83`). Batch senders must drop to `sendUserOperation`. Minor, since the capability exists elsewhere.
3. Cross-cutting API note (applies to all send-type actions in this scope): Dart requires explicit `maxFeePerGas`/`maxPriorityFeePerGas` (`smart_account_actions.dart:79-80`); JS treats them as optional overrides resolved by the client's gas estimation.

---

## signMessage: string-only input (row 6)

JS accepts viem's `SignMessageParameters`, i.e. `message: string | { raw: Hex | ByteArray }`, and delegates to `account.signMessage({ message })` (`actions/smartAccount/signMessage.ts:62, 72`). Dart accepts `String message` only and delegates to `account.signMessage(message)` (`smart_account_actions.dart:39`). Raw-bytes payloads (e.g. signing a 32-byte hash under EIP-191) cannot be expressed through the Dart action. Delegation itself mirrors; neither side applies ERC-6492 wrapping at the action layer (in JS that lives on the account implementations, out of this unit's scope).

---

## install/uninstall parameter surface (row 11)

JS `installModule`/`installModules`/`uninstallModule`/`uninstallModules` accept per-operation `paymaster` / `paymasterContext` overrides, EIP-7702 `authorization`, and **extra `calls` appended after the module-management calls** in the same userop (`actions/erc7579/installModule.ts:16, 66-67, 83-97` — `...(calls ?? [])` at `:89`; same shape in `installModules.ts:57-96`, `uninstallModule.ts:76-98`, `uninstallModules.ts:44-87`). JS also accepts `context` as an alias for `initData`/`deInitData` (`utils/encodeInstallModule.ts:86`, `utils/encodeUninstallModule.ts:84`).

Dart exposes only `type`/`address`/`initData|deInitData`/gas fees/`nonce` (`erc7579_actions.dart:47-54, 96-101, 142-149, 189-194`); paymaster behavior comes solely from client construction, and there is no way to piggyback additional calls or an authorization onto the module-management userop. Batching of the module list itself mirrors (one `Call` per module targeting the account address, `erc7579_actions.dart:108-115, 201-208` vs `encodeInstallModule.ts:50-56` map). Two trivial extras: Dart rejects empty module lists (`erc7579_actions.dart:102-104, 195-197`) where JS would submit an empty-call userop, and Dart's `Call` defaults `value` to 0 exactly like JS's explicit `BigInt(0)` (`encodeInstallModule.ts:55` vs `user_operation.dart:454`).

---

## Dart-only additions (row 19)

Not divergences — additive convenience APIs with no JS counterpart:

- `installModuleAndWait` (`erc7579_actions.dart:223-247`) and `uninstallModuleAndWait` (`erc7579_actions.dart:254-278`): compose the send action with `waitForReceipt`.
- `getInstalledModulesOfType` (`module_queries.dart:116-138`): sequentially probes candidate module addresses via `isModuleInstalled` (currently non-functional due to the selector bug above).
- Standalone address-based query functions in `module_queries.dart:26-95` (`isModuleInstalled`, `supportsModule`, `getAccountId` taking an explicit account address rather than a client) — parallel to but distinct from the client-extension versions.

---

## Mirrors (verified, no section needed)

- **sendCalls** (`actions/smartAccount/sendCalls.ts:27-37` vs `smart_account_actions.dart:173-184`): both submit a userop and return the hash as the EIP-5792 bundle id without waiting (JS wraps it as `{ id }`, Dart returns the `String` — same information).
- **getCallsStatus** (`actions/smartAccount/getCallsStatus.ts:52-90` vs `smart_account_actions.dart:210-241`): identical mapping — receipt found → `success`/`failure` with statusCode 200/500 from `receipt.success`; not found (throw in JS, `null`/throw in Dart) → `pending`/100; `version: '1.0'`, `atomic: true`; receipt projected to `{status, logs(address/topics/data), blockHash, blockNumber, gasUsed, transactionHash}` (`getCallsStatus.ts:68-78` vs `smart_account_actions.dart:244-259`; Dart's `status == 1 → 'success' : 'reverted'` matches viem's hex-status semantics).
- **signTypedData** (`actions/smartAccount/signTypedData.ts:136-156` vs `smart_account_actions.dart:47-48`): both delegate to the account; the `EIP712Domain` type JS injects via `getTypesForEIP712Domain` (`signTypedData.ts:138`) is auto-derived inside Dart's `TypedData` hashing (`lib/src/types/typed_data.dart:143`). JS's extra `validateTypedData` pre-flight (`signTypedData.ts:144`) only changes *which* error malformed input throws, not any signature bytes.
- **Module type id mapping**: `parseModuleTypeId` 1/2/3/4 (`actions/erc7579/supportsModule.ts:25-36`) ≡ `Erc7579ModuleType` enum ids (`lib/src/utils/erc7579.dart:15-38`).
- **installModule calldata**: selector `0x9517e29f` + `(uint256, address, bytes@0x60)` (`utils/encodeInstallModule.ts:56-88` vs `erc7579.dart:398-415`).
- **Fallback-module handling**: neither implementation special-cases module type 3 (no selector packed into initData) — the caller supplies the fully-formed context bytes on both sides.

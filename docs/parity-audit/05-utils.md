# Parity Audit — Unit 05: Utility Functions

**Scope:** `permissionless.js` v0.3.5 `utils/` vs `permissionless.dart` v0.3.0 `lib/src/utils/` (plus `accounts/account_owner.dart` for `toOwner`, and Safe MultiSend which lives in the JS Safe account file). `getPackedUserOperation` / `packed_user_operation.dart` are covered by another unit and skipped here.

**Roots:**
- JS: `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless`
- Dart: `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless`

**Headline finding:** four of the seven hardcoded ERC-7579 function selectors in `lib/src/utils/erc7579.dart` are **wrong** (`uninstallModule`, `isModuleInstalled`, `supportsModule`, `accountId`). They are consumed by the ERC-7579 actions layer, so module uninstallation and all module/account queries produce calldata that no ERC-7579 account will recognize. The unit tests assert the wrong values, so they pass. Additionally, the `revertOnError` execution-mode bit is encoded with **opposite polarity** in Dart vs JS.

## Verdict table

| # | Utility (JS) | JS location | Dart equivalent | Dart location | Verdict |
|---|---|---|---|---|---|
| 1 | `encode7579Calls` | `utils/encode7579Calls.ts:24` | `encode7579Execute` / `encode7579ExecuteBatch` / `ExecutionMode.encode` | `lib/src/utils/erc7579.dart:334,354,195` | **diverges** |
| 2 | `decode7579Calls` | `utils/decode7579Calls.ts:24` | `decode7579Calls` | `lib/src/utils/erc7579.dart:756` | **diverges** |
| 3 | `encodeInstallModule` | `utils/encodeInstallModule.ts:36` | `encode7579InstallModule` | `lib/src/utils/erc7579.dart:398` | mirrors |
| 4 | `encodeUninstallModule` | `utils/encodeUninstallModule.ts:36` | `encode7579UninstallModule` | `lib/src/utils/erc7579.dart:432` | **diverges (broken)** |
| 5 | `encodeNonce` | `utils/encodeNonce.ts:3` | `encodeNonce` | `lib/src/utils/erc7579.dart:703` | mirrors |
| 6 | `decodeNonce` | `utils/decodeNonce.ts:3` | `decodeNonce` | `lib/src/utils/erc7579.dart:684` | mirrors |
| 7 | `deepHexlify` | `utils/deepHexlify.ts:9` | — (typed `toJson()` per model) | `lib/src/types/user_operation.dart:205,380` | **missing** (by design) |
| 8 | `erc20AllowanceOverride` | `utils/erc20AllowanceOverride.ts:17` | `erc20AllowanceOverride` | `lib/src/utils/erc20.dart:340` | mirrors |
| 9 | `erc20BalanceOverride` | `utils/erc20BalanceOverride.ts:16` | `erc20BalanceOverride` | `lib/src/utils/erc20.dart:411` | mirrors |
| 10 | `getRequiredPrefund` | `utils/getRequiredPrefund.ts:24` | `getRequiredPrefund` (v0.7) + `getRequiredPrefundV06` | `lib/src/utils/gas.dart:358,390` | mirrors |
| 11 | `isSmartAccountDeployed` | `utils/isSmartAccountDeployed.ts:4` | `PublicClient.isDeployed` | `lib/src/clients/public/public_client.dart:60` | mirrors |
| 12 | `toOwner` | `utils/toOwner.ts:22` | `AccountOwner` / `PrivateKeyOwner` | `lib/src/accounts/account_owner.dart:31,88` | **diverges** (architectural) |
| 13 | `getAddressFromInitCodeOrPaymasterAndData` | `utils/getAddressFromInitCodeOrPaymasterAndData.ts:3` | same name | `lib/src/utils/gas.dart:432` | mirrors |
| 14 | `getPimlicoEstimationCallData` | `utils/getEstimationCallData.ts:259` | — | — | **missing** |
| 15 | `ox` shim (`getOxExports`/`hasOxModule`) | `utils/ox.ts:18,34` | native WebAuthn impl | `lib/src/utils/webauthn_encoding.dart`, `lib/src/utils/rip7212.dart` | mirrors (intent; JS-specific shim not needed) |
| 16 | MultiSend encoding (JS: Safe account internal) | `accounts/safe/toSafeSmartAccount.ts:566,590` | `encodeMultiSend` / `encodeMultiSendWithOperations` | `lib/src/utils/multisend.dart:41,82` | mirrors |
| 17 | — | — | `decodeMultiSend` | `lib/src/utils/multisend.dart:118` | dart-only |
| 18 | — (JS equivalents are actions, correct there) | `actions/erc7579/supportsModule.ts:25` etc. | `encode7579IsModuleInstalled` / `encode7579SupportsModule` / `encode7579AccountId` | `lib/src/utils/erc7579.dart:470,501,541` | **dart-only (broken selectors)** |
| 19 | — | — | `GasMultipliers`, `FeeEstimate`, `estimateFees*` | `lib/src/utils/gas.dart:29,188,272` | dart-only |
| 20 | — | — | `erc20PaymasterOverride`, `mergeStateOverrides`, `Erc20StorageSlots` | `lib/src/utils/erc20.dart:527,455,568` | dart-only |
| 21 | — | — | `units.dart`, `parsing.dart`, `message_hash.dart`, `erc20_paymaster.dart` | `lib/src/utils/` | dart-only (viem-builtin equivalents in JS) |

**Counts:** 9 mirrors · 4 diverges · 2 missing · 5 dart-only rows (one of which is broken).

---

## Finding 1 — `encode7579UninstallModule` and 3 query encoders use wrong function selectors (diverges — broken)

The Dart file hardcodes ERC-7579 selectors at `lib/src/utils/erc7579.dart:68-98`. Verified against `cast sig`:

| Function | Dart constant (`erc7579.dart` line) | Actual selector | Status |
|---|---|---|---|
| `execute(bytes32,bytes)` | `0xe9ae5c53` (:73) | `0xe9ae5c53` | correct |
| `installModule(uint256,address,bytes)` | `0x9517e29f` (:77) | `0x9517e29f` | correct |
| `uninstallModule(uint256,address,bytes)` | **`0xa4d6f1d2`** (:81) | **`0xa71763a8`** | **WRONG** |
| `isModuleInstalled(uint256,address,bytes)` | **`0x6d61fe70`** (:85) | **`0x112d3a7d`** | **WRONG** |
| `supportsModule(uint256)` | **`0x12d79da3`** (:89) | **`0xf2dc691d`** | **WRONG** |
| `accountId()` | **`0x7b60424a`** (:93) | **`0x9cfd7cff`** | **WRONG** |
| `supportsExecutionMode(bytes32)` | `0xd03c7914` (:97) | `0xd03c7914` | correct |

JS never hardcodes these: it derives selectors via `encodeFunctionData` from the ABI (`utils/encodeUninstallModule.ts:54-86`, `actions/erc7579/supportsModule.ts`, `actions/erc7579/isModuleInstalled.ts`, `actions/erc7579/accountId.ts`), so JS is correct.

**Impact.** The wrong selectors are consumed by the public actions layer:
- `lib/src/actions/erc7579/erc7579_actions.dart:152,202` (uninstall), `:346` (supportsModule), `:377` (isModuleInstalled), `:406` (accountId)
- `lib/src/actions/erc7579/module_queries.dart:33,69,92`

Any `uninstallModule` UserOperation reverts on-chain (or hits an unintended fallback handler), and all module/account queries return garbage or revert. Argument layout after the selector is otherwise correct (uint256, address, bytes-offset, bytes — matches JS).

**Tests are self-referential** and assert the wrong values, e.g. `test/utils/erc7579_test.dart:328` (`expect(... uninstallModule, equals('0xa4d6f1d2'))`), `:333`, `:338`, `:343` — so the suite passes despite the bug.

## Finding 2 — `encode7579Calls`: `revertOnError` wire polarity is inverted vs JS (diverges)

Per ERC-7579 the execType byte is `0x00` = default (revert on failure), `0x01` = try.

- **JS** `encodeExecutionMode` — `actions/erc7579/supportsExecutionMode.ts:56`:
  ```ts
  toHex(toBytes(revertOnError ? "0x01" : "0x00", { size: 1 }))
  ```
  i.e. `revertOnError: true` → byte `0x01` ("try" mode — arguably a JS naming bug, but it is the reference behavior, and `decode7579Calls.ts:76` round-trips it: `revertOnError: BigInt(revertOnError) === BigInt(1)`).
- **Dart** `ExecutionMode.encode` — `lib/src/utils/erc7579.dart:202`:
  ```dart
  mode[1] = revertOnError ? 0x00 : 0x01;
  ```
  i.e. `revertOnError: true` → byte `0x00` (spec-correct), decoded consistently at `erc7579.dart:778` (`revertOnError = modeBytes[1] == 0x00`).

Both libraries are internally self-consistent, and the *defaults* happen to produce identical wire bytes (JS default `revertOnError: undefined` → `0x00`; Dart default `true` → `0x00`). But any caller porting JS code that explicitly sets `revertOnError: true` gets the opposite execType byte in Dart. Dart matches the ERC-7579 spec semantics; JS does not. Document the intentional deviation (or rename the Dart field) — otherwise cross-port test vectors will mismatch.

## Finding 3 — `decode7579Calls`: mode selector/context byte offsets differ from JS (diverges — Dart is the correct one)

Mode layout (ERC-7579): `callType(1) | execType(1) | unused(4) | modeSelector(4 @ bytes 6-9) | payload(22 @ bytes 10-31)`.

- **JS decode** — `utils/decode7579Calls.ts:56-57` reads `selector = slice(mode, 3, 7)` (bytes 3-6) and `context = slice(mode, 7)` (bytes 7-31). This does **not** match JS's own encoder (`supportsExecutionMode.ts:53-60` places the selector at bytes 6-9), so a JS encode→decode round trip of a non-zero selector is lossy. Known upstream inconsistency.
- **Dart decode** — `lib/src/utils/erc7579.dart:780-799` reads selector at bytes 6-10 and context at bytes 10-32, matching both the Dart and JS encoders and the spec.

Deliberate, correct deviation — but note it when comparing decoded structures across the two libraries.

Two secondary decode differences:
- Dart assumes the `bytes executionCalldata` head offset is the standard `0x40` and ignores the actual offset word (`erc7579.dart:809-815`); JS uses viem's full ABI decoder. Nonstandard-but-valid ABI encodings would decode incorrectly in Dart. Low risk in practice.
- Single-call batch: JS `encode7579Calls` with 1 call keeps the *supplied* mode byte (e.g. `batchcall` `0x01` or `delegatecall` `0xff`) while packing single-call calldata (`encode7579Calls.ts:96-113`); Dart `encode7579ExecuteBatch` silently downgrades a 1-element batch to a plain `call` (`0x00`) encoding (`erc7579.dart:360-362`). Also, Dart has no public helper to encode a `delegatecall` execution (constants exist at `erc7579.dart:53,111`, but `encode7579Execute` hardcodes `Erc7579CallType.call` at `:335`). Batch tuple ABI layout itself (`(address,uint256,bytes)[]`, packed single call `to ++ value32 ++ data`) mirrors JS exactly (`encode7579Calls.ts:61-91,107-111` vs `erc7579.dart:254-329`).

## Finding 4 — `toOwner` (diverges — architectural)

JS `toOwner` (`utils/toOwner.ts:22-89`) normalizes any of {EIP-1193 provider, viem `WalletClient`, `LocalAccount`} into a `LocalAccount`, including `eth_requestAccounts`/`eth_accounts` address discovery for providers.

Dart replaces this with an abstract `AccountOwner` (`lib/src/accounts/account_owner.dart:31`) exposing `signPersonalMessage` / `signRawHash` / `signTypedData`, with two concrete implementations: `PrivateKeyOwner` (`account_owner.dart:88`) and `WebAuthnOwner` (`lib/src/accounts/webauthn_owner.dart`). There is no injected-provider / wallet-client owner, so browser-wallet-owned smart accounts have no Dart path. The three signing modes cover the same account needs as JS's `LocalAccount` surface (signMessage / signTypedData / raw). Reasonable platform adaptation; flagging so the gap (external signer / EIP-1193 owner) is a conscious decision.

## Finding 5 — `deepHexlify` (missing — by design)

JS uses `deepHexlify` (`utils/deepHexlify.ts:9-35`) to recursively convert arbitrary objects' bigints to minimal hex before RPC submission. Dart has no generic equivalent; each type serializes itself (`UserOperationV06.toJson` at `lib/src/types/user_operation.dart:205`, `UserOperationV07.toJson` at `:380`, using `Hex.fromBigInt` which produces minimal hex like JS `toHex`). Functionally equivalent for the RPC payloads that matter; the JS `transactionReceiptStatus` map (`deepHexlify.ts:3-6`) also has no Dart counterpart (receipt status handled in client parsing). No action needed unless arbitrary passthrough params must be hexlified.

## Finding 6 — `getPimlicoEstimationCallData` (missing)

JS ships `getPimlicoEstimationCallData` (`utils/getEstimationCallData.ts:259-297`): builds `simulateHandleOp` (EP v0.6) or `PimlicoSimulations.simulateEntryPoint`→`simulateHandleOpLast` (EP v0.7/0.8, estimation contract `0x949CeCa936909f75E5A40bD285d9985eFBb9B0D3`, `getEstimationCallData.ts:174`) calldata for client-side gas simulation. No Dart equivalent exists anywhere in `lib/` (`grep simulateEntryPoint|simulateHandleOp` returns nothing) — Dart relies entirely on bundler `eth_estimateUserOperationGas`. Note: this util is internal in JS (not exported from `utils/index.ts`), so the gap is low-priority unless local simulation is planned.

---

## Mirrors — verification notes

- **`encodeInstallModule`** — selector `0x9517e29f` correct; arg layout `uint256 moduleType, address module, bytes initData` with offset `0x60` matches JS ABI encoding (`encodeInstallModule.ts:56-88` vs `erc7579.dart:398-415`). Module type IDs match (JS `parseModuleTypeId` validator=1/executor=2/fallback=3/hook=4, `actions/erc7579/supportsModule.ts:25-38`; Dart `Erc7579ModuleType` `erc7579.dart:19-34`). API-shape difference only: JS binds to an account and returns `{to, value, data}[]` (and accepts `context ?? initData`); Dart returns bare calldata for a single module and the caller supplies `to`. Neither library applies per-module-type initData transformation — raw bytes pass through in both.
- **`encodeNonce`/`decodeNonce`** — settled: Dart **has** both, in `lib/src/utils/erc7579.dart:703` and `:684`, publicly exported via `lib/permissionless.dart:61`. Same math (`(key << 64) + sequence`; decode masks low 64 bits / shifts 64). One edge difference: JS `toHex(key, {size: 24})` **throws** if key ≥ 2^192 or sequence ≥ 2^64 (`encodeNonce.ts:4-5`), Dart silently masks to 192/64 bits (`erc7579.dart:705-710`).
- **`erc20AllowanceOverride`** — identical slot math: `keccak256(abi.encode(spender, keccak256(abi.encode(owner, slot))))` (`erc20AllowanceOverride.ts:26-53` vs `erc20.dart:353-369`); identical default amount `0x7FFF…FFFF` (max int256) (`erc20AllowanceOverride.ts:22-24` vs `erc20.dart:298-301`). Cosmetic: JS emits minimal-hex value (`toHex(amount)`), Dart 32-byte padded — both accepted by RPC state-override.
- **`erc20BalanceOverride`** — identical slot math `keccak256(abi.encode(owner, slot))` and identical default balance constant `0x1000…FFFF` (`erc20BalanceOverride.ts:20-36` vs `erc20.dart:304-307,420-427`). Token-specific slot knowledge is dart-only convenience (`Erc20StorageSlots`, `erc20.dart:568-596`) — JS makes the caller supply the slot; Dart does too but documents/provides common values.
- **`getRequiredPrefund`** — formulas identical. v0.6: `callGas + verificationGas * (paymasterAndData.length > 2 ? 3 : 1) + preVerificationGas` × `maxFeePerGas` (`getRequiredPrefund.ts:30-43` vs `gas.dart:390-401`). v0.7: sum of five gas fields (paymaster fields defaulting to 0) × `maxFeePerGas` (`getRequiredPrefund.ts:46-55` vs `gas.dart:358-372`). Dart splits into two typed functions instead of a version parameter — equivalent behavior.
- **`isSmartAccountDeployed`** — JS `Boolean(getCode(...))` (`isSmartAccountDeployed.ts:8-12`); Dart `code != '0x' && code.length > 2` after `eth_getCode` (`public_client.dart:46-63`). Equivalent (viem `getCode` returns `undefined` for `0x`).
- **`getAddressFromInitCodeOrPaymasterAndData`** — same 42-char threshold and first-20-bytes extraction (`getAddressFromInitCodeOrPaymasterAndData.ts:3-13` vs `gas.dart:432-452`). Edge: JS `getAddress` throws on malformed hex; Dart catches and returns `null`.
- **MultiSend** — packed layout identical: `uint8 operation | address to | uint256 value | uint256 dataLength | bytes data`, wrapped in `multiSend(bytes)` (JS `accounts/safe/toSafeSmartAccount.ts:566-607`; Dart `lib/src/utils/multisend.dart:41-115`, selector derived from signature at `lib/src/utils/encoding.dart:118-119`). Dart adds per-call operation control (`encodeMultiSendWithOperations`, `multisend.dart:82`) and a decoder (`decodeMultiSend`, `multisend.dart:118` — drops the operation byte when reconstructing `Call`s, `multisend.dart:148-149`).
- **ox shim** — `utils/ox.ts` exists only to make `ox` an optional JS dependency for WebAuthn. Dart implements WebAuthn encoding natively (`webauthn_encoding.dart`, `rip7212.dart`), so no counterpart is needed.

## Dart-only inventory (no JS counterpart in `utils/`)

- `lib/src/utils/gas.dart:29-183` — `GasMultipliers` presets (incl. `webAuthn` 3x verification buffer), `withMinimumVerificationGas`, `FeeEstimate`, `estimateFees`/`estimateFeesFromPimlico`, `GasCostEstimate`.
- `lib/src/utils/erc20.dart:64-160` — `encodeErc20Approve/Transfer/AllowanceCall/BalanceOfCall`, `decodeUint256Result`; `:455-596` — `mergeStateOverrides`, `erc20PaymasterOverride`, `Erc20StorageSlots`.
- `lib/src/utils/erc20_paymaster.dart` — allowance checking + `erc20PaymasterGasBuffer` helper.
- `lib/src/utils/units.dart`, `lib/src/utils/parsing.dart`, `lib/src/utils/message_hash.dart` — replacements for viem built-ins (`parseUnits`, `hashMessage`, `hashTypedData`).
- `lib/src/utils/rip7212.dart`, `lib/src/utils/webauthn_encoding.dart` — P256 precompile detection and validator-specific signature encodings.
- `lib/src/utils/erc7579.dart:470-595` — eth_call query encoders + `decode7579BoolResult`/`decode7579StringResult` (JS does this via viem `readContract` in actions). **Three of these are broken — see Finding 1.**

## Recommended fixes (priority order)

1. Fix the four wrong selectors in `lib/src/utils/erc7579.dart:81,85,89,93` (or derive them via `AbiEncoder.functionSelector` like `encoding.dart` does for Safe) and correct the assertions in `test/utils/erc7579_test.dart:328-343`; add a cross-check test that computes selectors from signatures.
2. Decide and document the `revertOnError` polarity (Finding 2); if JS-compat is the goal, flip `erc7579.dart:202` and `:778` together.
3. Consider an EIP-1193/external-signer `AccountOwner` implementation (Finding 4) if wallet-owned accounts are on the roadmap.

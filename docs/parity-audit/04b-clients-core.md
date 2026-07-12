# Parity Audit 04b — Smart-Account Client Pipeline & Native Bundler/Paymaster/Public Clients

**Reference:** permissionless.js v0.3.5 (`createSmartAccountClient.ts`, `clients/decorators/smartAccount.ts`, `actions/public/*`), which delegates the UserOperation pipeline to **viem**'s account-abstraction actions. viem is therefore the behavioral reference for `prepareUserOperation`, `estimateUserOperationGas`, `sendUserOperation`, `waitForUserOperationReceipt`, `getPaymasterData`/`getPaymasterStubData`.

**Port:** permissionless.dart v0.3.0 (`lib/src/clients/smart_account/`, `lib/src/clients/bundler/`, `lib/src/clients/paymaster/`, `lib/src/clients/public/`).

The Dart port does **not** wrap viem; it re-implements the whole middleware pipeline natively inside `SmartAccountClient.prepareUserOperationWithAuth`, plus hand-rolled bundler/paymaster/public JSON-RPC clients. This audit compares behavior, not shape.

## Scope note

permissionless.js itself is thin here: `createSmartAccountClient` just assembles a viem client, attaches `bundlerActions` + `smartAccountActions`, and stores `paymaster` / `paymasterContext` / `userOperation` config. All the pipeline logic lives in viem `prepareUserOperation.ts`. The Dart `SmartAccountClient` collapses viem's `createBundlerClient` + `prepareUserOperation` + `sendUserOperation` + `waitForUserOperationReceipt` into one class. So "JS side" citations point to viem where the logic actually is.

---

## Verdict table

| # | Aspect | Verdict |
|---|--------|---------|
| 1 | prepareUserOperation middleware order (sender/nonce/factory → stub sig → paymaster stub → gas est → paymaster final → sign) | **mirrors** |
| 2 | UserOperation partial-override semantics (override any field: callData, gas, signature, paymaster, factory) | **diverges** |
| 3 | Fee estimation (`userOperation.estimateFeesPerGas` hook / `estimateFeesPerGas` 2× buffer fallback) | **missing** |
| 4 | Gas-limit multipliers / defaults applied after estimation | **dart-only** |
| 5 | eth_estimateUserOperationGas params + state-override support | **mirrors** |
| 6 | Gas-estimation "estimate only if a field is missing" + preserve populated values | **diverges** |
| 7 | pm_getPaymasterStubData / pm_getPaymasterData param arity & context | **diverges** |
| 8 | Paymaster `isFinal` short-circuit | **mirrors** |
| 9 | pm_sponsorUserOperation (v0.6 combined path) param arity | **mirrors** |
| 10 | getAccountNonce (EntryPoint.getNonce encoding + key) | **mirrors** |
| 11 | getSenderAddress (helper-bytecode deploy trick vs. revert-decode) | **diverges** |
| 12 | waitForUserOperationReceipt (timeout default, throw-vs-null, error classification) | **diverges** |
| 13 | sendUserOperation (retryCount:0, no client retry) | **mirrors** |
| 14 | getChainId / eth_supportedEntryPoints | **mirrors** |
| 15 | Client-level `paymasterContext` default fallback | **missing** |
| 16 | Default nonce key source (viem `nonceKeyManager` timestamp vs. fixed `nonceKey`) | **diverges** (benign for Safe) |
| 17 | eip7702 authorization insertion into prepare pipeline | **mirrors** (dart-only marker mechanics) |

Counts: **mirrors 7**, **diverges 6**, **missing 2**, **dart-only 1** (plus one mirrors-with-caveat on 17).

---

## 1. Middleware order — mirrors

viem `prepareUserOperation.ts:419-705` runs: concurrently fill `callData` / `factory` (or `initCode` for 0.6) / `fees` / `nonce` / `authorization` (`:419-535`) → fill stub `signature` (`:553-560`) → paymaster **stub** for estimation (`:585-607`) → gas estimation (`:621-679`) → paymaster **final** for sending (`:687-705`).

Dart `smart_account_client.dart:201-323` runs the same sequence: resolve `sender`/`authorization` (`:210-214`), `isDeployed` + nonce (`:216-230`), factory/initCode (`:232-247`), build UserOp with stub signature (`:261-273`), paymaster stub (`:276-285`), gas estimate (`:293-306`), paymaster final gated on `!stubData.isFinal` (`:309-317`). Signing is a separate step (`signUserOperation`, `:328-331`), matching viem where `sendUserOperation.ts:137-138` signs after `prepareUserOperation`.

Order verdict: mirrors. The remaining findings are about *what happens inside* each step.

## 2. UserOperation partial-override semantics — diverges

viem accepts a partially- or fully-formed UserOperation and only fills what is missing. Every step guards on the caller-supplied value:
- `callData`: uses `parameters.callData` if `calls` absent (`prepareUserOperation.ts:420-435`).
- `factory`/`initCode`: honors `parameters.initCode` / `parameters.factory`+`factoryData` before calling `account.getFactoryArgs()` (`:436-457`).
- `nonce`: `if (typeof parameters.nonce === 'bigint') return parameters.nonce` (`:513-514`).
- `signature`: `if (parameters.signature !== undefined) request.signature = parameters.signature` (`:553-555`).
- gas fields: each is `request.x ?? gas.x` (`:665-677`); if all gas fields are pre-supplied, the estimate RPC is skipped entirely (`:636-644`).

Dart exposes only `nonce` and `sender` as overrides (`smart_account_client.dart:153-160`, `201-208`). `callData` is always computed from `calls` (`:249-258`), `signature` is always the stub then re-signed, gas limits are always estimated and overwritten (`:293-306`, `_applyGasEstimate` `:632-674`), and factory is always derived from the account. There is no way to pass a pre-formed UserOp or pin an individual gas field. Divergence: the Dart pipeline is prescriptive, not fill-the-gaps.

## 3. Fee estimation hook / fallback — missing

viem fills fees inside prepare (`prepareUserOperation.ts:458-511`):
1. If both `maxFeePerGas` and `maxPriorityFeePerGas` are supplied, keep them.
2. Else if `bundlerClient.userOperation.estimateFeesPerGas` hook exists, call it (`:469-479`). This is exactly the seam permissionless.js exposes in `createSmartAccountClient.ts:97-119` (`userOperation.estimateFeesPerGas`) and how a Pimlico gas-price oracle is injected.
3. Else fall back to viem `estimateFeesPerGas` and apply a **2× buffer** on both fields (`:482-507`): `2n * fees.maxFeePerGas`.

Dart makes `maxFeePerGas` and `maxPriorityFeePerGas` **required parameters** on every entry point (`smart_account_client.dart:155-156`, `202-206`, `394-402`, `483-490`). There is no in-pipeline fee hook and no 2× buffer. Fee estimation exists only as *standalone helpers* the caller must invoke and pass in manually: `estimateFees` (`utils/gas.dart:272-291`, 1.1× default) and `estimateFeesFromPimlico` (`utils/gas.dart:305-321`, no buffer). So the automatic "estimateFeesPerGas hook" middleware step is missing, and the 2×-buffer fallback behavior is absent. Practical consequence: a caller who forwards raw `eth_maxPriorityFeePerGas` without buffering will be under viem's effective floor and may be rejected by strict bundlers.

## 4. Gas-limit multipliers / post-estimation defaults — dart-only

viem returns **raw bundler gas estimates** from prepare — it applies no multiplier to `callGasLimit` / `verificationGasLimit` / `preVerificationGas` (`prepareUserOperation.ts:665-677` just does `request.x ?? gas.x`). The only buffer viem applies anywhere is the 2× on *fees* (see #3), not on gas limits.

Dart applies a whole buffering layer that has no counterpart in viem/permissionless.js:
- `GasMultipliers.standard` = 1.1× on verification/call/paymaster limits, 1.0× on preVerification (`utils/gas.dart:34-71`), applied in `_applyGasEstimate` (`smart_account_client.dart:636`) and `_applyGasEstimateV06` (`:681`).
- WebAuthn floor: `withMinimumVerificationGas()` forces `verificationGasLimit ≥ 900_000` for `account.isWebAuthn` (`smart_account_client.dart:640-642`, `utils/gas.dart:165-182`).
- Paymaster gas-limit floor/keep logic: keeps stub values, only takes bundler values `≥ 10_000`, discards sub-10k values (`smart_account_client.dart:648-665`).

These are dart-only. They are defensible (bundlers do sometimes underestimate), but they mean an identical UserOp will carry different gas limits than the viem reference, which can matter for prefund math and paymaster budgeting.

## 5. eth_estimateUserOperationGas params + state override — mirrors

viem `estimateUserOperationGas.ts:187-196`: params are `[formatUserOperationRequest(request), entryPointAddress]`, with `serializeStateOverride(stateOverride)` appended as an optional 3rd element only when present.

Dart `bundler_client.dart:100-114`: params are `[userOp.toJson(), entryPoint.hex]`, appending `stateOverride` as a 3rd element only when non-null. The smart-account client serializes overrides via `stateOverridesToJson` and passes `null` when empty (`smart_account_client.dart:289-305`). Same shape and same conditional-append behavior. Mirrors.

## 6. "Estimate only if missing" + preserve populated fields — diverges

viem only calls `eth_estimateUserOperationGas` when at least one gas field is undefined (`prepareUserOperation.ts:636-644`), and even then merges with `??` so any pre-populated field survives (`:665-677`). It also injects zeroish defaults for the RPC call (`callGasLimit: 0n, preVerificationGas: 0n, verificationGasLimit: 0n`, plus paymaster zeros when a paymaster is set) but lets the spread of `request` override them (`:650-664`).

Dart always calls estimation and always overwrites the three core gas fields from the buffered estimate (`smart_account_client.dart:293-306`, `_applyGasEstimate:667-673`). It builds the UserOp with `BigInt.zero` gas fields up front (`:267-269`) which matches viem's zeroish-default intent, but there is no "skip if already filled" and no `??`-preserve for the core limits (only paymaster limits get keep-logic, #4). Given #2 there is also no way to pre-fill a gas field to preserve. Minor behavioral divergence in the same direction; flagged because a caller cannot opt out of re-estimation.

## 7. Paymaster stub/data param arity & context — diverges

viem `getPaymasterStubData.ts:114-128` and `getPaymasterData.ts:137-151` send **4 positional params**: `[{...request, callGasLimit:'0x0', verificationGasLimit:'0x0', preVerificationGas:'0x0'}, entryPointAddress, numberToHex(chainId), context]`. The `context` slot is **always present** (4th arg), even when `undefined`. viem also force-defaults the three gas fields to `'0x0'` inside the paymaster request, and strips `sponsor` / hoists `paymasterPostOpGasLimit`/`paymasterVerificationGasLimit` to bigint in the return.

Dart `paymaster_client.dart:54-90` sends `[userOp.toJson(), entryPoint.hex, '0x<chainId>', if (context != null) context.toJson()]` — the context slot is **omitted** when null, so the request has only 3 elements. It also does not force `callGasLimit`/`verificationGasLimit`/`preVerificationGas` to `'0x0'` in the paymaster payload (it forwards whatever the UserOp currently holds — zeros at stub time, which happens to coincide, but not guaranteed at final-data time). Divergences:
- Positional context omission can shift a server that reads params by index (viem guarantees chainId at index 2, context at index 3 always).
- No explicit `'0x0'` gas defaulting in the paymaster request body.

## 8. Paymaster `isFinal` short-circuit — mirrors

viem sets `isPaymasterPopulated = isFinal` from stub (`prepareUserOperation.ts:592-602`) and skips `getPaymasterData` when true (`:687-692`). Dart mirrors: `PaymasterStubData.isFinal` (`paymaster/types.dart:34,49-50`) gates the final call via `!stubData.isFinal` (`smart_account_client.dart:309`). Mirrors.

## 9. pm_sponsorUserOperation (v0.6 combined path) — mirrors

permissionless.js `actions/pimlico/sponsorUserOperation.ts:100-107` sends `[deepHexlify(userOp), entryPoint.address, context?]` (2 or 3 params) and branches the response on entryPoint version (v0.6 returns combined `paymasterAndData` + gas, v0.7 returns split fields). Dart `paymaster_client.dart:99-113` sends `[userOp.toJson(), entryPoint.hex, if (context != null) context.toJson()]` and `SponsorUserOperationResult.fromJson` (`paymaster/types.dart:117-162`) branches on presence of `paymasterAndData` to handle both versions. Arity and version-branching match. Mirrors. (Note this is a Pimlico extension used only on the Dart v0.6 path in `prepareUserOperationV06:517-531`; viem's core prepare does not use it.)

## 10. getAccountNonce — mirrors

permissionless.js `actions/public/getAccountNonce.ts:37-74` calls `EntryPoint.getNonce(address sender, uint192 key)` via `readContract`, default `key = 0n`. Dart `public_client.dart:164-180` hand-encodes selector `0x35567e1a` (= `getNonce(address,uint192)`) + left-padded address + `key` padded to 32 bytes, default `key = 0` (`:169`), via `eth_call`, then `parseBigInt`. Selector, argument order, and default key all match; uint192 ABI-encodes into a 32-byte word so the padding is correct. Mirrors.

## 11. getSenderAddress — diverges

permissionless.js `actions/public/getSenderAddress.ts:97-129` uses the **Pimlico `GetSenderAddressHelper` deploy-bytecode trick**: it `encodeDeployData(helperByteCode, [entryPoint, initCode])` and `eth_call`s it *with no `to`* (`:112-122`). The helper contract internally calls `EntryPoint.getSenderAddress`, catches the `SenderAddressResult` revert, and **returns the address as normal return data**, which viem decodes with `decodeAbiParameters([{type:'address'}], data)` (`:128`). If the helper does not produce data, it throws `InvalidEntryPointError` (`:54-70,124-126`).

Dart `public_client.dart:202-258` takes the **opposite mechanism**: it calls `EntryPoint.getSenderAddress(bytes initCode)` directly (selector `0x9b249f69`, `:206-218`), expects it to **revert**, and decodes the address out of the revert error payload by matching the `SenderAddressResult` selector `0x6ca7b806` in `BundlerRpcError.data` (`:229-249`). This depends on the RPC node surfacing revert data inside the JSON-RPC error `data` field (and on the node not swallowing it). It also hand-encodes the `bytes` calldata (offset `0x20`, length, word-padded initCode) rather than using an ABI encoder. Divergence: same goal, structurally different and less node-robust than the helper-bytecode approach permissionless.js uses; nodes that return a bare `execution reverted` without data will fail the Dart path where the JS helper still works.

## 12. waitForUserOperationReceipt — diverges

viem `waitForUserOperationReceipt.ts:69-144`:
- Default **timeout 120_000 ms** (`:77`); polling at `client.pollingInterval` (`:75`).
- On timeout, **throws** `WaitForUserOperationReceiptTimeoutError` (`:99-104,111-115`).
- Error classification while polling: `getUserOperationReceipt` **throws** `UserOperationReceiptNotFoundError` when the receipt is absent (`getUserOperationReceipt.ts:60-61`); wait ignores only that error name and **rejects on any other error** (`:125-128`).

Dart `bundler_client.dart:208-224`:
- Default **timeout 60 s**, polling **2 s** (`:210-211`) — both hard-coded, not derived from a client `pollingInterval`.
- On timeout, **returns `null`** (`:223`) instead of throwing. The whole client API returns `UserOperationReceipt?` (`smart_account_client.dart:428-468`), so a timeout is indistinguishable from any other null.
- `getUserOperationReceipt` returns `null` on absent receipt (`bundler_client.dart:176-185`) rather than throwing, so there is **no not-found-vs-other-error classification** — any RPC exception raised mid-poll propagates directly out of the loop (it is not caught).

Divergences: (a) 60 s vs 120 s default; (b) null-on-timeout vs throw; (c) no distinction between "not found yet" and a real RPC error (viem keeps polling on not-found but rejects on real errors; Dart never sees a not-found error because it maps absence to null, and lets real errors escape unpolled).

## 13. sendUserOperation — mirrors

viem `sendUserOperation.ts:145-155` sends `eth_sendUserOperation` with `{ retryCount: 0 }` so the transport does not retry a broadcast. Dart `bundler_client.dart:55-61` posts once through `JsonRpcClient.call` which has no retry logic at all (`rpc_client.dart:43-84`). Effective behavior matches (single attempt). viem additionally re-wraps failures via `getUserOperationError` for nicer messages (`:156-163`); Dart surfaces a raw `BundlerRpcError` with an `aaErrorCode` extractor (`bundler/types.dart:293-327`) — different error ergonomics, same broadcast semantics. Mirrors.

## 14. getChainId / eth_supportedEntryPoints — mirrors

viem `getSupportedEntryPoints.ts:31-33` → `eth_supportedEntryPoints`. Dart `bundler_client.dart:188-193` calls the same and maps to `EthereumAddress`. viem chain id comes from `client.chain.id` or `getChainId` (`prepareUserOperation.ts:575-581`); Dart `bundler_client.dart:196-200` and `public_client.dart:127-130` call `eth_chainId` and parse. Mirrors.

## 15. Client-level paymasterContext default — missing

viem/permissionless.js let you set `paymasterContext` once on the client (`createSmartAccountClient.ts:94-95,160`) and prepare falls back to it: `parameters.paymasterContext ?? bundlerClient?.paymasterContext` (`prepareUserOperation.ts:401-403`). Dart's `SmartAccountClient` stores no `paymasterContext` field; context must be passed on every `prepareUserOperation`/`sendUserOperation` call (`smart_account_client.dart:158,399,433`). The per-call convenience of a client default is missing.

## 16. Default nonce-key source — diverges (benign for Safe)

viem's generic account `getNonce` defaults the 192-bit key from a **timestamp-based `nonceKeyManager`** (`toSmartAccount.ts:36-43,60-72`) to enable parallel nonces. permissionless.js Safe overrides `getNonce` to use `nonceKey ?? args?.key` (`accounts/safe/toSafeSmartAccount.ts:1780-1786`), which — when unset — bottoms out at `getAccountNonce`'s `key = 0n`, bypassing the timestamp manager. Dart uses a fixed `account.nonceKey` getter defaulting to `BigInt.zero` (`smart_account_interface.dart:100-103`; used at `smart_account_client.dart:225-229`) and has **no `nonceKeyManager`**. For Safe (and any account that fixes its key) the effective default is identical (0). For accounts that rely on viem's timestamp-parallel-nonce default, Dart diverges: it cannot auto-generate distinct parallel nonce keys.

## 17. EIP-7702 authorization in prepare — mirrors (dart-only mechanics)

viem inserts the authorization during the concurrent prepare phase (`prepareUserOperation.ts:517-534`) with a dummy signed authorization (`r/s/yParity` stubbed) for estimation, formatting it as `eip7702Auth` in the RPC request (`userOperationRequest.ts:55-56,61-75`). Dart mirrors the intent: `_createAuthorizationIfNeeded` (`smart_account_client.dart:110-124`) builds it before estimation, estimation and send both attach `eip7702Auth = authorization.toRpcFormat()` (`bundler_client.dart:74-91,122-145`). Dart adds a proprietary `0x7702…0000` factory **marker** normalized to `0x7702` for Pimlico (`smart_account_client.dart:130-131,236-239`; `bundler_client.dart:147-156`) — a dart-only mechanism with no viem equivalent, but the overall behavior (authorization filled pre-estimation, sent alongside the UserOp) mirrors. Note this path targets EntryPoint v0.8, outside viem 0.3.5's default 0.6/0.7 flow.

---

## Summary of actionable gaps

- **Missing fee middleware (#3)** and **missing client paymasterContext (#15)** are the two capability gaps versus permissionless.js: callers must supply fees (and per-call context) themselves, and there is no 2×-buffer fee fallback.
- **getSenderAddress (#11)** and **waitForUserOperationReceipt (#12)** are the two behavioral divergences most likely to bite in production: the revert-decode approach is node-dependent, and null-on-timeout hides failures that viem would throw.
- **Gas multipliers (#4)** and **prescriptive overrides (#2/#6)** mean Dart-produced UserOps will not be byte-identical to viem's for the same inputs; intentional, but worth documenting for anyone cross-checking gas/prefund.

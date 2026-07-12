# Parity Audit 04a — Pimlico and Etherspot Client Extensions

Scope: permissionless.js v0.3.5 `actions/pimlico/*`, `actions/etherspot/*`, `clients/pimlico.ts`, `clients/decorators/pimlico.ts`, `types/pimlico.ts`, `types/etherspot.ts` vs permissionless.dart v0.3.0 `lib/src/clients/pimlico/`, `lib/src/clients/etherspot/`, `lib/src/clients/paymaster/` (plus `lib/src/experimental/pimlico/erc20_paymaster.dart` where it overlaps).

Paths below are abbreviated:

- JS = `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless`
- Dart = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src`

## Priority question (answered)

**Does Dart implement `validateSponsorshipPolicies`, `estimateErc20PaymasterCost`, and `getTokenQuotes`?** Yes — all three exist on `PimlicoClient`:

- `getTokenQuotes` — Dart `clients/pimlico/pimlico_client.dart:160-182` — **mirrors** the JS action.
- `validateSponsorshipPolicies` — Dart `clients/pimlico/pimlico_client.dart:286-309` — exists but **diverges**: it sends RPC method `pimlico_validateSponsorshipPolicies` while JS/Pimlico use `pm_validateSponsorshipPolicies`.
- `estimateErc20PaymasterCost` — Dart `clients/pimlico/pimlico_client.dart:239-255` — exists but **diverges**: it calls a nonexistent RPC method `pimlico_estimateErc20PaymasterCost`, while JS computes the cost locally from `getTokenQuotes` + `getRequiredPrefund`. A correct local-computation variant exists at Dart `experimental/pimlico/erc20_paymaster.dart:312-345`, but it omits `costInUsd`.

## Verdict table

| # | Action | JS | Dart | Verdict |
|---|--------|----|------|---------|
| 1 | `getUserOperationGasPrice` (Pimlico) | `actions/pimlico/getUserOperationGasPrice.ts:49` | `clients/pimlico/pimlico_client.dart:74-77`, `clients/pimlico/types.dart:103-136` | mirrors |
| 2 | `getUserOperationStatus` | `actions/pimlico/getUserOperationStatus.ts:46`, enum `types/pimlico.ts:20-28` | `clients/pimlico/pimlico_client.dart:57-65`, `clients/pimlico/types.dart:9-65` | mirrors |
| 3 | `sendCompressedUserOperation` | `actions/pimlico/sendCompressedUserOperation.ts:56-58`, schema `types/pimlico.ts:57-64` | `clients/pimlico/pimlico_client.dart:90-107` | **diverges** |
| 4 | `sponsorUserOperation` (`pm_sponsorUserOperation`) | `actions/pimlico/sponsorUserOperation.ts:88-151` | `clients/paymaster/paymaster_client.dart:99-113`, `clients/paymaster/types.dart:99-242` | mirrors (see notes) |
| 5 | `validateSponsorshipPolicies` | `actions/pimlico/validateSponsorshipPolicies.ts:67-74` | `clients/pimlico/pimlico_client.dart:286-309` | **diverges** |
| 6 | `getTokenQuotes` | `actions/pimlico/getTokenQuotes.ts:57-77` | `clients/pimlico/pimlico_client.dart:160-182`, `clients/pimlico/types.dart:152-225` | mirrors |
| 7 | `estimateErc20PaymasterCost` | `actions/pimlico/estimateErc20PaymasterCost.ts:60-102` | `clients/pimlico/pimlico_client.dart:239-255` (+ `experimental/pimlico/erc20_paymaster.dart:312-345`) | **diverges** |
| 8 | Etherspot `getUserOperationGasPrice` (`skandha_getGasPrice`) | `actions/etherspot/getUserOperationGasPrice.ts:24-26` | `clients/etherspot/etherspot_client.dart:57-60`, `clients/etherspot/types.dart:24-28` | mirrors |
| 9 | `getSupportedTokens` (`pimlico_getSupportedTokens`) | — (not in JS v0.3.5) | `clients/pimlico/pimlico_client.dart:196-218` | dart-only |
| 10 | `waitForUserOperationStatus` | — | `clients/pimlico/pimlico_client.dart:113-136` | dart-only |

Counts: 5 mirrors, 3 diverges, 0 missing, 2 dart-only.

Architecture note (not a verdict): JS `createPimlicoClient` (`clients/pimlico.ts:96-124`) composes bundler + paymaster + pimlico actions on one client. Dart splits this: `PimlicoClient extends BundlerClient` (`clients/pimlico/pimlico_client.dart:34`) carries the `pimlico_*` methods, while `pm_*` sponsorship methods live on the separate `PaymasterClient` (`clients/paymaster/paymaster_client.dart:35`). Behavior per method is what is audited below.

---

## Finding 3: `sendCompressedUserOperation` — diverges (wrong param shape, would fail at runtime)

**JS** sends exactly 3 params, first being the pre-compressed calldata hex blob:

- `actions/pimlico/sendCompressedUserOperation.ts:56-58`:
  `params: [compressedUserOperation, inflatorAddress, entryPointAddress]`
- Schema confirms: `types/pimlico.ts:57-64` — `Parameters: [compressedUserOperation: Hex, inflatorAddress: Address, entryPoint: Address]`.
- JS also marks the action `@deprecated` (`sendCompressedUserOperation.ts:20`, `clients/decorators/pimlico.ts:86`) since EIP-4844.

**Dart** sends 4 params in a different order, with a full user-operation JSON map first (`clients/pimlico/pimlico_client.dart:97-105`):

```dart
final result = await rpcClient.call(
  'pimlico_sendCompressedUserOperation',
  [
    packedUserOp,          // <-- not in the JS/Pimlico API at all
    entryPoint.hex,
    compressedCalldata,
    inflator.hex,
  ],
);
```

Impact:

- Param 1 should be the compressed hex string, param 2 the inflator address, param 3 the entryPoint. Dart's call does not match the API and would be rejected by Pimlico's bundler.
- Dart's signature also demands the uncompressed `UserOperationV07` (`pimlico_client.dart:90-94`), which the RPC method never receives in JS.
- No deprecation notice on the Dart side.

Suggested fix: change the Dart method to `sendCompressedUserOperation(String compressedUserOperation, EthereumAddress inflator)` sending `[compressedUserOperation, inflator.hex, entryPoint.hex]`, and mark it deprecated.

## Finding 5: `validateSponsorshipPolicies` — diverges (wrong RPC method name; v0.7-only; unpacked vs packed userop)

**JS** (`actions/pimlico/validateSponsorshipPolicies.ts:67-73`):

```ts
method: "pm_validateSponsorshipPolicies",
params: [deepHexlify(args.userOperation), args.entryPointAddress, args.sponsorshipPolicyIds]
```

Schema: `types/pimlico.ts:126-131` — method is `pm_validateSponsorshipPolicies` and the userOperation may be any entry-point version.

**Dart** (`clients/pimlico/pimlico_client.dart:296-303`):

```dart
final result = await rpcClient.call(
  'pimlico_validateSponsorshipPolicies',   // wrong prefix: should be pm_
  [ packedUserOp, entryPoint.hex, sponsorshipPolicyIds ],
);
```

Divergences:

1. **RPC method name**: `pimlico_validateSponsorshipPolicies` vs JS `pm_validateSponsorshipPolicies`. Pimlico's endpoint is `pm_`-prefixed; the Dart call will get "method not found".
2. **v0.7 only**: Dart takes `required UserOperationV07 userOperation` (`pimlico_client.dart:287`); JS accepts any `UserOperation` (v0.6 included).
3. Param 1 serialization: both send the unpacked v0.7 shape with hex fields (Dart `_packUserOperationV07`, `pimlico_client.dart:339-369`, matches JS `deepHexlify` output for v0.7, modulo Dart omitting `factory`/`paymaster` groups when absent, which JS also effectively does since undefined keys are dropped in JSON). This part is fine.
4. Minor: Dart short-circuits to `[]` on empty `sponsorshipPolicyIds` (`pimlico_client.dart:290-292`); JS always issues the request. Harmless.
5. Response parsing: Dart `PimlicoSponsorshipPolicyData.fromJson` (`clients/pimlico/types.dart:295-301`) casts `name`/`author` with `as String` (non-null), but the JS type declares them `string | null` (`validateSponsorshipPolicies.ts:15-19`). A null `name`/`author` would throw a cast error in Dart.

Suggested fix: rename the RPC string to `pm_validateSponsorshipPolicies`, accept both entry-point versions, and make `name`/`author`/`icon`/`description` nullable in parsing.

## Finding 7: `estimateErc20PaymasterCost` — diverges (RPC call to a method that does not exist; JS computes locally)

**JS** performs no dedicated RPC call. `actions/pimlico/estimateErc20PaymasterCost.ts:60-102` fetches quotes via `getTokenQuotes` and computes:

```ts
const userOperationMaxCost = getRequiredPrefund({ userOperation, entryPointVersion })   // :83
const maxCostInWei = userOperationMaxCost + postOpGas * userOperation.maxFeePerGas      // :89
const costInToken = (maxCostInWei * exchangeRate) / BigInt(1e18)                        // :93
const costInUsd = (maxCostInWei * exchangeRateNativeToUsd) / 10n ** 18n                 // :96
```

There is no `pimlico_estimateErc20PaymasterCost` entry anywhere in the JS RPC schema (`types/pimlico.ts`).

**Dart** `PimlicoClient.estimateErc20PaymasterCost` (`clients/pimlico/pimlico_client.dart:245-252`) instead issues:

```dart
final result = await rpcClient.call(
  'pimlico_estimateErc20PaymasterCost',
  [ packedUserOp, entryPoint.hex, token.hex ],
);
```

This RPC method is not part of Pimlico's API (per the JS reference schema), so the client method will fail with "method not found" against a real endpoint. Its return type `PimlicoErc20PaymasterCost` (`clients/pimlico/types.dart:366-399`) also documents `costInUsd` as 8-decimal, whereas JS documents 6 decimals (`estimateErc20PaymasterCost.ts:19` "10^6 decimals"; the code divides by 10^18 with `exchangeRateNativeToUsd` being 6-decimal per `getTokenQuotes`).

Dart does have a behaviorally correct local-computation counterpart at `experimental/pimlico/erc20_paymaster.dart:312-345`:

- Gas sum (`erc20_paymaster.dart:326-332`) matches JS `getRequiredPrefund` for v0.7 (`utils/getRequiredPrefund.ts:36-45`): preVerificationGas + callGasLimit + verificationGasLimit + paymasterVerificationGasLimit + paymasterPostOpGasLimit, times maxFeePerGas.
- `maxCostInToken` formula (`erc20_paymaster.dart:334-337`) matches JS `costInToken` (`estimateErc20PaymasterCost.ts:89-93`).
- However it returns `Erc20CostEstimate` with **no `costInUsd`** (`erc20_paymaster.dart:339-344`), it is v0.7-only, and it lives under `experimental/` rather than on the client where JS exposes it (`clients/decorators/pimlico.ts:140-152, 186-191`).

Suggested fix: reimplement `PimlicoClient.estimateErc20PaymasterCost` as a local computation delegating to `getTokenQuotes` (like the experimental helper), add `costInUsd = maxCostInWei * exchangeRateNativeToUsd / 1e18`, support v0.6 via the prefund multiplier rule (`getRequiredPrefund.ts:20-33`), and remove the fictitious RPC method string.

---

## Mirrors — supporting evidence

**1. Pimlico `getUserOperationGasPrice`.** JS `pimlico_getUserOperationGasPrice` with `params: []`, mapping slow/standard/fast `{maxFeePerGas, maxPriorityFeePerGas}` to bigint (`actions/pimlico/getUserOperationGasPrice.ts:48-66`). Dart identical: method at `clients/pimlico/pimlico_client.dart:75` (the RPC client defaults `params` to `[]`, `clients/bundler/rpc_client.dart:43-51`), three tiers parsed to `BigInt` at `clients/pimlico/types.dart:82-86, 116-122`.

**2. Pimlico `getUserOperationStatus`.** JS `pimlico_getUserOperationStatus` with `params: [hash]` (`actions/pimlico/getUserOperationStatus.ts:46-48`); status enum `not_found | not_submitted | submitted | rejected | reverted | included | failed` (`types/pimlico.ts:20-28`). Dart identical method/params (`clients/pimlico/pimlico_client.dart:60-63`) and the same seven documented status strings (`clients/pimlico/types.dart:36-44`); status is kept as `String` rather than an enum, so unknown values pass through (lenient superset). Dart additionally parses an optional `receipt` field (`types.dart:23-31`) not present in the JS type — harmless extra.

**4. `pm_sponsorUserOperation`.** JS params: `[deepHexlify(userOperation), entryPoint.address, finalPaymasterContext?]` where `sponsorshipPolicyId` is merged into the paymaster context (`actions/pimlico/sponsorUserOperation.ts:91-107`). Dart `PaymasterClient.sponsorUserOperation` sends `[userOp.toJson(), entryPoint.hex, context?]` (`clients/paymaster/paymaster_client.dart:105-111`); `PaymasterContext.toJson` emits `sponsorshipPolicyId`, `token`, and arbitrary extras (`clients/paymaster/types.dart:236-241`), and `UserOperationV07.toJson` hexlifies BigInts identically to `deepHexlify` (`types/user_operation.dart:380-415`). Response: JS branches on entry-point version, BigInt-converting gas fields and returning `paymasterAndData` (v0.6) or `paymaster/paymasterData/...` (v0.7) (`sponsorUserOperation.ts:109-151`); Dart `SponsorUserOperationResult.fromJson` key-sniffs `paymasterAndData` vs `paymaster` and BigInt-converts the same fields (`clients/paymaster/types.dart:117-162`), and `withSponsorshipV06` re-concatenates paymaster+data back into `paymasterAndData` (`paymaster_client.dart:201-211`) — behaviorally equivalent. Notes (not verdict-changing):

- JS allows the userOperation's gas fields to be absent (`PartialBy<...>`; `sponsorUserOperation.ts:27-43`) so the paymaster can estimate; Dart `UserOperationV07` requires all gas fields (`types/user_operation.dart:250-258`), forcing callers to send explicit zeros instead of omitting the keys.
- Dart's method lives on `PaymasterClient`, not `PimlicoClient`; a `PimlicoClient` instance cannot sponsor directly, unlike JS `createPimlicoClient` output.
- `PaymasterRpcError` (`clients/paymaster/types.dart:245-269`) is declared but never thrown; errors surface as `BundlerRpcError` from `clients/bundler/rpc_client.dart:74-82` with the same code/message/data fields.

**6. `pimlico_getTokenQuotes`.** JS params `[{ tokens }, entryPointAddress, numberToHex(chainId)]`, response `{ quotes: [...] }` with `postOpGas/exchangeRate/exchangeRateNativeToUsd` hex-to-BigInt and optional `balanceSlot/allowanceSlot` (`actions/pimlico/getTokenQuotes.ts:57-77`). Dart identical param shape and order (`clients/pimlico/pimlico_client.dart:164-173`), unwraps `quotes` (`:177`), same BigInt conversions with optional slots (`clients/pimlico/types.dart:169-184`). Two benign differences: Dart resolves chainId via an `eth_chainId` RPC round-trip (`pimlico_client.dart:163`) instead of client config (JS throws `ChainNotFoundError` when unset, `getTokenQuotes.ts:53-55`); and Dart treats `exchangeRateNativeToUsd` as nullable (`types.dart:175-177`) where JS assumes it present — Dart is the lenient side.

**8. Etherspot `skandha_getGasPrice`.** JS: method with `params: []`, both fields `BigInt(...)` (`actions/etherspot/getUserOperationGasPrice.ts:24-31`). Dart identical (`clients/etherspot/etherspot_client.dart:58-59`, `clients/etherspot/types.dart:24-28`; `parseBigInt` accepts hex or decimal strings, matching `BigInt(string)` behavior). JS has no dedicated Etherspot client/decorator in v0.3.5 (only the barrel `actions/etherspot.ts`); Dart's `EtherspotClient extends BundlerClient` (`etherspot_client.dart:29`) is a reasonable structural equivalent and adds nothing beyond this one method.

## Dart-only items

**9. `getSupportedTokens` (`pimlico_getSupportedTokens`)** — `clients/pimlico/pimlico_client.dart:196-218`, types at `clients/pimlico/types.dart:239-275`. No counterpart anywhere in permissionless.js v0.3.5 (grep for `getSupportedTokens` returns nothing). Useful extension; flag as intentional dart-only surface.

**10. `waitForUserOperationStatus`** — polling helper over `getUserOperationStatus` with terminal-state detection (`clients/pimlico/pimlico_client.dart:113-136`). No JS counterpart (JS relies on viem's `waitForUserOperationReceipt`). Dart-only convenience.

Also noted: `experimental/pimlico/erc20_paymaster.dart` (`prepareUserOperationForErc20Paymaster`, lines 103-294) parallels JS `experimental/pimlico/` — that surface belongs to the experimental audit unit; here it was only consulted for Finding 7.

# Parity Audit 06 — Experimental APIs, Error Taxonomy, Primitive Types

Unit scope: `experimental/` (Pimlico ERC-20 paymaster), `errors/`, and `types/`
(pimlico, etherspot, passkeyServer on the JS side; address, hex, calls_status,
typed_data, eip7702 on the Dart side — `user_operation.dart` excluded, covered
by another unit).

- JS reference: `permissionless.js` v0.3.5 —
  `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless`
- Dart port: `permissionless.dart` v0.3.0 —
  `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless`
- Behavioral reference for viem primitives:
  `/Users/liorag/Documents/development/permissionless/viem`

Method: behavior comparison, not surface comparison. Where the JS side gets a
primitive from viem (hashTypedData, hashAuthorization, hexToBytes, AA error
mapping, EIP-5792 statuses), the viem source was used as the reference.

## Verdict table

| # | Aspect | Verdict |
|---|--------|---------|
| 1 | ERC-20 paymaster: token quote fetch + empty-quote error | mirrors |
| 2 | ERC-20 paymaster: dummy max-approval injection + USDT zero-approval (estimation round) | mirrors |
| 3 | ERC-20 paymaster: balance state override (default balance, slot fallback, missing-slot error) | mirrors |
| 4 | ERC-20 paymaster: paymaster **stub** substitution during estimation round | **diverges** |
| 5 | ERC-20 paymaster: `maxCostInToken` formula | mirrors |
| 6 | ERC-20 paymaster: allowance read + conditional exact-amount approval + USDT reset (final round) | mirrors |
| 7 | ERC-20 paymaster: final calldata re-encode + fresh paymaster data with context | mirrors |
| 8 | ERC-20 paymaster: API shape (decorator, `decodeCalls`, non-token passthrough, stateOverride merge) | **diverges** |
| 9 | `estimateErc20PaymasterCost` / `Erc20CostEstimate` | **dart-only** |
| 10 | Errors: `AccountNotFoundError` | **missing** |
| 11 | Errors: AA## bundler error mapping / revert-reason parsing | **diverges** |
| 12 | Errors: `PermissionlessException` taxonomy (`InvalidAddress`, `UnsupportedVersion`, `Rpc`, `Signature`, `BundlerRpcError`) | **dart-only** |
| 13 | Address: EIP-55 checksum validation/formatting | mirrors |
| 14 | Hex: validation, padding, concat, slice, BigInt round-trip | mirrors |
| 15 | EIP-712: hashStruct / domain separator / type encoding / array & nested-struct hashing | mirrors |
| 16 | EIP-712: edge cases (custom `EIP712Domain` type, value validation, non-ASCII type names) | **diverges** |
| 17 | calls_status: core EIP-5792 mapping (100/200/500, `version`, `atomic`, receipt shape) | mirrors |
| 18 | calls_status: legacy status strings + out-of-range code classification | **diverges** (minor) |
| 19 | EIP-7702: authorization hash + RPC tuple shape vs viem | mirrors |
| 20 | passkeyServer (types + client) | **missing** |
| 21 | types/pimlico.ts RPC surface (gas price tiers, op status strings, token quote fields) | mirrors |
| 22 | types/etherspot.ts (`skandha_getGasPrice`) | mirrors |

**Totals: 12 mirrors, 5 diverges, 2 missing, 2 dart-only** (verdict rows 1–22;
tallied by row).

Mirrors evidence (abbreviated citations, JS → Dart):

- (1) `experimental/pimlico/utils/prepareUserOperationForErc20Paymaster.ts:103-119` → `lib/src/experimental/pimlico/erc20_paymaster.dart:115-120` (error class differs: viem `RpcError` vs Dart `ArgumentError`, but both throw on empty quotes and use `quotes[0]`).
- (2) JS `...ts:134-152` (max-uint dummy approve prepended, USDT `0` approve unshifted first) → Dart `...erc20_paymaster.dart:127-149` (same ordering; same mainnet USDT constant, JS `...ts:31-33` vs Dart `...:19-20`).
- (3) JS `...ts:158-174` + `utils/erc20BalanceOverride.ts:20-48` (default balance `0x100...FFF...F`, `keccak256(abi.encode(owner, slot))`) → Dart `...erc20_paymaster.dart:152-166` + `lib/src/utils/erc20.dart:305-308,411-440` (identical constant and slot derivation); missing-slot error JS `...ts:161-165` → Dart `...:155-160`.
- (5) JS `...ts:223-238` → Dart `...erc20_paymaster.dart:181-194` — identical gas sum (preVerification + call + verification + postOp + paymasterVerification), identical singleton-paymaster formula `((maxCost + postOpGas*maxFeePerGas) * exchangeRate) / 1e18` with floor division.
- (6) JS `...ts:247-279` (on-chain `allowance(owner, paymaster)` read; skip if `allowance >= maxCostInToken`; else unshift exact-amount approve, USDT zero-approve first) → Dart `...erc20_paymaster.dart:197-236` (same reads, same threshold, same ordering).
- (7) JS `...ts:281-346` (re-`encodeCalls` final calls, re-fetch paymaster data with `context: paymasterContext` and estimated gas fields, merge into returned op) → Dart `...erc20_paymaster.dart:239-286` (same: final callData, `getPaymasterData(... context: paymasterContext)`, gas limits carried from the dummy-approval estimation).
- (13) Dart `lib/src/types/address.dart:13-36` delegates to `wallet` 0.0.18 (`~/.pub-cache/hosted/pub.dev/wallet-0.0.18/lib/src/ethereum/ethereum_address.dart:60,79-81,93`): `fromHex` lowercases `with0x`, computes `eip55With0x` checksum, and `isEip55ValidEthereumAddress` verifies checksum only for mixed-case input — behaviorally matching viem `getAddress`/`isAddress`. (Note: Dart's `.hex` getter emits lowercase where viem emits checksummed; both are valid on the wire.)
- (14) Dart `lib/src/types/hex.dart:41-58` (padLeft/padRight per byte length ≈ viem `pad`), `:61-68` (concat ≈ `concatHex`), `:74-79` (slice ≈ `slice`), `:82-95` (fromBigInt/toBigInt ≈ `numberToHex`/`hexToBigInt`, both emit minimal odd-length hex for e.g. 256 → `0x100`), `:17-22` (decode left-pads odd-length input exactly like viem `hexToBytes`, `viem/src/utils/encoding/toBytes.ts` `if (hexString.length % 2) hexString = '0'+hexString`). Trivial edge deltas only: `Hex.toBigInt('0x')` returns 0 and `Hex.isValid('0x')` returns true where viem throws/rejects empty in some paths.
- (15) Dart `lib/src/utils/message_hash.dart:52-67` (`keccak256("\x19\x01" ++ domainSeparator ++ hashStruct)`), `:73-107` (domain type built from present fields in the canonical name/version/chainId/verifyingContract/salt order), `:112-122` + `:139-163` (typeHash with recursively-collected referenced types sorted alphabetically), `:228-243` (arrays: keccak of concatenated encoded elements; nested structs: recursive hashStruct), `:246-310` (string/bytes keccak'd, bool/uint/int as uint256 with two's complement, bytesN right-padded via `encoding.dart:45`) — all matching viem `hashTypedData`/`hashStruct` semantics.
- (17) JS `actions/smartAccount/getCallsStatus.ts:16-91` → Dart `lib/src/actions/smart_account/smart_account_actions.dart:210-259` — both derive status from `getUserOperationReceipt`: success→200, revert→500, receipt-missing→pending/100; `version: '1.0'`, `atomic: true`; receipt fields (status/logs/blockHash/blockNumber/gasUsed/transactionHash) match, Dart `CallsStatus`/`CallReceipt` types at `lib/src/types/calls_status.dart:83-159,14-68`.
- (19) See section below (mirrors, with one cosmetic note).
- (21) JS `types/pimlico.ts:4-17` (slow/standard/fast tiers), `:19-29` (status strings `not_found|not_submitted|submitted|rejected|reverted|included|failed`), `:31-41` (quote fields paymaster/token/postOpGas/exchangeRate/exchangeRateNativeToUsd/balanceSlot?/allowanceSlot?) → Dart `lib/src/clients/pimlico/types.dart:9-60` (same status string set incl. helpers), `:152-176` (same quote fields incl. optional `balanceSlot`/`allowanceSlot`).
- (22) JS `types/etherspot.ts:1-12` (`skandha_getGasPrice` → maxFeePerGas/maxPriorityFeePerGas) → Dart `lib/src/clients/etherspot/etherspot_client.dart:45-58` + `lib/src/clients/etherspot/types.dart:23`.

---

## Finding 4 (diverges) — No paymaster-stub substitution during the ERC-20 estimation round

**JS** — `experimental/pimlico/utils/prepareUserOperationForErc20Paymaster.ts:188-217`:
during the first `prepareUserOperation` (the one carrying the dummy max
approval), JS deliberately replaces the paymaster's `getPaymasterData` with
`getPaymasterStubData`:

```ts
paymaster: {
    getPaymasterData: (args) => {
        ...
        if (getPaymasterStubData) return getPaymasterStubData(args)
        return getAction(bundlerClient, getPaymasterData_, ...)(args)
    }
}
```

So the real (signed) paymaster data is fetched exactly once — at the end
(`...ts:341-346`) — against the final calldata.

**Dart** — `lib/src/experimental/pimlico/erc20_paymaster.dart:171-178` calls the
ordinary `smartAccountClient.prepareUserOperation(...)`, and that flow runs
*both* `getPaymasterStubData` **and** the real `getPaymasterData`
(`lib/src/clients/smart_account/smart_account_client.dart:278` and `:310`).
Dart then fetches paymaster data a second time for the final calldata
(`erc20_paymaster.dart:249-266`).

**Impact**: the final returned operation is equivalent (last `getPaymasterData`
wins in both), but Dart issues one extra `pm_getPaymasterData` round-trip per
preparation, and the paymaster signs an intermediate operation (with the dummy
max approval) whose signature is discarded. With rate-limited or
signature-audited paymasters this is observable behavior, not just cost.

## Finding 8 (diverges) — API shape: standalone function vs prepareUserOperation decorator

**JS** — `...prepareUserOperationForErc20Paymaster.ts:35-65` is a higher-order
decorator over viem's `prepareUserOperation`:

- If `paymasterContext` has no `token`, it transparently falls back to plain
  `prepareUserOperation` (`...ts:78-83`, `:359-369`).
- If the caller passed raw `callData`, it recovers calls via
  `account.decodeCalls` (`...ts:129-131`).
- A caller-supplied `stateOverride` is *merged* with the balance override
  (`...ts:176-186`).
- Returns a standard `PrepareUserOperationReturnType` (`...ts:348-356`).

**Dart** — `lib/src/experimental/pimlico/erc20_paymaster.dart:103-113` is a
standalone function with required `token`, `calls`, `maxFeePerGas`,
`maxPriorityFeePerGas` and three explicit clients:

- No non-token fallback path (token is a required parameter).
- No `callData`→calls decoding path (calls list is required; no
  `decodeCalls` equivalent).
- No caller `stateOverride` parameter — the balance override is the only
  override passed (`...:152-166,177`).
- Returns a bespoke `Erc20PaymasterResult` wrapper (`...:46-68`) carrying the
  op plus `tokenQuote`, `maxCostInToken`, `approvalInjected`, instead of the
  bare prepared operation.

**Impact**: the core flow (findings 1–3, 5–7) mirrors, but callers cannot use
this as a drop-in `prepareUserOperation` middleware, cannot combine it with
their own state overrides, and cannot feed pre-encoded calldata. The extra
metadata in the result is a usability addition with no JS counterpart.

## Finding 9 (dart-only) — `estimateErc20PaymasterCost` / `Erc20CostEstimate`

Dart `lib/src/experimental/pimlico/erc20_paymaster.dart:312-374` adds a
quote-only cost estimator (same formula as finding 5) returning
`Erc20CostEstimate{maxCostInToken, exchangeRate, postOpGas, paymasterAddress}`.
No JS counterpart in `experimental/pimlico/index.ts:1` (which exports only
`prepareUserOperationForErc20Paymaster`). Benign addition; flag for doc parity
only.

## Finding 10 (missing) — `AccountNotFoundError`

**JS** — `errors/index.ts:3-17` defines the package's single error class,
`AccountNotFoundError extends BaseError` ("Could not find an Account to
execute with this Action...", `docsSlug: "account"`), thrown across actions
(e.g. `actions/smartAccount/sendTransaction.ts`,
`actions/erc7579/installModule.ts`) when `client.account` is undefined.

**Dart** — `lib/src/errors/errors.dart:1-49` has no equivalent. Structurally
the condition is near-impossible in Dart: `SmartAccountClient` binds the
account at construction, so an "account not found" state cannot arise at
action time. Verdict recorded as **missing** per the surface, but severity is
negligible; if constructors ever accept account-less clients, a typed
equivalent should be added rather than a bare `StateError` (compare
`erc20_paymaster.dart:243-247`, which throws `StateError` for the analogous
"paymaster not configured" case where JS throws a plain `Error`,
`...prepareUserOperationForErc20Paymaster.ts:332-334`).

## Finding 11 (diverges) — AA## bundler error taxonomy / revert-reason parsing

**JS** — inherits viem's full typed AA error mapping: every ERC-4337 code has
a `BaseError` subclass with a regex matcher (e.g. `InitCodeFailedError` with
`static message = /aa10/`,
`viem/src/account-abstraction/errors/bundler.ts:122-149,485`) and
`getBundlerError`
(`viem/src/account-abstraction/utils/errors/getBundlerError.ts:133`) parses
bundler revert reasons/messages into those classes, which viem's
`UserOperationExecutionError` machinery then surfaces with docs links and
human-readable causes.

**Dart** — `lib/src/clients/bundler/types.dart:293-328` defines a single
`BundlerRpcError{code, message, data}` whose only AA handling is a regex
extraction:

```dart
String? get aaErrorCode {
    if (data == null) return null;
    final match = RegExp(r'AA\d+').firstMatch(data.toString());
    return match?.group(0);
}
```

Notable gaps versus JS behavior:

1. No per-code typed classes — callers must string-match `aaErrorCode`
   themselves; no human-readable explanation is attached.
2. The regex only scans `data`, while viem's matchers scan `details`/message
   (`getBundlerError` matches on the error message). Bundlers that put
   `AA23 reverted` in `message` with empty `data` yield `aaErrorCode == null`
   in Dart.
3. Case sensitivity: viem matches `/aa10/` against a lowercased message;
   Dart's `AA\d+` misses lowercase `aa23` variants some bundlers emit.
4. No execution-revert reason decoding (viem additionally decodes contract
   revert data into `ContractFunctionRevertedError`); Dart passes `data`
   through verbatim.

## Finding 12 (dart-only) — `PermissionlessException` taxonomy

Dart `lib/src/errors/errors.dart` defines `PermissionlessException` (`:2-15`,
message + optional cause), `InvalidAddressException` (`:18-21`),
`UnsupportedVersionException` (`:24-29`, Safe/EntryPoint combination),
`RpcException` (`:32-44`, with optional numeric code), and
`SignatureException` (`:47-49`). None of these exist in JS: address
validation errors come from viem (`InvalidAddressError`), version mismatches
throw plain `Error`s inside account constructors, and RPC errors are viem
`RpcError`s. Dart's hierarchy is a reasonable idiom-level substitute; recorded
dart-only for surface tracking.

## Finding 16 (diverges) — EIP-712 edge cases

Core hashing mirrors viem (see verdict table, row 15). Three edge behaviors
diverge from viem's `hashTypedData`:

1. **Custom `EIP712Domain` type is ignored.** viem uses
   `types.EIP712Domain` when the caller supplies it (allowing nonstandard
   domain field sets/ordering); Dart hardcodes the domain struct from whichever
   of the five standard fields are non-null
   (`lib/src/utils/message_hash.dart:73-107`) and `TypedData.types` doc says
   the domain type "should not be included"
   (`lib/src/types/typed_data.dart:140-144`). Same result for standard
   domains; different result for exotic ones.
2. **No value validation.** viem's `validateTypedData` rejects out-of-range
   `uintN`/`intN`, oversized `bytesN`, and invalid addresses before hashing;
   Dart encodes everything as uint256/bytes32 without range checks
   (`message_hash.dart:246-310`), so a value that viem rejects hashes
   "successfully" (to a different digest than any correct signer would
   produce). Also `bytesN` size is not checked against N — any hex up to 32
   bytes is right-padded (`message_hash.dart:274-279`,
   `lib/src/utils/encoding.dart:45`).
3. **Type-string hashing uses `codeUnits`, not UTF-8**
   (`message_hash.dart:132` and `:84`): identical to viem for ASCII type
   names, divergent for non-ASCII struct/field names (viem hashes UTF-8
   bytes via `toHex(string)`).

All three are edge-case-only; every account implementation in the package uses
ASCII types and standard domains, so on-path behavior matches (verified digests
are exercised by `hashTypedData` call sites, e.g.
`lib/src/accounts/safe/safe_account.dart:876`).

## Finding 18 (diverges, minor) — EIP-5792 status classification edges

**JS** — `actions/smartAccount/getCallsStatus.ts:16-33`: 100–199 pending,
200–299 success, **300–699 failure**, plus backwards-compat for legacy string
statuses `"CONFIRMED"` → success/200 and `"PENDING"` → pending/100; anything
else yields `status: undefined` with the raw code.

**Dart** — `lib/src/types/calls_status.dart:96-105`: 100–199 pending, 200–299
success, **everything else failure** (including codes < 100 and ≥ 700, which
JS would classify as `undefined`); no legacy `"CONFIRMED"`/`"PENDING"` string
handling (`statusCode` is cast `as int` at `:97`, so a legacy string payload
throws a `TypeError` instead).

Impact is confined to `CallsStatus.fromJson` on nonstandard payloads; the
primary path (`getCallsStatus` action, finding 17) only ever produces
100/200/500 on both sides.

## Finding 19 (mirrors) — EIP-7702 authorization, recorded for evidence

Hash: Dart `lib/src/types/eip7702.dart:126-143` computes
`keccak256(0x05 || rlp([chainId, address, nonce]))` with zero values RLP-encoded
as empty strings (`_rlpEncodeBigInt(0)` → `0x80`, `:177-180`), matching viem
`hashAuthorization`
(`viem/src/utils/authorization/hashAuthorization.ts:38-47`:
`concatHex(['0x05', toRlp([chainId ? hex : '0x', address, nonce ? hex : '0x'])])`).
The hash is signed raw (no double keccak), `eip7702.dart:105-111`.

RPC tuple: Dart `toRpcFormat()` (`eip7702.dart:235-247`) emits
`{chainId, address, nonce, yParity, r, s}` all hex-encoded with
`yParity = v - 27`, matching viem's `formatAuthorizationList`
(`viem/src/utils/formatters/transactionRequest.ts:92-111`). One cosmetic
delta: Dart pads yParity to one byte (`0x00`/`0x01`) where viem's
`numberToHex` emits `0x0`/`0x1`; both are accepted hex quantities. Dart also
keeps a legacy `toJson()` with a `v` field (`eip7702.dart:219-226`) that has
no viem counterpart — unused by the bundler path.

## Finding 20 (missing) — passkeyServer

**JS surface** (`types/passkeyServer.ts:1-125`) — `PasskeyServerRpcSchema`
with five methods (consumed by the passkey-server client/actions elsewhere in
the JS package):

| Method | Params | Returns |
|---|---|---|
| `pks_startAuthentication` | `[]` | `{challenge, rpId, timeout?, userVerification? ('required'\|'preferred'\|'discouraged'), uuid}` |
| `pks_startRegistration` | `[context]` | WebAuthn creation options: `{rp{id,name}, user{id,name,displayName}, challenge, timeout?, authenticatorSelection?{authenticatorAttachment?, requireResidentKey?, residentKey?, userVerification?}, attestation ('direct'\|'enterprise'\|'indirect'\|'none'), extensions?{appid?, credProps?, hmacCreateSecret?, minPinLength?}}` |
| `pks_verifyRegistration` | `[credential, context]` — credential: `{id, rawId, response{clientDataJSON, attestationObject, authenticatorData?, transports?, publicKeyAlgorithm?, publicKeyType?}, authenticatorAttachment, clientExtensionResults, type:'public-key'}` | `{success, id, publicKey: Hex, userName}` |
| `pks_verifyAuthentication` | `[credential, context]` — credential: `{id, rawId, response{clientDataJSON, authenticatorData, signature, userHandle?}, authenticatorAttachment, clientExtensionResults, type:'public-key'}` | `{success, id, publicKey: Hex, userName}` |
| `pks_getCredentials` | `[context]` | `{id, publicKey: Hex}[]` |

**Dart** — no counterpart anywhere under `lib/src/` (no `pks_` strings, no
passkey-server client/types). This is the known-missing passkeyServer port;
verdict **missing**. Note the Dart package does have a `webauthn_owner.dart`
(signing side), but nothing that speaks the `pks_*` server protocol.

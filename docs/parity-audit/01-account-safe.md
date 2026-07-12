# Parity Audit: Safe Smart Account

**JS reference:** permissionless.js v0.3.5 — `accounts/safe/toSafeSmartAccount.ts` (2017 lines), `accounts/safe/signUserOperation.ts` (316 lines)
**Dart port:** permissionless.dart v0.3.0 — `lib/src/accounts/safe/safe_account.dart` (1181 lines), `lib/src/accounts/safe/constants.dart` (226 lines), plus helpers in `lib/src/utils/{encoding,multisend,erc7579,webauthn_encoding}.dart`

Paths below are relative to:

- JS: `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless/`
- Dart: `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/`

Scope: behavioral, byte-level comparison of addresses, CREATE2/initcode derivation, setup calldata (incl. `useMultiSendForSetup`), MultiSend usage, dummy signature, `signUserOperation` (incl. V adjustment), EIP-712 SafeOp domain/typehashes, validAfter/validUntil packing, ERC-7579 launchpad path, nonce key handling, and Safe4337 module addresses.

## Verdict table

| # | Aspect | Verdict |
|---|--------|---------|
| 1 | Safe v1.4.1 addresses (EP v0.6 + v0.7, all 8 contracts) | mirrors |
| 2 | Safe v1.5.0 addresses | **diverges** (MULTI_SEND_CALL_ONLY) |
| 3 | Safe4337 module addresses (0xa581… v0.6 / 0x75cf… v0.7) | mirrors |
| 4 | CREATE2 salt / deploymentCode / address math | mirrors |
| 5 | Proxy creation code source (RPC read vs hardcoded constant) | **diverges** (conditional — unverified for v1.5.0 factory) |
| 6 | factory/factoryData: `createProxyWithNonce` encoding | mirrors |
| 7 | Setup initializer (enableModules via MultiSend delegatecall, fallbackHandler = 4337 module, payment zeros) | mirrors |
| 8 | `useMultiSendForSetup: false` fast path (JS 0.3.5 feature) | mirrors |
| 9 | Default threshold | **diverges** |
| 10 | `setupTransactions` / `safeModules` / `paymentToken`/`payment`/`paymentReceiver` params | **missing** |
| 11 | Single-call encoding (`executeUserOpWithErrorString`, operation 0) | mirrors |
| 12 | Batch-call encoding target contract | **diverges** (MultiSend vs MultiSendCallOnly) |
| 13 | `onchainIdentifier` calldata suffix | **missing** |
| 14 | `decodeCalls` | **missing** (introspection only) |
| 15 | Stub signature — ECDSA dummy bytes | **diverges** |
| 16 | Stub signature — WebAuthn dummy bytes | **diverges** |
| 17 | Stub signature — structure (uint48/uint48 prefix + sorted concat) | mirrors |
| 18 | SafeOp EIP-712 v0.7 typehash, field order, domain (chainId + 4337-module verifyingContract) | mirrors |
| 19 | SafeOp v0.6 typehash + EP v0.6 signing | **missing** |
| 20 | Configurable `validAfter`/`validUntil` | **missing** |
| 21 | Custom EntryPoint address in SafeOp `entryPoint` field | **missing** (hardcoded canonical v0.7) |
| 22 | Signature concatenation (address sort, 65-byte static, dynamic contract-sig parts, type byte 0x00) | mirrors |
| 23 | V handling in `signUserOperation` (typed-data path, v = 27/28) | mirrors |
| 24 | `signMessage` / `signTypedData` (EIP-1271 SafeMessage wrapper, eth_sign +4 adjust, 7579 zero-address prefix) | **diverges** |
| 25 | Standalone `signUserOperation` (multi-device signature accumulation) | **missing** |
| 26 | Nonce key handling | **missing** |
| 27 | 7579: `preValidationSetup` initializer + InitData `initHash` | mirrors |
| 28 | 7579: `initSafe7579` encoding incl. attester sorting | mirrors |
| 29 | 7579: safe7579 module address resolution / domain in 7579 mode | **diverges** |
| 30 | 7579: WebAuthn owner mapping inside InitData owners | **diverges** |
| 31 | 7579: first-op `setupSafe` wrapping (auto vs manual) | **diverges** |
| 32 | 7579: call vs batchcall mode selection, revertOnError=false | mirrors |
| 33 | 7579 + Safe v1.5.0 incompatibility guard | **missing** |
| 34 | Dart-only additions (Safe7579Addresses defaults, `encodeCallsForDeployment`, hardcoded proxy code constant, unused `publicClient` param) | dart-only |

**Counts: 12 mirrors · 9 diverges · 9 missing · 1 dart-only (grouped).**

Key mirrored details verified byte-by-byte (not just by name):

- All v1.4.1 addresses: JS `accounts/safe/toSafeSmartAccount.ts:472-503` == Dart `lib/src/accounts/safe/constants.dart:131-178`.
- CREATE2: salt = `keccak256(keccak256(initializer) ++ saltNonce)`, deploymentCode = `proxyCreationCode ++ uint256(singleton|launchpad)` — JS `toSafeSmartAccount.ts:1329-1349` == Dart `safe_account.dart:274-319`.
- Initializer: `setup(owners, threshold, multiSend, multiSendCallData, safe4337Module, 0, 0, 0)` with `enableModules([safe4337Module])` delegatecalled (operation 1) — JS `toSafeSmartAccount.ts:861-940` == Dart `safe_account.dart:340-428` + `lib/src/utils/encoding.dart:122-186` + `lib/src/utils/multisend.dart:82-115` (MultiSend packing `uint8 ++ address ++ uint256 ++ uint256 len ++ bytes` identical to JS `toSafeSmartAccount.ts:566-588`).
- `useMultiSendForSetup: false` single-call direct `setup()` branch — JS `toSafeSmartAccount.ts:907-922` == Dart `safe_account.dart:400-414` (the extra `!_hasWebAuthnOwner` guard at `safe_account.dart:402` is redundant, not behavioral: a WebAuthn owner always adds a second MultiSend call, making `length == 1` false in JS too). Dart's CREATE2 outputs for both branches are pinned to JS-0.3.5-generated vectors in `test/accounts/safe/safe_account_test.dart:496-511`.
- SafeOp v0.7 typehash string — JS `toSafeSmartAccount.ts:430-446` (uint128 verificationGasLimit before callGasLimit, uint128 fee fields, uint48 validity, address entryPoint) == Dart `safe_account.dart:967-968`; all EIP-712 words are 32-byte padded (Dart `lib/src/utils/encoding.dart:21-26`); dynamic fields (`initCode`, `callData`, `paymasterAndData`) are keccak-hashed (`safe_account.dart:979-1013`); `paymasterAndData` reconstruction `paymaster ++ u128 pmVGL ++ u128 pmPoGL ++ pmData` — JS `toSafeSmartAccount.ts:942-966` == Dart `safe_account.dart:985-999`.
- Domain separator: `EIP712Domain(uint256 chainId,address verifyingContract)` with **verifyingContract = Safe4337Module**, not the account — JS `signUserOperation.ts:279-290` == Dart `safe_account.dart:943-958`.
- Signature concat: sort by signer address, 65-byte static parts, dynamic position = `n*65 + dynamicBytes/2`, type byte `00`, `{len}{data}` tail — JS `signUserOperation.ts:30-74` == Dart `safe_account.dart:1042-1076`.
- V values in `signUserOperation`: JS signs SafeOp via `signTypedData` (no +4 adjust, v stays 27/28, `toSafeSmartAccount.ts:1994-2008` → `signUserOperation.ts:279-291`); Dart signs the identical EIP-712 hash via `signRawHash` and normalizes v to 27/28 (`lib/src/accounts/account_owner.dart:132-148`). Same bytes for the same key. The +31 (`27+4`) eth_sign adjustment only exists in the JS *message*-signing path (see finding 24).
- validAfter/validUntil packing: `encodePacked(uint48, uint48, bytes)` prefix — JS `signUserOperation.ts:312-315` / stub `toSafeSmartAccount.ts:1827-1830` == Dart 6-byte-each prefix `safe_account.dart:790-794, 853-857`.
- 7579 initializer: `preValidationSetup(initHash, address(0), 0x)` where initHash = keccak of ABI-encoded `(singleton, owners, threshold, setupTo, setupData, safe7579, ModuleInit[] validators)` — JS `toSafeSmartAccount.ts:747-834` == Dart `safe_account.dart:435-568`; `initSafe7579` attesters sorted case-insensitively — JS `toSafeSmartAccount.ts:676-679` == Dart `lib/src/utils/encoding.dart:319-321`.
- 7579 execution mode: single call → callType 0x00, batch → 0x01, execType 0x00 (revertOnError false) — JS `toSafeSmartAccount.ts:1637-1661` == Dart `lib/src/utils/erc7579.dart:334-377` (Dart `encode7579ExecuteBatch` collapses single-element lists to call mode at `erc7579.dart:360-362`).

---

## Finding 2 — Safe v1.5.0 MULTI_SEND_CALL_ONLY address mismatch (diverges)

- JS: `accounts/safe/toSafeSmartAccount.ts:515-516` — `MULTI_SEND_CALL_ONLY_ADDRESS: "0xA83c336B20401Af773B6219BA5027174338D1836"`
- Dart: `lib/src/accounts/safe/constants.dart:196-198` — `multiSendCallOnlyAddress: 0x0c28E9886f79618371c5Af86aA7e5Cf62dddd8dC`

Every other address in the v1.5.0 block matches byte-for-byte (proxy factory `0x14F2982D…`, singleton `0xFf51A589…`, multiSend `0x21854328…`, module setup, 4337 module, shared signer, P256 verifier). Today this constant is latent in Dart because the batch path never uses it (see Finding 12), but it is the address JS routes all multi-call executions through on v1.5.0, so fixing Finding 12 without fixing this constant would produce calldata targeting the wrong contract.

## Finding 5 — Proxy creation code: hardcoded constant vs RPC `proxyCreationCode()` (diverges, conditional)

- JS: `accounts/safe/toSafeSmartAccount.ts:1299-1303` — `getAccountAddress` reads `proxyCreationCode()` from the *configured factory* via `readContract`, so the bytecode always matches the factory in use (1.4.1 factory `0x4e1DCf…` or 1.5.0 factory `0x14F2982D…`, or any custom factory).
- Dart: `lib/src/accounts/safe/safe_account.dart:24-25` — a single hardcoded `_proxyCreationCode` constant used for **all** versions/factories (`safe_account.dart:285-291`).

For Safe v1.4.1 the constant is proven byte-equivalent: the Dart CREATE2 test vectors were generated with permissionless.js 0.3.5 (`test/accounts/safe/safe_account_test.dart:496-511`) and match. For the v1.5.0 factory (and any `customAddresses.safeProxyFactoryAddress`) the constant is **unverified**: if that factory's `proxyCreationCode()` differs even in the metadata hash, `getAddress()` returns a wrong counterfactual address while `getFactoryData()` still deploys to the (different) correct one — a silent, funds-endangering mismatch. Recommend either fetching via the (already accepted but unused) `publicClient`, or adding a pinned per-factory constant verified against the deployed v1.5.0 factory.

## Finding 9 — Default threshold (diverges)

- JS: `accounts/safe/toSafeSmartAccount.ts:1388` — `threshold = BigInt(_owners.length)` (defaults to *all* owners).
- Dart: `lib/src/accounts/safe/safe_account.dart:58` — `threshold = threshold ?? BigInt.one` (defaults to 1).

For a multi-owner Safe created without an explicit threshold, JS and Dart produce **different initializers → different CREATE2 addresses** and different on-chain signing policies. Single-owner accounts (the common case) are unaffected since both resolve to 1.

## Finding 10 — `setupTransactions`, `safeModules`, `payment*` parameters (missing)

- JS: `toSafeSmartAccount.ts:1135-1140` (`setupTransactions`, `safeModules`), `1204-1206` (`paymentToken`, `payment`, `paymentReceiver`); consumed in `getInitializerCode` at `toSafeSmartAccount.ts:867, 900-905, 917-919, 935-937`.
- Dart: no equivalents — `SafeSmartAccountConfig` (`safe_account.dart:39-69`) exposes none of these; `_getStandardInitializer` hardcodes exactly one `enableModules([safe4337Module])` call (`safe_account.dart:358-366`) and zero payment fields (`safe_account.dart:410-412, 424-426`).

Behavior matches JS *defaults* exactly (empty setup txs, single enabled module, zero payments), so parity holds for default inputs; the configuration surface is absent. Any JS account created with these params has a CREATE2 address Dart cannot reproduce.

## Finding 12 — Batch execution targets MultiSend instead of MultiSendCallOnly (diverges)

- JS: `accounts/safe/toSafeSmartAccount.ts:1669-1681` — `encodeCalls` for >1 call: `to = multiSendCallOnlyAddress`, `operationType = 1`, inner operations all `0`.
- Dart: `lib/src/accounts/safe/safe_account.dart:678-687` — `encodeCalls` for >1 call: `to: _addresses.multiSendAddress`, delegatecall, inner operations `0` (`lib/src/utils/multisend.dart:41-77`, default `OperationType.call`).

Byte-level divergence in every batched UserOperation's `callData` (different 20-byte target inside `executeUserOpWithErrorString`). Functionally both execute the batch (inner ops are plain calls, which MultiSendCallOnly also permits), but JS deliberately uses the call-only variant as a safety property — the delegatecalled MultiSend contract Dart uses would also accept inner `delegatecall` operations. Also, Dart short-circuits `calls.length == 1` to a plain single-call encoding (`safe_account.dart:674-676`); JS reaches the same single-call encoding through its `else` branch (`toSafeSmartAccount.ts:1682-1692`) — that part is equivalent.

## Finding 13 — `onchainIdentifier` (missing)

- JS: `toSafeSmartAccount.ts:1207, 1700-1702` — optional hex identifier concatenated after `executeUserOpWithErrorString` calldata.
- Dart: no parameter, never appended (`safe_account.dart:642-687`).

## Finding 14 — `decodeCalls` (missing)

- JS: `toSafeSmartAccount.ts:1706-1780` — decodes `setupSafe`, 7579, `executeUserOpWithErrorString`, and MultiSend-batched calldata back to call lists.
- Dart: `SafeSmartAccount` exposes no decode method; a generic `decodeMultiSend` exists in `lib/src/utils/multisend.dart:118-141` but nothing decodes the Safe wrapper. Introspection-only gap; no signing/deployment impact.

## Finding 15 — ECDSA stub signature bytes (diverges)

- JS: `toSafeSmartAccount.ts:1792-1793` — fixed 65-byte dummy per owner: `0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaa…aaa1c` (r ≈ max, plausible s, v = 0x1c → ecrecover path in `checkSignatures`).
- Dart: `safe_account.dart:772-784` — r = owner address left-padded, s = 0, v = 0x01. In Safe's `checkSignatures`, v == 1 selects the **approved-hash** branch with r as the approver address, not the ecrecover branch.

Both are 65 bytes and structurally valid stubs, but they exercise different validation code paths during bundler gas estimation (approved-hash storage read vs ecrecover precompile), so estimated `verificationGasLimit` can differ from JS. Not a correctness bug for real signatures, but not byte- or path-parity.

## Finding 16 — WebAuthn stub signature bytes (diverges)

- JS: `toSafeSmartAccount.ts:1796-1810` — authenticatorData `0x49960de5…631d00000000` (37 bytes, realistic rpIdHash), clientDataFields `"origin":"http://somelargdomainheresothatwehaveenoughbytes.com","crossOrigin":false` (deliberately long, 77 chars), specific r/s constants.
- Dart: `lib/src/utils/webauthn_encoding.dart:211-242` — authenticatorData = 32×0x49 + flags + counter, clientDataFields `"origin":"http://localhost:3000","crossOrigin":false` (53 chars), r = 2²⁵⁶-ish max, s = P-256 half-order value.

Same ABI shape (`(bytes, string, uint256[2])`, matching JS `signUserOperation.ts:100-111` and Dart `webauthn_encoding.dart:165-205`), different content and — importantly — a **shorter** clientDataFields than JS's intentionally oversized one, so calldata/verification gas may be underestimated for real origins longer than localhost.

## Finding 19 — EntryPoint v0.6 SafeOp signing (missing)

- JS: v0.6 typehash `EIP712_SAFE_OPERATION_TYPE_V06` (`toSafeSmartAccount.ts:412-428`, uint256 gas fields, `callGasLimit` before `verificationGasLimit`) selected at `signUserOperation.ts:265-268, 284-287`; v0.6 message uses raw `initCode`/`paymasterAndData` (`signUserOperation.ts:161-175`).
- Dart: only the v0.7 typehash exists (`safe_account.dart:966-968`); `signUserOperation` accepts only `UserOperationV07` (`safe_account.dart:801`) and `SafeSmartAccount` does not implement the `SmartAccountV06` interface (`lib/src/clients/smart_account/smart_account_interface.dart:120-129`).

Dart *does* carry the full v0.6 address table (`constants.dart:132-151`) and allows `entryPointVersion: v06` in config (`safe_account.dart:43`), so a v0.6-configured account computes a correct counterfactual address but then produces v0.7-typed, v0.7-EntryPoint-addressed signatures (`safe_account.dart:1008-1016`) that can never validate. This half-supported state is worse than rejecting v0.6 outright.

## Finding 20 — Configurable `validAfter` / `validUntil` (missing)

- JS: parameters at `toSafeSmartAccount.ts:1201-1202, 1395-1396`, threaded into both the signed SafeOp message (`signUserOperation.ts:139-140, 168-169`) and the packed signature prefix (`signUserOperation.ts:312-315`).
- Dart: hardcoded zeros in the struct hash (`safe_account.dart:1014-1015`) and the prefix (`safe_account.dart:853-856`).

Identical bytes for the default (0, 0); time-bounded signatures are impossible in Dart.

## Finding 21 — Custom EntryPoint address in the SafeOp (missing)

- JS: `entryPoint: entryPoint.address` in the signed message (`signUserOperation.ts:170`), honoring `parameters.entryPoint.address` (`toSafeSmartAccount.ts:1458-1465`).
- Dart: `AbiEncoder.encodeAddress(EntryPointAddresses.v07)` hardcoded (`safe_account.dart:1016`), ignoring even its own `entryPointVersion` config (compounds Finding 19).

## Finding 24 — `signMessage` / `signTypedData`: SafeMessage EIP-1271 flow absent (diverges)

- JS `signMessage`: wraps the message hash in the `SafeMessage(bytes message)` typed struct with domain `{chainId, verifyingContract: safeAddress}` (`toSafeSmartAccount.ts:1846-1858`), each owner signs that hash via **eth_sign** (`localOwner.signMessage({raw})`, `toSafeSmartAccount.ts:1873-1880`), then `adjustVInSignature("eth_sign", …)` normalizes v to 27/28 and adds +4 → v ∈ {31, 32} (`toSafeSmartAccount.ts:525-547`) so Safe's `checkSignatures` re-applies the EIP-191 prefix. Threshold guard at `1836-1840`, v1.5.0+7579 guard at `1842-1844`, and in 7579 mode the result is prefixed with 20 zero bytes (`toSafeSmartAccount.ts:1898-1900`).
- JS `signTypedData`: same SafeMessage wrapper, signed via `signTypedData` with `adjustVInSignature("eth_signTypedData", …)` (v stays 27/28) (`toSafeSmartAccount.ts:1902-1981`).
- Dart: `signMessage`/`signTypedData` (`safe_account.dart:865-878`) hash the raw message (EIP-191 / EIP-712) and `_signHash` (`safe_account.dart:881-911`) has each owner `signRawHash` that hash directly — **no SafeMessage wrapper, no Safe domain, no eth_sign +4 adjustment, no zero-address 7579 prefix, no threshold guard**, and signatures are concatenated without the dynamic-part handling used elsewhere (`safe_account.dart:895-910` — plain string concat, so a WebAuthn contract signature would be malformed here too).

Consequence: Dart Safe `signMessage`/`signTypedData` output will **fail on-chain EIP-1271 verification** (`isValidSignature` via CompatibilityFallbackHandler), which is the entire purpose of these methods in the JS reference. This is the largest behavioral gap in the port. (`signUserOperation` is unaffected — see mirrored item 23.)

## Finding 25 — Standalone multi-signer `signUserOperation` helper (missing)

- JS: `accounts/safe/signUserOperation.ts:114-316`, exported via `accounts/safe/index.ts` — supports collecting signatures one owner at a time across devices: intermediate results are ABI-encoded `(address,bytes,bool)[]` tuples (`signUserOperation.ts:295-310`), decoded back on the next call (`213-251`, with legacy 2-field fallback), and only packed into `uint48‖uint48‖sigs` once `signatures.length === owners.length`.
- Dart: no equivalent; `SafeSmartAccount.signUserOperation` (`safe_account.dart:801-858`) requires every configured owner to sign in one process. Multi-device m-of-n flows cannot be reproduced.

## Finding 26 — Nonce key handling (missing)

- JS: `nonceKey?: bigint` parameter (`toSafeSmartAccount.ts:1203, 1397`); `getNonce` fetches from the EntryPoint with `key: nonceKey ?? args?.key` (`toSafeSmartAccount.ts:1781-1787`).
- Dart: `nonceKey` is a fixed `BigInt.zero` getter (`safe_account.dart:214-215`) with no configuration path. Parallel nonce lanes (2D nonces) are unusable for Safe in Dart.

## Finding 29 — 7579 module address resolution (diverges)

- JS: in 7579 mode the `safe7579` value in InitData **is** `safe4337ModuleAddress` (`toSafeSmartAccount.ts:663, 682`), which defaults to the standard Safe 4337 module `0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226` from the address map (`toSafeSmartAccount.ts:489-490, 1097-1098`) unless the caller overrides `safe4337ModuleAddress` with the Safe7579 adapter. The signing domain uses that same address (`signUserOperation.ts:149-155, 262-263`).
- Dart: 7579 mode force-substitutes `Safe7579Addresses.safe7579ModuleAddress = 0x7579EE8307284F293B1927136486880611F20002` (`safe_account.dart:236-238`, constant at `constants.dart:74-75`) for both InitData (`safe_account.dart:475, 583, 732`) and the EIP-712 domain (`safe_account.dart:953-955`). `customAddresses.safe4337ModuleAddress` is ignored in 7579 mode.

Dart's default is the one that actually works with the canonical Rhinestone launchpad (JS callers must pass the 7579 adapter explicitly — the JS default would produce a broken 7579 account), so Dart is arguably *more* correct — but it is not the reference behavior, cannot be overridden, and a JS config using a nonstandard adapter address is unreproducible in Dart.

## Finding 30 — 7579 InitData owners: WebAuthn mapping (diverges)

- JS: `get7579LaunchPadInitData` maps WebAuthn owners to `safeWebAuthnSharedSignerAddress` (`toSafeSmartAccount.ts:639-652`), same as the standard initializer.
- Dart: `_computeInitHash` and `_encodeSetupSafe` use `o.address` for every owner unconditionally (`safe_account.dart:461, 719`), unlike Dart's own standard-mode initializer which does map WebAuthn owners (`safe_account.dart:343-355`).

A 7579 Safe with a WebAuthn owner gets a different (wrong) initHash → different address and failed `setupSafe` validation versus JS. Edge case (WebAuthn + 7579), but byte-level divergence.

## Finding 31 — 7579 first-op `setupSafe` wrapping (diverges)

- JS: `encodeCalls` checks deployment status via `isSmartAccountDeployed` and, when counterfactual, automatically wraps user calls into `setupSafe(InitData{…, callData: encode7579Calls(...)})` (`toSafeSmartAccount.ts:1603-1651`); after deployment it emits plain 7579 calls (`1653-1661`).
- Dart: `encodeCalls` always emits plain 7579 calls (`safe_account.dart:669-671`); the caller must know to invoke the Dart-only `encodeCallsForDeployment` for the first op (`safe_account.dart:700-715`), which then produces the same `setupSafe` encoding (`encodeSetupSafe`, `lib/src/utils/encoding.dart:427-485` — tuple head offsets match JS ABI output).

The encodings agree; the *selection* is manual in Dart. A caller porting JS code 1:1 will deploy a 7579 Safe whose first UserOp reverts (launchpad expects `setupSafe`).

## Finding 33 — 7579 + Safe v1.5.0 guard (missing)

- JS: throws `"Safe 7579 & version 1.5.0 are not compatible"` in `signMessage`/`signTypedData` (`toSafeSmartAccount.ts:1842-1844, 1909-1911`).
- Dart: no such check anywhere in `safe_account.dart`; a 1.5.0 + launchpad config is silently accepted.

## Finding 34 — Dart-only surface (dart-only)

- `Safe7579Addresses` canonical constants: launchpad `0x7579011aB74c46090561ea277Ba79D510c6C00ff` and Rhinestone attester `0x000000333034E9f539ce08819E12c1b8Cb29084d` (`constants.dart:67-91`). JS ships no launchpad/attester defaults; callers supply them. Values match the canonical Rhinestone deployments.
- `encodeCallsForDeployment` (`safe_account.dart:700-715`) — see Finding 31.
- Hardcoded `_proxyCreationCode` (`safe_account.dart:24-25`) — see Finding 5.
- `publicClient` config field (`safe_account.dart:47, 92-93`) is accepted but never used (address derivation is fully local); its doc comment ("computed automatically via RPC") is stale.
- Ergonomic stub choice: approved-hash-style ECDSA stub (Finding 15) is a deliberate Dart design, not an accident, per the r=owner construction.

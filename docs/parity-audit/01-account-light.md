# Parity Audit 01 — Light Account (Alchemy)

**Reference:** permissionless.js v0.3.5 — `accounts/light/toLightSmartAccount.ts`
**Port:** permissionless.dart v0.3.0 — `lib/src/accounts/light/` (`light_account.dart`, `constants.dart`, `light.dart`)

Paths below are abbreviated:

- **JS** = `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless/accounts/light/toLightSmartAccount.ts`
- **DART** = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src/accounts/light/light_account.dart`
- **CONST** = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src/accounts/light/constants.dart`
- **OWNER** = `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src/accounts/account_owner.dart`

Function selectors were independently verified with viem's `toFunctionSelector`:
`execute(address,uint256,bytes)` = `0xb61d27f6`, `executeBatch(address[],uint256[],bytes[])` = `0x47e1da2a`, `createAccount(address,uint256)` = `0x5fbfb9cf` — all matching the Dart constants (CONST:68, CONST:72, CONST:76).

## Verdict table

| # | Aspect | Verdict | JS | Dart |
|---|--------|---------|----|------|
| 1 | Supported versions (1.1.0 / 2.0.0) + EP mapping | mirrors | JS:73-74 | CONST:9-36 |
| 2 | Factory addresses per version | mirrors | JS:123-134 | CONST:44-49 |
| 3 | initcode / factoryData (`createAccount(owner, salt)`, default salt 0) | mirrors | JS:35-71, 191, 222-227 | DART:35, 178-198 |
| 4 | Dummy signature (incl. v2 `0x00` EOA prefix) | mirrors | JS:415-427 | DART:282-300 |
| 5 | signUserOperation — EP v0.7 hash + raw EIP-191 sign + v2 prefix | mirrors | JS:465-494 | DART:302-319, 396-457 |
| 6 | signUserOperation — EP v0.6 hash path | **missing** | JS:469-477 (via viem `getUserOperationHash`, version-aware) | DART:303, 396-457 (v0.7-only) |
| 7 | signMessage / signTypedData — LightAccountMessage ERC-1271 wrapper | **diverges** | JS:100-121, 431-464 | DART:322-394 |
| 8 | `sign({ hash })` | **missing** | JS:428-430 | — (no counterpart in `SmartAccount` interface) |
| 9 | execute / executeBatch calldata | mirrors | JS:246-318 | DART:200-280 |
| 10 | decodeCalls | **missing** | JS:319-407 | — |
| 11 | Nonce handling — configurable `nonceKey` / per-call key | **missing** | JS:97, 192, 408-414 | DART:122 (hardcoded `BigInt.zero`) |
| 12 | getAddress via `eth_getSenderAddress` / precomputed address | mirrors | JS:96, 210, 233-245 | DART:129-155 |
| 13 | Version auto-selection from EntryPoint version | dart-only | JS:93 (explicit, type-enforced) | CONST:24-36, DART:36-37 |

**Counts:** 7 mirrors, 1 diverges, 4 missing, 1 dart-only.

---

## Finding 7 — signMessage / signTypedData: EIP-191 prefix wrongly applied on top of the EIP-712 wrapper digest (**diverges**)

**JS behavior.** `signWith1271WrapperV1` (JS:100-121) calls `signer.signTypedData(...)` with the `LightAccountMessage` typed data (domain `{ name: "LightAccount", version: "1", chainId, verifyingContract }`, type `LightAccountMessage(bytes message)`). viem's `LocalAccount.signTypedData` computes the EIP-712 digest (`keccak256("\x19\x01" ‖ domainSeparator ‖ structHash)`) and signs that digest **raw** — no EIP-191 personal-message prefix. This is what LightAccount's on-chain `isValidSignature` (ERC-1271) expects.

**Dart behavior.** `_signLightAccountMessage` (DART:372-394) builds the identical typed data (DART:376-390 — domain and `LightAccountMessage(bytes message)` match JS byte-for-byte), then:

```dart
final hash = hashTypedData(typedData);
return _config.owner.signPersonalMessage(hash);   // DART:392-393
```

`PrivateKeyOwner.signPersonalMessage` (OWNER:116-129) uses web3dart's `signPersonalMessageToUint8List`, which prepends `"\x19Ethereum Signed Message:\n32"` and re-hashes before signing. So the Dart signature is over `keccak256("\x19Ethereum Signed Message:\n32" ‖ eip712Digest)` instead of over `eip712Digest`.

**Impact.** Every signature produced by `LightSmartAccount.signMessage` (DART:322-344) and `signTypedData` (DART:347-369) recovers to a different digest than the contract computes; on-chain ERC-1271 validation (`isValidSignature`) will fail for both v1.1.0 and v2.0.0. The fix is to sign the wrapper digest raw — e.g. `owner.signRawHash(hash)` or `owner.signTypedData(typedData)` (OWNER:132-149 / OWNER:151-169 both sign without a personal prefix).

Note: the v2.0.0 `0x00` prefix concatenation itself (DART:333-341, 358-365) mirrors JS:439-446 / JS:456-463 correctly; only the inner ECDSA digest is wrong.

Minor related gap: JS `signMessage` accepts viem's `SignableMessage` (UTF-8 string or `{ raw }` bytes, hashed via `hashMessage`, JS:436); Dart only accepts a UTF-8 `String` (DART:322-323, hashed by `hashMessage` in `utils/message_hash.dart:23-36`). For string messages the digests match.

## Finding 6 — signUserOperation: EP v0.6 hash path missing (**missing**)

**JS behavior.** `signUserOperation` (JS:465-494) computes the userOp hash with viem's `getUserOperationHash` passing `entryPointVersion: entryPoint.version` (JS:475), so it packs the v0.6 format (separate `initCode`/`paymasterAndData`, unpacked gas fields) when the account is configured for EP v0.6 with LightAccount v1.1.0, and the v0.7 packed format otherwise. The hash is then signed as a raw 32-byte EIP-191 message (JS:479-484).

**Dart behavior.** `signUserOperation` accepts only `UserOperationV07` (DART:303) and `_computeUserOpHash`/`_packUserOpForHash` (DART:396-457) hardcode the v0.7 packed layout (`accountGasLimits`, `gasFees`, packed `paymasterAndData`). `LightSmartAccount` implements only `SmartAccount` (DART:89) and not `SmartAccountV06` (`lib/src/clients/smart_account/smart_account_interface.dart:120-130`, which other Dart accounts like Trust and Biconomy implement for v0.6 flows). Yet the config accepts `EntryPointVersion.v06` (DART:29) and correctly selects LightAccount v1.1.0 + the v0.6 factory (CONST:24-28, CONST:44-45) and the v0.6 EntryPoint address (DART:118-119).

**Impact.** A Light account configured for EP v0.6 / v1.1.0 can be constructed and will build correct initcode, but there is no way to sign a v0.6 UserOperation: the only signing path packs the hash v0.7-style, which produces an invalid v0.6 userOpHash. EP v0.6 support is therefore effectively missing despite being half-exposed in the config (a footgun — either implement `SmartAccountV06.signUserOperationV06` with the v0.6 hash layout, or reject `EntryPointVersion.v06` in the constructor).

The v0.7 hash computation itself (DART:396-457) was checked field-by-field against the ERC-4337 v0.7 spec (keccak over `abi.encode(sender, nonce, keccak(initCode), keccak(callData), accountGasLimits, preVerificationGas, gasFees, keccak(paymasterAndData))`, then `keccak(abi.encode(h, entryPoint, chainId))`) and mirrors what viem computes. The raw EIP-191 signing of the hash (DART:305 via OWNER:116-129) also mirrors JS:479-484, including the v2 `0x00` prefix (DART:308-315 vs JS:486-493).

## Finding 8 — `sign({ hash })` (**missing**)

JS exposes `sign` (JS:428-430) which delegates to `signMessage({ message: hash })` — used by viem for things like SIWE and generic hash signing. The Dart `SmartAccount` interface has no `sign` method and `LightSmartAccount` provides no equivalent. Low severity; callers can approximate it with `signMessage`, though only for UTF-8 string inputs.

## Finding 10 — decodeCalls (**missing**)

JS implements `decodeCalls` (JS:319-407), decoding `executeBatch(address[],uint256[],bytes[])` first and falling back to `execute(address,uint256,bytes)`, returning the structured call list. Dart has no decode capability for Light account calldata (the `SmartAccount` interface in `smart_account_interface.dart:20-114` defines only encoding). Affects tooling/introspection only, not transaction correctness.

## Finding 11 — Nonce handling: no configurable nonce key (**missing**)

JS accepts a `nonceKey` constructor parameter (JS:97, destructured at JS:192) and `getNonce(args)` uses `nonceKey ?? args?.key` when querying `EntryPoint.getNonce` (JS:408-414), enabling parallel (2D) nonces. Dart hardcodes `nonceKey => BigInt.zero` (DART:122) and `LightSmartAccountConfig` (DART:16-68) offers no nonce-key option, so the SmartAccountClient always fetches key-0 nonces. Sequential-nonce behavior mirrors JS defaults; the ability to opt into a custom key is missing.

## Finding 13 — Version auto-selection (dart-only)

JS requires an explicit `version` parameter whose allowed value is tied to the EntryPoint version at the type level (`LightAccountVersion<entryPointVersion>`, JS:73-74, JS:93) — "1.1.0" only with EP v0.6, "2.0.0" only with EP v0.7. Dart makes `version` optional and derives it via `LightAccountVersion.forEntryPoint` (CONST:24-36, applied at DART:36-37), which also explicitly rejects EP v0.8. This is a convenience addition with identical default behavior.

Caveat: because Dart's pairing is only a default, a caller can explicitly pass a mismatched combination (e.g. `version: v110` with `entryPointVersion: v07`), which neither side validates at runtime — JS relies on TypeScript types to prevent it. Not counted as a divergence since JS has no runtime check either.

## Mirrors — verification notes

- **Factory addresses** byte-for-byte: v1.1.0 `0x00004EC70002a32400f8ae005A26081065620D20` (JS:129 = CONST:45), v2.0.0 `0x0000000000400CdFef5E2714E63d8040b700BC24` (JS:132 = CONST:49). Custom factory override supported on both sides (JS:94, 136-151; DART:31, 94-96).
- **initcode/factoryData**: both encode `createAccount(address owner, uint256 salt)` with the owner address and index/salt (default 0) — JS:35-71 + JS:191 vs DART:194-198 + DART:35; selector `0x5fbfb9cf` verified. Dart's `getInitCode` (DART:179-185) is `factory ‖ factoryData`, matching the v0.6 initCode convention; `getFactoryData` (DART:188-192) matches the v0.7 split used by JS `getFactoryArgs` (JS:222-227).
- **Dummy signature**: identical 65-byte constant `0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaa...aaa1c` (JS:417 = DART:286), with `0x00` (SignatureType.EOA, JS:169-173 = CONST:80-91) prepended only for v2.0.0 (JS:419-426 = DART:289-299).
- **execute/executeBatch**: JS uses `execute` for a single call and `executeBatch` for >1, throwing on empty (JS:246-317); Dart identical (DART:205-215). Dart's hand-rolled ABI encoding (DART:217-280) was checked against canonical ABI head/tail layout: `execute` head offset `0x60` (DART:218), `executeBatch` three head offsets with correctly accumulated dynamic tails (DART:236-246), and `bytes[]` element offsets relative to the array data area starting at `n*32` (DART:266-277) — all standard-conformant; missing `value`/`data` defaults (`0`, `0x`) in JS:277-278/316 are non-nullable fields on the Dart `Call` type.
- **getAddress**: JS counterfactually derives via `getSenderAddress` with factory/factoryData and honors an explicit `address` parameter (JS:96, 210, 233-245); Dart does the same via `publicClient.getSenderAddress(initCode: ...)` or an explicit `address`, caching the result (DART:129-155). Dart throws a descriptive `StateError` when neither is available — JS always has a client, so this branch has no JS analogue but is not a behavioral divergence for valid usage.

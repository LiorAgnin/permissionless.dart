# Parity Audit: Biconomy Smart Account (legacy/deprecated)

**JS reference**: permissionless.js v0.3.5 — `accounts/biconomy/toBiconomySmartAccount.ts`, `accounts/biconomy/abi/BiconomySmartAccountAbi.ts`
**Dart port**: permissionless.dart v0.3.0 — `lib/src/accounts/biconomy/biconomy_account.dart`, `lib/src/accounts/biconomy/constants.dart`, `lib/src/accounts/biconomy/biconomy.dart`

Paths below are relative to:

- JS: `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless/`
- Dart: `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/`

Scope: behavioral parity of the deprecated EntryPoint v0.6 Biconomy Smart Account. All constants were read on both sides; the proxy creation code strings were diffed programmatically (identical, 578 hex chars); all five function selectors were re-derived with `cast sig` and match both sides.

## Verdict table

| # | Aspect | Verdict | JS | Dart |
|---|--------|---------|----|------|
| 1 | Factory address `0x000000a56Aaca3e9a4C479ea6b6CD0DbcB6634F5` | mirrors | toBiconomySmartAccount.ts:54 | constants.dart:15-16 |
| 2 | Account v2.0 logic address `0x0000002512019Dafb59528B82CB92D3c5D2423aC` | mirrors | toBiconomySmartAccount.ts:55 | constants.dart:19-20 |
| 3 | Default fallback handler `0x0bBa6d96BD616BedC6BFaa341742FD43c60b83C1` | mirrors | toBiconomySmartAccount.ts:56-57 | constants.dart:23-24 |
| 4 | ECDSA Ownership Registry Module `0x0000001c5b32F37F5beA87BDD5374eB2aC54eA8e` | mirrors | toBiconomySmartAccount.ts:52-53 | constants.dart:11-12 |
| 5 | Proxy creation code (CREATE2 bytecode) | mirrors | toBiconomySmartAccount.ts:36-37 | biconomy_account.dart:200-201 |
| 6 | Function selectors (execute_ncC `0x0000189a`, executeBatch_y6U `0x00004680`, deployCounterFactualAccount `0xdf20ffbc`, initForSmartAccount `0x2ede3bc0`, init `0x378dfd8e`) | mirrors | abi/BiconomySmartAccountAbi.ts:20,52,71,100,123 | constants.dart:37-53 |
| 7 | factoryData: `deployCounterFactualAccount(module, initForSmartAccount(owner), index)` | mirrors | toBiconomySmartAccount.ts:67-91, 209-218 | biconomy_account.dart:214-240 |
| 8 | initCode composition (factory ++ factoryData) | mirrors | via viem `toSmartAccount` + getFactoryArgs (toBiconomySmartAccount.ts:209-218) | biconomy_account.dart:204-211 |
| 9 | Counterfactual address: CREATE2 over `init(fallbackHandler, module, initData)` salted with keccak(keccak(initData) ++ index), bytecode = creationCode ++ uint256(logic) | mirrors | toBiconomySmartAccount.ts:128-179 | biconomy_account.dart:148-196 |
| 10 | Stub/dummy signature (module-wrapped, fixed 65-byte sig) | mirrors | toBiconomySmartAccount.ts:303-306 | biconomy_account.dart:323-332 |
| 11 | signUserOperation: v0.6 userOpHash → EIP-191 personal sign of raw hash → abi.encode(bytes sig, address module) | mirrors | toBiconomySmartAccount.ts:347-372 | biconomy_account.dart:336-342, 382-413 |
| 12 | Module signature wrapper `abi.encode(bytes, address)` layout | mirrors | toBiconomySmartAccount.ts:367-370 (also 324-327, 341-344) | biconomy_account.dart:374-379 |
| 13 | Single call: `execute_ncC(to, value, data)` | mirrors | toBiconomySmartAccount.ts:266-271 | biconomy_account.dart:244-252 |
| 14 | Batch call: `executeBatch_y6U(address[], uint256[], bytes[])` | mirrors | toBiconomySmartAccount.ts:248-259 | biconomy_account.dart:267-320 |
| 15 | encodeCalls dispatch (0 calls → throw, 1 → single, >1 → batch) | mirrors | toBiconomySmartAccount.ts:247-272 | biconomy_account.dart:256-264 |
| 16 | decodeCalls | missing | toBiconomySmartAccount.ts:273-301 | — (no counterpart) |
| 17 | signMessage (ERC-1271 personal-sign path) | **diverges** | toBiconomySmartAccount.ts:310-328 | biconomy_account.dart:354-358 |
| 18 | signTypedData (incl. v normalization) | mirrors | toBiconomySmartAccount.ts:329-345 | biconomy_account.dart:362-365; account_owner.dart:151-168 |
| 19 | `sign({ hash })` method | missing | toBiconomySmartAccount.ts:307-309 | — (no counterpart) |
| 20 | EntryPoint v0.6 only (v0.7 rejected) | mirrors | toBiconomySmartAccount.ts:107-110, 119-122 (type-enforced `"0.6"`) | biconomy_account.dart:104, 114-115, 344-350 (`signUserOperation` v0.7 throws `UnsupportedError`) |
| 21 | EntryPoint v0.6 address `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | mirrors | viem `entryPoint06Address` (toBiconomySmartAccount.ts:202) | constants/entry_point.dart:14-15 |
| 22 | Custom entryPoint address override | missing | toBiconomySmartAccount.ts:107-110, 201-205 | — (hard-coded, biconomy_account.dart:114-115) |
| 23 | `nonceKey` parameter | missing | toBiconomySmartAccount.ts:111, 239-246 | — (hard-coded `BigInt.zero`, biconomy_account.dart:117-119) |
| 24 | `accountLogicAddress` / `fallbackHandlerAddress` overrides | missing | toBiconomySmartAccount.ts:115-116, 193-194 | — (config exposes only factory + ECDSA module, biconomy_account.dart:34-35, 50-53) |
| 25 | Deprecation notes (points to Nexus) | mirrors | toBiconomySmartAccount.ts:181-184 (`@deprecated`) | biconomy_account.dart:16, 80, 419 (`@Deprecated`); constants.dart:6, 31; biconomy.dart:1-17 |
| 26 | Inert `publicClient` config parameter | dart-only | — | biconomy_account.dart:28, 36, 55-56 |

**Counts**: 18 mirrors, 1 diverges, 5 missing, 1 dart-only.

Notes on verified byte-level details:

- Selectors re-derived with `cast sig`: all five match the Dart constants and the JS ABI function signatures exactly.
- The stub signature bodies are the identical hex string on both sides (offset `0x40`, module address word, length `0x41`, fixed 65-byte signature, trailing zero padding). The JS version embeds the module address with checksum casing and Dart with lowercase (`EthereumAddress.hex`), which is byte-identical after hex decoding — not a divergence.
- The Dart v0.6 userOpHash (`_computeUserOpHashV06` / `_packUserOpForHashV06`, biconomy_account.dart:382-413) reproduces viem's `getUserOperationHash` for EP v0.6: `keccak256(abi.encode(keccak256(packedOp), entryPoint, chainId))` with `packedOp = abi.encode(sender, nonce, keccak(initCode), keccak(callData), callGasLimit, verificationGasLimit, preVerificationGas, maxFeePerGas, maxPriorityFeePerGas, keccak(paymasterAndData))`. Mirrors.
- V-value normalization: JS normalizes non-27/28 v to +27 in signMessage/signTypedData (toBiconomySmartAccount.ts:315-323, 332-340). Dart's `PrivateKeyOwner` produces v=27/28 natively for personal sign (web3dart) and normalizes `v < 27 → +27` for raw/typed-data signing (account_owner.dart:142-147, 162-167). Equivalent behavior.

---

## Finding 17 (diverges): `signMessage` applies the EIP-191 prefix twice

**JS** — `toBiconomySmartAccount.ts:310-313`:

```ts
async signMessage({ message }) {
    let signature = await localOwner.signMessage({ message })
```

viem's `LocalAccount.signMessage` computes `digest = keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)` and signs **that digest raw** (one prefix application). The result is then module-wrapped (ts:324-327).

**Dart** — `biconomy_account.dart:354-358`:

```dart
Future<String> signMessage(String message) async {
  final messageHash = hashMessage(message);
  final signature = await _config.owner.signPersonalMessage(messageHash);
  return _encodeModuleSignature(signature);
}
```

`hashMessage` (utils/message_hash.dart:22-36) already produces `keccak256(prefix(message))` — the same digest viem signs. But `signPersonalMessage` (account_owner.dart:116-129, via web3dart `signPersonalMessageToUint8List`) then prefixes **again** with `"\x19Ethereum Signed Message:\n32"` before hashing and signing.

Net effect:

- JS signs: `keccak256(prefix_N ++ message)`
- Dart signs: `keccak256(prefix_32 ++ keccak256(prefix_N ++ message))`

For the same input message the two produce different signatures, so ERC-1271 verification against the ECDSA Ownership module will not agree between the two SDKs. (`signUserOperation` is NOT affected — there the JS side signs the raw userOpHash via `message: { raw: hash }`, i.e. one prefix over the 32-byte hash, which matches Dart's `signPersonalMessage(userOpHash)` exactly.)

Fix direction: `signMessage` should sign the `hashMessage` digest raw (e.g. `signRawHash`) or pass the original message string through a personal-sign that prefixes once.

---

## Finding 16 (missing): `decodeCalls`

**JS** — `toBiconomySmartAccount.ts:273-301` implements `decodeCalls`, decoding `execute_ncC` and `executeBatch_y6U` calldata back to `{to, value, data}[]` and throwing `"Invalid function name"` otherwise.

**Dart** — no counterpart in `biconomy_account.dart`, and the `SmartAccountV06`/`SmartAccount` interface (lib/src/clients/smart_account/smart_account_interface.dart:20-120) defines no `decodeCalls` member at all — this is a port-wide interface gap, not Biconomy-specific, but it means calldata introspection available in JS has no Dart equivalent.

---

## Finding 19 (missing): `sign({ hash })`

**JS** — `toBiconomySmartAccount.ts:307-309`:

```ts
async sign({ hash }) {
    return this.signMessage({ message: hash })
}
```

**Dart** — no `sign` method exists on `BiconomySmartAccount` or its interface. Minor; primarily used by viem's ERC-1271/hash-signing plumbing.

---

## Finding 22 (missing): custom EntryPoint address override

**JS** — `ToBiconomySmartAccountParameters.entryPoint` accepts `{ address, version: "0.6" }` (toBiconomySmartAccount.ts:107-110) and the account uses `parameters.entryPoint?.address ?? entryPoint06Address` (ts:201-205).

**Dart** — `entryPoint` is hard-coded to `EntryPointAddresses.v06` (biconomy_account.dart:114-115) with no config field. Default behavior is identical (canonical v0.6 address, verified constants/entry_point.dart:14-15); only the override capability is absent.

---

## Finding 23 (missing): configurable `nonceKey`

**JS** — `nonceKey?: bigint` parameter (toBiconomySmartAccount.ts:111) is fed into `getAccountNonce` as the 2D-nonce key (ts:239-246).

**Dart** — `nonceKey` is a fixed getter returning `BigInt.zero` (biconomy_account.dart:117-119); `BiconomySmartAccountConfig` has no such field. The client consumes `account.nonceKey` (clients/smart_account/smart_account_client.dart:225-228), so the plumbing exists — only the configuration knob is missing. Behavior at defaults is identical (key 0).

---

## Finding 24 (missing): `accountLogicAddress` / `fallbackHandlerAddress` overrides

**JS** — both are optional parameters (toBiconomySmartAccount.ts:115-116) defaulted from `BICONOMY_ADDRESSES` (ts:193-194) and used in counterfactual address computation (ts:228-235).

**Dart** — `BiconomySmartAccountConfig` exposes only `customFactoryAddress` and `customEcdsaModuleAddress` (biconomy_account.dart:34-35, 50-53); `_computeAccountAddress` reads `BiconomyAddresses.defaultFallbackHandler` and `BiconomyAddresses.accountV2Logic` directly (biconomy_account.dart:159, 180). Defaults produce byte-identical addresses; only non-default deployments cannot be targeted from Dart.

---

## Finding 26 (dart-only): inert `publicClient` config parameter

`BiconomySmartAccountConfig.publicClient` (biconomy_account.dart:28, 36, 55-56) is documented as "Client for computing the account address via RPC" but is never referenced anywhere in the implementation — `getAddress` always computes the CREATE2 address locally (biconomy_account.dart:129-145). Harmless dead configuration; either wire it up or remove it. (Relatedly, Dart requires `chainId` in the config whereas JS derives it from `client.chain` — a constructor-shape difference with no behavioral impact given a correct chainId.)

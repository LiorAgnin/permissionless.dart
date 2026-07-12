# Parity Audit 01 — Etherspot Modular Smart Account

**Scope:** `toEtherspotSmartAccount` (permissionless.js v0.3.5) vs `EtherspotSmartAccount` (permissionless.dart v0.3.0).

**Reference (JS):**
- `permissionless.js/packages/permissionless/accounts/etherspot/toEtherspotSmartAccount.ts`
- `.../etherspot/constants.ts`, `.../etherspot/utils/getInitMSAData.ts`, `.../etherspot/utils/getNonceKey.ts`, `.../etherspot/utils/wrapMessageHash.ts`, `.../etherspot/abi/EtherspotBootstrapAbi.ts`
- `permissionless.js/packages/permissionless/utils/encode7579Calls.ts`, `.../actions/erc7579/supportsExecutionMode.ts`

**Port (Dart):**
- `permissionless.dart/packages/permissionless/lib/src/accounts/etherspot/etherspot_account.dart`
- `.../etherspot/constants.dart`, `.../etherspot/etherspot.dart`
- `.../lib/src/utils/erc7579.dart`, `.../lib/src/accounts/account_owner.dart`

## Method

Every static aspect was compared by reading both sides. Every byte-producing path was executed on both sides with identical inputs (owner private key `0x…01`, chainId `11155111`, index `{0,5}`, fixed calls and a fixed UserOperation) and the outputs compared byte-for-byte. JS vectors were produced against the repo's own `viem`; Dart vectors against the package under `dart --packages`.

## Verdict table

| Aspect | Verdict |
| --- | --- |
| Factory / metaFactory address | mirrors |
| Bootstrap address | mirrors |
| Validator (multiple-owner ECDSA) address | mirrors |
| initMSA bootstrap init data | mirrors |
| initCode / factoryData (createAccount + salt/index) | mirrors |
| Dummy / stub signature | mirrors |
| execute calldata (ERC-7579 single, mode encoding) | mirrors |
| execute calldata (ERC-7579 batch) | mirrors |
| signUserOperation path (userOpHash + signature) | mirrors |
| EntryPoint version / address handling | mirrors (default); custom EP address override **missing** |
| Nonce key encoding (default key) | mirrors |
| Configurable `nonceKey` parameter | missing |
| signMessage wrapping | **diverges** |
| signTypedData wrapping | **diverges** |
| `sign({ hash })` (ERC-1271 style entry) | missing |

## Byte-for-byte confirmations (mirrors)

- **Addresses** — `constants.ts:23-27` and `constants.dart:15-27` are identical: metaFactory `0x2A40091f044e48DEB5C0FCbc442E443F3341B451`, bootstrap `0x0D5154d7751b6e2fDaa06F0cC9B400549394C8AA`, validator `0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC1906`.
- **Selectors** — createAccount `0xf8a59370`, initMSA `0x642219af`, onInstall `0x6d61fe70`, ERC-7579 execute `0xe9ae5c53`. Confirmed against `toFunctionSelector` and matching `EtherspotSelectors` (`constants.dart:36-50`) / `Erc7579Selectors.execute` (`erc7579.dart:70`). (Note `EtherspotSelectors.execute = 0x61461954` at `constants.dart:50` is dead — encoding uses the ERC-7579 selector `0xe9ae5c53`; harmless.)
- **factoryData** — for index 0 and 5 the JS `getAccountInitCode` (`toEtherspotSmartAccount.ts:134-159`) and Dart `getFactoryData`/`_encodeInitCode`/`_encodeInitMSA` (`etherspot_account.dart:180-390`) produce identical bytes, including the `initMSA` header offsets `0x80/0x180/0x280/0x340`, the validators/executors/fallbacks arrays each containing one entry, the single hook tuple, and the `onInstall(0x)` payloads. Salt is `toHex(index,{size:32})` on both sides.
- **Stub signature** — `DUMMY_ECDSA_SIGNATURE` (`constants.ts:3-4`) equals `etherspotDummyEcdsaSignature` (`constants.dart:54-55`); string-diff confirmed identical.
- **execute calldata** — single-call (mode byte0 `0x00`, byte1 `0x00` because `revertOnError:false`) and batch (mode byte0 `0x01`) outputs match byte-for-byte. JS `encode7579Calls` (`encode7579Calls.ts`) with `encodeExecutionMode` (`supportsExecutionMode.ts:46-62`) vs Dart `encode7579Execute`/`encode7579ExecuteBatch` (`erc7579.dart:334-378`). Both encode single as packed `to‖value(32)‖data`, batch as `Execution[]` tuple array.
- **signUserOperation** — v0.7 packing and `getUserOperationHash` agree: identical `userOpHash` `0x76a1…bb62` and identical signature `0x4de4…1b`. JS signs `localOwner.signMessage({ message: { raw: hash } })` (`toEtherspotSmartAccount.ts:347-366`); Dart signs `owner.signPersonalMessage(opHash)` (`etherspot_account.dart:410-418`). Both apply the EIP-191 prefix to the 32-byte hash exactly once, and neither wraps the result with the validator address — matching intent and bytes.
- **Nonce key (default)** — JS `getNonceKeyWithEncoding` (`getNonceKey.ts:4-21`) and Dart `nonceKey` getter (`etherspot_account.dart:125-138`) both produce `0x740ed7c11b9da33d9c80bd76b826e4e90cc190600000000` (validator‖mode`00`‖type`00`‖key`0000`, left-padded to 24 bytes).
- **EntryPoint** — both default to v0.7 at `0x0000000071727De22E5E9d8BAf0edAc6f37da032` (`entry_point.dart:21-22`) and v0.7 packing only.

## Diverges / missing findings

### 1. signMessage wrapping — diverges

**JS** (`toEtherspotSmartAccount.ts:311-328`): signs the raw personal-message signature over the message, corrects V to 27/28, and packs `encodePacked(["address","bytes"], [validatorAddress, signature])`. Crucially, `localOwner.signMessage({ message })` computes `hashMessage(message)` and signs that hash **once** (EIP-191 applied a single time).

**Dart** (`etherspot_account.dart:423-432`): computes `hashMessage(message)` and then calls `owner.signPersonalMessage(messageHash)`. `PrivateKeyOwner.signPersonalMessage` (`account_owner.dart:116-129`) applies the EIP-191 prefix **again** to the already-hashed message before signing — a double prefix.

**Evidence (message `"hello etherspot"`):**
- JS wrapped: `0x0740…1906` + body `7227dee3…336d1c`
- Dart wrapped: `0x0740…1906` + body `2163475b…241d61b`

The validator-prefix envelope matches, but the signature body differs. Signing the message hash *raw* on the Dart side reproduces the JS body exactly: `owner.signRawHash(hashMessage(...)) = 7227dee3…336d1c`. So the fix is to sign the hash raw (as viem does) rather than via `signPersonalMessage`. As written, an on-chain ERC-1271 `isValidSignature` check would recover a different signer than JS produces.

### 2. signTypedData wrapping — diverges

Same root cause. **JS** (`toEtherspotSmartAccount.ts:329-345`) signs the EIP-712 digest via `localOwner.signTypedData(typedData)` (digest signed raw, once), then packs `[validatorAddress, signature]`. **Dart** (`etherspot_account.dart:437-446`) computes `hashTypedData(typedData)` then `owner.signPersonalMessage(hash)`, adding an EIP-191 prefix over the 712 digest.

**Evidence (fixed typed data):**
- JS wrapped: `0x0740…1906` + body `dd2e6d36…f598e51b`
- Dart wrapped: `0x0740…1906` + body `60751a9d…3b58321c`

Signing the 712 digest raw on the Dart side reproduces JS: `owner.signRawHash(hashTypedData(...)) = dd2e6d36…f598e51b` (and `owner.signTypedData(typedData)` yields the same). The Dart method should use raw-hash signing, not `signPersonalMessage`.

> Note: neither the JS nor the Dart `signMessage`/`signTypedData` applies the `wrapMessageHash` (ERC-7739 / EIP-712 nested-domain) wrapper that Nexus/Kernel use — the file `etherspot/utils/wrapMessageHash.ts` exists but is unused by `toEtherspotSmartAccount`. So this is purely the double-prefix bug, not a missing wrapper.

### 3. Configurable `nonceKey` — missing

**JS** threads `parameters.nonceKey ?? 0n` into `getNonceKeyWithEncoding` (`toEtherspotSmartAccount.ts:299-302`, `getNonceKey.ts:14-16`), placing the 2-byte user key at the tail of the 24-byte encoding.

**Dart** hardcodes the suffix to `'0000'` (`etherspot_account.dart:133`) and exposes no `nonceKey` field on `EtherspotSmartAccountConfig`. Default (key 0) behavior is identical; a non-zero user nonce key cannot be expressed. Low severity.

### 4. Custom EntryPoint address override — missing

**JS** accepts `entryPoint: { address, version }` and uses `parameters.entryPoint?.address ?? entryPoint07Address` (`toEtherspotSmartAccount.ts:176-179, 222-226`). **Dart** hardcodes `entryPoint => EntryPointAddresses.v07` (`etherspot_account.dart:121-122`) with no override. Both restrict version to v0.7, so default behavior mirrors; only a non-standard EP address deployment is unsupported. Low severity.

### 5. `sign({ hash })` entry point — missing

**JS** exposes `sign({ hash })` routed to `signMessage({ message: hash })` (`toEtherspotSmartAccount.ts:308-310`), used by generic signing/ERC-1271 flows. The Dart `SmartAccount` surface exposes `signMessage`, `signTypedData`, and `signUserOperation` but no generic `sign(hash)`. Low severity; also note that even if added it would inherit the divergence in finding 1.

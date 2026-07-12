# Parity Audit: Trust Wallet (Barz) Smart Account

**Scope**: permissionless.js v0.3.5 `accounts/trust/` vs permissionless.dart v0.3.0 `lib/src/accounts/trust/`

**JS files**:
- `/Users/liorag/Documents/development/permissionless/permissionless.js/packages/permissionless/accounts/trust/toTrustSmartAccount.ts`
- `.../accounts/trust/utils/getFactoryData.ts`, `encodeCallData.ts`, `decodeCallData.ts`

**Dart files**:
- `/Users/liorag/Documents/development/permissionless/permissionless.dart/packages/permissionless/lib/src/accounts/trust/trust_account.dart`
- `.../trust/constants.dart`, `.../trust/trust.dart` (barrel)

**Method**: Side-by-side source reading, plus byte-for-byte cross-execution: viem (`encodeFunctionData`, `getUserOperationHash`, `signMessage`, `signTypedData`) vs the Dart implementation run against the same inputs and private key. Calldata (factoryData, execute, executeBatch), stub signature, and userOp signatures were compared as raw hex.

## Verdict Table

| # | Aspect | Verdict | JS | Dart |
|---|--------|---------|----|------|
| 1 | Factory address `0x729c310186a57833f622630a16d13f710b83272a` | mirrors | toTrustSmartAccount.ts:67 | constants.dart:11 |
| 2 | Secp256k1 verification facet `0x81b9E3689390C7e74cF526594A105Dea21a8cdD5` | mirrors | toTrustSmartAccount.ts:66 | constants.dart:15 |
| 3 | factoryData: `createAccount(address,bytes,uint256)` selector `0x296601cd`, owner = 20-byte EOA address as `bytes`, salt = index (verified byte-identical) | mirrors | utils/getFactoryData.ts:16-49, toTrustSmartAccount.ts:145-154 | trust_account.dart:172-192, constants.dart:29 |
| 4 | initCode = factory ++ factoryData / getFactoryArgs tuple | mirrors | toTrustSmartAccount.ts:145-154 | trust_account.dart:153-169 |
| 5 | getAddress via `getSenderAddress` (EntryPoint simulation), with optional pre-set `address` | mirrors | toTrustSmartAccount.ts:160-173 (address param :87,127) | trust_account.dart:123-149 |
| 6 | Dummy/stub signature (identical 65-byte string, v=0x1c) | mirrors | toTrustSmartAccount.ts:187-189 | trust_account.dart:298-299 |
| 7 | Single call: `execute(address,uint256,bytes)` selector `0xb61d27f6` (verified byte-identical incl. empty-data case) | mirrors | utils/encodeCallData.ts:52-77 | trust_account.dart:196-214, constants.dart:23 |
| 8 | Batch: `executeBatch(address[],uint256[],bytes[])` selector `0x47e1da2a`, used when calls > 1 (verified byte-identical) | mirrors | utils/encodeCallData.ts:11-44 | trust_account.dart:218-294, constants.dart:26 |
| 9 | signUserOperation: v0.6 userOpHash then EIP-191 personal-sign of the raw hash (verified: identical signature for identical userOp/key) | mirrors | toTrustSmartAccount.ts:209-230 | trust_account.dart:313-316, 359-390 |
| 10 | EP version support: v0.6 only, v0.7 path rejected | mirrors | toTrustSmartAccount.ts:82-85 (type-level `"0.6"`) | trust_account.dart:109, 305-309 (`UnsupportedError`) |
| 11 | Custom EntryPoint address override (JS `entryPoint.address` param) | diverges (minor) | toTrustSmartAccount.ts:82-85, 129-133 | trust_account.dart:109 (hardcoded) |
| 12 | signMessage: Barz EIP-712 wrapper (`BarzMessage`, domain name "Barz", version "v0.2.0") | **diverges** | toTrustSmartAccount.ts:35-56, 193-200 | trust_account.dart:320-323, 333-356 |
| 13 | signTypedData: same Barz EIP-712 wrapper over `hashTypedData` | **diverges** (same root cause as 12) | toTrustSmartAccount.ts:201-208 | trust_account.dart:327-330, 333-356 |
| 14 | `sign({ hash })` (raw sign entry point, delegates to signMessage) | missing | toTrustSmartAccount.ts:190-192 | no counterpart (interface: smart_account_interface.dart:36-129) |
| 15 | decodeCalls (executeBatch/execute calldata decoding) | missing | utils/decodeCallData.ts:3-88, toTrustSmartAccount.ts:177-179 | no counterpart in trust/ or interface |
| 16 | nonceKey passthrough for getNonce | mirrors | toTrustSmartAccount.ts:180-186 | trust_account.dart:112-113 |

Counts: **10 mirrors, 3 diverges (2 of them one root cause, 1 minor), 2 missing, 0 dart-only.**

---

## Finding 1 (diverges, HIGH): signMessage / signTypedData sign the wrong digest

**JS behavior** (`toTrustSmartAccount.ts:35-56`): both `signMessage` and `signTypedData` funnel into `_signTypedData`, which calls `signer.signTypedData({...})` with the Barz domain. viem's `signTypedData` signs the **EIP-712 digest directly** — `sign(keccak256("\x19\x01" ‖ domainSeparator ‖ structHash))` — with no EIP-191 personal-message prefix.

```ts
// toTrustSmartAccount.ts:41-55
return signer.signTypedData({
    domain: { chainId, name: "Barz", verifyingContract: accountAddress, version: "v0.2.0" },
    types: { BarzMessage: [{ name: "message", type: "bytes" }] },
    message: { message: hashedMessage },
    primaryType: "BarzMessage"
})
```

**Dart behavior** (`trust_account.dart:333-356`): `_signWithBarzWrapper` builds the identical Barz `TypedData`, but then computes `hashTypedData(wrappedTypedData)` itself and passes the digest to `owner.signPersonalMessage(hash)`:

```dart
// trust_account.dart:353-355
// Trust signs typed data with personal message prefix
final hash = hashTypedData(wrappedTypedData);
return _config.owner.signPersonalMessage(hash);
```

`PrivateKeyOwner.signPersonalMessage` (`account_owner.dart:116-129`) prepends `"\x19Ethereum Signed Message:\n32"` and re-hashes before signing. So Dart signs `keccak256(EIP-191 prefix ‖ eip712Digest)` while JS signs `eip712Digest`. The comment in the Dart code asserting "Trust signs typed data with personal message prefix" contradicts the JS reference.

**Empirical proof** (same key `0x59c6...690d`, message `'hello'`, account `0x4444...4444`, chainId 11155111):
- JS `signTypedData` (Barz wrapper): `0x461b0fe38f4c33023993a07c4f39f9957295250657ad5d9332c8cab134e276344d5c0308b8971abf79cb4ea4980c581ad1b44f4a862ff2be9854a57ac3db7f841c`
- Dart `signMessage('hello')`: `0xa1f5e89edd8c0a1579b16ae14430b7af78a85935870d39d1746aceabb1a57ec61864a2379ce16baaf495463c054962a08e04df27a1b1e3342686c297305d01131c`

**Impact**: signatures produced by Dart `signMessage`/`signTypedData` will fail Barz's ERC-1271 on-chain verification (which expects the EIP-712 digest signature per the reference). `signUserOperation` is unaffected (verified identical, Finding table row 9).

**Fix**: `_signWithBarzWrapper` should call `_config.owner.signTypedData(wrappedTypedData)` — that method already exists and signs the EIP-712 digest raw (`account_owner.dart:151-169`) — instead of `hashTypedData` + `signPersonalMessage`.

## Finding 2 (diverges, minor): custom EntryPoint address not configurable

JS accepts `entryPoint: { address, version: "0.6" }` and uses `parameters.entryPoint?.address ?? entryPoint06Address` (`toTrustSmartAccount.ts:82-85, 129-133`), so a nonstandard v0.6 EntryPoint deployment can be targeted. Dart hardcodes `EntryPointAddresses.v06` (`trust_account.dart:109`) with no config parameter (`TrustSmartAccountConfig`, `trust_account.dart:30-64`). Behavior is identical for the canonical EntryPoint; only the override capability is absent.

## Finding 3 (missing): `sign({ hash })`

JS exposes `sign` (`toTrustSmartAccount.ts:190-192`), delegating to `signMessage({ message: hash })` — used by viem infrastructure (e.g., ERC-1271 flows). The Dart `SmartAccountV06` interface (`smart_account_interface.dart:36-129`) has no raw `sign` method and `TrustSmartAccount` provides none. Callers can approximate via `signMessage`, but note viem's `sign` treats the hash hex string as a UTF-8 message (`hashMessage(hexString)`), which Dart's `signMessage(String)` (`trust_account.dart:320-323`, `message_hash.dart:22-36`) would reproduce if called with the hash string — so the gap is API surface, not a conflicting encoding.

## Finding 4 (missing): `decodeCalls`

JS implements `decodeCallData` (`utils/decodeCallData.ts:3-88`) wired as `decodeCalls` (`toTrustSmartAccount.ts:177-179`): tries `executeBatch(address[],uint256[],bytes[])` first, falls back to `execute(address,uint256,bytes)`. Dart has no decode counterpart anywhere in `lib/src/accounts/trust/` and the interface defines none. This appears to be a library-wide omission in the Dart port (no account exposes decode), not Trust-specific.

## Notes (non-behavioral)

- `PrivateKeyOwner.publicKey` (`account_owner.dart:104-113`) is documented as "Required by TrustAccount for the Barz factory" but is never used — the factory owner bytes are the 20-byte EOA address on both sides (matching JS `localOwner.address`, `toTrustSmartAccount.ts:149`). The doc comment is stale, the behavior is correct.
- Dart `getAddress` throws `StateError` when neither `address` nor `publicClient` is supplied (`trust_account.dart:144-148`); JS always has a client by construction. Equivalent when used as documented.
- Byte-for-byte verified vectors: `createAccount` factoryData, initCode, `execute` (with and without calldata), `executeBatch` (2 calls, mixed empty data), stub signature, and v0.6 userOp signature all match viem output exactly.

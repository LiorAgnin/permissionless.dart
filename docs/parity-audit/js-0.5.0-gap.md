# JS 0.5.0 gap — permissionless.dart vs permissionless.js

**Date:** 2026-11-04
**Tags compared:** `permissionless@0.4.1` → `permissionless@0.5.0`
**JS package:** `permissionless.js/packages/permissionless/`
**Dart packages:** `permissionless.dart/packages/permissionless/`, `permissionless.dart/packages/permissionless_passkeys/`
**Diff command:** `git -C permissionless.js diff permissionless@0.4.1 permissionless@0.5.0 -- packages/permissionless`

12 files changed in the package. One is an API removal (`utils/ox.ts` plus its re-export in `utils/index.ts`). Eight are call-site rewrites from `await getOxExports()` to a static `import { … } from "ox"`. Four of those eight also absorb the ox 0.x → 1.x type change (coordinates and signature scalars became `Hex` strings, now wrapped in `BigInt(...)`). The rest are packaging and docs.

## Bottom line

For valid inputs, 0.5.0 produces the same bytes 0.4.1 did. Every ox function JS calls (`Base64.toBytes`, `Base64.fromBytes`, `PublicKey.fromHex`, `Signature.fromHex`) returns the same numeric values in ox 1.8.8 as in ox 0.11.3. The only runtime differences come from ox 1.8.8 being stricter on malformed input: `Base64.toBytes` now throws on invalid characters, impossible lengths and excess padding, and `PublicKey.fromHex` now rejects a 65-byte key whose prefix is not `0x04`. Dart already throws on malformed base64. It never parses a serialized P-256 public key on these paths: x and y arrive as `BigInt`. Dart never had `getOxExports` / `hasOxModule` or any optional-dependency fallback, so the removal leaves nothing to port.

**Behavioral Dart gaps from 0.5.0: 0.**

## `getOxExports` / `hasOxModule` removal (`utils/ox.ts`, `utils/index.ts`)

### JS 0.4.1 (`utils/ox.ts:1-48`, re-exported at `utils/index.ts:43-44`)

```ts
let oxModule: any = null
try {
    const importPromise = import("ox")
    oxModule = { importPromise }
} catch (error) {
    // ox is not installed, this is fine for optional dependency
}

export async function getOxModule() {
    if (!oxModule) throw new Error("The 'ox' package is required for WebAuthn functionality. ...")
    try { return await oxModule.importPromise }
    catch (error) { throw new Error("The 'ox' package is required for WebAuthn functionality. ...") }
}

export function hasOxModule(): boolean { return oxModule !== null }

export async function getOxExports() {
    const ox = await getOxModule()
    return { Base64: ox.Base64, Hex: ox.Hex, PublicKey: ox.PublicKey,
             Signature: ox.Signature, WebAuthnP256: ox.WebAuthnP256 }
}
```

`ox` was an optional peer dependency (`peerDependenciesMeta.ox.optional: true`, pinned `^0.11.3`). The module started `import("ox")` at load time and stored the promise. A missing `ox` only failed when a WebAuthn path awaited `getOxExports()`, and the user then got the "please install ox" error.

Two facts from reading the code:

- `hasOxModule()` always returned `true`. `import()` never throws synchronously, so the `catch` never ran and `oxModule` was always set. The helper could not detect a missing `ox`.
- Inside the package, `hasOxModule` had no callers. `getOxExports` had eight callers, all on WebAuthn or passkey-server paths (listed in the next section). Outside the package, only `packages/wagmi-demo/src/PasskeyServerDemo.tsx` used it, for `WebAuthnP256.sign`; that demo now imports `WebAuthnP256` from `ox` directly. `WebAuthnP256` was exported but no library code used it.

### JS 0.5.0

`utils/ox.ts` is deleted and the re-export is gone from `utils/index.ts`. `ox` moved to `dependencies` (`"ox": "^1.8.8"`). `viem` stays the only peer. Every former call site imports from `ox` at module top level.

Runtime effect: the "ox missing" branch no longer exists, because `ox` is always installed. Non-WebAuthn code paths never touched `getOxExports`, so they behave as before. WebAuthn paths now run against ox 1.8.8 rather than whatever `^0.11.3` the consumer had installed. The `await getOxExports()` microtask hop is gone, but that changes no ordering anyone can observe.

### Dart today

None of this has a Dart counterpart. No `getOxExports`, `hasOxModule`, dynamic import or optional-dependency fallback exists in either package. A search for `ox` / `getOxExports` / `hasOxModule` across `packages/permissionless/lib` and `packages/permissionless_passkeys/lib` finds one comment (`lib/src/clients/passkey_server/passkey_server_client.dart:383`, "Base64 helpers matching ox Base64.fromBytes / toBytes used by permissionless.js"). Base64 comes from `dart:convert`. P-256 coordinates are typed `BigInt` on `WebAuthnAccountOwner` (`lib/src/accounts/webauthn_owner.dart:68`, `:71`, `:77`: getters `x`, `y`, `credentialId`). Native WebAuthn signing and its dependencies live in the separate `permissionless_passkeys` package. That package split plays the role JS's optional peer used to play.

### Verdict

API-only change in JS. Dart has nothing to remove and nothing to add. The 0.5.0 "always installed" state matches how Dart has always worked.

## WebAuthn / passkey call sites after the ox 0.11.3 → 1.8.8 bump

The ox 1.0.0 changelog lists the relevant breaking change: "Migrated ECDSA and BLS coordinate fields (`r`, `s`, `x`, `y` …) from `bigint` to padded `Hex.Hex` strings … on `Signature`, `PublicKey` …". JS 0.5.0 compensates by wrapping each read in `BigInt(...)`. Each function was compared from source: ox 0.11.3 from the rig's `node_modules/ox/core/`, ox 1.8.8 from the published npm tarball `src/core/`.

| ox function | 0.11.3 | 1.8.8 | Same output for valid input? |
|---|---|---|---|
| `Signature.fromHex` | length check 130/132; `r`,`s` = `BigInt(Hex.slice(...))` | same length check; `r`,`s` = `Hex.slice(...)` (32-byte padded hex) | Yes: `BigInt(hex)` gives the same scalar |
| `PublicKey.fromHex` | length check 130/132/68; `x`,`y` as `bigint`; **no prefix check** | same lengths; `x`,`y` as padded hex; then `assert(result)` requires `prefix === 4` for uncompressed and `2`/`3` for compressed | Yes for a 64-byte key (prefix set to 4) and for a 65-byte key with `0x04`. A 65-byte key with any other prefix now throws. |
| `Base64.toBytes` | lenient: unknown chars map to `undefined` and decode as garbage; no length or padding validation | strict: throws `InvalidCharacterError` (incl. `=` inside the body), `InvalidLengthError` (`len % 4 == 1`), `InvalidPaddingError` (>2 `=`) | Yes. Same size formula; both alphabets accepted (`-`/`_` → 62/63) |
| `Base64.fromBytes` | loop encoder; `pad` default true; `url` swaps `+/` → `-_` | native `Uint8Array.prototype.toBase64` when present, else the identical loop | Yes |

The ox 1.0.0 move to noble v2 also made `P256` signing default to low-S. permissionless.js never calls `P256.sign`: WebAuthn signatures come from viem's `WebAuthnAccount.sign`, which uses viem's own `ox`. `Signature.fromHex` does not normalize `s`. The bump therefore changes no signature bytes.

### Kernel WebAuthn validator data (`accounts/kernel/toKernelSmartAccount.ts`)

**JS 0.4.1 (`:324-349`)**

```ts
const { PublicKey, Hex, Base64 } = await getOxExports()
const parsedPublicKey = PublicKey.fromHex(owner.publicKey)
const authenticatorIdHash = keccak256(Hex.fromBytes(Base64.toBytes(owner.id)))
// ... { x: parsedPublicKey.x, y: parsedPublicKey.y }, authenticatorIdHash
```

**JS 0.5.0 (`:1`, `:324-345`)**

```ts
import { Base64, PublicKey } from "ox"
const parsedPublicKey = PublicKey.fromHex(owner.publicKey)
const authenticatorIdHash = keccak256(Base64.toBytes(owner.id))
// ... { x: BigInt(parsedPublicKey.x), y: BigInt(parsedPublicKey.y) }, authenticatorIdHash
```

viem `keccak256` hashes the decoded bytes whether it gets hex or bytes, so dropping `Hex.fromBytes` leaves `authenticatorIdHash` unchanged. `BigInt(hex)` gives back the old `bigint`. The new failure modes: a malformed `owner.id` now throws instead of hashing garbage, and a 65-byte `publicKey` with a non-`0x04` prefix now throws.

**Dart today**

- `lib/src/accounts/kernel/kernel_account.dart:479-485` calls `encodeKernelWebAuthnValidatorData(x: webAuthnOwner.x, y: webAuthnOwner.y, credentialId: webAuthnOwner.credentialId)`.
- `lib/src/utils/webauthn_encoding.dart:344-359` returns `x ‖ y ‖ keccak256(credentialId)`, each a 32-byte word. That matches the JS `encodeAbiParameters([tuple(uint256,uint256), bytes32])` layout.
- `credentialId` is the raw credential ID bytes: `permissionless_passkeys/lib/src/accounts/to_webauthn_account.dart:135` (`credential.rawId`), filled from `PassKeyPublicKey.credentialId` at `permissionless_passkeys/lib/src/types/webauthn_credential.dart:34-36`. JS `Base64.toBytes(owner.id)` decodes viem's base64url `id`, which is the base64url encoding of `rawId`. The bytes are the same.
- x and y come from `credential.x` / `credential.y` (`to_webauthn_account.dart:129-132`) as `BigInt`. No serialized public key is parsed, so the prefix assertion has no equivalent input in Dart.

**Verdict:** matches 0.5.0. No test pins Kernel validator-data bytes against a JS vector; the match rests on reading the code.

### Kernel WebAuthn `signMessage` (`accounts/kernel/utils/signMessage.ts`)

**JS 0.4.1 (`:59-77`):** `const { Signature } = await getOxExports()`, then `Signature.fromHex(signatureData)`, then `BigInt(signature.r)` / `BigInt(signature.s)` (the `BigInt` wrap already existed and was a no-op on `bigint`).

**JS 0.5.0 (`:1`, `:59-76`):** static `import { Signature } from "ox"`; otherwise identical. `BigInt` now converts hex to `bigint`.

**Dart today:** `lib/src/accounts/kernel/kernel_account.dart:792-806` (`_signWebAuthnWithKernelWrapper`) and `:668-679` (userOp signing) call `signP256`, which returns `r` and `s` as `BigInt` straight from web3_signers (`permissionless_passkeys/lib/src/accounts/to_webauthn_account.dart:141-152`). Dart never parses a compact hex signature, and `encodeKernelWebAuthnSignature` (`lib/src/utils/webauthn_encoding.dart:31-69`) writes them as uint256 words.

**Verdict:** matches 0.5.0. The `usePrecompiled` difference (JS hard-codes `false`, Dart detects RIP-7212) predates this release and is recorded as `01-account-kernel.md` D5 / O2.

### Safe WebAuthn signature (`accounts/safe/signUserOperation.ts`)

**JS 0.4.1 (`:95-121`) / 0.5.0 (`:1`, `:95-120`):** the same change as Kernel `signMessage`: `Signature.fromHex`, then `[BigInt(signature.r), BigInt(signature.s)]`. The `BigInt` wrap already existed.

**Dart today:** `lib/src/accounts/safe/safe_account.dart:960-965` → `encodeSafeWebAuthnSignature` (`lib/src/utils/webauthn_encoding.dart:126-205`). `r` and `s` are `BigInt` from `signP256`.

**Verdict:** matches 0.5.0. This release did not touch the challenge regex. JS pins the challenge at exactly 43 base64url chars, while Dart's `_extractClientDataFields` (`webauthn_encoding.dart:150-152`) accepts 1 or more. For a 32-byte challenge both match the same input, so the difference is cosmetic.

### Safe WebAuthn shared-signer `configure` (`accounts/safe/toSafeSmartAccount.ts`)

**JS 0.4.1 (`:878-889`):** `const { PublicKey } = await getOxExports()`, then `{ x: parsedPublicKey.x, y: parsedPublicKey.y, verifiers: BigInt(safeP256VerifierAddress) }`.

**JS 0.5.0 (`:1`, `:878-888`):** static import; `x: BigInt(parsedPublicKey.x)`, `y: BigInt(parsedPublicKey.y)`. Same values, plus the new prefix assertion on 65-byte keys.

**Dart today:** `lib/src/accounts/safe/safe_account.dart:457-470` → `encodeWebAuthnSignerConfigure(x: webAuthnOwner.x, y: webAuthnOwner.y, p256VerifierAddress: …)` (`lib/src/utils/webauthn_encoding.dart:293-330`), with `x`/`y` as `BigInt`.

**Verdict:** matches 0.5.0. Dart has no serialized-key input for the prefix check to apply to.

### Passkey server actions (`actions/passkeyServer/*.ts`)

**JS 0.4.1 → 0.5.0:**

| File | 0.4.1 | 0.5.0 | Behavior change |
|---|---|---|---|
| `startAuthentication.ts` | `toHex((await getOxExports()).Base64.toBytes(response.challenge))` (`:33`) | `toHex(Base64.toBytes(response.challenge))` (`:32`) | Malformed `challenge` from the server now throws |
| `startRegistration.ts` | `challenge: Base64.toBytes(...)`, `user.id: Base64.toBytes(...)` (`:107-120`) | same, `user.id` wrapped in `new Uint8Array(...)` (`:110`, `:119`) | Malformed `challenge` / `user.id` now throws. The wrap is a typed-array copy (0.11.3 returned a view into a larger buffer), with the same bytes |
| `verifyAuthentication.ts` | `const { Base64 } = await getOxExports()` (`:40`) | static import (`:1`); the stale `// import { Base64 } from "ox"` comment becomes the real import | None: `fromBytes` output is identical |
| `verifyRegistration.ts` | `const { Base64 } = await getOxExports()` (`:28`) | static import (`:1`) | None |

**Dart today** (`lib/src/clients/passkey_server/passkey_server_client.dart`):

- Decode: `_base64ToBytes` (`:386-397`) normalizes `-_` to `+/`, pads to a multiple of 4, and calls `dart:convert` `base64Decode`. Used for `user.id` and `challenge` in `startRegistration` (`:75`, `:79`) and for `challenge` in `startAuthentication` (`:150`, returned as `0x` hex at `:153`, like JS `toHex`).
- Encode: `_base64Encode` / `_base64UrlEncode` (`:399-407`). `verifyRegistration` (`:103-112`): `rawId` url/no-pad, `clientDataJSON` std/pad, `attestationObject` url/pad, `authenticatorData` std/pad. `verifyAuthentication` (`:173-182`): `rawId`, `clientDataJSON`, `signature`, `userHandle` url/no-pad; `authenticatorData` url/pad. Each matches the JS 0.5.0 `Base64.fromBytes` options.
- Strictness, checked by running `base64Decode` on edge inputs: Dart throws `FormatException` on invalid characters (`'a b='`), `=` inside the body (`'ab=c'`), excess padding (`'abc====='`), and `len % 4 == 1` (via padding to an invalid length). ox 1.8.8 rejects the same inputs, so JS 0.5.0 now agrees with Dart where 0.4.1 decoded garbage.

**Verdict:** matches 0.5.0. Side note, not a 0.5.0 gap: Dart also rejects non-canonical trailing bits (`base64Decode('AB==')` throws). Both ox 0.11.3 and 1.8.8 accept that input and drop the bits (`[0]`). Only a non-conforming passkey server would send it.

## Other files in the 0.4.1 → 0.5.0 diff

| File | Change | Classification |
|---|---|---|
| `packages/permissionless/CHANGELOG.md` | 0.5.0 notes | n/a (docs) |
| `packages/permissionless/package.json` | `0.4.1` → `0.5.0`; `ox` moves from optional peer `^0.11.3` to dependency `^1.8.8`; `viem ^2.44.4` stays peer | n/a (packaging) |
| `packages/permissionless/utils/ox.ts` | deleted | API surface (covered above) |
| `packages/permissionless/utils/index.ts` | drops `export { getOxExports, hasOxModule }` | API surface (covered above) |
| `accounts/kernel/utils/signMessage.ts`, `accounts/safe/signUserOperation.ts`, `actions/passkeyServer/verifyAuthentication.ts`, `actions/passkeyServer/verifyRegistration.ts` | `getOxExports()` → static import | packaging (import mechanics only) |
| `accounts/kernel/toKernelSmartAccount.ts`, `accounts/safe/toSafeSmartAccount.ts`, `actions/passkeyServer/startAuthentication.ts`, `actions/passkeyServer/startRegistration.ts` | static import plus ox 1.x type adaptation | behavioral on malformed input only (stricter ox 1.8.8 `Base64.toBytes` / `PublicKey.fromHex`); same bytes for valid input |

Outside `packages/permissionless` (same tag range, not part of the package diff): root `package.json` and `bun.lock` bump the dev `ox` to `1.8.8` (with noble/scure v2); `.github/fixtures/type-consumer/package.json` drops its `ox` devDependency; `packages/wagmi-demo/src/PasskeyServerDemo.tsx` imports `WebAuthnP256` from `ox` directly. None of these affect Dart.

## Dart work required

None for 0.5.0.

- Dart never had `getOxExports` / `hasOxModule` or an optional-`ox` fallback, so the removal needs no port.
- Kernel validator data, Kernel WebAuthn signatures, Safe WebAuthn signatures and Safe shared-signer `configure` take `x`, `y`, `r`, `s` as `BigInt` and the credential ID as raw bytes. The ox `bigint` → `Hex` change and the `BigInt(...)` wraps leave the JS values unchanged, and Dart produces the same words.
- Passkey-server base64 decoding was already strict in Dart. JS 0.5.0 now throws on the same malformed inputs.

Optional, not required by this release: add a Kernel WebAuthn validator-data test vector (fixed x, y and credential ID, expected bytes taken from JS) to `packages/permissionless/test/`. No test pins those bytes today.

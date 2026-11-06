# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-06

This release removes the package's own signature encoders, which is a breaking
change, and fixes several WebAuthn signing bugs
([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Removed

- **BREAKING: the encoders in `lib/src/encoding/`.** The package barrel
  `package:permissionless_passkeys/permissionless_passkeys.dart` exported
  `src/encoding/kernel_encoding.dart` and `src/encoding/safe_encoding.dart`,
  so these were public API. Both files are deleted, and the barrel no longer
  exports these seven functions:
  `encodeKernelWebAuthnSignature`, `getDummyKernelWebAuthnSignature`,
  `encodeSafeWebAuthnSignature`, `encodeSafeWebAuthnSignatureRaw`,
  `getDummySafeWebAuthnSignature`, `encodeWebAuthnSignerConfig` and
  `encodeWebAuthnSignerConfigure`.

  Core `package:permissionless` exports functions with the same names. An app
  that imported both barrels, which is the documented setup, got an
  `ambiguous_import` error on every unqualified call, so most apps could not
  have used the passkeys copies anyway. The Safe copies also produced wrong
  data: `encodeWebAuthnSignerConfigure` used selector `0x75794a3c` instead of
  `configure((uint256,uint256,uint176))` = `0x0dd9692f`, padded the verifier
  to 22 bytes, and `encodeSafeWebAuthnSignature` emitted a
  `validAfter ‖ validUntil ‖ r ‖ s` format that `SafeWebAuthnSharedSigner`
  does not verify. No library code in either package called them.

  To migrate, use the core functions. The signature encoders there take a
  `P256SignatureData`, which `WebAuthnAccount.signP256(hash)` returns, in
  place of a `web3_signers` `Signature`. `encodeSafeWebAuthnSignatureRaw` has
  no replacement because its format was the wrong one. Most apps need none of
  this: pass the `WebAuthnAccount` as the owner to `createKernelSmartAccount`
  or `createSafeSmartAccount`, and the account encodes its own signatures
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Added

- `createPasskeyCredential` takes an optional `authenticatorAttachment`,
  `'platform'` or `'cross-platform'`. The default, `'cross-platform'`, is what
  it used before
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Changed

- Bumped `permissionless` dependency constraint to `^0.6.0` (was `^0.5.0`).
  This release calls `hashMessageBytes`, which is new in permissionless 0.6.0.
  See its [changelog](https://pub.dev/packages/permissionless/changelog).
- **`WebAuthnSignMetadata.challengeIndex` is the offset of the `"challenge"`
  key** in `clientDataJSON`, as in ox's `WebAuthnP256.sign` (viem) and on-chain
  WebAuthn verifiers. It used to be the offset of the challenge *value*, so a
  caller that forwarded it to such a verifier pointed at the wrong bytes. The
  number you see is smaller than before. `typeIndex` already matched, and no
  encoder in either package reads `challengeIndex`
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Deprecated

- `createWebAuthnAccountFromCredential`. Use `createWebAuthnAccount`, which
  has the same parameters and does the same thing
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Fixed

- **`signMessage` and `signTypedDataViem` threw `UnimplementedError`.** They
  now sign `hashMessage(message)` and `hashTypedData(...)`, like viem's
  `toWebAuthnAccount`. A `String` message is UTF-8 text even when it looks
  like hex; pass bytes to sign raw data, like viem's `{ raw }`
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Missing WebAuthn metadata produced an unverifiable signature.** When the
  authenticator returned no `authenticatorData` or `clientDataJSON`, `sign`
  and `signP256` filled in empty values and returned a signature no verifier
  accepts. They now throw `StateError`
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **A `clientDataJSON` without the signed challenge or the `"type"` key was
  accepted** with an index of -1. A Kernel signature then failed later, deep
  in the ABI encoder. `sign` now throws a `StateError` that names the missing
  part ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`WebAuthnCredential` silently truncated coordinates wider than 32 bytes**
  in `publicKeyHex` and `toJson`. It now throws `ArgumentError`. Real P-256
  keys always fit, so real credentials are unaffected
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- The README documented the removed encoders with parameters they never had.
  It now points at the core encoders. The `ToWebAuthnAccountParameters.rpId`
  doc no longer claims a fallback to the credential's rpId, which the
  credential does not store
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

## [0.1.3] - 2026-11-04

### Changed

- Bumped `permissionless` dependency constraint to `^0.5.0` (was `^0.4.0`).
  permissionless 0.5.0 adds `sendUserOperationSync`, fixes Etherspot/Safe v0.7
  signing for a `factory` with null `factoryData`, and makes v0.7/v0.8 signing
  throw for packed gas fields outside uint128. See its
  [changelog](https://pub.dev/packages/permissionless/changelog).
- Bumped `web3_signers` dependency constraint to `^1.1.0` (was `^1.0.0`). This
  pulls in `passkeys` 2.24 (from 2.18); `passkeys_ios` is gone and iOS/macOS go
  through `passkeys_darwin` 0.4. The bytes `signAsync` produces are unchanged.
  web3_signers 1.1.0 removes its deprecated aliases (`PassKeyPair`,
  `PrivateKeySigner`, `EOAWallet`, `signToEc`, …), so apps that import those
  directly from `web3_signers` need to switch to the current names.
- Raised the minimum SDK to Dart `^3.9.0` / Flutter `>=3.35.0` (was
  `>=3.5.0` / `>=3.10.0`), matching what `web3_signers` 1.1.0 already required.

### Fixed

- `WebAuthnCredential.fromPassKeyPair` docs no longer point at `PassKeyPair`,
  which `web3_signers` 1.1.0 removed; they now point at `fromPublicKey`.

## [0.1.2] - 2026-07-12

### Changed

- Bumped `permissionless` dependency constraint to `^0.4.0` (was `^0.3.0`).
  permissionless 0.4.0 fixes the parity-audit P0/P1 bugs, including the
  WebAuthn-relevant Safe stub signatures and ERC-1271 signing paths — see its
  [changelog](https://pub.dev/packages/permissionless/changelog) and note its
  breaking changes (Safe default threshold, counterfactual addresses).
- Bumped `web3dart` dependency constraint to `^3.0.3` (was `^3.0.2`).

## [0.1.1] - 2026-04-21

### Changed

- Bumped `permissionless` dependency constraint to `^0.3.0` (was `^0.2.0`).
- Bumped `web3dart` dependency constraint to `^3.0.2` (was `^3.0.1`).

## [0.1.0] - 2026-02-20

Initial release of permissionless_passkeys - WebAuthn/Passkeys support for permissionless.dart
ERC-4337 smart accounts.

### Added

- **viem-compatible WebAuthn Account API**
  - `WebAuthnAccount` - Abstract account interface extending `WebAuthnAccountOwner` from permissionless
  - `WebAuthnSignReturnType` - Return type with signature and metadata
  - `WebAuthnSignMetadata` - Authenticator data, client JSON, indices
  - `toWebAuthnAccount()` - Factory function (matches viem pattern)
  - `createWebAuthnAccount()` - Dart-idiomatic convenience function

- **Types**
  - `WebAuthnCredential` - Wrapper for WebAuthn credential data with JSON serialization

- **Factory Functions**
  - `createPasskeyCredential()` - Register passkeys with biometrics
  - `createWebAuthnAccountFromCredential()` - Create account from credential

- **Encoding Functions**
  - `encodeKernelWebAuthnSignature()` - ABI encode signatures for Kernel WebAuthn validator
  - `encodeSafeWebAuthnSignature()` - ABI encode signatures for Safe WebAuthn signer
  - `encodeSafeWebAuthnSignatureRaw()` - Encode with explicit timestamps
  - `encodeWebAuthnSignerConfig()` - Encode signer public key configuration
  - `encodeWebAuthnSignerConfigure()` - Encode SafeWebAuthnSharedSigner configure call
  - `getDummyKernelWebAuthnSignature()` - Gas estimation stub for Kernel
  - `getDummySafeWebAuthnSignature()` - Gas estimation stub for Safe

- **Smart Account Integration**
  - `WebAuthnAccount` can be passed directly to `createKernelSmartAccount()` as owner
  - `WebAuthnAccount` can be passed directly to `createSafeSmartAccount()` as owner
  - Works with Kernel v0.3.x (WebAuthn validator) and Safe v1.4.1/v1.5.0 (shared signer)

- **Tests**
  - Comprehensive unit tests for encoding functions
  - Credential serialization tests (JSON round-trip)
  - WebAuthnAccount creation and signing tests

- **Example App**
  - Flutter example demonstrating passkey registration
  - Kernel and Safe account creation from WebAuthn credentials
  - Riverpod state management

### Fixed
- **Kernel WebAuthn**: Fixed null safety for `typeIndex` in kernel signature encoding
  - `signature.getTypeLocation()!` replaced with `signature.getTypeLocation() ?? 0`
  - Handles undefined typeIndex by defaulting to 0

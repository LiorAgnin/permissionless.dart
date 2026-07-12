# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

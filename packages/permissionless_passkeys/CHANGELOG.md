# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-dev.2] - 2025-01-24

### Fixed
- **Monorepo**: Fixed `repository` URL in pubspec.yaml to point to package subdirectory for pub.dev score

## [0.1.0-dev.1] - 2025-01-24

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

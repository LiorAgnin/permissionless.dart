# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WebAuthn/Passkeys extension for [permissionless.dart](../permissionless/). Enables biometric authentication (Face ID, Touch ID, Windows Hello) for ERC-4337 smart accounts using P256 signatures.

## Commands

```bash
flutter pub get                    # Install dependencies
flutter analyze                    # Static analysis
flutter test                       # Run all tests
flutter test test/encoding/        # Run specific test directory
dart format .                      # Format code
dart doc                           # Generate API docs
```

## Code Style

- Follow official Dart style guide (enforced by `flutter_lints` package)
- Use `final` for variables that won't be reassigned
- Prefer `const` constructors where possible
- All public APIs must have dartdoc comments with examples
- Use named parameters for functions with 3+ parameters

## Architecture

### Directory Structure
```
lib/src/
├── accounts/              # WebAuthn account implementation
│   ├── webauthn_account.dart         # WebAuthnAccount abstract class
│   └── to_webauthn_account.dart      # toWebAuthnAccount() factory
├── encoding/              # ABI encoding functions
│   ├── kernel_encoding.dart          # Kernel signature format
│   └── safe_encoding.dart            # Safe signature format
├── types/                 # Type definitions
│   └── webauthn_credential.dart      # Credential wrapper
└── factory.dart           # Convenience factory functions
```

### Key Abstractions
- `WebAuthnCredential`: Wrapper for P256 public key coordinates (x, y) and credential ID
- `WebAuthnAccount`: Account owner interface for signing with passkeys (extends `WebAuthnAccountOwner` from permissionless)
- `toWebAuthnAccount()`: Factory function to create a WebAuthn account from a credential (viem-compatible API)

### Signature Encoding
Kernel and Safe use different signature formats:

**Kernel** (ABI-encoded struct):
```
(authenticatorData, clientDataJSON, responseTypeLocation, r, s, usePrecompiled)
```

**Safe** (validAfter + validUntil + dynamic signature):
```
validAfter (6 bytes) + validUntil (6 bytes) + ABI-encoded(authenticatorData, clientDataFields, r, s)
```

## Dependencies

- `permissionless`: Core ERC-4337 package (sibling in monorepo)
- `web3_signers`: PassKeySigner for WebAuthn registration/signing
- `web3dart`: Ethereum types (EthereumAddress, etc.)

## Testing

- Tests are in `test/` mirroring `lib/src/` structure
- Unit tests only (no integration tests requiring network/biometrics)
- Use mock credentials from `test/helpers/test_fixtures.dart`
- Test encoding functions with known input/output vectors

### What Can Be Tested
- Signature encoding functions
- Credential serialization (JSON round-trip)
- WebAuthn account creation and signing

### What Cannot Be Tested
- `PassKeySigner.register()` - requires platform biometrics
- Actual signature verification - requires on-chain execution

## P256 Precompile (RIP-7212)

Chains with the P256 precompile at `0x0000...0100` verify signatures in ~3.5k gas vs ~800k without.

Supported chains: Mainnet, Sepolia, Base, Optimism, Polygon, Arbitrum, Scroll, Linea, Zora

## Common Patterns

### Creating Accounts from Credentials
```dart
// 1. Create WebAuthn account from credential (viem-compatible API)
final webAuthnAccount = toWebAuthnAccount(
  ToWebAuthnAccountParameters(
    credential: credential,
    rpId: 'myapp.com',
  ),
);

// Or use the convenience function with named parameters
final webAuthnAccount = createWebAuthnAccount(
  credential: credential,
  rpId: 'myapp.com',
);

// 2. Use with Kernel smart account (v0.3.x supports WebAuthn)
final kernelAccount = createKernelSmartAccount(
  owner: webAuthnAccount,
  chainId: BigInt.from(11155111),
  version: KernelVersion.v0_3_1,
);

// 3. Use with Safe smart account
final safeAccount = createSafeSmartAccount(
  owners: [webAuthnAccount],
  chainId: BigInt.from(11155111),
  version: SafeVersion.v1_4_1,
);
```

### Creating New Passkeys
```dart
// Create a new passkey credential (triggers biometric prompt)
final credential = await createPasskeyCredential(
  rpId: 'myapp.com',
  rpName: 'My Application',
  userName: 'user@example.com',
);

// Serialize for storage
final json = credential.toJson();
```

## Warnings

- Credential IDs are base64-encoded, not hex
- P256 coordinates must be exactly 32 bytes (pad with leading zeros)
- Safe signatures include 6-byte timestamps (validAfter, validUntil)
- Kernel v0.2.x does NOT support WebAuthn - only v0.3.x
- The `rpId` must match exactly between registration and signing

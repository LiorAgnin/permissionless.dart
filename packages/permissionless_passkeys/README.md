# permissionless_passkeys

WebAuthn/Passkeys support for [permissionless.dart](../permissionless/) ERC-4337 smart accounts.

Enable biometric authentication (Face ID, Touch ID, Windows Hello) for your smart accounts using P256 signatures.

## Features

- **WebAuthn Smart Accounts** - Create passkey-authenticated smart accounts
- **Kernel v0.3.x Support** - WebAuthn validator with P256 precompile (RIP-7212)
- **Safe v1.4.1/v1.5.0 Support** - Shared WebAuthn signer module
- **Cross-Platform** - Works on iOS, Android, Web, macOS
- **Biometric Authentication** - Face ID, Touch ID, Windows Hello, Security Keys

## Supported Account Types

| Account | Version | EntryPoint | WebAuthn Signer |
|---------|---------|------------|-----------------|
| **Kernel** | v0.3.0, v0.3.1 | v0.7 | WebAuthn validator module |
| **Safe** | v1.4.1, v1.5.0 | v0.7 | Shared WebAuthn signer |

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  permissionless_passkeys: ^0.1.0
  permissionless: ^0.1.2  # Required peer dependency
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Register a Passkey

```dart
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Register a new passkey (triggers biometric prompt)
final credential = await createPasskeyCredential(
  rpId: 'myapp.com',
  rpName: 'My Application',
  userName: 'user@example.com',
);

// Credential can be serialized for storage
final json = credential.toJson();
// Later: final restored = WebAuthnCredential.fromJson(json);
```

### 2. Create a WebAuthn Account

```dart
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Create a WebAuthn account from the credential
final webAuthnAccount = createWebAuthnAccount(
  credential: credential,
  rpId: 'myapp.com',
);

// Or use the viem-compatible API
final webAuthnAccount = toWebAuthnAccount(
  ToWebAuthnAccountParameters(
    credential: credential,
    rpId: 'myapp.com',
  ),
);

print('Public Key: ${webAuthnAccount.publicKey}');
```

### 3. Use with Kernel or Safe Smart Account

```dart
import 'package:permissionless/permissionless.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Use with Kernel v0.3.x (supports WebAuthn validators)
final kernelAccount = createKernelSmartAccount(
  owner: webAuthnAccount,  // WebAuthnAccount IS an AccountOwner
  chainId: BigInt.from(11155111),
  version: KernelVersion.v0_3_1,
);

// Or use with Safe v1.4.1/v1.5.0 (supports WebAuthn shared signer)
final safeAccount = createSafeSmartAccount(
  owners: [webAuthnAccount],  // WebAuthnAccount IS an AccountOwner
  chainId: BigInt.from(11155111),
  version: SafeVersion.v1_4_1,
);

print('Account Address: ${kernelAccount.address.hex}');
```

### 4. Sign and Send Transactions

```dart
import 'package:permissionless/permissionless.dart';

// Create clients
final bundler = createPimlicoClient(
  url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
  entryPoint: EntryPointAddresses.v07,
);

final smartAccountClient = SmartAccountClient(
  account: account,
  bundler: bundler,
  publicClient: publicClient,
);

// Send a user operation (triggers biometric prompt for signing)
final hash = await smartAccountClient.sendUserOperation(
  calls: [
    Call(
      to: recipientAddress,
      value: BigInt.from(1000000000000000), // 0.001 ETH
    ),
  ],
  maxFeePerGas: gasPrices.fast.maxFeePerGas,
  maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
);

print('UserOperation hash: $hash');
```

### 5. Use the WebAuthn Account Interface (viem-compatible)

For direct signing without a smart account, use the `toWebAuthnAccount` API:

```dart
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Create a WebAuthn account from a credential
final account = createWebAuthnAccount(
  credential: credential,
  rpId: 'myapp.com',
);

// Account properties
print('ID: ${account.id}');           // Base64 credential ID
print('Public Key: ${account.publicKey}'); // Hex: 0x + x(64) + y(64)
print('Type: ${account.type}');       // 'webAuthn'

// Sign a hash (triggers biometric prompt)
final result = await account.sign(hash: userOpHash);

// Result contains:
// - result.signature: Hex signature (r + s, 64 bytes)
// - result.webauthn.authenticatorData: WebAuthn authenticator data
// - result.webauthn.clientDataJSON: Client data JSON string
// - result.webauthn.challengeIndex: Index of challenge in JSON
// - result.webauthn.typeIndex: Index of type in JSON
// - result.raw: Raw Signature object
```

## API Reference

### Types

#### `WebAuthnCredential`

Wrapper for WebAuthn credential data:

```dart
// Create from a PassKeyPublicKey (after registration)
final credential = WebAuthnCredential.fromPublicKey(passKeyPublicKey);

// Or use the factory function
final credential = await createPasskeyCredential(
  rpId: 'myapp.com',
  rpName: 'My App',
  userName: 'user@example.com',
);

// Convert to/from JSON for storage
final json = credential.toJson();
final restored = WebAuthnCredential.fromJson(json);

// Get public key as hex (64 bytes: x || y)
final pubKeyHex = credential.publicKeyHex;
```

#### `WebAuthnAccount`

viem-compatible account interface for passkey signing:

```dart
// Create from credential
final account = createWebAuthnAccount(
  credential: credential,
  rpId: 'myapp.com',
);

// Or use the viem-style function
final account = toWebAuthnAccount(
  ToWebAuthnAccountParameters(
    credential: credential,
    rpId: 'myapp.com',
  ),
);

// Properties
account.id         // Base64 credential ID
account.publicKey  // Hex public key (0x + x + y)
account.type       // 'webAuthn'

// Sign a hash
final result = await account.sign(hash: '0x...');
// Returns WebAuthnSignReturnType with signature and metadata
```

### Encoding Functions

#### Kernel Signatures

```dart
// Encode a WebAuthn signature for Kernel
final encoded = encodeKernelWebAuthnSignature(
  authenticatorData: '0x...',
  clientDataJSON: '{"type":"webauthn.get",...}',
  responseTypeLocation: BigInt.from(1),
  r: BigInt.parse('...'),
  s: BigInt.parse('...'),
  usePrecompile: true,
);

// Get dummy signature for gas estimation
final dummy = getDummyKernelWebAuthnSignature(usePrecompile: true);
```

#### Safe Signatures

```dart
// Encode a WebAuthn signature for Safe
final encoded = encodeSafeWebAuthnSignature(
  authenticatorData: '0x...',
  clientDataFields: '"challenge":"..."',
  r: BigInt.parse('...'),
  s: BigInt.parse('...'),
  validAfter: BigInt.zero,
  validUntil: BigInt.zero,
);

// Get dummy signature for gas estimation
final dummy = getDummySafeWebAuthnSignature();
```

## Platform Setup

WebAuthn requires platform-specific configuration. See the [example app README](example/README.md) for detailed setup instructions for:

- iOS (Associated Domains)
- Android (App Links)
- Web (HTTPS)
- macOS (Entitlements)

## P256 Precompile (RIP-7212)

For gas-efficient signature verification, use chains with the P256 precompile:

| Chain | Precompile Support |
|-------|-------------------|
| Ethereum Mainnet | ❌ |
| Sepolia | ✅ |
| Base | ✅ |
| Optimism | ✅ |
| Polygon | ✅ |
| Arbitrum | ✅ |

Without the precompile, signature verification falls back to Solidity-based P256, which uses more gas.

## Example

See the [example/](example/) directory for a complete Flutter app demonstrating:

- Passkey registration with biometrics
- Kernel and Safe account creation
- Transaction encoding
- Credential export/import

Run the example:

```bash
cd example
flutter pub get
flutter run
```

## Testing

Run the unit tests:

```bash
dart test
```

The package includes comprehensive tests for:
- Signature encoding (Kernel and Safe formats)
- Credential serialization
- Account configuration
- Address computation

## Architecture

```
lib/
├── permissionless_passkeys.dart   # Public exports
└── src/
    ├── accounts/
    │   ├── webauthn_account.dart         # WebAuthnAccount abstract class
    │   └── to_webauthn_account.dart      # toWebAuthnAccount factory
    ├── encoding/
    │   ├── kernel_encoding.dart          # Kernel signature ABI
    │   └── safe_encoding.dart            # Safe signature ABI
    ├── types/
    │   └── webauthn_credential.dart      # Credential wrapper
    └── factory.dart                      # Convenience factory functions
```

## Related

- [permissionless](../permissionless/) - Core ERC-4337 package
- [web3_signers](https://pub.dev/packages/web3_signers) - PassKeySigner implementation
- [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) - Account Abstraction
- [WebAuthn](https://www.w3.org/TR/webauthn-2/) - Web Authentication standard
- [RIP-7212](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md) - P256 Precompile

## License

MIT License - see [LICENSE](LICENSE) for details.

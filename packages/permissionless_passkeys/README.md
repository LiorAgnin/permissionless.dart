# permissionless_passkeys

WebAuthn/Passkeys support for [permissionless.dart](../permissionless/) ERC-4337 smart accounts.

Enable biometric authentication (Face ID, Touch ID, Windows Hello) for your smart accounts using P256 signatures.

## Features

- **WebAuthn Smart Accounts** - Create passkey-authenticated smart accounts
- **Kernel v0.3.x Support** - WebAuthn validator; uses the RIP-7212 P256 precompile where the chain has it
- **Safe v1.4.1/v1.5.0 Support** - Shared WebAuthn signer module
- **Cross-Platform** - Works on iOS, Android, Web, macOS
- **Biometric Authentication** - Face ID, Touch ID, Windows Hello, Security Keys

## Supported Account Types

| Account    | Version                     | EntryPoint | WebAuthn Signer           |
| ---------- | --------------------------- | ---------- | ------------------------- |
| **Kernel** | v0.3.0-beta, v0.3.1, v0.3.3 | v0.7       | WebAuthn validator module |
| **Safe**   | v1.4.1, v1.5.0              | v0.7       | Shared WebAuthn signer    |

Other Kernel versions (v0.2.x, and v0.3.2, which has no WebAuthn validator)
throw `ArgumentError` when created with a WebAuthn owner. So does Safe 1.4.1 on
EntryPoint v0.6, whose address table has no WebAuthn shared signer.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  permissionless_passkeys: ^0.2.0
  permissionless: ^0.6.0  # Required peer dependency
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
  publicClient: publicClient,  // Kernel resolves its address through RPC
);

// Or use with Safe v1.4.1/v1.5.0 (supports WebAuthn shared signer)
final safeAccount = createSafeSmartAccount(
  owners: [webAuthnAccount],  // WebAuthnAccount IS an AccountOwner
  chainId: BigInt.from(11155111),
  version: SafeVersion.v1_4_1,
);

final kernelAddress = await kernelAccount.getAddress();
print('Account Address: ${kernelAddress.hex}');
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
// - result.webauthn.challengeIndex: Offset of the "challenge" key in clientDataJSON
// - result.webauthn.typeIndex: Offset of the "type" key in clientDataJSON
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

### Signature Encoding

Kernel and Safe WebAuthn signature encoders live in core
`package:permissionless`, and the smart accounts call them for you. To encode
a signature yourself, pass the account's `P256SignatureData`:

```dart
final p256 = await account.signP256(userOpHash);

final kernelSignature = encodeKernelWebAuthnSignature(p256);
final safeSignature = encodeSafeWebAuthnSignature(p256);

// Dummy signatures for gas estimation
final kernelDummy = getDummyKernelWebAuthnSignature();
final safeDummy = getDummySafeWebAuthnSignature();
```

## Platform Setup

WebAuthn requires platform-specific configuration. See the [example app README](example/README.md) for detailed setup instructions for:

- iOS (Associated Domains)
- Android (App Links)
- Web (HTTPS)
- macOS (Entitlements)

## P256 Precompile (RIP-7212)

For gas-efficient signature verification, use chains with the P256 precompile. The library supports two detection methods:

- **Dynamic detection** (recommended): `isRip7212Supported(publicClient)` probes the precompile via `eth_call` with a known-valid P256 test vector. Works on any chain. An answer is cached per chain ID; a failed call returns `false` and is not cached, so the next call probes again.
- **Static detection**: `supportsRip7212(chainId:)` checks against a curated list of 67 known-supported chain IDs.

Kernel accounts automatically use dynamic detection when a `publicClient` is configured, falling back to the static list otherwise.

```dart
import 'package:permissionless/permissionless.dart';

// Dynamic: probe any chain via RPC
final supported = await isRip7212Supported(publicClient);

// Static: check against known chain IDs
final supported = supportsRip7212(chainId: chainId);
```

Without the precompile, signature verification falls back to a Solidity P256
verifier, which costs a few hundred thousand gas. The precompile call costs
3,450 gas (6,900 on Ethereum mainnet).

For Kernel, the gas estimate does not depend on the precompile. The Kernel
WebAuthn stub signature prices the Solidity verifier, so a chain with the
precompile gets the same estimate and a larger required prefund than the
operation uses. `SmartAccountClient` applies no WebAuthn-specific gas floor;
pass `verificationGasLimit` if you need a minimum.

## Example

See the [example/](example/) directory for a complete Flutter app demonstrating:

- Passkey registration with biometrics
- Kernel and Safe account creation
- Transaction encoding
- Sending a sponsored or self-funded UserOperation on Sepolia
- Credential export/import

Run the example:

```bash
cd example
flutter pub get
flutter run
```

## Testing

Run the unit tests (the package depends on Flutter):

```bash
flutter test
```

The package includes comprehensive tests for:
- Signing (raw hash, personal message, typed data)
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

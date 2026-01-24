# Permissionless Dart SDK

A Dart/Flutter SDK for building ERC-4337 (Account Abstraction) applications. This monorepo contains packages for smart account creation, user operation bundling, and WebAuthn/Passkey authentication.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [permissionless](packages/permissionless/) | Core ERC-4337 SDK for smart accounts and bundler interactions | [![pub](https://img.shields.io/pub/v/permissionless.svg)](https://pub.dev/packages/permissionless) |
| [permissionless_passkeys](packages/permissionless_passkeys/) | WebAuthn/Passkeys support for biometric smart account authentication | [![pub](https://img.shields.io/pub/v/permissionless_passkeys.svg)](https://pub.dev/packages/permissionless_passkeys) |

## Quick Start

### Installation

Add the packages you need to your `pubspec.yaml`:

```yaml
dependencies:
  # Core ERC-4337 functionality
  permissionless: ^0.1.2

  # Optional: WebAuthn/Passkeys support
  permissionless_passkeys: ^0.1.0
```

### Basic Usage

```dart
import 'package:permissionless/permissionless.dart';

// Create a bundler client
final bundlerClient = BundlerClient(
  chain: Chain.sepolia,
  bundlerUrl: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
);

// Create a simple smart account
final account = SimpleSmartAccount(
  SimpleSmartAccountConfig(
    owner: privateKeyToAccount(privateKey),
    chainId: Chain.sepolia.id,
    publicClient: publicClient,
  ),
);

// Send a user operation
final hash = await bundlerClient.sendUserOperation(
  account: account,
  calls: [
    Call(
      to: recipientAddress,
      value: BigInt.from(1000000000000000), // 0.001 ETH
    ),
  ],
);
```

### With Passkeys

```dart
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Register a passkey
final signer = PassKeySigner(options: PassKeysOptions(
  namespace: 'myapp.com',
  name: 'My App',
  sharedWebauthnSigner: SafeWebAuthnSigners.sharedSigner,
));
final passkey = await signer.register('user@example.com', 'User Name');
final credential = WebAuthnCredential.fromPassKeyPair(passkey);

// Create a WebAuthn-authenticated smart account
final account = WebAuthnSafeSmartAccount(
  WebAuthnSafeSmartAccountConfig(
    owner: WebAuthnOwner(credential: credential, rpId: 'myapp.com'),
    credential: credential,
    chainId: Chain.sepolia.id,
    publicClient: publicClient,
  ),
);
```

## Development

This project uses [Melos](https://melos.invertase.dev/) 6.x for monorepo management. I use Melos 6.x rather than 7.x due to [known conflicts](https://pub.dev/packages/multi_step_widgets/versions/0.3.0+1/changelog) between Melos 7's pub workspaces and path dependencies.

### Setup

```bash
# Install dependencies (Melos is a dev dependency)
dart pub get

# Bootstrap the workspace (links local packages via pubspec_overrides.yaml)
dart run melos bootstrap
```

### Common Commands

```bash
# Run tests across all packages
dart run melos test

# Run static analysis
dart run melos analyze

# Format code
dart run melos format

# Clean build artifacts
dart run melos clean
```

### Installing Melos Globally (Optional)

For convenience, you can install Melos globally:

```bash
dart pub global activate melos

# Then use without "dart run"
melos bootstrap
melos test
```

### Package Structure

```
permissionless-dart/
├── packages/
│   ├── permissionless/           # Core ERC-4337 package
│   │   ├── lib/
│   │   ├── test/
│   │   └── example/
│   └── permissionless_passkeys/  # WebAuthn extension
│       ├── lib/
│       ├── test/
│       └── example/
├── melos.yaml                    # Monorepo configuration
└── README.md
```

## Supported Account Types

### Core Package (`permissionless`)
- **SimpleSmartAccount** - Minimal ERC-4337 account
- **SafeSmartAccount** - Safe (Gnosis Safe) smart account
- **KernelSmartAccount** - ZeroDev Kernel smart account

### Passkeys Package (`permissionless_passkeys`)
- **WebAuthnSafeSmartAccount** - Safe with WebAuthn shared signer
- **WebAuthnKernelSmartAccount** - Kernel with WebAuthn validator (v0.3.x)

## Supported Chains

The SDK supports any EVM chain with ERC-4337 infrastructure:
- Ethereum Mainnet & Sepolia
- Polygon, Arbitrum, Optimism, Base
- And many more...

See the [permissionless package](packages/permissionless/) for the full chain list.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes using conventional commits
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

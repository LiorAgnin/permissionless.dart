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
  permissionless: ^0.4.0

  # Optional: WebAuthn/Passkeys support
  permissionless_passkeys: ^0.1.2
```

### Basic Usage

```dart
import 'package:permissionless/permissionless.dart';

// Create an owner and a smart account
final owner = PrivateKeyOwner('0x...');
final account = createSafeSmartAccount(
  owners: [owner],
  version: SafeVersion.v1_4_1,
  entryPointVersion: EntryPointVersion.v07,
  chainId: BigInt.from(11155111), // Sepolia
);

// Create clients
final publicClient = createPublicClient(url: 'https://rpc.example.com');
final bundler = createPimlicoClient(
  url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
  entryPoint: EntryPointAddresses.v07,
);

// Send a user operation
final client = SmartAccountClient(
  account: account,
  bundler: bundler,
  publicClient: publicClient,
);
final hash = await client.sendUserOperation(
  calls: [
    Call(
      to: recipientAddress,
      value: BigInt.from(1000000000000000), // 0.001 ETH
      data: '0x',
    ),
  ],
  maxFeePerGas: BigInt.from(20000000000),
  maxPriorityFeePerGas: BigInt.from(1000000000),
);
```

### With Passkeys

```dart
import 'package:permissionless/permissionless.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

// Register a passkey (triggers biometric prompt)
final credential = await createPasskeyCredential(
  rpId: 'myapp.com',
  rpName: 'My Application',
  userName: 'user@example.com',
);

// Create a WebAuthn account and use it as a smart account owner
final webAuthnAccount = createWebAuthnAccount(
  credential: credential,
  rpId: 'myapp.com',
);
final account = createKernelSmartAccount(
  owner: webAuthnAccount, // WebAuthnAccount IS an AccountOwner
  chainId: BigInt.from(11155111),
  version: KernelVersion.v0_3_1,
);
```

## Development

This project uses [Melos](https://melos.invertase.dev/) 7.x with Dart pub workspaces for monorepo management (the Melos configuration lives in the root `pubspec.yaml`).

### Setup

```bash
# Install dependencies (resolves the whole pub workspace; Melos is a dev dependency)
dart pub get
```

### Common Commands

```bash
# Run tests across all packages
dart run melos run test

# Run static analysis
dart run melos run analyze

# Format code
dart run melos run format

# Clean build artifacts
dart run melos run clean
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
├── pubspec.yaml                  # Pub workspace + Melos configuration
└── README.md
```

## Supported Account Types

### Core Package (`permissionless`)
- **Safe** (Gnosis) - battle-tested multi-sig account
- **Kernel** (ZeroDev) - modular account, ERC-7579 in v0.3.x
- **Nexus** (Biconomy) - ERC-7579 modular account
- **Light** (Alchemy) - gas-efficient single-owner account
- **Simple** (eth-infinitism) - minimal reference implementation
- **Thirdweb**, **Trust (Barz)**, **Etherspot**, **Biconomy (deprecated)**

### Passkeys Package (`permissionless_passkeys`)
- **WebAuthnAccount** - passkey credential as an `AccountOwner` for Kernel (WebAuthn validator) and Safe (shared WebAuthn signer) accounts

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

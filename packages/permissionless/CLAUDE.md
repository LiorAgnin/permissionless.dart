# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Dart implementation of [permissionless.js](https://github.com/pimlicolabs/permissionless.js) for ERC-4337 smart accounts. Supports 9 account types (Safe, Kernel, Nexus, Light, Simple, Thirdweb, Trust, Etherspot, Biconomy) with bundler and paymaster clients.

## Commands

```bash
dart pub get                              # Install dependencies
dart analyze                              # Static analysis
dart test                                 # Run all tests
dart test -P quick                        # Run without network/funded tests
dart test -t integration                  # Run integration tests only
dart test test/accounts/safe_test.dart    # Run specific test file
dart format .                             # Format code
dart doc                                  # Generate API docs
```

### Environment Variables (Integration Tests)
```bash
PIMLICO_API_KEY=your_key
TEST_PRIVATE_KEY=0x...
FUNDED_ACCOUNT_ADDRESS=0x...
```

## Code Style

- Follow official Dart style guide (enforced by `lints` package)
- Use `final` for variables that won't be reassigned
- Prefer `const` constructors where possible
- All public APIs must have dartdoc comments
- Use named parameters for functions with 3+ parameters
- Prefer extension methods for type utilities

## Architecture

### Directory Structure
```
lib/src/
├── accounts/              # Smart account implementations
│   ├── safe/              # Gnosis Safe (EP v0.6, v0.7)
│   ├── kernel/            # ZeroDev Kernel (v0.2.x, v0.3.x)
│   ├── nexus/             # Biconomy Nexus (ERC-7579)
│   ├── light/             # Alchemy Light Account
│   ├── simple/            # Minimal reference implementation
│   ├── thirdweb/          # Thirdweb SDK account
│   ├── trust/             # Trust Wallet Barz (diamond)
│   ├── etherspot/         # Etherspot modular
│   └── biconomy/          # Deprecated (use Nexus)
├── clients/               # RPC client abstractions
│   ├── bundler/           # ERC-4337 bundler client
│   ├── paymaster/         # Paymaster sponsorship
│   ├── public/            # Standard Ethereum RPC
│   ├── pimlico/           # Pimlico bundler extensions
│   ├── etherspot/         # Etherspot bundler extensions
│   └── smart_account/     # High-level account operations
├── actions/               # Account actions (ERC-7579, signing)
├── types/                 # Core types (UserOperation, Address, Hex)
├── utils/                 # Encoding, gas, ERC-20, MultiSend
├── constants/             # EntryPoint addresses
└── experimental/          # Unstable APIs (ERC-20 paymaster)
```

### Key Abstractions
- `SmartAccountInterface`: Base contract for all account implementations
- `AccountOwner`: Abstract owner class for signing (per-account variants like `PrivateKeyOwner`, `PrivateKeyKernelOwner`)
- `UserOperation` / `PackedUserOperation`: ERC-4337 operation structures (v0.6 vs v0.7)
- `EntryPointVersion`: Enum for v0.6 vs v0.7 support

### Account Implementation Pattern
Each account type follows this structure:
- `*_account.dart` - Main implementation with `SmartAccountInterface`
- `constants.dart` - Contract addresses per version/chain
- Barrel file (e.g., `safe.dart`) - Public exports

## Reference Implementation

The TypeScript reference is at: `../permissionless.js/packages/permissionless/`
- Safe account: `accounts/safe/toSafeSmartAccount.ts`
- Types: `types/`
- Utils: `utils/`

## Testing

- Tests live in `test/` mirroring `lib/src/` structure
- Use `group()` for organizing related tests
- Mock RPC calls using `MockClient` from test utilities
- Test vectors should match TypeScript implementation outputs

## ERC-4337 Specifics

### EntryPoint Versions
- v0.6: Older, widely deployed
- v0.7: Newer, gas optimizations, different signature format

### Safe Versions
- 1.4.1: Supports both EntryPoint v0.6 and v0.7
- 1.5.0: Only supports EntryPoint v0.7

### Critical Implementation Notes
- Safe signatures require V value adjustment (+31 for eth_sign)
- Multi-sig signatures must be sorted by signer address
- CREATE2 address calculation must match proxy factory exactly
- EIP-712 domain uses Safe module address, not Safe address

## Common Patterns

### BigInt Handling
```dart
// Use BigInt for all uint256 values
final value = BigInt.parse('1000000000000000000'); // 1 ETH in wei
```

### Hex String Convention
```dart
// All hex strings include '0x' prefix
final address = '0x1234...';
final data = '0xabcd...';
```

### Error Handling
- Throw `PermissionlessException` for library errors
- Throw `RpcException` for JSON-RPC errors
- Use `Result` pattern for operations that may fail gracefully

## Warnings

- Do NOT use `dart:mirrors` - breaks tree shaking
- BigInt arithmetic: watch for integer overflow in gas calculations
- Signature bytes must be exactly 65 bytes (r: 32, s: 32, v: 1)
- ABI encoding must be exactly compatible with Solidity ABI encoder

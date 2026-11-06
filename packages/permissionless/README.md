# permissionless.dart

A Dart implementation of [permissionless.js](https://github.com/pimlicolabs/permissionless.js) for ERC-4337 smart accounts.

Build account abstraction applications in Dart with support for multiple smart account implementations, bundler clients, and paymaster integration.

## Features

### Smart Accounts

| Account         | Provider       | EntryPoint       | ERC-7579   | Description                      |
| --------------- | -------------- | ---------------- | ---------- | -------------------------------- |
| **Safe**        | Gnosis         | v0.6, v0.7       | Optional*  | Battle-tested multi-sig account  |
| **Kernel**      | ZeroDev        | v0.6, v0.7       | v0.3.x     | Modular account with plugins     |
| **Nexus**       | Biconomy       | v0.7             | Yes        | ERC-7579 modular account         |
| **Light**       | Alchemy        | v0.6, v0.7       | No         | Gas-efficient single-owner       |
| **Simple**      | eth-infinitism | v0.6, v0.7, v0.8 | No         | Minimal reference implementation |
| **Thirdweb**    | Thirdweb       | v0.6, v0.7       | No         | SDK ecosystem integration        |
| **Trust**       | Trust Wallet   | v0.6             | No         | Diamond architecture (Barz)      |
| **Etherspot**   | Etherspot      | v0.7             | Internal** | ModularEtherspotWallet           |
| **Biconomy**    | Biconomy       | v0.6             | No         | *Deprecated - use Nexus*         |
| **Simple 7702** | eth-infinitism | v0.8             | No         | EOA delegated via EIP-7702***    |
| **Kernel 7702** | ZeroDev        | v0.7             | v0.3.3     | EOA delegated via EIP-7702***    |

\* Safe requires `erc7579LaunchpadAddress` configuration to enable ERC-7579 module management.
\** Etherspot uses ERC-7579 call encoding internally but module management actions are not exposed in permissionless.js.
\*** The EOA itself is the account: `createEip7702SimpleSmartAccount` / `createEip7702KernelSmartAccount`. The first UserOperation carries the EIP-7702 authorization; send it with `sendPreparedUserOperation(..., authorization:)` (see `example/eip7702_*_example.dart`).

### Clients

- **BundlerClient** - ERC-4337 bundler RPC methods
- **PaymasterClient** - Paymaster sponsorship integration
- **SmartAccountClient** - High-level account operations
- **PimlicoClient** - Pimlico-specific bundler extensions
- **EtherspotClient** - Etherspot (Skandha) bundler extensions
- **PasskeyServerClient** - Passkey server `pks_*` RPC methods
- **PublicClient** - Standard Ethereum RPC (incl. deployless `eth_call` for counterfactual accounts)

### Utilities

- Gas estimation and cost calculation
- ERC-7579 call encoding and module management
- ERC-20 state overrides for gas estimation
- ABI encoding utilities
- MultiSend batch transactions
- Message signing (EIP-191, EIP-712)
- PackedUserOperation utilities

### Experimental

- **ERC-20 Paymaster Preparation** - Pay gas fees with ERC-20 tokens

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  permissionless: ^0.6.0
```

Then run:

```bash
dart pub get
```

### Upgrading from 0.5.x

Nothing exported was removed or renamed in 0.6.0, but some behaviour changed:

- **Counterfactual addresses** change for a Safe in ERC-7579 mode with a
  WebAuthn owner, and for a Safe v1.5.0 built without a `publicClient`. Both
  old addresses were wrong.
- **EntryPoint v0.6 with a paymaster** now uses ERC-7677
  (`pm_getPaymasterStubData` / `pm_getPaymasterData`) instead of
  `pm_sponsorUserOperation`.
- **WebAuthn accounts** no longer get a 900,000 verification-gas floor. Pass
  `verificationGasLimit` or custom `gasMultipliers` if you need a minimum.
- **Invalid account configs** throw `ArgumentError` when you create the
  account, and the top-level ERC-7579 queries and ERC-20 reads throw
  `StateError` when the call returns `0x` (for example, an undeployed account).

The [CHANGELOG](CHANGELOG.md) lists every change and the deprecated methods to
move off.

### Upgrading from 0.3.x

Version 0.4.0 fixes every P0/P1 divergence found by the
[Dart-vs-JS parity audit](https://github.com/LiorAgnin/permissionless.dart/tree/main/docs/parity-audit).
Two changes affect **counterfactual addresses**:

- **Safe default threshold** is now `owners.length` (was `1`). Multi-owner Safes
  created without an explicit `threshold` derive a different address. Pass
  `threshold: BigInt.one` to keep the previous 1-of-n default and address.
- **Thirdweb salts** are now UTF-8-encoded like permissionless.js (was
  hex-decoded), so non-default salts derive different (now JS-compatible)
  addresses.

ERC-1271 `signMessage`/`signTypedData` outputs also changed across accounts —
previous releases produced signatures that failed on-chain `isValidSignature`;
they now byte-match permissionless.js. See the
[CHANGELOG](CHANGELOG.md) for the full list.

## Quick Start

```dart
import 'package:permissionless/permissionless.dart';

void main() async {
  // 1. Create an owner from a private key (your own key; never a published
  //    test key such as Hardhat/Anvil account 0 on a live network)
  final owner = PrivateKeyOwner('0x<your-private-key>');

  // 2. Create a Safe smart account
  final account = createSafeSmartAccount(
    owners: [owner],
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    chainId: BigInt.from(11155111), // Sepolia
  );

  // 3. Get the account address (deterministic, works before deployment)
  final address = await account.getAddress();
  print('Smart Account Address: ${address.checksummed}');

  // 4. Create clients
  final publicClient = createPublicClient(
    url: 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY',
  );

  final pimlico = createPimlicoClient(
    url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
    entryPoint: EntryPointAddresses.v07,
  );

  final paymaster = createPaymasterClient(
    url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
  );

  // 5. Create a smart account client
  final client = SmartAccountClient(
    account: account,
    bundler: pimlico,
    publicClient: publicClient,
    paymaster: paymaster, // optional
  );

  // 6. Send a sponsored transaction
  final hash = await client.sendUserOperation(
    calls: [
      Call(
        to: EthereumAddress.fromHex('0x...'),
        value: BigInt.zero,
        data: '0x',
      ),
    ],
    maxFeePerGas: BigInt.from(20000000000),
    maxPriorityFeePerGas: BigInt.from(1000000000),
  );

  print('UserOperation hash: $hash');
}
```

## Smart Accounts

### Safe Account

The most battle-tested smart account, based on Gnosis Safe:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createSafeSmartAccount(
  owners: [owner],
  version: SafeVersion.v1_4_1,  // or v1_5_0
  entryPointVersion: EntryPointVersion.v07,
  chainId: BigInt.from(1),
  saltNonce: BigInt.zero,
);
```

**Features:**
- Multi-signature support with configurable threshold
- EIP-712 SafeOp typed data signing
- Safe v1.4.1 (EP v0.6, v0.7) and v1.5.0 (EP v0.7)

### Kernel Account

ZeroDev's modular smart account with plugin support:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createKernelSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  version: KernelVersion.v0_3_1,  // ERC-7579, EP v0.7
  index: BigInt.zero,
);
```

**Features:**
- v0.2.x (v0.2.1-v0.2.4): EntryPoint v0.6, custom execute
- v0.3.x (v0.3.0-beta, v0.3.1, v0.3.2, v0.3.3): EntryPoint v0.7, ERC-7579 compliant, external ECDSA validator

### Nexus Account (Biconomy)

Biconomy's next-generation ERC-7579 modular account:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createNexusSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  index: BigInt.zero,
);
```

**Features:**
- ERC-7579 modular architecture
- K1 validator for ECDSA signatures
- Replaces deprecated Biconomy Smart Account

### Light Account (Alchemy)

Alchemy's gas-efficient smart account:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createLightSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  version: LightAccountVersion.v200,  // EP v0.7, the default
  // For v1.1.0, also pass entryPointVersion: EntryPointVersion.v06.
  // Other version/EntryPoint pairs throw ArgumentError.
);
```

**Features:**
- Low gas overhead
- v1.1.0: EntryPoint v0.6
- v2.0.0: EntryPoint v0.7, signature type prefix

### Simple Account

Minimal reference implementation from eth-infinitism:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createSimpleSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  entryPointVersion: EntryPointVersion.v07,
);
```

**Features:**
- Minimal, gas-efficient design
- Direct signature validation
- Ideal for learning ERC-4337

### Thirdweb Account

Thirdweb SDK smart account:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createThirdwebSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  entryPointVersion: EntryPointVersion.v07,
);
```

**Features:**
- Both EntryPoint v0.6 and v0.7 support
- Thirdweb SDK ecosystem integration

### Trust Account (Barz)

Trust Wallet's diamond-based smart account:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createTrustSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  index: BigInt.zero,
);
```

**Features:**
- Diamond proxy pattern (EIP-2535)
- EntryPoint v0.6 only

### Etherspot Account

Etherspot's ModularEtherspotWallet:

```dart
final owner = PrivateKeyOwner('0x...');
final account = createEtherspotSmartAccount(
  owner: owner,
  chainId: BigInt.from(1),
  index: BigInt.zero,
);
```

**Features:**
- ERC-7579 modular architecture
- Multiple validator module support

## Clients

### BundlerClient

Interact with ERC-4337 bundlers:

```dart
final bundler = createBundlerClient(
  url: 'https://...',
  entryPoint: EntryPointAddresses.v07,
);

// Get supported entry points
final entryPoints = await bundler.supportedEntryPoints();

// Estimate gas for a UserOperation
final gasEstimate = await bundler.estimateUserOperationGas(userOp);

// Send a UserOperation
final hash = await bundler.sendUserOperation(userOp);

// Get UserOperation receipt (null while pending)
final maybeReceipt = await bundler.getUserOperationReceipt(hash);

// Wait for receipt with polling
final receipt = await bundler.waitForUserOperationReceipt(hash);
```

### PaymasterClient

Integrate with paymasters for sponsored transactions:

```dart
final paymaster = createPaymasterClient(
  url: 'https://...',
);

// Get stub data for gas estimation
final stubData = await paymaster.getPaymasterStubData(
  userOp: userOp,
  entryPoint: EntryPointAddresses.v07,
  chainId: BigInt.from(1),
);

// Get final paymaster data
final paymasterData = await paymaster.getPaymasterData(
  userOp: userOp,
  entryPoint: EntryPointAddresses.v07,
  chainId: BigInt.from(1),
);
```

### SmartAccountClient

High-level operations combining account, bundler, and paymaster:

```dart
final client = SmartAccountClient(
  account: account,
  bundler: bundler,
  publicClient: publicClient,
  paymaster: paymaster,  // Optional
);

// Get account address
final address = await client.account.getAddress();

// Prepare a UserOperation
final preparedOp = await client.prepareUserOperation(
  calls: [call1, call2],
  maxFeePerGas: BigInt.from(20000000000),
  maxPriorityFeePerGas: BigInt.from(1000000000),
);

// Sign a UserOperation
final signedOp = await client.signUserOperation(preparedOp);

// Send a prepared UserOperation
final preparedHash = await client.sendPreparedUserOperation(signedOp);

// Send in one call (prepare + sign + send)
final hash = await client.sendUserOperation(
  calls: [call],
  maxFeePerGas: BigInt.from(20000000000),
  maxPriorityFeePerGas: BigInt.from(1000000000),
);

// Wait for receipt
final receipt = await client.waitForReceipt(hash);
```

### PimlicoClient

Pimlico-specific bundler extensions:

```dart
final pimlico = createPimlicoClient(
  url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=...',
  entryPoint: EntryPointAddresses.v07,
);

// Get gas prices (slow, standard, fast)
final gasPrices = await pimlico.getUserOperationGasPrice();
print('Fast: ${gasPrices.fast.maxFeePerGas}');

// Get detailed operation status
final status = await pimlico.getUserOperationStatus(hash);

// Get supported ERC-20 tokens for gas payment
final tokens = await pimlico.getSupportedTokens();

// Get token quotes for ERC-20 paymaster
final quotes = await pimlico.getTokenQuotes([usdcAddress]);
```

### PublicClient

Standard Ethereum JSON-RPC:

```dart
final publicClient = createPublicClient(
  url: 'https://...',
);

// Check if account is deployed
final isDeployed = await publicClient.isDeployed(address);

// Get chain ID
final chainId = await publicClient.getChainId();

// Get account nonce (from EntryPoint)
final nonce = await publicClient.getAccountNonce(
  address,
  EntryPointAddresses.v07,
);

// Make a contract call
final result = await publicClient.call(
  Call(to: contractAddress, data: callData),
);

// Deployless call against an undeployed (counterfactual) account. It
// deploys via the factory inside eth_call, then executes the call.
final accountResult = await publicClient.call(
  Call(to: accountAddress, data: callData),
  factory: factoryAddress,
  factoryData: factoryData,
);
```

### PasskeyServerClient

Talk to a passkey server (e.g. Pimlico's) via the `pks_*` RPC methods:

```dart
final passkeyServer = createPasskeyServerClient(
  url: 'https://passkeys.example.com',
);

// Registration ceremony
final options = await passkeyServer.startRegistration(
  context: {'userName': 'alice@example.com'},
);
// ... create the credential via platform WebAuthn (see permissionless_passkeys) ...
final verified = await passkeyServer.verifyRegistration(
  credential: registrationCredential,
  context: {'userName': 'alice@example.com'},
);

// Authentication ceremony
final authOptions = await passkeyServer.startAuthentication();
final authResult = await passkeyServer.verifyAuthentication(
  credential: authenticationCredential,
  uuid: credentialUuid,
);

// List credentials
final credentials = await passkeyServer.getCredentials(
  context: {'userName': 'alice@example.com'},
);
```

## ERC-7579 Actions

For ERC-7579 compliant accounts (Kernel v0.3.x, Safe 7579, Nexus):

```dart
// Install a module
final installCallData = encode7579InstallModule(
  moduleType: Erc7579ModuleType.validator,
  module: moduleAddress,
  initData: '0x',
);

// Uninstall a module
final uninstallCallData = encode7579UninstallModule(
  moduleType: Erc7579ModuleType.executor,
  module: moduleAddress,
  deInitData: '0x',
);

// Check if module is installed. The SmartAccountClient method also works
// before the account is deployed (it retries through the factory); the
// top-level isModuleInstalled throws StateError for an undeployed account.
final isInstalled = await smartAccountClient.isModuleInstalled(
  type: Erc7579ModuleType.validator,
  address: moduleAddress,
);
```

## Smart Account Actions

Sign messages and typed data:

```dart
// Sign a personal message (EIP-191)
final signature = await account.signMessage('Hello World');

// Sign typed data (EIP-712)
final typedData = TypedData(
  domain: TypedDataDomain(
    name: 'MyApp',
    version: '1',
    chainId: BigInt.from(1),
    verifyingContract: contractAddress,
  ),
  types: {
    'Message': [
      TypedDataField(name: 'content', type: 'string'),
    ],
  },
  primaryType: 'Message',
  message: {'content': 'Hello'},
);
final typedSignature = await account.signTypedData(typedData);
```

## Gas Utilities

```dart
// Total gas limit of a UserOperationGasEstimate (includes paymaster gas)
final totalGas = estimates.totalGasLimit;

// Get required prefund
final prefund = getRequiredPrefund(userOp);
```

## ERC-20 Paymaster (Experimental)

Pay gas fees with ERC-20 tokens instead of ETH:

```dart
import 'package:permissionless/permissionless.dart';

// Prepare a UserOperation with ERC-20 gas payment
final result = await prepareUserOperationForErc20Paymaster(
  smartAccountClient: client,
  pimlicoClient: pimlico,
  publicClient: public,
  token: usdcAddress,
  calls: [transferCall],
  maxFeePerGas: gasPrices.fast.maxFeePerGas,
  maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
);

print('Max cost: ${result.maxCostInToken} tokens');
print('Approval injected: ${result.approvalInjected}');

// Sign and send. For an EIP-7702 account whose delegation is not yet
// active, result.authorization is non-null and this same operation installs
// the delegation. Otherwise it is null, so one code path covers both cases.
final signedOp = await client.signUserOperation(result.userOperation);
final hash = await client.sendPreparedUserOperation(
  signedOp,
  authorization: result.authorization,
);
```

See `example/erc20_paymaster_example.dart` for a complete gasless ERC-20
transfer (the sender needs no ETH at all).

## ERC-20 State Overrides

Simulate token balances during gas estimation:

```dart
// Create balance override for gas estimation
final stateOverride = erc20BalanceOverride(
  token: usdcAddress,
  owner: accountAddress,
  slot: BigInt.zero,  // Balance storage slot
);

// Create allowance override
final allowanceOverride = erc20AllowanceOverride(
  token: usdcAddress,
  owner: accountAddress,
  spender: paymasterAddress,
  slot: BigInt.one,  // Allowance storage slot
);
```

## EntryPoint Versions

| Version | Address         | Accounts                                                                                         |
| ------- | --------------- | ------------------------------------------------------------------------------------------------ |
| v0.6    | `0x5FF1...2789` | Safe v1.4.1, Kernel v0.2.x, Light v1.1.0, Simple, Thirdweb, Trust, Biconomy                      |
| v0.7    | `0x0000...a032` | Safe v1.4.1/v1.5.0, Kernel v0.3.x, Kernel 7702, Nexus, Light v2.0.0, Simple, Thirdweb, Etherspot |
| v0.8    | `0x4337...f108` | Simple, Simple 7702                                                                              |

The full addresses are `EntryPointAddresses.v06`, `.v07` and `.v08`.

## Examples

See the [example/](example/) directory for complete working examples:

| Example                         | Description                                    |
| ------------------------------- | ---------------------------------------------- |
| `safe_example.dart`             | Safe v1.4.1 multi-sig account                  |
| `safe_7579_example.dart`        | Safe with ERC-7579 modules                     |
| `safe_webauthn_example.dart`    | Safe with a WebAuthn owner (prepare only)      |
| `kernel_example.dart`           | Kernel v0.3.1                                  |
| `kernel_webauthn_example.dart`  | Kernel with a WebAuthn owner (prepare only)    |
| `nexus_example.dart`            | Biconomy Nexus (ERC-7579)                      |
| `light_example.dart`            | Alchemy Light Account                          |
| `simple_example.dart`           | Minimal reference account                      |
| `thirdweb_example.dart`         | Thirdweb SDK account                           |
| `trust_example.dart`            | Trust Wallet Barz                              |
| `etherspot_example.dart`        | Etherspot modular account                      |
| `biconomy_example.dart`         | Legacy Biconomy account                        |
| `eip7702_simple_example.dart`   | EIP-7702 Simple account                        |
| `eip7702_kernel_example.dart`   | EIP-7702 Kernel account                        |
| `erc20_paymaster_example.dart`  | Pay gas with ERC-20 tokens                     |

Safe, Kernel, Light, Simple and Thirdweb also have one file per version
(for example `kernel_v024_example.dart`, `simple_ep08_example.dart`) and an
`*_all_versions_example.dart` that runs every version.

Most examples send real UserOperations on a testnet. The two WebAuthn
examples stop before signing, since that needs a real authenticator (see
`permissionless_passkeys`). All of them read
`PIMLICO_API_KEY` and `TEST_PRIVATE_KEY` from the environment or from a
`.env` file in this package or the repo root. Both are required; there is no
built-in key. Use a throwaway key funded on Sepolia, never a well-known one
such as Hardhat/Anvil account 0. Run one:

```bash
dart run example/safe_example.dart
```

## API Reference

Generate API documentation:

```bash
dart doc
```

Then open `doc/api/index.html` in your browser.

## Testing

Run the tests that need no network:

```bash
dart test -P quick
```

Run all tests, including the `integration` and `funded` ones that call live
bundlers:

```bash
dart test
```

Run specific tests:

```bash
dart test test/accounts/safe/safe_account_test.dart
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `dart test`
5. Run static analysis: `dart analyze`
6. Submit a pull request

## Related Projects

- [permissionless.js](https://github.com/pimlicolabs/permissionless.js) - TypeScript implementation
- [Pimlico](https://pimlico.io/) - ERC-4337 infrastructure
- [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) - Account Abstraction specification
- [ERC-7579](https://eips.ethereum.org/EIPS/eip-7579) - Modular Smart Account specification

## License

MIT License - see [LICENSE](LICENSE) for details.

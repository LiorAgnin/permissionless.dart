# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2025-12-29

### Fixed
- **WebAuthn/Passkeys**: Fixed Safe account `isWebAuthn` detection
  - `SafeSmartAccount.isWebAuthn` now correctly returns `true` when WebAuthn owners are configured
  - This enables proper gas estimation with 900k minimum verification gas for P256 on-chain verification
  - Previously always returned `false`, causing AA26 (over verificationGasLimit) errors
- **WebAuthn/Passkeys**: Fixed paymaster gas limit handling for WebAuthn accounts
  - Smart fallback logic for paymaster verification and post-op gas limits
  - Uses stub values when valid, falls back to bundler estimates when needed
  - Fixes AA33 (paymaster reverted) errors for Kernel WebAuthn accounts
- **Nonce**: Fixed `nonceKey` not passed to `getAccountNonce()` in `SmartAccountClient`
  - Kernel v0.3.x accounts now correctly fetch nonces using their validator-encoded nonce key
  - Safe accounts unaffected (use default key 0)

### Added
- **Examples**: Added WebAuthn examples for Safe and Kernel accounts
  - `example/safe_webauthn_example.dart` - Safe with passkey owner
  - `example/kernel_webauthn_example.dart` - Kernel v0.3.1 with WebAuthn validator

## [0.1.2] - 2025-12-18

### Changed
- **Documentation**: Achieved 100% dartdoc coverage (1192/1192 API elements)
  - Added documentation to all `fromJson` factory constructors
  - Documented all UserOperation fields for both v0.6 and v0.7
  - Added dartdoc comments to Safe, Kernel, Pimlico, and Paymaster types
  - Documented all public class constructors and their parameters
  - Added field-level documentation for gas limits, fees, and paymaster data

## [0.1.1] - 2025-12-18

### Changed
- **BREAKING**: Replaced custom `EthAddress` class with `EthereumAddress` from the `wallet` package
  - `EthAddress('0x...')` → `EthereumAddress.fromHex('0x...')`
  - `EthAddress.zero` → `zeroAddress` (top-level constant)
  - Added `EthereumAddressExtension` with `.hex`, `.checksummed`, `.bytes`, `.isZero`, `.toAbiEncoded()` methods
  - Added `StringToAddress` extension: `'0x...'.toAddress()`
- **BREAKING**: Removed `includeFactoryData` parameter from `SmartAccountClient` methods
  - `prepareUserOperation`, `prepareUserOperationWithAuth`, `sendUserOperation`, `sendUserOperationAndWait`
  - `prepareUserOperationV06`, `sendUserOperationV06`, `sendUserOperationV06AndWait`
  - The SDK now automatically detects deployment status via `publicClient.isDeployed()` and includes factory data only when needed
  - **Important**: `publicClient` parameter is now required in `SmartAccountClient` constructor for auto-detection to work
  - This simplifies the API - users no longer need to track deployment status themselves
- Added `wallet` package as direct dependency for `EthereumAddress` type

### Fixed
- Improved interoperability with web3dart ecosystem by using standard types
- Fixed inconsistency between v0.6 and v0.7 UserOperation preparation
  - v0.6 now properly checks deployment status before including `initCode`, matching v0.7 behavior

## [0.1.0] - 2025-12-15

Initial release of permissionless.dart - a Dart implementation of permissionless.js for ERC-4337 smart accounts.

### Added

#### Smart Accounts
- **SafeSmartAccount** - Gnosis Safe with 4337 module support
  - Safe v1.4.1 (EntryPoint v0.6 and v0.7)
  - Safe v1.5.0 (EntryPoint v0.7)
  - Multi-signature support with threshold
  - EIP-712 typed data signing
- **SimpleSmartAccount** - Minimal single-owner account
  - EntryPoint v0.6 and v0.7 support
- **Eip7702SimpleSmartAccount** - EIP-7702 delegated Simple account
  - EOA code delegation support
  - EntryPoint v0.7
- **KernelSmartAccount** - ZeroDev's modular account
  - Kernel v0.2.4 (EntryPoint v0.6)
  - Kernel v0.3.1 (EntryPoint v0.7, ERC-7579 compliant)
- **Eip7702KernelSmartAccount** - EIP-7702 delegated Kernel account
  - EOA code delegation with modular architecture
  - EntryPoint v0.7
- **EtherspotSmartAccount** - ModularEtherspotWallet (EntryPoint v0.7)
  - ERC-7579 modular architecture
- **NexusSmartAccount** - Biconomy's ERC-7579 modular account (EntryPoint v0.7)
  - K1 validator for ECDSA signatures
- **LightSmartAccount** - Alchemy's gas-efficient account
  - Version 1.1.0 (EntryPoint v0.6)
  - Version 2.0.0 (EntryPoint v0.7, signature type prefix)
- **ThirdwebSmartAccount** - Thirdweb SDK smart account
  - EntryPoint v0.6 and v0.7 support
- **TrustSmartAccount** - Trust Wallet's Barz account
  - Diamond proxy pattern (EIP-2535)
  - EntryPoint v0.6 only
- **BiconomySmartAccount** (deprecated) - Use NexusSmartAccount instead

#### Clients
- **BundlerClient** - ERC-4337 bundler RPC methods
  - `eth_sendUserOperation`
  - `eth_estimateUserOperationGas`
  - `eth_getUserOperationReceipt`
  - `eth_getUserOperationByHash`
  - `eth_supportedEntryPoints`
  - `waitForUserOperationReceipt` - Polling with configurable timeout
- **PaymasterClient** - Paymaster integration
  - `pm_getPaymasterStubData`
  - `pm_getPaymasterData`
  - `pm_validateSponsorshipPolicies`
- **SmartAccountClient** - High-level account operations
  - `prepareUserOperation`
  - `signUserOperation`
  - `sendUserOperation`
  - `sendPreparedUserOperation`
  - `waitForReceipt`
- **PimlicoClient** - Pimlico bundler extensions
  - `pimlico_getUserOperationGasPrice`
  - `pimlico_getUserOperationStatus`
  - `pimlico_sendCompressedUserOperation`
  - `getSupportedTokens` - Get supported ERC-20 tokens for gas payment
  - `getTokenQuotes` - Get exchange rates and paymaster info for tokens
- **EtherspotClient** - Etherspot (Skandha) bundler extensions
  - `skandha_getGasPrice`
- **PublicClient** - Standard Ethereum JSON-RPC
  - `eth_chainId`
  - `eth_getCode` / `isDeployed`
  - `eth_call`
  - `eth_getTransactionReceipt`
  - `getSenderAddress`
  - `getAccountNonce`

#### Smart Account Actions
- `signMessage` - EIP-191 personal message signing for all accounts
- `signTypedData` - EIP-712 typed data signing for all accounts

#### ERC-7579 Actions
- `installModule` - Install a single module on the smart account
- `installModules` - Batch install multiple modules in one UserOperation
- `uninstallModule` - Remove a module from the smart account
- `isModuleInstalled` - Check if a module is installed on an account
- `supportsModule` - Check if an account supports a module type

#### ERC-20 Paymaster Support (Experimental)
- `prepareUserOperationForErc20Paymaster` - Prepare UserOperations for ERC-20 gas payment
  - Automatic token approval injection
  - USDT special case handling (approval reset)
  - Max cost calculation in tokens
- `estimateErc20PaymasterCost` - Estimate gas cost in ERC-20 tokens

#### Constants
- `EntryPointAddresses` - Canonical EntryPoint contract addresses
  - v0.6, v0.7, and v0.8 support
- `EntryPointVersion` - Enum for version selection

#### Types
- `UserOperationV06` - EntryPoint v0.6 UserOperation
- `UserOperationV07` - EntryPoint v0.7 UserOperation
- `EthereumAddress` - Ethereum address type (from wallet package) with extensions
- `Call` - Transaction call representation
- `TypedData` / `TypedDataDomain` / `TypedDataField` - EIP-712 typed data
- `CallsStatus` / `CallReceipt` - ERC-5792 response types
- `PackedUserOperation` - Packed UserOperation format utilities
- `Eip7702Authorization` - EIP-7702 EOA code delegation authorization
- `AccountOwner` / `PrivateKeyOwner` - Unified owner interface for all signing modes

#### Utilities
- **Gas Estimation**
  - `totalGasLimit` calculation
  - `getRequiredPrefund` for account funding
  - Gas multipliers for estimation buffers
- **ERC-7579** - Modular account call encoding
  - `encode7579Execute` for single calls
  - `encode7579ExecuteBatch` for batch calls
  - `encodeInstallModule` / `encodeUninstallModule`
  - `decode7579Calls`
- **ABI Encoding** - Solidity ABI encoding utilities
  - `AbiEncoder.encodeAddress`
  - `AbiEncoder.encodeUint256`
  - `AbiEncoder.encodeBytes`
- **MultiSend** - Safe batch transaction encoding
  - `encodeMultiSend`
  - `encodeMultiSendCall`
- **Message Hashing**
  - `hashMessage` - EIP-191 personal message hash
  - `hashTypedData` - EIP-712 typed data hash
- **PackedUserOperation Utilities**
  - `packUserOperation` / `unpackUserOperation`
  - `toPackedUserOperation` / `fromPackedUserOperation`
- **ERC-20 Utilities**
  - `encodeApprove` / `encodeTransfer` - Token operation encoding
  - `Erc20Selectors` - Function selector constants
  - `erc20BalanceOverride` - Simulate token balances
  - `erc20AllowanceOverride` - Simulate token allowances
  - `mergeStateOverrides` - Combine multiple state overrides
- **Units** - Wei/Gwei/Ether conversions
  - `parseEther` / `formatEther`
  - `parseGwei` / `formatGwei`
  - `parseUnits` / `formatUnits`
- **Hex Utilities**
  - `Hex.concat` / `Hex.slice`
  - `Hex.fromBigInt` / `Hex.toBigInt`
  - `Hex.fromBytes` / `Hex.decode`
- **Nonce Utilities**
  - `encodeNonce` / `decodeNonce` - 2D nonce encoding

#### Examples
- `simple_example.dart` - Simple account usage
- `safe_example.dart` - Safe account with multi-sig
- `safe_7579_example.dart` - Safe with ERC-7579 modules
- `kernel_example.dart` - Kernel v0.3.1 (ERC-7579)
- `kernel_v024_example.dart` - Kernel v0.2.4 (EntryPoint v0.6)
- `etherspot_example.dart` - Etherspot modular account
- `light_example.dart` - Light account with version comparison
- `nexus_example.dart` - Nexus (Biconomy) account
- `biconomy_example.dart` - Legacy Biconomy account
- `thirdweb_example.dart` - Thirdweb account
- `trust_example.dart` - Trust Wallet Barz account
- `eip7702_simple_example.dart` - EIP-7702 Simple account delegation
- `eip7702_kernel_example.dart` - EIP-7702 Kernel account delegation
- `erc20_paymaster_example.dart` - ERC-20 gas payment
- `erc7579_modules_example.dart` - Module installation and management

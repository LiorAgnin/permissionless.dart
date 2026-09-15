# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Kernel v4.0 + EntryPoint v0.9 feature release. Kernel v4 has no
permissionless.js counterpart; correctness is anchored to the Kernel v4.0
contracts (release v0.4.0) and viem EntryPoint v0.9 packing/hash via committed
Foundry-generated vectors (`tool/kernel_v4_vectors/`,
`tool/entry_point_v09_vectors/`). See
[ADR 0002](../../docs/adr/0002-kernel-v4-parity-baseline.md).

**Verified chains:** no public Kernel v4.0 / EntryPoint v0.9 deployments are
confirmed yet. Address cross-checks and funded e2e tests skip cleanly when
`KERNEL_V4_RPC_URL` / bundler / module env vars are unset; the intended path
is a local anvil where the release recipe has been run. Re-verify against a
public stack when one lands.

### Added

- **EntryPoint v0.9 as a first-class version.** `EntryPointVersion.v09` and
  `EntryPointAddresses.v09`
  (`0x433709009B8330FDa32311DF1C2AFA402eD8D009`). The UserOperation wire format
  is unchanged from v0.8, so `UserOperationV07` is reused rather than
  introducing a third UserOperation class.
- **Shared `getUserOperationHash` and `getUserOperationTypedData`** covering
  EntryPoint v0.6 through v0.9, including the EIP-7702 initCode hash override.
  Every account now delegates to these instead of carrying its own copy of the
  packing rules.
- **Paymaster signatures (EntryPoint v0.9).**
  `UserOperationV07.paymasterSignature` is packed as
  `signature ‖ uint16(length) ‖ 0x22e325a297439656` on the wire and excluded
  from the userOpHash, which is what lets the user and the paymaster sign in
  parallel. Helpers: `encodePaymasterSignatureSuffix`,
  `getPaymasterSignatureLength`, `getPaymasterSignature`,
  `getSignedPaymasterData`, `getHashedPaymasterAndData`,
  `splicePaymasterSignature`, and the `paymasterSignatureStub` placeholder for
  signing before the paymaster responds. See
  [ADR 0001](../../docs/adr/0001-entrypoint-v09-paymaster-signature-framing.md).
- `unpackPaymasterAndData` now reports a `paymasterSignature` separately from
  `paymasterData`.

- **`KernelVersion.v0_4_0`**, with `isV4` / `entryPointVersion` accessors. The
  v2/v3 Kernel factories reject it with a pointer to the v4 API.
- **Kernel v4.0 ImmutableECDSA accounts** (`createKernelImmutableECDSA`) —
  immutable fallback ECDSA signer in the proxy args; root UserOperations carry
  the raw 65-byte signature over the v0.9 userOpHash with routing in the nonce.
  Offline counterfactual addresses, `deployECDSA` factory data (Staker-wrapped
  by default, `useStaker: false` for direct factory calls), ERC-7579
  single/batch encoding, prepare/sign/send via the smart-account client.
- **Kernel v4.0 UUPS accounts** (`createKernelUUPS`) — upgradeable proxy with
  an initial root validator package; `deploy` / `getAddress` parity with the
  factory.
- **Kernel7702** (`createKernel7702`) — EIP-7702 delegation to the Kernel7702
  implementation on EntryPoint v0.9; EOA is the fallback signer; supports raw
  ERC-1271 where the contracts allow.
- **Nonce-encoded validation** — root / validator / permission vTypes;
  standard, enable, replayable (and enable-replayable) modes; 2-byte parallel
  nonce keys within the Kernel v4 layout.
- **Enable-mode UserOperations** — install modules atomically with the first
  validation (`KernelV4EnableMode` + EIP-712 InstallPackages digest).
- **Module management** — typed `KernelV4Install` packages (validator,
  executor, fallback, hook, policy, signer), install/uninstall/batch
  encoders, and smart-account-client actions (`installKernelV4Module(s)`,
  `uninstallKernelV4Module`, `uninstallKernelV4Permission`, `setKernelV4Root`,
  `grantKernelV4Access`).
- **Permissions / session keys** — compose policies + one signer under a
  `PermissionId`; permission-mode UserOp signatures
  (`abi.encode(bytes[])` of policy chunks then signer).
- **ERC-1271 / ERC-7739 signing** for Kernel v4 — nested EIP-712 PersonalSign
  and typed-data wrapping (chain-specific and replayable); Kernel7702 raw
  path.
- **Kernel v4 helpers** under `utils/kernel_v4/`: `KernelV4Addresses` (release
  v0.4.0 CREATE2 predictions), salt/address computation, install encoding,
  nonce packing, enable-mode digests, ERC-7739 wrappers.
- **Docs:** ADR 0001 (paymaster-signature framing), ADR 0002 (parity baseline),
  glossary terms, README account matrix for Kernel v4 / EntryPoint v0.9.
- **Integration and funded e2e** for address prediction, enable-mode estimation,
  Kernel7702 ERC-1271 against delegated code, and funded deploy/enable/
  permission/Kernel7702 paths that skip cleanly when the stack is missing.

### Changed

- `getPackedUserOperation` accepts an optional `delegationAddress` for EIP-7702
  operations.
- Accounts that do not support EntryPoint v0.9 now say so explicitly:
  `LightAccountVersion.forEntryPoint` and
  `SimpleAccountFactoryAddresses.fromVersion` throw with an actionable message
  rather than falling through.

v0.6, v0.7, and v0.8 hashes are byte-identical to previous releases; the
migration is verified against the existing viem fixtures, and the new v0.9
vectors are generated from the pinned EntryPoint contracts
(`tool/entry_point_v09_vectors/`).

## [0.4.1] - 2026-07-14

EIP-7702 + paymaster release: a paymaster-sponsored **first** 7702 operation no
longer fails AA34. Contributed by [@KabaDH](https://github.com/KabaDH) in
[#50](https://github.com/LiorAgnin/permissionless.dart/pull/50); verified live
on Sepolia against Pimlico (first-time delegation installed and gas paid in the
ERC-20 token by an EOA holding zero ETH).

### Fixed

- **`eip7702Auth` is now forwarded to paymaster RPCs.** `PaymasterClient.getPaymasterStubData`
  and `getPaymasterData` accept an optional `authorization` and serialize it as
  `eip7702Auth` inside `params[0]`, matching viem's `formatUserOperationRequest`.
  `prepareUserOperationWithAuth` passes the authorization to both calls, so the
  paymaster simulates against the delegated account instead of an empty EOA.
- **`prepareUserOperationForErc20Paymaster` no longer discards the signed
  authorization** — it is returned as `result.authorization` for submission via
  `sendPreparedUserOperationWithAuth`.
- **Paymaster gas limits survive the final `pm_getPaymasterData` call.** The
  helper now mutates only `callData` on the prepared operation instead of
  rebuilding it field by field, mirroring permissionless.js's spread-merge.
- **Removed a redundant (paid) `pm_getPaymasterData` call** during preparation:
  the flow is now 1× stub + 1× estimate + a single real data call, matching
  permissionless.js.

### Added

- `skipFinalPaymasterData` on `prepareUserOperationWithAuth` (default `false`)
  to stop after the stub for flows that fetch real paymaster data themselves.
- `example/erc20_paymaster_example.dart` — gasless ERC-20 transfer where gas is
  paid in the token itself, including automatic first-time 7702 delegation.
- Per-version example runners and configs for Kernel, Light, Safe, Simple, and
  Thirdweb accounts
  ([#45](https://github.com/LiorAgnin/permissionless.dart/pull/45)).

### Changed

- Bumped `web3dart` to 3.0.3
  ([#36](https://github.com/LiorAgnin/permissionless.dart/pull/36)).

## [0.4.0] - 2026-07-12

Parity release: fixes every P0/P1 divergence found by the
[Dart-vs-JS parity audit](https://github.com/LiorAgnin/permissionless.dart/tree/main/docs/parity-audit)
and aligns behavior with permissionless.js across accounts, clients, and actions.

### Breaking changes

- **Safe default threshold** is now `owners.length` (all owners must sign), matching
  permissionless.js `toSafeSmartAccount`. Previously defaulted to `1`.
  Multi-owner Safes created without an explicit `threshold` produce a different
  setup calldata and therefore a **different counterfactual address**.
  Pass `threshold: BigInt.one` to keep the previous 1-of-n default.
- **Thirdweb salt is now UTF-8-encoded** (was hex-decoded), matching permissionless.js
  `toHex(salt)`. Any account created with a non-default `salt` gets different
  `factoryData` and a **different counterfactual address**. The old decoding was a
  parity bug — addresses it produced never matched the TypeScript SDK's.
- **ERC-1271 `signMessage` / `signTypedData` outputs changed across accounts**
  (Light, Thirdweb, Trust, Etherspot, Biconomy, Kernel, Safe). Previous releases
  double-prefixed digests (EIP-712 wrapper digest signed via `personal_sign`),
  skipped validator prefixes (Kernel), or omitted the SafeMessage wrapper and
  eth_sign V adjustment (Safe) — producing signatures that failed on-chain
  `isValidSignature`. Signatures now byte-match permissionless.js.
- **ERC-7579 `revertOnError` execution-mode bit polarity flipped** to match the JS
  encoding; execution modes built with `revertOnError` now encode the correct
  `ModeSelector` byte.
- **ERC-7579 query actions** (`supportsModule`, `supportsExecutionMode`,
  `isModuleInstalled`, `getAccountId`) no longer swallow errors to `false`/`''`.
  On call failure they retry with the account's `factory`/`factoryData`
  (counterfactual path), matching permissionless.js; other errors propagate.

### Added

- **PasskeyServerClient** (`createPasskeyServerClient`) — port of permissionless.js
  `clients/passkeyServer` + `actions/passkeyServer`. Exposes all five `pks_*` RPC
  methods: `startRegistration`, `verifyRegistration`, `startAuthentication`,
  `verifyAuthentication`, and `getCredentials`. Placed in the core `permissionless`
  package for JS layout parity (client-side passkey creation remains in
  `permissionless_passkeys`).
- **`PublicClient.call` deployless factory path** — optional `factory` /
  `factoryData` parameters perform a viem-style deployless `eth_call` via
  `deploylessCallViaFactoryBytecode`, enabling counterfactual ERC-7579 reads.
- **`BundlerRpcError.aaErrorDescription`** — short descriptions for known ERC-4337
  AA## codes; `toString` includes the description when available.
- **`CallsStatus.parseCallsStatusCode`** — public helper matching viem
  `getCallsStatus` numeric ranges and legacy string statuses.

### Changed

- **Safe batch `encodeCalls`** routes through **MultiSendCallOnly** (not MultiSend),
  matching permissionless.js safety property (no inner delegatecalls).
- **Safe stub signatures** byte-match permissionless.js (ECDSA ecrecover-path dummy
  and WebAuthn dummy with realistic authenticatorData / long clientDataFields).
- **`writeContract`** now encodes calldata via web3dart's ABI encoder instead of a
  hand-rolled encoder that mis-encoded dynamic `bytes` and lacked support for
  strings, arrays, and tuples.

### Fixed

- **Four wrong hard-coded ERC-7579 selectors** (`utils/erc7579.dart`):
  `uninstallModule` (`0xa4d6f1d2` → `0xa71763a8`), `isModuleInstalled`
  (`0x6d61fe70` → `0x112d3a7d`), `supportsModule` (`0x12d79da3` → `0xf2dc691d`),
  and `accountId` (`0x7b60424a` → `0x9cfd7cff`). Previously, uninstall calldata
  reverted and queries silently returned `false`/`''`.
- **Kernel v0.2.4 `execute`/`executeBatch`** now use the Kernel v2 selectors
  (`0x51945447`/`0x34fcd5be`) with matching parameter encoding; the previous
  SimpleAccount-style calldata reverted on every v0.2.4 call.
- **Nexus `signUserOperation`** returns the bare 65-byte signature, matching
  permissionless.js. Previously the K1 validator address was prepended (85 bytes),
  causing AA24 signature errors on-chain (Nexus selects the validator via the
  nonce key).
- **Pimlico client actions** aligned with the Pimlico API:
  `validateSponsorshipPolicies` sends `pm_validateSponsorshipPolicies` (was a
  nonexistent `pimlico_*` method), `estimateErc20PaymasterCost` computes the cost
  locally from quotes (was calling a nonexistent RPC method), and
  `sendCompressedUserOperation` sends the correct 3-parameter shape.
- **Safe v1.5.0 `MULTI_SEND_CALL_ONLY` address** corrected to
  `0xA83c336B20401Af773B6219BA5027174338D1836`.
- **Simple account EntryPoint-version encode/sign paths**: v0.6 `executeBatch`
  emits the v0.6 selector `0x18dfb3c7` (`address[],bytes[]`) instead of the v0.7
  3-array form, and v0.8 non-7702 batching/signing follow the v0.8 shapes.
- **EntryPoint v0.6 `signUserOperation`** is now implemented for accounts that
  accept a v0.6 configuration (previously configured-but-unimplemented: accounts
  derived v0.6 addresses, then threw or mis-packed at signing).

- **Safe CREATE2 address derivation** fetches `proxyCreationCode()` from the configured
  SafeProxyFactory via `publicClient` when available, with fallback to the verified
  hardcoded v1.4.1 constant. Avoids silent getAddress-vs-deploy mismatch for v1.5.0
  and custom factories.
- **`BundlerRpcError.aaErrorCode`** scans both `message` and `data`, case-insensitively
  (matches viem `getBundlerError`); previously only scanned `data` with `AA\d+`.
- **`CallsStatus.fromJson`** accepts wallet `status` field, numeric strings, and
  legacy `"CONFIRMED"` / `"PENDING"` strings without throwing on `as int`.

### Deliberate deviations from permissionless.js (parity audit 018)

The following items were reviewed and intentionally not ported in this release:

- **EIP-712 edge cases** (`message_hash.dart`): custom `EIP712Domain` types,
  value-range/`bytesN` validation, and UTF-8 type-string hashing remain
  deferred. Standard ASCII domains and types match JS/viem.
- **ERC-20 paymaster flow shape** (`experimental/pimlico/erc20_paymaster.dart`):
  Dart still uses a stub+real estimation path with a re-fetch rather than JS's
  stub-substitution + single final data fetch; standalone function API vs JS
  decorator remains. Functional sponsorship works; round-trip efficiency is a
  follow-up.
- **install/uninstall / signMessage / sendTransaction surfaces**: per-op
  paymaster/authorization/appended-`calls` overrides on install/uninstall,
  raw-bytes `signMessage`, and batch/userop-params `sendTransaction` are not
  ported (narrower Dart API; core flows work via existing methods).
- **`AccountNotFoundError`**: structurally unnecessary — Dart always requires
  an account on `SmartAccountClient` construction, so the JS error cannot
  arise at action time.

## [0.3.0] - 2026-04-17

### Added

- **`useMultiSendForSetup` option** on `SafeSmartAccount` / `createSafeSmartAccount` — port of the same option from [permissionless.js@0.3.5](https://github.com/pimlicolabs/permissionless.js/releases/tag/permissionless%400.3.5).
  - Default `true` preserves the existing MultiSend-wrapped setup — no changes to counterfactual addresses for existing users.
  - When `false` and there is exactly one setup transaction (the default `enableModules` call, no WebAuthn owners, no ERC-7579 modules), `Safe.setup` is called directly with that call's `to`/`data` instead of being wrapped through MultiSend.
  - Set `useMultiSendForSetup: false` to produce CREATE2 addresses compatible with Safe Protocol Kit / relay-kit address derivation.
  - The flag has no effect in ERC-7579 mode (the launchpad path is independent) or when a WebAuthn owner is present (extra setup calls force MultiSend).



## [0.2.0] - 2026-02-20

### Added
- **RIP-7212 Dynamic Detection**: `isRip7212Supported(PublicClient)` probes the P256 precompile
  via `eth_call` with a known-valid Wycheproof test vector, detecting support on any chain
  - Results cached per chain ID for the lifetime of the application
  - `clearRip7212Cache()` for testing
  - Falls back gracefully when the precompile is not deployed (revert → `false`)
- **RIP-7212 Static Detection**: `supportsRip7212(chainId:)` and `shouldUseP256Precompile(chainId:)`
  check against a curated set of 67 chain IDs known to support the P256 precompile
- **RIP-7212 Chain Support**: Comprehensive `rip7212SupportedChainIds` set.
- **RIP-7212 Constants**: `p256PrecompileAddress` (`0x0000...0100`)
- **Kernel Precompile Integration**: Kernel WebAuthn accounts now dynamically detect P256
  precompile support via `isRip7212Supported` when a `publicClient` is available
  - `signUserOperation`, `signMessage`, `signTypedData` use dynamic detection (async)
  - `getStubSignature` uses static chain ID list (sync, for gas estimation)
  - Falls back to static `shouldUseP256Precompile` when no `publicClient` is configured

### Changed
- **Dependencies**: Bumped `web3dart` to `^3.0.2`
- **Monorepo**: Restructured as a Dart pub workspace monorepo
  - Package moved to `packages/permissionless/`
  - Uses native Dart pub workspaces (`resolution: workspace`)
  - Melos 7.x for workspace management
- **SDK**: Minimum SDK version bumped to `>=3.5.0` (required for pub workspaces)

### Added
- **Passkeys Package**: New `permissionless_passkeys` sibling package for WebAuthn/Passkeys support

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


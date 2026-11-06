# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-11-06

A structural refactor of the package plus the behaviour fixes it turned up
([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)). Each fix
landed with a test that failed first. Nothing exported was removed or renamed,
so calling code keeps compiling. Some things can still break you, all under
**Changed**:

- Subclasses that override a method which gained a parameter must add it.
- Some invalid configurations now throw where they used to build.
- Two Safe setups get a different counterfactual address.
- EntryPoint v0.6 accounts with a paymaster use different RPC methods.
- WebAuthn accounts no longer get a 900,000 verification-gas floor.

### Added

- **`EntryPointVersioned`** and **`entryPointVersionOfAccount`**: an interface
  for accounts that know their EntryPoint version, and a helper that reads it.
  Every built-in account implements it, so the client and
  `sendUserOperationSync` no longer have to guess the version from the
  EntryPoint address. `EtherspotSmartAccount` and `TrustSmartAccount` gain the
  public `entryPointVersion` getter the other accounts already had
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`DeploymentCallsEncoder`**: the interface an account implements when its
  first, deploying operation needs different call data. Safe ERC-7579 uses it
  for the `setupSafe` wrapper. `SmartAccountClient` checks for this interface
  instead of checking for `SafeSmartAccount`
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`hashMessageBytes`**: EIP-191 hash of raw bytes, like viem's
  `hashMessage({ raw })`. `hashMessage` and every account now share this one
  implementation ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`getUserOperationTypedData`**: the EIP-712 typed data an EntryPoint v0.8
  account signs, under viem's name
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`PermissionlessException`** is exported. `SendUserOperationSyncError`
  already extended it, but there was no way to catch the library's errors by
  their common type ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Solidity signature constants** for the selector tables, such as
  `erc7579ExecuteSignature`, `erc7579InstallModuleSignature`,
  `simpleAccountCreateAccountSignature` and `etherspotInitMsaSignature`. The
  selector tables are now derived from these strings
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`defaultReceiptTimeout`** (120 s) and **`defaultReceiptPollingInterval`**
  (2 s): the defaults every receipt wait uses
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **New optional parameters.** Each one defaults to the old behaviour
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - `BundlerClient.sendUserOperation` and `estimateUserOperationGas`:
    `entryPoint` (defaults to the client's) and `authorization` (sent as the
    operation's `eip7702Auth`).
  - `SmartAccountClient.sendPreparedUserOperation`: `authorization`.
  - `SmartAccountClient.sendUserOperationAndWait`: `callGasLimit`,
    `verificationGasLimit`, `preVerificationGas`, `signature`, `factory` and
    `factoryData`, forwarded to `sendUserOperation`. Before, the `AndWait`
    variant had no way to pass them.
    `sendUserOperationV06AndWait` gains `signature`.
  - `PimlicoClient.getTokenQuotes`, `estimateErc20PaymasterCost` and
    `validateSponsorshipPolicies`: `entryPoint` (defaults to the client's).
  - ERC-7579 queries `supportsExecutionMode`, `supportsModule`,
    `isModuleInstalled` and `getAccountId`: `publicClient` is optional and
    defaults to the `SmartAccountClient`'s own.
  - Experimental `prepareUserOperationForErc20Paymaster`: `publicClient` is
    optional and defaults to the `SmartAccountClient`'s own. Experimental
    `estimateErc20PaymasterCost` gains `entryPoint`.
  - `Hex.fromBytes` accepts any `List<int>`, not only `Uint8List`.
  - `SmartAccountClient.sendUserOperationV06` and
    `sendUserOperationV06AndWait`: `callGasLimit`, `verificationGasLimit`,
    `preVerificationGas`, `initCode` and `stateOverride`, forwarded to
    `prepareUserOperationV06`. They now take every parameter
    `prepareUserOperationV06` takes except `skipFinalPaymasterData`, which a
    sent operation can't use. A supplied gas limit skips the bundler estimate
    for that field ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
  - `SmartAccountClient.prepareUserOperationV06`:
    `stateOverride`, sent with `eth_estimateUserOperationGas`, and
    `skipFinalPaymasterData`, which keeps the stub `paymasterAndData` and skips
    `pm_getPaymasterData`. Both work as they do in `prepareUserOperation` ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`PaymasterStubData.fromJson` and
  `PaymasterData.fromJson` accept the ERC-7677 v0.6 response**
  `{ paymasterAndData, sponsor?, isFinal? }`. They split `paymasterAndData`
  into `paymaster` (the first 20 bytes) and `paymasterData` (the rest), so
  `withPaymasterStubV06` and `withPaymasterDataV06` rebuild the same bytes. A
  value shorter than an address throws `FormatException`. Responses that carry
  `paymaster` parse as before ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Changed

- **Subclasses that override these methods must add the new named
  parameters.** `BundlerClient.sendUserOperation` and
  `estimateUserOperationGas`, `SmartAccountClient.sendPreparedUserOperation`,
  `sendUserOperationAndWait` and `sendUserOperationV06AndWait`, and every other
  method listed under **Added → New optional parameters**. An override that
  keeps the old parameter list no longer compiles. An override of
  `PaymasterClient.sponsorUserOperation` that declares `required BigInt
  chainId` must make it optional. Code that only *calls* these methods is
  unaffected ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The EntryPoint v0.6 paymaster flow is ERC-7677,
  as in viem and the v0.7 path.** This affects EntryPoint v0.6 accounts that
  pass a `paymaster` to `createSmartAccountClient`: Simple, Light, Thirdweb or
  Safe on v0.6, Kernel v0.2, Biconomy and Trust. v0.7/v0.8 accounts, and v0.6
  accounts without a paymaster, see no change ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
  - `prepareUserOperationV06`, and the v0.6 send methods through it, no longer
    call `pm_sponsorUserOperation`. They call `pm_getPaymasterStubData`, then
    `eth_estimateUserOperationGas` on the bundler if a gas field is missing,
    then `pm_getPaymasterData`. A stub with `isFinal: true` skips the last call.
  - Pimlico serves ERC-7677 on v0.6, so Pimlico setups keep working. Only the
    methods on the wire change. Update request logs, mocks and allow-lists
    keyed on `pm_sponsorUserOperation`.
  - `callGasLimit`, `verificationGasLimit` and `preVerificationGas` now come
    from the bundler's estimate with the client's `gasMultipliers` applied,
    not from the paymaster's sponsorship response. Values you pass are still
    used as given.
  - Any ERC-7677 paymaster now works with v0.6 accounts. Before, non-Pimlico
    paymasters failed with "method not found".
  - `PaymasterClient.sponsorUserOperation` is still there as an explicit
    Pimlico action, as in permissionless.js, if you want the old single call.
- **WebAuthn accounts no longer get a 900,000
  verification-gas floor.** `SmartAccountClient` used to raise
  `verificationGasLimit` to at least 900,000 for every account with
  `isWebAuthn`. They now get the bundler estimate times the configured
  `gasMultipliers`, like every other account and as in permissionless.js. The
  estimate is now realistic because the Kernel WebAuthn stub was fixed (see
  **Fixed**). To keep a minimum, pass `verificationGasLimit` or use custom
  `gasMultipliers`. The `GasMultipliers.webAuthn` preset is still there and
  is opt-in ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Two Safe setups get a different counterfactual address.** Both old
  addresses were wrong
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - A Safe in ERC-7579 mode with a WebAuthn owner now lists that owner as the
    `SafeWebAuthnSharedSigner`, as standard mode and permissionless.js do. The
    old setup data listed a placeholder address that nobody can sign for.
  - A Safe v1.5.0 built without a `publicClient` now uses the v1.5.0 proxy
    creation code. Before, every offline v1.5.0 address was derived from the
    v1.4.1 proxy code.
- **Invalid account configs throw `ArgumentError` at construction** instead of
  building an account that cannot work
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - Kernel `customAddresses` without an `ecdsaValidator`, for every version.
    Kernel v0.2.x used to put the account implementation in the validator
    slot, so the initCode could never deploy.
  - Kernel with a WebAuthn owner on v0.2.x, or without a `webAuthnValidator`
    address. This used to be a `StateError` from the middle of
    `prepareUserOperation`, after RPC calls had already run.
  - Safe with more than one WebAuthn owner. Every WebAuthn owner maps to the
    same shared-signer address, so `Safe.setup` reverted with GS203/GS204, and
    the shared signer holds only one P-256 key. permissionless.js accepts this
    config and derives an address that can't be deployed.
  - Thirdweb with EntryPoint v0.8. It used to fall back to the v0.6 factory
    and EntryPoint without saying so.
  - Light Account pairs other than 1.1.0 with v0.6 and 2.0.0 with v0.7. Other
    pairs used to sign the wrong hash or use the wrong factory.
  - Safe with a WebAuthn owner when the resolved
    addresses lack `webAuthnSharedSignerAddress`, or, outside ERC-7579 mode,
    `safeP256VerifierAddress`. The built-in Safe 1.4.1 + EntryPoint v0.6 table
    has neither, so that pair now throws here. In 0.5.0 these configs failed
    later, with a null-check `TypeError` or a `StateError` from `getAddress`,
    `getStubSignature` or signing. This deliberately differs from permissionless.js, which reads these
    addresses only when it builds the setup and silently skips `configure()`
    without a verifier. Kernel already checks `webAuthnValidator` the same way.
    One config that used to work now throws: a pre-set `address` of an
    already-deployed Safe with a WebAuthn owner and custom addresses that
    have a shared signer but no verifier, in standard mode ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Encoders range-check their inputs and throw `ArgumentError`**, as viem
  does ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - `AbiEncoder` rejects out-of-range `uintN`/`intN` values and type widths
    Solidity doesn't have (`uint7`, `int264`, `bytes33`, `bytes0`), including
    inside arrays and tuples. Before, debug builds threw `AssertionError` and
    release builds encoded the bad value.
  - `hashTypedData` rejects out-of-range integers, a `bytesN` value longer than
    N bytes and invalid widths. Shorter `bytesN` values are still right-padded.
  - `ExecutionMode.encode` and `encode7579ExecuteMode` reject a selector over 4
    bytes, a context over 22 bytes, and a `callType`/`execType` over one byte.
    They used to truncate (`0x100` became call mode). Valid inputs encode as
    before.
- **Some failures now throw, or throw a different type.** Check handlers that
  catch the old type
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - Safe with a `publicClient`: an RPC error from `proxyCreationCode()` now
    propagates and nothing is cached. A `0x` or empty result throws
    `StateError`. Before, any failure fell back to the canonical proxy code
    and cached that address for the account's lifetime, which is wrong for a
    custom `safeProxyFactoryAddress`. Without a `publicClient` nothing changes.
  - Kernel signing an operation layout that doesn't match its EntryPoint
    version throws `ArgumentError`. It used to return a signature that could
    never validate (see **Fixed**).
  - `PimlicoClient.getSupportedTokens` throws when the result is not a JSON
    array. It used to return `[]` for any unexpected shape and also accepted
    an undocumented `{tokens: [...]}` object.
  - `estimateErc20PaymasterCost` throws `StateError` when the token quote has
    no `exchangeRateNativeToUsd`. It used to report a cost of $0.
- **Top-level ERC-7579 queries and ERC-20 reads
  throw `StateError` when the call returns no data (`0x`)**, as viem's
  `readContract` does ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)):
  - `isModuleInstalled`, `supportsModule`, `getAccountId` and
    `getInstalledModulesOfType` used to return `false`, `''` or `[]`. An
    account returns `0x` when it has no code on that chain, for example
    because it is not deployed yet. For a counterfactual account, use the
    `SmartAccountClient` methods of the same names. They retry through the
    factory, as permissionless.js does.
  - `getTokenAllowance` and `getTokenBalance` used to return 0 for an address
    with no code, such as a token on the wrong chain or a mistyped address.
    `getApprovalCallIfNeeded` and the experimental
    `prepareUserOperationForErc20Paymaster` pass the error on instead of
    building an `approve()` call for a non-token.
  - The decoders `decode7579BoolResult`, `decode7579StringResult` and
    `decodeUint256Result` still map `0x` to the default value.
- **`Eip7702Authorization.toJson` returns the `yParity` wire shape**, the same
  map as `toRpcFormat`, so `jsonEncode(authorization)` is what bundlers and
  viem expect. It used to emit the legacy `v` (27/28)
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`GasUnits` rounds sub-wei digits half up**, like viem's `parseUnits`.
  `GasUnits.parse('1.5 wei')` is now 2; it used to truncate to 1. Gwei and
  ether inputs already rounded this way
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **WebAuthn owners are recognised by class.** `isWebAuthnAccount(owner)` is
  `owner is WebAuthnAccountOwner`. An `AccountOwner` that reports
  `type == 'webAuthn'` without extending `WebAuthnAccountOwner` is treated as
  an ECDSA owner. Kernel and Safe used to crash on it with a `TypeError`
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **SimpleAccount on EntryPoint v0.6 ignores
  `Call.value` in a batch of more than one call**, and this is now documented
  on `createSimpleSmartAccount`, `SimpleSmartAccountConfig` and
  `SimpleSmartAccount.encodeCalls`. The v0.6 contract's
  `executeBatch(address[],bytes[])` has no value field. There is no runtime
  change, matching permissionless.js. To send value, use a single call or
  EntryPoint v0.7/v0.8. Every other account and version carries value per
  call ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Deprecated

All of these still work. All but the last come from
[#90](https://github.com/LiorAgnin/permissionless.dart/pull/90).

- `BundlerClient.sendUserOperationWithAuthorization` and
  `estimateUserOperationGasWithAuthorization`. Use `sendUserOperation(userOp,
  authorization: ...)` and `estimateUserOperationGas(userOp, authorization:
  ...)`. The old methods only ever sent the first authorization in the list.
- `PaymasterClient.sponsorUserOperation(chainId:)`. The parameter was never
  read, because `pm_sponsorUserOperation` takes no chain id. It is now
  optional; drop it.
- `PaymasterRpcError`. Nothing throws it; paymaster RPC errors arrive as
  `BundlerRpcError`.
- `erc20PaymasterGasBuffer`. Unused; the cost formula uses
  `PimlicoTokenQuote.postOpGas`.
- `shouldUseP256Precompile`. Use `supportsRip7212`, which it aliased.
- `Hex.encode`. Use `Hex.fromBytes`.
- `UserOperationGasEstimate.withMinimumVerificationGas`.
  `SmartAccountClient` no longer calls it. For an explicit limit, pass
  `verificationGasLimit` to `prepareUserOperation` ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

### Fixed

- **The Kernel WebAuthn gas-estimation stub was far
  from a real signature.**
  `getDummyKernelWebAuthnSignature`, which `KernelSmartAccount.getStubSignature`
  returns for a WebAuthn owner, used an r outside the P-256 curve order. So
  bundlers priced a signature check that fails early, and estimates came out
  far too low. It is now byte-identical to the permissionless.js 0.5.2 stub,
  with the same r, s, authenticatorData and clientDataJSON, and it always
  encodes `usePrecompiled = false`. Expect higher, realistic estimates. On a
  local test chain, Kernel v0.3.1 WebAuthn operations got about 630,000
  verification gas, or about 945,000 for the operation that deploys the
  account. The stub prices the Solidity P-256 verifier, so chains with the
  RIP-7212 precompile get the same estimate while the operation uses about
  120,000. permissionless.js behaves the same; the cost is a larger required
  prefund. In 0.5.0 the stub could also price the precompile path for the
  first operation on a chain whose node lacked it, then send the Solidity
  encoding ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

- **`SimpleSmartAccount.signMessage` and
  `Eip7702SimpleSmartAccount.signMessage` applied the EIP-191 prefix twice.**
  The signature verified against neither the message nor its hash, so
  `isValidSignature` on Simple7702Account rejected every message signed from
  Dart. Both now return the owner's `personal_sign` of the message.
  permissionless.js throws for `SimpleSmartAccount.signMessage` because
  SimpleAccount is not ERC-1271; this package keeps signing so existing
  callers keep working
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Kernel signed with the wrong UserOperation hash across versions.** Kernel
  v0.2.x `signUserOperation` hashed a v0.7 layout for the v0.6 EntryPoint, and
  v0.3.x `signUserOperationV06` hashed a v0.6 layout for v0.7. Neither
  signature could validate. Kernel now hashes by its EntryPoint version and
  implements `SmartAccountV06`, so `SmartAccountClient.signUserOperationV06`
  accepts Kernel v0.2.x
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **EntryPoint v0.6 operations always used nonce 0.** `prepareUserOperationV06`
  never read `EntryPoint.getNonce`, so every v0.6 operation after the first
  failed with AA25 unless you passed `nonce` yourself
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`SmartAccountClient` estimated and sent to the bundler's EntryPoint.**
  The nonce, paymaster data and signature came from `account.entryPoint`, but
  the estimate and the send went to `bundler.entryPoint`. An EIP-7702 Simple
  account (v0.8) paired with a bundler built on `EntryPointAddresses.v07` had
  a v0.8-signed operation simulated and sent on v0.7. Everything now uses
  `account.entryPoint`, as viem does
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The ERC-20 paymaster helper quoted tokens for the wrong EntryPoint.**
  `prepareUserOperationForErc20Paymaster` asked Pimlico for quotes against
  the `PimlicoClient`'s EntryPoint while the operation ran on the account's.
  When the two differed, the approval went to the wrong paymaster and the
  cost used the wrong `postOpGas` and exchange rate
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The first EIP-7702 operation on EntryPoint v0.7 reverted with AA10.** The
  client set the `0x7702` initCode marker for every first-time 7702
  operation, but the marker only exists on EntryPoint v0.8. On v0.7,
  `Eip7702KernelSmartAccount` could never send its first operation. The
  marker is now set only on v0.8, and on v0.7 the authorization goes alone,
  as in permissionless.js
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **Paymaster gas limits below 10,000 were replaced.** A
  `paymasterVerificationGasLimit` or `paymasterPostOpGasLimit` under 10,000,
  including the 0 that a paymaster without `postOp` returns, was swapped for
  the bundler's estimate. The operation then carried a different gas field
  from the one the paymaster signed, which usually fails with AA34. The
  paymaster's values are now kept
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The ERC-20 paymaster cost left out paymaster verification gas.**
  `estimateTokenCost`, `PimlicoClient.estimateErc20PaymasterCost` and the
  experimental helpers under-quoted the token amount, so the approval could
  be too small. They now share one formula built on the required prefund, as
  permissionless.js does. Expect higher, correct quotes
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The experimental ERC-20 paymaster helper dropped the Safe ERC-7579
  `setupSafe` wrapper.** It re-encoded the calls without it, so the first
  operation of an undeployed ERC-7579 Safe failed. v0.6 deploying operations
  now follow the same rule as v0.7
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`sendUserOperationSync` rejected accounts with a custom EntryPoint
  address** as unsupported, though `sendUserOperation` worked for them. It now
  reads the account's configured EntryPoint version
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`stateOverridesToJson` let overrides for the same address replace each
  other.** A balance override and an allowance override for one token kept
  only the last. Serialization now merges them
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`UserOperationV07.fromJson` could not read the `0x7702` factory marker**
  that `toJson` writes, so a 7702 operation failed to round-trip with a
  `FormatException` ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **EIP-7702 authorizations built with a 0/1 recovery id** threw "must fit in
  uint8" from `toRpcFormat`. Both 0/1 and 27/28 now work
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **The RIP-7212 probe cached `false` after one failed call.** A timeout or
  RPC error in `isRip7212Supported` disabled the precompile for that chain for
  the rest of the process. Now only a real answer is cached; a failed call
  returns `false` and the next call probes again
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`GasUnits` lost precision through `double`.** `parse`, `gweiToWei` and
  `etherToWei` dropped digits past 2^53 and saturated at 2^63 wei, so
  `'10 ether'` came back as 9223372036854775807. `format` printed `1e+21 ETH`
  for large values. Both now use exact decimal arithmetic
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`decode7579StringResult` mangled non-ASCII text.** `getAccountId` returned
  mojibake (`ñ✓` became `Ã±â`). It now decodes UTF-8
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`decode7579Calls` rejected upper-case selectors** and returned no calls for
  a truncated batch. It now accepts either case, throws on truncated input,
  and follows ABI head offsets
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).
- **`EtherspotSelectors.execute` held `0x61461954`** instead of the ERC-7579
  `execute(bytes32,bytes)` selector `0xe9ae5c53`. The account's own call data
  was always correct; only code that read the constant was affected
  ([#90](https://github.com/LiorAgnin/permissionless.dart/pull/90)).

## [0.5.0] - 2026-11-04

Parity with permissionless.js **0.5.2**: the new `sendUserOperationSync`
Pimlico action. This release also fixes two signing bugs found by a new property
test that checks every account signs exactly the `userOpHash` the EntryPoint
verifies, across v0.6, v0.7 and v0.8
([#80](https://github.com/LiorAgnin/permissionless.dart/pull/80)). Minor bump: new public API, and v0.7/v0.8 signing now
throws on out-of-range gas fields (see **Changed**).

### Added

- **`sendUserOperationSync`** (permissionless.js 0.5.1/0.5.2 parity): new
  `PimlicoActions` extension on `SmartAccountClient`. It prepares, signs and
  sends a user operation with `pimlico_sendUserOperationNow` and returns its
  receipt. A reverted call comes back as `success: false`, not a throw. If the
  outcome is unclear it polls for the receipt until `timeout` (default: the
  bundler RPC timeout) and never resends. Failures throw
  `SendUserOperationSyncError`, whose `kind` (`rejected`, `bundleReverted`,
  `pending`, `notFound`) and `canResend` say what happened and whether
  resending is safe. EntryPoint v0.7 and v0.8
  ([#87](https://github.com/LiorAgnin/permissionless.dart/pull/87)).
- **`getUserOperationHash`** and **`entryPointVersionOf`**: public helpers for
  the EntryPoint v0.7/v0.8 user operation hash, byte-identical to viem,
  including the EIP-7702 `initCode` delegation rule
  ([#87](https://github.com/LiorAgnin/permissionless.dart/pull/87)).
- **`BundlerHttpError`**: non-200 HTTP responses from the RPC endpoint now
  throw this `BundlerRpcError` subclass, so callers can tell an HTTP failure
  from a JSON-RPC error. Existing `on BundlerRpcError` handlers still catch it
  ([#87](https://github.com/LiorAgnin/permissionless.dart/pull/87)).
- **Kernel ERC-1271 helpers**: public `wrapMessageHash`, `signKernelMessage`
  and `signKernelTypedData` (unprefixed wrap-and-sign). Account `signMessage` /
  `signTypedData` still prefix (`0x01‖validator` on v0.3.x, `0x00` on 7702)
  ([#75](https://github.com/LiorAgnin/permissionless.dart/pull/75)).
- **`sortAddresses`**: public helper that copies, then sorts addresses by
  lowercased `0x` hex (UTF-16 code-unit order). Safe ERC-7579 and Nexus
  attester encoding use it. **Counterfactual addresses are unchanged**
  ([#75](https://github.com/LiorAgnin/permissionless.dart/pull/75)).

### Changed

- **Packed gas fields outside uint128 now throw before signing.**
  `signUserOperation` on every v0.7/v0.8 account throws `ArgumentError` when
  `callGasLimit`, `verificationGasLimit`, `maxFeePerGas`,
  `maxPriorityFeePerGas`, `paymasterVerificationGasLimit` or
  `paymasterPostOpGasLimit` is negative or ≥ 2^128. It used to return a
  signature over a malformed preimage that the EntryPoint would reject.
  `getPackedUserOperation`, `getAccountGasLimits`, `getGasFees` and
  `getPaymasterAndData` throw the same way. Valid inputs encode byte-for-byte
  as before; v0.6 is unchanged
  ([#82](https://github.com/LiorAgnin/permissionless.dart/pull/82)).
- **Range-checked low-level encoders.** `Hex.fromBigInt(value, byteLength: n)`
  throws `ArgumentError` for a negative value or one wider than `n` bytes, and
  takes a new optional `name:` for the error. `AbiEncoder.encodeUint128` and
  `encodeUint48` (new optional `name:`) now check 16 and 6 bytes. Calls
  without `byteLength` are unchanged
  ([#82](https://github.com/LiorAgnin/permissionless.dart/pull/82)).

### Fixed

- **Etherspot and Safe (EntryPoint v0.7): `factory` with a null `factoryData`
  no longer signs `initCode = 0x`.** The EntryPoint hashes
  `factory ‖ factoryData`, so these ops failed with AA24. A null `factoryData`
  is now treated as empty. Only callers who set `factory` themselves were
  affected; `getFactoryData` always returns both fields. Etherspot now matches
  permissionless.js. Safe intentionally differs from permissionless.js, which
  has the same bug, and follows the Safe 4337 module instead
  ([#81](https://github.com/LiorAgnin/permissionless.dart/pull/81)).

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


import '../../clients/public/public_client.dart';
import '../../clients/public/rip7212.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/erc7579.dart';
import '../../utils/message_hash.dart';
import '../../utils/rip7212.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../erc7579_calls.dart';
import '../webauthn_owner.dart';
import 'constants.dart';
import 'kernel_abi.dart';
import 'kernel_erc1271.dart';
import 'kernel_webauthn.dart';

/// Configuration for creating a Kernel smart account.
class KernelSmartAccountConfig {
  /// Creates a configuration for a Kernel smart account.
  ///
  /// - [owner]: The account owner
  /// - [chainId]: Chain ID for the network
  /// - [version]: Kernel version (defaults to `0.3.0-beta`, matching JS EP v0.7)
  /// - [index]: Index/salt for address derivation (defaults to 0)
  /// - [nonceKey]: Custom nonce key (v2: passthrough; v3: ≤ maxUint16, 2-byte slot)
  /// - [useMetaFactory]: For v0.3.x, route deployment via meta factory (default true)
  /// - [entryPointAddress]: Override the canonical EntryPoint address
  ///
  /// Throws [ArgumentError] if version-specific requirements aren't met.
  KernelSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_3_0_beta,
    BigInt? index,
    this.customAddresses,
    this.nonceKey,
    this.useMetaFactory = true,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  }) : index = index ?? BigInt.zero {
    final addresses =
        customAddresses ?? KernelVersionAddresses.getAddresses(version);
    if (addresses == null) {
      throw ArgumentError(
        'No addresses found for Kernel version ${version.value}',
      );
    }
    if (version.hasExternalValidator && addresses.ecdsaValidator == null) {
      throw ArgumentError(
        'ECDSA validator address required for Kernel ${version.value}',
      );
    }
    if (version.isV3) checkKernelV3NonceKey(nonceKey, version);
    if (version.isV3 && useMetaFactory && addresses.metaFactory == null) {
      throw ArgumentError(
        'Meta factory address required when useMetaFactory is true for '
        'Kernel ${version.value}',
      );
    }
  }

  /// The account owner.
  final AccountOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Kernel version to use.
  final KernelVersion version;

  /// Index/salt for address derivation.
  final BigInt index;

  /// Custom contract addresses (optional).
  final KernelAddresses? customAddresses;

  /// Optional custom nonce key.
  ///
  /// For v0.2.x: used as-is. For v0.3.x: must be ≤ maxUint16 and occupies the
  /// trailing 2 bytes of the 24-byte encoded key.
  final BigInt? nonceKey;

  /// Whether to deploy v0.3.x accounts via the meta factory.
  ///
  /// When `true` (default), factory args use
  /// `metaFactory.deployWithFactory(factory, initData, salt)`.
  /// When `false`, factory args use
  /// `factory.createAccount(initData, salt)` directly.
  ///
  /// Mirrors permissionless.js `useMetaFactory` (boolean path).
  final bool useMetaFactory;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  ///
  /// If provided, the account address will be computed using
  /// [PublicClient.getSenderAddress] which simulates account deployment.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  ///
  /// If provided, this address will be used instead of RPC computation.
  /// Use when you already know the account address.
  final EthereumAddress? address;
}

/// Kernel smart account implementation.
///
/// Supports both v0.2.x (EntryPoint v0.6) and v0.3.x (EntryPoint v0.7).
class KernelSmartAccount implements SmartAccountV06, EntryPointVersioned {
  /// Creates a Kernel smart account from the given configuration.
  ///
  /// Prefer using [createKernelSmartAccount] factory function instead
  /// of calling this constructor directly.
  KernelSmartAccount(this._config)
      : _addresses = _config.customAddresses ??
            KernelVersionAddresses.getAddresses(_config.version)!;

  final KernelSmartAccountConfig _config;
  final KernelAddresses _addresses;
  EthereumAddress? _cachedAddress;

  /// Returns the entry point version for this account.
  @override
  EntryPointVersion get entryPointVersion =>
      _config.version.isV2 ? EntryPointVersion.v06 : EntryPointVersion.v07;

  @override
  BigInt get chainId => _config.chainId;

  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  WebAuthnAccountOwner? get _webAuthnOwner => switch (_config.owner) {
        final WebAuthnAccountOwner owner => owner,
        _ => null,
      };

  bool get _isWebAuthn => _webAuthnOwner != null;

  @override
  bool get isWebAuthn => _isWebAuthn;

  EthereumAddress get _validatorAddress {
    if (_isWebAuthn) {
      final webAuthnValidator = _addresses.webAuthnValidator;
      if (webAuthnValidator == null) {
        throw StateError(
          'WebAuthn owner requires webAuthnValidator address. '
          'WebAuthn is only supported on Kernel v0.3.x+',
        );
      }
      return webAuthnValidator;
    }
    return _addresses.ecdsaValidator!;
  }

  @override
  BigInt get nonceKey {
    final userKey = _config.nonceKey ?? BigInt.zero;
    if (_config.version.isV2) {
      if (_isWebAuthn) {
        throw StateError(
          'WebAuthn owners are not supported on Kernel v0.2.x. '
          'Use Kernel v0.3.x or later.',
        );
      }
      // v2: passthrough (permissionless.js getNonceKeyWithEncoding)
      return userKey;
    }

    return encodeKernelV3NonceKey(
      validator: _validatorAddress,
      nonceKey: userKey,
    );
  }

  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Kernel',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  @override
  Future<String> getInitCode() async {
    final factoryData = await getFactoryData();
    return packUserOperationInitCode(
      factory: factoryData?.factory,
      factoryData: factoryData?.factoryData,
    );
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?> getFactoryData() =>
      _config.version.isV2 ? _getFactoryDataV2() : _getFactoryDataV3();

  Future<({EthereumAddress factory, String factoryData})>
      _getFactoryDataV2() async => (
            factory: _addresses.factory,
            factoryData: AbiEncoder.encodeFunctionData(
              kernelV2CreateAccountSignature,
              [
                _addresses.accountImplementation,
                _encodeInitializeV2(),
                _config.index,
              ],
            ),
          );

  Future<({EthereumAddress factory, String factoryData})>
      _getFactoryDataV3() async {
    final initializeCalldata = _encodeInitializeV3();
    final salt = Hex.fromBigInt(_config.index, byteLength: 32);
    if (!_config.useMetaFactory) {
      return (
        factory: _addresses.factory,
        factoryData: AbiEncoder.encodeFunctionData(
          kernelV3CreateAccountSignature,
          [initializeCalldata, salt],
        ),
      );
    }
    return (
      factory: _addresses.metaFactory!,
      factoryData: AbiEncoder.encodeFunctionData(
        kernelDeployWithFactorySignature,
        [_addresses.factory, initializeCalldata, salt],
      ),
    );
  }

  /// `initialize(validator, owner)`: the ECDSA validator's enable data is the
  /// owner address. Falls back to the account implementation when no
  /// validator is configured (backwards compatibility).
  String _encodeInitializeV2() => AbiEncoder.encodeFunctionData(
        kernelV2InitializeSignature,
        [
          _addresses.ecdsaValidator ?? _addresses.accountImplementation,
          _config.owner.address.hex,
        ],
      );

  /// v0.3.x `initialize` with no hook: 0.3.0-beta takes four arguments,
  /// later versions add an empty `bytes[] initConfig`.
  String _encodeInitializeV3() {
    final args = [
      _rootValidatorId,
      zeroAddress,
      _rootValidatorData,
      '0x',
    ];
    return _config.version.usesBetaInitialize
        ? AbiEncoder.encodeFunctionData(kernelV3BetaInitializeSignature, args)
        : AbiEncoder.encodeFunctionData(
            kernelV3InitializeSignature,
            [...args, <String>[]],
          );
  }

  /// Validator data: the owner address for ECDSA; for WebAuthn
  /// `abi.encode((x, y), keccak256(credentialId))`.
  String get _rootValidatorData {
    final webAuthnOwner = _webAuthnOwner;
    if (webAuthnOwner == null) return _config.owner.address.hex;
    return encodeKernelWebAuthnValidatorData(
      x: webAuthnOwner.x,
      y: webAuthnOwner.y,
      credentialId: webAuthnOwner.credentialId,
    );
  }

  /// Root validator identifier `0x01 ‖ validator` (type VALIDATOR, not the
  /// 0x00 ROOT/sudo nonce mode), used by `initialize` and as the ERC-1271
  /// signature prefix.
  String get _rootValidatorId => Hex.concat([
        Hex.fromBigInt(
          BigInt.from(KernelValidatorType.validator),
          byteLength: 1,
        ),
        _validatorAddress.hex,
      ]);

  @override
  String encodeCall(Call call) => _config.version.isV2
      ? encodeKernelV2Execute(call)
      : encode7579Execute(call);

  @override
  String encodeCalls(List<Call> calls) => _config.version.isV2
      ? encodeKernelV2Calls(calls)
      : encodeErc7579AccountCalls(calls);

  @override
  List<Call> decodeCalls(String callData) => _config.version.isV2
      ? decodeKernelV2Calls(callData)
      : decode7579Calls(callData).calls;

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Probes the chain via [isRip7212Supported] when a [PublicClient] is
  /// available, else uses the static chain list.
  Future<bool> _shouldUsePrecompile() async {
    final publicClient = _config.publicClient;
    return publicClient != null
        ? await isRip7212Supported(publicClient)
        : shouldUseP256Precompile(chainId: chainId);
  }

  /// The WebAuthn stub encodes `usePrecompiled: false`: the Solidity P256
  /// verifier is the costlier path, so the estimate covers either encoding
  /// [signUserOperation] may submit (permissionless.js always sends false).
  @override
  String getStubSignature() {
    if (_config.version.isV2) {
      return Hex.concat([kernelV2RootMode, ecdsaStubSignature]);
    }
    if (_isWebAuthn) {
      return getDummyKernelWebAuthnSignature();
    }
    return ecdsaStubSignature;
  }

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = _userOperationHash(userOp);

    final webAuthnOwner = _webAuthnOwner;
    if (webAuthnOwner != null) {
      final usePrecompiled = await _shouldUsePrecompile();
      final sigData = await webAuthnOwner.signP256(userOpHash);
      return encodeKernelWebAuthnSignature(
        sigData,
        usePrecompiled: usePrecompiled,
      );
    }

    // ECDSA: EIP-191 personal_sign over the raw userOpHash (matches
    // permissionless.js owner.signMessage({ message: { raw: hash } })).
    return _config.owner.signPersonalMessage(userOpHash);
  }

  /// Signs a v0.6 UserOperation (for Kernel v0.2.x).
  ///
  /// This method computes the correct hash for EntryPoint v0.6 format
  /// and returns the signature with ROOT_MODE prefix.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    final userOpHash = _userOperationHash(userOp);
    // EIP-191 personal_sign over the raw userOpHash (matches JS).
    final signature = await _config.owner.signPersonalMessage(userOpHash);
    return Hex.concat([kernelV2RootMode, signature]);
  }

  /// Signs a personal message (EIP-191) with Kernel EIP-712 wrapping.
  ///
  /// Returns the signature in the appropriate format for the owner type:
  /// - ECDSA: Kernel-wrapped personal signature, with `0x01‖validator` prefix on v0.3.x
  /// - WebAuthn: ABI-encoded P256 signature over the wrapped digest (same prefix rules)
  ///
  /// On Kernel 0.2.1 / 0.2.2, signs without Kernel wrapping (matches JS).
  @override
  Future<String> signMessage(String message) async {
    final webAuthnOwner = _webAuthnOwner;
    if (webAuthnOwner != null) {
      return _signWebAuthnWithKernelWrapper(
        webAuthnOwner,
        hashMessage(message),
      );
    }
    final signature = await signKernelMessage(
      owner: _config.owner,
      message: message,
      address: await getAddress(),
      version: _config.version,
      chainId: _config.chainId,
    );
    return _prefixKernelErc1271Signature(signature);
  }

  /// Signs EIP-712 typed data with Kernel EIP-712 wrapping.
  ///
  /// Returns the signature in the appropriate format for the owner type:
  /// - ECDSA: Kernel-wrapped personal signature, with `0x01‖validator` prefix on v0.3.x
  /// - WebAuthn: ABI-encoded P256 signature over the wrapped digest (same prefix rules)
  ///
  /// On Kernel 0.2.1 / 0.2.2, signs typed data without Kernel wrapping (matches JS).
  @override
  Future<String> signTypedData(TypedData typedData) async {
    final webAuthnOwner = _webAuthnOwner;
    if (webAuthnOwner != null) {
      return _signWebAuthnWithKernelWrapper(
        webAuthnOwner,
        hashTypedData(typedData),
      );
    }
    final signature = await signKernelTypedData(
      owner: _config.owner,
      typedData: typedData,
      address: await getAddress(),
      version: _config.version,
      chainId: _config.chainId,
    );
    return _prefixKernelErc1271Signature(signature);
  }

  /// WebAuthn ERC-1271 path: wrap via [wrapMessageHash], sign P256, prefix.
  Future<String> _signWebAuthnWithKernelWrapper(
    WebAuthnAccountOwner webAuthnOwner,
    String messageHash,
  ) async {
    final wrappedDigest = wrapMessageHash(
      hash: messageHash,
      address: await getAddress(),
      version: _config.version,
      chainId: _config.chainId,
    );
    final usePrecompiled = await _shouldUsePrecompile();
    final sigData = await webAuthnOwner.signP256(wrappedDigest);
    final signature = encodeKernelWebAuthnSignature(
      sigData,
      usePrecompiled: usePrecompiled,
    );
    return _prefixKernelErc1271Signature(signature);
  }

  /// v0.2.x: unprefixed helper bytes. v0.3.x: `0x01 ‖ validatorAddress`.
  String _prefixKernelErc1271Signature(String signature) => _config.version.isV2
      ? signature
      : Hex.concat([_rootValidatorId, signature]);

  /// Hash of [userOp] as this account's EntryPoint computes it; throws
  /// [ArgumentError] when the layout does not match that EntryPoint version.
  String _userOperationHash(UserOperation userOp) => getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: entryPointVersion,
        chainId: chainId,
      );
}

/// Creates a Kernel smart account.
///
/// Default [version] is [KernelVersion.v0_3_0_beta] (EntryPoint v0.7 default),
/// matching permissionless.js `toKernelSmartAccount`. For EntryPoint v0.6,
/// pass [KernelVersion.v0_2_2] (or another v0.2.x) explicitly — the JS default
/// for EP v0.6 is `0.2.2`.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createKernelSmartAccount(
///   owner: owner,
///   chainId: BigInt.from(11155111),
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Kernel account: $address');
/// ```
KernelSmartAccount createKernelSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_3_0_beta,
  BigInt? index,
  KernelAddresses? customAddresses,
  BigInt? nonceKey,
  bool useMetaFactory = true,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    KernelSmartAccount(
      KernelSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        index: index,
        customAddresses: customAddresses,
        nonceKey: nonceKey,
        useMetaFactory: useMetaFactory,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

/// Creates a Kernel smart account with an ECDSA validator.
///
/// Deprecated alias of [createKernelSmartAccount] that maps
/// [ecdsaValidatorAddress] → custom addresses, matching permissionless.js
/// `toEcdsaKernelSmartAccount`.
@Deprecated('Use createKernelSmartAccount instead')
KernelSmartAccount createEcdsaKernelSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_3_0_beta,
  BigInt? index,
  KernelAddresses? customAddresses,
  EthereumAddress? ecdsaValidatorAddress,
  BigInt? nonceKey,
  bool useMetaFactory = true,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) {
  final base = customAddresses ?? KernelVersionAddresses.getAddresses(version);
  final KernelAddresses? resolved;
  if (ecdsaValidatorAddress != null) {
    if (base == null) {
      throw ArgumentError(
        'No addresses found for Kernel version ${version.value}',
      );
    }
    resolved = KernelAddresses(
      accountImplementation: base.accountImplementation,
      factory: base.factory,
      metaFactory: base.metaFactory,
      ecdsaValidator: ecdsaValidatorAddress,
      webAuthnValidator: base.webAuthnValidator,
    );
  } else {
    resolved = customAddresses;
  }

  return createKernelSmartAccount(
    owner: owner,
    chainId: chainId,
    version: version,
    index: index,
    customAddresses: resolved,
    nonceKey: nonceKey,
    useMetaFactory: useMetaFactory,
    entryPointAddress: entryPointAddress,
    publicClient: publicClient,
    address: address,
  );
}

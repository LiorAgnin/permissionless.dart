import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../webauthn_utils.dart';
import 'constants.dart';

/// Configuration for creating a Kernel v4 ImmutableECDSA smart account.
class KernelImmutableECDSAConfig {
  /// Creates a configuration for a Kernel v4 ImmutableECDSA account.
  ///
  /// - [owner]: A local ECDSA owner; its address is baked into the proxy's
  ///   immutable args and is part of the account's CREATE2 identity
  /// - [chainId]: Chain ID for the network
  /// - [version]: Kernel version (defaults to v0.4.0; non-v4 rejected)
  /// - [index]: Deployment nonce for salt derivation (defaults to 0)
  /// - [nonceKey]: Custom 2-byte parallel nonce key (≤ maxUint16)
  /// - [additionalPackages]: Extra Install packages for creation-time
  ///   initialize; they feed the CREATE2 salt
  /// - [useStaker]: Route deployment through the staked `Staker` wrapper
  ///   (default), or call the `KernelFactory` directly
  /// - [customAddresses]: Override the release v0.4.0 contract addresses
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.9 address
  ///
  /// Throws [ArgumentError] when a requirement is violated, so
  /// misconfiguration fails fast and offline.
  KernelImmutableECDSAConfig({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_4_0,
    BigInt? index,
    this.nonceKey,
    List<KernelV4Install>? additionalPackages,
    this.useStaker = true,
    this.customAddresses,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  })  : index = index ?? BigInt.zero,
        additionalPackages = additionalPackages ?? const [] {
    if (!version.isV4) {
      throw ArgumentError.value(
        version,
        'version',
        'KernelImmutableECDSA is a Kernel v4 account; '
            'use createKernelSmartAccount for v0.2.x / v0.3.x',
      );
    }
    if (isWebAuthnAccount(owner)) {
      throw ArgumentError.value(
        owner,
        'owner',
        'KernelImmutableECDSA requires a local ECDSA owner — the signer '
            'address is embedded in the proxy immutable args. WebAuthn '
            'owners need an external validator module (not yet supported '
            'for Kernel v4)',
      );
    }
    // Delegates the ≤ 2-byte range check (and its error) to the encoder so
    // the rule lives in one place.
    encodeKernelV4NonceKey(nonceKey: nonceKey);
  }

  /// The account owner (local ECDSA; immutable fallback signer).
  final AccountOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Kernel version to use (v4 only).
  final KernelVersion version;

  /// Deployment nonce for CREATE2 salt derivation.
  final BigInt index;

  /// Optional custom 2-byte nonce key for parallel UserOperation streams.
  final BigInt? nonceKey;

  /// Install packages applied at creation (`initialize`).
  ///
  /// For ImmutableECDSA these never become root — the immutable signer is the
  /// root/fallback path — but they are installed and feed the CREATE2 salt.
  final List<KernelV4Install> additionalPackages;

  /// Whether deployment routes through the staked `Staker` wrapper.
  ///
  /// When `true` (default), factory args use
  /// `staker.deployWithFactory(factory, deployECDSA calldata)` — the wrapper
  /// bundlers accept as a staked deployment entity (the factory must be
  /// approved on the Staker). When `false`, factory args call
  /// `factory.deployECDSA(...)` directly, which suits fresh private
  /// deployments without an approval step. The counterfactual address is the
  /// same either way.
  final bool useStaker;

  /// Custom contract addresses (defaults to [KernelV4Addresses.predicted]).
  final KernelV4Addresses? customAddresses;

  /// Optional EntryPoint address override for forked or pre-release
  /// EntryPoint v0.9 deployments.
  final EthereumAddress? entryPointAddress;

  /// Optional public client. Not required — the account address is computed
  /// offline — but kept for parity with the other account configs.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional). Skips local computation.
  final EthereumAddress? address;
}

/// Kernel v4 ImmutableECDSA smart account (Solidity: `KernelImmutableECDSA`).
///
/// An ERC-1967 clone whose ECDSA signer lives in the proxy's immutable args.
/// Root validation is never set at initialization, so root-type UserOperations
/// (`vType 0x00`) fall through to the immutable fallback signer: the
/// signature is the raw 65-byte `r‖s‖v` over the EntryPoint v0.9 userOpHash —
/// no validator prefix; all routing lives in the nonce.
///
/// Targets EntryPoint v0.9 exclusively.
class KernelImmutableECDSA implements SmartAccount {
  /// Creates a Kernel v4 ImmutableECDSA account from the given configuration.
  ///
  /// Prefer the [createKernelImmutableECDSA] factory function.
  KernelImmutableECDSA(this._config)
      : _addresses = _config.customAddresses ?? KernelV4Addresses.predicted;

  final KernelImmutableECDSAConfig _config;
  final KernelV4Addresses _addresses;
  EthereumAddress? _cachedAddress;

  /// The EntryPoint version this account targets — always v0.9 for Kernel v4.
  EntryPointVersion get entryPointVersion => _config.version.entryPointVersion;

  @override
  BigInt get chainId => _config.chainId;

  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ?? EntryPointAddresses.v09;

  @override
  bool get isWebAuthn => false;

  @override
  BigInt get nonceKey => encodeKernelV4NonceKey(nonceKey: _config.nonceKey);

  @override
  Future<EthereumAddress> getAddress() async {
    if (_cachedAddress != null) return _cachedAddress!;
    _cachedAddress = _config.address ??
        computeKernelV4EcdsaAddress(
          signer: _config.owner.address,
          packages: _config.additionalPackages,
          nonce: _config.index,
          factory: _addresses.factory,
          implementation: _addresses.kernelImmutableECDSA,
        );
    return _cachedAddress!;
  }

  @override
  Future<String> getInitCode() async {
    final factoryData = await getFactoryData();
    if (factoryData == null) return '0x';
    return Hex.concat([
      factoryData.factory.hex,
      Hex.strip0x(factoryData.factoryData),
    ]);
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final createData = encodeKernelV4DeployEcdsaCalldata(
      signer: _config.owner.address,
      packages: _config.additionalPackages,
      nonce: _config.index,
    );

    if (!_config.useStaker) {
      return (factory: _addresses.factory, factoryData: createData);
    }

    return (
      factory: _addresses.staker,
      factoryData: encodeKernelV4DeployWithFactoryCalldata(
        factory: _addresses.factory,
        createData: createData,
      ),
    );
  }

  @override
  String encodeCall(Call call) => encode7579Execute(call);

  @override
  String encodeCalls(List<Call> calls) {
    if (calls.isEmpty) {
      throw ArgumentError('At least one call is required');
    }
    if (calls.length == 1) {
      return encodeCall(calls.first);
    }
    return encode7579ExecuteBatch(calls);
  }

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  String getStubSignature() => kernelDummyEcdsaSignature;

  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    final userOpHash = getUserOperationHash(
      userOperation: userOp,
      entryPointAddress: entryPoint,
      entryPointVersion: entryPointVersion,
      chainId: chainId,
    );
    // The contract recovers the signer over the raw EIP-712 userOpHash
    // digest (no EIP-191 personal-message prefix), and the root/fallback
    // signature carries no mode or validator prefix.
    return _config.owner.signRawHash(userOpHash);
  }

  @override
  Future<String> sign(String hash) => throw UnsupportedError(
        'Kernel v4 ERC-1271 signing uses ERC-7739 nested EIP-712 and is not '
        'implemented yet',
      );

  @override
  Future<String> signMessage(String message) => throw UnsupportedError(
        'Kernel v4 ERC-1271 message signing uses ERC-7739 nested EIP-712 and '
        'is not implemented yet',
      );

  @override
  Future<String> signTypedData(TypedData typedData) => throw UnsupportedError(
        'Kernel v4 ERC-1271 typed-data signing uses ERC-7739 nested EIP-712 '
        'and is not implemented yet',
      );
}

/// Creates a Kernel v4 ImmutableECDSA smart account.
///
/// The ECDSA [owner]'s address is embedded in the account proxy's immutable
/// args, so the owner is part of the CREATE2 identity and no validator module
/// is needed for the default signing path. The counterfactual address is
/// computed offline — no RPC round-trip.
///
/// Defaults use the Kernel release v0.4.0 addresses
/// ([KernelV4Addresses.predicted]) and the canonical EntryPoint v0.9. For
/// private or forked deployments pass [customAddresses] (and, if needed,
/// [entryPointAddress]).
///
/// ```dart
/// final account = createKernelImmutableECDSA(
///   owner: PrivateKeyOwner(privateKey),
///   chainId: BigInt.from(11155111),
/// );
/// final address = await account.getAddress(); // offline
/// ```
KernelImmutableECDSA createKernelImmutableECDSA({
  required AccountOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_4_0,
  BigInt? index,
  BigInt? nonceKey,
  List<KernelV4Install>? additionalPackages,
  bool useStaker = true,
  KernelV4Addresses? customAddresses,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    KernelImmutableECDSA(
      KernelImmutableECDSAConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        index: index,
        nonceKey: nonceKey,
        additionalPackages: additionalPackages,
        useStaker: useStaker,
        customAddresses: customAddresses,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

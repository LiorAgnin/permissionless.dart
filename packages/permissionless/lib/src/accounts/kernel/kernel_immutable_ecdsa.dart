import '../../clients/public/public_client.dart';
import '../../types/address.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../account_owner.dart';
import '../webauthn_utils.dart';
import 'constants.dart';
import 'kernel_v4_account.dart';

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
  /// - [validation]: Which validation path UserOperations run under
  ///   (defaults to root — the immutable fallback signer). Non-root paths
  ///   require the module(s) to be installed on the account
  /// - [replayableUserOps]: Set nonce mode `0x40` and sign the
  ///   chain-agnostic digest, so the same signed operation is portable
  ///   across chains
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
    this.validation = const KernelV4Validation.root(),
    this.replayableUserOps = false,
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

  /// The validation path UserOperations run under (root by default).
  final KernelV4Validation validation;

  /// Whether UserOperations carry the replayable mode bit (`0x40`).
  final bool replayableUserOps;

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
class KernelImmutableECDSA extends KernelV4AccountBase {
  /// Creates a Kernel v4 ImmutableECDSA account from the given configuration.
  ///
  /// Prefer the [createKernelImmutableECDSA] factory function.
  KernelImmutableECDSA(this._config)
      : _addresses = _config.customAddresses ?? KernelV4Addresses.predicted;

  final KernelImmutableECDSAConfig _config;
  final KernelV4Addresses _addresses;
  EthereumAddress? _cachedAddress;

  @override
  AccountOwner get owner => _config.owner;

  @override
  KernelVersion get version => _config.version;

  @override
  EthereumAddress? get entryPointOverride => _config.entryPointAddress;

  @override
  BigInt? get customNonceKey => _config.nonceKey;

  @override
  KernelV4Validation get validation => _config.validation;

  @override
  bool get replayableUserOps => _config.replayableUserOps;

  @override
  BigInt get chainId => _config.chainId;

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
  KernelV4Validation validation = const KernelV4Validation.root(),
  bool replayableUserOps = false,
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
        validation: validation,
        replayableUserOps: replayableUserOps,
        additionalPackages: additionalPackages,
        useStaker: useStaker,
        customAddresses: customAddresses,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

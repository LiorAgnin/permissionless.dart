import '../../clients/public/public_client.dart';
import '../../types/address.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../account_owner.dart';
import '../webauthn_utils.dart';
import 'constants.dart';
import 'kernel_v4_account.dart';

/// Configuration for creating a Kernel v4 UUPS smart account.
class KernelUUPSConfig {
  /// Creates a configuration for a Kernel v4 UUPS account.
  ///
  /// - [owner]: A local ECDSA owner; its 20-byte address becomes the root
  ///   validator's `onInstall` data, and thus part of the account's CREATE2
  ///   identity
  /// - [chainId]: Chain ID for the network
  /// - [rootValidator]: Root validator module address (type 1). **Required**
  ///   — Kernel v4 has no published validator deployments, so there is no
  ///   library default. Pass a self-deployed v4 ECDSAValidator, or knowingly
  ///   choose the v3 drop-in `0x845ADb2C…` (enable-mode ERC-1271 limitation)
  /// - [version]: Kernel version (defaults to v0.4.0; non-v4 rejected)
  /// - [index]: Deployment nonce for salt derivation (defaults to 0)
  /// - [nonceKey]: Custom 2-byte parallel nonce key (≤ maxUint16)
  /// - [validation]: Which validation path UserOperations run under
  ///   (defaults to root). Non-root paths require the module(s) to be
  ///   installed on the account
  /// - [replayableUserOps]: Set nonce mode `0x40` and sign the
  ///   chain-agnostic digest, so the same signed operation is portable
  ///   across chains
  /// - [enableMode]: Install modules atomically with the next UserOperation
  ///   (nonce mode `0x08`); pair with a non-root [validation] to use the
  ///   module being installed in the same operation
  /// - [additionalPackages]: Extra Install packages after the root
  ///   (packages[1…] of `initialize`); they feed the CREATE2 salt
  /// - [useStaker]: Route deployment through the staked `Staker` wrapper
  ///   (default), or call the `KernelFactory` directly
  /// - [customAddresses]: Override the release v0.4.0 contract addresses
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.9 address
  ///
  /// Throws [ArgumentError] when a requirement is violated, so
  /// misconfiguration fails fast and offline.
  KernelUUPSConfig({
    required this.owner,
    required this.chainId,
    required this.rootValidator,
    this.version = KernelVersion.v0_4_0,
    BigInt? index,
    this.nonceKey,
    this.validation = const KernelV4Validation.root(),
    this.replayableUserOps = false,
    this.enableMode,
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
        'KernelUUPS is a Kernel v4 account; '
            'use createKernelSmartAccount for v0.2.x / v0.3.x',
      );
    }
    if (isWebAuthnAccount(owner)) {
      throw ArgumentError.value(
        owner,
        'owner',
        'KernelUUPS synthesizes the root install data as the 20-byte owner '
            'address — an ECDSA-validator encoding. WebAuthn owners only '
            'have a derived placeholder address, so the account would be '
            'permanently broken (the moduleData is part of the CREATE2 '
            'identity). Kernel v4 WebAuthn root support is not available '
            'yet',
      );
    }
    // Delegates the ≤ 2-byte range check (and its error) to the encoder so
    // the rule lives in one place.
    encodeKernelV4NonceKey(nonceKey: nonceKey);
  }

  /// The account owner (local ECDSA; registered with the root validator).
  final AccountOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Root validator module address — packages[0] of `initialize`.
  final EthereumAddress rootValidator;

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

  /// Enable-mode configuration (`null` for plain operations).
  final KernelV4EnableMode? enableMode;

  /// Install packages applied after the root at creation (packages[1…] of
  /// `initialize`). They feed the CREATE2 salt.
  final List<KernelV4Install> additionalPackages;

  /// Whether deployment routes through the staked `Staker` wrapper.
  ///
  /// When `true` (default), factory args use
  /// `staker.deployWithFactory(factory, deploy calldata)` — the wrapper
  /// bundlers accept as a staked deployment entity (the factory must be
  /// approved on the Staker). When `false`, factory args call
  /// `factory.deploy(...)` directly, which suits fresh private deployments
  /// without an approval step. The counterfactual address is the same either
  /// way.
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

/// Kernel v4 UUPS smart account (Solidity: `KernelUUPS`).
///
/// A UUPS-upgradeable ERC-1967 proxy deployed by the `KernelFactory`. The
/// root validator is packages[0] of `initialize` — this account synthesizes
/// it from [KernelUUPSConfig.rootValidator] and the owner's 20-byte address
/// as `onInstall` data, so the owner is part of the CREATE2 identity via the
/// salt (not via immutable args, as in `KernelImmutableECDSA`).
///
/// Root-type UserOperations (`vType 0x00`) route to that validator: the
/// signature is the raw 65-byte `r‖s‖v` over the EntryPoint v0.9 userOpHash —
/// no validator prefix; all routing lives in the nonce.
///
/// Targets EntryPoint v0.9 exclusively.
class KernelUUPS extends KernelV4AccountBase {
  /// Creates a Kernel v4 UUPS account from the given configuration.
  ///
  /// Prefer the [createKernelUUPS] factory function.
  KernelUUPS(this._config)
      : _addresses = _config.customAddresses ?? KernelV4Addresses.predicted;

  final KernelUUPSConfig _config;
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
  KernelV4EnableMode? get enableMode => _config.enableMode;

  @override
  BigInt get chainId => _config.chainId;

  /// The full `initialize` package list: the synthesized root install
  /// followed by the caller's extras.
  List<KernelV4Install> get _packages => [
        KernelV4Install(
          moduleType: BigInt.one,
          module: _config.rootValidator,
          moduleData: _config.owner.address.hex,
        ),
        ..._config.additionalPackages,
      ];

  @override
  Future<EthereumAddress> getAddress() async {
    if (_cachedAddress != null) return _cachedAddress!;
    _cachedAddress = _config.address ??
        computeKernelV4UupsAddress(
          packages: _packages,
          nonce: _config.index,
          factory: _addresses.factory,
          implementation: _addresses.kernelUUPS,
        );
    return _cachedAddress!;
  }

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async {
    final createData = encodeKernelV4DeployCalldata(
      packages: _packages,
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

/// Creates a Kernel v4 UUPS smart account.
///
/// The root validator is packages[0] of the factory `initialize` call,
/// synthesized from [rootValidator] and the ECDSA [owner]'s 20-byte address
/// as `onInstall` data. Both feed the CREATE2 salt, so the owner and
/// validator are part of the account's identity. The counterfactual address
/// is computed offline — no RPC round-trip.
///
/// [rootValidator] is **required**: Kernel v4 ships no published validator
/// deployments, so there is no safe library default. Pass a self-deployed v4
/// ECDSAValidator, or knowingly choose the v3 drop-in
/// `0x845ADb2C711129d4f3966735eD98a9F09fC4cE57` (it lacks type-10 stateless
/// validation, which breaks enable-mode ERC-1271 — fine for basic root
/// flows).
///
/// Defaults use the Kernel release v0.4.0 addresses
/// ([KernelV4Addresses.predicted]) and the canonical EntryPoint v0.9. For
/// private or forked deployments pass [customAddresses] (and, if needed,
/// [entryPointAddress]).
///
/// ```dart
/// final account = createKernelUUPS(
///   owner: PrivateKeyOwner(privateKey),
///   chainId: BigInt.from(11155111),
///   rootValidator: myEcdsaValidator, // required — no default yet
/// );
/// final address = await account.getAddress(); // offline
/// ```
KernelUUPS createKernelUUPS({
  required AccountOwner owner,
  required BigInt chainId,
  required EthereumAddress rootValidator,
  KernelVersion version = KernelVersion.v0_4_0,
  BigInt? index,
  BigInt? nonceKey,
  KernelV4Validation validation = const KernelV4Validation.root(),
  bool replayableUserOps = false,
  KernelV4EnableMode? enableMode,
  List<KernelV4Install>? additionalPackages,
  bool useStaker = true,
  KernelV4Addresses? customAddresses,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    KernelUUPS(
      KernelUUPSConfig(
        owner: owner,
        chainId: chainId,
        rootValidator: rootValidator,
        version: version,
        index: index,
        nonceKey: nonceKey,
        validation: validation,
        replayableUserOps: replayableUserOps,
        enableMode: enableMode,
        additionalPackages: additionalPackages,
        useStaker: useStaker,
        customAddresses: customAddresses,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

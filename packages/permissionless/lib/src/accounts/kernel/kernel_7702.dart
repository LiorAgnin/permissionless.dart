import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/kernel_v4/kernel_v4.dart';
import '../account_owner.dart';
import 'constants.dart';
import 'eip7702_kernel_account.dart';
import 'kernel_v4_account.dart';

/// Configuration for creating a Kernel v4 EIP-7702 smart account.
class Kernel7702Config {
  /// Creates a configuration for a Kernel7702 account.
  ///
  /// - [owner]: The EOA owner. Its address *is* the account address, and it
  ///   signs UserOperations, ERC-1271 digests, and EIP-7702 authorizations
  /// - [chainId]: Chain ID for the network
  /// - [version]: Kernel version (defaults to v0.4.0; non-v4 rejected)
  /// - [nonceKey]: Custom 2-byte parallel nonce key (≤ maxUint16)
  /// - [validation]: Which validation path UserOperations run under
  ///   (defaults to root — the EOA fallback signer). Non-root paths require
  ///   the module(s) to be installed after delegation
  /// - [replayableUserOps]: Set nonce mode `0x40` and sign the
  ///   chain-agnostic digest, so the same signed operation is portable
  ///   across chains
  /// - [enableMode]: Install modules atomically with the next UserOperation
  ///   (nonce mode `0x08`); pair with a non-root [validation] to use the
  ///   module being installed in the same operation
  /// - [customAddresses]: Override the release v0.4.0 contract addresses;
  ///   must carry a `kernel7702` implementation (the delegation target)
  /// - [entryPointAddress]: Override the canonical EntryPoint v0.9 address
  /// - [publicClient]: Optional; when present, ERC-1271 signing first checks
  ///   the EOA actually carries delegated code (a bare EOA cannot answer
  ///   `isValidSignature`)
  ///
  /// Throws [ArgumentError] when a requirement is violated, so
  /// misconfiguration fails fast and offline.
  Kernel7702Config({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_4_0,
    this.nonceKey,
    this.validation = const KernelV4Validation.root(),
    this.replayableUserOps = false,
    this.enableMode,
    this.customAddresses,
    this.entryPointAddress,
    this.publicClient,
  }) {
    if (!version.isV4) {
      throw ArgumentError.value(
        version,
        'version',
        'Kernel7702 is a Kernel v4 account; '
            'use createEip7702KernelSmartAccount for v0.3.3',
      );
    }
    if (customAddresses != null && customAddresses!.kernel7702 == null) {
      throw ArgumentError.value(
        customAddresses,
        'customAddresses',
        'Kernel7702 needs a kernel7702 implementation address — it is the '
            'EIP-7702 delegation target',
      );
    }
    // Delegates the ≤ 2-byte range check (and its error) to the encoder so
    // the rule lives in one place.
    encodeKernelV4NonceKey(nonceKey: nonceKey);
  }

  /// The EOA owner (account address, root signer, authorization signer).
  final Eip7702KernelOwner owner;

  /// Chain ID for the network.
  final BigInt chainId;

  /// Kernel version to use (v4 only).
  final KernelVersion version;

  /// Optional custom 2-byte nonce key for parallel UserOperation streams.
  final BigInt? nonceKey;

  /// The validation path UserOperations run under (root by default).
  final KernelV4Validation validation;

  /// Whether UserOperations carry the replayable mode bit (`0x40`).
  final bool replayableUserOps;

  /// Enable-mode configuration (`null` for plain operations).
  final KernelV4EnableMode? enableMode;

  /// Custom contract addresses (defaults to [KernelV4Addresses.predicted]).
  final KernelV4Addresses? customAddresses;

  /// Optional EntryPoint address override for forked or pre-release
  /// EntryPoint v0.9 deployments.
  final EthereumAddress? entryPointAddress;

  /// Public client for checking delegation status before ERC-1271 signing.
  final PublicClient? publicClient;
}

/// Kernel v4 EIP-7702 smart account (Solidity: `Kernel7702`).
///
/// The EOA delegates its code to the `Kernel7702` implementation via an
/// EIP-7702 authorization, so:
///
/// - **Account address = EOA address** — no factory, no CREATE2, no deploy;
///   `initialize` on the implementation is a no-op.
/// - **The EOA is the fallback signer**: root-type UserOperations
///   (`vType 0x00`) carry the raw 65-byte `r‖s‖v` over the EntryPoint v0.9
///   userOpHash, recovered against the EOA itself.
/// - **Raw ERC-1271 is allowed** (unique to this variant): a bare 65-byte
///   EOA signature over the verifying app's hash validates without the
///   ERC-7739 nesting — see [signErc1271Raw]. The nested paths of the other
///   v4 accounts ([sign], [signMessage], [signTypedData]) also work.
/// - **Modules install after delegation** through the same
///   `KernelV4ModuleActions` / enable-mode paths as the factory accounts.
///
/// Targets EntryPoint v0.9 exclusively.
class Kernel7702 extends KernelV4AccountBase implements Eip7702SmartAccount {
  /// Creates a Kernel7702 account from the given configuration.
  ///
  /// Prefer the [createKernel7702] factory function.
  Kernel7702(this._config)
      : _addresses = _config.customAddresses ?? KernelV4Addresses.predicted,
        _owner = _Eip7702OwnerAdapter(_config.owner);

  final Kernel7702Config _config;
  final KernelV4Addresses _addresses;
  final _Eip7702OwnerAdapter _owner;

  /// The EIP-7702 owner (the EOA behind this account).
  Eip7702KernelOwner get eip7702Owner => _config.owner;

  @override
  AccountOwner get owner => _owner;

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

  @override
  bool get isEip7702 => true;

  /// The `Kernel7702` implementation the EOA delegates its code to.
  @override
  EthereumAddress get accountLogicAddress => _addresses.kernel7702!;

  /// The account address — always the owner's EOA address.
  @override
  Future<EthereumAddress> getAddress() async => _config.owner.address;

  /// EIP-7702 accounts have no factory; delegation replaces deployment.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => null;

  /// Creates the EIP-7702 authorization delegating the EOA to
  /// [accountLogicAddress].
  ///
  /// [nonce] must be the EOA's current *transaction* nonce (not the ERC-4337
  /// nonce). Include the authorization with the first UserOperation — the
  /// smart-account client does this automatically when the account carries
  /// no code yet.
  @override
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce}) =>
      _config.owner.createAuthorization(
        chainId: chainId,
        contractAddress: accountLogicAddress,
        nonce: nonce,
      );

  /// For operations carrying the `0x7702` factory marker, the EntryPoint
  /// hashes with `initCode = delegate ‖ factoryData` — so the signed digest
  /// must substitute the implementation address the same way.
  @override
  EthereumAddress? delegationFor(UserOperationV07 userOp) =>
      isEip7702FactoryMarker(userOp.factory) ? accountLogicAddress : null;

  /// Signs [hash] for the **raw** ERC-1271 path — a bare 65-byte EOA
  /// signature over the verifying app's hash, no `[vMode | vType]` prefix
  /// and no ERC-7739 wrap.
  ///
  /// Only `Kernel7702` validates this shape (`_erc1271RawAllowed` is false
  /// on the factory-deployed accounts). Prefer the nested [sign] /
  /// [signTypedData] flow when the verifying app supports ERC-7739 — the
  /// nesting is what scopes a signature to one app; a raw signature over an
  /// attacker-chosen "hash" is as powerful as the EOA key itself.
  Future<String> signErc1271Raw(String hash) async {
    await _ensureDelegatedForErc1271();
    return _config.owner.signHash(hash);
  }

  @override
  Future<String> sign(String hash) async {
    await _ensureDelegatedForErc1271();
    return super.sign(hash);
  }

  @override
  Future<String> signTypedData(TypedData typedData) async {
    await _ensureDelegatedForErc1271();
    return super.signTypedData(typedData);
  }

  @override
  Future<String> signTypedDataReplayable(TypedData typedData) async {
    await _ensureDelegatedForErc1271();
    return super.signTypedDataReplayable(typedData);
  }

  /// Before delegation the EOA has no code, so no on-chain verifier can
  /// accept any ERC-1271 signature it produces — and under a delegation to a
  /// *different* implementation, `isValidSignature` runs that contract's
  /// logic, not Kernel7702's. With a [PublicClient] configured, fail loudly
  /// in both cases instead of handing out a signature that cannot verify.
  Future<void> _ensureDelegatedForErc1271() async {
    final client = _config.publicClient;
    if (client == null) return;
    final code = (await client.getCode(_config.owner.address)).toLowerCase();
    final expected =
        '0xef0100${Hex.strip0x(accountLogicAddress.hex).toLowerCase()}';
    if (code == expected) return;
    if (code == '0x' || code.isEmpty) {
      throw StateError(
        'Kernel7702 is not ERC-1271 capable before delegation. Submit a '
        'UserOperation with the EIP-7702 authorization first.',
      );
    }
    throw StateError(
      'Kernel7702 ERC-1271 signatures cannot verify: the EOA code is not an '
      'EIP-7702 delegation to the Kernel7702 implementation '
      '(${accountLogicAddress.hex}); on-chain code: $code.',
    );
  }
}

/// Adapts an [Eip7702KernelOwner] to the [AccountOwner] surface the shared
/// Kernel v4 base signs through. Kernel v4 signs raw digests everywhere, so
/// [signRawHash] → `signHash` is the load-bearing mapping.
class _Eip7702OwnerAdapter implements AccountOwner {
  const _Eip7702OwnerAdapter(this._inner);

  final Eip7702KernelOwner _inner;

  @override
  String get type => OwnerType.local;

  @override
  EthereumAddress get address => _inner.address;

  @override
  Future<String> signRawHash(String hash) => _inner.signHash(hash);

  @override
  Future<String> signTypedData(TypedData typedData) =>
      _inner.signTypedData(typedData);

  @override
  Future<String> signPersonalMessage(String hash) {
    // Unused by the Kernel v4 signing paths, implemented for interface
    // completeness: EIP-191 over the raw 32-byte hash, then a raw sign.
    final hashBytes = Hex.decode(hash);
    final prefixBytes = '\x19Ethereum Signed Message:\n32'.codeUnits;
    final combined = Uint8List.fromList([...prefixBytes, ...hashBytes]);
    return _inner.signHash(Hex.fromBytes(keccak256(combined)));
  }
}

/// Creates a Kernel v4 EIP-7702 smart account.
///
/// The account address is the [owner]'s EOA address; an EIP-7702
/// authorization ([Kernel7702.getAuthorization]) delegates the EOA's code to
/// the `Kernel7702` implementation instead of deploying a proxy. The EOA is
/// the account's fallback signer, so no validator module is needed for the
/// default signing path, and modules can be installed after delegation via
/// the ordinary Kernel v4 module actions.
///
/// Defaults use the Kernel release v0.4.0 implementation address
/// ([KernelV4Addresses.predicted]) and the canonical EntryPoint v0.9. For
/// private or forked deployments pass [customAddresses] (which must carry a
/// `kernel7702` implementation) and, if needed, [entryPointAddress].
///
/// ```dart
/// final account = createKernel7702(
///   owner: PrivateKeyEip7702KernelOwner('0x...'),
///   chainId: BigInt.from(11155111),
/// );
/// final address = await account.getAddress(); // == the EOA address
/// final auth = await account.getAuthorization(nonce: eoaNonce);
/// ```
Kernel7702 createKernel7702({
  required Eip7702KernelOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_4_0,
  BigInt? nonceKey,
  KernelV4Validation validation = const KernelV4Validation.root(),
  bool replayableUserOps = false,
  KernelV4EnableMode? enableMode,
  KernelV4Addresses? customAddresses,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
}) =>
    Kernel7702(
      Kernel7702Config(
        owner: owner,
        chainId: chainId,
        version: version,
        nonceKey: nonceKey,
        validation: validation,
        replayableUserOps: replayableUserOps,
        enableMode: enableMode,
        customAddresses: customAddresses,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
      ),
    );

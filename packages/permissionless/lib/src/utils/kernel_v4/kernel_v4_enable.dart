import 'dart:convert';

import 'package:web3dart/web3dart.dart' show keccak256;

import '../../accounts/account_owner.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../encoding.dart';
import 'kernel_v4_erc7739.dart';
import 'kernel_v4_install.dart';

/// `keccak256("InstallPackages(uint256 nonce,Install[] packages)Install(uint256 moduleType,address module,bytes moduleData,bytes internalData)")`
/// — the EIP-712 typehash of the struct a Kernel v4 root signs to authorize
/// an enable-mode install (`INSTALL_PACKAGES_STRUCT_HASH`,
/// kernel/src/types/Constants.sol).
final String kernelV4InstallPackagesTypeHash = Hex.fromBytes(
  keccak256(
    ascii.encode(
      'InstallPackages(uint256 nonce,Install[] packages)Install(uint256 '
      'moduleType,address module,bytes moduleData,bytes internalData)',
    ),
  ),
);

/// `keccak256("Install(uint256 moduleType,address module,bytes moduleData,bytes internalData)")`
/// — the per-package EIP-712 typehash (`INSTALL_STRUCT_HASH`).
final String kernelV4InstallTypeHash = Hex.fromBytes(
  keccak256(
    ascii.encode(
      'Install(uint256 moduleType,address module,bytes moduleData,bytes internalData)',
    ),
  ),
);

String _keccakConcat(List<String> words) =>
    Hex.fromBytes(keccak256(Hex.decode(Hex.concat(words))));

/// The EIP-712 hash of an `Install[]` array: keccak of the concatenated
/// per-package struct hashes (`ModuleManager._installHash`).
String _installArrayHash(List<KernelV4Install> packages) => _keccakConcat([
      for (final pkg in packages)
        _keccakConcat([
          kernelV4InstallTypeHash,
          Hex.fromBigInt(pkg.moduleType, byteLength: 32),
          AbiEncoder.encodeAddress(pkg.module),
          Hex.fromBytes(keccak256(Hex.decode(pkg.moduleData))),
          Hex.fromBytes(keccak256(Hex.decode(pkg.internalData))),
        ]),
    ]);

/// Computes the `InstallPackages` digest a Kernel v4 root signs to authorize
/// installing [packages] — the enable-mode `enableSignature` payload, and the
/// digest behind `setRoot`-style install authorizations.
///
/// The digest is EIP-712 over the **account's** domain (`"Kernel"` /
/// `"0.4.0"`, verifyingContract = [accountAddress]) — not the EntryPoint's:
///
/// ```text
/// structHash = keccak( INSTALL_PACKAGES_TYPEHASH ‖ bytes32(installNonce) ‖
///                      keccak(pkgStructHash_0 ‖ …) )
/// digest     = keccak( 0x1901 ‖ domainSeparator ‖ structHash )
/// ```
///
/// [installNonce] is Kernel's internal install nonce (`kernel.nonce(key)`,
/// zero for a fresh account) — not the EntryPoint nonce.
///
/// With [replayable] set (nonce mode bit `0x04`, enable-replayable) the
/// domain drops its chainId field, making the same signed authorization
/// portable across chains; [chainId] is then unused and may be omitted.
/// Otherwise [chainId] is required and binds the signature to one chain.
String getKernelV4InstallPackagesDigest({
  required EthereumAddress accountAddress,
  required BigInt installNonce,
  required List<KernelV4Install> packages,
  BigInt? chainId,
  bool replayable = false,
}) {
  // A missing chainId on the chain-bound path throws ArgumentError inside
  // getKernelV4DomainSeparator.
  final structHash = _keccakConcat([
    kernelV4InstallPackagesTypeHash,
    Hex.fromBigInt(installNonce, byteLength: 32),
    _installArrayHash(packages),
  ]);
  final domainSeparator = getKernelV4DomainSeparator(
    accountAddress: accountAddress,
    chainId: chainId,
    sansChainId: replayable,
  );
  return _keccakConcat(['0x1901', domainSeparator, structHash]);
}

/// ABI-encodes the Kernel v4 `EnableModeSignature` struct — the
/// `userOp.signature` when the nonce carries the enable mode bit (`0x08`):
///
/// ```text
/// abi.encode(uint256 nonce, Install[] packages,
///            bytes enableSignature, bytes userOpSignature)
/// ```
///
/// The tuple encoding starts directly at the head (no extra wrapper offset
/// word) — Kernel casts the signature calldata to the struct in place.
///
/// - [installNonce]: Kernel's internal install nonce (see
///   [getKernelV4InstallPackagesDigest])
/// - [packages]: The modules installed atomically with this operation
/// - [enableSignature]: The root's signature over the InstallPackages digest
/// - [userOpSignature]: The inner signature the validation path in the nonce
///   expects (for a validator: the module owner's raw 65-byte signature over
///   the userOpHash)
String encodeKernelV4EnableModeSignature({
  required BigInt installNonce,
  required List<KernelV4Install> packages,
  required String enableSignature,
  required String userOpSignature,
}) {
  final packagesTail = encodeKernelV4InstallArray(packages);
  final enableTail = AbiEncoder.encodeBytes(enableSignature);
  const packagesOffset = 4 * 32; // the head: nonce + three offset words

  final enableOffset = packagesOffset + Hex.byteLength(packagesTail);
  final userOpOffset = enableOffset + Hex.byteLength(enableTail);
  return Hex.concat([
    Hex.fromBigInt(installNonce, byteLength: 32),
    AbiEncoder.encodeUint256(BigInt.from(packagesOffset)),
    AbiEncoder.encodeUint256(BigInt.from(enableOffset)),
    AbiEncoder.encodeUint256(BigInt.from(userOpOffset)),
    Hex.strip0x(packagesTail),
    Hex.strip0x(enableTail),
    Hex.strip0x(AbiEncoder.encodeBytes(userOpSignature)),
  ]);
}

/// Configuration for a Kernel v4 enable-mode UserOperation: install
/// [packages] atomically with the operation (nonce mode bit `0x08`).
///
/// The account's root signs the [getKernelV4InstallPackagesDigest] of the
/// packages; the operation itself is validated by whatever validation path
/// the nonce routes to — typically the validator or permission being
/// installed here, so a module works from its very first operation.
///
/// Enable mode is a one-shot authorization: an account configured with it
/// attaches the enable payload to **every** operation it signs, and the
/// Kernel consumes the [installNonce] on the first — a second identical
/// operation reverts on install-nonce replay. Once the install has landed,
/// switch to an account configured without `enableMode` (the module is now
/// installed and the plain validation path applies).
class KernelV4EnableMode {
  /// Creates an enable-mode configuration.
  ///
  /// - [packages]: The modules to install; must be non-empty
  /// - [installNonce]: Kernel's internal install nonce (`kernel.nonce(key)`),
  ///   zero (the default) for an account that has never used enable mode
  /// - [replayableEnableSignature]: Sign the sans-chainId install digest
  ///   (nonce mode bit `0x04`), so one authorization covers every chain
  /// - [rootOwner]: The key that signs the install digest, when it differs
  ///   from the account's owner
  KernelV4EnableMode({
    required this.packages,
    BigInt? installNonce,
    this.replayableEnableSignature = false,
    this.rootOwner,
  }) : installNonce = installNonce ?? BigInt.zero {
    if (packages.isEmpty) {
      throw ArgumentError.value(
        packages,
        'packages',
        'enable mode installs at least one module',
      );
    }
  }

  /// The modules installed atomically with the operation.
  final List<KernelV4Install> packages;

  /// Kernel's internal install nonce for replay protection.
  final BigInt installNonce;

  /// Whether the enable signature uses the chain-agnostic domain (`0x04`).
  final bool replayableEnableSignature;

  /// The root key that authorizes the install, when it is not the account's
  /// configured owner.
  ///
  /// Only the account's root can sign the InstallPackages digest. When
  /// enable mode installs a validator for a *new* key (a session key, a
  /// passkey validator, …), the account is configured with that new key as
  /// its owner — it signs the operations — and the root key signs only the
  /// install authorization here. Left `null`, the account's owner signs
  /// both, which is the single-key flow.
  ///
  /// Note: the account classes derive their counterfactual address from
  /// their owner, so a two-key setup on an existing account should also pass
  /// the account's known `address`.
  final AccountOwner? rootOwner;
}

import 'package:web3dart/web3dart.dart';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../encoding.dart';

/// One ERC-7579 install package for Kernel v4 (Solidity struct
/// `Install{uint256 moduleType, address module, bytes moduleData, bytes internalData}`).
///
/// Used for factory deployment (`deploy` / `deployECDSA` initial packages),
/// CREATE2 salt derivation, and — in later slices — batch installs and enable
/// mode.
class KernelV4Install {
  /// Creates an install package.
  ///
  /// - [moduleType]: ERC-7579 module type id (1 validator, 2 executor,
  ///   3 fallback, 4 hook, 5 policy, 6 signer)
  /// - [module]: The module contract address
  /// - [moduleData]: Data passed to the module's `onInstall`
  /// - [internalData]: Kernel-internal config (hook / selector bindings),
  ///   defaults to empty
  KernelV4Install({
    required this.moduleType,
    required this.module,
    required this.moduleData,
    this.internalData = '0x',
  }) {
    if (moduleType <= BigInt.zero) {
      throw ArgumentError.value(
        moduleType,
        'moduleType',
        'Kernel v4 module types are positive '
            '(1 validator, 2 executor, 3 fallback, 4 hook, 5 policy, 6 signer)',
      );
    }
  }

  /// ERC-7579 module type id.
  final BigInt moduleType;

  /// Module contract address.
  final EthereumAddress module;

  /// `onInstall` data for the module (hex).
  final String moduleData;

  /// Kernel-internal install config (hex).
  final String internalData;
}

/// Function selectors for the Kernel v4 factory contracts.
class KernelV4Selectors {
  KernelV4Selectors._();

  /// `deploy((uint256,address,bytes,bytes)[],uint256)` = 0x0609747b
  static const String deploy = '0x0609747b';

  /// `getAddress((uint256,address,bytes,bytes)[],uint256)` = 0x0e027ecd
  static const String getAddress = '0x0e027ecd';

  /// `deployECDSA(address,(uint256,address,bytes,bytes)[],uint256)` = 0xab03a058
  static const String deployEcdsa = '0xab03a058';

  /// `getECDSAAddress(address,(uint256,address,bytes,bytes)[],uint256)` = 0xdde411f2
  static const String getEcdsaAddress = '0xdde411f2';

  /// Staker: `deployWithFactory(address,bytes)` = 0x16077799
  static const String deployWithFactory = '0x16077799';
}

/// Computes the Kernel v4 factory CREATE2 salt for [packages] and [nonce].
///
/// Byte-for-byte `KernelFactory._calculateSalt`:
///
/// ```text
/// pkgHash_i = keccak( bytes32(moduleType) ‖ bytes32(uint160(module)) ‖
///                     keccak(moduleData) ‖ keccak(internalData) )
/// salt      = keccak( bytes32(nonce) ‖ pkgHash_0 ‖ … ‖ pkgHash_n-1 )
/// ```
///
/// The ECDSA signer is deliberately absent: for `KernelImmutableECDSA` it
/// lives in the proxy's immutable args (and thus the initcode hash), not the
/// salt.
String computeKernelV4Salt({
  required List<KernelV4Install> packages,
  required BigInt nonce,
}) {
  final words = <String>[Hex.fromBigInt(nonce, byteLength: 32)];
  for (final pkg in packages) {
    final packageHash = keccak256(
      Hex.decode(
        Hex.concat([
          Hex.fromBigInt(pkg.moduleType, byteLength: 32),
          AbiEncoder.encodeAddress(pkg.module),
          Hex.fromBytes(keccak256(Hex.decode(pkg.moduleData))),
          Hex.fromBytes(keccak256(Hex.decode(pkg.internalData))),
        ]),
      ),
    );
    words.add(Hex.fromBytes(packageHash));
  }
  return Hex.fromBytes(keccak256(Hex.decode(Hex.concat(words))));
}

/// ABI-encodes an `Install[]` value (length word, element offsets, elements),
/// without the leading offset word of an enclosing head.
String _encodeInstallArrayTail(List<KernelV4Install> packages) {
  final elements = packages.map(_encodeInstallElement).toList();

  final offsets = <String>[];
  var offset = packages.length * 32;
  for (final element in elements) {
    offsets.add(AbiEncoder.encodeUint256(BigInt.from(offset)));
    offset += Hex.byteLength(element);
  }

  return Hex.concat([
    AbiEncoder.encodeUint256(BigInt.from(packages.length)),
    ...offsets,
    ...elements,
  ]);
}

/// ABI-encodes one `Install` struct (dynamic tuple).
String _encodeInstallElement(KernelV4Install pkg) {
  final moduleData = AbiEncoder.encodeBytes(pkg.moduleData);
  const headSize = 4 * 32;
  return Hex.concat([
    Hex.fromBigInt(pkg.moduleType, byteLength: 32),
    AbiEncoder.encodeAddress(pkg.module),
    AbiEncoder.encodeUint256(BigInt.from(headSize)),
    AbiEncoder.encodeUint256(
      BigInt.from(headSize + Hex.byteLength(moduleData)),
    ),
    Hex.strip0x(moduleData),
    Hex.strip0x(AbiEncoder.encodeBytes(pkg.internalData)),
  ]);
}

/// Calldata for `KernelFactory.deploy(initialPackages, nonce)` — the UUPS
/// deployment path, where packages[0] becomes the root validator.
///
/// This is the `factoryData` a first `KernelUUPS` UserOperation carries
/// (directly, or wrapped via [encodeKernelV4DeployWithFactoryCalldata]).
String encodeKernelV4DeployCalldata({
  required List<KernelV4Install> packages,
  required BigInt nonce,
}) =>
    Hex.concat([
      KernelV4Selectors.deploy,
      AbiEncoder.encodeUint256(BigInt.from(2 * 32)), // offset to packages
      AbiEncoder.encodeUint256(nonce),
      Hex.strip0x(_encodeInstallArrayTail(packages)),
    ]);

/// Calldata for `KernelFactory.deployECDSA(signer, initialPackages, nonce)`.
///
/// This is the `factoryData` a first UserOperation carries (directly, or
/// wrapped via [encodeKernelV4DeployWithFactoryCalldata]).
String encodeKernelV4DeployEcdsaCalldata({
  required EthereumAddress signer,
  required List<KernelV4Install> packages,
  required BigInt nonce,
}) =>
    Hex.concat([
      KernelV4Selectors.deployEcdsa,
      AbiEncoder.encodeAddress(signer),
      AbiEncoder.encodeUint256(BigInt.from(3 * 32)), // offset to packages
      AbiEncoder.encodeUint256(nonce),
      Hex.strip0x(_encodeInstallArrayTail(packages)),
    ]);

/// Calldata for `Staker.deployWithFactory(factory, createData)`.
///
/// The Staker is the staked deployment entity for Kernel v4 (successor of the
/// v3 meta factory); it forwards [createData] to the approved [factory], so
/// counterfactual addresses are unchanged by this wrapper.
String encodeKernelV4DeployWithFactoryCalldata({
  required EthereumAddress factory,
  required String createData,
}) =>
    Hex.concat([
      KernelV4Selectors.deployWithFactory,
      AbiEncoder.encodeAddress(factory),
      AbiEncoder.encodeUint256(BigInt.from(2 * 32)), // offset to createData
      Hex.strip0x(AbiEncoder.encodeBytes(createData)),
    ]);

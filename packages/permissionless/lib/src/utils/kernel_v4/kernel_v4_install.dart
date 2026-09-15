import 'package:web3dart/web3dart.dart';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../encoding.dart';

/// Kernel v4 hook sentinel addresses used inside module `internalData`
/// (`HOOK_MODULE_NOT_INSTALLED` / `HOOK_MODULE_INSTALLED_NO_HOOK`,
/// kernel/src/types/Constants.sol).
///
/// For validation-typed installs (validators and permission signers) and
/// executors, both sentinels mean "no hook" — the Kernel normalizes
/// [notInstalled] to [installedNoHook] in storage. For fallback installs the
/// two differ: [notInstalled] restricts the selector to EntryPoint callers,
/// [installedNoHook] lets anyone call it (both without a hook).
class KernelV4HookSentinels {
  KernelV4HookSentinels._();

  /// `address(0)` — no hook; for fallback selectors: EntryPoint-only.
  static final EthereumAddress notInstalled =
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000');

  /// `address(1)` — installed with no hook; for fallback selectors: callable
  /// by anyone.
  static final EthereumAddress installedNoHook =
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001');
}

/// One ERC-7579 install package for Kernel v4 (Solidity struct
/// `Install{uint256 moduleType, address module, bytes moduleData, bytes internalData}`).
///
/// Used for factory deployment (`deploy` / `deployECDSA` initial packages),
/// CREATE2 salt derivation, batch installs, enable mode, and the
/// `installModule` / `setRoot` module-management calldata encoders.
///
/// The typed constructors ([KernelV4Install.validator],
/// [KernelV4Install.executor], [KernelV4Install.fallbackHandler],
/// [KernelV4Install.hook], [KernelV4Install.policy],
/// [KernelV4Install.signer]) build the Kernel-internal `internalData` layout
/// for each module type; the default constructor takes it raw.
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

  /// A validator install (type 1): `internalData` is empty (no hook,
  /// deny-all selectors) or `[20B hook | packed bytes4 selectors]`.
  ///
  /// - [moduleData]: passed to the validator's `onInstall` (for ECDSA-style
  ///   validators, the 20-byte owner)
  /// - [hook]: a hook module, or a [KernelV4HookSentinels] value; defaults
  ///   to no hook
  /// - [allowedSelectors]: account selectors this validation may call as the
  ///   leading `callData` selector (typically `execute`); empty means the
  ///   validator can only be used where selectors are not checked
  factory KernelV4Install.validator({
    required EthereumAddress module,
    String moduleData = '0x',
    EthereumAddress? hook,
    List<String> allowedSelectors = const [],
  }) =>
      KernelV4Install(
        moduleType: BigInt.one,
        module: module,
        moduleData: moduleData,
        internalData: _validationInternalData(
          hook: hook,
          allowedSelectors: allowedSelectors,
        ),
      );

  /// An executor install (type 2): `internalData` is the 20-byte hook —
  /// [KernelV4HookSentinels.notInstalled] (the default) for none.
  factory KernelV4Install.executor({
    required EthereumAddress module,
    String moduleData = '0x',
    EthereumAddress? hook,
  }) =>
      KernelV4Install(
        moduleType: BigInt.two,
        module: module,
        moduleData: moduleData,
        internalData: (hook ?? KernelV4HookSentinels.notInstalled).hex,
      );

  /// A fallback-selector install (type 3): `internalData` is
  /// `[4B selector | 1B callType | 20B hook]`.
  ///
  /// - [selector]: the 4-byte account selector the module handles
  /// - [callType]: `0x00` (call, the default) or `0xff` (delegatecall —
  ///   the module runs in the account's storage context; trusted modules
  ///   only)
  /// - [hook]: [KernelV4HookSentinels.notInstalled] (the default) restricts
  ///   the selector to EntryPoint callers;
  ///   [KernelV4HookSentinels.installedNoHook] opens it to anyone; any other
  ///   address is a hook module that must already be installed
  factory KernelV4Install.fallbackHandler({
    required EthereumAddress module,
    required String selector,
    String moduleData = '0x',
    int callType = 0x00,
    EthereumAddress? hook,
  }) {
    _checkSelector(selector, 'selector');
    if (callType != 0x00 && callType != 0xff) {
      throw ArgumentError.value(
        callType,
        'callType',
        'Kernel v4 fallback selectors support call (0x00) and '
            'delegatecall (0xff) only',
      );
    }
    return KernelV4Install(
      moduleType: BigInt.from(3),
      module: module,
      moduleData: moduleData,
      internalData: Hex.concat([
        selector,
        callType.toRadixString(16).padLeft(2, '0'),
        Hex.strip0x((hook ?? KernelV4HookSentinels.notInstalled).hex),
      ]),
    );
  }

  /// A hook install (type 4): `internalData` is ignored by the Kernel.
  factory KernelV4Install.hook({
    required EthereumAddress module,
    String moduleData = '0x',
  }) =>
      KernelV4Install(
        moduleType: BigInt.from(4),
        module: module,
        moduleData: moduleData,
        internalData: '0x',
      );

  /// A policy install (type 5): `internalData` carries the 4-byte
  /// [permissionId] the policy belongs to.
  ///
  /// Within one install batch, all policies for a permission must precede
  /// its signer, and the batch must include that signer — a permission is
  /// only complete once its signer is installed.
  factory KernelV4Install.policy({
    required EthereumAddress module,
    required String permissionId,
    String moduleData = '0x',
  }) {
    _checkSelector(permissionId, 'permissionId');
    return KernelV4Install(
      moduleType: BigInt.from(5),
      module: module,
      moduleData: moduleData,
      internalData: permissionId,
    );
  }

  /// A permission-signer install (type 6): `internalData` is the 4-byte
  /// [permissionId] followed by the same hook/selector layout as a validator
  /// install.
  ///
  /// Installing the signer finalizes the permission; it must come after the
  /// permission's policies in the batch.
  factory KernelV4Install.signer({
    required EthereumAddress module,
    required String permissionId,
    String moduleData = '0x',
    EthereumAddress? hook,
    List<String> allowedSelectors = const [],
  }) {
    _checkSelector(permissionId, 'permissionId');
    return KernelV4Install(
      moduleType: BigInt.from(6),
      module: module,
      moduleData: moduleData,
      internalData: Hex.concat([
        permissionId,
        Hex.strip0x(
          _validationInternalData(
            hook: hook,
            allowedSelectors: allowedSelectors,
          ),
        ),
      ]),
    );
  }

  /// ERC-7579 module type id.
  final BigInt moduleType;

  /// Module contract address.
  final EthereumAddress module;

  /// `onInstall` data for the module (hex).
  final String moduleData;

  /// Kernel-internal install config (hex).
  final String internalData;

  /// The `[20B hook | packed selectors]` layout shared by validator installs
  /// and the permission-signer suffix (`ValidationManager
  /// ._initializeValidation`): empty for the no-hook deny-all default,
  /// otherwise the hook (no-hook sentinel when only selectors are granted)
  /// followed by the packed 4-byte selectors.
  static String _validationInternalData({
    required EthereumAddress? hook,
    required List<String> allowedSelectors,
  }) {
    for (final selector in allowedSelectors) {
      _checkSelector(selector, 'allowedSelectors');
    }
    if (hook == null && allowedSelectors.isEmpty) return '0x';
    return Hex.concat([
      (hook ?? KernelV4HookSentinels.installedNoHook).hex,
      ...allowedSelectors.map(Hex.strip0x),
    ]);
  }

  static void _checkSelector(String value, String name) {
    if (Hex.strip0x(value).length != 8) {
      throw ArgumentError.value(value, name, 'expected exactly 4 bytes');
    }
  }
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

/// ABI-encodes an `Install[]` value (length word, element offsets, elements)
/// without the leading offset word of an enclosing head — the tail an
/// enclosing `abi.encode` places at the offset its head points to.
///
/// Shared by the factory deploy calldata encoders below and the enable-mode
/// signature blob (`encodeKernelV4EnableModeSignature`).
String encodeKernelV4InstallArray(List<KernelV4Install> packages) {
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
      Hex.strip0x(encodeKernelV4InstallArray(packages)),
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
      Hex.strip0x(encodeKernelV4InstallArray(packages)),
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

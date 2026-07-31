import '../../types/address.dart';
import '../../types/hex.dart';
import '../encoding.dart';
import '../erc7579.dart' show Erc7579ModuleType;
import 'kernel_v4_install.dart';
import 'kernel_v4_validation.dart';

/// Function selectors for Kernel v4 module management.
///
/// `installModule` / `uninstallModule` are the standard ERC-7579 selectors,
/// but the Kernel decodes their `initData` as
/// `abi.encode(bytes installData, bytes internalData)` — see
/// [encodeKernelV4ModuleInitData]. The remaining entrypoints are
/// Kernel-specific overloads.
class KernelV4ModuleSelectors {
  KernelV4ModuleSelectors._();

  /// `installModule(uint256,address,bytes)` = 0x9517e29f
  static const String installModule = '0x9517e29f';

  /// `uninstallModule(uint256,address,bytes)` = 0xa71763a8
  static const String uninstallModule = '0xa71763a8';

  /// `installModule((uint256,address,bytes,bytes)[])` = 0x640890f4
  /// — batch install from the EntryPoint or self.
  static const String batchInstallModule = '0x640890f4';

  /// `installModule(bool,uint256,(uint256,address,bytes,bytes)[],bytes)`
  /// = 0xa706cd33 — root-signed install callable by anyone.
  static const String signedInstallModule = '0xa706cd33';

  /// `setRoot((uint256,address,bytes,bytes)[],bool,bytes)` = 0x49eadd18
  static const String setRootPackages = '0x49eadd18';

  /// `setRoot(bytes21)` = 0x76babb15
  static const String setRootValidation = '0x76babb15';

  /// `grantAccess(bytes21,bytes)` = 0xe08c6ea2
  static const String grantAccess = '0xe08c6ea2';
}

/// Encodes the `initData` argument of Kernel v4's `installModule` /
/// `uninstallModule`: `abi.encode(InstallModuleDataFormat{bytes installData,
/// bytes internalData})`.
///
/// Unlike generic ERC-7579 accounts, the Kernel does **not** forward
/// `initData` raw to the module — [moduleData] goes to the module's
/// `onInstall` / `onUninstall`, [internalData] configures the Kernel itself
/// (hook bindings, selectors, permission ids).
String encodeKernelV4ModuleInitData({
  required String moduleData,
  required String internalData,
}) {
  final moduleDataEncoded = AbiEncoder.encodeBytes(moduleData);
  const headSize = 2 * 32;
  return Hex.concat([
    AbiEncoder.encodeUint256(BigInt.from(headSize)),
    AbiEncoder.encodeUint256(
      BigInt.from(headSize + Hex.byteLength(moduleDataEncoded)),
    ),
    Hex.strip0x(moduleDataEncoded),
    Hex.strip0x(AbiEncoder.encodeBytes(internalData)),
  ]);
}

/// Calldata for `installModule(moduleType, module, initData)` with the
/// Kernel-required [encodeKernelV4ModuleInitData] wrapping — an account
/// self-call (or EntryPoint call) installing one module.
///
/// Build [package] with the typed [KernelV4Install] constructors to get the
/// per-type `internalData` layouts right. Policies and signers should be
/// installed together via [encodeKernelV4BatchInstallCalldata] instead: a
/// permission only validates once its signer is installed, and only the
/// batch entrypoint checks that completeness.
String encodeKernelV4InstallModuleCalldata(KernelV4Install package) =>
    _moduleCalldata(
      selector: KernelV4ModuleSelectors.installModule,
      moduleType: package.moduleType,
      module: package.module,
      moduleData: package.moduleData,
      internalData: package.internalData,
    );

/// Calldata for `uninstallModule(moduleType, module, initData)` with the
/// Kernel-required [encodeKernelV4ModuleInitData] wrapping.
///
/// [moduleData] goes to the module's `onUninstall`; [internalData] tells the
/// Kernel what to unbind and is **required** for some types:
///
/// | type | internalData |
/// |---|---|
/// | validator (1), executor (2), hook (4) | ignored (`0x` fine) |
/// | fallback (3) | the 4-byte selector being unbound |
/// | policy (5), signer (6) | the 4-byte PermissionId |
///
/// Ordering rules the contracts enforce (see
/// [kernelV4PermissionUninstallCalldatas]): a permission's policies come off
/// in reverse install order (LIFO), and its signer only after every policy
/// is removed.
String encodeKernelV4UninstallModuleCalldata({
  required BigInt moduleType,
  required EthereumAddress module,
  String moduleData = '0x',
  String internalData = '0x',
}) {
  final type = moduleType.toInt();
  final isFallback = type == Erc7579ModuleType.fallback.id;
  final isPermissionModule = type == Erc7579ModuleType.policy.id ||
      type == Erc7579ModuleType.signer.id;
  if ((isFallback || isPermissionModule) && Hex.byteLength(internalData) < 4) {
    throw ArgumentError.value(
      internalData,
      'internalData',
      isFallback
          ? 'fallback uninstalls need the 4-byte selector being unbound'
          : 'policy/signer uninstalls need the 4-byte PermissionId',
    );
  }
  return _moduleCalldata(
    selector: KernelV4ModuleSelectors.uninstallModule,
    moduleType: moduleType,
    module: module,
    moduleData: moduleData,
    internalData: internalData,
  );
}

String _moduleCalldata({
  required String selector,
  required BigInt moduleType,
  required EthereumAddress module,
  required String moduleData,
  required String internalData,
}) {
  final initData = encodeKernelV4ModuleInitData(
    moduleData: moduleData,
    internalData: internalData,
  );
  return Hex.concat([
    selector,
    AbiEncoder.encodeUint256(moduleType),
    AbiEncoder.encodeAddress(module),
    AbiEncoder.encodeUint256(BigInt.from(3 * 32)), // offset to initData
    Hex.strip0x(AbiEncoder.encodeBytes(initData)),
  ]);
}

/// Calldata for the batch `installModule(Install[] packages)` — installs all
/// [packages] atomically from the EntryPoint or self.
///
/// This is the required path for permission installs: the Kernel checks at
/// the end of the batch that any started permission was finished by its
/// signer. The same completeness rules are enforced here offline — see
/// [validateKernelV4PermissionCompleteness].
String encodeKernelV4BatchInstallCalldata(List<KernelV4Install> packages) {
  if (packages.isEmpty) {
    throw ArgumentError.value(packages, 'packages', 'must not be empty');
  }
  validateKernelV4PermissionCompleteness(packages);
  return Hex.concat([
    KernelV4ModuleSelectors.batchInstallModule,
    AbiEncoder.encodeUint256(BigInt.from(32)), // offset to packages
    Hex.strip0x(encodeKernelV4InstallArray(packages)),
  ]);
}

/// Calldata for the standalone root-signed
/// `installModule(replayable, nonce, packages, signature)` — callable by
/// **anyone**, without the EntryPoint: the root authorizes the install by
/// signing the same `InstallPackages` digest as enable mode
/// (`getKernelV4InstallPackagesDigest`, with [replayable] selecting the
/// sans-chainId domain), over the Kernel-internal [installNonce].
String encodeKernelV4SignedInstallCalldata({
  required BigInt installNonce,
  required List<KernelV4Install> packages,
  required String signature,
  bool replayable = false,
}) {
  if (packages.isEmpty) {
    throw ArgumentError.value(packages, 'packages', 'must not be empty');
  }
  validateKernelV4PermissionCompleteness(packages);
  final packagesTail = encodeKernelV4InstallArray(packages);
  const headSize = 4 * 32;
  return Hex.concat([
    KernelV4ModuleSelectors.signedInstallModule,
    AbiEncoder.encodeBool(value: replayable),
    AbiEncoder.encodeUint256(installNonce),
    AbiEncoder.encodeUint256(BigInt.from(headSize)),
    AbiEncoder.encodeUint256(
      BigInt.from(headSize + Hex.byteLength(packagesTail)),
    ),
    Hex.strip0x(packagesTail),
    Hex.strip0x(AbiEncoder.encodeBytes(signature)),
  ]);
}

/// Calldata for `setRoot(Install[] pkg, bool removeCurrent, bytes
/// uninstallData)` — installs [packages] and promotes `packages[0]` to the
/// account's new root validation.
///
/// `packages[0]` must be able to root: a validator (1), or a permission's
/// policy (5) / signer (6) — the permission from its 4-byte id.
///
/// With [removeCurrent], the Kernel also uninstalls the old root:
/// - a **validator** root gets [uninstallData] raw in its `onUninstall`;
/// - a **permission** root needs [uninstallData] to be
///   [encodeKernelV4PermissionUninstallData] with one entry per policy (in
///   install order) plus a final entry for the signer.
///
/// Rotation invalidates the old root's selector grants; re-grant with
/// [encodeKernelV4GrantAccessCalldata] if the old validation stays in use.
String encodeKernelV4SetRootCalldata({
  required List<KernelV4Install> packages,
  bool removeCurrent = false,
  String uninstallData = '0x',
}) {
  if (packages.isEmpty) {
    throw ArgumentError.value(
      packages,
      'packages',
      'setRoot installs at least one package (packages[0] becomes the root)',
    );
  }
  final rootType = packages.first.moduleType.toInt();
  if (rootType != Erc7579ModuleType.validator.id &&
      rootType != Erc7579ModuleType.policy.id &&
      rootType != Erc7579ModuleType.signer.id) {
    throw ArgumentError.value(
      packages,
      'packages',
      'packages[0] must be a validator (1), policy (5), or signer (6) '
          'to become the root',
    );
  }
  validateKernelV4PermissionCompleteness(packages);
  final packagesTail = encodeKernelV4InstallArray(packages);
  const headSize = 3 * 32;
  return Hex.concat([
    KernelV4ModuleSelectors.setRootPackages,
    AbiEncoder.encodeUint256(BigInt.from(headSize)),
    AbiEncoder.encodeBool(value: removeCurrent),
    AbiEncoder.encodeUint256(
      BigInt.from(headSize + Hex.byteLength(packagesTail)),
    ),
    Hex.strip0x(packagesTail),
    Hex.strip0x(AbiEncoder.encodeBytes(uninstallData)),
  ]);
}

/// Calldata for `setRoot(ValidationId vId)` — repoints the root to an
/// **already installed** validator or permission, with no install or
/// cleanup.
String encodeKernelV4SetRootValidationCalldata(
  KernelV4Validation validation,
) =>
    Hex.concat([
      KernelV4ModuleSelectors.setRootValidation,
      AbiEncoder.encodeBytes32(_validationId(validation)),
    ]);

/// Calldata for `grantAccess(ValidationId vId, bytes selectors)` — grants
/// [validation] the right to lead UserOperations with the given account
/// [selectors] (packed 4-byte, typically `execute`).
///
/// Needed after a root rotation: promoting a new root invalidates the old
/// root's selector grants, so a demoted-but-kept validation must be
/// re-granted before it can validate again.
String encodeKernelV4GrantAccessCalldata({
  required KernelV4Validation validation,
  required List<String> selectors,
}) {
  if (selectors.isEmpty) {
    throw ArgumentError.value(selectors, 'selectors', 'must not be empty');
  }
  for (final selector in selectors) {
    if (Hex.strip0x(selector).length != 8) {
      throw ArgumentError.value(
        selector,
        'selectors',
        'selectors are exactly 4 bytes each',
      );
    }
  }
  return Hex.concat([
    KernelV4ModuleSelectors.grantAccess,
    AbiEncoder.encodeBytes32(_validationId(validation)),
    AbiEncoder.encodeUint256(BigInt.from(2 * 32)), // offset to selectors
    Hex.strip0x(AbiEncoder.encodeBytes(Hex.concat(selectors))),
  ]);
}

/// The bytes21 `ValidationId` (`[1B vType | 20B ident]`) for a non-root
/// [validation] — validator: the module address; permission: the 4-byte id
/// left-aligned.
String _validationId(KernelV4Validation validation) {
  if (validation is KernelV4RootValidation) {
    throw ArgumentError.value(
      validation,
      'validation',
      'the root validation has no standalone ValidationId; pass the '
          'validator or permission it points to',
    );
  }
  return Hex.concat([
    validation.vType.toRadixString(16).padLeft(2, '0'),
    Hex.strip0x(Hex.padRight(validation.vId, 20)),
  ]);
}

/// Encodes the `PermissionUninstallData` struct `setRoot` expects as
/// `uninstallData` when removing a **permission** root:
/// `abi.encode(bytes[])` with `policies.length + 1` entries — element `i` is
/// passed to `policies[i].onUninstall` (install order), the final element to
/// the signer's. The Kernel removes the policies in reverse (LIFO) but
/// indexes this array by install position.
String encodeKernelV4PermissionUninstallData(
  List<String> perModuleUninstallData,
) {
  final chunks = perModuleUninstallData.map(AbiEncoder.encodeBytes).toList();
  final offsets = <String>[];
  var offset = chunks.length * 32;
  for (final chunk in chunks) {
    offsets.add(AbiEncoder.encodeUint256(BigInt.from(offset)));
    offset += Hex.byteLength(chunk);
  }
  return Hex.concat([
    AbiEncoder.encodeUint256(BigInt.from(32)), // offset to the array
    AbiEncoder.encodeUint256(BigInt.from(chunks.length)),
    ...offsets,
    ...chunks.map(Hex.strip0x),
  ]);
}

/// The `uninstallModule` calldatas that remove a whole permission in the
/// order the contracts require: policies in **reverse install order**
/// (each policy uninstall must match the current last element of the
/// on-chain policy array), then the signer once no policies remain.
///
/// [policies] is the permission's policy list in **install order**;
/// [policyUninstallData] / [signerUninstallData] are the per-module
/// `onUninstall` payloads ([policyUninstallData] also in install order,
/// defaulting to empty).
List<String> kernelV4PermissionUninstallCalldatas({
  required String permissionId,
  required List<EthereumAddress> policies,
  required EthereumAddress signer,
  List<String>? policyUninstallData,
  String signerUninstallData = '0x',
}) {
  if (policyUninstallData != null &&
      policyUninstallData.length != policies.length) {
    throw ArgumentError.value(
      policyUninstallData,
      'policyUninstallData',
      'one entry per policy (in install order) is required',
    );
  }
  return [
    for (var i = policies.length - 1; i >= 0; i--)
      encodeKernelV4UninstallModuleCalldata(
        moduleType: BigInt.from(Erc7579ModuleType.policy.id),
        module: policies[i],
        moduleData: policyUninstallData?[i] ?? '0x',
        internalData: permissionId,
      ),
    encodeKernelV4UninstallModuleCalldata(
      moduleType: BigInt.from(Erc7579ModuleType.signer.id),
      module: signer,
      moduleData: signerUninstallData,
      internalData: permissionId,
    ),
  ];
}

/// Enforces the Kernel's batch permission rules offline
/// (`ModuleManager._install` / `_checkPermissionInstall`): once a policy or
/// signer opens a permission, every further policy/signer must carry the
/// same PermissionId until a signer closes it, and the batch must not end
/// with an open permission.
void validateKernelV4PermissionCompleteness(List<KernelV4Install> packages) {
  String? openPermission;
  for (final package in packages) {
    final type = package.moduleType.toInt();
    if (type != Erc7579ModuleType.policy.id &&
        type != Erc7579ModuleType.signer.id) {
      continue;
    }
    if (Hex.byteLength(package.internalData) < 4) {
      throw ArgumentError.value(
        package.internalData,
        'packages',
        'policy/signer internalData starts with the 4-byte PermissionId',
      );
    }
    final id =
        '0x${Hex.strip0x(package.internalData).substring(0, 8)}'.toLowerCase();
    if (openPermission != null && openPermission != id) {
      throw ArgumentError.value(
        packages,
        'packages',
        'permission $openPermission must be finished by its signer before '
            'another permission ($id) starts',
      );
    }
    if (type == 5) {
      openPermission = id;
    } else {
      openPermission = null; // the signer finalizes the permission
    }
  }
  if (openPermission != null) {
    throw ArgumentError.value(
      packages,
      'packages',
      'permission $openPermission is missing its signer — a permission is '
          'only complete (and usable) once its signer is installed in the '
          'same batch',
    );
  }
}

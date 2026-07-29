import '../../accounts/kernel/constants.dart';
import '../../types/address.dart';
import '../../types/hex.dart';
import '../encoding.dart';
import 'kernel_v4_nonce.dart';

/// ABI-encodes a Kernel v4 `PermissionSignature` — `abi.encode(bytes[])` with
/// one chunk per installed policy (in install order) and the signer module's
/// chunk last.
///
/// During validation the Kernel routes element `i` of the array to
/// `policies[i]` and the final element to the signer, and requires the array
/// length to be exactly `policies.length + 1`
/// (`ValidationManager._validateUserOpPermission`).
String encodeKernelV4PermissionSignature({
  required List<String> policySignatures,
  required String signerSignature,
}) {
  final chunks = [...policySignatures, signerSignature]
      .map(AbiEncoder.encodeBytes)
      .toList();

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

/// Which Kernel v4 validation path a UserOperation runs under.
///
/// Kernel v4 routes validation entirely through the ERC-4337 nonce — the
/// signature itself carries no mode or validator prefix. A validation config
/// therefore owns the three things that differ per path:
///
/// - the nonce `vType` byte and 20-byte `vId` field ([vType] / [vId]),
/// - the shape of the stub signature used for gas estimation
///   ([stubSignature]),
/// - how the owner's raw signature is framed into `userOp.signature`
///   ([wrapSignature]).
///
/// The default is [KernelV4Validation.root] — the account's root (or, for
/// `KernelImmutableECDSA` / `Kernel7702`, its fallback ECDSA signer).
/// [KernelV4Validation.validator] targets an installed validator module, and
/// [KernelV4Validation.permission] a policy-gated permission. Both non-root
/// paths require the module(s) to be installed and the UserOperation's leading
/// callData selector to be allow-listed for that validation — root bypasses
/// both checks by design.
sealed class KernelV4Validation {
  const KernelV4Validation._();

  /// Root / fallback validation (nonce `vType 0x00`, empty vId).
  const factory KernelV4Validation.root() = KernelV4RootValidation;

  /// Validation by the installed validator module at [validator]
  /// (nonce `vType 0x01`, vId = module address).
  ///
  /// The signature is passed to the module raw. The default [stubSignature]
  /// assumes an ECDSA-style validator; pass [stubSignature] for modules whose
  /// estimation stub has a different shape.
  const factory KernelV4Validation.validator(
    EthereumAddress validator, {
    String? stubSignature,
  }) = KernelV4ValidatorValidation;

  /// Validation by the installed permission [permissionId] (nonce
  /// `vType 0x02`, vId = the 4-byte id left-aligned).
  ///
  /// [policySignatures] carries one chunk per installed policy, in install order;
  /// the owner's signature becomes the signer module's final chunk. See
  /// [KernelV4PermissionValidation].
  factory KernelV4Validation.permission(
    String permissionId, {
    List<String> policySignatures,
    String? signerStubSignature,
  }) = KernelV4PermissionValidation;

  /// The nonce `vType` byte for this validation path.
  int get vType;

  /// The validation id, hex — left-aligned into the nonce's 20-byte vId
  /// field by `encodeKernelV4NonceKey`.
  String get vId;

  /// A `userOp.signature` of the correct shape (but invalid content) for gas
  /// estimation: validation must fail cleanly, not revert.
  String get stubSignature;

  /// Frames the owner's raw [ownerSignature] into the `userOp.signature`
  /// this validation path expects.
  String wrapSignature(String ownerSignature);
}

/// Root / fallback validation — see [KernelV4Validation.root].
class KernelV4RootValidation extends KernelV4Validation {
  /// Creates the root validation config.
  const KernelV4RootValidation() : super._();

  @override
  int get vType => KernelV4ValidationType.root;

  @override
  String get vId => '0x';

  @override
  String get stubSignature => kernelDummyEcdsaSignature;

  @override
  String wrapSignature(String ownerSignature) => ownerSignature;
}

/// Validation by an installed validator module — see
/// [KernelV4Validation.validator].
class KernelV4ValidatorValidation extends KernelV4Validation {
  /// Creates a validator validation config for [validator].
  const KernelV4ValidatorValidation(this.validator, {String? stubSignature})
      : _stubSignature = stubSignature,
        super._();

  /// The installed validator module the nonce routes to.
  final EthereumAddress validator;

  final String? _stubSignature;

  @override
  int get vType => KernelV4ValidationType.validator;

  @override
  String get vId => validator.hex;

  @override
  String get stubSignature => _stubSignature ?? kernelDummyEcdsaSignature;

  @override
  String wrapSignature(String ownerSignature) => ownerSignature;
}

/// Validation by an installed permission (policies + signer module) — see
/// [KernelV4Validation.permission].
///
/// The `userOp.signature` is `abi.encode(bytes[])`: [policySignatures] chunks in
/// policy install order, then the signer module's chunk. The Kernel requires
/// exactly `policies.length + 1` chunks, so [policySignatures] must list one entry
/// per installed policy even when a policy ignores its chunk (`0x` entries
/// are fine in that case).
class KernelV4PermissionValidation extends KernelV4Validation {
  /// Creates a permission validation config for the 4-byte [permissionId].
  KernelV4PermissionValidation(
    this.permissionId, {
    this.policySignatures = const [],
    String? signerStubSignature,
  })  : _signerStubSignature = signerStubSignature,
        super._() {
    if (Hex.strip0x(permissionId).length != 8) {
      throw ArgumentError.value(
        permissionId,
        'permissionId',
        'a Kernel v4 PermissionId is exactly 4 bytes',
      );
    }
  }

  /// The 4-byte PermissionId (hex).
  final String permissionId;

  /// One chunk per installed policy, in install order. Policies receive these
  /// verbatim — both at estimation time and in the signed operation.
  final List<String> policySignatures;

  final String? _signerStubSignature;

  @override
  int get vType => KernelV4ValidationType.permission;

  @override
  String get vId => permissionId;

  @override
  String get stubSignature => wrapSignature(
        _signerStubSignature ?? kernelDummyEcdsaSignature,
      );

  @override
  String wrapSignature(String ownerSignature) =>
      encodeKernelV4PermissionSignature(
        policySignatures: policySignatures,
        signerSignature: ownerSignature,
      );
}

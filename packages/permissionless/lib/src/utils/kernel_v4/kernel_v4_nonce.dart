import '../../types/hex.dart';

/// Kernel v4 validation-mode flags (the first nonce byte).
///
/// Unlike v3's enumerated mode, this is a bitfield; documented composite
/// values are `0x00` standard, `0x08` enable, `0x0C` enable + replayable
/// enable signature, `0x40` replayable userOp hash (chain-agnostic), and
/// combinations thereof.
class KernelV4ValidationMode {
  KernelV4ValidationMode._();

  /// Standard validation (no flags).
  static const int standard = 0x00;

  /// Replayable enable signature (chain-agnostic install digest).
  static const int replayableEnable = 0x04;

  /// Enable mode: install packages inline with validation.
  static const int enable = 0x08;

  /// Replayable userOp hash (chain-agnostic EIP-712 digest).
  static const int replayableUserOpHash = 0x40;
}

/// Kernel v4 validation types (the second nonce byte).
class KernelV4ValidationType {
  KernelV4ValidationType._();

  /// Root / fallback validation. The stored root — or, for
  /// `KernelImmutableECDSA` / `Kernel7702`, the fallback ECDSA signer when no
  /// root is set.
  static const int root = 0x00;

  /// An installed validator module; the vId is its 20-byte address.
  static const int validator = 0x01;

  /// A permission; the vId is the 4-byte PermissionId (left-aligned).
  static const int permission = 0x02;
}

final BigInt _maxUint16 = BigInt.from(0xffff);

/// Encodes the 24-byte ERC-4337 nonce key for Kernel v4's nonce layout:
///
/// ```text
/// | vMode (1) | vType (1) | vId (20) | nonceKey (2) |   ← 24-byte key
/// |                     seq (8)                     |   ← managed by EntryPoint
/// ```
///
/// For the default root path (all-zero mode, type, and vId) the key equals
/// [nonceKey] numerically, so plain sequential accounts keep key `0`.
///
/// - [vMode]: bitfield of [KernelV4ValidationMode] flags
/// - [vType]: a [KernelV4ValidationType] value
/// - [vId]: hex validation id, at most 20 bytes, left-aligned into the vId
///   slot (a validator address fills it; a 4-byte PermissionId is padded)
/// - [nonceKey]: caller's 2-byte parallel-nonce key
BigInt encodeKernelV4NonceKey({
  int vMode = KernelV4ValidationMode.standard,
  int vType = KernelV4ValidationType.root,
  String vId = '0x',
  BigInt? nonceKey,
}) {
  final key = nonceKey ?? BigInt.zero;
  if (key < BigInt.zero || key > _maxUint16) {
    throw ArgumentError.value(
      key,
      'nonceKey',
      'Kernel v4 reserves 2 bytes for the nonce key (max 0xffff)',
    );
  }
  if (vMode < 0 || vMode > 0xff) {
    throw ArgumentError.value(vMode, 'vMode', 'must fit in one byte');
  }
  if (vType < 0 || vType > 0xff) {
    throw ArgumentError.value(vType, 'vType', 'must fit in one byte');
  }
  final id = Hex.strip0x(vId);
  if (id.length > 40) {
    throw ArgumentError.value(
      vId,
      'vId',
      'Kernel v4 validation ids are at most 20 bytes',
    );
  }

  return Hex.toBigInt(
    Hex.concat([
      Hex.fromBigInt(BigInt.from(vMode), byteLength: 1),
      Hex.fromBigInt(BigInt.from(vType), byteLength: 1),
      Hex.padRight('0x$id', 20),
      Hex.fromBigInt(key, byteLength: 2),
    ]),
  );
}

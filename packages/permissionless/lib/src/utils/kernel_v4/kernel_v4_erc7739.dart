import 'dart:convert';

import 'package:web3dart/web3dart.dart';

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../encoding.dart';
import '../message_hash.dart';
import 'kernel_v4_nonce.dart';
import 'kernel_v4_validation.dart';

/// `keccak256("PersonalSign(bytes prefixed)")` — the ERC-7739 PersonalSign
/// typehash (`src/types/Constants.sol` in the pinned Kernel v4.0 repo).
final String kernelV4PersonalSignTypeHash =
    Hex.fromBytes(keccak256(ascii.encode('PersonalSign(bytes prefixed)')));

final String _nameHash = Hex.fromBytes(keccak256(ascii.encode('Kernel')));
final String _versionHash = Hex.fromBytes(keccak256(ascii.encode('0.4.0')));

final String _domainTypeHash = Hex.fromBytes(
  keccak256(
    ascii.encode(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
    ),
  ),
);

final String _domainTypeHashSansChainId = Hex.fromBytes(
  keccak256(
    ascii.encode(
      'EIP712Domain(string name,string version,address verifyingContract)',
    ),
  ),
);

String _keccakConcat(List<String> words) =>
    Hex.fromBytes(keccak256(Hex.decode(Hex.concat(words))));

/// The Kernel v4 account's own EIP-712 domain separator: name `"Kernel"`,
/// version `"0.4.0"`, verifyingContract = the account — Solady's default
/// field set, no salt.
///
/// With [sansChainId] the chainId field is dropped (the domain of replayable
/// enable/install signatures); otherwise [chainId] is required and binds the
/// domain to one chain.
String getKernelV4DomainSeparator({
  required EthereumAddress accountAddress,
  BigInt? chainId,
  bool sansChainId = false,
}) {
  if (!sansChainId && chainId == null) {
    throw ArgumentError.value(
      chainId,
      'chainId',
      'required unless the domain is chain-agnostic (sansChainId)',
    );
  }
  return sansChainId
      ? _keccakConcat([
          _domainTypeHashSansChainId,
          _nameHash,
          _versionHash,
          AbiEncoder.encodeAddress(accountAddress),
        ])
      : _keccakConcat([
          _domainTypeHash,
          _nameHash,
          _versionHash,
          AbiEncoder.encodeUint256(chainId!),
          AbiEncoder.encodeAddress(accountAddress),
        ]);
}

/// The ERC-7739 PersonalSign digest a Kernel v4 account verifies for a plain
/// ERC-1271 [hash]: the hash wrapped as `PersonalSign(bytes prefixed)` under
/// the *account's* own domain.
///
/// `isValidSignature(hash, …)` stores the input hash directly as the
/// pre-hashed `prefixed` field (`ERC1271.sol` PersonalSign branch), so for a
/// personal message [hash] must already be the EIP-191 message hash
/// (`hashMessage`) the verifying app passes on-chain — the wrap adds no
/// EIP-191 prefix of its own.
String getKernelV4PersonalSignDigest({
  required EthereumAddress accountAddress,
  required BigInt chainId,
  required String hash,
}) {
  final structHash = _keccakConcat([
    kernelV4PersonalSignTypeHash,
    AbiEncoder.encodeBytes32(hash),
  ]);
  return _keccakConcat([
    '0x1901',
    getKernelV4DomainSeparator(
      accountAddress: accountAddress,
      chainId: chainId,
    ),
    structHash,
  ]);
}

/// The two pieces of an ERC-7739 TypedDataSign signing flow: the [digest]
/// the owner signs, and the [extension] appended after the inner signature
/// so the contract can rebuild and verify the same digest.
class KernelV4TypedDataSignWrap {
  /// Creates the wrap result.
  const KernelV4TypedDataSignWrap({
    required this.digest,
    required this.extension,
  });

  /// The nested-EIP-712 digest to sign.
  final String digest;

  /// `APP_DOMAIN_SEPARATOR ‖ contents ‖ contentsType ‖ uint16(length)` —
  /// appended after the inner signature (implicit contentsDescription mode:
  /// the full `encodeType` string, which starts with the contents name).
  final String extension;
}

/// Wraps app-side EIP-712 [typedData] for Kernel v4 ERC-1271 verification
/// (ERC-7739 `TypedDataSign` workflow).
///
/// The signed digest re-hashes the typed data's struct hash as
/// `TypedDataSign({PrimaryType} contents,string name,string version,`
/// `uint256 chainId,address verifyingContract,bytes32 salt){ContentsType}` —
/// carrying the *account's* `eip712Domain()` fields (salt = 0) — under the
/// *app's* domain separator. With [replayable] the struct drops its chainId
/// field; Kernel accepts that variant through its replayable OR-branch, so
/// one signature can verify on every chain (provided the app's own domain
/// is not chain-bound).
KernelV4TypedDataSignWrap getKernelV4TypedDataSignWrap({
  required EthereumAddress accountAddress,
  required BigInt chainId,
  required TypedData typedData,
  bool replayable = false,
}) {
  final contentsName = typedData.primaryType;
  _validateContentsName(contentsName);
  final contentsType = encodeTypedDataType(contentsName, typedData.types);
  final appDomainSeparator = computeDomainSeparator(typedData.domain);
  final contents = hashStruct(contentsName, typedData.message, typedData.types);

  final typeHash = Hex.fromBytes(
    keccak256(
      utf8.encode(
        'TypedDataSign($contentsName contents,string name,string version,'
        '${replayable ? '' : 'uint256 chainId,'}'
        'address verifyingContract,bytes32 salt)$contentsType',
      ),
    ),
  );
  final structHash = _keccakConcat([
    typeHash,
    contents,
    _nameHash,
    _versionHash,
    if (!replayable) AbiEncoder.encodeUint256(chainId),
    AbiEncoder.encodeAddress(accountAddress),
    AbiEncoder.encodeBytes32('0x'), // the account publishes no salt
  ]);

  final contentsTypeBytes = utf8.encode(contentsType);
  return KernelV4TypedDataSignWrap(
    digest: _keccakConcat(['0x1901', appDomainSeparator, structHash]),
    extension: Hex.concat([
      appDomainSeparator,
      contents,
      Hex.fromBytes(contentsTypeBytes),
      Hex.fromBigInt(BigInt.from(contentsTypeBytes.length), byteLength: 2),
    ]),
  );
}

/// Frames an inner signature into the full Kernel v4 ERC-1271
/// `userOp`-independent signature:
///
/// ```text
/// [1B vMode | 1B vType | vId] ‖ signature ‖ extension
/// ```
///
/// - vId is empty for root, the 20-byte module address for a validator, the
///   4-byte PermissionId for a permission — [KernelV4Validation.vId].
/// - [signature] is the validation-path-shaped payload: the raw 65-byte
///   signature (root/validator), the ABI-encoded signature list
///   ([KernelV4Validation.wrapSignature] output) for a permission, or the
///   ABI-encoded `EnableModeSignature` blob in enable mode.
/// - [extension] is the TypedDataSign tail
///   ([KernelV4TypedDataSignWrap.extension]), empty for PersonalSign.
///
/// [vMode] carries only the enable bits in ERC-1271 (`0x08`, plus `0x04`
/// for a replayable enable signature); Kernel forbids the ROOT vType there
/// (`InvalidValidationType`), which this encoder rejects Dart-side.
String encodeKernelV4Erc1271Signature({
  required KernelV4Validation validation,
  required String signature,
  int vMode = KernelV4ValidationMode.standard,
  String extension = '',
}) {
  if ((vMode & KernelV4ValidationMode.enable) != 0 &&
      validation.vType == KernelV4ValidationType.root) {
    throw ArgumentError.value(
      validation,
      'validation',
      'Kernel forbids root validation in enable-mode ERC-1271 — select the '
          'validator or permission being enabled',
    );
  }
  return Hex.concat([
    Hex.fromBigInt(BigInt.from(vMode), byteLength: 1),
    Hex.fromBigInt(BigInt.from(validation.vType), byteLength: 1),
    validation.vId,
    signature,
    extension,
  ]);
}

/// Rejects contents names the on-chain ERC-7739 parser treats as invalid —
/// it would compute a deliberately-corrupted digest, so a Dart-side throw
/// is the only useful behavior.
void _validateContentsName(String contentsName) {
  const forbidden = [',', ' ', ')', '\x00'];
  final startsLower = contentsName.isNotEmpty &&
      contentsName.codeUnitAt(0) >= 0x61 &&
      contentsName.codeUnitAt(0) <= 0x7a;
  if (contentsName.isEmpty ||
      startsLower ||
      contentsName.startsWith('(') ||
      forbidden.any(contentsName.contains)) {
    throw ArgumentError.value(
      contentsName,
      'typedData.primaryType',
      'ERC-7739 forbids contents names that are empty, start with [a-z(], '
          r'or contain ", )\x00"',
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/hex.dart';
import '../types/typed_data.dart';
import 'abi_type.dart';
import 'encoding.dart';

/// Computes the EIP-191 personal message hash of UTF-8 text.
///
/// Format: keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
/// where `len` counts UTF-8 bytes.
///
/// This is the standard format used by `personal_sign` in wallets. For a
/// byte message (viem `hashMessage({ raw })`) use [hashMessageBytes].
///
/// Example:
/// ```dart
/// final hash = hashMessage('Hello, World!');
/// // Returns the keccak256 hash of the prefixed message
/// ```
String hashMessage(String message) => hashMessageBytes(utf8.encode(message));

/// Computes the EIP-191 personal message hash of raw bytes (viem
/// `hashMessage({ raw })`).
///
/// The length in the prefix is the byte count of [message], so signing a
/// 32-byte hash this way prefixes `32`, not the length of its hex string.
///
/// Example:
/// ```dart
/// final hash = hashMessageBytes(Hex.decode(userOpHash));
/// ```
String hashMessageBytes(List<int> message) => Hex.fromBytes(
      keccak256(
        Uint8List.fromList([
          ...utf8.encode('\x19Ethereum Signed Message:\n${message.length}'),
          ...message,
        ]),
      ),
    );

/// Computes the EIP-712 typed data hash.
///
/// Format: keccak256("\x19\x01" ++ domainSeparator ++ hashStruct(message))
///
/// Example:
/// ```dart
/// final typedData = TypedData(
///   domain: TypedDataDomain(name: 'My App', version: '1', chainId: BigInt.one),
///   types: {'Message': [TypedDataField(name: 'content', type: 'string')]},
///   primaryType: 'Message',
///   message: {'content': 'Hello'},
/// );
/// final hash = hashTypedData(typedData);
/// ```
String hashTypedData(TypedData typedData) {
  final domainSeparator = computeDomainSeparator(typedData.domain);
  final structHash = hashStruct(
    typedData.primaryType,
    typedData.message,
    typedData.types,
  );

  final preImage = Hex.concat([
    '0x1901',
    Hex.strip0x(domainSeparator),
    Hex.strip0x(structHash),
  ]);

  return Hex.fromBytes(keccak256(Hex.decode(preImage)));
}

/// Computes the EIP-712 domain separator.
///
/// The domain separator is computed by hashing the EIP712Domain struct
/// with only the fields that are present in the domain.
String computeDomainSeparator(TypedDataDomain domain) {
  final values = <String, Object?>{
    'name': domain.name,
    'version': domain.version,
    'chainId': domain.chainId,
    'verifyingContract': domain.verifyingContract,
    'salt': domain.salt,
  }..removeWhere((_, value) => value == null);
  final fields = [
    for (final field in _domainFields)
      if (values.containsKey(field.name)) field,
  ];
  return hashStruct('EIP712Domain', values, {'EIP712Domain': fields});
}

const _domainFields = [
  TypedDataField(name: 'name', type: 'string'),
  TypedDataField(name: 'version', type: 'string'),
  TypedDataField(name: 'chainId', type: 'uint256'),
  TypedDataField(name: 'verifyingContract', type: 'address'),
  TypedDataField(name: 'salt', type: 'bytes32'),
];

/// Computes the struct hash for EIP-712.
///
/// hashStruct(s) = keccak256(typeHash || encodeData(s))
String hashStruct(
  String primaryType,
  Map<String, dynamic> data,
  Map<String, List<TypedDataField>> types,
) {
  final typeHash = _computeTypeHash(primaryType, types);
  final encodedData = _encodeData(primaryType, data, types);

  final combined = Hex.concat([typeHash, encodedData]);
  return Hex.fromBytes(keccak256(Hex.decode(combined)));
}

String _computeTypeHash(
  String primaryType,
  Map<String, List<TypedDataField>> types,
) {
  final typeString = _encodeType(primaryType, types);
  return Hex.fromBytes(keccak256(Uint8List.fromList(typeString.codeUnits)));
}

/// Encodes the type string for a struct, including referenced types.
///
/// The format is: PrimaryType(field1 type1,field2 type2,...) ++ ReferencedType1(...) ++ ...
/// Referenced types are sorted alphabetically.
String _encodeType(
  String primaryType,
  Map<String, List<TypedDataField>> types,
) {
  final fields = types[primaryType];
  if (fields == null) {
    throw ArgumentError('Type $primaryType not found in types');
  }

  final referencedTypes = <String>{};
  _findReferencedTypes(primaryType, types, referencedTypes);
  referencedTypes.remove(primaryType);

  final buffer = StringBuffer()..write(_formatTypeString(primaryType, fields));

  final sortedRefs = referencedTypes.toList()..sort();
  for (final refType in sortedRefs) {
    buffer.write(_formatTypeString(refType, types[refType]!));
  }

  return buffer.toString();
}

String _formatTypeString(String typeName, List<TypedDataField> fields) {
  final fieldStrings = fields.map((f) => '${f.type} ${f.name}').join(',');
  return '$typeName($fieldStrings)';
}

void _findReferencedTypes(
  String typeName,
  Map<String, List<TypedDataField>> types,
  Set<String> found,
) {
  if (found.contains(typeName)) return;

  final fields = types[typeName];
  if (fields == null) return;

  found.add(typeName);

  for (final field in fields) {
    final baseType = _getBaseType(field.type);
    if (types.containsKey(baseType)) {
      _findReferencedTypes(baseType, types, found);
    }
  }
}

String _getBaseType(String type) {
  if (type.endsWith('[]')) {
    return type.substring(0, type.length - 2);
  }
  return type;
}

String _encodeData(
  String typeName,
  Map<String, dynamic> data,
  Map<String, List<TypedDataField>> types,
) {
  final fields = types[typeName];
  if (fields == null) {
    throw ArgumentError('Type $typeName not found in types');
  }

  final encodedParts = <String>[];

  for (final field in fields) {
    final value = data[field.name];
    encodedParts.add(_encodeValue(field.type, value, types));
  }

  return Hex.concat(encodedParts);
}

String _encodeValue(
  String type,
  dynamic value,
  Map<String, List<TypedDataField>> types,
) {
  if (type.endsWith('[]')) {
    final baseType = type.substring(0, type.length - 2);
    final array = value as List<dynamic>;
    final encodedElements = array.map((e) => _encodeValue(baseType, e, types));
    final combined = Hex.concat(encodedElements.toList());
    return Hex.fromBytes(keccak256(Hex.decode(combined)));
  }

  if (types.containsKey(type)) {
    return hashStruct(type, value as Map<String, dynamic>, types);
  }

  return _encodePrimitive(type, value);
}

/// Encodes a non-struct, non-array value.
///
/// `bytes` and `string` are hashed; every atomic type is encoded as
/// `abi.encode(value)`, which range-checks integers and sign-extends `intN`.
/// `bytesN` values shorter than N bytes are right-padded with zeros (kept from
/// earlier releases; viem rejects them).
String _encodePrimitive(String type, dynamic value) {
  if (type == 'bytes') {
    return Hex.fromBytes(keccak256(Hex.decode(value as String)));
  }
  if (type == 'string') {
    return _hashString(value as String);
  }
  // Checked here, not left to AbiEncoder: EIP-712 has no tuple or fixed-size
  // array field types, which abi.encode would accept.
  final match = atomicAbiType.firstMatch(type);
  if (match == null) {
    throw ArgumentError('Unsupported type: $type');
  }
  final bytesSize = match.group(2);
  final encodable = bytesSize != null && value is String
      ? Hex.padRight(value, int.parse(bytesSize))
      : value;
  return AbiEncoder.encodeParameters([type], [encodable]);
}

String _hashString(String value) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  return Hex.fromBytes(keccak256(bytes));
}

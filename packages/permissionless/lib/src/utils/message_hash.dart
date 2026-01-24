import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/typed_data.dart';
import 'encoding.dart';

/// Computes the EIP-191 personal message hash.
///
/// Format: keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
///
/// This is the standard format used by `personal_sign` in wallets.
///
/// Example:
/// ```dart
/// final hash = hashMessage('Hello, World!');
/// // Returns the keccak256 hash of the prefixed message
/// ```
String hashMessage(String message) {
  final messageBytes = utf8.encode(message);
  final prefix = '\x19Ethereum Signed Message:\n${messageBytes.length}';
  final prefixBytes = utf8.encode(prefix);

  final combined = Uint8List(prefixBytes.length + messageBytes.length)
    ..setRange(0, prefixBytes.length, prefixBytes)
    ..setRange(
      prefixBytes.length,
      prefixBytes.length + messageBytes.length,
      messageBytes,
    );

  return Hex.fromBytes(keccak256(combined));
}

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
  // Build the domain type string with only present fields
  final fields = <String>[];
  if (domain.name != null) fields.add('string name');
  if (domain.version != null) fields.add('string version');
  if (domain.chainId != null) fields.add('uint256 chainId');
  if (domain.verifyingContract != null) fields.add('address verifyingContract');
  if (domain.salt != null) fields.add('bytes32 salt');

  final domainTypeString = 'EIP712Domain(${fields.join(',')})';
  final domainTypeHash =
      keccak256(Uint8List.fromList(domainTypeString.codeUnits));

  // Encode domain values in order
  final encodedParts = <String>[Hex.fromBytes(domainTypeHash)];

  if (domain.name != null) {
    encodedParts.add(_hashString(domain.name!));
  }
  if (domain.version != null) {
    encodedParts.add(_hashString(domain.version!));
  }
  if (domain.chainId != null) {
    encodedParts.add(AbiEncoder.encodeUint256(domain.chainId!));
  }
  if (domain.verifyingContract != null) {
    encodedParts.add(AbiEncoder.encodeAddress(domain.verifyingContract!));
  }
  if (domain.salt != null) {
    encodedParts.add(AbiEncoder.encodeBytes32(domain.salt!));
  }

  final encoded = Hex.concat(encodedParts);
  return Hex.fromBytes(keccak256(Hex.decode(encoded)));
}

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

/// Computes the type hash for a struct.
///
/// typeHash = keccak256(encodeType(typeOf(s)))
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

  // Find all referenced types (recursively)
  final referencedTypes = <String>{};
  _findReferencedTypes(primaryType, types, referencedTypes);
  referencedTypes.remove(primaryType); // Don't include the primary type twice

  // Build the type string
  final buffer = StringBuffer()..write(_formatTypeString(primaryType, fields));

  // Append referenced types in alphabetical order
  final sortedRefs = referencedTypes.toList()..sort();
  for (final refType in sortedRefs) {
    buffer.write(_formatTypeString(refType, types[refType]!));
  }

  return buffer.toString();
}

/// Formats a single type definition string.
String _formatTypeString(String typeName, List<TypedDataField> fields) {
  final fieldStrings = fields.map((f) => '${f.type} ${f.name}').join(',');
  return '$typeName($fieldStrings)';
}

/// Recursively finds all types referenced by a given type.
void _findReferencedTypes(
  String typeName,
  Map<String, List<TypedDataField>> types,
  Set<String> found,
) {
  if (found.contains(typeName)) return;

  final fields = types[typeName];
  if (fields == null) return; // Primitive type

  found.add(typeName);

  for (final field in fields) {
    final baseType = _getBaseType(field.type);
    if (types.containsKey(baseType)) {
      _findReferencedTypes(baseType, types, found);
    }
  }
}

/// Gets the base type from an array type (e.g., 'Person[]' -> 'Person').
String _getBaseType(String type) {
  if (type.endsWith('[]')) {
    return type.substring(0, type.length - 2);
  }
  return type;
}

/// Encodes the data according to EIP-712 rules.
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

/// Encodes a single value according to its type.
String _encodeValue(
  String type,
  dynamic value,
  Map<String, List<TypedDataField>> types,
) {
  // Handle arrays
  if (type.endsWith('[]')) {
    final baseType = type.substring(0, type.length - 2);
    final array = value as List<dynamic>;
    final encodedElements = array.map((e) => _encodeValue(baseType, e, types));
    final combined = Hex.concat(encodedElements.toList());
    return Hex.fromBytes(keccak256(Hex.decode(combined)));
  }

  // Handle custom struct types
  if (types.containsKey(type)) {
    return hashStruct(type, value as Map<String, dynamic>, types);
  }

  // Handle primitive types
  return _encodePrimitive(type, value);
}

/// Encodes a primitive Solidity type.
String _encodePrimitive(String type, dynamic value) {
  // bytes (dynamic)
  if (type == 'bytes') {
    final hexValue = value as String;
    return Hex.fromBytes(keccak256(Hex.decode(hexValue)));
  }

  // string
  if (type == 'string') {
    final stringValue = value as String;
    return _hashString(stringValue);
  }

  // bool
  if (type == 'bool') {
    final boolValue = value as bool;
    return AbiEncoder.encodeUint256(boolValue ? BigInt.one : BigInt.zero);
  }

  // address
  if (type == 'address') {
    if (value is EthereumAddress) {
      return AbiEncoder.encodeAddress(value);
    }
    return AbiEncoder.encodeAddress(EthereumAddress.fromHex(value as String));
  }

  // bytes1 through bytes32
  if (type.startsWith('bytes') && type.length <= 7) {
    final size = int.tryParse(type.substring(5));
    if (size != null && size >= 1 && size <= 32) {
      return AbiEncoder.encodeBytes32(value as String);
    }
  }

  // uint types (uint8, uint16, ..., uint256)
  if (type.startsWith('uint')) {
    if (value is BigInt) {
      return AbiEncoder.encodeUint256(value);
    }
    if (value is int) {
      return AbiEncoder.encodeUint256(BigInt.from(value));
    }
    return AbiEncoder.encodeUint256(BigInt.parse(value.toString()));
  }

  // int types (int8, int16, ..., int256)
  if (type.startsWith('int')) {
    BigInt bigValue;
    if (value is BigInt) {
      bigValue = value;
    } else if (value is int) {
      bigValue = BigInt.from(value);
    } else {
      bigValue = BigInt.parse(value.toString());
    }
    // Convert to two's complement for negative values
    if (bigValue < BigInt.zero) {
      bigValue = (BigInt.one << 256) + bigValue;
    }
    return AbiEncoder.encodeUint256(bigValue);
  }

  throw ArgumentError('Unsupported type: $type');
}

/// Hashes a string value for EIP-712 encoding.
String _hashString(String value) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  return Hex.fromBytes(keccak256(bytes));
}

import 'address.dart';

/// EIP-712 typed data domain separator components.
///
/// Used to prevent signature replay attacks across different dApps and chains.
/// At least one field should be specified.
///
/// Example:
/// ```dart
/// final domain = TypedDataDomain(
///   name: 'My dApp',
///   version: '1',
///   chainId: BigInt.from(1),
///   verifyingContract: EthereumAddress.fromHex('0x...'),
/// );
/// ```
class TypedDataDomain {
  /// Creates an EIP-712 domain separator.
  ///
  /// At least one field should be specified to prevent signature replay.
  const TypedDataDomain({
    this.name,
    this.version,
    this.chainId,
    this.verifyingContract,
    this.salt,
  });

  /// The user-friendly name of the signing domain (e.g., dApp name).
  final String? name;

  /// The current major version of the signing domain.
  final String? version;

  /// The chain ID for the domain (EIP-155).
  final BigInt? chainId;

  /// The address of the contract that will verify the signature.
  final EthereumAddress? verifyingContract;

  /// An optional disambiguating salt for the protocol.
  final String? salt;

  /// Returns true if all fields are null.
  bool get isEmpty =>
      name == null &&
      version == null &&
      chainId == null &&
      verifyingContract == null &&
      salt == null;
}

/// A single field definition in an EIP-712 type.
///
/// Example:
/// ```dart
/// // Defines a field named 'from' of type 'address'
/// final field = TypedDataField(name: 'from', type: 'address');
/// ```
class TypedDataField {
  /// Creates an EIP-712 type field definition.
  ///
  /// - [name]: The field name as it appears in the struct
  /// - [type]: The Solidity type (e.g., 'address', 'uint256', 'bytes32',
  ///   or a custom type name defined in the types map)
  const TypedDataField({
    required this.name,
    required this.type,
  });

  /// The name of the field.
  final String name;

  /// The Solidity type of the field (e.g., 'address', 'uint256', 'bytes32').
  ///
  /// Can also reference other custom types defined in the types map,
  /// or arrays like 'uint256[]' or 'Person[]'.
  final String type;

  @override
  String toString() => '$name: $type';
}

/// Complete EIP-712 typed data structure for signing.
///
/// EIP-712 provides a standard for typed structured data hashing and signing.
/// This allows users to see exactly what they're signing in their wallet.
///
/// Example:
/// ```dart
/// final typedData = TypedData(
///   domain: TypedDataDomain(
///     name: 'Ether Mail',
///     version: '1',
///     chainId: BigInt.from(1),
///     verifyingContract: EthereumAddress.fromHex('0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC'),
///   ),
///   types: {
///     'Person': [
///       TypedDataField(name: 'name', type: 'string'),
///       TypedDataField(name: 'wallet', type: 'address'),
///     ],
///     'Mail': [
///       TypedDataField(name: 'from', type: 'Person'),
///       TypedDataField(name: 'to', type: 'Person'),
///       TypedDataField(name: 'contents', type: 'string'),
///     ],
///   },
///   primaryType: 'Mail',
///   message: {
///     'from': {
///       'name': 'Alice',
///       'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
///     },
///     'to': {
///       'name': 'Bob',
///       'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
///     },
///     'contents': 'Hello, Bob!',
///   },
/// );
/// ```
class TypedData {
  /// Creates an EIP-712 typed data structure for signing.
  ///
  /// - [domain]: The domain separator parameters
  /// - [types]: Type definitions for all custom types used in the message
  /// - [primaryType]: The name of the primary type being signed
  /// - [message]: The actual message data conforming to [primaryType]
  const TypedData({
    required this.domain,
    required this.types,
    required this.primaryType,
    required this.message,
  });

  /// The domain separator parameters.
  final TypedDataDomain domain;

  /// Type definitions for all custom types used in the message.
  ///
  /// Keys are type names, values are lists of field definitions.
  /// The EIP712Domain type is automatically added and should not be included.
  final Map<String, List<TypedDataField>> types;

  /// The primary type being signed (must be a key in [types]).
  final String primaryType;

  /// The actual message data to sign.
  ///
  /// Must conform to the structure defined by [primaryType] in [types].
  final Map<String, dynamic> message;
}

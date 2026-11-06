import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';
import 'abi_type.dart';

/// ABI encoding utilities for Ethereum smart contract interactions.
class AbiEncoder {
  AbiEncoder._();

  /// Encodes an address (20 bytes, left-padded to 32 bytes).
  static String encodeAddress(EthereumAddress address) =>
      Hex.padLeft(address.hex, 32);

  /// Encodes a uint256 value (32 bytes).
  static String encodeUint256(BigInt value) =>
      Hex.fromBigInt(value, byteLength: 32);

  /// Encodes a uint128 value (16 bytes, left-padded to 32 bytes).
  ///
  /// Throws an [ArgumentError] naming [name] if [value] does not fit in
  /// uint128.
  static String encodeUint128(BigInt value, {String? name}) => Hex.padLeft(
        Hex.fromBigInt(value, byteLength: 16, name: name),
        32,
      );

  /// Encodes a uint48 value (6 bytes, left-padded to 32 bytes).
  ///
  /// Throws an [ArgumentError] naming [name] if [value] does not fit in
  /// uint48.
  static String encodeUint48(int value, {String? name}) => Hex.padLeft(
        Hex.fromBigInt(BigInt.from(value), byteLength: 6, name: name),
        32,
      );

  /// Encodes a boolean value.
  static String encodeBool({required bool value}) =>
      Hex.fromBigInt(value ? BigInt.one : BigInt.zero, byteLength: 32);

  /// Encodes bytes (dynamic type with length prefix).
  static String encodeBytes(String hexData) {
    final data = Hex.decode(hexData);
    final length = encodeUint256(BigInt.from(data.length));

    final paddedLength = ((data.length + 31) ~/ 32) * 32;
    final paddedData = Uint8List(paddedLength)..setRange(0, data.length, data);

    return Hex.concat([length, Hex.fromBytes(paddedData)]);
  }

  /// Encodes bytes32 (static, no length prefix).
  static String encodeBytes32(String hexData) => Hex.padRight(hexData, 32);

  /// Computes the function selector (first 4 bytes of keccak256(signature)).
  static String functionSelector(String signature) {
    final hash = keccak256(Uint8List.fromList(signature.codeUnits));
    return Hex.slice(Hex.fromBytes(hash), 0, 4);
  }

  /// Encodes a function call with parameters.
  static String encodeFunctionCall(
    String selector,
    List<String> encodedParams,
  ) =>
      Hex.concat([selector, ...encodedParams.map(Hex.strip0x)]);

  /// Encodes function calldata from a Solidity signature and arguments.
  ///
  /// Uses web3dart's ABI encoder so encoding matches Solidity and viem
  /// `encodeFunctionData` for static types, dynamic `bytes`/`string`, arrays,
  /// and tuples (including nested).
  ///
  /// [functionSignature] examples:
  /// - `transfer(address,uint256)`
  /// - `execute(address,uint256,bytes)`
  /// - `setPoint((uint256,uint256))`
  ///
  /// Accepted argument forms:
  /// - `address`: [EthereumAddress] or hex [String]
  /// - `uint*` / `int*`: [BigInt] or [int]
  /// - `bool`: [bool]
  /// - `bytes` / `bytesN`: hex [String] or [Uint8List]
  /// - `string`: [String]
  /// - arrays / tuples: [List], converted element-wise
  ///
  /// Throws [ArgumentError] for a type viem rejects (e.g. `uint7`, `int264`,
  /// `bytes33`, `bytes0`), an argument count mismatch, or a value that does
  /// not fit its type.
  static String encodeFunctionData(
    String functionSignature, [
    List<dynamic> args = const [],
  ]) {
    final parsed = _parseFunctionSignature(functionSignature);
    if (parsed.types.length != args.length) {
      throw ArgumentError(
        'Argument count mismatch: expected ${parsed.types.length}, '
        'got ${args.length}',
      );
    }

    final function =
        ContractFunction(parsed.name, _abiParameters(parsed.types));
    final converted = <dynamic>[
      for (var i = 0; i < args.length; i++)
        _convertAbiArg(parsed.types[i], args[i]),
    ];

    return Hex.fromBytes(function.encodeCall(converted));
  }

  /// ABI-encodes [values] as the tuple [types] (Solidity `abi.encode`, viem
  /// `encodeAbiParameters`), e.g. constructor arguments or struct hashes.
  ///
  /// Accepts the same argument forms as [encodeFunctionData].
  static String encodeParameters(List<String> types, List<dynamic> values) =>
      Hex.slice(encodeFunctionData(_parametersSignature(types), values), 4);

  /// Inverse of [encodeParameters] (viem `decodeAbiParameters`).
  static List<dynamic> decodeParameters(List<String> types, String data) {
    final signature = _parametersSignature(types);
    return decodeFunctionData(
      signature,
      Hex.concat([functionSelector(signature), data]),
    );
  }

  // `abi.encode(params)` is the argument block of any function taking those
  // params, so the parameter codec reuses the function codec.
  static String _parametersSignature(List<String> types) =>
      'parameters(${types.join(',')})';

  /// Decodes function calldata produced by [encodeFunctionData] (or equivalent).
  ///
  /// [functionSignature] uses the same form as [encodeFunctionData], e.g.
  /// `execute(address,uint256,bytes)`.
  ///
  /// Returns the decoded argument list. Dynamic `bytes` values are [Uint8List];
  /// addresses are [EthereumAddress]; integers are [BigInt].
  ///
  /// Throws [ArgumentError] if the selector does not match or the data is invalid.
  static List<dynamic> decodeFunctionData(
    String functionSignature,
    String data,
  ) {
    final parsed = _parseFunctionSignature(functionSignature);
    final parameters = _abiParameters(parsed.types);
    final function = ContractFunction(parsed.name, parameters);
    final expectedSelector = Hex.fromBytes(function.selector).toLowerCase();

    final hex = Hex.strip0x(data);
    if (hex.length < 8) {
      throw ArgumentError('Call data too short for function selector');
    }
    final actualSelector = '0x${hex.substring(0, 8)}'.toLowerCase();
    if (actualSelector != expectedSelector) {
      throw ArgumentError(
        'Selector mismatch: expected $expectedSelector, got $actualSelector',
      );
    }

    final paramsHex = hex.substring(8);
    final bytes = Hex.decode(paramsHex.isEmpty ? '0x' : '0x$paramsHex');
    final tuple = TupleType(parameters.map((p) => p.type).toList());
    return List<dynamic>.from(tuple.decode(bytes.buffer, 0).data);
  }

  /// Encodes multiple values with dynamic types.
  ///
  /// `parts` - List of tuples (isStatic, encodedValue).
  /// For dynamic values, encodedValue should be the complete encoded data.
  static String encodeWithDynamics(List<(bool isStatic, String data)> parts) {
    final staticSize = parts.length * 32;
    var dynamicOffset = staticSize;

    final staticParts = <String>[];
    final dynamicParts = <String>[];

    for (final (isStatic, data) in parts) {
      if (isStatic) {
        staticParts.add(data);
      } else {
        staticParts.add(encodeUint256(BigInt.from(dynamicOffset)));
        dynamicParts.add(data);
        dynamicOffset += Hex.byteLength(data);
      }
    }

    return Hex.concat([...staticParts, ...dynamicParts]);
  }

  static ({String name, List<String> types}) _parseFunctionSignature(
    String signature,
  ) {
    final paramsStart = signature.indexOf('(');
    final paramsEnd = signature.lastIndexOf(')');
    if (paramsStart == -1 || paramsEnd == -1 || paramsEnd < paramsStart) {
      throw ArgumentError('Invalid function signature: $signature');
    }

    final name = signature.substring(0, paramsStart).trim();
    if (name.isEmpty) {
      throw ArgumentError('Invalid function signature: $signature');
    }

    final paramsStr = signature.substring(paramsStart + 1, paramsEnd);
    return (name: name, types: _splitAbiParameterTypes(paramsStr));
  }

  static List<FunctionParameter<dynamic>> _abiParameters(List<String> types) =>
      [
        for (var i = 0; i < types.length; i++)
          FunctionParameter<dynamic>(
            'arg$i',
            parseAbiType(_checkAbiType(types[i])),
          ),
      ];

  static final RegExp _arrayType = RegExp(r'^(.*)\[(\d*)\]$');

  /// Throws [ArgumentError] unless [type] is a Solidity ABI type with valid
  /// widths throughout (see [atomicAbiType]); returns [type].
  static String _checkAbiType(String type) {
    final array = _arrayType.firstMatch(type);
    if (array != null) {
      _checkAbiType(array.group(1)!);
    } else if (type.startsWith('(') && type.endsWith(')')) {
      _splitAbiParameterTypes(type.substring(1, type.length - 1))
          .forEach(_checkAbiType);
    } else if (!atomicAbiType.hasMatch(type)) {
      throw ArgumentError.value(type, 'type', 'not a Solidity ABI type');
    }
    return type;
  }

  /// Splits a top-level ABI parameter list, respecting nested tuples.
  static List<String> _splitAbiParameterTypes(String params) {
    final trimmed = params.trim();
    if (trimmed.isEmpty) return [];

    final types = <String>[];
    final buffer = StringBuffer();
    var depth = 0;

    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      if (char == '(') {
        depth++;
        buffer.write(char);
      } else if (char == ')') {
        depth--;
        buffer.write(char);
      } else if (char == ',' && depth == 0) {
        types.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      types.add(buffer.toString().trim());
    }

    if (depth != 0) {
      throw ArgumentError(
        'Invalid ABI type list (mismatched parentheses): $params',
      );
    }

    return types;
  }

  /// Converts a Dart-friendly argument into the form web3dart expects.
  static dynamic _convertAbiArg(String type, dynamic value) {
    final arrayMatch = _arrayType.firstMatch(type);
    if (arrayMatch != null) {
      final elementType = arrayMatch.group(1)!;
      if (value is! List) {
        throw ArgumentError(
          'Expected List for array type $type, got ${value.runtimeType}',
        );
      }
      final lengthStr = arrayMatch.group(2)!;
      if (lengthStr.isNotEmpty) {
        final expectedLength = int.parse(lengthStr);
        if (value.length != expectedLength) {
          throw ArgumentError(
            'Array length mismatch for $type: expected $expectedLength, '
            'got ${value.length}',
          );
        }
      }
      return [
        for (final element in value) _convertAbiArg(elementType, element),
      ];
    }

    if (type.startsWith('(') && type.endsWith(')')) {
      if (value is! List) {
        throw ArgumentError(
          'Expected List for tuple type $type, got ${value.runtimeType}',
        );
      }
      final componentTypes = _splitAbiParameterTypes(
        type.substring(1, type.length - 1),
      );
      if (componentTypes.length != value.length) {
        throw ArgumentError(
          'Tuple length mismatch for $type: expected '
          '${componentTypes.length}, got ${value.length}',
        );
      }
      return [
        for (var i = 0; i < componentTypes.length; i++)
          _convertAbiArg(componentTypes[i], value[i]),
      ];
    }

    if (type == 'address') {
      if (value is EthereumAddress) return value;
      return EthereumAddress.fromHex(value.toString());
    }

    if (type == 'bool') {
      return value as bool;
    }

    if (type == 'string') {
      return value as String;
    }

    if (type == 'bytes' || (type.startsWith('bytes') && type.length > 5)) {
      return _toBytes(
        value,
        fixedLength: type == 'bytes' ? null : int.parse(type.substring(5)),
      );
    }

    if (type.startsWith('uint') || type.startsWith('int')) {
      final number = switch (value) {
        final BigInt v => v,
        final int v => BigInt.from(v),
        _ => BigInt.parse(value.toString()),
      };
      _checkIntegerRange(type, number);
      return number;
    }

    return value;
  }

  /// web3dart only `assert`s integer widths, so release builds would
  /// silently encode an out-of-range value.
  static void _checkIntegerRange(String type, BigInt value) {
    final signed = type.startsWith('int');
    final widthText = type.substring(signed ? 3 : 4);
    final bits = widthText.isEmpty ? 256 : int.parse(widthText);
    final min = signed ? -(BigInt.one << (bits - 1)) : BigInt.zero;
    final maxExclusive = BigInt.one << (signed ? bits - 1 : bits);
    if (value < min || value >= maxExclusive) {
      throw ArgumentError.value(value, type, 'out of range for $type');
    }
  }

  static Uint8List _toBytes(dynamic value, {int? fixedLength}) {
    final Uint8List bytes;
    if (value is Uint8List) {
      bytes = value;
    } else if (value is List<int>) {
      bytes = Uint8List.fromList(value);
    } else {
      bytes = Hex.decode(value.toString());
    }

    if (fixedLength != null && bytes.length != fixedLength) {
      throw ArgumentError(
        'Invalid bytes$fixedLength length: expected $fixedLength, '
        'got ${bytes.length}',
      );
    }
    return bytes;
  }
}

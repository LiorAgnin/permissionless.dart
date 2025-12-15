import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';

/// ABI encoding utilities for Ethereum smart contract interactions.
class AbiEncoder {
  AbiEncoder._();

  /// Encodes an address (20 bytes, left-padded to 32 bytes).
  static String encodeAddress(EthAddress address) =>
      Hex.padLeft(address.hex, 32);

  /// Encodes a uint256 value (32 bytes).
  static String encodeUint256(BigInt value) =>
      Hex.fromBigInt(value, byteLength: 32);

  /// Encodes a uint128 value (16 bytes, left-padded to 32 bytes).
  static String encodeUint128(BigInt value) =>
      Hex.fromBigInt(value, byteLength: 32);

  /// Encodes a uint48 value (6 bytes, left-padded to 32 bytes).
  static String encodeUint48(int value) =>
      Hex.fromBigInt(BigInt.from(value), byteLength: 32);

  /// Encodes a boolean value.
  static String encodeBool({required bool value}) =>
      Hex.fromBigInt(value ? BigInt.one : BigInt.zero, byteLength: 32);

  /// Encodes bytes (dynamic type with length prefix).
  static String encodeBytes(String hexData) {
    final data = Hex.decode(hexData);
    final length = encodeUint256(BigInt.from(data.length));

    // Pad data to 32-byte boundary
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
        // Add offset pointer
        staticParts.add(encodeUint256(BigInt.from(dynamicOffset)));
        dynamicParts.add(data);
        dynamicOffset += Hex.byteLength(data);
      }
    }

    return Hex.concat([...staticParts, ...dynamicParts]);
  }
}

/// Common function selectors for Safe contracts.
class SafeSelectors {
  SafeSelectors._();

  // Safe singleton functions
  static final String setup = AbiEncoder.functionSelector(
    'setup(address[],uint256,address,bytes,address,address,uint256,address)',
  );

  // Safe 4337 module functions
  static final String executeUserOp = AbiEncoder.functionSelector(
    'executeUserOp(address,uint256,bytes,uint8)',
  );

  static final String executeUserOpWithErrorString =
      AbiEncoder.functionSelector(
    'executeUserOpWithErrorString(address,uint256,bytes,uint8)',
  );

  // Safe proxy factory functions
  static final String createProxyWithNonce = AbiEncoder.functionSelector(
    'createProxyWithNonce(address,bytes,uint256)',
  );

  // Safe module setup functions
  static final String enableModules =
      AbiEncoder.functionSelector('enableModules(address[])');

  // MultiSend functions
  static final String multiSend =
      AbiEncoder.functionSelector('multiSend(bytes)');
}

/// Encodes a Safe `setup` function call.
String encodeSafeSetup({
  required List<EthAddress> owners,
  required BigInt threshold,
  required EthAddress to,
  required String data,
  required EthAddress fallbackHandler,
  required EthAddress paymentToken,
  required BigInt payment,
  required EthAddress paymentReceiver,
}) {
  // Encode owners array
  const ownersOffset = 8 * 32; // 8 parameters * 32 bytes each for static parts
  final ownersEncoded = _encodeAddressArray(owners);

  // Encode data bytes
  final dataOffset = ownersOffset + Hex.byteLength(ownersEncoded);
  final dataEncoded = AbiEncoder.encodeBytes(data);

  final params = Hex.concat([
    // Offset to owners array
    AbiEncoder.encodeUint256(BigInt.from(ownersOffset)),
    // threshold
    AbiEncoder.encodeUint256(threshold),
    // to
    AbiEncoder.encodeAddress(to),
    // Offset to data
    AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
    // fallbackHandler
    AbiEncoder.encodeAddress(fallbackHandler),
    // paymentToken
    AbiEncoder.encodeAddress(paymentToken),
    // payment
    AbiEncoder.encodeUint256(payment),
    // paymentReceiver
    AbiEncoder.encodeAddress(paymentReceiver),
    // owners array (dynamic)
    Hex.strip0x(ownersEncoded),
    // data bytes (dynamic)
    Hex.strip0x(dataEncoded),
  ]);

  return Hex.concat([SafeSelectors.setup, Hex.strip0x(params)]);
}

/// Encodes an array of addresses.
String _encodeAddressArray(List<EthAddress> addresses) {
  final parts = <String>[
    AbiEncoder.encodeUint256(BigInt.from(addresses.length)),
    ...addresses.map((a) => Hex.strip0x(AbiEncoder.encodeAddress(a))),
  ];
  return Hex.concat(parts);
}

/// Encodes an `enableModules` call for Safe module setup.
String encodeEnableModules(List<EthAddress> modules) {
  const modulesOffset = 32; // Single parameter, offset to dynamic array
  final modulesEncoded = _encodeAddressArray(modules);

  return Hex.concat([
    SafeSelectors.enableModules,
    AbiEncoder.encodeUint256(BigInt.from(modulesOffset)),
    Hex.strip0x(modulesEncoded),
  ]);
}

/// Encodes an `executeUserOpWithErrorString` call.
String encodeExecuteUserOp({
  required EthAddress to,
  required BigInt value,
  required String data,
  required int operation,
}) {
  // Offset for the bytes data parameter
  const dataOffset = 4 * 32; // 4 static parameters
  final dataEncoded = AbiEncoder.encodeBytes(data);

  return Hex.concat([
    SafeSelectors.executeUserOpWithErrorString,
    AbiEncoder.encodeAddress(to),
    AbiEncoder.encodeUint256(value),
    AbiEncoder.encodeUint256(BigInt.from(dataOffset)),
    AbiEncoder.encodeUint256(BigInt.from(operation)),
    Hex.strip0x(dataEncoded),
  ]);
}

/// Encodes a `createProxyWithNonce` call.
String encodeCreateProxyWithNonce({
  required EthAddress singleton,
  required String initializer,
  required BigInt saltNonce,
}) {
  const initializerOffset = 3 * 32; // 3 static parameters
  final initializerEncoded = AbiEncoder.encodeBytes(initializer);

  return Hex.concat([
    SafeSelectors.createProxyWithNonce,
    AbiEncoder.encodeAddress(singleton),
    AbiEncoder.encodeUint256(BigInt.from(initializerOffset)),
    AbiEncoder.encodeUint256(saltNonce),
    Hex.strip0x(initializerEncoded),
  ]);
}

// ============================================================================
// Safe 7579 Encoding Functions
// ============================================================================

/// Function selectors for Safe 7579 contracts.
class Safe7579Selectors {
  Safe7579Selectors._();

  /// initSafe7579(address,tuple[],tuple[],tuple[],address[],uint8)
  static final String initSafe7579 = AbiEncoder.functionSelector(
    'initSafe7579(address,(address,bytes)[],(address,bytes)[],(address,bytes)[],address[],uint8)',
  );

  /// preValidationSetup(bytes32,address,bytes)
  static final String preValidationSetup = AbiEncoder.functionSelector(
    'preValidationSetup(bytes32,address,bytes)',
  );

  /// setupSafe(tuple)
  /// The tuple contains the full Safe7579 init data
  static final String setupSafe = AbiEncoder.functionSelector(
    'setupSafe((address,address[],uint256,address,bytes,address,(address,bytes)[],bytes))',
  );
}

/// Encodes an array of ModuleInit tuples.
///
/// Each ModuleInit is: (address module, bytes initData)
String _encodeModuleInitArray(
  List<(EthAddress module, String initData)> modules,
) {
  if (modules.isEmpty) {
    // Empty array: just the length (0)
    return AbiEncoder.encodeUint256(BigInt.zero);
  }

  // Array length
  final length = AbiEncoder.encodeUint256(BigInt.from(modules.length));

  // Calculate offsets for each struct
  // Each struct needs an offset pointer (32 bytes each)
  final structOffsets = <String>[];
  final structData = <String>[];

  var currentOffset = modules.length * 32; // Start after all offset pointers

  for (final (module, initData) in modules) {
    structOffsets.add(AbiEncoder.encodeUint256(BigInt.from(currentOffset)));

    // Encode the struct: (address, bytes)
    // address is static (32 bytes), bytes needs offset + data
    final initDataEncoded = AbiEncoder.encodeBytes(initData);
    const bytesOffset = 2 * 32; // address (32) + offset pointer (32)

    final structEncoded = Hex.concat([
      AbiEncoder.encodeAddress(module),
      AbiEncoder.encodeUint256(BigInt.from(bytesOffset)),
      Hex.strip0x(initDataEncoded),
    ]);

    structData.add(structEncoded);
    currentOffset += Hex.byteLength(structEncoded);
  }

  return Hex.concat([
    length,
    ...structOffsets.map(Hex.strip0x),
    ...structData.map(Hex.strip0x),
  ]);
}

/// Encodes the `initSafe7579` function call.
///
/// Function signature:
/// ```solidity
/// function initSafe7579(
///     address safe7579,
///     ModuleInit[] calldata executors,
///     ModuleInit[] calldata fallbacks,
///     ModuleInit[] calldata hooks,
///     address[] calldata attesters,
///     uint8 threshold
/// ) external;
/// ```
String encodeInitSafe7579({
  required EthAddress safe7579,
  required List<(EthAddress module, String initData)> executors,
  required List<(EthAddress module, String initData)> fallbacks,
  required List<(EthAddress module, String initData)> hooks,
  required List<EthAddress> attesters,
  required int threshold,
}) {
  // Sort attesters by address (lowercase comparison)
  final sortedAttesters = List<EthAddress>.from(attesters)
    ..sort((a, b) => a.hex.toLowerCase().compareTo(b.hex.toLowerCase()));

  // Encode each dynamic array
  final executorsEncoded = _encodeModuleInitArray(executors);
  final fallbacksEncoded = _encodeModuleInitArray(fallbacks);
  final hooksEncoded = _encodeModuleInitArray(hooks);
  final attestersEncoded = _encodeAddressArray(sortedAttesters);

  // Calculate offsets
  // Static parts: safe7579 (32) + 4 offsets (4*32) + threshold (32) = 192
  const staticSize = 6 * 32;
  const executorsOffset = staticSize;
  final fallbacksOffset = executorsOffset + Hex.byteLength(executorsEncoded);
  final hooksOffset = fallbacksOffset + Hex.byteLength(fallbacksEncoded);
  final attestersOffset = hooksOffset + Hex.byteLength(hooksEncoded);

  return Hex.concat([
    Safe7579Selectors.initSafe7579,
    AbiEncoder.encodeAddress(safe7579),
    AbiEncoder.encodeUint256(BigInt.from(executorsOffset)),
    AbiEncoder.encodeUint256(BigInt.from(fallbacksOffset)),
    AbiEncoder.encodeUint256(BigInt.from(hooksOffset)),
    AbiEncoder.encodeUint256(BigInt.from(attestersOffset)),
    AbiEncoder.encodeUint256(BigInt.from(threshold)),
    Hex.strip0x(executorsEncoded),
    Hex.strip0x(fallbacksEncoded),
    Hex.strip0x(hooksEncoded),
    Hex.strip0x(attestersEncoded),
  ]);
}

/// Encodes the `preValidationSetup` function call.
///
/// Function signature:
/// ```solidity
/// function preValidationSetup(
///     bytes32 initHash,
///     address to,
///     bytes calldata preInit
/// ) external;
/// ```
String encodePreValidationSetup({
  required String initHash,
  required EthAddress to,
  required String preInit,
}) {
  const preInitOffset = 3 * 32; // 3 static parameters
  final preInitEncoded = AbiEncoder.encodeBytes(preInit);

  return Hex.concat([
    Safe7579Selectors.preValidationSetup,
    Hex.strip0x(AbiEncoder.encodeBytes32(initHash)),
    AbiEncoder.encodeAddress(to),
    AbiEncoder.encodeUint256(BigInt.from(preInitOffset)),
    Hex.strip0x(preInitEncoded),
  ]);
}

/// Data structure for Safe 7579 initialization.
class Safe7579InitData {
  const Safe7579InitData({
    required this.singleton,
    required this.owners,
    required this.threshold,
    required this.setupTo,
    required this.setupData,
    required this.safe7579,
    required this.validators,
    required this.callData,
  });

  final EthAddress singleton;
  final List<EthAddress> owners;
  final BigInt threshold;
  final EthAddress setupTo;
  final String setupData;
  final EthAddress safe7579;
  final List<(EthAddress module, String initData)> validators;
  final String callData;
}

/// Encodes the `setupSafe` function call for Safe 7579.
///
/// This is called during the first UserOperation to initialize the Safe
/// with ERC-7579 support.
String encodeSetupSafe(Safe7579InitData initData) {
  // The initData struct has these fields:
  // - address singleton
  // - address[] owners
  // - uint256 threshold
  // - address setupTo
  // - bytes setupData
  // - address safe7579
  // - ModuleInit[] validators
  // - bytes callData

  // Encode dynamic fields
  final ownersEncoded = _encodeAddressArray(initData.owners);
  final setupDataEncoded = AbiEncoder.encodeBytes(initData.setupData);
  final validatorsEncoded = _encodeModuleInitArray(initData.validators);
  final callDataEncoded = AbiEncoder.encodeBytes(initData.callData);

  // Calculate offsets for tuple encoding
  // The tuple is passed as a single parameter, so offset 32 points to it
  // Inside the tuple:
  // - singleton (32)
  // - owners offset (32)
  // - threshold (32)
  // - setupTo (32)
  // - setupData offset (32)
  // - safe7579 (32)
  // - validators offset (32)
  // - callData offset (32)
  // Total static: 8 * 32 = 256

  const tupleStaticSize = 8 * 32;
  const ownersOffset = tupleStaticSize;
  final setupDataOffset = ownersOffset + Hex.byteLength(ownersEncoded);
  final validatorsOffset = setupDataOffset + Hex.byteLength(setupDataEncoded);
  final callDataOffset = validatorsOffset + Hex.byteLength(validatorsEncoded);

  // Encode the inner tuple
  final tupleData = Hex.concat([
    AbiEncoder.encodeAddress(initData.singleton),
    AbiEncoder.encodeUint256(BigInt.from(ownersOffset)),
    AbiEncoder.encodeUint256(initData.threshold),
    AbiEncoder.encodeAddress(initData.setupTo),
    AbiEncoder.encodeUint256(BigInt.from(setupDataOffset)),
    AbiEncoder.encodeAddress(initData.safe7579),
    AbiEncoder.encodeUint256(BigInt.from(validatorsOffset)),
    AbiEncoder.encodeUint256(BigInt.from(callDataOffset)),
    Hex.strip0x(ownersEncoded),
    Hex.strip0x(setupDataEncoded),
    Hex.strip0x(validatorsEncoded),
    Hex.strip0x(callDataEncoded),
  ]);

  // The function takes a single tuple parameter, so offset to the tuple is 32
  return Hex.concat([
    Safe7579Selectors.setupSafe,
    AbiEncoder.encodeUint256(BigInt.from(32)), // Offset to tuple
    Hex.strip0x(tupleData),
  ]);
}

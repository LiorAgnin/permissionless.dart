import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/erc7579.dart';
import '../../utils/sort_addresses.dart';
import 'multisend.dart';
import 'safe_abi.dart';

/// Common function selectors for Safe contracts.
///
/// Contains 4-byte function selectors used for encoding Safe contract calls.
class SafeSelectors {
  SafeSelectors._();

  /// Selector for Safe singleton `setup` function.
  static final String setup = AbiEncoder.functionSelector(safeSetupSignature);

  /// Selector for Safe 4337 module `executeUserOp` function.
  static final String executeUserOp =
      AbiEncoder.functionSelector(safeExecuteUserOpSignature);

  /// Selector for Safe 4337 module `executeUserOpWithErrorString` function.
  static final String executeUserOpWithErrorString =
      AbiEncoder.functionSelector(safeExecuteUserOpWithErrorStringSignature);

  /// Selector for Safe proxy factory `createProxyWithNonce` function.
  static final String createProxyWithNonce =
      AbiEncoder.functionSelector(safeCreateProxyWithNonceSignature);

  /// Selector for Safe module setup `enableModules` function.
  static final String enableModules =
      AbiEncoder.functionSelector(safeEnableModulesSignature);

  /// Selector for MultiSend `multiSend` function.
  static final String multiSend =
      AbiEncoder.functionSelector(safeMultiSendSignature);

  /// Selector for SafeProxyFactory `proxyCreationCode` function.
  static final String proxyCreationCode =
      AbiEncoder.functionSelector(safeProxyCreationCodeSignature);
}

/// Encodes a Safe `setup` function call.
String encodeSafeSetup({
  required List<EthereumAddress> owners,
  required BigInt threshold,
  required EthereumAddress to,
  required String data,
  required EthereumAddress fallbackHandler,
  required EthereumAddress paymentToken,
  required BigInt payment,
  required EthereumAddress paymentReceiver,
}) =>
    AbiEncoder.encodeFunctionData(safeSetupSignature, [
      owners,
      threshold,
      to,
      data,
      fallbackHandler,
      paymentToken,
      payment,
      paymentReceiver,
    ]);

/// Encodes an `enableModules` call for Safe module setup.
String encodeEnableModules(List<EthereumAddress> modules) =>
    AbiEncoder.encodeFunctionData(safeEnableModulesSignature, [modules]);

/// Encodes an `executeUserOpWithErrorString` call.
///
/// [operation] is the Safe operation type (0 = call, 1 = delegatecall).
/// Throws an [ArgumentError] if it does not fit in uint8.
String encodeExecuteUserOp({
  required EthereumAddress to,
  required BigInt value,
  required String data,
  required int operation,
}) =>
    AbiEncoder.encodeFunctionData(safeExecuteUserOpWithErrorStringSignature, [
      to,
      value,
      data,
      _uint8(operation, 'operation'),
    ]);

/// Encodes a `createProxyWithNonce` call.
String encodeCreateProxyWithNonce({
  required EthereumAddress singleton,
  required String initializer,
  required BigInt saltNonce,
}) =>
    AbiEncoder.encodeFunctionData(
      safeCreateProxyWithNonceSignature,
      [singleton, initializer, saltNonce],
    );

/// Function selectors for Safe 7579 contracts.
class Safe7579Selectors {
  Safe7579Selectors._();

  /// initSafe7579(address,tuple[],tuple[],tuple[],address[],uint8)
  static final String initSafe7579 =
      AbiEncoder.functionSelector(safe7579InitSignature);

  /// preValidationSetup(bytes32,address,bytes)
  static final String preValidationSetup =
      AbiEncoder.functionSelector(safe7579PreValidationSetupSignature);

  /// setupSafe(tuple)
  /// The tuple contains the full Safe7579 init data
  static final String setupSafe =
      AbiEncoder.functionSelector(safe7579SetupSafeSignature);
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
///
/// [attesters] are sorted ascending, as permissionless.js does. Throws an
/// [ArgumentError] if [threshold] does not fit in uint8.
String encodeInitSafe7579({
  required EthereumAddress safe7579,
  required List<(EthereumAddress module, String initData)> executors,
  required List<(EthereumAddress module, String initData)> fallbacks,
  required List<(EthereumAddress module, String initData)> hooks,
  required List<EthereumAddress> attesters,
  required int threshold,
}) =>
    AbiEncoder.encodeFunctionData(safe7579InitSignature, [
      safe7579,
      _moduleInits(executors),
      _moduleInits(fallbacks),
      _moduleInits(hooks),
      sortAddresses(attesters),
      _uint8(threshold, 'threshold'),
    ]);

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
///
/// An [initHash] shorter than 32 bytes is right-padded with zeros.
String encodePreValidationSetup({
  required String initHash,
  required EthereumAddress to,
  required String preInit,
}) =>
    AbiEncoder.encodeFunctionData(
      safe7579PreValidationSetupSignature,
      [Hex.padRight(initHash, 32), to, preInit],
    );

/// Data structure for Safe 7579 initialization.
///
/// Contains all parameters needed to initialize a Safe account with
/// ERC-7579 module support via the Safe7579 launchpad.
class Safe7579InitData {
  /// Creates initialization data for a Safe 7579 deployment.
  ///
  /// All fields correspond to the `InitData` struct in the Safe7579 launchpad.
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

  /// The Safe singleton (implementation) contract address.
  final EthereumAddress singleton;

  /// List of initial Safe owners.
  final List<EthereumAddress> owners;

  /// Number of required owner signatures for transactions.
  final BigInt threshold;

  /// Address of the setup contract to delegate call during initialization.
  final EthereumAddress setupTo;

  /// Calldata for the setup delegate call.
  final String setupData;

  /// The Safe7579 adapter module address.
  final EthereumAddress safe7579;

  /// List of ERC-7579 validators to install during initialization.
  final List<(EthereumAddress module, String initData)> validators;

  /// Additional calldata to execute after Safe initialization.
  final String callData;

  List<Object> get _hashedFields => [
        singleton,
        owners,
        threshold,
        setupTo,
        setupData,
        safe7579,
        _moduleInits(validators),
      ];
}

/// Encodes the `setupSafe` function call for Safe 7579.
///
/// This is called during the first UserOperation to initialize the Safe
/// with ERC-7579 support.
String encodeSetupSafe(Safe7579InitData initData) =>
    AbiEncoder.encodeFunctionData(safe7579SetupSafeSignature, [
      [...initData._hashedFields, initData.callData],
    ]);

/// The launchpad `initHash`: keccak256 of the ABI-encoded [initData]
/// without its `callData`.
String safe7579InitHash(Safe7579InitData initData) {
  // abi.encode(fields) is the calldata of a function taking them, minus
  // its 4-byte selector.
  final encoded = Hex.slice(
    AbiEncoder.encodeFunctionData(
      safe7579InitHashFieldsSignature,
      initData._hashedFields,
    ),
    4,
  );
  return Hex.fromBytes(keccak256(Hex.decode(encoded)));
}

/// Decodes `executeUserOpWithErrorString`, unpacking the MultiSend payload
/// when the call targets one of [multiSendAddresses].
List<Call> decodeSafeExecuteUserOp(
  String callData, {
  required Set<EthereumAddress> multiSendAddresses,
}) {
  final args = AbiEncoder.decodeFunctionData(
    safeExecuteUserOpWithErrorStringSignature,
    callData,
  );
  final to = args[0] as EthereumAddress;
  final data = Hex.fromBytes(args[2] as Uint8List);
  if (multiSendAddresses.contains(to)) {
    return decodeMultiSend(data);
  }
  return [Call(to: to, value: args[1] as BigInt, data: data)];
}

/// Decodes `setupSafe` and returns the calls in its embedded ERC-7579
/// `callData`.
List<Call> decodeSafeSetupSafe(String callData) {
  final initData =
      AbiEncoder.decodeFunctionData(safe7579SetupSafeSignature, callData)[0]
          as List;
  return decode7579Calls(Hex.fromBytes(initData.last as Uint8List)).calls;
}

List<List<Object>> _moduleInits(
  List<(EthereumAddress module, String initData)> modules,
) =>
    [
      for (final (module, initData) in modules) [module, initData],
    ];

int _uint8(int value, String name) {
  if (value < 0 || value > 0xff) {
    throw ArgumentError.value(value, name, 'must fit in uint8');
  }
  return value;
}

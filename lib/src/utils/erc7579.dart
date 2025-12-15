import 'dart:typed_data';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import 'encoding.dart';

/// ERC-7579 module types as defined in the specification.
///
/// Each module type serves a specific purpose in the modular account:
/// - **Validator**: Validates signatures and authorizes operations
/// - **Executor**: Can execute transactions on behalf of the account
/// - **Fallback**: Handles calls to functions not defined on the account
/// - **Hook**: Executes before/after other operations (pre/post hooks)
enum Erc7579ModuleType {
  /// Validators verify signatures and authorize user operations.
  ///
  /// Example: ECDSA validator, passkey validator, multisig validator.
  validator(1),

  /// Executors can call the account's execute function.
  ///
  /// Example: Session key module, automation module.
  executor(2),

  /// Fallback handlers respond to calls the account doesn't recognize.
  ///
  /// Example: ERC-721 receiver, custom function handlers.
  fallback(3),

  /// Hooks run before and/or after executions.
  ///
  /// Example: Spending limits, allowlist enforcement.
  hook(4);

  const Erc7579ModuleType(this.id);

  /// The numeric identifier for this module type.
  final int id;
}

/// ERC-7579 call types for smart account execution.
class Erc7579CallType {
  Erc7579CallType._();

  /// Single call execution.
  static const int call = 0x00;

  /// Batch call execution.
  static const int batchCall = 0x01;

  /// Delegate call execution.
  static const int delegateCall = 0xff;
}

/// ERC-7579 execution types.
class Erc7579ExecType {
  Erc7579ExecType._();

  /// Default execution (revert on failure).
  static const int defaultExec = 0x00;

  /// Try execution (continue on failure).
  static const int tryExec = 0x01;
}

/// ERC-7579 function selectors.
class Erc7579Selectors {
  Erc7579Selectors._();

  /// execute(bytes32 mode, bytes executionCalldata)
  /// `keccak256("execute(bytes32,bytes)")[0:4]` = 0xe9ae5c53
  static const String execute = '0xe9ae5c53';

  /// installModule(uint256 moduleTypeId, address module, bytes initData)
  /// `keccak256("installModule(uint256,address,bytes)")[0:4]` = 0x9517e29f
  static const String installModule = '0x9517e29f';

  /// uninstallModule(uint256 moduleTypeId, address module, bytes deInitData)
  /// `keccak256("uninstallModule(uint256,address,bytes)")[0:4]` = 0xa4d6f1d2
  static const String uninstallModule = '0xa4d6f1d2';

  /// isModuleInstalled(uint256 moduleTypeId, address module, bytes additionalContext)
  /// `keccak256("isModuleInstalled(uint256,address,bytes)")[0:4]` = 0x6d61fe70
  static const String isModuleInstalled = '0x6d61fe70';

  /// supportsModule(uint256 moduleTypeId)
  /// `keccak256("supportsModule(uint256)")[0:4]` = 0x12d79da3
  static const String supportsModule = '0x12d79da3';

  /// accountId()
  /// `keccak256("accountId()")[0:4]` = 0x7b60424a
  static const String accountId = '0x7b60424a';

  /// supportsExecutionMode(bytes32 mode)
  /// `keccak256("supportsExecutionMode(bytes32)")[0:4]` = 0xd03c7914
  static const String supportsExecutionMode = '0xd03c7914';
}

/// Call type for ERC-7579 execution.
///
/// Determines how the execution calldata is interpreted.
enum Erc7579CallKind {
  /// Single call execution (target, value, calldata packed).
  call(0x00),

  /// Batch call execution (array of Execution structs).
  batchCall(0x01),

  /// Delegate call execution (target, calldata only, no value).
  delegateCall(0xff);

  const Erc7579CallKind(this.value);

  /// The byte value for this call type.
  final int value;

  /// Creates from a byte value.
  static Erc7579CallKind fromValue(int value) {
    switch (value) {
      case 0x00:
        return Erc7579CallKind.call;
      case 0x01:
        return Erc7579CallKind.batchCall;
      case 0xff:
        return Erc7579CallKind.delegateCall;
      default:
        throw ArgumentError('Unknown call type: $value');
    }
  }
}

/// Execution mode configuration for ERC-7579 accounts.
///
/// The execution mode determines how the account executes calls and
/// handles errors. It is encoded as a 32-byte value:
/// - Byte 0: Call type (call=0x00, batch=0x01, delegatecall=0xff)
/// - Byte 1: Revert behavior (0x00=revert on error, 0x01=try/continue)
/// - Bytes 2-5: Reserved (padding)
/// - Bytes 6-9: Optional function selector
/// - Bytes 10-31: Optional context data (22 bytes)
///
/// Example:
/// ```dart
/// // Default single call mode (reverts on error)
/// final mode = ExecutionMode(type: Erc7579CallKind.call);
///
/// // Batch call that continues on error
/// final batchMode = ExecutionMode(
///   type: Erc7579CallKind.batchCall,
///   revertOnError: false,
/// );
///
/// // Check if account supports a mode
/// final supported = await client.supportsExecutionMode(mode);
/// ```
class ExecutionMode {
  /// Creates an execution mode configuration.
  const ExecutionMode({
    required this.type,
    this.revertOnError = true,
    this.selector,
    this.context,
  });

  /// The type of call execution.
  final Erc7579CallKind type;

  /// Whether to revert the entire operation on error.
  ///
  /// When true (default), any error reverts the transaction.
  /// When false, errors are caught and execution continues (try mode).
  final bool revertOnError;

  /// Optional 4-byte function selector.
  ///
  /// Used for mode-specific routing in advanced use cases.
  /// Most operations leave this as null (encoded as 0x00000000).
  final String? selector;

  /// Optional 22-byte context data.
  ///
  /// Additional data that can be used by the account for mode-specific logic.
  /// Most operations leave this as null (encoded as zeros).
  final String? context;

  /// Encodes this execution mode as a 32-byte hex string.
  ///
  /// The encoding follows ERC-7579:
  /// - Byte 0: call type
  /// - Byte 1: exec type (0x00 if revertOnError, 0x01 if try)
  /// - Bytes 2-5: padding (zeros)
  /// - Bytes 6-9: selector (or zeros)
  /// - Bytes 10-31: context (or zeros)
  String encode() {
    final mode = Uint8List(32);

    // Byte 0: Call type
    mode[0] = type.value;

    // Byte 1: Exec type (0x00 = revert on error, 0x01 = try/continue)
    mode[1] = revertOnError ? 0x00 : 0x01;

    // Bytes 2-5: Reserved (already zeros)

    // Bytes 6-9: Selector (4 bytes)
    if (selector != null && selector!.isNotEmpty && selector != '0x') {
      final selectorBytes = Hex.decode(selector!);
      final len = selectorBytes.length.clamp(0, 4);
      for (var i = 0; i < len; i++) {
        mode[6 + i] = selectorBytes[i];
      }
    }

    // Bytes 10-31: Context (22 bytes)
    if (context != null && context!.isNotEmpty && context != '0x') {
      final contextBytes = Hex.decode(context!);
      final len = contextBytes.length.clamp(0, 22);
      for (var i = 0; i < len; i++) {
        mode[10 + i] = contextBytes[i];
      }
    }

    return Hex.fromBytes(mode);
  }

  @override
  String toString() =>
      'ExecutionMode(type: ${type.name}, revertOnError: $revertOnError)';
}

/// Encodes an ERC-7579 execution mode.
///
/// Mode is 32 bytes:
/// - callType (1 byte): 0x00=call, 0x01=batch, 0xff=delegateCall
/// - execType (1 byte): 0x00=default, 0x01=try
/// - unused (4 bytes): 0x00000000
/// - modeSelector (4 bytes): 0x00000000
/// - modePayload (22 bytes): 0x0...
String encode7579ExecuteMode({
  int callType = Erc7579CallType.call,
  int execType = Erc7579ExecType.defaultExec,
}) {
  final mode = Uint8List(32);
  mode[0] = callType;
  mode[1] = execType;
  // Remaining bytes are already zero
  return Hex.fromBytes(mode);
}

/// Encodes a single call for ERC-7579 execution.
///
/// Format: abi.encodePacked(target (20), value (32), callData (variable))
String encode7579SingleCallData(Call call) {
  final callDataBytes = Hex.decode(call.data);
  return Hex.concat([
    call.to.hex, // 20 bytes (no padding)
    Hex.fromBigInt(call.value, byteLength: 32), // 32 bytes
    Hex.fromBytes(callDataBytes), // Variable length
  ]);
}

/// Encodes multiple calls for ERC-7579 batch execution.
///
/// Format: abi.encode(Execution[])
/// Where Execution is (address target, uint256 value, bytes callData)
String encode7579BatchCallData(List<Call> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required for batch execution');
  }

  // Each Execution struct has 3 fields (address, uint256, bytes)
  // The bytes field is dynamic, so we need offset pointers

  // First, calculate the offset to the array data
  const arrayOffset = 32; // Single parameter (array)

  // Array length
  final arrayLength = AbiEncoder.encodeUint256(BigInt.from(calls.length));

  // Calculate offsets for each Execution struct
  // Each struct starts with offset to its data
  final structOffsets = <String>[];
  final structData = <String>[];

  // Base offset starts after array length and all struct offsets
  var currentOffset = calls.length * 32;

  for (final call in calls) {
    // Add offset to this struct
    structOffsets.add(AbiEncoder.encodeUint256(BigInt.from(currentOffset)));

    // Encode the struct: (address, uint256, bytes)
    final encodedStruct = _encodeExecutionStruct(call);
    structData.add(encodedStruct);

    // Update offset for next struct
    currentOffset += Hex.byteLength(encodedStruct);
  }

  return Hex.concat([
    // Offset to array
    AbiEncoder.encodeUint256(BigInt.from(arrayOffset)),
    // Array length
    arrayLength,
    // Struct offsets
    ...structOffsets,
    // Struct data
    ...structData,
  ]);
}

/// Encodes a single Execution struct for batch calls.
///
/// Format: (address target, uint256 value, bytes callData)
String _encodeExecutionStruct(Call call) {
  final callDataEncoded = AbiEncoder.encodeBytes(call.data);

  // Struct has 3 fields: address (static), uint256 (static), bytes (dynamic)
  // Offset for bytes is 3 * 32 = 96
  const bytesOffset = 3 * 32;

  return Hex.concat([
    AbiEncoder.encodeAddress(call.to),
    AbiEncoder.encodeUint256(call.value),
    AbiEncoder.encodeUint256(BigInt.from(bytesOffset)),
    Hex.strip0x(callDataEncoded),
  ]);
}

/// Encodes a complete ERC-7579 execute call (single call).
///
/// Generates: execute(mode, executionCalldata) with single call encoding.
String encode7579Execute(Call call) {
  final mode = encode7579ExecuteMode(callType: Erc7579CallType.call);
  final executionData = encode7579SingleCallData(call);

  // Encode the execute function call
  // execute(bytes32 mode, bytes executionCalldata)
  const executionDataOffset = 2 * 32; // mode (32) + offset pointer (32)
  final executionDataEncoded = AbiEncoder.encodeBytes(executionData);

  return Hex.concat([
    Erc7579Selectors.execute,
    Hex.strip0x(mode), // bytes32 mode (no padding needed, already 32 bytes)
    AbiEncoder.encodeUint256(BigInt.from(executionDataOffset)),
    Hex.strip0x(executionDataEncoded),
  ]);
}

/// Encodes a complete ERC-7579 execute call (batch calls).
///
/// Generates: execute(mode, executionCalldata) with batch call encoding.
String encode7579ExecuteBatch(List<Call> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required');
  }

  // Single call optimization
  if (calls.length == 1) {
    return encode7579Execute(calls.first);
  }

  final mode = encode7579ExecuteMode(callType: Erc7579CallType.batchCall);
  final executionData = encode7579BatchCallData(calls);

  // Encode the execute function call
  const executionDataOffset = 2 * 32;
  final executionDataEncoded = AbiEncoder.encodeBytes(executionData);

  return Hex.concat([
    Erc7579Selectors.execute,
    Hex.strip0x(mode),
    AbiEncoder.encodeUint256(BigInt.from(executionDataOffset)),
    Hex.strip0x(executionDataEncoded),
  ]);
}

// ============================================================================
// Module Management Encoding
// ============================================================================

/// Encodes an ERC-7579 installModule call.
///
/// Generates calldata for: installModule(uint256 moduleTypeId, address module, bytes initData)
///
/// The [initData] is passed to the module's onInstall function. Its format
/// depends on the specific module being installed.
///
/// Example:
/// ```dart
/// final callData = encode7579InstallModule(
///   moduleType: Erc7579ModuleType.validator,
///   module: ecdsaValidatorAddress,
///   initData: encodedOwnerAddress, // Module-specific init data
/// );
/// ```
String encode7579InstallModule({
  required Erc7579ModuleType moduleType,
  required EthAddress module,
  String initData = '0x',
}) {
  // Function signature: installModule(uint256, address, bytes)
  // Static params: moduleTypeId (32) + module (32) + offset to bytes (32) = 96
  const initDataOffset = 3 * 32;
  final initDataEncoded = AbiEncoder.encodeBytes(initData);

  return Hex.concat([
    Erc7579Selectors.installModule,
    AbiEncoder.encodeUint256(BigInt.from(moduleType.id)),
    AbiEncoder.encodeAddress(module),
    AbiEncoder.encodeUint256(BigInt.from(initDataOffset)),
    Hex.strip0x(initDataEncoded),
  ]);
}

/// Encodes an ERC-7579 uninstallModule call.
///
/// Generates calldata for: uninstallModule(uint256 moduleTypeId, address module, bytes deInitData)
///
/// The [deInitData] is passed to the module's onUninstall function. Its format
/// depends on the specific module being uninstalled.
///
/// Example:
/// ```dart
/// final callData = encode7579UninstallModule(
///   moduleType: Erc7579ModuleType.validator,
///   module: oldValidatorAddress,
///   deInitData: '0x', // Module-specific cleanup data
/// );
/// ```
String encode7579UninstallModule({
  required Erc7579ModuleType moduleType,
  required EthAddress module,
  String deInitData = '0x',
}) {
  // Function signature: uninstallModule(uint256, address, bytes)
  const deInitDataOffset = 3 * 32;
  final deInitDataEncoded = AbiEncoder.encodeBytes(deInitData);

  return Hex.concat([
    Erc7579Selectors.uninstallModule,
    AbiEncoder.encodeUint256(BigInt.from(moduleType.id)),
    AbiEncoder.encodeAddress(module),
    AbiEncoder.encodeUint256(BigInt.from(deInitDataOffset)),
    Hex.strip0x(deInitDataEncoded),
  ]);
}

// ============================================================================
// Query Encoding (for eth_call)
// ============================================================================

/// Encodes an ERC-7579 isModuleInstalled call for use with eth_call.
///
/// Generates calldata for: isModuleInstalled(uint256 moduleTypeId, address module, bytes additionalContext)
///
/// The [additionalContext] is typically empty ('0x') but some modules may
/// require additional data for the check.
///
/// Example:
/// ```dart
/// final callData = encode7579IsModuleInstalled(
///   moduleType: Erc7579ModuleType.validator,
///   module: validatorAddress,
/// );
/// final result = await publicClient.call(Call(to: account, data: callData));
/// final isInstalled = decode7579BoolResult(result);
/// ```
String encode7579IsModuleInstalled({
  required Erc7579ModuleType moduleType,
  required EthAddress module,
  String additionalContext = '0x',
}) {
  // Function signature: isModuleInstalled(uint256, address, bytes)
  const contextOffset = 3 * 32;
  final contextEncoded = AbiEncoder.encodeBytes(additionalContext);

  return Hex.concat([
    Erc7579Selectors.isModuleInstalled,
    AbiEncoder.encodeUint256(BigInt.from(moduleType.id)),
    AbiEncoder.encodeAddress(module),
    AbiEncoder.encodeUint256(BigInt.from(contextOffset)),
    Hex.strip0x(contextEncoded),
  ]);
}

/// Encodes an ERC-7579 supportsModule call for use with eth_call.
///
/// Generates calldata for: supportsModule(uint256 moduleTypeId)
///
/// Use this to check if an account supports a particular module type
/// before attempting to install a module of that type.
///
/// Example:
/// ```dart
/// final callData = encode7579SupportsModule(Erc7579ModuleType.hook);
/// final result = await publicClient.call(Call(to: account, data: callData));
/// final supportsHooks = decode7579BoolResult(result);
/// ```
String encode7579SupportsModule(Erc7579ModuleType moduleType) => Hex.concat([
      Erc7579Selectors.supportsModule,
      AbiEncoder.encodeUint256(BigInt.from(moduleType.id)),
    ]);

/// Encodes an ERC-7579 supportsExecutionMode call for use with eth_call.
///
/// Generates calldata for: supportsExecutionMode(bytes32 mode)
///
/// Use this to check if an account supports a particular execution mode
/// before attempting to execute with that mode.
///
/// Example:
/// ```dart
/// final mode = ExecutionMode(
///   type: Erc7579CallKind.batchCall,
///   revertOnError: false,
/// );
/// final callData = encode7579SupportsExecutionMode(mode);
/// final result = await publicClient.call(Call(to: account, data: callData));
/// final supported = decode7579BoolResult(result);
/// ```
String encode7579SupportsExecutionMode(ExecutionMode mode) => Hex.concat([
      Erc7579Selectors.supportsExecutionMode,
      Hex.strip0x(mode.encode()), // bytes32 mode (already 32 bytes)
    ]);

/// Encodes an ERC-7579 accountId call for use with eth_call.
///
/// Generates calldata for: accountId()
///
/// Returns a unique identifier for the account implementation.
/// Format: "vendorname.accountname.semver"
///
/// Example:
/// ```dart
/// final callData = encode7579AccountId();
/// final result = await publicClient.call(Call(to: account, data: callData));
/// final accountId = decode7579StringResult(result); // e.g., "kernel.advanced.0.3.1"
/// ```
String encode7579AccountId() => Erc7579Selectors.accountId;

// ============================================================================
// Result Decoding
// ============================================================================

/// Decodes a boolean result from an eth_call response.
///
/// Returns true if the result is non-zero, false otherwise.
/// Handles empty responses as false.
bool decode7579BoolResult(String hexResult) {
  if (hexResult == '0x' || hexResult.isEmpty) {
    return false;
  }

  final hex = Hex.strip0x(hexResult);
  if (hex.isEmpty) {
    return false;
  }

  return BigInt.parse(hex, radix: 16) != BigInt.zero;
}

/// Decodes a string result from an eth_call response.
///
/// ABI-encoded strings have the format:
/// - bytes 0-31: offset to string data (usually 32)
/// - bytes 32-63: string length
/// - bytes 64+: string data (UTF-8 encoded)
String decode7579StringResult(String hexResult) {
  if (hexResult == '0x' || hexResult.isEmpty) {
    return '';
  }

  final hex = Hex.strip0x(hexResult);
  if (hex.length < 128) {
    // Need at least offset (64 chars) + length (64 chars)
    return '';
  }

  // Skip offset (first 32 bytes = 64 hex chars)
  // Read length (next 32 bytes = 64 hex chars)
  final lengthHex = hex.substring(64, 128);
  final length = int.parse(lengthHex, radix: 16);

  if (length == 0) {
    return '';
  }

  // Read string data (length bytes after the length field)
  final dataHex = hex.substring(128, 128 + length * 2);
  final bytes = Hex.decode('0x$dataHex');

  return String.fromCharCodes(bytes);
}

// ============================================================================
// Module Configuration Types
// ============================================================================

/// Configuration for installing a module.
class InstallModuleConfig {
  /// Creates a module installation configuration.
  const InstallModuleConfig({
    required this.type,
    required this.address,
    this.initData = '0x',
  });

  /// The type of module to install.
  final Erc7579ModuleType type;

  /// The address of the module contract.
  final EthAddress address;

  /// Initialization data passed to the module's onInstall function.
  final String initData;
}

/// Configuration for uninstalling a module.
class UninstallModuleConfig {
  /// Creates a module uninstallation configuration.
  const UninstallModuleConfig({
    required this.type,
    required this.address,
    this.deInitData = '0x',
  });

  /// The type of module to uninstall.
  final Erc7579ModuleType type;

  /// The address of the module contract.
  final EthAddress address;

  /// De-initialization data passed to the module's onUninstall function.
  final String deInitData;
}

// ============================================================================
// Nonce Encoding/Decoding (ERC-4337)
// ============================================================================

/// Result of decoding an ERC-4337 nonce.
///
/// The nonce is a 256-bit value composed of:
/// - Upper 192 bits: key (allows parallel transaction streams)
/// - Lower 64 bits: sequence (increments for each transaction with same key)
class DecodedNonce {
  const DecodedNonce({required this.key, required this.sequence});

  /// The nonce key (upper 192 bits).
  ///
  /// Different keys allow independent transaction sequences.
  /// Key 0 is the default sequential nonce.
  final BigInt key;

  /// The sequence number (lower 64 bits).
  ///
  /// Increments with each transaction using the same key.
  final BigInt sequence;

  @override
  String toString() => 'DecodedNonce(key: $key, sequence: $sequence)';
}

/// Decodes an ERC-4337 nonce into its key and sequence components.
///
/// The nonce is split as:
/// - Bits 64-255: key (192 bits)
/// - Bits 0-63: sequence (64 bits)
///
/// Example:
/// ```dart
/// final nonce = await publicClient.getAccountNonce(account, entryPoint);
/// final decoded = decodeNonce(nonce);
/// print('Key: ${decoded.key}, Sequence: ${decoded.sequence}');
/// ```
DecodedNonce decodeNonce(BigInt nonce) {
  // Lower 64 bits = sequence
  final sequence = nonce & BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);

  // Upper 192 bits = key (shift right by 64)
  final key = nonce >> 64;

  return DecodedNonce(key: key, sequence: sequence);
}

/// Encodes a key and sequence into an ERC-4337 nonce.
///
/// Combines a 192-bit key and 64-bit sequence into a 256-bit nonce.
///
/// Example:
/// ```dart
/// // Create a nonce with key=1, sequence=5
/// final nonce = encodeNonce(key: BigInt.one, sequence: BigInt.from(5));
/// ```
BigInt encodeNonce({required BigInt key, required BigInt sequence}) {
  // Mask key to 192 bits and sequence to 64 bits
  final maskedKey = key &
      BigInt.parse(
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        radix: 16,
      );
  final maskedSequence = sequence & BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);

  return (maskedKey << 64) + maskedSequence;
}

// ============================================================================
// Call Data Decoding
// ============================================================================

/// Result of decoding ERC-7579 execute call data.
class Decoded7579Calls {
  const Decoded7579Calls({
    required this.mode,
    required this.calls,
  });

  /// The execution mode used.
  final ExecutionMode mode;

  /// The decoded calls.
  final List<Call> calls;

  @override
  String toString() => 'Decoded7579Calls(mode: $mode, calls: ${calls.length})';
}

/// Decodes ERC-7579 execute call data back into mode and calls.
///
/// Reverses the encoding done by [encode7579Execute] or [encode7579ExecuteBatch].
///
/// Example:
/// ```dart
/// final decoded = decode7579Calls(userOperation.callData);
/// print('Mode: ${decoded.mode.type}');
/// for (final call in decoded.calls) {
///   print('  To: ${call.to}, Value: ${call.value}');
/// }
/// ```
///
/// Throws [ArgumentError] if the call data is invalid or not an ERC-7579 execute call.
Decoded7579Calls decode7579Calls(String callData) {
  final hex = Hex.strip0x(callData);

  // Minimum length: selector (8) + mode (64) + offset (64) = 136 chars
  if (hex.length < 136) {
    throw ArgumentError('Call data too short for ERC-7579 execute');
  }

  // Check function selector
  final selector = '0x${hex.substring(0, 8)}';
  if (selector != Erc7579Selectors.execute) {
    throw ArgumentError(
      'Invalid selector: expected ${Erc7579Selectors.execute}, got $selector',
    );
  }

  // Parse mode (bytes32 at offset 8-72)
  final modeHex = hex.substring(8, 72);
  final modeBytes = Hex.decode('0x$modeHex');

  // Decode mode components
  final callType = Erc7579CallKind.fromValue(modeBytes[0]);
  final revertOnError = modeBytes[1] == 0x00;

  // Bytes 6-9: selector (4 bytes)
  String? modeSelector;
  if (modeBytes[6] != 0 ||
      modeBytes[7] != 0 ||
      modeBytes[8] != 0 ||
      modeBytes[9] != 0) {
    modeSelector = Hex.fromBytes(Uint8List.fromList(modeBytes.sublist(6, 10)));
  }

  // Bytes 10-31: context (22 bytes)
  String? modeContext;
  var hasContext = false;
  for (var i = 10; i < 32; i++) {
    if (modeBytes[i] != 0) {
      hasContext = true;
      break;
    }
  }
  if (hasContext) {
    modeContext = Hex.fromBytes(Uint8List.fromList(modeBytes.sublist(10, 32)));
  }

  final mode = ExecutionMode(
    type: callType,
    revertOnError: revertOnError,
    selector: modeSelector,
    context: modeContext,
  );

  // Parse execution calldata offset (bytes 72-136)
  // final offsetHex = hex.substring(72, 136);
  // Offset should be 64 (0x40) pointing past mode and offset itself

  // Parse execution calldata length (at offset position)
  final lengthHex = hex.substring(136, 200);
  final length = int.parse(lengthHex, radix: 16);

  if (length == 0) {
    return Decoded7579Calls(mode: mode, calls: []);
  }

  // Extract execution calldata
  final executionHex = hex.substring(200, 200 + length * 2);

  // Decode based on call type
  if (callType == Erc7579CallKind.batchCall) {
    final calls = _decodeBatchCalls(executionHex);
    return Decoded7579Calls(mode: mode, calls: calls);
  } else {
    // Single call: packed as (address, value, calldata)
    final call = _decodeSingleCall(executionHex);
    return Decoded7579Calls(mode: mode, calls: [call]);
  }
}

/// Decodes a single call from packed format (address || value || data).
Call _decodeSingleCall(String executionHex) {
  // Address: 20 bytes (40 hex chars)
  final addressHex = executionHex.substring(0, 40);
  final to = EthAddress('0x$addressHex');

  // Value: 32 bytes (64 hex chars)
  final valueHex = executionHex.substring(40, 104);
  final value = BigInt.parse(valueHex, radix: 16);

  // Remaining: calldata
  final data =
      executionHex.length > 104 ? '0x${executionHex.substring(104)}' : '0x';

  return Call(to: to, value: value, data: data);
}

/// Decodes batch calls from ABI-encoded Execution[] array.
List<Call> _decodeBatchCalls(String executionHex) {
  // ABI encoded array:
  // - offset to array data (32 bytes)
  // - array length (32 bytes)
  // - offsets to each struct (32 bytes each)
  // - struct data

  if (executionHex.length < 128) {
    return [];
  }

  // Skip array offset, read length
  final lengthHex = executionHex.substring(64, 128);
  final arrayLength = int.parse(lengthHex, radix: 16);

  if (arrayLength == 0) {
    return [];
  }

  final calls = <Call>[];

  // Read struct offsets
  final offsets = <int>[];
  for (var i = 0; i < arrayLength; i++) {
    final offsetStart = 128 + (i * 64);
    final offsetHex = executionHex.substring(offsetStart, offsetStart + 64);
    offsets.add(int.parse(offsetHex, radix: 16));
  }

  // Decode each struct
  // Base for offsets is after the length field (position 64 = 32 bytes)
  const baseOffset = 64; // After array offset + length

  for (var i = 0; i < arrayLength; i++) {
    final structStart = (baseOffset + offsets[i]) * 2;

    // Each Execution struct: (address, uint256, bytes)
    // Address (32 bytes padded)
    final addressHex =
        executionHex.substring(structStart + 24, structStart + 64);
    final to = EthAddress('0x$addressHex');

    // Value (32 bytes)
    final valueHex =
        executionHex.substring(structStart + 64, structStart + 128);
    final value = BigInt.parse(valueHex, radix: 16);

    // Bytes offset (32 bytes) - points to bytes data relative to struct start
    final bytesOffsetHex =
        executionHex.substring(structStart + 128, structStart + 192);
    final bytesOffset = int.parse(bytesOffsetHex, radix: 16);

    // Bytes length
    final bytesLengthStart = structStart + (bytesOffset * 2);
    final bytesLengthHex =
        executionHex.substring(bytesLengthStart, bytesLengthStart + 64);
    final bytesLength = int.parse(bytesLengthHex, radix: 16);

    // Bytes data
    var data = '0x';
    if (bytesLength > 0) {
      final dataStart = bytesLengthStart + 64;
      final dataHex =
          executionHex.substring(dataStart, dataStart + bytesLength * 2);
      data = '0x$dataHex';
    }

    calls.add(Call(to: to, value: value, data: data));
  }

  return calls;
}

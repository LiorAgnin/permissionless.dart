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

/// ERC-7579 call type bytes (mode word byte 0), for the int-based
/// [encode7579ExecuteMode].
///
/// [Erc7579CallKind] is the typed form of the same values and takes its byte
/// values from these constants.
class Erc7579CallType {
  Erc7579CallType._();

  /// Single call execution.
  static const int call = 0x00;

  /// Batch call execution.
  static const int batchCall = 0x01;

  /// Delegate call execution.
  static const int delegateCall = 0xff;
}

/// ERC-7579 execution type bytes (mode word byte 1).
///
/// [ExecutionMode.revertOnError] maps `false` to [defaultExec] and `true` to
/// [tryExec].
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
  /// `keccak256("uninstallModule(uint256,address,bytes)")[0:4]` = 0xa71763a8
  static const String uninstallModule = '0xa71763a8';

  /// isModuleInstalled(uint256 moduleTypeId, address module, bytes additionalContext)
  /// `keccak256("isModuleInstalled(uint256,address,bytes)")[0:4]` = 0x112d3a7d
  static const String isModuleInstalled = '0x112d3a7d';

  /// supportsModule(uint256 moduleTypeId)
  /// `keccak256("supportsModule(uint256)")[0:4]` = 0xf2dc691d
  static const String supportsModule = '0xf2dc691d';

  /// accountId()
  /// `keccak256("accountId()")[0:4]` = 0x9cfd7cff
  static const String accountId = '0x9cfd7cff';

  /// supportsExecutionMode(bytes32 mode)
  /// `keccak256("supportsExecutionMode(bytes32)")[0:4]` = 0xd03c7914
  static const String supportsExecutionMode = '0xd03c7914';
}

const String _executeSignature = 'execute(bytes32,bytes)';
const String _installModuleSignature = 'installModule(uint256,address,bytes)';
const String _uninstallModuleSignature =
    'uninstallModule(uint256,address,bytes)';
const String _isModuleInstalledSignature =
    'isModuleInstalled(uint256,address,bytes)';
const String _supportsModuleSignature = 'supportsModule(uint256)';
const String _supportsExecutionModeSignature = 'supportsExecutionMode(bytes32)';

/// ERC-7579 batch execution calldata: `abi.encode(Execution[])`.
const List<String> _executionsAbi = ['(address,uint256,bytes)[]'];

/// Call type for ERC-7579 execution: the typed form of [Erc7579CallType].
///
/// Determines how the execution calldata is interpreted.
enum Erc7579CallKind {
  /// Single call execution (target, value, calldata packed).
  call(Erc7579CallType.call),

  /// Batch call execution (array of Execution structs).
  batchCall(Erc7579CallType.batchCall),

  /// Delegate call execution.
  delegateCall(Erc7579CallType.delegateCall);

  const Erc7579CallKind(this.value);

  /// The byte value for this call type.
  final int value;

  /// Creates from a byte value.
  static Erc7579CallKind fromValue(int value) => values.firstWhere(
        (kind) => kind.value == value,
        orElse: () => throw ArgumentError('Unknown call type: $value'),
      );
}

/// Execution mode configuration for ERC-7579 accounts.
///
/// The execution mode determines how the account executes calls and
/// handles errors. It is encoded as a 32-byte value:
/// - Byte 0: Call type (call=0x00, batch=0x01, delegatecall=0xff)
/// - Byte 1: Exec type (0x00=default/revert on failure, 0x01=try/continue)
/// - Bytes 2-5: Reserved (padding)
/// - Bytes 6-9: Optional function selector
/// - Bytes 10-31: Optional context data (22 bytes)
///
/// ## `revertOnError` polarity (permissionless.js parity)
///
/// The [revertOnError] flag matches permissionless.js `encodeExecutionMode`:
/// `true` → execType `0x01`, `false` → execType `0x00`.
///
/// That is **not** English/ERC-7579 naming: ERC-7579 `0x00` is default (revert
/// on failure) and `0x01` is try. Prefer thinking in execType bytes for on-chain
/// semantics; use [revertOnError] only when mirroring JS callers.
///
/// Example:
/// ```dart
/// // Default single call mode (execType 0x00 — reverts on failure)
/// final mode = ExecutionMode(type: Erc7579CallKind.call);
///
/// // Batch call with execType 0x01 (try / continue on error) — JS true
/// final batchMode = ExecutionMode(
///   type: Erc7579CallKind.batchCall,
///   revertOnError: true,
/// );
///
/// // Check if account supports a mode
/// final supported = await client.supportsExecutionMode(mode);
/// ```
class ExecutionMode {
  /// Creates an execution mode configuration.
  const ExecutionMode({
    required this.type,
    this.revertOnError = false,
    this.selector,
    this.context,
  });

  /// The type of call execution.
  final Erc7579CallKind type;

  /// permissionless.js-compatible flag mapped onto the ERC-7579 execType byte.
  ///
  /// Wire mapping (matches JS `encodeExecutionMode`):
  /// - `false` (default) → execType `0x00` (ERC-7579 default: revert on failure)
  /// - `true` → execType `0x01` (ERC-7579 try: continue on failure)
  ///
  /// The field name follows permissionless.js, not the English meaning of
  /// "revert on error".
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
  /// The encoding follows ERC-7579 layout with permissionless.js polarity:
  /// - Byte 0: call type
  /// - Byte 1: exec type (`0x01` if [revertOnError], else `0x00`)
  /// - Bytes 2-5: padding (zeros)
  /// - Bytes 6-9: selector (or zeros)
  /// - Bytes 10-31: context (or zeros)
  ///
  /// A shorter [selector] or [context] is left-aligned in its field.
  /// Throws [ArgumentError] if [selector] is over 4 bytes or [context] is
  /// over 22 bytes (permissionless.js throws too).
  String encode() => _encodeExecutionMode(
        callType: type.value,
        execType: revertOnError
            ? Erc7579ExecType.tryExec
            : Erc7579ExecType.defaultExec,
        selector: selector,
        context: context,
      );

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
///
/// Throws [ArgumentError] if [callType] or [execType] does not fit in a byte.
String encode7579ExecuteMode({
  int callType = Erc7579CallType.call,
  int execType = Erc7579ExecType.defaultExec,
}) =>
    _encodeExecutionMode(callType: callType, execType: execType);

String _encodeExecutionMode({
  required int callType,
  required int execType,
  String? selector,
  String? context,
}) =>
    Hex.fromBytes(
      Uint8List(32)
        ..[0] = _modeByte(callType, 'callType')
        ..[1] = _modeByte(execType, 'execType')
        ..setAll(6, _modeField(selector, 4, 'selector'))
        ..setAll(10, _modeField(context, 22, 'context')),
    );

int _modeByte(int value, String name) {
  if (value < 0 || value > 0xff) {
    throw ArgumentError.value(value, name, 'must fit in one byte');
  }
  return value;
}

Uint8List _modeField(String? hex, int size, String name) {
  final bytes = hex == null ? Uint8List(0) : Hex.decode(hex);
  if (bytes.length > size) {
    throw ArgumentError.value(hex, name, 'must be at most $size bytes');
  }
  return bytes;
}

/// Encodes a single call for ERC-7579 execution.
///
/// Format: abi.encodePacked(target (20), value (32), callData (variable))
String encode7579SingleCallData(Call call) {
  final callDataBytes = Hex.decode(call.data);
  return Hex.concat([
    call.to.hex,
    Hex.fromBigInt(call.value, byteLength: 32),
    Hex.fromBytes(callDataBytes),
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
  return AbiEncoder.encodeParameters(_executionsAbi, [
    [
      for (final call in calls) [call.to, call.value, call.data],
    ],
  ]);
}

/// Encodes a complete ERC-7579 execute call (single call).
///
/// Generates: execute(mode, executionCalldata) with single call encoding.
String encode7579Execute(Call call) =>
    _encodeExecute(Erc7579CallKind.call, encode7579SingleCallData(call));

/// Encodes a complete ERC-7579 execute call (batch calls).
///
/// Generates: execute(mode, executionCalldata) with batch call encoding
/// (`callType = 0x01`, `abi.encode(Execution[])`).
///
/// A single-element [calls] list still uses batch mode — it is **not**
/// silently downgraded to [encode7579Execute]. Callers that want call mode for
/// one item should use [encode7579Execute] (or branch on `calls.length` like
/// permissionless.js accounts do).
String encode7579ExecuteBatch(List<Call> calls) {
  if (calls.isEmpty) {
    throw ArgumentError('At least one call is required');
  }
  return _encodeExecute(
    Erc7579CallKind.batchCall,
    encode7579BatchCallData(calls),
  );
}

/// Encodes a complete ERC-7579 execute call as a delegatecall.
///
/// Generates: execute(mode, executionCalldata) with `callType = 0xff` and
/// packed single-call execution data (`to || value || data`), matching
/// permissionless.js `encode7579Calls` when `mode.type === "delegatecall"`.
String encode7579ExecuteDelegateCall(Call call) => _encodeExecute(
      Erc7579CallKind.delegateCall,
      encode7579SingleCallData(call),
    );

String _encodeExecute(Erc7579CallKind callType, String executionData) =>
    AbiEncoder.encodeFunctionData(_executeSignature, [
      ExecutionMode(type: callType).encode(),
      executionData,
    ]);

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
  required EthereumAddress module,
  String initData = '0x',
}) =>
    AbiEncoder.encodeFunctionData(
      _installModuleSignature,
      [moduleType.id, module, initData],
    );

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
  required EthereumAddress module,
  String deInitData = '0x',
}) =>
    AbiEncoder.encodeFunctionData(
      _uninstallModuleSignature,
      [moduleType.id, module, deInitData],
    );

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
  required EthereumAddress module,
  String additionalContext = '0x',
}) =>
    AbiEncoder.encodeFunctionData(
      _isModuleInstalledSignature,
      [moduleType.id, module, additionalContext],
    );

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
String encode7579SupportsModule(Erc7579ModuleType moduleType) =>
    AbiEncoder.encodeFunctionData(_supportsModuleSignature, [moduleType.id]);

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
///   revertOnError: true, // JS polarity → execType 0x01 (try)
/// );
/// final callData = encode7579SupportsExecutionMode(mode);
/// final result = await publicClient.call(Call(to: account, data: callData));
/// final supported = decode7579BoolResult(result);
/// ```
String encode7579SupportsExecutionMode(ExecutionMode mode) =>
    AbiEncoder.encodeFunctionData(
      _supportsExecutionModeSignature,
      [mode.encode()],
    );

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

/// Decodes an ABI-encoded `string` eth_call result (UTF-8).
///
/// Returns an empty string for empty call data (`0x`), which a contract
/// without the queried function returns.
String decode7579StringResult(String hexResult) {
  if (Hex.strip0x(hexResult).isEmpty) return '';
  return AbiEncoder.decodeParameters(['string'], hexResult).single as String;
}

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
  final EthereumAddress address;

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
  final EthereumAddress address;

  /// De-initialization data passed to the module's onUninstall function.
  final String deInitData;
}

/// Result of decoding an ERC-4337 nonce.
///
/// The nonce is a 256-bit value composed of:
/// - Upper 192 bits: key (allows parallel transaction streams)
/// - Lower 64 bits: sequence (increments for each transaction with same key)
class DecodedNonce {
  /// Creates a decoded nonce with the given key and sequence.
  ///
  /// This is returned by [decodeNonce] after splitting a 256-bit nonce.
  ///
  /// - [key]: The nonce key (upper 192 bits) for parallel transaction streams
  /// - [sequence]: The sequence number (lower 64 bits) within that key
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
  final sequence = nonce & BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);

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
  final maskedKey = key &
      BigInt.parse(
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        radix: 16,
      );
  final maskedSequence = sequence & BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);

  return (maskedKey << 64) + maskedSequence;
}

/// Result of decoding ERC-7579 execute call data.
class Decoded7579Calls {
  /// Creates a decoded ERC-7579 calls result.
  ///
  /// This is returned by [decode7579Calls] after parsing execute calldata.
  ///
  /// - [mode]: The execution mode (call type, revert behavior, etc.)
  /// - [calls]: The decoded list of calls to execute
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
/// Reverses the encoding done by [encode7579Execute], [encode7579ExecuteBatch],
/// or [encode7579ExecuteDelegateCall].
///
/// ## Mode layout (deliberate decode-offset stance)
///
/// Mode is decoded with the ERC-7579 layout used by both this library's encoder
/// and permissionless.js `encodeExecutionMode`:
/// `callType(1) | execType(1) | unused(4) | modeSelector(4 @ bytes 6-9) |
/// modePayload(22 @ bytes 10-31)`.
///
/// permissionless.js `decode7579Calls` currently slices selector/context at
/// bytes 3-6 / 7-31 (lossy vs its own encoder). Dart **keeps** the
/// spec-aligned offsets so encode→decode round-trips of non-zero selector /
/// context succeed. Cross-port comparisons of decoded `selector`/`context`
/// against JS decode output will differ for non-zero fields.
///
/// [ExecutionMode.revertOnError] uses permissionless.js polarity:
/// execType `0x01` → `true`, `0x00` → `false`.
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
  if (Hex.byteLength(callData) < 68) {
    throw ArgumentError('Call data too short for ERC-7579 execute');
  }
  final args = AbiEncoder.decodeFunctionData(_executeSignature, callData);
  final modeBytes = args[0] as Uint8List;
  final executionData = Hex.fromBytes(args[1] as Uint8List);

  final callType = Erc7579CallKind.fromValue(modeBytes[0]);
  // Bytes 6-9 selector / 10-31 context: ERC-7579 / JS encoder layout (not
  // JS decode).
  final modeSelector = Hex.fromBytes(modeBytes.sublist(6, 10));
  final modeContext = Hex.fromBytes(modeBytes.sublist(10, 32));
  final mode = ExecutionMode(
    type: callType,
    // permissionless.js: revertOnError === (execType == 0x01)
    revertOnError: modeBytes[1] == 0x01,
    selector: _isZero(modeSelector) ? null : modeSelector,
    context: _isZero(modeContext) ? null : modeContext,
  );

  if (executionData == '0x') {
    return Decoded7579Calls(mode: mode, calls: []);
  }
  if (callType == Erc7579CallKind.batchCall) {
    final executions =
        AbiEncoder.decodeParameters(_executionsAbi, executionData)[0];
    return Decoded7579Calls(
      mode: mode,
      calls: [
        for (final e in (executions as List).cast<List<dynamic>>())
          Call(
            to: e[0] as EthereumAddress,
            value: e[1] as BigInt,
            data: Hex.fromBytes(e[2] as Uint8List),
          ),
      ],
    );
  }
  return Decoded7579Calls(
    mode: mode,
    calls: [
      Call(
        to: EthereumAddress.fromHex(Hex.slice(executionData, 0, 20)),
        value: Hex.toBigInt(Hex.slice(executionData, 20, 52)),
        data: Hex.slice(executionData, 52),
      ),
    ],
  );
}

bool _isZero(String hex) => Hex.toBigInt(hex) == BigInt.zero;

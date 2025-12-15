import 'address.dart';
import 'hex.dart';

/// EntryPoint contract version for ERC-4337.
///
/// The EntryPoint is the singleton contract that handles UserOperation
/// validation and execution. Different versions have different features
/// and UserOperation formats.
///
/// ## Versions
/// - **v0.6**: Original specification, widely deployed
/// - **v0.7**: Updated spec with separate factory/paymaster fields,
///   better gas handling, and uint128 gas limits
enum EntryPointVersion {
  /// EntryPoint v0.6 - Original ERC-4337 specification.
  ///
  /// Address: `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`
  v06('0.6'),

  /// EntryPoint v0.7 - Updated specification with improved gas handling.
  ///
  /// Address: `0x0000000071727De22E5E9d8BAf0edAc6f37da032`
  v07('0.7'),

  /// EntryPoint v0.8 - Latest specification with EIP-7702 support.
  ///
  /// Address: `0x4337084d9e255ff0702461cf8895ce9e3b5ff108`
  /// This version adds native EIP-7702 support including:
  /// - UserOperation hash includes EIP-7702 delegation address
  /// - EntryPoint checks delegation address is set correctly
  /// - Support for `eip7702Auth` parameter in eth_sendUserOperation
  v08('0.8');

  const EntryPointVersion(this.value);

  /// The version string (e.g., "0.6", "0.7", or "0.8").
  final String value;
}

/// Base type for ERC-4337 User Operations.
///
/// A UserOperation is the "transaction" in account abstraction. Instead of
/// sending a regular Ethereum transaction, users create a UserOperation that
/// describes what their smart account should do. The UserOperation is then
/// sent to a bundler, which packages it into a real transaction.
///
/// ## Key Concepts
/// - **sender**: The smart account address that will execute the operation
/// - **nonce**: Prevents replay attacks, can be 2D for parallel transactions
/// - **callData**: The encoded function call(s) the account will execute
/// - **signature**: Proof that the account owner(s) authorized this operation
///
/// ## Usage
/// This sealed class allows type-safe handling of both v0.6 and v0.7
/// UserOperations. Use [UserOperationV06] for EntryPoint v0.6 or
/// [UserOperationV07] for EntryPoint v0.7.
sealed class UserOperation {
  /// The smart account address that will execute this operation.
  ///
  /// This is the counterfactual address if the account isn't deployed yet.
  EthAddress get sender;

  /// The account's nonce to prevent replay attacks.
  ///
  /// For EntryPoint v0.7, this is a 2D nonce: the upper 192 bits are the
  /// "key" and the lower 64 bits are the sequential nonce for that key.
  /// This allows parallel transaction submission with different keys.
  BigInt get nonce;

  /// The encoded function call(s) to execute on the smart account.
  ///
  /// This is typically the result of calling [SmartAccount.encodeCall] or
  /// [SmartAccount.encodeCalls] for batch operations.
  String get callData;

  /// The signature authorizing this operation.
  ///
  /// The format depends on the account implementation. For example:
  /// - Safe: EIP-712 signature with potential multi-sig
  /// - Kernel v0.3: mode + type + validator + ECDSA signature
  /// - Simple: Raw ECDSA signature
  String get signature;

  /// Converts to JSON-RPC compatible map for bundler submission.
  Map<String, dynamic> toJson();
}

/// ERC-4337 User Operation for EntryPoint v0.6.
///
/// This is the original UserOperation format from the ERC-4337 specification.
/// Use this when interacting with EntryPoint v0.6.
///
/// ## Fields
/// - [initCode]: Factory address + calldata for deploying the account
/// - [paymasterAndData]: Paymaster address + verification/postOp gas + data
///
/// ## Example
/// ```dart
/// final userOp = UserOperationV06(
///   sender: accountAddress,
///   nonce: BigInt.zero,
///   initCode: await account.getInitCode(), // or '0x' if deployed
///   callData: account.encodeCall(call),
///   callGasLimit: BigInt.from(100000),
///   verificationGasLimit: BigInt.from(100000),
///   preVerificationGas: BigInt.from(50000),
///   maxFeePerGas: BigInt.from(1000000000),
///   maxPriorityFeePerGas: BigInt.from(1000000000),
/// );
/// ```
class UserOperationV06 implements UserOperation {
  /// Creates a UserOperation for EntryPoint v0.6.
  const UserOperationV06({
    required this.sender,
    required this.nonce,
    this.initCode = '0x',
    required this.callData,
    required this.callGasLimit,
    required this.verificationGasLimit,
    required this.preVerificationGas,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
    this.paymasterAndData = '0x',
    this.signature = '0x',
  });

  /// Creates from JSON-RPC response.
  factory UserOperationV06.fromJson(Map<String, dynamic> json) =>
      UserOperationV06(
        sender: EthAddress(json['sender'] as String),
        nonce: Hex.toBigInt(json['nonce'] as String),
        initCode: json['initCode'] as String? ?? '0x',
        callData: json['callData'] as String,
        callGasLimit: Hex.toBigInt(json['callGasLimit'] as String),
        verificationGasLimit:
            Hex.toBigInt(json['verificationGasLimit'] as String),
        preVerificationGas: Hex.toBigInt(json['preVerificationGas'] as String),
        maxFeePerGas: Hex.toBigInt(json['maxFeePerGas'] as String),
        maxPriorityFeePerGas:
            Hex.toBigInt(json['maxPriorityFeePerGas'] as String),
        paymasterAndData: json['paymasterAndData'] as String? ?? '0x',
        signature: json['signature'] as String? ?? '0x',
      );

  @override
  final EthAddress sender;
  @override
  final BigInt nonce;
  final String initCode;
  @override
  final String callData;
  final BigInt callGasLimit;
  final BigInt verificationGasLimit;
  final BigInt preVerificationGas;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;
  final String paymasterAndData;
  @override
  final String signature;

  /// Creates a copy with updated fields.
  UserOperationV06 copyWith({
    EthAddress? sender,
    BigInt? nonce,
    String? initCode,
    String? callData,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    String? paymasterAndData,
    String? signature,
  }) =>
      UserOperationV06(
        sender: sender ?? this.sender,
        nonce: nonce ?? this.nonce,
        initCode: initCode ?? this.initCode,
        callData: callData ?? this.callData,
        callGasLimit: callGasLimit ?? this.callGasLimit,
        verificationGasLimit: verificationGasLimit ?? this.verificationGasLimit,
        preVerificationGas: preVerificationGas ?? this.preVerificationGas,
        maxFeePerGas: maxFeePerGas ?? this.maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas ?? this.maxPriorityFeePerGas,
        paymasterAndData: paymasterAndData ?? this.paymasterAndData,
        signature: signature ?? this.signature,
      );

  /// Converts to JSON-RPC compatible map.
  @override
  Map<String, dynamic> toJson() => {
        'sender': sender.hex,
        'nonce': Hex.fromBigInt(nonce),
        'initCode': initCode,
        'callData': callData,
        'callGasLimit': Hex.fromBigInt(callGasLimit),
        'verificationGasLimit': Hex.fromBigInt(verificationGasLimit),
        'preVerificationGas': Hex.fromBigInt(preVerificationGas),
        'maxFeePerGas': Hex.fromBigInt(maxFeePerGas),
        'maxPriorityFeePerGas': Hex.fromBigInt(maxPriorityFeePerGas),
        'paymasterAndData': paymasterAndData,
        'signature': signature,
      };
}

/// ERC-4337 User Operation for EntryPoint v0.7.
///
/// This is the updated UserOperation format with improved gas handling
/// and cleaner field separation. Use this when interacting with
/// EntryPoint v0.7.
///
/// ## Key Differences from v0.6
/// - [factory] and [factoryData] replace `initCode` (cleaner separation)
/// - Paymaster fields are split: [paymaster], [paymasterData],
///   [paymasterVerificationGasLimit], [paymasterPostOpGasLimit]
/// - Gas limits use uint128 instead of uint256 for efficiency
///
/// ## Example
/// ```dart
/// final userOp = UserOperationV07(
///   sender: accountAddress,
///   nonce: BigInt.zero,
///   factory: factoryAddress, // null if account deployed
///   factoryData: factoryCalldata, // null if account deployed
///   callData: account.encodeCall(call),
///   callGasLimit: BigInt.from(100000),
///   verificationGasLimit: BigInt.from(100000),
///   preVerificationGas: BigInt.from(50000),
///   maxFeePerGas: BigInt.from(1000000000),
///   maxPriorityFeePerGas: BigInt.from(1000000000),
/// );
/// ```
class UserOperationV07 implements UserOperation {
  /// Creates a UserOperation for EntryPoint v0.7.
  const UserOperationV07({
    required this.sender,
    required this.nonce,
    this.factory,
    this.factoryData,
    required this.callData,
    required this.callGasLimit,
    required this.verificationGasLimit,
    required this.preVerificationGas,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
    this.paymaster,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
    this.paymasterData,
    this.signature = '0x',
  });

  /// Creates from JSON-RPC response.
  factory UserOperationV07.fromJson(Map<String, dynamic> json) =>
      UserOperationV07(
        sender: EthAddress(json['sender'] as String),
        nonce: Hex.toBigInt(json['nonce'] as String),
        factory: json['factory'] != null
            ? EthAddress(json['factory'] as String)
            : null,
        factoryData: json['factoryData'] as String?,
        callData: json['callData'] as String,
        callGasLimit: Hex.toBigInt(json['callGasLimit'] as String),
        verificationGasLimit:
            Hex.toBigInt(json['verificationGasLimit'] as String),
        preVerificationGas: Hex.toBigInt(json['preVerificationGas'] as String),
        maxFeePerGas: Hex.toBigInt(json['maxFeePerGas'] as String),
        maxPriorityFeePerGas:
            Hex.toBigInt(json['maxPriorityFeePerGas'] as String),
        paymaster: json['paymaster'] != null
            ? EthAddress(json['paymaster'] as String)
            : null,
        paymasterVerificationGasLimit:
            json['paymasterVerificationGasLimit'] != null
                ? Hex.toBigInt(json['paymasterVerificationGasLimit'] as String)
                : null,
        paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
            ? Hex.toBigInt(json['paymasterPostOpGasLimit'] as String)
            : null,
        paymasterData: json['paymasterData'] as String?,
        signature: json['signature'] as String? ?? '0x',
      );

  @override
  final EthAddress sender;
  @override
  final BigInt nonce;
  final EthAddress? factory;
  final String? factoryData;
  @override
  final String callData;
  final BigInt callGasLimit;
  final BigInt verificationGasLimit;
  final BigInt preVerificationGas;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;
  final EthAddress? paymaster;
  final BigInt? paymasterVerificationGasLimit;
  final BigInt? paymasterPostOpGasLimit;
  final String? paymasterData;
  @override
  final String signature;

  /// Creates a copy with updated fields.
  UserOperationV07 copyWith({
    EthAddress? sender,
    BigInt? nonce,
    EthAddress? factory,
    String? factoryData,
    String? callData,
    BigInt? callGasLimit,
    BigInt? verificationGasLimit,
    BigInt? preVerificationGas,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    EthAddress? paymaster,
    BigInt? paymasterVerificationGasLimit,
    BigInt? paymasterPostOpGasLimit,
    String? paymasterData,
    String? signature,
  }) =>
      UserOperationV07(
        sender: sender ?? this.sender,
        nonce: nonce ?? this.nonce,
        factory: factory ?? this.factory,
        factoryData: factoryData ?? this.factoryData,
        callData: callData ?? this.callData,
        callGasLimit: callGasLimit ?? this.callGasLimit,
        verificationGasLimit: verificationGasLimit ?? this.verificationGasLimit,
        preVerificationGas: preVerificationGas ?? this.preVerificationGas,
        maxFeePerGas: maxFeePerGas ?? this.maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas ?? this.maxPriorityFeePerGas,
        paymaster: paymaster ?? this.paymaster,
        paymasterVerificationGasLimit:
            paymasterVerificationGasLimit ?? this.paymasterVerificationGasLimit,
        paymasterPostOpGasLimit:
            paymasterPostOpGasLimit ?? this.paymasterPostOpGasLimit,
        paymasterData: paymasterData ?? this.paymasterData,
        signature: signature ?? this.signature,
      );

  /// Converts to JSON-RPC compatible map.
  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'sender': sender.hex,
      'nonce': Hex.fromBigInt(nonce),
      'callData': callData,
      'callGasLimit': Hex.fromBigInt(callGasLimit),
      'verificationGasLimit': Hex.fromBigInt(verificationGasLimit),
      'preVerificationGas': Hex.fromBigInt(preVerificationGas),
      'maxFeePerGas': Hex.fromBigInt(maxFeePerGas),
      'maxPriorityFeePerGas': Hex.fromBigInt(maxPriorityFeePerGas),
      'signature': signature,
    };

    if (factory != null) {
      result['factory'] = factory!.hex;
    }
    if (factoryData != null) {
      result['factoryData'] = factoryData;
    }
    if (paymaster != null) {
      result['paymaster'] = paymaster!.hex;
    }
    if (paymasterVerificationGasLimit != null) {
      result['paymasterVerificationGasLimit'] =
          Hex.fromBigInt(paymasterVerificationGasLimit!);
    }
    if (paymasterPostOpGasLimit != null) {
      result['paymasterPostOpGasLimit'] =
          Hex.fromBigInt(paymasterPostOpGasLimit!);
    }
    if (paymasterData != null) {
      result['paymasterData'] = paymasterData;
    }

    return result;
  }
}

/// Represents a call to be executed by a smart account.
///
/// A Call encapsulates a single operation the smart account should perform:
/// transferring ETH, calling a contract function, or both.
///
/// ## Example
/// ```dart
/// // Simple ETH transfer
/// final transfer = Call(
///   to: EthAddress('0x...'),
///   value: BigInt.from(1000000000000000000), // 1 ETH in wei
/// );
///
/// // Contract function call
/// final call = Call(
///   to: contractAddress,
///   data: '0x...', // Encoded function call
/// );
///
/// // Combined: call with ETH value
/// final callWithValue = Call(
///   to: contractAddress,
///   value: BigInt.from(1000000000000000000),
///   data: '0x...', // payable function call
/// );
/// ```
class Call {
  /// Creates a call to be executed by a smart account.
  ///
  /// - [to]: The target address to call
  /// - [value]: Amount of ETH to send in wei (defaults to 0)
  /// - [data]: Encoded calldata (defaults to '0x' for simple transfers)
  Call({
    required this.to,
    BigInt? value,
    this.data = '0x',
  }) : value = value ?? BigInt.zero;

  /// Creates a call from a JSON map.
  factory Call.fromJson(Map<String, dynamic> json) => Call(
        to: EthAddress(json['to'] as String),
        value: json['value'] is BigInt
            ? json['value'] as BigInt
            : BigInt.parse(json['value']?.toString() ?? '0'),
        data: json['data'] as String? ?? '0x',
      );

  /// The target contract or EOA address.
  final EthAddress to;

  /// Amount of ETH to send in wei.
  final BigInt value;

  /// Encoded function calldata, or '0x' for simple transfers.
  final String data;

  /// Converts to a JSON map.
  Map<String, dynamic> toJson() => {
        'to': to.hex,
        'value': value.toString(),
        'data': data,
      };
}

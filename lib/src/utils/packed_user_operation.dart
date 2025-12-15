import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';

/// Packed UserOperation format for EntryPoint v0.7.
///
/// This is the on-chain representation of a v0.7 UserOperation where certain
/// fields are packed together for efficiency:
/// - [initCode] = factory address (20 bytes) + factoryData
/// - [accountGasLimits] = verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
/// - [gasFees] = maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
/// - [paymasterAndData] = paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
///   + paymasterPostOpGasLimit (16 bytes) + paymasterData
///
/// This format is used when computing the UserOperation hash and for
/// on-chain validation.
///
/// Example:
/// ```dart
/// final packed = getPackedUserOperation(userOperation);
/// print('initCode: ${packed.initCode}');
/// print('accountGasLimits: ${packed.accountGasLimits}');
/// ```
class PackedUserOperation {
  const PackedUserOperation({
    required this.sender,
    required this.nonce,
    required this.initCode,
    required this.callData,
    required this.accountGasLimits,
    required this.preVerificationGas,
    required this.gasFees,
    required this.paymasterAndData,
    required this.signature,
  });

  /// The smart account address.
  final EthAddress sender;

  /// The account's nonce.
  final BigInt nonce;

  /// Packed initCode: factory address (20 bytes) + factoryData.
  /// '0x' if no factory (account already deployed).
  final String initCode;

  /// The encoded callData for execution.
  final String callData;

  /// Packed gas limits: verificationGasLimit (16 bytes) + callGasLimit (16 bytes).
  final String accountGasLimits;

  /// Pre-verification gas.
  final BigInt preVerificationGas;

  /// Packed gas fees: maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes).
  final String gasFees;

  /// Packed paymaster data: paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
  /// + paymasterPostOpGasLimit (16 bytes) + paymasterData.
  /// '0x' if no paymaster.
  final String paymasterAndData;

  /// The signature.
  final String signature;

  /// Converts to JSON-RPC compatible map.
  Map<String, dynamic> toJson() => {
        'sender': sender.hex,
        'nonce': Hex.fromBigInt(nonce),
        'initCode': initCode,
        'callData': callData,
        'accountGasLimits': accountGasLimits,
        'preVerificationGas': Hex.fromBigInt(preVerificationGas),
        'gasFees': gasFees,
        'paymasterAndData': paymasterAndData,
        'signature': signature,
      };
}

// ============================================================================
// Packing Functions
// ============================================================================

/// Packs a v0.7 UserOperation into the packed format.
///
/// This converts the unpacked [UserOperationV07] into [PackedUserOperation]
/// which is the format used for on-chain validation and hash computation.
///
/// Example:
/// ```dart
/// final userOp = UserOperationV07(...);
/// final packed = getPackedUserOperation(userOp);
/// ```
PackedUserOperation getPackedUserOperation(UserOperationV07 userOperation) =>
    PackedUserOperation(
      sender: userOperation.sender,
      nonce: userOperation.nonce,
      initCode: getInitCode(userOperation),
      callData: userOperation.callData,
      accountGasLimits: getAccountGasLimits(userOperation),
      preVerificationGas: userOperation.preVerificationGas,
      gasFees: getGasFees(userOperation),
      paymasterAndData: getPaymasterAndData(userOperation),
      signature: userOperation.signature,
    );

/// Creates the packed initCode from factory + factoryData.
///
/// Returns '0x' if no factory is set (account already deployed).
///
/// Format: factory address (20 bytes) + factoryData
///
/// Example:
/// ```dart
/// final initCode = getInitCode(userOp);
/// // Returns '0x5fbdb2315678afecb367f032d93f642f64180aa3abcdef...'
/// ```
String getInitCode(UserOperationV07 userOperation) {
  if (userOperation.factory == null) {
    return '0x';
  }
  return Hex.concat([
    userOperation.factory!.hex,
    userOperation.factoryData ?? '0x',
  ]);
}

/// Creates the packed accountGasLimits from gas limits.
///
/// Format: verificationGasLimit (16 bytes) + callGasLimit (16 bytes)
///
/// Example:
/// ```dart
/// final gasLimits = getAccountGasLimits(userOp);
/// // Returns '0x0000000000000000000000000000c350000000000000000000000000000186a0'
/// ```
String getAccountGasLimits(UserOperationV07 userOperation) => Hex.concat([
      Hex.padLeft(Hex.fromBigInt(userOperation.verificationGasLimit), 16),
      Hex.padLeft(Hex.fromBigInt(userOperation.callGasLimit), 16),
    ]);

/// Creates the packed gasFees from fee parameters.
///
/// Format: maxPriorityFeePerGas (16 bytes) + maxFeePerGas (16 bytes)
///
/// Example:
/// ```dart
/// final fees = getGasFees(userOp);
/// ```
String getGasFees(UserOperationV07 userOperation) => Hex.concat([
      Hex.padLeft(Hex.fromBigInt(userOperation.maxPriorityFeePerGas), 16),
      Hex.padLeft(Hex.fromBigInt(userOperation.maxFeePerGas), 16),
    ]);

/// Creates the packed paymasterAndData from paymaster fields.
///
/// Returns '0x' if no paymaster is set.
///
/// Format: paymaster (20 bytes) + paymasterVerificationGasLimit (16 bytes)
///         + paymasterPostOpGasLimit (16 bytes) + paymasterData
///
/// Example:
/// ```dart
/// final pmData = getPaymasterAndData(userOp);
/// ```
String getPaymasterAndData(UserOperationV07 userOperation) {
  if (userOperation.paymaster == null) {
    return '0x';
  }
  return Hex.concat([
    userOperation.paymaster!.hex,
    Hex.padLeft(
      Hex.fromBigInt(
        userOperation.paymasterVerificationGasLimit ?? BigInt.zero,
      ),
      16,
    ),
    Hex.padLeft(
      Hex.fromBigInt(userOperation.paymasterPostOpGasLimit ?? BigInt.zero),
      16,
    ),
    userOperation.paymasterData ?? '0x',
  ]);
}

// ============================================================================
// Unpacking Functions
// ============================================================================

/// Result of unpacking initCode.
class UnpackedInitCode {
  const UnpackedInitCode({
    this.factory,
    this.factoryData,
  });

  /// The factory address, or null if no factory.
  final EthAddress? factory;

  /// The factory calldata, or null if no factory.
  final String? factoryData;
}

/// Unpacks initCode into factory + factoryData.
///
/// Example:
/// ```dart
/// final unpacked = unpackInitCode('0x5fbdb2315...abcdef');
/// print('Factory: ${unpacked.factory?.hex}');
/// print('Data: ${unpacked.factoryData}');
/// ```
UnpackedInitCode unpackInitCode(String initCode) {
  if (initCode == '0x' || initCode.isEmpty) {
    return const UnpackedInitCode();
  }

  final hex = Hex.strip0x(initCode);
  if (hex.length < 40) {
    return const UnpackedInitCode();
  }

  return UnpackedInitCode(
    factory: EthAddress('0x${hex.substring(0, 40)}'),
    factoryData: hex.length > 40 ? '0x${hex.substring(40)}' : '0x',
  );
}

/// Result of unpacking accountGasLimits.
class UnpackedAccountGasLimits {
  const UnpackedAccountGasLimits({
    required this.verificationGasLimit,
    required this.callGasLimit,
  });

  final BigInt verificationGasLimit;
  final BigInt callGasLimit;
}

/// Unpacks accountGasLimits into verificationGasLimit + callGasLimit.
///
/// Example:
/// ```dart
/// final unpacked = unpackAccountGasLimits(packed.accountGasLimits);
/// print('Verification: ${unpacked.verificationGasLimit}');
/// print('Call: ${unpacked.callGasLimit}');
/// ```
UnpackedAccountGasLimits unpackAccountGasLimits(String accountGasLimits) {
  final hex = Hex.strip0x(accountGasLimits);

  // Each field is 16 bytes = 32 hex chars
  final verificationHex = hex.substring(0, 32);
  final callHex = hex.substring(32, 64);

  return UnpackedAccountGasLimits(
    verificationGasLimit: BigInt.parse(verificationHex, radix: 16),
    callGasLimit: BigInt.parse(callHex, radix: 16),
  );
}

/// Result of unpacking gasFees.
class UnpackedGasFees {
  const UnpackedGasFees({
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
  });

  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
}

/// Unpacks gasFees into maxPriorityFeePerGas + maxFeePerGas.
///
/// Example:
/// ```dart
/// final unpacked = unpackGasFees(packed.gasFees);
/// print('Priority: ${unpacked.maxPriorityFeePerGas}');
/// print('Max: ${unpacked.maxFeePerGas}');
/// ```
UnpackedGasFees unpackGasFees(String gasFees) {
  final hex = Hex.strip0x(gasFees);

  // Each field is 16 bytes = 32 hex chars
  final priorityHex = hex.substring(0, 32);
  final maxHex = hex.substring(32, 64);

  return UnpackedGasFees(
    maxPriorityFeePerGas: BigInt.parse(priorityHex, radix: 16),
    maxFeePerGas: BigInt.parse(maxHex, radix: 16),
  );
}

/// Result of unpacking paymasterAndData.
class UnpackedPaymasterAndData {
  const UnpackedPaymasterAndData({
    this.paymaster,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
    this.paymasterData,
  });

  /// The paymaster address, or null if no paymaster.
  final EthAddress? paymaster;

  /// The paymaster verification gas limit, or null if no paymaster.
  final BigInt? paymasterVerificationGasLimit;

  /// The paymaster post-op gas limit, or null if no paymaster.
  final BigInt? paymasterPostOpGasLimit;

  /// The paymaster data, or null if no paymaster.
  final String? paymasterData;
}

/// Unpacks paymasterAndData into its components.
///
/// Example:
/// ```dart
/// final unpacked = unpackPaymasterAndData(packed.paymasterAndData);
/// if (unpacked.paymaster != null) {
///   print('Paymaster: ${unpacked.paymaster!.hex}');
/// }
/// ```
UnpackedPaymasterAndData unpackPaymasterAndData(String paymasterAndData) {
  if (paymasterAndData == '0x' || paymasterAndData.isEmpty) {
    return const UnpackedPaymasterAndData();
  }

  final hex = Hex.strip0x(paymasterAndData);

  // Minimum: paymaster (40) + verificationGas (32) + postOpGas (32) = 104 chars
  if (hex.length < 104) {
    return const UnpackedPaymasterAndData();
  }

  return UnpackedPaymasterAndData(
    paymaster: EthAddress('0x${hex.substring(0, 40)}'),
    paymasterVerificationGasLimit:
        BigInt.parse(hex.substring(40, 72), radix: 16),
    paymasterPostOpGasLimit: BigInt.parse(hex.substring(72, 104), radix: 16),
    paymasterData: hex.length > 104 ? '0x${hex.substring(104)}' : '0x',
  );
}

/// Converts a PackedUserOperation back to an unpacked UserOperationV07.
///
/// This is the inverse of [getPackedUserOperation].
///
/// Example:
/// ```dart
/// final packed = getPackedUserOperation(userOp);
/// final unpacked = unpackUserOperation(packed);
/// // unpacked is equivalent to the original userOp
/// ```
UserOperationV07 unpackUserOperation(PackedUserOperation packed) {
  final initCode = unpackInitCode(packed.initCode);
  final gasLimits = unpackAccountGasLimits(packed.accountGasLimits);
  final fees = unpackGasFees(packed.gasFees);
  final paymaster = unpackPaymasterAndData(packed.paymasterAndData);

  return UserOperationV07(
    sender: packed.sender,
    nonce: packed.nonce,
    factory: initCode.factory,
    factoryData: initCode.factoryData,
    callData: packed.callData,
    verificationGasLimit: gasLimits.verificationGasLimit,
    callGasLimit: gasLimits.callGasLimit,
    preVerificationGas: packed.preVerificationGas,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
    maxFeePerGas: fees.maxFeePerGas,
    paymaster: paymaster.paymaster,
    paymasterVerificationGasLimit: paymaster.paymasterVerificationGasLimit,
    paymasterPostOpGasLimit: paymaster.paymasterPostOpGasLimit,
    paymasterData: paymaster.paymasterData,
    signature: packed.signature,
  );
}

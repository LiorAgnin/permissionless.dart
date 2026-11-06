import 'parsing.dart';

/// Gas estimation response from eth_estimateUserOperationGas.
///
/// Contains the gas limits needed to execute a UserOperation.
/// Fields vary slightly between EntryPoint v0.6 and v0.7.
class UserOperationGasEstimate {
  /// Creates a gas estimate with the given values.
  ///
  /// Use [UserOperationGasEstimate.fromJson] for parsing API responses.
  const UserOperationGasEstimate({
    required this.preVerificationGas,
    required this.verificationGasLimit,
    required this.callGasLimit,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
  });

  /// Creates a [UserOperationGasEstimate] from a JSON response.
  ///
  /// Parses the `eth_estimateUserOperationGas` RPC response.
  factory UserOperationGasEstimate.fromJson(Map<String, dynamic> json) =>
      UserOperationGasEstimate(
        preVerificationGas: parseBigInt(json['preVerificationGas']),
        verificationGasLimit: parseBigInt(
          json['verificationGasLimit'] ?? json['verificationGas'],
        ),
        callGasLimit: parseBigInt(json['callGasLimit']),
        paymasterVerificationGasLimit:
            parseBigIntOrNull(json['paymasterVerificationGasLimit']),
        paymasterPostOpGasLimit:
            parseBigIntOrNull(json['paymasterPostOpGasLimit']),
      );

  /// Gas for data serialization and pre-verification checks.
  final BigInt preVerificationGas;

  /// Gas for account validation (validateUserOp).
  final BigInt verificationGasLimit;

  /// Gas for the actual execution call.
  final BigInt callGasLimit;

  /// Gas for paymaster validation (v0.7 only).
  final BigInt? paymasterVerificationGasLimit;

  /// Gas for paymaster postOp (v0.7 only).
  final BigInt? paymasterPostOpGasLimit;

  @override
  String toString() =>
      'UserOperationGasEstimate(preVerificationGas: $preVerificationGas, '
      'verificationGasLimit: $verificationGasLimit, callGasLimit: $callGasLimit)';
}

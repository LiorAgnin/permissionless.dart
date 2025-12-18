import '../../types/address.dart';
import '../../utils/parsing.dart';

/// Response from pm_getPaymasterStubData.
///
/// Contains stub paymaster data used for gas estimation.
/// The actual paymaster signature comes from [PaymasterData].
class PaymasterStubData {
  const PaymasterStubData({
    required this.paymaster,
    required this.paymasterData,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
    this.isFinal = false,
  });

  factory PaymasterStubData.fromJson(Map<String, dynamic> json) =>
      PaymasterStubData(
        paymaster: EthereumAddress.fromHex(json['paymaster'] as String),
        paymasterData: json['paymasterData'] as String,
        paymasterVerificationGasLimit:
            json['paymasterVerificationGasLimit'] != null
                ? parseBigInt(json['paymasterVerificationGasLimit'])
                : null,
        paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
            ? parseBigInt(json['paymasterPostOpGasLimit'])
            : null,
        isFinal: json['isFinal'] as bool? ?? false,
      );

  /// The paymaster contract address.
  final EthereumAddress paymaster;

  /// Stub paymaster data (for gas estimation).
  final String paymasterData;

  /// Gas limit for paymaster validation (v0.7).
  final BigInt? paymasterVerificationGasLimit;

  /// Gas limit for paymaster postOp (v0.7).
  final BigInt? paymasterPostOpGasLimit;

  /// If true, this stub data can be used as final data (no second call needed).
  final bool isFinal;
}

/// Response from pm_getPaymasterData.
///
/// Contains the actual paymaster signature for submission.
class PaymasterData {
  const PaymasterData({
    required this.paymaster,
    required this.paymasterData,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
  });

  factory PaymasterData.fromJson(Map<String, dynamic> json) => PaymasterData(
        paymaster: EthereumAddress.fromHex(json['paymaster'] as String),
        paymasterData: json['paymasterData'] as String,
        paymasterVerificationGasLimit:
            json['paymasterVerificationGasLimit'] != null
                ? parseBigInt(json['paymasterVerificationGasLimit'])
                : null,
        paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
            ? parseBigInt(json['paymasterPostOpGasLimit'])
            : null,
      );

  /// The paymaster contract address.
  final EthereumAddress paymaster;

  /// Paymaster data with signature.
  final String paymasterData;

  /// Gas limit for paymaster validation (v0.7).
  final BigInt? paymasterVerificationGasLimit;

  /// Gas limit for paymaster postOp (v0.7).
  final BigInt? paymasterPostOpGasLimit;
}

/// Combined response from pm_sponsorUserOperation.
///
/// Some paymaster APIs return gas estimates along with paymaster data.
/// Handles both v0.6 (paymasterAndData combined) and v0.7 (separate fields).
class SponsorUserOperationResult {
  const SponsorUserOperationResult({
    required this.paymaster,
    required this.paymasterData,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
    this.preVerificationGas,
    this.verificationGasLimit,
    this.callGasLimit,
  });

  factory SponsorUserOperationResult.fromJson(Map<String, dynamic> json) {
    // Handle v0.6 format (combined paymasterAndData)
    if (json.containsKey('paymasterAndData')) {
      final paymasterAndData = json['paymasterAndData'] as String;
      // Extract paymaster (first 20 bytes = 40 hex chars after 0x)
      final paymaster = '0x${paymasterAndData.substring(2, 42)}';
      // Extract data (rest)
      final paymasterData = '0x${paymasterAndData.substring(42)}';

      return SponsorUserOperationResult(
        paymaster: EthereumAddress.fromHex(paymaster),
        paymasterData: paymasterData,
        preVerificationGas: json['preVerificationGas'] != null
            ? parseBigInt(json['preVerificationGas'])
            : null,
        verificationGasLimit: json['verificationGasLimit'] != null
            ? parseBigInt(json['verificationGasLimit'])
            : null,
        callGasLimit: json['callGasLimit'] != null
            ? parseBigInt(json['callGasLimit'])
            : null,
      );
    }

    // Handle v0.7 format (separate paymaster and paymasterData)
    return SponsorUserOperationResult(
      paymaster: EthereumAddress.fromHex(json['paymaster'] as String),
      paymasterData: json['paymasterData'] as String,
      paymasterVerificationGasLimit:
          json['paymasterVerificationGasLimit'] != null
              ? parseBigInt(json['paymasterVerificationGasLimit'])
              : null,
      paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
          ? parseBigInt(json['paymasterPostOpGasLimit'])
          : null,
      preVerificationGas: json['preVerificationGas'] != null
          ? parseBigInt(json['preVerificationGas'])
          : null,
      verificationGasLimit: json['verificationGasLimit'] != null
          ? parseBigInt(json['verificationGasLimit'])
          : null,
      callGasLimit: json['callGasLimit'] != null
          ? parseBigInt(json['callGasLimit'])
          : null,
    );
  }

  /// The paymaster contract address.
  final EthereumAddress paymaster;

  /// Paymaster data with signature.
  final String paymasterData;

  /// Gas limit for paymaster validation (v0.7).
  final BigInt? paymasterVerificationGasLimit;

  /// Gas limit for paymaster postOp (v0.7).
  final BigInt? paymasterPostOpGasLimit;

  /// Pre-verification gas (if provided by paymaster).
  final BigInt? preVerificationGas;

  /// Verification gas limit (if provided by paymaster).
  final BigInt? verificationGasLimit;

  /// Call gas limit (if provided by paymaster).
  final BigInt? callGasLimit;
}

/// Context data for paymaster requests.
///
/// Paymasters may require additional context like sender address,
/// sponsorship policy identifiers, or ERC-20 token for gas payment.
///
/// ## Sponsored Mode (default)
/// When [token] is null, the paymaster sponsors the transaction
/// (pays gas in native ETH on behalf of the user).
///
/// ## ERC-20 Paymaster Mode
/// When [token] is set, the paymaster charges gas fees in the specified
/// ERC-20 token instead of sponsoring. The user must have approved
/// the paymaster to spend their tokens.
///
/// Example:
/// ```dart
/// // Sponsored transaction
/// final sponsored = PaymasterContext(sponsorshipPolicyId: 'my-policy');
///
/// // Pay gas with USDC
/// final erc20 = PaymasterContext(token: usdcAddress);
/// ```
class PaymasterContext {
  const PaymasterContext({
    this.sponsorshipPolicyId,
    this.token,
    this.extra,
  });

  /// Sponsorship policy identifier (for policy-based paymasters).
  final String? sponsorshipPolicyId;

  /// ERC-20 token address for paying gas fees.
  ///
  /// When set, the paymaster charges gas fees in this token instead
  /// of sponsoring the transaction. The user must approve the paymaster
  /// to spend their tokens before submitting the UserOperation.
  ///
  /// Common tokens: USDC, USDT, DAI, etc.
  final EthereumAddress? token;

  /// Additional context data specific to the paymaster.
  final Map<String, dynamic>? extra;

  Map<String, dynamic> toJson() => {
        if (sponsorshipPolicyId != null)
          'sponsorshipPolicyId': sponsorshipPolicyId,
        if (token != null) 'token': token!.hex,
        ...?extra,
      };
}

/// Error returned by paymaster RPC calls.
class PaymasterRpcError implements Exception {
  const PaymasterRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  /// JSON-RPC error code.
  final int code;

  /// Error message.
  final String message;

  /// Additional error data.
  final dynamic data;

  @override
  String toString() =>
      'PaymasterRpcError($code): $message${data != null ? ' - $data' : ''}';
}

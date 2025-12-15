import '../../types/address.dart';
import '../../utils/parsing.dart';

/// Gas estimation response from eth_estimateUserOperationGas.
///
/// Contains the gas limits needed to execute a UserOperation.
/// Fields vary slightly between EntryPoint v0.6 and v0.7.
class UserOperationGasEstimate {
  const UserOperationGasEstimate({
    required this.preVerificationGas,
    required this.verificationGasLimit,
    required this.callGasLimit,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
  });

  factory UserOperationGasEstimate.fromJson(Map<String, dynamic> json) =>
      UserOperationGasEstimate(
        preVerificationGas: parseBigInt(json['preVerificationGas']),
        verificationGasLimit: parseBigInt(
          json['verificationGasLimit'] ?? json['verificationGas'],
        ),
        callGasLimit: parseBigInt(json['callGasLimit']),
        paymasterVerificationGasLimit:
            json['paymasterVerificationGasLimit'] != null
                ? parseBigInt(json['paymasterVerificationGasLimit'])
                : null,
        paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
            ? parseBigInt(json['paymasterPostOpGasLimit'])
            : null,
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

/// Response from eth_getUserOperationByHash.
///
/// Contains the UserOperation and its inclusion details.
class UserOperationByHashResponse {
  const UserOperationByHashResponse({
    required this.userOperation,
    required this.entryPoint,
    this.blockNumber,
    this.blockHash,
    this.transactionHash,
  });

  factory UserOperationByHashResponse.fromJson(Map<String, dynamic> json) =>
      UserOperationByHashResponse(
        userOperation: json['userOperation'] as Map<String, dynamic>,
        entryPoint: EthAddress(json['entryPoint'] as String),
        blockNumber: json['blockNumber'] != null
            ? parseBigInt(json['blockNumber'])
            : null,
        blockHash: json['blockHash'] as String?,
        transactionHash: json['transactionHash'] as String?,
      );

  /// The UserOperation as a JSON map.
  final Map<String, dynamic> userOperation;

  /// The EntryPoint address that processed this UserOperation.
  final EthAddress entryPoint;

  /// Block number where the UserOperation was included.
  final BigInt? blockNumber;

  /// Block hash where the UserOperation was included.
  final String? blockHash;

  /// Transaction hash that included this UserOperation.
  final String? transactionHash;
}

/// Receipt returned after a UserOperation is mined.
///
/// Contains execution results and logs from the operation.
class UserOperationReceipt {
  const UserOperationReceipt({
    required this.userOpHash,
    required this.sender,
    required this.nonce,
    required this.success,
    required this.actualGasCost,
    required this.actualGasUsed,
    required this.logs,
    this.receipt,
    this.reason,
  });

  factory UserOperationReceipt.fromJson(Map<String, dynamic> json) =>
      UserOperationReceipt(
        userOpHash: json['userOpHash'] as String,
        sender: EthAddress(json['sender'] as String),
        nonce: parseBigInt(json['nonce']),
        success: json['success'] as bool,
        actualGasCost: parseBigInt(json['actualGasCost']),
        actualGasUsed: parseBigInt(json['actualGasUsed']),
        logs: (json['logs'] as List<dynamic>)
            .map((l) => UserOperationLog.fromJson(l as Map<String, dynamic>))
            .toList(),
        receipt: json['receipt'] != null
            ? TransactionReceipt.fromJson(
                json['receipt'] as Map<String, dynamic>,
              )
            : null,
        reason: json['reason'] as String?,
      );

  /// Hash of the UserOperation.
  final String userOpHash;

  /// Sender (smart account) address.
  final EthAddress sender;

  /// Nonce of the UserOperation.
  final BigInt nonce;

  /// Whether execution succeeded.
  final bool success;

  /// Actual gas cost in wei.
  final BigInt actualGasCost;

  /// Actual gas used.
  final BigInt actualGasUsed;

  /// Logs emitted during execution.
  final List<UserOperationLog> logs;

  /// The underlying transaction receipt.
  final TransactionReceipt? receipt;

  /// Revert reason if execution failed.
  final String? reason;
}

/// A log entry from UserOperation execution.
class UserOperationLog {
  const UserOperationLog({
    required this.address,
    required this.topics,
    required this.data,
    this.blockNumber,
    this.transactionHash,
    this.logIndex,
  });

  factory UserOperationLog.fromJson(Map<String, dynamic> json) =>
      UserOperationLog(
        address: EthAddress(json['address'] as String),
        topics:
            (json['topics'] as List<dynamic>).map((t) => t as String).toList(),
        data: json['data'] as String,
        blockNumber: json['blockNumber'] != null
            ? parseBigInt(json['blockNumber'])
            : null,
        transactionHash: json['transactionHash'] as String?,
        logIndex:
            json['logIndex'] != null ? _parseHexInt(json['logIndex']) : null,
      );

  /// Contract address that emitted the log.
  final EthAddress address;

  /// Log topics (indexed parameters).
  final List<String> topics;

  /// Log data (non-indexed parameters).
  final String data;

  /// Block number.
  final BigInt? blockNumber;

  /// Transaction hash.
  final String? transactionHash;

  /// Log index within the block.
  final int? logIndex;
}

/// Transaction receipt from the underlying bundle transaction.
class TransactionReceipt {
  const TransactionReceipt({
    required this.transactionHash,
    required this.blockHash,
    required this.blockNumber,
    required this.from,
    this.to,
    required this.cumulativeGasUsed,
    required this.gasUsed,
    required this.status,
    required this.logs,
  });

  factory TransactionReceipt.fromJson(Map<String, dynamic> json) =>
      TransactionReceipt(
        transactionHash: json['transactionHash'] as String,
        blockHash: json['blockHash'] as String,
        blockNumber: parseBigInt(json['blockNumber']),
        from: EthAddress(json['from'] as String),
        to: json['to'] != null ? EthAddress(json['to'] as String) : null,
        cumulativeGasUsed: parseBigInt(json['cumulativeGasUsed']),
        gasUsed: parseBigInt(json['gasUsed']),
        status: _parseHexInt(json['status']),
        logs: (json['logs'] as List<dynamic>)
            .map((l) => UserOperationLog.fromJson(l as Map<String, dynamic>))
            .toList(),
      );

  /// Transaction hash.
  final String transactionHash;

  /// Block hash.
  final String blockHash;

  /// Block number.
  final BigInt blockNumber;

  /// Sender of the bundle transaction (bundler).
  final EthAddress from;

  /// Recipient (EntryPoint address).
  final EthAddress? to;

  /// Cumulative gas used in the block.
  final BigInt cumulativeGasUsed;

  /// Gas used by this transaction.
  final BigInt gasUsed;

  /// Transaction status (1 = success, 0 = failure).
  final int status;

  /// Logs emitted by the transaction.
  final List<UserOperationLog> logs;
}

/// Error returned by bundler RPC calls.
///
/// ERC-4337 defines specific error codes (AA* codes) for different
/// validation and execution failures.
class BundlerRpcError implements Exception {
  const BundlerRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  /// JSON-RPC error code.
  final int code;

  /// Error message.
  final String message;

  /// Additional error data (often contains AA* error code).
  final dynamic data;

  /// Returns the AA error code if present (e.g., "AA21", "AA25").
  String? get aaErrorCode {
    if (data == null) return null;
    final dataStr = data.toString();
    final match = RegExp(r'AA\d+').firstMatch(dataStr);
    return match?.group(0);
  }

  @override
  String toString() =>
      'BundlerRpcError($code): $message${data != null ? ' - $data' : ''}';
}

// Helper to parse hex or decimal int
int _parseHexInt(dynamic value) {
  if (value is int) return value;
  final str = value.toString();
  if (str.startsWith('0x')) {
    return int.parse(str.substring(2), radix: 16);
  }
  return int.parse(str);
}

import '../../types/address.dart';
import '../../utils/parsing.dart';

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
  /// Creates a UserOperation lookup response.
  ///
  /// Use [UserOperationByHashResponse.fromJson] for parsing API responses.
  const UserOperationByHashResponse({
    required this.userOperation,
    required this.entryPoint,
    this.blockNumber,
    this.blockHash,
    this.transactionHash,
  });

  /// Creates a [UserOperationByHashResponse] from a JSON response.
  ///
  /// Parses the `eth_getUserOperationByHash` RPC response.
  factory UserOperationByHashResponse.fromJson(Map<String, dynamic> json) =>
      UserOperationByHashResponse(
        userOperation: json['userOperation'] as Map<String, dynamic>,
        entryPoint: EthereumAddress.fromHex(json['entryPoint'] as String),
        blockNumber: json['blockNumber'] != null
            ? parseBigInt(json['blockNumber'])
            : null,
        blockHash: json['blockHash'] as String?,
        transactionHash: json['transactionHash'] as String?,
      );

  /// The UserOperation as a JSON map.
  final Map<String, dynamic> userOperation;

  /// The EntryPoint address that processed this UserOperation.
  final EthereumAddress entryPoint;

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
  /// Creates a UserOperation receipt with execution results.
  ///
  /// Use [UserOperationReceipt.fromJson] for parsing API responses.
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

  /// Creates a [UserOperationReceipt] from a JSON response.
  ///
  /// Parses the `eth_getUserOperationReceipt` RPC response.
  factory UserOperationReceipt.fromJson(Map<String, dynamic> json) =>
      UserOperationReceipt(
        userOpHash: json['userOpHash'] as String,
        sender: EthereumAddress.fromHex(json['sender'] as String),
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
  final EthereumAddress sender;

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
  /// Creates a log entry from UserOperation execution.
  ///
  /// Use [UserOperationLog.fromJson] for parsing API responses.
  const UserOperationLog({
    required this.address,
    required this.topics,
    required this.data,
    this.blockNumber,
    this.transactionHash,
    this.logIndex,
  });

  /// Creates a [UserOperationLog] from a JSON response.
  ///
  /// Parses log entries from UserOperation receipts.
  factory UserOperationLog.fromJson(Map<String, dynamic> json) =>
      UserOperationLog(
        address: EthereumAddress.fromHex(json['address'] as String),
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
  final EthereumAddress address;

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
  /// Creates a transaction receipt with the given details.
  ///
  /// Use [TransactionReceipt.fromJson] for parsing API responses.
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

  /// Creates a [TransactionReceipt] from a JSON response.
  ///
  /// Parses the receipt from `eth_getTransactionReceipt` RPC responses.
  factory TransactionReceipt.fromJson(Map<String, dynamic> json) =>
      TransactionReceipt(
        transactionHash: json['transactionHash'] as String,
        blockHash: json['blockHash'] as String,
        blockNumber: parseBigInt(json['blockNumber']),
        from: EthereumAddress.fromHex(json['from'] as String),
        to: json['to'] != null
            ? EthereumAddress.fromHex(json['to'] as String)
            : null,
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
  final EthereumAddress from;

  /// Recipient (EntryPoint address).
  final EthereumAddress? to;

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
  /// Creates a bundler RPC error with the given details.
  ///
  /// - [code]: The JSON-RPC error code (e.g., -32000 for execution errors)
  /// - [message]: Human-readable error description
  /// - [data]: Optional additional data, often contains AA* error codes
  ///
  /// Use [aaErrorCode] to extract ERC-4337 specific error codes like
  /// "AA21" (insufficient funds) or "AA25" (invalid nonce).
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

  /// Case-insensitive AA## matcher (matches viem `getBundlerError` lowercasing).
  static final RegExp _aaCodePattern = RegExp(r'AA\d+', caseSensitive: false);

  /// Known ERC-4337 AA code short descriptions (EntryPoint / bundler).
  static const Map<String, String> aaErrorDescriptions = {
    'AA10': 'Sender already constructed',
    'AA13': 'InitCode failed or OOG',
    'AA14': 'InitCode must return sender',
    'AA15': 'InitCode must create sender',
    'AA20': 'Account not deployed',
    'AA21': "Didn't pay prefund",
    'AA22': 'Expired or not due',
    'AA23': 'Reverted (or OOG)',
    'AA24': 'Signature error',
    'AA25': 'Invalid account nonce',
    'AA30': 'Paymaster not deployed',
    'AA31': 'Paymaster deposit too low',
    'AA32': 'Paymaster expired or not due',
    'AA33': 'Paymaster reverted (or OOG)',
    'AA34': 'Paymaster signature error',
    'AA40': 'Over verificationGasLimit',
    'AA41': 'Over paymasterVerificationGasLimit',
    'AA50': 'PostOp reverted',
    'AA51': 'Paymaster postOp reverted',
    'AA90': 'Invalid aggregator',
    'AA91': 'Failed to send to beneficiary',
    'AA92': 'Gas values overflow',
    'AA93': 'Internal call only',
    'AA94': 'Gas value overflow',
    'AA95': 'Out of gas',
    'AA96': 'Invalid aggregator',
  };

  /// Returns the AA error code if present (e.g., `"AA21"`, `"AA25"`).
  ///
  /// Scans both [message] and [data] (case-insensitive), matching viem's
  /// `getBundlerError` which lowercases the error details before matching.
  /// Codes are always returned uppercased.
  String? get aaErrorCode {
    for (final source in [message, if (data != null) data.toString()]) {
      final match = _aaCodePattern.firstMatch(source);
      if (match != null) {
        return match.group(0)!.toUpperCase();
      }
    }
    return null;
  }

  /// Human-readable description for [aaErrorCode], if known.
  String? get aaErrorDescription {
    final code = aaErrorCode;
    if (code == null) return null;
    return aaErrorDescriptions[code];
  }

  @override
  String toString() {
    final aa = aaErrorCode;
    final desc = aaErrorDescription;
    final aaPart = aa == null
        ? ''
        : desc == null
            ? ' [$aa]'
            : ' [$aa: $desc]';
    return 'BundlerRpcError($code)$aaPart: $message'
        '${data != null ? ' - $data' : ''}';
  }
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

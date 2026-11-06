import '../../types/address.dart';
import '../../types/parsing.dart';

export '../../types/user_operation_gas_estimate.dart';
export '../rpc/rpc_errors.dart';

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
        blockNumber: parseBigIntOrNull(json['blockNumber']),
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
        blockNumber: parseBigIntOrNull(json['blockNumber']),
        transactionHash: json['transactionHash'] as String?,
        logIndex: json['logIndex'] == null ? null : parseInt(json['logIndex']),
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
        status: parseInt(json['status']),
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

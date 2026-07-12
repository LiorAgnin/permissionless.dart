/// Status of a batch call operation (ERC-5792).
enum CallsStatusType {
  /// The operation is still being processed.
  pending,

  /// The operation completed successfully.
  success,

  /// The operation failed.
  failure,
}

/// Receipt for an individual call within a batch (ERC-5792).
class CallReceipt {
  /// Creates a new CallReceipt.
  const CallReceipt({
    required this.status,
    required this.logs,
    required this.blockHash,
    required this.blockNumber,
    required this.gasUsed,
    required this.transactionHash,
  });

  /// Creates a CallReceipt from a JSON map.
  factory CallReceipt.fromJson(Map<String, dynamic> json) => CallReceipt(
        status: json['status'] as String,
        logs: (json['logs'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList(),
        blockHash: json['blockHash'] as String,
        blockNumber: json['blockNumber'] is BigInt
            ? json['blockNumber'] as BigInt
            : BigInt.parse(json['blockNumber'].toString()),
        gasUsed: json['gasUsed'] is BigInt
            ? json['gasUsed'] as BigInt
            : BigInt.parse(json['gasUsed'].toString()),
        transactionHash: json['transactionHash'] as String,
      );

  /// The status of this call: "success" or "reverted".
  final String status;

  /// Logs emitted during the call execution.
  final List<Map<String, dynamic>> logs;

  /// The hash of the block containing this transaction.
  final String blockHash;

  /// The block number containing this transaction.
  final BigInt blockNumber;

  /// The amount of gas used by this transaction.
  final BigInt gasUsed;

  /// The on-chain transaction hash.
  final String transactionHash;

  /// Converts this receipt to a JSON map.
  Map<String, dynamic> toJson() => {
        'status': status,
        'logs': logs,
        'blockHash': blockHash,
        'blockNumber': '0x${blockNumber.toRadixString(16)}',
        'gasUsed': '0x${gasUsed.toRadixString(16)}',
        'transactionHash': transactionHash,
      };
}

/// Response from getCallsStatus (ERC-5792).
///
/// Represents the status of a batch call operation initiated via `sendCalls`.
///
/// Example:
/// ```dart
/// final status = await client.getCallsStatus(callId);
/// if (status.status == CallsStatusType.success) {
///   print('Transaction hash: ${status.receipts?.first.transactionHash}');
/// } else if (status.status == CallsStatusType.pending) {
///   print('Still processing...');
/// }
/// ```
class CallsStatus {
  /// Creates a new CallsStatus.
  const CallsStatus({
    required this.id,
    required this.version,
    required this.chainId,
    required this.status,
    required this.statusCode,
    required this.atomic,
    this.receipts,
  });

  /// Creates a CallsStatus from a JSON map.
  ///
  /// Accepts either `statusCode` (Dart/library shape) or `status` (EIP-5792 /
  /// wallet RPC field). Handles:
  /// - Numeric codes: 100–199 pending, 200–299 success, 300–699 failure
  /// - Legacy string statuses: `"CONFIRMED"` → success/200, `"PENDING"` → pending/100
  /// - Numeric strings (e.g. `"100"`)
  factory CallsStatus.fromJson(Map<String, dynamic> json) {
    final raw =
        json.containsKey('statusCode') ? json['statusCode'] : json['status'];
    final parsed = parseCallsStatusCode(raw);

    return CallsStatus(
      id: json['id'] as String,
      version: json['version'] as String? ?? '1.0',
      chainId: json['chainId'] is BigInt
          ? json['chainId'] as BigInt
          : BigInt.parse(json['chainId']?.toString() ?? '0'),
      status: parsed.status,
      statusCode: parsed.statusCode,
      atomic: json['atomic'] as bool? ?? true,
      receipts: json['receipts'] != null
          ? (json['receipts'] as List<dynamic>)
              .map((e) => CallReceipt.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Parses an EIP-5792 status value into [CallsStatusType] + numeric code.
  ///
  /// Matches viem `getCallsStatus` mapping (including legacy string statuses).
  static ({CallsStatusType status, int statusCode}) parseCallsStatusCode(
    dynamic raw,
  ) {
    if (raw is String) {
      final upper = raw.toUpperCase();
      if (upper == 'CONFIRMED') {
        return (status: CallsStatusType.success, statusCode: 200);
      }
      if (upper == 'PENDING') {
        return (status: CallsStatusType.pending, statusCode: 100);
      }
      final asInt = int.tryParse(raw) ??
          (raw.startsWith('0x') || raw.startsWith('0X')
              ? int.tryParse(raw.substring(2), radix: 16)
              : null);
      if (asInt != null) {
        return _mapNumericStatusCode(asInt);
      }
      // Unknown string: treat as failure with a sentinel outside EIP-5792 ranges.
      return (status: CallsStatusType.failure, statusCode: 500);
    }

    if (raw is int) {
      return _mapNumericStatusCode(raw);
    }

    if (raw is num) {
      return _mapNumericStatusCode(raw.toInt());
    }

    return (status: CallsStatusType.failure, statusCode: 500);
  }

  static ({CallsStatusType status, int statusCode}) _mapNumericStatusCode(
    int statusCode,
  ) {
    if (statusCode >= 100 && statusCode < 200) {
      return (status: CallsStatusType.pending, statusCode: statusCode);
    }
    if (statusCode >= 200 && statusCode < 300) {
      return (status: CallsStatusType.success, statusCode: statusCode);
    }
    // EIP-5792 / viem: 300–699 are failure; other codes also surface as failure
    // (Dart has no undefined status equivalent to viem's `undefined`).
    return (status: CallsStatusType.failure, statusCode: statusCode);
  }

  /// The identifier for this call batch (userOperation hash).
  final String id;

  /// The version of the ERC-5792 response format.
  final String version;

  /// The chain ID where this operation was submitted.
  final BigInt chainId;

  /// The current status of the operation.
  final CallsStatusType status;

  /// Numeric status code:
  /// - 100-199: Pending
  /// - 200-299: Success
  /// - 300-699: Failure
  final int statusCode;

  /// Whether the calls were executed atomically (all-or-nothing).
  final bool atomic;

  /// Receipts for completed calls (only present when status is success/failure).
  final List<CallReceipt>? receipts;

  /// Converts this status to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'chainId': '0x${chainId.toRadixString(16)}',
        'status': status.name,
        'statusCode': statusCode,
        'atomic': atomic,
        if (receipts != null)
          'receipts': receipts!.map((r) => r.toJson()).toList(),
      };
}

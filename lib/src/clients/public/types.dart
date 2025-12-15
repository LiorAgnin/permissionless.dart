/// Fee data from the network.
///
/// Contains gas price information for transaction fee estimation.
class FeeData {
  const FeeData({
    required this.gasPrice,
    this.maxPriorityFeePerGas,
  });

  /// Legacy gas price (wei per gas unit).
  final BigInt gasPrice;

  /// EIP-1559 max priority fee (tip) per gas.
  final BigInt? maxPriorityFeePerGas;
}

/// Error returned by public RPC calls.
class PublicRpcError implements Exception {
  const PublicRpcError({
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
      'PublicRpcError($code): $message${data != null ? ' - $data' : ''}';
}

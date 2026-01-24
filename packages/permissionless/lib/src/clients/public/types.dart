/// Fee data from the network.
///
/// Contains gas price information for transaction fee estimation.
class FeeData {
  /// Creates fee data with the given gas price values.
  ///
  /// - [gasPrice]: Legacy gas price in wei
  /// - [maxPriorityFeePerGas]: EIP-1559 priority fee (null if not supported)
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
  /// Creates a public RPC error with the given details.
  ///
  /// - [code]: The JSON-RPC error code
  /// - [message]: Human-readable error description
  /// - [data]: Optional additional error data
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

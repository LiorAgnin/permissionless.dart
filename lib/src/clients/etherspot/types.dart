import '../../utils/parsing.dart';

/// Gas price response from Etherspot's Skandha bundler.
///
/// Contains EIP-1559 gas price values optimized for the current network
/// conditions when using the Skandha bundler.
///
/// Example:
/// ```dart
/// final gasPrice = await etherspotClient.getUserOperationGasPrice();
/// print('Max fee: ${gasPrice.maxFeePerGas}');
/// print('Priority fee: ${gasPrice.maxPriorityFeePerGas}');
/// ```
class EtherspotGasPrice {
  const EtherspotGasPrice({
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
  });

  factory EtherspotGasPrice.fromJson(Map<String, dynamic> json) =>
      EtherspotGasPrice(
        maxFeePerGas: parseBigInt(json['maxFeePerGas']),
        maxPriorityFeePerGas: parseBigInt(json['maxPriorityFeePerGas']),
      );

  /// Maximum total fee per gas unit (base fee + priority fee).
  final BigInt maxFeePerGas;

  /// Maximum priority fee (tip) per gas unit.
  final BigInt maxPriorityFeePerGas;

  @override
  String toString() =>
      'EtherspotGasPrice(maxFee: $maxFeePerGas, maxPriority: $maxPriorityFeePerGas)';
}

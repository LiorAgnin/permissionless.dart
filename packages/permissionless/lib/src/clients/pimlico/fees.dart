import '../../utils/gas.dart';
import 'pimlico_client.dart';

/// Gets fee estimates from Pimlico's gas price oracle for a [speed] tier.
///
/// Example:
/// ```dart
/// final fees = await estimateFeesFromPimlico(
///   pimlicoClient,
///   speed: GasSpeed.fast,
/// );
/// ```
Future<FeeEstimate> estimateFeesFromPimlico(
  PimlicoClient pimlico, {
  GasSpeed speed = GasSpeed.standard,
}) async {
  final gasPrices = await pimlico.getUserOperationGasPrice();
  final price = switch (speed) {
    GasSpeed.slow => gasPrices.slow,
    GasSpeed.standard => gasPrices.standard,
    GasSpeed.fast => gasPrices.fast,
  };
  return FeeEstimate(
    maxFeePerGas: price.maxFeePerGas,
    maxPriorityFeePerGas: price.maxPriorityFeePerGas,
  );
}

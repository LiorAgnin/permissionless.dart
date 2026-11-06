import '../../utils/gas.dart';
import 'public_client.dart';

/// Gets fee estimates from a public client.
///
/// Combines gasPrice and maxPriorityFeePerGas into a FeeEstimate, scaled by
/// [multiplier] for safety.
///
/// Example:
/// ```dart
/// final fees = await estimateFees(publicClient, multiplier: 1.2);
/// ```
Future<FeeEstimate> estimateFees(
  PublicClient public, {
  double multiplier = 1.1,
}) async {
  final feeData = await public.getFeeData();
  return FeeEstimate(
    maxFeePerGas: feeData.gasPrice,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas ?? feeData.gasPrice,
  ).withMultiplier(multiplier);
}

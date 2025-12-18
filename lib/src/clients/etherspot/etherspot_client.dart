import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../bundler/bundler_client.dart';
import '../bundler/rpc_client.dart';
import 'types.dart';

/// Etherspot-specific bundler client with Skandha extensions.
///
/// Extends [BundlerClient] with Etherspot's Skandha bundler-specific RPC
/// methods, including gas price oracle and chain configuration.
///
/// Skandha is Etherspot's open-source ERC-4337 bundler implementation.
///
/// Example:
/// ```dart
/// final etherspot = createEtherspotClient(
///   url: 'https://polygon-bundler.etherspot.io',
///   entryPoint: EntryPointAddresses.v07,
/// );
///
/// // Use standard bundler methods
/// final estimate = await etherspot.estimateUserOperationGas(userOp);
///
/// // Use Skandha-specific methods
/// final gasPrice = await etherspot.getUserOperationGasPrice();
/// print('Max fee: ${gasPrice.maxFeePerGas}');
/// ```
class EtherspotClient extends BundlerClient {
  EtherspotClient({
    required super.rpcClient,
    required super.entryPoint,
  });

  /// Gets recommended gas prices from Skandha's gas oracle.
  ///
  /// Returns EIP-1559 gas prices optimized for the current network conditions.
  /// Use these values to set maxFeePerGas and maxPriorityFeePerGas on your
  /// UserOperations.
  ///
  /// This calls the `skandha_getGasPrice` RPC method.
  ///
  /// Example:
  /// ```dart
  /// final gasPrice = await etherspot.getUserOperationGasPrice();
  ///
  /// final userOp = UserOperationV07(
  ///   // ... other fields
  ///   maxFeePerGas: gasPrice.maxFeePerGas,
  ///   maxPriorityFeePerGas: gasPrice.maxPriorityFeePerGas,
  /// );
  /// ```
  Future<EtherspotGasPrice> getUserOperationGasPrice() async {
    final result = await rpcClient.call('skandha_getGasPrice');
    return EtherspotGasPrice.fromJson(result as Map<String, dynamic>);
  }
}

/// Creates an [EtherspotClient] from a URL and EntryPoint address.
///
/// Example:
/// ```dart
/// final etherspot = createEtherspotClient(
///   url: 'https://polygon-bundler.etherspot.io',
///   entryPoint: EntryPointAddresses.v07,
/// );
///
/// final gasPrice = await etherspot.getUserOperationGasPrice();
/// ```
EtherspotClient createEtherspotClient({
  required String url,
  required EthereumAddress entryPoint,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    EtherspotClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
      entryPoint: entryPoint,
    );

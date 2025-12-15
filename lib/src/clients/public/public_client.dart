import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../../utils/parsing.dart';
import '../bundler/rpc_client.dart';
import '../bundler/types.dart';
import 'types.dart';

/// Client for read-only Ethereum JSON-RPC operations.
///
/// Provides access to standard Ethereum RPC methods for reading
/// chain state, checking balances, and querying contracts.
///
/// Example:
/// ```dart
/// final public = createPublicClient(
///   url: 'https://eth.llamarpc.com',
/// );
///
/// // Check if account is deployed
/// final isDeployed = await public.isDeployed(accountAddress);
///
/// // Get balance
/// final balance = await public.getBalance(accountAddress);
///
/// // Get gas prices
/// final feeData = await public.getFeeData();
/// ```
class PublicClient {
  PublicClient({
    required this.rpcClient,
  });

  /// The underlying JSON-RPC client.
  final JsonRpcClient rpcClient;

  /// Gets the bytecode at an address.
  ///
  /// Returns '0x' if no code is deployed at the address.
  Future<String> getCode(
    EthAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getCode',
      [address.hex, blockTag],
    );
    return result as String;
  }

  /// Checks if an account is deployed (has code).
  ///
  /// Returns true if the address has bytecode, false otherwise.
  Future<bool> isDeployed(EthAddress address) async {
    final code = await getCode(address);
    return code != '0x' && code.length > 2;
  }

  /// Gets the ETH balance of an address in wei.
  Future<BigInt> getBalance(
    EthAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getBalance',
      [address.hex, blockTag],
    );
    return parseBigInt(result);
  }

  /// Executes a read-only call to a contract.
  ///
  /// Returns the encoded result data.
  Future<String> call(
    Call call, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_call',
      [
        {
          'to': call.to.hex,
          'data': call.data,
          if (call.value != BigInt.zero) 'value': Hex.fromBigInt(call.value),
        },
        blockTag,
      ],
    );
    return result as String;
  }

  /// Gets the transaction count (nonce) for an EOA.
  ///
  /// Note: For smart account nonces, use [getAccountNonce] instead.
  Future<BigInt> getTransactionCount(
    EthAddress address, {
    String blockTag = 'latest',
  }) async {
    final result = await rpcClient.call(
      'eth_getTransactionCount',
      [address.hex, blockTag],
    );
    return parseBigInt(result);
  }

  /// Gets the current gas price.
  Future<BigInt> getGasPrice() async {
    final result = await rpcClient.call('eth_gasPrice');
    return parseBigInt(result);
  }

  /// Gets the current max priority fee per gas (EIP-1559).
  ///
  /// Throws if the network doesn't support EIP-1559.
  Future<BigInt> getMaxPriorityFeePerGas() async {
    final result = await rpcClient.call('eth_maxPriorityFeePerGas');
    return parseBigInt(result);
  }

  /// Gets the chain ID.
  Future<BigInt> getChainId() async {
    final result = await rpcClient.call('eth_chainId');
    return parseBigInt(result);
  }

  /// Gets gas price data for fee estimation.
  ///
  /// Returns both legacy gas price and EIP-1559 priority fee
  /// (if supported by the network).
  Future<FeeData> getFeeData() async {
    final gasPrice = await getGasPrice();

    BigInt? maxPriorityFee;
    try {
      maxPriorityFee = await getMaxPriorityFeePerGas();
    } on Exception {
      // Network might not support EIP-1559
    }

    return FeeData(
      gasPrice: gasPrice,
      maxPriorityFeePerGas: maxPriorityFee,
    );
  }

  /// Gets the ERC-4337 nonce for a smart account from the EntryPoint.
  ///
  /// The [nonceKey] parameter supports parallel nonces (defaults to 0
  /// for sequential transactions).
  ///
  /// Example:
  /// ```dart
  /// final nonce = await public.getAccountNonce(
  ///   accountAddress,
  ///   EntryPointAddresses.v07,
  /// );
  /// ```
  Future<BigInt> getAccountNonce(
    EthAddress account,
    EthAddress entryPoint, {
    BigInt? nonceKey,
  }) async {
    final key = nonceKey ?? BigInt.zero;

    // EntryPoint.getNonce(address, uint192) selector: 0x35567e1a
    final callData = Hex.concat([
      '0x35567e1a',
      _abiEncodeAddress(account),
      Hex.padLeft(Hex.fromBigInt(key), 32),
    ]);

    final result = await call(Call(to: entryPoint, data: callData));
    return parseBigInt(result);
  }

  /// Gets the counterfactual address for a smart account before deployment.
  ///
  /// This calls the EntryPoint's `getSenderAddress` function which simulates
  /// account creation with the provided [initCode] and returns the address
  /// that would be created.
  ///
  /// The [initCode] is the concatenation of factory address + factory calldata.
  /// It's the same value used in UserOperation.initCode.
  ///
  /// Example:
  /// ```dart
  /// final address = await public.getSenderAddress(
  ///   initCode: factoryAddress.hex + factoryCalldata.substring(2),
  ///   entryPoint: EntryPointAddresses.v07,
  /// );
  /// print('Account will be deployed at: ${address.checksummed}');
  /// ```
  ///
  /// Throws [PublicRpcError] if the initCode is invalid or the call fails
  /// for reasons other than the expected SenderAddressResult revert.
  Future<EthAddress> getSenderAddress({
    required String initCode,
    required EthAddress entryPoint,
  }) async {
    // EntryPoint.getSenderAddress(bytes initCode) selector: 0x9b249f69
    final callData = Hex.concat([
      '0x9b249f69',
      // Offset to initCode bytes (32 = 0x20)
      '0000000000000000000000000000000000000000000000000000000000000020',
      // Length of initCode
      Hex.padLeft(
        Hex.fromBigInt(BigInt.from((initCode.length - 2) ~/ 2)),
        32,
      ).substring(2),
      // initCode data (padded to 32-byte boundary)
      _padToWordBoundary(Hex.strip0x(initCode)),
    ]);

    try {
      // This call is expected to revert with SenderAddressResult
      await call(Call(to: entryPoint, data: callData));

      // If we get here, something unexpected happened
      throw const PublicRpcError(
        code: -1,
        message: 'getSenderAddress did not revert as expected',
      );
    } on BundlerRpcError catch (e) {
      // Parse the revert data to extract the address
      // SenderAddressResult(address) selector: 0x6ca7b806
      final data = e.data?.toString() ?? '';

      if (data.length >= 74 && data.startsWith('0x6ca7b806')) {
        // Extract address from bytes 4-36 (after selector)
        // Address is at offset 4 (selector) + 12 (padding) = 16
        final addressHex = '0x${data.substring(34, 74)}';
        return EthAddress(addressHex);
      }

      // Check for alternative error format (some nodes wrap the error)
      if (data.contains('6ca7b806')) {
        final selectorIndex = data.indexOf('6ca7b806');
        if (selectorIndex != -1 && data.length >= selectorIndex + 72) {
          final addressHex =
              '0x${data.substring(selectorIndex + 32, selectorIndex + 72)}';
          return EthAddress(addressHex);
        }
      }

      // Not the expected revert, rethrow
      throw PublicRpcError(
        code: e.code,
        message: e.message,
        data: e.data?.toString(),
      );
    }
  }

  /// Closes the underlying HTTP client.
  void close() => rpcClient.close();
}

/// Creates a [PublicClient] from a URL.
///
/// Example:
/// ```dart
/// final public = createPublicClient(
///   url: 'https://eth.llamarpc.com',
/// );
/// ```
PublicClient createPublicClient({
  required String url,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    PublicClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
    );

/// ABI-encodes an address (left-padded to 32 bytes).
String _abiEncodeAddress(EthAddress address) =>
    Hex.padLeft(address.hex.substring(2), 32);

/// Pads hex data to a 32-byte (64 char) word boundary.
String _padToWordBoundary(String hexWithout0x) {
  final remainder = hexWithout0x.length % 64;
  if (remainder == 0) return hexWithout0x;
  return hexWithout0x.padRight(hexWithout0x.length + (64 - remainder), '0');
}

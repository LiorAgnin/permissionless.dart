import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/user_operation.dart';
import 'rpc_client.dart';
import 'types.dart';

/// Client for interacting with ERC-4337 bundlers.
///
/// Provides methods to submit, estimate, and track UserOperations
/// through a bundler endpoint.
///
/// Example:
/// ```dart
/// final client = createBundlerClient(
///   url: 'https://bundler.example.com/rpc',
///   entryPoint: EntryPointAddresses.v07,
/// );
///
/// // Estimate gas
/// final estimate = await client.estimateUserOperationGas(userOp);
///
/// // Submit UserOperation
/// final hash = await client.sendUserOperation(signedUserOp);
///
/// // Wait for receipt
/// final receipt = await client.waitForUserOperationReceipt(hash);
/// ```
class BundlerClient {
  /// Creates a bundler client with the given RPC client and EntryPoint.
  ///
  /// Prefer using [createBundlerClient] factory function instead of
  /// calling this constructor directly, as it handles RPC client setup.
  ///
  /// - [rpcClient]: The JSON-RPC client for bundler communication
  /// - [entryPoint]: The EntryPoint contract address (v0.6 or v0.7)
  BundlerClient({
    required this.rpcClient,
    required this.entryPoint,
  });

  /// The underlying JSON-RPC client.
  final JsonRpcClient rpcClient;

  /// The EntryPoint address to use for operations.
  final EthereumAddress entryPoint;

  /// Submits a UserOperation to the bundler.
  ///
  /// Returns the UserOperation hash that can be used to track
  /// the operation's status.
  ///
  /// Throws [BundlerRpcError] if validation fails.
  Future<String> sendUserOperation(UserOperation userOp) async {
    final result = await rpcClient.call(
      'eth_sendUserOperation',
      [userOp.toJson(), entryPoint.hex],
    );
    return result as String;
  }

  /// Submits a UserOperation with EIP-7702 authorization.
  ///
  /// This is used for EIP-7702 accounts where the authorization
  /// must be included in the UserOperation to enable code delegation.
  ///
  /// [userOp] is the UserOperation to submit.
  /// [authorizationList] contains signed EIP-7702 authorizations.
  ///
  /// Returns the UserOperation hash.
  ///
  /// **Note**: Requires a bundler that supports EntryPoint v0.8 and EIP-7702.
  Future<String> sendUserOperationWithAuthorization(
    UserOperation userOp,
    List<Eip7702Authorization> authorizationList,
  ) async {
    // Per Pimlico API, eip7702Auth is a single authorization object
    final userOpJson = userOp.toJson();
    if (authorizationList.isNotEmpty) {
      userOpJson['eip7702Auth'] = authorizationList.first.toRpcFormat();
    }
    // Handle EIP-7702 factory marker - bundler expects '0x7702' not the padded form
    _normalizeEip7702Factory(userOpJson);

    final result = await rpcClient.call(
      'eth_sendUserOperation',
      [userOpJson, entryPoint.hex],
    );
    return result as String;
  }

  /// Estimates gas limits for a UserOperation.
  ///
  /// The returned estimate contains preVerificationGas,
  /// verificationGasLimit, and callGasLimit values that
  /// can be used to fill in the UserOperation gas fields.
  ///
  /// For v0.7 with paymasters, also returns paymaster gas limits.
  Future<UserOperationGasEstimate> estimateUserOperationGas(
    UserOperation userOp, {
    Map<String, dynamic>? stateOverride,
  }) async {
    final params = <dynamic>[userOp.toJson(), entryPoint.hex];
    if (stateOverride != null) {
      params.add(stateOverride);
    }

    final result = await rpcClient.call(
      'eth_estimateUserOperationGas',
      params,
    );
    return UserOperationGasEstimate.fromJson(result as Map<String, dynamic>);
  }

  /// Estimates gas limits for a UserOperation with EIP-7702 authorization.
  ///
  /// Similar to [estimateUserOperationGas] but includes the authorization
  /// inside the UserOperation for accurate gas estimation of EIP-7702 accounts.
  ///
  /// **Note**: Requires a bundler that supports EntryPoint v0.8 and EIP-7702.
  Future<UserOperationGasEstimate> estimateUserOperationGasWithAuthorization(
    UserOperation userOp,
    List<Eip7702Authorization> authorizationList, {
    Map<String, dynamic>? stateOverride,
  }) async {
    // Per Pimlico API, eip7702Auth is a single authorization object
    final userOpJson = userOp.toJson();
    if (authorizationList.isNotEmpty) {
      userOpJson['eip7702Auth'] = authorizationList.first.toRpcFormat();
    }
    // Handle EIP-7702 factory marker - bundler expects '0x7702' not the padded form
    _normalizeEip7702Factory(userOpJson);

    final params = <dynamic>[userOpJson, entryPoint.hex];
    if (stateOverride != null) {
      params.add(stateOverride);
    }

    final result = await rpcClient.call(
      'eth_estimateUserOperationGas',
      params,
    );
    return UserOperationGasEstimate.fromJson(result as Map<String, dynamic>);
  }

  /// Normalizes the factory field for EIP-7702.
  ///
  /// The bundler expects '0x7702' (4 bytes) not the padded 20-byte address.
  void _normalizeEip7702Factory(Map<String, dynamic> userOpJson) {
    final factory = userOpJson['factory'] as String?;
    if (factory != null &&
        factory.toLowerCase() == '0x7702000000000000000000000000000000000000') {
      userOpJson['factory'] = '0x7702';
    }
  }

  /// Gets a UserOperation by its hash.
  ///
  /// Returns null if the operation is not found or not yet processed.
  Future<UserOperationByHashResponse?> getUserOperationByHash(
    String userOpHash,
  ) async {
    final result = await rpcClient.call(
      'eth_getUserOperationByHash',
      [userOpHash],
    );
    if (result == null) return null;
    return UserOperationByHashResponse.fromJson(result as Map<String, dynamic>);
  }

  /// Gets the receipt for a UserOperation.
  ///
  /// Returns null if the operation is not yet included in a block.
  /// Once included, returns the receipt with execution results.
  Future<UserOperationReceipt?> getUserOperationReceipt(
    String userOpHash,
  ) async {
    final result = await rpcClient.call(
      'eth_getUserOperationReceipt',
      [userOpHash],
    );
    if (result == null) return null;
    return UserOperationReceipt.fromJson(result as Map<String, dynamic>);
  }

  /// Gets the list of EntryPoints supported by this bundler.
  Future<List<EthereumAddress>> supportedEntryPoints() async {
    final result = await rpcClient.call('eth_supportedEntryPoints');
    return (result as List<dynamic>)
        .map((addr) => EthereumAddress.fromHex(addr as String))
        .toList();
  }

  /// Gets the chain ID from the bundler.
  Future<BigInt> chainId() async {
    final result = await rpcClient.call('eth_chainId');
    final hexStr = result as String;
    return BigInt.parse(hexStr.substring(2), radix: 16);
  }

  /// Waits for a UserOperation to be included in a block.
  ///
  /// Polls [getUserOperationReceipt] until the operation is found
  /// or the timeout is reached.
  ///
  /// Returns the receipt, or null if timed out.
  Future<UserOperationReceipt?> waitForUserOperationReceipt(
    String userOpHash, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final receipt = await getUserOperationReceipt(userOpHash);
      if (receipt != null) {
        return receipt;
      }
      await Future<void>.delayed(pollingInterval);
    }

    return null;
  }

  /// Closes the underlying HTTP client.
  void close() => rpcClient.close();
}

/// Creates a [BundlerClient] from a URL and EntryPoint address.
///
/// Example:
/// ```dart
/// final client = createBundlerClient(
///   url: 'https://bundler.example.com/rpc',
///   entryPoint: EntryPointAddresses.v07,
/// );
/// ```
BundlerClient createBundlerClient({
  required String url,
  required EthereumAddress entryPoint,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    BundlerClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
      entryPoint: entryPoint,
    );

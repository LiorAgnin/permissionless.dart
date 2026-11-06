import 'dart:async';

import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/parsing.dart';
import '../../types/user_operation.dart';
import 'rpc_client.dart';
import 'types.dart';
import 'user_operation_request.dart';

/// How long receipt-waiting helpers wait by default (viem parity).
const Duration defaultReceiptTimeout = Duration(seconds: 120);

/// How often receipt-waiting helpers poll the bundler by default.
const Duration defaultReceiptPollingInterval = Duration(seconds: 2);

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

  /// The default EntryPoint address for operations.
  ///
  /// [sendUserOperation] and [estimateUserOperationGas] accept a per-call
  /// `entryPoint` that overrides it; `SmartAccountClient` always passes the
  /// account's EntryPoint (viem's bundler actions take
  /// `account.entryPoint.address`).
  final EthereumAddress entryPoint;

  /// Submits a UserOperation to the bundler.
  ///
  /// [entryPoint] defaults to [BundlerClient.entryPoint]. [authorization] is
  /// the signed EIP-7702 authorization of an EIP-7702 account, sent as the
  /// op's `eip7702Auth` (requires a bundler that supports EIP-7702).
  ///
  /// Returns the UserOperation hash that can be used to track
  /// the operation's status.
  ///
  /// Throws [BundlerRpcError] if validation fails.
  Future<String> sendUserOperation(
    UserOperation userOp, {
    EthereumAddress? entryPoint,
    Eip7702Authorization? authorization,
  }) async {
    final result = await rpcClient.call(
      'eth_sendUserOperation',
      [
        userOperationRequestJson(userOp, authorization: authorization),
        (entryPoint ?? this.entryPoint).hex,
      ],
    );
    return result as String;
  }

  /// Submits a UserOperation with EIP-7702 authorization.
  ///
  /// Only the first element of [authorizationList] is sent: the Pimlico API
  /// and viem take a single `eip7702Auth` object.
  @Deprecated('Use sendUserOperation(userOp, authorization: ...)')
  Future<String> sendUserOperationWithAuthorization(
    UserOperation userOp,
    List<Eip7702Authorization> authorizationList,
  ) =>
      sendUserOperation(userOp, authorization: authorizationList.firstOrNull);

  /// Estimates gas limits for a UserOperation.
  ///
  /// The returned estimate contains preVerificationGas,
  /// verificationGasLimit, and callGasLimit values that
  /// can be used to fill in the UserOperation gas fields.
  ///
  /// For v0.7 with paymasters, also returns paymaster gas limits.
  ///
  /// [entryPoint] defaults to [BundlerClient.entryPoint]. [authorization] is
  /// the signed EIP-7702 authorization of an EIP-7702 account, sent as the
  /// op's `eip7702Auth` so the estimate covers the delegation.
  Future<UserOperationGasEstimate> estimateUserOperationGas(
    UserOperation userOp, {
    Map<String, dynamic>? stateOverride,
    EthereumAddress? entryPoint,
    Eip7702Authorization? authorization,
  }) async {
    final result = await rpcClient.call(
      'eth_estimateUserOperationGas',
      [
        userOperationRequestJson(userOp, authorization: authorization),
        (entryPoint ?? this.entryPoint).hex,
        if (stateOverride != null) stateOverride,
      ],
    );
    return UserOperationGasEstimate.fromJson(result as Map<String, dynamic>);
  }

  /// Estimates gas limits for a UserOperation with EIP-7702 authorization.
  ///
  /// Only the first element of [authorizationList] is sent: the Pimlico API
  /// and viem take a single `eip7702Auth` object.
  @Deprecated('Use estimateUserOperationGas(userOp, authorization: ...)')
  Future<UserOperationGasEstimate> estimateUserOperationGasWithAuthorization(
    UserOperation userOp,
    List<Eip7702Authorization> authorizationList, {
    Map<String, dynamic>? stateOverride,
  }) =>
      estimateUserOperationGas(
        userOp,
        stateOverride: stateOverride,
        authorization: authorizationList.firstOrNull,
      );

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
  Future<BigInt> chainId() async =>
      parseBigInt(await rpcClient.call('eth_chainId'));

  /// Waits for a UserOperation to be included in a block.
  ///
  /// Polls [getUserOperationReceipt] until the operation is found
  /// or the timeout is reached.
  ///
  /// Default timeout is 120 seconds, matching viem's
  /// `waitForUserOperationReceipt`.
  ///
  /// Returns the receipt when found.
  ///
  /// Throws [TimeoutException] if the receipt is not found within [timeout].
  Future<UserOperationReceipt> waitForUserOperationReceipt(
    String userOpHash, {
    Duration timeout = defaultReceiptTimeout,
    Duration pollingInterval = defaultReceiptPollingInterval,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final receipt = await getUserOperationReceipt(userOpHash);
      if (receipt != null) {
        return receipt;
      }
      await Future<void>.delayed(pollingInterval);
    }

    throw TimeoutException(
      'Timed out waiting for UserOperation receipt: $userOpHash',
      timeout,
    );
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
      rpcClient: createRpcClient(
        url,
        httpClient: httpClient,
        headers: headers,
        timeout: timeout,
      ),
      entryPoint: entryPoint,
    );

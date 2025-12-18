import 'package:http/http.dart' as http;

import '../../types/address.dart';
import '../../types/hex.dart';
import '../../types/user_operation.dart';
import '../bundler/bundler_client.dart';
import '../bundler/rpc_client.dart';
import 'types.dart';

/// Pimlico-specific bundler client with enhanced features.
///
/// Extends [BundlerClient] with Pimlico-specific RPC methods for:
/// - Detailed UserOperation status tracking
/// - Optimized gas price recommendations
/// - Compressed UserOperations for L2 cost savings
///
/// Example:
/// ```dart
/// final pimlico = createPimlicoClient(
///   url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=...',
///   entryPoint: EntryPointAddresses.v07,
/// );
///
/// // Use standard bundler methods
/// final estimate = await pimlico.estimateUserOperationGas(userOp);
///
/// // Use Pimlico-specific methods
/// final gasPrices = await pimlico.getUserOperationGasPrice();
/// print('Fast gas: ${gasPrices.fast.maxFeePerGas}');
///
/// final hash = await pimlico.sendUserOperation(signedUserOp);
/// final status = await pimlico.getUserOperationStatus(hash);
/// ```
class PimlicoClient extends BundlerClient {
  PimlicoClient({
    required super.rpcClient,
    required super.entryPoint,
  });

  /// Gets detailed status of a UserOperation.
  ///
  /// Provides more granular status than [getUserOperationReceipt],
  /// including intermediate states like 'submitted' and 'queued'.
  ///
  /// Status values:
  /// - 'not_found': UserOperation not found
  /// - 'not_submitted': Received but not yet submitted to mempool
  /// - 'submitted': Submitted to the mempool
  /// - 'rejected': Rejected by the bundler
  /// - 'reverted': Execution reverted
  /// - 'included': Successfully included in a block
  /// - 'failed': Failed for other reasons
  Future<PimlicoUserOperationStatus> getUserOperationStatus(
    String userOpHash,
  ) async {
    final result = await rpcClient.call(
      'pimlico_getUserOperationStatus',
      [userOpHash],
    );
    return PimlicoUserOperationStatus.fromJson(result as Map<String, dynamic>);
  }

  /// Gets recommended gas prices for different speed tiers.
  ///
  /// Returns slow, standard, and fast gas price recommendations
  /// optimized for the current network conditions.
  ///
  /// Use these values to set maxFeePerGas and maxPriorityFeePerGas
  /// on your UserOperations for predictable confirmation times.
  Future<PimlicoGasPrices> getUserOperationGasPrice() async {
    final result = await rpcClient.call('pimlico_getUserOperationGasPrice');
    return PimlicoGasPrices.fromJson(result as Map<String, dynamic>);
  }

  /// Sends a compressed UserOperation for L2 cost savings.
  ///
  /// On L2s, calldata is expensive because it's posted to L1.
  /// Compressed UserOps use an inflator contract to decompress
  /// the calldata on-chain, significantly reducing costs.
  ///
  /// [userOp] is the UserOperation to send.
  /// [inflator] is the address of the inflator contract on the target chain.
  /// [compressedCalldata] is the pre-compressed calldata.
  ///
  /// Returns the UserOperation hash.
  Future<String> sendCompressedUserOperation(
    UserOperationV07 userOp,
    EthereumAddress inflator,
    String compressedCalldata,
  ) async {
    final packedUserOp = _packUserOperationV07(userOp);

    final result = await rpcClient.call(
      'pimlico_sendCompressedUserOperation',
      [
        packedUserOp,
        entryPoint.hex,
        compressedCalldata,
        inflator.hex,
      ],
    );
    return result as String;
  }

  /// Waits for a UserOperation using Pimlico's status endpoint.
  ///
  /// Similar to [waitForUserOperationReceipt] but uses the more
  /// detailed Pimlico status API.
  Future<PimlicoUserOperationStatus> waitForUserOperationStatus(
    String userOpHash, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollingInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await getUserOperationStatus(userOpHash);

      // Return if we've reached a terminal state
      if (status.status == 'included' ||
          status.status == 'rejected' ||
          status.status == 'reverted' ||
          status.status == 'failed') {
        return status;
      }

      await Future<void>.delayed(pollingInterval);
    }

    // Return the last status even if not terminal
    return getUserOperationStatus(userOpHash);
  }

  // ================================================================
  // ERC-20 Paymaster Methods
  // ================================================================

  /// Gets token quotes for ERC-20 paymaster gas payment.
  ///
  /// Returns exchange rates and paymaster information for the requested
  /// tokens. Use these quotes to understand the cost of using ERC-20
  /// tokens for gas payment.
  ///
  /// The quote includes:
  /// - [PimlicoTokenQuote.paymaster]: Address to approve for token spending
  /// - [PimlicoTokenQuote.exchangeRate]: Token/ETH exchange rate
  /// - [PimlicoTokenQuote.postOpGas]: Additional gas for token transfer (~75k)
  ///
  /// Example:
  /// ```dart
  /// final quotes = await pimlico.getTokenQuotes([usdcAddress, daiAddress]);
  /// for (final quote in quotes) {
  ///   print('${quote.token}: rate ${quote.exchangeRate}');
  /// }
  /// ```
  Future<List<PimlicoTokenQuote>> getTokenQuotes(
    List<EthereumAddress> tokens,
  ) async {
    final chain = await chainId();
    final result = await rpcClient.call(
      'pimlico_getTokenQuotes',
      [
        // First param: object with tokens array
        {'tokens': tokens.map((t) => t.hex).toList()},
        // Second param: entryPoint address
        entryPoint.hex,
        // Third param: chainId in hex
        Hex.fromBigInt(chain),
      ],
    );

    // API returns { quotes: [...] }
    final quotes = (result as Map<String, dynamic>)['quotes'] as List<dynamic>;
    return quotes
        .cast<Map<String, dynamic>>()
        .map(PimlicoTokenQuote.fromJson)
        .toList();
  }

  /// Gets the list of supported ERC-20 tokens for gas payment.
  ///
  /// Returns all tokens that can be used with the Pimlico ERC-20
  /// paymaster on the current chain.
  ///
  /// Example:
  /// ```dart
  /// final supported = await pimlico.getSupportedTokens();
  /// for (final token in supported) {
  ///   print('${token.symbol}: ${token.token.checksummed}');
  /// }
  /// ```
  Future<List<PimlicoSupportedToken>> getSupportedTokens() async {
    final result = await rpcClient.call(
      'pimlico_getSupportedTokens',
      [],
    );

    // API returns a list directly
    if (result is List) {
      return result
          .cast<Map<String, dynamic>>()
          .map(PimlicoSupportedToken.fromJson)
          .toList();
    }

    // Fallback for wrapped response format
    final tokens = result['tokens'] as List<dynamic>?;
    if (tokens == null) return [];

    return tokens
        .cast<Map<String, dynamic>>()
        .map(PimlicoSupportedToken.fromJson)
        .toList();
  }

  /// Estimates the cost to pay gas with an ERC-20 token.
  ///
  /// Returns the estimated token cost for the given UserOperation.
  /// This is useful for showing users the expected cost before
  /// they submit a transaction.
  ///
  /// [userOperation] is the UserOperation to estimate cost for.
  /// [token] is the ERC-20 token to pay gas with.
  ///
  /// Example:
  /// ```dart
  /// final cost = await pimlico.estimateErc20PaymasterCost(
  ///   userOperation: userOp,
  ///   token: usdcAddress,
  /// );
  ///
  /// final usdAmount = cost.costInUsd.toDouble() / 1e8;
  /// print('Estimated cost: \$${usdAmount.toStringAsFixed(2)}');
  /// ```
  Future<PimlicoErc20PaymasterCost> estimateErc20PaymasterCost({
    required UserOperationV07 userOperation,
    required EthereumAddress token,
  }) async {
    final packedUserOp = _packUserOperationV07(userOperation);

    final result = await rpcClient.call(
      'pimlico_estimateErc20PaymasterCost',
      [
        packedUserOp,
        entryPoint.hex,
        token.hex,
      ],
    );

    return PimlicoErc20PaymasterCost.fromJson(result as Map<String, dynamic>);
  }

  // ================================================================
  // Sponsorship Policy Methods
  // ================================================================

  /// Validates sponsorship policy IDs for a UserOperation.
  ///
  /// Checks which sponsorship policies are valid for the given
  /// UserOperation and returns metadata about each valid policy.
  ///
  /// Use this to verify that a sponsorship policy will cover a
  /// UserOperation before submitting it.
  ///
  /// [userOperation] is the UserOperation to validate against policies.
  /// [sponsorshipPolicyIds] is a list of policy IDs to check.
  ///
  /// Returns a list of valid policies with their metadata.
  /// Invalid policies are not included in the response.
  ///
  /// Example:
  /// ```dart
  /// final policies = await pimlico.validateSponsorshipPolicies(
  ///   userOperation: userOp,
  ///   sponsorshipPolicyIds: ['sp_my_policy_id'],
  /// );
  ///
  /// if (policies.isNotEmpty) {
  ///   print('Valid policy: ${policies.first.data.name}');
  /// }
  /// ```
  Future<List<PimlicoSponsorshipPolicy>> validateSponsorshipPolicies({
    required UserOperationV07 userOperation,
    required List<String> sponsorshipPolicyIds,
  }) async {
    if (sponsorshipPolicyIds.isEmpty) {
      return [];
    }

    final packedUserOp = _packUserOperationV07(userOperation);

    final result = await rpcClient.call(
      'pimlico_validateSponsorshipPolicies',
      [
        packedUserOp,
        entryPoint.hex,
        sponsorshipPolicyIds,
      ],
    );

    return (result as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(PimlicoSponsorshipPolicy.fromJson)
        .toList();
  }
}

/// Creates a [PimlicoClient] from a URL and EntryPoint address.
///
/// Example:
/// ```dart
/// final pimlico = createPimlicoClient(
///   url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
///   entryPoint: EntryPointAddresses.v07,
/// );
/// ```
PimlicoClient createPimlicoClient({
  required String url,
  required EthereumAddress entryPoint,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    PimlicoClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
      entryPoint: entryPoint,
    );

/// Packs a UserOperationV07 for RPC transmission.
Map<String, dynamic> _packUserOperationV07(UserOperationV07 userOp) {
  final packed = <String, dynamic>{
    'sender': userOp.sender.hex,
    'nonce': Hex.fromBigInt(userOp.nonce),
    'callData': userOp.callData,
    'callGasLimit': Hex.fromBigInt(userOp.callGasLimit),
    'verificationGasLimit': Hex.fromBigInt(userOp.verificationGasLimit),
    'preVerificationGas': Hex.fromBigInt(userOp.preVerificationGas),
    'maxFeePerGas': Hex.fromBigInt(userOp.maxFeePerGas),
    'maxPriorityFeePerGas': Hex.fromBigInt(userOp.maxPriorityFeePerGas),
    'signature': userOp.signature,
  };

  // Factory data (v0.7 style)
  if (userOp.factory != null) {
    packed['factory'] = userOp.factory!.hex;
    packed['factoryData'] = userOp.factoryData ?? '0x';
  }

  // Paymaster data (v0.7 style)
  if (userOp.paymaster != null) {
    packed['paymaster'] = userOp.paymaster!.hex;
    packed['paymasterVerificationGasLimit'] =
        Hex.fromBigInt(userOp.paymasterVerificationGasLimit ?? BigInt.zero);
    packed['paymasterPostOpGasLimit'] =
        Hex.fromBigInt(userOp.paymasterPostOpGasLimit ?? BigInt.zero);
    packed['paymasterData'] = userOp.paymasterData ?? '0x';
  }

  return packed;
}

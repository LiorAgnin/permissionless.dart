/// Experimental ERC-20 paymaster utilities for Pimlico.
///
/// These utilities help prepare UserOperations that pay gas fees using
/// ERC-20 tokens instead of native ETH through Pimlico's ERC-20 paymaster.
///
/// **Warning:** This is experimental and the API may change.
library;

import '../../clients/paymaster/types.dart';
import '../../clients/pimlico/pimlico_client.dart';
import '../../clients/pimlico/types.dart';
import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_client.dart';
import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/erc20.dart';

/// Mainnet USDT address - requires special handling (reset to 0 before approve).
final EthereumAddress _mainnetUsdtAddress =
    EthereumAddress.fromHex('0xdAC17F958D2ee523a2206206994597C13D831ec7');

/// Configuration for ERC-20 paymaster preparation.
class Erc20PaymasterConfig {
  /// Creates a configuration for ERC-20 paymaster preparation.
  ///
  /// - [balanceOverride]: Whether to simulate a large token balance
  /// - [balanceSlot]: Custom storage slot for the balance mapping
  const Erc20PaymasterConfig({
    this.balanceOverride = false,
    this.balanceSlot,
  });

  /// Whether to use balance state override for gas estimation.
  ///
  /// When true, simulates having a large token balance during gas estimation.
  /// Useful when the account doesn't have tokens yet.
  final bool balanceOverride;

  /// Custom balance storage slot override.
  ///
  /// If not provided, uses the slot from token quotes (if available).
  final BigInt? balanceSlot;
}

/// Result of preparing a UserOperation for ERC-20 paymaster.
class Erc20PaymasterResult {
  /// Creates an ERC-20 paymaster preparation result.
  ///
  /// This is returned by [prepareUserOperationForErc20Paymaster].
  const Erc20PaymasterResult({
    required this.userOperation,
    required this.tokenQuote,
    required this.maxCostInToken,
    required this.approvalInjected,
  });

  /// The prepared UserOperation ready for signing.
  final UserOperationV07 userOperation;

  /// The token quote used for calculation.
  final PimlicoTokenQuote tokenQuote;

  /// Maximum cost of the operation in token units.
  final BigInt maxCostInToken;

  /// Whether an approval call was injected.
  final bool approvalInjected;
}

/// Prepares a UserOperation for ERC-20 paymaster gas payment.
///
/// This function handles the complexity of using ERC-20 tokens to pay for
/// gas fees with Pimlico's ERC-20 paymaster:
///
/// 1. Gets token quotes from Pimlico
/// 2. Injects a dummy approval for accurate gas estimation
/// 3. Calculates the maximum cost in tokens
/// 4. Checks existing allowance and injects approval if needed
/// 5. Handles USDT special case (requires 0 approval first)
/// 6. Re-calculates paymaster data with final calls
///
/// **Example:**
/// ```dart
/// final result = await prepareUserOperationForErc20Paymaster(
///   smartAccountClient: client,
///   pimlicoClient: pimlico,
///   publicClient: public,
///   token: usdcAddress,
///   calls: [transferCall],
///   maxFeePerGas: feeData.maxFeePerGas,
///   maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
/// );
///
/// // Sign and send the prepared operation
/// final signedOp = await client.signUserOperation(result.userOperation);
/// final hash = await client.sendPreparedUserOperation(signedOp);
///
/// print('Max cost: ${result.maxCostInToken} tokens');
/// print('Approval injected: ${result.approvalInjected}');
/// ```
///
/// **Warning:** This is experimental and the API may change.
Future<Erc20PaymasterResult> prepareUserOperationForErc20Paymaster({
  required SmartAccountClient smartAccountClient,
  required PimlicoClient pimlicoClient,
  required PublicClient publicClient,
  required EthereumAddress token,
  required List<Call> calls,
  required BigInt maxFeePerGas,
  required BigInt maxPriorityFeePerGas,
  BigInt? nonce,
  Erc20PaymasterConfig config = const Erc20PaymasterConfig(),
}) async {
  // 1. Get token quotes
  final quotes = await pimlicoClient.getTokenQuotes([token]);
  if (quotes.isEmpty) {
    throw ArgumentError(
      'Token $token is not supported by the Pimlico ERC-20 paymaster',
    );
  }

  final quote = quotes.first;
  final paymasterAddress = quote.paymaster;

  // 2. Create calls with dummy max approval for accurate gas estimation
  final accountAddress = await smartAccountClient.account.getAddress();
  final callsWithDummyApproval = [
    // Dummy max approval to ensure simulation passes
    encodeErc20Approve(
      token: token,
      spender: paymasterAddress,
      amount: maxUint256,
    ),
    ...calls,
  ];

  // Handle USDT special case (requires reset to 0 first)
  final isMainnetUsdt =
      token.hex.toLowerCase() == _mainnetUsdtAddress.hex.toLowerCase();
  if (isMainnetUsdt) {
    callsWithDummyApproval.insert(
      0,
      encodeErc20Approve(
        token: _mainnetUsdtAddress,
        spender: paymasterAddress,
        amount: BigInt.zero,
      ),
    );
  }

  // 3. Build state override if balance override is configured
  List<StateOverride>? stateOverride;
  if (config.balanceOverride) {
    final balanceSlot = config.balanceSlot ?? quote.balanceSlot;
    if (balanceSlot == null) {
      throw ArgumentError(
        'Balance override requested but no balance slot available for $token. '
        'Provide a custom balanceSlot in the config.',
      );
    }
    stateOverride = erc20BalanceOverride(
      token: token,
      owner: accountAddress,
      slot: balanceSlot,
    );
  }

  // 4. Prepare initial UserOperation with dummy approval
  final paymasterContext = PaymasterContext(token: token);

  final initialUserOp = await smartAccountClient.prepareUserOperation(
    calls: callsWithDummyApproval,
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    nonce: nonce,
    paymasterContext: paymasterContext,
    stateOverride: stateOverride,
  );

  // 5. Calculate maximum cost in tokens
  final userOperationMaxGas = initialUserOp.preVerificationGas +
      initialUserOp.callGasLimit +
      initialUserOp.verificationGasLimit +
      (initialUserOp.paymasterPostOpGasLimit ?? BigInt.zero) +
      (initialUserOp.paymasterVerificationGasLimit ?? BigInt.zero);

  final userOperationMaxCost = userOperationMaxGas * initialUserOp.maxFeePerGas;

  // Formula from Pimlico's singleton paymaster:
  // maxCostInToken = ((userOpMaxCost + postOpGas * maxFeePerGas) * exchangeRate) / 1e18
  final maxCostInToken =
      ((userOperationMaxCost + quote.postOpGas * initialUserOp.maxFeePerGas) *
              quote.exchangeRate) ~/
          BigInt.from(10).pow(18);

  // 6. Check existing allowance
  final allowanceCallData = encodeErc20AllowanceCall(
    owner: accountAddress,
    spender: paymasterAddress,
  );

  final allowanceResult = await publicClient.call(
    Call(to: token, data: allowanceCallData),
  );
  final currentAllowance = decodeUint256Result(allowanceResult);

  // 7. Build final calls with approval if needed
  final hasSufficientApproval = currentAllowance >= maxCostInToken;
  final finalCalls = List<Call>.from(calls);
  var approvalInjected = false;

  if (!hasSufficientApproval) {
    approvalInjected = true;

    // Add approval for exact max cost (not unlimited for security)
    finalCalls.insert(
      0,
      encodeErc20Approve(
        token: token,
        spender: paymasterAddress,
        amount: maxCostInToken,
      ),
    );

    // Handle USDT special case
    if (isMainnetUsdt) {
      finalCalls.insert(
        0,
        encodeErc20Approve(
          token: _mainnetUsdtAddress,
          spender: paymasterAddress,
          amount: BigInt.zero,
        ),
      );
    }
  }

  // 8. Re-encode call data with final calls
  final finalCallData = smartAccountClient.account.encodeCalls(finalCalls);

  // 9. Get final paymaster data
  final paymaster = smartAccountClient.paymaster;
  if (paymaster == null) {
    throw StateError(
      'SmartAccountClient must have a paymaster configured to use ERC-20 paymaster',
    );
  }

  final finalPaymasterData = await paymaster.getPaymasterData(
    userOp: UserOperationV07(
      sender: initialUserOp.sender,
      nonce: initialUserOp.nonce,
      factory: initialUserOp.factory,
      factoryData: initialUserOp.factoryData,
      callData: finalCallData,
      callGasLimit: initialUserOp.callGasLimit,
      verificationGasLimit: initialUserOp.verificationGasLimit,
      preVerificationGas: initialUserOp.preVerificationGas,
      maxFeePerGas: initialUserOp.maxFeePerGas,
      maxPriorityFeePerGas: initialUserOp.maxPriorityFeePerGas,
      signature: initialUserOp.signature,
    ),
    entryPoint: smartAccountClient.account.entryPoint,
    chainId: smartAccountClient.account.chainId,
    context: paymasterContext,
  );

  // 10. Build final UserOperation
  final finalUserOp = UserOperationV07(
    sender: initialUserOp.sender,
    nonce: initialUserOp.nonce,
    factory: initialUserOp.factory,
    factoryData: initialUserOp.factoryData,
    callData: finalCallData,
    callGasLimit: initialUserOp.callGasLimit,
    verificationGasLimit: initialUserOp.verificationGasLimit,
    preVerificationGas: initialUserOp.preVerificationGas,
    maxFeePerGas: initialUserOp.maxFeePerGas,
    maxPriorityFeePerGas: initialUserOp.maxPriorityFeePerGas,
    paymaster: finalPaymasterData.paymaster,
    paymasterVerificationGasLimit:
        finalPaymasterData.paymasterVerificationGasLimit,
    paymasterPostOpGasLimit: finalPaymasterData.paymasterPostOpGasLimit,
    paymasterData: finalPaymasterData.paymasterData,
    signature: smartAccountClient.account.getStubSignature(),
  );

  return Erc20PaymasterResult(
    userOperation: finalUserOp,
    tokenQuote: quote,
    maxCostInToken: maxCostInToken,
    approvalInjected: approvalInjected,
  );
}

/// Estimates the cost of a UserOperation in ERC-20 tokens.
///
/// This is a simpler utility that only calculates the estimated cost
/// without preparing the full UserOperation.
///
/// **Example:**
/// ```dart
/// final estimate = await estimateErc20PaymasterCost(
///   pimlicoClient: pimlico,
///   token: usdcAddress,
///   userOperation: preparedUserOp,
/// );
///
/// print('Estimated cost: ${estimate.maxCostInToken} tokens');
/// print('Exchange rate: ${estimate.exchangeRate}');
/// ```
Future<Erc20CostEstimate> estimateErc20PaymasterCost({
  required PimlicoClient pimlicoClient,
  required EthereumAddress token,
  required UserOperationV07 userOperation,
}) async {
  final quotes = await pimlicoClient.getTokenQuotes([token]);
  if (quotes.isEmpty) {
    throw ArgumentError(
      'Token $token is not supported by the Pimlico ERC-20 paymaster',
    );
  }

  final quote = quotes.first;

  final userOperationMaxGas = userOperation.preVerificationGas +
      userOperation.callGasLimit +
      userOperation.verificationGasLimit +
      (userOperation.paymasterPostOpGasLimit ?? BigInt.zero) +
      (userOperation.paymasterVerificationGasLimit ?? BigInt.zero);

  final userOperationMaxCost = userOperationMaxGas * userOperation.maxFeePerGas;

  final maxCostInToken =
      ((userOperationMaxCost + quote.postOpGas * userOperation.maxFeePerGas) *
              quote.exchangeRate) ~/
          BigInt.from(10).pow(18);

  return Erc20CostEstimate(
    maxCostInToken: maxCostInToken,
    exchangeRate: quote.exchangeRate,
    postOpGas: quote.postOpGas,
    paymasterAddress: quote.paymaster,
  );
}

/// Estimated cost of a UserOperation in ERC-20 tokens.
class Erc20CostEstimate {
  /// Creates an ERC-20 cost estimate.
  ///
  /// This is returned by [estimateErc20PaymasterCost].
  const Erc20CostEstimate({
    required this.maxCostInToken,
    required this.exchangeRate,
    required this.postOpGas,
    required this.paymasterAddress,
  });

  /// Maximum cost in token units.
  final BigInt maxCostInToken;

  /// Exchange rate used for calculation.
  final BigInt exchangeRate;

  /// Post-op gas overhead.
  final BigInt postOpGas;

  /// The paymaster address to approve.
  final EthereumAddress paymasterAddress;

  @override
  String toString() =>
      'Erc20CostEstimate(maxCost: $maxCostInToken, rate: $exchangeRate)';
}

/// Experimental ERC-20 paymaster utilities for Pimlico.
///
/// These utilities help prepare UserOperations that pay gas fees using
/// ERC-20 tokens instead of native ETH through Pimlico's ERC-20 paymaster.
///
/// **Warning:** This is experimental and the API may change.
library;

import '../../clients/paymaster/paymaster_client.dart';
import '../../clients/paymaster/types.dart';
import '../../clients/pimlico/erc20_cost.dart';
import '../../clients/pimlico/erc20_paymaster.dart';
import '../../clients/pimlico/pimlico_client.dart';
import '../../clients/pimlico/types.dart';
import '../../clients/public/public_client.dart';
import '../../clients/smart_account/call_encoding.dart';
import '../../clients/smart_account/smart_account_client.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/user_operation.dart';
import '../../utils/erc20.dart';
import '../../utils/state_override.dart';

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
    this.authorization,
  });

  /// The prepared UserOperation ready for signing.
  final UserOperationV07 userOperation;

  /// The token quote used for calculation.
  final PimlicoTokenQuote tokenQuote;

  /// Maximum cost of the operation in token units.
  final BigInt maxCostInToken;

  /// Whether an approval call was injected.
  final bool approvalInjected;

  /// EIP-7702 authorization for first-time delegation, if required.
  ///
  /// Non-null only for EIP-7702 accounts whose delegation is not yet active.
  /// Pass it as the `authorization` of
  /// `SmartAccountClient.sendPreparedUserOperation` so the bundler receives
  /// it as the `eip7702Auth` field.
  final Eip7702Authorization? authorization;

  /// Whether this operation requires EIP-7702 authorization on submission.
  bool get needsAuthorization => authorization != null;
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
/// // Sign and send the prepared operation.
/// // For EIP-7702 first-time delegation, result.authorization is non-null
/// // and must be submitted alongside the op (the delegation is installed by
/// // this same operation); a null authorization sends the op without one.
/// final signedOp = await client.signUserOperation(result.userOperation);
/// final hash = await client.sendPreparedUserOperation(
///   signedOp,
///   authorization: result.authorization,
/// );
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
  // permissionless.js parity: quoted for `account.entryPoint.address`, the
  // EntryPoint the op is sponsored and sent on, not the Pimlico client's.
  final quote = tokenQuoteFor(
    token,
    await pimlicoClient.getTokenQuotes(
      [token],
      entryPoint: smartAccountClient.account.entryPoint,
    ),
  );
  final paymasterAddress = quote.paymaster;

  // A max approval keeps gas simulation from failing on allowance checks.
  final accountAddress = await smartAccountClient.account.getAddress();
  final callsWithDummyApproval = _withApproval(
    calls,
    token: token,
    spender: paymasterAddress,
    amount: maxUint256,
  );

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

  // Auth-aware variant: for an EIP-7702 account with inactive delegation this
  // also produces the signed authorization, which must accompany every
  // paymaster/bundler request (as `eip7702Auth`) and the final submission.
  //
  // skipFinalPaymasterData: the paymaster re-signs the op below
  // over the final calldata, so the prepare-time pm_getPaymasterData result
  // would be discarded. Stub data + gas estimation are enough here
  // (permissionless.js parity: its prepare step substitutes stub data).
  final paymasterContext = PaymasterContext(token: token);

  final prepared = await smartAccountClient.prepareUserOperationWithAuth(
    calls: callsWithDummyApproval,
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    nonce: nonce,
    paymasterContext: paymasterContext,
    stateOverride: stateOverride,
    skipFinalPaymasterData: true,
  );
  final initialUserOp = prepared.userOp;
  final authorization = prepared.authorization;

  final maxCostInToken = estimateTokenCost(quote: quote, userOp: initialUserOp);

  final currentAllowance = await getTokenAllowance(
    publicClient: publicClient,
    token: token,
    owner: accountAddress,
    spender: paymasterAddress,
  );
  // Approve exactly the max cost (not unlimited) when the allowance is short.
  final approvalInjected = currentAllowance < maxCostInToken;
  final finalCalls = approvalInjected
      ? _withApproval(
          calls,
          token: token,
          spender: paymasterAddress,
          amount: maxCostInToken,
        )
      : calls;

  final finalCallData = encodeUserOperationCalls(
    smartAccountClient.account,
    finalCalls,
    deploysAccount: initialUserOp.factory != null,
  );

  final paymaster = smartAccountClient.paymaster;
  if (paymaster == null) {
    throw StateError(
      'SmartAccountClient must have a paymaster configured to use ERC-20 paymaster',
    );
  }

  // Send the FULL prepared op with only callData replaced (permissionless.js
  // parity: it mutates userOperation.callData and spreads the whole op).
  // The stub paymaster fields and the estimated paymaster gas limits must be
  // present — Pimlico's ERC-20 mode rejects the request without them
  // ("paymasterValidationGasLimit is required for erc20 mode").
  final finalPaymasterData = await paymaster.getPaymasterData(
    userOp: initialUserOp.copyWith(callData: finalCallData),
    entryPoint: smartAccountClient.account.entryPoint,
    chainId: smartAccountClient.account.chainId,
    context: paymasterContext,
    // EIP-7702 first op: the paymaster must sign over the same op the account
    // signs/sends, so it needs the same `eip7702Auth` context as stub/estimate.
    authorization: authorization,
  );

  // permissionless.js parity:
  // `{...userOperation, ...paymasterData}` — response fields override, gas
  // limits estimated earlier survive if the response omits them).
  final finalUserOp = initialUserOp
      .copyWith(callData: finalCallData)
      .withPaymasterData(finalPaymasterData);

  return Erc20PaymasterResult(
    userOperation: finalUserOp,
    tokenQuote: quote,
    maxCostInToken: maxCostInToken,
    approvalInjected: approvalInjected,
    authorization: authorization,
  );
}

/// Estimates the cost of a UserOperation in ERC-20 tokens.
///
/// This is a simpler utility that only calculates the estimated cost
/// without preparing the full UserOperation.
///
/// [entryPoint] is the EntryPoint whose paymaster quotes the token; pass the
/// account's. It defaults to the [PimlicoClient]'s EntryPoint.
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
  EthereumAddress? entryPoint,
}) async {
  final quote = tokenQuoteFor(
    token,
    await pimlicoClient.getTokenQuotes([token], entryPoint: entryPoint),
  );
  final maxCostInToken = estimateTokenCost(quote: quote, userOp: userOperation);

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

/// [calls] preceded by an ERC-20 approval of [amount] to [spender]. Mainnet
/// USDT rejects changing a non-zero allowance, so it is reset to 0 first.
List<Call> _withApproval(
  List<Call> calls, {
  required EthereumAddress token,
  required EthereumAddress spender,
  required BigInt amount,
}) =>
    [
      if (token.hex == _mainnetUsdtAddress.hex)
        encodeErc20Approve(token: token, spender: spender, amount: BigInt.zero),
      encodeErc20Approve(token: token, spender: spender, amount: amount),
      ...calls,
    ];

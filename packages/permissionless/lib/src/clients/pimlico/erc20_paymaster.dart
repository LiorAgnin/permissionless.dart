import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/erc20.dart';
import '../public/public_client.dart';
import 'erc20_cost.dart';
import 'types.dart';

/// A typical postOp gas figure for ERC-20 paymasters (about 75,000).
///
/// Nothing in this library reads it: the ERC-20 cost uses the quote's own
/// [PimlicoTokenQuote.postOpGas].
@Deprecated('Unused; the cost uses PimlicoTokenQuote.postOpGas')
const int erc20PaymasterGasBuffer = 75000;

/// Checks the token allowance for a spender.
///
/// Returns how much the [spender] is allowed to transfer on behalf
/// of the [owner] for the specified [token].
///
/// Use this to check if a token approval is needed before submitting
/// a UserOperation with an ERC-20 paymaster.
///
/// Throws [StateError] when the call returns no data (`0x`): [token] has no
/// code on this chain (wrong chain or mistyped address). viem's
/// `readContract` throws `ContractFunctionZeroDataError` there too.
///
/// Example:
/// ```dart
/// final allowance = await getTokenAllowance(
///   publicClient: publicClient,
///   token: usdcAddress,
///   owner: accountAddress,
///   spender: paymasterAddress,
/// );
///
/// if (allowance < requiredAmount) {
///   // Need to add approval call to the batch
/// }
/// ```
Future<BigInt> getTokenAllowance({
  required PublicClient publicClient,
  required EthereumAddress token,
  required EthereumAddress owner,
  required EthereumAddress spender,
}) async {
  final callData = encodeErc20AllowanceCall(owner: owner, spender: spender);
  final result =
      await _readToken(publicClient, token, callData, 'getTokenAllowance');
  return decodeUint256Result(result);
}

/// Checks the token balance of an account.
///
/// Returns the balance of [token] held by [account].
///
/// Throws [StateError] when the call returns no data (`0x`): [token] has no
/// code on this chain (wrong chain or mistyped address). viem's
/// `readContract` throws `ContractFunctionZeroDataError` there too.
///
/// Example:
/// ```dart
/// final balance = await getTokenBalance(
///   publicClient: publicClient,
///   token: usdcAddress,
///   account: myAddress,
/// );
/// print('Balance: $balance');
/// ```
Future<BigInt> getTokenBalance({
  required PublicClient publicClient,
  required EthereumAddress token,
  required EthereumAddress account,
}) async {
  final callData = encodeErc20BalanceOfCall(account: account);
  final result =
      await _readToken(publicClient, token, callData, 'getTokenBalance');
  return decodeUint256Result(result);
}

/// `eth_call` to [token]; `0x` is an error, as with viem `readContract`.
Future<String> _readToken(
  PublicClient publicClient,
  EthereumAddress token,
  String callData,
  String function,
) async {
  final result = await publicClient.call(Call(to: token, data: callData));
  if (result.isEmpty || result == '0x') {
    throw StateError(
      '$function: eth_call to token ${token.checksummed} returned no data; '
      'is it an ERC-20 contract on this chain?',
    );
  }
  return result;
}

/// Creates an approval call for the paymaster.
///
/// Returns a [Call] that approves the [paymaster] to spend tokens
/// from the smart account. Include this at the beginning of your
/// batch transaction if the allowance is insufficient.
///
/// By default, uses [maxUint256] for unlimited approval. You can
/// specify a smaller [amount] for more restrictive approvals.
///
/// Example:
/// ```dart
/// final approveCall = createPaymasterApprovalCall(
///   token: usdcAddress,
///   paymaster: quote.paymaster,
/// );
///
/// // Include in batch with other calls
/// final calls = [approveCall, ...userCalls];
/// await client.sendUserOperation(
///   calls: calls,
///   paymasterContext: PaymasterContext(token: usdcAddress),
/// );
/// ```
Call createPaymasterApprovalCall({
  required EthereumAddress token,
  required EthereumAddress paymaster,
  BigInt? amount,
}) =>
    encodeErc20Approve(
      token: token,
      spender: paymaster,
      amount: amount ?? maxUint256,
    );

/// Estimates the token cost for a UserOperation.
///
/// Calculates how many tokens will be charged for the operation
/// based on the gas limits and the exchange rate from the quote.
///
/// This is an estimate - actual cost may vary based on execution.
///
/// Example:
/// ```dart
/// final tokenCost = estimateTokenCost(
///   quote: tokenQuote,
///   userOp: preparedUserOp,
/// );
/// print('Estimated cost: $tokenCost tokens');
/// ```
BigInt estimateTokenCost({
  required PimlicoTokenQuote quote,
  required UserOperation userOp,
}) =>
    weiToTokenUnits(
      erc20PaymasterMaxCostInWei(userOp, quote.postOpGas),
      quote.exchangeRate,
    );

/// Checks if approval is needed and returns an optional approval call.
///
/// This is a convenience function that combines allowance checking
/// with approval call creation.
///
/// Returns an approval [Call] if the current allowance is less than
/// [requiredAmount], or null if no approval is needed.
///
/// Throws [StateError] like [getTokenAllowance] when [token] has no code.
///
/// Example:
/// ```dart
/// final approvalCall = await getApprovalCallIfNeeded(
///   publicClient: publicClient,
///   token: usdcAddress,
///   owner: accountAddress,
///   spender: paymasterAddress,
///   requiredAmount: estimatedTokenCost,
/// );
///
/// final calls = [
///   if (approvalCall != null) approvalCall,
///   ...userCalls,
/// ];
/// ```
Future<Call?> getApprovalCallIfNeeded({
  required PublicClient publicClient,
  required EthereumAddress token,
  required EthereumAddress owner,
  required EthereumAddress spender,
  required BigInt requiredAmount,
  BigInt? approvalAmount,
}) async {
  final currentAllowance = await getTokenAllowance(
    publicClient: publicClient,
    token: token,
    owner: owner,
    spender: spender,
  );

  if (currentAllowance >= requiredAmount) {
    return null;
  }

  return createPaymasterApprovalCall(
    token: token,
    paymaster: spender,
    amount: approvalAmount,
  );
}

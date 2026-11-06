import '../../types/address.dart';
import '../../types/user_operation.dart';
import '../../utils/gas.dart';
import 'types.dart';

final BigInt _rateScale = BigInt.from(10).pow(18);

/// The quote for [token] from a `pimlico_getTokenQuotes` result, which is
/// requested for that one token.
PimlicoTokenQuote tokenQuoteFor(
  EthereumAddress token,
  List<PimlicoTokenQuote> quotes,
) {
  if (quotes.isEmpty) {
    throw ArgumentError(
      'Token $token is not supported by the Pimlico ERC-20 paymaster',
    );
  }
  return quotes.first;
}

/// The most native currency (wei) Pimlico's ERC-20 paymaster can charge for
/// [userOperation]: the EntryPoint prefund plus the paymaster's own postOp
/// gas, both at `maxFeePerGas` (permissionless.js
/// `estimateErc20PaymasterCost`).
BigInt erc20PaymasterMaxCostInWei(
  UserOperation userOperation,
  BigInt postOpGas,
) =>
    switch (userOperation) {
      UserOperationV07() => getRequiredPrefund(userOperation) +
          postOpGas * userOperation.maxFeePerGas,
      UserOperationV06() => getRequiredPrefundV06(userOperation) +
          postOpGas * userOperation.maxFeePerGas,
    };

/// Converts [wei] with an 18-decimal [exchangeRate] (token units per wei).
BigInt weiToTokenUnits(BigInt wei, BigInt exchangeRate) =>
    (wei * exchangeRate) ~/ _rateScale;

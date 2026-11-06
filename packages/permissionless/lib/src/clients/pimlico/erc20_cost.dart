import '../../types/user_operation.dart';
import '../../utils/gas.dart';

final BigInt _rateScale = BigInt.from(10).pow(18);

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

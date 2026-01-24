import '../clients/bundler/types.dart';
import '../clients/pimlico/pimlico_client.dart';
import '../clients/public/public_client.dart';
import '../types/address.dart';
import '../types/user_operation.dart';

/// Speed tier for gas price estimation.
enum GasSpeed {
  /// Lower fees, longer confirmation time.
  slow,

  /// Balanced fees and confirmation time.
  standard,

  /// Higher fees, faster confirmation.
  fast,
}

/// Multipliers to apply to gas estimates for safety margins.
///
/// Bundler gas estimates can sometimes be slightly low, leading to
/// failed transactions. Applying multipliers provides safety margins.
///
/// Example:
/// ```dart
/// final estimate = await bundler.estimateUserOperationGas(userOp);
/// final buffered = estimate.withMultipliers(GasMultipliers.conservative);
/// ```
class GasMultipliers {
  /// Creates gas multipliers with the given values.
  ///
  /// All multipliers default to 1.1 (10% buffer) except for preVerificationGas
  /// which defaults to 1.0 (no buffer).
  const GasMultipliers({
    this.verificationGasLimit = 1.1,
    this.callGasLimit = 1.1,
    this.preVerificationGas = 1.0,
    this.paymasterVerificationGasLimit = 1.1,
    this.paymasterPostOpGasLimit = 1.1,
  });

  /// Multiplier for verification gas limit.
  final double verificationGasLimit;

  /// Multiplier for call gas limit.
  final double callGasLimit;

  /// Multiplier for pre-verification gas.
  final double preVerificationGas;

  /// Multiplier for paymaster verification gas limit.
  final double paymasterVerificationGasLimit;

  /// Multiplier for paymaster post-op gas limit.
  final double paymasterPostOpGasLimit;

  /// No buffers - use exact estimates.
  ///
  /// Use when gas estimates are known to be accurate.
  static const none = GasMultipliers(
    verificationGasLimit: 1,
    callGasLimit: 1,
    preVerificationGas: 1,
    paymasterVerificationGasLimit: 1,
    paymasterPostOpGasLimit: 1,
  );

  /// Default multipliers - 10% buffer on most limits.
  ///
  /// Safe for most use cases.
  static const standard = GasMultipliers();

  /// Conservative multipliers - larger buffers.
  ///
  /// Use when you want to minimize transaction failures.
  static const conservative = GasMultipliers(
    verificationGasLimit: 1.3,
    callGasLimit: 1.2,
    preVerificationGas: 1.1,
    paymasterVerificationGasLimit: 1.3,
    paymasterPostOpGasLimit: 1.2,
  );

  /// Multipliers for WebAuthn/Passkey accounts.
  ///
  /// P256 signature verification without the RIP-7212 precompile requires
  /// approximately 800k gas for on-chain ECDSA math. This preset provides
  /// a 3x buffer on verificationGasLimit to account for this.
  ///
  /// Use this preset when the smart account uses WebAuthn/Passkey authentication
  /// and the chain does NOT have reliable RIP-7212 precompile support.
  ///
  /// Example:
  /// ```dart
  /// final estimate = await bundler.estimateUserOperationGas(userOp);
  /// final buffered = estimate.withMultipliers(GasMultipliers.webAuthn);
  /// ```
  static const webAuthn = GasMultipliers(
    verificationGasLimit: 3, // P256 on-chain verification is ~800k gas
    callGasLimit: 1.2,
    preVerificationGas: 1,
    paymasterVerificationGasLimit: 1.3,
    paymasterPostOpGasLimit: 1.2,
  );
}

/// Extension to apply multipliers to gas estimates.
extension GasEstimateMultipliers on UserOperationGasEstimate {
  /// Applies multipliers to this gas estimate.
  ///
  /// Returns a new estimate with buffered values.
  UserOperationGasEstimate withMultipliers(GasMultipliers multipliers) =>
      UserOperationGasEstimate(
        preVerificationGas: _applyMultiplier(
          preVerificationGas,
          multipliers.preVerificationGas,
        ),
        verificationGasLimit: _applyMultiplier(
          verificationGasLimit,
          multipliers.verificationGasLimit,
        ),
        callGasLimit: _applyMultiplier(
          callGasLimit,
          multipliers.callGasLimit,
        ),
        paymasterVerificationGasLimit: paymasterVerificationGasLimit != null
            ? _applyMultiplier(
                paymasterVerificationGasLimit!,
                multipliers.paymasterVerificationGasLimit,
              )
            : null,
        paymasterPostOpGasLimit: paymasterPostOpGasLimit != null
            ? _applyMultiplier(
                paymasterPostOpGasLimit!,
                multipliers.paymasterPostOpGasLimit,
              )
            : null,
      );

  /// Calculates the total gas limit for this estimate.
  BigInt get totalGasLimit {
    var total = preVerificationGas + verificationGasLimit + callGasLimit;
    if (paymasterVerificationGasLimit != null) {
      total += paymasterVerificationGasLimit!;
    }
    if (paymasterPostOpGasLimit != null) {
      total += paymasterPostOpGasLimit!;
    }
    return total;
  }

  /// Ensures verificationGasLimit is at least the specified minimum.
  ///
  /// Use this for WebAuthn/Passkey accounts where P256 signature verification
  /// without the RIP-7212 precompile requires ~800k gas. Bundler estimates
  /// may underestimate this cost.
  ///
  /// The default minimum of 900,000 provides buffer for on-chain P256 math.
  ///
  /// Example:
  /// ```dart
  /// final estimate = await bundler.estimateUserOperationGas(userOp);
  /// final adjusted = estimate.withMinimumVerificationGas();
  /// ```
  UserOperationGasEstimate withMinimumVerificationGas({
    BigInt? minimum,
  }) {
    // Default: 900k gas for P256 on-chain verification with buffer
    final minGas = minimum ?? BigInt.from(900000);

    if (verificationGasLimit >= minGas) {
      return this;
    }

    return UserOperationGasEstimate(
      preVerificationGas: preVerificationGas,
      verificationGasLimit: minGas,
      callGasLimit: callGasLimit,
      paymasterVerificationGasLimit: paymasterVerificationGasLimit,
      paymasterPostOpGasLimit: paymasterPostOpGasLimit,
    );
  }
}

/// Estimated gas fees for a transaction.
///
/// Contains both maxFeePerGas and maxPriorityFeePerGas for EIP-1559.
class FeeEstimate {
  /// Creates a fee estimate with the given gas price values.
  ///
  /// - [maxFeePerGas]: Maximum total fee per gas unit
  /// - [maxPriorityFeePerGas]: Maximum priority fee (tip) per gas unit
  const FeeEstimate({
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
  });

  /// Maximum total fee per gas unit.
  final BigInt maxFeePerGas;

  /// Maximum priority fee (tip) per gas unit.
  final BigInt maxPriorityFeePerGas;

  /// Applies a multiplier to both fees.
  ///
  /// Useful for adding a buffer to ensure faster inclusion.
  FeeEstimate withMultiplier(double multiplier) => FeeEstimate(
        maxFeePerGas: _applyMultiplier(maxFeePerGas, multiplier),
        maxPriorityFeePerGas:
            _applyMultiplier(maxPriorityFeePerGas, multiplier),
      );

  @override
  String toString() =>
      'FeeEstimate(maxFee: $maxFeePerGas, maxPriority: $maxPriorityFeePerGas)';
}

/// Estimates the maximum cost of a UserOperation.
///
/// Helps users understand the maximum amount they might pay.
class GasCostEstimate {
  /// Creates a gas cost estimate with the given values.
  ///
  /// Prefer using [GasCostEstimate.calculate] factory to compute these
  /// values from a [UserOperationGasEstimate] and gas price.
  const GasCostEstimate({
    required this.totalGasLimit,
    required this.maxGasCost,
  });

  /// Calculates the maximum cost for a UserOperation.
  ///
  /// Example:
  /// ```dart
  /// final cost = GasCostEstimate.calculate(
  ///   gasEstimate: estimate,
  ///   maxFeePerGas: fees.maxFeePerGas,
  /// );
  /// print('Max cost: ${GasUnits.weiToEther(cost.maxGasCost)} ETH');
  /// ```
  factory GasCostEstimate.calculate({
    required UserOperationGasEstimate gasEstimate,
    required BigInt maxFeePerGas,
  }) {
    final totalGas = gasEstimate.totalGasLimit;
    return GasCostEstimate(
      totalGasLimit: totalGas,
      maxGasCost: totalGas * maxFeePerGas,
    );
  }

  /// Total gas limit (sum of all gas components).
  final BigInt totalGasLimit;

  /// Maximum cost in wei (totalGasLimit * maxFeePerGas).
  final BigInt maxGasCost;

  @override
  String toString() =>
      'GasCostEstimate(totalGas: $totalGasLimit, maxCost: $maxGasCost)';
}

/// Gets fee estimates from a public client.
///
/// Combines gasPrice and maxPriorityFeePerGas into a FeeEstimate.
/// Applies an optional multiplier for safety.
///
/// Example:
/// ```dart
/// final fees = await estimateFees(publicClient, multiplier: 1.2);
/// ```
Future<FeeEstimate> estimateFees(
  PublicClient public, {
  double multiplier = 1.1,
}) async {
  final feeData = await public.getFeeData();

  var maxFeePerGas = feeData.gasPrice;
  var maxPriorityFeePerGas = feeData.maxPriorityFeePerGas ?? feeData.gasPrice;

  // Apply multiplier
  if (multiplier != 1.0) {
    maxFeePerGas = _applyMultiplier(maxFeePerGas, multiplier);
    maxPriorityFeePerGas = _applyMultiplier(maxPriorityFeePerGas, multiplier);
  }

  return FeeEstimate(
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
  );
}

/// Gets fee estimates from a Pimlico client.
///
/// Uses Pimlico's gas price oracle for more accurate estimates.
/// Supports speed tiers (slow, standard, fast).
///
/// Example:
/// ```dart
/// final fees = await estimateFeesFromPimlico(
///   pimlicoClient,
///   speed: GasSpeed.fast,
/// );
/// ```
Future<FeeEstimate> estimateFeesFromPimlico(
  PimlicoClient pimlico, {
  GasSpeed speed = GasSpeed.standard,
}) async {
  final gasPrices = await pimlico.getUserOperationGasPrice();

  final price = switch (speed) {
    GasSpeed.slow => gasPrices.slow,
    GasSpeed.standard => gasPrices.standard,
    GasSpeed.fast => gasPrices.fast,
  };

  return FeeEstimate(
    maxFeePerGas: price.maxFeePerGas,
    maxPriorityFeePerGas: price.maxPriorityFeePerGas,
  );
}

/// Applies a multiplier to a BigInt value.
BigInt _applyMultiplier(BigInt value, double multiplier) {
  if (multiplier == 1.0) return value;
  // Scale up to avoid precision loss, then scale back down
  final scaled = (value.toDouble() * multiplier * 1000).round();
  return BigInt.from(scaled) ~/ BigInt.from(1000);
}

// ============================================================================
// Required Prefund Calculation
// ============================================================================

/// Calculates the required prefund for a UserOperation (v0.7).
///
/// The prefund is the minimum amount of ETH that must be in the smart account
/// (or covered by a paymaster) to execute the UserOperation.
///
/// Formula for v0.7:
/// ```
/// requiredGas = verificationGasLimit + callGasLimit +
///               paymasterVerificationGasLimit + paymasterPostOpGasLimit +
///               preVerificationGas
/// requiredPrefund = requiredGas * maxFeePerGas
/// ```
///
/// Example:
/// ```dart
/// final prefund = getRequiredPrefund(userOperation);
/// print('Required prefund: ${prefund / BigInt.from(10).pow(18)} ETH');
///
/// final balance = await publicClient.getBalance(accountAddress);
/// if (balance < prefund) {
///   print('Insufficient balance! Need ${prefund - balance} more wei');
/// }
/// ```
BigInt getRequiredPrefund(UserOperationV07 userOperation) {
  var requiredGas = userOperation.verificationGasLimit +
      userOperation.callGasLimit +
      userOperation.preVerificationGas;

  // Add paymaster gas limits if present
  if (userOperation.paymasterVerificationGasLimit != null) {
    requiredGas += userOperation.paymasterVerificationGasLimit!;
  }
  if (userOperation.paymasterPostOpGasLimit != null) {
    requiredGas += userOperation.paymasterPostOpGasLimit!;
  }

  return requiredGas * userOperation.maxFeePerGas;
}

/// Calculates the required prefund for a UserOperation (v0.6).
///
/// Formula for v0.6:
/// ```
/// multiplier = hasPaymaster ? 3 : 1
/// requiredGas = callGasLimit + (verificationGasLimit * multiplier) + preVerificationGas
/// requiredPrefund = requiredGas * maxFeePerGas
/// ```
///
/// The multiplier accounts for the additional verification done when
/// a paymaster is involved (paymaster validation + post-op).
///
/// Example:
/// ```dart
/// final prefund = getRequiredPrefundV06(userOperationV06);
/// ```
BigInt getRequiredPrefundV06(UserOperationV06 userOperation) {
  // Check if paymaster is present (paymasterAndData > 2 chars means it has content beyond '0x')
  final hasPaymaster = userOperation.paymasterAndData.length > 2;

  final multiplier = hasPaymaster ? BigInt.from(3) : BigInt.one;

  final requiredGas = userOperation.callGasLimit +
      (userOperation.verificationGasLimit * multiplier) +
      userOperation.preVerificationGas;

  return requiredGas * userOperation.maxFeePerGas;
}

// ============================================================================
// Address Extraction Utilities
// ============================================================================

/// Extracts an address from `initCode` or `paymasterAndData` fields.
///
/// In ERC-4337, both `initCode` and `paymasterAndData` start with a 20-byte
/// address followed by additional data:
/// - `initCode` = factory address (20 bytes) + factory call data
/// - `paymasterAndData` = paymaster address (20 bytes) + paymaster-specific data
///
/// Returns the leading address if the data is long enough (at least 20 bytes),
/// or `null` if the data is empty or too short.
///
/// Example:
/// ```dart
/// // Extract factory address from initCode
/// final factoryAddress = getAddressFromInitCodeOrPaymasterAndData(
///   userOp.initCode,
/// );
/// if (factoryAddress != null) {
///   print('Factory: ${factoryAddress.hex}');
/// }
///
/// // Extract paymaster address from paymasterAndData
/// final paymasterAddress = getAddressFromInitCodeOrPaymasterAndData(
///   userOp.paymasterAndData,
/// );
/// ```
EthereumAddress? getAddressFromInitCodeOrPaymasterAndData(String? data) {
  // Handle null or empty data
  if (data == null || data.isEmpty || data == '0x') {
    return null;
  }

  // An address needs at least 42 hex characters: '0x' + 40 hex digits (20 bytes)
  if (data.length < 42) {
    return null;
  }

  // Extract the first 20 bytes (40 hex chars + '0x' prefix)
  final addressHex = data.substring(0, 42);

  try {
    return EthereumAddress.fromHex(addressHex);
  } catch (_) {
    // Invalid address format
    return null;
  }
}

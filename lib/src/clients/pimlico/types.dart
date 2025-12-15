import '../../types/address.dart';
import '../../utils/parsing.dart';
import '../bundler/types.dart';

/// Detailed status of a UserOperation from Pimlico.
///
/// Provides more granular status than the standard bundler receipt,
/// including states like queued, pending, and rejected.
class PimlicoUserOperationStatus {
  const PimlicoUserOperationStatus({
    required this.status,
    this.transactionHash,
    this.receipt,
  });

  factory PimlicoUserOperationStatus.fromJson(Map<String, dynamic> json) {
    final receiptJson = json['receipt'] as Map<String, dynamic>?;

    return PimlicoUserOperationStatus(
      status: json['status'] as String,
      transactionHash: json['transactionHash'] as String?,
      receipt: receiptJson != null
          ? UserOperationReceipt.fromJson(receiptJson)
          : null,
    );
  }

  /// Status of the UserOperation.
  ///
  /// Possible values:
  /// - 'not_found': UserOperation not found
  /// - 'not_submitted': UserOperation received but not yet submitted
  /// - 'submitted': UserOperation submitted to the mempool
  /// - 'rejected': UserOperation rejected by bundler
  /// - 'reverted': UserOperation execution reverted
  /// - 'included': UserOperation included in a block
  /// - 'failed': UserOperation failed
  final String status;

  /// Transaction hash if the UserOperation was submitted.
  final String? transactionHash;

  /// Full receipt if the UserOperation was included.
  final UserOperationReceipt? receipt;

  /// Whether the UserOperation is still pending (not yet included or failed).
  bool get isPending => status == 'not_submitted' || status == 'submitted';

  /// Whether the UserOperation was successful.
  bool get isSuccess => status == 'included' && (receipt?.success ?? false);

  /// Whether the UserOperation failed.
  bool get isFailed =>
      status == 'rejected' || status == 'reverted' || status == 'failed';

  @override
  String toString() =>
      'PimlicoUserOperationStatus($status${transactionHash != null ? ', tx: $transactionHash' : ''})';
}

/// Gas price tier from Pimlico's gas price oracle.
///
/// Contains EIP-1559 gas price values for a specific speed tier.
class PimlicoGasPrice {
  const PimlicoGasPrice({
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
  });

  factory PimlicoGasPrice.fromJson(Map<String, dynamic> json) =>
      PimlicoGasPrice(
        maxFeePerGas: parseBigInt(json['maxFeePerGas']),
        maxPriorityFeePerGas: parseBigInt(json['maxPriorityFeePerGas']),
      );

  /// Maximum total fee per gas unit (base fee + priority fee).
  final BigInt maxFeePerGas;

  /// Maximum priority fee (tip) per gas unit.
  final BigInt maxPriorityFeePerGas;

  @override
  String toString() =>
      'PimlicoGasPrice(maxFee: $maxFeePerGas, maxPriority: $maxPriorityFeePerGas)';
}

/// Gas price recommendations from Pimlico.
///
/// Provides three tiers of gas prices optimized for different
/// confirmation speed requirements.
class PimlicoGasPrices {
  const PimlicoGasPrices({
    required this.slow,
    required this.standard,
    required this.fast,
  });

  factory PimlicoGasPrices.fromJson(Map<String, dynamic> json) =>
      PimlicoGasPrices(
        slow: PimlicoGasPrice.fromJson(json['slow'] as Map<String, dynamic>),
        standard:
            PimlicoGasPrice.fromJson(json['standard'] as Map<String, dynamic>),
        fast: PimlicoGasPrice.fromJson(json['fast'] as Map<String, dynamic>),
      );

  /// Slow tier - lower fees, longer confirmation time.
  final PimlicoGasPrice slow;

  /// Standard tier - balanced fees and confirmation time.
  final PimlicoGasPrice standard;

  /// Fast tier - higher fees, faster confirmation.
  final PimlicoGasPrice fast;

  @override
  String toString() =>
      'PimlicoGasPrices(slow: $slow, standard: $standard, fast: $fast)';
}

/// Token quote from pimlico_getTokenQuotes.
///
/// Contains exchange rate and gas overhead information for a specific
/// ERC-20 token when used with the Pimlico ERC-20 paymaster.
///
/// Example:
/// ```dart
/// final quotes = await pimlico.getTokenQuotes([usdcAddress]);
/// final quote = quotes.first;
///
/// print('Paymaster: ${quote.paymaster.checksummed}');
/// print('Exchange rate: ${quote.exchangeRate}');
/// print('Post-op gas: ${quote.postOpGas}');
/// ```
class PimlicoTokenQuote {
  const PimlicoTokenQuote({
    required this.token,
    required this.paymaster,
    required this.postOpGas,
    required this.exchangeRate,
    this.exchangeRateNativeToUsd,
    this.balanceSlot,
    this.allowanceSlot,
  });

  factory PimlicoTokenQuote.fromJson(Map<String, dynamic> json) =>
      PimlicoTokenQuote(
        token: EthAddress(json['token'] as String),
        paymaster: EthAddress(json['paymaster'] as String),
        postOpGas: parseBigInt(json['postOpGas']),
        exchangeRate: parseBigInt(json['exchangeRate']),
        exchangeRateNativeToUsd: json['exchangeRateNativeToUsd'] != null
            ? parseBigInt(json['exchangeRateNativeToUsd'])
            : null,
        balanceSlot: json['balanceSlot'] != null
            ? parseBigInt(json['balanceSlot'])
            : null,
        allowanceSlot: json['allowanceSlot'] != null
            ? parseBigInt(json['allowanceSlot'])
            : null,
      );

  /// The ERC-20 token address.
  final EthAddress token;

  /// The paymaster contract address for this token.
  ///
  /// Users must approve this address to spend their tokens.
  final EthAddress paymaster;

  /// Additional gas used in postOp for token transfer.
  ///
  /// This is added to the paymasterPostOpGasLimit in the UserOperation.
  final BigInt postOpGas;

  /// Exchange rate between the token and the native gas token.
  ///
  /// Used to calculate token cost from wei cost.
  final BigInt exchangeRate;

  /// Exchange rate: native gas token to USD (with 6 decimals precision).
  ///
  /// Example: `0xe9e52828` = 3923,076,136 = ~$3923.08 per ETH
  /// May be null if the API doesn't provide this field.
  final BigInt? exchangeRateNativeToUsd;

  /// Storage slot for the token's balance mapping.
  ///
  /// Used for state overrides during gas estimation. Use with
  /// [erc20BalanceOverride] to simulate token balances.
  final BigInt? balanceSlot;

  /// Storage slot for the token's allowance mapping.
  ///
  /// Used for state overrides during gas estimation. Use with
  /// [erc20AllowanceOverride] to simulate token allowances.
  final BigInt? allowanceSlot;

  @override
  String toString() =>
      'PimlicoTokenQuote(token: ${token.hex}, paymaster: ${paymaster.hex}, rate: $exchangeRate)';
}

/// Supported token information from pimlico_getSupportedTokens.
///
/// Contains metadata about ERC-20 tokens that can be used for
/// gas payment on a specific chain.
///
/// Example:
/// ```dart
/// final tokens = await pimlico.getSupportedTokens();
/// for (final token in tokens) {
///   print('${token.name} (${token.symbol}): ${token.token.checksummed}');
/// }
/// ```
class PimlicoSupportedToken {
  const PimlicoSupportedToken({
    required this.token,
    required this.name,
    required this.symbol,
    required this.decimals,
  });

  factory PimlicoSupportedToken.fromJson(Map<String, dynamic> json) =>
      PimlicoSupportedToken(
        token: EthAddress(json['token'] as String),
        name: json['name'] as String,
        symbol: json['symbol'] as String,
        decimals: json['decimals'] as int,
      );

  /// The ERC-20 token contract address.
  final EthAddress token;

  /// Full human-readable name of the token (e.g., "Dai Stablecoin", "USD Coin").
  final String name;

  /// Token symbol (e.g., "USDC", "USDT", "DAI").
  final String symbol;

  /// Token decimals (e.g., 6 for USDC, 18 for DAI).
  final int decimals;

  @override
  String toString() => 'PimlicoSupportedToken($name ($symbol), ${token.hex})';
}

/// Sponsorship policy metadata from Pimlico.
///
/// Contains information about a validated sponsorship policy,
/// including the policy author and description.
class PimlicoSponsorshipPolicyData {
  const PimlicoSponsorshipPolicyData({
    required this.name,
    required this.author,
    this.icon,
    this.description,
  });

  factory PimlicoSponsorshipPolicyData.fromJson(Map<String, dynamic> json) =>
      PimlicoSponsorshipPolicyData(
        name: json['name'] as String,
        author: json['author'] as String,
        icon: json['icon'] as String?,
        description: json['description'] as String?,
      );

  /// Human-readable name of the sponsorship policy.
  final String name;

  /// Author or organization that created the policy.
  final String author;

  /// Optional icon URL for the policy.
  final String? icon;

  /// Optional description of the policy's purpose.
  final String? description;

  @override
  String toString() =>
      'PimlicoSponsorshipPolicyData(name: $name, author: $author)';
}

/// Result of validating a sponsorship policy.
///
/// Links a policy ID to its metadata after validation.
class PimlicoSponsorshipPolicy {
  const PimlicoSponsorshipPolicy({
    required this.sponsorshipPolicyId,
    required this.data,
  });

  factory PimlicoSponsorshipPolicy.fromJson(Map<String, dynamic> json) =>
      PimlicoSponsorshipPolicy(
        sponsorshipPolicyId: json['sponsorshipPolicyId'] as String,
        data: PimlicoSponsorshipPolicyData.fromJson(
          json['data'] as Map<String, dynamic>,
        ),
      );

  /// The unique identifier for this sponsorship policy.
  final String sponsorshipPolicyId;

  /// Metadata about the sponsorship policy.
  final PimlicoSponsorshipPolicyData data;

  @override
  String toString() => 'PimlicoSponsorshipPolicy($sponsorshipPolicyId)';
}

/// ERC-20 paymaster cost estimate from Pimlico.
///
/// Contains the estimated cost to pay for gas using a specific
/// ERC-20 token. Both token amount and USD equivalent are provided.
///
/// Example:
/// ```dart
/// final cost = await pimlico.estimateErc20PaymasterCost(
///   userOperation: userOp,
///   token: usdcAddress,
/// );
/// print('Cost: ${cost.costInToken} tokens (~\$${cost.costInUsd / 1e8})');
/// ```
class PimlicoErc20PaymasterCost {
  const PimlicoErc20PaymasterCost({
    required this.costInToken,
    required this.costInUsd,
  });

  factory PimlicoErc20PaymasterCost.fromJson(Map<String, dynamic> json) =>
      PimlicoErc20PaymasterCost(
        costInToken: parseBigInt(json['costInToken']),
        costInUsd: parseBigInt(json['costInUsd']),
      );

  /// Cost in token units (with token's decimal precision).
  ///
  /// For USDC (6 decimals): 1000000 = 1 USDC
  /// For DAI (18 decimals): 1000000000000000000 = 1 DAI
  final BigInt costInToken;

  /// Cost in USD with 8 decimals precision.
  ///
  /// Divide by 10^8 to get human-readable USD amount.
  /// Example: 150000000 = $1.50
  final BigInt costInUsd;

  @override
  String toString() =>
      'PimlicoErc20PaymasterCost(token: $costInToken, usd: $costInUsd)';
}

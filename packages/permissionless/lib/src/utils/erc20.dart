import 'package:web3dart/web3dart.dart';

import '../types/address.dart';
import '../types/hex.dart';
import '../types/user_operation.dart';
import 'encoding.dart';

/// ERC-20 function selectors for common operations.
///
/// These are the first 4 bytes of the keccak256 hash of the function signature.
class Erc20Selectors {
  Erc20Selectors._();

  /// approve(address spender, uint256 amount)
  static final String approve = AbiEncoder.functionSelector(
    'approve(address,uint256)',
  );

  /// allowance(address owner, address spender)
  static final String allowance = AbiEncoder.functionSelector(
    'allowance(address,address)',
  );

  /// balanceOf(address account)
  static final String balanceOf = AbiEncoder.functionSelector(
    'balanceOf(address)',
  );

  /// transfer(address to, uint256 amount)
  static final String transfer = AbiEncoder.functionSelector(
    'transfer(address,uint256)',
  );

  /// transferFrom(address from, address to, uint256 amount)
  static final String transferFrom = AbiEncoder.functionSelector(
    'transferFrom(address,address,uint256)',
  );
}

/// Maximum uint256 value for unlimited token approvals.
///
/// Using max uint256 for approvals means users don't need to re-approve
/// for each transaction. However, this is a security trade-off: if the
/// spender contract is compromised, all tokens could be at risk.
final BigInt maxUint256 = (BigInt.one << 256) - BigInt.one;

/// Encodes an ERC-20 approve(spender, amount) call.
///
/// Returns a [Call] that can be included in a batch transaction to
/// approve a spender (like a paymaster) to transfer tokens.
///
/// Example:
/// ```dart
/// // Approve paymaster to spend USDC
/// final approveCall = encodeErc20Approve(
///   token: usdcAddress,
///   spender: paymasterAddress,
///   amount: maxUint256, // Unlimited approval
/// );
///
/// // Include in batch with other calls
/// final calls = [approveCall, transferCall];
/// ```
Call encodeErc20Approve({
  required EthereumAddress token,
  required EthereumAddress spender,
  required BigInt amount,
}) {
  final callData = Hex.concat([
    Erc20Selectors.approve,
    AbiEncoder.encodeAddress(spender),
    AbiEncoder.encodeUint256(amount),
  ]);

  return Call(
    to: token,
    data: callData,
  );
}

/// Encodes an ERC-20 transfer(to, amount) call.
///
/// Returns a [Call] that can be included in a transaction to transfer
/// tokens from the smart account to another address.
///
/// Example:
/// ```dart
/// final transferCall = encodeErc20Transfer(
///   token: usdcAddress,
///   to: recipientAddress,
///   amount: BigInt.from(1000000), // 1 USDC (6 decimals)
/// );
/// ```
Call encodeErc20Transfer({
  required EthereumAddress token,
  required EthereumAddress to,
  required BigInt amount,
}) {
  final callData = Hex.concat([
    Erc20Selectors.transfer,
    AbiEncoder.encodeAddress(to),
    AbiEncoder.encodeUint256(amount),
  ]);

  return Call(
    to: token,
    data: callData,
  );
}

/// Encodes an ERC-20 allowance(owner, spender) call for eth_call.
///
/// Use this with [PublicClient.call] to check how much a spender
/// is allowed to transfer on behalf of an owner.
///
/// Example:
/// ```dart
/// final callData = encodeErc20AllowanceCall(
///   owner: accountAddress,
///   spender: paymasterAddress,
/// );
///
/// final result = await publicClient.call(Call(
///   to: usdcAddress,
///   data: callData,
/// ));
///
/// final allowance = decodeUint256Result(result);
/// ```
String encodeErc20AllowanceCall({
  required EthereumAddress owner,
  required EthereumAddress spender,
}) =>
    Hex.concat([
      Erc20Selectors.allowance,
      AbiEncoder.encodeAddress(owner),
      AbiEncoder.encodeAddress(spender),
    ]);

/// Encodes an ERC-20 balanceOf(account) call for eth_call.
///
/// Use this with [PublicClient.call] to check the token balance
/// of an account.
///
/// Example:
/// ```dart
/// final callData = encodeErc20BalanceOfCall(account: myAddress);
/// final result = await publicClient.call(Call(
///   to: usdcAddress,
///   data: callData,
/// ));
/// final balance = decodeUint256Result(result);
/// ```
String encodeErc20BalanceOfCall({
  required EthereumAddress account,
}) =>
    Hex.concat([
      Erc20Selectors.balanceOf,
      AbiEncoder.encodeAddress(account),
    ]);

/// Decodes a uint256 result from an eth_call response.
///
/// Handles both empty responses (returns zero) and padded hex strings.
///
/// Example:
/// ```dart
/// final result = '0x0000000000000000000000000000000000000000000000000000000000000064';
/// final value = decodeUint256Result(result); // BigInt.from(100)
/// ```
BigInt decodeUint256Result(String hexResult) {
  if (hexResult == '0x' || hexResult.isEmpty) {
    return BigInt.zero;
  }

  // Remove 0x prefix if present
  final hex = Hex.strip0x(hexResult);
  if (hex.isEmpty) {
    return BigInt.zero;
  }

  return BigInt.parse(hex, radix: 16);
}

// ============================================================================
// State Override Types and Utilities
// ============================================================================

/// A single storage slot override.
///
/// Used in [StateOverride] to modify storage values during `eth_call` or
/// `eth_estimateUserOperationGas` simulations.
class StateDiff {
  /// Creates a storage slot override.
  ///
  /// - [slot]: The storage slot to override (32-byte hex string)
  /// - [value]: The value to set at this slot (32-byte hex string)
  const StateDiff({
    required this.slot,
    required this.value,
  });

  /// The storage slot (32-byte hex string).
  final String slot;

  /// The value to set at this slot (32-byte hex string).
  final String value;

  /// Converts to JSON for RPC calls.
  Map<String, String> toJson() => {slot: value};
}

/// State override for a single address.
///
/// Allows overriding balance, nonce, code, and storage during simulation.
/// Used with `eth_call` and `eth_estimateUserOperationGas` to test
/// scenarios without modifying on-chain state.
///
/// Example:
/// ```dart
/// final override = StateOverride(
///   address: tokenAddress,
///   stateDiff: [
///     StateDiff(slot: balanceSlot, value: newBalanceHex),
///   ],
/// );
/// ```
class StateOverride {
  /// Creates a state override for simulation.
  ///
  /// - [address]: The address to override state for
  /// - [balance]: Override the account's ETH balance
  /// - [nonce]: Override the account's nonce
  /// - [code]: Override the contract bytecode
  /// - [stateDiff]: Override specific storage slots
  const StateOverride({
    required this.address,
    this.balance,
    this.nonce,
    this.code,
    this.stateDiff,
  });

  /// The address to override.
  final EthereumAddress address;

  /// Override the account balance (in wei).
  final BigInt? balance;

  /// Override the account nonce.
  final BigInt? nonce;

  /// Override the contract code.
  final String? code;

  /// Override specific storage slots.
  final List<StateDiff>? stateDiff;

  /// Converts to JSON for RPC calls.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (balance != null) {
      json['balance'] = '0x${balance!.toRadixString(16)}';
    }
    if (nonce != null) {
      json['nonce'] = '0x${nonce!.toRadixString(16)}';
    }
    if (code != null) {
      json['code'] = code;
    }
    if (stateDiff != null && stateDiff!.isNotEmpty) {
      final slots = <String, String>{};
      for (final diff in stateDiff!) {
        slots[diff.slot] = diff.value;
      }
      json['stateDiff'] = slots;
    }

    return json;
  }
}

/// Converts a list of [StateOverride]s to the JSON format expected by RPC calls.
///
/// The format is: `{ address: { balance?, nonce?, code?, stateDiff? } }`
Map<String, dynamic> stateOverridesToJson(List<StateOverride> overrides) {
  final result = <String, dynamic>{};
  for (final override in overrides) {
    result[override.address.hex] = override.toJson();
  }
  return result;
}

/// Maximum uint256 value for state override amounts.
///
/// Useful for simulating unlimited token balances or allowances.
final BigInt _maxOverrideAmount = BigInt.parse(
  '7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
  radix: 16,
);

/// Default large balance for state override simulations.
final BigInt _defaultOverrideBalance = BigInt.parse(
  '100000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
  radix: 16,
);

/// Creates a state override to simulate an ERC-20 allowance.
///
/// This is useful for gas estimation with ERC-20 paymasters, where you need
/// to simulate having sufficient token allowance without actually approving
/// on-chain.
///
/// **Important:** The [slot] parameter is the storage slot index where the
/// token stores its `allowances` mapping. Common values:
/// - Standard ERC-20: typically slot 1 or 2
/// - OpenZeppelin ERC-20: typically slot 1
/// - USDC: slot 10
/// - USDT: slot 2
///
/// You can find the slot by checking the token's source code or using
/// storage layout tools.
///
/// Example:
/// ```dart
/// // Override USDC allowance for gas estimation
/// final override = erc20AllowanceOverride(
///   token: usdcAddress,
///   owner: accountAddress,
///   spender: paymasterAddress,
///   slot: BigInt.from(10), // USDC allowance slot
/// );
///
/// final gasEstimate = await bundler.estimateUserOperationGas(
///   userOp,
///   stateOverride: stateOverridesToJson(override),
/// );
/// ```
List<StateOverride> erc20AllowanceOverride({
  required EthereumAddress token,
  required EthereumAddress owner,
  required EthereumAddress spender,
  required BigInt slot,
  BigInt? amount,
}) {
  final effectiveAmount = amount ?? _maxOverrideAmount;

  // Calculate the storage slot for allowance[owner][spender]
  // This is: keccak256(spender . keccak256(owner . slot))
  // where '.' is concatenation

  // First: keccak256(abi.encode(owner, slot))
  final ownerSlotData = Hex.decode(
    Hex.concat([
      AbiEncoder.encodeAddress(owner),
      AbiEncoder.encodeUint256(slot),
    ]),
  );
  final innerHash = keccak256(ownerSlotData);

  // Then: keccak256(abi.encode(spender, innerHash))
  final spenderInnerData = Hex.decode(
    Hex.concat([
      AbiEncoder.encodeAddress(spender),
      Hex.fromBytes(innerHash),
    ]),
  );
  final storageSlot = keccak256(spenderInnerData);

  return [
    StateOverride(
      address: token,
      stateDiff: [
        StateDiff(
          slot: Hex.fromBytes(storageSlot),
          value: Hex.fromBigInt(effectiveAmount, byteLength: 32),
        ),
      ],
    ),
  ];
}

/// Creates a state override to simulate an ERC-20 balance.
///
/// This is useful for gas estimation and testing scenarios where you need
/// to simulate having a certain token balance without actually owning tokens.
///
/// **Important:** The [slot] parameter is the storage slot index where the
/// token stores its `balances` mapping. Common values:
/// - Standard ERC-20: typically slot 0 or 1
/// - OpenZeppelin ERC-20: typically slot 0
/// - USDC: slot 9
/// - USDT: slot 2
///
/// Example:
/// ```dart
/// // Override USDC balance for testing
/// final override = erc20BalanceOverride(
///   token: usdcAddress,
///   owner: accountAddress,
///   slot: BigInt.from(9), // USDC balance slot
///   balance: BigInt.from(1000000000), // 1000 USDC
/// );
///
/// final result = await publicClient.call(
///   Call(to: usdcAddress, data: encodeErc20BalanceOfCall(account: accountAddress)),
///   stateOverride: stateOverridesToJson(override),
/// );
/// ```
List<StateOverride> erc20BalanceOverride({
  required EthereumAddress token,
  required EthereumAddress owner,
  required BigInt slot,
  BigInt? balance,
}) {
  final effectiveBalance = balance ?? _defaultOverrideBalance;

  // Calculate the storage slot for balances[owner]
  // This is: keccak256(abi.encode(owner, slot))
  final ownerSlotData = Hex.decode(
    Hex.concat([
      AbiEncoder.encodeAddress(owner),
      AbiEncoder.encodeUint256(slot),
    ]),
  );
  final storageSlot = keccak256(ownerSlotData);

  return [
    StateOverride(
      address: token,
      stateDiff: [
        StateDiff(
          slot: Hex.fromBytes(storageSlot),
          value: Hex.fromBigInt(effectiveBalance, byteLength: 32),
        ),
      ],
    ),
  ];
}

/// Merges multiple state overrides for the same address.
///
/// If multiple overrides target the same address, their state diffs are
/// combined. Later values override earlier ones for the same slot.
///
/// Example:
/// ```dart
/// final balanceOverride = erc20BalanceOverride(...);
/// final allowanceOverride = erc20AllowanceOverride(...);
///
/// // Combine for a single gas estimation call
/// final merged = mergeStateOverrides([...balanceOverride, ...allowanceOverride]);
/// ```
List<StateOverride> mergeStateOverrides(List<StateOverride> overrides) {
  final byAddress = <String, List<StateOverride>>{};

  for (final override in overrides) {
    final key = override.address.hex.toLowerCase();
    byAddress.putIfAbsent(key, () => []).add(override);
  }

  return byAddress.entries.map((entry) {
    final addressOverrides = entry.value;
    if (addressOverrides.length == 1) {
      return addressOverrides.first;
    }

    // Merge all overrides for this address
    BigInt? balance;
    BigInt? nonce;
    String? code;
    final stateDiffs = <String, StateDiff>{};

    for (final o in addressOverrides) {
      if (o.balance != null) balance = o.balance;
      if (o.nonce != null) nonce = o.nonce;
      if (o.code != null) code = o.code;
      if (o.stateDiff != null) {
        for (final diff in o.stateDiff!) {
          stateDiffs[diff.slot] = diff;
        }
      }
    }

    return StateOverride(
      address: addressOverrides.first.address,
      balance: balance,
      nonce: nonce,
      code: code,
      stateDiff: stateDiffs.values.toList(),
    );
  }).toList();
}

/// Creates combined balance and allowance state overrides for ERC-20 paymaster.
///
/// This is a convenience function that creates both balance and allowance
/// overrides in a single call, useful for ERC-20 paymaster gas estimation
/// where both sufficient balance and allowance are required.
///
/// **Parameters:**
/// - [token] - The ERC-20 token contract address
/// - [owner] - The account that owns the tokens
/// - [spender] - The account allowed to spend (typically the paymaster)
/// - [balanceSlot] - Storage slot index for the balances mapping
/// - [allowanceSlot] - Storage slot index for the allowances mapping
/// - [balance] - Balance to simulate (defaults to a very large value)
/// - [allowance] - Allowance to simulate (defaults to max int256)
///
/// Example:
/// ```dart
/// // Override both balance and allowance for USDC paymaster estimation
/// final override = erc20PaymasterOverride(
///   token: usdcAddress,
///   owner: accountAddress,
///   spender: paymasterAddress,
///   balanceSlot: Erc20StorageSlots.usdcBalance,
///   allowanceSlot: Erc20StorageSlots.usdcAllowance,
/// );
///
/// final gasEstimate = await bundler.estimateUserOperationGas(
///   userOp,
///   stateOverride: stateOverridesToJson(override),
/// );
/// ```
List<StateOverride> erc20PaymasterOverride({
  required EthereumAddress token,
  required EthereumAddress owner,
  required EthereumAddress spender,
  required BigInt balanceSlot,
  required BigInt allowanceSlot,
  BigInt? balance,
  BigInt? allowance,
}) {
  final balanceOverride = erc20BalanceOverride(
    token: token,
    owner: owner,
    slot: balanceSlot,
    balance: balance,
  );

  final allowanceOverride = erc20AllowanceOverride(
    token: token,
    owner: owner,
    spender: spender,
    slot: allowanceSlot,
    amount: allowance,
  );

  return mergeStateOverrides([...balanceOverride, ...allowanceOverride]);
}

/// Common ERC-20 token storage slot indices.
///
/// These are the most common slot indices for popular tokens.
/// Always verify the slot for your specific token contract.
///
/// Example:
/// ```dart
/// // Use USDC balance slot for state override
/// final override = erc20BalanceOverride(
///   token: usdcAddress,
///   owner: accountAddress,
///   slot: Erc20StorageSlots.usdcBalance,
/// );
/// ```
class Erc20StorageSlots {
  Erc20StorageSlots._();

  // Balance slots
  /// OpenZeppelin ERC-20 balance slot (slot 0).
  static final BigInt openzeppelinBalance = BigInt.zero;

  /// USDC balance slot (slot 9).
  static final BigInt usdcBalance = BigInt.from(9);

  /// USDT balance slot (slot 2).
  static final BigInt usdtBalance = BigInt.two;

  /// DAI balance slot (slot 2).
  static final BigInt daiBalance = BigInt.two;

  // Allowance slots
  /// OpenZeppelin ERC-20 allowance slot (slot 1).
  static final BigInt openzeppelinAllowance = BigInt.one;

  /// USDC allowance slot (slot 10).
  static final BigInt usdcAllowance = BigInt.from(10);

  /// USDT allowance slot (slot 4).
  static final BigInt usdtAllowance = BigInt.from(4);

  /// DAI allowance slot (slot 3).
  static final BigInt daiAllowance = BigInt.from(3);
}

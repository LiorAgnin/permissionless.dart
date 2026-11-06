import '../types/address.dart';

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
///
/// Overrides that target the same address are merged first
/// ([mergeStateOverrides]); a JSON object can hold only one entry per address.
Map<String, dynamic> stateOverridesToJson(List<StateOverride> overrides) => {
      for (final override in mergeStateOverrides(overrides))
        override.address.hex: override.toJson(),
    };

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
    final key = override.address.hex;
    byAddress.putIfAbsent(key, () => []).add(override);
  }

  return byAddress.entries.map((entry) {
    final addressOverrides = entry.value;
    if (addressOverrides.length == 1) {
      return addressOverrides.first;
    }

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

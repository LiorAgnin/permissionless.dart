/// Utilities for converting between Ethereum gas and value units.
///
/// Ethereum uses wei as the base unit (1 ETH = 10^18 wei).
/// Gas prices are commonly expressed in gwei (1 gwei = 10^9 wei).
library;

/// Constants for unit conversion.
class EthUnits {
  EthUnits._();

  /// Wei per gwei (10^9).
  static final BigInt weiPerGwei = BigInt.from(1000000000);

  /// Wei per ether (10^18).
  static final BigInt weiPerEther = BigInt.parse('1000000000000000000');

  /// Gwei per ether (10^9).
  static final BigInt gweiPerEther = BigInt.from(1000000000);
}

/// Gas and value unit conversion utilities.
///
/// Example:
/// ```dart
/// // Convert 50 gwei to wei
/// final maxFeePerGas = GasUnits.gweiToWei(50);
///
/// // Convert wei to ether for display
/// final costInEth = GasUnits.weiToEther(gasCost);
/// print('Cost: $costInEth ETH');
///
/// // Parse from string
/// final fee = GasUnits.parse('1.5 gwei');
/// ```
class GasUnits {
  GasUnits._();

  /// Converts gwei to wei.
  ///
  /// Example: `gweiToWei(50)` returns 50 * 10^9 wei
  ///
  /// Converts the shortest decimal form of [gwei] (`0.1` is exactly
  /// 10^8 wei); digits below one wei round half up.
  static BigInt gweiToWei(num gwei) => _scaleDecimal(_numToDecimal(gwei), 9);

  /// Converts wei to gwei.
  ///
  /// Example: `weiToGwei(BigInt.from(50000000000))` returns 50.0
  static double weiToGwei(BigInt wei) => wei / EthUnits.weiPerGwei;

  /// Converts ether to wei.
  ///
  /// Example: `etherToWei(1.5)` returns 1.5 * 10^18 wei
  ///
  /// Converts the shortest decimal form of [ether] (`0.1` is exactly
  /// 10^17 wei); digits below one wei round half up.
  static BigInt etherToWei(num ether) =>
      _scaleDecimal(_numToDecimal(ether), 18);

  /// Converts wei to ether.
  ///
  /// Example: `weiToEther(BigInt.parse('1500000000000000000'))` returns 1.5
  static double weiToEther(BigInt wei) => wei / EthUnits.weiPerEther;

  /// Converts gwei to ether.
  static double gweiToEther(num gwei) =>
      gwei / EthUnits.gweiPerEther.toDouble();

  /// Converts ether to gwei.
  static double etherToGwei(num ether) =>
      ether * EthUnits.gweiPerEther.toDouble();

  /// Parses a gas/value string with unit suffix.
  ///
  /// Supported formats:
  /// - "50 gwei", "50gwei", "50 Gwei"
  /// - "1.5 eth", "1.5eth", "1.5 ether", "1.5 ETH"
  /// - "1000000000" (wei, no suffix)
  ///
  /// Returns the value in wei, computed exactly from the decimal digits.
  /// Digits below one wei round half up, as viem `parseUnits` does.
  ///
  /// Example:
  /// ```dart
  /// GasUnits.parse('50 gwei');  // 50000000000 wei
  /// GasUnits.parse('1.5 eth');  // 1500000000000000000 wei
  /// GasUnits.parse('1000');     // 1000 wei
  /// ```
  static BigInt parse(String value) {
    final match = RegExp(r'^([\d.]+)\s*(gwei|eth|ether|wei)?$')
        .firstMatch(value.trim().toLowerCase());
    if (match == null) {
      throw FormatException('Invalid gas unit format: $value');
    }
    final decimals = switch (match.group(2)) {
      'gwei' => 9,
      'eth' || 'ether' => 18,
      _ => 0,
    };
    return _scaleDecimal(match.group(1)!, decimals);
  }

  /// Formats a wei value as a human-readable string.
  ///
  /// Automatically chooses the best unit (wei, gwei, or ether) and rounds
  /// the exact value half up to [decimals] places.
  ///
  /// Example:
  /// ```dart
  /// GasUnits.format(BigInt.from(50000000000));  // "50 gwei"
  /// GasUnits.format(BigInt.parse('1500000000000000000'));  // "1.5 ETH"
  /// ```
  static String format(BigInt wei, {int decimals = 4}) {
    if (wei >= EthUnits.weiPerEther) {
      return '${_formatUnits(wei, 18, decimals)} ETH';
    } else if (wei >= EthUnits.weiPerGwei) {
      return '${_formatUnits(wei, 9, decimals)} gwei';
    } else {
      return '$wei wei';
    }
  }

  static final _decimalNumber =
      RegExp(r'^(-?)(\d*)(?:\.(\d*))?(?:e([+-]?\d+))?$', caseSensitive: false);

  /// Dart prints the shortest decimal that round-trips, so `0.1` becomes
  /// `'0.1'` rather than its binary expansion.
  static String _numToDecimal(num value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    return value.toString();
  }

  /// [number] * 10^[decimals], with digits below 1 rounded half up (viem
  /// `parseUnits` rounding).
  static BigInt _scaleDecimal(String number, int decimals) {
    final match = _decimalNumber.firstMatch(number);
    final integer = match?.group(2) ?? '';
    final fraction = match?.group(3) ?? '';
    if (match == null || (integer.isEmpty && fraction.isEmpty)) {
      throw FormatException('Invalid number: $number');
    }
    final shift = decimals + int.parse(match.group(4) ?? '0') - fraction.length;
    final digits = BigInt.parse('0$integer$fraction');
    BigInt scaled;
    if (shift >= 0) {
      scaled = digits * BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      scaled = digits ~/ divisor;
      if (digits.remainder(divisor) * BigInt.two >= divisor) {
        scaled += BigInt.one;
      }
    }
    return match.group(1) == '-' ? -scaled : scaled;
  }

  /// Positive [value] / 10^[unitDecimals] rounded half up to [decimals]
  /// places, trailing zeros dropped.
  static String _formatUnits(BigInt value, int unitDecimals, int decimals) {
    RangeError.checkNotNegative(decimals, 'decimals');
    final kept = decimals < unitDecimals ? decimals : unitDecimals;
    final divisor = BigInt.from(10).pow(unitDecimals - kept);
    var scaled = value ~/ divisor;
    if (value.remainder(divisor) * BigInt.two >= divisor) {
      scaled += BigInt.one;
    }
    final digits = scaled.toString().padLeft(kept + 1, '0');
    final integer = digits.substring(0, digits.length - kept);
    final fraction =
        digits.substring(digits.length - kept).replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? integer : '$integer.$fraction';
  }
}

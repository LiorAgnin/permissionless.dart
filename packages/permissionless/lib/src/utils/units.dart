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
  static BigInt gweiToWei(num gwei) {
    // Handle decimal gwei values by scaling up
    final scaledGwei = (gwei * 1e9).round();
    return BigInt.from(scaledGwei);
  }

  /// Converts wei to gwei.
  ///
  /// Example: `weiToGwei(BigInt.from(50000000000))` returns 50.0
  static double weiToGwei(BigInt wei) => wei / EthUnits.weiPerGwei;

  /// Converts ether to wei.
  ///
  /// Example: `etherToWei(1.5)` returns 1.5 * 10^18 wei
  static BigInt etherToWei(num ether) {
    // Handle decimal ether values by scaling up
    final scaledEther = (ether * 1e18).round();
    return BigInt.from(scaledEther);
  }

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
  /// Returns the value in wei.
  ///
  /// Example:
  /// ```dart
  /// GasUnits.parse('50 gwei');  // 50000000000 wei
  /// GasUnits.parse('1.5 eth');  // 1500000000000000000 wei
  /// GasUnits.parse('1000');     // 1000 wei
  /// ```
  static BigInt parse(String value) {
    final trimmed = value.trim().toLowerCase();

    // Try to extract number and unit
    final match =
        RegExp(r'^([\d.]+)\s*(gwei|eth|ether|wei)?$').firstMatch(trimmed);

    if (match == null) {
      throw FormatException('Invalid gas unit format: $value');
    }

    final numStr = match.group(1)!;
    final unit = match.group(2) ?? 'wei';

    final num = double.tryParse(numStr);
    if (num == null) {
      throw FormatException('Invalid number: $numStr');
    }

    return switch (unit) {
      'gwei' => gweiToWei(num),
      'eth' || 'ether' => etherToWei(num),
      'wei' || '' => BigInt.from(num),
      _ => throw FormatException('Unknown unit: $unit'),
    };
  }

  /// Formats a wei value as a human-readable string.
  ///
  /// Automatically chooses the best unit (wei, gwei, or ether).
  ///
  /// Example:
  /// ```dart
  /// GasUnits.format(BigInt.from(50000000000));  // "50 gwei"
  /// GasUnits.format(BigInt.parse('1500000000000000000'));  // "1.5 ETH"
  /// ```
  static String format(BigInt wei, {int decimals = 4}) {
    if (wei >= EthUnits.weiPerEther) {
      final eth = weiToEther(wei);
      return '${_formatDecimal(eth, decimals)} ETH';
    } else if (wei >= EthUnits.weiPerGwei) {
      final gwei = weiToGwei(wei);
      return '${_formatDecimal(gwei, decimals)} gwei';
    } else {
      return '$wei wei';
    }
  }

  /// Formats a decimal number with specified precision.
  static String _formatDecimal(double value, int decimals) {
    final str = value.toStringAsFixed(decimals);
    // Remove trailing zeros after decimal point
    if (str.contains('.')) {
      var result = str.replaceAll(RegExp(r'0+$'), '');
      if (result.endsWith('.')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    }
    return str;
  }
}

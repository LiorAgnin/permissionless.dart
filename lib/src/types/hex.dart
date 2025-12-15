import 'dart:typed_data';
import 'package:convert/convert.dart';

/// Utility class for handling hexadecimal strings in Ethereum.
///
/// All hex strings are expected to have '0x' prefix.
class Hex {
  Hex._();

  /// Converts bytes to a hex string with '0x' prefix.
  static String encode(List<int> bytes) => '0x${hex.encode(bytes)}';

  /// Converts bytes to a hex string with '0x' prefix.
  static String fromBytes(Uint8List bytes) => '0x${hex.encode(bytes)}';

  /// Converts a hex string (with or without '0x' prefix) to bytes.
  static Uint8List decode(String hexString) {
    final cleanHex = strip0x(hexString);
    // Pad with leading zero if odd length
    final paddedHex = cleanHex.length.isOdd ? '0$cleanHex' : cleanHex;
    return Uint8List.fromList(hex.decode(paddedHex));
  }

  /// Removes '0x' prefix if present.
  static String strip0x(String hexString) {
    if (hexString.startsWith('0x') || hexString.startsWith('0X')) {
      return hexString.substring(2);
    }
    return hexString;
  }

  /// Ensures hex string has '0x' prefix.
  static String add0x(String hexString) {
    if (hexString.startsWith('0x') || hexString.startsWith('0X')) {
      return hexString;
    }
    return '0x$hexString';
  }

  /// Pads a hex string to a specific byte length (left-padded with zeros).
  static String padLeft(String hexString, int byteLength) {
    final clean = strip0x(hexString);
    final targetLength = byteLength * 2;
    if (clean.length >= targetLength) {
      return '0x$clean';
    }
    return '0x${clean.padLeft(targetLength, '0')}';
  }

  /// Pads a hex string to a specific byte length (right-padded with zeros).
  static String padRight(String hexString, int byteLength) {
    final clean = strip0x(hexString);
    final targetLength = byteLength * 2;
    if (clean.length >= targetLength) {
      return '0x$clean';
    }
    return '0x${clean.padRight(targetLength, '0')}';
  }

  /// Concatenates multiple hex strings.
  static String concat(List<String> hexStrings) {
    if (hexStrings.isEmpty) return '0x';
    final buffer = StringBuffer('0x');
    for (final s in hexStrings) {
      buffer.write(strip0x(s));
    }
    return buffer.toString();
  }

  /// Gets the byte length of a hex string.
  static int byteLength(String hexString) => strip0x(hexString).length ~/ 2;

  /// Slices a hex string from start to end byte indices.
  static String slice(String hexString, int start, [int? end]) {
    final clean = strip0x(hexString);
    final startChar = start * 2;
    final endChar = end != null ? end * 2 : clean.length;
    return '0x${clean.substring(startChar, endChar)}';
  }

  /// Converts a BigInt to a hex string with '0x' prefix.
  static String fromBigInt(BigInt value, {int? byteLength}) {
    var hexStr = value.toRadixString(16);
    if (byteLength != null) {
      hexStr = hexStr.padLeft(byteLength * 2, '0');
    }
    return '0x$hexStr';
  }

  /// Converts a hex string to BigInt.
  static BigInt toBigInt(String hexString) {
    final clean = strip0x(hexString);
    if (clean.isEmpty) return BigInt.zero;
    return BigInt.parse(clean, radix: 16);
  }

  /// Checks if a string is a valid hex string.
  static bool isValid(String hexString) {
    final clean = strip0x(hexString);
    if (clean.isEmpty) return true;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
  }

  /// Empty hex value.
  static const String empty = '0x';

  /// Zero bytes of various sizes.
  static const String zero32 =
      '0x0000000000000000000000000000000000000000000000000000000000000000';
  static const String zero20 = '0x0000000000000000000000000000000000000000';
}

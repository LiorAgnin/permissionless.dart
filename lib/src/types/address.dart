import 'dart:typed_data';
import 'package:wallet/wallet.dart';
import 'hex.dart';

// Re-export EthereumAddress from wallet package for convenience
export 'package:wallet/wallet.dart' show EthereumAddress;

/// Zero address constant.
final EthereumAddress zeroAddress =
    EthereumAddress.fromHex('0x0000000000000000000000000000000000000000');

/// Extension to add utility methods to EthereumAddress.
extension EthereumAddressExtension on EthereumAddress {
  /// Returns the address as a lowercase hex string with '0x' prefix.
  String get hex => with0x;

  /// Returns the address as a checksummed hex string (EIP-55).
  String get checksummed => eip55With0x;

  /// Returns the address as bytes.
  Uint8List get bytes => Uint8List.fromList(value);

  /// Checks if the address is the zero address.
  bool get isZero => with0x == zeroAddress.with0x;

  /// Converts to ABI-encoded format (32 bytes, left-padded).
  String toAbiEncoded() => Hex.padLeft(with0x, 32);
}

/// Checks if a string is a valid Ethereum address.
///
/// This is a convenience wrapper around [EthereumAddress.isEip55ValidEthereumAddress].
/// It validates the basic hex format and, for mixed-case addresses, verifies
/// the EIP-55 checksum.
bool isValidEthereumAddress(String address) =>
    EthereumAddress.isEip55ValidEthereumAddress(address);

/// Extension for converting strings to EthereumAddress.
extension StringToAddress on String {
  EthereumAddress toAddress() => EthereumAddress.fromHex(this);
}

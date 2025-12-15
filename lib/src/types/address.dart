import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'hex.dart';

/// Represents an Ethereum address (20 bytes).
///
/// Provides validation, checksumming, and comparison utilities.
class EthAddress implements Comparable<EthAddress> {
  /// Creates an EthAddress from a hex string.
  ///
  /// Throws [ArgumentError] if the address is invalid.
  EthAddress(String address) : _address = _normalize(address) {
    if (!isValidAddress(_address)) {
      throw ArgumentError('Invalid Ethereum address: $address');
    }
  }

  /// Creates an EthAddress without validation (use with caution).
  EthAddress.unsafe(this._address);

  final String _address;

  /// Zero address constant.
  static final EthAddress zero =
      EthAddress('0x0000000000000000000000000000000000000000');

  static String _normalize(String address) {
    final clean = Hex.strip0x(address).toLowerCase();
    return '0x$clean';
  }

  /// Returns the address as a lowercase hex string with '0x' prefix.
  String get hex => _address;

  /// Returns the address as a checksummed hex string (EIP-55).
  String get checksummed {
    final addr = Hex.strip0x(_address).toLowerCase();
    final hash =
        Hex.strip0x(Hex.encode(keccak256(Uint8List.fromList(addr.codeUnits))));

    final buffer = StringBuffer('0x');
    for (var i = 0; i < addr.length; i++) {
      final char = addr[i];
      final hashChar = int.parse(hash[i], radix: 16);
      if (hashChar >= 8) {
        buffer.write(char.toUpperCase());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Returns the address as bytes.
  Uint8List get bytes => Hex.decode(_address);

  /// Checks if a string is a valid Ethereum address.
  static bool isValidAddress(String address) {
    final clean = Hex.strip0x(address);
    if (clean.length != 40) return false;
    return RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(clean);
  }

  /// Checks if the address is the zero address.
  bool get isZero => _address == zero._address;

  /// Compares addresses for sorting (by numerical value).
  @override
  int compareTo(EthAddress other) =>
      Hex.toBigInt(_address).compareTo(Hex.toBigInt(other._address));

  @override
  bool operator ==(Object other) {
    if (other is EthAddress) {
      return _address == other._address;
    }
    if (other is String) {
      return _address == _normalize(other);
    }
    return false;
  }

  @override
  int get hashCode => _address.hashCode;

  @override
  String toString() => _address;

  /// Converts to ABI-encoded format (32 bytes, left-padded).
  String toAbiEncoded() => Hex.padLeft(_address, 32);
}

/// Extension for converting strings to EthAddress.
extension StringToAddress on String {
  EthAddress toAddress() => EthAddress(this);
}

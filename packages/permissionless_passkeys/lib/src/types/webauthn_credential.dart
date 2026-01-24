import 'dart:convert';
import 'dart:typed_data';

import 'package:web3_signers/web3_signers.dart';

/// Wrapper for WebAuthn/Passkey credentials used with smart accounts.
///
/// This provides a unified interface over [PassKeyPublicKey] from web3_signers,
/// extracting the key fields needed for ERC-4337 account initialization.
///
/// Example:
/// ```dart
/// // From newly registered passkey
/// final key = await signer.register('user@example.com', 'User');
/// final credential = WebAuthnCredential.fromPublicKey(key);
///
/// // Access public key coordinates for validator init
/// print('x: ${credential.x}');
/// print('y: ${credential.y}');
/// ```
class WebAuthnCredential {
  /// Creates a credential with the given parameters.
  const WebAuthnCredential({
    required this.id,
    required this.rawId,
    required this.x,
    required this.y,
    required this.raw,
  });

  /// Creates a credential from a [PassKeyPublicKey].
  ///
  /// Extracts the credential ID and P256 public key coordinates.
  factory WebAuthnCredential.fromPublicKey(PassKeyPublicKey key) {
    final rawId = Uint8List.fromList(key.credentialId);
    final id = base64Url.encode(rawId).replaceAll('=', '');
    return WebAuthnCredential(
      id: id,
      rawId: rawId,
      x: key.x.value,
      y: key.y.value,
      raw: key,
    );
  }

  /// Creates a credential from a [PassKeyPair] (deprecated alias).
  @Deprecated('Use fromPublicKey instead')
  factory WebAuthnCredential.fromPassKeyPair(PassKeyPublicKey key) {
    return WebAuthnCredential.fromPublicKey(key);
  }

  /// Deserializes a credential from JSON.
  ///
  /// Reconstructs the [PassKeyPublicKey] from stored values.
  factory WebAuthnCredential.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rawData = map['raw'] as Map<String, dynamic>;

    final key = PassKeyPublicKey(
      x: Uint256.fromHex(rawData['x'] as String),
      y: Uint256.fromHex(rawData['y'] as String),
      credentialId:
          base64Url.decode(_padBase64(rawData['credentialId'] as String)),
      userName: rawData['userName'] as String? ?? '',
      aaGuid: rawData['aaGuid'] as String? ?? '',
    );
    return WebAuthnCredential.fromPublicKey(key);
  }

  /// Pads a Base64 string to be a multiple of 4.
  static String _padBase64(String b64) {
    final padding = 4 - b64.length % 4;
    return padding < 4 ? '$b64${"=" * padding}' : b64;
  }

  /// Base64-encoded credential ID.
  ///
  /// Used for identifying the credential during authentication.
  final String id;

  /// Raw credential ID bytes.
  ///
  /// Used when building allowed credentials list for authentication.
  final Uint8List rawId;

  /// P256 public key X coordinate.
  ///
  /// Used for on-chain verification and account initialization.
  final BigInt x;

  /// P256 public key Y coordinate.
  ///
  /// Used for on-chain verification and account initialization.
  final BigInt y;

  /// The underlying [PassKeyPublicKey] from web3_signers.
  ///
  /// Contains public key data including credential ID, username and AAGUID.
  final PassKeyPublicKey raw;

  /// Hex-encoded public key (x || y, 64 bytes).
  ///
  /// Format used by some on-chain verifiers.
  String get publicKeyHex {
    final xBytes = _bigIntToBytes32(x);
    final yBytes = _bigIntToBytes32(y);
    return '0x${_bytesToHex(xBytes)}${_bytesToHex(yBytes)}';
  }

  /// Serializes the credential to JSON.
  ///
  /// Can be stored and later restored with [fromJson].
  String toJson() {
    return jsonEncode({
      'raw': {
        'x': '0x${x.toRadixString(16).padLeft(64, '0')}',
        'y': '0x${y.toRadixString(16).padLeft(64, '0')}',
        'credentialId': base64Url.encode(rawId).replaceAll('=', ''),
        'userName': raw.userName,
        'aaGuid': raw.aaGuid,
      },
    });
  }

  /// Converts a [BigInt] to a 32-byte array (left-padded).
  static Uint8List _bigIntToBytes32(BigInt value) {
    final bytes = _bigIntToBytes(value);
    if (bytes.length >= 32) {
      return Uint8List.fromList(bytes.sublist(bytes.length - 32));
    }
    final padded = Uint8List(32);
    padded.setRange(32 - bytes.length, 32, bytes);
    return padded;
  }

  /// Converts a [BigInt] to bytes (big-endian).
  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList([0]);
    }
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Converts bytes to hex string (without 0x prefix).
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

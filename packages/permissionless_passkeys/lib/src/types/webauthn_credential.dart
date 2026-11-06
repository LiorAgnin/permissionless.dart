import 'dart:convert';
import 'dart:typed_data';

import 'package:permissionless/permissionless.dart' show Hex;
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
    return WebAuthnCredential(
      id: _base64UrlNoPadding(rawId),
      rawId: rawId,
      x: key.x.value,
      y: key.y.value,
      raw: key,
    );
  }

  /// Deprecated alias for [WebAuthnCredential.fromPublicKey].
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
      credentialId: base64Url.decode(
        base64Url.normalize(rawData['credentialId'] as String),
      ),
      userName: rawData['userName'] as String? ?? '',
      aaGuid: rawData['aaGuid'] as String? ?? '',
    );
    return WebAuthnCredential.fromPublicKey(key);
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
  /// Format used by some on-chain verifiers. Throws an [ArgumentError] if a
  /// coordinate does not fit in 32 bytes.
  String get publicKeyHex => Hex.concat([_uint256Hex(x), _uint256Hex(y)]);

  /// Serializes the credential to JSON.
  ///
  /// Can be stored and later restored with [fromJson].
  String toJson() {
    return jsonEncode({
      'raw': {
        'x': _uint256Hex(x),
        'y': _uint256Hex(y),
        'credentialId': _base64UrlNoPadding(rawId),
        'userName': raw.userName,
        'aaGuid': raw.aaGuid,
      },
    });
  }

  static String _uint256Hex(BigInt value) =>
      Hex.fromBigInt(value, byteLength: 32);

  static String _base64UrlNoPadding(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

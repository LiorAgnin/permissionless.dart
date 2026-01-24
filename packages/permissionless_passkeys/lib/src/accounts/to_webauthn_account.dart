import 'dart:convert';
import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:web3_signers/web3_signers.dart';

import '../types/webauthn_credential.dart';
import 'webauthn_account.dart';

/// Parameters for creating a WebAuthn account.
///
/// Matches viem's `ToWebAuthnAccountParameters` type.
class ToWebAuthnAccountParameters {
  /// Creates parameters for toWebAuthnAccount.
  const ToWebAuthnAccountParameters({
    required this.credential,
    this.rpId,
    this.getFn,
  });

  /// The WebAuthn credential containing public key coordinates.
  final WebAuthnCredential credential;

  /// Relying Party identifier (your domain).
  ///
  /// Must match the rpId used during credential registration.
  /// If not provided, defaults to the credential's original rpId.
  final String? rpId;

  /// Optional custom function for WebAuthn authentication.
  ///
  /// If provided, this function will be called instead of the default
  /// PassKeySigner authentication flow. Useful for custom WebAuthn
  /// implementations or testing.
  final Future<Signature> Function(Uint8List challenge)? getFn;
}

/// Creates a WebAuthn account from a credential.
///
/// This function matches viem's `toWebAuthnAccount` for API compatibility.
/// It creates an account that can sign messages using the device's
/// biometric authentication (Face ID, Touch ID, Windows Hello).
///
/// [params] - Configuration including credential and rpId.
///
/// Example:
/// ```dart
/// final account = toWebAuthnAccount(
///   ToWebAuthnAccountParameters(
///     credential: credential,
///     rpId: 'myapp.com',
///   ),
/// );
///
/// final signed = await account.sign(hash: userOpHash);
/// ```
WebAuthnAccount toWebAuthnAccount(ToWebAuthnAccountParameters params) {
  return _WebAuthnAccountImpl(
    credential: params.credential,
    rpId: params.rpId ?? '',
    getFn: params.getFn,
  );
}

/// Convenience function to create a WebAuthn account with named parameters.
///
/// This is the recommended way to create WebAuthn accounts in Dart,
/// using idiomatic named parameters instead of a parameters object.
///
/// Example:
/// ```dart
/// final account = createWebAuthnAccount(
///   credential: credential,
///   rpId: 'myapp.com',
/// );
///
/// print('Public Key: ${account.publicKey}');
///
/// final result = await account.sign(hash: '0x1234...');
/// print('Signature: ${result.signature}');
/// ```
WebAuthnAccount createWebAuthnAccount({
  required WebAuthnCredential credential,
  String? rpId,
  Future<Signature> Function(Uint8List challenge)? getFn,
}) {
  return toWebAuthnAccount(
    ToWebAuthnAccountParameters(
      credential: credential,
      rpId: rpId,
      getFn: getFn,
    ),
  );
}

/// Internal implementation of WebAuthnAccount.
class _WebAuthnAccountImpl extends WebAuthnAccount {
  _WebAuthnAccountImpl({
    required this.credential,
    required this.rpId,
    this.getFn,
  }) : _signer = rpId.isNotEmpty
            ? PassKeySigner.withConfig(
                PassKeyConfig(rpId: rpId, rpName: rpId),
                credential.raw,
              )
            : null;

  final WebAuthnCredential credential;
  final String rpId;
  final Future<Signature> Function(Uint8List challenge)? getFn;
  final PassKeySigner? _signer;

  // ============================================================================
  // WebAuthnAccount interface (passkeys-specific)
  // ============================================================================

  @override
  String get id => credential.id;

  @override
  String get publicKey => credential.publicKeyHex;

  // ============================================================================
  // WebAuthnAccountOwner interface (from permissionless)
  // ============================================================================

  @override
  BigInt get x => credential.x;

  @override
  BigInt get y => credential.y;

  @override
  Uint8List get credentialId => credential.rawId;

  @override
  String get publicKeyHex => credential.publicKeyHex;

  @override
  Future<P256SignatureData> signP256(String hash) async {
    final hashBytes = _hexToBytes(hash);
    final signature = await _sign(hashBytes);

    return P256SignatureData(
      r: signature.r,
      s: signature.s,
      authenticatorData: signature.authData ?? Uint8List(0),
      clientDataJSON: signature.clientDataJson ?? '',
      challengeIndex: signature.getChallengeLocation(hashBytes) ?? 0,
      typeIndex: signature.getTypeLocation() ?? 0,
    );
  }

  // ============================================================================
  // WebAuthn signing methods
  // ============================================================================

  @override
  Future<WebAuthnSignReturnType> sign({required String hash}) async {
    final hashBytes = _hexToBytes(hash);
    final signature = await _sign(hashBytes);
    return _createReturnType(signature, hashBytes);
  }

  @override
  Future<WebAuthnSignReturnType> signMessage({required dynamic message}) async {
    // Hash the message according to EIP-191 personal sign
    final messageBytes = _messageToBytes(message);
    final prefixedMessage = _personalSignPrefix(messageBytes);
    final hash = _keccak256(prefixedMessage);
    return sign(hash: _bytesToHex(hash));
  }

  @override
  Future<WebAuthnSignReturnType> signTypedDataViem({
    required Map<String, dynamic> domain,
    required Map<String, List<Map<String, String>>> types,
    required String primaryType,
    required Map<String, dynamic> message,
  }) async {
    // EIP-712 typed data hashing would go here
    // For now, throw unimplemented as full EIP-712 requires more infrastructure
    throw UnimplementedError(
      'signTypedDataViem requires EIP-712 encoding infrastructure. '
      'Use sign() with a pre-computed EIP-712 hash instead.',
    );
  }

  // ============================================================================
  // Internal helpers
  // ============================================================================

  /// Signs a challenge using the configured method.
  Future<Signature> _sign(Uint8List challenge) async {
    if (getFn != null) {
      return getFn!(challenge);
    }

    if (_signer == null) {
      throw StateError(
        'Cannot sign: no rpId provided and no custom getFn configured. '
        'Provide rpId when creating the account or use a custom getFn.',
      );
    }

    return _signer.signAsync(challenge);
  }

  /// Creates the return type from a signature.
  WebAuthnSignReturnType _createReturnType(
      Signature signature, Uint8List hash) {
    // Build compact signature (r + s, 64 bytes)
    final rHex = signature.r.toRadixString(16).padLeft(64, '0');
    final sHex = signature.s.toRadixString(16).padLeft(64, '0');
    final compactSignature = '0x$rHex$sHex';

    // Extract metadata
    final metadata = WebAuthnSignMetadata(
      authenticatorData: signature.authData ?? Uint8List(0),
      clientDataJSON: signature.clientDataJson ?? '',
      challengeIndex: signature.getChallengeLocation(hash) ?? 0,
      typeIndex: signature.getTypeLocation() ?? 0,
    );

    return WebAuthnSignReturnType(
      signature: compactSignature,
      webauthn: metadata,
      raw: signature,
    );
  }

  /// Converts a hex string to bytes.
  Uint8List _hexToBytes(String hex) {
    final cleanHex = hex.startsWith('0x') ? hex.substring(2) : hex;
    final paddedHex = cleanHex.length.isOdd ? '0$cleanHex' : cleanHex;
    final result = Uint8List(paddedHex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(paddedHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Converts bytes to hex string with 0x prefix.
  String _bytesToHex(Uint8List bytes) {
    return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Converts a message to bytes.
  Uint8List _messageToBytes(dynamic message) {
    if (message is Uint8List) {
      return message;
    }
    if (message is List<int>) {
      return Uint8List.fromList(message);
    }
    if (message is String) {
      // Check if it's hex
      if (message.startsWith('0x')) {
        return _hexToBytes(message);
      }
      return Uint8List.fromList(utf8.encode(message));
    }
    throw ArgumentError('Message must be Uint8List, List<int>, or String');
  }

  /// Creates the EIP-191 personal sign prefix.
  Uint8List _personalSignPrefix(Uint8List message) {
    final prefix = '\x19Ethereum Signed Message:\n${message.length}';
    final prefixBytes = utf8.encode(prefix);
    return Uint8List.fromList([...prefixBytes, ...message]);
  }

  /// Placeholder for keccak256 hash.
  ///
  /// Note: In production, this should use a proper keccak256 implementation.
  /// The actual hash computation happens when signMessage is called with
  /// a pre-computed hash.
  Uint8List _keccak256(Uint8List data) {
    // This would need a keccak256 implementation
    // For now, we'll use the permissionless package's utils when integrated
    throw UnimplementedError(
      'signMessage requires keccak256 hashing. '
      'Use sign() with a pre-computed hash instead.',
    );
  }
}

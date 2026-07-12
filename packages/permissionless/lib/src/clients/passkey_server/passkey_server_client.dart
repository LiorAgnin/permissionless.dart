import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../types/hex.dart';
import '../bundler/rpc_client.dart';
import 'types.dart';

/// Client for a permissionless-compatible passkey server (`pks_*` RPC).
///
/// Ports permissionless.js `createPasskeyServerClient` / passkeyServer actions:
/// registration, authentication, and credential listing against a remote
/// WebAuthn ceremony server.
///
/// This lives in the core package (JS layout parity). Client-side passkey
/// creation and on-device signing remain in `permissionless_passkeys`.
///
/// Example:
/// ```dart
/// final client = createPasskeyServerClient(
///   url: 'https://passkeys.example.com',
/// );
///
/// final options = await client.startRegistration(
///   context: {'userName': 'alice@example.com'},
/// );
/// // ... create credential via platform WebAuthn / passkeys package ...
/// final result = await client.verifyRegistration(
///   credential: registrationCredential,
///   context: {'userName': 'alice@example.com'},
/// );
/// ```
class PasskeyServerClient {
  /// Creates a passkey server client with the given RPC client.
  ///
  /// Prefer [createPasskeyServerClient] for URL-based setup.
  PasskeyServerClient({
    required this.rpcClient,
  });

  /// The underlying JSON-RPC client.
  final JsonRpcClient rpcClient;

  /// Starts WebAuthn registration (`pks_startRegistration`).
  ///
  /// [context] is opaque server context (e.g. `{userName: ...}`), matching
  /// permissionless.js `StartRegistrationParameters.context`.
  ///
  /// Decodes base64 `challenge` and `user.id` into bytes, matching JS.
  Future<PasskeyRegistrationOptions> startRegistration({
    Map<String, dynamic>? context,
  }) async {
    final result = await rpcClient.call(
      'pks_startRegistration',
      [context],
    );

    if (result is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid response from server - expected object for pks_startRegistration',
      );
    }

    _validateRegistrationResponse(result);

    final userJson = result['user'] as Map<String, dynamic>;
    final authenticatorSelectionJson =
        result['authenticatorSelection'] as Map<String, dynamic>?;
    final extensionsJson = result['extensions'] as Map<String, dynamic>?;

    return PasskeyRegistrationOptions(
      rp: PasskeyRp.fromJson(result['rp'] as Map<String, dynamic>),
      user: PasskeyUser(
        id: _base64ToBytes(userJson['id'] as String),
        name: userJson['name'] as String,
        displayName: userJson['displayName'] as String,
      ),
      challenge: _base64ToBytes(result['challenge'] as String),
      attestation: result['attestation'] as String,
      timeout: result['timeout'] as int?,
      authenticatorSelection: authenticatorSelectionJson != null
          ? PasskeyAuthenticatorSelection.fromJson(authenticatorSelectionJson)
          : null,
      extensions: extensionsJson != null
          ? Map<String, dynamic>.from(extensionsJson)
          : null,
    );
  }

  /// Completes registration (`pks_verifyRegistration`).
  ///
  /// Encodes binary fields to base64 / base64url the same way as
  /// permissionless.js `verifyRegistration`.
  Future<PasskeyVerificationResult> verifyRegistration({
    required PasskeyRegistrationCredential credential,
    dynamic context,
  }) async {
    final response = credential.response;
    final params = <dynamic>[
      {
        'id': credential.id,
        'rawId': _base64UrlEncode(credential.rawId, pad: false),
        'response': {
          'clientDataJSON': _base64Encode(response.clientDataJSON),
          'attestationObject':
              _base64UrlEncode(response.attestationObject, pad: true),
          if (response.transports != null) 'transports': response.transports,
          if (response.publicKeyAlgorithm != null)
            'publicKeyAlgorithm': response.publicKeyAlgorithm,
          if (response.authenticatorData != null)
            'authenticatorData': _base64Encode(response.authenticatorData!),
          if (response.publicKeyType != null)
            'publicKeyType': response.publicKeyType,
        },
        'authenticatorAttachment': credential.authenticatorAttachment,
        'clientExtensionResults': credential.clientExtensionResults,
        'type': credential.type,
      },
      context,
    ];

    final result = await rpcClient.call('pks_verifyRegistration', params);
    return _parseVerificationResult(result);
  }

  /// Starts WebAuthn authentication (`pks_startAuthentication`).
  ///
  /// Decodes the server's base64 challenge and returns it as `0x` hex,
  /// matching permissionless.js `startAuthentication`.
  Future<PasskeyAuthenticationOptions> startAuthentication() async {
    final result = await rpcClient.call('pks_startAuthentication', []);

    if (result is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid response from server - expected object for pks_startAuthentication',
      );
    }

    final challengeB64 = result['challenge'] as String?;
    final rpId = result['rpId'] as String?;
    final uuid = result['uuid'] as String?;

    if (challengeB64 == null || rpId == null || uuid == null) {
      throw const FormatException(
        'Invalid response from server - missing challenge, rpId, or uuid',
      );
    }

    final challengeBytes = _base64ToBytes(challengeB64);

    return PasskeyAuthenticationOptions(
      challenge: Hex.fromBytes(challengeBytes),
      rpId: rpId,
      uuid: uuid,
      timeout: result['timeout'] as int?,
      userVerification: result['userVerification'] as String?,
    );
  }

  /// Completes authentication (`pks_verifyAuthentication`).
  ///
  /// [uuid] is the session id from [startAuthentication].
  /// Encodes binary fields as base64url (no pad) like permissionless.js.
  Future<PasskeyVerificationResult> verifyAuthentication({
    required PasskeyAuthenticationCredential credential,
    required String uuid,
  }) async {
    final response = credential.response;
    final params = <dynamic>[
      {
        'id': credential.id,
        'rawId': _base64UrlEncode(credential.rawId, pad: false),
        'authenticatorAttachment': credential.authenticatorAttachment,
        'response': {
          'clientDataJSON':
              _base64UrlEncode(response.clientDataJSON, pad: false),
          'authenticatorData':
              _base64UrlEncode(response.authenticatorData, pad: true),
          'signature': _base64UrlEncode(response.signature, pad: false),
          if (response.userHandle != null)
            'userHandle': _base64UrlEncode(response.userHandle!, pad: false),
        },
        'clientExtensionResults': credential.clientExtensionResults,
        'type': credential.type,
      },
      {'uuid': uuid},
    ];

    final result = await rpcClient.call('pks_verifyAuthentication', params);
    return _parseVerificationResult(result);
  }

  /// Lists registered credentials (`pks_getCredentials`).
  ///
  /// [context] is opaque server context, matching permissionless.js.
  Future<List<PasskeyCredentialInfo>> getCredentials({
    Map<String, dynamic>? context,
  }) async {
    final result = await rpcClient.call(
      'pks_getCredentials',
      [context],
    );

    if (result is! List) {
      throw const FormatException(
        'Invalid response from server - expected array for pks_getCredentials',
      );
    }

    final credentials = <PasskeyCredentialInfo>[];
    for (final item in result) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
            'Invalid passkey entry returned from server');
      }
      final id = item['id'];
      final publicKey = item['publicKey'];
      if (id is! String) {
        throw const FormatException('Invalid passkey id returned from server');
      }
      if (publicKey is! String || !publicKey.startsWith('0x')) {
        throw const FormatException(
          'Invalid public key returned from server - must be hex string starting with 0x',
        );
      }
      credentials.add(PasskeyCredentialInfo(id: id, publicKey: publicKey));
    }
    return credentials;
  }

  PasskeyVerificationResult _parseVerificationResult(dynamic result) {
    if (result is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid response from server - expected object for verification',
      );
    }

    final success = result['success'] == true;
    final id = result['id'];
    final publicKey = result['publicKey'];
    final userName = result['userName'];

    if (id is! String) {
      throw const FormatException('Invalid passkey id returned from server');
    }
    if (publicKey is! String || !publicKey.startsWith('0x')) {
      throw const FormatException(
        'Invalid public key returned from server - must be hex string starting with 0x',
      );
    }
    if (userName is! String) {
      throw const FormatException('Invalid user name returned from server');
    }

    return PasskeyVerificationResult(
      success: success,
      id: id,
      publicKey: publicKey,
      userName: userName,
    );
  }

  void _validateRegistrationResponse(Map<String, dynamic> response) {
    const validAttestations = {'direct', 'enterprise', 'indirect', 'none'};
    const validAttachments = {'platform', 'cross-platform'};
    const validKeyOptions = {'required', 'preferred', 'discouraged'};

    final attestation = response['attestation'];
    if (attestation is! String || !validAttestations.contains(attestation)) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }

    final selection = response['authenticatorSelection'];
    if (selection is! Map<String, dynamic>) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }
    final attachment = selection['authenticatorAttachment'];
    final requireResidentKey = selection['requireResidentKey'];
    final residentKey = selection['residentKey'];
    final userVerification = selection['userVerification'];
    if (attachment is! String ||
        !validAttachments.contains(attachment) ||
        requireResidentKey is! bool ||
        residentKey is! String ||
        !validKeyOptions.contains(residentKey) ||
        userVerification is! String ||
        !validKeyOptions.contains(userVerification)) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }

    if (response['challenge'] is! String ||
        (response['challenge'] as String).isEmpty) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }

    final extensions = response['extensions'];
    if (extensions != null) {
      if (extensions is! Map) {
        throw const FormatException(
            'Invalid response format from passkey server');
      }
      final ext = Map<String, dynamic>.from(extensions);
      if (ext.containsKey('appid') && ext['appid'] is! String) {
        throw const FormatException(
            'Invalid response format from passkey server');
      }
      if (ext.containsKey('credProps') && ext['credProps'] is! bool) {
        throw const FormatException(
            'Invalid response format from passkey server');
      }
      if (ext.containsKey('hmacCreateSecret') &&
          ext['hmacCreateSecret'] is! bool) {
        throw const FormatException(
            'Invalid response format from passkey server');
      }
      if (ext.containsKey('minPinLength') && ext['minPinLength'] is! bool) {
        throw const FormatException(
            'Invalid response format from passkey server');
      }
    }

    final rp = response['rp'];
    if (rp is! Map || rp['id'] is! String || rp['name'] is! String) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }

    final user = response['user'];
    if (user is! Map ||
        user['id'] is! String ||
        user['name'] is! String ||
        user['displayName'] is! String) {
      throw const FormatException(
          'Invalid response format from passkey server');
    }
  }

  /// Closes the underlying HTTP client.
  void close() => rpcClient.close();
}

/// Creates a [PasskeyServerClient] from a passkey server URL.
///
/// Example:
/// ```dart
/// final client = createPasskeyServerClient(
///   url: 'https://passkeys.example.com',
/// );
/// ```
PasskeyServerClient createPasskeyServerClient({
  required String url,
  http.Client? httpClient,
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    PasskeyServerClient(
      rpcClient: JsonRpcClient(
        url: Uri.parse(url),
        httpClient: httpClient,
        headers: headers ?? {},
        timeout: timeout ?? const Duration(seconds: 30),
      ),
    );

// ---------------------------------------------------------------------------
// Base64 helpers matching ox Base64.fromBytes / toBytes used by permissionless.js
// ---------------------------------------------------------------------------

Uint8List _base64ToBytes(String value) {
  var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder == 2) {
    normalized = '$normalized==';
  } else if (remainder == 3) {
    normalized = '$normalized=';
  } else if (remainder == 1) {
    // Invalid length; let base64Decode throw
  }
  return Uint8List.fromList(base64Decode(normalized));
}

String _base64Encode(List<int> bytes) => base64Encode(bytes);

String _base64UrlEncode(List<int> bytes, {required bool pad}) {
  var encoded = base64Url.encode(bytes);
  if (!pad) {
    encoded = encoded.replaceAll('=', '');
  }
  return encoded;
}

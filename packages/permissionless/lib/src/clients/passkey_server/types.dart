import 'dart:typed_data';

/// Relying Party (RP) info from `pks_startRegistration`.
class PasskeyRp {
  /// Creates RP metadata.
  const PasskeyRp({
    required this.id,
    required this.name,
  });

  /// Creates from a JSON-RPC response object.
  factory PasskeyRp.fromJson(Map<String, dynamic> json) => PasskeyRp(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  /// Relying Party ID (typically a domain).
  final String id;

  /// Human-readable RP name.
  final String name;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  @override
  String toString() => 'PasskeyRp(id: $id, name: $name)';
}

/// User entity from `pks_startRegistration` (decoded from base64).
class PasskeyUser {
  /// Creates a WebAuthn user entity.
  const PasskeyUser({
    required this.id,
    required this.name,
    required this.displayName,
  });

  /// User handle bytes (decoded from base64 in the RPC response).
  final Uint8List id;

  /// User name (e.g. email).
  final String name;

  /// Display name shown in the authenticator UI.
  final String displayName;

  @override
  String toString() => 'PasskeyUser(name: $name, displayName: $displayName)';
}

/// Authenticator selection criteria from registration options.
class PasskeyAuthenticatorSelection {
  /// Creates authenticator selection criteria.
  const PasskeyAuthenticatorSelection({
    this.authenticatorAttachment,
    this.requireResidentKey,
    this.residentKey,
    this.userVerification,
  });

  /// Creates from a JSON-RPC response object.
  factory PasskeyAuthenticatorSelection.fromJson(Map<String, dynamic> json) =>
      PasskeyAuthenticatorSelection(
        authenticatorAttachment: json['authenticatorAttachment'] as String?,
        requireResidentKey: json['requireResidentKey'] as bool?,
        residentKey: json['residentKey'] as String?,
        userVerification: json['userVerification'] as String?,
      );

  /// Preferred authenticator attachment: `platform` or `cross-platform`.
  final String? authenticatorAttachment;

  /// Whether a resident (discoverable) key is required.
  final bool? requireResidentKey;

  /// Resident key preference: `required`, `preferred`, or `discouraged`.
  final String? residentKey;

  /// User verification preference: `required`, `preferred`, or `discouraged`.
  final String? userVerification;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
        if (authenticatorAttachment != null)
          'authenticatorAttachment': authenticatorAttachment,
        if (requireResidentKey != null)
          'requireResidentKey': requireResidentKey,
        if (residentKey != null) 'residentKey': residentKey,
        if (userVerification != null) 'userVerification': userVerification,
      };
}

/// WebAuthn credential creation options from `pks_startRegistration`.
///
/// Pass these options to the platform WebAuthn API
/// (`navigator.credentials.create` / passkeys package).
class PasskeyRegistrationOptions {
  /// Creates registration options returned by the passkey server.
  const PasskeyRegistrationOptions({
    required this.rp,
    required this.user,
    required this.challenge,
    required this.attestation,
    this.timeout,
    this.authenticatorSelection,
    this.extensions,
  });

  /// Relying Party information.
  final PasskeyRp rp;

  /// User entity (id is decoded bytes).
  final PasskeyUser user;

  /// Challenge bytes (decoded from base64 in the RPC response).
  final Uint8List challenge;

  /// Attestation conveyance preference:
  /// `direct`, `enterprise`, `indirect`, or `none`.
  final String attestation;

  /// Optional timeout in milliseconds.
  final int? timeout;

  /// Authenticator selection criteria.
  final PasskeyAuthenticatorSelection? authenticatorSelection;

  /// Optional WebAuthn client extensions.
  final Map<String, dynamic>? extensions;
}

/// Authentication challenge options from `pks_startAuthentication`.
class PasskeyAuthenticationOptions {
  /// Creates authentication options returned by the passkey server.
  const PasskeyAuthenticationOptions({
    required this.challenge,
    required this.rpId,
    required this.uuid,
    this.timeout,
    this.userVerification,
  });

  /// Creates from a JSON-RPC response (challenge already hex-encoded).
  factory PasskeyAuthenticationOptions.fromJson(Map<String, dynamic> json) =>
      PasskeyAuthenticationOptions(
        challenge: json['challenge'] as String,
        rpId: json['rpId'] as String,
        uuid: json['uuid'] as String,
        timeout: json['timeout'] as int?,
        userVerification: json['userVerification'] as String?,
      );

  /// Challenge as a `0x`-prefixed hex string (matches permissionless.js).
  final String challenge;

  /// Relying Party ID.
  final String rpId;

  /// Server session UUID used when verifying authentication.
  final String uuid;

  /// Optional timeout in milliseconds.
  final int? timeout;

  /// User verification preference.
  final String? userVerification;
}

/// A registered passkey credential summary from `pks_getCredentials`.
class PasskeyCredentialInfo {
  /// Creates a credential summary.
  const PasskeyCredentialInfo({
    required this.id,
    required this.publicKey,
  });

  /// Creates from a JSON-RPC response object.
  factory PasskeyCredentialInfo.fromJson(Map<String, dynamic> json) =>
      PasskeyCredentialInfo(
        id: json['id'] as String,
        publicKey: json['publicKey'] as String,
      );

  /// Credential ID (typically base64url).
  final String id;

  /// Public key as a `0x`-prefixed hex string.
  final String publicKey;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'publicKey': publicKey,
      };

  @override
  String toString() => 'PasskeyCredentialInfo(id: $id, publicKey: $publicKey)';
}

/// Result of `pks_verifyRegistration` / `pks_verifyAuthentication`.
class PasskeyVerificationResult {
  /// Creates a verification result.
  const PasskeyVerificationResult({
    required this.success,
    required this.id,
    required this.publicKey,
    required this.userName,
  });

  /// Creates from a JSON-RPC response object.
  factory PasskeyVerificationResult.fromJson(Map<String, dynamic> json) =>
      PasskeyVerificationResult(
        success: json['success'] as bool,
        id: json['id'] as String,
        publicKey: json['publicKey'] as String,
        userName: json['userName'] as String,
      );

  /// Whether the server accepted the credential.
  final bool success;

  /// Credential ID.
  final String id;

  /// Public key as a `0x`-prefixed hex string.
  final String publicKey;

  /// Associated user name.
  final String userName;

  @override
  String toString() =>
      'PasskeyVerificationResult(success: $success, id: $id, userName: $userName)';
}

/// Attestation response fields for registration verification.
///
/// Binary fields are raw bytes; the client encodes them for the RPC payload
/// to match permissionless.js (standard / URL-safe base64).
class PasskeyAttestationResponse {
  /// Creates an attestation response.
  const PasskeyAttestationResponse({
    required this.clientDataJSON,
    required this.attestationObject,
    this.authenticatorData,
    this.transports,
    this.publicKeyAlgorithm,
    this.publicKeyType,
  });

  /// Client data JSON bytes from the authenticator.
  final Uint8List clientDataJSON;

  /// Attestation object bytes.
  final Uint8List attestationObject;

  /// Optional authenticator data bytes.
  final Uint8List? authenticatorData;

  /// Optional transport hints (e.g. `usb`, `internal`, `hybrid`).
  final List<String>? transports;

  /// COSE algorithm identifier from `getPublicKeyAlgorithm()`.
  final int? publicKeyAlgorithm;

  /// Optional public key type string.
  final String? publicKeyType;
}

/// Credential payload for `pks_verifyRegistration`.
///
/// Mirrors the browser `PublicKeyCredential` fields used by permissionless.js
/// `verifyRegistration`, using [Uint8List] instead of `ArrayBuffer`.
class PasskeyRegistrationCredential {
  /// Creates a registration credential for server verification.
  const PasskeyRegistrationCredential({
    required this.id,
    required this.rawId,
    required this.response,
    required this.authenticatorAttachment,
    this.clientExtensionResults = const {},
    this.type = 'public-key',
  });

  /// Credential ID string from the authenticator.
  final String id;

  /// Raw credential ID bytes.
  final Uint8List rawId;

  /// Attestation response.
  final PasskeyAttestationResponse response;

  /// `platform` or `cross-platform`.
  final String authenticatorAttachment;

  /// Client extension results map.
  final Map<String, dynamic> clientExtensionResults;

  /// Credential type (always `public-key` for WebAuthn).
  final String type;
}

/// Assertion response fields for authentication verification.
class PasskeyAssertionResponse {
  /// Creates an assertion response.
  const PasskeyAssertionResponse({
    required this.clientDataJSON,
    required this.authenticatorData,
    required this.signature,
    this.userHandle,
  });

  /// Client data JSON bytes.
  final Uint8List clientDataJSON;

  /// Authenticator data bytes.
  final Uint8List authenticatorData;

  /// Signature bytes.
  final Uint8List signature;

  /// Optional user handle bytes.
  final Uint8List? userHandle;
}

/// Credential payload for `pks_verifyAuthentication`.
class PasskeyAuthenticationCredential {
  /// Creates an authentication credential for server verification.
  const PasskeyAuthenticationCredential({
    required this.id,
    required this.rawId,
    required this.response,
    required this.authenticatorAttachment,
    this.clientExtensionResults = const {},
    this.type = 'public-key',
  });

  /// Credential ID string from the authenticator.
  final String id;

  /// Raw credential ID bytes.
  final Uint8List rawId;

  /// Assertion response.
  final PasskeyAssertionResponse response;

  /// `platform` or `cross-platform`.
  final String authenticatorAttachment;

  /// Client extension results map.
  final Map<String, dynamic> clientExtensionResults;

  /// Credential type (always `public-key` for WebAuthn).
  final String type;
}

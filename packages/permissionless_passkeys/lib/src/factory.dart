import 'package:web3_signers/web3_signers.dart';

import 'types/webauthn_credential.dart';

/// Creates a new passkey credential via WebAuthn registration.
///
/// This triggers the platform's biometric prompt (Face ID, Touch ID, etc.)
/// to create a new passkey bound to your relying party.
///
/// [rpId] - Relying Party identifier (your domain, e.g., 'myapp.com')
/// [rpName] - Human-readable name of your application
/// [userName] - User identifier (e.g., email address)
/// [displayName] - Optional human-readable display name for the user
/// [authenticatorAttachment] - `'platform'` (device biometrics) or
/// `'cross-platform'` (security keys, other devices; the default)
///
/// Example:
/// ```dart
/// final credential = await createPasskeyCredential(
///   rpId: 'myapp.com',
///   rpName: 'My Application',
///   userName: 'user@example.com',
/// );
///
/// // Credential can be serialized for storage
/// final json = credential.toJson();
/// ```
///
/// Throws an exception if the user cancels or WebAuthn fails.
Future<WebAuthnCredential> createPasskeyCredential({
  required String rpId,
  required String rpName,
  required String userName,
  String? displayName,
  String authenticatorAttachment = 'cross-platform',
}) async {
  final config = PassKeyConfig(
    rpId: rpId,
    rpName: rpName,
    authenticatorAttachment: authenticatorAttachment,
  );

  final publicKey = await generatePassKey(
    config: config,
    username: userName,
    displayname: displayName ?? userName,
  );
  return WebAuthnCredential.fromPublicKey(publicKey);
}

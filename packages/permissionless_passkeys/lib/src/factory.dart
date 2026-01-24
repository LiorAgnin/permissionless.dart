import 'package:web3_signers/web3_signers.dart';

import 'accounts/to_webauthn_account.dart';
import 'accounts/webauthn_account.dart';
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
}) async {
  final config = PassKeyConfig(
    rpId: rpId,
    rpName: rpName,
  );

  final publicKey = await generatePassKey(
    config: config,
    username: userName,
    displayname: displayName ?? userName,
  );
  return WebAuthnCredential.fromPublicKey(publicKey);
}

/// Creates a WebAuthn account from a credential.
///
/// This is a convenience alias for [toWebAuthnAccount] that uses
/// named parameters in a more Dart-idiomatic style.
///
/// The account can be passed as an owner to smart accounts like
/// Kernel or Safe that support WebAuthn authentication.
///
/// [credential] - The WebAuthn credential (from [createPasskeyCredential])
/// [rpId] - Relying Party identifier (must match credential registration)
/// [getFn] - Optional custom signing function for testing
///
/// Example:
/// ```dart
/// // Create WebAuthn account from credential
/// final webAuthnAccount = createWebAuthnAccountFromCredential(
///   credential: credential,
///   rpId: 'myapp.com',
/// );
///
/// // Use with Kernel smart account (v0.3.x supports WebAuthn)
/// final kernelAccount = createKernelSmartAccount(
///   owner: webAuthnAccount,
///   chainId: BigInt.from(11155111),
///   version: KernelVersion.v0_3_1,
///   publicClient: publicClient,
/// );
///
/// // Use with Safe smart account
/// final safeAccount = createSafeSmartAccount(
///   owners: [webAuthnAccount],
///   chainId: BigInt.from(11155111),
///   publicClient: publicClient,
/// );
/// ```
WebAuthnAccount createWebAuthnAccountFromCredential({
  required WebAuthnCredential credential,
  String? rpId,
  Future<Signature> Function(dynamic)? getFn,
}) {
  return createWebAuthnAccount(
    credential: credential,
    rpId: rpId,
    getFn: getFn,
  );
}

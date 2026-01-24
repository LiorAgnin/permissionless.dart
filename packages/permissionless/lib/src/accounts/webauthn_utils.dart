import 'account_owner.dart';

/// Checks if an owner is a WebAuthn account.
///
/// This function checks the `type` property of the owner to determine
/// if it's a WebAuthn account (passkey-based) rather than a standard
/// ECDSA account.
///
/// WebAuthn accounts use P256 signatures and require special encoding
/// for signature verification on-chain.
///
/// Example:
/// ```dart
/// if (isWebAuthnAccount(owner)) {
///   // Use WebAuthn signature encoding
/// } else {
///   // Use standard ECDSA signature
/// }
/// ```
bool isWebAuthnAccount(dynamic owner) {
  if (owner == null) return false;

  // Check if owner has a 'type' getter
  try {
    final type = (owner as dynamic).type as String?;
    return type == OwnerType.webAuthn;
  } catch (_) {
    return false;
  }
}

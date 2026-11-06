import 'webauthn_owner.dart';

/// Whether [owner] is a WebAuthn (passkey) owner, i.e. a
/// [WebAuthnAccountOwner].
///
/// WebAuthn owners sign with P256 through [WebAuthnAccountOwner.signP256],
/// so accounts encode their signatures differently from ECDSA owners. An
/// owner that only reports `type == OwnerType.webAuthn` without extending
/// [WebAuthnAccountOwner] has no P256 key and is not a WebAuthn owner.
///
/// Example:
/// ```dart
/// if (isWebAuthnAccount(owner)) {
///   // Use WebAuthn signature encoding
/// } else {
///   // Use standard ECDSA signature
/// }
/// ```
bool isWebAuthnAccount(dynamic owner) => owner is WebAuthnAccountOwner;

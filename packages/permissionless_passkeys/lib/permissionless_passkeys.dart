/// WebAuthn/Passkey support for permissionless.dart ERC-4337 smart accounts.
///
/// This package enables biometric authentication (Face ID, Touch ID, Windows Hello)
/// for blockchain transactions using WebAuthn passkeys with P256/secp256r1 signatures.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:permissionless/permissionless.dart';
/// import 'package:permissionless_passkeys/permissionless_passkeys.dart';
///
/// // 1. Create or retrieve a passkey credential
/// final credential = await createPasskeyCredential(
///   rpId: 'myapp.com',
///   rpName: 'My Application',
///   userName: 'user@example.com',
/// );
///
/// // 2. Create WebAuthn account from credential
/// final webAuthnAccount = toWebAuthnAccount(
///   ToWebAuthnAccountParameters(
///     credential: credential,
///     rpId: 'myapp.com',
///   ),
/// );
///
/// // 3. Use as the owner of a smart account: Kernel v0.3.0-beta, v0.3.1 or
/// //    v0.3.3 (v0.2.x and v0.3.2 have no WebAuthn validator), or Safe
/// // Note: Smart account integration with WebAuthn owners is
/// // handled by the permissionless package.
/// ```
///
/// ## Platform Requirements
///
/// | Platform | Requirement |
/// |----------|-------------|
/// | iOS | 16.0+, Associated Domains configured |
/// | Android | SDK 28+, App Links configured |
/// | Web | Modern browser with WebAuthn support |
/// | macOS | 13.0+, Associated Domains |
/// | Windows | Windows Hello configured |
///
/// See the [platform setup guide](https://pub.dev/packages/passkeys) for configuration details.
library;

export 'src/accounts/to_webauthn_account.dart';
export 'src/accounts/webauthn_account.dart';
export 'src/factory.dart';
export 'src/types/webauthn_credential.dart';

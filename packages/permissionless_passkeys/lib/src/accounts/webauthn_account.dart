import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:web3_signers/web3_signers.dart';

/// Metadata from a WebAuthn signing operation.
///
/// Contains the data needed for on-chain P256 signature verification.
class WebAuthnSignMetadata {
  /// Creates WebAuthn sign metadata.
  const WebAuthnSignMetadata({
    required this.authenticatorData,
    required this.clientDataJSON,
    required this.challengeIndex,
    required this.typeIndex,
  });

  /// Authenticator data from the WebAuthn response.
  ///
  /// Contains RP ID hash, flags, and counter.
  final Uint8List authenticatorData;

  /// Client data JSON string.
  ///
  /// Contains challenge, origin, and type.
  final String clientDataJSON;

  /// Index of the challenge in the client data JSON.
  final int challengeIndex;

  /// Index of the type field in the client data JSON.
  final int typeIndex;

  /// Converts to [P256SignatureData] by combining with signature components.
  P256SignatureData toSignatureData({
    required BigInt r,
    required BigInt s,
  }) {
    return P256SignatureData(
      r: r,
      s: s,
      authenticatorData: authenticatorData,
      clientDataJSON: clientDataJSON,
      challengeIndex: challengeIndex,
      typeIndex: typeIndex,
    );
  }
}

/// Return type for WebAuthn sign operations.
///
/// Matches viem's `WebAuthnSignReturnType` for API compatibility.
///
/// Example:
/// ```dart
/// final result = await account.sign(hash: userOpHash);
/// print('Signature: ${result.signature}');
/// print('AuthData length: ${result.webauthn.authenticatorData.length}');
/// ```
class WebAuthnSignReturnType {
  /// Creates a WebAuthn sign return value.
  const WebAuthnSignReturnType({
    required this.signature,
    required this.webauthn,
    required this.raw,
  });

  /// The P256 signature as hex (0x + r(64 hex) + s(64 hex)).
  ///
  /// This is the compact 64-byte signature without recovery byte.
  final String signature;

  /// WebAuthn metadata for on-chain verification.
  final WebAuthnSignMetadata webauthn;

  /// The raw Signature object from web3_signers.
  final Signature raw;

  /// Converts to [P256SignatureData] for use with smart accounts.
  P256SignatureData toP256SignatureData() {
    return webauthn.toSignatureData(r: raw.r, s: raw.s);
  }
}

/// WebAuthn account interface for passkey-based signing.
///
/// This interface extends [WebAuthnAccountOwner] from permissionless, allowing
/// WebAuthn accounts to be used directly with smart accounts like Kernel and Safe:
///
/// ```dart
/// final webAuthnAccount = createWebAuthnAccount(credential: credential, rpId: 'myapp.com');
///
/// // Use directly with Kernel or Safe
/// final kernelAccount = createKernelSmartAccount(
///   owner: webAuthnAccount,  // WebAuthnAccount is a valid AccountOwner
///   version: KernelVersion.v0_3_1,
///   ...
/// );
/// ```
///
/// Unlike EOA accounts that use secp256k1, WebAuthn accounts use
/// P256 (secp256r1) signatures that require special handling:
/// - On chains with RIP-7212 precompile: Native P256 verification
/// - On other chains: Contract-based P256 verification
///
/// Example:
/// ```dart
/// final account = toWebAuthnAccount(
///   credential: credential,
///   rpId: 'myapp.com',
/// );
///
/// print('Account ID: ${account.id}');
/// print('Public Key: ${account.publicKey}');
///
/// final signed = await account.sign(hash: userOpHash);
/// ```
abstract class WebAuthnAccount extends WebAuthnAccountOwner {
  /// Creates a WebAuthn account.
  const WebAuthnAccount();

  /// Base64-encoded credential ID.
  ///
  /// Uniquely identifies this passkey credential.
  String get id;

  /// Hex-encoded public key (0x + x(64 hex) + y(64 hex)).
  ///
  /// The 64-byte P256 public key as concatenated x and y coordinates.
  /// This is an alias for [publicKeyHex] from the parent class.
  String get publicKey;

  /// Signs a hash using WebAuthn.
  ///
  /// [hash] - The 32-byte hash to sign (as hex string with 0x prefix).
  ///
  /// Returns a [WebAuthnSignReturnType] containing:
  /// - `signature`: The P256 signature (r + s)
  /// - `webauthn`: Metadata for on-chain verification
  /// - `raw`: The underlying Signature object
  ///
  /// Throws if the user cancels the biometric prompt or signing fails.
  Future<WebAuthnSignReturnType> sign({required String hash});

  /// Signs a message using WebAuthn.
  ///
  /// The message is hashed before signing according to EIP-191.
  ///
  /// [message] - The message to sign (string or bytes).
  ///
  /// Returns a [WebAuthnSignReturnType] with the signature and metadata.
  Future<WebAuthnSignReturnType> signMessage({required dynamic message});

  /// Signs typed data using WebAuthn.
  ///
  /// The typed data is hashed according to EIP-712 before signing.
  ///
  /// Returns a [WebAuthnSignReturnType] with the signature and metadata.
  Future<WebAuthnSignReturnType> signTypedDataViem({
    required Map<String, dynamic> domain,
    required Map<String, List<Map<String, String>>> types,
    required String primaryType,
    required Map<String, dynamic> message,
  });
}

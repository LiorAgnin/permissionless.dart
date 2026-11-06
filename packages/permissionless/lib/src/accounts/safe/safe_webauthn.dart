import 'dart:typed_data';

import '../../types/hex.dart';
import '../../utils/encoding.dart';
import '../webauthn_owner.dart';
import 'safe_abi.dart';

/// `abi.encode` layout of the WebAuthn signature data the Safe shared signer
/// decodes.
const _safeWebAuthnSignatureTypes = [
  'bytes', // authenticatorData
  'string', // clientDataFields
  'uint256[2]', // [r, s]
];

/// Encodes a P256 signature for Safe WebAuthn shared signer verification.
///
/// Returns the ABI-encoded WebAuthn signature data:
/// ```solidity
/// abi.encode(
///   bytes authenticatorData,
///   string clientDataFields,  // Fields portion only, not full JSON
///   uint256[2] signature      // [r, s]
/// )
/// ```
///
/// Note: This returns ONLY the signature data. The Safe account is responsible
/// for wrapping this in the contract signature format with dynamic offsets.
///
/// Throws [ArgumentError] when `clientDataJSON` does not start with the
/// `{"type":"webauthn.get","challenge":"<base64url>",` prefix the shared
/// signer reconstructs on-chain.
///
/// [signature] - The raw P256 signature data from WebAuthn signing.
///
/// Example:
/// ```dart
/// final sigData = await webAuthnOwner.signP256(safeOpHash);
/// final encoded = encodeSafeWebAuthnSignature(sigData);
/// ```
String encodeSafeWebAuthnSignature(P256SignatureData signature) =>
    _encodeSafeWebAuthnSignatureData(
      authenticatorData: signature.authenticatorData,
      clientDataFields: _clientDataFields(signature.clientDataJSON),
      r: signature.r,
      s: signature.s,
    );

/// The fields after the challenge in [clientDataJSON]: the shared signer
/// rebuilds `{"type":"webauthn.get","challenge":"<challenge>",<fields>}`
/// itself, so only `<fields>` is signed over the wire.
String _clientDataFields(String clientDataJSON) {
  final match = RegExp(
    r'^\{"type":"webauthn\.get","challenge":"[A-Za-z0-9_-]+",(.+)\}$',
  ).firstMatch(clientDataJSON);
  if (match == null) {
    throw ArgumentError(
      'Invalid clientDataJSON format. Expected: {"type":"webauthn.get","challenge":"...","origin":...}',
    );
  }
  return match.group(1)!;
}

String _encodeSafeWebAuthnSignatureData({
  required Uint8List authenticatorData,
  required String clientDataFields,
  required BigInt r,
  required BigInt s,
}) =>
    AbiEncoder.encodeParameters(_safeWebAuthnSignatureTypes, [
      authenticatorData,
      clientDataFields,
      [r, s],
    ]);

/// Returns a dummy Safe WebAuthn signature for gas estimation.
///
/// This returns the ABI-encoded WebAuthn signature data (without validity period).
/// The Safe account will wrap this in the contract signature format.
///
/// Values match permissionless.js `toSafeSmartAccount.getStubSignature`
/// (realistic rpIdHash, intentionally long clientDataFields for gas headroom).
String getDummySafeWebAuthnSignature() => _encodeSafeWebAuthnSignatureData(
      authenticatorData: Hex.decode(
        '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631d00000000',
      ),
      clientDataFields:
          '"origin":"http://somelargdomainheresothatwehaveenoughbytes.com","crossOrigin":false',
      r: BigInt.parse(
        '44941127272049826721201904734628716258498742255959991581049806490182030242267',
      ),
      s: BigInt.parse(
        '9910254599581058084911561569808925251374718953855182016200087235935345969636',
      ),
    );

/// Encodes WebAuthn signer configuration for Safe shared signer setup.
///
/// Used during Safe initialization to configure the shared signer
/// with the passkey's P256 public key coordinates.
///
/// Format:
/// ```solidity
/// struct Signer {
///   uint256 x;
///   uint256 y;
///   P256.Verifiers verifiers; // uint176 packed verifier address
/// }
/// ```
///
/// [p256VerifierAddress] is a hex address, with or without `0x`.
String encodeWebAuthnSignerConfig({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) =>
    AbiEncoder.encodeParameters(
      [safeWebAuthnSignerType],
      [_signer(x, y, p256VerifierAddress)],
    );

/// Encodes the `configure` function call for SafeWebAuthnSharedSigner.
///
/// Called during Safe setup to register the passkey with the shared signer.
String encodeWebAuthnSignerConfigure({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) =>
    AbiEncoder.encodeFunctionData(
      safeWebAuthnSignerConfigureSignature,
      [_signer(x, y, p256VerifierAddress)],
    );

/// `P256.Verifiers` packs the verifier address into a uint176.
List<Object> _signer(BigInt x, BigInt y, String p256VerifierAddress) =>
    [x, y, Hex.toBigInt(p256VerifierAddress)];

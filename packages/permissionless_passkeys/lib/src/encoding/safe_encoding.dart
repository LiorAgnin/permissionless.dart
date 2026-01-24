import 'dart:typed_data';

import 'package:web3_signers/web3_signers.dart';
import 'package:web3dart/web3dart.dart'
    show unsignedIntToBytes, padUint8ListTo32;

/// Encodes a [Signature] for Safe WebAuthn verification.
///
/// Safe signatures for passkeys use a validity window format:
/// ```
/// validAfter (6 bytes) + validUntil (6 bytes) + signature
/// ```
///
/// Unlike ECDSA signatures which have 65 bytes (r+s+v), passkey signatures
/// don't include the recovery parameter (v) since P256 verification
/// works differently.
///
/// Example:
/// ```dart
/// final signature = await signer.signAsync(hash);
/// final encoded = encodeSafeWebAuthnSignature(
///   signature,
///   validAfter: DateTime.now().subtract(Duration(hours: 1)),
///   validUntil: DateTime.now().add(Duration(hours: 1)),
/// );
/// ```
String encodeSafeWebAuthnSignature(
  Signature signature, {
  DateTime? validAfter,
  DateTime? validUntil,
}) {
  final now = DateTime.now();
  final after = validAfter ?? now.subtract(const Duration(hours: 1));
  final until = validUntil ?? now.add(const Duration(hours: 1));

  // Convert to Unix timestamps
  final afterTimestamp = after.millisecondsSinceEpoch ~/ 1000;
  final untilTimestamp = until.millisecondsSinceEpoch ~/ 1000;

  // Encode as 6-byte hex (uint48)
  final afterHex = afterTimestamp.toRadixString(16).padLeft(12, '0');
  final untilHex = untilTimestamp.toRadixString(16).padLeft(12, '0');

  // Get raw signature bytes: r (32 bytes) + s (32 bytes)
  final rBytes = padUint8ListTo32(unsignedIntToBytes(signature.r));
  final sBytes = padUint8ListTo32(unsignedIntToBytes(signature.s));
  final sigBytes = Uint8List.fromList([...rBytes, ...sBytes]);
  final sigHex = _bytesToHex(sigBytes);

  return '0x$afterHex$untilHex$sigHex';
}

/// Encodes a Safe WebAuthn signature with explicit timestamps.
///
/// [signature] - The raw signature bytes from PassKeySigner
/// [validAfterSeconds] - Unix timestamp (seconds) for validity start
/// [validUntilSeconds] - Unix timestamp (seconds) for validity end
String encodeSafeWebAuthnSignatureRaw({
  required Uint8List signature,
  required int validAfterSeconds,
  required int validUntilSeconds,
}) {
  final afterHex = validAfterSeconds.toRadixString(16).padLeft(12, '0');
  final untilHex = validUntilSeconds.toRadixString(16).padLeft(12, '0');
  final sigHex = _bytesToHex(signature);

  return '0x$afterHex$untilHex$sigHex';
}

/// Generates a dummy Safe WebAuthn signature for gas estimation.
///
/// Returns a properly formatted but invalid signature that has the correct
/// byte length for gas estimation purposes.
String getDummySafeWebAuthnSignature() {
  // Format: validAfter (6 bytes) + validUntil (6 bytes) + signature
  const validAfter = '000000000000'; // 0 (always valid from past)
  const validUntil = 'ffffffffffff'; // max uint48 (valid until far future)

  // Dummy passkey signature - r (32 bytes) + s (32 bytes) = 64 bytes
  // Plus authenticatorData and clientDataJSON when ABI-encoded
  // For estimation, use a reasonable-length dummy
  final dummySig = 'ff' * 64;

  return '0x$validAfter$validUntil$dummySig';
}

/// Encodes WebAuthn signer configuration for Safe setup.
///
/// This is used during Safe initialization to configure the shared signer
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
String encodeWebAuthnSignerConfig({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) {
  // Encode x and y as uint256 (32 bytes each)
  final xHex = x.toRadixString(16).padLeft(64, '0');
  final yHex = y.toRadixString(16).padLeft(64, '0');

  // P256.Verifiers is uint176 (22 bytes), but address is 20 bytes
  // Pad the address to 22 bytes with leading zeros for the verifier config
  final verifierClean = p256VerifierAddress.replaceAll('0x', '').toLowerCase();
  final verifierHex = verifierClean.padLeft(44, '0'); // 22 bytes = 44 hex chars

  // ABI encode as tuple
  return '0x$xHex$yHex$verifierHex';
}

/// Encodes the `configure` function call for SafeWebAuthnSharedSigner.
///
/// This is called during Safe setup to register the passkey with the
/// shared signer contract.
String encodeWebAuthnSignerConfigure({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) {
  // Function selector for configure((uint256,uint256,uint176))
  const selector =
      '75794a3c'; // keccak256("configure((uint256,uint256,uint176))")[:4]

  // The struct is passed as a tuple, which is ABI-encoded inline (no offset)
  final signerConfig = encodeWebAuthnSignerConfig(
    x: x,
    y: y,
    p256VerifierAddress: p256VerifierAddress,
  );

  return '0x$selector${signerConfig.substring(2)}';
}

/// Converts bytes to hex string (without 0x prefix).
String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

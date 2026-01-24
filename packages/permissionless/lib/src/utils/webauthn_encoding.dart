import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import '../accounts/webauthn_owner.dart';
import 'encoding.dart';

/// Encodes a P256 signature for Kernel WebAuthn validator verification.
///
/// The Kernel WebAuthn validator expects:
/// ```solidity
/// abi.encode(
///   bytes authenticatorData,
///   string clientDataJSON,
///   uint256 responseTypeLocation,
///   uint256 r,
///   uint256 s,
///   bool usePrecompiled
/// )
/// ```
///
/// [signature] - The raw P256 signature data from WebAuthn signing.
/// [usePrecompiled] - Whether to use RIP-7212 P256 precompile (default: true).
///
/// Example:
/// ```dart
/// final sigData = await webAuthnOwner.signP256(userOpHash);
/// final encoded = encodeKernelWebAuthnSignature(sigData);
/// ```
String encodeKernelWebAuthnSignature(
  P256SignatureData signature, {
  bool usePrecompiled = true,
}) {
  // Encode dynamic types
  final authDataEncoded = _encodeAbiBytes(signature.authenticatorData);
  final clientDataEncoded = _encodeAbiString(signature.clientDataJSON);

  // Calculate offsets
  // Static parts: 6 parameters * 32 bytes = 192 bytes
  const staticSize = 6 * 32;

  // authenticatorData offset (points to length + data)
  const authDataOffset = staticSize;

  // clientDataJSON offset (after authenticatorData)
  final clientDataOffset = authDataOffset + _encodedLength(authDataEncoded);

  // Build the encoded parameters
  final buffer = StringBuffer()
    // 1. Offset to authenticatorData (bytes)
    ..write(_uint256ToHex(BigInt.from(authDataOffset)))
    // 2. Offset to clientDataJSON (string)
    ..write(_uint256ToHex(BigInt.from(clientDataOffset)))
    // 3. responseTypeLocation (uint256)
    ..write(_uint256ToHex(BigInt.from(signature.typeIndex)))
    // 4. r (uint256)
    ..write(_uint256ToHex(signature.r))
    // 5. s (uint256)
    ..write(_uint256ToHex(signature.s))
    // 6. usePrecompiled (bool)
    ..write(_uint256ToHex(usePrecompiled ? BigInt.one : BigInt.zero))
    // 7. authenticatorData (bytes - dynamic)
    ..write(authDataEncoded)
    // 8. clientDataJSON (string - dynamic)
    ..write(clientDataEncoded);

  return '0x${buffer.toString()}';
}

/// Returns a dummy Kernel WebAuthn signature for gas estimation.
///
/// This returns a properly formatted but invalid signature with the correct
/// byte length for bundler gas estimation.
///
/// [usePrecompiled] - Whether to use RIP-7212 P256 precompile. Set based on
/// chain support using [shouldUseP256Precompile] from `rip7212.dart`.
String getDummyKernelWebAuthnSignature({bool usePrecompiled = false}) {
  final dummyAuthData = Uint8List(37); // Typical authenticator data length
  const dummyClientData =
      '{"type":"webauthn.get","challenge":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","origin":"https://example.com"}';
  const dummyTypeIndex = 1;
  final dummyR = BigInt.parse(
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    radix: 16,
  );
  final dummyS = BigInt.parse(
    '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0',
    radix: 16,
  );

  return encodeKernelWebAuthnSignature(
    P256SignatureData(
      r: dummyR,
      s: dummyS,
      authenticatorData: dummyAuthData,
      clientDataJSON: dummyClientData,
      challengeIndex: 0,
      typeIndex: dummyTypeIndex,
    ),
    usePrecompiled: usePrecompiled,
  );
}

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
/// [signature] - The raw P256 signature data from WebAuthn signing.
///
/// Example:
/// ```dart
/// final sigData = await webAuthnOwner.signP256(safeOpHash);
/// final encoded = encodeSafeWebAuthnSignature(sigData);
/// ```
String encodeSafeWebAuthnSignature(P256SignatureData signature) {
  // Extract clientDataFields from clientDataJSON
  // Format: {"type":"webauthn.get","challenge":"...",<fields>}
  // We need just the <fields> portion (everything after the challenge)
  final clientDataFields = _extractClientDataFields(signature.clientDataJSON);

  // ABI encode: (bytes authenticatorData, string clientDataFields, uint256[2] sig)
  final webAuthnSigEncoded = _encodeWebAuthnSignatureData(
    authenticatorData: signature.authenticatorData,
    clientDataFields: clientDataFields,
    r: signature.r,
    s: signature.s,
  );

  return '0x$webAuthnSigEncoded';
}

/// Extracts the fields portion from clientDataJSON.
///
/// Input: `{"type":"webauthn.get","challenge":"abc123...","origin":"https://..."}`
/// Output: `"origin":"https://..."`
String _extractClientDataFields(String clientDataJSON) {
  // Pattern: {"type":"webauthn.get","challenge":"<base64url>",<fields>}
  // Base64url chars: A-Z, a-z, 0-9, -, _
  final pattern = RegExp(
    r'^\{"type":"webauthn\.get","challenge":"[A-Za-z0-9_-]+",(.+)\}$',
  );
  final match = pattern.firstMatch(clientDataJSON);
  if (match == null) {
    throw ArgumentError(
      'Invalid clientDataJSON format. Expected: {"type":"webauthn.get","challenge":"...","origin":...}',
    );
  }
  return match.group(1)!;
}

/// ABI encodes WebAuthn signature data for Safe verification.
///
/// Returns hex string WITHOUT 0x prefix.
String _encodeWebAuthnSignatureData({
  required Uint8List authenticatorData,
  required String clientDataFields,
  required BigInt r,
  required BigInt s,
}) {
  // ABI structure: (bytes, string, uint256[2])
  // - Offset to bytes authenticatorData
  // - Offset to string clientDataFields
  // - uint256[2] inline (r, s)
  // - bytes authenticatorData (length + padded data)
  // - string clientDataFields (length + padded data)

  // Static part: 3 slots (offset, offset, r) + 1 slot (s) = 4 * 32 = 128 bytes
  // But uint256[2] is inline, so: offset(32) + offset(32) + r(32) + s(32) = 128
  const staticSize = 4 * 32;

  // Encode dynamic parts
  final authDataEncoded = _encodeAbiBytes(authenticatorData);
  final fieldsEncoded = _encodeAbiString(clientDataFields);

  // Calculate offsets
  const authDataOffset = staticSize; // 128
  final fieldsOffset = authDataOffset + _encodedLength(authDataEncoded);

  final buffer = StringBuffer()
    // 1. Offset to authenticatorData
    ..write(_uint256ToHex(BigInt.from(authDataOffset)))
    // 2. Offset to clientDataFields
    ..write(_uint256ToHex(BigInt.from(fieldsOffset)))
    // 3. r (uint256)
    ..write(_uint256ToHex(r))
    // 4. s (uint256)
    ..write(_uint256ToHex(s))
    // 5. authenticatorData (bytes - dynamic)
    ..write(authDataEncoded)
    // 6. clientDataFields (string - dynamic)
    ..write(fieldsEncoded);

  return buffer.toString();
}

/// Returns a dummy Safe WebAuthn signature for gas estimation.
///
/// This returns the ABI-encoded WebAuthn signature data (without validity period).
/// The Safe account will wrap this in the contract signature format.
String getDummySafeWebAuthnSignature() {
  // Dummy values matching permissionless.js format
  final dummyAuthData = Uint8List.fromList([
    // rpIdHash (32 bytes) + flags (1 byte) + signCount (4 bytes) = 37 bytes
    ...List.filled(32, 0x49), // rpIdHash
    0x1d, // flags
    0x00, 0x00, 0x00, 0x00, // signCount
  ]);

  // Dummy clientDataFields (the portion after challenge)
  const dummyFields =
      '"origin":"http://localhost:3000","crossOrigin":false';

  // Dummy r and s values
  final dummyR = BigInt.parse(
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    radix: 16,
  );
  final dummyS = BigInt.parse(
    '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0',
    radix: 16,
  );

  // ABI encode the WebAuthn signature data
  final webAuthnSigEncoded = _encodeWebAuthnSignatureData(
    authenticatorData: dummyAuthData,
    clientDataFields: dummyFields,
    r: dummyR,
    s: dummyS,
  );

  return '0x$webAuthnSigEncoded';
}

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
String encodeWebAuthnSignerConfig({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) {
  // Encode x and y as uint256 (32 bytes each)
  final xHex = x.toRadixString(16).padLeft(64, '0');
  final yHex = y.toRadixString(16).padLeft(64, '0');

  // P256.Verifiers is uint176, but ABI encoding pads all static types to 32 bytes
  // The verifier address is treated as a uint176, left-padded to 32 bytes
  final verifierClean = p256VerifierAddress.replaceAll('0x', '').toLowerCase();
  final verifierHex = verifierClean.padLeft(64, '0'); // 32 bytes = 64 hex chars

  // ABI encode as tuple (each element is 32 bytes)
  return '0x$xHex$yHex$verifierHex';
}

/// Encodes the `configure` function call for SafeWebAuthnSharedSigner.
///
/// Called during Safe setup to register the passkey with the shared signer.
String encodeWebAuthnSignerConfigure({
  required BigInt x,
  required BigInt y,
  required String p256VerifierAddress,
}) {
  // Function selector for configure((uint256,uint256,uint176))
  // Computed via AbiEncoder for correctness (returns with 0x prefix)
  final selector = AbiEncoder.functionSelector(
    'configure((uint256,uint256,uint176))',
  );

  // The struct is passed as a tuple, which is ABI-encoded inline (no offset)
  final signerConfig = encodeWebAuthnSignerConfig(
    x: x,
    y: y,
    p256VerifierAddress: p256VerifierAddress,
  );

  // selector already has 0x prefix, signerConfig also has 0x prefix
  return '$selector${signerConfig.substring(2)}';
}

/// Encodes the WebAuthn validator data for Kernel v0.3.x initialization.
///
/// The WebAuthn validator expects ABI-encoded tuple + authenticatorIdHash:
/// ```solidity
/// (tuple(uint256 x, uint256 y) webAuthnData, bytes32 authenticatorIdHash)
/// ```
///
/// Where authenticatorIdHash = keccak256(credentialId)
String encodeKernelWebAuthnValidatorData({
  required BigInt x,
  required BigInt y,
  required Uint8List credentialId,
}) {
  // Compute authenticatorIdHash = keccak256(credentialId)
  final authenticatorIdHash = keccak256(credentialId);

  // ABI encode: tuple(uint256 x, uint256 y), bytes32 authenticatorIdHash
  // Tuple is encoded inline as (x, y), followed by authenticatorIdHash
  final xHex = x.toRadixString(16).padLeft(64, '0');
  final yHex = y.toRadixString(16).padLeft(64, '0');
  final hashHex = _bytesToHex(authenticatorIdHash);

  return '0x$xHex$yHex$hashHex';
}

// ============================================================================
// Internal ABI Encoding Helpers
// ============================================================================

/// Encodes bytes for ABI (length + padded data).
String _encodeAbiBytes(Uint8List data) {
  final length = _uint256ToHex(BigInt.from(data.length));
  final paddedLength = ((data.length + 31) ~/ 32) * 32;
  final padded = Uint8List(paddedLength)..setRange(0, data.length, data);
  return '$length${_bytesToHex(padded)}';
}

/// Encodes string for ABI (length + UTF-8 bytes padded).
String _encodeAbiString(String value) {
  final bytes = utf8.encode(value);
  return _encodeAbiBytes(Uint8List.fromList(bytes));
}

/// Returns the byte length of encoded bytes/string in ABI format.
int _encodedLength(String encoded) {
  final clean = encoded.startsWith('0x') ? encoded.substring(2) : encoded;
  return clean.length ~/ 2;
}

/// Converts BigInt to 32-byte hex string (without 0x prefix).
String _uint256ToHex(BigInt value) => value.toRadixString(16).padLeft(64, '0');

/// Converts bytes to hex string (without 0x prefix).
String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

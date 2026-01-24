import 'dart:convert';
import 'dart:typed_data';

import 'package:web3_signers/web3_signers.dart';

/// Encodes a [Signature] for on-chain verification by Kernel WebAuthn validator.
///
/// The encoded format is:
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
/// Example:
/// ```dart
/// final signature = await signer.signAsync(hash);
/// final encoded = encodeKernelWebAuthnSignature(
///   signature,
///   usePrecompiled: true,  // Use RIP-7212 P256 precompile
/// );
/// ```
String encodeKernelWebAuthnSignature(
  Signature signature, {
  bool usePrecompiled = true,
}) {
  // Extract signature components
  final authenticatorData = signature.authData!;
  final clientDataJSON = signature.clientDataJson!;
  final typeIndex = BigInt.from(signature.getTypeLocation()!);
  final r = signature.r;
  final s = signature.s;

  // ABI encode the signature
  return _abiEncodeKernelSignature(
    authenticatorData: authenticatorData,
    clientDataJSON: clientDataJSON,
    responseTypeLocation: typeIndex,
    r: r,
    s: s,
    usePrecompiled: usePrecompiled,
  );
}

/// Generates a dummy WebAuthn signature for gas estimation.
///
/// Returns a properly formatted but invalid signature that has the correct
/// byte length for gas estimation purposes.
String getDummyKernelWebAuthnSignature() {
  // Generate dummy values matching real signature structure
  final dummyAuthData = Uint8List(37); // Typical authenticator data length
  final dummyClientData =
      '{"type":"webauthn.get","challenge":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","origin":"https://example.com"}';
  final dummyTypeIndex = BigInt.from(1);
  final dummyR = BigInt.parse(
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    radix: 16,
  );
  final dummyS = BigInt.parse(
    '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0',
    radix: 16,
  );

  return _abiEncodeKernelSignature(
    authenticatorData: dummyAuthData,
    clientDataJSON: dummyClientData,
    responseTypeLocation: dummyTypeIndex,
    r: dummyR,
    s: dummyS,
    usePrecompiled: true,
  );
}

/// Internal ABI encoding for Kernel WebAuthn signature.
String _abiEncodeKernelSignature({
  required Uint8List authenticatorData,
  required String clientDataJSON,
  required BigInt responseTypeLocation,
  required BigInt r,
  required BigInt s,
  required bool usePrecompiled,
}) {
  // Encode dynamic types
  final authDataEncoded = _encodeBytes(authenticatorData);
  final clientDataEncoded = _encodeString(clientDataJSON);

  // Calculate offsets
  // Static parts: 6 parameters * 32 bytes = 192 bytes
  const staticSize = 6 * 32;

  // authenticatorData offset (points to length + data)
  const authDataOffset = staticSize;

  // clientDataJSON offset (after authenticatorData)
  final clientDataOffset =
      authDataOffset + _encodedBytesLength(authDataEncoded);

  // Build the encoded parameters
  final buffer = StringBuffer();

  // 1. Offset to authenticatorData (bytes)
  buffer.write(_uint256ToHex(BigInt.from(authDataOffset)));

  // 2. Offset to clientDataJSON (string)
  buffer.write(_uint256ToHex(BigInt.from(clientDataOffset)));

  // 3. responseTypeLocation (uint256)
  buffer.write(_uint256ToHex(responseTypeLocation));

  // 4. r (uint256)
  buffer.write(_uint256ToHex(r));

  // 5. s (uint256)
  buffer.write(_uint256ToHex(s));

  // 6. usePrecompiled (bool)
  buffer.write(_uint256ToHex(usePrecompiled ? BigInt.one : BigInt.zero));

  // 7. authenticatorData (bytes - dynamic)
  buffer.write(authDataEncoded);

  // 8. clientDataJSON (string - dynamic)
  buffer.write(clientDataEncoded);

  return '0x${buffer.toString()}';
}

/// Encodes bytes for ABI (length + padded data).
String _encodeBytes(Uint8List data) {
  final length = _uint256ToHex(BigInt.from(data.length));
  final paddedLength = ((data.length + 31) ~/ 32) * 32;
  final padded = Uint8List(paddedLength)..setRange(0, data.length, data);
  return '$length${_bytesToHex(padded)}';
}

/// Encodes string for ABI (length + UTF-8 bytes padded).
String _encodeString(String value) {
  final bytes = utf8.encode(value);
  return _encodeBytes(Uint8List.fromList(bytes));
}

/// Returns the byte length of encoded bytes/string in ABI format.
int _encodedBytesLength(String encoded) {
  // Remove 0x prefix if present and divide by 2
  final clean = encoded.startsWith('0x') ? encoded.substring(2) : encoded;
  return clean.length ~/ 2;
}

/// Converts BigInt to 32-byte hex string (without 0x prefix).
String _uint256ToHex(BigInt value) {
  return value.toRadixString(16).padLeft(64, '0');
}

/// Converts bytes to hex string (without 0x prefix).
String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

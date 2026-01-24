import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';

/// Test fixtures for WebAuthn passkeys tests.
///
/// These fixtures provide mock data for testing encoding functions,
/// account implementations, and other functionality without requiring
/// actual WebAuthn hardware or biometric authentication.

/// Mock P256 public key X coordinate (32 bytes).
final BigInt testPublicKeyX = BigInt.parse(
  '0x65a3d7c52bf7e3f3a3d0e8b2c1d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2',
);

/// Mock P256 public key Y coordinate (32 bytes).
final BigInt testPublicKeyY = BigInt.parse(
  '0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b',
);

/// Mock credential ID (base64).
const String testCredentialId = 'dGVzdC1jcmVkZW50aWFsLWlk';

/// Mock credential ID (raw bytes).
final Uint8List testCredentialIdBytes = Uint8List.fromList(
  'test-credential-id'.codeUnits,
);

/// Mock P256 signature R value (32 bytes).
final BigInt testSignatureR = BigInt.parse(
  '0xaabbccdd11223344556677889900aabbccdd11223344556677889900aabbccdd',
);

/// Mock P256 signature S value (32 bytes).
final BigInt testSignatureS = BigInt.parse(
  '0x1122334455667788990011223344556677889900112233445566778899001122',
);

/// Mock authenticator data (37 bytes minimum).
///
/// Format: rpIdHash (32) + flags (1) + signCount (4)
final Uint8List testAuthenticatorData = Uint8List.fromList([
  // rpIdHash (32 bytes) - SHA256 of relying party ID
  0x49, 0x96, 0x0d, 0xe5, 0x88, 0x0e, 0x8c, 0x68,
  0x74, 0x34, 0x17, 0x0f, 0x64, 0x76, 0x60, 0x5b,
  0x8f, 0xe4, 0xae, 0xb9, 0xa2, 0x86, 0x32, 0xc7,
  0x99, 0x5c, 0xf3, 0xba, 0x83, 0x1d, 0x97, 0x63,
  // flags (1 byte) - UP (user present) + UV (user verified)
  0x05,
  // signCount (4 bytes, big-endian)
  0x00, 0x00, 0x00, 0x01,
]);

/// Mock client data JSON for WebAuthn assertion.
const String testClientDataJSON = '{"type":"webauthn.get",'
    '"challenge":"dGVzdC1jaGFsbGVuZ2U",'
    '"origin":"https://example.com",'
    '"crossOrigin":false}';

/// Mock response type location in client data JSON.
///
/// This is the byte offset where '"type"' key starts in the JSON.
/// Note: getTypeLocation() returns the position of the key, not the value.
const int testResponseTypeLocation = 1;

/// Creates a mock Ethereum address for testing.
EthereumAddress testAddress(
    [String hex = '0x1234567890123456789012345678901234567890']) {
  return EthereumAddress.fromHex(hex);
}

/// Test chain IDs.
class TestChainIds {
  TestChainIds._();

  static final BigInt sepolia = BigInt.from(11155111);
  static final BigInt baseSepolia = BigInt.from(84532);
  static final BigInt mainnet = BigInt.from(1);
  static final BigInt optimism = BigInt.from(10);
  static final BigInt unsupported = BigInt.from(999999);
}

/// Encodes a BigInt to a 32-byte hex string (without 0x prefix).
String bigIntToHex32(BigInt value) {
  return value.toRadixString(16).padLeft(64, '0');
}

/// Encodes bytes to a hex string (without 0x prefix).
String bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Mock Call for transaction encoding tests.
Call testCall({
  EthereumAddress? to,
  BigInt? value,
  String data = '0x',
}) {
  return Call(
    to: to ?? testAddress(),
    value: value ?? BigInt.zero,
    data: data,
  );
}

/// Mock calls for batch transaction tests.
List<Call> testCalls({int count = 3}) {
  return List.generate(
    count,
    (i) => Call(
      to: EthereumAddress.fromHex(
        '0x${(i + 1).toRadixString(16).padLeft(40, '0')}',
      ),
      value: BigInt.from(i * 1000),
      data: '0x${(i + 1).toRadixString(16).padLeft(8, '0')}',
    ),
  );
}

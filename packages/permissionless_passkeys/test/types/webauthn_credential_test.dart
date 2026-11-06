import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';
import 'package:web3_signers/web3_signers.dart';

import '../helpers/test_fixtures.dart';

void main() {
  group('WebAuthnCredential', () {
    group('constructor', () {
      test('creates credential with all required fields', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        expect(credential.id, equals(testCredentialId));
        expect(credential.rawId, equals(testCredentialIdBytes));
        expect(credential.x, equals(testPublicKeyX));
        expect(credential.y, equals(testPublicKeyY));
      });

      test('stores immutable values', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        // Values should match after access
        expect(credential.x, equals(testPublicKeyX));
        expect(credential.y, equals(testPublicKeyY));
      });
    });

    group('publicKeyHex', () {
      test('returns hex with 0x prefix', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        expect(credential.publicKeyHex.startsWith('0x'), isTrue);
      });

      test('returns 64-byte hex string (128 hex chars + 0x)', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        // 0x + 64 bytes (x) + 64 bytes (y) = 130 total chars
        expect(credential.publicKeyHex.length, equals(130));
      });

      test('contains x coordinate in first 32 bytes', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        final hex = credential.publicKeyHex.substring(2);
        final xHex = hex.substring(0, 64);

        // Verify x matches
        final expectedXHex = bigIntToHex32(testPublicKeyX);
        expect(xHex, equals(expectedXHex));
      });

      test('contains y coordinate in second 32 bytes', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        final hex = credential.publicKeyHex.substring(2);
        final yHex = hex.substring(64, 128);

        // Verify y matches
        final expectedYHex = bigIntToHex32(testPublicKeyY);
        expect(yHex, equals(expectedYHex));
      });

      test('handles small coordinates with proper padding', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: BigInt.from(255), // 0xff - 1 byte
          y: BigInt.from(256), // 0x100 - 2 bytes
          raw: _createMockPassKeyPair(),
        );

        final hex = credential.publicKeyHex.substring(2);

        // x = 255 should be padded to 32 bytes
        final xHex = hex.substring(0, 64);
        expect(xHex, equals('00' * 31 + 'ff'));

        // y = 256 should be padded to 32 bytes
        final yHex = hex.substring(64, 128);
        expect(yHex, equals('00' * 30 + '0100'));
      });

      test('handles zero coordinates', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: BigInt.zero,
          y: BigInt.zero,
          raw: _createMockPassKeyPair(),
        );

        final hex = credential.publicKeyHex.substring(2);

        expect(hex, equals('00' * 64));
      });

      test('handles max uint256 coordinates', () {
        final maxUint256 = (BigInt.one << 256) - BigInt.one;

        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: maxUint256,
          y: maxUint256,
          raw: _createMockPassKeyPair(),
        );

        final hex = credential.publicKeyHex.substring(2);

        expect(hex, equals('ff' * 64));
      });

      test('is deterministic (same output each call)', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        final hex1 = credential.publicKeyHex;
        final hex2 = credential.publicKeyHex;

        expect(hex1, equals(hex2));
      });
    });

    group('field access', () {
      test('id is accessible', () {
        final credential = WebAuthnCredential(
          id: 'custom-id',
          rawId: Uint8List.fromList([1, 2, 3]),
          x: BigInt.one,
          y: BigInt.two,
          raw: _createMockPassKeyPair(),
        );

        expect(credential.id, equals('custom-id'));
      });

      test('rawId is accessible', () {
        final rawId = Uint8List.fromList([1, 2, 3, 4, 5]);

        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: rawId,
          x: BigInt.one,
          y: BigInt.two,
          raw: _createMockPassKeyPair(),
        );

        expect(credential.rawId, equals(rawId));
      });

      test('raw PassKeyPublicKey is accessible', () {
        final pair = _createMockPassKeyPair();

        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: testPublicKeyX,
          y: testPublicKeyY,
          raw: pair,
        );

        expect(credential.raw, equals(pair));
      });
    });

    group('publicKeyHex range', () {
      test('rejects a coordinate wider than 32 bytes', () {
        final credential = WebAuthnCredential(
          id: testCredentialId,
          rawId: testCredentialIdBytes,
          x: BigInt.one << 256,
          y: testPublicKeyY,
          raw: _createMockPassKeyPair(),
        );

        expect(() => credential.publicKeyHex, throwsArgumentError);
      });
    });

    group('JSON', () {
      test('toJson/fromJson round-trips every field', () {
        final original = WebAuthnCredential.fromPublicKey(
          PassKeyPublicKey(
            x: Uint256(BigInt.from(0x1234)),
            y: Uint256(testPublicKeyY),
            // 7 bytes: base64url needs '==' padding, which toJson strips.
            credentialId: Uint8List.fromList('mock-id'.codeUnits),
            userName: 'test@example.com',
            aaGuid: '00000000-0000-0000-0000-000000000000',
          ),
        );

        final restored = WebAuthnCredential.fromJson(original.toJson());

        expect(restored.id, original.id);
        expect(restored.id, 'bW9jay1pZA');
        expect(restored.rawId, original.rawId);
        expect(restored.x, original.x);
        expect(restored.y, original.y);
        expect(restored.publicKeyHex, original.publicKeyHex);
        expect(restored.raw.userName, 'test@example.com');
        expect(restored.raw.aaGuid, '00000000-0000-0000-0000-000000000000');
        expect(restored.toJson(), original.toJson());
      });

      test('fromJson defaults missing userName and aaGuid to empty', () {
        final credential = WebAuthnCredential.fromJson(
          '{"raw":{"x":"0x01","y":"0x02","credentialId":"bW9jay1pZA"}}',
        );

        expect(credential.x, BigInt.one);
        expect(credential.y, BigInt.two);
        expect(credential.rawId, 'mock-id'.codeUnits);
        expect(credential.raw.userName, '');
        expect(credential.raw.aaGuid, '');
      });
    });
  });
}

/// Creates a mock PassKeyPublicKey for testing.
PassKeyPublicKey _createMockPassKeyPair() {
  return PassKeyPublicKey(
    x: Uint256(testPublicKeyX),
    y: Uint256(testPublicKeyY),
    credentialId: Uint8List.fromList('mock-id'.codeUnits),
    userName: 'test@example.com',
    aaGuid: '00000000-0000-0000-0000-000000000000',
  );
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless_passkeys/src/encoding/safe_encoding.dart';

import '../helpers/test_fixtures.dart';

void main() {
  group('Safe Encoding', () {
    group('getDummySafeWebAuthnSignature', () {
      test('returns valid hex string', () {
        final sig = getDummySafeWebAuthnSignature();

        expect(sig.startsWith('0x'), isTrue);
        expect(sig.length, greaterThan(2));
      });

      test('has correct format (validAfter + validUntil + signature)', () {
        final sig = getDummySafeWebAuthnSignature();
        final hex = sig.substring(2); // Remove 0x

        // Format: 6 bytes validAfter + 6 bytes validUntil + 64 bytes signature
        // = 12 + 12 + 128 = 152 hex chars
        expect(hex.length, equals(152));

        // validAfter should be 0
        final validAfter = hex.substring(0, 12);
        expect(validAfter, equals('000000000000'));

        // validUntil should be max uint48
        final validUntil = hex.substring(12, 24);
        expect(validUntil, equals('ffffffffffff'));

        // Signature should be 64 bytes of 0xff
        final signature = hex.substring(24);
        expect(signature.length, equals(128));
        expect(signature, equals('ff' * 64));
      });
    });

    group('encodeSafeWebAuthnSignatureRaw', () {
      test('encodes with explicit timestamps', () {
        final signature = Uint8List(64);
        for (var i = 0; i < 64; i++) {
          signature[i] = i;
        }

        final result = encodeSafeWebAuthnSignatureRaw(
          signature: signature,
          validAfterSeconds: 1000,
          validUntilSeconds: 2000,
        );

        expect(result.startsWith('0x'), isTrue);

        final hex = result.substring(2);

        // validAfter = 1000 = 0x3e8
        final validAfter = hex.substring(0, 12);
        expect(validAfter, equals('0000000003e8'));

        // validUntil = 2000 = 0x7d0
        final validUntil = hex.substring(12, 24);
        expect(validUntil, equals('0000000007d0'));

        // Signature bytes
        final sigHex = hex.substring(24);
        expect(sigHex.length, equals(128));
      });

      test('handles zero timestamps', () {
        final signature = Uint8List(64);

        final result = encodeSafeWebAuthnSignatureRaw(
          signature: signature,
          validAfterSeconds: 0,
          validUntilSeconds: 0,
        );

        final hex = result.substring(2);
        expect(hex.substring(0, 12), equals('000000000000'));
        expect(hex.substring(12, 24), equals('000000000000'));
      });

      test('handles large timestamps', () {
        final signature = Uint8List(64);
        // Max uint48 = 281474976710655
        const maxUint48 = 281474976710655;

        final result = encodeSafeWebAuthnSignatureRaw(
          signature: signature,
          validAfterSeconds: maxUint48,
          validUntilSeconds: maxUint48,
        );

        final hex = result.substring(2);
        expect(hex.substring(0, 12), equals('ffffffffffff'));
        expect(hex.substring(12, 24), equals('ffffffffffff'));
      });
    });

    group('encodeWebAuthnSignerConfig', () {
      test('encodes public key coordinates and verifier', () {
        final result = encodeWebAuthnSignerConfig(
          x: testPublicKeyX,
          y: testPublicKeyY,
          p256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
        );

        expect(result.startsWith('0x'), isTrue);

        final hex = result.substring(2);

        // x coordinate (32 bytes = 64 hex chars)
        final xHex = hex.substring(0, 64);
        expect(xHex, equals(bigIntToHex32(testPublicKeyX)));

        // y coordinate (32 bytes = 64 hex chars)
        final yHex = hex.substring(64, 128);
        expect(yHex, equals(bigIntToHex32(testPublicKeyY)));

        // verifier address (22 bytes = 44 hex chars, padded)
        final verifierHex = hex.substring(128);
        expect(verifierHex.length, equals(44));
        expect(
          verifierHex
              .toLowerCase()
              .endsWith('a86e0054c51e4894d88762a017ecc5e5235f5dba'),
          isTrue,
        );
      });

      test('handles verifier address with 0x prefix', () {
        final result = encodeWebAuthnSignerConfig(
          x: BigInt.one,
          y: BigInt.two,
          p256VerifierAddress: '0x1234567890123456789012345678901234567890',
        );

        expect(result.contains('1234567890123456789012345678901234567890'),
            isTrue);
      });

      test('handles verifier address without 0x prefix', () {
        final result = encodeWebAuthnSignerConfig(
          x: BigInt.one,
          y: BigInt.two,
          p256VerifierAddress: '1234567890123456789012345678901234567890',
        );

        expect(result.contains('1234567890123456789012345678901234567890'),
            isTrue);
      });
    });

    group('encodeWebAuthnSignerConfigure', () {
      test('has correct function selector', () {
        final result = encodeWebAuthnSignerConfigure(
          x: testPublicKeyX,
          y: testPublicKeyY,
          p256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
        );

        // Function selector for configure((uint256,uint256,uint176))
        expect(result.startsWith('0x75794a3c'), isTrue);
      });

      test('includes signer config after selector', () {
        final result = encodeWebAuthnSignerConfigure(
          x: testPublicKeyX,
          y: testPublicKeyY,
          p256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
        );

        // 4 byte selector + encoded config
        final hex = result.substring(2);
        expect(hex.length, greaterThan(8)); // More than just selector

        // Check config is included
        final configPart = hex.substring(8);
        expect(configPart, contains(bigIntToHex32(testPublicKeyX)));
        expect(configPart, contains(bigIntToHex32(testPublicKeyY)));
      });
    });
  });
}

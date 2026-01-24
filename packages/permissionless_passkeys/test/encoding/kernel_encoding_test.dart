import 'package:flutter_test/flutter_test.dart';
import 'package:permissionless_passkeys/src/encoding/kernel_encoding.dart';

void main() {
  group('Kernel Encoding', () {
    group('getDummyKernelWebAuthnSignature', () {
      test('returns valid hex string', () {
        final sig = getDummyKernelWebAuthnSignature();

        expect(sig.startsWith('0x'), isTrue);
        expect(sig.length, greaterThan(2));
      });

      test('is deterministic (same output each call)', () {
        final sig1 = getDummyKernelWebAuthnSignature();
        final sig2 = getDummyKernelWebAuthnSignature();

        expect(sig1, equals(sig2));
      });

      test('has valid ABI encoding structure', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2); // Remove 0x prefix

        // ABI encoded struct has at least:
        // - 6 static slots (6 * 32 = 192 bytes = 384 hex chars)
        // - Plus dynamic data (authenticatorData + clientDataJSON)
        expect(hex.length, greaterThan(384));

        // All characters should be valid hex
        expect(RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex), isTrue);
      });

      test('has correct static slot count', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // First 6 slots are:
        // 1. authDataOffset
        // 2. clientDataOffset
        // 3. responseTypeLocation
        // 4. r
        // 5. s
        // 6. usePrecompiled

        // authDataOffset should point past the static section (192 = 0xc0)
        final authDataOffset = hex.substring(0, 64);
        expect(
          BigInt.parse(authDataOffset, radix: 16),
          equals(BigInt.from(192)),
        );
      });

      test('has usePrecompiled set to true', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // usePrecompiled is in slot 6 (bytes 160-192)
        // Slots are 0-indexed at positions: 0, 64, 128, 192, 256, 320
        // Slot 5 (0-indexed) is at position 320-384
        final usePrecompiledHex = hex.substring(320, 384);

        expect(
          BigInt.parse(usePrecompiledHex, radix: 16),
          equals(BigInt.one),
        );
      });

      test('r value is max uint256', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // r is in slot 4 (bytes 96-128)
        // Slot 3 (0-indexed) is at position 192-256
        final rHex = hex.substring(192, 256);

        expect(rHex, equals('f' * 64));
      });

      test('s value is valid secp256r1 half-order', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // s is in slot 5 (bytes 128-160)
        // Slot 4 (0-indexed) is at position 256-320
        final sHex = hex.substring(256, 320);

        // Expected value from source: 7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0
        expect(
          sHex,
          equals(
              '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0'),
        );
      });

      test('contains valid authenticator data', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // AuthData starts at offset 192 (0xc0)
        // First 64 chars at that offset are the length
        final authDataStart = 192 * 2; // Convert bytes to hex chars
        final authDataLengthHex =
            hex.substring(authDataStart, authDataStart + 64);
        final authDataLength = BigInt.parse(authDataLengthHex, radix: 16);

        // Dummy authenticator data is 37 bytes
        expect(authDataLength, equals(BigInt.from(37)));
      });

      test('contains valid client data JSON', () {
        final sig = getDummyKernelWebAuthnSignature();
        final hex = sig.substring(2);

        // clientDataJSON offset is in slot 2
        final clientDataOffsetHex = hex.substring(64, 128);
        final clientDataOffset =
            BigInt.parse(clientDataOffsetHex, radix: 16).toInt();

        // Read length at that offset
        final clientDataLengthHex = hex.substring(
          clientDataOffset * 2,
          clientDataOffset * 2 + 64,
        );
        final clientDataLength =
            BigInt.parse(clientDataLengthHex, radix: 16).toInt();

        // Client data JSON should be reasonable length
        expect(clientDataLength, greaterThan(50));
        expect(clientDataLength, lessThan(500));
      });
    });

    group('signature format validation', () {
      test('signature is valid for gas estimation', () {
        final sig = getDummyKernelWebAuthnSignature();

        // For gas estimation, we need a signature that:
        // 1. Has valid ABI structure
        // 2. Has reasonable length
        // 3. Won't cause parsing errors

        expect(sig.length, greaterThan(100));
        expect(sig.startsWith('0x'), isTrue);

        // Should be even length (complete bytes)
        final hex = sig.substring(2);
        expect(hex.length % 2, equals(0));
      });

      test('signature byte length is consistent', () {
        final sig1 = getDummyKernelWebAuthnSignature();
        final sig2 = getDummyKernelWebAuthnSignature();

        expect(sig1.length, equals(sig2.length));
      });
    });
  });
}

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('appendPaymasterSignature', () {
    test('exposes the v0.9 magic value', () {
      expect(paymasterSignatureMagic, equals('0x22e325a297439656'));
    });

    test('appends signature size and magic suffix', () {
      final result = appendPaymasterSignature(
        paymasterData: '0x1122',
        paymasterSignature: '0xaabbcc',
      );

      expect(result, equals('0x1122aabbcc000322e325a297439656'));
    });

    test('encodes signature size as uint16', () {
      final signature = '0x${List.filled(256, '12').join()}';

      final result = appendPaymasterSignature(
        paymasterData: '0x',
        paymasterSignature: signature,
      );

      expect(
        result,
        equals('${signature}0100${paymasterSignatureMagic.substring(2)}'),
      );
    });

    test('preserves existing paymaster data before the suffix', () {
      final result = appendPaymasterSignature(
        paymasterData: '0xabcdef1234',
        paymasterSignature: '0x9876',
      );

      expect(result, startsWith('0xabcdef1234'));
      expect(result, equals('0xabcdef12349876000222e325a297439656'));
    });

    test('rejects empty signatures', () {
      expect(
        () => appendPaymasterSignature(
          paymasterData: '0x',
          paymasterSignature: '0x',
        ),
        throwsArgumentError,
      );
    });

    test('rejects signatures too large for uint16 encoding', () {
      final signature = '0x${List.filled(65536, '12').join()}';

      expect(
        () => appendPaymasterSignature(
          paymasterData: '0x',
          paymasterSignature: signature,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid hex input', () {
      expect(
        () => appendPaymasterSignature(
          paymasterData: '0xzz',
          paymasterSignature: '0x12',
        ),
        throwsArgumentError,
      );
      expect(
        () => appendPaymasterSignature(
          paymasterData: '0x',
          paymasterSignature: '0x123',
        ),
        throwsArgumentError,
      );
    });
  });
}

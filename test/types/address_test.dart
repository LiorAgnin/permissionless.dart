import 'package:permissionless/src/types/address.dart';
import 'package:test/test.dart';

void main() {
  group('EthAddress', () {
    group('creation', () {
      test('creates from valid lowercase address', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(addr.hex, equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'));
      });

      test('creates from valid mixed-case address', () {
        final addr = EthAddress('0xD8dA6BF26964aF9D7eEd9e03E53415D37aA96045');
        expect(addr.hex, equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'));
      });

      test('creates from address without 0x prefix', () {
        final addr = EthAddress('d8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(addr.hex, equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'));
      });

      test('throws on invalid address length', () {
        expect(
          () => EthAddress('0x1234'),
          throwsArgumentError,
        );
      });

      test('throws on invalid characters', () {
        expect(
          () => EthAddress('0xghijklmnopqrstuvwxyz1234567890123456'),
          throwsArgumentError,
        );
      });
    });

    group('zero address', () {
      test('creates zero address', () {
        expect(
          EthAddress.zero.hex,
          equals('0x0000000000000000000000000000000000000000'),
        );
      });

      test('isZero returns true for zero address', () {
        expect(EthAddress.zero.isZero, isTrue);
      });

      test('isZero returns false for non-zero address', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(addr.isZero, isFalse);
      });
    });

    group('checksummed', () {
      test('returns EIP-55 checksummed address', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(
          addr.checksummed,
          equals('0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045'),
        );
      });

      test('checksums zero address', () {
        expect(
          EthAddress.zero.checksummed,
          equals('0x0000000000000000000000000000000000000000'),
        );
      });
    });

    group('bytes', () {
      test('returns 20 bytes', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(addr.bytes.length, equals(20));
      });

      test('bytes are correct', () {
        final addr = EthAddress('0xff00000000000000000000000000000000000001');
        expect(addr.bytes.first, equals(0xff));
        expect(addr.bytes.last, equals(0x01));
      });
    });

    group('equality', () {
      test('equal addresses are equal', () {
        final addr1 = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        final addr2 = EthAddress('0xD8dA6BF26964aF9D7eEd9e03E53415D37aA96045');
        expect(addr1, equals(addr2));
      });

      test('different addresses are not equal', () {
        final addr1 = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        final addr2 = EthAddress('0x0000000000000000000000000000000000000001');
        expect(addr1, isNot(equals(addr2)));
      });

      test('equals string comparison', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        // ignore: unrelated_type_equality_checks
        expect(addr == '0xd8da6bf26964af9d7eed9e03e53415d37aa96045', isTrue);
      });
    });

    group('comparison', () {
      test('compares addresses numerically', () {
        final lower = EthAddress('0x0000000000000000000000000000000000000001');
        final higher = EthAddress('0x0000000000000000000000000000000000000002');
        expect(lower.compareTo(higher), lessThan(0));
        expect(higher.compareTo(lower), greaterThan(0));
      });

      test('equal addresses compare as 0', () {
        final addr1 = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        final addr2 = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        expect(addr1.compareTo(addr2), equals(0));
      });
    });

    group('toAbiEncoded', () {
      test('left-pads to 32 bytes', () {
        final addr = EthAddress('0xd8da6bf26964af9d7eed9e03e53415d37aa96045');
        final encoded = addr.toAbiEncoded();
        expect(encoded.length, equals(66)); // 0x + 64 hex chars
        expect(encoded.startsWith('0x000000000000000000000000'), isTrue);
      });
    });

    group('isValidAddress', () {
      test('validates correct address', () {
        expect(
          EthAddress.isValidAddress(
            '0xd8da6bf26964af9d7eed9e03e53415d37aa96045',
          ),
          isTrue,
        );
      });

      test('rejects short address', () {
        expect(EthAddress.isValidAddress('0x1234'), isFalse);
      });

      test('rejects invalid characters', () {
        expect(
          EthAddress.isValidAddress(
            '0xgggggggggggggggggggggggggggggggggggggggg',
          ),
          isFalse,
        );
      });
    });

    group('StringToAddress extension', () {
      test('converts string to address', () {
        final addr = '0xd8da6bf26964af9d7eed9e03e53415d37aa96045'.toAddress();
        expect(addr.hex, equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'));
      });
    });
  });
}

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('EthUnits', () {
    test('weiPerGwei is 10^9', () {
      expect(EthUnits.weiPerGwei, equals(BigInt.from(1000000000)));
    });

    test('weiPerEther is 10^18', () {
      expect(
        EthUnits.weiPerEther,
        equals(BigInt.parse('1000000000000000000')),
      );
    });

    test('gweiPerEther is 10^9', () {
      expect(EthUnits.gweiPerEther, equals(BigInt.from(1000000000)));
    });
  });

  group('GasUnits', () {
    group('gweiToWei', () {
      test('converts integer gwei to wei', () {
        expect(
          GasUnits.gweiToWei(50),
          equals(BigInt.from(50000000000)),
        );
      });

      test('converts decimal gwei to wei', () {
        expect(
          GasUnits.gweiToWei(1.5),
          equals(BigInt.from(1500000000)),
        );
      });

      test('converts zero', () {
        expect(GasUnits.gweiToWei(0), equals(BigInt.zero));
      });

      test('handles large values', () {
        expect(
          GasUnits.gweiToWei(1000),
          equals(BigInt.from(1000000000000)),
        );
      });
    });

    group('weiToGwei', () {
      test('converts wei to gwei', () {
        expect(
          GasUnits.weiToGwei(BigInt.from(50000000000)),
          equals(50.0),
        );
      });

      test('handles fractional gwei', () {
        expect(
          GasUnits.weiToGwei(BigInt.from(1500000000)),
          equals(1.5),
        );
      });

      test('converts zero', () {
        expect(GasUnits.weiToGwei(BigInt.zero), equals(0.0));
      });
    });

    group('etherToWei', () {
      test('converts integer ether to wei', () {
        expect(
          GasUnits.etherToWei(1),
          equals(BigInt.parse('1000000000000000000')),
        );
      });

      test('converts decimal ether to wei', () {
        expect(
          GasUnits.etherToWei(1.5),
          equals(BigInt.parse('1500000000000000000')),
        );
      });

      test('converts small fractions', () {
        expect(
          GasUnits.etherToWei(0.001),
          equals(BigInt.parse('1000000000000000')),
        );
      });

      test('converts zero', () {
        expect(GasUnits.etherToWei(0), equals(BigInt.zero));
      });
    });

    group('weiToEther', () {
      test('converts wei to ether', () {
        expect(
          GasUnits.weiToEther(BigInt.parse('1000000000000000000')),
          equals(1.0),
        );
      });

      test('handles fractional ether', () {
        expect(
          GasUnits.weiToEther(BigInt.parse('1500000000000000000')),
          equals(1.5),
        );
      });

      test('handles small amounts', () {
        expect(
          GasUnits.weiToEther(BigInt.parse('1000000000000000')),
          equals(0.001),
        );
      });
    });

    group('gweiToEther', () {
      test('converts gwei to ether', () {
        expect(
          GasUnits.gweiToEther(1000000000),
          equals(1.0),
        );
      });

      test('handles small gwei amounts', () {
        expect(
          GasUnits.gweiToEther(1000000),
          closeTo(0.001, 0.0000001),
        );
      });
    });

    group('etherToGwei', () {
      test('converts ether to gwei', () {
        expect(
          GasUnits.etherToGwei(1),
          equals(1000000000.0),
        );
      });

      test('handles fractional ether', () {
        expect(
          GasUnits.etherToGwei(0.001),
          equals(1000000.0),
        );
      });
    });

    group('parse', () {
      test('parses gwei with space', () {
        expect(
          GasUnits.parse('50 gwei'),
          equals(BigInt.from(50000000000)),
        );
      });

      test('parses gwei without space', () {
        expect(
          GasUnits.parse('50gwei'),
          equals(BigInt.from(50000000000)),
        );
      });

      test('parses gwei case-insensitive', () {
        expect(
          GasUnits.parse('50 Gwei'),
          equals(BigInt.from(50000000000)),
        );
      });

      test('parses decimal gwei', () {
        expect(
          GasUnits.parse('1.5 gwei'),
          equals(BigInt.from(1500000000)),
        );
      });

      test('parses eth', () {
        expect(
          GasUnits.parse('1.5 eth'),
          equals(BigInt.parse('1500000000000000000')),
        );
      });

      test('parses ether', () {
        expect(
          GasUnits.parse('2 ether'),
          equals(BigInt.parse('2000000000000000000')),
        );
      });

      test('parses wei (no unit)', () {
        expect(
          GasUnits.parse('1000'),
          equals(BigInt.from(1000)),
        );
      });

      test('parses explicit wei', () {
        expect(
          GasUnits.parse('1000 wei'),
          equals(BigInt.from(1000)),
        );
      });

      test('handles whitespace', () {
        expect(
          GasUnits.parse('  50 gwei  '),
          equals(BigInt.from(50000000000)),
        );
      });

      test('throws on invalid format', () {
        expect(
          () => GasUnits.parse('invalid'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws on unknown unit', () {
        expect(
          () => GasUnits.parse('50 foo'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('format', () {
      test('formats small values as wei', () {
        expect(
          GasUnits.format(BigInt.from(999)),
          equals('999 wei'),
        );
      });

      test('formats medium values as gwei', () {
        expect(
          GasUnits.format(BigInt.from(50000000000)),
          equals('50 gwei'),
        );
      });

      test('formats large values as ETH', () {
        expect(
          GasUnits.format(BigInt.parse('1500000000000000000')),
          equals('1.5 ETH'),
        );
      });

      test('formats with specified decimals', () {
        expect(
          GasUnits.format(BigInt.parse('1234567890000000000'), decimals: 2),
          equals('1.23 ETH'),
        );
      });

      test('removes trailing zeros', () {
        expect(
          GasUnits.format(BigInt.parse('1000000000000000000')),
          equals('1 ETH'),
        );
      });

      test('formats fractional gwei', () {
        expect(
          GasUnits.format(BigInt.from(1500000000)),
          equals('1.5 gwei'),
        );
      });
    });
  });
}

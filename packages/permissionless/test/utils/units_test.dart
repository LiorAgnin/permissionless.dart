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

    group('parse is exact (decimal string arithmetic, no double)', () {
      // Expected values: `cast to-wei <value> <unit>` (Foundry 1.5.1).
      test('0.1 eth (cast to-wei 0.1 ether)', () {
        expect(
          GasUnits.parse('0.1 eth'),
          equals(BigInt.parse('100000000000000000')),
        );
      });

      test('18 fractional digits (cast to-wei 1.123456789123456789 ether)', () {
        expect(
          GasUnits.parse('1.123456789123456789 eth'),
          equals(BigInt.parse('1123456789123456789')),
        );
      });

      test('integer part above 2^53 (cast to-wei 9007199254740993 ether)', () {
        expect(
          GasUnits.parse('9007199254740993 ether'),
          equals(BigInt.parse('9007199254740993000000000000000000')),
        );
      });

      test('wei above 2^53 (cast to-wei 9007199254740993 wei)', () {
        expect(
          GasUnits.parse('9007199254740993'),
          equals(BigInt.parse('9007199254740993')),
        );
      });

      test('ether above int64 range (cast to-wei 10 ether)', () {
        expect(
          GasUnits.parse('10 ether'),
          equals(BigInt.parse('10000000000000000000')),
        );
      });

      test('gwei with 9 fractional digits (cast to-wei 123.456789123 gwei)',
          () {
        expect(
          GasUnits.parse('123.456789123 gwei'),
          equals(BigInt.parse('123456789123')),
        );
      });

      test('leading dot (cast to-wei .5 ether)', () {
        expect(
          GasUnits.parse('.5 ether'),
          equals(BigInt.parse('500000000000000000')),
        );
      });

      // Sub-wei digits round half up, as viem parseUnits does:
      // parseUnits('1.0000000005', 9) === 1000000001n, parseUnits('1.5', 0)
      // === 2n (bun, viem/src/utils/unit/parseUnits.ts). cast truncates.
      test('sub-wei gwei digits round half up (viem parseUnits)', () {
        expect(
          GasUnits.parse('1.0000000005 gwei'),
          equals(BigInt.from(1000000001)),
        );
      });

      test('fractional wei rounds half up (viem parseUnits)', () {
        expect(GasUnits.parse('1.5 wei'), equals(BigInt.two));
      });

      test('rejects more than one decimal point', () {
        expect(
          () => GasUnits.parse('1.2.3 eth'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('num conversions are exact for the value as written', () {
      // Expected values: `cast to-wei <value> <unit>` (Foundry 1.5.1).
      test('etherToWei(0.1) (cast to-wei 0.1 ether)', () {
        expect(
          GasUnits.etherToWei(0.1),
          equals(BigInt.parse('100000000000000000')),
        );
      });

      test('etherToWei(10) above int64 range (cast to-wei 10 ether)', () {
        expect(
          GasUnits.etherToWei(10),
          equals(BigInt.parse('10000000000000000000')),
        );
      });

      test('etherToWei(1.123456789) (cast to-wei 1.123456789 ether)', () {
        expect(
          GasUnits.etherToWei(1.123456789),
          equals(BigInt.parse('1123456789000000000')),
        );
      });

      test('gweiToWei above int64 range (cast to-wei 10000000000 gwei)', () {
        expect(
          GasUnits.gweiToWei(10000000000),
          equals(BigInt.parse('10000000000000000000')),
        );
      });

      test('gweiToWei(1e-7) exponent form (cast to-wei 0.0000001 gwei)', () {
        expect(GasUnits.gweiToWei(1e-7), equals(BigInt.from(100)));
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

      // Exact digits: `cast from-wei <wei> [gwei]` (Foundry 1.5.1), then
      // rounded half up to `decimals` places.
      test(
          'ETH integer part above 2^53 (cast from-wei '
          '9007199254740993000000000000000000)', () {
        expect(
          GasUnits.format(BigInt.parse('9007199254740993000000000000000000')),
          equals('9007199254740993 ETH'),
        );
      });

      test(
          'ETH at or above 1e21 has no exponent '
          '(cast from-wei 1000000000000000000000000000000000000000)', () {
        expect(
          GasUnits.format(
            BigInt.parse('1000000000000000000000000000000000000000'),
          ),
          equals('1000000000000000000000 ETH'),
        );
      });

      test(
          'rounds on exact digits (cast from-wei 1000050000000000001 = '
          '1.000050000000000001)', () {
        expect(
          GasUnits.format(BigInt.parse('1000050000000000001')),
          equals('1.0001 ETH'),
        );
      });

      test('exact half rounds up (cast from-wei 1000050000 gwei = 1.00005)',
          () {
        expect(
          GasUnits.format(BigInt.from(1000050000)),
          equals('1.0001 gwei'),
        );
      });

      test(
          'decimals beyond the unit keep every digit '
          '(cast from-wei 1123456789123456789 = 1.123456789123456789)', () {
        expect(
          GasUnits.format(BigInt.parse('1123456789123456789'), decimals: 20),
          equals('1.123456789123456789 ETH'),
        );
      });
    });
  });
}

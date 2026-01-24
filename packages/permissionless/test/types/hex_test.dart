import 'dart:typed_data';

import 'package:permissionless/src/types/hex.dart';
import 'package:test/test.dart';

void main() {
  group('Hex', () {
    group('encode', () {
      test('encodes empty bytes', () {
        expect(Hex.encode([]), equals('0x'));
      });

      test('encodes single byte', () {
        expect(Hex.encode([0xff]), equals('0xff'));
      });

      test('encodes multiple bytes', () {
        expect(Hex.encode([0x12, 0x34, 0xab, 0xcd]), equals('0x1234abcd'));
      });
    });

    group('decode', () {
      test('decodes empty hex', () {
        expect(Hex.decode('0x'), equals(Uint8List(0)));
      });

      test('decodes hex with 0x prefix', () {
        expect(Hex.decode('0xff'), equals(Uint8List.fromList([0xff])));
      });

      test('decodes hex without 0x prefix', () {
        expect(Hex.decode('ff'), equals(Uint8List.fromList([0xff])));
      });

      test('decodes multi-byte hex', () {
        expect(
          Hex.decode('0x1234abcd'),
          equals(Uint8List.fromList([0x12, 0x34, 0xab, 0xcd])),
        );
      });

      test('pads odd-length hex', () {
        expect(Hex.decode('0xf'), equals(Uint8List.fromList([0x0f])));
      });
    });

    group('strip0x', () {
      test('strips 0x prefix', () {
        expect(Hex.strip0x('0xabcd'), equals('abcd'));
      });

      test('strips 0X prefix', () {
        expect(Hex.strip0x('0Xabcd'), equals('abcd'));
      });

      test('returns unchanged if no prefix', () {
        expect(Hex.strip0x('abcd'), equals('abcd'));
      });
    });

    group('add0x', () {
      test('adds 0x prefix', () {
        expect(Hex.add0x('abcd'), equals('0xabcd'));
      });

      test('does not double prefix', () {
        expect(Hex.add0x('0xabcd'), equals('0xabcd'));
      });
    });

    group('padLeft', () {
      test('pads to specified byte length', () {
        expect(Hex.padLeft('0xff', 4), equals('0x000000ff'));
      });

      test('does not truncate longer values', () {
        expect(Hex.padLeft('0xffffff', 2), equals('0xffffff'));
      });
    });

    group('padRight', () {
      test('pads to specified byte length', () {
        expect(Hex.padRight('0xff', 4), equals('0xff000000'));
      });
    });

    group('concat', () {
      test('concatenates empty list', () {
        expect(Hex.concat([]), equals('0x'));
      });

      test('concatenates single element', () {
        expect(Hex.concat(['0xabcd']), equals('0xabcd'));
      });

      test('concatenates multiple elements', () {
        expect(Hex.concat(['0x12', '0x34', '0xab']), equals('0x1234ab'));
      });

      test('handles mixed prefixes', () {
        expect(Hex.concat(['0x12', '34', '0xab']), equals('0x1234ab'));
      });
    });

    group('byteLength', () {
      test('returns 0 for empty', () {
        expect(Hex.byteLength('0x'), equals(0));
      });

      test('returns correct length', () {
        expect(Hex.byteLength('0x1234abcd'), equals(4));
      });
    });

    group('slice', () {
      test('slices from start', () {
        expect(Hex.slice('0x1234abcd', 0, 2), equals('0x1234'));
      });

      test('slices middle', () {
        expect(Hex.slice('0x1234abcd', 1, 3), equals('0x34ab'));
      });

      test('slices to end', () {
        expect(Hex.slice('0x1234abcd', 2), equals('0xabcd'));
      });
    });

    group('BigInt conversion', () {
      test('fromBigInt without length', () {
        expect(Hex.fromBigInt(BigInt.from(255)), equals('0xff'));
      });

      test('fromBigInt with length', () {
        expect(
          Hex.fromBigInt(BigInt.from(255), byteLength: 4),
          equals('0x000000ff'),
        );
      });

      test('toBigInt', () {
        expect(Hex.toBigInt('0xff'), equals(BigInt.from(255)));
      });

      test('toBigInt empty', () {
        expect(Hex.toBigInt('0x'), equals(BigInt.zero));
      });

      test('toBigInt large number', () {
        expect(
          Hex.toBigInt(
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          ),
          equals(BigInt.two.pow(256) - BigInt.one),
        );
      });
    });

    group('isValid', () {
      test('empty is valid', () {
        expect(Hex.isValid('0x'), isTrue);
      });

      test('valid hex is valid', () {
        expect(Hex.isValid('0x1234abcd'), isTrue);
      });

      test('invalid chars are invalid', () {
        expect(Hex.isValid('0xghij'), isFalse);
      });
    });
  });
}

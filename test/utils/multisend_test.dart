import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('MultiSend', () {
    group('encodeMultiSend', () {
      test('encodes single call', () {
        final calls = [
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            value: BigInt.from(1000),
            data: '0x',
          ),
        ];

        final encoded = encodeMultiSend(calls);
        expect(encoded.startsWith('0x'), isTrue);
        // Should start with multiSend selector
        expect(encoded.substring(0, 10).toLowerCase(), equals('0x8d80ff0a'));
      });

      test('encodes multiple calls', () {
        final calls = [
          Call(
            to: EthAddress('0x1111111111111111111111111111111111111111'),
            value: BigInt.from(1000),
            data: '0x',
          ),
          Call(
            to: EthAddress('0x2222222222222222222222222222222222222222'),
            value: BigInt.from(2000),
            data: '0xabcd',
          ),
        ];

        final encoded = encodeMultiSend(calls);
        expect(encoded.startsWith('0x'), isTrue);
      });

      test('throws on empty calls', () {
        expect(
          () => encodeMultiSend([]),
          throwsArgumentError,
        );
      });

      test('handles call with data', () {
        final calls = [
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            value: BigInt.zero,
            data: '0xa9059cbb', // transfer selector
          ),
        ];

        final encoded = encodeMultiSend(calls);
        expect(encoded.contains('a9059cbb'), isTrue);
      });
    });

    group('decodeMultiSend', () {
      test('round-trips single call', () {
        final originalCalls = [
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            value: BigInt.from(1000),
            data: '0x',
          ),
        ];

        final encoded = encodeMultiSend(originalCalls);
        final decoded = decodeMultiSend(encoded);

        expect(decoded.length, equals(1));
        expect(decoded[0].to.hex, equals(originalCalls[0].to.hex));
        expect(decoded[0].value, equals(originalCalls[0].value));
      });

      test('round-trips multiple calls', () {
        final originalCalls = [
          Call(
            to: EthAddress('0x1111111111111111111111111111111111111111'),
            value: BigInt.from(1000),
            data: '0x',
          ),
          Call(
            to: EthAddress('0x2222222222222222222222222222222222222222'),
            value: BigInt.from(2000),
            data: '0xabcdef',
          ),
        ];

        final encoded = encodeMultiSend(originalCalls);
        final decoded = decodeMultiSend(encoded);

        expect(decoded.length, equals(2));
        expect(decoded[0].to.hex, equals(originalCalls[0].to.hex));
        expect(decoded[0].value, equals(originalCalls[0].value));
        expect(decoded[1].to.hex, equals(originalCalls[1].to.hex));
        expect(decoded[1].value, equals(originalCalls[1].value));
        expect(decoded[1].data.toLowerCase(), equals('0xabcdef'));
      });

      test('preserves large values', () {
        final originalCalls = [
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            value: BigInt.parse('1000000000000000000'), // 1 ETH
            data: '0x',
          ),
        ];

        final encoded = encodeMultiSend(originalCalls);
        final decoded = decodeMultiSend(encoded);

        expect(decoded[0].value, equals(BigInt.parse('1000000000000000000')));
      });
    });
  });
}

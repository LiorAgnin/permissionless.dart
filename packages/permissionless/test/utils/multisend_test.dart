import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('MultiSend', () {
    group('encodeMultiSend', () {
      // Each transaction is packed as (uint8 operation, address to,
      // uint256 value, uint256 dataLength, bytes data):
      //   TX=$(cast abi-encode --packed \
      //     'f(uint8,address,uint256,uint256,bytes)' <op> <to> <value> <len> <data>)
      //   cast calldata 'multiSend(bytes)' <TX1><TX2>
      test('packs every call into multiSend(bytes)', () {
        final encoded = encodeMultiSend([
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.from(1000),
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(2000),
            data: '0xabcd',
          ),
        ]);

        expect(
          encoded,
          equals(
            '0x8d80ff0a'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '00000000000000000000000000000000000000000000000000000000000000ac'
            '00'
            '1111111111111111111111111111111111111111'
            '00000000000000000000000000000000000000000000000000000000000003e8'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '00'
            '2222222222222222222222222222222222222222'
            '00000000000000000000000000000000000000000000000000000000000007d0'
            '0000000000000000000000000000000000000000000000000000000000000002'
            'abcd'
            '0000000000000000000000000000000000000000',
          ),
        );
      });

      test('writes operation byte 1 for delegatecall', () {
        final encoded = encodeMultiSend(
          [
            Call(
              to: EthereumAddress.fromHex(
                '0x2222222222222222222222222222222222222222',
              ),
              data: '0xabcd',
            ),
          ],
          defaultOperation: OperationType.delegateCall,
        );

        expect(
          encoded,
          equals(
            '0x8d80ff0a'
            '0000000000000000000000000000000000000000000000000000000000000020'
            '0000000000000000000000000000000000000000000000000000000000000057'
            '01'
            '2222222222222222222222222222222222222222'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000002'
            'abcd000000000000000000',
          ),
        );
      });

      test('throws on empty calls', () {
        expect(
          () => encodeMultiSend([]),
          throwsArgumentError,
        );
      });
    });

    group('decodeMultiSend', () {
      test('round-trips single call', () {
        final originalCalls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
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
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.from(1000),
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
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
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
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

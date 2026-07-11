import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Fixtures generated with viem `encodeFunctionData` (permissionless.js peer).
/// Acceptance for parity-audit issue 011.
void main() {
  group('AbiEncoder.encodeFunctionData', () {
    test('static params: transfer(address,uint256)', () {
      final encoded = AbiEncoder.encodeFunctionData(
        'transfer(address,uint256)',
        [
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890'),
          BigInt.from(1000),
        ],
      );
      expect(
        encoded,
        equals(
          '0xa9059cbb'
          '0000000000000000000000001234567890123456789012345678901234567890'
          '00000000000000000000000000000000000000000000000000000000000003e8',
        ),
      );
    });

    test('no args: increment()', () {
      expect(
        AbiEncoder.encodeFunctionData('increment()'),
        equals('0xd09de08a'),
      );
    });

    test('static bool', () {
      expect(
        AbiEncoder.encodeFunctionData('setFlag(bool)', [true]),
        equals(
          '0x3927f6af'
          '0000000000000000000000000000000000000000000000000000000000000001',
        ),
      );
    });

    test('bytes32', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'setHash(bytes32)',
          [
            '0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
          ],
        ),
        equals(
          '0x0c4c4285'
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        ),
      );
    });

    test('dynamic bytes alone includes offset head', () {
      expect(
        AbiEncoder.encodeFunctionData('setData(bytes)', ['0xdeadbeef']),
        equals(
          '0xab62f0e1'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000004'
          'deadbeef00000000000000000000000000000000000000000000000000000000',
        ),
      );
    });

    test('execute(address,uint256,bytes) offsets dynamic bytes correctly', () {
      // Critical bug case: previously inlined bytes tail with no offset.
      expect(
        AbiEncoder.encodeFunctionData(
          'execute(address,uint256,bytes)',
          [
            EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            BigInt.zero,
            '0xabcdef',
          ],
        ),
        equals(
          '0xb61d27f6'
          '0000000000000000000000001234567890123456789012345678901234567890'
          '0000000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000060'
          '0000000000000000000000000000000000000000000000000000000000000003'
          'abcdef0000000000000000000000000000000000000000000000000000000000',
        ),
      );
    });

    test('empty bytes', () {
      expect(
        AbiEncoder.encodeFunctionData('setData(bytes)', ['0x']),
        equals(
          '0xab62f0e1'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000000',
        ),
      );
    });

    test('string', () {
      expect(
        AbiEncoder.encodeFunctionData('setName(string)', ['hello']),
        equals(
          '0xc47f0027'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000005'
          '68656c6c6f000000000000000000000000000000000000000000000000000000',
        ),
      );
    });

    test('dynamic uint256[]', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'setValues(uint256[])',
          [
            [BigInt.one, BigInt.two, BigInt.from(3)],
          ],
        ),
        equals(
          '0x6da2c5d0'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000003'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000003',
        ),
      );
    });

    test('address[]', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'setOwners(address[])',
          [
            [
              EthereumAddress.fromHex(
                '0x1111111111111111111111111111111111111111',
              ),
              EthereumAddress.fromHex(
                '0x2222222222222222222222222222222222222222',
              ),
            ],
          ],
        ),
        equals(
          '0xfa4d3698'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000001111111111111111111111111111111111111111'
          '0000000000000000000000002222222222222222222222222222222222222222',
        ),
      );
    });

    test('fixed-length array uint256[2]', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'setPair(uint256[2])',
          [
            [BigInt.from(10), BigInt.from(20)],
          ],
        ),
        equals(
          '0x4df6a9b1'
          '000000000000000000000000000000000000000000000000000000000000000a'
          '0000000000000000000000000000000000000000000000000000000000000014',
        ),
      );
    });

    test('tuple (uint256,uint256)', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'setPoint((uint256,uint256))',
          [
            [BigInt.one, BigInt.two],
          ],
        ),
        equals(
          '0xc81a8916'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000002',
        ),
      );
    });

    test('mixed static + dynamic params', () {
      expect(
        AbiEncoder.encodeFunctionData(
          'multi(address,bytes,string,uint256)',
          [
            EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            '0xdead',
            'hi',
            BigInt.from(42),
          ],
        ),
        equals(
          '0x264a3c4b'
          '0000000000000000000000001234567890123456789012345678901234567890'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '00000000000000000000000000000000000000000000000000000000000000c0'
          '000000000000000000000000000000000000000000000000000000000000002a'
          '0000000000000000000000000000000000000000000000000000000000000002'
          'dead000000000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '6869000000000000000000000000000000000000000000000000000000000000',
        ),
      );
    });

    test('nested tuple with dynamic components', () {
      // Solidity: f(S memory s, T memory t, uint a)
      // S { uint a; uint[] b; T[] c; } T { uint x; uint y; }
      expect(
        AbiEncoder.encodeFunctionData(
          'f((uint256,uint256[],(uint256,uint256)[]),(uint256,uint256),uint256)',
          [
            [
              BigInt.one,
              [BigInt.two, BigInt.from(3)],
              [
                [BigInt.from(4), BigInt.from(5)],
                [BigInt.from(6), BigInt.from(7)],
              ],
            ],
            [BigInt.from(8), BigInt.from(9)],
            BigInt.from(10),
          ],
        ),
        equals(
          '0x6f2be728'
          '0000000000000000000000000000000000000000000000000000000000000080'
          '0000000000000000000000000000000000000000000000000000000000000008'
          '0000000000000000000000000000000000000000000000000000000000000009'
          '000000000000000000000000000000000000000000000000000000000000000a'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '0000000000000000000000000000000000000000000000000000000000000060'
          '00000000000000000000000000000000000000000000000000000000000000c0'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000003'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000004'
          '0000000000000000000000000000000000000000000000000000000000000005'
          '0000000000000000000000000000000000000000000000000000000000000006'
          '0000000000000000000000000000000000000000000000000000000000000007',
        ),
      );
    });

    test('accepts hex string addresses and Uint8List bytes', () {
      final encoded = AbiEncoder.encodeFunctionData(
        'execute(address,uint256,bytes)',
        [
          '0x1234567890123456789012345678901234567890',
          0,
          Uint8List.fromList([0xab, 0xcd, 0xef]),
        ],
      );
      expect(
        encoded,
        equals(
          AbiEncoder.encodeFunctionData(
            'execute(address,uint256,bytes)',
            [
              EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              BigInt.zero,
              '0xabcdef',
            ],
          ),
        ),
      );
    });

    test('throws on invalid signature', () {
      expect(
        () => AbiEncoder.encodeFunctionData('notAFunction'),
        throwsArgumentError,
      );
    });

    test('throws on arg count mismatch', () {
      expect(
        () => AbiEncoder.encodeFunctionData('setFlag(bool)'),
        throwsArgumentError,
      );
    });

    test('dataSuffix appends after encoded calldata (writeContract parity)',
        () {
      // Mirrors JS: `${data}${dataSuffix.replace("0x", "")}`
      final data = AbiEncoder.encodeFunctionData('increment()');
      final withSuffix = Hex.concat([data, '0xdeadbeef']);
      expect(withSuffix, equals('0xd09de08adeadbeef'));
    });

    test('throws on bytes32 size mismatch', () {
      expect(
        () => AbiEncoder.encodeFunctionData(
          'setHash(bytes32)',
          ['0xdeadbeef'],
        ),
        throwsArgumentError,
      );
      expect(
        () => AbiEncoder.encodeFunctionData(
          'setHash(bytes32)',
          [
            '0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789ff',
          ],
        ),
        throwsArgumentError,
      );
    });

    test('throws on fixed array length mismatch', () {
      expect(
        () => AbiEncoder.encodeFunctionData(
          'setPair(uint256[2])',
          [
            [BigInt.one],
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => AbiEncoder.encodeFunctionData(
          'setPair(uint256[2])',
          [
            [BigInt.one, BigInt.two, BigInt.from(3)],
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}

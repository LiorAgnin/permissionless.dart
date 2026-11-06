import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('hashMessage (EIP-191)', () {
    test('hashes empty string', () {
      final hash = hashMessage('');
      // Empty string: keccak256("\x19Ethereum Signed Message:\n0")
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66)); // 32 bytes as hex + 0x
    });

    test('hashes simple message', () {
      final hash = hashMessage('hello');
      // Known hash for "hello" with EIP-191 prefix
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('hashes "Hello, World!"', () {
      // Verified hash using keccak256("\x19Ethereum Signed Message:\n13Hello, World!")
      final hash = hashMessage('Hello, World!');
      expect(
        hash.toLowerCase(),
        equals(
          '0xc8ee0d506e864589b799a645ddb88b08f5d39e8049f9f702b3b61fa15e55fc73',
        ),
      );
    });

    test('different messages produce different hashes', () {
      final hash1 = hashMessage('message1');
      final hash2 = hashMessage('message2');
      expect(hash1, isNot(equals(hash2)));
    });

    test('same message produces same hash', () {
      final hash1 = hashMessage('consistent');
      final hash2 = hashMessage('consistent');
      expect(hash1, equals(hash2));
    });

    test('handles unicode characters', () {
      final hash = hashMessage('Hello 🌍!');
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('handles long messages', () {
      final longMessage = 'a' * 1000;
      final hash = hashMessage(longMessage);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });
  });

  group('hashTypedData (EIP-712)', () {
    test('hashes simple typed data', () {
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Test App',
          version: '1',
          chainId: BigInt.from(1),
        ),
        types: {
          'Message': [
            const TypedDataField(name: 'content', type: 'string'),
          ],
        },
        primaryType: 'Message',
        message: {'content': 'Hello'},
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('hashes EIP-712 with verifyingContract', () {
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Test Contract',
          version: '1',
          chainId: BigInt.from(1),
          verifyingContract: EthereumAddress.fromHex(
            '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
          ),
        ),
        types: {
          'Transfer': [
            const TypedDataField(name: 'to', type: 'address'),
            const TypedDataField(name: 'amount', type: 'uint256'),
          ],
        },
        primaryType: 'Transfer',
        message: {
          'to': '0x1234567890123456789012345678901234567890',
          'amount': BigInt.from(1000000),
        },
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('handles nested structs', () {
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Nested Test',
          version: '1',
          chainId: BigInt.from(1),
        ),
        types: {
          'Person': [
            const TypedDataField(name: 'name', type: 'string'),
            const TypedDataField(name: 'wallet', type: 'address'),
          ],
          'Mail': [
            const TypedDataField(name: 'from', type: 'Person'),
            const TypedDataField(name: 'to', type: 'Person'),
            const TypedDataField(name: 'contents', type: 'string'),
          ],
        },
        primaryType: 'Mail',
        message: {
          'from': {
            'name': 'Alice',
            'wallet': '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
          },
          'to': {
            'name': 'Bob',
            'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
          },
          'contents': 'Hello, Bob!',
        },
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('handles array types', () {
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Array Test',
          version: '1',
          chainId: BigInt.from(1),
        ),
        types: {
          'Batch': [
            const TypedDataField(name: 'recipients', type: 'address[]'),
            const TypedDataField(name: 'amounts', type: 'uint256[]'),
          ],
        },
        primaryType: 'Batch',
        message: {
          'recipients': [
            '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
            '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
          ],
          'amounts': [BigInt.from(100), BigInt.from(200)],
        },
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('handles bool type', () {
      const typedData = TypedData(
        domain: TypedDataDomain(name: 'Bool Test', version: '1'),
        types: {
          'Toggle': [
            TypedDataField(name: 'enabled', type: 'bool'),
          ],
        },
        primaryType: 'Toggle',
        message: {'enabled': true},
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('handles bytes32 type', () {
      const typedData = TypedData(
        domain: TypedDataDomain(name: 'Bytes Test', version: '1'),
        types: {
          'Hash': [
            TypedDataField(name: 'value', type: 'bytes32'),
          ],
        },
        primaryType: 'Hash',
        message: {
          'value':
              '0x0000000000000000000000000000000000000000000000000000000000000001',
        },
      );

      final hash = hashTypedData(typedData);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('different data produces different hashes', () {
      const typedData1 = TypedData(
        domain: TypedDataDomain(name: 'Test', version: '1'),
        types: {
          'Message': [TypedDataField(name: 'text', type: 'string')],
        },
        primaryType: 'Message',
        message: {'text': 'hello'},
      );

      const typedData2 = TypedData(
        domain: TypedDataDomain(name: 'Test', version: '1'),
        types: {
          'Message': [TypedDataField(name: 'text', type: 'string')],
        },
        primaryType: 'Message',
        message: {'text': 'world'},
      );

      final hash1 = hashTypedData(typedData1);
      final hash2 = hashTypedData(typedData2);
      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('computeDomainSeparator', () {
    test('computes domain with all fields', () {
      final domain = TypedDataDomain(
        name: 'Test App',
        version: '1',
        chainId: BigInt.from(1),
        verifyingContract: EthereumAddress.fromHex(
          '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
        ),
        salt:
            '0x0000000000000000000000000000000000000000000000000000000000000001',
      );

      final separator = computeDomainSeparator(domain);
      expect(separator, startsWith('0x'));
      expect(separator.length, equals(66));
    });

    test('computes domain with minimal fields', () {
      const domain = TypedDataDomain(name: 'Minimal');

      final separator = computeDomainSeparator(domain);
      expect(separator, startsWith('0x'));
      expect(separator.length, equals(66));
    });

    test('different domains produce different separators', () {
      const domain1 = TypedDataDomain(name: 'App1', version: '1');
      const domain2 = TypedDataDomain(name: 'App2', version: '1');

      final sep1 = computeDomainSeparator(domain1);
      final sep2 = computeDomainSeparator(domain2);
      expect(sep1, isNot(equals(sep2)));
    });

    test('same domain produces same separator', () {
      final domain1 = TypedDataDomain(
        name: 'Test',
        version: '1',
        chainId: BigInt.from(1),
      );
      final domain2 = TypedDataDomain(
        name: 'Test',
        version: '1',
        chainId: BigInt.from(1),
      );

      final sep1 = computeDomainSeparator(domain1);
      final sep2 = computeDomainSeparator(domain2);
      expect(sep1, equals(sep2));
    });
  });

  group('hashStruct', () {
    test('hashes simple struct', () {
      final types = {
        'Simple': [
          const TypedDataField(name: 'value', type: 'uint256'),
        ],
      };

      final hash = hashStruct('Simple', {'value': BigInt.from(42)}, types);
      expect(hash, startsWith('0x'));
      expect(hash.length, equals(66));
    });

    test('throws for unknown type', () {
      expect(
        () => hashStruct('Unknown', {}, {}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // Expected values come from viem 2.21.55 (hashDomain / hashStruct /
  // hashTypedData), not from this package:
  //   /Users/liorag/.claude/jobs/037f9518/tmp/a/viem/vectors.ts
  //   cd /Users/liorag/.claude/jobs/037f9518/tmp/a/viem && bun run vectors.ts
  // The Dart inputs deliberately mix the accepted input forms (int, BigInt,
  // decimal and 0x strings, EthereumAddress and hex strings) that viem
  // receives as number/bigint/hex.
  group('viem vectors', () {
    void expectVector(
      TypedData typedData, {
      required String domainSeparator,
      required String structHash,
      required String hash,
    }) {
      expect(computeDomainSeparator(typedData.domain), domainSeparator);
      expect(
        hashStruct(typedData.primaryType, typedData.message, typedData.types),
        structHash,
      );
      expect(hashTypedData(typedData), hash);
    }

    test('canonical Ether Mail example', () {
      expectVector(
        TypedData(
          domain: TypedDataDomain(
            name: 'Ether Mail',
            version: '1',
            chainId: BigInt.one,
            verifyingContract: EthereumAddress.fromHex(
              '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
            ),
          ),
          types: const {
            'Person': [
              TypedDataField(name: 'name', type: 'string'),
              TypedDataField(name: 'wallet', type: 'address'),
            ],
            'Mail': [
              TypedDataField(name: 'from', type: 'Person'),
              TypedDataField(name: 'to', type: 'Person'),
              TypedDataField(name: 'contents', type: 'string'),
            ],
          },
          primaryType: 'Mail',
          message: {
            'from': {
              'name': 'Cow',
              'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
            },
            'to': {
              'name': 'Bob',
              'wallet': EthereumAddress.fromHex(
                '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
              ),
            },
            'contents': 'Hello, Bob!',
          },
        ),
        domainSeparator:
            '0xf2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f',
        structHash:
            '0xc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e',
        hash:
            '0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2',
      );
    });

    test('every atomic type, dynamic types, arrays and nested struct array',
        () {
      expectVector(
        TypedData(
          domain: TypedDataDomain(
            name: 'Kitchen Sink',
            version: '2',
            chainId: BigInt.from(11155111),
            verifyingContract: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
          ),
          types: const {
            'Inner': [
              TypedDataField(name: 'id', type: 'uint64'),
              TypedDataField(name: 'tag', type: 'bytes4'),
            ],
            'Kitchen': [
              TypedDataField(name: 'small', type: 'uint8'),
              TypedDataField(name: 'big', type: 'uint64'),
              TypedDataField(name: 'neg8', type: 'int8'),
              TypedDataField(name: 'neg256', type: 'int256'),
              TypedDataField(name: 'flag', type: 'bool'),
              TypedDataField(name: 'selector', type: 'bytes4'),
              TypedDataField(name: 'digest', type: 'bytes32'),
              TypedDataField(name: 'data', type: 'bytes'),
              TypedDataField(name: 'text', type: 'string'),
              TypedDataField(name: 'owners', type: 'address[]'),
              TypedDataField(name: 'inners', type: 'Inner[]'),
            ],
          },
          primaryType: 'Kitchen',
          message: {
            'small': 255,
            'big': '18446744073709551615',
            'neg8': -128,
            'neg256': BigInt.parse('-123456789012345678901234567890'),
            'flag': true,
            'selector': '0xdeadbeef',
            'digest':
                '0xabababababababababababababababababababababababababababababababab',
            'data': '0x0102030405',
            'text': 'héllo 🌍',
            'owners': [
              EthereumAddress.fromHex(
                '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
              ),
              '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
            ],
            'inners': [
              {'id': BigInt.one, 'tag': '0x01020304'},
              {'id': '0x8000000000000000', 'tag': '0xffffffff'},
            ],
          },
        ),
        domainSeparator:
            '0xce11dcab0d188872a846afd0684d9b38546a3f4ad17178c19802d98ad15f42d6',
        structHash:
            '0xd0e58d90139b5847679703273b8ad9396a100870b3c7fa9fd68e9a8eefcf032a',
        hash:
            '0xc4688b7898bc1a276cd08c79c6f237f9dcecb556db2d38ac29a0165721224d1b',
      );
    });

    test('domain with salt', () {
      expectVector(
        TypedData(
          domain: TypedDataDomain(
            name: 'Salted',
            version: '1',
            chainId: BigInt.from(137),
            verifyingContract: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            salt:
                '0xf2d857f4a3edcb9b78b4d503bfe733db1e3f6cdc2b7971ee739626c97e86a558',
          ),
          types: const {
            'Ping': [TypedDataField(name: 'nonce', type: 'uint256')],
          },
          primaryType: 'Ping',
          message: {'nonce': 7},
        ),
        domainSeparator:
            '0x41ee8ced8f0fd291d6684c3257ac7bda003f6fab97e903f2b446402f879d805c',
        structHash:
            '0x62776b5705f49cd0dbd4998bffa456f4c1d25510851a08354308ca9941427485',
        hash:
            '0x5e776615ee2eae7ba87ac9bc6655cc6e460c6881d567e865922da3359f275379',
      );
    });
  });

  // viem throws IntegerOutOfRangeError / BytesSizeMismatchError for these;
  // no contract could verify a signature over such a value.
  group('rejects values that do not fit the field type', () {
    String hashSingle(String type, Object value) => hashStruct(
          'M',
          {'v': value},
          {
            'M': [TypedDataField(name: 'v', type: type)],
          },
        );

    for (final (type, value) in [
      ('uint8', 256),
      ('uint8', -1),
      ('int8', 128),
      ('int8', -129),
      ('uint64', '18446744073709551616'),
      ('int256', BigInt.one << 255),
    ]) {
      test('$type = $value', () {
        expect(() => hashSingle(type, value), throwsArgumentError);
      });
    }

    test('bytes4 given 5 bytes', () {
      expect(() => hashSingle('bytes4', '0x0102030405'), throwsArgumentError);
    });

    test('rejects integer widths Solidity does not have', () {
      expect(() => hashSingle('uint7', 1), throwsArgumentError);
      expect(() => hashSingle('int264', 1), throwsArgumentError);
    });

    test('accepts the boundaries', () {
      expect(hashSingle('uint8', 255), isNotEmpty);
      expect(hashSingle('int8', -128), isNotEmpty);
      expect(hashSingle('int8', 127), isNotEmpty);
    });

    test('keeps right-padding bytesN values shorter than N', () {
      expect(
        hashSingle('bytes32', '0x1234'),
        hashSingle('bytes32', '0x1234${'00' * 30}'),
      );
    });
  });
}

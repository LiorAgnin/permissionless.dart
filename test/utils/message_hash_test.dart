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
}

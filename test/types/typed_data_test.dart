import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('TypedDataDomain', () {
    test('creates with all fields', () {
      final domain = TypedDataDomain(
        name: 'Test App',
        version: '1.0.0',
        chainId: BigInt.from(1),
        verifyingContract:
            EthAddress('0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC'),
        salt:
            '0x0000000000000000000000000000000000000000000000000000000000000001',
      );

      expect(domain.name, equals('Test App'));
      expect(domain.version, equals('1.0.0'));
      expect(domain.chainId, equals(BigInt.one));
      expect(
        domain.verifyingContract?.hex.toLowerCase(),
        equals('0xcccccccccccccccccccccccccccccccccccccccc'),
      );
      expect(
        domain.salt,
        equals(
          '0x0000000000000000000000000000000000000000000000000000000000000001',
        ),
      );
    });

    test('creates with minimal fields', () {
      const domain = TypedDataDomain();

      expect(domain.name, isNull);
      expect(domain.version, isNull);
      expect(domain.chainId, isNull);
      expect(domain.verifyingContract, isNull);
      expect(domain.salt, isNull);
    });

    test('creates with only name', () {
      const domain = TypedDataDomain(name: 'Only Name');

      expect(domain.name, equals('Only Name'));
      expect(domain.version, isNull);
    });

    test('handles large chain IDs', () {
      final domain = TypedDataDomain(
        chainId: BigInt.from(137), // Polygon
      );

      expect(domain.chainId, equals(BigInt.from(137)));
    });
  });

  group('TypedDataField', () {
    test('creates with name and type', () {
      const field = TypedDataField(name: 'amount', type: 'uint256');

      expect(field.name, equals('amount'));
      expect(field.type, equals('uint256'));
    });

    test('handles address type', () {
      const field = TypedDataField(name: 'recipient', type: 'address');

      expect(field.name, equals('recipient'));
      expect(field.type, equals('address'));
    });

    test('handles array types', () {
      const field = TypedDataField(name: 'values', type: 'uint256[]');

      expect(field.name, equals('values'));
      expect(field.type, equals('uint256[]'));
    });

    test('handles custom struct types', () {
      const field = TypedDataField(name: 'person', type: 'Person');

      expect(field.name, equals('person'));
      expect(field.type, equals('Person'));
    });
  });

  group('TypedData', () {
    test('creates complete typed data structure', () {
      final typedData = TypedData(
        domain: const TypedDataDomain(name: 'Test', version: '1'),
        types: {
          'Message': [
            const TypedDataField(name: 'content', type: 'string'),
            const TypedDataField(name: 'timestamp', type: 'uint256'),
          ],
        },
        primaryType: 'Message',
        message: {
          'content': 'Hello, World!',
          'timestamp': BigInt.from(1234567890),
        },
      );

      expect(typedData.domain.name, equals('Test'));
      expect(typedData.types.containsKey('Message'), isTrue);
      expect(typedData.types['Message']?.length, equals(2));
      expect(typedData.primaryType, equals('Message'));
      expect(typedData.message['content'], equals('Hello, World!'));
    });

    test('creates EIP-712 permit structure', () {
      // Standard ERC-20 permit structure
      final typedData = TypedData(
        domain: TypedDataDomain(
          name: 'Test Token',
          version: '1',
          chainId: BigInt.from(1),
          verifyingContract:
              EthAddress('0x6B175474E89094C44Da98b954eedeAC495271d0F'),
        ),
        types: {
          'Permit': [
            const TypedDataField(name: 'owner', type: 'address'),
            const TypedDataField(name: 'spender', type: 'address'),
            const TypedDataField(name: 'value', type: 'uint256'),
            const TypedDataField(name: 'nonce', type: 'uint256'),
            const TypedDataField(name: 'deadline', type: 'uint256'),
          ],
        },
        primaryType: 'Permit',
        message: {
          'owner': '0x1234567890123456789012345678901234567890',
          'spender': '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
          'value': BigInt.from(1000000000000000000),
          'nonce': BigInt.zero,
          'deadline': BigInt.from(1893456000),
        },
      );

      expect(typedData.primaryType, equals('Permit'));
      expect(typedData.types['Permit']?.length, equals(5));
    });

    test('creates nested struct structure', () {
      const typedData = TypedData(
        domain: TypedDataDomain(name: 'Mail', version: '1'),
        types: {
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
            'name': 'Alice',
            'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
          },
          'to': {
            'name': 'Bob',
            'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
          },
          'contents': 'Hello!',
        },
      );

      expect(typedData.types.containsKey('Person'), isTrue);
      expect(typedData.types.containsKey('Mail'), isTrue);
      expect(typedData.message['from'], isA<Map<String, dynamic>>());
    });

    test('handles empty types map', () {
      // This is technically invalid but should not throw during construction
      const typedData = TypedData(
        domain: TypedDataDomain(name: 'Empty'),
        types: {},
        primaryType: 'Empty',
        message: {},
      );

      expect(typedData.types, isEmpty);
    });
  });
}

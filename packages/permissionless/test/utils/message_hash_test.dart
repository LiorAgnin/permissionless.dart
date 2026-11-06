import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Expected values from Foundry 1.5.1 `cast hash-message '<message>'`, matched
  // by viem 2.21.55 hashMessage:
  //   /Users/liorag/.claude/jobs/037f9518/tmp/t1/viem/message_hash.ts
  // 'a' * 1000 has a multi-digit length prefix ("\n1000").
  group('hashMessage (EIP-191)', () {
    for (final (label, message, hash) in [
      (
        'empty string',
        '',
        '0x5f35dce98ba4fba25530a026ed80b2cecdaa31091ba4958b99b52ea1d068adad',
      ),
      (
        'hello',
        'hello',
        '0x50b2c43fd39106bafbba0da34fc430e1f91e3c96ea2acee2bc34119f92b37750',
      ),
      (
        'Hello, World!',
        'Hello, World!',
        '0xc8ee0d506e864589b799a645ddb88b08f5d39e8049f9f702b3b61fa15e55fc73',
      ),
      (
        'unicode (length prefix counts UTF-8 bytes)',
        'Hello 🌍!',
        '0x9c394471ead71dc5f5899bf21fdb2b3034abd64cc6c9804865b62588a38eb8ac',
      ),
      (
        "'a' * 1000",
        'a' * 1000,
        '0x646dfe80977f3cb244f566d96cd3aabb891d47b9ba5159076d78e9999835e0d6',
      ),
    ]) {
      test(label, () {
        expect(hashMessage(message), equals(hash));
      });
    }
  });

  group('hashStruct', () {
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

    // EIP712Domain lists only the fields the domain sets.
    test('domain with only a name', () {
      const typedData = TypedData(
        domain: TypedDataDomain(name: 'Minimal'),
        types: {
          'Ping': [TypedDataField(name: 'nonce', type: 'uint256')],
        },
        primaryType: 'Ping',
        message: {'nonce': 7},
      );
      expect(
        computeDomainSeparator(typedData.domain),
        '0xbdc2d970970bec81f4837fc7d5246cecfdcf2ac100245c8799925f6db922414e',
      );
      expect(
        hashTypedData(typedData),
        '0x918350ea719158484c5079e8ed33f059493fbb04f60d0c4df150f338a74b9b22',
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

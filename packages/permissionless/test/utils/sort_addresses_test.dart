import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('sortAddresses', () {
    test('sorts addresses in ascending byte-wise order', () {
      final addresses = [
        EthereumAddress.fromHex(
          '0xffffffffffffffffffffffffffffffffffffff03',
        ),
        EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
        ),
        EthereumAddress.fromHex(
          '0xcccccccccccccccccccccccccccccccccccccc04',
        ),
        EthereumAddress.fromHex(
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
        ),
      ];

      expect(
        sortAddresses(addresses).map((a) => a.hex).toList(),
        equals([
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
          '0xcccccccccccccccccccccccccccccccccccccc04',
          '0xffffffffffffffffffffffffffffffffffffff03',
        ]),
      );
    });

    test('ignores checksum casing when sorting', () {
      final addresses = [
        EthereumAddress.fromHex(
          '0xAb12000000000000000000000000000000000000',
        ),
        EthereumAddress.fromHex(
          '0xaB58000000000000000000000000000000000000',
        ),
        EthereumAddress.fromHex(
          '0x9F00000000000000000000000000000000000000',
        ),
      ];

      expect(
        sortAddresses(addresses).map((a) => a.hex).toList(),
        equals([
          '0x9f00000000000000000000000000000000000000',
          '0xab12000000000000000000000000000000000000',
          '0xab58000000000000000000000000000000000000',
        ]),
      );
    });

    test('does not mutate the input list', () {
      final addresses = [
        EthereumAddress.fromHex(
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
        ),
        EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
        ),
      ];
      final originalOrder = addresses.map((a) => a.hex).toList();

      final sorted = sortAddresses(addresses);

      expect(identical(sorted, addresses), isFalse);
      expect(addresses.map((a) => a.hex).toList(), equals(originalOrder));
    });

    test('does not depend on host locale (da collation regression)', () {
      // Under a Danish/Norwegian ICU collation the "aa" digraph sorts
      // after "z", so a locale collator would order 0xaaaa... last.
      // UTF-16 code-unit order must keep it first regardless of locale.
      final addresses = [
        EthereumAddress.fromHex(
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
        ),
        EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
        ),
        EthereumAddress.fromHex(
          '0xab12000000000000000000000000000000000000',
        ),
      ];

      final sorted = sortAddresses(addresses);

      expect(
        sorted.first.hex,
        equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01'),
      );
      expect(
        sorted.map((a) => a.hex).toList(),
        equals([
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01',
          '0xab12000000000000000000000000000000000000',
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02',
        ]),
      );
    });

    test('orders 0x7f before 0x80 (unsigned, not signed-byte)', () {
      final addresses = [
        EthereumAddress.fromHex(
          '0x8000000000000000000000000000000000000000',
        ),
        EthereumAddress.fromHex(
          '0x7f00000000000000000000000000000000000000',
        ),
      ];

      expect(
        sortAddresses(addresses).map((a) => a.hex).toList(),
        equals([
          '0x7f00000000000000000000000000000000000000',
          '0x8000000000000000000000000000000000000000',
        ]),
      );
    });
  });
}

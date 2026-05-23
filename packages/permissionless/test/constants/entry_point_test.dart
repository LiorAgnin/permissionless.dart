import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('EntryPointAddresses', () {
    test('maps EntryPoint v0.6', () {
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v06),
        equals(EntryPointAddresses.v06),
      );
    });

    test('maps EntryPoint v0.7', () {
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v07),
        equals(EntryPointAddresses.v07),
      );
    });

    test('maps EntryPoint v0.8', () {
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v08),
        equals(EntryPointAddresses.v08),
      );
    });

    test('maps EntryPoint v0.9', () {
      expect(
        EntryPointAddresses.v09.hex.toLowerCase(),
        equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
      );
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v09),
        equals(EntryPointAddresses.v09),
      );
    });
  });
}

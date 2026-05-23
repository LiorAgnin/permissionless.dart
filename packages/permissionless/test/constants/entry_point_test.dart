import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('EntryPointAddresses', () {
    test('maps all supported EntryPoint versions', () {
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v06),
        equals(EntryPointAddresses.v06),
      );
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v07),
        equals(EntryPointAddresses.v07),
      );
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v08),
        equals(EntryPointAddresses.v08),
      );
      expect(
        EntryPointAddresses.fromVersion(EntryPointVersion.v09),
        equals(EntryPointAddresses.v09),
      );
    });

    test('has official v0.9 EntryPoint address', () {
      expect(
        EntryPointAddresses.v09.hex.toLowerCase(),
        equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
      );
    });
  });
}

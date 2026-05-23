import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('EntryPointAddresses', () {
    test('exposes official EntryPoint addresses', () {
      expect(
        EntryPointAddresses.v06.hex.toLowerCase(),
        equals('0x5ff137d4b0fdcd49dca30c7cf57e578a026d2789'),
      );
      expect(
        EntryPointAddresses.v07.hex.toLowerCase(),
        equals('0x0000000071727de22e5e9d8baf0edac6f37da032'),
      );
      expect(
        EntryPointAddresses.v08.hex.toLowerCase(),
        equals('0x4337084d9e255ff0702461cf8895ce9e3b5ff108'),
      );
      expect(
        EntryPointAddresses.v09.hex.toLowerCase(),
        equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
      );
    });

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

    test('exposes EntryPoint v0.9 version value', () {
      expect(EntryPointVersion.v09.value, equals('0.9'));
    });

    test('has official v0.9 EntryPoint address', () {
      expect(
        EntryPointAddresses.v09.hex.toLowerCase(),
        equals('0x433709009b8330fda32311df1c2afa402ed8d009'),
      );
    });
  });
}

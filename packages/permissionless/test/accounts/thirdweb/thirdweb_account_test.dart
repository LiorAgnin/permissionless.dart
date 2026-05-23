import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('ThirdwebSmartAccount', () {
    late PrivateKeyOwner owner;

    final mockAddress = EthereumAddress.fromHex(
      '0x1234567890123456789012345678901234567890',
    );

    setUp(() {
      owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );
    });

    test('rejects built-in EntryPoint v0.9 factory selection', () {
      expect(
        () => createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v09,
          address: mockAddress,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('allows custom EntryPoint v0.9 factory experimentation', () {
      final customFactory = EthereumAddress.fromHex(
        '0x1234567890123456789012345678901234567890',
      );

      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        entryPointVersion: EntryPointVersion.v09,
        customFactoryAddress: customFactory,
        address: mockAddress,
      );

      expect(account.entryPointVersion, equals(EntryPointVersion.v09));
      expect(account.entryPoint, equals(EntryPointAddresses.v09));
    });
  });
}

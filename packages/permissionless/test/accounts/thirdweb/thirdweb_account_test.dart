import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Hardhat account 0 — do not use in production
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  // Same owner address as privateKeyToAccount(testPrivateKey) in viem
  const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  // Fixtures from permissionless.js / viem:
  //   salt omitted → "0x" empty bytes
  //   salt "test-salt" → toHex("test-salt") = 0x746573742d73616c74
  // encodeFunctionData(createAccount(admin, saltBytes))
  const jsFactoryDataDefaultSalt =
      '0xd8fd8f44000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266'
      '0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000000000000000000000000000000000000000';

  const jsFactoryDataTestSalt =
      '0xd8fd8f44000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266'
      '0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000000000000000000000000000000000000009'
      '746573742d73616c740000000000000000000000000000000000000000000000';

  group('ThirdwebSmartAccount salt encoding', () {
    late PrivateKeyOwner owner;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      expect(
          owner.address.hex.toLowerCase(), equals(ownerAddress.toLowerCase()));
    });

    test('default (empty) salt factoryData matches permissionless.js',
        () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );

      final factoryData = await account.getFactoryData();
      expect(factoryData, isNotNull);
      expect(
        factoryData!.factoryData.toLowerCase(),
        equals(jsFactoryDataDefaultSalt.toLowerCase()),
      );
      expect(
        factoryData.factory.hex.toLowerCase(),
        equals(ThirdwebAddresses.factoryV07.hex.toLowerCase()),
      );
    });

    test(
      'custom salt "test-salt" factoryData UTF-8-encodes like JS toHex',
      () async {
        final account = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          salt: 'test-salt',
          address: mockAddress,
        );

        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
        expect(
          factoryData!.factoryData.toLowerCase(),
          equals(jsFactoryDataTestSalt.toLowerCase()),
        );
      },
    );

    test('initCode embeds the same factoryData for custom salt', () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        salt: 'test-salt',
        address: mockAddress,
      );

      final factoryData = await account.getFactoryData();
      final initCode = await account.getInitCode();

      expect(
        initCode.toLowerCase(),
        equals(
          '${factoryData!.factory.hex}${factoryData.factoryData.substring(2)}'
              .toLowerCase(),
        ),
      );
      expect(
        initCode.toLowerCase(),
        endsWith(jsFactoryDataTestSalt.substring(2).toLowerCase()),
      );
    });

    test('custom salt must not be hex-decoded (regression)', () async {
      // If salt were hex-decoded, "test-salt" would throw or produce garbage.
      // JS toHex UTF-8-encodes → salt bytes include ASCII 't','e','s','t',...
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        salt: 'test-salt',
        address: mockAddress,
      );

      final factoryData = await account.getFactoryData();
      // UTF-8 of "test-salt" appears after the length word (0x09)
      expect(
        factoryData!.factoryData.toLowerCase(),
        contains('746573742d73616c74'),
      );
      // Must not contain a short hex-decode of the string as hex digits
      expect(
        factoryData.factoryData.toLowerCase(),
        isNot(equals(jsFactoryDataDefaultSalt.toLowerCase())),
      );
    });
  });

  group('ThirdwebSmartAccount signUserOperation', () {
    late PrivateKeyOwner owner;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
    });

    UserOperationV07 fixtureUserOpV07(EthereumAddress sender) =>
        UserOperationV07(
          sender: sender,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
        );

    UserOperationV06 fixtureUserOpV06(EthereumAddress sender) =>
        UserOperationV06(
          sender: sender,
          nonce: BigInt.one,
          initCode: '0x',
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          paymasterAndData: '0x',
          signature: '0x',
        );

    test('v0.6 personal-signs v0.6 userOpHash matching viem fixture', () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v06,
        address: mockAddress,
      );

      final signature =
          await account.signUserOperationV06(fixtureUserOpV06(mockAddress));

      // viem getUserOperationHash (v0.6) + signMessage({ raw: hash })
      expect(
        signature.toLowerCase(),
        equals(
          '0x722cff5408f0bfb44be7b89c1352926b788b13e3aab3ca90eba3f140541ef0e84f013c007081d3f0d27f5fccbdb10d1d33c7582f930504f7b874134d1781c55d1b',
        ),
      );
    });

    test('v0.6 throws when signUserOperation (v0.7 API) is used', () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v06,
        address: mockAddress,
      );

      expect(
        () => account.signUserOperation(fixtureUserOpV07(mockAddress)),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('v0.7 throws when signUserOperationV06 is used', () async {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v07,
        address: mockAddress,
      );

      expect(
        () => account.signUserOperationV06(fixtureUserOpV06(mockAddress)),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('implements SmartAccountV06 for client v0.6 pipeline', () {
      final account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v06,
        address: mockAddress,
      );

      expect(account, isA<SmartAccountV06>());
    });
  });
}

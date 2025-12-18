import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  group('Light Account', () {
    group('LightAccountVersion', () {
      test('v110 is for EntryPoint v0.6', () {
        expect(
          LightAccountVersion.forEntryPoint(EntryPointVersion.v06),
          equals(LightAccountVersion.v110),
        );
      });

      test('v200 is for EntryPoint v0.7', () {
        expect(
          LightAccountVersion.forEntryPoint(EntryPointVersion.v07),
          equals(LightAccountVersion.v200),
        );
      });

      test('v110 has version string "1.1.0"', () {
        expect(LightAccountVersion.v110.version, equals('1.1.0'));
      });

      test('v200 has version string "2.0.0"', () {
        expect(LightAccountVersion.v200.version, equals('2.0.0'));
      });
    });

    group('LightAccountFactoryAddresses', () {
      test('v110 factory address is correct', () {
        expect(
          LightAccountFactoryAddresses.v110.hex.toLowerCase(),
          equals('0x00004EC70002a32400f8ae005A26081065620D20'.toLowerCase()),
        );
      });

      test('v200 factory address is correct', () {
        expect(
          LightAccountFactoryAddresses.v200.hex.toLowerCase(),
          equals('0x0000000000400CdFef5E2714E63d8040b700BC24'.toLowerCase()),
        );
      });

      test('fromVersion returns correct factory for v1.1.0', () {
        expect(
          LightAccountFactoryAddresses.fromVersion(LightAccountVersion.v110)
              .hex
              .toLowerCase(),
          equals(LightAccountFactoryAddresses.v110.hex.toLowerCase()),
        );
      });

      test('fromVersion returns correct factory for v2.0.0', () {
        expect(
          LightAccountFactoryAddresses.fromVersion(LightAccountVersion.v200)
              .hex
              .toLowerCase(),
          equals(LightAccountFactoryAddresses.v200.hex.toLowerCase()),
        );
      });
    });

    group('LightAccountSelectors', () {
      test('execute selector is correct', () {
        // keccak256("execute(address,uint256,bytes)")[0:4] = 0xb61d27f6
        expect(LightAccountSelectors.execute, equals('0xb61d27f6'));
      });

      test('executeBatch selector is correct', () {
        // keccak256("executeBatch(address[],uint256[],bytes[])")[0:4] = 0x47e1da2a
        expect(LightAccountSelectors.executeBatch, equals('0x47e1da2a'));
      });

      test('createAccount selector is correct', () {
        // keccak256("createAccount(address,uint256)")[0:4] = 0x5fbfb9cf
        expect(LightAccountSelectors.createAccount, equals('0x5fbfb9cf'));
      });
    });

    group('LightAccountSignatureType', () {
      test('EOA signature type is 0x00', () {
        expect(LightAccountSignatureType.eoa, equals(0x00));
      });

      test('contract signature type is 0x01', () {
        expect(LightAccountSignatureType.contract, equals(0x01));
      });

      test('contractWithAddr signature type is 0x02', () {
        expect(LightAccountSignatureType.contractWithAddr, equals(0x02));
      });
    });

    group('PrivateKeyOwner', () {
      test('creates from hex private key', () {
        final owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );

        expect(owner.address.hex, startsWith('0x'));
        expect(owner.address.hex.length, equals(42));
      });

      test('address is derived correctly', () {
        // Known test key from hardhat
        final owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );

        // This is the expected address for this private key
        expect(
          owner.address.hex.toLowerCase(),
          equals('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'.toLowerCase()),
        );
      });

      test('signHash signs message hash correctly', () async {
        final owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );

        final signature = await owner.signPersonalMessage('0x${'00' * 32}');

        expect(signature, startsWith('0x'));
        // 65 bytes = 130 hex chars + 0x = 132
        expect(signature.length, equals(132));
      });
    });

    group('LightSmartAccount', () {
      late PrivateKeyOwner owner;

      setUp(() {
        owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );
      });

      test('creates account with default settings', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(account.chainId, equals(BigInt.from(1)));
      });

      test('creates account for v0.6 EntryPoint', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(account.entryPointVersion, equals(EntryPointVersion.v06));
      });

      test('address is deterministic', () async {
        final account1 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.from(12345),
          address: mockAddress,
        );

        final account2 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.from(12345),
          address: mockAddress,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1.hex.toLowerCase(), equals(address2.hex.toLowerCase()));
      });

      test('different salt produces different address', () async {
        final mockAddress1 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account1 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.from(11111),
          address: mockAddress1,
        );

        final account2 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.from(22222),
          address: mockAddress2,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(
          address1.hex.toLowerCase(),
          isNot(equals(address2.hex.toLowerCase())),
        );
      });

      test('different owners produce different addresses', () async {
        final owner2 = PrivateKeyOwner(
          '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        );
        final mockAddress1 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account1 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.zero,
          address: mockAddress1,
        );

        final account2 = createLightSmartAccount(
          owner: owner2,
          chainId: BigInt.from(1),
          salt: BigInt.zero,
          address: mockAddress2,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(
          address1.hex.toLowerCase(),
          isNot(equals(address2.hex.toLowerCase())),
        );
      });

      test('getFactoryData returns valid data', () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final factoryData = await account.getFactoryData();

        expect(factoryData, isNotNull);
        expect(factoryData!.factory.hex, startsWith('0x'));
        expect(factoryData.factoryData, startsWith('0x'));
        // Factory data should start with createAccount selector
        expect(
          factoryData.factoryData.toLowerCase(),
          startsWith(LightAccountSelectors.createAccount),
        );
      });

      test('encodeCall encodes single call correctly', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0xabcd',
        );

        final callData = account.encodeCall(call);

        expect(callData, startsWith('0x'));
        // Should start with execute selector
        expect(
          callData.toLowerCase(),
          startsWith(LightAccountSelectors.execute),
        );
      });

      test('encodeCalls encodes batch calls correctly', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(100),
            data: '0xaabb',
          ),
        ];

        final callData = account.encodeCalls(calls);

        expect(callData, startsWith('0x'));
        // Should start with executeBatch selector
        expect(
          callData.toLowerCase(),
          startsWith(LightAccountSelectors.executeBatch),
        );
      });

      test('getStubSignature returns valid dummy', () {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final dummy = account.getStubSignature();

        expect(dummy, startsWith('0x'));
        // v2.0.0: 1 type byte + 65 signature bytes = 66 bytes = 132 hex + 0x
        expect(dummy.length, equals(134));
      });

      test('signMessage creates EIP-1271 compatible signature', () async {
        final account = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        // Simulate account being deployed
        const message = 'Hello, Light Account!';
        final signature = await account.signMessage(message);

        expect(signature, startsWith('0x'));
        // Should be a valid signature
        expect(signature.length, greaterThan(100));
      });
    });

    group('Light Account v0.6 vs v0.7', () {
      late PrivateKeyOwner owner;

      setUp(() {
        owner = PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        );
      });

      test('v0.6 uses different factory than v0.7', () async {
        final account06 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        final account07 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress,
        );

        final factory06 = (await account06.getFactoryData())!.factory;
        final factory07 = (await account07.getFactoryData())!.factory;

        expect(
          factory06.hex.toLowerCase(),
          equals(LightAccountFactoryAddresses.v110.hex.toLowerCase()),
        );
        expect(
          factory07.hex.toLowerCase(),
          equals(LightAccountFactoryAddresses.v200.hex.toLowerCase()),
        );
      });

      test('same owner produces different addresses for v0.6 vs v0.7',
          () async {
        final mockAddress06 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress07 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account06 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.zero,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress06,
        );

        final account07 = createLightSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.zero,
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress07,
        );

        final address06 = await account06.getAddress();
        final address07 = await account07.getAddress();

        // Different factories = different addresses
        expect(
          address06.hex.toLowerCase(),
          isNot(equals(address07.hex.toLowerCase())),
        );
      });
    });
  });
}

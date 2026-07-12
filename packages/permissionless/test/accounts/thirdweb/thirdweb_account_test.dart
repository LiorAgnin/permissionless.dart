import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Unit tests for Thirdweb smart account.
///
/// Fixtures generated from permissionless.js v0.3.5 / viem with:
/// - privateKey: Hardhat #0
/// - chainId: 1
/// - sender: 0x1234...7890
/// - message: "hello"
void main() {
  // Hardhat account #0 — do not use in production
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  const ownerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  // Pre-set address for unit tests (avoids RPC). Same sender used in JS fixtures.
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  final singleCall = Call(
    to: EthereumAddress.fromHex('0x2222222222222222222222222222222222222222'),
    value: BigInt.one,
    data: '0xdeadbeef',
  );
  final batchCalls = [
    singleCall,
    Call(
      to: EthereumAddress.fromHex('0x3333333333333333333333333333333333333333'),
      value: BigInt.zero,
      data: '0x',
    ),
  ];

  // verifyingContract != account so AccountMessage wrapper path is exercised
  // (self-verifying-contract short-circuit is a separate path).
  final sampleTypedData = TypedData(
    domain: TypedDataDomain(
      name: 'Mail',
      version: '1',
      chainId: BigInt.one,
      verifyingContract: EthereumAddress.fromHex(
        '0x2222222222222222222222222222222222222222',
      ),
    ),
    types: {
      'Mail': [const TypedDataField(name: 'contents', type: 'string')],
    },
    primaryType: 'Mail',
    message: {'contents': 'Hello'},
  );

  UserOperationV06 fixtureUserOpV06(EthereumAddress sender) => UserOperationV06(
        sender: sender,
        nonce: BigInt.zero,
        initCode: '0x',
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        paymasterAndData: '0x',
      );

  UserOperationV07 fixtureUserOpV07(EthereumAddress sender) => UserOperationV07(
        sender: sender,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

  // ---- permissionless.js fixtures ----
  const jsFactoryData =
      '0xd8fd8f44000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cf'
      'ffb9226600000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '00000000';

  const jsFactoryDataTestSalt =
      '0xd8fd8f44000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cf'
      'ffb9226600000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '00000009746573742d73616c7400000000000000000000000000000000000000'
      '00000000';

  const jsFactoryDataV06 =
      '0xd8fd8f44000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cf'
      'ffb9226600000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '00000000';

  const jsInitCode =
      '0x4be0ddfebca9a5a4a617dee4dece99e7c862dcebd8fd8f440000000000000000'
      '00000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000'
      '0000000000000000000000000000000000000000000000400000000000000000'
      '000000000000000000000000000000000000000000000000';

  const jsStubSignature =
      '0xfffffffffffffffffffffffffffffff000000000000000000000000000000000'
      '7aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      '1c';

  const jsEncodeCallsSingle =
      '0xb61d27f600000000000000000000000022222222222222222222222222222222'
      '2222222200000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '00000004deadbeef000000000000000000000000000000000000000000000000'
      '00000000';

  const jsEncodeCallsBatch =
      '0x47e1da2a00000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '000000c000000000000000000000000000000000000000000000000000000000'
      '0000012000000000000000000000000000000000000000000000000000000000'
      '0000000200000000000000000000000022222222222222222222222222222222'
      '2222222200000000000000000000000033333333333333333333333333333333'
      '3333333300000000000000000000000000000000000000000000000000000000'
      '0000000200000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000200000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '0000008000000000000000000000000000000000000000000000000000000000'
      '00000004deadbeef000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00000000';

  const jsSignUserOperation =
      '0x00538c3d1fb4197de5a15394fcaf23ca1a570c63576424c0615656be0e112f59'
      '64840719f944a8d5b0e21ad3a262725d1004ac6a9926ac6299b3f48d1c0c0d8d'
      '1b';

  const jsSignUserOperationV06 =
      '0x722cff5408f0bfb44be7b89c1352926b788b13e3aab3ca90eba3f140541ef0e8'
      '4f013c007081d3f0d27f5fccbdb10d1d33c7582f930504f7b874134d1781c55d'
      '1b';

  const jsSignMessage =
      '0x8e4a8b16b48ba2a07170cf2c9bce6d31131e5781ba5075505daedcd13fe968a3'
      '37dd2d3ddb7805a3c4d3bc1a1922eb100bcfdcc22489b0883b52ab88fd7ca93b'
      '1c';

  // AccountMessage-wrapped Mail typed data (verifyingContract = 0x2222…, not account)
  const jsSignTypedData =
      '0x9ba4681a98b55f06ee90731308a6f49f7fa9059b68ffa59584cee32ccccc3772'
      '72cf5d3982d8eff0352a34b3e45047e35de19bd966f88f94af88c3ea617eee11'
      '1b';

  group('ThirdwebAddresses', () {
    test('factory v0.7 matches permissionless.js', () {
      expect(
        ThirdwebAddresses.factoryV07.hex.toLowerCase(),
        equals('0x4be0ddfebca9a5a4a617dee4dece99e7c862dceb'),
      );
    });

    test('factory v0.6 matches permissionless.js', () {
      expect(
        ThirdwebAddresses.factoryV06.hex.toLowerCase(),
        equals('0x85e23b94e7f5e9cc1ff78bce78cfb15b81f0df00'),
      );
    });
  });

  group('ThirdwebSmartAccount', () {
    late PrivateKeyOwner owner;
    late ThirdwebSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      expect(
          owner.address.hex.toLowerCase(), equals(ownerAddress.toLowerCase()));
      account = createThirdwebSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('defaults to EntryPoint v0.7', () {
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(account.chainId, equals(BigInt.one));
      });

      test('getAddress returns configured address', () async {
        final address = await account.getAddress();
        expect(
            address.hex.toLowerCase(), equals(mockAddress.hex.toLowerCase()));
      });

      test('throws without address or publicClient', () {
        final bare = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
        );
        expect(() => bare.getAddress(), throwsA(isA<StateError>()));
      });
    });

    group('factoryData / initCode / salt', () {
      test('default (empty) salt factoryData matches permissionless.js',
          () async {
        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals(ThirdwebAddresses.factoryV07.hex.toLowerCase()),
        );
        expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryData));
      });

      test('custom salt "test-salt" UTF-8-encodes like JS toHex', () async {
        final salted = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          salt: 'test-salt',
          address: mockAddress,
        );
        final factoryData = await salted.getFactoryData();
        expect(factoryData!.factoryData.toLowerCase(),
            equals(jsFactoryDataTestSalt));
        // UTF-8 of "test-salt"
        expect(factoryData.factoryData.toLowerCase(),
            contains('746573742d73616c74'));
      });

      test('initCode embeds factoryData', () async {
        final initCode = await account.getInitCode();
        expect(initCode.toLowerCase(), equals(jsInitCode));
      });

      test('v0.6 factoryData uses factoryV06', () async {
        final v06 = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );
        final factoryData = await v06.getFactoryData();
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals(ThirdwebAddresses.factoryV06.hex.toLowerCase()),
        );
        expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryDataV06));
      });
    });

    group('stub signature', () {
      test('matches permissionless.js dummy signature', () {
        expect(
            account.getStubSignature().toLowerCase(), equals(jsStubSignature));
      });
    });

    group('encodeCalls', () {
      test('single call matches permissionless.js execute', () {
        expect(
          account.encodeCalls([singleCall]).toLowerCase(),
          equals(jsEncodeCallsSingle),
        );
      });

      test('batch matches permissionless.js executeBatch', () {
        expect(
          account.encodeCalls(batchCalls).toLowerCase(),
          equals(jsEncodeCallsBatch),
        );
      });

      test('throws on empty calls', () {
        expect(() => account.encodeCalls([]), throwsA(isA<ArgumentError>()));
      });
    });

    group('signUserOperation', () {
      test('v0.7 matches permissionless.js', () async {
        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));
        expect(signature.toLowerCase(), equals(jsSignUserOperation));
      });

      test('v0.6 matches permissionless.js / viem fixture', () async {
        final v06 = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );
        final userOp = UserOperationV06(
          sender: mockAddress,
          nonce: BigInt.one,
          initCode: '0x',
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          paymasterAndData: '0x',
        );
        final signature = await v06.signUserOperationV06(userOp);
        expect(signature.toLowerCase(), equals(jsSignUserOperationV06));
      });

      test('v0.6 throws when signUserOperation (v0.7 API) is used', () {
        final v06 = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );
        expect(
          () => v06.signUserOperation(fixtureUserOpV07(mockAddress)),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('v0.7 throws when signUserOperationV06 is used', () {
        expect(
          () => account.signUserOperationV06(fixtureUserOpV06(mockAddress)),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('implements SmartAccountV06 for client v0.6 pipeline', () {
        final v06 = createThirdwebSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );
        expect(v06, isA<SmartAccountV06>());
      });
    });

    group('ERC-1271 signing', () {
      test('signMessage matches permissionless.js AccountMessage wrapper',
          () async {
        final signature = await account.signMessage('hello');
        expect(signature.toLowerCase(), equals(jsSignMessage));
      });

      test('signTypedData matches permissionless.js AccountMessage wrapper',
          () async {
        final signature = await account.signTypedData(sampleTypedData);
        expect(signature.toLowerCase(), equals(jsSignTypedData));
      });
    });
  });
}

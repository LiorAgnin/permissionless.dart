import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Unit tests for Biconomy (legacy EP v0.6) smart account.
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

  final sampleTypedData = TypedData(
    domain: TypedDataDomain(
      name: 'Mail',
      version: '1',
      chainId: BigInt.one,
      verifyingContract: mockAddress,
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

  // ---- permissionless.js fixtures ----
  const jsFactoryData =
      '0xdf20ffbc0000000000000000000000000000001c5b32f37f5bea87bdd5374eb2'
      'ac54ea8e00000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '000000242ede3bc0000000000000000000000000f39fd6e51aad88f6f4ce6ab8'
      '827279cfffb92266000000000000000000000000000000000000000000000000'
      '00000000';

  const jsInitCode =
      '0x000000a56aaca3e9a4c479ea6b6cd0dbcb6634f5df20ffbc0000000000000000'
      '000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e0000000000000000'
      '0000000000000000000000000000000000000000000000600000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000242ede3bc000000000'
      '0000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb9226600000000'
      '000000000000000000000000000000000000000000000000';

  const jsStubSignature =
      '0x0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e'
      '0000000000000000000000000000000000000000000000000000000000000041'
      '81d4b4981670cb18f99f0b4a66446df1bf5b204d24cfcb659bf38ba27a4359b5'
      '711649ec2423c5e1247245eba2964679b6a1dbb85c992ae40b9b00c6935b02ff'
      '1b00000000000000000000000000000000000000000000000000000000000000';

  const jsEncodeCallsSingle =
      '0x0000189a00000000000000000000000022222222222222222222222222222222'
      '2222222200000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '00000004deadbeef000000000000000000000000000000000000000000000000'
      '00000000';

  const jsEncodeCallsBatch =
      '0x0000468000000000000000000000000000000000000000000000000000000000'
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
      '0x0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e'
      '0000000000000000000000000000000000000000000000000000000000000041'
      'c6a17ddf898b2b92ca9ad4ca38b8d3eb73d538e199b939b416ebbe746debeac2'
      '57952180f7c4e4f5433bf20caf4b1bc5330104661b71f16f8cafeecba1aba762'
      '1b00000000000000000000000000000000000000000000000000000000000000';

  const jsSignMessage =
      '0x0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e'
      '0000000000000000000000000000000000000000000000000000000000000041'
      'f16ea9a3478698f695fd1401bfe27e9e4a7e8e3da94aa72b021125e31fa899cc'
      '573c48ea3fe1d4ab61a9db10c19032026e3ed2dbccba5a178235ac27f9450431'
      '1c00000000000000000000000000000000000000000000000000000000000000';

  const jsSignTypedData =
      '0x0000000000000000000000000000000000000000000000000000000000000040'
      '0000000000000000000000000000001c5b32f37f5bea87bdd5374eb2ac54ea8e'
      '0000000000000000000000000000000000000000000000000000000000000041'
      'd8fd05ea6e49e0922a405ed6321ffbd3eedd417fcc8bc44873fa2c78c52bd051'
      '4a1fb653acc8e3752a3901b320950712aecfec9ca122dd7676c9fb9c888e6911'
      '1b00000000000000000000000000000000000000000000000000000000000000';

  const jsCounterfactualAddress = '0x0788816536defa6a14779711c0b08b7f0edfe68b';

  group('BiconomyAddresses', () {
    test('factory matches permissionless.js', () {
      // ignore: deprecated_member_use_from_same_package
      expect(
        BiconomyAddresses.factory.hex.toLowerCase(),
        equals('0x000000a56aaca3e9a4c479ea6b6cd0dbcb6634f5'),
      );
    });

    test('ecdsa ownership module matches permissionless.js', () {
      // ignore: deprecated_member_use_from_same_package
      expect(
        BiconomyAddresses.ecdsaOwnershipModule.hex.toLowerCase(),
        equals('0x0000001c5b32f37f5bea87bdd5374eb2ac54ea8e'),
      );
    });
  });

  group('BiconomySmartAccount', () {
    late PrivateKeyOwner owner;
    // ignore: deprecated_member_use_from_same_package
    late BiconomySmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      expect(
          owner.address.hex.toLowerCase(), equals(ownerAddress.toLowerCase()));
      // ignore: deprecated_member_use_from_same_package
      account = createBiconomySmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('defaults to EntryPoint v0.6', () {
        expect(account.entryPoint, equals(EntryPointAddresses.v06));
        expect(account.chainId, equals(BigInt.one));
        expect(account.index, equals(BigInt.zero));
      });
    });

    group('counterfactual address', () {
      test('CREATE2 address matches permissionless.js', () async {
        // No pre-set address — pure local CREATE2
        // ignore: deprecated_member_use_from_same_package
        final create2Account = createBiconomySmartAccount(
          owner: owner,
          chainId: BigInt.one,
        );
        final address = await create2Account.getAddress();
        expect(
          address.hex.toLowerCase(),
          equals(jsCounterfactualAddress),
        );
      });

      test('returns pre-set address when provided', () async {
        final address = await account.getAddress();
        expect(
            address.hex.toLowerCase(), equals(mockAddress.hex.toLowerCase()));
      });
    });

    group('factoryData / initCode', () {
      test('factoryData matches permissionless.js', () async {
        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals('0x000000a56aaca3e9a4c479ea6b6cd0dbcb6634f5'),
        );
        expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryData));
      });

      test('initCode is factory ++ factoryData', () async {
        final initCode = await account.getInitCode();
        expect(initCode.toLowerCase(), equals(jsInitCode));
      });
    });

    group('stub signature', () {
      test('matches permissionless.js module-wrapped dummy', () {
        expect(
            account.getStubSignature().toLowerCase(), equals(jsStubSignature));
      });
    });

    group('encodeCalls', () {
      test('single call matches permissionless.js execute_ncC', () {
        expect(
          account.encodeCalls([singleCall]).toLowerCase(),
          equals(jsEncodeCallsSingle),
        );
      });

      test('batch matches permissionless.js executeBatch_y6U', () {
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
      test('matches permissionless.js module-wrapped signature', () async {
        final signature =
            await account.signUserOperationV06(fixtureUserOpV06(mockAddress));
        expect(signature.toLowerCase(), equals(jsSignUserOperation));
      });

      test('v0.7 API throws UnsupportedError', () async {
        expect(
          () => account.signUserOperation(
            UserOperationV07(
              sender: mockAddress,
              nonce: BigInt.zero,
              callData: '0x',
              callGasLimit: BigInt.from(100000),
              verificationGasLimit: BigInt.from(100000),
              preVerificationGas: BigInt.from(21000),
              maxFeePerGas: BigInt.from(1000000000),
              maxPriorityFeePerGas: BigInt.from(1000000000),
            ),
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('ERC-1271 signing', () {
      test('signMessage matches permissionless.js', () async {
        final signature = await account.signMessage('hello');
        expect(signature.toLowerCase(), equals(jsSignMessage));
      });

      test('signTypedData matches permissionless.js', () async {
        final signature = await account.signTypedData(sampleTypedData);
        expect(signature.toLowerCase(), equals(jsSignTypedData));
      });
    });
  });
}

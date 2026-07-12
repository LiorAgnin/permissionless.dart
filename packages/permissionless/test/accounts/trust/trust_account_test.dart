import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Unit tests for Trust (Barz) smart account (EP v0.6).
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
      '0x296601cd00000000000000000000000081b9e3689390c7e74cf526594a105dea'
      '21a8cdd500000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00000014f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000'
      '00000000';

  const jsInitCode =
      '0x729c310186a57833f622630a16d13f710b83272a296601cd0000000000000000'
      '0000000081b9e3689390c7e74cf526594a105dea21a8cdd50000000000000000'
      '0000000000000000000000000000000000000000000000600000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '000000000000000000000000000000000000000000000014f39fd6e51aad88f6'
      'f4ce6ab8827279cfffb92266000000000000000000000000';

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
      '0xc6a17ddf898b2b92ca9ad4ca38b8d3eb73d538e199b939b416ebbe746debeac2'
      '57952180f7c4e4f5433bf20caf4b1bc5330104661b71f16f8cafeecba1aba762'
      '1b';

  const jsSignMessage =
      '0xa122dd8b23c31f309fef8d1fc19573a88eac9adb07cc4ffc7c21f39c9af46aa3'
      '5910a5a6cc389c7ea09483dd2c6ff02eae6a7a2d2d13d4e532377b188b85a5fa'
      '1c';

  const jsSignTypedData =
      '0xe8daf41f4e69ebf2ed45751142f77ba5071675ee48fa11c6bc4f3da9dfeb8b24'
      '2a2089763d70ba54fa7b8a77faac46ca0100beb841484c4b37006e45cb0f12e5'
      '1b';

  group('TrustAddresses', () {
    test('factory matches permissionless.js', () {
      expect(
        TrustAddresses.factory.hex.toLowerCase(),
        equals('0x729c310186a57833f622630a16d13f710b83272a'),
      );
    });

    test('secp256k1 verification facet matches permissionless.js', () {
      expect(
        TrustAddresses.secp256k1VerificationFacet.hex.toLowerCase(),
        equals('0x81b9e3689390c7e74cf526594a105dea21a8cdd5'),
      );
    });
  });

  group('TrustSmartAccount', () {
    late PrivateKeyOwner owner;
    late TrustSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      expect(
          owner.address.hex.toLowerCase(), equals(ownerAddress.toLowerCase()));
      account = createTrustSmartAccount(
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
      test(
          'returns pre-set address (unit path; RPC address via getSenderAddress)',
          () async {
        // Trust derives address via EntryPoint.getSenderAddress when no
        // address is supplied — that path needs a publicClient (integration).
        // Unit tests assert the pre-set address path used by clients offline.
        final address = await account.getAddress();
        expect(
            address.hex.toLowerCase(), equals(mockAddress.hex.toLowerCase()));
      });

      test('throws without address or publicClient', () {
        final bare = createTrustSmartAccount(
          owner: owner,
          chainId: BigInt.one,
        );
        expect(() => bare.getAddress(), throwsA(isA<StateError>()));
      });
    });

    group('factoryData / initCode', () {
      test('factoryData matches permissionless.js', () async {
        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals('0x729c310186a57833f622630a16d13f710b83272a'),
        );
        expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryData));
      });

      test('initCode is factory ++ factoryData', () async {
        final initCode = await account.getInitCode();
        expect(initCode.toLowerCase(), equals(jsInitCode));
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
      test('matches permissionless.js personal-sign of userOpHash', () async {
        final signature =
            await account.signUserOperationV06(fixtureUserOpV06(mockAddress));
        expect(signature.toLowerCase(), equals(jsSignUserOperation));
      });

      test('v0.7 API throws UnsupportedError', () {
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
      test('signMessage matches permissionless.js Barz EIP-712 wrapper',
          () async {
        final signature = await account.signMessage('hello');
        expect(signature.toLowerCase(), equals(jsSignMessage));
      });

      test('signTypedData matches permissionless.js Barz EIP-712 wrapper',
          () async {
        final signature = await account.signTypedData(sampleTypedData);
        expect(signature.toLowerCase(), equals(jsSignTypedData));
      });
    });
  });
}

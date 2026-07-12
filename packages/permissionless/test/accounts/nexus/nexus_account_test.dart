import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Unit tests for Nexus (Biconomy ERC-7579) smart account.
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
      '0x0d51f0b7000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cf'
      'ffb9226600000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000008000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '00000000';

  const jsInitCode =
      '0x00000bb19a3579f4d779215def97afbd0e30db550d51f0b70000000000000000'
      '00000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000800000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '000000000000000000000000000000000000000000000000';

  const jsStubSignature =
      '0x0000000000000000000000000000000000000000000000000000000000000040'
      '00000000000000000000000000000004171351c442b202678c48d8ab5b321e8f'
      '0000000000000000000000000000000000000000000000000000000000000041'
      '81d4b4981670cb18f99f0b4a66446df1bf5b204d24cfcb659bf38ba27a4359b5'
      '711649ec2423c5e1247245eba2964679b6a1dbb85c992ae40b9b00c6935b02ff'
      '1b00000000000000000000000000000000000000000000000000000000000000';

  const jsEncodeCallsSingle =
      '0xe9ae5c5300000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '0000003822222222222222222222222222222222222222220000000000000000'
      '000000000000000000000000000000000000000000000001deadbeef00000000'
      '00000000';

  const jsEncodeCallsBatch =
      '0xe9ae5c5301000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '000001a000000000000000000000000000000000000000000000000000000000'
      '0000002000000000000000000000000000000000000000000000000000000000'
      '0000000200000000000000000000000000000000000000000000000000000000'
      '0000004000000000000000000000000000000000000000000000000000000000'
      '000000e000000000000000000000000022222222222222222222222222222222'
      '2222222200000000000000000000000000000000000000000000000000000000'
      '0000000100000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '00000004deadbeef000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000033333333333333333333333333333333'
      '3333333300000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000006000000000000000000000000000000000000000000000000000000000'
      '00000000';

  const jsSignUserOperation =
      '0x00538c3d1fb4197de5a15394fcaf23ca1a570c63576424c0615656be0e112f59'
      '64840719f944a8d5b0e21ad3a262725d1004ac6a9926ac6299b3f48d1c0c0d8d'
      '1b';

  const jsSignMessage =
      '0x00000004171351c442b202678c48d8ab5b321e8fc3531b0bf5e9557d802246e8'
      'a4c71d4bcd37324f686c1c8b880a08662253c952537a603b4f98ac4a321f28f7'
      '5b3f7aec20f40be9765409903ab30e328b7cd71b1b';

  const jsSignTypedData =
      '0x00000004171351c442b202678c48d8ab5b321e8fcf7df200fcddb8965cf2e49b'
      '9566bf97aa1b645097f72ec8086ff240844358130b2091f1368fa3187f5f0b6b'
      'fb52fe300a38461ff03d2a0a71cfe76f86a79b8b1c';

  group('NexusAddresses', () {
    test('k1ValidatorFactory address matches permissionless.js', () {
      expect(
        NexusAddresses.k1ValidatorFactory.hex.toLowerCase(),
        equals('0x00000bb19a3579f4d779215def97afbd0e30db55'),
      );
    });

    test('k1Validator address matches permissionless.js', () {
      expect(
        NexusAddresses.k1Validator.hex.toLowerCase(),
        equals('0x00000004171351c442b202678c48d8ab5b321e8f'),
      );
    });
  });

  group('NexusSelectors', () {
    test('createAccount selector is correct', () {
      expect(NexusSelectors.createAccount, equals('0x0d51f0b7'));
    });

    test('computeAccountAddress selector is correct', () {
      expect(NexusSelectors.computeAccountAddress, equals('0x322cc8ca'));
    });
  });

  group('NexusSmartAccount', () {
    late PrivateKeyOwner owner;
    late NexusSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      expect(
          owner.address.hex.toLowerCase(), equals(ownerAddress.toLowerCase()));
      account = createNexusSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('creates account with defaults for EntryPoint v0.7', () {
        expect(account.owner, equals(owner));
        expect(account.chainId, equals(BigInt.one));
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(account.index, equals(BigInt.zero));
      });

      test('getAddress returns configured address', () async {
        final address = await account.getAddress();
        expect(
            address.hex.toLowerCase(), equals(mockAddress.hex.toLowerCase()));
      });

      test('throws without address or publicClient', () {
        final bare = createNexusSmartAccount(
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
          equals('0x00000bb19a3579f4d779215def97afbd0e30db55'),
        );
        expect(factoryData.factoryData.toLowerCase(), equals(jsFactoryData));
      });

      test('initCode is factory ++ factoryData', () async {
        final initCode = await account.getInitCode();
        expect(initCode.toLowerCase(), equals(jsInitCode));
      });
    });

    group('stub signature', () {
      test('matches permissionless.js validator-wrapped dummy', () {
        expect(
            account.getStubSignature().toLowerCase(), equals(jsStubSignature));
      });

      test('includes validator address for gas estimation', () {
        final stub = account.getStubSignature();
        final validatorHex =
            Hex.strip0x(NexusAddresses.k1Validator.hex).toLowerCase();
        expect(Hex.strip0x(stub).toLowerCase().contains(validatorHex), isTrue);
      });
    });

    group('encodeCalls', () {
      test('single call matches permissionless.js ERC-7579 execute', () {
        expect(
          account.encodeCalls([singleCall]).toLowerCase(),
          equals(jsEncodeCallsSingle),
        );
      });

      test('batch matches permissionless.js ERC-7579 batch execute', () {
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
      test('returns bare 65-byte ECDSA signature (no validator prefix)',
          () async {
        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));
        expect(signature, startsWith('0x'));
        expect(signature.length, equals(132)); // 65 bytes
        expect((signature.length - 2) ~/ 2, equals(65));
      });

      test('does not prepend K1 validator address', () async {
        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));
        final validatorHex =
            Hex.strip0x(NexusAddresses.k1Validator.hex).toLowerCase();
        final sigBody = Hex.strip0x(signature).toLowerCase();
        expect(sigBody.startsWith(validatorHex), isFalse);
        expect(signature.length, isNot(equals(172))); // not 85 bytes
      });

      test('byte-matches permissionless.js for same key and userOp', () async {
        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));
        expect(signature.toLowerCase(), equals(jsSignUserOperation));
      });
    });

    group('ERC-1271 signing', () {
      test('signMessage matches permissionless.js (validator ++ sig)',
          () async {
        final signature = await account.signMessage('hello');
        expect(signature.toLowerCase(), equals(jsSignMessage));
        // 20-byte validator + 65-byte ECDSA = 85 bytes
        expect((signature.length - 2) ~/ 2, equals(85));
      });

      test('signTypedData matches permissionless.js (validator ++ sig)',
          () async {
        final signature = await account.signTypedData(sampleTypedData);
        expect(signature.toLowerCase(), equals(jsSignTypedData));
        expect((signature.length - 2) ~/ 2, equals(85));
      });
    });
  });
}

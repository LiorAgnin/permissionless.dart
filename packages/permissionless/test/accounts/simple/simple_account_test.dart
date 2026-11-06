import 'package:permissionless/permissionless.dart';
import 'package:permissionless/src/accounts/standard_execute.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleSmartAccount', () {
    late SimpleSmartAccount account;
    late PrivateKeyOwner owner;

    // Mock address for unit tests (avoids RPC calls)
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    setUp(() {
      // Test private key (do not use in production!)
      owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );
    });

    // One EIP-191 prefix, as verifyMessage(owner, "hello") expects:
    // cast wallet sign --private-key <owner key> hello
    test('signMessage is the owner personal_sign of the message', () async {
      account = createSimpleSmartAccount(
        owner: owner,
        chainId: BigInt.one,
        address: mockAddress,
      );
      expect(
        await account.signMessage('hello'),
        '0xf16ea9a3478698f695fd1401bfe27e9e4a7e8e3da94aa72b021125e31fa899cc'
        '573c48ea3fe1d4ab61a9db10c19032026e3ed2dbccba5a178235ac27f94504311c',
      );
    });

    group('getFactoryData / getInitCode', () {
      // cast calldata "createAccount(address,uint256)" <owner> 0
      const createAccountSalt0 =
          '0x5fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000';

      test('defaults to the v0.7 factory with createAccount(owner, 0)',
          () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        final factoryData = (await account.getFactoryData())!;

        // permissionless.js toSimpleSmartAccount getFactoryAddress("0.7")
        expect(
          factoryData.factory,
          equals(
            EthereumAddress.fromHex(
              '0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985',
            ),
          ),
        );
        expect(
          factoryData.factoryData.toLowerCase(),
          equals(createAccountSalt0),
        );
      });

      test('salt is the createAccount index', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          salt: BigInt.from(123),
          address: mockAddress,
        );

        // cast calldata "createAccount(address,uint256)" <owner> 123
        expect(
          (await account.getFactoryData())!.factoryData.toLowerCase(),
          equals(
            '0x5fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000007b',
          ),
        );
      });

      // permissionless.js toSimpleSmartAccount getFactoryAddress / viem
      // entryPoint06Address, entryPoint07Address, entryPoint08Address.
      for (final (ep, factory, entryPoint) in [
        (
          EntryPointVersion.v06,
          '0x9406Cc6185a346906296840746125a0E44976454',
          '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789',
        ),
        (
          EntryPointVersion.v07,
          '0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985',
          '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
        ),
        (
          EntryPointVersion.v08,
          '0x13E9ed32155810FDbd067D4522C492D6f68E5944',
          '0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108',
        ),
      ]) {
        test('EntryPoint ${ep.value} uses factory $factory', () async {
          account = createSimpleSmartAccount(
            owner: owner,
            chainId: BigInt.one,
            entryPointVersion: ep,
            address: mockAddress,
          );

          expect(
            account.entryPoint,
            equals(EthereumAddress.fromHex(entryPoint)),
          );
          expect(
            (await account.getFactoryData())!.factory,
            equals(EthereumAddress.fromHex(factory)),
          );
        });
      }

      test('customFactoryAddress replaces the factory, not the calldata',
          () async {
        final customFactory = EthereumAddress.fromHex(
          '0x5555555555555555555555555555555555555555',
        );
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          customFactoryAddress: customFactory,
          address: mockAddress,
        );

        final factoryData = (await account.getFactoryData())!;
        expect(factoryData.factory, equals(customFactory));
        expect(
          factoryData.factoryData.toLowerCase(),
          equals(createAccountSalt0),
        );
      });

      test('initCode is factory ++ factoryData', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        // cast concat-hex <v0.7 factory> <createAccount(owner, 0) calldata>
        expect(
          (await account.getInitCode()).toLowerCase(),
          equals(
            '0x91e60e0613810449d098b0b5ec8b51a0fe8c89855fbfb9cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });
    });

    group('encodeCall', () {
      test('encodes single execute call', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final callData = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000000000000000000), // 1 ETH
            data: '0xabcdef',
          ),
        );

        // cast calldata "execute(address,uint256,bytes)" \
        //   0x1234567890123456789012345678901234567890 1000000000000000000 0xabcdef
        expect(
          callData.toLowerCase(),
          equals(
            '0xb61d27f600000000000000000000000012345678901234567890123456789012345678900000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003abcdef0000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('encodes call with zero value', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final callData = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            data: '0x12345678',
          ),
        );

        // cast calldata "execute(address,uint256,bytes)" \
        //   0x1234567890123456789012345678901234567890 0 0x12345678
        expect(
          callData.toLowerCase(),
          equals(
            '0xb61d27f600000000000000000000000012345678901234567890123456789012345678900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000041234567800000000000000000000000000000000000000000000000000000000',
          ),
        );
      });
    });

    group('encodeCalls', () {
      // Shared batch inputs used for viem/permissionless.js fixtures below.
      final batchCalls = [
        Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          data: '0xabcdef',
        ),
        Call(
          to: EthereumAddress.fromHex(
            '0x2345678901234567890123456789012345678901',
          ),
          value: BigInt.from(1000),
          data: '0x123456',
        ),
      ];

      test('uses execute for single call', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final callData = account.encodeCalls([
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            data: '0xabcdef',
          ),
        ]);

        // Single call uses execute, not executeBatch:
        // cast calldata "execute(address,uint256,bytes)" \
        //   0x1234567890123456789012345678901234567890 0 0xabcdef
        expect(
          callData.toLowerCase(),
          equals(
            '0xb61d27f60000000000000000000000001234567890123456789012345678901234567890000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003abcdef0000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('v0.6 uses executeBatch(address[],bytes[]) selector 0x18dfb3c7', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        final callData = account.encodeCalls(batchCalls);

        // viem encodeFunctionData fixture for executeBatch06Abi
        expect(
          callData.toLowerCase(),
          equals(
            '0x18dfb3c7000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000123456789012345678901234567890123456789000000000000000000000000023456789012345678901234567890123456789010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003abcdef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test(
          'v0.7 uses executeBatch(address[],uint256[],bytes[]) selector 0x47e1da2a',
          () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress,
        );

        final callData = account.encodeCalls(batchCalls);

        // viem encodeFunctionData fixture for executeBatch07Abi
        expect(
          callData.toLowerCase(),
          equals(
            '0x47e1da2a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000123456789012345678901234567890123456789000000000000000000000000023456789012345678901234567890123456789010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e80000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003abcdef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test(
          'v0.8 uses executeBatch((address,uint256,bytes)[]) selector 0x34fcd5be',
          () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v08,
          address: mockAddress,
        );

        final callData = account.encodeCalls(batchCalls);

        // viem encodeFunctionData fixture for executeBatch08Abi
        expect(
          callData.toLowerCase(),
          equals(
            '0x34fcd5be00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000001234567890123456789012345678901234567890000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003abcdef0000000000000000000000000000000000000000000000000000000000000000000000000000000000234567890123456789012345678901234567890100000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000031234560000000000000000000000000000000000000000000000000000000000',
          ),
        );
      });

      test('throws on empty calls', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          () => account.encodeCalls([]),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('getStubSignature', () {
      test('matches permissionless.js dummy signature', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          address: mockAddress,
        );

        // permissionless.js toSimpleSmartAccount getStubSignature()
        expect(
          account.getStubSignature(),
          equals(
            '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c',
          ),
        );
      });
    });

    group('signUserOperation', () {
      /// Canonical UserOperation used for viem fixture signatures (chainId=1).
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

      test('v0.7 personal-signs userOpHash matching viem fixture', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v07,
          address: mockAddress,
        );

        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));

        // viem getUserOperationHash (v0.7) + signMessage({ raw: hash })
        expect(
          signature.toLowerCase(),
          equals(
            '0xc6a3c86d23bc0a8f53a1a6b8f0d0918a93582e804cb77736199801cbb1a6f08d6c87bf1af6de3f99e40152770b759abc36107b8c168e9a7be8651eeb4a1bfa001c',
          ),
        );
      });

      test('v0.6 personal-signs v0.6 userOpHash matching viem fixture',
          () async {
        account = createSimpleSmartAccount(
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

      test('v0.8 signs EIP-712 typed data matching viem fixture', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v08,
          address: mockAddress,
        );

        final signature =
            await account.signUserOperation(fixtureUserOpV07(mockAddress));

        // viem getUserOperationTypedData + signTypedData
        expect(
          signature.toLowerCase(),
          equals(
            '0x7717cbb0620c7bf781b2175f13e7e6b809fe9042bce6937ae82deb396c4f537b2c5cfad80c2b6880a6de20e94123f3e341470e18a10443b7896a6c2167e32b501b',
          ),
        );
      });

      test('v0.6 throws when signUserOperation (v0.7 API) is used', () async {
        account = createSimpleSmartAccount(
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
        account = createSimpleSmartAccount(
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
    });
  });

  group('SimpleAccountFactoryAddresses', () {
    test('has v0.6 factory address', () {
      expect(
        SimpleAccountFactoryAddresses.v06.hex.toLowerCase(),
        equals('0x9406cc6185a346906296840746125a0e44976454'),
      );
    });

    test('has v0.7 factory address', () {
      expect(
        SimpleAccountFactoryAddresses.v07.hex.toLowerCase(),
        equals('0x91e60e0613810449d098b0b5ec8b51a0fe8c8985'),
      );
    });

    test('fromVersion returns correct address', () {
      expect(
        SimpleAccountFactoryAddresses.fromVersion(EntryPointVersion.v06),
        equals(SimpleAccountFactoryAddresses.v06),
      );
      expect(
        SimpleAccountFactoryAddresses.fromVersion(EntryPointVersion.v07),
        equals(SimpleAccountFactoryAddresses.v07),
      );
    });
  });

  group('SimpleAccountSelectors', () {
    // cast sig 'createAccount(address,uint256)'
    test('createAccount matches cast sig', () {
      expect(SimpleAccountSelectors.createAccount, equals('0x5fbfb9cf'));
    });

    test('are the selectors of the signatures the account encodes', () {
      for (final (selector, signature) in [
        (SimpleAccountSelectors.execute, executeSignature),
        (
          SimpleAccountSelectors.executeBatchV06,
          ExecuteBatchAbi.addressesAndBytes.signature
        ),
        (
          SimpleAccountSelectors.executeBatch,
          ExecuteBatchAbi.addressesValuesAndBytes.signature
        ),
        (
          SimpleAccountSelectors.executeBatchV08,
          ExecuteBatchAbi.callTuples.signature
        ),
        (
          SimpleAccountSelectors.createAccount,
          simpleAccountCreateAccountSignature
        ),
      ]) {
        expect(
          selector,
          AbiEncoder.functionSelector(signature),
          reason: signature,
        );
      }
    });
  });
}

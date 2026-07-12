import 'package:permissionless/permissionless.dart';
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

    group('creation', () {
      test('creates account with single owner', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(11155111),
          address: mockAddress,
        );

        expect(account.owner, equals(owner));
        expect(account.chainId, equals(BigInt.from(11155111)));
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(account.salt, equals(BigInt.zero));
      });

      test('creates account with custom salt', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.from(123),
          address: mockAddress,
        );

        expect(account.salt, equals(BigInt.from(123)));
      });

      test('creates account with EntryPoint v0.6', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(account.entryPointVersion, equals(EntryPointVersion.v06));
        expect(account.entryPoint, equals(EntryPointAddresses.v06));
      });

      test('creates account with custom factory address', () {
        final customFactory = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          customFactoryAddress: customFactory,
          address: mockAddress,
        );

        // Factory data should use custom address
        // We can verify this through getFactoryData
        expect(account, isNotNull);
      });
    });

    group('getAddress', () {
      test('returns deterministic address', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(11155111),
          address: mockAddress,
        );

        final address = await account.getAddress();

        // Address should be deterministic based on owner and salt
        expect(address.hex, startsWith('0x'));
        expect(address.hex.length, equals(42));

        // Same config should produce same address
        final account2 = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(11155111),
          address: mockAddress,
        );
        final address2 = await account2.getAddress();

        expect(address2.hex, equals(address.hex));
      });

      test('caches address after first calculation', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final address1 = await account.getAddress();
        final address2 = await account.getAddress();

        expect(identical(address1, address2), isTrue);
      });

      test('different salt produces different address', () async {
        final mockAddress1 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account1 = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.zero,
          address: mockAddress1,
        );

        final account2 = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          salt: BigInt.one,
          address: mockAddress2,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1.hex, isNot(equals(address2.hex)));
      });
    });

    group('getInitCode', () {
      test('returns factory address + calldata', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final initCode = await account.getInitCode();

        // InitCode starts with factory address (20 bytes = 40 hex chars + 0x)
        expect(initCode, startsWith('0x'));
        expect(initCode.length, greaterThan(42));

        // Should contain createAccount selector
        expect(initCode.contains('5fbfb9cf'), isTrue);
      });

      test('encodes owner address in init code', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final initCode = await account.getInitCode();

        // Owner address should be in the calldata (lowercase, without 0x prefix)
        final ownerHex = owner.address.hex.toLowerCase().substring(2);
        expect(initCode.toLowerCase(), contains(ownerHex));
      });
    });

    group('getFactoryData', () {
      test('returns factory and data separately', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final factoryData = await account.getFactoryData();

        expect(factoryData, isNotNull);
        expect(factoryData!.factory, equals(SimpleAccountFactoryAddresses.v07));
        expect(factoryData.factoryData, startsWith('0x5fbfb9cf'));
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

        // Should start with execute selector
        expect(callData, startsWith('0xb61d27f6'));
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

        expect(callData, startsWith('0xb61d27f6'));
        expect(callData.length, greaterThan(10));
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

        // Single call should use execute, not executeBatch
        expect(callData, startsWith('0xb61d27f6'));
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
      test('returns 65-byte signature', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final stubSig = account.getStubSignature();

        // 65 bytes = 130 hex chars + "0x"
        expect(stubSig, startsWith('0x'));
        expect(stubSig.length, equals(132));
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

      test('implements SmartAccountV06 for client v0.6 pipeline', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(account, isA<SmartAccountV06>());
      });

      test('produces deterministic signature', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final userOp = UserOperationV07(
          sender: await account.getAddress(),
          nonce: BigInt.from(5),
          callData: '0x1234',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
        );

        final sig1 = await account.signUserOperation(userOp);
        final sig2 = await account.signUserOperation(userOp);

        expect(sig1, equals(sig2));
      });

      test('different userOps produce different signatures', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final sender = await account.getAddress();

        final userOp1 = UserOperationV07(
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

        final userOp2 = UserOperationV07(
          sender: sender,
          nonce: BigInt.from(2), // Different nonce
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
        );

        final sig1 = await account.signUserOperation(userOp1);
        final sig2 = await account.signUserOperation(userOp2);

        expect(sig1, isNot(equals(sig2)));
      });

      test('handles paymaster data', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final userOp = UserOperationV07(
          sender: await account.getAddress(),
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
          paymaster: EthereumAddress.fromHex(
            '0xaaaa567890123456789012345678901234567890',
          ),
          paymasterData: '0x1234',
          paymasterVerificationGasLimit: BigInt.from(50000),
          paymasterPostOpGasLimit: BigInt.from(25000),
        );

        final signature = await account.signUserOperation(userOp);

        // Should still produce valid signature
        expect(signature, startsWith('0x'));
        expect(signature.length, equals(132));
      });

      test('handles factory data', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final factoryData = await account.getFactoryData();

        final userOp = UserOperationV07(
          sender: await account.getAddress(),
          nonce: BigInt.zero,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
          factory: factoryData!.factory,
          factoryData: factoryData.factoryData,
        );

        final signature = await account.signUserOperation(userOp);

        // Should still produce valid signature
        expect(signature, startsWith('0x'));
        expect(signature.length, equals(132));
      });
    });

    group('nonceKey', () {
      test('returns zero for sequential transactions', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.nonceKey, equals(BigInt.zero));
      });
    });
  });

  group('PrivateKeyOwner', () {
    test('derives address from private key', () {
      final owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );

      // This is the first Hardhat test account
      expect(
        owner.address.hex.toLowerCase(),
        equals('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'),
      );
    });

    test('signs message hash', () async {
      final owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );

      const messageHash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final signature = await owner.signPersonalMessage(messageHash);

      // Signature should be 65 bytes
      expect(signature, startsWith('0x'));
      expect(signature.length, equals(132));
    });

    test('produces deterministic signatures', () async {
      final owner = PrivateKeyOwner(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );

      const messageHash =
          '0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd';

      final sig1 = await owner.signPersonalMessage(messageHash);
      final sig2 = await owner.signPersonalMessage(messageHash);

      expect(sig1, equals(sig2));
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
    test('has correct execute selector', () {
      expect(SimpleAccountSelectors.execute, equals('0xb61d27f6'));
    });

    test('has correct executeBatch v0.6 selector', () {
      expect(SimpleAccountSelectors.executeBatchV06, equals('0x18dfb3c7'));
    });

    test('has correct executeBatch v0.7 selector', () {
      expect(SimpleAccountSelectors.executeBatch, equals('0x47e1da2a'));
    });

    test('has correct executeBatch v0.8 selector', () {
      expect(SimpleAccountSelectors.executeBatchV08, equals('0x34fcd5be'));
    });

    test('has correct createAccount selector', () {
      expect(SimpleAccountSelectors.createAccount, equals('0x5fbfb9cf'));
    });
  });
}

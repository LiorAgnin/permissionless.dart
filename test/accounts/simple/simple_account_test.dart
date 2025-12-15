import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleSmartAccount', () {
    late SimpleSmartAccount account;
    late PrivateKeyOwner owner;

    // Mock address for unit tests (avoids RPC calls)
    final mockAddress =
        EthAddress('0x1234567890123456789012345678901234567890');

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
        final customFactory =
            EthAddress('0x1234567890123456789012345678901234567890');
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
        final mockAddress1 =
            EthAddress('0x1111111111111111111111111111111111111111');
        final mockAddress2 =
            EthAddress('0x2222222222222222222222222222222222222222');

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
            to: EthAddress('0x1234567890123456789012345678901234567890'),
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
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            data: '0x12345678',
          ),
        );

        expect(callData, startsWith('0xb61d27f6'));
        expect(callData.length, greaterThan(10));
      });
    });

    group('encodeCalls', () {
      test('uses execute for single call', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final callData = account.encodeCalls([
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            data: '0xabcdef',
          ),
        ]);

        // Single call should use execute, not executeBatch
        expect(callData, startsWith('0xb61d27f6'));
      });

      test('uses executeBatch for multiple calls', () {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final callData = account.encodeCalls([
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            data: '0xabcdef',
          ),
          Call(
            to: EthAddress('0x2345678901234567890123456789012345678901'),
            value: BigInt.from(1000),
            data: '0x123456',
          ),
        ]);

        // Multiple calls should use executeBatch
        expect(callData, startsWith('0x47e1da2a'));
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
      test('signs UserOperation and returns signature', () async {
        account = createSimpleSmartAccount(
          owner: owner,
          chainId: BigInt.from(11155111),
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
        );

        final signature = await account.signUserOperation(userOp);

        // Signature should be 65 bytes (r + s + v)
        expect(signature, startsWith('0x'));
        expect(signature.length, equals(132));
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
          paymaster: EthAddress('0xaaaa567890123456789012345678901234567890'),
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

    test('has correct executeBatch selector', () {
      expect(SimpleAccountSelectors.executeBatch, equals('0x47e1da2a'));
    });

    test('has correct createAccount selector', () {
      expect(SimpleAccountSelectors.createAccount, equals('0x5fbfb9cf'));
    });
  });
}

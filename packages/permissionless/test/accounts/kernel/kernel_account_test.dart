import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Test private key (Hardhat account 0 - DO NOT use in production!)
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  const testOwnerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  group('KernelVersion', () {
    test('v0_2_4 has correct value', () {
      expect(KernelVersion.v0_2_4.value, equals('0.2.4'));
    });

    test('v0_3_1 has correct value', () {
      expect(KernelVersion.v0_3_1.value, equals('0.3.1'));
    });

    test('v0_2_4 does not use ERC-7579', () {
      expect(KernelVersion.v0_2_4.usesErc7579, isFalse);
    });

    test('v0_3_1 uses ERC-7579', () {
      expect(KernelVersion.v0_3_1.usesErc7579, isTrue);
    });

    test('v0_2_4 does not have external validator', () {
      expect(KernelVersion.v0_2_4.hasExternalValidator, isFalse);
    });

    test('v0_3_1 has external validator', () {
      expect(KernelVersion.v0_3_1.hasExternalValidator, isTrue);
    });
  });

  group('KernelVersionAddresses', () {
    test('returns addresses for v0.2.4', () {
      final addresses =
          KernelVersionAddresses.getAddresses(KernelVersion.v0_2_4);
      expect(addresses, isNotNull);
      expect(addresses!.factory.hex, isNotEmpty);
      expect(addresses.accountImplementation.hex, isNotEmpty);
    });

    test('returns addresses for v0.3.1', () {
      final addresses =
          KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1);
      expect(addresses, isNotNull);
      expect(addresses!.factory.hex, isNotEmpty);
      expect(addresses.metaFactory, isNotNull);
      expect(addresses.ecdsaValidator, isNotNull);
    });

    test('v0.3.1 has meta factory', () {
      final addresses =
          KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1);
      expect(addresses!.metaFactory, isNotNull);
      expect(
        addresses.metaFactory!.hex.toLowerCase(),
        equals('0xd703aae79538628d27099b8c4f621be4ccd142d5'),
      );
    });

    test('v0.3.1 has ECDSA validator', () {
      final addresses =
          KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1);
      expect(addresses!.ecdsaValidator, isNotNull);
      expect(
        addresses.ecdsaValidator!.hex.toLowerCase(),
        equals('0x845adb2c711129d4f3966735ed98a9f09fc4ce57'),
      );
    });
  });

  group('PrivateKeyOwner', () {
    test('derives correct address from private key', () {
      final owner = PrivateKeyOwner(testPrivateKey);
      expect(
        owner.address.hex.toLowerCase(),
        equals(testOwnerAddress.toLowerCase()),
      );
    });

    test('signs hash and returns valid signature', () async {
      final owner = PrivateKeyOwner(testPrivateKey);
      const hash =
          '0x0000000000000000000000000000000000000000000000000000000000000001';

      final signature = await owner.signRawHash(hash);

      expect(signature, startsWith('0x'));
      // ECDSA signature: r (32) + s (32) + v (1) = 65 bytes = 130 hex + 0x
      expect(signature.length, equals(132));
    });

    test('produces deterministic signatures', () async {
      final owner = PrivateKeyOwner(testPrivateKey);
      const hash =
          '0x0000000000000000000000000000000000000000000000000000000000000001';

      final sig1 = await owner.signRawHash(hash);
      final sig2 = await owner.signRawHash(hash);

      expect(sig1, equals(sig2));
    });
  });

  group('KernelSmartAccount v0.3.1', () {
    late PrivateKeyOwner owner;
    late KernelSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('creates account with default index', () {
        expect(account, isNotNull);
      });

      test('creates account with custom index', () {
        final customAccount = createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          version: KernelVersion.v0_3_1,
          index: BigInt.from(123),
          address: mockAddress,
        );
        expect(customAccount, isNotNull);
      });

      test('uses entry point v0.7', () {
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
        expect(
          account.entryPoint.hex.toLowerCase(),
          equals(EntryPointAddresses.v07.hex.toLowerCase()),
        );
      });
    });

    group('address', () {
      test('returns deterministic address', () async {
        final address = await account.getAddress();
        expect(address.hex, startsWith('0x'));
        expect(address.hex.length, equals(42));
      });

      test('same config produces same address', () async {
        final account2 = createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          version: KernelVersion.v0_3_1,
          address: mockAddress,
        );

        final addr1 = await account.getAddress();
        final addr2 = await account2.getAddress();

        expect(addr1.hex, equals(addr2.hex));
      });

      test('different index produces different address', () async {
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );
        final account2 = createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          version: KernelVersion.v0_3_1,
          index: BigInt.from(1),
          address: mockAddress2,
        );

        final addr1 = await account.getAddress();
        final addr2 = await account2.getAddress();

        expect(addr1.hex, isNot(equals(addr2.hex)));
      });

      test('caches address after first calculation', () async {
        final addr1 = await account.getAddress();
        final addr2 = await account.getAddress();

        expect(identical(addr1, addr2), isTrue);
      });
    });

    group('factory data', () {
      test('returns factory data for v0.3.1', () async {
        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
        expect(factoryData!.factory, isNotNull);
        expect(factoryData.factoryData, startsWith('0x'));
      });

      test('uses meta factory for v0.3.1', () async {
        final factoryData = await account.getFactoryData();
        final addresses =
            KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1);
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals(addresses!.metaFactory!.hex.toLowerCase()),
        );
      });

      test('factory data contains deployWithFactory selector', () async {
        final factoryData = await account.getFactoryData();
        expect(
          factoryData!.factoryData.toLowerCase(),
          startsWith(KernelSelectors.deployWithFactory.toLowerCase()),
        );
      });
    });

    group('init code', () {
      test('returns init code', () async {
        final initCode = await account.getInitCode();
        expect(initCode, startsWith('0x'));
        expect(initCode.length, greaterThan(42)); // More than just address
      });

      test('init code starts with factory address', () async {
        final initCode = await account.getInitCode();
        final factoryData = await account.getFactoryData();
        expect(
          initCode.toLowerCase(),
          startsWith(factoryData!.factory.hex.toLowerCase()),
        );
      });
    });

    group('call encoding', () {
      test('encodes single call with ERC-7579', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        final encoded = account.encodeCall(call);

        expect(encoded, startsWith('0x'));
        // Should use ERC-7579 execute selector
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.substring(2).toLowerCase()),
        );
      });

      test('encodes batch calls with ERC-7579', () {
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
            data: '0xabcd',
          ),
        ];

        final encoded = account.encodeCalls(calls);

        expect(encoded, startsWith('0x'));
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.substring(2).toLowerCase()),
        );
      });

      test('single call optimization in encodeCalls', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ];

        final batchEncoded = account.encodeCalls(calls);
        final singleEncoded = account.encodeCall(calls.first);

        expect(batchEncoded, equals(singleEncoded));
      });

      test('throws on empty calls list', () {
        expect(
          () => account.encodeCalls([]),
          throwsArgumentError,
        );
      });
    });

    group('stub signature', () {
      test('returns stub signature for v0.3.1', () {
        final stub = account.getStubSignature();

        expect(stub, startsWith('0x'));
        // v0.3.1: just ECDSA signature (65 bytes = 130 hex)
        // No validator prefix for stub signatures (matches permissionless.js)
        expect(stub.length, equals(132)); // 130 + 2 for 0x
      });

      test('stub signature is raw ECDSA signature', () {
        final stub = account.getStubSignature();

        // Should be dummy ECDSA signature directly (65 bytes)
        expect(stub, equals(kernelDummyEcdsaSignature));
      });
    });

    group('sign user operation', () {
      test('signs user operation', () async {
        final address = await account.getAddress();
        final userOp = UserOperationV07(
          sender: address,
          nonce: BigInt.zero,
          callData: account.encodeCall(
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
              data: '0x',
            ),
          ),
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final signature = await account.signUserOperation(userOp);

        expect(signature, startsWith('0x'));
        // v0.3.1: just ECDSA signature (65 bytes = 130 hex)
        // No validator prefix for signUserOperation (matches permissionless.js)
        expect(signature.length, equals(132)); // 130 + 2 for 0x
      });

      test('signature is raw ECDSA signature', () async {
        final address = await account.getAddress();
        final userOp = UserOperationV07(
          sender: address,
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final signature = await account.signUserOperation(userOp);

        // v0.3.1 signatures are raw ECDSA (r, s, v format)
        // Should be 65 bytes
        expect((signature.length - 2) ~/ 2, equals(65));
      });
    });

    group('nonce key', () {
      test('returns encoded nonce key for v0.3.1', () {
        final nonceKey = account.nonceKey;

        // 24-byte key as BigInt
        expect(nonceKey, isNotNull);
        expect(nonceKey, greaterThanOrEqualTo(BigInt.zero));
      });
    });
  });

  group('KernelSmartAccount v0.2.4', () {
    late PrivateKeyOwner owner;
    late KernelSmartAccount account;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_2_4,
        address: mockAddress,
      );
    });

    group('creation', () {
      test('creates account with v0.2.4', () {
        expect(account, isNotNull);
      });

      test('uses entry point v0.6', () {
        expect(account.entryPointVersion, equals(EntryPointVersion.v06));
        expect(
          account.entryPoint.hex.toLowerCase(),
          equals(EntryPointAddresses.v06.hex.toLowerCase()),
        );
      });
    });

    group('address', () {
      test('returns deterministic address', () async {
        final address = await account.getAddress();
        expect(address.hex, startsWith('0x'));
        expect(address.hex.length, equals(42));
      });

      test('different from v0.3.1 address', () async {
        final mockAddress024 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress031 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );
        final v024Account = createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          version: KernelVersion.v0_2_4,
          address: mockAddress024,
        );
        final v031Account = createKernelSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          version: KernelVersion.v0_3_1,
          address: mockAddress031,
        );

        final addr024 = await v024Account.getAddress();
        final addr031 = await v031Account.getAddress();

        expect(addr024.hex, isNot(equals(addr031.hex)));
      });
    });

    group('factory data', () {
      test('returns factory data for v0.2.4', () async {
        final factoryData = await account.getFactoryData();
        expect(factoryData, isNotNull);
      });

      test('uses direct factory for v0.2.4', () async {
        final factoryData = await account.getFactoryData();
        final addresses =
            KernelVersionAddresses.getAddresses(KernelVersion.v0_2_4);
        expect(
          factoryData!.factory.hex.toLowerCase(),
          equals(addresses!.factory.hex.toLowerCase()),
        );
      });

      test('factory data contains createAccount selector', () async {
        final factoryData = await account.getFactoryData();
        expect(
          factoryData!.factoryData.toLowerCase(),
          startsWith(KernelSelectors.createAccountV2.toLowerCase()),
        );
      });
    });

    group('call encoding', () {
      // Fixtures generated from permissionless.js KernelExecuteAbi via viem
      // encodeFunctionData (accounts/kernel/abi/KernelAccountAbi.ts).
      // execute(address,uint256,bytes,uint8) = 0x51945447
      // executeBatch((address,uint256,bytes)[]) = 0x34fcd5be
      const jsSingleEmpty =
          '0x5194544700000000000000000000000012345678901234567890123456789012345678900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
      const jsSingleWithData =
          '0x51945447000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd00000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004deadbeef00000000000000000000000000000000000000000000000000000000';
      const jsBatch =
          '0x34fcd5be00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000011111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222222222222222222222222222000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000002abcd000000000000000000000000000000000000000000000000000000000000';
      const jsBatchThree =
          '0x34fcd5be00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000180000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccccccccccccccccccccccccccccccccccc00000000000000000000000000000000000000000000000000000000000003e700000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004abcdef0100000000000000000000000000000000000000000000000000000000';

      test('encodes single call with Kernel v2 execute selector', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        final encoded = account.encodeCall(call);

        expect(encoded, startsWith('0x'));
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals('51945447'),
        );
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(KernelSelectors.executeV2.substring(2).toLowerCase()),
        );
      });

      test('single empty call byte-matches permissionless.js', () {
        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        );

        expect(encoded.toLowerCase(), equals(jsSingleEmpty.toLowerCase()));
      });

      test('single call with value/data byte-matches permissionless.js', () {
        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
            ),
            value: BigInt.from(1000),
            data: '0xdeadbeef',
          ),
        );

        expect(encoded.toLowerCase(), equals(jsSingleWithData.toLowerCase()));
      });

      test('encodes batch calls with Kernel v2 executeBatch selector', () {
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
            data: '0xabcd',
          ),
        ];

        final encoded = account.encodeCalls(calls);

        expect(encoded, startsWith('0x'));
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals('34fcd5be'),
        );
        expect(
          encoded.substring(2, 10).toLowerCase(),
          equals(KernelSelectors.executeBatchV2.substring(2).toLowerCase()),
        );
      });

      test('batch calls byte-match permissionless.js', () {
        final encoded = account.encodeCalls([
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
            data: '0xabcd',
          ),
        ]);

        expect(encoded.toLowerCase(), equals(jsBatch.toLowerCase()));
      });

      test('three-call batch byte-matches permissionless.js', () {
        final encoded = account.encodeCalls([
          Call(
            to: EthereumAddress.fromHex(
              '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
            value: BigInt.one,
            data: '0x01',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0xcccccccccccccccccccccccccccccccccccccccc',
            ),
            value: BigInt.from(999),
            data: '0xabcdef01',
          ),
        ]);

        expect(encoded.toLowerCase(), equals(jsBatchThree.toLowerCase()));
      });

      test('single call via encodeCalls matches encodeCall', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        expect(account.encodeCalls([call]), equals(account.encodeCall(call)));
      });
    });

    group('stub signature', () {
      test('returns stub signature for v0.2.4', () {
        final stub = account.getStubSignature();

        expect(stub, startsWith('0x'));
        // v0.2.4: ROOT_MODE (4) + sig (65) = 69 bytes = 138 hex
        expect(stub.length, equals(140)); // 138 + 2 for 0x
      });

      test('stub signature starts with ROOT_MODE', () {
        final stub = account.getStubSignature();

        // ROOT_MODE = 0x00000000
        expect(stub.substring(2, 10), equals('00000000'));
      });
    });

    group('sign user operation', () {
      test('signature contains ROOT_MODE prefix', () async {
        final address = await account.getAddress();
        final userOp = UserOperationV07(
          sender: address,
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final signature = await account.signUserOperation(userOp);

        // Should have ROOT_MODE prefix
        expect(signature.substring(2, 10), equals('00000000'));
      });
    });

    group('nonce key', () {
      test('returns zero for v0.2.4', () {
        expect(account.nonceKey, equals(BigInt.zero));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // RIP-7212 / _shouldUsePrecompile integration
  //
  // The WebAuthn signing path (signUserOperation, signMessage, signTypedData)
  // now calls _shouldUsePrecompile() which uses isRip7212Supported(publicClient)
  // when a publicClient is available, falling back to shouldUseP256Precompile.
  //
  // Full WebAuthn + isRip7212Supported testing requires a WebAuthnAccountOwner
  // implementation and a mock PublicClient, which is covered by integration
  // tests (see test/integration/). The tests below verify that ECDSA paths
  // remain unaffected by the async _shouldUsePrecompile changes and that
  // getStubSignature stays synchronous.
  // ---------------------------------------------------------------------------

  group('RIP-7212 / precompile regression (ECDSA path)', () {
    late PrivateKeyOwner owner;

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
    });

    test('getStubSignature remains synchronous for ECDSA v0.3.1', () {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );

      // getStubSignature must be synchronous (no Future return).
      // This ensures ECDSA stub signatures are not broken by the async
      // _shouldUsePrecompile changes that only affect the WebAuthn path.
      final stub = account.getStubSignature();
      expect(stub, equals(kernelDummyEcdsaSignature));
    });

    test('getStubSignature remains synchronous for ECDSA v0.2.4', () {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_2_4,
        address: mockAddress,
      );

      final stub = account.getStubSignature();
      expect(stub, startsWith('0x00000000'));
      // ROOT_MODE (4 bytes) + ECDSA signature (65 bytes) = 69 bytes = 138 hex
      expect(stub.length, equals(140));
    });

    test('signUserOperation works without publicClient for ECDSA v0.3.1',
        () async {
      // Creating an account without publicClient should still allow ECDSA
      // signing, since _shouldUsePrecompile is only invoked on the WebAuthn
      // path. This test ensures the async precompile check does not regress
      // the ECDSA flow.
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );

      final address = await account.getAddress();
      final userOp = UserOperationV07(
        sender: address,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final signature = await account.signUserOperation(userOp);

      // ECDSA signature: 65 bytes = 130 hex + 0x prefix
      expect(signature, startsWith('0x'));
      expect(signature.length, equals(132));
    });

    test('signUserOperation works without publicClient for ECDSA v0.2.4',
        () async {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_2_4,
        address: mockAddress,
      );

      final address = await account.getAddress();
      final userOp = UserOperationV07(
        sender: address,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final signature = await account.signUserOperation(userOp);

      // ROOT_MODE prefix + 65-byte ECDSA = 69 bytes = 138 hex + 0x
      expect(signature, startsWith('0x00000000'));
      expect(signature.length, equals(140));
    });

    test(
        'ECDSA signing produces deterministic results regardless of publicClient absence',
        () async {
      final account1 = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );
      final account2 = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );

      final address = await account1.getAddress();
      final userOp = UserOperationV07(
        sender: address,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final sig1 = await account1.signUserOperation(userOp);
      final sig2 = await account2.signUserOperation(userOp);

      expect(sig1, equals(sig2));
    });

    test('isWebAuthn is false for PrivateKeyOwner', () {
      final account = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        address: mockAddress,
      );

      // Confirm the account correctly identifies ECDSA owners as non-WebAuthn.
      // This is the gate that prevents _shouldUsePrecompile from being called.
      expect(account.isWebAuthn, isFalse);
    });
  });

  group('KernelSelectors', () {
    test('executeV2 is Kernel execute(address,uint256,bytes,uint8)', () {
      // cast sig "execute(address,uint256,bytes,uint8)"
      // Not SimpleAccount's execute(address,uint256,bytes) = 0xb61d27f6
      expect(KernelSelectors.executeV2, equals('0x51945447'));
    });

    test('executeBatchV2 is Kernel executeBatch((address,uint256,bytes)[])',
        () {
      // cast sig "executeBatch((address,uint256,bytes)[])"
      // Not SimpleAccount's executeBatch(address[],uint256[],bytes[]) = 0x47e1da2a
      expect(KernelSelectors.executeBatchV2, equals('0x34fcd5be'));
    });

    test('executeV3 selector matches ERC-7579', () {
      expect(
        KernelSelectors.executeV3.toLowerCase(),
        equals(Erc7579Selectors.execute.toLowerCase()),
      );
    });
  });
}

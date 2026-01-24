import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  // Test private key (DO NOT use in production)
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  // Expected address for the test private key
  const expectedOwnerAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  group('EtherspotAddresses', () {
    test('factory has correct address', () {
      expect(
        EtherspotAddresses.factory.hex.toLowerCase(),
        equals('0x2a40091f044e48deb5c0fcbc442e443f3341b451'),
      );
    });

    test('bootstrap has correct address', () {
      expect(
        EtherspotAddresses.bootstrap.hex.toLowerCase(),
        equals('0x0d5154d7751b6e2fdaa06f0cc9b400549394c8aa'),
      );
    });

    test('ecdsaValidator has correct address', () {
      expect(
        EtherspotAddresses.ecdsaValidator.hex.toLowerCase(),
        equals('0x0740ed7c11b9da33d9c80bd76b826e4e90cc1906'),
      );
    });
  });

  group('EtherspotSelectors', () {
    test('createAccount selector is correct', () {
      // createAccount(bytes32,bytes) = 0xf8a59370
      expect(EtherspotSelectors.createAccount, equals('0xf8a59370'));
    });

    test('initMSA selector is correct', () {
      expect(EtherspotSelectors.initMSA, equals('0x642219af'));
    });

    test('execute selector is correct', () {
      expect(EtherspotSelectors.execute, equals('0x61461954'));
    });
  });

  group('PrivateKeyOwner', () {
    test('derives correct address from private key', () {
      final owner = PrivateKeyOwner(testPrivateKey);
      expect(
        owner.address.hex.toLowerCase(),
        equals(expectedOwnerAddress.toLowerCase()),
      );
    });

    test('signs hash and returns valid signature', () async {
      final owner = PrivateKeyOwner(testPrivateKey);
      const messageHash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

      final signature = await owner.signPersonalMessage(messageHash);

      expect(signature.startsWith('0x'), isTrue);
      // 65 bytes = 130 hex chars + 2 for '0x'
      expect(signature.length, equals(132));
    });

    test('produces deterministic signatures', () async {
      final owner = PrivateKeyOwner(testPrivateKey);
      const messageHash =
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

      final sig1 = await owner.signPersonalMessage(messageHash);
      final sig2 = await owner.signPersonalMessage(messageHash);

      expect(sig1, equals(sig2));
    });
  });

  group('EtherspotSmartAccount', () {
    late PrivateKeyOwner owner;
    late EtherspotSmartAccount account;

    // Mock account address (would normally be computed via getSenderAddress)
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    setUp(() {
      owner = PrivateKeyOwner(testPrivateKey);
      account = createEtherspotSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        address: mockAddress,
      );
    });

    group('creation', () {
      test('creates account with default index', () {
        expect(account.index, equals(BigInt.zero));
      });

      test('creates account with custom index', () {
        final customAccount = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          index: BigInt.from(42),
        );
        expect(customAccount.index, equals(BigInt.from(42)));
      });

      test('uses correct entry point', () {
        expect(
          account.entryPoint.hex.toLowerCase(),
          equals(EntryPointAddresses.v07.hex.toLowerCase()),
        );
      });

      test('uses correct chain ID', () {
        expect(account.chainId, equals(BigInt.from(1)));
      });
    });

    group('address', () {
      test('throws StateError when address not provided', () async {
        final accountWithoutAddress = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
        );

        expect(
          accountWithoutAddress.getAddress,
          throwsA(isA<StateError>()),
        );
      });

      test('returns provided address', () async {
        final providedAddress = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );
        final accountWithAddress = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: providedAddress,
        );

        final address = await accountWithAddress.getAddress();
        expect(
          address.hex.toLowerCase(),
          equals(providedAddress.hex.toLowerCase()),
        );
      });

      test('caches address after first retrieval', () async {
        final providedAddress = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        );
        final accountWithAddress = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          address: providedAddress,
        );

        final address1 = await accountWithAddress.getAddress();
        final address2 = await accountWithAddress.getAddress();

        expect(identical(address1, address2), isTrue);
      });
    });

    group('factory data', () {
      test('returns factory data record', () async {
        final factoryData = await account.getFactoryData();

        expect(factoryData, isNotNull);
        expect(factoryData!.factory.hex, equals(account.factory.hex));
        expect(factoryData.factoryData.startsWith('0x'), isTrue);
      });

      test('factory data contains createAccount selector', () async {
        final factoryData = await account.getFactoryData();

        expect(
          factoryData!.factoryData.toLowerCase().substring(0, 10),
          equals(EtherspotSelectors.createAccount.toLowerCase()),
        );
      });
    });

    group('init code', () {
      test('returns init code', () async {
        final initCode = await account.getInitCode();

        expect(initCode.startsWith('0x'), isTrue);
        expect(initCode.length, greaterThan(2));
      });

      test('init code starts with factory address', () async {
        final initCode = await account.getInitCode();
        final factoryHex = account.factory.hex.toLowerCase().substring(2);

        expect(initCode.toLowerCase().substring(2, 42), equals(factoryHex));
      });
    });

    group('call encoding', () {
      test('encodes single call with ERC-7579', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000000000000000000),
          data: '0xabcdef',
        );

        final encoded = account.encodeCall(call);

        expect(encoded.startsWith('0x'), isTrue);
        // Should start with ERC-7579 execute selector
        expect(
          encoded.substring(0, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.toLowerCase()),
        );
      });

      test('encodes batch calls with ERC-7579', () {
        final calls = [
          Call(
            to: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            value: BigInt.zero,
            data: '0x11',
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.from(1000),
            data: '0x22',
          ),
        ];

        final encoded = account.encodeCalls(calls);

        expect(encoded.startsWith('0x'), isTrue);
        expect(
          encoded.substring(0, 10).toLowerCase(),
          equals(Erc7579Selectors.execute.toLowerCase()),
        );
      });

      test('single call optimization in encodeCalls', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        final singleEncoded = account.encodeCall(call);
        final batchEncodedSingle = account.encodeCalls([call]);

        expect(singleEncoded, equals(batchEncodedSingle));
      });

      test('throws on empty calls list', () {
        expect(
          () => account.encodeCalls([]),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('stub signature', () {
      test('returns stub signature without validator prefix', () {
        final stubSig = account.getStubSignature();

        expect(stubSig.startsWith('0x'), isTrue);
        // 65 bytes ECDSA signature = 130 hex chars + 2 for '0x'
        expect(stubSig.length, equals(132));
      });

      test('stub signature matches dummy ECDSA signature', () {
        final stubSig = account.getStubSignature();

        expect(stubSig, equals(etherspotDummyEcdsaSignature));
      });
    });

    group('sign user operation', () {
      test('signs user operation without validator prefix', () async {
        final userOp = UserOperationV07(
          sender: await account.getAddress(),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final signature = await account.signUserOperation(userOp);

        expect(signature.startsWith('0x'), isTrue);
        // 65 bytes ECDSA signature = 130 hex chars + 2 for '0x'
        // Unlike signMessage/signTypedData, signUserOperation does NOT prepend validator
        expect(signature.length, equals(132));
      });

      test('produces deterministic signature', () async {
        final userOp = UserOperationV07(
          sender: await account.getAddress(),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final signature1 = await account.signUserOperation(userOp);
        final signature2 = await account.signUserOperation(userOp);

        expect(signature1, equals(signature2));
      });
    });

    group('nonce key', () {
      test('encodes validator address with mode and type', () {
        final nonceKey = account.nonceKey;

        // Etherspot nonce key encoding:
        // validatorAddress (20 bytes) + validatorMode (1 byte) + validatorType (1 byte) + nonceKey (2 bytes)
        final validatorHex = account.ecdsaValidator.hex.substring(2);
        const validatorMode = '00'; // DEFAULT
        const validatorType = '00'; // ROOT
        const nonceKeySuffix = '0000'; // 2 bytes

        final expectedEncoding =
            '$validatorHex$validatorMode$validatorType$nonceKeySuffix';
        final expectedNonceKey = BigInt.parse(expectedEncoding, radix: 16);

        expect(nonceKey, equals(expectedNonceKey));
      });

      test('nonce key encodes 24 bytes total', () {
        final nonceKey = account.nonceKey;

        // 24 bytes = 48 hex chars
        final hexLength = nonceKey.toRadixString(16).length;
        expect(hexLength, lessThanOrEqualTo(48)); // May have leading zeros
      });
    });

    group('custom addresses', () {
      test('uses custom meta factory when provided', () {
        final customFactory = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final customAccount = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          customAddresses: EtherspotCustomAddresses(
            factory: customFactory,
          ),
        );

        expect(customAccount.factory.hex, equals(customFactory.hex));
      });

      test('uses custom validator when provided', () {
        final customValidator = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );
        final customAccount = createEtherspotSmartAccount(
          owner: owner,
          chainId: BigInt.from(1),
          customAddresses: EtherspotCustomAddresses(
            ecdsaValidator: customValidator,
          ),
        );

        expect(customAccount.ecdsaValidator.hex, equals(customValidator.hex));
      });
    });
  });
}

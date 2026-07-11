import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Minimal test-local double for [WebAuthnAccountOwner].
///
/// The real subclasses live in `permissionless_passkeys`; importing that
/// package here would create a reverse dependency. For address-derivation
/// tests we only need stable `x`/`y` (which drive the base-class `address`)
/// and a `credentialId`. `signP256` is never invoked, so it throws.
class _TestWebAuthnOwner extends WebAuthnAccountOwner {
  const _TestWebAuthnOwner(this.x, this.y, this.credentialId);

  @override
  final BigInt x;

  @override
  final BigInt y;

  @override
  final Uint8List credentialId;

  @override
  Future<P256SignatureData> signP256(String hash) {
    throw UnsupportedError('test double: signP256 not implemented');
  }
}

void main() {
  // Test private key (DO NOT use in production!)
  // This is a well-known test key from Foundry/Hardhat
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  final testOwnerAddress =
      EthereumAddress.fromHex('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266');

  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  group('SafeSmartAccount', () {
    group('creation', () {
      test('creates account with single owner', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.owners.length, equals(1));
        expect(account.threshold, equals(BigInt.one));
        expect(account.version, equals(SafeVersion.v1_4_1));
        expect(account.entryPointVersion, equals(EntryPointVersion.v07));
      });

      test('creates account with multiple owners and threshold', () {
        final owner1 = PrivateKeyOwner(testPrivateKey);
        // Second test key from Foundry
        final owner2 = PrivateKeyOwner(
          '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        );

        final account = createSafeSmartAccount(
          owners: [owner1, owner2],
          threshold: BigInt.from(2),
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.owners.length, equals(2));
        expect(account.threshold, equals(BigInt.from(2)));
      });

      test('throws when no owners provided', () {
        expect(
          () => createSafeSmartAccount(
            owners: [],
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('throws when threshold exceeds owner count', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            threshold: BigInt.from(2),
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('throws when threshold is zero', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            threshold: BigInt.zero,
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });

      test('creates account with Safe v1.5.0', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          version: SafeVersion.v1_5_0,
          entryPointVersion: EntryPointVersion.v07,
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.version, equals(SafeVersion.v1_5_0));
      });

      test('throws for unsupported version combination', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        // Safe 1.5.0 doesn't support EntryPoint v0.6
        expect(
          () => createSafeSmartAccount(
            owners: [owner],
            version: SafeVersion.v1_5_0,
            entryPointVersion: EntryPointVersion.v06,
            chainId: BigInt.from(1),
          ),
          throwsArgumentError,
        );
      });
    });

    group('getAddress', () {
      test('returns deterministic address', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final address = await account.getAddress();
        expect(address.hex.startsWith('0x'), isTrue);
        expect(address.hex.length, equals(42));
      });

      test('same config produces same address', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final account1 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );
        final account2 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1, equals(address2));
      });

      test('different salt produces different address', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final mockAddress1 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account1 = createSafeSmartAccount(
          owners: [owner],
          saltNonce: BigInt.from(0),
          chainId: BigInt.from(1),
          address: mockAddress1,
        );
        final account2 = createSafeSmartAccount(
          owners: [owner],
          saltNonce: BigInt.from(1),
          chainId: BigInt.from(1),
          address: mockAddress2,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1, isNot(equals(address2)));
      });

      test('different owners produce different address', () async {
        final owner1 = PrivateKeyOwner(testPrivateKey);
        final owner2 = PrivateKeyOwner(
          '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        );
        final mockAddress1 = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111',
        );
        final mockAddress2 = EthereumAddress.fromHex(
          '0x2222222222222222222222222222222222222222',
        );

        final account1 = createSafeSmartAccount(
          owners: [owner1],
          chainId: BigInt.from(1),
          address: mockAddress1,
        );
        final account2 = createSafeSmartAccount(
          owners: [owner2],
          chainId: BigInt.from(1),
          address: mockAddress2,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1, isNot(equals(address2)));
      });
    });

    group('getInitCode', () {
      test('returns valid init code', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final initCode = await account.getInitCode();

        // Init code starts with factory address (20 bytes = 40 hex chars + 0x)
        expect(initCode.startsWith('0x'), isTrue);
        expect(initCode.length > 42, isTrue);
      });

      test('init code starts with proxy factory address', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final initCode = await account.getInitCode();
        final addresses = SafeVersionAddresses.getAddresses(
          SafeVersion.v1_4_1,
          EntryPointVersion.v07,
        )!;

        // First 20 bytes should be factory address
        final factoryFromInitCode = initCode.substring(0, 42);
        expect(
          factoryFromInitCode.toLowerCase(),
          equals(addresses.safeProxyFactoryAddress.hex.toLowerCase()),
        );
      });
    });

    group('getFactoryData', () {
      test('returns factory and data', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final result = await account.getFactoryData();

        expect(result, isNotNull);
        expect(result!.factory.hex.startsWith('0x'), isTrue);
        expect(result.factoryData.startsWith('0x'), isTrue);
      });
    });

    group('encodeCall', () {
      test('encodes single call', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000000000000000000), // 1 ETH
            data: '0x',
          ),
        );

        expect(encoded.startsWith('0x'), isTrue);
        // Should contain executeUserOpWithErrorString selector
        expect(encoded.length > 10, isTrue);
      });

      test('encodes call with data', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data:
                '0xa9059cbb0000000000000000000000001234567890123456789012345678901234567890000000000000000000000000000000000000000000000000000000000000000a',
          ),
        );

        expect(encoded.startsWith('0x'), isTrue);
      });
    });

    group('encodeCalls', () {
      test('single call delegates to encodeCall', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
        );

        final encodedSingle = account.encodeCall(call);
        final encodedMultiple = account.encodeCalls([call]);

        expect(encodedSingle, equals(encodedMultiple));
      });

      test('multiple calls use MultiSend', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final encoded = account.encodeCalls([
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x0987654321098765432109876543210987654321',
            ),
            value: BigInt.from(2000),
          ),
        ]);

        expect(encoded.startsWith('0x'), isTrue);
        // MultiSend calls are typically longer
        expect(encoded.length > 200, isTrue);
      });

      test('throws on empty calls', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(
          () => account.encodeCalls([]),
          throwsArgumentError,
        );
      });
    });

    group('getStubSignature', () {
      test('returns valid stub signature', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final stub = account.getStubSignature();
        expect(stub.startsWith('0x'), isTrue);
        // 6 bytes validAfter + 6 bytes validUntil + 65 bytes per signature
        expect(stub.length, equals(2 + 12 + 12 + 130)); // 0x + 6*2 + 6*2 + 65*2
      });

      test('stub signature length scales with owners', () {
        final owner1 = PrivateKeyOwner(testPrivateKey);
        final owner2 = PrivateKeyOwner(
          '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        );

        final account1 = createSafeSmartAccount(
          owners: [owner1],
          chainId: BigInt.from(1),
          address: mockAddress,
        );
        final account2 = createSafeSmartAccount(
          owners: [owner1, owner2],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final stub1 = account1.getStubSignature();
        final stub2 = account2.getStubSignature();

        // Each additional owner adds 65 bytes (130 hex chars)
        expect(stub2.length - stub1.length, equals(130));
      });
    });

    group('signUserOperation', () {
      test('signs user operation', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
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

        expect(signature.startsWith('0x'), isTrue);
        // Should have validAfter, validUntil, and signature
        expect(signature.length > 12 + 12, isTrue);
      });

      test('signature changes with different nonce', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final address = await account.getAddress();

        final userOp1 = UserOperationV07(
          sender: address,
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final userOp2 = userOp1.copyWith(nonce: BigInt.one);

        final sig1 = await account.signUserOperation(userOp1);
        final sig2 = await account.signUserOperation(userOp2);

        expect(sig1, isNot(equals(sig2)));
      });

      test(
        'v0.6 EIP-712 SafeOp signature matches permissionless.js fixture',
        () async {
          final owner = PrivateKeyOwner(testPrivateKey);
          final account = createSafeSmartAccount(
            owners: [owner],
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
            signature: '0x',
          );

          final signature = await account.signUserOperationV06(userOp);

          // viem signTypedData over EIP712_SAFE_OPERATION_TYPE_V06 with
          // Safe4337Module 0xa581c4A4…4037, validAfter=0, validUntil=0,
          // then packed as uint48‖uint48‖sig.
          expect(
            signature.toLowerCase(),
            equals(
              '0x000000000000000000000000c43b190628af4f8c76904c710f7a0f081556482309ff0352d0351986e0c8fecc298b32f1ccb48415db61fc1ef259f328e52e611cb13a51194a31c75036abbb971b',
            ),
          );
        },
      );

      test('v0.6 throws when signUserOperation (v0.7 API) is used', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        final userOp = UserOperationV07(
          sender: mockAddress,
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
        );

        expect(
          () => account.signUserOperation(userOp),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('v0.7 throws when signUserOperationV06 is used', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v07,
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

        expect(
          () => account.signUserOperationV06(userOp),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('implements SmartAccountV06 for client v0.6 pipeline', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: mockAddress,
        );

        expect(account, isA<SmartAccountV06>());
      });
    });

    group('useMultiSendForSetup', () {
      // Expected CREATE2 addresses generated by calling
      // `toSafeSmartAccount` from permissionless.js@0.3.5 with the fixed
      // input (testPrivateKey, saltNonce=0n, version: '1.4.1',
      // entryPoint: { address: entryPoint07Address, version: '0.7' },
      // chainId=1) twice — once with useMultiSendForSetup: true (yields
      // multiSendAddress) and once with useMultiSendForSetup: false
      // (yields directSetupAddress). The JS transport is stubbed to
      // return chainId=1 and empty getCode; no network is required since
      // CREATE2 derivation is purely local.
      final multiSendAddress = EthereumAddress.fromHex(
        '0x124Ef647181eda69861b61596802129E3B018765',
      );
      final directSetupAddress = EthereumAddress.fromHex(
        '0x08eA90D108291a05830B25E8eFaF027979dEb8D1',
      );

      test('default is true (backwards compatible)', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final accountDefault = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
        );
        final accountExplicit = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          useMultiSendForSetup: true,
        );

        final defaultAddress = await accountDefault.getAddress();
        final explicitAddress = await accountExplicit.getAddress();

        expect(defaultAddress, equals(explicitAddress));
        expect(defaultAddress, equals(multiSendAddress));
      });

      test(
        'useMultiSendForSetup: false matches permissionless.js@0.3.5 vector',
        () async {
          final owner = PrivateKeyOwner(testPrivateKey);
          final account = createSafeSmartAccount(
            owners: [owner],
            chainId: BigInt.one,
            useMultiSendForSetup: false,
          );

          final address = await account.getAddress();

          expect(address, equals(directSetupAddress));
        },
      );

      test(
        'useMultiSendForSetup false vs true produce different addresses',
        () async {
          final owner = PrivateKeyOwner(testPrivateKey);

          final accountTrue = createSafeSmartAccount(
            owners: [owner],
            chainId: BigInt.one,
            useMultiSendForSetup: true,
          );
          final accountFalse = createSafeSmartAccount(
            owners: [owner],
            chainId: BigInt.one,
            useMultiSendForSetup: false,
          );

          final addressTrue = await accountTrue.getAddress();
          final addressFalse = await accountFalse.getAddress();

          expect(addressTrue, isNot(equals(addressFalse)));
        },
      );

      test(
        'useMultiSendForSetup is ignored when a WebAuthn owner is present',
        () async {
          // When any owner is a WebAuthn owner, the Safe.setup fast path is
          // guarded off (see safe_account.dart `!_hasWebAuthnOwner`). Both
          // `useMultiSendForSetup: true` and `false` must therefore produce
          // the same CREATE2 address since both go through the MultiSend
          // initializer branch.
          final webAuthnOwner = _TestWebAuthnOwner(
            BigInt.from(0x1234),
            BigInt.from(0x5678),
            Uint8List.fromList(
              List<int>.generate(16, (i) => i),
            ),
          );

          final accountTrue = createSafeSmartAccount(
            owners: [webAuthnOwner],
            chainId: BigInt.one,
            useMultiSendForSetup: true,
          );
          final accountFalse = createSafeSmartAccount(
            owners: [webAuthnOwner],
            chainId: BigInt.one,
            useMultiSendForSetup: false,
          );

          final addressTrue = await accountTrue.getAddress();
          final addressFalse = await accountFalse.getAddress();

          expect(addressTrue, equals(addressFalse));
        },
      );

      test('useMultiSendForSetup is ignored in ERC-7579 mode', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final accountDefault = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );
        final accountFalse = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.one,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          useMultiSendForSetup: false,
        );

        final defaultAddress = await accountDefault.getAddress();
        final falseAddress = await accountFalse.getAddress();

        // In ERC-7579 mode, _getInitializer() routes to _get7579Initializer()
        // and never consults useMultiSendForSetup, so both addresses match.
        expect(falseAddress, equals(defaultAddress));
      });
    });
  });

  group('PrivateKeyOwner', () {
    test('derives correct address', () {
      final owner = PrivateKeyOwner(testPrivateKey);
      expect(
        owner.address.hex.toLowerCase(),
        equals(testOwnerAddress.hex.toLowerCase()),
      );
    });

    test('signs message', () async {
      final owner = PrivateKeyOwner(testPrivateKey);
      final hash = '0x${'00' * 32}'; // 32 zero bytes

      final signature = await owner.signPersonalMessage(hash);

      expect(signature.startsWith('0x'), isTrue);
      expect(signature.length, equals(132)); // 0x + 65 bytes * 2
    });
  });

  group('SafeVersionAddresses', () {
    // Fixtures from permissionless.js `toSafeSmartAccount.ts` SAFE_VERSION_TO_ADDRESSES_MAP.
    // Independent source of truth for parity — do not derive from Dart constants.
    void expectMatchesJsTable(
      SafeAddresses actual, {
      required String safeModuleSetupAddress,
      required String safe4337ModuleAddress,
      required String safeProxyFactoryAddress,
      required String safeSingletonAddress,
      required String multiSendAddress,
      required String multiSendCallOnlyAddress,
      String? webAuthnSharedSignerAddress,
      String? safeP256VerifierAddress,
    }) {
      expect(
        actual.safeModuleSetupAddress,
        equals(EthereumAddress.fromHex(safeModuleSetupAddress)),
      );
      expect(
        actual.safe4337ModuleAddress,
        equals(EthereumAddress.fromHex(safe4337ModuleAddress)),
      );
      expect(
        actual.safeProxyFactoryAddress,
        equals(EthereumAddress.fromHex(safeProxyFactoryAddress)),
      );
      expect(
        actual.safeSingletonAddress,
        equals(EthereumAddress.fromHex(safeSingletonAddress)),
      );
      expect(
        actual.multiSendAddress,
        equals(EthereumAddress.fromHex(multiSendAddress)),
      );
      expect(
        actual.multiSendCallOnlyAddress,
        equals(EthereumAddress.fromHex(multiSendCallOnlyAddress)),
      );
      if (webAuthnSharedSignerAddress == null) {
        expect(actual.webAuthnSharedSignerAddress, isNull);
      } else {
        expect(
          actual.webAuthnSharedSignerAddress,
          equals(EthereumAddress.fromHex(webAuthnSharedSignerAddress)),
        );
      }
      if (safeP256VerifierAddress == null) {
        expect(actual.safeP256VerifierAddress, isNull);
      } else {
        expect(
          actual.safeP256VerifierAddress,
          equals(EthereumAddress.fromHex(safeP256VerifierAddress)),
        );
      }
    }

    test('returns addresses for v1.4.1 + EP v0.6', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_4_1,
        EntryPointVersion.v06,
      );

      expect(addresses, isNotNull);
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x8EcD4ec46D4D2a6B64fE960B3D64e8B94B2234eb',
        safe4337ModuleAddress: '0xa581c4A4DB7175302464fF3C06380BC3270b4037',
        safeProxyFactoryAddress: '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        safeSingletonAddress: '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        multiSendAddress: '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        multiSendCallOnlyAddress: '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
      );
    });

    test('returns addresses for v1.4.1 + EP v0.7', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_4_1,
        EntryPointVersion.v07,
      );

      expect(addresses, isNotNull);
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        safe4337ModuleAddress: '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        safeProxyFactoryAddress: '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        safeSingletonAddress: '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        multiSendAddress: '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        multiSendCallOnlyAddress: '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
        webAuthnSharedSignerAddress:
            '0x94a4F6affBd8975951142c3999aEAB7ecee555c2',
        safeP256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
      );
    });

    test('returns addresses for v1.5.0 + EP v0.7', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_5_0,
        EntryPointVersion.v07,
      );

      expect(addresses, isNotNull);
      // JS: MULTI_SEND_CALL_ONLY_ADDRESS 0xA83c…1836 (Etherscan: MultiSendCallOnly, verified)
      expectMatchesJsTable(
        addresses!,
        safeModuleSetupAddress: '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        safe4337ModuleAddress: '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        safeProxyFactoryAddress: '0x14F2982D601c9458F93bd70B218933A6f8165e7b',
        safeSingletonAddress: '0xFf51A5898e281Db6DfC7855790607438dF2ca44b',
        multiSendAddress: '0x218543288004CD07832472D464648173c77D7eB7',
        multiSendCallOnlyAddress: '0xA83c336B20401Af773B6219BA5027174338D1836',
        webAuthnSharedSignerAddress:
            '0x94a4F6affBd8975951142c3999aEAB7ecee555c2',
        safeP256VerifierAddress: '0xA86e0054C51E4894D88762a017ECc5E5235f5DBA',
      );
    });

    test('returns null for v1.5.0 + EP v0.6', () {
      final addresses = SafeVersionAddresses.getAddresses(
        SafeVersion.v1_5_0,
        EntryPointVersion.v06,
      );

      expect(addresses, isNull);
    });
  });

  // ===========================================================================
  // ERC-7579 Mode Tests
  // ===========================================================================

  group('SafeSmartAccount ERC-7579 Mode', () {
    // Test private key (DO NOT use in production!)
    const testPrivateKey =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    group('creation', () {
      test('creates account with ERC-7579 enabled', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        expect(account.isErc7579Enabled, isTrue);
      });

      test('creates account with ERC-7579 disabled by default', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        expect(account.isErc7579Enabled, isFalse);
      });

      test('creates account with attesters and threshold', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        expect(account.isErc7579Enabled, isTrue);
      });

      test('creates account with module configurations', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final validatorAddress = EthereumAddress.fromHex(
          '0xabcdef1234567890abcdef1234567890abcdef12',
        );

        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          validators: [
            Safe7579ModuleInit(module: validatorAddress, initData: '0x1234'),
          ],
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        expect(account.isErc7579Enabled, isTrue);
      });
    });

    group('getAddress', () {
      test('7579 and non-7579 produce different addresses', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final standardAccount = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
        );

        final erc7579Account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final standardAddress = await standardAccount.getAddress();
        final erc7579Address = await erc7579Account.getAddress();

        // Different modes produce different addresses due to different singletons
        expect(standardAddress, isNot(equals(erc7579Address)));
      });

      test('same 7579 config produces same address', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final account1 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final account2 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        expect(address1, equals(address2));
      });
    });

    group('getInitCode', () {
      test('7579 init code uses launchpad singleton', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final initCode = await account.getInitCode();

        expect(initCode.startsWith('0x'), isTrue);
        // Init code should be longer due to 7579 initialization data
        expect(initCode.length > 100, isTrue);
      });

      test('7579 and non-7579 produce different init codes', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final standardAccount = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final erc7579Account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final standardInitCode = await standardAccount.getInitCode();
        final erc7579InitCode = await erc7579Account.getInitCode();

        // Different modes produce different init codes
        expect(standardInitCode, isNot(equals(erc7579InitCode)));
      });
    });

    group('encodeCalls', () {
      test('7579 mode uses ERC-7579 execute encoding', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
            data: '0x',
          ),
        );

        // ERC-7579 execute selector: 0xe9ae5c53
        expect(encoded.startsWith('0xe9ae5c53'), isTrue);
      });

      test('standard mode uses executeUserOp encoding', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
        );

        final encoded = account.encodeCall(
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
            data: '0x',
          ),
        );

        // executeUserOpWithErrorString selector is different from 7579
        expect(encoded.startsWith('0xe9ae5c53'), isFalse);
      });

      test('7579 batch encoding uses correct format', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final encoded = account.encodeCalls([
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
          ),
          Call(
            to: EthereumAddress.fromHex(
              '0x0987654321098765432109876543210987654321',
            ),
            value: BigInt.from(2000),
          ),
        ]);

        // ERC-7579 execute selector
        expect(encoded.startsWith('0xe9ae5c53'), isTrue);
      });
    });

    group('signUserOperation', () {
      test('signs user operation in 7579 mode', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
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

        expect(signature.startsWith('0x'), isTrue);
        // Should have validAfter, validUntil, and signature
        expect(signature.length > 12 + 12, isTrue);
      });
    });

    group('encodeCallsForDeployment', () {
      test('uses setupSafe encoding for first deployment', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final encoded = account.encodeCallsForDeployment([
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.from(1000),
            data: '0x',
          ),
        ]);

        // setupSafe selector: 0xd9ed0e8f
        expect(encoded.startsWith('0xd9ed0e8f'), isTrue);
      });

      test('setupSafe encoding is different from regular encoding', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        );

        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0x',
        );

        final deploymentEncoded = account.encodeCallsForDeployment([call]);
        final regularEncoded = account.encodeCalls([call]);

        // Deployment uses setupSafe (0xd9ed0e8f), regular uses execute (0xe9ae5c53)
        expect(deploymentEncoded.startsWith('0xd9ed0e8f'), isTrue);
        expect(regularEncoded.startsWith('0xe9ae5c53'), isTrue);
        expect(deploymentEncoded, isNot(equals(regularEncoded)));
      });

      test('standard mode falls back to regular encoding', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          // No erc7579LaunchpadAddress - standard mode
        );

        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.from(1000),
          data: '0x',
        );

        final deploymentEncoded = account.encodeCallsForDeployment([call]);
        final regularEncoded = account.encodeCalls([call]);

        // In standard mode, both should be the same
        expect(deploymentEncoded, equals(regularEncoded));
      });

      test('includes full InitData in setupSafe encoding', () {
        final owner = PrivateKeyOwner(testPrivateKey);
        final validatorAddress = EthereumAddress.fromHex(
          '0xabcdef1234567890abcdef1234567890abcdef12',
        );

        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          address: mockAddress,
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          validators: [
            Safe7579ModuleInit(module: validatorAddress, initData: '0x1234'),
          ],
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final encoded = account.encodeCallsForDeployment([
          Call(
            to: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890',
            ),
            value: BigInt.zero,
            data: '0x',
          ),
        ]);

        // setupSafe selector
        expect(encoded.startsWith('0xd9ed0e8f'), isTrue);
        // Should be longer due to full InitData struct
        expect(encoded.length > 500, isTrue);
      });
    });

    group('7579 initializer', () {
      test('uses preValidationSetup selector', () async {
        final owner = PrivateKeyOwner(testPrivateKey);
        final account = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final initCode = await account.getInitCode();

        // preValidationSetup selector: 0x4fff40e1
        // It's embedded in the factory data, after the createProxyWithNonce call
        expect(initCode.contains('4fff40e1'), isTrue);
      });

      test('different attesters produce different addresses', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final account1 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [Safe7579Addresses.rhinestoneAttester],
          attestersThreshold: 1,
        );

        final account2 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          attesters: [
            EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
          ],
          attestersThreshold: 1,
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        // Different attesters change initSafe7579 data, thus initHash, thus address
        expect(address1, isNot(equals(address2)));
      });

      test('different validators produce different addresses', () async {
        final owner = PrivateKeyOwner(testPrivateKey);

        final account1 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          validators: [
            Safe7579ModuleInit(
              module: EthereumAddress.fromHex(
                '0xaaaa111111111111111111111111111111111111',
              ),
            ),
          ],
        );

        final account2 = createSafeSmartAccount(
          owners: [owner],
          chainId: BigInt.from(1),
          erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
          validators: [
            Safe7579ModuleInit(
              module: EthereumAddress.fromHex(
                '0xbbbb222222222222222222222222222222222222',
              ),
            ),
          ],
        );

        final address1 = await account1.getAddress();
        final address2 = await account2.getAddress();

        // Different validators change initHash (they're part of InitData struct)
        expect(address1, isNot(equals(address2)));
      });
    });
  });

  group('Safe7579Addresses', () {
    test('has correct Safe7579 module address', () {
      expect(
        Safe7579Addresses.safe7579ModuleAddress.hex.toLowerCase(),
        equals('0x7579ee8307284f293b1927136486880611f20002'),
      );
    });

    test('has correct launchpad address', () {
      expect(
        Safe7579Addresses.erc7579LaunchpadAddress.hex.toLowerCase(),
        equals('0x7579011ab74c46090561ea277ba79d510c6c00ff'),
      );
    });

    test('has correct Rhinestone attester address', () {
      expect(
        Safe7579Addresses.rhinestoneAttester.hex.toLowerCase(),
        equals('0x000000333034e9f539ce08819e12c1b8cb29084d'),
      );
    });
  });
}

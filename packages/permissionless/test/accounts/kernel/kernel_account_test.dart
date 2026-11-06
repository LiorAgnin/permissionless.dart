import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:permissionless/src/accounts/kernel/kernel_abi.dart';
import 'package:permissionless/src/accounts/standard_execute.dart';
import 'package:test/test.dart';

void main() {
  // Test private key (Hardhat account 0 - DO NOT use in production!)
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  // Mock address for unit tests (avoids RPC calls)
  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

  // ---- permissionless.js fixtures ----
  // permissionless.js 0.5.2 (source at a536891) toKernelSmartAccount with
  // viem 2.21.55, owner =
  // privateKeyToAccount(testPrivateKey), address = mockAddress, chainId 1.
  //   jsFactoryDataV031Index123 = v0.3.1, index: 123n, getFactoryArgs()
  //     (lower-cased; viem keeps checksummed addresses inside packed bytes)
  //   jsEncodeSingleV031 = v0.3.1 encodeCalls([{to: mockAddress, 0, 0x}])
  //   jsEncodeBatchV031  = v0.3.1 encodeCalls([{0x11…11, 0, 0x},
  //                        {0x22…22, 100, 0xabcd}])
  //   jsDummyEcdsaSignature = DUMMY_ECDSA_SIGNATURE (v0.3.x getStubSignature)
  //   jsStubV024 = v0.2.4 getStubSignature (ROOT_MODE_KERNEL_V2 ‖ dummy)
  //   jsSignUserOpV031 / jsSignUserOpV024 = signUserOperation of
  //     userOpV07() / userOpV06() below with chainId 1
  const jsFactoryDataV031Index123 =
      '0xc5265d5d000000000000000000000000aac5d4240af87249b3f71bc8e4a2ca'
      'e074a3e419000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '000000007b000000000000000000000000000000000000000000000000000000'
      '00000001243c3b752b01845adb2c711129d4f3966735ed98a9f09fc4ce570000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000a00000000000000000000000000000000000000000000000'
      '0000000000000000e00000000000000000000000000000000000000000000000'
      '0000000000000001000000000000000000000000000000000000000000000000'
      '000000000000000014f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncodeSingleV031 =
      '0xe9ae5c53000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '0000000034123456789012345678901234567890123456789000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsEncodeBatchV031 =
      '0xe9ae5c53010000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '00000001a0000000000000000000000000000000000000000000000000000000'
      '0000000020000000000000000000000000000000000000000000000000000000'
      '0000000002000000000000000000000000000000000000000000000000000000'
      '0000000040000000000000000000000000000000000000000000000000000000'
      '00000000c0000000000000000000000000111111111111111111111111111111'
      '1111111111000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '0000000000000000000000000000000000222222222222222222222222222222'
      '2222222222000000000000000000000000000000000000000000000000000000'
      '0000000064000000000000000000000000000000000000000000000000000000'
      '0000000060000000000000000000000000000000000000000000000000000000'
      '0000000002abcd00000000000000000000000000000000000000000000000000'
      '0000000000';
  const jsDummyEcdsaSignature =
      '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000'
      '007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aa1c';
  const jsStubV024 =
      '0x00000000fffffffffffffffffffffffffffffff00000000000000000000000'
      '00000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaa1c';
  const jsSignUserOpV031 =
      '0x00538c3d1fb4197de5a15394fcaf23ca1a570c63576424c0615656be0e112f'
      '5964840719f944a8d5b0e21ad3a262725d1004ac6a9926ac6299b3f48d1c0c0d'
      '8d1b';
  const jsSignUserOpV024 =
      '0x00000000c6a17ddf898b2b92ca9ad4ca38b8d3eb73d538e199b939b416ebbe'
      '746debeac257952180f7c4e4f5433bf20caf4b1bc5330104661b71f16f8cafee'
      'cba1aba7621b';

  UserOperationV07 userOpV07() => UserOperationV07(
        sender: mockAddress,
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

  UserOperationV06 userOpV06() => UserOperationV06(
        sender: mockAddress,
        nonce: BigInt.zero,
        initCode: '0x',
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

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

    test('uses EntryPoint v0.7', () {
      expect(account.entryPointVersion, equals(EntryPointVersion.v07));
      expect(
        account.entryPoint.hex.toLowerCase(),
        equals('0x0000000071727de22e5e9d8baf0edac6f37da032'),
      );
    });

    test('index is the deployWithFactory salt (permissionless.js)', () async {
      final indexed = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        index: BigInt.from(123),
        address: mockAddress,
      );

      final factoryData = await indexed.getFactoryData();
      expect(
        factoryData!.factory.hex.toLowerCase(),
        equals('0xd703aae79538628d27099b8c4f621be4ccd142d5'),
      );
      expect(factoryData.factoryData, equals(jsFactoryDataV031Index123));
    });

    test('getAddress resolves through getSenderAddress once and caches it',
        () async {
      final requests = <Map<String, dynamic>>[];
      final rpc = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': '0x000000000000000000000000'
                'd8da6bf26964af9d7eed9e03e53415d37aa96045',
          }),
          200,
        );
      });
      final rpcAccount = createKernelSmartAccount(
        owner: owner,
        chainId: BigInt.from(1),
        version: KernelVersion.v0_3_1,
        publicClient: createPublicClient(
          url: 'http://localhost:8545',
          httpClient: rpc,
        ),
      );

      final first = await rpcAccount.getAddress();
      final second = await rpcAccount.getAddress();

      expect(
        first.hex.toLowerCase(),
        equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'),
      );
      expect(second, equals(first));
      expect(requests, hasLength(1));
      expect(requests.single['method'], equals('eth_call'));
      // The init code (pinned in kernel_version_parity_test) is what the
      // EntryPoint helper simulates.
      final tx = (requests.single['params'] as List<dynamic>).first
          as Map<String, dynamic>;
      expect(
        (tx['data'] as String).toLowerCase(),
        contains(Hex.strip0x(await rpcAccount.getInitCode()).toLowerCase()),
      );
    });

    group('call encoding', () {
      final single = Call(
        to: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        value: BigInt.zero,
        data: '0x',
      );

      test('encodes a single call like permissionless.js', () {
        expect(account.encodeCall(single), equals(jsEncodeSingleV031));
      });

      test('encodeCalls with one call uses single-call mode', () {
        expect(account.encodeCalls([single]), equals(jsEncodeSingleV031));
      });

      test('encodes batch calls like permissionless.js', () {
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

        expect(account.encodeCalls(calls), equals(jsEncodeBatchV031));
      });

      test('throws on empty calls list', () {
        expect(
          () => account.encodeCalls([]),
          throwsArgumentError,
        );
      });
    });

    test('stub signature is the permissionless.js ECDSA dummy', () {
      expect(account.getStubSignature(), equals(jsDummyEcdsaSignature));
    });

    group('sign user operation', () {
      test('matches permissionless.js (no validator prefix)', () async {
        expect(
          await account.signUserOperation(userOpV07()),
          equals(jsSignUserOpV031),
        );
      });

      test('rejects a v0.6 UserOperation (EntryPoint v0.7 account)', () async {
        await expectLater(
          account.signUserOperationV06(userOpV06()),
          throwsArgumentError,
        );
      });
    });

    test('nonce key is getNonceKeyWithEncoding(0.3.1, validator, 0)', () {
      // permissionless.js: mode 00 ‖ type 00 ‖ ECDSA validator ‖ key 0000
      expect(
        account.nonceKey,
        equals(
          BigInt.parse(
            '845adb2c711129d4f3966735ed98a9f09fc4ce570000',
            radix: 16,
          ),
        ),
      );
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

    test('uses EntryPoint v0.6', () {
      expect(account.entryPointVersion, equals(EntryPointVersion.v06));
      expect(
        account.entryPoint.hex.toLowerCase(),
        equals('0x5ff137d4b0fdcd49dca30c7cf57e578a026d2789'),
      );
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

      // permissionless.js encodeCallData uses execute (not executeBatch) for
      // a single call.
      test('encodeCalls with one call uses execute like permissionless.js', () {
        final call = Call(
          to: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          value: BigInt.zero,
          data: '0x',
        );

        expect(
          account.encodeCalls([call]).toLowerCase(),
          equals(jsSingleEmpty.toLowerCase()),
        );
      });
    });

    test('stub signature is ROOT_MODE ‖ ECDSA dummy (permissionless.js)', () {
      expect(account.getStubSignature(), equals(jsStubV024));
    });

    group('sign user operation', () {
      test('matches permissionless.js (ROOT_MODE prefix)', () async {
        expect(
          await account.signUserOperationV06(userOpV06()),
          equals(jsSignUserOpV024),
        );
      });

      test('rejects a v0.7 UserOperation (EntryPoint v0.6 account)', () async {
        await expectLater(
          account.signUserOperation(userOpV07()),
          throwsArgumentError,
        );
      });
    });

    test('nonce key is zero (permissionless.js returns the raw key for v2)',
        () {
      expect(account.nonceKey, equals(BigInt.zero));
    });
  });

  group('RIP-7212 / precompile flag (WebAuthn path)', () {
    setUp(clearRip7212Cache);

    final p256Signature = P256SignatureData(
      r: BigInt.from(7),
      s: BigInt.from(9),
      authenticatorData: Uint8List(37),
      clientDataJSON: '{"type":"webauthn.get","challenge":"AA","origin":"o"}',
      challengeIndex: 23,
      typeIndex: 1,
    );

    // Chain 10 is on the static RIP-7212 list, but this node's precompile
    // call returns 0, so the probe says the precompile is absent.
    KernelSmartAccount account() => createKernelSmartAccount(
          owner: _FixedWebAuthnOwner(p256Signature),
          chainId: BigInt.from(10),
          version: KernelVersion.v0_3_1,
          address: mockAddress,
          publicClient: PublicClient(
            rpcClient: _FakeRpcClient({
              'eth_chainId': (_) => '0xa',
              'eth_call': (_) => Hex.zero32,
            }),
          ),
        );

    test('stub encodes the same precompile flag as the last signature',
        () async {
      final kernel = account();
      final signature = await kernel.signUserOperation(
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
      );

      expect(
        signature,
        encodeKernelWebAuthnSignature(p256Signature, usePrecompiled: false),
      );
      expect(
        kernel.getStubSignature(),
        getDummyKernelWebAuthnSignature(),
      );
    });

    // The first user operation is estimated before anything is signed. The
    // stub must cover the Solidity-verifier path the account may submit.
    test('stub estimates the Solidity verifier before any signature', () {
      expect(
        account().getStubSignature(),
        getDummyKernelWebAuthnSignature(usePrecompiled: false),
      );
    });
  });

  group('KernelSelectors', () {
    // cast sig 'execute(address,uint256,bytes,uint8)'; not SimpleAccount's
    // execute(address,uint256,bytes) = 0xb61d27f6.
    test('executeV2 matches cast sig', () {
      expect(KernelSelectors.executeV2, equals('0x51945447'));
    });

    test('are the selectors of the signatures the account encodes', () {
      for (final (selector, signature) in [
        (KernelSelectors.executeV2, kernelV2ExecuteSignature),
        (KernelSelectors.executeBatchV2, ExecuteBatchAbi.callTuples.signature),
        (KernelSelectors.executeV3, erc7579ExecuteSignature),
        (KernelSelectors.createAccountV2, kernelV2CreateAccountSignature),
        (KernelSelectors.createAccountV3, kernelV3CreateAccountSignature),
        (KernelSelectors.deployWithFactory, kernelDeployWithFactorySignature),
        (KernelSelectors.initializeV2, kernelV2InitializeSignature),
        (KernelSelectors.initializeV3Beta, kernelV3BetaInitializeSignature),
        (KernelSelectors.initializeV3, kernelV3InitializeSignature),
      ]) {
        expect(
          selector,
          AbiEncoder.functionSelector(signature),
          reason: signature,
        );
      }
    });
  });

  group('WebAuthn owner config is checked up front', () {
    final webAuthnOwner = _FixedWebAuthnOwner(
      P256SignatureData(
        r: BigInt.one,
        s: BigInt.one,
        authenticatorData: Uint8List(37),
        clientDataJSON: '{}',
        challengeIndex: 0,
        typeIndex: 0,
      ),
    );

    test('Kernel v0.2.x rejects a WebAuthn owner', () {
      expect(
        () => KernelSmartAccountConfig(
          owner: webAuthnOwner,
          chainId: BigInt.one,
          version: KernelVersion.v0_2_4,
        ),
        throwsArgumentError,
      );
    });

    test('a WebAuthn owner requires a webAuthnValidator address', () {
      final v031 = KernelVersionAddresses.getAddresses(KernelVersion.v0_3_1)!;
      expect(
        () => KernelSmartAccountConfig(
          owner: webAuthnOwner,
          chainId: BigInt.one,
          version: KernelVersion.v0_3_1,
          customAddresses: KernelAddresses(
            accountImplementation: v031.accountImplementation,
            factory: v031.factory,
            metaFactory: v031.metaFactory,
            ecdsaValidator: v031.ecdsaValidator,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('custom addresses are checked up front', () {
    // v0.2 initialize(validator, data) needs the ECDSA validator as its root
    // validator (permissionless.js getDefaultAddresses always supplies one).
    test('Kernel v0.2.x requires an ecdsaValidator address', () {
      expect(
        () => createKernelSmartAccount(
          owner: PrivateKeyOwner(testPrivateKey),
          chainId: BigInt.one,
          version: KernelVersion.v0_2_4,
          customAddresses: KernelAddresses(
            accountImplementation: EthereumAddress.fromHex(
              '0x1111111111111111111111111111111111111111',
            ),
            factory: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
          ),
          address: mockAddress,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('ECDSA validator'), contains('0.2.4')),
          ),
        ),
      );
    });
  });
}

class _FixedWebAuthnOwner extends WebAuthnAccountOwner {
  _FixedWebAuthnOwner(this._signature);

  final P256SignatureData _signature;

  @override
  BigInt get x => BigInt.one;

  @override
  BigInt get y => BigInt.two;

  @override
  Uint8List get credentialId => Uint8List(16);

  @override
  Future<P256SignatureData> signP256(String hash) async => _signature;
}

class _FakeRpcClient extends JsonRpcClient {
  _FakeRpcClient(this._handlers) : super(url: Uri.parse('http://localhost'));

  final Map<String, dynamic Function(List<dynamic>)> _handlers;

  @override
  Future<dynamic> call(String method, [List<dynamic>? params]) async {
    final handler = _handlers[method];
    if (handler == null) throw StateError('Unexpected RPC call: $method');
    return handler(params ?? const []);
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../../helpers/kernel_v4_vectors.dart';

/// Hardhat account #0 — fixed offline unit-test key, never used on live
/// networks.
const String _testPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

void main() {
  final vectors = loadKernelV4Vectors();
  final addressCases =
      (vectors['addressCases'] as List<dynamic>).cast<Map<String, dynamic>>();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final owner = PrivateKeyOwner(_testPrivateKey);

  Map<String, dynamic> caseNamed(String name) =>
      addressCases.firstWhere((c) => c['name'] == name);

  group('KernelVersion.v0_4_0', () {
    test('carries the 0.4.0 version string and flags', () {
      expect(KernelVersion.v0_4_0.value, equals('0.4.0'));
      expect(KernelVersion.v0_4_0.isV4, isTrue);
      expect(KernelVersion.v0_4_0.isV2, isFalse);
      expect(KernelVersion.v0_4_0.isV3, isFalse);
      expect(
        KernelVersion.v0_4_0.entryPointVersion,
        equals(EntryPointVersion.v09),
      );
    });

    test('does not change existing version classification', () {
      expect(KernelVersion.v0_2_2.isV2, isTrue);
      expect(KernelVersion.v0_2_2.isV4, isFalse);
      expect(KernelVersion.v0_3_1.isV3, isTrue);
      expect(KernelVersion.v0_3_1.isV4, isFalse);
      expect(
        KernelVersion.v0_2_2.entryPointVersion,
        equals(EntryPointVersion.v06),
      );
      expect(
        KernelVersion.v0_3_1.entryPointVersion,
        equals(EntryPointVersion.v07),
      );
    });

    test('is rejected by the v2/v3 Kernel factory', () {
      expect(
        () => createKernelSmartAccount(
          owner: owner,
          chainId: chainId,
          version: KernelVersion.v0_4_0,
          address: EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000001',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('is rejected by the EIP-7702 Kernel factory', () {
      expect(
        () => createEip7702KernelSmartAccount(
          owner: PrivateKeyEip7702KernelOwner(_testPrivateKey),
          chainId: chainId,
          version: KernelVersion.v0_4_0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('createKernelImmutableECDSA validation', () {
    test('rejects non-v4 Kernel versions', () {
      expect(
        () => createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          version: KernelVersion.v0_3_1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects nonce keys above two bytes', () {
      expect(
        () => createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          nonceKey: BigInt.from(0x10000),
        ),
        throwsArgumentError,
      );
    });
  });

  group('KernelImmutableECDSA account surface', () {
    final account = createKernelImmutableECDSA(
      owner: owner,
      chainId: chainId,
    );

    test('reports EntryPoint v0.9', () {
      expect(account.entryPointVersion, equals(EntryPointVersion.v09));
      expect(account.entryPoint, equals(EntryPointAddresses.v09));
      expect(account.chainId, equals(chainId));
      expect(account.isWebAuthn, isFalse);
    });

    test('honors an EntryPoint address override', () {
      final override =
          EthereumAddress.fromHex('0x43370900c8de573dB349BEd8DD53b4Ebd3Cce709');
      final overridden = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        entryPointAddress: override,
      );
      expect(overridden.entryPoint, equals(override));
    });

    test('default nonce key is zero, custom keys pass through', () {
      expect(account.nonceKey, equals(BigInt.zero));
      final keyed = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        nonceKey: BigInt.from(0x1234),
      );
      expect(keyed.nonceKey, equals(BigInt.from(0x1234)));
    });

    test('stub signature is the 65-byte Kernel ECDSA dummy', () {
      expect(account.getStubSignature(), equals(kernelDummyEcdsaSignature));
      expect(Hex.byteLength(account.getStubSignature()), equals(65));
    });

    test('message and typed-data signing are not implemented yet', () {
      expect(() => account.signMessage('hello'), throwsUnsupportedError);
      expect(() => account.sign('0x${'11' * 32}'), throwsUnsupportedError);
      expect(
        () => account.signTypedData(
          const TypedData(
            domain: TypedDataDomain(name: 'T', version: '1'),
            types: {
              'M': [TypedDataField(name: 'v', type: 'string')],
            },
            primaryType: 'M',
            message: {'v': 'x'},
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('counterfactual address (offline)', () {
    test('defaults resolve to the canonical release prediction', () async {
      final c = caseNamed('emptyNonce0');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['canonicalAddress'] as String).toLowerCase()),
      );
    });

    test('index feeds the deployment nonce', () async {
      for (final name in ['emptyNonce1', 'emptyNonceLarge']) {
        final c = caseNamed(name);
        final account = createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          index: BigInt.parse(c['nonce'] as String),
        );
        final address = await account.getAddress();
        expect(
          address.hex.toLowerCase(),
          equals((c['canonicalAddress'] as String).toLowerCase()),
          reason: name,
        );
      }
    });

    test('additional packages feed the salt', () async {
      for (final name in ['oneValidatorPackage', 'twoPackages']) {
        final c = caseNamed(name);
        final account = createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          index: BigInt.parse(c['nonce'] as String),
          additionalPackages: kernelV4PackagesFromCase(c),
        );
        final address = await account.getAddress();
        expect(
          address.hex.toLowerCase(),
          equals((c['canonicalAddress'] as String).toLowerCase()),
          reason: name,
        );
      }
    });

    test('custom addresses reproduce the locally deployed factory', () async {
      final c = caseNamed('emptyNonce0');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        customAddresses: KernelV4Addresses(
          kernelUUPS:
              EthereumAddress.fromHex(vectors['localKernelUUPS'] as String),
          kernelImmutableECDSA: EthereumAddress.fromHex(
            vectors['localKernelImmutableECDSA'] as String,
          ),
          factory: EthereumAddress.fromHex(vectors['localFactory'] as String),
          staker: KernelV4Addresses.predicted.staker,
        ),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['localAddress'] as String).toLowerCase()),
      );
    });

    test('a pre-computed address override wins', () async {
      final pinned =
          EthereumAddress.fromHex('0x00000000000000000000000000000000DeaDBeef');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        address: pinned,
      );
      expect(await account.getAddress(), equals(pinned));
    });
  });

  group('factory data', () {
    test('routes through the Staker by default', () async {
      final c = caseNamed('emptyNonce0');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
      );
      final data = await account.getFactoryData();
      expect(data, isNotNull);
      expect(data!.factory, equals(KernelV4Addresses.predicted.staker));
      expect(data.factoryData, equals(c['deployWithFactoryCalldata']));
    });

    test('useStaker: false targets the KernelFactory directly', () async {
      final c = caseNamed('emptyNonce0');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        useStaker: false,
      );
      final data = await account.getFactoryData();
      expect(data, isNotNull);
      expect(data!.factory, equals(KernelV4Addresses.predicted.factory));
      expect(data.factoryData, equals(c['deployEcdsaCalldata']));
    });

    test('init code concatenates factory and data', () async {
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        useStaker: false,
      );
      final c = caseNamed('emptyNonce0');
      expect(
        (await account.getInitCode()).toLowerCase(),
        equals(
          '${KernelV4Addresses.predicted.factory.hex}'
                  '${Hex.strip0x(c['deployEcdsaCalldata'] as String)}'
              .toLowerCase(),
        ),
      );
    });

    test('index and packages flow into the deploy calldata', () async {
      final c = caseNamed('twoPackages');
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
        index: BigInt.parse(c['nonce'] as String),
        additionalPackages: kernelV4PackagesFromCase(c),
        useStaker: false,
      );
      final data = await account.getFactoryData();
      expect(data!.factoryData, equals(c['deployEcdsaCalldata']));
    });
  });

  group('call encoding', () {
    final account = createKernelImmutableECDSA(owner: owner, chainId: chainId);
    final execute = vectors['execute'] as Map<String, dynamic>;

    test('single call byte-matches the executed calldata', () {
      final single = execute['single'] as Map<String, dynamic>;
      final call = Call(
        to: EthereumAddress.fromHex(single['to'] as String),
        value: BigInt.from(single['value'] as int),
        data: single['data'] as String,
      );
      expect(account.encodeCall(call), equals(single['callData']));
      expect(account.encodeCalls([call]), equals(single['callData']));
    });

    test('batch byte-matches the executed calldata', () {
      final batch = execute['batch'] as Map<String, dynamic>;
      final calls = (batch['calls'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (c) => Call(
              to: EthereumAddress.fromHex(c['to'] as String),
              value: BigInt.from(c['value'] as int),
              data: c['data'] as String,
            ),
          )
          .toList();
      expect(account.encodeCalls(calls), equals(batch['callData']));
    });

    test('decodeCalls round-trips single and batch', () {
      final single = execute['single'] as Map<String, dynamic>;
      final decodedSingle = account.decodeCalls(single['callData'] as String);
      expect(decodedSingle, hasLength(1));
      expect(
        decodedSingle.single.to.hex.toLowerCase(),
        equals((single['to'] as String).toLowerCase()),
      );
      expect(
        decodedSingle.single.value,
        equals(BigInt.from(single['value'] as int)),
      );
      expect(decodedSingle.single.data, equals(single['data']));

      final batch = execute['batch'] as Map<String, dynamic>;
      final expected =
          (batch['calls'] as List<dynamic>).cast<Map<String, dynamic>>();
      final decodedBatch = account.decodeCalls(batch['callData'] as String);
      expect(decodedBatch, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(
          decodedBatch[i].to.hex.toLowerCase(),
          equals((expected[i]['to'] as String).toLowerCase()),
        );
        expect(
          decodedBatch[i].value,
          equals(BigInt.from(expected[i]['value'] as int)),
        );
        expect(decodedBatch[i].data, equals(expected[i]['data']));
      }
    });

    test('rejects an empty batch', () {
      expect(() => account.encodeCalls([]), throwsArgumentError);
    });
  });

  group('root UserOperation signing', () {
    final r = vectors['rootUserOp'] as Map<String, dynamic>;

    test(
        'signs the EntryPoint v0.9 userOpHash with a raw 65-byte ECDSA '
        'signature the contract accepted', () async {
      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
      );

      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(r['sender'] as String),
        nonce: BigInt.parse(r['nonce'] as String),
        callData: r['callData'] as String,
        callGasLimit: BigInt.from(r['callGasLimit'] as int),
        verificationGasLimit: BigInt.from(r['verificationGasLimit'] as int),
        preVerificationGas: BigInt.from(r['preVerificationGas'] as int),
        maxFeePerGas: BigInt.from(r['maxFeePerGas'] as int),
        maxPriorityFeePerGas: BigInt.from(r['maxPriorityFeePerGas'] as int),
      );

      // The digest the account signs is the on-chain userOpHash…
      final hash = getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: account.entryPoint,
        entryPointVersion: EntryPointVersion.v09,
        chainId: chainId,
      );
      expect(hash, equals(r['userOpHash']));

      // …and the signature is the exact raw signature validateUserOp
      // returned 0 for (deterministic RFC-6979 signing).
      final signature = await account.signUserOperation(userOp);
      expect(signature, equals(r['signature']));
      expect(Hex.byteLength(signature), equals(65));
    });
  });

  group('smart-account client prepare/sign/send (mocked RPC)', () {
    test('flows through the client without hand-built payloads', () async {
      final bundlerRequests = <Map<String, dynamic>>[];

      final bundlerMock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bundlerRequests.add(body);
        final result = switch (body['method'] as String) {
          'eth_estimateUserOperationGas' => {
              'preVerificationGas': '0x5208',
              'verificationGasLimit': '0x186a0',
              'callGasLimit': '0x186a0',
            },
          'eth_sendUserOperation' => '0x${'ab' * 32}',
          _ => null,
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          200,
        );
      });

      final publicMock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final result = switch (body['method'] as String) {
          'eth_getCode' => '0x', // not deployed → factory data expected
          'eth_call' => '0x${'00' * 32}', // getNonce(sender, key) → 0
          'eth_gasPrice' => '0x3b9aca00',
          'eth_maxPriorityFeePerGas' => '0x5f5e100',
          _ => null,
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          200,
        );
      });

      final account = createKernelImmutableECDSA(
        owner: owner,
        chainId: chainId,
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: account.entryPoint,
          httpClient: bundlerMock,
        ),
        publicClient: PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: publicMock,
          ),
        ),
      );

      final expectedAddress = await account.getAddress();
      final c = caseNamed('emptyNonce0');

      final hash = await client.sendUserOperation(
        calls: [
          Call(
            to: EthereumAddress.fromHex(
              '0x000000000000000000000000000000000000dEaD',
            ),
            value: BigInt.one,
            data: '0x',
          ),
        ],
      );
      expect(hash, equals('0x${'ab' * 32}'));

      final estimate = bundlerRequests
          .firstWhere((r) => r['method'] == 'eth_estimateUserOperationGas');
      final estimateParams = estimate['params'] as List<dynamic>;
      final estimatedOp = estimateParams[0] as Map<String, dynamic>;
      // Estimation runs against EntryPoint v0.9, from the counterfactual
      // sender, with the staker-wrapped factory data and the stub signature.
      expect(
        (estimateParams[1] as String).toLowerCase(),
        equals(EntryPointAddresses.v09.hex.toLowerCase()),
      );
      expect(
        (estimatedOp['sender'] as String).toLowerCase(),
        equals(expectedAddress.hex.toLowerCase()),
      );
      expect(
        (estimatedOp['factory'] as String).toLowerCase(),
        equals(KernelV4Addresses.predicted.staker.hex.toLowerCase()),
      );
      expect(
        estimatedOp['factoryData'],
        equals(c['deployWithFactoryCalldata']),
      );
      expect(estimatedOp['signature'], equals(kernelDummyEcdsaSignature));

      final send = bundlerRequests
          .firstWhere((r) => r['method'] == 'eth_sendUserOperation');
      final sentOp =
          (send['params'] as List<dynamic>)[0] as Map<String, dynamic>;
      // The sent operation carries a real 65-byte root signature.
      expect(sentOp['signature'], isNot(equals(kernelDummyEcdsaSignature)));
      expect(
        Hex.byteLength(sentOp['signature'] as String),
        equals(65),
      );
      expect(sentOp.containsKey('paymasterSignature'), isFalse);
    });
  });
}

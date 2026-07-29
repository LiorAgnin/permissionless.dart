import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../../helpers/kernel_v4_vectors.dart';

/// Minimal WebAuthn owner test double (same pattern as the Safe account
/// tests — the real subclasses live in `permissionless_passkeys`).
class _TestWebAuthnOwner extends WebAuthnAccountOwner {
  _TestWebAuthnOwner();

  @override
  final BigInt x = BigInt.one;

  @override
  final BigInt y = BigInt.two;

  @override
  final Uint8List credentialId = Uint8List(16);

  @override
  Future<P256SignatureData> signP256(String hash) {
    throw UnsupportedError('test double: signP256 not implemented');
  }
}

/// Hardhat account #0 — fixed offline unit-test key, never used on live
/// networks.
const String _testPrivateKey =
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

/// Hardhat account #1 — the fixture's "other owner" case.
const String _otherPrivateKey =
    '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

/// The v3-era ECDSA validator the fixture's root packages install (drop-in
/// for basic v4 root flows).
final EthereumAddress _ecdsaValidator =
    EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');

void main() {
  final vectors = loadKernelV4Vectors();
  final addressCases =
      (vectors['addressCases'] as List<dynamic>).cast<Map<String, dynamic>>();
  final chainId = BigInt.from(vectors['chainId'] as int);
  final owner = PrivateKeyOwner(_testPrivateKey);

  Map<String, dynamic> caseNamed(String name) =>
      addressCases.firstWhere((c) => c['name'] == name);

  KernelV4Addresses localAddresses() => KernelV4Addresses(
        kernelUUPS:
            EthereumAddress.fromHex(vectors['localKernelUUPS'] as String),
        kernelImmutableECDSA: EthereumAddress.fromHex(
          vectors['localKernelImmutableECDSA'] as String,
        ),
        factory: EthereumAddress.fromHex(vectors['localFactory'] as String),
        staker: KernelV4Addresses.predicted.staker,
      );

  group('createKernelUUPS validation', () {
    test('rejects non-v4 Kernel versions', () {
      expect(
        () => createKernelUUPS(
          owner: owner,
          chainId: chainId,
          rootValidator: _ecdsaValidator,
          version: KernelVersion.v0_3_1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects nonce keys above two bytes', () {
      expect(
        () => createKernelUUPS(
          owner: owner,
          chainId: chainId,
          rootValidator: _ecdsaValidator,
          nonceKey: BigInt.from(0x10000),
        ),
        throwsArgumentError,
      );
    });

    test('rejects WebAuthn owners', () {
      // The root install's moduleData is the 20-byte owner address — an
      // ECDSA-validator encoding. A WebAuthn owner only has a dummy derived
      // address, so accepting one would CREATE2-commit a broken account.
      expect(
        () => createKernelUUPS(
          owner: _TestWebAuthnOwner(),
          chainId: chainId,
          rootValidator: _ecdsaValidator,
        ),
        throwsArgumentError,
      );
    });
  });

  group('KernelUUPS account surface', () {
    final account = createKernelUUPS(
      owner: owner,
      chainId: chainId,
      rootValidator: _ecdsaValidator,
    );

    test('reports EntryPoint v0.9', () {
      expect(account.entryPointVersion, equals(EntryPointVersion.v09));
      expect(account.entryPoint, equals(EntryPointAddresses.v09));
      expect(account.chainId, equals(chainId));
      expect(account.isWebAuthn, isFalse);
    });

    test('honors an EntryPoint address override', () {
      final override =
          EthereumAddress.fromHex('0x0000000000000000000000000000000000000901');
      final overridden = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        entryPointAddress: override,
      );
      expect(overridden.entryPoint, equals(override));
    });

    test('default nonce key is zero, custom keys pass through', () {
      expect(account.nonceKey, equals(BigInt.zero));
      final keyed = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        nonceKey: BigInt.from(0x1234),
      );
      expect(keyed.nonceKey, equals(BigInt.from(0x1234)));
    });

    test('stub signature is the 65-byte Kernel ECDSA dummy', () {
      expect(account.getStubSignature(), equals(kernelDummyEcdsaSignature));
      expect(Hex.byteLength(account.getStubSignature()), equals(65));
    });

    test('non-root validation and replayable mode route the nonce key', () {
      // The routing logic is shared with KernelImmutableECDSA, where the
      // fixture-backed cases live; this pins the UUPS wiring.
      final routed = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        validation: KernelV4Validation.validator(_ecdsaValidator),
        replayableUserOps: true,
        nonceKey: BigInt.from(0x1234),
      );
      final decoded = decodeKernelV4Nonce(routed.nonceKey << 64);
      expect(
        decoded.vMode,
        equals(KernelV4ValidationMode.replayableUserOpHash),
      );
      expect(decoded.vType, equals(KernelV4ValidationType.validator));
      expect(decoded.vId, equals(_ecdsaValidator.hex.toLowerCase()));
      expect(decoded.nonceKey, equals(BigInt.from(0x1234)));
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
      // The fixture's oneValidatorPackage case is exactly the synthesized
      // root install: type 1, the validator module, the owner as moduleData.
      final c = caseNamed('oneValidatorPackage');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['canonicalUupsAddress'] as String).toLowerCase()),
      );
    });

    test('index feeds the deployment nonce', () async {
      final c = caseNamed('rootValidatorNonce1');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        index: BigInt.parse(c['nonce'] as String),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['canonicalUupsAddress'] as String).toLowerCase()),
      );
    });

    test('the owner feeds the salt through the root moduleData', () async {
      // Unlike ImmutableECDSA (signer in immutable args, not the salt), the
      // UUPS identity commits to the owner via packages[0].moduleData.
      final c = caseNamed('rootValidatorOtherOwner');
      final account = createKernelUUPS(
        owner: PrivateKeyOwner(_otherPrivateKey),
        chainId: chainId,
        rootValidator: _ecdsaValidator,
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['canonicalUupsAddress'] as String).toLowerCase()),
      );
      expect(
        address.hex.toLowerCase(),
        isNot(
          equals(
            (caseNamed('oneValidatorPackage')['canonicalUupsAddress'] as String)
                .toLowerCase(),
          ),
        ),
      );
    });

    test('additional packages install after the root', () async {
      final c = caseNamed('twoPackages');
      final packages = kernelV4PackagesFromCase(c);
      // packages[0] is the root the account synthesizes itself; the caller
      // only supplies the extras.
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        index: BigInt.parse(c['nonce'] as String),
        additionalPackages: packages.sublist(1),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['canonicalUupsAddress'] as String).toLowerCase()),
      );
    });

    test('custom addresses reproduce the locally deployed factory', () async {
      final c = caseNamed('oneValidatorPackage');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        customAddresses: localAddresses(),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((c['localUupsAddress'] as String).toLowerCase()),
      );
    });

    test('a pre-computed address override wins', () async {
      final pinned =
          EthereumAddress.fromHex('0x00000000000000000000000000000000DeaDBeef');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        address: pinned,
      );
      expect(await account.getAddress(), equals(pinned));
    });
  });

  group('factory data', () {
    test('routes through the Staker by default', () async {
      final c = caseNamed('oneValidatorPackage');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
      );
      final data = await account.getFactoryData();
      expect(data, isNotNull);
      expect(data!.factory, equals(KernelV4Addresses.predicted.staker));
      expect(data.factoryData, equals(c['deployUupsWithFactoryCalldata']));
    });

    test('useStaker: false targets the KernelFactory directly', () async {
      final c = caseNamed('oneValidatorPackage');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        useStaker: false,
      );
      final data = await account.getFactoryData();
      expect(data, isNotNull);
      expect(data!.factory, equals(KernelV4Addresses.predicted.factory));
      expect(data.factoryData, equals(c['deployUupsCalldata']));
    });

    test('init code concatenates factory and data', () async {
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        useStaker: false,
      );
      final c = caseNamed('oneValidatorPackage');
      expect(
        (await account.getInitCode()).toLowerCase(),
        equals(
          '${KernelV4Addresses.predicted.factory.hex}'
                  '${Hex.strip0x(c['deployUupsCalldata'] as String)}'
              .toLowerCase(),
        ),
      );
    });

    test('index and additional packages flow into the deploy calldata',
        () async {
      final c = caseNamed('twoPackages');
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
        index: BigInt.parse(c['nonce'] as String),
        additionalPackages: kernelV4PackagesFromCase(c).sublist(1),
        useStaker: false,
      );
      final data = await account.getFactoryData();
      expect(data!.factoryData, equals(c['deployUupsCalldata']));
    });
  });

  group('call encoding', () {
    final account = createKernelUUPS(
      owner: owner,
      chainId: chainId,
      rootValidator: _ecdsaValidator,
    );
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
      expect(decodedSingle.single.data, equals(single['data']));

      final batch = execute['batch'] as Map<String, dynamic>;
      final expected =
          (batch['calls'] as List<dynamic>).cast<Map<String, dynamic>>();
      final decodedBatch = account.decodeCalls(batch['callData'] as String);
      expect(decodedBatch, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(decodedBatch[i].data, equals(expected[i]['data']));
      }
    });

    test('rejects an empty batch', () {
      expect(() => account.encodeCalls([]), throwsArgumentError);
    });
  });

  group('root UserOperation signing', () {
    final r = vectors['uupsRootUserOp'] as Map<String, dynamic>;

    test(
        'signs the EntryPoint v0.9 userOpHash with a raw 65-byte ECDSA '
        'signature the deployed UUPS account accepted', () async {
      // The account the oracle deployed: local factory + implementation,
      // with the freshly deployed root validator module.
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: EthereumAddress.fromHex(r['rootValidator'] as String),
        customAddresses: localAddresses(),
      );

      // Our offline computation reproduces the deployed sender.
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((r['sender'] as String).toLowerCase()),
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

    test('canonical sender matches the release-address prediction', () async {
      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: EthereumAddress.fromHex(r['rootValidator'] as String),
      );
      final address = await account.getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((r['canonicalSender'] as String).toLowerCase()),
      );
    });
  });

  group('enable-mode UserOperations (nonce mode 0x08)', () {
    final e = vectors['uupsEnableUserOp'] as Map<String, dynamic>;

    // The fixture's single-key flow: the root owner also owns the module
    // being enabled, so one key signs both the install authorization and
    // the operation — no rootOwner override needed.
    KernelUUPS enableAccount() => createKernelUUPS(
          owner: owner,
          chainId: chainId,
          rootValidator: EthereumAddress.fromHex(e['rootValidator'] as String),
          index: BigInt.from(206),
          validation: KernelV4Validation.validator(
            EthereumAddress.fromHex(e['validator'] as String),
          ),
          enableMode: KernelV4EnableMode(
            packages: kernelV4PackagesFromCase(e),
          ),
          customAddresses: localAddresses(),
        );

    test('the offline address reproduces the deployed sender', () async {
      final address = await enableAccount().getAddress();
      expect(
        address.hex.toLowerCase(),
        equals((e['sender'] as String).toLowerCase()),
      );
    });

    test('the nonce key carries the enable flag and routes to the module',
        () {
      final account = enableAccount();
      expect(
        account.nonceKey,
        equals(BigInt.parse(e['nonce'] as String) >> 64),
      );
      final decoded = decodeKernelV4Nonce(account.nonceKey << 64);
      expect(decoded.vMode, equals(KernelV4ValidationMode.enable));
      expect(decoded.vType, equals(KernelV4ValidationType.validator));
    });

    test(
        'signs the EnableModeSignature blob — the bytes the contract '
        'accepted', () async {
      final signature =
          await enableAccount().signUserOperation(kernelV4UserOpFromCase(e));
      expect(signature, equals(e['signature']));
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

      final account = createKernelUUPS(
        owner: owner,
        chainId: chainId,
        rootValidator: _ecdsaValidator,
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
      final c = caseNamed('oneValidatorPackage');

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
        equals(c['deployUupsWithFactoryCalldata']),
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

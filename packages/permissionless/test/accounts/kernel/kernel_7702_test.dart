import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart' as crypto;

import '../../helpers/kernel_v4_vectors.dart';

/// Hardhat account #2 — the fixture's Kernel7702 delegated EOA (its own
/// dedicated offline unit-test key; accounts #0/#1 stay plain signers).
const String _eoaPrivateKey =
    '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';

/// Recomputes the EIP-7702 authorization signing hash —
/// `keccak256(0x05 ‖ rlp([chainId, address, nonce]))` — independently of the
/// library's encoder, so the recovery test pins the byte layout.
Uint8List _authorizationHash({
  required BigInt chainId,
  required EthereumAddress address,
  required BigInt nonce,
}) {
  List<int> rlpInt(BigInt value) {
    if (value == BigInt.zero) return [0x80];
    var bytes = Hex.decode(Hex.fromBigInt(value));
    while (bytes.isNotEmpty && bytes.first == 0) {
      bytes = bytes.sublist(1);
    }
    if (bytes.length == 1 && bytes.first < 0x80) return bytes;
    return [0x80 + bytes.length, ...bytes];
  }

  final payload = [
    ...rlpInt(chainId),
    ...[0x94, ...Hex.decode(address.hex)],
    ...rlpInt(nonce),
  ];
  // The authorization tuple is far below the 55-byte long-list threshold.
  final rlp = [0xc0 + payload.length, ...payload];
  return crypto.keccak256(Uint8List.fromList([0x05, ...rlp]));
}

void main() {
  final vectors = loadKernelV4Vectors();
  final fixture = vectors['kernel7702'] as Map<String, dynamic>;
  final chainId = BigInt.from(vectors['chainId'] as int);
  final owner = PrivateKeyEip7702KernelOwner(_eoaPrivateKey);
  final localImplementation =
      EthereumAddress.fromHex(fixture['localImplementation'] as String);

  /// The account wired to the locally deployed implementation the fixture
  /// contract calls actually ran against.
  Kernel7702 localAccount({
    PublicClient? publicClient,
    KernelV4Validation validation = const KernelV4Validation.root(),
    bool replayableUserOps = false,
  }) =>
      createKernel7702(
        owner: owner,
        chainId: chainId,
        customAddresses: KernelV4Addresses(
          kernelUUPS: KernelV4Addresses.predicted.kernelUUPS,
          kernelImmutableECDSA:
              KernelV4Addresses.predicted.kernelImmutableECDSA,
          factory: KernelV4Addresses.predicted.factory,
          staker: KernelV4Addresses.predicted.staker,
          kernel7702: localImplementation,
        ),
        publicClient: publicClient,
        validation: validation,
        replayableUserOps: replayableUserOps,
      );

  group('createKernel7702 validation', () {
    test('rejects non-v4 Kernel versions', () {
      expect(
        () => createKernel7702(
          owner: owner,
          chainId: chainId,
          version: KernelVersion.v0_3_3,
        ),
        throwsArgumentError,
      );
    });

    test('rejects nonce keys above two bytes', () {
      expect(
        () => createKernel7702(
          owner: owner,
          chainId: chainId,
          nonceKey: BigInt.from(0x10000),
        ),
        throwsArgumentError,
      );
    });

    test('rejects custom addresses without a Kernel7702 implementation', () {
      expect(
        () => createKernel7702(
          owner: owner,
          chainId: chainId,
          customAddresses: KernelV4Addresses(
            kernelUUPS: KernelV4Addresses.predicted.kernelUUPS,
            kernelImmutableECDSA:
                KernelV4Addresses.predicted.kernelImmutableECDSA,
            factory: KernelV4Addresses.predicted.factory,
            staker: KernelV4Addresses.predicted.staker,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Kernel7702 account surface', () {
    final account = createKernel7702(owner: owner, chainId: chainId);

    test('reports EntryPoint v0.9', () {
      expect(account.entryPointVersion, equals(EntryPointVersion.v09));
      expect(account.entryPoint, equals(EntryPointAddresses.v09));
      expect(account.chainId, equals(chainId));
      expect(account.isWebAuthn, isFalse);
      expect(account.isEip7702, isTrue);
    });

    test('the account address is the EOA address', () async {
      expect(await account.getAddress(), equals(owner.address));
      expect(
        (await account.getAddress()).hex.toLowerCase(),
        equals((fixture['eoa'] as String).toLowerCase()),
      );
    });

    test('delegates to the release Kernel7702 implementation by default', () {
      expect(
        account.accountLogicAddress,
        equals(KernelV4Addresses.predicted.kernel7702),
      );
      expect(
        account.accountLogicAddress.hex.toLowerCase(),
        equals((fixture['canonicalImplementation'] as String).toLowerCase()),
      );
    });

    test('has no factory — delegation replaces deployment', () async {
      expect(await account.getFactoryData(), isNull);
      expect(await account.getInitCode(), equals('0x'));
    });

    test('honors an EntryPoint address override', () {
      final override =
          EthereumAddress.fromHex('0x000000000000000000000000000000000000beef');
      final overridden = createKernel7702(
        owner: owner,
        chainId: chainId,
        entryPointAddress: override,
      );
      expect(overridden.entryPoint, equals(override));
    });

    test('default nonce key is zero, custom keys pass through', () {
      expect(account.nonceKey, equals(BigInt.zero));
      final keyed = createKernel7702(
        owner: owner,
        chainId: chainId,
        nonceKey: BigInt.from(0x1234),
      );
      expect(keyed.nonceKey, equals(BigInt.from(0x1234)));
    });

    test('replayable mode sets the 0x40 bit in the nonce key', () {
      final replayable = createKernel7702(
        owner: owner,
        chainId: chainId,
        replayableUserOps: true,
      );
      final decoded = decodeKernelV4Nonce(replayable.nonceKey << 64);
      expect(
        decoded.vMode,
        equals(KernelV4ValidationMode.replayableUserOpHash),
      );
      expect(decoded.vType, equals(KernelV4ValidationType.root));
    });

    test('stub signature is the 65-byte Kernel ECDSA dummy', () {
      expect(account.getStubSignature(), equals(kernelDummyEcdsaSignature));
      expect(Hex.byteLength(account.getStubSignature()), equals(65));
    });

    test('the adapted owner signs like a plain AccountOwner', () async {
      // The Kernel v4 base signs through an AccountOwner adapter over the
      // EIP-7702 owner; every mode must match the canonical implementation
      // for the same key.
      final reference = PrivateKeyOwner(_eoaPrivateKey);
      final hash = hashMessage('adapter parity');
      expect(account.owner.address, equals(reference.address));
      expect(
        await account.owner.signRawHash(hash),
        equals(await reference.signRawHash(hash)),
      );
      expect(
        await account.owner.signPersonalMessage(hash),
        equals(await reference.signPersonalMessage(hash)),
      );
    });
  });

  group('EIP-7702 authorization', () {
    final account = createKernel7702(owner: owner, chainId: chainId);

    test('carries the chain, the implementation, and the EOA nonce', () async {
      final auth = await account.getAuthorization(nonce: BigInt.from(7));
      expect(auth.chainId, equals(chainId));
      expect(auth.address, equals(KernelV4Addresses.predicted.kernel7702));
      expect(auth.nonce, equals(BigInt.from(7)));
    });

    test('targets a custom implementation when one is configured', () async {
      final auth = await localAccount().getAuthorization(nonce: BigInt.zero);
      expect(auth.address, equals(localImplementation));
    });

    test('the signature recovers the EOA over the 0x05-magic RLP hash',
        () async {
      final auth = await account.getAuthorization(nonce: BigInt.zero);
      final hash = _authorizationHash(
        chainId: auth.chainId,
        address: auth.address,
        nonce: auth.nonce,
      );
      final publicKey = crypto.ecRecover(
        hash,
        crypto.MsgSignature(
          Hex.toBigInt(auth.r),
          Hex.toBigInt(auth.s),
          auth.v < 27 ? auth.v + 27 : auth.v,
        ),
      );
      final recovered = EthereumAddress.fromHex(
        Hex.fromBytes(crypto.publicKeyToAddress(publicKey)),
      );
      expect(recovered, equals(owner.address));
    });
  });

  group('UserOperations under EntryPoint v0.9', () {
    final c = fixture['userOp'] as Map<String, dynamic>;
    final userOp = kernelV4UserOpFromCase(c);

    test('the v0.9 hash matches the EntryPoint oracle', () {
      expect(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: EntryPointAddresses.v09,
          entryPointVersion: EntryPointVersion.v09,
          chainId: chainId,
        ),
        equals(c['userOpHash']),
      );
    });

    test('signs the raw 65-byte signature the delegated EOA accepted',
        () async {
      final signature = await localAccount().signUserOperation(userOp);
      expect(signature, equals(c['signature']));
      expect(Hex.byteLength(signature), equals(65));
    });

    test('the 0x7702 factory marker swaps the delegate into the digest',
        () async {
      final marked = UserOperationV07(
        sender: userOp.sender,
        nonce: userOp.nonce,
        factory: eip7702FactoryMarkerAddress,
        factoryData: '0x',
        callData: userOp.callData,
        callGasLimit: userOp.callGasLimit,
        verificationGasLimit: userOp.verificationGasLimit,
        preVerificationGas: userOp.preVerificationGas,
        maxFeePerGas: userOp.maxFeePerGas,
        maxPriorityFeePerGas: userOp.maxPriorityFeePerGas,
      );
      final rawSigner = PrivateKeyOwner(_eoaPrivateKey);
      final expected = await rawSigner.signRawHash(
        getUserOperationHash(
          userOperation: marked,
          entryPointAddress: EntryPointAddresses.v09,
          entryPointVersion: EntryPointVersion.v09,
          chainId: chainId,
          delegationAddress: localImplementation,
        ),
      );
      final signature = await localAccount().signUserOperation(marked);
      expect(signature, equals(expected));
      // Without the substitution the digest (and thus the signature) would
      // differ — the marker really changes what is signed.
      expect(
        signature,
        isNot(
          equals(
            await rawSigner.signRawHash(
              getUserOperationHash(
                userOperation: marked,
                entryPointAddress: EntryPointAddresses.v09,
                entryPointVersion: EntryPointVersion.v09,
                chainId: chainId,
              ),
            ),
          ),
        ),
      );
    });
  });

  group('ERC-1271', () {
    final c = fixture['erc1271'] as Map<String, dynamic>;
    final message = c['message'] as String;

    test('raw: a bare EOA signature over the app hash — Kernel7702-only',
        () async {
      expect(hashMessage(message), equals(c['hash']));
      final signature =
          await localAccount().signErc1271Raw(hashMessage(message));
      expect(signature, equals(c['rawSignature']));
      expect(Hex.byteLength(signature), equals(65));
    });

    test('nested: the standard prefixed ERC-7739 PersonalSign flow', () async {
      final signature = await localAccount().signMessage(message);
      expect(signature, equals(c['nestedSignature']));
      expect(signature, startsWith('0x0000'));
      expect(Hex.byteLength(signature), equals(2 + 65));
      expect(
        await localAccount().sign(hashMessage(message)),
        equals(signature),
      );
    });

    test('refuses to sign before delegation when a public client is wired',
        () async {
      PublicClient clientReturningCode(String code) => PublicClient(
            rpcClient: JsonRpcClient(
              url: Uri.parse('http://localhost:8545'),
              httpClient: MockClient((request) async {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                return http.Response(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': body['id'],
                    'result': code,
                  }),
                  200,
                );
              }),
            ),
          );

      final undelegated = localAccount(
        publicClient: clientReturningCode('0x'),
      );
      expect(
        () => undelegated.signMessage(message),
        throwsA(isA<StateError>()),
      );
      expect(
        () => undelegated.signErc1271Raw(hashMessage(message)),
        throwsA(isA<StateError>()),
      );

      final delegated = localAccount(
        publicClient: clientReturningCode(
          '0xef0100${Hex.strip0x(localImplementation.hex)}',
        ),
      );
      expect(
        await delegated.signMessage(message),
        equals(c['nestedSignature']),
      );
    });
  });

  group('module install after delegation', () {
    final c = fixture['install'] as Map<String, dynamic>;

    test('the ticket-06 encoder emits the bytes the delegated EOA executed',
        () {
      final calldata = encodeKernelV4InstallModuleCalldata(
        KernelV4Install(
          moduleType: BigInt.from(c['moduleType'] as int),
          module: EthereumAddress.fromHex(c['module'] as String),
          moduleData: c['moduleData'] as String,
          internalData: c['internalData'] as String,
        ),
      );
      expect(calldata, equals(c['callData']));
    });

    test('the account frames a self-call install as ERC-7579 execute',
        () async {
      final account = localAccount();
      final call = Call(
        to: await account.getAddress(),
        value: BigInt.zero,
        data: c['callData'] as String,
      );
      final encoded = account.encodeCall(call);
      final decoded = account.decodeCalls(encoded);
      expect(decoded, hasLength(1));
      expect(decoded.single.to, equals(owner.address));
      expect(decoded.single.data, equals(c['callData']));
    });
  });

  group('smart-account client prepare/sign/send (mocked RPC)', () {
    test('first operation carries the 0x7702 factory and the authorization',
        () async {
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
          'eth_getCode' => '0x', // bare EOA → authorization + marker expected
          'eth_getTransactionCount' => '0x0',
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

      final account = localAccount();
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

      final prepared = await client.prepareUserOperationWithAuth(
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

      // The bare EOA gets a first-time authorization for the implementation…
      expect(prepared.authorization, isNotNull);
      expect(prepared.authorization!.address, equals(localImplementation));
      expect(prepared.authorization!.nonce, equals(BigInt.zero));
      // …and the operation itself is sent from the EOA with the 0x7702
      // factory marker instead of factory data.
      expect(prepared.userOp.sender, equals(owner.address));
      expect(
        isEip7702FactoryMarker(prepared.userOp.factory),
        isTrue,
      );

      final signature = await account.signUserOperation(prepared.userOp);
      expect(Hex.byteLength(signature), equals(65));

      final estimate = bundlerRequests
          .firstWhere((r) => r['method'] == 'eth_estimateUserOperationGas');
      final estimatedOp =
          (estimate['params'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(estimatedOp['factory'], equals('0x7702'));
      expect(
        (estimatedOp['sender'] as String).toLowerCase(),
        equals(owner.address.hex.toLowerCase()),
      );
      expect(estimatedOp['signature'], equals(kernelDummyEcdsaSignature));
    });
  });
}

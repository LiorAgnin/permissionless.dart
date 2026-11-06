import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// Parity tests for ERC-7579 read actions (issue 018 item 5):
/// - errors are not swallowed to `false` / `''`
/// - counterfactual `factory`/`factoryData` fallback on first-call failure
void main() {
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  final mockAddress =
      EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
  final moduleAddress =
      EthereumAddress.fromHex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd');

  const boolTrue =
      '0x0000000000000000000000000000000000000000000000000000000000000001';
  // ABI-encoded string "kernel.advanced.0.3.1"
  const accountIdResult = '0x'
      '0000000000000000000000000000000000000000000000000000000000000020'
      '0000000000000000000000000000000000000000000000000000000000000015'
      '6b65726e656c2e616476616e6365642e302e332e310000000000000000000000';

  SmartAccountClient createClient() {
    // Any SmartAccount with factory data works for the fallback path.
    final account = createSafeSmartAccount(
      owners: [PrivateKeyOwner(testPrivateKey)],
      chainId: BigInt.from(1),
      address: mockAddress,
    );

    final bundler = createBundlerClient(
      url: 'http://localhost:4337',
      entryPoint: EntryPointAddresses.v07,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': null,
          }),
          200,
        );
      }),
    );

    final public = createPublicClient(
      url: 'http://localhost:8545',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': '0x',
          }),
          200,
        );
      }),
    );

    return createSmartAccountClient(
      account: account,
      bundler: bundler,
      publicClient: public,
    );
  }

  PublicClient publicClientFromHandler(
    dynamic Function(Map<String, dynamic> body) handler,
  ) =>
      createPublicClient(
        url: 'http://localhost:8545',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final response = handler(body);
          if (response is Map && response.containsKey('error')) {
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'error': response['error'],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': response,
            }),
            200,
          );
        }),
      );

  const revert = {
    'error': {'code': -32000, 'message': 'execution reverted'},
  };

  /// Answers eth_call like an undeployed account: the direct call (has `to`)
  /// gets [direct]; the deployless factory call (no `to`) gets [deployless].
  /// Every call's tx object is appended to [txs].
  PublicClient undeployedAccount(
    List<Map<String, dynamic>> txs, {
    required Object direct,
    required String deployless,
  }) =>
      publicClientFromHandler((body) {
        final tx = (body['params'] as List<dynamic>)[0] as Map<String, dynamic>;
        txs.add(tx);
        return tx.containsKey('to') ? direct : deployless;
      });

  /// One direct eth_call to the account with [calldata], then one deployless
  /// call that wraps the same calldata with the Safe factory (viem
  /// deploylessCallViaFactory: bytecode ++ abi.encode(to, data, factory,
  /// factoryData)).
  void expectDirectThenDeployless(
    List<Map<String, dynamic>> txs,
    String calldata,
  ) {
    expect(txs, hasLength(2));
    expect(txs[0]['to'], equals(mockAddress.hex));
    expect(txs[0]['data'], equals(calldata));
    expect(txs[1].containsKey('to'), isFalse);
    final data = txs[1]['data'] as String;
    expect(data, startsWith('0x608060405234801561001057600080fd5b50'));
    expect(data, contains(calldata.substring(2)));
    // SafeProxyFactory 1.4.1 and its factoryData, a createProxyWithNonce call
    // (`cast sig "createProxyWithNonce(address,bytes,uint256)"` = 0x1688f0b9).
    expect(data, contains('4e1dcf7ad4e460cfd30791ccc4f9c8a4f820ec67'));
    expect(data, contains('1688f0b9'));
  }

  group('ERC-7579 query parity', () {
    test('supportsModule succeeds on direct eth_call', () async {
      final client = createClient();
      final public = publicClientFromHandler((_) => boolTrue);

      final result = await client.supportsModule(
        publicClient: public,
        moduleType: Erc7579ModuleType.validator,
      );
      expect(result, isTrue);
    });

    test(
      'supportsModule falls back to factory deployless call when direct fails',
      () async {
        final txs = <Map<String, dynamic>>[];
        final result = await createClient().supportsModule(
          publicClient:
              undeployedAccount(txs, direct: revert, deployless: boolTrue),
          moduleType: Erc7579ModuleType.validator,
        );

        expect(result, isTrue);
        // cast calldata "supportsModule(uint256)" 1
        expectDirectThenDeployless(
          txs,
          '0xf2dc691d'
          '0000000000000000000000000000000000000000000000000000000000000001',
        );
      },
    );

    test('isModuleInstalled uses factory fallback', () async {
      final txs = <Map<String, dynamic>>[];
      final result = await createClient().isModuleInstalled(
        publicClient:
            undeployedAccount(txs, direct: revert, deployless: boolTrue),
        type: Erc7579ModuleType.validator,
        address: moduleAddress,
      );

      expect(result, isTrue);
      // cast calldata "isModuleInstalled(uint256,address,bytes)" 1 \
      //   0xabcdefabcdefabcdefabcdefabcdefabcdefabcd 0x
      expectDirectThenDeployless(
        txs,
        '0x112d3a7d'
        '0000000000000000000000000000000000000000000000000000000000000001'
        '000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd'
        '0000000000000000000000000000000000000000000000000000000000000060'
        '0000000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test(
      'supportsModule falls back when direct call returns empty 0x (no error)',
      () async {
        // Geth-style nodes often return success with "0x" for eth_call to an
        // undeployed address instead of reverting.
        final txs = <Map<String, dynamic>>[];
        final result = await createClient().supportsModule(
          publicClient:
              undeployedAccount(txs, direct: '0x', deployless: boolTrue),
          moduleType: Erc7579ModuleType.validator,
        );

        expect(result, isTrue);
        expectDirectThenDeployless(
          txs,
          '0xf2dc691d'
          '0000000000000000000000000000000000000000000000000000000000000001',
        );
      },
    );

    test('getAccountId uses factory fallback and decodes string', () async {
      final txs = <Map<String, dynamic>>[];
      final id = await createClient().getAccountId(
        publicClient:
            undeployedAccount(txs, direct: revert, deployless: accountIdResult),
      );

      expect(id, equals('kernel.advanced.0.3.1'));
      // cast calldata "accountId()"
      expectDirectThenDeployless(txs, '0x9cfd7cff');
    });

    test('supportsExecutionMode uses factory fallback', () async {
      final txs = <Map<String, dynamic>>[];
      final result = await createClient().supportsExecutionMode(
        publicClient:
            undeployedAccount(txs, direct: revert, deployless: boolTrue),
        mode: const ExecutionMode(
          type: Erc7579CallKind.batchCall,
          revertOnError: true,
        ),
      );

      expect(result, isTrue);
      // callType 0x01 (batch); execType 0x01 for revertOnError: true —
      // permissionless.js supportsExecutionMode encodes
      // `revertOnError ? "0x01" : "0x00"` (polarity documented on
      // ExecutionMode). cast calldata "supportsExecutionMode(bytes32)" \
      //   0x0101000000000000000000000000000000000000000000000000000000000000
      expectDirectThenDeployless(
        txs,
        '0xd03c7914'
        '0101000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test('queries default to the client publicClient', () async {
      final txs = <Map<String, dynamic>>[];
      final client = createSmartAccountClient(
        account: createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(1),
          address: mockAddress,
        ),
        bundler: createBundlerClient(
          url: 'http://localhost:4337',
          entryPoint: EntryPointAddresses.v07,
        ),
        publicClient: publicClientFromHandler((body) {
          final tx =
              (body['params'] as List<dynamic>)[0] as Map<String, dynamic>;
          txs.add(tx);
          return tx['data'] == '0x9cfd7cff' ? accountIdResult : boolTrue;
        }),
      );

      expect(
        await client.supportsModule(moduleType: Erc7579ModuleType.validator),
        isTrue,
      );
      expect(
        await client.supportsExecutionMode(
          mode: const ExecutionMode(type: Erc7579CallKind.call),
        ),
        isTrue,
      );
      expect(
        await client.isModuleInstalled(
          type: Erc7579ModuleType.validator,
          address: moduleAddress,
        ),
        isTrue,
      );
      expect(await client.getAccountId(), equals('kernel.advanced.0.3.1'));
      expect(txs, hasLength(4));
      expect(txs.every((tx) => tx['to'] == mockAddress.hex), isTrue);
    });

    test('propagates error when direct and factory fallback both fail',
        () async {
      final client = createClient();
      final public = publicClientFromHandler(
        (_) => {
          'error': {
            'code': -32000,
            'message': 'execution reverted',
          },
        },
      );

      await expectLater(
        client.supportsModule(
          publicClient: public,
          moduleType: Erc7579ModuleType.hook,
        ),
        throwsA(isA<BundlerRpcError>()),
      );
    });
  });
}

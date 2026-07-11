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
  ) {
    return createPublicClient(
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
        final client = createClient();
        var callCount = 0;
        final public = publicClientFromHandler((body) {
          callCount++;
          final params = body['params'] as List<dynamic>;
          final tx = params[0] as Map<String, dynamic>;
          if (callCount == 1) {
            // Direct call to account (has `to`) — simulate undeployed revert
            expect(tx.containsKey('to'), isTrue);
            return {
              'error': {
                'code': -32000,
                'message': 'execution reverted',
              },
            };
          }
          // Deployless factory fallback — no `to`
          expect(tx.containsKey('to'), isFalse);
          final data = tx['data'] as String;
          expect(
            data.startsWith('0x608060405234801561001057600080fd5b50'),
            isTrue,
          );
          return boolTrue;
        });

        final result = await client.supportsModule(
          publicClient: public,
          moduleType: Erc7579ModuleType.validator,
        );
        expect(result, isTrue);
        expect(callCount, equals(2));
      },
    );

    test('isModuleInstalled uses factory fallback', () async {
      final client = createClient();
      var callCount = 0;
      final public = publicClientFromHandler((body) {
        callCount++;
        if (callCount == 1) {
          return {
            'error': {'code': -32000, 'message': 'execution reverted'},
          };
        }
        return boolTrue;
      });

      final result = await client.isModuleInstalled(
        publicClient: public,
        type: Erc7579ModuleType.validator,
        address: moduleAddress,
      );
      expect(result, isTrue);
      expect(callCount, equals(2));
    });

    test(
      'supportsModule falls back when direct call returns empty 0x (no error)',
      () async {
        // Geth-style nodes often return success with "0x" for eth_call to an
        // undeployed address instead of reverting.
        final client = createClient();
        var callCount = 0;
        final public = publicClientFromHandler((body) {
          callCount++;
          if (callCount == 1) {
            return '0x';
          }
          final params = body['params'] as List<dynamic>;
          final tx = params[0] as Map<String, dynamic>;
          expect(tx.containsKey('to'), isFalse);
          return boolTrue;
        });

        final result = await client.supportsModule(
          publicClient: public,
          moduleType: Erc7579ModuleType.validator,
        );
        expect(result, isTrue);
        expect(callCount, equals(2));
      },
    );

    test('getAccountId uses factory fallback and decodes string', () async {
      final client = createClient();
      var callCount = 0;
      final public = publicClientFromHandler((body) {
        callCount++;
        if (callCount == 1) {
          return {
            'error': {'code': -32000, 'message': 'execution reverted'},
          };
        }
        return accountIdResult;
      });

      final id = await client.getAccountId(publicClient: public);
      expect(id, equals('kernel.advanced.0.3.1'));
      expect(callCount, equals(2));
    });

    test('supportsExecutionMode uses factory fallback', () async {
      final client = createClient();
      var callCount = 0;
      final public = publicClientFromHandler((body) {
        callCount++;
        if (callCount == 1) {
          return {
            'error': {'code': -32000, 'message': 'execution reverted'},
          };
        }
        return boolTrue;
      });

      final result = await client.supportsExecutionMode(
        publicClient: public,
        mode: ExecutionMode(
          type: Erc7579CallKind.batchCall,
          revertOnError: true,
        ),
      );
      expect(result, isTrue);
      expect(callCount, equals(2));
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

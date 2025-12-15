import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('BundlerClient', () {
    late BundlerClient client;
    late List<Map<String, dynamic>> capturedRequests;

    // Helper to create a mock HTTP client
    MockClient createMockClient(
      dynamic Function(Map<String, dynamic> request) responseFactory,
    ) {
      capturedRequests = [];
      return MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedRequests.add(body);
        final response = responseFactory(body);
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': response,
          }),
          200,
        );
      });
    }

    // Helper to create mock client with error response
    MockClient createErrorMockClient(
      int code,
      String message, {
      dynamic data,
    }) =>
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {
                'code': code,
                'message': message,
                if (data != null) 'data': data,
              },
            }),
            200,
          );
        });

    group('sendUserOperation', () {
      test('sends user operation and returns hash', () async {
        const expectedHash =
            '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

        final mockClient = createMockClient((_) => expectedHash);
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthAddress('0x1234567890123456789012345678901234567890'),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final result = await client.sendUserOperation(userOp);

        expect(result, equals(expectedHash));
        expect(capturedRequests.length, equals(1));
        expect(capturedRequests[0]['method'], equals('eth_sendUserOperation'));
        expect(
          capturedRequests[0]['params'][1],
          equals(EntryPointAddresses.v07.hex),
        );
      });

      test('throws BundlerRpcError on validation failure', () async {
        final mockClient = createErrorMockClient(
          -32602,
          'AA21 didn\'t pay prefund',
          data: 'AA21',
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthAddress('0x1234567890123456789012345678901234567890'),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(
          () => client.sendUserOperation(userOp),
          throwsA(
            isA<BundlerRpcError>().having(
              (e) => e.aaErrorCode,
              'aaErrorCode',
              'AA21',
            ),
          ),
        );
      });
    });

    group('estimateUserOperationGas', () {
      test('returns gas estimate for v0.7', () async {
        final mockClient = createMockClient(
          (_) => {
            'preVerificationGas': '0x5208',
            'verificationGasLimit': '0x186a0',
            'callGasLimit': '0x186a0',
            'paymasterVerificationGasLimit': '0xc350',
            'paymasterPostOpGasLimit': '0x4e20',
          },
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthAddress('0x1234567890123456789012345678901234567890'),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final estimate = await client.estimateUserOperationGas(userOp);

        expect(estimate.preVerificationGas, equals(BigInt.from(21000)));
        expect(estimate.verificationGasLimit, equals(BigInt.from(100000)));
        expect(estimate.callGasLimit, equals(BigInt.from(100000)));
        expect(
          estimate.paymasterVerificationGasLimit,
          equals(BigInt.from(50000)),
        );
        expect(estimate.paymasterPostOpGasLimit, equals(BigInt.from(20000)));

        expect(
          capturedRequests[0]['method'],
          equals('eth_estimateUserOperationGas'),
        );
      });

      test('handles v0.6 response format', () async {
        final mockClient = createMockClient(
          (_) => {
            'preVerificationGas': '0x5208',
            'verificationGas': '0x186a0', // v0.6 uses verificationGas
            'callGasLimit': '0x186a0',
          },
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v06,
          httpClient: mockClient,
        );

        final userOp = UserOperationV06(
          sender: EthAddress('0x1234567890123456789012345678901234567890'),
          nonce: BigInt.zero,
          initCode: '0x',
          callData: '0x',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          paymasterAndData: '0x',
          signature: '0x',
        );

        final estimate = await client.estimateUserOperationGas(userOp);

        expect(estimate.verificationGasLimit, equals(BigInt.from(100000)));
      });
    });

    group('getUserOperationByHash', () {
      test('returns operation when found', () async {
        final mockClient = createMockClient(
          (_) => {
            'userOperation': {
              'sender': '0x1234567890123456789012345678901234567890',
              'nonce': '0x0',
              'callData': '0x',
            },
            'entryPoint': '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
            'blockNumber': '0x100',
            'blockHash':
                '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
            'transactionHash':
                '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          },
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.getUserOperationByHash(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result, isNotNull);
        expect(result!.entryPoint, equals(EntryPointAddresses.v07));
        expect(result.blockNumber, equals(BigInt.from(256)));
        expect(
          capturedRequests[0]['method'],
          equals('eth_getUserOperationByHash'),
        );
      });

      test('returns null when not found', () async {
        final mockClient = createMockClient((_) => null);
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.getUserOperationByHash(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result, isNull);
      });
    });

    group('getUserOperationReceipt', () {
      test('returns receipt when found', () async {
        final mockClient = createMockClient(
          (_) => {
            'userOpHash':
                '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
            'sender': '0x1234567890123456789012345678901234567890',
            'nonce': '0x0',
            'success': true,
            'actualGasCost': '0x38d7ea4c68000',
            'actualGasUsed': '0x186a0',
            'logs': <dynamic>[],
          },
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.getUserOperationReceipt(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result, isNotNull);
        expect(result!.success, isTrue);
        expect(result.actualGasUsed, equals(BigInt.from(100000)));
        expect(
          capturedRequests[0]['method'],
          equals('eth_getUserOperationReceipt'),
        );
      });

      test('returns null when pending', () async {
        final mockClient = createMockClient((_) => null);
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.getUserOperationReceipt(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        );

        expect(result, isNull);
      });
    });

    group('supportedEntryPoints', () {
      test('returns list of supported entry points', () async {
        final mockClient = createMockClient(
          (_) => [
            '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789',
            '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
          ],
        );
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.supportedEntryPoints();

        expect(result.length, equals(2));
        expect(result[0], equals(EntryPointAddresses.v06));
        expect(result[1], equals(EntryPointAddresses.v07));
        expect(
          capturedRequests[0]['method'],
          equals('eth_supportedEntryPoints'),
        );
      });
    });

    group('chainId', () {
      test('returns chain ID', () async {
        final mockClient = createMockClient((_) => '0x1'); // Mainnet
        client = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final result = await client.chainId();

        expect(result, equals(BigInt.one));
        expect(capturedRequests[0]['method'], equals('eth_chainId'));
      });
    });
  });

  group('JsonRpcClient', () {
    test('increments request ID', () async {
      final requests = <Map<String, dynamic>>[];
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': null}),
          200,
        );
      });

      final rpcClient = JsonRpcClient(
        url: Uri.parse('http://localhost:3000'),
        httpClient: mockClient,
      );

      await rpcClient.call('method1');
      await rpcClient.call('method2');
      await rpcClient.call('method3');

      expect(requests[0]['id'], equals(1));
      expect(requests[1]['id'], equals(2));
      expect(requests[2]['id'], equals(3));
    });

    test('batch returns results in order', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as List<dynamic>;
        // Return results in reverse order to test reordering
        final responses = body.reversed.map((req) {
          final r = req as Map<String, dynamic>;
          return {
            'jsonrpc': '2.0',
            'id': r['id'],
            'result': 'result_${r['method']}',
          };
        }).toList();
        return http.Response(jsonEncode(responses), 200);
      });

      final rpcClient = JsonRpcClient(
        url: Uri.parse('http://localhost:3000'),
        httpClient: mockClient,
      );

      final results = await rpcClient.batch([
        const RpcRequest('method1'),
        const RpcRequest('method2'),
        const RpcRequest('method3'),
      ]);

      expect(results[0], equals('result_method1'));
      expect(results[1], equals('result_method2'));
      expect(results[2], equals('result_method3'));
    });
  });

  group('UserOperationGasEstimate', () {
    test('parses from JSON with hex values', () {
      final estimate = UserOperationGasEstimate.fromJson({
        'preVerificationGas': '0x5208',
        'verificationGasLimit': '0x186a0',
        'callGasLimit': '0x186a0',
      });

      expect(estimate.preVerificationGas, equals(BigInt.from(21000)));
      expect(estimate.verificationGasLimit, equals(BigInt.from(100000)));
      expect(estimate.callGasLimit, equals(BigInt.from(100000)));
    });

    test('parses from JSON with decimal values', () {
      final estimate = UserOperationGasEstimate.fromJson({
        'preVerificationGas': 21000,
        'verificationGasLimit': 100000,
        'callGasLimit': 100000,
      });

      expect(estimate.preVerificationGas, equals(BigInt.from(21000)));
      expect(estimate.verificationGasLimit, equals(BigInt.from(100000)));
      expect(estimate.callGasLimit, equals(BigInt.from(100000)));
    });
  });

  group('BundlerRpcError', () {
    test('extracts AA error code', () {
      const error = BundlerRpcError(
        code: -32602,
        message: 'AA21 didn\'t pay prefund',
        data: 'AA21 didn\'t pay prefund',
      );

      expect(error.aaErrorCode, equals('AA21'));
    });

    test('returns null for non-AA errors', () {
      const error = BundlerRpcError(
        code: -32600,
        message: 'Invalid Request',
      );

      expect(error.aaErrorCode, isNull);
    });
  });
}

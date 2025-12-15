import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('PublicClient', () {
    late PublicClient client;
    late List<Map<String, dynamic>> capturedRequests;

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

    group('getCode', () {
      test('returns bytecode for deployed contract', () async {
        final mockClient = createMockClient(
          (_) => '0x608060405234801561001057600080fd5b50',
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final code = await client.getCode(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(code, equals('0x608060405234801561001057600080fd5b50'));
        expect(capturedRequests[0]['method'], equals('eth_getCode'));
        expect(capturedRequests[0]['params'][1], equals('latest'));
      });

      test('returns 0x for EOA', () async {
        final mockClient = createMockClient((_) => '0x');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final code = await client.getCode(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(code, equals('0x'));
      });

      test('supports custom block tag', () async {
        final mockClient = createMockClient((_) => '0x');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        await client.getCode(
          EthAddress('0x1234567890123456789012345678901234567890'),
          blockTag: 'pending',
        );

        expect(capturedRequests[0]['params'][1], equals('pending'));
      });
    });

    group('isDeployed', () {
      test('returns true for deployed contract', () async {
        final mockClient = createMockClient(
          (_) => '0x608060405234801561001057600080fd5b50',
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final deployed = await client.isDeployed(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(deployed, isTrue);
      });

      test('returns false for EOA', () async {
        final mockClient = createMockClient((_) => '0x');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final deployed = await client.isDeployed(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(deployed, isFalse);
      });
    });

    group('getBalance', () {
      test('returns balance in wei', () async {
        final mockClient = createMockClient(
          (_) => '0xde0b6b3a7640000', // 1 ETH in wei
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final balance = await client.getBalance(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(balance, equals(BigInt.parse('1000000000000000000')));
        expect(capturedRequests[0]['method'], equals('eth_getBalance'));
      });

      test('handles zero balance', () async {
        final mockClient = createMockClient((_) => '0x0');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final balance = await client.getBalance(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(balance, equals(BigInt.zero));
      });
    });

    group('call', () {
      test('executes call and returns result', () async {
        final mockClient = createMockClient(
          (_) =>
              '0x0000000000000000000000000000000000000000000000000000000000000064',
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final result = await client.call(
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            data: '0x70a08231', // balanceOf selector
          ),
        );

        expect(
          result,
          equals(
            '0x0000000000000000000000000000000000000000000000000000000000000064',
          ),
        );
        expect(capturedRequests[0]['method'], equals('eth_call'));
      });

      test('includes value when non-zero', () async {
        final mockClient = createMockClient((_) => '0x');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        await client.call(
          Call(
            to: EthAddress('0x1234567890123456789012345678901234567890'),
            value: BigInt.from(1000000000000000000),
            data: '0x',
          ),
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        final callParams = params[0] as Map<String, dynamic>;
        expect(callParams.containsKey('value'), isTrue);
      });
    });

    group('getTransactionCount', () {
      test('returns nonce', () async {
        final mockClient = createMockClient((_) => '0x5');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final nonce = await client.getTransactionCount(
          EthAddress('0x1234567890123456789012345678901234567890'),
        );

        expect(nonce, equals(BigInt.from(5)));
        expect(
          capturedRequests[0]['method'],
          equals('eth_getTransactionCount'),
        );
      });
    });

    group('getGasPrice', () {
      test('returns gas price in wei', () async {
        final mockClient = createMockClient(
          (_) => '0x3b9aca00', // 1 gwei
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final gasPrice = await client.getGasPrice();

        expect(gasPrice, equals(BigInt.from(1000000000)));
        expect(capturedRequests[0]['method'], equals('eth_gasPrice'));
      });
    });

    group('getMaxPriorityFeePerGas', () {
      test('returns priority fee', () async {
        final mockClient = createMockClient(
          (_) => '0x77359400', // 2 gwei
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final priorityFee = await client.getMaxPriorityFeePerGas();

        expect(priorityFee, equals(BigInt.from(2000000000)));
        expect(
          capturedRequests[0]['method'],
          equals('eth_maxPriorityFeePerGas'),
        );
      });
    });

    group('getChainId', () {
      test('returns chain ID', () async {
        final mockClient = createMockClient((_) => '0x1');
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final chainId = await client.getChainId();

        expect(chainId, equals(BigInt.one));
        expect(capturedRequests[0]['method'], equals('eth_chainId'));
      });
    });

    group('getFeeData', () {
      test('returns gas price and priority fee', () async {
        var callCount = 0;
        final mockClient = createMockClient((body) {
          callCount++;
          if (callCount == 1) return '0x3b9aca00'; // gas price: 1 gwei
          return '0x77359400'; // priority fee: 2 gwei
        });
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final feeData = await client.getFeeData();

        expect(feeData.gasPrice, equals(BigInt.from(1000000000)));
        expect(feeData.maxPriorityFeePerGas, equals(BigInt.from(2000000000)));
      });
    });

    group('getAccountNonce', () {
      test('returns ERC-4337 nonce from EntryPoint', () async {
        final mockClient = createMockClient(
          (_) =>
              '0x0000000000000000000000000000000000000000000000000000000000000003',
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final nonce = await client.getAccountNonce(
          EthAddress('0x1234567890123456789012345678901234567890'),
          EntryPointAddresses.v07,
        );

        expect(nonce, equals(BigInt.from(3)));
        expect(capturedRequests[0]['method'], equals('eth_call'));

        // Verify call is to EntryPoint
        final params = capturedRequests[0]['params'] as List<dynamic>;
        final callParams = params[0] as Map<String, dynamic>;
        expect(callParams['to'], equals(EntryPointAddresses.v07.hex));

        // Verify function selector (getNonce)
        expect(callParams['data'].toString().startsWith('0x35567e1a'), isTrue);
      });

      test('supports custom nonce key', () async {
        final mockClient = createMockClient(
          (_) =>
              '0x0000000000000000000000000000000000000000000000000000000000000001',
        );
        client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final nonce = await client.getAccountNonce(
          EthAddress('0x1234567890123456789012345678901234567890'),
          EntryPointAddresses.v07,
          nonceKey: BigInt.from(1),
        );

        expect(nonce, equals(BigInt.one));

        // Verify nonce key is encoded in call data
        final params = capturedRequests[0]['params'] as List<dynamic>;
        final callParams = params[0] as Map<String, dynamic>;
        final data = callParams['data'] as String;
        // Nonce key should be last 32 bytes (64 hex chars)
        expect(
          data.endsWith('0000000000000000000000000000000000000001'),
          isTrue,
        );
      });
    });

    group('createPublicClient', () {
      test('creates client with factory function', () {
        final mockClient = createMockClient((_) => '0x1');

        final public = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        expect(public, isA<PublicClient>());
      });
    });

    group('getSenderAddress', () {
      test('returns address from SenderAddressResult revert', () async {
        // Mock client that simulates the EntryPoint revert with SenderAddressResult
        final mockClient = MockClient(
          (request) async => http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': 3,
                'message': 'execution reverted',
                // SenderAddressResult(address sender) with address 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
                'data':
                    '0x6ca7b806000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045',
              },
            }),
            200,
          ),
        );
        final client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        const initCode = '0x5de4839a76cf55d0c90e2061ef4386d962E15ae3'
            '5fbfb9cf0000000000000000000000000000000000000000000000000000000000000001';

        final address = await client.getSenderAddress(
          initCode: initCode,
          entryPoint: EntryPointAddresses.v07,
        );

        expect(
          address.hex.toLowerCase(),
          equals('0xd8da6bf26964af9d7eed9e03e53415d37aa96045'),
        );
      });

      test('handles wrapped error format', () async {
        // Some nodes wrap the error data differently
        final mockClient = MockClient(
          (request) async => http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': -32000,
                'message': 'execution reverted',
                // Error data with SenderAddressResult embedded
                'data':
                    '0x08c379a00000006ca7b806000000000000000000000000abcdef1234567890abcdef1234567890abcdef12',
              },
            }),
            200,
          ),
        );
        final client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        final address = await client.getSenderAddress(
          initCode: '0x1234567890123456789012345678901234567890abcdef',
          entryPoint: EntryPointAddresses.v07,
        );

        expect(
          address.hex.toLowerCase(),
          equals('0xabcdef1234567890abcdef1234567890abcdef12'),
        );
      });

      test('throws PublicRpcError for non-SenderAddressResult revert',
          () async {
        final mockClient = MockClient(
          (request) async => http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': -32000,
                'message': 'execution reverted: invalid initCode',
                'data': '0x08c379a0',
              },
            }),
            200,
          ),
        );
        final client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        expect(
          () => client.getSenderAddress(
            initCode: '0xinvalid',
            entryPoint: EntryPointAddresses.v07,
          ),
          throwsA(isA<PublicRpcError>()),
        );
      });

      test('encodes initCode correctly in call data', () async {
        String? capturedData;
        final mockClient = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final params = body['params'] as List<dynamic>;
          final callParams = params[0] as Map<String, dynamic>;
          capturedData = callParams['data'] as String;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': 3,
                'message': 'execution reverted',
                'data':
                    '0x6ca7b8060000000000000000000000001234567890123456789012345678901234567890',
              },
            }),
            200,
          );
        });
        final client = createPublicClient(
          url: 'http://localhost:8545',
          httpClient: mockClient,
        );

        await client.getSenderAddress(
          initCode: '0xaabbccdd',
          entryPoint: EntryPointAddresses.v07,
        );

        // Verify function selector
        expect(capturedData!.startsWith('0x9b249f69'), isTrue);
        // Verify offset (32 = 0x20)
        expect(
          capturedData!.substring(10, 74),
          equals(
            '0000000000000000000000000000000000000000000000000000000000000020',
          ),
        );
        // Verify length (4 bytes = aabbccdd)
        expect(
          capturedData!.substring(74, 138),
          equals(
            '0000000000000000000000000000000000000000000000000000000000000004',
          ),
        );
        // Verify initCode (padded to word boundary)
        expect(capturedData!.substring(138, 202), startsWith('aabbccdd'));
      });
    });
  });

  group('FeeData', () {
    test('stores gas price', () {
      final feeData = FeeData(gasPrice: BigInt.zero);

      expect(feeData.gasPrice, equals(BigInt.zero));
      expect(feeData.maxPriorityFeePerGas, isNull);
    });

    test('stores priority fee when provided', () {
      final feeData = FeeData(
        gasPrice: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(2000000000),
      );

      expect(feeData.gasPrice, equals(BigInt.from(1000000000)));
      expect(feeData.maxPriorityFeePerGas, equals(BigInt.from(2000000000)));
    });
  });

  group('PublicRpcError', () {
    test('formats error message', () {
      const error = PublicRpcError(
        code: -32000,
        message: 'execution reverted',
        data: 'revert reason',
      );

      expect(
        error.toString(),
        equals('PublicRpcError(-32000): execution reverted - revert reason'),
      );
    });

    test('formats error without data', () {
      const error = PublicRpcError(
        code: -32602,
        message: 'invalid params',
      );

      expect(
        error.toString(),
        equals('PublicRpcError(-32602): invalid params'),
      );
    });
  });
}

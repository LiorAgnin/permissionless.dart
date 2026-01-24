import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('EtherspotClient', () {
    late EtherspotClient client;
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

    group('getUserOperationGasPrice', () {
      test('returns gas price from skandha_getGasPrice', () async {
        final mockClient = createMockClient(
          (_) => {
            'maxFeePerGas': '0x77359400', // 2 gwei
            'maxPriorityFeePerGas': '0x3b9aca00', // 1 gwei
          },
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final gasPrice = await client.getUserOperationGasPrice();

        expect(gasPrice.maxFeePerGas, equals(BigInt.from(2000000000)));
        expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(1000000000)));
        expect(
          capturedRequests[0]['method'],
          equals('skandha_getGasPrice'),
        );
      });

      test('handles decimal string values', () async {
        final mockClient = createMockClient(
          (_) => {
            'maxFeePerGas': '5000000000',
            'maxPriorityFeePerGas': '2500000000',
          },
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final gasPrice = await client.getUserOperationGasPrice();

        expect(gasPrice.maxFeePerGas, equals(BigInt.from(5000000000)));
        expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(2500000000)));
      });

      test('handles integer values', () async {
        final mockClient = createMockClient(
          (_) => {
            'maxFeePerGas': 1000000000,
            'maxPriorityFeePerGas': 500000000,
          },
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final gasPrice = await client.getUserOperationGasPrice();

        expect(gasPrice.maxFeePerGas, equals(BigInt.from(1000000000)));
        expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(500000000)));
      });
    });

    group('inherits BundlerClient methods', () {
      test('can call sendUserOperation', () async {
        final mockClient = createMockClient(
          (_) => '0xuserophash1234567890abcdef1234567890abcdef',
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0xsignature',
        );

        final hash = await client.sendUserOperation(userOp);

        expect(hash, isNotEmpty);
        expect(capturedRequests[0]['method'], equals('eth_sendUserOperation'));
      });

      test('can call estimateUserOperationGas', () async {
        final mockClient = createMockClient(
          (_) => {
            'preVerificationGas': '0xc350',
            'verificationGasLimit': '0x30d40',
            'callGasLimit': '0x186a0',
          },
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0x',
        );

        final estimate = await client.estimateUserOperationGas(userOp);

        expect(estimate.preVerificationGas, equals(BigInt.from(50000)));
        expect(estimate.verificationGasLimit, equals(BigInt.from(200000)));
        expect(estimate.callGasLimit, equals(BigInt.from(100000)));
        expect(
          capturedRequests[0]['method'],
          equals('eth_estimateUserOperationGas'),
        );
      });

      test('can call getUserOperationReceipt', () async {
        final mockClient = createMockClient(
          (_) => {
            'userOpHash': '0x1234567890abcdef',
            'sender': '0x1234567890123456789012345678901234567890',
            'nonce': '0x1',
            'success': true,
            'actualGasCost': '0x12345',
            'actualGasUsed': '0x5000',
            'logs': <dynamic>[],
          },
        );
        client = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final receipt = await client.getUserOperationReceipt('0x1234');

        expect(receipt, isNotNull);
        expect(receipt!.success, isTrue);
        expect(
          capturedRequests[0]['method'],
          equals('eth_getUserOperationReceipt'),
        );
      });
    });

    group('createEtherspotClient', () {
      test('creates client with factory function', () {
        final mockClient = createMockClient((_) => '0x1');

        final etherspot = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        expect(etherspot, isA<EtherspotClient>());
        expect(etherspot, isA<BundlerClient>());
      });

      test('accepts custom timeout', () {
        final mockClient = createMockClient((_) => '0x1');

        final etherspot = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
          timeout: const Duration(seconds: 60),
        );

        expect(etherspot, isA<EtherspotClient>());
      });

      test('accepts custom headers', () {
        final mockClient = createMockClient((_) => '0x1');

        final etherspot = createEtherspotClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
          headers: {'Authorization': 'Bearer token'},
        );

        expect(etherspot, isA<EtherspotClient>());
      });
    });
  });

  group('EtherspotGasPrice', () {
    test('fromJson with hex values', () {
      final gasPrice = EtherspotGasPrice.fromJson({
        'maxFeePerGas': '0x77359400',
        'maxPriorityFeePerGas': '0x3b9aca00',
      });

      expect(gasPrice.maxFeePerGas, equals(BigInt.from(2000000000)));
      expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(1000000000)));
    });

    test('fromJson with decimal string values', () {
      final gasPrice = EtherspotGasPrice.fromJson({
        'maxFeePerGas': '3000000000',
        'maxPriorityFeePerGas': '1500000000',
      });

      expect(gasPrice.maxFeePerGas, equals(BigInt.from(3000000000)));
      expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(1500000000)));
    });

    test('fromJson with int values', () {
      final gasPrice = EtherspotGasPrice.fromJson({
        'maxFeePerGas': 1000000000,
        'maxPriorityFeePerGas': 500000000,
      });

      expect(gasPrice.maxFeePerGas, equals(BigInt.from(1000000000)));
      expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.from(500000000)));
    });

    test('toString formats correctly', () {
      final gasPrice = EtherspotGasPrice(
        maxFeePerGas: BigInt.from(2000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );
      expect(
        gasPrice.toString(),
        equals(
          'EtherspotGasPrice(maxFee: 2000000000, maxPriority: 1000000000)',
        ),
      );
    });

    test('stores values correctly', () {
      final gasPrice = EtherspotGasPrice(
        maxFeePerGas: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
      );
      expect(gasPrice.maxFeePerGas, equals(BigInt.zero));
      expect(gasPrice.maxPriorityFeePerGas, equals(BigInt.zero));
    });
  });
}

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

    test('createEtherspotClient sends custom headers', () async {
      final seenHeaders = <Map<String, String>>[];
      final etherspot = createEtherspotClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: MockClient((request) async {
          seenHeaders.add(request.headers);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'maxFeePerGas': '0x1',
                'maxPriorityFeePerGas': '0x1',
              },
            }),
            200,
          );
        }),
        headers: {'Authorization': 'Bearer token'},
      );

      await etherspot.getUserOperationGasPrice();

      expect(seenHeaders.single['Authorization'], equals('Bearer token'));
    });
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('PimlicoClient', () {
    late PimlicoClient client;
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

    group('getUserOperationStatus', () {
      test('returns included status with receipt', () async {
        final mockClient = createMockClient(
          (_) => {
            'status': 'included',
            'transactionHash': '0xabc123',
            'receipt': {
              'userOpHash': '0x1234567890abcdef',
              'sender': '0x1234567890123456789012345678901234567890',
              'nonce': '0x1',
              'success': true,
              'actualGasCost': '0x12345',
              'actualGasUsed': '0x5000',
              'logs': <dynamic>[],
            },
          },
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final status = await client.getUserOperationStatus('0x1234');

        expect(status.status, equals('included'));
        expect(status.transactionHash, equals('0xabc123'));
        expect(status.receipt, isNotNull);
        expect(status.receipt!.success, isTrue);
        expect(status.isSuccess, isTrue);
        expect(status.isPending, isFalse);
        expect(status.isFailed, isFalse);
        expect(
          capturedRequests[0]['method'],
          equals('pimlico_getUserOperationStatus'),
        );
      });

      test('returns submitted status without receipt', () async {
        final mockClient = createMockClient(
          (_) => {
            'status': 'submitted',
            'transactionHash': '0xpending',
          },
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final status = await client.getUserOperationStatus('0x1234');

        expect(status.status, equals('submitted'));
        expect(status.transactionHash, equals('0xpending'));
        expect(status.receipt, isNull);
        expect(status.isPending, isTrue);
        expect(status.isSuccess, isFalse);
        expect(status.isFailed, isFalse);
      });

      test('returns not_found status', () async {
        final mockClient = createMockClient(
          (_) => {'status': 'not_found'},
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final status = await client.getUserOperationStatus('0xnonexistent');

        expect(status.status, equals('not_found'));
        expect(status.isPending, isFalse);
        expect(status.isSuccess, isFalse);
        expect(status.isFailed, isFalse);
      });

      test('returns rejected status', () async {
        final mockClient = createMockClient(
          (_) => {'status': 'rejected'},
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final status = await client.getUserOperationStatus('0xrejected');

        expect(status.status, equals('rejected'));
        expect(status.isFailed, isTrue);
        expect(status.isSuccess, isFalse);
      });

      test('returns reverted status', () async {
        final mockClient = createMockClient(
          (_) => {'status': 'reverted'},
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final status = await client.getUserOperationStatus('0xreverted');

        expect(status.status, equals('reverted'));
        expect(status.isFailed, isTrue);
      });
    });

    group('getUserOperationGasPrice', () {
      test('returns slow, standard, and fast gas prices', () async {
        final mockClient = createMockClient(
          (_) => {
            'slow': {
              'maxFeePerGas': '0x3b9aca00', // 1 gwei
              'maxPriorityFeePerGas': '0x5f5e100', // 0.1 gwei
            },
            'standard': {
              'maxFeePerGas': '0x77359400', // 2 gwei
              'maxPriorityFeePerGas': '0xbebc200', // 0.2 gwei
            },
            'fast': {
              'maxFeePerGas': '0xb2d05e00', // 3 gwei
              'maxPriorityFeePerGas': '0x11e1a300', // 0.3 gwei
            },
          },
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final prices = await client.getUserOperationGasPrice();

        expect(prices.slow.maxFeePerGas, equals(BigInt.from(1000000000)));
        expect(
          prices.slow.maxPriorityFeePerGas,
          equals(BigInt.from(100000000)),
        );
        expect(prices.standard.maxFeePerGas, equals(BigInt.from(2000000000)));
        expect(
          prices.standard.maxPriorityFeePerGas,
          equals(BigInt.from(200000000)),
        );
        expect(prices.fast.maxFeePerGas, equals(BigInt.from(3000000000)));
        expect(
          prices.fast.maxPriorityFeePerGas,
          equals(BigInt.from(300000000)),
        );
        expect(
          capturedRequests[0]['method'],
          equals('pimlico_getUserOperationGasPrice'),
        );
      });

      test('handles decimal string values', () async {
        final mockClient = createMockClient(
          (_) => {
            'slow': {
              'maxFeePerGas': '1000000000',
              'maxPriorityFeePerGas': '100000000',
            },
            'standard': {
              'maxFeePerGas': '2000000000',
              'maxPriorityFeePerGas': '200000000',
            },
            'fast': {
              'maxFeePerGas': '3000000000',
              'maxPriorityFeePerGas': '300000000',
            },
          },
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final prices = await client.getUserOperationGasPrice();

        expect(prices.slow.maxFeePerGas, equals(BigInt.from(1000000000)));
        expect(prices.fast.maxFeePerGas, equals(BigInt.from(3000000000)));
      });
    });

    group('sendCompressedUserOperation', () {
      test('sends 3 params matching Pimlico/JS schema', () async {
        final mockClient = createMockClient(
          (_) => '0xcompresseduserophash1234567890abcdef',
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        final inflator = EthereumAddress.fromHex(
          '0xabcdef1234567890abcdef1234567890abcdef12',
        );
        const compressedUserOperation = '0xcompresseddata123';

        // ignore: deprecated_member_use_from_same_package
        final hash = await client.sendCompressedUserOperation(
          compressedUserOperation,
          inflator,
        );

        expect(hash, equals('0xcompresseduserophash1234567890abcdef'));
        expect(
          capturedRequests[0]['method'],
          equals('pimlico_sendCompressedUserOperation'),
        );

        // JS/Pimlico: [compressedUserOperation, inflatorAddress, entryPoint]
        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params.length, equals(3));
        expect(params[0], equals(compressedUserOperation));
        expect(params[1], equals(inflator.hex));
        expect(params[2], equals(EntryPointAddresses.v07.hex));
      });

      test('uses client entryPoint for param 3', () async {
        final mockClient = createMockClient(
          (_) => '0xhash1234567890abcdef1234567890abcdef',
        );
        client = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v06,
          httpClient: mockClient,
        );

        // ignore: deprecated_member_use_from_same_package
        await client.sendCompressedUserOperation(
          '0xcompressed',
          EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params[0], equals('0xcompressed'));
        expect(params[2], equals(EntryPointAddresses.v06.hex));
      });
    });

    group('inherits BundlerClient methods', () {
      test('can call sendUserOperation', () async {
        final mockClient = createMockClient(
          (_) => '0xuserophash1234567890abcdef1234567890abcdef',
        );
        client = createPimlicoClient(
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
        client = createPimlicoClient(
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
    });

    group('createPimlicoClient', () {
      test('creates client with factory function', () {
        final mockClient = createMockClient((_) => '0x1');

        final pimlico = createPimlicoClient(
          url: 'http://localhost:8545',
          entryPoint: EntryPointAddresses.v07,
          httpClient: mockClient,
        );

        expect(pimlico, isA<PimlicoClient>());
        expect(pimlico, isA<BundlerClient>());
      });
    });
  });

  group('PimlicoUserOperationStatus', () {
    test('isPending returns true for not_submitted', () {
      const status = PimlicoUserOperationStatus(status: 'not_submitted');
      expect(status.isPending, isTrue);
    });

    test('isPending returns true for submitted', () {
      const status = PimlicoUserOperationStatus(status: 'submitted');
      expect(status.isPending, isTrue);
    });

    test('isPending returns false for included', () {
      const status = PimlicoUserOperationStatus(status: 'included');
      expect(status.isPending, isFalse);
    });

    test('isFailed returns true for rejected/reverted/failed', () {
      expect(
        const PimlicoUserOperationStatus(status: 'rejected').isFailed,
        isTrue,
      );
      expect(
        const PimlicoUserOperationStatus(status: 'reverted').isFailed,
        isTrue,
      );
      expect(
        const PimlicoUserOperationStatus(status: 'failed').isFailed,
        isTrue,
      );
    });

    test('isSuccess requires included status and receipt.success', () {
      const statusWithoutReceipt = PimlicoUserOperationStatus(
        status: 'included',
      );
      expect(statusWithoutReceipt.isSuccess, isFalse);
    });

    test('toString formats correctly', () {
      const status = PimlicoUserOperationStatus(
        status: 'included',
        transactionHash: '0xabc',
      );
      expect(
        status.toString(),
        equals('PimlicoUserOperationStatus(included, tx: 0xabc)'),
      );
    });
  });

  group('PimlicoGasPrice', () {
    test('toString formats correctly', () {
      final price = PimlicoGasPrice(
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
      );
      expect(
        price.toString(),
        equals('PimlicoGasPrice(maxFee: 1000000000, maxPriority: 100000000)'),
      );
    });
  });

  group('PimlicoGasPrices', () {
    test('toString formats correctly', () {
      final prices = PimlicoGasPrices(
        slow: PimlicoGasPrice(
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
        ),
        standard: PimlicoGasPrice(
          maxFeePerGas: BigInt.from(2000000000),
          maxPriorityFeePerGas: BigInt.from(200000000),
        ),
        fast: PimlicoGasPrice(
          maxFeePerGas: BigInt.from(3000000000),
          maxPriorityFeePerGas: BigInt.from(300000000),
        ),
      );
      expect(prices.toString(), contains('slow:'));
      expect(prices.toString(), contains('standard:'));
      expect(prices.toString(), contains('fast:'));
    });
  });

  group('estimateErc20PaymasterCost', () {
    late PimlicoClient client;
    late List<Map<String, dynamic>> capturedRequests;

    /// Token quote fixture matching pimlico_getTokenQuotes response shape.
    Map<String, dynamic> tokenQuotesResult({
      required String token,
      String postOpGas = '0x124f8', // 75000
      String exchangeRate = '0xde0b6b3a7640000', // 1e18 (1:1)
      String exchangeRateNativeToUsd = '0xe4e1c0', // 15_000_000 ($15.00, 6 dec)
    }) =>
        {
          'quotes': [
            {
              'token': token,
              'paymaster': '0x0000000000000039cd5e8aE05257CE51C473ddd1',
              'postOpGas': postOpGas,
              'exchangeRate': exchangeRate,
              'exchangeRateNativeToUsd': exchangeRateNativeToUsd,
            },
          ],
        };

    MockClient createMockClient({
      Map<String, dynamic> Function(String token)? quotesForToken,
    }) {
      capturedRequests = [];
      return MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedRequests.add(body);
        final method = body['method'] as String;
        final dynamic result;
        if (method == 'eth_chainId') {
          result = '0xaa36a7'; // sepolia
        } else if (method == 'pimlico_getTokenQuotes') {
          final params = body['params'] as List<dynamic>;
          final tokensObj = params[0] as Map<String, dynamic>;
          final tokens = tokensObj['tokens'] as List<dynamic>;
          final token = tokens.first as String;
          result =
              quotesForToken?.call(token) ?? tokenQuotesResult(token: token);
        } else {
          throw StateError('Unexpected RPC method: $method');
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': result,
          }),
          200,
        );
      });
    }

    UserOperationV07 sampleV07() => UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000), // 1 gwei
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0xsignature',
        );

    test('computes cost locally via getTokenQuotes (no fictitious RPC)',
        () async {
      final token = EthereumAddress.fromHex(
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: createMockClient(),
      );

      final userOp = sampleV07();
      final cost = await client.estimateErc20PaymasterCost(
        userOperation: userOp,
        token: token,
      );

      // Never call the nonexistent pimlico_estimateErc20PaymasterCost
      expect(
        capturedRequests.map((r) => r['method']),
        isNot(contains('pimlico_estimateErc20PaymasterCost')),
      );
      expect(
        capturedRequests.map((r) => r['method']),
        containsAll(['eth_chainId', 'pimlico_getTokenQuotes']),
      );

      // prefund gas = 50k + 100k + 200k = 350k; * 1 gwei = 350e12 wei
      // + postOpGas 75k * 1 gwei = 75e12
      // maxCostInWei = 425e12
      // exchangeRate 1e18 => costInToken = 425e12
      // exchangeRateNativeToUsd 15e6 => costInUsd = 425e12 * 15e6 / 1e18
      final expectedPrefund = getRequiredPrefund(userOp);
      final postOpGas = BigInt.from(75000);
      final maxCostInWei = expectedPrefund + postOpGas * userOp.maxFeePerGas;
      final expectedToken =
          (maxCostInWei * BigInt.from(10).pow(18)) ~/ BigInt.from(10).pow(18);
      final expectedUsd =
          (maxCostInWei * BigInt.from(15000000)) ~/ BigInt.from(10).pow(18);

      expect(cost.costInToken, equals(expectedToken));
      expect(cost.costInUsd, equals(expectedUsd));
    });

    test('getTokenQuotes request params match JS fixture shape', () async {
      final token = EthereumAddress.fromHex(
        '0xdAC17F958D2ee523a2206206994597C13D831ec7',
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: createMockClient(),
      );

      await client.estimateErc20PaymasterCost(
        userOperation: sampleV07(),
        token: token,
      );

      final quotesReq = capturedRequests
          .firstWhere((r) => r['method'] == 'pimlico_getTokenQuotes');
      final params = quotesReq['params'] as List<dynamic>;

      // JS: [{ tokens }, entryPointAddress, numberToHex(chainId)]
      expect(params.length, equals(3));
      expect(
        (params[0] as Map<String, dynamic>)['tokens'],
        equals([token.hex]),
      );
      expect(params[1], equals(EntryPointAddresses.v07.hex));
      expect(params[2], equals('0xaa36a7'));
    });

    test('supports UserOperationV06 prefund formula', () async {
      final token = EthereumAddress.fromHex(
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v06,
        httpClient: createMockClient(),
      );

      final userOp = UserOperationV06(
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

      final cost = await client.estimateErc20PaymasterCost(
        userOperation: userOp,
        token: token,
      );

      final expectedPrefund = getRequiredPrefundV06(userOp);
      final maxCostInWei =
          expectedPrefund + BigInt.from(75000) * userOp.maxFeePerGas;
      final expectedToken =
          (maxCostInWei * BigInt.from(10).pow(18)) ~/ BigInt.from(10).pow(18);
      final expectedUsd =
          (maxCostInWei * BigInt.from(15000000)) ~/ BigInt.from(10).pow(18);

      expect(cost.costInToken, equals(expectedToken));
      expect(cost.costInUsd, equals(expectedUsd));
    });

    test('throws when token has no quotes', () async {
      final token = EthereumAddress.fromHex(
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: createMockClient(
          quotesForToken: (_) => {'quotes': <dynamic>[]},
        ),
      );

      expect(
        () => client.estimateErc20PaymasterCost(
          userOperation: sampleV07(),
          token: token,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('validateSponsorshipPolicies', () {
    late PimlicoClient client;
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

    UserOperationV07 sampleV07({BigInt? nonce}) => UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: nonce ?? BigInt.one,
          callData: '0xabcdef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(200000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(100000000),
          signature: '0xsignature',
        );

    test('returns valid sponsorship policies', () async {
      final mockClient = createMockClient(
        (_) => [
          {
            'sponsorshipPolicyId': 'sp_my_policy_123',
            'data': {
              'name': 'Test Policy',
              'author': 'Test Author',
              'icon': 'https://example.com/icon.png',
              'description': 'A test sponsorship policy',
            },
          },
        ],
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: sampleV07(),
        sponsorshipPolicyIds: ['sp_my_policy_123'],
      );

      expect(policies.length, equals(1));
      expect(policies[0].sponsorshipPolicyId, equals('sp_my_policy_123'));
      expect(policies[0].data.name, equals('Test Policy'));
      expect(policies[0].data.author, equals('Test Author'));
      expect(policies[0].data.icon, equals('https://example.com/icon.png'));
      expect(policies[0].data.description, equals('A test sponsorship policy'));
      expect(
        capturedRequests[0]['method'],
        equals('pm_validateSponsorshipPolicies'),
      );
    });

    test('returns multiple valid policies', () async {
      final mockClient = createMockClient(
        (_) => [
          {
            'sponsorshipPolicyId': 'sp_policy_1',
            'data': {'name': 'Policy One', 'author': 'Author 1'},
          },
          {
            'sponsorshipPolicyId': 'sp_policy_2',
            'data': {'name': 'Policy Two', 'author': 'Author 2'},
          },
        ],
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: sampleV07(),
        sponsorshipPolicyIds: ['sp_policy_1', 'sp_policy_2'],
      );

      expect(policies.length, equals(2));
      expect(policies[0].sponsorshipPolicyId, equals('sp_policy_1'));
      expect(policies[1].sponsorshipPolicyId, equals('sp_policy_2'));
    });

    test('returns empty list for empty policy IDs', () async {
      final mockClient = createMockClient((_) => <dynamic>[]);
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: sampleV07(),
        sponsorshipPolicyIds: [],
      );

      expect(policies, isEmpty);
      // Should not make an RPC call if no policy IDs provided
      expect(capturedRequests, isEmpty);
    });

    test('request params match JS fixture: method + deepHexlify userOp',
        () async {
      final mockClient = createMockClient((_) => <dynamic>[]);
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final userOp = sampleV07(nonce: BigInt.from(42));

      await client.validateSponsorshipPolicies(
        userOperation: userOp,
        sponsorshipPolicyIds: ['sp_test_1', 'sp_test_2'],
      );

      expect(
        capturedRequests[0]['method'],
        equals('pm_validateSponsorshipPolicies'),
      );

      // JS: [deepHexlify(userOperation), entryPointAddress, sponsorshipPolicyIds]
      final params = capturedRequests[0]['params'] as List<dynamic>;
      expect(params.length, equals(3));
      expect(params[0], equals(userOp.toJson()));
      expect(params[1], equals(EntryPointAddresses.v07.hex));
      expect(params[2], equals(['sp_test_1', 'sp_test_2']));
    });

    test('supports UserOperationV06 payload shape', () async {
      final mockClient = createMockClient((_) => <dynamic>[]);
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v06,
        httpClient: mockClient,
      );

      final userOp = UserOperationV06(
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
        signature: '0xsig',
        initCode: '0x',
        paymasterAndData: '0x',
      );

      await client.validateSponsorshipPolicies(
        userOperation: userOp,
        sponsorshipPolicyIds: ['sp_v06'],
      );

      final params = capturedRequests[0]['params'] as List<dynamic>;
      final sent = params[0] as Map<String, dynamic>;
      expect(sent['initCode'], equals('0x'));
      expect(sent['paymasterAndData'], equals('0x'));
      expect(sent.containsKey('factory'), isFalse);
      expect(params[1], equals(EntryPointAddresses.v06.hex));
    });

    test('handles null name/author in policy data', () async {
      final mockClient = createMockClient(
        (_) => [
          {
            'sponsorshipPolicyId': 'sp_null_fields',
            'data': {
              'name': null,
              'author': null,
              'icon': null,
              'description': null,
            },
          },
        ],
      );
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: sampleV07(),
        sponsorshipPolicyIds: ['sp_null_fields'],
      );

      expect(policies.length, equals(1));
      expect(policies[0].data.name, isNull);
      expect(policies[0].data.author, isNull);
      expect(policies[0].data.icon, isNull);
      expect(policies[0].data.description, isNull);
    });
  });

  group('PimlicoSponsorshipPolicy types', () {
    test('PimlicoSponsorshipPolicyData fromJson with all fields', () {
      final data = PimlicoSponsorshipPolicyData.fromJson({
        'name': 'My Policy',
        'author': 'My Company',
        'icon': 'https://example.com/icon.png',
        'description': 'A detailed description',
      });

      expect(data.name, equals('My Policy'));
      expect(data.author, equals('My Company'));
      expect(data.icon, equals('https://example.com/icon.png'));
      expect(data.description, equals('A detailed description'));
    });

    test('PimlicoSponsorshipPolicyData fromJson with minimal fields', () {
      final data = PimlicoSponsorshipPolicyData.fromJson({
        'name': 'Minimal',
        'author': 'Author',
      });

      expect(data.name, equals('Minimal'));
      expect(data.author, equals('Author'));
      expect(data.icon, isNull);
      expect(data.description, isNull);
    });

    test('PimlicoSponsorshipPolicyData fromJson with null name/author', () {
      final data = PimlicoSponsorshipPolicyData.fromJson({
        'name': null,
        'author': null,
        'icon': null,
        'description': null,
      });

      expect(data.name, isNull);
      expect(data.author, isNull);
      expect(data.icon, isNull);
      expect(data.description, isNull);
    });

    test('PimlicoSponsorshipPolicyData toString', () {
      const data = PimlicoSponsorshipPolicyData(
        name: 'Test',
        author: 'Test Author',
      );
      expect(
        data.toString(),
        equals('PimlicoSponsorshipPolicyData(name: Test, author: Test Author)'),
      );
    });

    test('PimlicoSponsorshipPolicy fromJson', () {
      final policy = PimlicoSponsorshipPolicy.fromJson({
        'sponsorshipPolicyId': 'sp_123',
        'data': {
          'name': 'Test',
          'author': 'Author',
        },
      });

      expect(policy.sponsorshipPolicyId, equals('sp_123'));
      expect(policy.data.name, equals('Test'));
      expect(policy.data.author, equals('Author'));
    });

    test('PimlicoSponsorshipPolicy toString', () {
      const policy = PimlicoSponsorshipPolicy(
        sponsorshipPolicyId: 'sp_test',
        data: PimlicoSponsorshipPolicyData(
          name: 'Test',
          author: 'Author',
        ),
      );
      expect(policy.toString(), equals('PimlicoSponsorshipPolicy(sp_test)'));
    });
  });

  group('PimlicoErc20PaymasterCost', () {
    test('fromJson with hex values', () {
      final cost = PimlicoErc20PaymasterCost.fromJson({
        'costInToken': '0x5f5e100',
        'costInUsd': '0xbebc200',
      });

      expect(cost.costInToken, equals(BigInt.from(100000000)));
      expect(cost.costInUsd, equals(BigInt.from(200000000)));
    });

    test('fromJson with decimal string values', () {
      final cost = PimlicoErc20PaymasterCost.fromJson({
        'costInToken': '123456789',
        'costInUsd': '987654321',
      });

      expect(cost.costInToken, equals(BigInt.from(123456789)));
      expect(cost.costInUsd, equals(BigInt.from(987654321)));
    });

    test('fromJson with int values', () {
      final cost = PimlicoErc20PaymasterCost.fromJson({
        'costInToken': 1000000,
        'costInUsd': 2000000,
      });

      expect(cost.costInToken, equals(BigInt.from(1000000)));
      expect(cost.costInUsd, equals(BigInt.from(2000000)));
    });

    test('toString formats correctly', () {
      final cost = PimlicoErc20PaymasterCost(
        costInToken: BigInt.from(100000000),
        costInUsd: BigInt.from(150000000),
      );
      expect(
        cost.toString(),
        equals('PimlicoErc20PaymasterCost(token: 100000000, usd: 150000000)'),
      );
    });
  });
}

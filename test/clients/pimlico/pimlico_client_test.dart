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
      test('sends compressed UserOp with inflator', () async {
        final mockClient = createMockClient(
          (_) => '0xcompresseduserophash1234567890abcdef',
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

        final inflator = EthereumAddress.fromHex(
          '0xabcdef1234567890abcdef1234567890abcdef12',
        );
        const compressedCalldata = '0xcompresseddata123';

        final hash = await client.sendCompressedUserOperation(
          userOp,
          inflator,
          compressedCalldata,
        );

        expect(hash, equals('0xcompresseduserophash1234567890abcdef'));
        expect(
          capturedRequests[0]['method'],
          equals('pimlico_sendCompressedUserOperation'),
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params[1], equals(EntryPointAddresses.v07.hex));
        expect(params[2], equals(compressedCalldata));
        expect(params[3], equals(inflator.hex));
      });

      test('includes factory and paymaster data when present', () async {
        final mockClient = createMockClient(
          (_) => '0xhash1234567890abcdef1234567890abcdef',
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
          factory: EthereumAddress.fromHex(
            '0xaaaa567890123456789012345678901234567890',
          ),
          factoryData: '0xfactorydata',
          paymaster: EthereumAddress.fromHex(
            '0xbbbb567890123456789012345678901234567890',
          ),
          paymasterData: '0xpaymasterdata',
          paymasterVerificationGasLimit: BigInt.from(50000),
          paymasterPostOpGasLimit: BigInt.from(25000),
        );

        await client.sendCompressedUserOperation(
          userOp,
          EthereumAddress.fromHex('0xabcdef1234567890abcdef1234567890abcdef12'),
          '0xcompressed',
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        final packedUserOp = params[0] as Map<String, dynamic>;

        expect(packedUserOp['factory'], equals(userOp.factory!.hex));
        expect(packedUserOp['factoryData'], equals('0xfactorydata'));
        expect(packedUserOp['paymaster'], equals(userOp.paymaster!.hex));
        expect(packedUserOp['paymasterData'], equals('0xpaymasterdata'));
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

    test('returns cost estimate for ERC-20 token', () async {
      final mockClient = createMockClient(
        (_) => {
          'costInToken':
              '0x5f5e100', // 100,000,000 (1 USDC with 6 decimals = $100)
          'costInUsd': '0x5f5e100', // 100,000,000 (1.00 USD with 8 decimals)
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
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
        signature: '0xsignature',
      );

      final cost = await client.estimateErc20PaymasterCost(
        userOperation: userOp,
        token: EthereumAddress.fromHex(
          '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        ), // USDC
      );

      expect(cost.costInToken, equals(BigInt.from(100000000)));
      expect(cost.costInUsd, equals(BigInt.from(100000000)));
      expect(
        capturedRequests[0]['method'],
        equals('pimlico_estimateErc20PaymasterCost'),
      );
    });

    test('includes correct parameters in request', () async {
      final mockClient = createMockClient(
        (_) => {'costInToken': '0x1', 'costInUsd': '0x1'},
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
        nonce: BigInt.from(5),
        callData: '0xabcdef123456',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
        signature: '0xsig',
      );

      final tokenAddress = EthereumAddress.fromHex(
        '0xdAC17F958D2ee523a2206206994597C13D831ec7',
      ); // USDT

      await client.estimateErc20PaymasterCost(
        userOperation: userOp,
        token: tokenAddress,
      );

      final params = capturedRequests[0]['params'] as List<dynamic>;
      final packedUserOp = params[0] as Map<String, dynamic>;

      expect(packedUserOp['sender'], equals(userOp.sender.hex));
      expect(params[1], equals(EntryPointAddresses.v07.hex));
      expect(params[2], equals(tokenAddress.hex));
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

      final policies = await client.validateSponsorshipPolicies(
        userOperation: userOp,
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
        equals('pimlico_validateSponsorshipPolicies'),
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
        signature: '0xsig',
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: userOp,
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
        signature: '0xsig',
      );

      final policies = await client.validateSponsorshipPolicies(
        userOperation: userOp,
        sponsorshipPolicyIds: [],
      );

      expect(policies, isEmpty);
      // Should not make an RPC call if no policy IDs provided
      expect(capturedRequests, isEmpty);
    });

    test('includes correct parameters in request', () async {
      final mockClient = createMockClient((_) => <dynamic>[]);
      client = createPimlicoClient(
        url: 'http://localhost:8545',
        entryPoint: EntryPointAddresses.v07,
        httpClient: mockClient,
      );

      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.from(42),
        callData: '0xabcdef',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
        signature: '0xsig',
      );

      await client.validateSponsorshipPolicies(
        userOperation: userOp,
        sponsorshipPolicyIds: ['sp_test_1', 'sp_test_2'],
      );

      final params = capturedRequests[0]['params'] as List<dynamic>;
      expect(params[1], equals(EntryPointAddresses.v07.hex));
      expect(params[2], equals(['sp_test_1', 'sp_test_2']));
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

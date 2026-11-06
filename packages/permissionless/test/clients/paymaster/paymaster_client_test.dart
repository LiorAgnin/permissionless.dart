import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('PaymasterClient', () {
    late PaymasterClient client;
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

    group('getPaymasterStubData', () {
      test('returns stub data for gas estimation', () async {
        final mockClient = createMockClient(
          (_) => {
            'paymaster': '0x1234567890123456789012345678901234567890',
            'paymasterData': '0xabcdef',
            'paymasterVerificationGasLimit': '0xc350',
            'paymasterPostOpGasLimit': '0x4e20',
            'isFinal': false,
          },
        );
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final result = await client.getPaymasterStubData(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
          chainId: BigInt.one,
        );

        expect(
          result.paymaster.hex,
          equals('0x1234567890123456789012345678901234567890'),
        );
        expect(result.paymasterData, equals('0xabcdef'));
        expect(
          result.paymasterVerificationGasLimit,
          equals(BigInt.from(50000)),
        );
        expect(result.paymasterPostOpGasLimit, equals(BigInt.from(20000)));
        expect(result.isFinal, isFalse);

        expect(
          capturedRequests[0]['method'],
          equals('pm_getPaymasterStubData'),
        );
        expect(
          capturedRequests[0]['params'][1],
          equals(EntryPointAddresses.v07.hex),
        );
        expect(capturedRequests[0]['params'][2], equals('0x1'));
        // Always 4 params; context is null when omitted
        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params.length, equals(4));
        expect(params[3], isNull);
        // Gas fields carried from the userOp (100000 = 0x186a0, 21000 = 0x5208)
        final userOpJson = params[0] as Map<String, dynamic>;
        expect(userOpJson['callGasLimit'], equals('0x186a0'));
        expect(userOpJson['verificationGasLimit'], equals('0x186a0'));
        expect(userOpJson['preVerificationGas'], equals('0x5208'));
      });

      test('sends zero gas fields as 0x0 instead of omitting them', () async {
        final mockClient = createMockClient(
          (_) => {
            'paymaster': '0x1234567890123456789012345678901234567890',
            'paymasterData': '0xabcdef',
          },
        );
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        await client.getPaymasterStubData(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
          chainId: BigInt.one,
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        final userOpJson = params[0] as Map<String, dynamic>;
        expect(userOpJson['callGasLimit'], equals('0x0'));
        expect(userOpJson['verificationGasLimit'], equals('0x0'));
        expect(userOpJson['preVerificationGas'], equals('0x0'));
      });

      test('includes context when provided', () async {
        final mockClient = createMockClient(
          (_) => {
            'paymaster': '0x1234567890123456789012345678901234567890',
            'paymasterData': '0xabcdef',
          },
        );
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        await client.getPaymasterStubData(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
          chainId: BigInt.one,
          context: const PaymasterContext(sponsorshipPolicyId: 'policy-123'),
        );

        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params.length, equals(4));
        expect(params[3]['sponsorshipPolicyId'], equals('policy-123'));
      });
    });

    group('getPaymasterData', () {
      test('returns paymaster data with signature', () async {
        final mockClient = createMockClient(
          (_) => {
            'paymaster': '0x1234567890123456789012345678901234567890',
            'paymasterData': '0xsigneddata123456',
            'paymasterVerificationGasLimit': '0xc350',
            'paymasterPostOpGasLimit': '0x4e20',
          },
        );
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(21000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final result = await client.getPaymasterData(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
          chainId: BigInt.one,
        );

        expect(
          result.paymaster.hex,
          equals('0x1234567890123456789012345678901234567890'),
        );
        expect(result.paymasterData, equals('0xsigneddata123456'));
        expect(capturedRequests[0]['method'], equals('pm_getPaymasterData'));
        final params = capturedRequests[0]['params'] as List<dynamic>;
        expect(params.length, equals(4));
        expect(params[3], isNull);
      });
    });

    group('sponsorUserOperation', () {
      test('returns combined sponsorship result', () async {
        final mockClient = createMockClient(
          (_) => {
            'paymaster': '0x1234567890123456789012345678901234567890',
            'paymasterData': '0xsponsordata',
            'paymasterVerificationGasLimit': '0xc350',
            'paymasterPostOpGasLimit': '0x4e20',
            'preVerificationGas': '0x5208',
            'verificationGasLimit': '0x186a0',
            'callGasLimit': '0x186a0',
          },
        );
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: mockClient,
        );

        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final result = await client.sponsorUserOperation(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
          chainId: BigInt.one,
        );

        expect(
          result.paymaster.hex,
          equals('0x1234567890123456789012345678901234567890'),
        );
        expect(result.paymasterData, equals('0xsponsordata'));
        expect(result.preVerificationGas, equals(BigInt.from(21000)));
        expect(result.verificationGasLimit, equals(BigInt.from(100000)));
        expect(result.callGasLimit, equals(BigInt.from(100000)));
        expect(
          capturedRequests[0]['method'],
          equals('pm_sponsorUserOperation'),
        );
      });

      // permissionless.js sponsorUserOperation sends
      // [userOperation, entryPoint, sponsorshipPolicyId?]; no chain id.
      test('needs no chainId and sends [userOp, entryPoint]', () async {
        client = createPaymasterClient(
          url: 'http://localhost:3000/rpc',
          httpClient: createMockClient(
            (_) => {
              'paymaster': '0x1234567890123456789012345678901234567890',
              'paymasterData': '0x',
              'preVerificationGas': '0x5208',
              'verificationGasLimit': '0x186a0',
              'callGasLimit': '0x186a0',
            },
          ),
        );
        final userOp = UserOperationV07(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          callData: '0x',
          callGasLimit: BigInt.zero,
          verificationGasLimit: BigInt.zero,
          preVerificationGas: BigInt.zero,
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        await client.sponsorUserOperation(
          userOp: userOp,
          entryPoint: EntryPointAddresses.v07,
        );

        expect(
          capturedRequests.single['params'],
          equals([userOp.toJson(), EntryPointAddresses.v07.hex]),
        );
      });
    });
  });

  group('PaymasterUserOperationExtension', () {
    test('withPaymasterStub applies stub data', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final stub = PaymasterStubData(
        paymaster: EthereumAddress.fromHex(
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        paymasterData: '0xstubdata',
        paymasterVerificationGasLimit: BigInt.from(50000),
        paymasterPostOpGasLimit: BigInt.from(20000),
      );

      final result = userOp.withPaymasterStub(stub);

      expect(
        result.paymaster?.hex,
        equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      );
      expect(result.paymasterData, equals('0xstubdata'));
      expect(result.paymasterVerificationGasLimit, equals(BigInt.from(50000)));
      expect(result.paymasterPostOpGasLimit, equals(BigInt.from(20000)));
      // Original fields preserved
      expect(result.callGasLimit, equals(BigInt.from(100000)));
    });

    test('withPaymasterData applies final data', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(100000),
        preVerificationGas: BigInt.from(21000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final data = PaymasterData(
        paymaster: EthereumAddress.fromHex(
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        paymasterData: '0xsigneddata',
      );

      final result = userOp.withPaymasterData(data);

      expect(
        result.paymaster?.hex,
        equals('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      );
      expect(result.paymasterData, equals('0xsigneddata'));
    });

    test('withSponsorship applies full sponsorship result', () {
      final userOp = UserOperationV07(
        sender: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        nonce: BigInt.zero,
        callData: '0x',
        callGasLimit: BigInt.zero,
        verificationGasLimit: BigInt.zero,
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      final sponsorship = SponsorUserOperationResult(
        paymaster: EthereumAddress.fromHex(
          '0xcccccccccccccccccccccccccccccccccccccccc',
        ),
        paymasterData: '0xsponsordata',
        paymasterVerificationGasLimit: BigInt.from(50000),
        paymasterPostOpGasLimit: BigInt.from(20000),
        preVerificationGas: BigInt.from(21000),
        verificationGasLimit: BigInt.from(100000),
        callGasLimit: BigInt.from(150000),
      );

      final result = userOp.withSponsorship(sponsorship);

      expect(
        result.paymaster?.hex,
        equals('0xcccccccccccccccccccccccccccccccccccccccc'),
      );
      expect(result.paymasterData, equals('0xsponsordata'));
      expect(result.preVerificationGas, equals(BigInt.from(21000)));
      expect(result.verificationGasLimit, equals(BigInt.from(100000)));
      expect(result.callGasLimit, equals(BigInt.from(150000)));
    });
  });

  group('PaymasterStubData', () {
    test('isFinal defaults to false', () {
      final stub = PaymasterStubData.fromJson({
        'paymaster': '0x1234567890123456789012345678901234567890',
        'paymasterData': '0xabcdef',
      });

      expect(stub.isFinal, isFalse);
    });
  });

  group('PaymasterContext', () {
    test('toJson includes sponsorshipPolicyId', () {
      const context = PaymasterContext(sponsorshipPolicyId: 'policy-abc');
      final json = context.toJson();

      expect(json['sponsorshipPolicyId'], equals('policy-abc'));
    });

    test('toJson includes extra fields', () {
      const context = PaymasterContext(
        extra: {'customField': 'value', 'anotherField': 123},
      );
      final json = context.toJson();

      expect(json['customField'], equals('value'));
      expect(json['anotherField'], equals(123));
    });

    test('toJson combines all fields', () {
      const context = PaymasterContext(
        sponsorshipPolicyId: 'policy-xyz',
        extra: {'metadata': 'test'},
      );
      final json = context.toJson();

      expect(json['sponsorshipPolicyId'], equals('policy-xyz'));
      expect(json['metadata'], equals('test'));
    });
  });
}

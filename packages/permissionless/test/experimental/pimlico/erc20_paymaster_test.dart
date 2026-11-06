import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('prepareUserOperationForErc20Paymaster', () {
    const testPrivateKey =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

    final token = EthereumAddress.fromHex(
      '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
    );
    final recipient = EthereumAddress.fromHex(
      '0x1234567890123456789012345678901234567890',
    );

    late List<Map<String, dynamic>> bundlerRequests;
    late List<Map<String, dynamic>> paymasterRequests;
    late List<Map<String, dynamic>> pimlicoRequests;

    setUp(() {
      bundlerRequests = [];
      paymasterRequests = [];
      pimlicoRequests = [];
    });

    MockClient createBundlerMock() => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bundlerRequests.add(body);
          final method = body['method'] as String;
          final result = switch (method) {
            'eth_estimateUserOperationGas' => {
                'preVerificationGas': '0x5208',
                'verificationGasLimit': '0x186a0',
                'callGasLimit': '0x186a0',
              },
            _ => null,
          };
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
            200,
          );
        });

    MockClient createPaymasterMock() => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          paymasterRequests.add(body);
          final method = body['method'] as String;
          final result = switch (method) {
            'pm_getPaymasterStubData' => {
                'paymaster': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'paymasterData': '0xabcdef0123456789',
                'paymasterVerificationGasLimit': '0xc350',
                'paymasterPostOpGasLimit': '0x4e20',
                'isFinal': false,
              },
            'pm_getPaymasterData' => {
                'paymaster': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'paymasterData': '0xfedcba9876543210',
                'paymasterVerificationGasLimit': '0xc350',
                'paymasterPostOpGasLimit': '0x4e20',
              },
            _ => null,
          };
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
            200,
          );
        });

    // Pimlico mock: chain id + a single USDC-like token quote.
    MockClient createPimlicoMock() => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          pimlicoRequests.add(body);
          final method = body['method'] as String;
          final result = switch (method) {
            'eth_chainId' => '0xaa36a7',
            'pimlico_getTokenQuotes' => {
                'quotes': [
                  {
                    'token': token.hex,
                    'paymaster': '0x888888888888Ec68A58AB8094Cc1AD20Ba3D2402',
                    'postOpGas': '0x124f8',
                    // 1e18: 1 token wei per 1 wei of gas (keeps math simple)
                    'exchangeRate': '0xde0b6b3a7640000',
                  },
                ],
              },
            _ => null,
          };
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
            200,
          );
        });

    // Public client mock:
    // - eth_getCode → '0x' unless [isDeployed] (7702: not yet delegated)
    // - eth_getTransactionCount → '0x0' (EOA nonce for the authorization)
    // - eth_call → 0 (serves both EntryPoint.getNonce and ERC-20 allowance)
    PublicClient createPublicClientMock({bool isDeployed = false}) {
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String;
        final result = switch (method) {
          'eth_getCode' => isDeployed ? '0x6080604052' : '0x',
          'eth_getTransactionCount' => '0x0',
          'eth_call' =>
            '0x0000000000000000000000000000000000000000000000000000000000000000',
          _ => null,
        };
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          200,
        );
      });
      return PublicClient(
        rpcClient: JsonRpcClient(
          url: Uri.parse('http://localhost:8545'),
          httpClient: mock,
        ),
      );
    }

    PimlicoClient createPimlico() => createPimlicoClient(
          url: 'http://localhost:3002/rpc',
          entryPoint: EntryPointAddresses.v08,
          httpClient: createPimlicoMock(),
        );

    final call = Call(to: recipient, value: BigInt.zero);

    test(
        'undeployed ERC-7579 Safe: final call data keeps the setupSafe '
        'deployment wrapper', () async {
      final publicClient = createPublicClientMock();
      final account = createSafeSmartAccount(
        owners: [PrivateKeyOwner(testPrivateKey)],
        chainId: BigInt.from(11155111),
        address: recipient,
        erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        ),
        paymaster: createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        ),
        publicClient: publicClient,
      );

      final result = await prepareUserOperationForErc20Paymaster(
        smartAccountClient: client,
        pimlicoClient: createPimlico(),
        publicClient: publicClient,
        token: token,
        calls: [call],
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      expect(result.userOperation.factory, isNotNull);
      expect(
        result.userOperation.callData,
        account.encodeCallsForDeployment([
          encodeErc20Approve(
            token: token,
            spender: result.tokenQuote.paymaster,
            amount: result.maxCostInToken,
          ),
          call,
        ]),
      );
    });

    test(
      'EIP-7702 first op: returns authorization, forwards eip7702Auth '
      'to every paymaster request incl. the final pm_getPaymasterData',
      () async {
        final publicClient = createPublicClientMock();
        final account = createEip7702SimpleSmartAccount(
          owner: PrivateKeyEip7702Owner(testPrivateKey),
          chainId: BigInt.from(11155111),
          publicClient: publicClient,
        );
        final client = SmartAccountClient(
          account: account,
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v08,
            httpClient: createBundlerMock(),
          ),
          paymaster: createPaymasterClient(
            url: 'http://localhost:3001/rpc',
            httpClient: createPaymasterMock(),
          ),
          publicClient: publicClient,
        );

        final result = await prepareUserOperationForErc20Paymaster(
          smartAccountClient: client,
          pimlicoClient: createPimlico(),
          publicClient: publicClient,
          token: token,
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        // The authorization must be surfaced to the caller for submission.
        expect(result.needsAuthorization, isTrue);
        expect(result.authorization, isNotNull);

        // First 7702 op carries the EIP-7702 factory marker.
        expect(isEip7702FactoryMarker(result.userOperation.factory), isTrue);

        // Zero allowance → approval must be injected.
        expect(result.approvalInjected, isTrue);

        // Paid-RPC economy (permissionless.js parity): exactly one stub call
        // during prepare and exactly ONE real pm_getPaymasterData — the final
        // one over the final calldata (step 9). The prepare-time data call is
        // skipped via skipFinalPaymasterData.
        final dataRequests = paymasterRequests
            .where((r) => r['method'] == 'pm_getPaymasterData')
            .toList();
        expect(dataRequests.length, equals(1));
        expect(
          paymasterRequests
              .where((r) => r['method'] == 'pm_getPaymasterStubData')
              .length,
          equals(1),
        );

        // Every paymaster request — including the final pm_getPaymasterData
        // issued by the helper itself (step 9) — must carry eip7702Auth and
        // the short factory marker.
        for (final req in paymasterRequests) {
          final userOpJson =
              (req['params'] as List<dynamic>)[0] as Map<String, dynamic>;
          expect(
            userOpJson.containsKey('eip7702Auth'),
            isTrue,
            reason: '${req['method']} must forward eip7702Auth',
          );
          expect(userOpJson['factory'], equals('0x7702'));
        }

        // The final pm_getPaymasterData must carry the FULL prepared op —
        // stub paymaster fields and paymaster gas limits included. Pimlico's
        // ERC-20 mode rejects the request without the limits
        // ("paymasterValidationGasLimit is required for erc20 mode").
        final dataOpJson = (dataRequests.single['params'] as List<dynamic>)[0]
            as Map<String, dynamic>;
        expect(dataOpJson['paymasterVerificationGasLimit'], isNotNull);
        expect(dataOpJson['paymasterPostOpGasLimit'], isNotNull);
        expect(dataOpJson['paymaster'], isNotNull);
      },
    );

    test(
      'non-7702 (Safe, deployed): no authorization, no eip7702Auth on wire',
      () async {
        final publicClient = createPublicClientMock(isDeployed: true);
        final account = createSafeSmartAccount(
          owners: [PrivateKeyOwner(testPrivateKey)],
          chainId: BigInt.from(11155111),
          address: recipient,
        );
        final client = SmartAccountClient(
          account: account,
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v07,
            httpClient: createBundlerMock(),
          ),
          paymaster: createPaymasterClient(
            url: 'http://localhost:3001/rpc',
            httpClient: createPaymasterMock(),
          ),
          publicClient: publicClient,
        );

        final result = await prepareUserOperationForErc20Paymaster(
          smartAccountClient: client,
          pimlicoClient: createPimlico(),
          publicClient: publicClient,
          token: token,
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(result.needsAuthorization, isFalse);
        expect(result.authorization, isNull);

        // Non-7702 flow: no eip7702Auth anywhere.
        for (final req in paymasterRequests) {
          final userOpJson =
              (req['params'] as List<dynamic>)[0] as Map<String, dynamic>;
          expect(
            userOpJson.containsKey('eip7702Auth'),
            isFalse,
            reason: '${req['method']} must not carry eip7702Auth for non-7702',
          );
        }

        // Paymaster data applied to the final op.
        expect(result.userOperation.paymaster, isNotNull);
        expect(result.userOperation.paymasterData, isNotNull);

        // Exactly one paid pm_getPaymasterData for the whole flow (step 9).
        expect(
          paymasterRequests
              .where((r) => r['method'] == 'pm_getPaymasterData')
              .length,
          equals(1),
        );
      },
    );

    test('throws ArgumentError when token is not supported', () async {
      final publicClient = createPublicClientMock(isDeployed: true);
      final account = createSafeSmartAccount(
        owners: [PrivateKeyOwner(testPrivateKey)],
        chainId: BigInt.from(11155111),
        address: recipient,
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        ),
        paymaster: createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        ),
        publicClient: publicClient,
      );

      // Pimlico mock returning an empty quotes list.
      final emptyQuotesPimlico = createPimlicoClient(
        url: 'http://localhost:3002/rpc',
        entryPoint: EntryPointAddresses.v07,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final method = body['method'] as String;
          final result = switch (method) {
            'eth_chainId' => '0xaa36a7',
            'pimlico_getTokenQuotes' => {'quotes': <dynamic>[]},
            _ => null,
          };
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
            200,
          );
        }),
      );

      await expectLater(
        prepareUserOperationForErc20Paymaster(
          smartAccountClient: client,
          pimlicoClient: emptyQuotesPimlico,
          publicClient: publicClient,
          token: token,
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
        throwsArgumentError,
      );
    });
  });
}

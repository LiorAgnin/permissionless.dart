import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('SmartAccountClient', () {
    const testPrivateKey =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

    // Mock address for unit tests (avoids RPC calls)
    final mockAddress =
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

    late SafeSmartAccount account;
    late List<Map<String, dynamic>> bundlerRequests;
    late List<Map<String, dynamic>> paymasterRequests;

    setUp(() {
      account = createSafeSmartAccount(
        owners: [PrivateKeyOwner(testPrivateKey)],
        chainId: BigInt.from(1),
        address: mockAddress,
      );
      bundlerRequests = [];
      paymasterRequests = [];
    });

    MockClient createBundlerMock({
      Map<String, dynamic> Function(Map<String, dynamic>)? responseFactory,
    }) =>
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bundlerRequests.add(body);

          final method = body['method'] as String;
          dynamic result;

          if (responseFactory != null) {
            result = responseFactory(body);
          } else {
            result = switch (method) {
              'eth_estimateUserOperationGas' => {
                  'preVerificationGas': '0x5208',
                  'verificationGasLimit': '0x186a0',
                  'callGasLimit': '0x186a0',
                },
              'eth_sendUserOperation' => '0xabcdef1234567890',
              'eth_getUserOperationReceipt' => {
                  'userOpHash': '0xabcdef1234567890',
                  'sender': '0x1234567890123456789012345678901234567890',
                  'nonce': '0x0',
                  'success': true,
                  'actualGasCost': '0x1234',
                  'actualGasUsed': '0x5678',
                  'logs': <dynamic>[],
                  'receipt': {
                    'transactionHash': '0x${'cd' * 32}',
                    'blockHash': '0x${'ef' * 32}',
                    'blockNumber': '0x1',
                    'from': '0x1234567890123456789012345678901234567890',
                    'cumulativeGasUsed': '0x5678',
                    'gasUsed': '0x5678',
                    'status': '0x1',
                    'logs': <dynamic>[],
                  },
                },
              _ => null,
            };
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

    MockClient createPaymasterMock({
      Map<String, dynamic>? Function(Map<String, dynamic>)? responseFactory,
    }) =>
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          paymasterRequests.add(body);

          final method = body['method'] as String;
          dynamic result;

          if (responseFactory != null) {
            final customResult = responseFactory(body);
            if (customResult != null) {
              result = customResult;
            }
          }

          result ??= switch (method) {
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
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': result,
            }),
            200,
          );
        });

    /// Creates a mock PublicClient for testing.
    /// By default returns empty code (not deployed account).
    PublicClient createPublicClientMock({
      bool isDeployed = false,
      BigInt? gasPrice,
      BigInt? maxPriorityFeePerGas,
    }) {
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String;

        dynamic result;
        if (method == 'eth_getCode') {
          // Return code if deployed, empty otherwise
          result = isDeployed ? '0x6080604052' : '0x';
        } else if (method == 'eth_call') {
          // Return nonce for getAccountNonce
          result =
              '0x0000000000000000000000000000000000000000000000000000000000000000';
        } else if (method == 'eth_gasPrice') {
          result =
              '0x${(gasPrice ?? BigInt.from(1000000000)).toRadixString(16)}';
        } else if (method == 'eth_maxPriorityFeePerGas') {
          result =
              '0x${(maxPriorityFeePerGas ?? BigInt.from(100000000)).toRadixString(16)}';
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

      return PublicClient(
        rpcClient: JsonRpcClient(
          url: Uri.parse('http://localhost:8545'),
          httpClient: mock,
        ),
      );
    }

    group('getAddress', () {
      test('returns account address', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        final address = await client.getAddress();

        expect(address, equals(mockAddress));
      });
    });

    group('prepareUserOperation', () {
      test('builds userOp with gas estimates', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.from(1000000000000000000),
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        // Check gas estimates were applied (with default 1.1x multipliers)
        expect(userOp.preVerificationGas, equals(BigInt.from(21000)));
        expect(userOp.verificationGasLimit, equals(BigInt.from(110000)));
        expect(userOp.callGasLimit, equals(BigInt.from(110000)));

        // Undeployed Safe 1.4.1: SafeProxyFactory.createProxyWithNonce
        // (permissionless.js safe constants; `cast sig
        // "createProxyWithNonce(address,bytes,uint256)"` = 0x1688f0b9).
        expect(
          userOp.factory,
          equals(
            EthereumAddress.fromHex(
              '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
            ),
          ),
        );
        expect(userOp.factoryData, startsWith('0x1688f0b9'));

        // The estimate went to the bundler for this sender and EntryPoint.
        final estimate = bundlerRequests.singleWhere(
          (r) => r['method'] == 'eth_estimateUserOperationGas',
        );
        final params = estimate['params'] as List<dynamic>;
        expect(
          (params[0] as Map<String, dynamic>)['sender'],
          equals(mockAddress.hex),
        );
        expect(params[1], equals(EntryPointAddresses.v07.hex));
      });

      test('applies paymaster stub and final data when paymaster provided',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        // Check paymaster data was applied
        expect(
          userOp.paymaster?.hex,
          equals('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        );
        expect(userOp.paymasterData, equals('0xfedcba9876543210'));

        // Check both paymaster calls were made (stub + final)
        expect(paymasterRequests.length, equals(2));
        expect(
          paymasterRequests[0]['method'],
          equals('pm_getPaymasterStubData'),
        );
        expect(paymasterRequests[1]['method'], equals('pm_getPaymasterData'));
      });

      test('skips final paymaster call when isFinal is true', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(
            responseFactory: (body) {
              final method = body['method'] as String;
              if (method == 'pm_getPaymasterStubData') {
                return {
                  'paymaster': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'paymasterData': '0x1234567890abcdef',
                  'isFinal': true,
                };
              }
              return null;
            },
          ),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        // Only stub call should be made since isFinal is true
        expect(paymasterRequests.length, equals(1));
        expect(
          paymasterRequests[0]['method'],
          equals('pm_getPaymasterStubData'),
        );
        expect(userOp.paymasterData, equals('0x1234567890abcdef'));
      });

      // viem prepareUserOperation: `paymasterPostOpGasLimit:
      // request.paymasterPostOpGasLimit ?? gas.paymasterPostOpGasLimit`.
      // A final stub's gas fields are part of what the paymaster signed, so
      // they must reach the op unchanged, including a 0 postOp limit.
      test('keeps the paymaster gas limits of a final stub, including 0',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(
            responseFactory: (body) => {
              'preVerificationGas': '0x5208',
              'verificationGasLimit': '0x186a0',
              'callGasLimit': '0x186a0',
              'paymasterVerificationGasLimit': '0x9c40',
              'paymasterPostOpGasLimit': '0x4e20',
            },
          ),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(
            responseFactory: (body) => {
              'paymaster': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'paymasterData': '0x1234567890abcdef',
              'paymasterVerificationGasLimit': '0x7530',
              'paymasterPostOpGasLimit': '0x0',
              'isFinal': true,
            },
          ),
        );
        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(
          userOp.paymasterVerificationGasLimit,
          equals(BigInt.from(30000)),
        );
        expect(userOp.paymasterPostOpGasLimit, equals(BigInt.zero));
      });

      test('excludes factory data when account is deployed', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        // Mock publicClient that returns code for the account (simulating deployed)
        final publicClientMock = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final method = body['method'] as String;

          dynamic result;
          if (method == 'eth_getCode') {
            // Return non-empty code to simulate deployed account
            result = '0x6080604052';
          } else if (method == 'eth_call') {
            // Return nonce for getAccountNonce
            result =
                '0x0000000000000000000000000000000000000000000000000000000000000000';
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

        final publicClient = PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: publicClientMock,
          ),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: publicClient,
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(userOp.factory, isNull);
        expect(userOp.factoryData, isNull);
      });

      test('respects partial overrides and skips gas estimate when all set',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(isDeployed: true),
        );

        const prefilledCallData = '0xdeadbeef';
        final userOp = await client.prepareUserOperation(
          callData: prefilledCallData,
          callGasLimit: BigInt.from(50000),
          verificationGasLimit: BigInt.from(60000),
          preVerificationGas: BigInt.from(21000),
          signature: '0xcafebabe',
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(userOp.callData, equals(prefilledCallData));
        expect(userOp.callGasLimit, equals(BigInt.from(50000)));
        expect(userOp.verificationGasLimit, equals(BigInt.from(60000)));
        expect(userOp.preVerificationGas, equals(BigInt.from(21000)));
        expect(userOp.signature, equals('0xcafebabe'));
        // No eth_estimateUserOperationGas when all gas fields provided
        expect(bundlerRequests, isEmpty);
      });

      test('preserves caller gas fields while estimating missing ones',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(isDeployed: true),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
            ),
          ],
          callGasLimit: BigInt.from(99999),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        // Caller callGasLimit preserved; others estimated (1.1x of 0x186a0)
        expect(userOp.callGasLimit, equals(BigInt.from(99999)));
        expect(userOp.verificationGasLimit, equals(BigInt.from(110000)));
        expect(userOp.preVerificationGas, equals(BigInt.from(21000)));
        expect(bundlerRequests.length, equals(1));
      });

      test('uses client paymasterContext default when per-call omitted',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
          paymasterContext:
              const PaymasterContext(sponsorshipPolicyId: 'default-policy'),
        );

        await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        final stubParams = paymasterRequests[0]['params'] as List<dynamic>;
        expect(stubParams.length, equals(4));
        expect(stubParams[3]['sponsorshipPolicyId'], equals('default-policy'));
      });

      test('uses estimateFeesPerGas hook when fees not supplied', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        var hookCalled = false;
        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
          estimateFeesPerGas: () async {
            hookCalled = true;
            return FeeEstimate(
              maxFeePerGas: BigInt.from(42),
              maxPriorityFeePerGas: BigInt.from(7),
            );
          },
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
            ),
          ],
        );

        expect(hookCalled, isTrue);
        expect(userOp.maxFeePerGas, equals(BigInt.from(42)));
        expect(userOp.maxPriorityFeePerGas, equals(BigInt.from(7)));
      });

      test('falls back to 2x fee data when no hook and fees omitted', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(
            gasPrice: BigInt.from(1000),
            maxPriorityFeePerGas: BigInt.from(100),
          ),
        );

        final userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
            ),
          ],
        );

        expect(userOp.maxFeePerGas, equals(BigInt.from(2000)));
        expect(userOp.maxPriorityFeePerGas, equals(BigInt.from(200)));
      });

      test(
          'skipFinalPaymasterData: only stub is requested, '
          'stub data retained on the op', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        final prepared = await client.prepareUserOperationWithAuth(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          skipFinalPaymasterData: true,
        );

        // No paid pm_getPaymasterData: stub only.
        expect(paymasterRequests.length, equals(1));
        expect(
          paymasterRequests[0]['method'],
          equals('pm_getPaymasterStubData'),
        );

        // Stub paymaster data retained; gas still estimated.
        expect(prepared.userOp.paymasterData, equals('0xabcdef0123456789'));
        // 0x186a0 (100000) estimate x 1.1 default multiplier.
        expect(prepared.userOp.callGasLimit, equals(BigInt.from(110000)));
      });
    });

    group('EIP-7702 paymaster forwarding', () {
      // Public client mock for a not-yet-delegated 7702 EOA:
      // - eth_getCode → '0x' (not deployed → needs authorization)
      // - eth_getTransactionCount → '0x0' (EOA nonce for the authorization)
      // - eth_call → 0 (account nonce via EntryPoint.getNonce)
      PublicClient create7702PublicClientMock() {
        final mock = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final method = body['method'] as String;
          final result = switch (method) {
            'eth_getCode' => '0x',
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

      SmartAccountClient create7702Client({
        PaymasterClient? paymaster,
        EthereumAddress? bundlerEntryPoint,
      }) {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: bundlerEntryPoint ?? EntryPointAddresses.v08,
          httpClient: createBundlerMock(),
        );
        final publicClient = create7702PublicClientMock();
        final eip7702Account = createEip7702SimpleSmartAccount(
          owner: PrivateKeyEip7702Owner(testPrivateKey),
          chainId: BigInt.from(11155111),
          publicClient: publicClient,
        );
        return SmartAccountClient(
          account: eip7702Account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: publicClient,
        );
      }

      final call = Call(
        to: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
        value: BigInt.zero,
      );

      test('paymaster requests carry eip7702Auth for a first 7702 op',
          () async {
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );
        final client = create7702Client(paymaster: paymaster);

        final prepared = await client.prepareUserOperationWithAuth(
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(prepared.needsAuthorization, isTrue);

        // Both pm_getPaymasterStubData and pm_getPaymasterData must carry
        // eip7702Auth — the paymaster signs its data over the same op the
        // account signs and the bundler receives (viem parity).
        expect(paymasterRequests, hasLength(2));
        for (final req in paymasterRequests) {
          final userOpJson =
              (req['params'] as List<dynamic>)[0] as Map<String, dynamic>;
          expect(
            userOpJson.containsKey('eip7702Auth'),
            isTrue,
            reason: '${req['method']} must forward eip7702Auth',
          );
          // The EIP-7702 factory marker stays in its short wire form.
          expect(userOpJson['factory'], equals('0x7702'));
        }
      });

      // viem's bundler actions take `account.entryPoint.address`; the nonce,
      // paymaster requests and signature already use the account's
      // EntryPoint, so estimate and send must target it too.
      test('estimate and send target the account EntryPoint, not the bundler',
          () async {
        final client = create7702Client(
          bundlerEntryPoint: EntryPointAddresses.v07,
        );
        expect(client.account.entryPoint, equals(EntryPointAddresses.v08));

        await client.sendUserOperation(
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        for (final method in [
          'eth_estimateUserOperationGas',
          'eth_sendUserOperation',
        ]) {
          final request = bundlerRequests.singleWhere(
            (r) => r['method'] == method,
          );
          final params = request['params'] as List<dynamic>;
          expect(
            params[1],
            equals(EntryPointAddresses.v08.hex),
            reason: method,
          );
          expect(
            (params[0] as Map<String, dynamic>).containsKey('eip7702Auth'),
            isTrue,
            reason: method,
          );
        }
      });

      // The 0x7702 initCode marker is an EntryPoint v0.8 feature. On v0.7 the
      // EntryPoint sees non-empty initCode for an EOA that the authorization
      // already gave code to and reverts AA10 "sender already constructed";
      // permissionless.js's 7702 Kernel (v0.7) returns no factory, so the
      // authorization travels alone.
      test('a first 7702 op on EntryPoint v0.7 carries no factory marker',
          () async {
        final publicClient = create7702PublicClientMock();
        final client = SmartAccountClient(
          account: createEip7702KernelSmartAccount(
            owner: PrivateKeyEip7702KernelOwner(testPrivateKey),
            chainId: BigInt.from(11155111),
            publicClient: publicClient,
          ),
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v07,
            httpClient: createBundlerMock(),
          ),
          publicClient: publicClient,
        );

        final prepared = await client.prepareUserOperationWithAuth(
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(prepared.needsAuthorization, isTrue);
        expect(prepared.userOp.factory, isNull);
        expect(prepared.userOp.factoryData, isNull);
      });

      test('non-7702 paymaster requests carry NO eip7702Auth', () async {
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );
        final client = SmartAccountClient(
          account: account,
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v07,
            httpClient: createBundlerMock(),
          ),
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        final prepared = await client.prepareUserOperationWithAuth(
          calls: [call],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(prepared.needsAuthorization, isFalse);
        expect(paymasterRequests, isNotEmpty);
        for (final req in paymasterRequests) {
          final userOpJson =
              (req['params'] as List<dynamic>)[0] as Map<String, dynamic>;
          expect(userOpJson.containsKey('eip7702Auth'), isFalse);
        }
      });
    });

    group('signUserOperation', () {
      test('signs the userOpHash for the account chain and EntryPoint',
          () async {
        final simpleAccount = createSimpleSmartAccount(
          owner: PrivateKeyOwner(testPrivateKey),
          chainId: BigInt.from(11155111),
          address: mockAddress,
        );
        final client = SmartAccountClient(
          account: simpleAccount,
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v07,
            httpClient: createBundlerMock(),
          ),
          publicClient: createPublicClientMock(),
        );

        final signed = await client.signUserOperation(
          UserOperationV07(
            sender: mockAddress,
            nonce: BigInt.from(5),
            callData: '0xdeadbeef',
            callGasLimit: BigInt.from(100000),
            verificationGasLimit: BigInt.from(200000),
            preVerificationGas: BigInt.from(50000),
            maxFeePerGas: BigInt.from(3000000000),
            maxPriorityFeePerGas: BigInt.from(1000000000),
          ),
        );

        // viem 2.21.55 getUserOperationHash({ userOperation: <the op above>,
        //   entryPointAddress: v0.7, entryPointVersion: '0.7',
        //   chainId: 11155111 })
        //   = 0xda7036ab884cec44635d3ab30e58eba02b40c8e3d69f17daf61ed3a4143fb0a8
        // cast wallet sign --private-key <testPrivateKey> <that hash>
        //   (EIP-191 over the raw 32 bytes, as SimpleAccount verifies)
        expect(
          signed.signature,
          equals(
            '0x8b98265ff94361c314b28eb0fb7d707281b774dbbe30478759184187e76aa7aa'
            '52bb91bd3dd1518b83594a967ebcb16f5f1ac52ba8ebee1c2773fef811c2bec5'
            '1b',
          ),
        );
      });
    });

    group('sendPreparedUserOperation', () {
      test('sends userOp and returns hash', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        var userOp = await client.prepareUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );
        userOp = await client.signUserOperation(userOp);

        final hash = await client.sendPreparedUserOperation(userOp);

        expect(hash, equals('0xabcdef1234567890'));
        expect(
          bundlerRequests.last['method'],
          equals('eth_sendUserOperation'),
        );
      });
    });

    group('sendUserOperation', () {
      test('prepares, signs, and sends in one call', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        final hash = await client.sendUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.from(1000000000000000000),
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        );

        expect(hash, equals('0xabcdef1234567890'));

        final send = bundlerRequests.singleWhere(
          (r) => r['method'] == 'eth_sendUserOperation',
        );
        final params = send['params'] as List<dynamic>;
        final sentOp = params[0] as Map<String, dynamic>;
        expect(params[1], equals(EntryPointAddresses.v07.hex));
        expect(sentOp['sender'], equals(mockAddress.hex));
        // cast calldata \
        //   "executeUserOpWithErrorString(address,uint256,bytes,uint8)" \
        //   0x1234567890123456789012345678901234567890 1000000000000000000 0x 0
        expect(
          sentOp['callData'],
          equals(
            '0x541d63c8'
            '0000000000000000000000001234567890123456789012345678901234567890'
            '0000000000000000000000000000000000000000000000000de0b6b3a7640000'
            '0000000000000000000000000000000000000000000000000000000000000080'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        );
        // Estimated gas (0x186a0 x 1.1 = 110000 = 0x1adb0) reached the send.
        expect(sentOp['callGasLimit'], equals('0x1adb0'));
        expect(sentOp['verificationGasLimit'], equals('0x1adb0'));
      });

      test('includes paymaster context when provided', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final paymaster = createPaymasterClient(
          url: 'http://localhost:3001/rpc',
          httpClient: createPaymasterMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          paymaster: paymaster,
          publicClient: createPublicClientMock(),
        );

        await client.sendUserOperation(
          calls: [
            Call(
              to: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
              value: BigInt.zero,
            ),
          ],
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          paymasterContext:
              const PaymasterContext(sponsorshipPolicyId: 'policy-123'),
        );

        // Check context was passed to paymaster
        final stubParams = paymasterRequests[0]['params'] as List<dynamic>;
        expect(stubParams.length, equals(4));
        expect(stubParams[3]['sponsorshipPolicyId'], equals('policy-123'));
      });
    });

    group('sendUserOperationAndWait', () {
      test('forwards gas limits, signature and factory to the send', () async {
        final client = SmartAccountClient(
          account: account,
          bundler: createBundlerClient(
            url: 'http://localhost:3000/rpc',
            entryPoint: EntryPointAddresses.v07,
            httpClient: createBundlerMock(),
          ),
          publicClient: createPublicClientMock(),
        );
        final factory = EthereumAddress.fromHex(
          '0x3333333333333333333333333333333333333333',
        );

        final receipt = await client.sendUserOperationAndWait(
          callData: '0xdeadbeef',
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          callGasLimit: BigInt.from(0x1111),
          verificationGasLimit: BigInt.from(0x2222),
          preVerificationGas: BigInt.from(0x3333),
          signature: '0xabcd',
          factory: factory,
          factoryData: '0xf00d',
          pollingInterval: Duration.zero,
        );

        expect(receipt.success, isTrue);
        expect(
          bundlerRequests.map((r) => r['method']),
          isNot(contains('eth_estimateUserOperationGas')),
        );
        final sentOp = (bundlerRequests.singleWhere(
          (r) => r['method'] == 'eth_sendUserOperation',
        )['params'] as List<dynamic>)[0] as Map<String, dynamic>;
        expect(sentOp['callGasLimit'], equals('0x1111'));
        expect(sentOp['verificationGasLimit'], equals('0x2222'));
        expect(sentOp['preVerificationGas'], equals('0x3333'));
        expect(sentOp['signature'], equals('0xabcd'));
        expect(sentOp['factory'], equals(factory.hex));
        expect(sentOp['factoryData'], equals('0xf00d'));
      });
    });

    group('waitForReceipt', () {
      test('returns receipt when found', () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        final receipt = await client.waitForReceipt(
          '0xabcdef1234567890',
          timeout: const Duration(seconds: 5),
        );

        expect(receipt.success, isTrue);
        expect(receipt.userOpHash, equals('0xabcdef1234567890'));
      });
    });

    group('writeContract', () {
      test('appends dataSuffix to the encoded call inside the sent callData',
          () async {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );
        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        final txHash = await client.writeContract(
          address: EthereumAddress.fromHex(
            '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
          ),
          functionSignature: 'transfer(address,uint256)',
          args: [
            EthereumAddress.fromHex(
              '0x70997970C51812dc3A010C7d01b75Ec5Bb3E7DcF',
            ),
            BigInt.from(1000000),
          ],
          dataSuffix: '0xdeadbeefcafe',
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
          timeout: const Duration(seconds: 5),
        );

        expect(txHash, equals('0x${'cd' * 32}'));
        final sentOp = (bundlerRequests.singleWhere(
          (r) => r['method'] == 'eth_sendUserOperation',
        )['params'] as List<dynamic>)[0] as Map<String, dynamic>;
        // inner = `cast calldata "transfer(address,uint256)"
        //   0x70997970C51812dc3A010C7d01b75Ec5Bb3E7DcF 1000000` ++ deadbeefcafe
        // cast calldata \
        //   "executeUserOpWithErrorString(address,uint256,bytes,uint8)" \
        //   0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 0 <inner> 0
        expect(
          sentOp['callData'],
          equals(
            '0x541d63c8'
            '0000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c7238'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '0000000000000000000000000000000000000000000000000000000000000080'
            '0000000000000000000000000000000000000000000000000000000000000000'
            '000000000000000000000000000000000000000000000000000000000000004a'
            'a9059cbb'
            '00000000000000000000000070997970c51812dc3a010c7d01b75ec5bb3e7dcf'
            '00000000000000000000000000000000000000000000000000000000000f4240'
            'deadbeefcafe'
            '00000000000000000000000000000000000000000000',
          ),
        );
      });
    });
  });

  group('signUserOperationV06', () {
    test('signs with a Kernel v0.2.x account', () async {
      final unusedRpc = MockClient(
        (request) async => throw StateError('no RPC expected'),
      );
      final account = createKernelSmartAccount(
        owner: PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        ),
        chainId: BigInt.from(1),
        version: KernelVersion.v0_2_4,
        address: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v06,
          httpClient: unusedRpc,
        ),
        publicClient: PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: unusedRpc,
          ),
        ),
      );
      final signed = await client.signUserOperationV06(
        UserOperationV06(
          sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890',
          ),
          nonce: BigInt.zero,
          initCode: '0x',
          callData: '0xdeadbeef',
          callGasLimit: BigInt.from(100000),
          verificationGasLimit: BigInt.from(100000),
          preVerificationGas: BigInt.from(50000),
          maxFeePerGas: BigInt.from(1000000000),
          maxPriorityFeePerGas: BigInt.from(1000000000),
        ),
      );

      // viem 2.21.55 getUserOperationHash({ userOperation: <the op above,
      //   paymasterAndData 0x>, entryPointAddress: v0.6,
      //   entryPointVersion: '0.6', chainId: 1 })
      //   = 0x7cdf1cf2c5ed808db37c34a7a47a8cedfa353613961f581b1f546c618574ccc2
      // Kernel v2 ROOT mode prefix 0x00000000 (permissionless.js
      // toKernelSmartAccount 0.2.x) ++
      // cast wallet sign --private-key <key> <that hash>
      expect(
        signed.signature,
        equals(
          '0x00000000'
          'e6a78f9d12048e904f6880eeaea8fae2bfee7217a12a6a0f7e3b0a2cb2b15c04'
          '2cc08d258e89d6255dcdffc2e92720cb9813928c26b8d0413a046175e3a20ed4'
          '1b',
        ),
      );
    });
  });

  group('prepareUserOperationV06', () {
    test('reads the nonce from the v0.6 EntryPoint when none is given',
        () async {
      final ethCalls = <Map<String, dynamic>>[];
      final publicClient = PublicClient(
        rpcClient: JsonRpcClient(
          url: Uri.parse('http://localhost:8545'),
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final result = switch (body['method'] as String) {
              'eth_getCode' => '0x6080604052',
              'eth_call' => () {
                  ethCalls.add(
                    (body['params'] as List).first as Map<String, dynamic>,
                  );
                  return '0x${'0' * 63}7';
                }(),
              'eth_gasPrice' => '0x3b9aca00',
              'eth_maxPriorityFeePerGas' => '0x5f5e100',
              _ => null,
            };
            return http.Response(
              jsonEncode(
                {'jsonrpc': '2.0', 'id': body['id'], 'result': result},
              ),
              200,
            );
          }),
        ),
      );
      final account = createSimpleSmartAccount(
        owner: PrivateKeyOwner(
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        ),
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v06,
        address: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v06,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': {
                  'preVerificationGas': '0x5208',
                  'verificationGasLimit': '0x186a0',
                  'callGasLimit': '0x186a0',
                },
              }),
              200,
            );
          }),
        ),
        publicClient: publicClient,
      );

      final userOp = await client.prepareUserOperationV06(
        calls: [
          Call(
            to: EthereumAddress.fromHex(
              '0x2222222222222222222222222222222222222222',
            ),
            value: BigInt.one,
          ),
        ],
      );

      expect(userOp.nonce, BigInt.from(7));
      expect(
        ethCalls.single['to'].toString().toLowerCase(),
        EntryPointAddresses.v06.hex,
      );
    });

    test('a deploying op uses encodeCallsForDeployment like v0.7', () async {
      MockClient rpc(Object? Function(String method) result) =>
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': result(body['method'] as String),
              }),
              200,
            );
          });
      final account = createSafeSmartAccount(
        owners: [
          PrivateKeyOwner(
            '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          ),
        ],
        chainId: BigInt.one,
        entryPointVersion: EntryPointVersion.v06,
        erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
        address: EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890',
        ),
      );
      final client = SmartAccountClient(
        account: account,
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v06,
          httpClient: rpc(
            (_) => {
              'preVerificationGas': '0x5208',
              'verificationGasLimit': '0x186a0',
              'callGasLimit': '0x186a0',
            },
          ),
        ),
        publicClient: PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: rpc(
              (method) => switch (method) {
                'eth_getCode' => '0x',
                'eth_call' => '0x${'0' * 64}',
                _ => null,
              },
            ),
          ),
        ),
      );
      final calls = [
        Call(
          to: EthereumAddress.fromHex(
            '0x2222222222222222222222222222222222222222',
          ),
          value: BigInt.one,
        ),
      ];

      final userOp = await client.prepareUserOperationV06(
        calls: calls,
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      );

      expect(userOp.initCode, isNot('0x'));
      expect(
        account.encodeCallsForDeployment(calls),
        isNot(account.encodeCalls(calls)),
      );
      expect(userOp.callData, account.encodeCallsForDeployment(calls));
    });
  });

  group('sendUserOperationV06AndWait', () {
    test('forwards a caller signature to the send', () async {
      final bundlerRequests = <Map<String, dynamic>>[];
      MockClient rpc(Object? Function(String method) result) =>
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bundlerRequests.add(body);
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': result(body['method'] as String),
              }),
              200,
            );
          });
      final sender =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final client = SmartAccountClient(
        account: createSimpleSmartAccount(
          owner: PrivateKeyOwner(
            '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
          ),
          chainId: BigInt.one,
          entryPointVersion: EntryPointVersion.v06,
          address: sender,
        ),
        bundler: createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v06,
          httpClient: rpc(
            (method) => switch (method) {
              'eth_estimateUserOperationGas' => {
                  'preVerificationGas': '0x5208',
                  'verificationGasLimit': '0x186a0',
                  'callGasLimit': '0x186a0',
                },
              'eth_sendUserOperation' => '0x${'ab' * 32}',
              'eth_getUserOperationReceipt' => {
                  'userOpHash': '0x${'ab' * 32}',
                  'sender': sender.hex,
                  'nonce': '0x0',
                  'success': true,
                  'actualGasCost': '0x1',
                  'actualGasUsed': '0x1',
                  'logs': <dynamic>[],
                  'receipt': {
                    'transactionHash': '0x${'cd' * 32}',
                    'blockHash': '0x${'ef' * 32}',
                    'blockNumber': '0x1',
                    'from': sender.hex,
                    'cumulativeGasUsed': '0x1',
                    'gasUsed': '0x1',
                    'status': '0x1',
                    'logs': <dynamic>[],
                  },
                },
              _ => null,
            },
          ),
        ),
        publicClient: PublicClient(
          rpcClient: JsonRpcClient(
            url: Uri.parse('http://localhost:8545'),
            httpClient: MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final result = switch (body['method'] as String) {
                'eth_getCode' => '0x6080604052',
                'eth_call' => '0x${'0' * 64}',
                _ => null,
              };
              return http.Response(
                jsonEncode(
                  {'jsonrpc': '2.0', 'id': body['id'], 'result': result},
                ),
                200,
              );
            }),
          ),
        ),
      );

      await client.sendUserOperationV06AndWait(
        callData: '0xdeadbeef',
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
        signature: '0xabcd',
        pollingInterval: Duration.zero,
      );

      final sentOp = (bundlerRequests.singleWhere(
        (r) => r['method'] == 'eth_sendUserOperation',
      )['params'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(sentOp['signature'], equals('0xabcd'));
    });
  });
}

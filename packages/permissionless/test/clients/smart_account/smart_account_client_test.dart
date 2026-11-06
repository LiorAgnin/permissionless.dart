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
        final accountAddress = await account.getAddress();

        expect(address.hex, equals(accountAddress.hex));
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

        // Check factory data included
        expect(userOp.factory, isNotNull);
        expect(userOp.factoryData, isNotNull);

        // Check bundler was called
        expect(bundlerRequests.length, equals(1));
        expect(
          bundlerRequests[0]['method'],
          equals('eth_estimateUserOperationGas'),
        );
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
        expect(prepared.userOp.callGasLimit, greaterThan(BigInt.zero));
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

      SmartAccountClient create7702Client({PaymasterClient? paymaster}) {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v08,
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
      test('signs userOp and returns with signature', () async {
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

        final preparedUserOp = await client.prepareUserOperation(
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

        final signedUserOp = await client.signUserOperation(preparedUserOp);

        // Signature should be different from stub
        expect(signedUserOp.signature, isNot(equals(preparedUserOp.signature)));
        expect(signedUserOp.signature.length, greaterThan(10));
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

        // Should have called estimate and send
        expect(bundlerRequests.length, equals(2));
        expect(
          bundlerRequests[0]['method'],
          equals('eth_estimateUserOperationGas'),
        );
        expect(bundlerRequests[1]['method'], equals('eth_sendUserOperation'));
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

    group('createSmartAccountClient', () {
      test('creates client with factory function', () {
        final bundler = createBundlerClient(
          url: 'http://localhost:3000/rpc',
          entryPoint: EntryPointAddresses.v07,
          httpClient: createBundlerMock(),
        );

        final client = createSmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: createPublicClientMock(),
        );

        expect(client, isA<SmartAccountClient>());
        expect(client.account, equals(account));
        expect(client.bundler, equals(bundler));
        expect(client.paymaster, isNull);
      });
    });
  });

  group('SmartAccount interface', () {
    test('SafeSmartAccount implements SmartAccount', () {
      const testPrivateKey =
          '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
      final mockAddress =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');

      final account = createSafeSmartAccount(
        owners: [PrivateKeyOwner(testPrivateKey)],
        chainId: BigInt.from(1),
        address: mockAddress,
      );

      // Verify it implements the interface
      expect(account, isA<SmartAccount>());
      expect(account.chainId, equals(BigInt.from(1)));
      expect(account.entryPoint.hex, equals(EntryPointAddresses.v07.hex));
      expect(account.nonceKey, equals(BigInt.zero));
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
  });
}

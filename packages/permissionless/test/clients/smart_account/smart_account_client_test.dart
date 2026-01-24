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
    PublicClient createPublicClientMock({bool isDeployed = false}) {
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

        expect(receipt, isNotNull);
        expect(receipt!.success, isTrue);
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
}

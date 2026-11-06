import 'dart:async';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

/// A fake [JsonRpcClient] that routes calls to configurable handlers.
///
/// Used to test RPC-dependent logic without hitting a real network.
class FakeRpcClient extends JsonRpcClient {
  FakeRpcClient(this.handlers) : super(url: Uri.parse('http://localhost:8545'));
  final Map<String, dynamic Function(List<dynamic>)> handlers;
  int callCount = 0;

  @override
  Future<dynamic> call(String method, [List<dynamic>? params]) async {
    callCount++;
    final handler = handlers[method];
    if (handler != null) {
      return handler(params ?? []);
    }
    throw Exception('Unexpected RPC call: $method');
  }
}

void main() {
  group('RIP-7212 P256 Precompile Support', () {
    group('isRip7212Supported (dynamic detection)', () {
      setUp(clearRip7212Cache);

      test('returns true when precompile returns 0x01', () async {
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) => '0xa', // chain 10
          'eth_call': (_) =>
              '0x${List.filled(63, '0').join()}1', // uint256(1) padded
        });
        final client = PublicClient(rpcClient: fakeRpc);

        final result = await isRip7212Supported(client);

        expect(result, isTrue);
      });

      test('returns false when precompile call reverts', () async {
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) => '0xa',
          'eth_call': (_) => throw Exception('execution reverted'),
        });
        final client = PublicClient(rpcClient: fakeRpc);

        final result = await isRip7212Supported(client);

        expect(result, isFalse);
      });

      test('returns false when precompile returns 0x00', () async {
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) => '0xa',
          'eth_call': (_) =>
              '0x${List.filled(64, '0').join()}', // uint256(0) padded
        });
        final client = PublicClient(rpcClient: fakeRpc);

        final result = await isRip7212Supported(client);

        expect(result, isFalse);
      });

      test('caches result per chain ID', () async {
        var ethCallCount = 0;
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) => '0xa',
          'eth_call': (_) {
            ethCallCount++;
            return '0x${List.filled(63, '0').join()}1';
          },
        });
        final client = PublicClient(rpcClient: fakeRpc);

        await isRip7212Supported(client);
        expect(ethCallCount, equals(1));

        await isRip7212Supported(client);
        expect(ethCallCount, equals(1));
      });

      test('clearRip7212Cache resets cache', () async {
        var ethCallCount = 0;
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) => '0xa',
          'eth_call': (_) {
            ethCallCount++;
            return '0x${List.filled(63, '0').join()}1';
          },
        });
        final client = PublicClient(rpcClient: fakeRpc);

        await isRip7212Supported(client);
        expect(ethCallCount, equals(1));

        clearRip7212Cache();

        await isRip7212Supported(client);
        expect(ethCallCount, equals(2));
      });

      // A failed probe says nothing about the chain, so it must not pin
      // `false` for the rest of the process.
      for (final (name, failure) in [
        ('timeout', TimeoutException('eth_call timed out')),
        (
          'HTTP 503',
          const BundlerHttpError(statusCode: 503, reasonPhrase: 'Unavailable'),
        ),
        ('JSON-RPC error', const BundlerRpcError(code: -32005, message: 'x')),
      ]) {
        test('does not cache a failed probe ($name)', () async {
          var ethCallCount = 0;
          final fakeRpc = FakeRpcClient({
            'eth_chainId': (_) => '0xa',
            'eth_call': (_) {
              ethCallCount++;
              if (ethCallCount == 1) throw failure;
              return '0x${List.filled(63, '0').join()}1';
            },
          });
          final client = PublicClient(rpcClient: fakeRpc);

          expect(await isRip7212Supported(client), isFalse);
          expect(await isRip7212Supported(client), isTrue);
          expect(ethCallCount, equals(2));
          expect(await isRip7212Supported(client), isTrue);
          expect(ethCallCount, equals(2));
        });
      }

      test('asks the client for its chain ID once', () async {
        var chainIdCalls = 0;
        final fakeRpc = FakeRpcClient({
          'eth_chainId': (_) {
            chainIdCalls++;
            return '0xa';
          },
          'eth_call': (_) => '0x${List.filled(63, '0').join()}1',
        });
        final client = PublicClient(rpcClient: fakeRpc);

        await isRip7212Supported(client);
        await isRip7212Supported(client);

        expect(chainIdCalls, equals(1));
      });
    });
  });
}

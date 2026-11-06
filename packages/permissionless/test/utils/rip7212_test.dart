import 'dart:async';

import 'package:permissionless/src/clients/bundler/rpc_client.dart';
import 'package:permissionless/src/clients/bundler/types.dart';
import 'package:permissionless/src/clients/public/public_client.dart';
import 'package:permissionless/src/clients/public/rip7212.dart';
import 'package:permissionless/src/utils/rip7212.dart';
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
    group('supportsRip7212', () {
      test('returns true for Sepolia', () {
        expect(supportsRip7212(chainId: BigInt.from(11155111)), isTrue);
      });

      test('returns true for Optimism', () {
        expect(supportsRip7212(chainId: BigInt.from(10)), isTrue);
      });

      test('returns true for Base', () {
        expect(supportsRip7212(chainId: BigInt.from(8453)), isTrue);
      });

      test('returns true for Polygon', () {
        expect(supportsRip7212(chainId: BigInt.from(137)), isTrue);
      });

      test('returns true for Arbitrum One', () {
        expect(supportsRip7212(chainId: BigInt.from(42161)), isTrue);
      });

      test('returns true for zkSync Era', () {
        expect(supportsRip7212(chainId: BigInt.from(324)), isTrue);
      });

      test('returns false for unsupported chain', () {
        // Some random chain ID that doesn't support RIP-7212
        expect(supportsRip7212(chainId: BigInt.from(999)), isFalse);
      });

      test('returns true for Ethereum Mainnet (Fusaka)', () {
        // Ethereum mainnet supports RIP-7212 since Fusaka upgrade (Jan 2026)
        expect(supportsRip7212(chainId: BigInt.from(1)), isTrue);
      });
    });

    group('shouldUseP256Precompile', () {
      test('returns same as supportsRip7212', () {
        final testChainIds = [
          BigInt.from(10), // Optimism - supported
          BigInt.from(1), // Mainnet - supported (Fusaka)
          BigInt.from(11155111), // Sepolia - supported
        ];

        for (final chainId in testChainIds) {
          expect(
            shouldUseP256Precompile(chainId: chainId),
            equals(supportsRip7212(chainId: chainId)),
          );
        }
      });
    });

    group('rip7212SupportedChainIds', () {
      test('contains expected L2 chains', () {
        final expectedChains = [
          10, // Optimism
          8453, // Base
          42161, // Arbitrum One
          137, // Polygon
          534352, // Scroll
          59144, // Linea
          7777777, // Zora
        ];

        for (final chainId in expectedChains) {
          expect(
            rip7212SupportedChainIds.contains(chainId),
            isTrue,
            reason: 'Chain $chainId should be supported',
          );
        }
      });

      test('contains newly added ZeroDev-listed mainnet chains', () {
        final newMainnetChains = [
          56, // BNB Smart Chain
          130, // Unichain
          143, // Monad
          204, // opBNB
          360, // Shape
          747, // Flow
          1514, // Story
          2741, // Abstract
          5000, // Mantle
          7000, // ZetaChain
          43114, // Avalanche
          57073, // Ink
          60808, // BOB
          33139, // Apechain
          43111, // Hemi Network
          98866, // Plume
          666666666, // Degen
        ];

        for (final chainId in newMainnetChains) {
          expect(
            rip7212SupportedChainIds.contains(chainId),
            isTrue,
            reason: 'Chain $chainId should be supported',
          );
        }
      });

      test('contains expected testnets', () {
        final expectedTestnets = [
          11155111, // Sepolia
          11155420, // Optimism Sepolia
          84532, // Base Sepolia
          421614, // Arbitrum Sepolia,
          97, // BNB Testnet
          919, // Mode Sepolia
          1301, // Unichain Sepolia
          1315, // Story Aeneid
          5003, // Mantle Sepolia
          10143, // Monad Testnet
          17000, // Holesky
          43113, // Avalanche Fuji
          743111, // Hemi Sepolia
          763373, // Ink Sepolia
        ];

        for (final chainId in expectedTestnets) {
          expect(
            rip7212SupportedChainIds.contains(chainId),
            isTrue,
            reason: 'Testnet $chainId should be supported',
          );
        }
      });
    });

    test('p256PrecompileAddress is correct', () {
      expect(
        p256PrecompileAddress,
        equals('0x0000000000000000000000000000000000000100'),
      );
    });

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

        // First call: should hit the RPC
        await isRip7212Supported(client);
        expect(ethCallCount, equals(1));

        // Second call: should use the cache
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

        // First call: populates cache
        await isRip7212Supported(client);
        expect(ethCallCount, equals(1));

        // Clear the cache
        clearRip7212Cache();

        // Third call: should hit the RPC again after cache cleared
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

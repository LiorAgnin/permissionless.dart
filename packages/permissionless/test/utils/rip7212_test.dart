import 'package:permissionless/src/utils/rip7212.dart';
import 'package:test/test.dart';

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

      test('returns false for Ethereum Mainnet (pending Osaka)', () {
        // Ethereum mainnet doesn't have RIP-7212 yet (pending Osaka hardfork)
        expect(supportsRip7212(chainId: BigInt.from(1)), isFalse);
      });
    });

    group('shouldUseP256Precompile', () {
      test('returns same as supportsRip7212', () {
        final testChainIds = [
          BigInt.from(10), // Optimism - supported
          BigInt.from(1), // Mainnet - not yet
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

      test('contains expected testnets', () {
        final expectedTestnets = [
          11155111, // Sepolia
          11155420, // Optimism Sepolia
          84532, // Base Sepolia
          421614, // Arbitrum Sepolia
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
  });
}

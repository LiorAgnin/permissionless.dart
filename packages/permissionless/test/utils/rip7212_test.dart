import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

void main() {
  group('RIP-7212 P256 Precompile Support', () {
    group('supportsRip7212', () {
      test('returns true for a listed chain (Optimism)', () {
        expect(supportsRip7212(chainId: BigInt.from(10)), isTrue);
      });

      test('returns false for unsupported chain', () {
        // Some random chain ID that doesn't support RIP-7212
        expect(supportsRip7212(chainId: BigInt.from(999)), isFalse);
      });
    });

    test('deprecated shouldUseP256Precompile follows the chain list', () {
      // ignore: deprecated_member_use_from_same_package
      expect(shouldUseP256Precompile(chainId: BigInt.from(10)), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(shouldUseP256Precompile(chainId: BigInt.from(999)), isFalse);
    });

    // The expected chains come from the sources cited on
    // rip7212SupportedChainIds (EIP-7951, OP Fjord, ZeroDev passkey docs).
    group('rip7212SupportedChainIds', () {
      test('contains expected mainnet and L2 chains', () {
        final expectedChains = [
          1, // Ethereum Mainnet (EIP-7951, Fusaka)
          324, // zkSync Era
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
  });
}

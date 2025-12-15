@Tags(['integration'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

void main() {
  group('PimlicoClient Integration', () {
    for (final chain in TestChain.values) {
      group(chain.name, () {
        PimlicoClient? client;

        setUp(() {
          if (!TestConfig.hasApiKeys) return;

          client = createPimlicoClient(
            url: chain.pimlicoUrl,
            entryPoint: chain.entryPointV07,
            timeout: TestTimeouts.shortNetwork,
          );
        });

        tearDown(() {
          client?.close();
        });

        test(
          'chainId returns correct chain ID',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final result = await client!.chainId();
            expect(result, equals(chain.chainIdBigInt));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'supportedEntryPoints includes v0.7',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final entryPoints = await client!.supportedEntryPoints();

            expect(entryPoints, isNotEmpty);
            expect(
              entryPoints.map((e) => e.hex.toLowerCase()),
              contains(EntryPointAddresses.v07.hex.toLowerCase()),
            );
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getUserOperationGasPrice returns valid prices',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final prices = await client!.getUserOperationGasPrice();

            // All tiers should have positive values
            expect(prices.slow.maxFeePerGas, greaterThanBigInt(BigInt.zero));
            expect(
              prices.standard.maxFeePerGas,
              greaterThanBigInt(BigInt.zero),
            );
            expect(prices.fast.maxFeePerGas, greaterThanBigInt(BigInt.zero));

            // Slow <= Standard <= Fast ordering
            expect(
              prices.standard.maxFeePerGas,
              greaterThanOrEqualToBigInt(prices.slow.maxFeePerGas),
            );
            expect(
              prices.fast.maxFeePerGas,
              greaterThanOrEqualToBigInt(prices.standard.maxFeePerGas),
            );

            // Priority fees should be positive
            expect(
              prices.slow.maxPriorityFeePerGas,
              greaterThanBigInt(BigInt.zero),
            );
            expect(
              prices.standard.maxPriorityFeePerGas,
              greaterThanBigInt(BigInt.zero),
            );
            expect(
              prices.fast.maxPriorityFeePerGas,
              greaterThanBigInt(BigInt.zero),
            );
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getUserOperationStatus returns not_found for invalid hash',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            // Use a zero hash that won't exist
            const invalidHash =
                '0x0000000000000000000000000000000000000000000000000000000000000000';

            final status = await client!.getUserOperationStatus(invalidHash);

            expect(status.status, equals('not_found'));
            expect(status.receipt, isNull);
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'gas prices are reasonable values',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final prices = await client!.getUserOperationGasPrice();

            // Gas prices should be in a reasonable range (1 gwei to 10000 gwei)
            final minGas = BigInt.from(1000000000); // 1 gwei
            final maxGas = BigInt.from(10000000000000); // 10000 gwei

            expect(prices.standard.maxFeePerGas, greaterThanBigInt(minGas));
            expect(prices.standard.maxFeePerGas, lessThan(maxGas));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );
      });
    }
  });
}

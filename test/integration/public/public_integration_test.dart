@Tags(['integration'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

void main() {
  group('PublicClient Integration', () {
    for (final chain in TestChain.values) {
      group(chain.name, () {
        late PublicClient client;

        setUp(() {
          client = createPublicClient(
            url: chain.rpcUrl,
            timeout: TestTimeouts.shortNetwork,
          );
        });

        tearDown(() {
          client.close();
        });

        test(
          'getChainId returns correct chain ID',
          () async {
            final result = await client.getChainId();
            expect(result, equals(chain.chainIdBigInt));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getBalance returns balance for zero address',
          () async {
            // Zero address should return a BigInt (possibly zero)
            final balance = await client.getBalance(
              EthereumAddress.fromHex(
                '0x0000000000000000000000000000000000000000',
              ),
            );

            expect(balance, isA<BigInt>());
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getCode returns bytecode for EntryPoint v0.7',
          () async {
            final code = await client.getCode(EntryPointAddresses.v07);

            expect(code, isNot(equals('0x')));
            expect(code, startsWith('0x'));
            expect(code.length, greaterThan(100));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'isDeployed returns true for EntryPoint v0.7',
          () async {
            final deployed = await client.isDeployed(EntryPointAddresses.v07);
            expect(deployed, isTrue);
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'isDeployed returns false for random address',
          () async {
            // Random address unlikely to have code
            final deployed = await client.isDeployed(
              EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890',
              ),
            );
            expect(deployed, isFalse);
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getCode returns code for Safe 4337 Module v0.7',
          () async {
            final addresses = SafeVersionAddresses.getAddresses(
              SafeVersion.v1_4_1,
              EntryPointVersion.v07,
            )!;

            final code = await client.getCode(addresses.safe4337ModuleAddress);

            expect(code, isNot(equals('0x')));
            expect(code.length, greaterThan(100));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getCode returns code for SimpleAccount Factory v0.7',
          () async {
            final code =
                await client.getCode(SimpleAccountFactoryAddresses.v07);

            expect(code, isNot(equals('0x')));
            expect(code.length, greaterThan(100));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getFeeData returns valid gas prices',
          () async {
            final feeData = await client.getFeeData();

            expect(feeData.gasPrice, greaterThanBigInt(BigInt.zero));
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'getGasPrice returns positive value',
          () async {
            final gasPrice = await client.getGasPrice();

            expect(gasPrice, greaterThanBigInt(BigInt.zero));

            // Should be in reasonable range (can be very low on L2s/testnets)
            // Just verify it's positive and not astronomically high
            expect(
              gasPrice,
              lessThan(BigInt.from(10000000000000)),
            ); // < 10000 gwei
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );
      });
    }
  });
}

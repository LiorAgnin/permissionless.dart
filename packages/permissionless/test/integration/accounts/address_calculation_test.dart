@Tags(['integration'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

void main() {
  group('Account Address Calculation', () {
    for (final chain in TestChain.values) {
      group('${chain.name} - SafeSmartAccount', () {
        test(
          'address is deterministic across multiple instantiations',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account1 = createSafeSmartAccount(
                owners: [owner],
                chainId: chain.chainIdBigInt,
                saltNonce: BigInt.from(12345),
                publicClient: client,
              );

              final account2 = createSafeSmartAccount(
                owners: [owner],
                chainId: chain.chainIdBigInt,
                saltNonce: BigInt.from(12345),
                publicClient: client,
              );

              final address1 = await account1.getAddress();
              final address2 = await account2.getAddress();

              expect(
                address1.hex.toLowerCase(),
                equals(address2.hex.toLowerCase()),
              );
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'different salt produces different address',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account1 = createSafeSmartAccount(
                owners: [owner],
                chainId: chain.chainIdBigInt,
                saltNonce: BigInt.from(11111),
                publicClient: client,
              );

              final account2 = createSafeSmartAccount(
                owners: [owner],
                chainId: chain.chainIdBigInt,
                saltNonce: BigInt.from(22222),
                publicClient: client,
              );

              final address1 = await account1.getAddress();
              final address2 = await account2.getAddress();

              expect(
                address1.hex.toLowerCase(),
                isNot(equals(address2.hex.toLowerCase())),
              );
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'Safe proxy factory is deployed on-chain',
          () async {
            final addresses = SafeVersionAddresses.getAddresses(
              SafeVersion.v1_4_1,
              EntryPointVersion.v07,
            )!;

            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final isDeployed =
                  await client.isDeployed(addresses.safeProxyFactoryAddress);
              expect(isDeployed, isTrue);
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'Safe singleton is deployed on-chain',
          () async {
            final addresses = SafeVersionAddresses.getAddresses(
              SafeVersion.v1_4_1,
              EntryPointVersion.v07,
            )!;

            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final isDeployed =
                  await client.isDeployed(addresses.safeSingletonAddress);
              expect(isDeployed, isTrue);
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'factory data contains valid factory address',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account = createSafeSmartAccount(
                owners: [owner],
                chainId: chain.chainIdBigInt,
                publicClient: client,
              );

              final factoryData = await account.getFactoryData();

              expect(factoryData, isNotNull);
              expect(factoryData!.factory.hex, startsWith('0x'));
              expect(factoryData.factoryData, startsWith('0x'));

              // Verify factory is deployed
              final isDeployed = await client.isDeployed(factoryData.factory);
              expect(isDeployed, isTrue);
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );
      });

      group('${chain.name} - SimpleSmartAccount', () {
        test(
          'address is deterministic across multiple instantiations',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account1 = createSimpleSmartAccount(
                owner: owner,
                chainId: chain.chainIdBigInt,
                salt: BigInt.from(67890),
                publicClient: client,
              );

              final account2 = createSimpleSmartAccount(
                owner: owner,
                chainId: chain.chainIdBigInt,
                salt: BigInt.from(67890),
                publicClient: client,
              );

              final address1 = await account1.getAddress();
              final address2 = await account2.getAddress();

              expect(
                address1.hex.toLowerCase(),
                equals(address2.hex.toLowerCase()),
              );
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'different salt produces different address',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account1 = createSimpleSmartAccount(
                owner: owner,
                chainId: chain.chainIdBigInt,
                salt: BigInt.from(33333),
                publicClient: client,
              );

              final account2 = createSimpleSmartAccount(
                owner: owner,
                chainId: chain.chainIdBigInt,
                salt: BigInt.from(44444),
                publicClient: client,
              );

              final address1 = await account1.getAddress();
              final address2 = await account2.getAddress();

              expect(
                address1.hex.toLowerCase(),
                isNot(equals(address2.hex.toLowerCase())),
              );
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'SimpleAccount factory is deployed on-chain',
          () async {
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final isDeployed = await client.isDeployed(
                SimpleAccountFactoryAddresses.v07,
              );
              expect(isDeployed, isTrue);
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'factory data contains valid factory address',
          () async {
            final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
            final client = createPublicClient(
              url: chain.rpcUrl,
              timeout: TestTimeouts.shortNetwork,
            );

            try {
              final account = createSimpleSmartAccount(
                owner: owner,
                chainId: chain.chainIdBigInt,
                publicClient: client,
              );

              final factoryData = await account.getFactoryData();

              expect(factoryData, isNotNull);
              expect(
                factoryData!.factory.hex.toLowerCase(),
                equals(SimpleAccountFactoryAddresses.v07.hex.toLowerCase()),
              );
              expect(factoryData.factoryData, startsWith('0x'));
            } finally {
              client.close();
            }
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );
      });
    }
  });
}

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

              // SafeProxyFactory 1.4.1 (permissionless.js safe constants);
              // `cast sig "createProxyWithNonce(address,bytes,uint256)"`.
              expect(
                factoryData!.factory,
                equals(
                  EthereumAddress.fromHex(
                    '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
                  ),
                ),
              );
              expect(factoryData.factoryData, startsWith('0x1688f0b9'));

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
            // Simple accounts resolve address via eth_call (getSenderAddress);
            // free public RPCs can return transient/non-standard errors.
            await withRetry(() async {
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
            });
          },
          timeout: const Timeout(TestTimeouts.mediumNetwork),
        );

        test(
          'different salt produces different address',
          () async {
            await withRetry(() async {
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
            });
          },
          timeout: const Timeout(TestTimeouts.mediumNetwork),
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

              expect(
                factoryData!.factory.hex.toLowerCase(),
                equals(SimpleAccountFactoryAddresses.v07.hex.toLowerCase()),
              );
              // `cast sig "createAccount(address,uint256)"` = 0x5fbfb9cf
              expect(factoryData.factoryData, startsWith('0x5fbfb9cf'));
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

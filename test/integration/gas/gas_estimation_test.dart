@Tags(['integration'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

void main() {
  group('Gas Estimation Integration', () {
    for (final chain in TestChain.values) {
      group(chain.name, () {
        PimlicoClient? bundler;
        PaymasterClient? paymaster;
        PublicClient? publicClient;
        SafeSmartAccount? safeAccount;
        SimpleSmartAccount? simpleAccount;

        setUp(() {
          if (!TestConfig.hasApiKeys) return;

          final rpcClient = JsonRpcClient(
            url: Uri.parse(chain.pimlicoUrl),
            timeout: TestTimeouts.mediumNetwork,
          );

          bundler = createPimlicoClient(
            url: chain.pimlicoUrl,
            entryPoint: chain.entryPointV07,
            timeout: TestTimeouts.mediumNetwork,
          );

          // Pimlico provides paymaster on the same endpoint
          paymaster = PaymasterClient(rpcClient: rpcClient);

          publicClient = PublicClient(
            rpcClient: JsonRpcClient(url: Uri.parse(chain.rpcUrl)),
          );

          safeAccount = createSafeSmartAccount(
            owners: [PrivateKeyOwner(TestConfig.hardhatTestKey)],
            chainId: chain.chainIdBigInt,
            saltNonce: BigInt.from(999999), // Unique salt for testing
          );

          simpleAccount = createSimpleSmartAccount(
            owner: PrivateKeyOwner(TestConfig.hardhatTestKey),
            chainId: chain.chainIdBigInt,
            salt: BigInt.from(888888),
            publicClient: publicClient,
          );
        });

        tearDown(() {
          bundler?.close();
          publicClient?.close();
        });

        /// Helper to get a sponsored UserOperation with paymaster stub data.
        Future<UserOperationV07> getSponsoredUserOp(
          UserOperationV07 userOp,
        ) async {
          final stubData = await paymaster!.getPaymasterStubData(
            userOp: userOp,
            entryPoint: chain.entryPointV07,
            chainId: chain.chainIdBigInt,
          );
          return userOp.withPaymasterStub(stubData);
        }

        group('SafeSmartAccount', () {
          test(
            'estimateUserOperationGas returns valid estimates',
            () async {
              if (!TestConfig.hasApiKeys) {
                markTestSkipped(TestConfig.skipNoApiKey);
                return;
              }

              final address = await safeAccount!.getAddress();
              final factoryData = await safeAccount!.getFactoryData();

              // Create a simple ETH transfer UserOp
              final callData = safeAccount!.encodeCall(
                Call(
                  to: EthereumAddress.fromHex(
                    '0x0000000000000000000000000000000000000001',
                  ),
                  value: BigInt.zero,
                  data: '0x',
                ),
              );

              final gasPrices = await bundler!.getUserOperationGasPrice();

              var userOp = UserOperationV07(
                sender: address,
                nonce: BigInt.zero,
                factory: factoryData?.factory,
                factoryData: factoryData?.factoryData,
                callData: callData,
                callGasLimit: BigInt.zero,
                verificationGasLimit: BigInt.zero,
                preVerificationGas: BigInt.zero,
                maxFeePerGas: gasPrices.fast.maxFeePerGas,
                maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
                signature: safeAccount!.getStubSignature(),
              );

              // Add paymaster sponsorship for gas estimation
              userOp = await getSponsoredUserOp(userOp);

              final estimate = await bundler!.estimateUserOperationGas(userOp);

              // All gas values should be positive
              expect(
                estimate.preVerificationGas,
                greaterThanBigInt(BigInt.zero),
              );
              expect(
                estimate.verificationGasLimit,
                greaterThanBigInt(BigInt.zero),
              );
              expect(
                estimate.callGasLimit,
                greaterThanBigInt(BigInt.zero),
              );

              // Verification gas for Safe is typically higher due to module
              expect(
                estimate.verificationGasLimit,
                greaterThan(BigInt.from(100000)),
              );
            },
            timeout: const Timeout(TestTimeouts.mediumNetwork),
          );

          test(
            'gas multipliers can be applied to estimates',
            () async {
              if (!TestConfig.hasApiKeys) {
                markTestSkipped(TestConfig.skipNoApiKey);
                return;
              }

              final address = await safeAccount!.getAddress();
              final factoryData = await safeAccount!.getFactoryData();

              final callData = safeAccount!.encodeCall(
                Call(
                  to: EthereumAddress.fromHex(
                    '0x0000000000000000000000000000000000000001',
                  ),
                  value: BigInt.zero,
                ),
              );

              final gasPrices = await bundler!.getUserOperationGasPrice();

              var userOp = UserOperationV07(
                sender: address,
                nonce: BigInt.zero,
                factory: factoryData?.factory,
                factoryData: factoryData?.factoryData,
                callData: callData,
                callGasLimit: BigInt.zero,
                verificationGasLimit: BigInt.zero,
                preVerificationGas: BigInt.zero,
                maxFeePerGas: gasPrices.fast.maxFeePerGas,
                maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
                signature: safeAccount!.getStubSignature(),
              );

              // Add paymaster sponsorship for gas estimation
              userOp = await getSponsoredUserOp(userOp);

              final estimate = await bundler!.estimateUserOperationGas(userOp);

              // Apply conservative multipliers
              final buffered =
                  estimate.withMultipliers(GasMultipliers.conservative);

              // Buffered values should be larger
              expect(
                buffered.verificationGasLimit,
                greaterThan(estimate.verificationGasLimit),
              );
              expect(
                buffered.callGasLimit,
                greaterThan(estimate.callGasLimit),
              );
            },
            timeout: const Timeout(TestTimeouts.mediumNetwork),
          );
        });

        group('SimpleSmartAccount', () {
          test(
            'estimateUserOperationGas returns valid estimates',
            () async {
              if (!TestConfig.hasApiKeys) {
                markTestSkipped(TestConfig.skipNoApiKey);
                return;
              }

              final address = await simpleAccount!.getAddress();
              final factoryData = await simpleAccount!.getFactoryData();

              final callData = simpleAccount!.encodeCall(
                Call(
                  to: EthereumAddress.fromHex(
                    '0x0000000000000000000000000000000000000001',
                  ),
                  value: BigInt.zero,
                  data: '0x',
                ),
              );

              final gasPrices = await bundler!.getUserOperationGasPrice();

              var userOp = UserOperationV07(
                sender: address,
                nonce: BigInt.zero,
                factory: factoryData?.factory,
                factoryData: factoryData?.factoryData,
                callData: callData,
                callGasLimit: BigInt.zero,
                verificationGasLimit: BigInt.zero,
                preVerificationGas: BigInt.zero,
                maxFeePerGas: gasPrices.fast.maxFeePerGas,
                maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
                signature: simpleAccount!.getStubSignature(),
              );

              // Add paymaster sponsorship for gas estimation
              userOp = await getSponsoredUserOp(userOp);

              final estimate = await bundler!.estimateUserOperationGas(userOp);

              // All gas values should be positive
              expect(
                estimate.preVerificationGas,
                greaterThanBigInt(BigInt.zero),
              );
              expect(
                estimate.verificationGasLimit,
                greaterThanBigInt(BigInt.zero),
              );
              expect(
                estimate.callGasLimit,
                greaterThanBigInt(BigInt.zero),
              );
            },
            timeout: const Timeout(TestTimeouts.mediumNetwork),
          );
        });

        test(
          'totalGasLimit calculation is correct',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final address = await safeAccount!.getAddress();
            final factoryData = await safeAccount!.getFactoryData();

            final callData = safeAccount!.encodeCall(
              Call(
                to: EthereumAddress.fromHex(
                  '0x0000000000000000000000000000000000000001',
                ),
                value: BigInt.zero,
              ),
            );

            final gasPrices = await bundler!.getUserOperationGasPrice();

            var userOp = UserOperationV07(
              sender: address,
              nonce: BigInt.zero,
              factory: factoryData?.factory,
              factoryData: factoryData?.factoryData,
              callData: callData,
              callGasLimit: BigInt.zero,
              verificationGasLimit: BigInt.zero,
              preVerificationGas: BigInt.zero,
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
              maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
              signature: safeAccount!.getStubSignature(),
            );

            // Add paymaster sponsorship for gas estimation
            userOp = await getSponsoredUserOp(userOp);

            final estimate = await bundler!.estimateUserOperationGas(userOp);

            // Verify totalGasLimit calculation (includes paymaster gas if present)
            var expectedTotal = estimate.preVerificationGas +
                estimate.verificationGasLimit +
                estimate.callGasLimit;
            if (estimate.paymasterVerificationGasLimit != null) {
              expectedTotal += estimate.paymasterVerificationGasLimit!;
            }
            if (estimate.paymasterPostOpGasLimit != null) {
              expectedTotal += estimate.paymasterPostOpGasLimit!;
            }

            expect(estimate.totalGasLimit, equals(expectedTotal));
          },
          timeout: const Timeout(TestTimeouts.mediumNetwork),
        );

        test(
          'GasCostEstimate calculates max cost correctly',
          () async {
            if (!TestConfig.hasApiKeys) {
              markTestSkipped(TestConfig.skipNoApiKey);
              return;
            }

            final address = await safeAccount!.getAddress();
            final factoryData = await safeAccount!.getFactoryData();

            final callData = safeAccount!.encodeCall(
              Call(
                to: EthereumAddress.fromHex(
                  '0x0000000000000000000000000000000000000001',
                ),
                value: BigInt.zero,
              ),
            );

            final gasPrices = await bundler!.getUserOperationGasPrice();

            var userOp = UserOperationV07(
              sender: address,
              nonce: BigInt.zero,
              factory: factoryData?.factory,
              factoryData: factoryData?.factoryData,
              callData: callData,
              callGasLimit: BigInt.zero,
              verificationGasLimit: BigInt.zero,
              preVerificationGas: BigInt.zero,
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
              maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
              signature: safeAccount!.getStubSignature(),
            );

            // Add paymaster sponsorship for gas estimation
            userOp = await getSponsoredUserOp(userOp);

            final estimate = await bundler!.estimateUserOperationGas(userOp);

            final costEstimate = GasCostEstimate.calculate(
              gasEstimate: estimate,
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
            );

            // Verify calculation
            expect(
              costEstimate.maxGasCost,
              equals(
                costEstimate.totalGasLimit * gasPrices.fast.maxFeePerGas,
              ),
            );

            // Max cost should be reasonable (less than 1 ETH for a simple tx)
            expect(
              costEstimate.maxGasCost,
              lessThan(BigInt.parse('1000000000000000000')),
            );
          },
          timeout: const Timeout(TestTimeouts.mediumNetwork),
        );
      });
    }
  });
}

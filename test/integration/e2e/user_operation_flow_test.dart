@Tags(['integration', 'funded'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

/// End-to-end tests for full UserOperation flow.
///
/// These tests require a funded account and will actually send transactions.
/// They are tagged with 'funded' and skipped by default.
///
/// To run these tests:
/// 1. Fund the test account with testnet ETH
/// 2. Set environment variables:
///    - PIMLICO_API_KEY
///    - TEST_PRIVATE_KEY (funded account private key)
///    - FUNDED_ACCOUNT_ADDRESS (pre-computed smart account address)
/// 3. Run: dart test --tags funded
void main() {
  group('UserOperation E2E Flow', () {
    for (final chain in TestChain.values) {
      group(chain.name, () {
        PimlicoClient? bundler;
        PaymasterClient? paymaster;
        PublicClient? publicClient;
        SmartAccountClient? smartAccountClient;
        SafeSmartAccount? account;

        setUp(() {
          if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) return;

          bundler = createPimlicoClient(
            url: chain.pimlicoUrl,
            entryPoint: chain.entryPointV07,
            timeout: TestTimeouts.longNetwork,
          );

          paymaster = createPaymasterClient(
            url: chain.pimlicoUrl,
            timeout: TestTimeouts.longNetwork,
          );

          publicClient = createPublicClient(
            url: chain.rpcUrl,
            timeout: TestTimeouts.shortNetwork,
          );

          account = createSafeSmartAccount(
            owners: [PrivateKeyOwner(TestConfig.testPrivateKey!)],
            chainId: chain.chainIdBigInt,
          );

          smartAccountClient = createSmartAccountClient(
            account: account!,
            bundler: bundler!,
            paymaster: paymaster,
            publicClient: publicClient!,
          );
        });

        tearDown(() {
          bundler?.close();
          paymaster?.close();
          publicClient?.close();
        });

        test('account address matches expected', () async {
          if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) {
            markTestSkipped(TestConfig.skipNoFundedAccount);
            return;
          }

          final address = await smartAccountClient!.getAddress();

          expect(
            address.hex.toLowerCase(),
            equals(TestConfig.fundedAccountAddress!.toLowerCase()),
          );
        });

        test(
          'can prepare UserOperation with paymaster',
          () async {
            if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) {
              markTestSkipped(TestConfig.skipNoFundedAccount);
              return;
            }

            final address = await smartAccountClient!.getAddress();
            final gasPrices = await bundler!.getUserOperationGasPrice();

            final userOp = await smartAccountClient!.prepareUserOperation(
              calls: [
                Call(
                  to: address, // Send to self
                  value: BigInt.zero,
                  data: '0x',
                ),
              ],
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
              maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
            );

            // Verify UserOp is properly formed
            expect(
              userOp.sender.hex.toLowerCase(),
              equals(address.hex.toLowerCase()),
            );
            expect(userOp.callGasLimit, greaterThanBigInt(BigInt.zero));
            expect(userOp.verificationGasLimit, greaterThanBigInt(BigInt.zero));
            expect(userOp.preVerificationGas, greaterThanBigInt(BigInt.zero));

            // If paymaster is used, paymaster fields should be set
            if (userOp.paymaster != null) {
              expect(userOp.paymasterData, isNotNull);
            }
          },
          timeout: const Timeout(TestTimeouts.longNetwork),
        );

        test(
          'full sponsored UserOperation flow',
          () async {
            if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) {
              markTestSkipped(TestConfig.skipNoFundedAccount);
              return;
            }

            final address = await smartAccountClient!.getAddress();

            // 1. Verify account address matches
            expect(
              address.hex.toLowerCase(),
              equals(TestConfig.fundedAccountAddress!.toLowerCase()),
            );

            // 2. Get gas prices
            final gasPrices = await bundler!.getUserOperationGasPrice();

            // 3. Send a minimal transaction (0 ETH to self)
            final hash = await smartAccountClient!.sendUserOperation(
              calls: [
                Call(
                  to: address,
                  value: BigInt.zero,
                  data: '0x',
                ),
              ],
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
              maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
            );

            // 4. Verify hash format
            expect(hash, startsWith('0x'));
            expect(hash.length, equals(66)); // 0x + 64 hex chars

            // 5. Wait for receipt
            final receipt = await smartAccountClient!.waitForReceipt(
              hash,
              timeout: TestTimeouts.e2eFlow,
            );

            expect(receipt, isNotNull);
            expect(receipt!.success, isTrue);
            expect(receipt.receipt?.transactionHash, startsWith('0x'));
          },
          timeout: const Timeout(TestTimeouts.e2eFlow),
        );

        test(
          'account is deployed after first UserOp',
          () async {
            if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) {
              markTestSkipped(TestConfig.skipNoFundedAccount);
              return;
            }

            final address = await account!.getAddress();
            final isDeployed = await publicClient!.isDeployed(address);

            // Note: This test assumes a UserOp has been sent previously
            // It will pass if the account is deployed, skip otherwise
            if (!isDeployed) {
              markTestSkipped(
                'Account not yet deployed. Run full flow test first.',
              );
            }

            expect(isDeployed, isTrue);
          },
          timeout: const Timeout(TestTimeouts.shortNetwork),
        );

        test(
          'can send batch transaction',
          () async {
            if (!TestConfig.hasApiKeys || !TestConfig.hasFundedAccount) {
              markTestSkipped(TestConfig.skipNoFundedAccount);
              return;
            }

            final address = await smartAccountClient!.getAddress();
            final gasPrices = await bundler!.getUserOperationGasPrice();

            // Send batch of 2 calls
            final hash = await smartAccountClient!.sendUserOperation(
              calls: [
                Call(
                  to: address,
                  value: BigInt.zero,
                  data: '0x',
                ),
                Call(
                  to: EthereumAddress.fromHex(
                    '0x0000000000000000000000000000000000000001',
                  ),
                  value: BigInt.zero,
                  data: '0x',
                ),
              ],
              maxFeePerGas: gasPrices.fast.maxFeePerGas,
              maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
            );

            expect(hash, startsWith('0x'));

            final receipt = await smartAccountClient!.waitForReceipt(
              hash,
              timeout: TestTimeouts.e2eFlow,
            );

            expect(receipt, isNotNull);
            expect(receipt!.success, isTrue);
          },
          timeout: const Timeout(TestTimeouts.e2eFlow),
        );
      });
    }
  });
}

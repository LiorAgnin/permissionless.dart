@Tags(['integration'])
library;

import 'dart:io';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';

/// Kernel v4 enable-mode on-chain checks.
///
/// Enable mode installs modules atomically with a UserOperation (nonce mode
/// `0x08`), so its full acceptance path needs a chain carrying the Kernel v4
/// stack — no public deployments exist yet. Like the other Kernel v4
/// integration tests, these run against an explicitly configured RPC
/// (typically a local anvil where the release recipe has been executed) and
/// skip cleanly everywhere else.
///
/// Environment variables:
/// - `KERNEL_V4_RPC_URL`: RPC of a chain carrying the Kernel v4 stack
/// - `KERNEL_V4_BUNDLER_URL`: an EntryPoint v0.9-aware bundler
void main() {
  final rpcUrl = Platform.environment['KERNEL_V4_RPC_URL'];
  final bundlerUrl = Platform.environment['KERNEL_V4_BUNDLER_URL'];

  const skipNoRpc = 'Skipping: KERNEL_V4_RPC_URL not set '
      '(no public Kernel v4 deployments exist yet)';
  const skipNoBundler = 'Skipping: KERNEL_V4_BUNDLER_URL not set '
      '(needs an EntryPoint v0.9-aware bundler)';

  final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
  final index = BigInt.from(7440);

  // The v3 drop-in ECDSA validator — the module the enable op installs.
  final ecdsaValidator =
      EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');

  group('Kernel v4 enable-mode estimation', () {
    test(
      'the all-stub EnableModeSignature blob passes bundler simulation',
      () async {
        final publicClient = createPublicClient(url: rpcUrl!);
        try {
          final addresses = KernelV4Addresses.predicted;
          if (!await publicClient.isDeployed(addresses.factory)) {
            markTestSkipped(
              'Skipping: KernelFactory not deployed on this chain',
            );
            return;
          }
          // The enable path installs the module during validation, so the
          // module must have code (ModuleInstallFailed otherwise).
          if (!await publicClient.isDeployed(ecdsaValidator)) {
            markTestSkipped(
              'Skipping: ECDSA validator ${ecdsaValidator.hex} not deployed '
              'on this chain (the enable op installs it)',
            );
            return;
          }

          // Deploy + enable in one operation: the module is installed
          // atomically and validates this very op. `execute` must be
          // allow-listed for the module (non-root validations gate on the
          // leading selector).
          final packages = [
            KernelV4Install(
              moduleType: BigInt.one,
              module: ecdsaValidator,
              moduleData: owner.address.hex,
              internalData:
                  '0x0000000000000000000000000000000000000000e9ae5c53',
            ),
          ];
          final account = createKernelImmutableECDSA(
            owner: owner,
            chainId: await publicClient.getChainId(),
            index: index,
            useStaker: false,
            validation: KernelV4Validation.validator(ecdsaValidator),
            enableMode: KernelV4EnableMode(packages: packages),
          );
          final client = SmartAccountClient(
            account: account,
            bundler: createBundlerClient(
              url: bundlerUrl!,
              entryPoint: account.entryPoint,
            ),
            publicClient: publicClient,
          );

          final userOp = await client.prepareUserOperation(
            calls: [
              Call(
                to: EthereumAddress.fromHex(
                  '0x000000000000000000000000000000000000dEaD',
                ),
                value: BigInt.zero,
                data: '0x',
              ),
            ],
          );

          // The nonce carries the enable flag and routes to the module…
          final decoded = decodeKernelV4Nonce(userOp.nonce);
          expect(decoded.vMode, equals(KernelV4ValidationMode.enable));
          expect(decoded.vType, equals(KernelV4ValidationType.validator));
          expect(decoded.vId, equals(ecdsaValidator.hex.toLowerCase()));

          // …and simulation of the full enable path succeeded.
          expect(userOp.callGasLimit, greaterThan(BigInt.zero));
          expect(userOp.verificationGasLimit, greaterThan(BigInt.zero));
          expect(userOp.preVerificationGas, greaterThan(BigInt.zero));
        } finally {
          publicClient.close();
        }
      },
      skip: rpcUrl == null ||
              rpcUrl.isEmpty ||
              bundlerUrl == null ||
              bundlerUrl.isEmpty
          ? (bundlerUrl == null || bundlerUrl.isEmpty
              ? skipNoBundler
              : skipNoRpc)
          : false,
    );
  });
}

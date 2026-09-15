@Tags(['integration'])
library;

import 'dart:io';

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';

/// Kernel v4 on-chain cross-checks.
///
/// Kernel v4.0 has no confirmed public deployments yet (the release recipe is
/// deterministic and permissionless, so addresses are chain-independent).
/// These tests therefore run against an explicitly configured RPC — typically
/// a local anvil where the release recipe has been executed — and skip
/// cleanly everywhere else.
///
/// Environment variables:
/// - `KERNEL_V4_RPC_URL`: RPC of a chain carrying the Kernel v4 stack
/// - `KERNEL_V4_BUNDLER_URL`: an EntryPoint v0.9-aware bundler (optional)
void main() {
  final rpcUrl = Platform.environment['KERNEL_V4_RPC_URL'];
  final bundlerUrl = Platform.environment['KERNEL_V4_BUNDLER_URL'];

  const skipNoRpc = 'Skipping: KERNEL_V4_RPC_URL not set '
      '(no public Kernel v4 deployments exist yet)';
  const skipNoBundler = 'Skipping: KERNEL_V4_BUNDLER_URL not set '
      '(needs an EntryPoint v0.9-aware bundler)';

  final owner = PrivateKeyOwner(TestConfig.hardhatTestKey);
  final index = BigInt.from(7439);

  group('Kernel v4 factory cross-check', () {
    test(
      'local address equals factory.getECDSAAddress',
      () async {
        final client = createPublicClient(url: rpcUrl!);
        try {
          final addresses = KernelV4Addresses.predicted;
          if (!await client.isDeployed(addresses.factory)) {
            markTestSkipped(
              'Skipping: KernelFactory not deployed at '
              '${addresses.factory.hex} on this chain',
            );
            return;
          }

          final account = createKernelImmutableECDSA(
            owner: owner,
            chainId: await client.getChainId(),
            index: index,
          );

          // getECDSAAddress takes the same arguments as deployECDSA; swap
          // the selector on the encoded deploy calldata.
          final deployCalldata = encodeKernelV4DeployEcdsaCalldata(
            signer: owner.address,
            packages: const [],
            nonce: index,
          );
          final callData = Hex.concat([
            KernelV4Selectors.getEcdsaAddress,
            Hex.strip0x(deployCalldata).substring(8),
          ]);
          final result = await client.call(
            Call(to: addresses.factory, data: callData),
          );
          final onChain = EthereumAddress.fromHex(Hex.slice(result, 12));

          expect(await account.getAddress(), equals(onChain));
        } finally {
          client.close();
        }
      },
      skip: rpcUrl == null || rpcUrl.isEmpty ? skipNoRpc : false,
    );

    test(
      'local address equals EntryPoint getSenderAddress',
      () async {
        final client = createPublicClient(url: rpcUrl!);
        try {
          final addresses = KernelV4Addresses.predicted;
          if (!await client.isDeployed(addresses.factory) ||
              !await client.isDeployed(EntryPointAddresses.v09)) {
            markTestSkipped(
              'Skipping: Kernel v4 factory or EntryPoint v0.9 not deployed '
              'on this chain',
            );
            return;
          }

          // Direct-factory init code: getSenderAddress simulates deployment,
          // which needs no Staker approval.
          final account = createKernelImmutableECDSA(
            owner: owner,
            chainId: await client.getChainId(),
            index: index,
            useStaker: false,
          );

          final sender = await client.getSenderAddress(
            initCode: await account.getInitCode(),
            entryPoint: EntryPointAddresses.v09,
          );

          expect(await account.getAddress(), equals(sender));
        } finally {
          client.close();
        }
      },
      skip: rpcUrl == null || rpcUrl.isEmpty ? skipNoRpc : false,
    );
  });

  group('Kernel v4 UUPS factory cross-check', () {
    // The v3 drop-in ECDSA validator — only its address feeds the salt for
    // getAddress, so the module need not be deployed for these checks.
    final rootValidator =
        EthereumAddress.fromHex('0x845ADb2C711129d4f3966735eD98a9F09fC4cE57');

    test(
      'local address equals factory.getAddress',
      () async {
        final client = createPublicClient(url: rpcUrl!);
        try {
          final addresses = KernelV4Addresses.predicted;
          if (!await client.isDeployed(addresses.factory)) {
            markTestSkipped(
              'Skipping: KernelFactory not deployed at '
              '${addresses.factory.hex} on this chain',
            );
            return;
          }

          final account = createKernelUUPS(
            owner: owner,
            chainId: await client.getChainId(),
            rootValidator: rootValidator,
            index: index,
          );

          // getAddress takes the same arguments as deploy; swap the
          // selector on the encoded deploy calldata.
          final deployCalldata = encodeKernelV4DeployCalldata(
            packages: [
              KernelV4Install(
                moduleType: BigInt.one,
                module: rootValidator,
                moduleData: owner.address.hex,
              ),
            ],
            nonce: index,
          );
          final callData = Hex.concat([
            KernelV4Selectors.getAddress,
            Hex.strip0x(deployCalldata).substring(8),
          ]);
          final result = await client.call(
            Call(to: addresses.factory, data: callData),
          );
          final onChain = EthereumAddress.fromHex(Hex.slice(result, 12));

          expect(await account.getAddress(), equals(onChain));
        } finally {
          client.close();
        }
      },
      skip: rpcUrl == null || rpcUrl.isEmpty ? skipNoRpc : false,
    );

    test(
      'local address equals EntryPoint getSenderAddress',
      () async {
        final client = createPublicClient(url: rpcUrl!);
        try {
          final addresses = KernelV4Addresses.predicted;
          if (!await client.isDeployed(addresses.factory) ||
              !await client.isDeployed(EntryPointAddresses.v09)) {
            markTestSkipped(
              'Skipping: Kernel v4 factory or EntryPoint v0.9 not deployed '
              'on this chain',
            );
            return;
          }
          // The simulated deploy installs the root validator, and the Kernel
          // requires the module to have code (ModuleInstallFailed otherwise).
          if (!await client.isDeployed(rootValidator)) {
            markTestSkipped(
              'Skipping: root validator ${rootValidator.hex} not deployed '
              'on this chain (required by the simulated initialize)',
            );
            return;
          }

          // Direct-factory init code: getSenderAddress simulates deployment,
          // which needs no Staker approval.
          final account = createKernelUUPS(
            owner: owner,
            chainId: await client.getChainId(),
            rootValidator: rootValidator,
            index: index,
            useStaker: false,
          );

          final sender = await client.getSenderAddress(
            initCode: await account.getInitCode(),
            entryPoint: EntryPointAddresses.v09,
          );

          expect(await account.getAddress(), equals(sender));
        } finally {
          client.close();
        }
      },
      skip: rpcUrl == null || rpcUrl.isEmpty ? skipNoRpc : false,
    );
  });

  group('Kernel v4 bundler gas estimation', () {
    test(
      'estimation succeeds with the stub signature',
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

          final account = createKernelImmutableECDSA(
            owner: owner,
            chainId: await publicClient.getChainId(),
            index: index,
            useStaker: false,
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

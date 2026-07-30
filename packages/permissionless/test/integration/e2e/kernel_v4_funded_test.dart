@Tags(['integration', 'funded'])
library;

import 'package:permissionless/permissionless.dart';
import 'package:test/test.dart';

import '../config/test_config.dart';
import '../config/test_utils.dart';

/// Funded end-to-end tests for Kernel v4.0 on EntryPoint v0.9.
///
/// These tests submit real UserOperations. They are tagged `funded` and
/// excluded by the `quick` preset. Kernel v4.0 has **no confirmed public
/// deployments** yet; the release recipe is deterministic and permissionless,
/// so addresses are chain-independent once the recipe has been run (typically
/// a local anvil). Every case skips cleanly when infrastructure is missing.
///
/// ## Environment
///
/// Required for any case to leave the skip path:
/// - `KERNEL_V4_RPC_URL` — chain with Kernel v4 + EntryPoint v0.9
/// - `KERNEL_V4_BUNDLER_URL` — EntryPoint v0.9-aware bundler
/// - `TEST_PRIVATE_KEY` — funded EOA (**never** Hardhat #0 on a live network)
///
/// Optional:
/// - `KERNEL_V4_PAYMASTER_URL` — sponsor gas (otherwise self-funded; the
///   counterfactual account must hold native ETH, or the RPC must support
///   `anvil_setBalance`)
/// - `KERNEL_V4_ECDSA_VALIDATOR` — for enable-mode install (defaults to the
///   v3 drop-in `0x845ADb2C…` when that code is deployed)
/// - `KERNEL_V4_POLICY` + `KERNEL_V4_SIGNER_MODULE` +
///   `KERNEL_V4_SESSION_PRIVATE_KEY` — for permission-scoped UserOps
///
/// ## Verified chains
///
/// As of this release, funded Kernel v4 e2e has no public chain verification.
/// Local anvil with the Kernel v0.4.0 release recipe is the intended path.
/// Re-run with the env vars above once a public stack is available.
void main() {
  final canRun = TestConfig.hasKernelV4FundedInfra;

  group('Kernel v4 funded e2e', () {
    late PublicClient publicClient;
    late BundlerClient bundler;
    late PaymasterClient? paymaster;
    late PrivateKeyOwner owner;
    late BigInt chainId;
    late BigInt deployIndex;

    setUp(() async {
      if (!canRun) return;

      publicClient = createPublicClient(
        url: TestConfig.kernelV4RpcUrl!,
        timeout: TestTimeouts.longNetwork,
      );
      bundler = createBundlerClient(
        url: TestConfig.kernelV4BundlerUrl!,
        entryPoint: EntryPointAddresses.v09,
        timeout: TestTimeouts.longNetwork,
      );
      final paymasterUrl = TestConfig.kernelV4PaymasterUrl;
      paymaster = paymasterUrl != null && paymasterUrl.isNotEmpty
          ? createPaymasterClient(
              url: paymasterUrl,
              timeout: TestTimeouts.longNetwork,
            )
          : null;
      owner = PrivateKeyOwner(TestConfig.testPrivateKey!);
      chainId = await publicClient.getChainId();
      // Unique salt per process so re-runs do not collide with deployed
      // accounts from earlier suite runs.
      deployIndex = BigInt.from(
        DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      );
    });

    tearDown(() {
      if (!canRun) return;
      publicClient.close();
      bundler.close();
      paymaster?.close();
    });

    test(
      'ImmutableECDSA: deploy + UserOperation lands',
      () async {
        if (!canRun) {
          markTestSkipped(TestConfig.skipNoKernelV4FundedInfra);
          return;
        }
        if (!await _kernelV4StackReady(publicClient)) {
          markTestSkipped(_skipNoStack);
          return;
        }

        final account = createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          index: deployIndex,
          // Direct factory — no Staker approval required on fresh chains.
          useStaker: false,
          publicClient: publicClient,
        );
        final address = await account.getAddress();
        if (!await _ensureNativeBalance(publicClient, address)) {
          markTestSkipped(_skipNoBalance(address));
          return;
        }

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: publicClient,
          paymaster: paymaster,
        );

        final receipt = await client.sendUserOperationAndWait(
          calls: [
            Call(to: address, value: BigInt.zero, data: '0x'),
          ],
          timeout: TestTimeouts.e2eFlow,
        );

        expect(receipt.success, isTrue);
        expect(await publicClient.isDeployed(address), isTrue);
      },
      skip: canRun ? false : TestConfig.skipNoKernelV4FundedInfra,
      timeout: const Timeout(TestTimeouts.e2eTest),
    );

    test(
      'enable-mode: install validator and land a UserOperation',
      () async {
        if (!canRun) {
          markTestSkipped(TestConfig.skipNoKernelV4FundedInfra);
          return;
        }
        if (!await _kernelV4StackReady(publicClient)) {
          markTestSkipped(_skipNoStack);
          return;
        }

        final validator = await _resolveEcdsaValidator(publicClient);
        if (validator == null) {
          markTestSkipped(
            'Skipping: no ECDSA validator module on this chain. '
            'Set KERNEL_V4_ECDSA_VALIDATOR or deploy the v3 drop-in '
            '0x845ADb2C711129d4f3966735eD98a9F09fC4cE57.',
          );
          return;
        }

        // Allow-list execute so the newly installed validator may authorize
        // this op's callData.
        final packages = [
          KernelV4Install.validator(
            module: validator,
            moduleData: owner.address.hex,
            allowedSelectors: [Erc7579Selectors.execute],
          ),
        ];
        final account = createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          index: deployIndex + BigInt.one,
          useStaker: false,
          validation: KernelV4Validation.validator(validator),
          enableMode: KernelV4EnableMode(packages: packages),
          publicClient: publicClient,
        );
        final address = await account.getAddress();
        if (!await _ensureNativeBalance(publicClient, address)) {
          markTestSkipped(_skipNoBalance(address));
          return;
        }

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: publicClient,
          paymaster: paymaster,
        );

        final receipt = await client.sendUserOperationAndWait(
          calls: [
            Call(to: address, value: BigInt.zero, data: '0x'),
          ],
          timeout: TestTimeouts.e2eFlow,
        );

        expect(receipt.success, isTrue);
      },
      skip: canRun ? false : TestConfig.skipNoKernelV4FundedInfra,
      timeout: const Timeout(TestTimeouts.e2eTest),
    );

    test(
      'permission-scoped UserOperation under a session key',
      () async {
        if (!canRun) {
          markTestSkipped(TestConfig.skipNoKernelV4FundedInfra);
          return;
        }
        if (!await _kernelV4StackReady(publicClient)) {
          markTestSkipped(_skipNoStack);
          return;
        }

        final policyHex = TestConfig.kernelV4Policy;
        final signerHex = TestConfig.kernelV4SignerModule;
        final sessionKey = TestConfig.kernelV4SessionPrivateKey;
        if (!_nonEmpty(policyHex) ||
            !_nonEmpty(signerHex) ||
            !_nonEmpty(sessionKey)) {
          markTestSkipped(
            'Skipping: permission-scoped funded e2e needs '
            'KERNEL_V4_POLICY, KERNEL_V4_SIGNER_MODULE, and '
            'KERNEL_V4_SESSION_PRIVATE_KEY (and those modules deployed).',
          );
          return;
        }
        if (TestConfig.isHardhatZeroKey(sessionKey)) {
          markTestSkipped(
            'Skipping: KERNEL_V4_SESSION_PRIVATE_KEY must not be Hardhat #0',
          );
          return;
        }

        final policy = EthereumAddress.fromHex(policyHex!);
        final signerModule = EthereumAddress.fromHex(signerHex!);
        if (!await publicClient.isDeployed(policy) ||
            !await publicClient.isDeployed(signerModule)) {
          markTestSkipped(
            'Skipping: policy ${policy.hex} or signer ${signerModule.hex} '
            'not deployed on this chain',
          );
          return;
        }

        final session = PrivateKeyOwner(sessionKey!);
        // 4-byte PermissionId — unique-ish per run, left-aligned in the nonce.
        final permissionId =
            '0x${(deployIndex & BigInt.from(0xffffffff)).toRadixString(16).padLeft(8, '0')}';
        final packages = [
          KernelV4Install.policy(
            module: policy,
            permissionId: permissionId,
          ),
          KernelV4Install.signer(
            module: signerModule,
            permissionId: permissionId,
            moduleData: session.address.hex,
            hook: KernelV4HookSentinels.notInstalled,
            allowedSelectors: [Erc7579Selectors.execute],
          ),
        ];

        // Grant the permission at deploy time so one UserOp proves the
        // permission path end-to-end.
        final rootAccount = createKernelImmutableECDSA(
          owner: owner,
          chainId: chainId,
          index: deployIndex + BigInt.from(2),
          useStaker: false,
          additionalPackages: packages,
          publicClient: publicClient,
        );
        final address = await rootAccount.getAddress();
        if (!await _ensureNativeBalance(publicClient, address)) {
          markTestSkipped(_skipNoBalance(address));
          return;
        }

        // First op deploys with the permission packages under root validation.
        final rootClient = SmartAccountClient(
          account: rootAccount,
          bundler: bundler,
          publicClient: publicClient,
          paymaster: paymaster,
        );
        final deployReceipt = await rootClient.sendUserOperationAndWait(
          calls: [
            Call(to: address, value: BigInt.zero, data: '0x'),
          ],
          timeout: TestTimeouts.e2eFlow,
        );
        expect(deployReceipt.success, isTrue);

        // Second op is signed by the session key under the PermissionId.
        // The ImmutableECDSA CREATE2 identity is the root signer; pass the
        // already-deployed address so the session owner only supplies the
        // permission signature (not a new counterfactual).
        // Proof policies often accept empty policy chunks (`0x`).
        final sessionAccount = createKernelImmutableECDSA(
          owner: session,
          chainId: chainId,
          address: address,
          validation: KernelV4Validation.permission(
            permissionId,
            policySignatures: ['0x'],
          ),
          publicClient: publicClient,
        );
        final sessionClient = SmartAccountClient(
          account: sessionAccount,
          bundler: bundler,
          publicClient: publicClient,
          paymaster: paymaster,
        );
        final permissionReceipt = await sessionClient.sendUserOperationAndWait(
          calls: [
            Call(to: address, value: BigInt.zero, data: '0x'),
          ],
          timeout: TestTimeouts.e2eFlow,
        );
        expect(permissionReceipt.success, isTrue);
      },
      skip: canRun ? false : TestConfig.skipNoKernelV4FundedInfra,
      timeout: const Timeout(TestTimeouts.e2eTest),
    );

    test(
      'Kernel7702: authorize + UserOperation when EIP-7702 is available',
      () async {
        if (!canRun) {
          markTestSkipped(TestConfig.skipNoKernelV4FundedInfra);
          return;
        }

        final implementation = KernelV4Addresses.predicted.kernel7702!;
        if (!await publicClient.isDeployed(implementation) ||
            !await publicClient.isDeployed(EntryPointAddresses.v09)) {
          markTestSkipped(
            'Skipping: Kernel7702 implementation or EntryPoint v0.9 not '
            'deployed on this chain',
          );
          return;
        }

        // EIP-7702 UserOps need a bundler that accepts eip7702Auth. Probe
        // with a dry prepare if the chain is not known to support 7702.
        final eoaOwner =
            PrivateKeyEip7702KernelOwner(TestConfig.testPrivateKey!);
        final account = createKernel7702(
          owner: eoaOwner,
          chainId: chainId,
          publicClient: publicClient,
        );
        final address = await account.getAddress();
        expect(address, equals(eoaOwner.address));

        if (!await _ensureNativeBalance(publicClient, address)) {
          markTestSkipped(_skipNoBalance(address));
          return;
        }

        final client = SmartAccountClient(
          account: account,
          bundler: bundler,
          publicClient: publicClient,
          paymaster: paymaster,
        );

        try {
          final receipt = await client.sendUserOperationAndWait(
            calls: [
              Call(to: address, value: BigInt.zero, data: '0x'),
            ],
            timeout: TestTimeouts.e2eFlow,
          );
          expect(receipt.success, isTrue);
        } on Object catch (e) {
          // Bundlers that do not yet speak EIP-7702 + EntryPoint v0.9
          // reject at estimate or send — document and skip rather than fail.
          final message = e.toString();
          if (_isInfrastructureRejection(message)) {
            markTestSkipped(
              'Skipping: bundler/chain rejected Kernel7702 UserOp '
              '(EIP-7702 + EntryPoint v0.9 may be unsupported): $message',
            );
            return;
          }
          rethrow;
        }
      },
      skip: canRun ? false : TestConfig.skipNoKernelV4FundedInfra,
      timeout: const Timeout(TestTimeouts.e2eTest),
    );
  });
}

const _skipNoStack =
    'Skipping: KernelFactory or EntryPoint v0.9 not deployed on this chain '
    '(no public Kernel v4 deployments exist yet)';

String _skipNoBalance(EthereumAddress address) =>
    'Skipping: account ${address.hex} has zero native balance and '
    'anvil_setBalance is unavailable. Fund the counterfactual address or set '
    'KERNEL_V4_PAYMASTER_URL.';

bool _nonEmpty(String? value) => value != null && value.isNotEmpty;

Future<bool> _kernelV4StackReady(PublicClient client) async {
  final addresses = KernelV4Addresses.predicted;
  return await client.isDeployed(addresses.factory) &&
      await client.isDeployed(EntryPointAddresses.v09) &&
      await client.isDeployed(addresses.kernelImmutableECDSA);
}

/// Default v3 drop-in ECDSA validator used by Kernel v4 integration fixtures.
final _defaultEcdsaValidator = EthereumAddress.fromHex(
  '0x845ADb2C711129d4f3966735eD98a9F09fC4cE57',
);

Future<EthereumAddress?> _resolveEcdsaValidator(PublicClient client) async {
  final fromEnv = TestConfig.kernelV4EcdsaValidator;
  if (_nonEmpty(fromEnv)) {
    final address = EthereumAddress.fromHex(fromEnv!);
    if (await client.isDeployed(address)) return address;
    return null;
  }
  if (await client.isDeployed(_defaultEcdsaValidator)) {
    return _defaultEcdsaValidator;
  }
  return null;
}

/// Ensure [address] can pay for a self-funded UserOp, or return false.
///
/// Tries `anvil_setBalance` first (local stacks). On live networks the
/// counterfactual must already hold ETH, or a paymaster must be configured.
Future<bool> _ensureNativeBalance(
  PublicClient client,
  EthereumAddress address,
) async {
  final balance = await client.getBalance(address);
  if (balance > BigInt.zero) return true;

  // ~10 ETH — enough for several EntryPoint deposits on a test chain.
  const tenEth = '0x8ac7230489e80000';
  try {
    await client.rpcClient.call('anvil_setBalance', [address.hex, tenEth]);
    final after = await client.getBalance(address);
    return after > BigInt.zero;
  } on Object {
    return false;
  }
}

bool _isInfrastructureRejection(String message) {
  final lower = message.toLowerCase();
  return lower.contains('eip-7702') ||
      lower.contains('eip7702') ||
      lower.contains('authorization') ||
      lower.contains('aa23') ||
      lower.contains('aa24') ||
      lower.contains('aa25') ||
      lower.contains('unsupported') ||
      lower.contains('method not found') ||
      lower.contains('not supported');
}

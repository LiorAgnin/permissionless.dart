// Shared Light Account runner used by per-version examples.
//
// Supported combinations (from [LightAccountVersion]):
//   - Light v1.1.0 + EntryPoint v0.6
//   - Light v2.0.0 + EntryPoint v0.7
//
// Light does not support EntryPoint v0.8 (use Eip7702Simple for that).

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

/// A concrete Light Account configuration matrix cell.
class LightVariant {
  LightVariant({
    required this.version,
    required this.entryPointVersion,
    required int salt,
    required this.label,
  }) : salt = BigInt.from(salt);

  final LightAccountVersion version;
  final EntryPointVersion entryPointVersion;

  /// Distinct salt so each variant gets its own address under the same owner.
  final BigInt salt;
  final String label;

  String get id => 'light-${version.version}-ep${entryPointVersion.value}';

  EthereumAddress get entryPointAddress =>
      EntryPointAddresses.fromVersion(entryPointVersion);

  bool get isV06 => entryPointVersion == EntryPointVersion.v06;
}

/// All supported Light Account example variants.
final List<LightVariant> allLightVariants = [
  LightVariant(
    version: LightAccountVersion.v110,
    entryPointVersion: EntryPointVersion.v06,
    salt: 1106,
    label: 'Light Account v1.1.0 + EntryPoint v0.6',
  ),
  LightVariant(
    version: LightAccountVersion.v200,
    entryPointVersion: EntryPointVersion.v07,
    salt: 2007,
    label: 'Light Account v2.0.0 + EntryPoint v0.7',
  ),
];

/// Result of a single Light variant run.
class LightRunResult {
  const LightRunResult({
    required this.variant,
    required this.ok,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });

  final LightVariant variant;
  final bool ok;
  final String? userOpHash;
  final String? transactionHash;
  final String? error;

  @override
  String toString() {
    if (ok) {
      return 'OK  ${variant.label}'
          '${transactionHash != null ? '  tx=$transactionHash' : ''}';
    }
    return 'FAIL ${variant.label}: $error';
  }
}

/// Parse a version string like `1.1.0`, `2.0.0`, `v110`, `ep0.6`.
LightVariant? parseLightVariant(String raw) {
  final s = raw.trim().toLowerCase();
  for (final v in allLightVariants) {
    if (v.id == s || v.label.toLowerCase() == s) return v;
  }
  switch (s) {
    case '1.1.0':
    case 'v1.1.0':
    case 'v110':
    case 'ep0.6':
    case '0.6':
      return allLightVariants.firstWhere(
        (v) => v.version == LightAccountVersion.v110,
      );
    case '2.0.0':
    case 'v2.0.0':
    case 'v200':
    case 'ep0.7':
    case '0.7':
    case 'default':
      return allLightVariants.firstWhere(
        (v) => v.version == LightAccountVersion.v200,
      );
    default:
      return null;
  }
}

/// Run a sponsored (or self-funded) self-ping UserOp for [variant].
Future<LightRunResult> runLightVariant({
  required LightVariant variant,
  bool selfFunded = false,
  bool quiet = false,
}) async {
  void log(String msg) {
    if (!quiet) print(msg);
  }

  final config = ExampleConfig.load();
  final ep = variant.entryPointAddress;
  final epLabel = 'v${variant.entryPointVersion.value}';

  log('='.padRight(60, '='));
  log(variant.label);
  log('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  log('='.padRight(60, '='));

  final owner = PrivateKeyOwner(config.privateKey);
  log('\nOwner address: ${owner.address.checksummed}');

  final publicClient = createPublicClient(url: config.sepoliaRpcUrl);
  final pimlicoUrl = config.sepoliaPimlicoUrl;

  final account = createLightSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    entryPointVersion: variant.entryPointVersion,
    version: variant.version,
    salt: variant.salt,
    publicClient: publicClient,
  );

  final factory = LightAccountFactoryAddresses.fromVersion(variant.version);

  log('Light version: ${variant.version.version}');
  log('EntryPoint: ${account.entryPoint.checksummed} ($epLabel)');
  log('Factory: ${factory.checksummed}');
  log(
    'Signature type prefix: '
    '${variant.version == LightAccountVersion.v200 ? "yes (0x00 EOA)" : "no (v1.1.0)"}',
  );

  final accountAddress = await account.getAddress();
  final isDeployed = await publicClient.isDeployed(accountAddress);
  log(
    'Account: ${accountAddress.checksummed} '
    '${isDeployed ? "(already deployed)" : "(will be deployed)"}',
  );

  final bundler = createBundlerClient(url: pimlicoUrl, entryPoint: ep);
  final pimlico = createPimlicoClient(url: pimlicoUrl, entryPoint: ep);
  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: bundler,
    publicClient: publicClient,
    paymaster: paymaster,
  );

  try {
    log('\n--- Account Status ---');
    final gasPrices = await pimlico.getUserOperationGasPrice();
    log('Gas prices - Fast: ${gasPrices.fast.maxFeePerGas} wei');

    final nonce = await publicClient.getAccountNonce(
      accountAddress,
      ep,
      nonceKey: account.nonceKey,
    );
    log('Current nonce: $nonce');

    if (selfFunded) {
      final balance = await publicClient.getBalance(accountAddress);
      log('Balance: ${balance / BigInt.from(10).pow(18)} ETH');
      if (balance == BigInt.zero) {
        final msg =
            'Self-funded mode requires ETH at ${accountAddress.checksummed}';
        log('\n⚠️  $msg');
        return LightRunResult(variant: variant, ok: false, error: msg);
      }
    }

    log('\n--- Building Transaction ---');
    final call = Call(to: accountAddress, value: BigInt.zero, data: '0x');
    log('Transaction: Self-ping (0 ETH to self)');

    log('\n--- Preparing / Signing / Sending ---');

    late final String hash;
    if (variant.isV06) {
      late final UserOperationV06 userOp;
      try {
        userOp = await smartAccountClient.prepareUserOperationV06(
          calls: [call],
          maxFeePerGas: gasPrices.fast.maxFeePerGas,
          maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
          sender: accountAddress,
          nonce: nonce,
        );
      } on BundlerRpcError catch (e) {
        log('⚠️  prepareUserOperationV06 failed: ${e.message}');
        return LightRunResult(variant: variant, ok: false, error: e.message);
      }

      log('Sender: ${userOp.sender.checksummed}');
      log('Nonce: ${userOp.nonce}');
      log('Call gas limit: ${userOp.callGasLimit}');
      log('Verification gas limit: ${userOp.verificationGasLimit}');
      if (userOp.paymasterAndData != '0x' &&
          userOp.paymasterAndData.length > 2) {
        final pm = EthereumAddress.fromHex(
          '0x${userOp.paymasterAndData.substring(2, 42)}',
        );
        log('Paymaster: ${pm.checksummed} (SPONSORED)');
      } else {
        log('Paymaster: None (SELF-FUNDED)');
      }

      final signed = await smartAccountClient.signUserOperationV06(userOp);
      log('Signature length: ${signed.signature.length} chars');
      hash = await smartAccountClient.sendPreparedUserOperationV06(signed);
    } else {
      late final UserOperationV07 userOp;
      try {
        userOp = await smartAccountClient.prepareUserOperation(
          calls: [call],
          maxFeePerGas: gasPrices.fast.maxFeePerGas,
          maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
          sender: accountAddress,
          nonce: nonce,
        );
      } on BundlerRpcError catch (e) {
        log('⚠️  prepareUserOperation failed: ${e.message}');
        return LightRunResult(variant: variant, ok: false, error: e.message);
      }

      log('Sender: ${userOp.sender.checksummed}');
      log('Nonce: ${userOp.nonce}');
      log('Call gas limit: ${userOp.callGasLimit}');
      log('Verification gas limit: ${userOp.verificationGasLimit}');
      if (userOp.paymaster != null) {
        log('Paymaster: ${userOp.paymaster!.checksummed} (SPONSORED)');
      } else {
        log('Paymaster: None (SELF-FUNDED)');
      }

      final signed = await smartAccountClient.signUserOperation(userOp);
      log('Signature length: ${signed.signature.length} chars');
      hash = await smartAccountClient.sendPreparedUserOperation(signed);
    }

    log('UserOperation hash: $hash');
    log('\n--- Waiting for Confirmation ---');

    final status = await pimlico.waitForUserOperationStatus(
      hash,
      timeout: const Duration(seconds: 60),
    );

    log('Status: ${status.status}');
    final included = status.isSuccess || status.status == 'included';
    if (included) {
      log('✅ Transaction included!');
      if (status.transactionHash != null) {
        log('Transaction hash: ${status.transactionHash}');
        log('https://sepolia.etherscan.io/tx/${status.transactionHash}');
      }
      log('\n${'='.padRight(60, '=')}');
      log('Example complete! ${variant.label}');
      log('='.padRight(60, '='));
      return LightRunResult(
        variant: variant,
        ok: true,
        userOpHash: hash,
        transactionHash: status.transactionHash,
      );
    }

    final err = 'status=${status.status}';
    log('❌ $err');
    return LightRunResult(
      variant: variant,
      ok: false,
      userOpHash: hash,
      error: err,
    );
  } catch (e) {
    log('❌ Unexpected error: $e');
    return LightRunResult(variant: variant, ok: false, error: e.toString());
  } finally {
    smartAccountClient.close();
    bundler.close();
    pimlico.close();
    publicClient.close();
  }
}

/// CLI helper: parse `--self-fund` / `-s` and optional `--version=…`.
({bool selfFunded, LightVariant? variant}) parseLightArgs(List<String> args) {
  final selfFunded = args.contains('--self-fund') || args.contains('-s');
  LightVariant? variant;
  for (final a in args) {
    if (a.startsWith('--version=')) {
      variant = parseLightVariant(a.substring('--version='.length));
    } else if (a.startsWith('--variant=')) {
      variant = parseLightVariant(a.substring('--variant='.length));
    }
  }
  for (final a in args) {
    if (a.startsWith('-')) continue;
    variant ??= parseLightVariant(a);
  }
  return (selfFunded: selfFunded, variant: variant);
}

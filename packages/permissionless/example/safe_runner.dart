// Shared Safe smart-account runner used by per-version examples.
//
// Supported combinations (from [SafeVersionAddresses]):
//   - Safe 1.4.1 + EntryPoint v0.6
//   - Safe 1.4.1 + EntryPoint v0.7
//   - Safe 1.5.0 + EntryPoint v0.7
//   - Safe 1.4.1 + EntryPoint v0.7 + ERC-7579
//
// Note: Safe 1.5.0 + ERC-7579 is intentionally unsupported
// (permissionless.js / Dart both reject that combination).

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

/// A concrete Safe configuration matrix cell.
class SafeVariant {
  SafeVariant({
    required this.version,
    required this.entryPointVersion,
    this.erc7579 = false,
    required int saltNonce,
    required this.label,
  }) : saltNonce = BigInt.from(saltNonce);

  final SafeVersion version;
  final EntryPointVersion entryPointVersion;
  final bool erc7579;

  /// Distinct salt so each variant gets its own address under the same owner.
  final BigInt saltNonce;
  final String label;

  String get id => 'safe-${version.value}-ep${entryPointVersion.value}'
      '${erc7579 ? '-7579' : ''}';

  EthereumAddress get entryPointAddress =>
      EntryPointAddresses.fromVersion(entryPointVersion);

  bool get isV06 => entryPointVersion == EntryPointVersion.v06;
}

/// All supported Safe example variants.
final List<SafeVariant> allSafeVariants = [
  SafeVariant(
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v06,
    saltNonce: 14106,
    label: 'Safe 1.4.1 + EntryPoint v0.6',
  ),
  SafeVariant(
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    saltNonce: 14107,
    label: 'Safe 1.4.1 + EntryPoint v0.7',
  ),
  SafeVariant(
    version: SafeVersion.v1_5_0,
    entryPointVersion: EntryPointVersion.v07,
    saltNonce: 15007,
    label: 'Safe 1.5.0 + EntryPoint v0.7',
  ),
  SafeVariant(
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    erc7579: true,
    saltNonce: 1417579,
    label: 'Safe 1.4.1 + EntryPoint v0.7 + ERC-7579',
  ),
];

/// Result of a single Safe variant run.
class SafeRunResult {
  const SafeRunResult({
    required this.variant,
    required this.ok,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });

  final SafeVariant variant;
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

/// Parse a variant selector like `1.4.1`, `1.5.0`, `1.4.1-ep0.6`, `7579`.
SafeVariant? parseSafeVariant(String raw) {
  final s = raw.trim().toLowerCase();
  for (final v in allSafeVariants) {
    if (v.id == s || v.label.toLowerCase() == s) return v;
  }
  // Convenience aliases
  switch (s) {
    case '1.4.1':
    case 'v1.4.1':
    case '1.4.1-ep0.7':
    case 'default':
      return allSafeVariants.firstWhere(
        (v) =>
            v.version == SafeVersion.v1_4_1 &&
            v.entryPointVersion == EntryPointVersion.v07 &&
            !v.erc7579,
      );
    case '1.4.1-ep0.6':
    case '1.4.1-v06':
    case 'ep0.6':
      return allSafeVariants.firstWhere(
        (v) =>
            v.version == SafeVersion.v1_4_1 &&
            v.entryPointVersion == EntryPointVersion.v06,
      );
    case '1.5.0':
    case 'v1.5.0':
      return allSafeVariants.firstWhere(
        (v) => v.version == SafeVersion.v1_5_0,
      );
    case '7579':
    case 'erc7579':
    case '1.4.1-7579':
      return allSafeVariants.firstWhere((v) => v.erc7579);
    default:
      return null;
  }
}

/// Run a sponsored (or self-funded) self-ping UserOp for [variant].
Future<SafeRunResult> runSafeVariant({
  required SafeVariant variant,
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

  final account = createSafeSmartAccount(
    owners: [owner],
    version: variant.version,
    entryPointVersion: variant.entryPointVersion,
    chainId: BigInt.from(11155111), // Sepolia
    saltNonce: variant.saltNonce,
    publicClient: publicClient,
    erc7579LaunchpadAddress:
        variant.erc7579 ? Safe7579Addresses.erc7579LaunchpadAddress : null,
    attesters:
        variant.erc7579 ? [Safe7579Addresses.rhinestoneAttester] : const [],
    attestersThreshold: variant.erc7579 ? 1 : 0,
  );

  final addresses = SafeVersionAddresses.getAddresses(
    variant.version,
    variant.entryPointVersion,
  );

  log('Safe version: ${variant.version.value}');
  log('EntryPoint: ${account.entryPoint.checksummed} ($epLabel)');
  log('ERC-7579: ${account.isErc7579Enabled}');
  if (addresses != null) {
    log('Singleton: ${addresses.safeSingletonAddress.checksummed}');
    log('ProxyFactory: ${addresses.safeProxyFactoryAddress.checksummed}');
    log('4337 Module: ${addresses.safe4337ModuleAddress.checksummed}');
    log('MultiSendCallOnly: ${addresses.multiSendCallOnlyAddress.checksummed}');
  }
  if (variant.erc7579) {
    log(
      'Launchpad: ${Safe7579Addresses.erc7579LaunchpadAddress.checksummed}',
    );
  }

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
        return SafeRunResult(variant: variant, ok: false, error: msg);
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
        return SafeRunResult(variant: variant, ok: false, error: e.message);
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
        return SafeRunResult(variant: variant, ok: false, error: e.message);
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
      return SafeRunResult(
        variant: variant,
        ok: true,
        userOpHash: hash,
        transactionHash: status.transactionHash,
      );
    }

    final err = 'status=${status.status}';
    log('❌ $err');
    return SafeRunResult(
      variant: variant,
      ok: false,
      userOpHash: hash,
      error: err,
    );
  } catch (e) {
    log('❌ Unexpected error: $e');
    return SafeRunResult(variant: variant, ok: false, error: e.toString());
  } finally {
    smartAccountClient.close();
    bundler.close();
    pimlico.close();
    publicClient.close();
  }
}

/// CLI helper: parse `--self-fund` / `-s` and optional `--version=…`.
({bool selfFunded, SafeVariant? variant}) parseSafeArgs(List<String> args) {
  final selfFunded = args.contains('--self-fund') || args.contains('-s');
  SafeVariant? variant;
  for (final a in args) {
    if (a.startsWith('--version=')) {
      variant = parseSafeVariant(a.substring('--version='.length));
    } else if (a.startsWith('--variant=')) {
      variant = parseSafeVariant(a.substring('--variant='.length));
    }
  }
  for (final a in args) {
    if (a.startsWith('-')) continue;
    variant ??= parseSafeVariant(a);
  }
  return (selfFunded: selfFunded, variant: variant);
}

// Shared Thirdweb smart-account runner used by per-version examples.
//
// Supported combinations:
//   - Thirdweb + EntryPoint v0.6 (factoryV06)
//   - Thirdweb + EntryPoint v0.7 (factoryV07)
//
// There is no separate Thirdweb account version enum — EP version selects
// the factory (see [ThirdwebAddresses]).

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

/// A concrete Thirdweb configuration matrix cell.
class ThirdwebVariant {
  const ThirdwebVariant({
    required this.entryPointVersion,
    required this.salt,
    required this.label,
  });

  final EntryPointVersion entryPointVersion;

  /// Distinct salt so each variant gets its own address under the same owner.
  /// Thirdweb salt is bytes (hex string), not a numeric index.
  final String salt;
  final String label;

  String get id => 'thirdweb-ep${entryPointVersion.value}';

  EthereumAddress get entryPointAddress =>
      EntryPointAddresses.fromVersion(entryPointVersion);

  EthereumAddress get factoryAddress =>
      entryPointVersion == EntryPointVersion.v07
          ? ThirdwebAddresses.factoryV07
          : ThirdwebAddresses.factoryV06;

  bool get isV06 => entryPointVersion == EntryPointVersion.v06;
}

/// All supported Thirdweb example variants.
const List<ThirdwebVariant> allThirdwebVariants = [
  ThirdwebVariant(
    entryPointVersion: EntryPointVersion.v06,
    salt: '0x06',
    label: 'Thirdweb + EntryPoint v0.6',
  ),
  ThirdwebVariant(
    entryPointVersion: EntryPointVersion.v07,
    salt: '0x07',
    label: 'Thirdweb + EntryPoint v0.7',
  ),
];

/// Result of a single Thirdweb variant run.
class ThirdwebRunResult {
  const ThirdwebRunResult({
    required this.variant,
    required this.ok,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });

  final ThirdwebVariant variant;
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

/// Parse a selector like `0.6`, `ep0.7`, `v07`.
ThirdwebVariant? parseThirdwebVariant(String raw) {
  final s = raw.trim().toLowerCase();
  for (final v in allThirdwebVariants) {
    if (v.id == s || v.label.toLowerCase() == s) return v;
  }
  switch (s) {
    case '0.6':
    case 'ep0.6':
    case 'v06':
    case 'v0.6':
      return allThirdwebVariants.firstWhere((v) => v.isV06);
    case '0.7':
    case 'ep0.7':
    case 'v07':
    case 'v0.7':
    case 'default':
      return allThirdwebVariants.firstWhere((v) => !v.isV06);
    default:
      return null;
  }
}

/// Run a sponsored (or self-funded) self-ping UserOp for [variant].
Future<ThirdwebRunResult> runThirdwebVariant({
  required ThirdwebVariant variant,
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

  final account = createThirdwebSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    entryPointVersion: variant.entryPointVersion,
    salt: variant.salt,
    publicClient: publicClient,
  );

  log('EntryPoint: ${account.entryPoint.checksummed} ($epLabel)');
  log('Factory: ${variant.factoryAddress.checksummed}');
  log('Salt: ${variant.salt}');

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
        return ThirdwebRunResult(variant: variant, ok: false, error: msg);
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
        return ThirdwebRunResult(variant: variant, ok: false, error: e.message);
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
        return ThirdwebRunResult(variant: variant, ok: false, error: e.message);
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
      return ThirdwebRunResult(
        variant: variant,
        ok: true,
        userOpHash: hash,
        transactionHash: status.transactionHash,
      );
    }

    final err = 'status=${status.status}';
    log('❌ $err');
    return ThirdwebRunResult(
      variant: variant,
      ok: false,
      userOpHash: hash,
      error: err,
    );
  } catch (e) {
    log('❌ Unexpected error: $e');
    return ThirdwebRunResult(variant: variant, ok: false, error: e.toString());
  } finally {
    smartAccountClient.close();
    bundler.close();
    pimlico.close();
    publicClient.close();
  }
}

/// CLI helper: parse `--self-fund` / `-s` and optional `--version=…`.
({bool selfFunded, ThirdwebVariant? variant}) parseThirdwebArgs(
  List<String> args,
) {
  final selfFunded = args.contains('--self-fund') || args.contains('-s');
  ThirdwebVariant? variant;
  for (final a in args) {
    if (a.startsWith('--version=')) {
      variant = parseThirdwebVariant(a.substring('--version='.length));
    } else if (a.startsWith('--variant=')) {
      variant = parseThirdwebVariant(a.substring('--variant='.length));
    }
  }
  for (final a in args) {
    if (a.startsWith('-')) continue;
    variant ??= parseThirdwebVariant(a);
  }
  return (selfFunded: selfFunded, variant: variant);
}

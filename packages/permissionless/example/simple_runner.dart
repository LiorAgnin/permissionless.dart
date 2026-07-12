// Shared Simple Account runner used by per-version examples.
//
// Supported factory-deployed combinations:
//   - Simple + EntryPoint v0.6
//   - Simple + EntryPoint v0.7
//   - Simple + EntryPoint v0.8
//
// EIP-7702 Simple (EOA code delegation) is a separate account type —
// see eip7702_simple_example.dart.

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

/// A concrete Simple Account configuration matrix cell.
class SimpleVariant {
  SimpleVariant({
    required this.entryPointVersion,
    required int salt,
    required this.label,
  }) : salt = BigInt.from(salt);

  final EntryPointVersion entryPointVersion;

  /// Distinct salt so each variant gets its own address under the same owner.
  final BigInt salt;
  final String label;

  String get id => 'simple-ep${entryPointVersion.value}';

  EthereumAddress get entryPointAddress =>
      EntryPointAddresses.fromVersion(entryPointVersion);

  EthereumAddress get factoryAddress =>
      SimpleAccountFactoryAddresses.fromVersion(entryPointVersion);

  bool get isV06 => entryPointVersion == EntryPointVersion.v06;
}

/// All supported factory-deployed Simple example variants.
final List<SimpleVariant> allSimpleVariants = [
  SimpleVariant(
    entryPointVersion: EntryPointVersion.v06,
    salt: 6,
    label: 'Simple Account + EntryPoint v0.6',
  ),
  SimpleVariant(
    entryPointVersion: EntryPointVersion.v07,
    salt: 7,
    label: 'Simple Account + EntryPoint v0.7',
  ),
  SimpleVariant(
    entryPointVersion: EntryPointVersion.v08,
    salt: 8,
    label: 'Simple Account + EntryPoint v0.8',
  ),
];

/// Result of a single Simple variant run.
class SimpleRunResult {
  const SimpleRunResult({
    required this.variant,
    required this.ok,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });

  final SimpleVariant variant;
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

/// Parse a selector like `0.6`, `ep0.7`, `v08`.
SimpleVariant? parseSimpleVariant(String raw) {
  final s = raw.trim().toLowerCase();
  for (final v in allSimpleVariants) {
    if (v.id == s || v.label.toLowerCase() == s) return v;
  }
  switch (s) {
    case '0.6':
    case 'ep0.6':
    case 'v06':
    case 'v0.6':
      return allSimpleVariants.firstWhere(
        (v) => v.entryPointVersion == EntryPointVersion.v06,
      );
    case '0.7':
    case 'ep0.7':
    case 'v07':
    case 'v0.7':
    case 'default':
      return allSimpleVariants.firstWhere(
        (v) => v.entryPointVersion == EntryPointVersion.v07,
      );
    case '0.8':
    case 'ep0.8':
    case 'v08':
    case 'v0.8':
      return allSimpleVariants.firstWhere(
        (v) => v.entryPointVersion == EntryPointVersion.v08,
      );
    default:
      return null;
  }
}

/// Run a sponsored (or self-funded) self-ping UserOp for [variant].
Future<SimpleRunResult> runSimpleVariant({
  required SimpleVariant variant,
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

  final account = createSimpleSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    entryPointVersion: variant.entryPointVersion,
    salt: variant.salt,
    publicClient: publicClient,
  );

  log('EntryPoint: ${account.entryPoint.checksummed} ($epLabel)');
  log('Factory: ${variant.factoryAddress.checksummed}');
  log(
    'Signing: ${switch (variant.entryPointVersion) {
      EntryPointVersion.v06 => 'EIP-191 personal-sign (v0.6 hash)',
      EntryPointVersion.v07 => 'EIP-191 personal-sign (packed hash)',
      EntryPointVersion.v08 => 'EIP-712 PackedUserOperation typed data',
    }}',
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
        return SimpleRunResult(variant: variant, ok: false, error: msg);
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
        return SimpleRunResult(variant: variant, ok: false, error: e.message);
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
      // v0.7 and v0.8 share UserOperationV07 RPC shape
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
        return SimpleRunResult(variant: variant, ok: false, error: e.message);
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
      return SimpleRunResult(
        variant: variant,
        ok: true,
        userOpHash: hash,
        transactionHash: status.transactionHash,
      );
    }

    final err = 'status=${status.status}';
    log('❌ $err');
    return SimpleRunResult(
      variant: variant,
      ok: false,
      userOpHash: hash,
      error: err,
    );
  } catch (e) {
    log('❌ Unexpected error: $e');
    return SimpleRunResult(variant: variant, ok: false, error: e.toString());
  } finally {
    smartAccountClient.close();
    bundler.close();
    pimlico.close();
    publicClient.close();
  }
}

/// CLI helper: parse `--self-fund` / `-s` and optional `--version=…`.
({bool selfFunded, SimpleVariant? variant}) parseSimpleArgs(List<String> args) {
  final selfFunded = args.contains('--self-fund') || args.contains('-s');
  SimpleVariant? variant;
  for (final a in args) {
    if (a.startsWith('--version=')) {
      variant = parseSimpleVariant(a.substring('--version='.length));
    } else if (a.startsWith('--variant=')) {
      variant = parseSimpleVariant(a.substring('--variant='.length));
    }
  }
  for (final a in args) {
    if (a.startsWith('-')) continue;
    variant ??= parseSimpleVariant(a);
  }
  return (selfFunded: selfFunded, variant: variant);
}

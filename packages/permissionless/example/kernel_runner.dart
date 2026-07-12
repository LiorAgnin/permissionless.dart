// Shared Kernel smart-account runner used by per-version examples.
//
// Covers every [KernelVersion] in the SDK (v0.2.1 … v0.3.3).

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

/// Result of a single Kernel version run.
class KernelRunResult {
  const KernelRunResult({
    required this.version,
    required this.ok,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });

  final KernelVersion version;
  final bool ok;
  final String? userOpHash;
  final String? transactionHash;
  final String? error;

  @override
  String toString() {
    if (ok) {
      return 'OK  Kernel ${version.value}'
          '${transactionHash != null ? '  tx=$transactionHash' : ''}';
    }
    return 'FAIL Kernel ${version.value}: $error';
  }
}

/// Stable, version-specific salt so each Kernel version gets its own address
/// under the same owner key (avoids cross-version collisions).
BigInt kernelExampleIndex(KernelVersion version) => switch (version) {
      KernelVersion.v0_2_1 => BigInt.from(201),
      KernelVersion.v0_2_2 => BigInt.from(202),
      KernelVersion.v0_2_3 => BigInt.from(203),
      KernelVersion.v0_2_4 => BigInt.from(204),
      KernelVersion.v0_3_0_beta => BigInt.from(300),
      KernelVersion.v0_3_1 => BigInt.from(301),
      KernelVersion.v0_3_2 => BigInt.from(302),
      KernelVersion.v0_3_3 => BigInt.from(303),
    };

/// Parse a version string like `0.3.1` or `0.3.0-beta` into [KernelVersion].
KernelVersion? parseKernelVersion(String raw) {
  final s = raw.trim().toLowerCase();
  for (final v in KernelVersion.values) {
    if (v.value.toLowerCase() == s) return v;
    // Allow underscored / dotted aliases: 0_2_4, v0.2.4, 0.2.4
    final alias = v.name.replaceFirst('v', '').replaceAll('_', '.');
    if (alias == s || 'v$s' == v.name.replaceAll('_', '.')) return v;
    if (v.name.toLowerCase() == s || v.name.toLowerCase() == 'v$s') return v;
  }
  // Common aliases
  const aliases = {
    '0.2.1': KernelVersion.v0_2_1,
    '0.2.2': KernelVersion.v0_2_2,
    '0.2.3': KernelVersion.v0_2_3,
    '0.2.4': KernelVersion.v0_2_4,
    '0.3.0-beta': KernelVersion.v0_3_0_beta,
    '0.3.0': KernelVersion.v0_3_0_beta,
    '0.3.1': KernelVersion.v0_3_1,
    '0.3.2': KernelVersion.v0_3_2,
    '0.3.3': KernelVersion.v0_3_3,
  };
  return aliases[s];
}

/// Run a sponsored (or self-funded) self-ping UserOp for [version].
///
/// Returns a [KernelRunResult]; does not rethrow bundler/account errors so
/// multi-version runners can continue.
Future<KernelRunResult> runKernelVersion({
  required KernelVersion version,
  bool selfFunded = false,
  bool quiet = false,
}) async {
  void log(String msg) {
    if (!quiet) print(msg);
  }

  final config = ExampleConfig.load();
  final ep = version.isV2 ? EntryPointAddresses.v06 : EntryPointAddresses.v07;
  final epLabel = version.isV2 ? 'v0.6' : 'v0.7';

  log('='.padRight(60, '='));
  log('Kernel ${version.value} Smart Account Example (EntryPoint $epLabel)');
  log('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  log('='.padRight(60, '='));

  final owner = PrivateKeyOwner(config.privateKey);
  log('\nOwner address: ${owner.address.checksummed}');

  final publicClient = createPublicClient(url: config.sepoliaRpcUrl);
  final pimlicoUrl = config.sepoliaPimlicoUrl;

  final account = createKernelSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    version: version,
    index: kernelExampleIndex(version),
    publicClient: publicClient,
  );

  final addresses = KernelVersionAddresses.getAddresses(version);
  log('Kernel version: ${version.value}');
  log('EntryPoint: ${account.entryPoint.checksummed} ($epLabel)');
  log('isV2: ${version.isV2}  usesErc7579: ${version.usesErc7579}  '
      'supportsEip7702: ${version.supportsEip7702}');
  if (addresses != null) {
    log('Implementation: ${addresses.accountImplementation.checksummed}');
    log('Factory: ${addresses.factory.checksummed}');
    if (addresses.metaFactory != null) {
      log('MetaFactory: ${addresses.metaFactory!.checksummed}');
    }
    if (addresses.ecdsaValidator != null) {
      log('ECDSA validator: ${addresses.ecdsaValidator!.checksummed}');
    }
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
        return KernelRunResult(version: version, ok: false, error: msg);
      }
    }

    log('\n--- Building Transaction ---');
    final call = Call(to: accountAddress, value: BigInt.zero, data: '0x');
    log('Transaction: Self-ping (0 ETH to self)');

    log('\n--- Preparing / Signing / Sending ---');

    late final String hash;
    if (version.isV2) {
      // EntryPoint v0.6 path
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
        return KernelRunResult(version: version, ok: false, error: e.message);
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

      // KernelSmartAccount exposes signUserOperationV06 but does not implement
      // SmartAccountV06; sign via the account directly (matches v0.2.4 example).
      final signature = await account.signUserOperationV06(userOp);
      final signed = userOp.copyWith(signature: signature);
      log('Signature length: ${signed.signature.length} chars');

      hash = await smartAccountClient.sendPreparedUserOperationV06(signed);
    } else {
      // EntryPoint v0.7 path
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
        return KernelRunResult(version: version, ok: false, error: e.message);
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
        log(
          'https://sepolia.etherscan.io/tx/${status.transactionHash}',
        );
      }
      log('\n${'='.padRight(60, '=')}');
      log('Example complete! Kernel ${version.value} / EntryPoint $epLabel');
      log('='.padRight(60, '='));
      return KernelRunResult(
        version: version,
        ok: true,
        userOpHash: hash,
        transactionHash: status.transactionHash,
      );
    }

    final err = 'status=${status.status}';
    log('❌ $err');
    return KernelRunResult(
      version: version,
      ok: false,
      userOpHash: hash,
      error: err,
    );
  } catch (e) {
    log('❌ Unexpected error: $e');
    return KernelRunResult(version: version, ok: false, error: e.toString());
  } finally {
    smartAccountClient.close();
    bundler.close();
    pimlico.close();
    publicClient.close();
  }
}

/// CLI helper: parse `--self-fund` / `-s` and optional `--version=…`.
({bool selfFunded, KernelVersion? version, bool all}) parseKernelArgs(
  List<String> args,
) {
  final selfFunded = args.contains('--self-fund') || args.contains('-s');
  final all = args.contains('--all');
  KernelVersion? version;
  for (final a in args) {
    if (a.startsWith('--version=')) {
      version = parseKernelVersion(a.substring('--version='.length));
    } else if (a.startsWith('-v=') || a.startsWith('-v')) {
      final raw = a.contains('=') ? a.split('=').last : null;
      if (raw != null) version = parseKernelVersion(raw);
    }
  }
  // Bare version token (e.g. `dart run … 0.3.2`)
  for (final a in args) {
    if (a.startsWith('-')) continue;
    version ??= parseKernelVersion(a);
  }
  return (selfFunded: selfFunded, version: version, all: all);
}

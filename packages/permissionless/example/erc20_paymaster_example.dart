// Example: Gasless ERC-20 transfer — pay gas with the token itself
//
// This example demonstrates sending an ERC-20 transfer where the gas fee is
// paid in the same ERC-20 token via Pimlico's ERC-20 paymaster. The sender
// needs NO ETH at all:
// 1. Creating an EIP-7702 Simple account (account address == owner's EOA)
// 2. Preparing the op with prepareUserOperationForErc20Paymaster
// 3. Automatic first-time delegation: if the EOA is not yet delegated, the
//    helper returns an EIP-7702 authorization and the delegation is installed
//    by this very same transaction
// 4. Signing and sending — one code path for the first and all subsequent ops
//
// USAGE:
//   dart run example/erc20_paymaster_example.dart
//
// Reads PIMLICO_API_KEY / TEST_PRIVATE_KEY / SEPOLIA_RPC_URL from the
// environment or a nearby `.env` file (see example_config.dart).
//
// REQUIREMENTS:
// - A bundler/paymaster that supports EntryPoint v0.8 and EIP-7702 (Pimlico)
// - A chain with EIP-7702 enabled (Sepolia after the Prague upgrade)
// - The sender EOA holds enough of the token for transfer + gas
//   (or use Erc20PaymasterConfig(balanceOverride: true) on a testnet)
//
// KEY FEATURES:
// - No ETH needed on the sender: gas is paid in the ERC-20 token
// - Exact-amount approval for the paymaster is injected automatically
//   (skipped when a sufficient allowance is already in place)
// - USDT-on-mainnet quirk (reset approval to 0 first) is handled internally
// - First-time delegation and subsequent transfers share the same code path

import 'package:permissionless/permissionless.dart';

import 'example_config.dart';

void main(List<String> args) async {
  print('='.padRight(60, '='));
  print('Gasless ERC-20 Transfer (ERC-20 Paymaster + EIP-7702)');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Configuration
  // ================================================================

  final config = ExampleConfig.load();
  const chainId = 11155111; // Sepolia
  final rpcUrl = config.sepoliaRpcUrl;
  final pimlicoUrl = config.sepoliaPimlicoUrl;

  // The ERC-20 token used BOTH for the transfer and for the gas payment.
  // Sepolia USDC (6 decimals). Must be supported by the Pimlico paymaster —
  // check with pimlico.getTokenQuotes([token]).
  final token =
      EthereumAddress.fromHex('0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238');
  const tokenDecimals = 6;

  // Recipient and amount of the main transfer (in the token's base units).
  final recipient =
      EthereumAddress.fromHex('0x57Be4787b25ed040b69677B57D7Db565e174Aa97');
  final amount = BigInt.from(1000000); // 1.000000 USDC

  // NOTE: Use a fresh key without an existing EIP-7702 delegation to a
  // different delegate (check eth_getCode: a 0xef0100... prefix means an
  // active delegation).
  final owner = PrivateKeyEip7702Owner(config.privateKey);

  // ================================================================
  // 1. Create the EIP-7702 account and clients
  // ================================================================
  //
  // EIP-7702: the account address IS the owner's EOA address. No new address —
  // code is delegated via a signed authorization instead of a factory deploy.

  final publicClient = createPublicClient(url: rpcUrl);

  final account = createEip7702SimpleSmartAccount(
    owner: owner,
    chainId: BigInt.from(chainId),
    publicClient: publicClient,
  );

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: account.entryPoint,
  );

  final paymaster = createPaymasterClient(url: pimlicoUrl);

  final client = SmartAccountClient(
    account: account,
    bundler: pimlico,
    publicClient: publicClient, // required for EIP-7702 delegation checks
    paymaster: paymaster, // required for the ERC-20 paymaster helper
  );

  final accountAddress = await account.getAddress();
  print('\nSender (EOA == account): ${accountAddress.checksummed}');
  print('Recipient:               ${recipient.checksummed}');
  print('Token:                   ${token.checksummed}');

  // Whether the delegation is already active. Informational only — the
  // helper detects this itself and handles both cases transparently.
  final isDelegated = await publicClient.isDeployed(accountAddress);
  print(
    'Delegation active:       $isDelegated'
    '${isDelegated ? '' : ' (will be installed by this transaction)'}',
  );

  try {
    // ==============================================================
    // 2. Prepare the gasless op with the ERC-20 paymaster helper
    // ==============================================================
    //
    // One call replaces the whole manual flow: token quote → dummy approval
    // for estimation → maxCostInToken math → exact-amount approval injection
    // (skipped if the current allowance suffices) → final paymaster data.
    //
    // If the EOA is not delegated yet, the helper also creates and returns
    // the EIP-7702 authorization (result.authorization) — nothing extra to do.
    //
    // You can batch more calls here (e.g. several transfers) — the helper
    // injects the gas approval in front of YOUR calls.
    //
    // NOTE: an unsupported token makes the helper throw ArgumentError —
    // check support upfront with pimlico.getTokenQuotes([token]).

    final gasPrices = await pimlico.getUserOperationGasPrice();

    final result = await prepareUserOperationForErc20Paymaster(
      smartAccountClient: client,
      pimlicoClient: pimlico,
      token: token,
      calls: [
        encodeErc20Transfer(token: token, to: recipient, amount: amount),
      ],
      maxFeePerGas: gasPrices.fast.maxFeePerGas,
      maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
      // On a testnet without a real token balance you can simulate one for
      // gas estimation: Erc20PaymasterConfig(balanceOverride: true).
    );

    String fmt(BigInt raw) {
      final unit = BigInt.from(10).pow(tokenDecimals);
      final frac = (raw % unit).toString().padLeft(tokenDecimals, '0');
      return '${raw ~/ unit}.$frac';
    }

    print('\n--- Cost Breakdown (in token) ---');
    print('Transfer to recipient:  ${fmt(amount)}');
    print('Max gas cost (token):   ${fmt(result.maxCostInToken)}');
    print('Total (max):            ${fmt(amount + result.maxCostInToken)}');
    print('Approval injected:      ${result.approvalInjected}');
    print(
      'First-time delegation:  ${result.needsAuthorization}'
      '${result.needsAuthorization ? ' (authorization attached)' : ''}',
    );

    // ==============================================================
    // 3. Sign and send — one path for the first and subsequent ops
    // ==============================================================
    //
    // Pass result.authorization as-is:
    // - non-null (first 7702 op): the bundler receives it as the
    //   `eip7702Auth` field and the delegation is installed on-chain
    // - null (already delegated): standard submission

    print('\n--- Signing and Sending ---');
    final signedOp = await client.signUserOperation(result.userOperation);
    final hash = await client.sendPreparedUserOperation(
      signedOp,
      authorization: result.authorization,
    );
    print('UserOperation hash: $hash');

    // ==============================================================
    // 4. Wait for confirmation
    // ==============================================================

    print('\n--- Waiting for Confirmation ---');
    final status = await pimlico.waitForUserOperationStatus(
      hash,
      timeout: const Duration(seconds: 90),
    );

    print('Status: ${status.status}');
    if (status.transactionHash != null) {
      print('Transaction hash: ${status.transactionHash}');
      print('View on Etherscan:');
      print('  https://sepolia.etherscan.io/tx/${status.transactionHash}');
    }
  } on BundlerRpcError catch (e) {
    print('\nBundler/paymaster error: ${e.message}');
    print('\nThis may be because:');
    print('  - The bundler does not support EntryPoint v0.8 / EIP-7702');
    print('  - The sender does not hold enough of the token');
    print('    (transfer amount + max gas cost)');
    print('  - The paymaster does not support this token on this chain');
  } finally {
    client.close();
    pimlico.close();
    publicClient.close();
  }

  print('\n${'='.padRight(60, '=')}');
  print('Key takeaways:');
  print('  - Sender needs ZERO ETH: gas is paid in the ERC-20 token');
  print('  - One helper call prepares approval + paymaster data');
  print('  - First-time 7702 delegation is handled by the same code path');
  print('  - Send via sendPreparedUserOperation(op, authorization: ...)');
  print('='.padRight(60, '='));
}

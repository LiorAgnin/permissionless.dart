// Example: Creating and using a legacy Biconomy smart account with permissionless.dart
//
// ⚠️  DEPRECATION NOTICE: Biconomy Smart Account v2 is deprecated!
// For new projects, use NexusSmartAccount instead - see nexus_example.dart
//
// This example is provided for users who need to interact with existing
// Biconomy v2 accounts that use EntryPoint v0.6.
//
// This example demonstrates:
// 1. Creating a legacy Biconomy smart account (EntryPoint v0.6)
// 2. Using SmartAccountClient to prepare, sign, and send v0.6 UserOperations
// 3. Both sponsored (Pimlico paymaster) and self-funded modes
//
// USAGE:
//   dart run example/biconomy_example.dart              # Sponsored (free gas)
//   dart run example/biconomy_example.dart --self-fund  # Self-funded (requires ETH)
//
// REQUIREMENTS:
// - For sponsored mode: Just run it! Pimlico sponsors testnet transactions.
// - For self-funded mode: Send ~0.01 Sepolia ETH to the account address.

// ignore_for_file: deprecated_member_use_from_same_package

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('Legacy Biconomy Smart Account Example (EntryPoint v0.6)');
  print('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('');
  print('⚠️  WARNING: Biconomy v2 is DEPRECATED!');
  print('   For new projects, use NexusSmartAccount instead.');
  print('   See: example/nexus_example.dart');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Create an owner from a private key
  // ================================================================
  //
  // WARNING: Never hardcode private keys in production!
  // This is a well-known test key from Foundry/Hardhat for demonstration.
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  final owner = PrivateKeyOwner(testPrivateKey);
  print('\nOwner address: ${owner.address.checksummed}');

  // ================================================================
  // 1. Create Public Client and Biconomy Smart Account
  // ================================================================
  //
  // Legacy Biconomy accounts use:
  // - EntryPoint v0.6 (older standard)
  // - ECDSA Ownership Module for signature validation
  // - Custom execute functions (execute_ncC, executeBatch_y6U)

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createBiconomySmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    index: BigInt.zero,
    publicClient: publicClient, // For address computation
  );

  print('EntryPoint: ${account.entryPoint.checksummed} (v0.6)');

  // ================================================================
  // 2. Get Account Address
  // ================================================================

  final accountAddress = await account.getAddress();
  final isDeployed = await publicClient.isDeployed(accountAddress);

  print(
    'Biconomy Account: ${accountAddress.checksummed} ${isDeployed ? "(already deployed)" : "(will be deployed)"}',
  );

  // ================================================================
  // 3. Create Clients
  // ================================================================

  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

  final bundler = createBundlerClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v06, // v0.6 for Biconomy
  );

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v06,
  );

  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: bundler,
    paymaster: paymaster,
  );

  // ================================================================
  // 4. Check Account Status
  // ================================================================

  print('\n--- Account Status ---');

  final gasPrices = await pimlico.getUserOperationGasPrice();
  print('Gas prices - Fast: ${gasPrices.fast.maxFeePerGas} wei');

  // Fetch the current nonce from the EntryPoint
  final nonce = await publicClient.getAccountNonce(
    accountAddress,
    EntryPointAddresses.v06, // v0.6
  );
  print('Current nonce: $nonce');

  if (selfFunded) {
    final balance = await publicClient.getBalance(accountAddress);
    final balanceEth = balance / BigInt.from(10).pow(18);
    print('Balance: $balanceEth ETH');

    if (balance == BigInt.zero) {
      print('\n⚠️  Account has no balance!');
      print('For self-funded mode, send ~0.01 Sepolia ETH to:');
      print('  ${accountAddress.checksummed}');
      return;
    }
  }

  // ================================================================
  // 5. Build Transaction
  // ================================================================

  print('\n--- Building Transaction ---');

  // Send a "ping" transaction to self
  final call = Call(
    to: accountAddress,
    value: BigInt.zero,
    data: '0x',
  );

  print('Transaction: Self-ping (0 ETH to self)');

  // ================================================================
  // 6. Prepare UserOperation
  // ================================================================

  print('\n--- Preparing UserOperation ---');

  late final UserOperationV06 userOp;
  try {
    userOp = await smartAccountClient.prepareUserOperationV06(
      calls: [call],
      maxFeePerGas: gasPrices.fast.maxFeePerGas,
      maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
      sender: accountAddress,
      nonce: nonce,
      includeFactoryData: !isDeployed,
    );
  } on BundlerRpcError catch (e) {
    if (e.message.contains('AA') || e.message.contains('initCode')) {
      print('\n⚠️  UserOperation preparation failed!');
      print('Error: ${e.message}');

      if (selfFunded) {
        print('\nFor self-funded mode, send ~0.01 Sepolia ETH to:');
        print('  ${accountAddress.checksummed}');
      } else {
        print('\nSponsorship may have failed. Check:');
        print('  - API key is valid');
        print('  - Pimlico has sponsorship enabled for this chain');
      }
      return;
    }
    rethrow;
  }

  print('Sender: ${userOp.sender.checksummed}');
  print('Nonce: ${userOp.nonce}');
  print('Call gas limit: ${userOp.callGasLimit}');
  print('Verification gas limit: ${userOp.verificationGasLimit}');

  if (userOp.paymasterAndData != '0x' && userOp.paymasterAndData.length > 2) {
    // Extract paymaster address from paymasterAndData (first 20 bytes)
    final paymasterAddress = EthAddress(
      '0x${userOp.paymasterAndData.substring(2, 42)}',
    );
    print('Paymaster: ${paymasterAddress.checksummed} (SPONSORED)');
  } else {
    print('Paymaster: None (SELF-FUNDED)');
  }

  // ================================================================
  // 7. Sign and Send
  // ================================================================

  print('\n--- Signing and Sending ---');

  final signedUserOp = await smartAccountClient.signUserOperationV06(userOp);
  print('Signature length: ${signedUserOp.signature.length} chars');

  final hash =
      await smartAccountClient.sendPreparedUserOperationV06(signedUserOp);
  print('UserOperation hash: $hash');

  // ================================================================
  // 8. Wait for Receipt
  // ================================================================

  print('\n--- Waiting for Confirmation ---');
  print('(This may take 10-30 seconds...)');

  final status = await pimlico.waitForUserOperationStatus(
    hash,
    timeout: const Duration(seconds: 60),
  );

  print('\n--- Result ---');
  print('Status: ${status.status}');

  if (status.isSuccess) {
    print('✅ Transaction successful!');
    print('Transaction hash: ${status.transactionHash}');
    print('\nView on Etherscan:');
    print('  https://sepolia.etherscan.io/tx/${status.transactionHash}');
  } else if (status.status == 'included') {
    print('✅ Transaction included!');
    if (status.transactionHash != null) {
      print('Transaction hash: ${status.transactionHash}');
      print('\nView on Etherscan:');
      print('  https://sepolia.etherscan.io/tx/${status.transactionHash}');
    }
  } else if (status.isFailed) {
    print('❌ Transaction failed: ${status.status}');
  } else {
    print('⏳ Transaction still pending: ${status.status}');
  }

  print('\n${'='.padRight(60, '=')}');
  print('Example complete!');
  print('');
  print('Account type: Legacy Biconomy v2 (DEPRECATED)');
  print('EntryPoint: v0.6');
  print('Mode: ${selfFunded ? "Self-funded" : "Sponsored by Pimlico"}');
  print('');
  print('⚠️  REMINDER: For new projects, use NexusSmartAccount instead!');
  print('   It uses EntryPoint v0.7 and ERC-7579 modular architecture.');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  bundler.close();
  pimlico.close();
  publicClient.close();
}

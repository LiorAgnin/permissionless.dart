// Example: Creating and using a Biconomy Nexus account with permissionless.dart
//
// This example demonstrates:
// 1. Creating a Nexus smart account (Biconomy's ERC-7579 modular account)
// 2. Sending a real UserOperation on Base Sepolia testnet
// 3. Both sponsored (Pimlico paymaster) and self-funded modes
//
// USAGE:
//   dart run example/nexus_example.dart              # Sponsored (free gas)
//   dart run example/nexus_example.dart --self-fund  # Self-funded (requires ETH)
//
// REQUIREMENTS:
// - For sponsored mode: Just run it! Pimlico sponsors testnet transactions.
// - For self-funded mode: Send ~0.01 Base Sepolia ETH to the account address.

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('Biconomy Nexus Smart Account Example (Base Sepolia)');
  print('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
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
  // 1. Create Clients and Nexus Smart Account
  // ================================================================
  //
  // Nexus is Biconomy's next-generation ERC-7579 modular smart account.
  // Key features:
  // - ERC-7579 modular architecture
  // - K1 validator for ECDSA signature validation
  // - EntryPoint v0.7 support

  // Create public client first - needed for account address computation
  const rpcUrl = 'https://base-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createNexusSmartAccount(
    owner: owner,
    chainId: BigInt.from(84532), // Base Sepolia
    index: BigInt.zero, // Use default index
    publicClient: publicClient, // Pass client for address computation
  );

  print('EntryPoint: ${account.entryPoint.checksummed}');

  // ================================================================
  // 2. Get Account Address
  // ================================================================

  // Get the account address (computed via RPC and cached)
  final accountAddress = await account.getAddress();
  final isDeployed = await publicClient.isDeployed(accountAddress);

  print(
    'Nexus Account: ${accountAddress.checksummed} ${isDeployed ? "(already deployed)" : "(will be deployed)"}',
  );

  // ================================================================
  // 3. Create Clients
  // ================================================================

  const pimlicoUrl =
      'https://api.pimlico.io/v2/base-sepolia/rpc?apikey=YOUR_KEY';

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v07,
  );

  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: pimlico,
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
    EntryPointAddresses.v07,
    nonceKey: account.nonceKey,
  );
  print('Current nonce: $nonce');

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

  late final UserOperationV07 userOp;
  try {
    userOp = await smartAccountClient.prepareUserOperation(
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
        print('\nFor self-funded mode, send ~0.01 Base Sepolia ETH to:');
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

  if (userOp.paymaster != null) {
    print('Paymaster: ${userOp.paymaster!.checksummed} (SPONSORED)');
  } else {
    print('Paymaster: None (SELF-FUNDED)');
  }

  // ================================================================
  // 7. Sign and Send
  // ================================================================

  print('\n--- Signing and Sending ---');

  final signedUserOp = await smartAccountClient.signUserOperation(userOp);
  print('Signature length: ${signedUserOp.signature.length} chars');

  final hash = await smartAccountClient.sendPreparedUserOperation(signedUserOp);
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
    print('\nView on Basescan:');
    print('  https://sepolia.basescan.org/tx/${status.transactionHash}');
  } else if (status.status == 'included') {
    print('✅ Transaction included!');
    if (status.transactionHash != null) {
      print('Transaction hash: ${status.transactionHash}');
      print('\nView on Basescan:');
      print('  https://sepolia.basescan.org/tx/${status.transactionHash}');
    }
  } else if (status.isFailed) {
    print('❌ Transaction failed: ${status.status}');
  } else {
    print('⏳ Transaction still pending: ${status.status}');
  }

  print('\n${'='.padRight(60, '=')}');
  print('Example complete!');
  print('Account type: Biconomy Nexus');
  print('Mode: ${selfFunded ? "Self-funded" : "Sponsored by Pimlico"}');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

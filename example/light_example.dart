// Example: Creating and using an Alchemy Light Account with permissionless.dart
//
// This example demonstrates:
// 1. Creating a Light Account (Alchemy's gas-efficient smart account)
// 2. Sending a real UserOperation on Sepolia testnet
// 3. Both sponsored (Pimlico paymaster) and self-funded modes
//
// USAGE:
//   dart run example/light_example.dart              # Sponsored (free gas)
//   dart run example/light_example.dart --self-fund  # Self-funded (requires ETH)
//
// REQUIREMENTS:
// - For sponsored mode: Just run it! Pimlico sponsors testnet transactions.
// - For self-funded mode: Send ~0.01 Sepolia ETH to the account address.

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('Light Account Example');
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
  // 1. Create Clients and Light Account (v2.0.0)
  // ================================================================
  //
  // Light Account is Alchemy's gas-efficient smart account.
  // Key features:
  // - Low gas overhead compared to other implementations
  // - EIP-1271 signature validation with LightAccountMessage wrapper
  // - Version 2.0.0 uses signature type prefix

  // Create public client first - needed for account address computation
  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createLightSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    entryPointVersion: EntryPointVersion.v07,
    version: LightAccountVersion.v200, // Latest version
    salt: BigInt.zero,
    publicClient: publicClient, // Pass client for address computation
  );

  print('Light Account version: ${account.version.version}');

  // ================================================================
  // 2. Get Account Address
  // ================================================================

  // Get the account address (computed via RPC and cached)
  final accountAddress = await account.getAddress();
  final isDeployed = await publicClient.isDeployed(accountAddress);

  print(
    'Light Account: ${accountAddress.checksummed} ${isDeployed ? "(already deployed)" : "(will be deployed)"}',
  );

  // ================================================================
  // 3. Create Clients
  // ================================================================

  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

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
  print('Account type: Light Account ${account.version.version}');
  print('Mode: ${selfFunded ? "Self-funded" : "Sponsored by Pimlico"}');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

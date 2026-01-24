// Example: Creating and using a Trust (Barz) smart account with permissionless.dart
//
// This example demonstrates:
// 1. Creating a Trust smart account (Trust Wallet's Barz implementation)
// 2. Sending a real UserOperation on Sepolia testnet
// 3. Both sponsored (Pimlico paymaster) and self-funded modes
//
// USAGE:
//   dart run example/trust_example.dart              # Sponsored (free gas)
//   dart run example/trust_example.dart --self-fund  # Self-funded (requires ETH)
//
// REQUIREMENTS:
// - For sponsored mode: Just run it! Pimlico sponsors testnet transactions.
// - For self-funded mode: Send ~0.01 Sepolia ETH to the account address.

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('Trust (Barz) Smart Account Example (EntryPoint v0.6)');
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
  // 1. Create Public Client and Trust Smart Account (Barz)
  // ================================================================
  //
  // Trust Wallet's Barz uses a diamond-based architecture with
  // verification facets (Secp256k1). Only supports EntryPoint v0.6.

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  var account = createTrustSmartAccount(
    owner: owner,
    chainId: BigInt.from(11155111), // Sepolia
    index: BigInt.from(2024), // Fresh index for this example
  );

  print('Account type: Trust (Barz) - Diamond Proxy');
  print('EntryPoint version: v0.6');

  // ================================================================
  // 2. Get Account Address
  // ================================================================
  //
  // For production reliability, use getSenderAddress to verify
  // the counterfactual address against the factory.

  // Get initCode first for address resolution
  final initCode = await account.getInitCode();

  // Resolve accurate address via EntryPoint simulation
  EthereumAddress accountAddress;
  try {
    accountAddress = await publicClient.getSenderAddress(
      initCode: initCode,
      entryPoint: EntryPointAddresses.v06,
    );
    print('Account address (on-chain): ${accountAddress.checksummed}');

    // Recreate account with verified address
    account = createTrustSmartAccount(
      owner: owner,
      chainId: BigInt.from(11155111),
      index: BigInt.from(2024),
      address: accountAddress,
    );
  } catch (e) {
    print('getSenderAddress error: $e');
    accountAddress = await account.getAddress();
    print('Using computed address: ${accountAddress.checksummed}');
  }

  final isDeployed = await publicClient.isDeployed(accountAddress);
  print(
    'Trust Account: ${accountAddress.checksummed} ${isDeployed ? "(deployed)" : "(will be deployed)"}',
  );
  print('EntryPoint: ${account.entryPoint.checksummed}');

  // ================================================================
  // 3. Create Clients
  // ================================================================

  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v06,
  );

  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: pimlico,
    publicClient: publicClient,
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
    EntryPointAddresses.v06,
    nonceKey: account.nonceKey,
  );
  print('Current nonce: $nonce');

  // ================================================================
  // 5. Build Transaction
  // ================================================================

  print('\n--- Building Transaction ---');

  // Send a "ping" transaction to self (proves account works)
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
    );
  } on BundlerRpcError catch (e) {
    if (e.message.contains('AA') || e.message.contains('initCode')) {
      print('\n⚠️  UserOperation preparation failed!');
      print('Error: ${e.message}');
      print('\nSponsorship may have failed. Check:');
      print('  - API key is valid');
      print('  - Pimlico has sponsorship enabled for this chain');
      return;
    }
    rethrow;
  }

  print('Sender: ${userOp.sender.checksummed}');
  print('Nonce: ${userOp.nonce}');
  print('Call gas limit: ${userOp.callGasLimit}');
  print('Verification gas limit: ${userOp.verificationGasLimit}');

  if (userOp.paymasterAndData != '0x' && userOp.paymasterAndData.length > 2) {
    final paymasterAddress = EthereumAddress.fromHex(
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
  print('Signature length: ${(signedUserOp.signature.length - 2) ~/ 2} bytes');

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
  print('Account type: Trust (Barz) - Diamond Proxy');
  print('EntryPoint: v0.6');
  print('Mode: ${selfFunded ? "Self-funded" : "Sponsored by Pimlico"}');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

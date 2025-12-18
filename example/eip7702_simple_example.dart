// Example: Creating and using an EIP-7702 Simple smart account
//
// This example demonstrates the EIP-7702 smart account flow:
// 1. Creating an EIP-7702 Simple account (EOA with code delegation)
// 2. Understanding that account address = owner's EOA address
// 3. Using SmartAccountClient for automatic authorization handling
// 4. Sending a UserOperation via bundler
//
// USAGE:
//   dart run example/eip7702_simple_example.dart              # Sponsored
//   dart run example/eip7702_simple_example.dart --self-fund  # Self-funded
//
// REQUIREMENTS:
// - A bundler that supports EIP-7702 (EntryPoint v0.8)
// - A chain with EIP-7702 enabled (Sepolia after Prague upgrade)
//
// KEY FEATURES:
// - SmartAccountClient automatically handles EIP-7702 authorization
// - No manual authorization creation needed
// - Authorization-aware gas estimation is automatic
// - First-time delegation vs subsequent transactions handled transparently

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('EIP-7702 Simple Smart Account Example');
  print('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Configuration
  // ================================================================
  //
  // EIP-7702 requires:
  // - A chain that supports EIP-7702 (Prague upgrade)
  // - A bundler that supports EntryPoint v0.8

  const chainId = 11155111; // Sepolia
  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';

  // NOTE: Replace with a bundler URL that supports EntryPoint v0.8
  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

  // ================================================================
  // SETUP: Create an owner from a private key
  // ================================================================
  //
  // WARNING: Never hardcode private keys in production!
  //
  // NOTE: Well-known Hardhat/Foundry test keys have existing EIP-7702
  // delegations to incompatible contracts on Sepolia. If you see AA24
  // signature errors, check if your address has an existing delegation
  // using eth_getCode - a 0xef0100... prefix indicates active delegation.
  //
  // For testing, generate a fresh random key:
  //   dart -e "import 'dart:math'; print('0x' + List.generate(64, (_) => Random.secure().nextInt(16).toRadixString(16)).join());"
  //
  // This key is for example purposes only (randomly generated):
  // NOTE: Use a fresh key without existing EIP-7702 delegation
  const testPrivateKey =
      '0xa1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';

  final owner = PrivateKeyEip7702Owner(testPrivateKey);
  print('\nOwner address: ${owner.address.checksummed}');

  // ================================================================
  // 1. Create Clients and EIP-7702 Simple Smart Account
  // ================================================================
  //
  // EIP-7702 accounts are unique because:
  // - The account address IS the owner's EOA address
  // - No factory deployment needed
  // - Code is delegated via signed authorization
  // - Uses EntryPoint v0.8

  // Create public client first - needed for EIP-7702 delegation checks
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createEip7702SimpleSmartAccount(
    owner: owner,
    chainId: BigInt.from(chainId),
    publicClient: publicClient,
  );

  // ================================================================
  // 2. Create Bundler and SmartAccountClient
  // ================================================================
  //
  // SmartAccountClient with publicClient automatically handles:
  // - Checking if delegation is active
  // - Creating authorization when needed
  // - Using authorization-aware gas estimation
  // - Sending with authorization for first-time setup

  final bundler = createBundlerClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v08,
  );

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v08,
  );

  // Paymaster for sponsored transactions (optional)
  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  // Create SmartAccountClient with publicClient for EIP-7702 support
  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: bundler,
    publicClient: publicClient,
    paymaster: paymaster,
  );

  // ================================================================
  // 3. Get Account Information
  // ================================================================
  //
  // For EIP-7702, the account address is the same as the owner's EOA address.
  // No getSenderAddress needed!

  final accountAddress = await account.getAddress();
  print('Account address: ${accountAddress.checksummed}');
  print('Owner address:   ${owner.address.checksummed}');
  print(
    'Addresses match: ${accountAddress.hex == owner.address.hex ? "YES" : "NO"}',
  );

  // ================================================================
  // 4. Check Account Status
  // ================================================================

  print('\n--- Account Status ---');

  // Check if there's any code at the address
  // For a fresh EOA, this will be false
  // After EIP-7702 authorization, this may show delegated code
  final isDeployed = await publicClient.isDeployed(accountAddress);
  print('Has code (delegation active): $isDeployed');

  // Get balance
  final balance = await publicClient.getBalance(accountAddress);
  final balanceEth = balance / BigInt.from(10).pow(18);
  print('Balance: $balanceEth ETH');

  // Get the EntryPoint nonce for the smart account
  final nonce = await publicClient.getAccountNonce(
    accountAddress,
    EntryPointAddresses.v08,
  );
  print('EntryPoint nonce: $nonce');

  // Get gas prices
  final gasPrices = await pimlico.getUserOperationGasPrice();
  print('Gas prices - Fast: ${gasPrices.fast.maxFeePerGas} wei');

  // ================================================================
  // 5. Build Transaction
  // ================================================================
  //
  // We'll send a simple 0-value transaction to ourselves.
  // This is a "ping" transaction that proves the account works.

  print('\n--- Building Transaction ---');

  final call = Call(
    to: accountAddress, // Send to self
    value: BigInt.zero, // No ETH transfer
    data: '0x', // No calldata
  );

  print('Transaction: Self-ping (0 ETH to self)');

  // ================================================================
  // 6. Prepare UserOperation
  // ================================================================
  //
  // SmartAccountClient handles all the EIP-7702 complexity:
  // - Detects if authorization is needed (delegation not active)
  // - Creates authorization with correct EOA nonce
  // - Uses 0x7702 factory marker for first-time setup
  // - Calls authorization-aware gas estimation
  // - Applies paymaster if configured

  print('\n--- Preparing UserOperation ---');

  late final PreparedUserOperation prepared;
  try {
    // Use prepareUserOperationWithAuth to get both userOp and authorization
    prepared = await smartAccountClient.prepareUserOperationWithAuth(
      calls: [call],
      maxFeePerGas: gasPrices.fast.maxFeePerGas,
      maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
      nonce: nonce,
    );
  } on BundlerRpcError catch (e) {
    print('\nUserOperation preparation failed: ${e.message}');
    print('\nThis likely means:');
    print('  - The bundler does not support EntryPoint v0.8');
    print('  - The bundler does not support EIP-7702 authorization');
    print('\nFor EIP-7702 to work, you may need:');
    print('  - A bundler with explicit EIP-7702/v0.8 support');
    print('  - A chain with EIP-7702 enabled');

    smartAccountClient.close();
    pimlico.close();
    publicClient.close();
    return;
  }

  final userOp = prepared.userOp;
  print('Sender: ${userOp.sender.checksummed}');
  print('Nonce: ${userOp.nonce}');
  print('Call gas limit: ${userOp.callGasLimit}');
  print('Verification gas limit: ${userOp.verificationGasLimit}');
  print('Needs authorization: ${prepared.needsAuthorization}');

  if (userOp.paymaster != null) {
    print('Paymaster: ${userOp.paymaster!.checksummed} (SPONSORED)');
  } else {
    print('Paymaster: None (SELF-FUNDED)');
  }

  // ================================================================
  // 7. Sign and Send
  // ================================================================
  //
  // SmartAccountClient automatically includes authorization when sending
  // if delegation is not yet active.

  print('\n--- Signing and Sending ---');

  final signedOp = await smartAccountClient.signUserOperation(userOp);
  print('Signature: ${signedOp.signature.substring(0, 30)}...');

  String hash;
  try {
    // Use sendPreparedUserOperationWithAuth to include EIP-7702 authorization
    hash = await smartAccountClient.sendPreparedUserOperationWithAuth(
      signedOp,
      prepared.authorization,
    );
    print('UserOperation hash: $hash');
  } on BundlerRpcError catch (e) {
    print('\nSend failed: ${e.message}');
    if (e.data != null) {
      print('Error data: ${e.data}');
    }
    print('\nThis may be because:');
    print('  - The bundler does not support EIP-7702 authorization list');
    print('  - Insufficient balance for self-funded transaction');
    print('  - Sponsorship policy rejected the transaction');

    smartAccountClient.close();
    pimlico.close();
    publicClient.close();
    return;
  }

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
    print('Transaction successful!');
    print('Transaction hash: ${status.transactionHash}');
    print('\nView on Etherscan:');
    print('  https://sepolia.etherscan.io/tx/${status.transactionHash}');
  } else if (status.status == 'included') {
    print('Transaction included!');
    if (status.transactionHash != null) {
      print('Transaction hash: ${status.transactionHash}');
      print('\nView on Etherscan:');
      print('  https://sepolia.etherscan.io/tx/${status.transactionHash}');
    }
  } else if (status.isFailed) {
    print('Transaction failed: ${status.status}');
  } else {
    print('Transaction still pending: ${status.status}');
  }

  print('\n${'='.padRight(60, '=')}');
  print('Example complete!');
  print('');
  print('Key takeaways:');
  print('  - Account address = Owner\'s EOA address');
  print('  - SmartAccountClient handles authorization automatically');
  print('  - Uses EntryPoint v0.8');
  print('  - Uses EIP-712 typed data signing');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

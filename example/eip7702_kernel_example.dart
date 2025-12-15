// Example: Creating and using an EIP-7702 Kernel smart account
//
// This example demonstrates the EIP-7702 Kernel account flow:
// 1. Creating an EIP-7702 Kernel account (EOA with code delegation)
// 2. Understanding that account address = owner's EOA address
// 3. Using SmartAccountClient for automatic authorization handling
// 4. Sending a UserOperation via bundler
//
// USAGE:
//   dart run example/eip7702_kernel_example.dart              # Sponsored
//   dart run example/eip7702_kernel_example.dart --self-fund  # Self-funded
//
// REQUIREMENTS:
// - A bundler that supports EIP-7702 with EntryPoint v0.7
// - A chain with EIP-7702 enabled (Sepolia after Prague upgrade)
//
// KEY DIFFERENCES FROM EIP-7702 SIMPLE ACCOUNT:
// - Uses EntryPoint v0.7 (not v0.8)
// - Uses hash-based UserOp signing (not EIP-712 typed data)
// - Uses Kernel v0.3.3 account logic (ERC-7579 compliant)
// - Message signing uses Kernel's EIP-712 domain wrapper
//
// NOTE: EIP-7702 bundler support for v0.7 is limited. Most bundlers implement
// EIP-7702 primarily for EntryPoint v0.8.

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('EIP-7702 Kernel Smart Account Example');
  print('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Configuration
  // ================================================================
  //
  // EIP-7702 Kernel requires:
  // - A chain that supports EIP-7702 (Prague upgrade)
  // - A bundler that supports EntryPoint v0.7 with EIP-7702

  const chainId = 11155111; // Sepolia
  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';

  // Pimlico bundler URL
  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

  // ================================================================
  // SETUP: Create an owner from a private key
  // ================================================================
  //
  // WARNING: Never hardcode private keys in production!
  //
  // For testing, generate a fresh random key:
  //   dart -e "import 'dart:math'; print('0x' + List.generate(64, (_) => Random.secure().nextInt(16).toRadixString(16)).join());"
  //
  // This key is for example purposes only (randomly generated):
  // NOTE: Use a fresh key without existing EIP-7702 delegation
  const testPrivateKey =
      '0xe9c56c50a13777407cbe1d640fcf6f6d6cdeb788a0e1d9f14a32d70723139bd5';

  final owner = PrivateKeyEip7702KernelOwner(testPrivateKey);
  print('\nOwner address: ${owner.address.checksummed}');

  // ================================================================
  // 1. Create Clients and EIP-7702 Kernel Smart Account
  // ================================================================
  //
  // EIP-7702 Kernel accounts are unique because:
  // - The account address IS the owner's EOA address
  // - No factory deployment needed
  // - Code is delegated via signed authorization
  // - Uses EntryPoint v0.7 (not v0.8 like Simple7702)
  // - Uses Kernel v0.3.3 logic (ERC-7579 compliant)

  // Create public client first - needed for EIP-7702 delegation checks
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createEip7702KernelSmartAccount(
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
    entryPoint: EntryPointAddresses.v07, // v0.7 for Kernel
  );

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v07,
  );

  // Paymaster for sponsored transactions (optional)
  final paymaster = selfFunded ? null : createPaymasterClient(url: pimlicoUrl);

  // Create SmartAccountClient with publicClient for EIP-7702 support
  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: bundler,
    paymaster: paymaster,
    publicClient: publicClient, // Required for EIP-7702 authorization handling
  );

  // ================================================================
  // 3. Get Account Information
  // ================================================================
  //
  // For EIP-7702, the account address is the same as the owner's EOA address.

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

  final isDeployed = await publicClient.isDeployed(accountAddress);
  print('Has code (delegation active): $isDeployed');

  final balance = await publicClient.getBalance(accountAddress);
  final balanceEth = balance / BigInt.from(10).pow(18);
  print('Balance: $balanceEth ETH');

  // Get the EntryPoint nonce for the smart account
  // For Kernel, we need to use the account's nonceKey (encodes validator info)
  final nonce = await publicClient.getAccountNonce(
    accountAddress,
    EntryPointAddresses.v07, // v0.7 for Kernel
    nonceKey: account.nonceKey,
  );
  print('EntryPoint nonce: $nonce');
  print('Nonce key: ${account.nonceKey.toRadixString(16)}');

  // Get gas prices
  final gasPrices = await pimlico.getUserOperationGasPrice();
  print('Gas prices - Fast: ${gasPrices.fast.maxFeePerGas} wei');

  // ================================================================
  // 5. Build Transaction
  // ================================================================
  //
  // We'll send a simple 0-value transaction to ourselves.

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
  // - Calls authorization-aware gas estimation
  // - Applies paymaster if configured

  print('\n--- Preparing UserOperation ---');

  late final UserOperationV07 userOp;
  try {
    userOp = await smartAccountClient.prepareUserOperation(
      calls: [call],
      maxFeePerGas: gasPrices.fast.maxFeePerGas,
      maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
      nonce: nonce,
    );
  } on BundlerRpcError catch (e) {
    print('\nUserOperation preparation failed: ${e.message}');
    print('\nThis likely means:');
    print('  - The bundler does not support EIP-7702 with v0.7');
    print('  - The sender address has no code (delegation not active)');

    smartAccountClient.close();
    pimlico.close();
    publicClient.close();
    return;
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
  //
  // SmartAccountClient automatically includes authorization when sending
  // if delegation is not yet active.

  print('\n--- Signing and Sending ---');

  final signedOp = await smartAccountClient.signUserOperation(userOp);
  print('Signature: ${signedOp.signature.substring(0, 30)}...');

  String hash;
  try {
    hash = await smartAccountClient.sendPreparedUserOperation(signedOp);
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
  print('Key differences from Simple7702:');
  print('  - Uses EntryPoint v0.7 (not v0.8)');
  print('  - Uses hash-based UserOp signing (not EIP-712 typed data)');
  print('  - Uses Kernel v0.3.3 logic (ERC-7579 compliant)');
  print('  - SmartAccountClient handles authorization automatically');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  bundler.close();
  pimlico.close();
  publicClient.close();
}

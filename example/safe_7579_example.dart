// Example: Creating a Safe smart account with ERC-7579 modular support
//
// This example demonstrates:
// 1. Creating a Safe account with ERC-7579 enabled
// 2. Configuring attesters for module verification
// 3. Sending a UserOperation using the ERC-7579 execute encoding
//
// USAGE:
//   dart run example/safe_7579_example.dart              # Sponsored (free gas)
//   dart run example/safe_7579_example.dart --self-fund  # Self-funded
//
// REQUIREMENTS:
// - For sponsored mode: Just run it! Pimlico sponsors testnet transactions.
// - For self-funded mode: Send ~0.01 Sepolia ETH to the account address.

import 'package:permissionless/permissionless.dart';

void main(List<String> args) async {
  // Parse command line arguments
  final selfFunded = args.contains('--self-fund') || args.contains('-s');

  print('='.padRight(60, '='));
  print('Safe Smart Account with ERC-7579 Example');
  print('Mode: ${selfFunded ? "SELF-FUNDED" : "SPONSORED"}');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Create an owner from a private key
  // ================================================================
  //
  // WARNING: Never hardcode private keys in production!
  const testPrivateKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  final owner = PrivateKeyOwner(testPrivateKey);
  print('\nOwner address: ${owner.address.checksummed}');

  // ================================================================
  // 1. Create Public Client and Safe Smart Account with ERC-7579
  // ================================================================
  //
  // ERC-7579 enables modular smart account functionality:
  // - Install/uninstall validators, executors, hooks, and fallbacks
  // - Standard execute(mode, calldata) encoding
  // - Module verification through attesters (e.g., Rhinestone)

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  // Create Safe with ERC-7579 enabled by providing the launchpad address
  final account = createSafeSmartAccount(
    owners: [owner],
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    chainId: BigInt.from(11155111), // Sepolia
    saltNonce: BigInt.from(7579), // Unique salt for this example
    publicClient: publicClient,
    // ERC-7579 Configuration
    erc7579LaunchpadAddress: Safe7579Addresses.erc7579LaunchpadAddress,
    // Attesters verify that modules are safe to install
    // Rhinestone is the default attester for the ERC-7579 ecosystem
    attesters: [Safe7579Addresses.rhinestoneAttester],
    attestersThreshold: 1, // Require 1 attester approval for modules
  );

  print('\n--- ERC-7579 Configuration ---');
  print('ERC-7579 Enabled: ${account.isErc7579Enabled}');
  print('Launchpad: ${Safe7579Addresses.erc7579LaunchpadAddress.checksummed}');
  print(
    'Safe7579 Module: ${Safe7579Addresses.safe7579ModuleAddress.checksummed}',
  );
  print(
    'Rhinestone Attester: ${Safe7579Addresses.rhinestoneAttester.checksummed}',
  );

  // ================================================================
  // 2. Get Account Address
  // ================================================================

  final accountAddress = await account.getAddress();
  final isDeployed = await publicClient.isDeployed(accountAddress);

  print('\n--- Account Status ---');
  print(
    'Safe 7579 Account: ${accountAddress.checksummed} '
    '${isDeployed ? "(already deployed)" : "(will be deployed)"}',
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
    publicClient: publicClient,
    paymaster: paymaster,
  );

  // ================================================================
  // 4. Check Gas Prices and Nonce
  // ================================================================

  final gasPrices = await pimlico.getUserOperationGasPrice();
  print('Gas prices - Fast: ${gasPrices.fast.maxFeePerGas} wei');

  final nonce = await publicClient.getAccountNonce(
    accountAddress,
    EntryPointAddresses.v07,
  );
  print('Current nonce: $nonce');

  // ================================================================
  // 5. Build Transaction
  // ================================================================
  //
  // In ERC-7579 mode, calls are encoded using the standard
  // execute(bytes32 mode, bytes executionCalldata) format

  print('\n--- Building Transaction ---');

  final call = Call(
    to: accountAddress,
    value: BigInt.zero,
    data: '0x',
  );

  print('Transaction: Self-ping using ERC-7579 execute encoding');

  // Demonstrate the ERC-7579 encoding (this is done automatically)
  final encodedCall = account.encodeCall(call);
  print('Encoded call starts with: ${encodedCall.substring(0, 10)}');
  print('(0xe9ae5c53 is the ERC-7579 execute selector)');

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
    );
  } on BundlerRpcError catch (e) {
    if (e.message.contains('AA') || e.message.contains('initCode')) {
      print('\n! UserOperation preparation failed!');
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

  // Show factory data if deploying
  if (!isDeployed && userOp.factory != null) {
    print('Factory: ${userOp.factory!.checksummed}');
    print('Factory data length: ${userOp.factoryData!.length} chars');
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
    // Included but no receipt yet (or receipt.success is false)
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
  print('Account type: Safe v${account.version.value} with ERC-7579');
  print('Mode: ${selfFunded ? "Self-funded" : "Sponsored by Pimlico"}');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

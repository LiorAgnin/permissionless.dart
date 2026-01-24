// Example: Kernel Smart Account with WebAuthn/Passkey Owner
//
// This example demonstrates creating a Kernel v0.3.1 smart account with a
// WebAuthn (passkey) owner using P256 signatures.
//
// IMPORTANT: This example shows the structure for WebAuthn integration.
// Actual WebAuthn signing requires platform-specific code (web3-signers
// package) or browser WebAuthn APIs.
//
// For full passkey support, see the permissionless_passkeys package.

import 'dart:typed_data';

import 'package:permissionless/permissionless.dart';

/// Example WebAuthn owner implementation.
///
/// In production, use web3-signers PassKeySigner or implement
/// WebAuthnAccountOwner with actual WebAuthn APIs.
class ExampleWebAuthnOwner extends WebAuthnAccountOwner {
  ExampleWebAuthnOwner({
    required this.x,
    required this.y,
    required this.credentialId,
  });

  @override
  final BigInt x;

  @override
  final BigInt y;

  @override
  final Uint8List credentialId;

  @override
  Future<P256SignatureData> signP256(String hash) async {
    // In production, this would call:
    // - Browser: navigator.credentials.get() with WebAuthn
    // - Mobile: Platform authenticator APIs
    // - Package: web3-signers PassKeySigner.signAsync()
    throw UnimplementedError(
      'Implement signP256 with actual WebAuthn signing. '
      'See permissionless_passkeys package for full implementation.',
    );
  }
}

void main() async {
  print('='.padRight(60, '='));
  print('Kernel WebAuthn (Passkey) Smart Account Example');
  print('='.padRight(60, '='));

  // ================================================================
  // SETUP: Create a WebAuthn owner from passkey credentials
  // ================================================================
  //
  // These values come from WebAuthn registration (navigator.credentials.create)
  // The x/y coordinates are the P256 public key from the attestation.
  //
  // Example values (replace with actual passkey registration data):
  final webAuthnOwner = ExampleWebAuthnOwner(
    x: BigInt.parse(
      '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
    ),
    y: BigInt.parse(
      '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321',
    ),
    credentialId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
  );

  print('\nWebAuthn Owner:');
  print('  Public Key X: 0x${webAuthnOwner.x.toRadixString(16)}');
  print('  Public Key Y: 0x${webAuthnOwner.y.toRadixString(16)}');
  print('  Credential ID: ${webAuthnOwner.credentialId.length} bytes');
  print('  Derived Address: ${webAuthnOwner.address.checksummed}');

  // ================================================================
  // 1. Create Clients and Kernel Smart Account with WebAuthn
  // ================================================================
  //
  // Kernel v0.3.x supports WebAuthn via a dedicated P256 validator module.
  // The SDK automatically uses the WebAuthn validator address when a
  // WebAuthn owner is detected.

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createKernelSmartAccount(
    owner: webAuthnOwner, // WebAuthn owner instead of PrivateKeyOwner
    chainId: BigInt.from(11155111), // Sepolia
    version: KernelVersion.v0_3_1, // WebAuthn requires v0.3.x
    index: BigInt.zero,
    publicClient: publicClient,
  );

  // ================================================================
  // 2. Verify WebAuthn Detection and Nonce Key
  // ================================================================

  print('\n--- Account Configuration ---');
  print('Kernel Version: ${KernelVersion.v0_3_1.value}');
  print('EntryPoint: ${account.entryPoint.checksummed}');
  print('Is WebAuthn: ${account.isWebAuthn}'); // Should be true!

  // Kernel v0.3.x encodes the validator address in the nonce key
  // WebAuthn validator: 0x7ab16Ff354AcB328452F1D445b3Ddee9a91e9e69
  final nonceKeyHex = account.nonceKey.toRadixString(16).padLeft(48, '0');
  print('Nonce Key: 0x$nonceKeyHex');
  print('  Format: mode(1) + type(1) + validator(20) + salt(2)');
  print('  Validator in key: 0x${nonceKeyHex.substring(4, 44)}');

  // ================================================================
  // 3. Get Account Address
  // ================================================================

  final accountAddress = await account.getAddress();
  print('\nKernel Account Address: ${accountAddress.checksummed}');

  // ================================================================
  // 4. Create Smart Account Client
  // ================================================================

  const pimlicoUrl = 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY';

  final pimlico = createPimlicoClient(
    url: pimlicoUrl,
    entryPoint: EntryPointAddresses.v07,
  );

  final paymaster = createPaymasterClient(url: pimlicoUrl);

  final smartAccountClient = SmartAccountClient(
    account: account,
    bundler: pimlico,
    publicClient: publicClient,
    paymaster: paymaster,
  );

  // ================================================================
  // 5. Fetch Nonce with Correct Key
  // ================================================================
  //
  // Kernel v0.3.x uses validator-specific nonce keys. The SDK now
  // automatically passes the correct nonce key when fetching nonces.

  print('\n--- Nonce Handling ---');

  final nonce = await publicClient.getAccountNonce(
    accountAddress,
    EntryPointAddresses.v07,
    nonceKey: account.nonceKey, // Pass the validator-encoded key!
  );
  print('Current nonce (with correct key): $nonce');

  // ================================================================
  // 6. Prepare and Send Transaction
  // ================================================================
  //
  // WebAuthn accounts require ~800k verification gas for P256
  // on-chain signature verification. The SDK automatically
  // applies minimum gas limits when isWebAuthn is true.

  print('\n--- Preparing UserOperation ---');

  final call = Call(
    to: accountAddress,
    value: BigInt.zero,
    data: '0x', // Self-ping transaction
  );

  final gasPrices = await pimlico.getUserOperationGasPrice();

  try {
    final userOp = await smartAccountClient.prepareUserOperation(
      calls: [call],
      maxFeePerGas: gasPrices.fast.maxFeePerGas,
      maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
    );

    print('Verification Gas Limit: ${userOp.verificationGasLimit}');
    print('(Should be ~900k+ for WebAuthn P256 verification)');

    // Note: signUserOperation will fail with UnimplementedError
    // because ExampleWebAuthnOwner.signP256 is not implemented.
    // In production, use actual WebAuthn signing.

    print('\n--- Signing (requires actual WebAuthn implementation) ---');
    // final signedUserOp = await smartAccountClient.signUserOperation(userOp);
    // final hash = await smartAccountClient.sendPreparedUserOperation(signedUserOp);
    print('Skipping signing - implement signP256 for actual use.');
  } on BundlerRpcError catch (e) {
    print('Bundler error: ${e.message}');
  }

  // ================================================================
  // Summary
  // ================================================================

  print('\n${'='.padRight(60, '=')}');
  print('WebAuthn Kernel Account Example Complete');
  print('');
  print('Key points:');
  print('  - Kernel v0.3.x supports WebAuthn via P256 validator module');
  print('  - account.isWebAuthn returns true for WebAuthn owners');
  print('  - Nonce key encodes the WebAuthn validator address');
  print('  - SDK auto-applies 900k min verification gas for P256');
  print('  - Use permissionless_passkeys for full WebAuthn support');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

// Example: Safe Smart Account with WebAuthn/Passkey Owner
//
// This example demonstrates creating a Safe smart account with a
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
  print('Safe WebAuthn (Passkey) Smart Account Example');
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
  // 1. Create Clients and Safe Smart Account with WebAuthn
  // ================================================================
  //
  // Safe supports WebAuthn owners alongside traditional ECDSA owners.
  // The account automatically detects WebAuthn owners and uses
  // appropriate signature encoding.

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  final account = createSafeSmartAccount(
    owners: [webAuthnOwner], // WebAuthn owner instead of PrivateKeyOwner
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    chainId: BigInt.from(11155111), // Sepolia
    saltNonce: BigInt.zero,
    publicClient: publicClient,
  );

  // ================================================================
  // 2. Verify WebAuthn Detection
  // ================================================================

  print('\n--- Account Configuration ---');
  print('Safe Version: ${account.version.value}');
  print('EntryPoint: ${account.entryPoint.checksummed}');
  print('Is WebAuthn: ${account.isWebAuthn}'); // Should be true!
  print('Nonce Key: ${account.nonceKey}');

  // ================================================================
  // 3. Get Account Address
  // ================================================================

  final accountAddress = await account.getAddress();
  print('\nSafe Account Address: ${accountAddress.checksummed}');

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
  // 5. Prepare and Send Transaction
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
  print('WebAuthn Safe Account Example Complete');
  print('');
  print('Key points:');
  print('  - WebAuthn owners use P256 (secp256r1) signatures');
  print('  - account.isWebAuthn returns true for WebAuthn owners');
  print('  - SDK auto-applies 900k min verification gas for P256');
  print('  - Use permissionless_passkeys for full WebAuthn support');
  print('='.padRight(60, '='));

  // Cleanup
  smartAccountClient.close();
  pimlico.close();
  publicClient.close();
}

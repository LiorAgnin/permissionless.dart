// Copyright (c) 2025 Lior Ageniho. All rights reserved.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

/// Example demonstrating permissionless.dart ERC-4337 smart accounts.
///
/// This example shows how to:
/// - Create a private key owner
/// - Set up a Safe smart account
/// - Get the counterfactual address
/// - Create bundler, paymaster, and smart account clients
/// - Send a sponsored UserOperation
library;

import 'package:permissionless/permissionless.dart';

void main() async {
  // 1. Create an owner from a private key
  final owner = PrivateKeyOwner(
    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );

  const rpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
  final publicClient = createPublicClient(url: rpcUrl);

  // 2. Create a Safe smart account
  final account = createSafeSmartAccount(
    owners: [owner],
    version: SafeVersion.v1_4_1,
    entryPointVersion: EntryPointVersion.v07,
    chainId: BigInt.from(11155111), // Sepolia
    publicClient: publicClient,
  );

  // 3. Get the account address (deterministic, works before deployment)
  final accountAddress = await account.getAddress();
  print('Smart Account Address: ${accountAddress.checksummed}');

  // 4. Create clients
  final pimlico = createPimlicoClient(
    url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
    entryPoint: EntryPointAddresses.v07,
  );

  final paymaster = createPaymasterClient(
    url: 'https://api.pimlico.io/v2/sepolia/rpc?apikey=YOUR_KEY',
  );

  // 5. Create a smart account client
  final client = SmartAccountClient(
    account: account,
    bundler: pimlico,
    publicClient: publicClient,
    paymaster: paymaster,
  );

  // 6. Send a sponsored transaction
  final hash = await client.sendUserOperation(
    calls: [
      Call(
        to: accountAddress,
        value: BigInt.zero,
        data: '0x',
      ),
    ],
    maxFeePerGas: BigInt.from(20000000000),
    maxPriorityFeePerGas: BigInt.from(1000000000),
  );

  print('UserOperation hash: $hash');
}

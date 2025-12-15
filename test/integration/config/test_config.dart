import 'dart:io';

import 'package:permissionless/permissionless.dart';

/// Configuration for integration tests.
///
/// Environment variables:
/// - `PIMLICO_API_KEY`: Required for bundler/paymaster access
/// - `TEST_PRIVATE_KEY`: Optional, for funded account tests
/// - `FUNDED_ACCOUNT_ADDRESS`: Optional, pre-computed address of funded account
class TestConfig {
  TestConfig._();

  /// Pimlico API key from environment.
  static String? get pimlicoApiKey => Platform.environment['PIMLICO_API_KEY'];

  /// Private key for funded tests (optional).
  static String? get testPrivateKey => Platform.environment['TEST_PRIVATE_KEY'];

  /// Pre-funded account address (optional).
  static String? get fundedAccountAddress =>
      Platform.environment['FUNDED_ACCOUNT_ADDRESS'];

  /// Whether API keys are configured for integration tests.
  static bool get hasApiKeys =>
      pimlicoApiKey != null && pimlicoApiKey!.isNotEmpty;

  /// Whether funded account tests can run.
  static bool get hasFundedAccount =>
      testPrivateKey != null &&
      testPrivateKey!.isNotEmpty &&
      fundedAccountAddress != null;

  /// Skip message for missing API keys.
  static const String skipNoApiKey =
      'Skipping: PIMLICO_API_KEY environment variable not set';

  /// Skip message for missing funded account.
  static const String skipNoFundedAccount =
      'Skipping: TEST_PRIVATE_KEY and FUNDED_ACCOUNT_ADDRESS not set';

  /// Well-known test private key (Foundry/Hardhat account 0).
  /// DO NOT use in production!
  static const String hardhatTestKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
}

/// Chain configurations for testnets.
enum TestChain {
  /// Ethereum Sepolia testnet.
  sepolia(
    chainId: 11155111,
    name: 'Sepolia',
    // Using 1rpc.io public RPC (more reliable)
    rpcUrl: 'https://1rpc.io/sepolia',
    pimlicoPath: 'sepolia',
  ),

  /// Base Sepolia testnet (L2).
  baseSepolia(
    chainId: 84532,
    name: 'Base Sepolia',
    rpcUrl: 'https://sepolia.base.org',
    pimlicoPath: 'base-sepolia',
  );

  const TestChain({
    required this.chainId,
    required this.name,
    required this.rpcUrl,
    required this.pimlicoPath,
  });

  /// Numeric chain ID.
  final int chainId;

  /// Human-readable name.
  final String name;

  /// Public RPC URL for read-only operations.
  final String rpcUrl;

  /// Pimlico API path segment.
  final String pimlicoPath;

  /// Chain ID as BigInt for SDK compatibility.
  BigInt get chainIdBigInt => BigInt.from(chainId);

  /// Constructs the Pimlico bundler URL.
  String get pimlicoUrl {
    final apiKey = TestConfig.pimlicoApiKey;
    return 'https://api.pimlico.io/v2/$pimlicoPath/rpc?apikey=$apiKey';
  }

  /// EntryPoint v0.7 address (same across all chains).
  EthAddress get entryPointV07 => EntryPointAddresses.v07;
}

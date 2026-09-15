import 'dart:io';

import 'package:permissionless/permissionless.dart';

/// Configuration for integration tests.
///
/// Environment variables:
/// - `PIMLICO_API_KEY`: Required for bundler/paymaster access
/// - `TEST_PRIVATE_KEY`: Optional, for funded account tests
/// - `FUNDED_ACCOUNT_ADDRESS`: Optional, pre-computed address of funded account
/// - `KERNEL_V4_RPC_URL`: RPC of a chain carrying the Kernel v4 stack
/// - `KERNEL_V4_BUNDLER_URL`: EntryPoint v0.9-aware bundler for Kernel v4
/// - `KERNEL_V4_PAYMASTER_URL`: Optional paymaster for sponsored Kernel v4 ops
/// - `KERNEL_V4_ECDSA_VALIDATOR`: Optional ECDSA validator module address
/// - `KERNEL_V4_POLICY`: Optional policy module for permission-scoped UserOps
/// - `KERNEL_V4_SIGNER_MODULE`: Optional signer module for permission UserOps
/// - `KERNEL_V4_SESSION_PRIVATE_KEY`: Optional session-key private key
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

  /// RPC of a chain carrying Kernel v4.0 + EntryPoint v0.9.
  static String? get kernelV4RpcUrl =>
      Platform.environment['KERNEL_V4_RPC_URL'];

  /// EntryPoint v0.9-aware bundler for Kernel v4 UserOperations.
  static String? get kernelV4BundlerUrl =>
      Platform.environment['KERNEL_V4_BUNDLER_URL'];

  /// Optional paymaster URL for sponsored Kernel v4 operations.
  static String? get kernelV4PaymasterUrl =>
      Platform.environment['KERNEL_V4_PAYMASTER_URL'];

  /// Optional external ECDSA validator module (enable-mode / UUPS root).
  static String? get kernelV4EcdsaValidator =>
      Platform.environment['KERNEL_V4_ECDSA_VALIDATOR'];

  /// Optional policy module address for permission-scoped UserOps.
  static String? get kernelV4Policy => Platform.environment['KERNEL_V4_POLICY'];

  /// Optional signer module address for permission-scoped UserOps.
  static String? get kernelV4SignerModule =>
      Platform.environment['KERNEL_V4_SIGNER_MODULE'];

  /// Optional session-key private key (permission signer owner).
  ///
  /// When unset, permission-scoped funded tests skip rather than reuse the
  /// root key as the session signer.
  static String? get kernelV4SessionPrivateKey =>
      Platform.environment['KERNEL_V4_SESSION_PRIVATE_KEY'];

  /// Whether Kernel v4 funded e2e infrastructure is configured.
  ///
  /// Requires RPC + bundler + a non-Hardhat-#0 [testPrivateKey]. Contracts
  /// and module addresses are checked at runtime and skip cleanly when
  /// missing (no public Kernel v4 deployments exist yet).
  static bool get hasKernelV4FundedInfra =>
      _nonEmpty(kernelV4RpcUrl) &&
      _nonEmpty(kernelV4BundlerUrl) &&
      _nonEmpty(testPrivateKey) &&
      !isHardhatZeroKey(testPrivateKey);

  /// Skip message for missing API keys.
  static const String skipNoApiKey =
      'Skipping: PIMLICO_API_KEY environment variable not set';

  /// Skip message for missing funded account.
  static const String skipNoFundedAccount =
      'Skipping: TEST_PRIVATE_KEY and FUNDED_ACCOUNT_ADDRESS not set';

  /// Skip message for missing Kernel v4 funded infrastructure.
  static const String skipNoKernelV4FundedInfra =
      'Skipping: Kernel v4 funded e2e needs KERNEL_V4_RPC_URL, '
      'KERNEL_V4_BUNDLER_URL, and TEST_PRIVATE_KEY (not Hardhat #0). '
      'No public Kernel v4 / EntryPoint v0.9 deployments exist yet — '
      'point these at a local anvil where the release recipe has been run.';

  /// Well-known test private key (Foundry/Hardhat account 0).
  /// DO NOT use on live networks!
  static const String hardhatTestKey =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  /// Whether [key] is the well-known Hardhat/Foundry account #0 key.
  ///
  /// Funded tests on live networks must never use this key.
  static bool isHardhatZeroKey(String? key) {
    if (key == null || key.isEmpty) return false;
    final normalized = key.toLowerCase().startsWith('0x')
        ? key.toLowerCase()
        : '0x${key.toLowerCase()}';
    return normalized == hardhatTestKey.toLowerCase();
  }

  static bool _nonEmpty(String? value) => value != null && value.isNotEmpty;
}

/// Chain configurations for testnets.
enum TestChain {
  /// Ethereum Sepolia testnet.
  sepolia(
    chainId: 11155111,
    name: 'Sepolia',
    // publicnode: free and stable for full suites; 1rpc/0xrpc rate-limit heavily
    rpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
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
  EthereumAddress get entryPointV07 => EntryPointAddresses.v07;
}

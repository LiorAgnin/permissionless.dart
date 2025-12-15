/// Alchemy Light Account implementation.
///
/// Light Account is a simple, gas-efficient ERC-4337 smart account from Alchemy.
///
/// ## Supported Versions
///
/// - **v1.1.0** (EntryPoint v0.6) - Legacy version
/// - **v2.0.0** (EntryPoint v0.7) - Current version with signature type prefix
///
/// ## Features
///
/// - Single owner with ECDSA validation
/// - EIP-1271 signature validation with LightAccountMessage wrapper
/// - execute/executeBatch for transaction batching
/// - Low gas overhead
///
/// ## Note on ERC-7579
///
/// Light Account does NOT implement ERC-7579 modular architecture.
/// For modular account support, consider Kernel v0.3.x or Nexus.
library;

export 'constants.dart';
export 'light_account.dart';

/// Simple smart account - minimal ERC-4337 reference implementation.
///
/// This library provides Simple smart account implementations,
/// including the standard Simple account and the EIP-7702 variant.
///
/// - [SimpleSmartAccount]: Standard CREATE2-deployed smart account
/// - [Eip7702SimpleSmartAccount]: EIP-7702 code delegation account
///
/// ## Features
///
/// - Single owner with ECDSA validation
/// - Direct signature validation (no modules)
/// - Built-in execute/executeBatch functions
/// - EntryPoint v0.6 and v0.7 support
///
/// ## Note on ERC-7579
///
/// Simple Account does NOT implement ERC-7579 modular architecture.
/// For modular account support, consider Kernel v0.3.x or Nexus.
library;

export 'constants.dart';
export 'eip7702_simple_account.dart';
export 'simple_account.dart';

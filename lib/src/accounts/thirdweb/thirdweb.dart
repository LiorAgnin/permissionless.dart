/// Thirdweb Smart Account implementation.
///
/// Thirdweb provides ERC-4337 smart accounts through their SDK and
/// managed infrastructure.
///
/// ## Features
///
/// - Single owner with ECDSA validation
/// - Factory-based deterministic deployment
/// - EntryPoint v0.6 and v0.7 support
/// - Integration with Thirdweb SDK and dashboard
///
/// ## Note on ERC-7579
///
/// Thirdweb Smart Account does NOT implement ERC-7579 modular architecture.
/// For modular account support, consider Kernel v0.3.x or Nexus.
library;

export 'constants.dart';
export 'thirdweb_account.dart';

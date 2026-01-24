/// Biconomy Smart Account implementation (legacy).
///
/// **Note:** Biconomy Smart Account is the legacy version for EntryPoint v0.6.
/// For new projects, use [Nexus] which is Biconomy's ERC-7579 modular smart
/// account for EntryPoint v0.7.
///
/// ## Features
///
/// - Single or multi-owner support
/// - ECDSA validation
/// - EntryPoint v0.6 only
///
/// ## Note on ERC-7579
///
/// Biconomy Smart Account does NOT implement ERC-7579.
/// For ERC-7579 support, use [Nexus] or Kernel v0.3.x.
library;

export 'biconomy_account.dart';
export 'constants.dart';

/// Trust Account (Barz) implementation.
///
/// Trust Account (Barz) is a diamond-based ERC-4337 smart account from
/// Trust Wallet, featuring a modular diamond proxy architecture.
///
/// ## Features
///
/// - Single owner with ECDSA validation
/// - Diamond proxy pattern (EIP-2535) for upgradability
/// - Secp256r1 (P-256) key support via facets
/// - EntryPoint v0.6 only
///
/// ## Note on ERC-7579
///
/// Trust Account does NOT implement ERC-7579 modular architecture.
/// It uses the diamond standard (EIP-2535) instead.
/// For ERC-7579 modular accounts, consider Kernel v0.3.x or Nexus.
library;

export 'constants.dart';
export 'trust_account.dart';

/// Nexus Smart Account implementation (Biconomy's ERC-7579 account).
///
/// Nexus is the modern successor to Biconomy Smart Account, built on
/// ERC-7579 modular architecture for EntryPoint v0.7.
///
/// ## ERC-7579 Support
///
/// Nexus implements the full ERC-7579 modular account standard:
/// - ERC-7579 call encoding (`execute(bytes32 mode, bytes executionCalldata)`)
/// - Module installation/uninstallation (validators, executors, hooks)
/// - Module type queries (`supportsModule`, `isModuleInstalled`)
/// - Execution mode queries (`supportsExecutionMode`)
/// - K1 validator for ECDSA signatures
/// - Optional attester-based validation
///
/// ## Migration from Biconomy Smart Account
///
/// If you're using the legacy Biconomy Smart Account (EP v0.6), consider
/// migrating to Nexus for ERC-7579 module support and EntryPoint v0.7.
library;

export 'constants.dart';
export 'nexus_account.dart';

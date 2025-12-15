/// Etherspot ModularEtherspotWallet smart account implementation.
///
/// Etherspot provides a modular ERC-4337 smart account that uses
/// ERC-7579 call encoding and EntryPoint v0.7.
///
/// ## ERC-7579 Support
///
/// Etherspot ModularEtherspotWallet uses ERC-7579 call encoding:
/// - ERC-7579 execute format (`execute(bytes32 mode, bytes executionCalldata)`)
/// - ECDSA validator for signature validation
/// - Bootstrap-based initialization
///
/// ## Features
///
/// - Single owner with ECDSA validation
/// - Modular architecture for validators
/// - Deterministic address derivation via CREATE2
/// - EntryPoint v0.7 only
library;

export 'constants.dart';
export 'etherspot_account.dart';

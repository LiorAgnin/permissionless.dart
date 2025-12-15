import '../../types/address.dart';

/// Nexus Smart Account addresses (Biconomy's ERC-7579 account).
///
/// Nexus is the successor to Biconomy Smart Account, built on ERC-7579
/// modular architecture.
class NexusAddresses {
  NexusAddresses._();

  /// K1 Validator Factory address for account deployment.
  static final EthAddress k1ValidatorFactory =
      EthAddress('0x00000bb19a3579F4D779215dEf97AFbd0e30DB55');

  /// K1 Validator address for ECDSA signature validation.
  static final EthAddress k1Validator =
      EthAddress('0x00000004171351c442B202678c48D8AB5B321E8f');
}

/// Nexus function selectors.
class NexusSelectors {
  NexusSelectors._();

  /// createAccount(address eoaOwner, uint256 index, address[] attesters, uint8 threshold)
  /// `keccak256("createAccount(address,uint256,address[],uint8)")[0:4]` = 0x0d51f0b7
  static const String createAccount = '0x0d51f0b7';

  /// computeAccountAddress(address eoaOwner, uint256 index, address[] attesters, uint8 threshold)
  static const String computeAccountAddress = '0x8b97fea1';
}

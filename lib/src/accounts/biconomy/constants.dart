import '../../types/address.dart';

/// Biconomy Smart Account addresses (deprecated, v0.6 only).
///
/// Note: Biconomy Smart Account is deprecated. Use Nexus for new projects.
@Deprecated('Use Nexus Smart Account instead')
class BiconomyAddresses {
  BiconomyAddresses._();

  /// ECDSA Ownership Registry Module address.
  static final EthAddress ecdsaOwnershipModule =
      EthAddress('0x0000001c5b32F37F5beA87BDD5374eB2aC54eA8e');

  /// Factory address for account deployment.
  static final EthAddress factory =
      EthAddress('0x000000a56Aaca3e9a4C479ea6b6CD0DbcB6634F5');

  /// Account v2.0 logic/implementation address.
  static final EthAddress accountV2Logic =
      EthAddress('0x0000002512019Dafb59528B82CB92D3c5D2423aC');

  /// Default fallback handler address.
  static final EthAddress defaultFallbackHandler =
      EthAddress('0x0bBa6d96BD616BedC6BFaa341742FD43c60b83C1');
}

/// Biconomy function selectors.
///
/// These are keccak256 hashes of the function signatures, truncated to 4 bytes.
/// Example: keccak256("initForSmartAccount(address)").slice(0, 4) = 0x2ede3bc0
@Deprecated('Use Nexus Smart Account instead')
class BiconomySelectors {
  BiconomySelectors._();

  /// execute_ncC(address dest, uint256 value, bytes calldata func)
  /// `keccak256("execute_ncC(address,uint256,bytes)")[0:4]`
  static const String execute = '0x0000189a';

  /// executeBatch_y6U(address[] dest, uint256[] values, bytes[] func)
  /// `keccak256("executeBatch_y6U(address[],uint256[],bytes[])")[0:4]`
  static const String executeBatch = '0x00004680';

  /// deployCounterFactualAccount(address moduleSetupContract, bytes moduleSetupData, uint256 index)
  /// `keccak256("deployCounterFactualAccount(address,bytes,uint256)")[0:4]`
  static const String deployCounterFactualAccount = '0xdf20ffbc';

  /// initForSmartAccount(address owner)
  /// `keccak256("initForSmartAccount(address)")[0:4]`
  static const String initForSmartAccount = '0x2ede3bc0';

  /// init(address handler, address moduleSetupContract, bytes moduleSetupData)
  /// `keccak256("init(address,address,bytes)")[0:4]`
  static const String init = '0x378dfd8e';
}

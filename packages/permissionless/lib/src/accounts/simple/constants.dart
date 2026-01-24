import '../../types/address.dart';
import '../../types/user_operation.dart';

/// Factory addresses for SimpleAccount deployment.
///
/// These are the official eth-infinitism reference implementation
/// factory addresses deployed across EVM chains.
class SimpleAccountFactoryAddresses {
  SimpleAccountFactoryAddresses._();

  /// SimpleAccountFactory for EntryPoint v0.6.
  static final EthereumAddress v06 =
      EthereumAddress.fromHex('0x9406Cc6185a346906296840746125a0E44976454');

  /// SimpleAccountFactory for EntryPoint v0.7.
  static final EthereumAddress v07 =
      EthereumAddress.fromHex('0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985');

  /// SimpleAccountFactory for EntryPoint v0.8.
  static final EthereumAddress v08 =
      EthereumAddress.fromHex('0x13E9ed32155810FDbd067D4522C492D6f68E5944');

  /// Gets the factory address for the given EntryPoint version.
  static EthereumAddress fromVersion(EntryPointVersion version) =>
      switch (version) {
        EntryPointVersion.v06 => v06,
        EntryPointVersion.v07 => v07,
        EntryPointVersion.v08 => v08,
      };
}

/// Default Simple7702Account logic address for EIP-7702 delegation.
///
/// This is the audited Simple7702Account contract that EOAs can delegate to.
class Simple7702AccountAddresses {
  Simple7702AccountAddresses._();

  /// The default Simple7702Account implementation address.
  ///
  /// This contract is part of the eth-infinitism ERC-4337 v0.8 release.
  static final EthereumAddress defaultLogic =
      EthereumAddress.fromHex('0xe6Cae83BdE06E4c305530e199D7217f42808555B');
}

/// Function selectors for SimpleAccount contracts.
class SimpleAccountSelectors {
  SimpleAccountSelectors._();

  /// execute(address dest, uint256 value, bytes calldata func)
  /// Used by all versions for single call execution.
  static const String execute = '0xb61d27f6';

  /// executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func)
  /// Used by v0.6 and v0.7 for batch execution.
  static const String executeBatch = '0x47e1da2a';

  /// executeBatch(Call[] calldata calls) where Call = (address target, uint256 value, bytes data)
  /// Used by v0.8 for batch execution with tuple array.
  static const String executeBatchV08 = '0x34fcd5be';

  /// createAccount(address owner, uint256 salt)
  static const String createAccount = '0x5fbfb9cf';
}

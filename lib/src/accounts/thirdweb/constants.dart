import '../../types/address.dart';

/// Thirdweb Smart Account addresses.
///
/// Thirdweb accounts support both EntryPoint v0.6 and v0.7.
class ThirdwebAddresses {
  ThirdwebAddresses._();

  /// Factory address for EntryPoint v0.6.
  static final EthAddress factoryV06 =
      EthAddress('0x85e23b94e7F5E9cC1fF78BCe78cfb15B81f0DF00');

  /// Factory address for EntryPoint v0.7.
  static final EthAddress factoryV07 =
      EthAddress('0x4be0ddfebca9a5a4a617dee4dece99e7c862dceb');
}

/// Thirdweb function selectors.
class ThirdwebSelectors {
  ThirdwebSelectors._();

  /// execute(address dest, uint256 value, bytes func)
  static const String execute = '0xb61d27f6';

  /// executeBatch(address[] dest, uint256[] value, bytes[] func)
  static const String executeBatch = '0x47e1da2a';

  /// createAccount(address _admin, bytes _salt)
  /// `keccak256("createAccount(address,bytes)")[0:4]` = 0xd8fd8f44
  static const String createAccount = '0xd8fd8f44';

  /// getAddress(address _adminSigner, bytes _data)
  static const String getAddress = '0x8878ed33';
}

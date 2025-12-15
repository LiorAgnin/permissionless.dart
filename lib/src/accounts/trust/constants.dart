import '../../types/address.dart';

/// Trust Smart Account (Barz) addresses.
///
/// Trust accounts only support EntryPoint v0.6.
class TrustAddresses {
  TrustAddresses._();

  /// Factory address for account deployment.
  static final EthAddress factory =
      EthAddress('0x729c310186a57833f622630a16d13f710b83272a');

  /// Secp256k1 verification facet address.
  static final EthAddress secp256k1VerificationFacet =
      EthAddress('0x81b9E3689390C7e74cF526594A105Dea21a8cdD5');
}

/// Trust function selectors.
class TrustSelectors {
  TrustSelectors._();

  /// execute(address dest, uint256 value, bytes func)
  static const String execute = '0xb61d27f6';

  /// executeBatch(address[] dest, uint256[] value, bytes[] func)
  static const String executeBatch = '0x47e1da2a';

  /// createAccount(address _verificationFacet, bytes _owner, uint256 _salt)
  static const String createAccount = '0x296601cd';
}

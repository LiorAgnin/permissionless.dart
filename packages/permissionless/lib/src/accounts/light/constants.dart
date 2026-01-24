import '../../types/address.dart';
import '../../types/user_operation.dart';

/// Light Account versions.
///
/// Each version corresponds to a specific EntryPoint version:
/// - v1.1.0: EntryPoint v0.6
/// - v2.0.0: EntryPoint v0.7
enum LightAccountVersion {
  /// Version 1.1.0 for EntryPoint v0.6.
  v110('1.1.0'),

  /// Version 2.0.0 for EntryPoint v0.7.
  v200('2.0.0');

  const LightAccountVersion(this.version);

  /// The version string (e.g., "2.0.0").
  final String version;

  /// Gets the version for an EntryPoint version.
  ///
  /// Throws [ArgumentError] for unsupported EntryPoint versions.
  static LightAccountVersion forEntryPoint(EntryPointVersion entryPoint) {
    switch (entryPoint) {
      case EntryPointVersion.v06:
        return LightAccountVersion.v110;
      case EntryPointVersion.v07:
        return LightAccountVersion.v200;
      case EntryPointVersion.v08:
        throw ArgumentError(
          'Light Account does not support EntryPoint v0.8. '
          'Use Eip7702SimpleSmartAccount for EIP-7702 support.',
        );
    }
  }
}

/// Light Account factory addresses by version.
class LightAccountFactoryAddresses {
  LightAccountFactoryAddresses._();

  /// Factory for Light Account v1.1.0 (EntryPoint v0.6).
  static final v110 =
      EthereumAddress.fromHex('0x00004EC70002a32400f8ae005A26081065620D20');

  /// Factory for Light Account v2.0.0 (EntryPoint v0.7).
  static final v200 =
      EthereumAddress.fromHex('0x0000000000400CdFef5E2714E63d8040b700BC24');

  /// Gets the factory address for a Light Account version.
  static EthereumAddress fromVersion(LightAccountVersion version) {
    switch (version) {
      case LightAccountVersion.v110:
        return v110;
      case LightAccountVersion.v200:
        return v200;
    }
  }
}

/// Light Account function selectors.
class LightAccountSelectors {
  LightAccountSelectors._();

  /// execute(address dest, uint256 value, bytes calldata func)
  /// `keccak256("execute(address,uint256,bytes)")[0:4]` = 0xb61d27f6
  static const String execute = '0xb61d27f6';

  /// executeBatch(address[] dest, uint256[] values, bytes[] func)
  /// `keccak256("executeBatch(address[],uint256[],bytes[])")[0:4]` = 0x47e1da2a
  static const String executeBatch = '0x47e1da2a';

  /// createAccount(address owner, uint256 salt)
  /// `keccak256("createAccount(address,uint256)")[0:4]` = 0x5fbfb9cf
  static const String createAccount = '0x5fbfb9cf';
}

/// Light Account signature type prefixes (v2.0.0+).
class LightAccountSignatureType {
  LightAccountSignatureType._();

  /// EOA signature type (0x00).
  static const int eoa = 0x00;

  /// Contract signature type (0x01).
  static const int contract = 0x01;

  /// Contract signature with address (0x02).
  static const int contractWithAddr = 0x02;
}

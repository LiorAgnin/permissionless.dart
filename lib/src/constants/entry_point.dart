import '../types/address.dart';
import '../types/user_operation.dart';

/// Default EntryPoint contract addresses for ERC-4337.
///
/// EntryPoint is the singleton contract that processes UserOperations.
/// These addresses are the same across all EVM chains.
class EntryPointAddresses {
  EntryPointAddresses._();

  /// EntryPoint v0.6 address.
  ///
  /// Deployed at the same address on all chains.
  static final EthereumAddress v06 =
      EthereumAddress.fromHex('0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789');

  /// EntryPoint v0.7 address.
  ///
  /// Deployed at the same address on all chains.
  /// This is the recommended version for new deployments.
  static final EthereumAddress v07 =
      EthereumAddress.fromHex('0x0000000071727De22E5E9d8BAf0edAc6f37da032');

  /// EntryPoint v0.8 address.
  ///
  /// Deployed at the same address on all chains.
  static final EthereumAddress v08 =
      EthereumAddress.fromHex('0x4337084d9e255ff0702461cf8895ce9e3b5ff108');

  /// Gets the EntryPoint address for a given version.
  static EthereumAddress fromVersion(EntryPointVersion version) =>
      switch (version) {
        EntryPointVersion.v06 => v06,
        EntryPointVersion.v07 => v07,
        EntryPointVersion.v08 => v08,
      };
}

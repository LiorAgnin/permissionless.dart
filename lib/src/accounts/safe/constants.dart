import '../../types/address.dart';
import '../../types/user_operation.dart';

/// Safe smart account version.
enum SafeVersion {
  v1_4_1('1.4.1'),
  v1_5_0('1.5.0');

  const SafeVersion(this.value);

  final String value;
}

/// Contract addresses for Safe smart accounts.
class SafeAddresses {
  const SafeAddresses({
    required this.safeModuleSetupAddress,
    required this.safe4337ModuleAddress,
    required this.safeProxyFactoryAddress,
    required this.safeSingletonAddress,
    required this.multiSendAddress,
    required this.multiSendCallOnlyAddress,
    this.webAuthnSharedSignerAddress,
    this.safeP256VerifierAddress,
  });

  final EthereumAddress safeModuleSetupAddress;
  final EthereumAddress safe4337ModuleAddress;
  final EthereumAddress safeProxyFactoryAddress;
  final EthereumAddress safeSingletonAddress;
  final EthereumAddress multiSendAddress;
  final EthereumAddress multiSendCallOnlyAddress;
  final EthereumAddress? webAuthnSharedSignerAddress;
  final EthereumAddress? safeP256VerifierAddress;
}

/// ERC-7579 specific addresses for Safe modular accounts.
///
/// These addresses enable ERC-7579 module management on Safe accounts.
/// When `erc7579LaunchpadAddress` is provided to a Safe account, it switches
/// to ERC-7579 mode with full module management capabilities.
class Safe7579Addresses {
  Safe7579Addresses._();

  /// The Safe7579 module address that provides ERC-7579 compatibility.
  ///
  /// This module implements the ERC-7579 interface for Safe accounts,
  /// enabling module installation, uninstallation, and execution.
  static final EthereumAddress safe7579ModuleAddress =
      EthereumAddress.fromHex('0x7579EE8307284F293B1927136486880611F20002');

  /// The Safe7579 launchpad address for deploying ERC-7579 Safe accounts.
  ///
  /// The launchpad handles the initial setup of the ERC-7579 module
  /// and configures the Safe with the provided validators, executors,
  /// fallbacks, hooks, and attesters.
  static final EthereumAddress erc7579LaunchpadAddress =
      EthereumAddress.fromHex('0x7579011aB74c46090561ea277Ba79D510c6C00ff');

  /// The default Rhinestone attester address.
  ///
  /// By designating Rhinestone as an attester, only modules explicitly
  /// approved by Rhinestone can be installed on your Safe.
  static final EthereumAddress rhinestoneAttester =
      EthereumAddress.fromHex('0x000000333034E9f539ce08819E12c1b8Cb29084d');
}

/// Module initialization configuration for ERC-7579 Safe accounts.
///
/// Used to configure validators, executors, fallbacks, and hooks
/// during Safe 7579 deployment.
class Safe7579ModuleInit {
  const Safe7579ModuleInit({
    required this.module,
    this.initData = '0x',
  });

  /// The address of the module to install.
  final EthereumAddress module;

  /// Initialization data passed to the module's onInstall function.
  final String initData;
}

/// Safe version and EntryPoint version to addresses mapping.
///
/// These are the officially deployed Safe contract addresses.
class SafeVersionAddresses {
  SafeVersionAddresses._();

  static SafeAddresses? getAddresses(
    SafeVersion safeVersion,
    EntryPointVersion entryPointVersion,
  ) =>
      _addressMap[safeVersion]?[entryPointVersion];

  static final Map<SafeVersion, Map<EntryPointVersion, SafeAddresses>>
      _addressMap = {
    SafeVersion.v1_4_1: {
      EntryPointVersion.v06: SafeAddresses(
        safeModuleSetupAddress: EthereumAddress.fromHex(
          '0x8EcD4ec46D4D2a6B64fE960B3D64e8B94B2234eb',
        ),
        safe4337ModuleAddress: EthereumAddress.fromHex(
          '0xa581c4A4DB7175302464fF3C06380BC3270b4037',
        ),
        safeProxyFactoryAddress: EthereumAddress.fromHex(
          '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        ),
        safeSingletonAddress: EthereumAddress.fromHex(
          '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        ),
        multiSendAddress: EthereumAddress.fromHex(
          '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        ),
        multiSendCallOnlyAddress: EthereumAddress.fromHex(
          '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
        ),
      ),
      EntryPointVersion.v07: SafeAddresses(
        safeModuleSetupAddress: EthereumAddress.fromHex(
          '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        ),
        safe4337ModuleAddress: EthereumAddress.fromHex(
          '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        ),
        safeProxyFactoryAddress: EthereumAddress.fromHex(
          '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
        ),
        safeSingletonAddress: EthereumAddress.fromHex(
          '0x41675C099F32341bf84BFc5382aF534df5C7461a',
        ),
        multiSendAddress: EthereumAddress.fromHex(
          '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
        ),
        multiSendCallOnlyAddress: EthereumAddress.fromHex(
          '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
        ),
        webAuthnSharedSignerAddress: EthereumAddress.fromHex(
          '0xfD90FAd33ee8b58f32c00aceEad1358e4AFC23f9',
        ),
        safeP256VerifierAddress: EthereumAddress.fromHex(
          '0x445a0683e494ea0c5AF3E83c5159fBE47Cf9e765',
        ),
      ),
    },
    SafeVersion.v1_5_0: {
      EntryPointVersion.v07: SafeAddresses(
        safeModuleSetupAddress: EthereumAddress.fromHex(
          '0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47',
        ),
        safe4337ModuleAddress: EthereumAddress.fromHex(
          '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
        ),
        safeProxyFactoryAddress: EthereumAddress.fromHex(
          '0x14F2982D601c9458F93bd70B218933A6f8165e7b',
        ),
        safeSingletonAddress: EthereumAddress.fromHex(
          '0xFf51A5898e281Db6DfC7855790607438dF2ca44b',
        ),
        multiSendAddress: EthereumAddress.fromHex(
          '0x218543288004CD07832472D464648173c77D7eB7',
        ),
        multiSendCallOnlyAddress: EthereumAddress.fromHex(
          '0x0c28E9886f79618371c5Af86aA7e5Cf62dddd8dC',
        ),
        webAuthnSharedSignerAddress: EthereumAddress.fromHex(
          '0xfD90FAd33ee8b58f32c00aceEad1358e4AFC23f9',
        ),
        safeP256VerifierAddress: EthereumAddress.fromHex(
          '0x445a0683e494ea0c5AF3E83c5159fBE47Cf9e765',
        ),
      ),
    },
  };
}

/// Operation types for Safe transactions.
enum OperationType {
  call(0),
  delegateCall(1);

  const OperationType(this.value);

  final int value;
}

import '../../types/address.dart';
import '../../utils/erc7579.dart';
import '../account_support.dart';

/// Etherspot ModularEtherspotWallet contract addresses.
///
/// These are the official deployment addresses for the Etherspot
/// modular wallet infrastructure. The wallet is ERC-7579 compliant
/// and uses EntryPoint v0.7.
///
/// Note: Addresses differ per network. The defaults are for Sepolia testnet.
class EtherspotAddresses {
  EtherspotAddresses._();

  /// ModularEtherspotWalletFactory for deploying wallets.
  /// Deploys via CREATE2 with createAccount(bytes32 salt, bytes initCode).
  static final EthereumAddress factory = EthereumAddress.fromHex(
    '0x2A40091f044e48DEB5C0FCbc442E443F3341B451',
  );

  /// Bootstrap contract for initializing wallet modules.
  static final EthereumAddress bootstrap = EthereumAddress.fromHex(
    '0x0D5154d7751b6e2fDaa06F0cC9B400549394C8AA',
  );

  /// Multiple owner ECDSA validator module address.
  static final EthereumAddress ecdsaValidator = EthereumAddress.fromHex(
    '0x0740Ed7c11b9da33d9C80Bd76b826e4E90CC1906',
  );
}

/// ModularEtherspotWalletFactory `createAccount(bytes32 salt,
/// bytes initCode)`.
const String etherspotCreateAccountSignature = 'createAccount(bytes32,bytes)';

/// Bootstrap `initMSA(BootstrapConfig[] validators,
/// BootstrapConfig[] executors, BootstrapConfig hook,
/// BootstrapConfig[] fallbacks)` with
/// `BootstrapConfig = (address module, bytes data)`.
const String etherspotInitMsaSignature =
    'initMSA((address,bytes)[],(address,bytes)[],(address,bytes),'
    '(address,bytes)[])';

/// Module `onInstall(bytes data)`.
const String etherspotOnInstallSignature = 'onInstall(bytes)';

/// Function selectors for Etherspot contracts.
class EtherspotSelectors {
  EtherspotSelectors._();

  /// Factory: createAccount(bytes32 salt, bytes initCode)
  /// `keccak256("createAccount(bytes32,bytes)")[0:4]` = 0xf8a59370
  static const String createAccount = '0xf8a59370';

  /// Bootstrap: initMSA(BootstrapConfig[] validators, BootstrapConfig[] executors,
  ///   BootstrapConfig hook, BootstrapConfig[] fallbacks)
  /// where BootstrapConfig = (address module, bytes data)
  /// `keccak256("initMSA((address,bytes)[],(address,bytes)[],(address,bytes),(address,bytes)[])")[0:4]`
  static const String initMSA = '0x642219af';

  /// onInstall(bytes data) for validator initialization
  /// `keccak256("onInstall(bytes)")[0:4]`
  static const String onInstall = '0x6d61fe70';

  /// ModularEtherspotWallet: execute(bytes32 mode, bytes executionCalldata)
  /// Same as ERC-7579 standard.
  static const String execute = Erc7579Selectors.execute;
}

/// Dummy ECDSA signature for gas estimation.
const String etherspotDummyEcdsaSignature = ecdsaStubSignature;

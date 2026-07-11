import '../../types/address.dart';

/// Kernel smart account version.
///
/// Covers the full set of versions supported by permissionless.js
/// (`KernelVersion<entryPointVersion>`).
enum KernelVersion {
  /// Kernel v0.2.1 - EntryPoint v0.6 (no Kernel EIP-712 message wrap).
  v0_2_1('0.2.1'),

  /// Kernel v0.2.2 - EntryPoint v0.6 default (no Kernel EIP-712 message wrap).
  v0_2_2('0.2.2'),

  /// Kernel v0.2.3 - EntryPoint v0.6.
  v0_2_3('0.2.3'),

  /// Kernel v0.2.4 - EntryPoint v0.6.
  v0_2_4('0.2.4'),

  /// Kernel v0.3.0-beta - EntryPoint v0.7 default; 4-arg `initialize`.
  v0_3_0_beta('0.3.0-beta'),

  /// Kernel v0.3.1 - EntryPoint v0.7, ERC-7579, 5-arg `initialize`.
  v0_3_1('0.3.1'),

  /// Kernel v0.3.2 - EntryPoint v0.7, ERC-7579.
  v0_3_2('0.3.2'),

  /// Kernel v0.3.3 - EntryPoint v0.7 with EIP-7702 support.
  v0_3_3('0.3.3');

  const KernelVersion(this.value);

  /// Version string (e.g., "0.3.1", "0.3.0-beta").
  final String value;

  /// Whether this is a Kernel v0.2.x (EntryPoint v0.6) account.
  bool get isV2 =>
      this == v0_2_1 || this == v0_2_2 || this == v0_2_3 || this == v0_2_4;

  /// Whether this is a Kernel v0.3.x (EntryPoint v0.7) account.
  bool get isV3 => !isV2;

  /// Whether this version uses ERC-7579 encoding.
  bool get usesErc7579 => isV3;

  /// Whether this version requires a separate validator address.
  bool get hasExternalValidator => isV3;

  /// Whether this version supports EIP-7702.
  bool get supportsEip7702 => this == v0_3_3;

  /// Whether `signMessage` / `signTypedData` skip Kernel EIP-712 wrapping.
  ///
  /// Matches permissionless.js: only 0.2.1 and 0.2.2 sign without wrapping.
  bool get skipsKernelMessageWrap => this == v0_2_1 || this == v0_2_2;

  /// Whether this version uses the 4-arg `initialize(bytes21,address,bytes,bytes)`.
  ///
  /// 0.3.0-beta only; later v0.3.x use the 5-arg form with `bytes[] initConfig`.
  bool get usesBetaInitialize => this == v0_3_0_beta;

  /// Default Kernel version for the given EntryPoint version.
  ///
  /// Mirrors permissionless.js `getDefaultKernelVersion`:
  /// - EP v0.6 → `0.2.2`
  /// - EP v0.7 → `0.3.0-beta`
  static KernelVersion defaultForEntryPoint({required bool isEntryPointV06}) =>
      isEntryPointV06 ? v0_2_2 : v0_3_0_beta;
}

/// Contract addresses for a Kernel deployment.
class KernelAddresses {
  /// Creates a set of Kernel contract addresses.
  ///
  /// - [accountImplementation]: The Kernel account implementation address
  /// - [factory]: The factory contract for deploying accounts
  /// - [metaFactory]: Meta factory for v0.3.x deployments (optional)
  /// - [ecdsaValidator]: ECDSA validator address (optional)
  /// - [webAuthnValidator]: WebAuthn validator address for passkeys (optional)
  const KernelAddresses({
    required this.accountImplementation,
    required this.factory,
    this.metaFactory,
    this.ecdsaValidator,
    this.webAuthnValidator,
  });

  /// Account implementation address.
  final EthereumAddress accountImplementation;

  /// Factory contract address.
  final EthereumAddress factory;

  /// Meta factory for v0.3.x (deploys via factory).
  final EthereumAddress? metaFactory;

  /// ECDSA validator address.
  final EthereumAddress? ecdsaValidator;

  /// WebAuthn (P256) validator address for passkey support.
  final EthereumAddress? webAuthnValidator;
}

/// Version-specific Kernel addresses.
///
/// Source: permissionless.js `KERNEL_VERSION_TO_ADDRESSES_MAP`.
class KernelVersionAddresses {
  KernelVersionAddresses._();

  /// Get addresses for a specific Kernel version.
  static KernelAddresses? getAddresses(KernelVersion version) =>
      _addressMap[version];

  static final Map<KernelVersion, KernelAddresses> _addressMap = {
    KernelVersion.v0_2_1: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xf048AD83CB2dfd6037A43902a2A5Be04e53cd2Eb',
      ),
      factory: EthereumAddress.fromHex(
        '0x5de4839a76cf55d0c90e2061ef4386d962E15ae3',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0xd9AB5096a832b9ce79914329DAEE236f8Eea0390',
      ),
    ),
    KernelVersion.v0_2_2: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0x0DA6a956B9488eD4dd761E59f52FDc6c8068E6B5',
      ),
      factory: EthereumAddress.fromHex(
        '0x5de4839a76cf55d0c90e2061ef4386d962E15ae3',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0xd9AB5096a832b9ce79914329DAEE236f8Eea0390',
      ),
    ),
    KernelVersion.v0_2_3: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xD3F582F6B4814E989Ee8E96bc3175320B5A540ab',
      ),
      factory: EthereumAddress.fromHex(
        '0x5de4839a76cf55d0c90e2061ef4386d962E15ae3',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0xd9AB5096a832b9ce79914329DAEE236f8Eea0390',
      ),
    ),
    KernelVersion.v0_2_4: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xd3082872F8B06073A021b4602e022d5A070d7cfC',
      ),
      factory: EthereumAddress.fromHex(
        '0x5de4839a76cf55d0c90e2061ef4386d962E15ae3',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0xd9AB5096a832b9ce79914329DAEE236f8Eea0390',
      ),
    ),
    KernelVersion.v0_3_0_beta: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0x94F097E1ebEB4ecA3AAE54cabb08905B239A7D27',
      ),
      factory: EthereumAddress.fromHex(
        '0x6723b44Abeec4E71eBE3232BD5B455805baDD22f',
      ),
      metaFactory: EthereumAddress.fromHex(
        '0xd703aaE79538628d27099B8c4f621bE4CCd142d5',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0x8104e3Ad430EA6d354d013A6789fDFc71E671c43',
      ),
      webAuthnValidator: EthereumAddress.fromHex(
        '0x7ab16Ff354AcB328452F1D445b3Ddee9a91e9e69',
      ),
    ),
    KernelVersion.v0_3_1: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xBAC849bB641841b44E965fB01A4Bf5F074f84b4D',
      ),
      factory: EthereumAddress.fromHex(
        '0xaac5D4240AF87249B3f71BC8E4A2cae074A3E419',
      ),
      metaFactory: EthereumAddress.fromHex(
        '0xd703aaE79538628d27099B8c4f621bE4CCd142d5',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0x845ADb2C711129d4f3966735eD98a9F09fC4cE57',
      ),
      webAuthnValidator: EthereumAddress.fromHex(
        '0x7ab16Ff354AcB328452F1D445b3Ddee9a91e9e69',
      ),
    ),
    KernelVersion.v0_3_2: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xD830D15D3dc0C269F3dBAa0F3e8626d33CFdaBe1',
      ),
      factory: EthereumAddress.fromHex(
        '0x7a1dBAB750f12a90EB1B60D2Ae3aD17D4D81EfFe',
      ),
      metaFactory: EthereumAddress.fromHex(
        '0xd703aaE79538628d27099B8c4f621bE4CCd142d5',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0x845ADb2C711129d4f3966735eD98a9F09fC4cE57',
      ),
    ),
    // JS omits WEB_AUTHN_VALIDATOR for 0.3.3; Dart keeps the patched
    // validator as an intentional extension (parity audit O1).
    KernelVersion.v0_3_3: KernelAddresses(
      accountImplementation: EthereumAddress.fromHex(
        '0xd6CEDDe84be40893d153Be9d467CD6aD37875b28',
      ),
      factory: EthereumAddress.fromHex(
        '0x2577507b78c2008Ff367261CB6285d44ba5eF2E9',
      ),
      metaFactory: EthereumAddress.fromHex(
        '0xd703aaE79538628d27099B8c4f621bE4CCd142d5',
      ),
      ecdsaValidator: EthereumAddress.fromHex(
        '0x845ADb2C711129d4f3966735eD98a9F09fC4cE57',
      ),
      webAuthnValidator: EthereumAddress.fromHex(
        '0x7ab16Ff354AcB328452F1D445b3Ddee9a91e9e69',
      ),
    ),
  };
}

/// Function selectors for Kernel contracts.
class KernelSelectors {
  KernelSelectors._();

  /// v0.2.x: execute(address to, uint256 value, bytes data, uint8 operation)
  /// `keccak256("execute(address,uint256,bytes,uint8)")[0:4]` = 0x51945447
  static const String executeV2 = '0x51945447';

  /// v0.2.x: executeBatch((address to, uint256 value, bytes data)[] calls)
  /// `keccak256("executeBatch((address,uint256,bytes)[])")[0:4]` = 0x34fcd5be
  static const String executeBatchV2 = '0x34fcd5be';

  /// v0.3.x: execute(bytes32,bytes) - ERC-7579 standard
  /// `keccak256("execute(bytes32,bytes)")[0:4]` = 0xe9ae5c53
  static const String executeV3 = '0xe9ae5c53';

  /// v0.2.x: Factory createAccount(address,bytes,uint256)
  /// `keccak256("createAccount(address,bytes,uint256)")[0:4]` = 0x296601cd
  static const String createAccountV2 = '0x296601cd';

  /// v0.3.x: Inner factory createAccount(bytes,bytes32)
  /// `keccak256("createAccount(bytes,bytes32)")[0:4]` = 0xea6d13ac
  static const String createAccountV3 = '0xea6d13ac';

  /// v0.3.x: Meta factory deployWithFactory(address,bytes,bytes32)
  /// `keccak256("deployWithFactory(address,bytes,bytes32)")[0:4]` = 0xc5265d5d
  static const String deployWithFactory = '0xc5265d5d';

  /// v0.2.x: initialize(address,bytes)
  static const String initializeV2 = '0xd1f57894';

  /// v0.3.0-beta: initialize(bytes21,address,bytes,bytes)
  /// `keccak256("initialize(bytes21,address,bytes,bytes)")[0:4]` = 0x12af322c
  static const String initializeV3Beta = '0x12af322c';

  /// v0.3.1+: initialize(bytes21,address,bytes,bytes,bytes[])
  /// `keccak256("initialize(bytes21,address,bytes,bytes,bytes[])")[0:4]` = 0x3c3b752b
  static const String initializeV3 = '0x3c3b752b';
}

/// Kernel validator modes (v0.3.x).
class KernelValidatorMode {
  KernelValidatorMode._();

  /// Sudo/root mode - full permissions.
  static const int sudo = 0x00;

  /// Enable mode - validate and enable.
  static const int enable = 0x01;
}

/// Kernel validator types (v0.3.x).
class KernelValidatorType {
  KernelValidatorType._();

  /// Root validator type.
  static const int root = 0x00;

  /// Standard validator type.
  static const int validator = 0x01;

  /// Permission-based validator.
  static const int permission = 0x02;

  /// EIP-7702 validator type (same as root, but used for EIP-7702 accounts).
  static const int eip7702 = 0x00;
}

/// Dummy ECDSA signature for gas estimation.
const String kernelDummyEcdsaSignature =
    '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';

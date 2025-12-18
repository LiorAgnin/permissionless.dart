import '../../types/address.dart';

/// Kernel smart account version.
enum KernelVersion {
  /// Kernel v0.2.4 - Supports EntryPoint v0.6
  v0_2_4('0.2.4'),

  /// Kernel v0.3.1 - Supports EntryPoint v0.7, ERC-7579 compliant
  v0_3_1('0.3.1'),

  /// Kernel v0.3.3 - Supports EntryPoint v0.7 with EIP-7702 support
  v0_3_3('0.3.3');

  const KernelVersion(this.value);

  /// Version string (e.g., "0.3.1").
  final String value;

  /// Whether this version uses ERC-7579 encoding.
  bool get usesErc7579 => this == v0_3_1 || this == v0_3_3;

  /// Whether this version requires a separate validator address.
  bool get hasExternalValidator => this == v0_3_1 || this == v0_3_3;

  /// Whether this version supports EIP-7702.
  bool get supportsEip7702 => this == v0_3_3;
}

/// Contract addresses for a Kernel deployment.
class KernelAddresses {
  const KernelAddresses({
    required this.accountImplementation,
    required this.factory,
    this.metaFactory,
    this.ecdsaValidator,
  });

  /// Account implementation address.
  final EthereumAddress accountImplementation;

  /// Factory contract address.
  final EthereumAddress factory;

  /// Meta factory for v0.3.x (deploys via factory).
  final EthereumAddress? metaFactory;

  /// ECDSA validator address (v0.3.x only).
  final EthereumAddress? ecdsaValidator;
}

/// Version-specific Kernel addresses.
class KernelVersionAddresses {
  KernelVersionAddresses._();

  /// Get addresses for a specific Kernel version.
  static KernelAddresses? getAddresses(KernelVersion version) =>
      _addressMap[version];

  static final Map<KernelVersion, KernelAddresses> _addressMap = {
    // Kernel v0.2.4 (EntryPoint v0.6)
    // Addresses from permissionless.js KERNEL_VERSION_TO_ADDRESSES_MAP
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

    // Kernel v0.3.1 (EntryPoint v0.7)
    // Addresses from: https://github.com/zerodevapp/kernel
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
    ),

    // Kernel v0.3.3 (EntryPoint v0.7, EIP-7702 support)
    // Addresses from permissionless.js KERNEL_VERSION_TO_ADDRESSES_MAP
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
    ),
  };
}

/// Function selectors for Kernel contracts.
class KernelSelectors {
  KernelSelectors._();

  /// v0.2.x: execute(address,uint256,bytes,uint8)
  static const String executeV2 = '0xb61d27f6';

  /// v0.2.x: executeBatch((address,uint256,bytes)[])
  static const String executeBatchV2 = '0x47e1da2a';

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

  /// v0.3.x: initialize(bytes21,address,bytes,bytes,bytes[])
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

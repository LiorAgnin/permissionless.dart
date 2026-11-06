import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/erc7579.dart';
import '../../utils/message_hash.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../erc7579_calls.dart';
import 'constants.dart';
import 'kernel_abi.dart';
import 'kernel_erc1271.dart';

/// Owner abstraction for EIP-7702 Kernel accounts.
///
/// This owner can sign messages, typed data, and EIP-7702 authorizations.
abstract class Eip7702KernelOwner {
  /// Creates an [Eip7702KernelOwner].
  ///
  /// Implementations must provide signing methods for messages, typed data,
  /// and EIP-7702 authorizations.
  const Eip7702KernelOwner();

  /// The Ethereum address of this owner (the EOA).
  EthereumAddress get address;

  /// Signs [messageHash] as is (raw ECDSA, no EIP-191 prefix) and returns
  /// the 65-byte signature.
  Future<String> signHash(String messageHash);

  /// Signs EIP-712 typed data and returns the signature.
  Future<String> signTypedData(TypedData typedData);

  /// Creates an EIP-7702 authorization for this owner.
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  });
}

/// A local private key owner for EIP-7702 Kernel accounts.
class PrivateKeyEip7702KernelOwner implements Eip7702KernelOwner {
  /// Creates an owner from a hex-encoded private key.
  ///
  /// The [privateKeyHex] can optionally include the '0x' prefix.
  ///
  /// Example:
  /// ```dart
  /// final owner = PrivateKeyEip7702KernelOwner('0xac0974...');
  /// print(owner.address); // The EOA address derived from this key
  /// ```
  PrivateKeyEip7702KernelOwner(String privateKeyHex)
      : _owner = PrivateKeyOwner(privateKeyHex),
        _privateKeyHex = privateKeyHex;

  final PrivateKeyOwner _owner;
  final String _privateKeyHex;

  @override
  EthereumAddress get address => _owner.address;

  @override
  Future<String> signHash(String messageHash) =>
      _owner.signRawHash(messageHash);

  @override
  Future<String> signTypedData(TypedData typedData) =>
      _owner.signTypedData(typedData);

  @override
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  }) =>
      Eip7702Authorization.sign(
        chainId: chainId,
        contractAddress: contractAddress,
        nonce: nonce,
        privateKey: _privateKeyHex,
      );
}

/// Configuration for creating an EIP-7702 Kernel smart account.
class Eip7702KernelSmartAccountConfig {
  /// Creates a configuration for an EIP-7702 Kernel smart account.
  ///
  /// Required parameters:
  /// - [owner]: The EOA owner that controls this account
  /// - [chainId]: The chain ID for signature domain separation
  ///
  /// Optional parameters:
  /// - [version]: Kernel version (must support EIP-7702, defaults to v0.3.3)
  /// - [publicClient]: Client for checking deployment status (EIP-1271)
  /// - [accountLogicAddress]: Override the default Kernel implementation
  /// - [ecdsaValidatorAddress]: Override the default ECDSA validator
  ///
  /// Throws [ArgumentError] if the specified version doesn't support EIP-7702.
  Eip7702KernelSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.version = KernelVersion.v0_3_3,
    this.publicClient,
    EthereumAddress? accountLogicAddress,
    EthereumAddress? ecdsaValidatorAddress,
    this.nonceKey,
    this.entryPointAddress,
  })  : accountLogicAddress = accountLogicAddress ??
            KernelVersionAddresses.getAddresses(version)!.accountImplementation,
        ecdsaValidatorAddress = ecdsaValidatorAddress ??
            KernelVersionAddresses.getAddresses(version)!.ecdsaValidator! {
    if (!version.supportsEip7702) {
      throw ArgumentError(
        'Kernel version ${version.value} does not support EIP-7702. '
        'Use v0.3.3 or later.',
      );
    }
    checkKernelV3NonceKey(nonceKey, version);
  }

  /// The owner of this EIP-7702 account (the EOA).
  final Eip7702KernelOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Kernel version (must support EIP-7702).
  final KernelVersion version;

  /// Optional custom nonce key (≤ maxUint16, 2-byte slot).
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

  /// Public client for checking deployment status.
  ///
  /// Required for EIP-1271 signature validation to check if the account
  /// has been delegated (deployed) before signing messages/typed data.
  final PublicClient? publicClient;

  /// The Kernel account logic contract address for delegation.
  final EthereumAddress accountLogicAddress;

  /// The ECDSA validator address.
  final EthereumAddress ecdsaValidatorAddress;
}

/// An EIP-7702 Kernel smart account implementation.
///
/// This account uses EIP-7702 to delegate code execution from an EOA to
/// a Kernel account implementation. Key characteristics:
///
/// - **Account address = EOA address**: No separate smart account deployment
/// - **No factory needed**: The authorization delegates code on-demand
/// - **EntryPoint v0.7**: Uses standard v0.7 UserOperation format
/// - **ERC-7579 compliant**: Uses modular account encoding
/// - **Kernel EIP-712 domain**: Message signing uses Kernel-specific domain
///
/// Example:
/// ```dart
/// final account = createEip7702KernelSmartAccount(
///   owner: PrivateKeyEip7702KernelOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // The account address is the same as the owner's EOA address
/// final address = await account.getAddress();
/// print('EIP-7702 Kernel account: $address');
///
/// // Get authorization for submitting to bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
class Eip7702KernelSmartAccount
    implements Eip7702SmartAccount, EntryPointVersioned {
  /// Creates an EIP-7702 Kernel smart account from the given configuration.
  ///
  /// Prefer using [createEip7702KernelSmartAccount] factory function instead
  /// of calling this constructor directly.
  Eip7702KernelSmartAccount(this._config)
      : _accountOwner = _Eip7702KernelAccountOwner(_config.owner);

  final Eip7702KernelSmartAccountConfig _config;
  final _Eip7702KernelAccountOwner _accountOwner;

  /// The owner of this account.
  Eip7702KernelOwner get owner => _config.owner;

  /// The Kernel account logic contract address.
  @override
  EthereumAddress get accountLogicAddress => _config.accountLogicAddress;

  /// Whether this account uses EIP-7702 code delegation.
  @override
  bool get isEip7702 => true;

  /// The EntryPoint version (v0.7 for Kernel EIP-7702).
  @override
  EntryPointVersion get entryPointVersion => EntryPointVersion.v07;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for this account.
  ///
  /// For Kernel v3, the nonce key encodes: mode (1) + type (1) + validatorAddress (20) + salt (2).
  /// Uses ROOT type (0x00) with the ECDSA validator address.
  @override
  BigInt get nonceKey => encodeKernelV3NonceKey(
        validator: _config.ecdsaValidatorAddress,
        nonceKey: _config.nonceKey,
      );

  @override
  bool get isWebAuthn => false;

  /// Gets the address of this EIP-7702 account.
  ///
  /// For EIP-7702 accounts, this is the same as the owner's EOA address.
  @override
  Future<EthereumAddress> getAddress() async => _config.owner.address;

  /// Gets the init code for deploying this account.
  ///
  /// For EIP-7702 accounts, this returns '0x' as no deployment is needed.
  @override
  Future<String> getInitCode() async => '0x';

  /// Gets the factory address and data for UserOperation v0.7.
  ///
  /// For EIP-7702 accounts, this returns null as no factory is used.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async => null;

  /// Creates an EIP-7702 authorization for this account.
  ///
  /// The authorization must be included in the transaction that submits
  /// the UserOperation to enable the EOA to execute smart account code.
  ///
  /// [nonce] should be the EOA's current transaction nonce.
  @override
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce}) =>
      _config.owner.createAuthorization(
        chainId: _config.chainId,
        contractAddress: _config.accountLogicAddress,
        nonce: nonce,
      );

  /// Encodes a single call for execution using ERC-7579 format.
  @override
  String encodeCall(Call call) => encode7579Execute(call);

  /// Encodes multiple calls using ERC-7579 batch format.
  @override
  String encodeCalls(List<Call> calls) => encodeErc7579AccountCalls(calls);

  @override
  List<Call> decodeCalls(String callData) => decode7579Calls(callData).calls;

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  ///
  /// For Kernel v3 (including EIP-7702), the UserOperation signature is just
  /// the raw ECDSA signature without any validator identifier prefix.
  /// The validator identifier is only used for message/typedData signing (EIP-1271).
  @override
  String getStubSignature() => ecdsaStubSignature;

  /// Gets the EIP-7702 validator identifier.
  ///
  /// For EIP-7702, the identifier is just the type byte (0x00) with no address.
  /// Per permissionless.js: getEcdsaRootIdentifierForKernelV3(validatorAddress, eip7702)
  /// When eip7702=true: concatHex([VALIDATOR_TYPE.EIP7702, "0x"])
  String _getEip7702ValidatorIdentifier() =>
      Hex.fromBigInt(BigInt.from(KernelValidatorType.eip7702), byteLength: 1);

  /// Signs a UserOperation using v0.7 hash format.
  ///
  /// For Kernel v3 (including EIP-7702), the UserOperation is signed using
  /// EIP-191 personal_sign format: the UserOp hash is wrapped with
  /// "\x19Ethereum Signed Message:\n32" prefix before signing.
  ///
  /// This matches permissionless.js which uses owner.signMessage({ message: { raw: hash } }).
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) =>
      _accountOwner.signPersonalMessage(
        getUserOperationHash(
          userOperation: userOp,
          entryPointAddress: entryPoint,
          entryPointVersion: entryPointVersion,
          chainId: chainId,
          eip7702DelegationAddress: accountLogicAddress,
        ),
      );

  /// Signs a personal message using Kernel's EIP-712 wrapper.
  ///
  /// Kernel wraps messages in its own EIP-712 domain for 1271 compliance.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signMessage(String message) async {
    await _ensureDeployedForEip1271();
    final signature = await signKernelMessage(
      owner: _accountOwner,
      message: message,
      address: _config.owner.address,
      version: _config.version,
      chainId: _config.chainId,
      eip7702: true,
    );
    return Hex.concat([
      _getEip7702ValidatorIdentifier(),
      Hex.strip0x(signature),
    ]);
  }

  /// Signs EIP-712 typed data using Kernel's EIP-712 wrapper.
  ///
  /// Kernel wraps the typed data hash in its own EIP-712 domain.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    await _ensureDeployedForEip1271();
    final signature = await signKernelTypedData(
      owner: _accountOwner,
      typedData: typedData,
      address: _config.owner.address,
      version: _config.version,
      chainId: _config.chainId,
      eip7702: true,
    );
    return Hex.concat([
      _getEip7702ValidatorIdentifier(),
      Hex.strip0x(signature),
    ]);
  }

  Future<void> _ensureDeployedForEip1271() => ensureEip7702Delegated(
        accountName: 'Kernel with EIP-7702',
        publicClient: _config.publicClient,
        address: getAddress,
      );
}

/// Adapts [Eip7702KernelOwner] to [AccountOwner]: [signRawHash] is the
/// owner's raw `signHash`, [signPersonalMessage] is EIP-191 over the hash
/// bytes (viem `signMessage({ message: { raw } })`) signed raw.
class _Eip7702KernelAccountOwner extends AccountOwner {
  const _Eip7702KernelAccountOwner(this._owner);

  final Eip7702KernelOwner _owner;

  @override
  EthereumAddress get address => _owner.address;

  @override
  Future<String> signTypedData(TypedData typedData) =>
      _owner.signTypedData(typedData);

  @override
  Future<String> signRawHash(String hash) => _owner.signHash(hash);

  @override
  Future<String> signPersonalMessage(String hash) =>
      _owner.signHash(hashMessageBytes(Hex.decode(hash)));
}

/// Creates an EIP-7702 Kernel smart account.
///
/// This creates an account that uses EIP-7702 code delegation, enabling
/// an EOA to function as a Kernel smart account without deployment.
///
/// **Requirements:**
/// - EntryPoint v0.7 (automatically used)
/// - Bundler with EIP-7702 support
/// - Chain with EIP-7702 enabled
///
/// Example:
/// ```dart
/// final account = createEip7702KernelSmartAccount(
///   owner: PrivateKeyEip7702KernelOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // Account address = owner's EOA address
/// final address = await account.getAddress();
///
/// // Create authorization for bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
Eip7702KernelSmartAccount createEip7702KernelSmartAccount({
  required Eip7702KernelOwner owner,
  required BigInt chainId,
  KernelVersion version = KernelVersion.v0_3_3,
  PublicClient? publicClient,
  EthereumAddress? accountLogicAddress,
  EthereumAddress? ecdsaValidatorAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
}) =>
    Eip7702KernelSmartAccount(
      Eip7702KernelSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        version: version,
        publicClient: publicClient,
        accountLogicAddress: accountLogicAddress,
        ecdsaValidatorAddress: ecdsaValidatorAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
      ),
    );

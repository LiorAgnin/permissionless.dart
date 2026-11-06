import 'dart:convert';

import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/user_operation_hash.dart' as user_op_hash;
import '../account_owner.dart';
import '../account_support.dart';
import '../standard_execute.dart';
import 'constants.dart';

/// Owner abstraction for EIP-7702 Simple accounts.
///
/// This owner can sign both messages and EIP-7702 authorizations.
abstract class Eip7702SimpleAccountOwner {
  /// Creates an [Eip7702SimpleAccountOwner].
  ///
  /// Implementations must provide signing methods for messages, typed data,
  /// and EIP-7702 authorizations.
  const Eip7702SimpleAccountOwner();

  /// The Ethereum address of this owner (the EOA).
  EthereumAddress get address;

  /// Signs [messageHash] with the EIP-191 personal-message prefix
  /// (`"\x19Ethereum Signed Message:\n" + len + bytes`) and returns the
  /// 65-byte signature.
  Future<String> signHash(String messageHash);

  /// Signs EIP-712 typed data and returns the signature.
  Future<String> signTypedData(TypedData typedData);

  /// Creates an EIP-7702 authorization for this owner.
  ///
  /// The authorization allows the EOA to delegate code execution to
  /// the specified contract address.
  Future<Eip7702Authorization> createAuthorization({
    required BigInt chainId,
    required EthereumAddress contractAddress,
    required BigInt nonce,
  });
}

/// A local private key owner for EIP-7702 Simple accounts.
class PrivateKeyEip7702Owner implements Eip7702SimpleAccountOwner {
  /// Creates an owner from a hex-encoded private key.
  ///
  /// The [privateKeyHex] can optionally include the '0x' prefix.
  ///
  /// Example:
  /// ```dart
  /// final owner = PrivateKeyEip7702Owner('0xac0974...');
  /// print(owner.address); // The EOA address derived from this key
  /// ```
  PrivateKeyEip7702Owner(String privateKeyHex)
      : _owner = PrivateKeyOwner(privateKeyHex),
        _privateKeyHex = privateKeyHex;

  final PrivateKeyOwner _owner;
  final String _privateKeyHex;

  @override
  EthereumAddress get address => _owner.address;

  @override
  Future<String> signHash(String messageHash) =>
      _owner.signPersonalMessage(messageHash);

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

/// Configuration for creating an EIP-7702 Simple smart account.
class Eip7702SimpleSmartAccountConfig {
  /// Creates a configuration for an EIP-7702 Simple smart account.
  ///
  /// Required parameters:
  /// - [owner]: The EOA owner that controls this account
  /// - [chainId]: The chain ID for signature domain separation
  ///
  /// Optional parameters:
  /// - [publicClient]: Client for checking deployment status (EIP-1271)
  /// - [accountLogicAddress]: Override the default Simple7702Account logic
  Eip7702SimpleSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.publicClient,
    EthereumAddress? accountLogicAddress,
    this.nonceKey,
    this.entryPointAddress,
  }) : accountLogicAddress =
            accountLogicAddress ?? Simple7702AccountAddresses.defaultLogic;

  /// The owner of this EIP-7702 account (the EOA).
  final Eip7702SimpleAccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Public client for checking deployment status.
  ///
  /// Required for EIP-1271 signature validation to check if the account
  /// has been delegated (deployed) before signing messages/typed data.
  final PublicClient? publicClient;

  /// The Simple7702Account logic contract address.
  ///
  /// Defaults to the official eth-infinitism Simple7702Account.
  final EthereumAddress accountLogicAddress;

  /// Optional custom nonce key for parallel transaction support.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override (defaults to v0.8 canonical).
  final EthereumAddress? entryPointAddress;
}

/// An EIP-7702 Simple smart account implementation.
///
/// This account uses EIP-7702 to delegate code execution from an EOA to
/// a Simple7702Account implementation. Key characteristics:
///
/// - **Account address = EOA address**: No separate smart account deployment
/// - **No factory needed**: The authorization delegates code on-demand
/// - **EntryPoint v0.8**: Required for native EIP-7702 support
/// - **Typed data signing**: v0.8 uses EIP-712 typed data for UserOperation signing
///
/// Example:
/// ```dart
/// final account = createEip7702SimpleSmartAccount(
///   owner: PrivateKeyEip7702Owner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // The account address is the same as the owner's EOA address
/// final address = await account.getAddress();
/// print('EIP-7702 account: $address');
///
/// // Get authorization for submitting to bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
class Eip7702SimpleSmartAccount
    implements Eip7702SmartAccount, EntryPointVersioned {
  /// Creates an EIP-7702 Simple smart account from the given configuration.
  ///
  /// Prefer using [createEip7702SimpleSmartAccount] factory function instead
  /// of calling this constructor directly.
  Eip7702SimpleSmartAccount(this._config);

  final Eip7702SimpleSmartAccountConfig _config;

  /// The owner of this account.
  Eip7702SimpleAccountOwner get owner => _config.owner;

  /// The Simple7702Account logic contract address.
  @override
  EthereumAddress get accountLogicAddress => _config.accountLogicAddress;

  /// Whether this account uses EIP-7702 code delegation.
  @override
  bool get isEip7702 => true;

  /// The EntryPoint version (always v0.8 for EIP-7702).
  @override
  EntryPointVersion get entryPointVersion => EntryPointVersion.v08;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

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
  /// The authorization handles code delegation.
  @override
  Future<String> getInitCode() async => '0x';

  /// Gets the factory address and data for UserOperation v0.7/v0.8.
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
  ///
  /// Example:
  /// ```dart
  /// final nonce = await publicClient.getTransactionCount(ownerAddress);
  /// final auth = await account.getAuthorization(nonce: nonce);
  /// ```
  @override
  Future<Eip7702Authorization> getAuthorization({required BigInt nonce}) =>
      _config.owner.createAuthorization(
        chainId: _config.chainId,
        contractAddress: _config.accountLogicAddress,
        nonce: nonce,
      );

  /// Encodes a single call as `execute(address,uint256,bytes)`.
  @override
  String encodeCall(Call call) => encodeExecute(call);

  /// Encodes multiple calls using the v0.8
  /// `executeBatch((address,uint256,bytes)[])` format.
  @override
  String encodeCalls(List<Call> calls) =>
      encodeExecuteCalls(calls, ExecuteBatchAbi.callTuples);

  @override
  List<Call> decodeCalls(String callData) =>
      decodeExecuteCalls(callData, ExecuteBatchAbi.callTuples);

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() => ecdsaStubSignature;

  /// Signs a UserOperation using EIP-712 typed data (v0.8 format).
  ///
  /// EntryPoint v0.8 uses typed data signing instead of raw hash signing.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async =>
      _config.owner.signTypedData(getUserOperationTypedData(userOp));

  /// Gets the typed data for a UserOperation (for debugging).
  ///
  /// When the operation's factory is the EIP-7702 marker, `initCode` is
  /// `accountLogicAddress ‖ factoryData`, as the EntryPoint hashes it.
  TypedData getUserOperationTypedData(UserOperationV07 userOp) =>
      user_op_hash.getUserOperationTypedData(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        chainId: _config.chainId,
        eip7702DelegationAddress: accountLogicAddress,
      );

  /// Gets the hash of the UserOperation typed data (for debugging).
  String getUserOperationHash(UserOperationV07 userOp) =>
      user_op_hash.getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: entryPointVersion,
        chainId: _config.chainId,
        eip7702DelegationAddress: accountLogicAddress,
      );

  /// Signs a personal message (EIP-191).
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signMessage(String message) async {
    await _ensureDeployedForEip1271();
    // Simple7702Account.isValidSignature recovers against hashMessage(message)
    // with no further prefix, and signHash applies the EIP-191 prefix itself,
    // so it signs the raw message bytes (viem `signMessage`).
    return _config.owner.signHash(Hex.fromBytes(utf8.encode(message)));
  }

  /// Signs EIP-712 typed data.
  ///
  /// **Note:** For EIP-7702 accounts, EIP-1271 signature validation only works
  /// after the account has been delegated. If a `publicClient` is provided,
  /// this method will check deployment status and throw if not delegated.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    await _ensureDeployedForEip1271();
    return _config.owner.signTypedData(typedData);
  }

  /// Checks if the account is deployed (delegated) before EIP-1271 signing.
  ///
  /// EIP-7702 accounts are not EIP-1271 compliant before delegation because
  /// the EOA has no code to execute `isValidSignature`.
  Future<void> _ensureDeployedForEip1271() async {
    if (_config.publicClient == null) return;

    final address = await getAddress();
    final isDeployed = await _config.publicClient!.isDeployed(address);
    if (!isDeployed) {
      throw StateError(
        'EIP-7702 Simple account is not EIP-1271 compliant before delegation. '
        'Submit a UserOperation with the EIP-7702 authorization first.',
      );
    }
  }
}

/// Creates an EIP-7702 Simple smart account.
///
/// This creates an account that uses EIP-7702 code delegation, enabling
/// an EOA to function as a smart account without deploying a separate contract.
///
/// **Requirements:**
/// - EntryPoint v0.8 (automatically used)
/// - Bundler with EIP-7702 support
/// - Chain with EIP-7702 enabled
///
/// Example:
/// ```dart
/// final account = createEip7702SimpleSmartAccount(
///   owner: PrivateKeyEip7702Owner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// // Account address = owner's EOA address
/// final address = await account.getAddress();
///
/// // Create authorization for bundler
/// final auth = await account.getAuthorization(nonce: BigInt.zero);
/// ```
Eip7702SimpleSmartAccount createEip7702SimpleSmartAccount({
  required Eip7702SimpleAccountOwner owner,
  required BigInt chainId,
  PublicClient? publicClient,
  EthereumAddress? accountLogicAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
}) =>
    Eip7702SimpleSmartAccount(
      Eip7702SimpleSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        publicClient: publicClient,
        accountLogicAddress: accountLogicAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
      ),
    );

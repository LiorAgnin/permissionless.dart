import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/message_hash.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../standard_execute.dart';
import 'constants.dart';

/// Configuration for creating a Simple smart account.
class SimpleSmartAccountConfig {
  /// Creates a configuration for a Simple smart account.
  ///
  /// - [owner]: The owner of this Simple account
  /// - [chainId]: Chain ID for signature domain
  /// - [entryPointVersion]: EntryPoint version (defaults to v0.7)
  /// - [salt]: Salt for deterministic address generation (defaults to 0)
  /// - [nonceKey]: Custom nonce key for parallel transactions (defaults to 0)
  /// - [entryPointAddress]: Override the canonical EntryPoint address
  SimpleSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? salt,
    this.customFactoryAddress,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  }) : salt = salt ?? BigInt.zero;

  /// The owner of this Simple account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// The EntryPoint version to use.
  final EntryPointVersion entryPointVersion;

  /// Salt for deterministic address generation.
  final BigInt salt;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom nonce key for parallel transaction support.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override (defaults to the canonical address
  /// for [entryPointVersion]).
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  ///
  /// If provided, the account address will be computed using
  /// [PublicClient.getSenderAddress] which simulates account deployment.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  ///
  /// If provided, this address will be used instead of RPC computation.
  /// Use when you already know the account address.
  final EthereumAddress? address;
}

/// A Simple smart account implementation for ERC-4337.
///
/// This is the minimal reference implementation from eth-infinitism.
/// Unlike Safe accounts, Simple accounts have:
/// - Single owner (no multi-sig)
/// - Direct signature validation (no EIP-712 SafeOp)
/// - Built-in execute/executeBatch (no modules)
///
/// Example:
/// ```dart
/// final account = createSimpleSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Simple account: $address');
/// ```
class SimpleSmartAccount implements SmartAccount, SmartAccountV06 {
  /// Creates a Simple smart account from the given configuration.
  ///
  /// Prefer using [createSimpleSmartAccount] factory function instead
  /// of calling this constructor directly.
  SimpleSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            SimpleAccountFactoryAddresses.fromVersion(
              _config.entryPointVersion,
            );

  final SimpleSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version being used.
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The salt used for address derivation.
  BigInt get salt => _config.salt;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address for this account.
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(_config.entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Simple account.
  ///
  /// Uses the configured `address`, otherwise asks the EntryPoint via
  /// [PublicClient.getSenderAddress].
  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Simple',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  /// Gets the init code for deploying this Simple account.
  ///
  /// This is used in the UserOperation when the account doesn't exist yet.
  @override
  Future<String> getInitCode() async => packUserOperationInitCode(
        factory: _factoryAddress,
        factoryData: _createAccountData(),
      );

  /// Gets the factory address and data for UserOperation v0.7.
  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async =>
          (factory: _factoryAddress, factoryData: _createAccountData());

  String _createAccountData() => AbiEncoder.encodeFunctionData(
        'createAccount(address,uint256)',
        [_config.owner.address, _config.salt],
      );

  ExecuteBatchAbi get _executeBatchAbi => switch (_config.entryPointVersion) {
        EntryPointVersion.v06 => ExecuteBatchAbi.addressesAndBytes,
        EntryPointVersion.v07 => ExecuteBatchAbi.addressesValuesAndBytes,
        EntryPointVersion.v08 => ExecuteBatchAbi.callTuples,
      };

  /// Encodes a single call as `execute(address,uint256,bytes)`.
  @override
  String encodeCall(Call call) => encodeExecute(call);

  /// Encodes multiple calls using the version-specific executeBatch ABI.
  ///
  /// - v0.6: `executeBatch(address[],bytes[])` (`0x18dfb3c7`); the v0.6
  ///   SimpleAccount has no values array, so call values are dropped
  ///   (permissionless.js parity)
  /// - v0.7: `executeBatch(address[],uint256[],bytes[])` (`0x47e1da2a`)
  /// - v0.8: `executeBatch((address,uint256,bytes)[])` (`0x34fcd5be`)
  @override
  String encodeCalls(List<Call> calls) =>
      encodeExecuteCalls(calls, _executeBatchAbi);

  @override
  List<Call> decodeCalls(String callData) =>
      decodeExecuteCalls(callData, _executeBatchAbi);

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  ///
  /// Returns a 65-byte dummy signature that can pass basic validation.
  /// This signature format is compatible with ERC-4337 bundler simulation.
  @override
  String getStubSignature() => ecdsaStubSignature;

  /// Signs a UserOperation for EntryPoint v0.7 or v0.8.
  ///
  /// - v0.7: EIP-191 personal-sign of the packed userOpHash
  /// - v0.8: EIP-712 typed data over PackedUserOperation (same as 7702 path)
  /// - v0.6: throws — use [signUserOperationV06] instead
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    switch (_config.entryPointVersion) {
      case EntryPointVersion.v06:
        throw UnsupportedError(
          'Simple account configured for EntryPoint v0.6. '
          'Use signUserOperationV06 instead.',
        );
      case EntryPointVersion.v07:
        return _config.owner.signPersonalMessage(
          getUserOperationHash(
            userOperation: userOp,
            entryPointAddress: entryPoint,
            entryPointVersion: EntryPointVersion.v07,
            chainId: _config.chainId,
          ),
        );
      case EntryPointVersion.v08:
        return _config.owner.signTypedData(
          getUserOperationTypedData(
            userOperation: userOp,
            entryPointAddress: entryPoint,
            chainId: _config.chainId,
          ),
        );
    }
  }

  /// Signs a UserOperation for EntryPoint v0.6.
  ///
  /// Uses the v0.6 userOpHash layout (unpacked gas fields) and EIP-191
  /// personal-sign, matching permissionless.js / viem.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) async {
    if (_config.entryPointVersion != EntryPointVersion.v06) {
      throw UnsupportedError(
        'signUserOperationV06 requires EntryPoint v0.6. '
        'This account is configured for ${_config.entryPointVersion.name}.',
      );
    }
    return _config.owner.signPersonalMessage(
      getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: EntryPointVersion.v06,
        chainId: _config.chainId,
      ),
    );
  }

  /// Signs a personal message (EIP-191).
  ///
  /// Returns the raw ECDSA signature.
  @override
  Future<String> signMessage(String message) async =>
      _config.owner.signPersonalMessage(hashMessage(message));

  /// Signs EIP-712 typed data.
  ///
  /// Returns the raw ECDSA signature.
  @override
  Future<String> signTypedData(TypedData typedData) async =>
      _config.owner.signTypedData(typedData);
}

/// Creates a Simple smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createSimpleSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Simple account: $address');
/// ```
SimpleSmartAccount createSimpleSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  BigInt? salt,
  EthereumAddress? customFactoryAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    SimpleSmartAccount(
      SimpleSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        entryPointVersion: entryPointVersion,
        salt: salt,
        customFactoryAddress: customFactoryAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

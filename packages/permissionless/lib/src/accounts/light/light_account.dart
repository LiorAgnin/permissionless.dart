import '../../clients/public/public_client.dart';
import '../../clients/smart_account/smart_account_interface.dart';
import '../../constants/entry_point.dart';
import '../../types/address.dart';
import '../../types/eip7702.dart';
import '../../types/hex.dart';
import '../../types/typed_data.dart';
import '../../types/user_operation.dart';
import '../../utils/encoding.dart';
import '../../utils/message_hash.dart';
import '../../utils/user_operation_hash.dart';
import '../account_owner.dart';
import '../account_support.dart';
import '../standard_execute.dart';
import '../wrapped_message.dart';
import 'constants.dart';

/// Configuration for creating a Light smart account.
class LightSmartAccountConfig {
  /// Creates a configuration for an Alchemy Light smart account.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for signature domain
  /// - [entryPointVersion]: EntryPoint version (defaults to v0.7)
  /// - [version]: Light Account version (auto-selected based on EntryPoint)
  /// - [salt]: Salt for deterministic address generation (defaults to 0)
  /// - [nonceKey]: Custom nonce key for parallel transactions (defaults to 0)
  /// - [entryPointAddress]: Override the canonical EntryPoint address
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  ///
  /// The only supported pairs are v1.1.0 with EntryPoint v0.6 and v2.0.0 with
  /// EntryPoint v0.7; any other [version] / [entryPointVersion] combination
  /// throws [ArgumentError].
  LightSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.entryPointVersion = EntryPointVersion.v07,
    BigInt? salt,
    this.customFactoryAddress,
    LightAccountVersion? version,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  })  : salt = salt ?? BigInt.zero,
        version = _supportedVersion(version, entryPointVersion);

  // permissionless.js pairs LightAccount 1.1.0 with EntryPoint 0.6 and 2.0.0
  // with 0.7; other pairings sign a hash the EntryPoint does not verify.
  static LightAccountVersion _supportedVersion(
    LightAccountVersion? version,
    EntryPointVersion entryPointVersion,
  ) {
    final supported = LightAccountVersion.forEntryPoint(entryPointVersion);
    if (version != null && version != supported) {
      throw ArgumentError.value(
        version,
        'version',
        'Light Account ${version.version} does not support EntryPoint '
            '${entryPointVersion.value}; use ${supported.version}',
      );
    }
    return supported;
  }

  /// The owner of this Light account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// The EntryPoint version to use.
  final EntryPointVersion entryPointVersion;

  /// Light Account version.
  final LightAccountVersion version;

  /// Salt for deterministic address generation.
  final BigInt salt;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom nonce key for parallel transaction support.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
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

/// An Alchemy Light Account implementation for ERC-4337.
///
/// Light Account is a simple, gas-efficient smart account from Alchemy.
/// It features:
/// - Single owner (ECDSA validation)
/// - EIP-1271 signature validation with wrapped messages
/// - execute/executeBatch for transaction batching
/// - Low gas overhead
///
/// Example:
/// ```dart
/// final account = createLightSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Light account: $address');
/// ```
class LightSmartAccount
    implements SmartAccount, SmartAccountV06, EntryPointVersioned {
  /// Creates a Light smart account from the given configuration.
  ///
  /// Prefer using [createLightSmartAccount] factory function instead
  /// of calling this constructor directly.
  LightSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            LightAccountFactoryAddresses.fromVersion(_config.version);

  final LightSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The Light Account version.
  LightAccountVersion get version => _config.version;

  /// The EntryPoint version being used.
  @override
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The salt used for address derivation.
  BigInt get salt => _config.salt;

  @override
  BigInt get chainId => _config.chainId;

  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(_config.entryPointVersion);

  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Light account.
  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Light',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  @override
  Future<String> getInitCode() async => packUserOperationInitCode(
        factory: _factoryAddress,
        factoryData: _createAccountData(),
      );

  @override
  Future<({EthereumAddress factory, String factoryData})?>
      getFactoryData() async =>
          (factory: _factoryAddress, factoryData: _createAccountData());

  String _createAccountData() => AbiEncoder.encodeFunctionData(
        'createAccount(address,uint256)',
        [_config.owner.address, _config.salt],
      );

  @override
  String encodeCall(Call call) => encodeExecute(call);

  @override
  String encodeCalls(List<Call> calls) =>
      encodeExecuteCalls(calls, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  List<Call> decodeCalls(String callData) =>
      decodeExecuteCalls(callData, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  Future<String> sign(String hash) => signMessage(hash);

  @override
  String getStubSignature() => _withSignatureType(ecdsaStubSignature);

  /// Signs a UserOperation for EntryPoint v0.7.
  ///
  /// For v0.6 accounts, use [signUserOperationV06] instead.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) async {
    if (_config.entryPointVersion == EntryPointVersion.v06) {
      throw UnsupportedError(
        'Light account configured for EntryPoint v0.6. '
        'Use signUserOperationV06 instead.',
      );
    }

    final signature = await _config.owner.signPersonalMessage(
      getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: EntryPointVersion.v07,
        chainId: _config.chainId,
      ),
    );
    return _withSignatureType(signature);
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

    // v1.1.0 (EP v0.6) has no signature-type prefix.
    return _config.owner.signPersonalMessage(
      getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: EntryPointVersion.v06,
        chainId: _config.chainId,
      ),
    );
  }

  @override
  Future<String> signMessage(String message) =>
      _signLightAccountMessage(hashMessage(message));

  @override
  Future<String> signTypedData(TypedData typedData) =>
      _signLightAccountMessage(hashTypedData(typedData));

  /// Signs [hashedMessage] through the LightAccountMessage EIP-712 wrapper.
  Future<String> _signLightAccountMessage(String hashedMessage) async {
    final typedData = wrappedMessageTypedData(
      domainName: 'LightAccount',
      domainVersion: '1',
      chainId: _config.chainId,
      verifyingContract: await getAddress(),
      primaryType: 'LightAccountMessage',
      message: hashedMessage,
    );

    // Sign the EIP-712 digest raw (no EIP-191 prefix). LightAccount's
    // on-chain isValidSignature recovers against this digest.
    return _withSignatureType(await _config.owner.signTypedData(typedData));
  }

  /// LightAccount v2.0.0 expects a leading signature-type byte (EOA = 0x00);
  /// v1.1.0 takes the bare signature.
  String _withSignatureType(String signature) =>
      _config.version == LightAccountVersion.v200
          ? Hex.concat([
              Hex.fromBigInt(
                BigInt.from(LightAccountSignatureType.eoa),
                byteLength: 1,
              ),
              signature,
            ])
          : signature;
}

/// Creates an Alchemy Light smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createLightSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Light account: $address');
/// ```
LightSmartAccount createLightSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  LightAccountVersion? version,
  BigInt? salt,
  EthereumAddress? customFactoryAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    LightSmartAccount(
      LightSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        entryPointVersion: entryPointVersion,
        version: version,
        salt: salt,
        customFactoryAddress: customFactoryAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );

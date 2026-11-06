import 'dart:convert';
import 'dart:typed_data';

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
import '../wrapped_message.dart';
import 'constants.dart';

// permissionless.js ships Thirdweb factories for EntryPoint 0.6 and 0.7 only.
final _factories = {
  EntryPointVersion.v06: ThirdwebAddresses.factoryV06,
  EntryPointVersion.v07: ThirdwebAddresses.factoryV07,
};

/// Configuration for creating a Thirdweb smart account.
class ThirdwebSmartAccountConfig {
  /// Creates a configuration for a Thirdweb smart account.
  ///
  /// Thirdweb accounts support both EntryPoint v0.6 and v0.7.
  ///
  /// - [owner]: The account owner who controls the account
  /// - [chainId]: Chain ID for the network
  /// - [salt]: Salt for deterministic address generation. Treated as a UTF-8
  ///   string (matching permissionless.js `toHex(salt)`), not as hex. Empty or
  ///   the historical default `"0x"` produce empty salt bytes.
  /// - [entryPointVersion]: EntryPoint version (defaults to v0.7); v0.8
  ///   throws [ArgumentError]
  /// - [nonceKey]: Custom nonce key for parallel transaction support
  /// - [entryPointAddress]: Override the canonical EntryPoint address
  /// - [publicClient]: For RPC-based address computation (recommended)
  /// - [address]: Pre-computed address (alternative to publicClient)
  ThirdwebSmartAccountConfig({
    required this.owner,
    required this.chainId,
    this.salt = '0x',
    EntryPointVersion entryPointVersion = EntryPointVersion.v07,
    this.customFactoryAddress,
    this.nonceKey,
    this.entryPointAddress,
    this.publicClient,
    this.address,
  }) : entryPointVersion = _supportedEntryPointVersion(entryPointVersion);

  static EntryPointVersion _supportedEntryPointVersion(
    EntryPointVersion version,
  ) {
    if (!_factories.containsKey(version)) {
      throw ArgumentError.value(
        version,
        'entryPointVersion',
        'Thirdweb accounts support EntryPoint v0.6 and v0.7 only',
      );
    }
    return version;
  }

  /// The owner of this Thirdweb account.
  final AccountOwner owner;

  /// Chain ID for signature domain.
  final BigInt chainId;

  /// Salt for deterministic address generation.
  ///
  /// Encoded as UTF-8 bytes (permissionless.js `toHex(salt)`), not hex-decoded.
  final String salt;

  /// EntryPoint version (default: v0.7).
  final EntryPointVersion entryPointVersion;

  /// Optional custom factory address.
  final EthereumAddress? customFactoryAddress;

  /// Optional custom nonce key.
  final BigInt? nonceKey;

  /// Optional EntryPoint address override.
  final EthereumAddress? entryPointAddress;

  /// Public client for computing the account address via RPC.
  final PublicClient? publicClient;

  /// Pre-computed account address (optional).
  final EthereumAddress? address;
}

/// A Thirdweb smart account implementation for ERC-4337.
///
/// Thirdweb accounts support both EntryPoint v0.6 and v0.7.
///
/// Example:
/// ```dart
/// final account = createThirdwebSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
/// );
///
/// final address = await account.getAddress();
/// print('Thirdweb account: $address');
/// ```
class ThirdwebSmartAccount
    implements SmartAccount, SmartAccountV06, EntryPointVersioned {
  /// Creates a Thirdweb smart account from the given configuration.
  ///
  /// Prefer using [createThirdwebSmartAccount] factory function instead
  /// of calling this constructor directly.
  ThirdwebSmartAccount(this._config)
      : _factoryAddress = _config.customFactoryAddress ??
            _factories[_config.entryPointVersion]!;

  final ThirdwebSmartAccountConfig _config;
  final EthereumAddress _factoryAddress;
  EthereumAddress? _cachedAddress;

  /// The owner of this account.
  AccountOwner get owner => _config.owner;

  /// The EntryPoint version.
  @override
  EntryPointVersion get entryPointVersion => _config.entryPointVersion;

  /// The chain ID.
  @override
  BigInt get chainId => _config.chainId;

  /// The EntryPoint address.
  @override
  EthereumAddress get entryPoint =>
      _config.entryPointAddress ??
      EntryPointAddresses.fromVersion(_config.entryPointVersion);

  /// The nonce key for parallel transaction support.
  @override
  BigInt get nonceKey => _config.nonceKey ?? BigInt.zero;

  @override
  bool get isWebAuthn => false;

  /// Gets the deterministic address of this Thirdweb account.
  ///
  /// Uses the configured `address`, otherwise asks the EntryPoint via
  /// [PublicClient.getSenderAddress].
  @override
  Future<EthereumAddress> getAddress() async =>
      _cachedAddress ??= await resolveCounterfactualAddress(
        accountName: 'Thirdweb',
        address: _config.address,
        publicClient: _config.publicClient,
        entryPoint: entryPoint,
        initCode: getInitCode,
      );

  /// Gets the init code for deploying this Thirdweb account.
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
        'createAccount(address,bytes)',
        [_config.owner.address, _saltToBytes(_config.salt)],
      );

  /// Converts the salt config string to bytes matching permissionless.js.
  ///
  /// JS uses `salt ? toHex(salt) : "0x"` where `toHex` on a string is UTF-8.
  /// Empty string and the historical Dart default `"0x"` map to empty bytes
  /// (JS omitted / falsy salt).
  static Uint8List _saltToBytes(String salt) {
    if (salt.isEmpty || salt == '0x') {
      return Uint8List(0);
    }
    return Uint8List.fromList(utf8.encode(salt));
  }

  /// Encodes a single call as `execute(address,uint256,bytes)`.
  @override
  String encodeCall(Call call) => encodeExecute(call);

  /// Encodes multiple calls as `executeBatch(address[],uint256[],bytes[])`.
  @override
  String encodeCalls(List<Call> calls) =>
      encodeExecuteCalls(calls, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  List<Call> decodeCalls(String callData) =>
      decodeExecuteCalls(callData, ExecuteBatchAbi.addressesValuesAndBytes);

  @override
  Future<String> sign(String hash) => signMessage(hash);

  /// Gets a stub signature for gas estimation.
  @override
  String getStubSignature() => ecdsaStubSignature;

  /// Signs a UserOperation for EntryPoint v0.7.
  ///
  /// For v0.6 accounts, use [signUserOperationV06] instead.
  @override
  Future<String> signUserOperation(UserOperationV07 userOp) =>
      _signUserOperation(userOp);

  /// Signs a UserOperation for EntryPoint v0.6.
  ///
  /// Uses the v0.6 userOpHash layout (unpacked gas fields) and EIP-191
  /// personal-sign, matching permissionless.js / viem.
  @override
  Future<String> signUserOperationV06(UserOperationV06 userOp) =>
      _signUserOperation(userOp);

  Future<String> _signUserOperation(UserOperation userOp) async {
    checkUserOperationLayout(
      accountName: 'Thirdweb',
      entryPointVersion: entryPointVersion,
      userOperation: userOp,
    );
    return _config.owner.signPersonalMessage(
      getUserOperationHash(
        userOperation: userOp,
        entryPointAddress: entryPoint,
        entryPointVersion: entryPointVersion,
        chainId: chainId,
      ),
    );
  }

  /// Signs a personal message (EIP-191) with Thirdweb wrapper.
  @override
  Future<String> signMessage(String message) =>
      _signAccountMessage(hashMessage(message));

  /// Signs EIP-712 typed data with Thirdweb wrapper.
  ///
  /// Typed data whose verifying contract is this account is signed as-is.
  @override
  Future<String> signTypedData(TypedData typedData) async {
    if (typedData.domain.verifyingContract == await getAddress()) {
      return _config.owner.signTypedData(typedData);
    }
    return _signAccountMessage(hashTypedData(typedData));
  }

  /// Signs [hashedMessage] through the AccountMessage EIP-712 wrapper.
  Future<String> _signAccountMessage(String hashedMessage) async =>
      // Sign the AccountMessage EIP-712 digest raw (no EIP-191 prefix).
      _config.owner.signTypedData(
        wrappedMessageTypedData(
          domainName: 'Account',
          domainVersion: '1',
          chainId: _config.chainId,
          verifyingContract: await getAddress(),
          primaryType: 'AccountMessage',
          message: hashedMessage,
        ),
      );
}

/// Creates a Thirdweb smart account.
///
/// You must provide either [publicClient] or [address] for address computation:
/// - [publicClient] - Address will be computed automatically via RPC (recommended)
/// - [address] - Use a pre-computed address
///
/// [salt] is a plain UTF-8 string (not hex), matching permissionless.js
/// `toHex(salt)`. Omit or pass empty/`"0x"` for empty salt bytes.
///
/// Example with publicClient (recommended):
/// ```dart
/// final publicClient = createPublicClient(url: rpcUrl);
/// final account = createThirdwebSmartAccount(
///   owner: PrivateKeyOwner('0x...'),
///   chainId: BigInt.from(11155111), // Sepolia
///   publicClient: publicClient,
/// );
///
/// final address = await account.getAddress();
/// print('Thirdweb account: $address');
/// ```
ThirdwebSmartAccount createThirdwebSmartAccount({
  required AccountOwner owner,
  required BigInt chainId,
  String salt = '0x',
  EntryPointVersion entryPointVersion = EntryPointVersion.v07,
  EthereumAddress? customFactoryAddress,
  BigInt? nonceKey,
  EthereumAddress? entryPointAddress,
  PublicClient? publicClient,
  EthereumAddress? address,
}) =>
    ThirdwebSmartAccount(
      ThirdwebSmartAccountConfig(
        owner: owner,
        chainId: chainId,
        salt: salt,
        entryPointVersion: entryPointVersion,
        customFactoryAddress: customFactoryAddress,
        nonceKey: nonceKey,
        entryPointAddress: entryPointAddress,
        publicClient: publicClient,
        address: address,
      ),
    );
